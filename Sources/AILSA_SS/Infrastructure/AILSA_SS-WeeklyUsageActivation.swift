import Foundation
import CryptoKit
import Darwin

struct WeeklyUsageActivationResult: Codable, Equatable, Sendable {
    var model: String
    var inputTokens: Int64
    var outputTokens: Int64
    var confirmedAt: Int64
    var reasoningOutputTokens: Int64? = nil
    var totalTokens: Int64? = nil
}
struct WeeklyUsageActivationRecord: Codable, Equatable {
    var attemptedAt: Int64
    var resetAt: Int64?
    var result: WeeklyUsageActivationResult?
}
struct WeeklyUsageActivationStore {
    var path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexToolsSwift/weekly-usage-activation.json")
    static func key(provider: AccountProvider, email: String?, accountID: String) -> String {
        let identity = AccountIdentity.normalizedEmail(email) ?? accountID
        return SHA256.hash(data:Data((provider.rawValue+"|"+identity).utf8)).map{String(format:"%02x",$0)}.joined()
    }
    func read(_ key: String) -> WeeklyUsageActivationRecord? {
        guard let data=try? Data(contentsOf:path),data.count<256_000 else{return nil}
        return (try? JSONDecoder().decode([String:WeeklyUsageActivationRecord].self,from:data))?[key]
    }
    func mutate(_ key:String, _ change:(inout WeeklyUsageActivationRecord?) throws -> Void) throws {
        let folder=path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let fd=open(path.appendingPathExtension("lock").path,O_CREAT|O_RDWR,0o600)
        guard fd>=0 else{throw AppError.io(L10n.tr("accounts.weekly.failed"))}
        defer{_ = flock(fd,LOCK_UN);close(fd)}
        guard flock(fd,LOCK_EX|LOCK_NB)==0 else{throw AppError.io(L10n.tr("accounts.weekly.busy"))}
        var rows:[String:WeeklyUsageActivationRecord]=[:]
        if FileManager.default.fileExists(atPath:path.path){rows=try JSONDecoder().decode([String:WeeklyUsageActivationRecord].self,from:Data(contentsOf:path))}
        var record=rows[key];try change(&record);rows[key]=record
        try JSONEncoder().encode(rows).write(to:path,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:path.path)
    }
    func claim(_ key:String, resetAt:Int64?, now:Int64) throws {
        try mutate(key){ record in
            if let last=record,now-last.attemptedAt<180 {throw AppError.io(L10n.tr("accounts.weekly.busy"))}
            record = .init(attemptedAt:now,resetAt:resetAt)
        }
    }
    func confirm(_ key:String, result:WeeklyUsageActivationResult) throws {
        try mutate(key){record in record?.result=result}
    }
}
enum WeeklyUsageActivationState: Equatable {
    case active, idle, unknown
    static func windows(_ usage:UsageSnapshot?) -> [UsageWindow] {
        guard let usage else{return []}
        var result:[UsageWindow]=[]
        if let week=usage.oneWeek,week.windowSeconds==604800 {result.append(week)}
        for family in (usage.quotaFamilies ?? [])+(usage.codexQuotaFamilies ?? []) {
            result += family.buckets.filter{$0.isUsageKnown && $0.windowSeconds==604800}.compactMap{ b in
                b.usedPercent.map{UsageWindow(usedPercent:$0,windowSeconds:604800,resetAt:b.resetAt)}
            }
        }
        return result.filter{$0.usedPercent.isFinite && (0...100).contains($0.usedPercent)}
    }
    static func resolve(usage:UsageSnapshot?, receipt:WeeklyUsageActivationRecord?, now:Int64) -> Self {
        guard usage?.sourceAccountMatched != false else{return .unknown}
        let windows=windows(usage).filter{($0.resetAt ?? now+1)>now}
        if let receipt,let result=receipt.result,let end=receipt.resetAt,end>now,
           result.confirmedAt<=now,windows.contains(where:{abs(($0.resetAt ?? 0)-end)<=5}) {return .active}
        guard let usage,usage.sourceAccountMatched != false,now>=usage.fetchedAt,now-usage.fetchedAt<=300,!windows.isEmpty else{return .unknown}
        return windows.contains{$0.usedPercent>0} ? .active : .idle
    }
}

