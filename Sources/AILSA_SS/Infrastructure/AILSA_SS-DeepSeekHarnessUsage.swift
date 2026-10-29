import Foundation
import CryptoKit

struct DeepSeekHarnessDiagnostics: Equatable, Sendable {
    var files = 0, requests = 0, duplicates = 0, overlaps = 0, invalid = 0, unsupported = 0
    var partial = false, unavailable = false
}

struct DeepSeekHarnessReference: Equatable, Sendable {
    let provider: String
    let model: String
    static func official(provider: String, model: String, responseModel: String?) -> Self? {
        guard ["deepseek", "deepseek-official", "deepseek-api-key", "deepseek-api"].contains(provider.lowercased()) else { return nil }
        let aliases = ["deepseek-flash":"deepseek-flash", "deepseek-v4-flash":"deepseek-flash",
                       "deepseek-v4-flash-vision-exp":"deepseek-flash", "deepseek-v4-pro":"deepseek-v4-pro"]
        guard let name = aliases[model.lowercased()] else { return nil }
        return Self(provider: "deepseek", model: name)
    }
}

struct DeepSeekHarnessUsage: Sendable {
    struct Entry: Sendable {
        let identity: String
        let responseKeys: Set<String>
        let contribution: QuotaContribution
    }
    var entries: [Entry] = []
    var diagnostics = DeepSeekHarnessDiagnostics()

    func merging(into base: QuotaDashboardSnapshot, now: Date, historyDays: Int) -> QuotaDashboardSnapshot {
        let calendar = Calendar.current, today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding:.day,value:-(max(1,historyDays)-1),to:today)!
        let end = calendar.date(byAdding:.day,value:1,to:today)!
        var days=base.days, all=base.all, minutes=base.minuteTokens, buckets=base.minuteBuckets
        var diagnostics=self.diagnostics, keys=base.providerResponseKeys, included=0
        for entry in entries {
            if !keys.isDisjoint(with:entry.responseKeys) { diagnostics.overlaps += 1; continue }
            keys.formUnion(entry.responseKeys)
            let c=entry.contribution; all.merge(c.value); included += 1
            if c.day >= start && c.day < end { days[c.day,default:QuotaBucket()].add(c.value,key:c.key) }
            if c.day == today, let minute=c.minute {
                minutes[minute,default:0] += c.value.tokens.total
                buckets[minute,default:QuotaBucket()].add(c.value,key:c.key)
            }
        }
        var result=QuotaDashboardSnapshot(scannedAt:base.scannedAt,days:days,all:all,
            source:included>0 ? base.source+" + DeepSeek Harness local" : base.source,
            pricingSources:base.pricingSources,discardedRows:base.discardedRows+diagnostics.duplicates,
            quotaWindows:base.quotaWindows,quotaTrend:base.quotaTrend,buildMilliseconds:base.buildMilliseconds,
            minuteTokens:minutes,minuteBuckets:buckets,quotaTrends:base.quotaTrends,
            pricingProvenance:base.pricingProvenance,providerResponseKeys:keys)
        result.antigravityTokenUsage=base.antigravityTokenUsage
        result.deepSeekHarnessUsage=diagnostics.files>0 || diagnostics.unavailable ? diagnostics : nil
        if included>0 && !result.pricingProvenance.contains(where:{$0.basis == .standardReference}) {
            result.pricingProvenance.append(.init(basis:.standardReference,auditDate:OpenCodexStandardReferenceEstimator.auditDate))
        }
        return result
    }
}

struct DeepSeekHarnessUsageReader: Sendable {
    typealias Resolver = @Sendable (String, String, String?) -> DeepSeekHarnessReference?
    private var stamp: String?
    private var cached: DeepSeekHarnessUsage?

