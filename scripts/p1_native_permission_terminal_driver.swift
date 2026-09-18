import Foundation

/// Focused P1 regression driver for native credential boundaries. It uses
/// synthetic OAuth-looking bytes, an in-memory Keychain substitute, and
/// loopback-shaped RPC responses only; it never opens AntiGravity, reads a
/// real credential, or changes the user's account store.
@main
struct P1NativePermissionTerminalDriver {
    static func main() async {
        do {
            for error in [
                AntigravityNativeCredentialAccessError.userCancelled,
                .accessDenied,
                .lockedOrInteractionUnavailable
            ] {
                try await verifyAddStopsAfterOneCredentialRead(error)
                try await verifyReauthenticationStopsAfterOneCredentialRead(error)
            }
            try await verifySilentBackgroundAutoSwitchSucceeds()
            try await verifyBackgroundKeychainStorageHasNoNativeSideEffects()
            try await verifyFailedBackgroundSwitchRestoresExactBytes()
            try await verifyBackgroundKeychainBlockStopsAutomaticRetry()
            print("p1-native-permission: pass manual_terminal_including_cancel=6 file_token_auto_success=1 keychain_auto_no_side_effect=1 file_token_exact_rollback=1 keychain_block_dedup=1")
        } catch {
            let category = (error as? DriverFailure).map { String(describing: $0) } ?? "unexpected"
            FileHandle.standardError.write(Data("p1-native-permission: fail category=\(category)\n".utf8))
            exit(1)
        }
    }

    private static func verifyAddStopsAfterOneCredentialRead(
        _ expectedError: AntigravityNativeCredentialAccessError
    ) async throws {
        let fixture = try Fixture(
            keychain: SyntheticKeychainStore(readError: expectedError),
            accounts: [],
            editor: RecordingEditor(running: false, launchActions: [.keepCurrent])
        )
        defer { fixture.removeTemporaryFiles() }
        do {
            _ = try await fixture.coordinator.addAntigravityAccountViaNativeLogin(
                customLabel: nil,
                timeoutSeconds: 1
            )
            throw DriverFailure.expectedTerminalError
        } catch let error as AntigravityNativeCredentialAccessError {
            guard error == expectedError else { throw DriverFailure.wrongTerminalError }
        }
        guard fixture.keychain.readAccesses == [.userInitiated],
              fixture.editor.launchCount == 1,
              try fixture.store.loadStore().accounts.isEmpty
        else {
            throw DriverFailure.addRetriedOrMutated
        }
    }

    private static func verifyReauthenticationStopsAfterOneCredentialRead(
        _ expectedError: AntigravityNativeCredentialAccessError
    ) async throws {
        let account = nativeSessionAccount(
            id: "permission-card",
            email: "synthetic@example.invalid",
            usage: nil
        )
        let fixture = try Fixture(
            keychain: SyntheticKeychainStore(readError: expectedError),
            accounts: [account],
            editor: RecordingEditor(running: false, launchActions: [.keepCurrent])
        )
        defer { fixture.removeTemporaryFiles() }
        do {
            _ = try await fixture.coordinator.reauthenticateAntigravityAccount(
                id: account.id,
                timeoutSeconds: 1
            )
            throw DriverFailure.expectedTerminalError
        } catch let error as AntigravityNativeCredentialAccessError {
            guard error == expectedError else { throw DriverFailure.wrongTerminalError }
        }
        let saved = try fixture.store.loadStore()
        guard fixture.keychain.readAccesses == [.userInitiated],
              fixture.editor.launchCount == 1,
              saved.accounts.count == 1,
              saved.currentAntigravityAccountID == nil
        else {
            throw DriverFailure.reauthenticationRetriedOrMutated
        }
    }

