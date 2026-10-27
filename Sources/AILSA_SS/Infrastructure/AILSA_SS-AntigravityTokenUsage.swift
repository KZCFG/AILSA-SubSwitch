import Foundation
import CryptoKit

/// App-local generation metadata only. No CLI execution, login or quota/network request.
enum AntigravityTokenScanner {
    struct Event: Equatable, Sendable {
        let session: String
        let row: Int64
        let turn: AntigravityTokenProto.ParsedTurn
        let cacheWrite: Int
        let input: Int
        let total: Int
        init?(session: String, row: Int64, turn: AntigravityTokenProto.ParsedTurn, cacheWrite: Int) {
            guard let usage = turn.usage, turn.timestampMs != nil,
                  let total = AntigravityTokenSum.integers([usage.newInput, usage.output, usage.cacheRead, cacheWrite, usage.reasoning]) else { return nil }
            self.session = session; self.row = row; self.turn = turn
            self.cacheWrite = cacheWrite; self.input = usage.newInput; self.total = total
        }
    }
    struct SourceResult: Sendable {
        var events: [Event] = []
        var isComplete = true
        var containsHistorySource = false
        var evidenceIsUnstable = false
    }
    static func checkedAdd(_ a: Int, _ b: Int) -> Int? { AntigravityTokenSum.integers([a,b]) }
}

struct AntigravityTokenDiagnostics: Equatable, Sendable {
    var files = 0
    var requests = 0
    var duplicates = 0
    var overlaps = 0
    var conflicts = 0
    var partial = false
    var unavailable = false
    var cacheHits = 0
    var emptyRecords = 0
}

struct AntigravityTokenUsage: Sendable {
    struct Entry: Sendable {
        let identity: String
        let responseKey: String?
        let contribution: QuotaContribution
    }
    var entries: [Entry] = []
    var diagnostics = AntigravityTokenDiagnostics()

    /// The same model/request identity can be recorded in both sources. Prefer
    /// the ledger when it carries that identity; never dedupe by similar counts.
    func merging(into base: QuotaDashboardSnapshot, now: Date, historyDays: Int) -> QuotaDashboardSnapshot {
        let calendar = Calendar.current, today = Calendar.current.startOfDay(for: now)
        let start = calendar.date(byAdding:.day,value:-(max(1,historyDays)-1),to:today)!
        let end = calendar.date(byAdding:.day,value:1,to:today)!
        var days = base.days, all = base.all, minutes = base.minuteTokens, buckets = base.minuteBuckets
        var diagnostics = self.diagnostics
        for entry in entries {
            if let key = entry.responseKey, base.providerResponseKeys.contains(key) { diagnostics.overlaps += 1; continue }
            let c = entry.contribution; all.merge(c.value)
            if c.day >= start && c.day < end { days[c.day,default:QuotaBucket()].add(c.value,key:c.key) }
            if c.day == today, let minute = c.minute {
                minutes[minute,default:0] += c.value.tokens.total
                buckets[minute,default:QuotaBucket()].add(c.value,key:c.key)
            }
        }
        let included = max(0, entries.count - diagnostics.overlaps)
        var result = QuotaDashboardSnapshot(scannedAt:base.scannedAt,days:days,all:all,
            source:included > 0 ? base.source + " + Antigravity App local" : base.source,
            pricingSources:base.pricingSources,discardedRows:base.discardedRows + diagnostics.duplicates,
            quotaWindows:base.quotaWindows,quotaTrend:base.quotaTrend,buildMilliseconds:base.buildMilliseconds,
            minuteTokens:minutes,minuteBuckets:buckets,quotaTrends:base.quotaTrends,
            pricingProvenance:base.pricingProvenance,providerResponseKeys:base.providerResponseKeys)
        result.antigravityTokenUsage = diagnostics.files > 0 || diagnostics.unavailable ? diagnostics : nil
        if included > 0 && !result.pricingProvenance.contains(where:{$0.basis == .standardReference}) {
            result.pricingProvenance.append(.init(basis:.standardReference,auditDate:OpenCodexStandardReferenceEstimator.auditDate))
        }
        return result
    }