/// One explicit request, with no model fallback or generation retry. Credentials
/// are sent only to the provider's fixed HTTPS host, never a configured proxy.
struct WeeklyUsageRequestClient {
    typealias Loader = @Sendable (URLRequest) async throws -> (Data,URLResponse)
    var loader:Loader = {try await BackgroundNetworkSession.shared.data(for:$0)}
    func codex(accessToken:String,accountID:String) async throws -> WeeklyUsageActivationResult {
        func request(_ path:String)->URLRequest {
            var r=URLRequest(url:URL(string:"https://chatgpt.com/backend-api/codex/"+path)!)
            r.timeoutInterval=35;r.setValue("Bearer "+accessToken,forHTTPHeaderField:"Authorization")
            r.setValue(accountID,forHTTPHeaderField:"ChatGPT-Account-Id");r.setValue("codex-1",forHTTPHeaderField:"OpenAI-Beta")
            r.setValue("AILSA SubSwitch",forHTTPHeaderField:"originator");return r
        }
        let (catalog,response)=try await loader(request("models?client_version=1.0.0"))
        guard (response as? HTTPURLResponse)?.statusCode==200,catalog.count<2_000_000,
              let root=try? JSONDecoder().decode(JSONValue.self,from:catalog) else{throw AppError.network(L10n.tr("accounts.weekly.failed"))}
        let models=(root["models"]?.arrayValue ?? root["data"]?.arrayValue ?? []).compactMap{$0["slug"]?.stringValue ?? $0["id"]?.stringValue}.filter{$0.hasPrefix("gpt-")}
        let model=models.sorted{ a,b in
            func score(_ s:String)->Int{s.contains("mini") || s.contains("luna") ? 0 : s.contains("terra") ? 1 : s.contains("sol") ? 2 : 3}
            return score(a)==score(b) ? a<b : score(a)<score(b)
        }.first
        guard let model else{throw AppError.network(L10n.tr("accounts.weekly.failed"))}
        var r=request("responses");r.httpMethod="POST";r.setValue("application/json",forHTTPHeaderField:"Content-Type");r.setValue("text/event-stream",forHTTPHeaderField:"Accept")
        r.httpBody=try JSONSerialization.data(withJSONObject:["model":model,"instructions":"Reply with exactly OK. Do not use tools.","input":[["role":"user","content":[["type":"input_text","text":"Reply with OK."]]]],"tools":[],"tool_choice":"none","store":false,"stream":true,"reasoning":["effort":"low"]])
        try Task.checkCancellation()
        let (data,http)=try await loader(r)
        guard (http as? HTTPURLResponse)?.statusCode==200,data.count<2_000_000 else{throw AppError.network(L10n.tr("accounts.weekly.failed"))}
        for line in String(decoding:data,as:UTF8.self).components(separatedBy:.newlines) where line.hasPrefix("data: ") {
            guard let event=try? JSONDecoder().decode(JSONValue.self,from:Data(line.dropFirst(6).utf8)),event["type"]?.stringValue=="response.completed",let response=event["response"],response["status"]?.stringValue=="completed",
                  let input=response["usage"]?["input_tokens"]?.int64Value,input>0,
                  let output=response["usage"]?["output_tokens"]?.int64Value,output>0 else{continue}
            return .init(model:response["model"]?.stringValue ?? model,inputTokens:input,outputTokens:output,confirmedAt:Int64(Date().timeIntervalSince1970))
        }
        throw AppError.network(L10n.tr("accounts.weekly.unconfirmed"))
    }
}

extension AccountsCoordinator {
    func activateWeeklyUsage(id:String,force:Bool=false,records:WeeklyUsageActivationStore = .init(),client:WeeklyUsageRequestClient = .init()) async throws -> WeeklyUsageActivationResult {
        try await withExclusiveAntigravityOperation {
            let store=try storeRepository.loadStore()
            guard let account=store.accounts.first(where:{$0.id==id}),[AccountProvider.codex,.antigravity].contains(account.provider) else{throw AppError.invalidData(L10n.tr("accounts.weekly.unavailable"))}
            let now=dateProvider.unixSecondsNow(),key=WeeklyUsageActivationStore.key(provider:account.provider,email:account.email,accountID:account.accountID)
            guard force || WeeklyUsageActivationState.resolve(usage:account.usage,receipt:records.read(key),now:now) != .active else{throw AppError.invalidData(L10n.tr("accounts.weekly.already"))}
            var auth=account.authJSON
            let result:WeeklyUsageActivationResult
            if account.provider == .codex {
                guard let token=AuthJWTDecoder.tokenObject(from:auth)?["access_token"]?.stringValue else{throw AppError.unauthorized(L10n.tr("accounts.weekly.unavailable"))}
                if ((try? AuthJWTDecoder.decodePayload(token)["exp"]?.int64Value) ?? 0)<=now+60 {auth=try await authRepository.refreshChatGPTAuth(auth)}
                let extracted=try authRepository.extractAuth(from:auth)
                guard extracted.accountID==account.accountID else{throw AppError.unauthorized(L10n.tr("accounts.weekly.unavailable"))}
                _ = try storeRepository.mutateStore { s in
                    guard let i=s.accounts.firstIndex(where:{$0.id==id}),s.accounts[i].authJSON==account.authJSON else{throw AppError.invalidData(L10n.tr("accounts.weekly.unavailable"))}
                    s.accounts[i].authJSON=auth
                }
                try records.claim(key,resetAt:WeeklyUsageActivationState.windows(account.usage).first?.resetAt,now:now)
                result=try await client.codex(accessToken:extracted.accessToken,accountID:extracted.accountID)
            } else {
                guard let service=antigravityUsageService,let email=account.email,auth["native_session"]?.boolValue != true else{throw AppError.unauthorized(L10n.tr("accounts.weekly.unavailable"))}
                auth=try await service.refreshStoredCredentialIfNeeded(auth)
                _ = try storeRepository.mutateStore { s in
                    guard let i=s.accounts.firstIndex(where:{$0.id==id}),s.accounts[i].authJSON==account.authJSON else{throw AppError.invalidData(L10n.tr("accounts.weekly.unavailable"))}
                    s.accounts[i].authJSON=auth
                }
                try records.claim(key,resetAt:WeeklyUsageActivationState.windows(account.usage).first?.resetAt,now:now)
                result=try await service.sendWeeklyUsageRequest(authJSON:auth,expectedEmail:email)
            }
            try records.confirm(key,result:result)
            return result
        }
    }
}