    /// Native's explicit FileTokenStorage fallback can be staged and committed
    /// in the background without touching the Keychain.
    private static func verifySilentBackgroundAutoSwitchSucceeds() async throws {
        let currentEmail = "current@example.invalid"
        let targetEmail = "target@example.invalid"
        let current = nativeSessionAccount(
            id: "current-card", email: currentEmail, usage: verifiedUsage(usedPercent: 100)
        )
        let target = portableAccount(
            id: "target-card", email: targetEmail, usage: verifiedUsage(usedPercent: 10)
        )
        let keychain = SyntheticKeychainStore(secret: Data("p1-original-keychain".utf8))
        let scenario = SyntheticNativeScenario(currentEmail: currentEmail, targetEmail: targetEmail)
        let editor = RecordingEditor(
            running: true, scenario: scenario, launchActions: [.activateTarget]
        )
        let fixture = try Fixture(
            keychain: keychain,
            accounts: [current, target],
            currentAntigravityAccountID: current.id,
            autoSmartSwitchAntigravity: true,
            fallback: Data("p1-original-fallback".utf8),
            keychainBypassed: true,
            scenario: scenario,
            editor: editor
        )
        defer { fixture.removeTemporaryFiles() }

        let result = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let notice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        let store = try fixture.store.loadStore()
        guard result?.selectedAccount.id == target.id,
              notice == nil,
              store.currentAntigravityAccountID == target.id,
              store.pendingAntigravityAccountID == nil,
              keychain.readAccesses.isEmpty,
              keychain.preflightAccesses.isEmpty,
              keychain.writeAccesses.isEmpty,
              editor.quitCount == 1,
              editor.launchCount == 1,
              scenario.activeEmail == targetEmail
        else {
            throw DriverFailure.silentAutoDidNotCommit
        }
    }

    /// Traditional Keychain storage is rejected before any SecItem call. It
    /// must happen before quit/stage/launch/store mutation, and block the next
    /// tick without implying that automatic native switching succeeded.
    private static func verifyBackgroundKeychainStorageHasNoNativeSideEffects() async throws {
        let currentEmail = "current@example.invalid"
        let targetEmail = "target@example.invalid"
        let current = nativeSessionAccount(
            id: "current-card", email: currentEmail, usage: verifiedUsage(usedPercent: 100)
        )
        let target = portableAccount(
            id: "target-card", email: targetEmail, usage: verifiedUsage(usedPercent: 10)
        )
        let keychain = SyntheticKeychainStore(secret: Data("p1-no-touch-keychain".utf8))
        let scenario = SyntheticNativeScenario(currentEmail: currentEmail, targetEmail: targetEmail)
        let editor = RecordingEditor(running: true, scenario: scenario, launchActions: [])
        let fixture = try Fixture(
            keychain: keychain,
            accounts: [current, target],
            currentAntigravityAccountID: current.id,
            autoSmartSwitchAntigravity: true,
            scenario: scenario,
            editor: editor
        )
        defer { fixture.removeTemporaryFiles() }

        let first = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let firstNotice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        let second = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let secondNotice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        let store = try fixture.store.loadStore()
        guard first == nil,
              second == nil,
              firstNotice != nil,
              secondNotice == nil,
              store.currentAntigravityAccountID == current.id,
              keychain.readAccesses.isEmpty,
              keychain.preflightAccesses.isEmpty,
              keychain.writeAccesses.isEmpty,
              editor.quitCount == 0,
              editor.launchCount == 0,
              scenario.activeEmail == currentEmail
        else {
            throw DriverFailure.interactionRequirementHadSideEffects
        }
    }

