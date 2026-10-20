import Foundation
import CryptoKit
import Darwin

struct OpenCodexPoolRange: Codable, Equatable, Sendable {
    var minimum: Int = 10
    var maximum: Int = 10
    var isValid: Bool { (0...99).contains(minimum) && (minimum...99).contains(maximum) }
}
struct OpenCodexPoolWindow: Codable, Equatable, Sendable {
    var label: String
    var percent: Double
    var resetAt: Double?
    var modelId: String?
}
struct OpenCodexPoolQuota: Codable, Equatable, Sendable {
    var customWindows: [OpenCodexPoolWindow]?
    var updatedAt: Double
    func windows(for family: String) -> [OpenCodexPoolWindow] {
        (customWindows ?? []).filter {
            guard $0.modelId == nil, $0.percent.isFinite, (0...100).contains($0.percent) else { return false }
            let label = $0.label.lowercased()
            return family == "gemini" ? label.hasPrefix("gem") : label.hasPrefix("cla")
        }
    }
}
struct OpenCodexPoolAccount: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var label: String
    var email: String?
    var selected: Bool
    var needsReauth: Bool
    var range: OpenCodexPoolRange
    var effectiveThreshold: Int?
    var effectiveClaudeThreshold: Int?
    var remainingPercent: Double? = nil
    var isAvailable: Bool = true
}
struct OpenCodexPoolSnapshot: Codable, Equatable, Sendable {
    var provider: String
    var enabled: Bool
    var activeAccountId: String?
    var accounts: [OpenCodexPoolAccount]
    var monitoredFamily: String = "gemini"
    var policyRevision: String = ""
    var managementEnabled: Bool = false
    var legacyConflict: Bool = false
    var lastSyncAt: Double? = nil
    var candidates: [OpenCodexPoolCandidate] = []
    var lastDecision: OpenCodexPoolDecision? = nil
}

struct OpenCodexPoolCandidate: Identifiable, Equatable, Sendable, Codable { var id: String; var label: String }

struct OpenCodexLocalPoolPolicy: Codable, Equatable, Sendable {
    var enabled = false
    var provider = "antigravity-pool"
    var ranges: [String: OpenCodexPoolRange] = [:]
    var seed = UUID().uuidString
    var revision = UUID().uuidString
    var previousNativePreference: Bool? = nil
    var managementEnabled = false
    var managedSince: Double? = nil
    var desktopSelection: String? = nil
    var nativeSelectionFingerprint: String? = nil
    var lastSyncAt: Double? = nil
    var disabledLegacyLabels: [String] = []
    init() {}
    enum CodingKeys: String, CodingKey {
        case enabled, provider, ranges, seed, revision, previousNativePreference
        case managementEnabled, managedSince, desktopSelection, nativeSelectionFingerprint, lastSyncAt, disabledLegacyLabels
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "antigravity-pool"
        ranges = try c.decodeIfPresent([String: OpenCodexPoolRange].self, forKey: .ranges) ?? [:]
        seed = try c.decodeIfPresent(String.self, forKey: .seed) ?? UUID().uuidString
        revision = try c.decodeIfPresent(String.self, forKey: .revision) ?? UUID().uuidString
        previousNativePreference = try c.decodeIfPresent(Bool.self, forKey: .previousNativePreference)
        managementEnabled = try c.decodeIfPresent(Bool.self, forKey: .managementEnabled) ?? false
        managedSince = try c.decodeIfPresent(Double.self, forKey: .managedSince)
        desktopSelection = try c.decodeIfPresent(String.self, forKey: .desktopSelection)
        nativeSelectionFingerprint = try c.decodeIfPresent(String.self, forKey: .nativeSelectionFingerprint)
        lastSyncAt = try c.decodeIfPresent(Double.self, forKey: .lastSyncAt)
        disabledLegacyLabels = try c.decodeIfPresent([String].self, forKey: .disabledLegacyLabels) ?? []
    }

