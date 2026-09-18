import XCTest
import Combine
@testable import AILSA_SS

@MainActor
final class AppSmokeTests: XCTestCase {
    func testAccountsPageLoadSwitchAndSettingsFlow() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = SmokeAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-current",
                        label: "Current",
                        email: "current@example.com",
                        accountID: "account-current",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("current-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: makeSmokeUsageSnapshot(fetchedAt: now),
                        usageError: nil
                    ),
                    StoredAccount(
                        id: "acct-next",
                        label: "Next",
                        email: "next@example.com",
                        accountID: "account-next",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("next-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: makeSmokeUsageSnapshot(fetchedAt: now),
                        usageError: nil
                    )
                ],
                currentAccountID: "acct-current",
                currentSelection: CurrentAccountSelection(
                    cardID: "acct-current",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "smoke-device"
                )
            )
        )
        let settingsRepository = TestSettingsRepository()
        let authRepository = SmokeAuthRepository(currentAccountKey: "account-current")
        let accountsCoordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            settingsRepository: settingsRepository,
            authRepository: authRepository,
            usageService: SmokeUsageService(snapshot: makeSmokeUsageSnapshot(fetchedAt: now)),
            chatGPTOAuthLoginService: SmokeChatLoginService(),
            codexCLIService: SmokeCodexCLIService(),
            editorAppService: SmokeEditorAppService(),
            opencodeAuthSyncService: SmokeAILSA_SSAuthSyncService(),
            dateProvider: SmokeDateProvider(now: now)
        )
        let settingsCoordinator = SettingsCoordinator(
            settingsRepository: settingsRepository,
            launchAtStartupService: SmokeLaunchAtStartupService()
        )
        let accountsModel = AccountsPageModel(
            coordinator: accountsCoordinator
        )
        let settingsModel = SettingsPageModel(
            settingsCoordinator: settingsCoordinator,
            editorAppService: SmokeEditorAppService()
        )

        await accountsModel.loadIfNeeded()
        guard case .content(let loadedAccounts) = accountsModel.state else {
            return XCTFail("Expected loaded accounts content state")
        }
        XCTAssertEqual(loadedAccounts.map(\.label), ["Current", "Next"])
        XCTAssertEqual(loadedAccounts.first(where: \.isCurrent)?.id, "acct-current")

        await accountsModel.switchAccount(id: "acct-next")
        guard case .content(let switchedAccounts) = accountsModel.state else {
            return XCTFail("Expected switched accounts content state")
        }
        XCTAssertEqual(switchedAccounts.first(where: \.isCurrent)?.id, "acct-next")
        XCTAssertEqual(authRepository.currentAccountKey, "account-next")

        settingsModel.settings = try await settingsCoordinator.currentSettings()
        settingsModel.setLaunchAtStartup(true)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(settingsModel.settings.launchAtStartup)
        XCTAssertEqual(try settingsRepository.loadSettings().launchAtStartup, true)
    }

    func testAccountsPageSmartSwitchUpdatesCurrentStateAndAuth() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = SmokeAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-current",
                        label: "Current",
                        email: "current@example.com",
                        accountID: "account-current",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("current-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: UsageSnapshot(
                            fetchedAt: now,
                            planType: "pro",
                            fiveHour: UsageWindow(usedPercent: 100, windowSeconds: 18_000, resetAt: nil),
                            oneWeek: UsageWindow(usedPercent: 95, windowSeconds: 604_800, resetAt: nil),
                            credits: nil
                        ),
                        usageError: nil
                    ),
                    StoredAccount(
                        id: "acct-next",
                        label: "Next",
                        email: "next@example.com",
                        accountID: "account-next",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("next-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: UsageSnapshot(
                            fetchedAt: now,
                            planType: "pro",
                            fiveHour: UsageWindow(usedPercent: 10, windowSeconds: 18_000, resetAt: nil),
                            oneWeek: UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: nil),
                            credits: nil
                        ),
                        usageError: nil
                    )
                ],
                currentAccountID: "acct-current",
                currentSelection: CurrentAccountSelection(
                    cardID: "acct-current",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "smoke-device"
                )
            )
        )
        let settingsRepository = TestSettingsRepository()
        let authRepository = SmokeAuthRepository(currentAccountKey: "account-current")
        let accountsCoordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            settingsRepository: settingsRepository,
            authRepository: authRepository,
            usageService: SmokeMappedUsageService(
                snapshotsByAccountID: [
                    "account-current": UsageSnapshot(
                        fetchedAt: now,
                        planType: "pro",
                        fiveHour: UsageWindow(usedPercent: 100, windowSeconds: 18_000, resetAt: nil),
                        oneWeek: UsageWindow(usedPercent: 95, windowSeconds: 604_800, resetAt: nil),
                        credits: nil
                    ),
                    "account-next": UsageSnapshot(
                        fetchedAt: now,
                        planType: "pro",
                        fiveHour: UsageWindow(usedPercent: 10, windowSeconds: 18_000, resetAt: nil),
                        oneWeek: UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: nil),
                        credits: nil
                    )
                ]
            ),
            chatGPTOAuthLoginService: SmokeChatLoginService(),
            codexCLIService: SmokeCodexCLIService(),
            editorAppService: SmokeEditorAppService(),
            opencodeAuthSyncService: SmokeAILSA_SSAuthSyncService(),
            dateProvider: SmokeDateProvider(now: now)
        )
        let model = AccountsPageModel(coordinator: accountsCoordinator)

        await model.loadIfNeeded()
        await model.smartSwitch()

        guard case .content(let switchedAccounts) = model.state else {
            return XCTFail("Expected switched accounts content state")
        }
        XCTAssertEqual(switchedAccounts.first(where: \.isCurrent)?.id, "acct-next")
        XCTAssertEqual(authRepository.currentAccountKey, "account-next")
    }

    func testTrayAutoSmartSwitchUpdatesAccountsPageCurrentState() async throws {
        let now: Int64 = 1_763_216_000
        let storeRepository = SmokeAccountsStoreRepository(
            store: AccountsStore(
                version: 1,
                accounts: [
                    StoredAccount(
                        id: "acct-current",
                        label: "Current",
                        email: "current@example.com",
                        accountID: "account-current",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("current-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    ),
                    StoredAccount(
                        id: "acct-next",
                        label: "Next",
                        email: "next@example.com",
                        accountID: "account-next",
                        planType: "pro",
                        teamName: nil,
                        teamAlias: nil,
                        authJSON: .object(["id_token": .string("next-token")]),
                        addedAt: now,
                        updatedAt: now,
                        usage: nil,
                        usageError: nil
                    )
                ],
                currentAccountID: "acct-current",
                currentSelection: CurrentAccountSelection(
                    cardID: "acct-current",
                    selectedAt: now * 1_000,
                    sourceDeviceID: "smoke-device"
                )
            )
        )
        var settings = AppSettings.defaultValue
        settings.autoSmartSwitch = true
        settings.launchCodexAfterSwitch = false
        let settingsRepository = TestSettingsRepository(settings: settings)
        let authRepository = SmokeAuthRepository(currentAccountKey: "account-current")
        let accountsCoordinator = AccountsCoordinator(
            storeRepository: storeRepository,
            settingsRepository: settingsRepository,
            authRepository: authRepository,
            usageService: SmokeMappedUsageService(
                snapshotsByAccountID: [
                    "account-current": UsageSnapshot(
                        fetchedAt: now,
                        planType: "pro",
                        fiveHour: UsageWindow(usedPercent: 100, windowSeconds: 18_000, resetAt: nil),
                        oneWeek: UsageWindow(usedPercent: 95, windowSeconds: 604_800, resetAt: nil),
                        credits: nil
                    ),
                    "account-next": UsageSnapshot(
                        fetchedAt: now,
                        planType: "pro",
                        fiveHour: UsageWindow(usedPercent: 10, windowSeconds: 18_000, resetAt: nil),
                        oneWeek: UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: nil),
                        credits: nil
                    )
                ]
            ),
            chatGPTOAuthLoginService: SmokeChatLoginService(),
            codexCLIService: SmokeCodexCLIService(),
            editorAppService: SmokeEditorAppService(),
            opencodeAuthSyncService: SmokeAILSA_SSAuthSyncService(),
            dateProvider: SmokeDateProvider(now: now)
        )
        let settingsCoordinator = SettingsCoordinator(
            settingsRepository: settingsRepository,
            launchAtStartupService: SmokeLaunchAtStartupService()
        )
        let trayModel = TrayMenuModel(
            accountsCoordinator: accountsCoordinator,
            settingsCoordinator: settingsCoordinator,
            backgroundRefreshPolicy: .init(
                initialRefreshDelay: .zero,
                usageRefreshInterval: .seconds(30),
                refreshUsageOnRecurringTick: false
            ),
            dateProvider: SmokeDateProvider(now: now),
            initialAccounts: try await accountsCoordinator.listAccounts(refreshWorkspaceMetadata: false)
        )
        trayModel.autoSmartSwitchEnabled = true
        let accountsModel = AccountsPageModel(
            coordinator: accountsCoordinator,
            manualRefreshService: trayModel,
            localAccountsMutationSyncService: trayModel,
            onLocalAccountsChanged: { accounts in
                trayModel.acceptLocalAccountsSnapshot(accounts)
            },
            initialAccounts: try await accountsCoordinator.listAccounts(refreshWorkspaceMetadata: false)
        )
        let accountsSyncCancellable = trayModel.$accounts
            .removeDuplicates()
            .sink { accounts in
                accountsModel.acceptExternalAccountsSnapshot(accounts)
            }
        defer { _ = accountsSyncCancellable }

        await accountsModel.loadIfNeeded()
        let localRefreshResult = try await trayModel.refreshLocalAccounts(
            forceUsageRefresh: true,
            prefersSerialUsageRefresh: false,
            bypassUsageThrottle: true,
            targetAccountIDs: nil,
            onPartialUpdate: nil
        )
        let latestAccounts = localRefreshResult.accounts
        trayModel.acceptLocalAccountsSnapshot(latestAccounts)

        XCTAssertEqual(authRepository.currentAccountKey, "account-next")
        guard case .content(let accounts) = accountsModel.state else {
            return XCTFail("Expected accounts page content state")
        }
        XCTAssertEqual(accounts.first(where: \.isCurrent)?.id, "acct-next")
    }
}