    static func modelReference(_ raw: String) -> String {
        let id = raw.lowercased()
        // Antigravity product variants use a public API equivalent, not a
        // claim of a provider-confirmed bill. Keep the raw model on the row.
        let aliases = ["gemini-3.8-flash-n":"gemini-3.8-flash", "gemini-3.8-flash-control":"gemini-3.8-flash",
            "gemini-3.8-flash-tiered":"gemini-3.8-flash", "gemini-4-argon-trial":"gemini-4-argon"]
        return aliases[id] ?? id
    }
    static func responseKey(model: String, responseID: String) -> String? {
        let model = modelReference(model)
        guard !model.isEmpty, !responseID.isEmpty, responseID.utf8.count <= 4096 else { return nil }
        return SHA256.hash(data:Data((model + "\0" + responseID).utf8)).map{String(format:"%02x",$0)}.joined()
    }
}

struct AntigravityTokenUsageReader: Sendable {
    private struct Cache: Sendable { let stamp: String; let value: AntigravityTokenScanner.SourceResult }
    private var cache: [String:Cache] = [:]

    mutating func read(roots: [URL], cacheRoot: URL?, limits: AntigravityTokenScanner.Limits = .init()) throws -> AntigravityTokenUsage {
        guard !roots.isEmpty || cacheRoot != nil else { return .init() }
        let budget = AntigravityTokenScanner.Budget(limits:limits,cancellation:{ try Task.checkCancellation() })
        var diagnostics = AntigravityTokenDiagnostics(), source = AntigravityTokenScanner.SourceResult()
        do {
            let dbs = try AntigravityTokenScanner.discover(roots:roots,extension:"db",budget:budget)
            var paths = dbs.paths, json = false
            diagnostics.partial = !dbs.isComplete
            if paths.isEmpty && dbs.isComplete, let cacheRoot {
                let found = try AntigravityTokenScanner.discover(roots:[cacheRoot],extension:"jsonl",budget:budget)
                paths = found.paths; json = true; diagnostics.partial = !found.isComplete
            }
            diagnostics.files = paths.count
            let activePaths = Set(paths.map(\.path)); cache = cache.filter { activePaths.contains($0.key) }
            for path in paths {
                try budget.check()
                let before = Self.stamp(path)
                let item: AntigravityTokenScanner.SourceResult
                if let before, let cached = cache[path.path], cached.stamp == before {
                    item = cached.value; diagnostics.cacheHits += 1
                } else {
                    item = try json ? AntigravityTokenScanner.readJSONL([path],budget:budget)
                        : AntigravityTokenScanner.readDatabases([path],budget:budget)
                    if let before, before == Self.stamp(path), !item.evidenceIsUnstable {
                        cache[path.path] = Cache(stamp:before,value:item)
                    } else { cache.removeValue(forKey:path.path) }
                }
                diagnostics.partial = diagnostics.partial || !item.isComplete || item.evidenceIsUnstable
                if item.evidenceIsUnstable { continue }
                source.events.append(contentsOf:item.events)
                source.containsHistorySource = source.containsHistorySource || item.containsHistorySource
                guard source.events.count <= limits.rows else { throw AntigravityTokenScanner.ScanFailure.exhausted }
            }
            diagnostics.unavailable = diagnostics.files > 0 && !source.containsHistorySource
            return try Self.aggregate(source.events,diagnostics:diagnostics,budget:budget)
        } catch AntigravityTokenScanner.ScanFailure.exhausted, AntigravityTokenScanner.ScanFailure.schemaExhausted {
            diagnostics.partial = true; diagnostics.unavailable = true
            return AntigravityTokenUsage(entries:[],diagnostics:diagnostics)
        }
    }

    private static func stamp(_ url: URL) -> String? {
        var parts: [String] = []
        for path in [url.path,url.path+"-wal"] {
            guard let a = try? FileManager.default.attributesOfItem(atPath:path) else { parts.append("absent"); continue }
            let modified = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(a[.systemFileNumber] ?? 0):\(a[.size] ?? 0):\(modified)")
        }
        return parts.first == "absent" ? nil : parts.joined(separator:"|")
    }

