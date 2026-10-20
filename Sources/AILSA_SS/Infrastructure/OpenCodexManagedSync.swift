import Foundation
import Darwin
import CryptoKit

struct OpenCodexManagedSyncWorker {
    static func run(_ input: Data) async throws -> Data {
        try await Task.detached { try runSynchronously(input) }.value
    }
    private static func runSynchronously(_ input: Data) throws -> Data {
            let roots = ["/opt/homebrew/lib/node_modules/@bitkyc08/opencodex", "/usr/local/lib/node_modules/@bitkyc08/opencodex"]
            guard let root = roots.first(where: { FileManager.default.fileExists(atPath: $0 + "/src/oauth/store.ts") }),
                  let worker = Bundle.main.url(forResource: "OpenCodexManagedSync", withExtension: "ts") else {
                throw AppError.invalidData(L10n.tr("settings.pool.sync_unsupported"))
            }
            let binary = root + "/node_modules/bun/bin/bun.exe"
            guard FileManager.default.isExecutableFile(atPath: binary) else { throw AppError.invalidData(L10n.tr("settings.pool.sync_unsupported")) }
            let task = Process(), source = Pipe(), output = Pipe()
            task.executableURL = URL(fileURLWithPath: binary); task.arguments = [worker.path, root]
            task.standardInput = source; task.standardOutput = output; task.standardError = FileHandle.nullDevice
            try task.run()
            do { try source.fileHandleForWriting.write(contentsOf: input); try source.fileHandleForWriting.close() }
            catch { task.terminate(); throw error }
            let deadline = Date().addingTimeInterval(15)
            while task.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
            if task.isRunning {
                task.terminate()
                let stop = Date().addingTimeInterval(1)
                while task.isRunning && Date() < stop { Thread.sleep(forTimeInterval: 0.02) }
                if task.isRunning { _ = kill(task.processIdentifier, SIGKILL) }
                task.waitUntilExit()
                throw AppError.network(L10n.tr("settings.pool.sync_failed"))
            }
            let result = output.fileHandleForReading.readDataToEndOfFile()
            guard task.terminationStatus == 0, result.count < 16_000 else { throw AppError.io(L10n.tr("settings.pool.sync_failed")) }
            return result
    }
}

extension OpenCodexPoolService {
    struct SavedSyncStore: Decodable { var accounts: [SavedSyncAccount]; var currentAntigravityAccountId: String? }
    struct SavedSyncAccount: Decodable { var id: String; var label: String; var email: String?; var provider: String?; var authJson: JSONValue }
    struct ProxySyncStore: Decodable { var accounts: [ProxySyncAccount] }
    struct ProxySyncAccount: Decodable { var id: String; var credential: JSONValue }