    struct Projection: Decodable {
        let version: Int, files: Int
        let partial: Bool
        let records: [Record]
    }
    struct Record: Decodable, Equatable {
        let session: String, provider: String, model: String
        let turn: Int, step: Int, epoch: Int, seq: Int
        let time: Int64
        let usage: Usage
        var requestedOnly = false
        let responseID: String?, responseModel: String?, messageID: String?
        let timeEstimated: Bool?
    }
    struct Usage: Decodable, Equatable {
        let inputTokens: Int, outputTokens: Int
        let totalTokens: Int?, cacheReadTokens: Int?, cacheWriteTokens: Int?, reasoningTokens: Int?
    }
    enum Failure: Error { case invalid, runtimeUnavailable }

    mutating func read(root: URL?, runtime: URL?, helper: URL?, resolver: Resolver = { DeepSeekHarnessReference.official(provider:$0,model:$1,responseModel:$2) },
                       load: (@Sendable (URL,URL,URL) throws -> Data)? = nil) throws -> DeepSeekHarnessUsage {
        guard let root, FileManager.default.fileExists(atPath:root.path) else { return .init() }
        let fresh=try Self.fileStamp(root)
        if stamp==fresh, let cached { return cached }
        guard let runtime, let helper else { throw Failure.runtimeUnavailable }
        let data=try (load ?? Self.load)(root,runtime,helper)
        let result=try Self.decode(data,resolver:resolver)
        // An incomplete writer tail is retried even when filesystem timestamps are coarse.
        if !result.diagnostics.partial { stamp=fresh;cached=result }
        return result
    }
    static func load(root: URL, runtime: URL, helper: URL) throws -> Data {
        // Launch the installed, offline JavaScript runtime directly; no login,
        // plugin startup, shell interpolation or application UI is involved.
        let output=try CommandRunner.run(runtime.path,arguments:[helper.path,root.path],environment:["NODE_OPTIONS":"","NODE_PATH":""],timeout:20)
        guard output.status==0,output.stdout.utf8.count<=64*1024*1024 else { throw Failure.invalid }
        return Data(output.stdout.utf8)
    }
    static func runtime(fileManager: FileManager = .default) -> URL? {
        let names=["/Applications/DeepSeek Harness.app/Contents/Resources/runtime/primary-runtime/dependencies/node/bin/node",
                   fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/DeepSeek Harness.app/Contents/Resources/runtime/primary-runtime/dependencies/node/bin/node").path]
        return names.first(where:{fileManager.isExecutableFile(atPath:$0)}).map{URL(fileURLWithPath:$0)}
    }
    private static func fileStamp(_ root: URL) throws -> String {
        let fm=FileManager.default
        let names:Set<String>=["session.v4.jsonl","session.v4.jsonl.zstd"]
        guard let files=fm.enumerator(at:root,includingPropertiesForKeys:[.isSymbolicLinkKey],options:[.skipsHiddenFiles]) else { throw Failure.invalid }
        var values:[String]=[]
        for case let file as URL in files {
            try Task.checkCancellation()
            if (try? file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink)==true { files.skipDescendants();continue }
            guard names.contains(file.lastPathComponent) else { continue }
            guard values.count<4096 else { throw Failure.invalid }
            let a=try fm.attributesOfItem(atPath:file.path)
            let modified=(a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            values.append("\(file.path):\(a[.systemFileNumber] ?? 0):\(a[.size] ?? 0):\(modified)")
        }
        return values.sorted().joined(separator:"\n")
    }
    static func decode(_ data: Data, resolver: Resolver = { DeepSeekHarnessReference.official(provider:$0,model:$1,responseModel:$2) }) throws -> DeepSeekHarnessUsage {
        guard data.count<=64*1024*1024 else { throw Failure.invalid }
        let projection=try JSONDecoder().decode(Projection.self,from:data)
        guard projection.version==1,projection.files>=0,projection.files<=4096,projection.records.count<=200000 else { throw Failure.invalid }
        var result=DeepSeekHarnessUsage();result.diagnostics.files=projection.files;result.diagnostics.partial=projection.partial
        var newest:[String:Record]=[:], conflicts=Set<String>()
        for record in projection.records {
            let id="\(record.session)\0\(record.turn):\(record.step):\(record.epoch)"
            if conflicts.contains(id) { continue }
            if let prior=newest[id] {
                result.diagnostics.duplicates += 1
                if prior.seq == record.seq && prior != record {newest[id]=nil;conflicts.insert(id);result.diagnostics.invalid += 1;continue}
                if prior.seq>record.seq { continue }
            }
            newest[id]=record
        }
        for id in newest.keys.sorted() {
            let record=newest[id]!,u=record.usage
            guard let reference=resolver(record.provider,record.model,record.responseModel) else {result.diagnostics.unsupported += 1;continue}
            let read=u.cacheReadTokens ?? 0,write=u.cacheWriteTokens ?? 0,reasoning=u.reasoningTokens ?? 0
            guard !record.session.isEmpty,record.session.utf8.count<=4096,record.turn>=0,record.step>=0,record.epoch>=0,record.seq>=0,
                  record.time>0,record.time<=253402300799999,
                  u.inputTokens>=0,u.outputTokens>=0,read>=0,write>=0,
                  let input=AntigravityTokenSum.integers([u.inputTokens,read,write]),
                  let total=AntigravityTokenSum.integers([input,u.outputTokens]),
                  u.totalTokens.map({$0==total}) ?? true,reasoning>=0,reasoning<=u.outputTokens else {result.diagnostics.invalid += 1;continue}
            let tokens=OpenCodexUsageTokens(inputTokens:input,outputTokens:u.outputTokens,totalTokens:total,cachedInputTokens:read,cacheReadInputTokens:read,cacheCreationInputTokens:write,reasoningOutputTokens:reasoning,totalSemantics:.inputPlusOutput)
            let date=Date(timeIntervalSince1970:Double(record.time)/1000)
            let price=OpenCodexStandardReferenceEstimator().estimate(.init(provider:reference.provider,resolvedModel:reference.model,requestedModel:nil,modelEcho:nil,usageStatus:.reported,usageEstimated:false,streamAborted:false,currency:"USD",apiEquivalentEligibility:nil,tierOutcomeConfirmation:nil,tierOutcomeCanonical:nil,responseServiceTier:nil,fastOutcome:nil,confirmedServiceTier:nil,fastGrantEvidence:.unknown,tokens:tokens,tokenSemanticIssue:false,occurredAt:date,cacheCreationIsInputSubset:true))
            var value=QuotaAggregate();value.requests=1;value.reported=1
            value.tokens=UsageTokenBreakdown(input:input,cachedInput:read,cacheWriteInput:write,output:u.outputTokens,reasoningOutput:reasoning)
            value.cacheReuse.observe(input:input,cachedInput:read);value.reference.add(price.picoUSD)
            value.states[price.status.rawValue]=1;value.states["deepseek_harness_local"]=1
            if record.requestedOnly {value.highEstimateRecords=1;value.states["native_model_reference_alias"]=1}
            if record.timeEstimated==true {value.highEstimateRecords=1;value.states["harness_time_reference_estimate"]=1}
            let minute=Date(timeIntervalSince1970:floor(date.timeIntervalSince1970/60)*60)
            let c=QuotaContribution(minute:minute,day:Calendar.current.startOfDay(for:date),key:.init(provider:reference.provider,model:reference.model),value:value)
            var keys=Set<String>()
            if let messageID=record.messageID,!messageID.isEmpty,messageID.utf8.count<=4096 {
                let identity="deepseek-harness-message\0"+reference.model+"\0"+messageID
                keys.insert(SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined())
            }
            if let responseID=record.responseID {
                for model in [record.model,record.responseModel,reference.model].compactMap({$0}) {
                    if let key=AntigravityTokenUsage.responseKey(model:model,responseID:responseID) {keys.insert(key)}
                }
            }
            result.entries.append(.init(identity:id,responseKeys:keys,contribution:c))
        }
        result.diagnostics.requests=result.entries.count
        return result
    }
}