    /// A post-stage launch failure in FileTokenStorage mode must restore the
    /// fallback bytes exactly, then reestablish the original identity via RPC.
    private static func verifyFailedBackgroundSwitchRestoresExactBytes() async throws {
        let currentEmail = "current@example.invalid"
        let targetEmail = "target@example.invalid"
        let current = nativeSessionAccount(
            id: "current-card", email: currentEmail, usage: verifiedUsage(usedPercent: 100)
        )
        let target = portableAccount(
            id: "target-card", email: targetEmail, usage: verifiedUsage(usedPercent: 10)
        )
        let originalKeychain = Data("p1-rollback-keychain".utf8)
        let originalFallback = Data("p1-rollback-fallback".utf8)
        let keychain = SyntheticKeychainStore(secret: originalKeychain)
        let scenario = SyntheticNativeScenario(currentEmail: currentEmail, targetEmail: targetEmail)
        let editor = RecordingEditor(
            running: true, scenario: scenario, launchActions: [.fail, .keepCurrent]
        )
        let fixture = try Fixture(
            keychain: keychain,
            accounts: [current, target],
            currentAntigravityAccountID: current.id,
            autoSmartSwitchAntigravity: true,
            fallback: originalFallback,
            keychainBypassed: true,
            scenario: scenario,
            editor: editor
        )
        defer { fixture.removeTemporaryFiles() }

        let result = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let notice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        let store = try fixture.store.loadStore()
        guard result == nil,
              notice == nil,
              store.currentAntigravityAccountID == current.id,
              keychain.currentSecret == originalKeychain,
              try Data(contentsOf: fixture.fallbackPath) == originalFallback,
              keychain.readAccesses.isEmpty,
              keychain.preflightAccesses.isEmpty,
              keychain.writeAccesses.isEmpty,
              editor.quitCount == 1,
              editor.launchCount == 2,
              scenario.activeEmail == currentEmail
        else {
            throw DriverFailure.rollbackDidNotRestoreExactBytes
        }
    }

    /// The traditional-Keychain block is terminal for the automatic session:
    /// one quiet notice, no native side effect, and no retry on the next tick.
    /// Explicit user-cancel handling is covered by the six manual cases above.
    private static func verifyBackgroundKeychainBlockStopsAutomaticRetry() async throws {
        let currentEmail = "current@example.invalid"
        let targetEmail = "target@example.invalid"
        let current = nativeSessionAccount(
            id: "current-card", email: currentEmail, usage: verifiedUsage(usedPercent: 100)
        )
        let target = portableAccount(
            id: "target-card", email: targetEmail, usage: verifiedUsage(usedPercent: 10)
        )
        let keychain = SyntheticKeychainStore(secret: Data("p1-no-touch-keychain".utf8))
        let scenario = SyntheticNativeScenario(currentEmail: currentEmail, targetEmail: targetEmail)
        let editor = RecordingEditor(running: true, scenario: scenario, launchActions: [])
        let fixture = try Fixture(
            keychain: keychain,
            accounts: [current, target],
            currentAntigravityAccountID: current.id,
            autoSmartSwitchAntigravity: true,
            scenario: scenario,
            editor: editor
        )
        defer { fixture.removeTemporaryFiles() }

        _ = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let firstNotice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        _ = try await fixture.coordinator.autoSmartSwitchIfNeeded()
        let secondNotice = await fixture.coordinator.consumeAutoSmartSwitchNotice()
        guard firstNotice != nil,
              secondNotice == nil,
              keychain.readAccesses.isEmpty,
              keychain.preflightAccesses.isEmpty,
              keychain.writeAccesses.isEmpty,
              editor.quitCount == 0,
              editor.launchCount == 0
        else {
            throw DriverFailure.cancellationRetriedAutomaticSwitch
        }
    }

    private static func nativeSessionAccount(id: String, email: String, usage: UsageSnapshot?) -> StoredAccount {
        StoredAccount(
            id: id, label: id, email: email, accountID: email, planType: "pro",
            teamName: nil, teamAlias: nil,
            authJSON: .object(["native_session": .bool(true), "email": .string(email)]),
            addedAt: 1, updatedAt: 1, usage: usage, usageError: nil,
            principalID: email, provider: .antigravity
        )
    }

    private static func portableAccount(id: String, email: String, usage: UsageSnapshot?) -> StoredAccount {
        StoredAccount(
            id: id, label: id, email: email, accountID: email, planType: "pro",
            teamName: nil, teamAlias: nil, authJSON: portableCredential(email: email),
            addedAt: 1, updatedAt: 1, usage: usage, usageError: nil,
            principalID: email, provider: .antigravity
        )
    }

