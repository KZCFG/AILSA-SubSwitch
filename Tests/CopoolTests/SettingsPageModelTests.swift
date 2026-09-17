import XCTest
@testable import Copool

@MainActor
final class SettingsPageModelTests: XCTestCase {
    func testQuitAppInvokesInjectedAction() {
        var didQuit = false
        let model = SettingsPageModel(
            settingsCoordinator: SettingsCoordinator(
                settingsRepository: TestSettingsRepository(),
                launchAtStartupService: SettingsStubLaunchAtStartupService()
            ),
            editorAppService: SettingsStubEditorAppService(),
            onQuitRequested: {
                didQuit = true
            }
        )

        model.quitApp()

        XCTAssertTrue(didQuit)
    }

    func testAccountsPageModelToggleUsageProgressDisplayPersistsAndShowsNotice() async {
        let settingsRepository = TestSettingsRepository(settings: .defaultValue)
        let settingsCoordinator = SettingsCoordinator(
            settingsRepository: settingsRepository,
            launchAtStartupService: SettingsStubLaunchAtStartupService()
        )
        let coordinator = AccountsCoordinator(
            storeRepository: SettingsTestAccountsStoreRepository(),
            settingsRepository: settingsRepository,
            authRepository: SettingsTestAuthRepository(),
            usageService: SettingsTestUsageService(),
            chatGPTOAuthLoginService: SettingsStubChatGPTOAuthLoginService(),
            codexCLIService: SettingsStubCodexCLIService(),
            editorAppService: SettingsStubEditorAppService(),
            opencodeAuthSyncService: SettingsStubOpencodeAuthSyncService(),
            dateProvider: SettingsFixedDateProvider(now: 1)
        )
        let model = AccountsPageModel(
            coordinator: coordinator,
            settingsCoordinator: settingsCoordinator
        )

        await model.handlePageAction(AccountsPageActionIntent.toggleUsageProgressDisplay)

        XCTAssertEqual(model.usageProgressDisplayMode, UsageProgressDisplayMode.remaining)
        XCTAssertEqual(
            try? settingsRepository.loadSettings().usageProgressDisplayMode,
            UsageProgressDisplayMode.remaining
        )
        XCTAssertEqual(
            model.notice?.text,
            L10n.tr(
                "accounts.notice.usage_progress_display_changed_format",
                L10n.tr("settings.usage_progress_display.remaining")
            )
        )
    }

    func testAccountsPageModelToggleUsageProgressDisplayInvokesSettingsUpdateCallback() async {
        let settingsRepository = TestSettingsRepository(settings: .defaultValue)
        let settingsCoordinator = SettingsCoordinator(
            settingsRepository: settingsRepository,
            launchAtStartupService: SettingsStubLaunchAtStartupService()
        )
        let coordinator = AccountsCoordinator(
            storeRepository: SettingsTestAccountsStoreRepository(),
            settingsRepository: settingsRepository,
            authRepository: SettingsTestAuthRepository(),
            usageService: SettingsTestUsageService(),
            chatGPTOAuthLoginService: SettingsStubChatGPTOAuthLoginService(),
            codexCLIService: SettingsStubCodexCLIService(),
            editorAppService: SettingsStubEditorAppService(),
            opencodeAuthSyncService: SettingsStubOpencodeAuthSyncService(),
            dateProvider: SettingsFixedDateProvider(now: 1)
        )
        var callbackMode: UsageProgressDisplayMode?
        let model = AccountsPageModel(
            coordinator: coordinator,
            settingsCoordinator: settingsCoordinator,
            onSettingsUpdated: { settings in
                callbackMode = settings.usageProgressDisplayMode
            }
        )

        await model.handlePageAction(AccountsPageActionIntent.toggleUsageProgressDisplay)

        XCTAssertEqual(callbackMode, .remaining)
    }
}

final class TestSettingsRepository: SettingsRepository, @unchecked Sendable {
    private var settings: AppSettings

    init(settings: AppSettings = .defaultValue) {
        self.settings = settings
    }

    func loadSettings() throws -> AppSettings {
        settings
    }

    func saveSettings(_ settings: AppSettings) throws {
        self.settings = settings
    }
}

private struct SettingsStubLaunchAtStartupService: LaunchAtStartupServiceProtocol {
    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }

    func syncWithStoreValue(_ enabled: Bool) throws {
        _ = enabled
    }
}

private struct SettingsStubEditorAppService: EditorAppServiceProtocol {
    func listInstalledApps() -> [InstalledEditorApp] {
        []
    }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        (targets, nil)
    }
}

private final class SettingsTestAccountsStoreRepository: AccountsStoreRepository, @unchecked Sendable {
    private var store = AccountsStore()

    func loadStore() throws -> AccountsStore {
        store
    }

    func saveStore(_ store: AccountsStore) throws {
        self.store = store
    }
}

private struct SettingsTestAuthRepository: AuthRepository {
    func readCurrentAuth() throws -> JSONValue { .object([:]) }
    func readCurrentAuthOptional() throws -> JSONValue? { nil }
    func readAuth(from url: URL) throws -> JSONValue { .object([:]) }
    func writeCurrentAuth(_ auth: JSONValue) throws {}
    func removeCurrentAuth() throws {}
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue { .object([:]) }

    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth {
        _ = auth
        return ExtractedAuth(
            accountID: "account-1",
            accessToken: "token",
            email: "test@example.com",
            planType: "pro",
            teamName: nil
        )
    }
}

private struct SettingsTestUsageService: UsageService {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot {
        _ = accessToken
        _ = accountID
        return UsageSnapshot(
            fetchedAt: 1,
            planType: "pro",
            fiveHour: nil,
            oneWeek: nil,
            credits: nil
        )
    }
}

private struct SettingsStubChatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens {
        _ = timeoutSeconds
        return ChatGPTOAuthTokens(
            accessToken: "token",
            refreshToken: "refresh",
            idToken: "id",
            apiKey: nil
        )
    }
}

private struct SettingsStubCodexCLIService: CodexCLIServiceProtocol {
    func launchApp(workspacePath: String?) throws -> Bool {
        _ = workspacePath
        return true
    }
}

private struct SettingsStubOpencodeAuthSyncService: OpencodeAuthSyncServiceProtocol {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        _ = authJSON
    }
}

private struct SettingsFixedDateProvider: DateProviding {
    let now: Int64

    func unixSecondsNow() -> Int64 {
        now
    }
}
