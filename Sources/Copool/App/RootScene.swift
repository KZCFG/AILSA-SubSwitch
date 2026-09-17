import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

struct RootScene: View {
    @State private var selectedTab: AppTab = .accounts
    @StateObject private var chromeStore: RootSceneChromeStore
    private let trayModel: TrayMenuModel
    private let accountsModel: AccountsPageModel
    private let settingsModel: SettingsPageModel
    private let quotaManagementModel: QuotaManagementPageModel

    init(container: AppContainer, trayModel: TrayMenuModel) {
        self.accountsModel = container.accountsModel
        self.settingsModel = container.settingsModel
        self.quotaManagementModel = container.quotaManagementModel
        _chromeStore = StateObject(
            wrappedValue: RootSceneChromeStore(
                accountsModel: container.accountsModel,
                settingsModel: container.settingsModel
            )
        )
        self.trayModel = trayModel
    }

    private var runtimeLocale: Locale {
        Locale(identifier: AppLocale.resolve(chromeStore.localeIdentifier).identifier)
    }

    private var currentNotice: NoticeMessage? {
        switch selectedTab {
        case .accounts:
            return chromeStore.accountsNotice
        case .quotaManagement:
            return quotaManagementModel.notice
        case .settings:
            return chromeStore.settingsNotice
        }
    }

    private var currentAppLocale: AppLocale {
        AppLocale.resolve(chromeStore.localeIdentifier)
    }

    /// This must not depend on `selectedTab`: a `MenuBarExtra` using the
    /// window style asks NSHostingView to animate every content-size change.
    /// macOS 26 can throw an AppKit constraint exception during that display
    /// cycle. A stable panel size keeps tab/provider swaps inside the existing
    /// hosting window rather than resizing it.
    private var macPanelSize: CGSize {
        let desired = CGSize(
            width: LayoutRules.accountsPageTargetWidth,
            height: LayoutRules.macOSMenuBarPanelHeight
        )
        #if canImport(AppKit)
        guard let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame else {
            return desired
        }
        return CGSize(
            width: min(desired.width, max(360, visibleFrame.width - 32)),
            height: min(desired.height, max(LayoutRules.minimumPanelHeight, visibleFrame.height - 32))
        )
        #else
        return desired
        #endif
    }

    private var visibleTabs: [AppTab] {
        #if os(iOS)
        [.accounts, .quotaManagement]
        #else
        AppTab.allCases
        #endif
    }

    var body: some View {
        platformTabShell
        .modifier(ASModalSurface())
        .appCanvas()
        .appAccentTint()
        .environment(\.locale, runtimeLocale)
        .onAppear {
            selectedTab = .accounts
            Task { await quotaManagementModel.refreshOnWindowOpen() }
            L10n.setLocale(identifier: chromeStore.localeIdentifier)
        }
        .onChange(of: chromeStore.localeIdentifier) { _, value in
            L10n.setLocale(identifier: value)
        }
        .onReceive(trayModel.$accounts.removeDuplicates()) { _ in
            Task {
                await accountsModel.reloadFromLocalStoreAfterExternalMutation()
            }
        }
        .onReceive(trayModel.$remoteUsageRefreshingAccountIDs.removeDuplicates()) { accountIDs in
            accountsModel.syncRemoteUsageRefreshActivity(refreshingAccountIDs: accountIDs)
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .copoolOpenQuotaDisplaySettings)) { _ in
            // Keep routing inside the already-fixed MenuBarExtra host. This
            // changes content only; RootScene never asks AppKit to resize the
            // popup while opening the relevant settings page.
            selectedTab = .settings
            settingsModel.openQuotaDisplaySettings()
        }
        #endif
        .task {
            await accountsModel.loadIfNeeded()
        }
        .task {
            await settingsModel.loadIfNeeded()
        }
        .rootSceneNoticePresentation(currentNotice)
        #if os(macOS)
        // Keep all layout updates non-animated inside the fixed MenuBarExtra
        // host. This complements the stable size above and avoids a second
        // window-size transaction when selection state changes.
        .transaction { transaction in
            transaction.animation = nil
        }
        .environment(\.panelViewportSize, macPanelSize)
        .frame(
            width: macPanelSize.width,
            height: macPanelSize.height,
            alignment: .topLeading
        )
        #else
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(uiColor: .systemBackground))
        #endif
    }

    @ViewBuilder
    private var platformTabShell: some View {
        #if os(iOS)
        TabView(selection: $selectedTab) {
            NavigationStack {
                AccountsPageView(
                    model: accountsModel,
                    currentLocale: currentAppLocale,
                    onSelectLocale: { locale in
                        settingsModel.setLocale(locale.identifier)
                    }
                )
            }
            .tag(AppTab.accounts)
            .tabItem {
                Label {
                    Text(AppTab.accounts.toolbarTitle)
                } icon: {
                    Image(systemName: AppTab.accounts.iconName)
                }
            }
            NavigationStack {
                QuotaManagementPageView(model: quotaManagementModel)
            }
            .tag(AppTab.quotaManagement)
            .tabItem {
                Label {
                    Text(AppTab.quotaManagement.toolbarTitle)
                } icon: {
                    Image(systemName: AppTab.quotaManagement.iconName)
                }
            }
        }
        #else
        VStack(spacing: 0) {
            AppTabToolbarSwitcher(selection: $selectedTab, tabs: visibleTabs)
                .frame(maxWidth: LayoutRules.tabSwitcherMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, LayoutRules.pagePadding)
                .padding(.top, 10)
                .padding(.bottom, 8)

            activePage
        }
        #endif
    }

    @ViewBuilder
    private var activePage: some View {
        switch selectedTab {
        case .accounts:
            AccountsPageView(
                model: accountsModel,
                currentLocale: currentAppLocale,
                onSelectLocale: { locale in
                    settingsModel.setLocale(locale.identifier)
                }
            )
        case .quotaManagement:
            QuotaManagementPageView(model: quotaManagementModel)
        case .settings:
            SettingsPageView(model: settingsModel)
        }
    }

}