    private static func portableCredential(email: String) -> JSONValue {
        .object([
            "email": .string(email),
            "access_token": .string("p1-synthetic-access"),
            "refresh_token": .string("p1-synthetic-refresh"),
            "expiry": .string("2099-01-01T00:00:00Z"),
            "auth_method": .string("consumer"),
            AntigravityOAuthProfile.profileStorageKey: .string("consumer"),
            "client_id": .string(AntigravityOAuthProfile.consumer.publicClientID),
            AntigravityOAuthProfile.refreshVerificationStorageKey: .number(1),
            "antigravity_native_credential": .bool(true),
            "antigravity_native_credential_email": .string(email)
        ])
    }

    fileprivate static func verifiedUsage(usedPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            fetchedAt: 1_763_216_000, planType: "pro", fiveHour: nil, oneWeek: nil, credits: nil,
            quotaFamilies: [
                UsageQuotaFamily(
                    id: "synthetic", displayName: "Synthetic",
                    buckets: [
                        UsageQuotaBucket(
                            id: "synthetic-5h", displayName: "Synthetic five hour",
                            usedPercent: usedPercent, resetAt: nil, windowSeconds: 18_000,
                            resetDescription: nil, isUsageKnown: true
                        )
                    ]
                )
            ],
            source: .antigravityNativeSummary, sourceAccountMatched: true
        )
    }

    private enum DriverFailure: Error {
        case expectedTerminalError
        case wrongTerminalError
        case addRetriedOrMutated
        case reauthenticationRetriedOrMutated
        case silentAutoDidNotCommit
        case interactionRequirementHadSideEffects
        case rollbackDidNotRestoreExactBytes
        case cancellationRetriedAutomaticSwitch
    }
}

private final class Fixture {
    let root: URL
    let fallbackPath: URL
    let keychain: SyntheticKeychainStore
    let editor: RecordingEditor
    let store: InMemoryStore
    let coordinator: AccountsCoordinator

    init(
        keychain: SyntheticKeychainStore,
        accounts: [StoredAccount],
        currentAntigravityAccountID: String? = nil,
        autoSmartSwitchAntigravity: Bool = false,
        fallback: Data? = nil,
        keychainBypassed: Bool = false,
        scenario: SyntheticNativeScenario? = nil,
        editor: RecordingEditor
    ) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-p1-native-permission-\(UUID().uuidString)", isDirectory: true)
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        fallbackPath = gemini.appendingPathComponent("jetski-standalone-oauth-token")
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        if let fallback { try fallback.write(to: fallbackPath) }
        let keyringUnavailableMarkerPath = gemini.appendingPathComponent("keyring-unavailable")
        if keychainBypassed { try Data().write(to: keyringUnavailableMarkerPath) }
        self.keychain = keychain
        self.editor = editor
        store = InMemoryStore(
            AccountsStore(accounts: accounts, currentAntigravityAccountID: currentAntigravityAccountID)
        )
        var settings = AppSettings.defaultValue
        settings.autoSmartSwitchAntigravity = autoSmartSwitchAntigravity
        let repository = AntigravityAuthRepository(
            paths: AntigravityAuthPaths(
                geminiDirectory: gemini,
                oauthCredsPath: root.appendingPathComponent("oauth_creds.json"),
                googleAccountsPath: root.appendingPathComponent("google_accounts.json"),
                jetskiTokenPath: fallbackPath,
                keyringUnavailableMarkerPath: keyringUnavailableMarkerPath,
                storePath: root.appendingPathComponent("legacy-antigravity.json"),
                relayCredentialsPath: root.appendingPathComponent("relay.json"),
                codexBarConfigPath: root.appendingPathComponent("config.json")
            ),
            keychainStore: keychain
        )
        let nativeScenario = scenario ?? SyntheticNativeScenario(
            currentEmail: "synthetic@example.invalid", targetEmail: "synthetic@example.invalid"
        )
        coordinator = AccountsCoordinator(
            storeRepository: store,
            settingsRepository: FixedSettingsRepository(settings),
            authRepository: StubAuthRepository(),
            usageService: StubUsageService(),
            chatGPTOAuthLoginService: StubLoginService(),
            codexCLIService: StubCodexCLIService(),
            editorAppService: editor,
            opencodeAuthSyncService: StubOpencodeService(),
            antigravityAuthRepository: repository,
            antigravityUsageService: Self.nativeUsageService(scenario: nativeScenario),
            dateProvider: FixedDateProvider(),
            runtimePlatform: .macOS
        )
    }

    func removeTemporaryFiles() { try? FileManager.default.removeItem(at: root) }

    private static func nativeUsageService(scenario: SyntheticNativeScenario) -> AntigravityUsageService {
        let native = AntigravityNativeUsageService(
            processListing: {
                "4242 /private/var/folders/synthetic/language_server --app_data_dir \"/tmp/antigravity\" --csrf_token=synthetic"
            },
            listeningPorts: { _ in [61_091] },
            requestLoader: { request in
                let state = scenario.snapshot
                let body: Data
                switch request.url?.lastPathComponent {
                case "GetUnleashData":
                    body = Data()
                case "Login":
                    body = Data(#"{"authResult":{"hasValidAuth":true}}"#.utf8)
                case "GetUserStatus":
                    body = Data("{\"userStatus\":{\"email\":\"\(state.email)\",\"userTier\":{\"name\":\"Pro\"}}}".utf8)
                case "RetrieveUserQuotaSummary":
                    let remaining = max(0, min(1, (100 - state.usedPercent) / 100))
                    body = Data("{\"response\":{\"groups\":[{\"displayName\":\"Synthetic\",\"buckets\":[{\"bucketId\":\"synthetic-5h\",\"displayName\":\"Synthetic five hour\",\"remainingFraction\":\(remaining),\"window\":\"5h\"}]}]}}".utf8)
                default:
                    throw URLError(.badURL)
                }
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://127.0.0.1")!,
                    statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (body, response)
            }
        )
        return AntigravityUsageService(
            dateProvider: FixedDateProvider(),
            nativeUsageService: native,
            userInfoLoader: { request in
                let body = Data("{\"email\":\"\(scenario.targetEmail)\"}".utf8)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://openidconnect.googleapis.com")!,
                    statusCode: 200, httpVersion: nil, headerFields: nil
                )!
                return (body, response)
            }
        )
    }
}