    func threshold(id: String, quota: OpenCodexPoolQuota?, family: String, now: Date = Date()) -> Int? {
        let millis = now.timeIntervalSince1970 * 1000
        guard let quota, quota.updatedAt <= millis, millis - quota.updatedAt <= 2 * 60_000 else { return nil }
        // Idle short-window end estimates may slide on every provider poll.
        let cycleWindows = quota.windows(for: family).filter {
            let label = $0.label.lowercased()
            return $0.percent > 0 || label.contains("week") || label.contains("7d") || label.contains("1w")
        }
        let cycle = cycleWindows.compactMap(\.resetAt).map { $0 < 1e11 ? $0 * 1000 : $0 }.filter { $0.isFinite && $0 > millis }.sorted()
        guard !cycle.isEmpty else { return nil }
        let range = ranges[id] ?? OpenCodexPoolRange()
        guard range.isValid else { return nil }
        let key = [seed, id, family, cycle.map { String(Int64($0)) }.joined(separator: ","), "\(range.minimum):\(range.maximum)"].joined(separator: "|")
        let bytes = Array(SHA256.hash(data: Data(key.utf8)))
        let draw = bytes.prefix(4).reduce(UInt64(0)) { $0 * 256 + UInt64($1) }
        return range.minimum + Int(draw % UInt64(range.maximum - range.minimum + 1))
    }
}

