import Foundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AppContainer {
    let accountsModel: AccountsPageModel
    let settingsModel: SettingsPageModel
    let quotaManagementModel: QuotaManagementPageModel
    let trayModel: TrayMenuModel

    private let settingsCoordinator: SettingsCoordinator
    private let accountsWidgetSnapshotWriter: AccountsWidgetSnapshotWriter
    private let accountsWidgetDisplayModeStore: AccountsWidgetDisplayModeStore
    private var accountsWidgetSnapshotCancellable: AnyCancellable?
    private var accountsPageSnapshotCancellable: AnyCancellable?
    private var widgetUsageProgressDisplayMode: UsageProgressDisplayMode
    private var widgetQuotaVisibility: UsageQuotaVisibilityPreferences

    static func liveOrCrash() -> AppContainer {
        do {
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let settingsRepository = SettingsFileRepository(paths: paths)
            let authRepository = AuthFileRepository(paths: paths)
            let initialAccounts = try initialAccountsSnapshot(using: storeRepository)
            let usageService = DefaultUsageService(configPath: paths.codexConfigPath)
            let workspaceMetadataService = DefaultWorkspaceMetadataService(configPath: paths.codexConfigPath)
            let chatGPTOAuthLoginService = OpenAIChatGPTOAuthLoginService(configPath: paths.codexConfigPath)
            let codexCLIService = CodexCLIService()
            let editorAppService = EditorAppService()
            let opencodeSyncService = AILSA_SSAuthSyncService()
            let launchAtStartupService = LaunchAtStartupService()
            let antigravityAuthRepository = AntigravityAuthRepository()
            let accountsCoordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                settingsRepository: settingsRepository,
                authRepository: authRepository,
                usageService: usageService,
                workspaceMetadataService: workspaceMetadataService,
                chatGPTOAuthLoginService: chatGPTOAuthLoginService,
                codexCLIService: codexCLIService,
                editorAppService: editorAppService,
                opencodeAuthSyncService: opencodeSyncService,
                antigravityAuthRepository: antigravityAuthRepository,
                antigravityUsageService: AntigravityUsageService()
            )
            let settingsCoordinator = SettingsCoordinator(
                settingsRepository: settingsRepository,
                launchAtStartupService: launchAtStartupService
            )
            let initialSettings = try settingsRepository.loadSettings()
            // Scene titles and the menu bar label are built before RootScene
            // appears; seed the localization bundle from the saved locale now.
            L10n.setLocale(identifier: initialSettings.locale)
            var applySettingsToContainer: ((AppSettings) -> Void)?
            try launchAtStartupService.syncWithStoreValue(initialSettings.launchAtStartup)
            let accountsWidgetDisplayModeStore = AccountsWidgetDisplayModeStore()
            let accountsWidgetSnapshotWriter = AccountsWidgetSnapshotWriter(
                localeProvider: {
                    let identifier = (try? await settingsCoordinator.currentSettings().locale)
                        ?? AppLocale.systemDefault.identifier
                    return Locale(identifier: AppLocale.resolve(identifier).identifier)
                }
            )
            let trayModel = TrayMenuModel(
                accountsCoordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator,
                backgroundRefreshPolicy: .forPlatform(PlatformCapabilities.currentPlatform),
                initialAccounts: initialAccounts
            )
            let accountsModel = AccountsPageModel(
                coordinator: accountsCoordinator,
                settingsCoordinator: settingsCoordinator,
                manualRefreshService: trayModel,
                localAccountsMutationSyncService: trayModel,
                chooseAuthDocumentURL: {
                    #if canImport(AppKit)
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.canCreateDirectories = false
                    panel.allowedContentTypes = [.json]
                    panel.title = L10n.tr("accounts.action.import_auth_file")
                    NSApp.activate(ignoringOtherApps: true)
                    guard panel.runModal() == .OK else { return nil }
                    return panel.url
                    #else
                    return nil
                    #endif
                },
                runtimePlatform: PlatformCapabilities.currentPlatform,
                usageProgressDisplayMode: initialSettings.usageProgressDisplayMode,
                quotaVisibility: initialSettings.quotaVisibility,
                onLocalAccountsChanged: { accounts in
                    trayModel.acceptLocalAccountsSnapshot(accounts)
                },
                onSettingsUpdated: { settings in
                    applySettingsToContainer?(settings)
                },
                initialAccounts: initialAccounts
            )
            let settingsModel = SettingsPageModel(
                settingsCoordinator: settingsCoordinator,
                editorAppService: editorAppService,
                antigravityAutomaticSwitchCapabilityProvider: {
                    antigravityAuthRepository.automaticSwitchCapability()
                },
                onSettingsUpdated: { settings in
                    applySettingsToContainer?(settings)
                },
                onQuitRequested: {
                    #if canImport(AppKit)
                    NSApp.terminate(nil)
                    #endif
                }
            )
            let quotaManagementModel = QuotaManagementPageModel.live()
            settingsModel.updateQuotaVisibilityCatalog(from: initialAccounts)

            let container = AppContainer(
                settingsCoordinator: settingsCoordinator,
                accountsWidgetSnapshotWriter: accountsWidgetSnapshotWriter,
                accountsWidgetDisplayModeStore: accountsWidgetDisplayModeStore,
                widgetUsageProgressDisplayMode: initialSettings.usageProgressDisplayMode,
                widgetQuotaVisibility: initialSettings.quotaVisibility,
                accountsModel: accountsModel,
                settingsModel: settingsModel,
                quotaManagementModel: quotaManagementModel,
                trayModel: trayModel
            )
            applySettingsToContainer = { settings in
                container.applySettings(settings)
            }
            return container
        } catch {
            fatalError("Failed to bootstrap Swift migration app: \(error.localizedDescription)")
        }
    }

    private init(
        settingsCoordinator: SettingsCoordinator,
        accountsWidgetSnapshotWriter: AccountsWidgetSnapshotWriter,
        accountsWidgetDisplayModeStore: AccountsWidgetDisplayModeStore,
        widgetUsageProgressDisplayMode: UsageProgressDisplayMode,
        widgetQuotaVisibility: UsageQuotaVisibilityPreferences,
        accountsModel: AccountsPageModel,
        settingsModel: SettingsPageModel,
        quotaManagementModel: QuotaManagementPageModel,
        trayModel: TrayMenuModel
    ) {
        self.settingsCoordinator = settingsCoordinator
        self.accountsWidgetSnapshotWriter = accountsWidgetSnapshotWriter
        self.accountsWidgetDisplayModeStore = accountsWidgetDisplayModeStore
        self.widgetUsageProgressDisplayMode = widgetUsageProgressDisplayMode
        self.widgetQuotaVisibility = widgetQuotaVisibility
        self.accountsModel = accountsModel
        self.settingsModel = settingsModel
        self.quotaManagementModel = quotaManagementModel
        self.trayModel = trayModel
        accountsWidgetDisplayModeStore.save(rawValue: widgetUsageProgressDisplayMode.rawValue)
        accountsWidgetSnapshotCancellable = trayModel.$accounts
            .removeDuplicates()
            .sink { [weak self] accounts in
                guard let self else { return }
                Task {
                    await self.accountsWidgetSnapshotWriter.write(
                        accounts: accounts,
                        usageProgressDisplayMode: self.widgetUsageProgressDisplayMode,
                        quotaVisibility: self.widgetQuotaVisibility
                    )
                }
            }
        accountsPageSnapshotCancellable = trayModel.$accounts
            .removeDuplicates()
            .sink { [weak accountsModel, weak settingsModel] accounts in
                accountsModel?.acceptExternalAccountsSnapshot(accounts)
                settingsModel?.updateQuotaVisibilityCatalog(from: accounts)
            }
        Task {
            await accountsWidgetSnapshotWriter.write(
                accounts: trayModel.accounts,
                usageProgressDisplayMode: widgetUsageProgressDisplayMode,
                quotaVisibility: widgetQuotaVisibility
            )
        }
    }

    func applySettings(_ settings: AppSettings) {
        widgetUsageProgressDisplayMode = settings.usageProgressDisplayMode
        widgetQuotaVisibility = settings.quotaVisibility
        accountsWidgetDisplayModeStore.save(rawValue: settings.usageProgressDisplayMode.rawValue)
        trayModel.applySettings(settings)
        accountsModel.applySettings(settings)
        Task {
            await accountsWidgetSnapshotWriter.write(
                accounts: trayModel.accounts,
                usageProgressDisplayMode: settings.usageProgressDisplayMode,
                quotaVisibility: settings.quotaVisibility
            )
        }
    }

    private static func initialAccountsSnapshot(
        using storeRepository: StoreFileRepository
    ) throws -> [AccountSummary] {
        let store = try storeRepository.loadStore()
        return store.accountSummaries()
    }
}