private final class SyntheticKeychainStore: AntigravityKeychainStoreProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var secret: Data?
    private let readError: AntigravityNativeCredentialAccessError?
    private let preflightError: AntigravityNativeCredentialAccessError?
    private(set) var readAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var preflightAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var writeAccesses: [AntigravityNativeCredentialAccess] = []

    init(
        secret: Data? = nil,
        readError: AntigravityNativeCredentialAccessError? = nil,
        preflightError: AntigravityNativeCredentialAccessError? = nil
    ) {
        self.secret = secret
        self.readError = readError
        self.preflightError = preflightError
    }

    var currentSecret: Data? {
        lock.lock()
        defer { lock.unlock() }
        return secret
    }

    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data? {
        lock.lock()
        readAccesses.append(access)
        let error = readError
        let value = secret
        lock.unlock()
        if let error { throw error }
        return value
    }

    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws {
        lock.lock()
        writeAccesses.append(access)
        secret = data
        lock.unlock()
    }

    func removeSecret(access: AntigravityNativeCredentialAccess) throws {
        lock.lock()
        writeAccesses.append(access)
        secret = nil
        lock.unlock()
    }

    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        lock.lock()
        preflightAccesses.append(access)
        let error = preflightError
        let current = secret
        lock.unlock()
        if let error { throw error }
        guard let existingSecret else {
            throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
        }
        guard current == existingSecret else {
            throw AntigravityNativeCredentialAccessError.unavailable
        }
    }
}

private final class SyntheticNativeScenario: @unchecked Sendable {
    private let lock = NSLock()
    private var email: String
    let targetEmail: String
    private var usedPercent: Double

    init(currentEmail: String, targetEmail: String, usedPercent: Double = 100) {
        email = currentEmail
        self.targetEmail = targetEmail
        self.usedPercent = usedPercent
    }

    var activeEmail: String {
        lock.lock()
        defer { lock.unlock() }
        return email
    }