/// Local rules are application-owned. Routing uses original APIs; credential sync uses its locked transaction.
struct OpenCodexPoolService: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".opencodex")
    var policyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexToolsSwift/opencodex-pool.json")
    var localQuotaURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexToolsSwift/accounts.json")
    var loader: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
        try await OpenCodexPoolNetworkSession.shared.data(for: request)
    }
    var ownershipOverride: OpenCodexControlOwnership? = nil
    var nativeSelection: @Sendable () async throws -> String? = { try await AntigravityNativeUsageService().fetchCurrentUsage().email }
    var syncWorker: @Sendable (Data) async throws -> Data = { try await OpenCodexManagedSyncWorker.run($0) }
    var credentialValidator: @Sendable (JSONValue, String) async throws -> (JSONValue, JSONValue) = { auth, email in
        try await AntigravityUsageService().validatedOpenCodexCredential(authJSON: auth, expectedEmail: email)
    }
    var ownership: OpenCodexControlOwnership { ownershipOverride ?? OpenCodexControlOwnership(home: home.deletingLastPathComponent()) }
    private static let policyLock = NSLock()
    private enum Failure: Error { case http(Int) }

    func policy() throws -> OpenCodexLocalPoolPolicy {
        Self.policyLock.lock(); defer { Self.policyLock.unlock() }
        return try readPolicy()
    }
    private func readPolicy() throws -> OpenCodexLocalPoolPolicy {
        guard FileManager.default.fileExists(atPath: policyURL.path) else { return OpenCodexLocalPoolPolicy() }
        let data = try Data(contentsOf: policyURL)
        guard data.count < 256_000 else { throw AppError.invalidData(L10n.tr("settings.pool.update_failed")) }
        let value = try JSONDecoder().decode(OpenCodexLocalPoolPolicy.self, from: data)
        guard ["antigravity-pool", "google-antigravity"].contains(value.provider), value.ranges.values.allSatisfy(\.isValid) else {
            throw AppError.invalidData(L10n.tr("settings.pool.update_failed"))
        }
        return value
    }
    func updatePolicy(_ update: (inout OpenCodexLocalPoolPolicy) -> Void) throws {
        Self.policyLock.lock(); defer { Self.policyLock.unlock() }
        var value = try readPolicy(); update(&value); value.revision = UUID().uuidString
        try FileManager.default.createDirectory(at: policyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: policyURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: policyURL.path)
    }
    func request(_ path: String, method: String = "GET", body: [String: JSONValue]? = nil) async throws -> Data {
        let token = try String(contentsOf: home.appendingPathComponent("admin-api-token"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains("\n"), !token.contains("\r") else { throw AppError.invalidData(L10n.tr("settings.pool.unavailable")) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:10100" + path)!)
        request.httpMethod = method; request.timeoutInterval = 30
        request.setValue(token, forHTTPHeaderField: "X-OpenCodex-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await loader(request)
        guard let http = response as? HTTPURLResponse else { throw Failure.http(0) }
        guard (200..<300).contains(http.statusCode), data.count < 256_000 else { throw Failure.http(http.statusCode) }
        return data
    }
    private struct StockAccount: Decodable {
        var id: String
        var alias: String?
        var email: String?
        var paused: Bool?
        var needsReauth: Bool?
        var health: StockHealth?
        var quota: OpenCodexPoolQuota?
    }
    private struct StockHealth: Decodable { var status: String }
    private struct StockAccounts: Decodable { var activeAccountId: String?; var accounts: [StockAccount] }
    struct StockPreference: Decodable { var enabled: Bool }

    /// Read identity metadata only; never copy or return the credential objects themselves.
    private func identityEmails(provider: String) -> [String: String] {
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")), data.count < 8 * 1024 * 1024,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let set = root[provider] as? [String: Any], let accounts = set["accounts"] as? [[String: Any]] else { return [:] }
        return accounts.reduce(into: [:]) { result, row in
            if let id = row["id"] as? String, let credential = row["credential"] as? [String: Any], let email = credential["email"] as? String {
                result[id] = email
            }
        }
    }
    private func recentModelFamily(provider: String, now: Date) -> String {
        guard let handle = try? FileHandle(forReadingFrom: home.appendingPathComponent("usage.jsonl")) else { return "gemini" }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return "gemini" }
        let offset = size > 262_144 ? size - 262_144 : 0
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return "gemini" }
        for line in text.split(separator: "\n").reversed() {
            guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], row["provider"] as? String == provider,
                  let status = row["status"] as? Int, (200..<300).contains(status),
                  let timestamp = row["timestamp"] as? Double, timestamp <= now.timeIntervalSince1970 * 1000, now.timeIntervalSince1970 * 1000 - timestamp < 3_600_000 else { continue }
            let model = ((row["servedModel"] ?? row["model"]) as? String ?? "").lowercased()
            if model.contains("claude") || model.contains("gpt-oss") { return "claude" }
            if model.contains("gemini") { return "gemini" }
        }
        return "gemini"
    }
    private struct LocalAccounts: Decodable { var accounts: [LocalAccount] }
    private struct LocalAccount: Decodable { var provider: String; var email: String?; var usage: UsageSnapshot?; var usageError: String? }

    /// Only identity-matched, provider-confirmed usage is consumed; authJSON is not decoded.
    func localQuotas(now: Date = Date()) -> [String: OpenCodexPoolQuota] {
        guard let data = try? Data(contentsOf: localQuotaURL), data.count < 8 * 1024 * 1024,
              let store = try? JSONDecoder().decode(LocalAccounts.self, from: data) else { return [:] }
        var result: [String: OpenCodexPoolQuota] = [:]
        for account in store.accounts where account.provider == "antigravity" && account.usageError == nil {
            guard let email = AccountIdentity.normalizedEmail(account.email), let usage = account.usage,
                  usage.sourceAccountMatched == true, Double(usage.fetchedAt) <= now.timeIntervalSince1970,
                  now.timeIntervalSince1970 - Double(usage.fetchedAt) <= 120 else { continue }
            var windows: [OpenCodexPoolWindow] = []
            for family in usage.quotaFamilies ?? [] {
                guard let key = QuotaActivationFamily.identify(family.id + " " + family.displayName) else { continue }
                for bucket in family.buckets {
                    guard bucket.isUsageKnown, let used = bucket.usedPercent, used.isFinite, (0...100).contains(used), let reset = bucket.resetAt, Double(reset) > now.timeIntervalSince1970 else { continue }
                    // Idle 5h reset estimates can move with every poll. They are not a cycle identity.
                    let idle = QuotaCountdownState.requiresRequestEvidence(windowSeconds: bucket.windowSeconds, identifier: bucket.id)
                        && bucket.usedPercent == 0 && bucket.countdownStartedAt == nil
                    windows.append(OpenCodexPoolWindow(label: key.rawValue + " " + bucket.id, percent: used,
                        resetAt: idle ? nil : Double(reset) * 1000, modelId: nil))
                }
            }
            let quota = OpenCodexPoolQuota(customWindows: windows, updatedAt: Double(usage.fetchedAt) * 1000)
            if (result[email]?.updatedAt ?? 0) < quota.updatedAt { result[email] = quota }
        }
        return result
    }

    func snapshot(refresh: Bool = false) async throws -> OpenCodexPoolSnapshot {
        let local = try policy()
        var provider = local.provider
        let suffix = "&quota=1" + (refresh ? "&refresh=1" : "")
        let data: Data
        do { data = try await request("/api/oauth/accounts?provider=" + provider + suffix) }
        catch Failure.http(let status) where provider == "antigravity-pool" && [400, 404, 409].contains(status) {
            provider = "google-antigravity"
            data = try await request("/api/oauth/accounts?provider=" + provider + suffix)
        }
        let stock = try JSONDecoder().decode(StockAccounts.self, from: data)
        let identities = identityEmails(provider: provider)
        let now = Date(), family = recentModelFamily(provider: provider, now: Date())
        let savedQuotas = localQuotas(now: now)
        return OpenCodexPoolSnapshot(provider: provider, enabled: local.enabled, activeAccountId: stock.activeAccountId,
            accounts: stock.accounts.map { account in
                let email = identities[account.id] ?? account.email
                let quota = AccountIdentity.normalizedEmail(email).flatMap { savedQuotas[$0] } ?? account.quota
                let fresh = quota.map { $0.updatedAt <= now.timeIntervalSince1970 * 1000 && now.timeIntervalSince1970 * 1000 - $0.updatedAt <= 2 * 60_000 } ?? false
                let used = fresh ? quota?.windows(for: family).map(\.percent).max() : nil
                return OpenCodexPoolAccount(id: account.id, label: account.alias ?? account.email ?? account.id,
                    email: email, selected: account.paused != true, needsReauth: account.needsReauth == true || account.health?.status == "reauth_required",
                    range: local.ranges[account.id] ?? OpenCodexPoolRange(),
                    effectiveThreshold: local.enabled ? local.threshold(id: account.id, quota: quota, family: "gemini", now: now) : nil,
                    effectiveClaudeThreshold: local.enabled ? local.threshold(id: account.id, quota: quota, family: "claude", now: now) : nil,
                    remainingPercent: used.map { 100 - $0 }, isAvailable: account.health == nil || account.health?.status == "healthy")
            }, monitoredFamily: family, policyRevision: local.revision,
            managementEnabled: local.managementEnabled, legacyConflict: ownership.hasConflictingWriter(),
            lastSyncAt: local.lastSyncAt, candidates: savedCandidates(excluding: Set(identities.values.compactMap { AccountIdentity.normalizedEmail($0) })),
            lastDecision: try? OpenCodexPoolAudit.read(at: auditURL).last)
    }
    func setEnabled(_ enabled: Bool) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        try updatePolicy { $0.enabled = enabled }
        recordDecision(OpenCodexPoolDecision(outcome: enabled ? .enabled : .disabled))
    }
    func setRange(id: String, range: OpenCodexPoolRange) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        guard range.isValid else { throw AppError.invalidData(L10n.tr("settings.pool.range_invalid")) }
        let pool = try await snapshot()
        guard pool.accounts.contains(where: { $0.id == id }) else { throw AppError.invalidData(L10n.tr("settings.pool.update_failed")) }
        let previous = pool.accounts.first { $0.id == id }?.range
        try updatePolicy { $0.provider = pool.provider; $0.ranges[id] = range }
        recordDecision(OpenCodexPoolDecision(outcome: .rangeChanged, activeAccountId: id, range: range, previousRange: previous))
    }
    func setSelected(id: String, selected: Bool) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        let pool = try await snapshot()
        guard pool.accounts.contains(where: { $0.id == id }) else { throw AppError.invalidData(L10n.tr("settings.pool.update_failed")) }
        _ = try await request("/api/oauth/accounts/pause", method: "PUT", body: ["provider": .string(pool.provider), "accountId": .string(id), "paused": .bool(!selected)])
    }
    func selectNextIfNeeded(holding existingLease: OpenCodexControlLease? = nil, syncDeferred: Bool = false) async throws -> Bool {
        guard try policy().managementEnabled else { return false }
        let lease = try existingLease ?? controlLease(); defer { withExtendedLifetime(lease) {} }
        let pool = try await snapshot()
        var decision = OpenCodexPoolDecision.plan(pool)
        decision.credentialSyncDeferred = syncDeferred
        guard decision.outcome == .candidateChosen, let nextID = decision.targetAccountId else {
            recordDecision(decision); return false
        }
        func stopped(_ outcome: OpenCodexPoolOutcome) -> Bool {
            decision.outcome = outcome; recordDecision(decision); return false
        }
        // A manual account change or pause during quota IO wins over this scheduled decision.
        let rechecked = try JSONDecoder().decode(StockAccounts.self, from: await request("/api/oauth/accounts?provider=" + pool.provider))
        guard rechecked.activeAccountId == pool.activeAccountId else { return stopped(.manualSelectionChanged) }
        guard let candidate = rechecked.accounts.first(where: { $0.id == nextID }), candidate.paused != true,
              candidate.needsReauth != true, candidate.health == nil || candidate.health?.status == "healthy" else { return stopped(.targetUnavailable) }
        let latest = try policy()
        guard latest.managementEnabled, latest.enabled, latest.revision == pool.policyRevision else { return stopped(.policyChanged) }
        guard (try? savedSyncStore().currentAntigravityAccountId) == latest.desktopSelection else { return stopped(.desktopSelectionChanged) }
        try ownership.requireNoLegacyWriter()
        let preference = try JSONDecoder().decode(StockPreference.self, from: await request("/api/oauth/accounts/pool?provider=" + pool.provider))
        guard !preference.enabled else { return stopped(.externalController) }
        try Task.checkCancellation()
        _ = try await request("/api/oauth/accounts/active", method: "PUT", body: ["provider": .string(pool.provider), "accountId": .string(nextID)])
        let verified = try JSONDecoder().decode(StockAccounts.self, from: await request("/api/oauth/accounts?provider=" + pool.provider))
        guard verified.activeAccountId == nextID else { return stopped(.selectionUnconfirmed) }
        decision.outcome = .switched; recordDecision(decision)
        return true
    }

}