private func makeSmokeUsageSnapshot(fetchedAt: Int64) -> UsageSnapshot {
    UsageSnapshot(
        fetchedAt: fetchedAt,
        planType: "pro",
        fiveHour: nil,
        oneWeek: nil,
        credits: nil
    )
}

private final class SmokeAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var store: AccountsStore

    init(store: AccountsStore) {
        self.store = store
    }

    func loadStore() throws -> AccountsStore {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    func saveStore(_ store: AccountsStore) throws {
        lock.lock()
        self.store = store
        lock.unlock()
    }
}

private final class SmokeAuthRepository: AuthRepository, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var currentAccountKey: String?
    private var currentAuth: JSONValue

    init(currentAccountKey: String?) {
        self.currentAccountKey = currentAccountKey
        self.currentAuth = .object(["id_token": .string("current-token")])
    }

    func readCurrentAuth() throws -> JSONValue { currentAuth }
    func readCurrentAuthOptional() throws -> JSONValue? { currentAuth }

    func readAuth(from url: URL) throws -> JSONValue {
        _ = url
        return currentAuth
    }

    func writeCurrentAuth(_ auth: JSONValue) throws {
        lock.lock()
        currentAuth = auth
        if case .object(let object) = auth,
           case .string(let token) = object["id_token"] {
            currentAccountKey = token == "next-token" ? "account-next" : "account-current"
        }
        lock.unlock()
    }

    func removeCurrentAuth() throws {
        lock.lock()
        currentAuth = .object([:])
        currentAccountKey = nil
        lock.unlock()
    }

    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue {
        .object([
            "id_token": .string(tokens.idToken),
            "access_token": .string(tokens.accessToken),
            "refresh_token": .string(tokens.refreshToken)
        ])
    }

    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        let token: String
        if case .object(let object) = auth,
           case .string(let idToken) = object["id_token"] {
            token = idToken
        } else {
            token = "current-token"
        }
        let accountID = token == "next-token" ? "account-next" : "account-current"
        return ExtractedAuth(
            accountID: accountID,
            accessToken: "access-token",
            email: accountID == "account-next" ? "next@example.com" : "current@example.com",
            planType: "pro",
            teamName: nil,
            principalID: accountID
        )
    }

}