    private static func aggregate(_ events: [AntigravityTokenScanner.Event], diagnostics initial: AntigravityTokenDiagnostics,
                                  budget: AntigravityTokenScanner.Budget) throws -> AntigravityTokenUsage {
        struct Label: Hashable { let session: String; let label: String }
        var diagnostics = initial
        var labels: [Label:String] = [:], badLabels = Set<Label>()
        for event in events {
            if let label = event.turn.label, let model = event.turn.model {
                let key = Label(session:event.session,label:label)
                if let prior = labels[key], prior != model { badLabels.insert(key) } else { labels[key] = model }
            }
        }
        var rows: [String:AntigravityTokenScanner.Event] = [:], responses: [String:AntigravityTokenScanner.Event] = [:]
        var accepted: [String:AntigravityTokenUsage.Entry] = [:], rowOwners: [String:String] = [:], conflicts = Set<String>()
        for event in events {
            try budget.check()
            // Zero-counter setup metadata is not evidence of a consumed request.
            if event.total == 0 { diagnostics.emptyRecords += 1; continue }
            let row = event.session + ":" + String(event.row)
            let inherited = event.turn.label.flatMap { label -> String? in
                let key = Label(session:event.session,label:label); return badLabels.contains(key) ? nil : labels[key]
            }
            let model = event.turn.model ?? inherited
            let responseKey = model.flatMap { model in event.turn.usage?.responseID.flatMap { AntigravityTokenUsage.responseKey(model:model,responseID:$0) } }
            let identity = responseKey ?? row
            if let prior = rows[row] {
                diagnostics.duplicates += 1
                if prior != event {
                    diagnostics.conflicts += 1; conflicts.insert(identity)
                    if let old = rowOwners[row] { conflicts.insert(old) }
                }
                continue
            }
            if let responseKey, let prior = responses[responseKey] {
                diagnostics.duplicates += 1
                if prior.turn != event.turn || prior.cacheWrite != event.cacheWrite { diagnostics.conflicts += 1; conflicts.insert(identity) }
                continue
            }
            guard let contribution = contribution(event,model:model) else { diagnostics.partial = true; continue }
            rows[row] = event; rowOwners[row] = identity
            if let responseKey { responses[responseKey] = event }
            accepted[identity] = AntigravityTokenUsage.Entry(identity:identity,responseKey:responseKey,contribution:contribution)
        }
        for key in conflicts { accepted.removeValue(forKey:key) }
        diagnostics.partial = diagnostics.partial || !conflicts.isEmpty
        diagnostics.requests = accepted.count
        return AntigravityTokenUsage(entries:accepted.keys.sorted().compactMap{accepted[$0]},diagnostics:diagnostics)
    }

    private static func contribution(_ event: AntigravityTokenScanner.Event, model: String?) -> QuotaContribution? {
        guard let u = event.turn.usage, let stamp = event.turn.timestampMs,
              let input = AntigravityTokenSum.integers([u.newInput,u.cacheRead,event.cacheWrite]),
              let output = AntigravityTokenSum.integers([u.output,u.reasoning]),
              let total = AntigravityTokenSum.integers([input,output]), total == event.total,
              total >= 0 else { return nil }
        let date = Date(timeIntervalSince1970:Double(stamp)/1000)
        let refModel = model.map(AntigravityTokenUsage.modelReference)
        let tokens = OpenCodexUsageTokens(inputTokens:input,outputTokens:output,totalTokens:total,
            cachedInputTokens:u.cacheRead,cacheReadInputTokens:u.cacheRead,cacheCreationInputTokens:event.cacheWrite,
            reasoningOutputTokens:u.reasoning,totalSemantics:.inputPlusOutput)
        let price = OpenCodexStandardReferenceEstimator().estimate(.init(provider:"google-antigravity",resolvedModel:refModel,
            requestedModel:nil,modelEcho:nil,usageStatus:.reported,usageEstimated:false,streamAborted:false,currency:"USD",
            apiEquivalentEligibility:nil,tierOutcomeConfirmation:nil,tierOutcomeCanonical:nil,responseServiceTier:nil,
            fastOutcome:nil,confirmedServiceTier:nil,fastGrantEvidence:.unknown,tokens:tokens,tokenSemanticIssue:false,occurredAt:date,cacheCreationIsInputSubset:true))
        var value = QuotaAggregate(); value.requests = 1; value.reported = 1
        value.tokens = UsageTokenBreakdown(input:input,cachedInput:u.cacheRead,cacheWriteInput:event.cacheWrite,
            output:output,reasoningOutput:u.reasoning)
        value.cacheReuse.observe(input:input,cachedInput:u.cacheRead)
        value.reference.add(price.picoUSD)
        value.states[price.status.rawValue] = 1
        if price.priceBasis == "official_cache_write_upper_bound" {value.highEstimateRecords=1;value.states["cache_write_upper_bound"]=1}
        if let model, refModel != model.lowercased(), price.picoUSD != nil {
            value.highEstimateRecords = 1; value.states["native_model_reference_alias"] = 1
        }
        value.unknownRoute = model == nil ? 1 : 0
        return QuotaContribution(minute:Date(timeIntervalSince1970:floor(date.timeIntervalSince1970/60)*60),
            day:Calendar.current.startOfDay(for:date),key:model.map{QuotaModelKey(provider:"google-antigravity",model:$0)} ?? .unknown,value:value)
    }
}