actor OpenCodexPoolRuntime {
    static let shared = OpenCodexPoolRuntime()
    private var lastCheck = Date.distantPast
    private var checking = false
    func check(service: OpenCodexPoolService = OpenCodexPoolService(), now: Date = Date()) async throws {
        guard !checking, now.timeIntervalSince(lastCheck) >= 30, try service.policy().managementEnabled else { return }
        checking = true; lastCheck = now
        defer { checking = false }
        try await service.runManagedCycle()
    }
}

private final class OpenCodexPoolNetworkSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = URLSession(configuration: .ephemeral, delegate: OpenCodexPoolNetworkSession(), delegateQueue: nil)
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}


enum OpenCodexPoolOutcome: String, Codable, Sendable {
    case enabled, disabled, rangeChanged, managementStarted, managementStopped
    case manualSelected, desktopFollowed, aboveThreshold, activeQuotaUnknown, activeThresholdUnknown
    case noEligibleTarget, candidateChosen, switched, manualSelectionChanged, targetUnavailable
    case policyChanged, desktopSelectionChanged, externalController, selectionUnconfirmed, checkFailed
    var titleKey: String { "settings.pool.decision." + rawValue }
}

struct OpenCodexPoolDecision: Codable, Equatable, Sendable {
    var timestamp = Date().timeIntervalSince1970
    var outcome: OpenCodexPoolOutcome
    var family: String? = nil
    var activeAccountId: String? = nil
    var targetAccountId: String? = nil
    var remainingPercent: Double? = nil
    var threshold: Int? = nil
    var range: OpenCodexPoolRange? = nil
    var previousRange: OpenCodexPoolRange? = nil
    var credentialSyncDeferred = false
    var stage: String? = nil
    var candidates: [Candidate] = []
    struct Candidate: Codable, Equatable, Sendable {
        var id: String
        var selected: Bool
        var available: Bool
        var remainingPercent: Double?
        var threshold: Int?
    }
    static func plan(_ pool: OpenCodexPoolSnapshot) -> Self {
        let threshold: (OpenCodexPoolAccount) -> Int? = { pool.monitoredFamily == "claude" ? $0.effectiveClaudeThreshold : $0.effectiveThreshold }
        let active = pool.accounts.first { $0.id == pool.activeAccountId }
        var decision = Self(outcome: .disabled, family: pool.monitoredFamily, activeAccountId: pool.activeAccountId,
                            remainingPercent: active?.remainingPercent, threshold: active.flatMap(threshold), range: active?.range)
        decision.candidates = pool.accounts.map { Candidate(id: $0.id, selected: $0.selected,
            available: $0.isAvailable && !$0.needsReauth, remainingPercent: $0.remainingPercent, threshold: threshold($0)) }
        guard pool.enabled else { return decision }
        if let active, active.selected && !active.needsReauth && active.isAvailable {
            guard let remaining = active.remainingPercent else { decision.outcome = .activeQuotaUnknown; return decision }
            guard let limit = threshold(active) else { decision.outcome = .activeThresholdUnknown; return decision }
            guard remaining <= Double(limit) else { decision.outcome = .aboveThreshold; return decision }
        }
        let start = pool.accounts.firstIndex { $0.id == pool.activeAccountId } ?? -1
        let ring = start < 0 ? pool.accounts : Array(pool.accounts.dropFirst(start + 1)) + Array(pool.accounts.prefix(start + 1))
        guard let next = ring.first(where: { account in
            guard account.id != pool.activeAccountId, account.selected, !account.needsReauth, account.isAvailable,
                  let remaining = account.remainingPercent, let limit = threshold(account) else { return false }
            return remaining > Double(limit)
        }) else { decision.outcome = .noEligibleTarget; return decision }
        decision.outcome = .candidateChosen; decision.targetAccountId = next.id
        return decision
    }
}