    var snapshot: (email: String, usedPercent: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (email, usedPercent)
    }

    func activateTarget() {
        lock.lock()
        email = targetEmail
        usedPercent = 10
        lock.unlock()
    }
}

private final class RecordingEditor: EditorAppServiceProtocol, @unchecked Sendable {
    enum LaunchAction {
        case fail
        case keepCurrent
        case activateTarget
    }

    private let lock = NSLock()
    private var running: Bool
    private let scenario: SyntheticNativeScenario?
    private var launchActions: [LaunchAction]
    private var recordedLaunchCount = 0
    private var recordedQuitCount = 0

    init(running: Bool, scenario: SyntheticNativeScenario? = nil, launchActions: [LaunchAction]) {
        self.running = running
        self.scenario = scenario
        self.launchActions = launchActions
    }

    var launchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedLaunchCount
    }

    var quitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return recordedQuitCount
    }

    func listInstalledApps() -> [InstalledEditorApp] { [] }
    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) { ([], nil) }

    func launchApp(_ target: EditorAppID) -> (launched: Bool, error: String?) {
        guard target == .antigravity else { return (false, nil) }
        lock.lock()
        recordedLaunchCount += 1
        let action = launchActions.isEmpty ? .keepCurrent : launchActions.removeFirst()
        if action == .fail {
            lock.unlock()
            return (false, "synthetic-launch-failure")
        }
        running = true
        lock.unlock()
        if action == .activateTarget { scenario?.activateTarget() }
        return (true, nil)
    }

    func isAppRunning(_ target: EditorAppID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return target == .antigravity && running
    }

    func quitAppGracefully(
        _ target: EditorAppID,
        timeoutSeconds: TimeInterval
    ) -> (didQuit: Bool, error: String?) {
        _ = timeoutSeconds
        guard target == .antigravity else { return (false, nil) }
        lock.lock()
        recordedQuitCount += 1
        running = false
        lock.unlock()
        return (true, nil)
    }
}

private final class InMemoryStore: AccountsStoreRepository, @unchecked Sendable {
    private var value: AccountsStore
    init(_ value: AccountsStore) { self.value = value }
    func loadStore() throws -> AccountsStore { value }
    func saveStore(_ store: AccountsStore) throws { value = store }
    func mutateStore(_ transform: (inout AccountsStore) throws -> Void) throws -> AccountsStore {
        try transform(&value)
        return value
    }
}

private final class FixedSettingsRepository: SettingsRepository, @unchecked Sendable {
    private var settings: AppSettings
    init(_ settings: AppSettings) { self.settings = settings }
    func loadSettings() throws -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws { self.settings = settings }
}

private final class StubAuthRepository: AuthRepository, @unchecked Sendable {
    func readCurrentAuth() throws -> JSONValue { .null }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue { .null }
    func writeCurrentAuth(_ auth: JSONValue) throws {}
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue { .null }
    func exchangeAuth(email: String, refreshToken: String) async throws -> JSONValue { .null }
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        ExtractedAuth(accountID: "synthetic", accessToken: "synthetic", email: "synthetic@example.invalid", planType: "pro", teamName: nil)
    }
    func refreshChatGPTAuth(_ auth: JSONValue) async throws -> JSONValue { auth }
}

private final class StubUsageService: UsageService, @unchecked Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        P1NativePermissionTerminalDriver.verifiedUsage(usedPercent: 0)
    }
}

private final class StubLoginService: ChatGPTOAuthLoginServiceProtocol, @unchecked Sendable {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        throw AppError.invalidData("unavailable")
    }
}

private final class StubCodexCLIService: CodexCLIServiceProtocol, @unchecked Sendable {
    func launchApp(workspacePath: String?) throws -> Bool { false }
}

private final class StubOpencodeService: AILSA_SSAuthSyncServiceProtocol, @unchecked Sendable {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {}
}

private final class FixedDateProvider: DateProviding, @unchecked Sendable {
    func unixSecondsNow() -> Int64 { 1_763_216_000 }
}