@MainActor
private final class RootSceneChromeStore: ObservableObject {
    @Published private(set) var localeIdentifier: String
    @Published private(set) var accountsNotice: NoticeMessage?
    @Published private(set) var settingsNotice: NoticeMessage?

    private var cancellables: Set<AnyCancellable> = []

    init(accountsModel: AccountsPageModel, settingsModel: SettingsPageModel) {
        localeIdentifier = settingsModel.settings.locale
        accountsNotice = accountsModel.notice
        settingsNotice = settingsModel.notice

        settingsModel.$settings
            .map(\.locale)
            .removeDuplicates()
            .sink { [weak self] localeIdentifier in
                self?.localeIdentifier = localeIdentifier
            }
            .store(in: &cancellables)

        accountsModel.$notice
            .removeDuplicates()
            .sink { [weak self] notice in
                self?.accountsNotice = notice
            }
            .store(in: &cancellables)

        settingsModel.$notice
            .removeDuplicates()
            .sink { [weak self] notice in
                self?.settingsNotice = notice
            }
            .store(in: &cancellables)
    }
}

private extension View {
    @ViewBuilder
    func rootSceneNoticePresentation(_ notice: NoticeMessage?) -> some View {
        #if os(iOS)
        self
            .animation(.easeInOut(duration: 0.2), value: notice)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NoticeBanner(notice: notice)
                    .allowsHitTesting(false)
                    .padding(.horizontal, LayoutRules.pagePadding)
                    .padding(.bottom, 6)
            }
        #else
        self
            .overlay(alignment: .top) {
                NoticeBanner(notice: notice)
                    .padding(.horizontal, LayoutRules.pagePadding)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        #endif
    }
}

private struct AppTabToolbarSwitcher: View {
    @Binding var selection: AppTab
    let tabs: [AppTab]
    var body: some View {
        ASSegmentedControl(selection: $selection, values: tabs,
                           title: { $0.toolbarTitle }, icon: { $0.iconName })
    }
}

private extension AppTab {
    var iconName: String {
        switch self {
        case .accounts: return "person.2"
        case .quotaManagement: return "chart.bar.xaxis"
        case .settings: return "gearshape"
        }
    }

    var titleTranslationKey: String {
        switch self {
        case .accounts: return "tab.accounts"
        case .quotaManagement: return "tab.quota_management"
        case .settings: return "tab.settings"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .accounts: return "tab.accounts"
        case .quotaManagement: return "tab.quota_management"
        case .settings: return "tab.settings"
        }
    }

    var toolbarTitle: String {
        L10n.tr(titleTranslationKey)
    }
}