    static func nativeFingerprint(_ email: String?) -> String? {
        AccountIdentity.normalizedEmail(email).map { SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined() }
    }
    func verifyRuntime() async throws {
        let data = try await syncWorker(JSONEncoder().encode(JSONValue.object(["action": .string("probe"), "home": .string(home.path)])))
        guard try JSONDecoder().decode(JSONValue.self, from: data)["supported"]?.boolValue == true else {
            throw AppError.invalidData(L10n.tr("settings.pool.sync_unsupported"))
        }
    }
    func savedSyncStore() throws -> SavedSyncStore {
        guard FileManager.default.fileExists(atPath: localQuotaURL.path) else {
            return SavedSyncStore(accounts: [], currentAntigravityAccountId: nil)
        }
        let data = try Data(contentsOf: localQuotaURL)
        guard data.count < 8 * 1024 * 1024 else { throw AppError.invalidData(L10n.tr("settings.pool.sync_failed")) }
        return try JSONDecoder().decode(SavedSyncStore.self, from: data)
    }
    func savedCandidates(excluding emails: Set<String>) -> [OpenCodexPoolCandidate] {
        guard let store = try? savedSyncStore() else { return [] }
        return store.accounts.filter { account in
            account.provider == "antigravity" && account.authJson["native_session"]?.boolValue != true &&
            AccountIdentity.normalizedEmail(account.email).map { !emails.contains($0) } == true
        }.map { OpenCodexPoolCandidate(id: $0.id, label: $0.label) }
    }
    func controlLease() throws -> OpenCodexControlLease {
        guard try policy().managementEnabled else { throw AppError.invalidData(L10n.tr("settings.pool.control_required")) }
        let lease = try OpenCodexControlLease(directory: policyURL.deletingLastPathComponent())
        try ownership.requireNoLegacyWriter()
        return lease
    }
    func setManagementEnabled(_ enabled: Bool) async throws {
        let lease = try OpenCodexControlLease(directory: policyURL.deletingLastPathComponent())
        defer { withExtendedLifetime(lease) {} }
        if enabled {
            try await verifyRuntime()
            let pool = try await snapshot()
            let before = try JSONDecoder().decode(StockPreference.self, from: await request("/api/oauth/accounts/pool?provider=" + pool.provider))
            let oldPolicy = try policy()
            let labels = try ownership.takeOver(backupDirectory: policyURL.deletingLastPathComponent().appendingPathComponent("legacy-sync-backup"))
            _ = try await request("/api/oauth/accounts/pool", method: "PUT", body: ["provider": .string(pool.provider), "enabled": .bool(false)])
            let desktop = try? savedSyncStore().currentAntigravityAccountId
            let native = Self.nativeFingerprint(try? await nativeSelection())
            try updatePolicy {
                $0.managementEnabled = true; $0.provider = pool.provider
                $0.managedSince = $0.managedSince ?? Date().timeIntervalSince1970
                // Establish a baseline; enabling management never chooses over the current route.
                $0.desktopSelection = desktop; $0.nativeSelectionFingerprint = native; $0.disabledLegacyLabels = labels
                if !oldPolicy.managementEnabled { $0.previousNativePreference = oldPolicy.enabled ? (oldPolicy.previousNativePreference ?? before.enabled) : before.enabled }
            }
        } else {
            let old = try policy()
            try updatePolicy { $0.managementEnabled = false; $0.enabled = false }
            if let previous = old.previousNativePreference {
                let current = try JSONDecoder().decode(StockPreference.self, from: await request("/api/oauth/accounts/pool?provider=" + old.provider))
                if !current.enabled { _ = try await request("/api/oauth/accounts/pool", method: "PUT", body: ["provider": .string(old.provider), "enabled": .bool(previous)]) }
            }
            // A stopped legacy writer stays disabled; restoring it is never an implicit side effect.
        }
        recordDecision(OpenCodexPoolDecision(outcome: enabled ? .managementStarted : .managementStopped))
    }
    func selectAccount(id: String) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        try await selectManagedAccount(id: id)
        recordDecision(OpenCodexPoolDecision(outcome: .manualSelected, targetAccountId: id))
    }
    private func selectManagedAccount(id: String) async throws {
        let pool = try await snapshot()
        guard let account = pool.accounts.first(where: { $0.id == id }), account.selected, !account.needsReauth, account.isAvailable else {
            throw AppError.invalidData(L10n.tr("settings.pool.unavailable_account"))
        }
        try ownership.requireNoLegacyWriter()
        _ = try await request("/api/oauth/accounts/active", method: "PUT", body: ["provider": .string(pool.provider), "accountId": .string(id)])
        let after = try await snapshot()
        guard after.activeAccountId == id else { throw AppError.invalidData(L10n.tr("settings.pool.update_failed")) }
    }
    func followDesktopAccount(email: String) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        let pool = try await snapshot()
        guard let account = pool.accounts.first(where: { AccountIdentity.normalizedEmail($0.email) == AccountIdentity.normalizedEmail(email) }) else {
            throw AppError.invalidData(L10n.tr("settings.pool.import_required"))
        }
        try await selectManagedAccount(id: account.id)
        let desktop = try? savedSyncStore().currentAntigravityAccountId
        try updatePolicy { $0.desktopSelection = desktop; $0.nativeSelectionFingerprint = Self.nativeFingerprint(email) }
        recordDecision(OpenCodexPoolDecision(outcome: .desktopFollowed, targetAccountId: account.id))
    }
    func runManagedCycle() async throws {
        var stage = "control"
        do {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        let pref = try JSONDecoder().decode(StockPreference.self, from: await request("/api/oauth/accounts/pool?provider=" + policy().provider))
        guard !pref.enabled else { throw AppError.invalidData(L10n.tr("settings.pool.control_conflict")) }
        var syncDeferred = false
        stage = "credentials"
        do { try await synchronizeSavedAccounts(holding: lease) }
        catch is CancellationError { throw CancellationError() }
        catch {
            // A local grant refresh failure must not disable rotation of independently
            // healthy proxy accounts with fresh, identity-matched quota.
            try ownership.requireNoLegacyWriter()
            syncDeferred = true
        }
        stage = "identity"
        let local = try policy(), saved = try savedSyncStore()
        let settingsURL = localQuotaURL.deletingLastPathComponent().appendingPathComponent("settings.json")
        let settings = FileManager.default.fileExists(atPath: settingsURL.path) ? try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: settingsURL)) : .defaultValue
        // Only observed identity transitions count as manual choices. A refresh never pins a pool.
        let nativeEmail = try? await nativeSelection()
        let fingerprint = Self.nativeFingerprint(nativeEmail)
        let desktopChanged = saved.currentAntigravityAccountId != local.desktopSelection
        let nativeChanged = fingerprint != nil && local.nativeSelectionFingerprint != nil && fingerprint != local.nativeSelectionFingerprint
        let selectedEmail = desktopChanged
            ? saved.accounts.first(where: { $0.id == saved.currentAntigravityAccountId })?.email
            : (nativeChanged ? nativeEmail : nil)
        var followed = false
        if settings.syncOpencodeAntigravityAuth, let email = selectedEmail,
           let target = try await snapshot().accounts.first(where: { AccountIdentity.normalizedEmail($0.email) == AccountIdentity.normalizedEmail(email) }),
           target.selected && target.isAvailable && !target.needsReauth {
            try await selectManagedAccount(id: target.id)
            recordDecision(OpenCodexPoolDecision(outcome: .desktopFollowed, targetAccountId: target.id, credentialSyncDeferred: syncDeferred))
            followed = true
        }
        if desktopChanged || (fingerprint != nil && fingerprint != local.nativeSelectionFingerprint) {
            try updatePolicy {
                $0.desktopSelection = saved.currentAntigravityAccountId
                if let fingerprint { $0.nativeSelectionFingerprint = fingerprint }
            }
        }
        if followed { return }
        stage = "rotation"
        _ = try await selectNextIfNeeded(holding: lease, syncDeferred: syncDeferred)
        } catch {
            if !(error is CancellationError) { recordDecision(OpenCodexPoolDecision(outcome: .checkFailed, stage: stage)) }
            throw error
        }
    }
    func importSavedAccount(id: String) async throws {
        let lease = try controlLease(); defer { withExtendedLifetime(lease) {} }
        try await synchronizeSavedAccounts(holding: lease, importing: id)
    }
    private func synchronizeSavedAccounts(holding lease: OpenCodexControlLease, importing: String? = nil) async throws {
        let local = try policy(), saved = try savedSyncStore()
        let bytes = try Data(contentsOf: home.appendingPathComponent("auth.json"))
        guard bytes.count < 8 * 1024 * 1024 else { throw AppError.invalidData(L10n.tr("settings.pool.sync_failed")) }
        guard let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any], let target = root[local.provider] else {
            throw AppError.invalidData(L10n.tr("settings.pool.sync_failed"))
        }
        let existing = try JSONDecoder().decode(ProxySyncStore.self, from: JSONSerialization.data(withJSONObject: target)).accounts
        var rows: [JSONValue] = []
        var sourceProofs: [String: JSONValue] = [:]
        for account in saved.accounts where account.provider == "antigravity" {
            guard let email = AccountIdentity.normalizedEmail(account.email), account.authJson["native_session"]?.boolValue != true else { continue }
            let previous = existing.first { AccountIdentity.normalizedEmail($0.credential["email"]?.stringValue) == email }
            // Only explicit admission adds an account. Existing membership/exclusions cannot be resurrected by a scan.
            guard previous != nil || account.id == importing else { continue }
            if let previous, previous.credential["refresh"]?.stringValue == account.authJson["refresh_token"]?.stringValue { continue }
            let (_, credential) = try await credentialValidator(account.authJson, email)
            var row: [String: JSONValue] = ["email": .string(email), "credential": credential, "insert": .bool(previous == nil)]
            if let previous { row["id"] = .string(previous.id); row["expected"] = previous.credential }
            rows.append(.object(row)); sourceProofs[account.id] = account.authJson
        }
        if !rows.isEmpty {
            let latest = try savedSyncStore()
            guard sourceProofs.allSatisfy({ id, auth in latest.accounts.contains { $0.id == id && $0.authJson == auth } }) else {
                throw AppError.invalidData(L10n.tr("settings.pool.sync_failed"))
            }
            try ownership.requireNoLegacyWriter()
            let payload = JSONValue.object(["provider": .string(local.provider), "home": .string(home.path), "rows": .array(rows)])
            let data = try await syncWorker(JSONEncoder().encode(payload))
            guard let result = try JSONDecoder().decode(JSONValue.self, from: data).objectValue,
                  result["error"] == nil, result["superseded"]?.int64Value == 0 else { throw AppError.invalidData(L10n.tr("settings.pool.sync_failed")) }
        }
        try updatePolicy { $0.lastSyncAt = Date().timeIntervalSince1970 }
    }
}