/// Bounded diagnostic metadata only: no emails, credentials, prompts or raw error output.
enum OpenCodexPoolAudit {
    private static let lock = NSLock()
    static let maximumEntries = 512
    static func read(at url: URL) throws -> [OpenCodexPoolDecision] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard data.count <= 2 * 1024 * 1024 else { throw AppError.invalidData("Pool diagnostic history is oversized.") }
        return try JSONDecoder().decode([OpenCodexPoolDecision].self, from: data)
    }
    static func append(_ decision: OpenCodexPoolDecision, at url: URL) throws {
        lock.lock(); defer { lock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.deletingLastPathComponent().appendingPathComponent("opencodex-pool-audit.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw AppError.io("Pool diagnostic lock is unavailable.") }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw AppError.io("Pool diagnostic history is busy.") }
        defer { _ = flock(descriptor, LOCK_UN) }
        _ = fchmod(descriptor, 0o600)
        var rows = try read(at: url); rows.append(decision)
        if rows.count > maximumEntries { rows.removeFirst(rows.count - maximumEntries) }
        let data = try JSONEncoder().encode(rows)
        guard data.count <= 2 * 1024 * 1024 else { throw AppError.invalidData("Pool diagnostic history is oversized.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

extension OpenCodexPoolService {
    var auditURL: URL { policyURL.deletingLastPathComponent().appendingPathComponent("opencodex-pool-decisions.json") }
    func recordDecision(_ value: OpenCodexPoolDecision) { try? OpenCodexPoolAudit.append(value, at: auditURL) }
}