private struct SmokeUsageService: UsageService {
    let snapshot: UsageSnapshot

    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        _ = accountID
        return snapshot
    }
}

private struct SmokeMappedUsageService: UsageService {
    let snapshotsByAccountID: [String: UsageSnapshot]

    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        guard let snapshot = snapshotsByAccountID[accountID] else {
            throw AppError.invalidData("Missing smoke usage snapshot for \(accountID)")
        }
        return snapshot
    }
}

private struct SmokeDateProvider: DateProviding {
    let now: Int64

    func unixSecondsNow() -> Int64 {
        now
    }
}

private struct SmokeChatLoginService: ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        _ = timeoutSeconds
        return ChatGPTOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            idToken: "id"
        )
    }
}

private struct SmokeCodexCLIService: CodexCLIServiceProtocol {
    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        return true
    }
}

private struct SmokeEditorAppService: EditorAppServiceProtocol {
    func listInstalledApps() -> [InstalledEditorApp] { [] }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        (targets, nil)
    }
}

private struct SmokeAILSA_SSAuthSyncService: AILSA_SSAuthSyncServiceProtocol {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        _ = authJSON
    }

    func syncFromAntigravityAuth(_ authJSON: JSONValue) throws {
        _ = authJSON
    }
}

private final class SmokeLaunchAtStartupService: LaunchAtStartupServiceProtocol, @unchecked Sendable {
    private(set) var enabled = false

    func setEnabled(_ enabled: Bool) throws {
        self.enabled = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        self.enabled = enabled
    }
}
