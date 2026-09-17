import SwiftUI

struct AccountsPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        #if os(iOS)
        AccountsIOSPageShell(
            model: model,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onReauthenticateAccount: onReauthenticateAccount,
            onAuthorizeWorkspace: onAuthorizeWorkspace,
            onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
            onDeletePendingWorkspace: onDeletePendingWorkspace,
            onDeleteAccount: onDeleteAccount
        )
        #else
        AccountsMacPageShell(
            model: model,
            areCardsPresented: areCardsPresented,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse,
            onSwitchAccount: onSwitchAccount,
            onRefreshAccountUsage: onRefreshAccountUsage,
            onReauthenticateAccount: onReauthenticateAccount,
            onAuthorizeWorkspace: onAuthorizeWorkspace,
            onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
            onDeletePendingWorkspace: onDeletePendingWorkspace,
            onDeleteAccount: onDeleteAccount
        )
        #endif
    }
}

#if os(iOS)
private struct AccountsIOSPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            AccountsIOSContentHost(
                model: model,
                safeAreaInsets: proxy.safeAreaInsets,
                viewportSize: proxy.size,
                areCardsPresented: areCardsPresented,
                onSwitchAccount: onSwitchAccount,
                onRefreshAccountUsage: onRefreshAccountUsage,
                onReauthenticateAccount: onReauthenticateAccount,
                onAuthorizeWorkspace: onAuthorizeWorkspace,
                onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
                onDeletePendingWorkspace: onDeletePendingWorkspace,
                onDeleteAccount: onDeleteAccount
            )
            .ignoresSafeArea(edges: [.top, .bottom])
            .toolbar {
                AccountsToolbarHost(
                    model: model,
                    currentLocale: currentLocale,
                    onSelectLocale: onSelectLocale,
                    onTriggerAction: onTriggerAction,
                    onToggleCollapse: onToggleCollapse
                )
            }
        }
    }
}
#endif

private struct AccountsMacPageShell: View {
    @ObservedObject var model: AccountsPageModel
    let areCardsPresented: Bool
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    private var pageContentWidth: CGFloat {
        LayoutRules.accountsPageContentWidth(isCompactWidth: false) ?? LayoutRules.accountsPageTargetWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
            AccountsPageHeader(selectedProvider: $model.selectedProvider)
            .padding(.horizontal, LayoutRules.pagePadding)
            .frame(width: pageContentWidth, alignment: .leading)

            if model.selectedProvider == .cursor {
                CursorAccountsView(progressMode: model.usageProgressDisplayMode, visibility: model.quotaVisibilityPreferences)
            } else {
            AccountsMacActionBarHost(
                model: model,
                onTriggerAction: onTriggerAction,
                onToggleCollapse: onToggleCollapse
            )
            .padding(.horizontal, LayoutRules.pagePadding)
            .frame(width: pageContentWidth, alignment: .leading)

            AccountsMacContentHost(
                model: model,
                pageContentWidth: pageContentWidth,
                areCardsPresented: areCardsPresented,
                onSwitchAccount: onSwitchAccount,
                onRefreshAccountUsage: onRefreshAccountUsage,
                onReauthenticateAccount: onReauthenticateAccount,
                onAuthorizeWorkspace: onAuthorizeWorkspace,
                onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
                onDeletePendingWorkspace: onDeletePendingWorkspace,
                onDeleteAccount: onDeleteAccount
            )
            }
        }
        .frame(width: pageContentWidth, alignment: .topLeading)
        .padding(.top, LayoutRules.pagePadding)
    }
}

private struct AccountsMacActionBarHost: View {
    @ObservedObject var model: AccountsPageModel
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void
    @Environment(\.panelViewportSize) private var panelViewportSize

    var body: some View {
        AccountsActionBarView(
            presentation: model.makeMacActionBarPresentation(
                forceOverview: LayoutRules.accountsForcesCompactCards(panelHeight: panelViewportSize?.height)),
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse
        )
    }
}

#if os(iOS)
private struct AccountsIOSContentHost: View {
    @ObservedObject var model: AccountsPageModel
    let safeAreaInsets: EdgeInsets
    let viewportSize: CGSize
    let areCardsPresented: Bool
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountsPageHeader(selectedProvider: $model.selectedProvider)
                .padding(.horizontal, LayoutRules.pagePadding)
                .padding(.bottom, LayoutRules.sectionSpacing)

            AccountsPageContentSection(
                presentation: model.makeContentPresentation(),
                cards: model.makeAccountCardViewStates(),
                availableViewportSize: viewportSize,
                areCardsPresented: areCardsPresented,
                onSwitchAccount: onSwitchAccount,
                onRefreshAccountUsage: onRefreshAccountUsage,
                onReauthenticateAccount: onReauthenticateAccount,
                onAuthorizeWorkspace: onAuthorizeWorkspace,
                onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
                onDeletePendingWorkspace: onDeletePendingWorkspace,
                onDeleteAccount: onDeleteAccount
            )
            Spacer(minLength: 0)
        }
        .padding(.top, LayoutRules.iOSAccountsContentTopPadding(safeAreaTop: safeAreaInsets.top))
        .padding(.bottom, LayoutRules.iOSAccountsContentBottomPadding(safeAreaBottom: safeAreaInsets.bottom))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif

private struct AccountsMacContentHost: View {
    @ObservedObject var model: AccountsPageModel
    let pageContentWidth: CGFloat
    let areCardsPresented: Bool
    @Environment(\.panelViewportSize) private var panelViewportSize
    private var forcesCompactCards: Bool {
        LayoutRules.accountsForcesCompactCards(panelHeight: panelViewportSize?.height)
    }
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AccountsPageContentSection(
                presentation: model.makeContentPresentation(forceOverview: forcesCompactCards),
                cards: model.makeAccountCardViewStates(forceCollapsed: forcesCompactCards),
                availableViewportSize: CGSize(
                    width: pageContentWidth,
                    height: panelViewportSize?.height ?? LayoutRules.accountsPanelHeight
                ),
                areCardsPresented: areCardsPresented,
                onSwitchAccount: onSwitchAccount,
                onRefreshAccountUsage: onRefreshAccountUsage,
                onReauthenticateAccount: onReauthenticateAccount,
                onAuthorizeWorkspace: onAuthorizeWorkspace,
                onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
                onDeletePendingWorkspace: onDeletePendingWorkspace,
                onDeleteAccount: onDeleteAccount
            )
            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .frame(width: pageContentWidth, alignment: .leading)
    }
}

private struct AccountsPageHeader: View {
    @Binding var selectedProvider: AccountProvider

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.groupSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L10n.tr("tab.accounts"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(AppDesign.primaryText(for: colorScheme))

                Spacer(minLength: 0)

                Text(providerTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppDesign.mutedText(for: colorScheme))
            }

            AccountsProviderSwitcher(selection: $selectedProvider)
        }
    }

    private var providerTitle: String {
        switch selectedProvider {
        case .codex:
            L10n.tr("accounts.provider.codex")
        case .antigravity:
            L10n.tr("accounts.provider.antigravity")
        case .cursor: "Cursor"
        }
    }
}

private struct AccountsProviderSwitcher: View {
    @Binding var selection: AccountProvider

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let providers: [AccountProvider] = [.codex, .antigravity, .cursor]

    var body: some View {
        ASSegmentedControl(selection: $selection, values: providers,
            title: providerTitle, icon: { providerIcon($0) })
    }

    private func providerTitle(_ provider: AccountProvider) -> String {
        switch provider {
        case .codex:
            L10n.tr("accounts.provider.codex")
        case .antigravity:
            L10n.tr("accounts.provider.antigravity")
        case .cursor: "Cursor"
        }
    }

    private func providerIcon(_ provider: AccountProvider) -> String {
        switch provider {
        case .codex:
            "terminal"
        case .antigravity:
            "sparkles"
        case .cursor: "cube"
        }
    }
}

#if os(iOS)
private struct AccountsToolbarHost: ToolbarContent {
    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void

    var body: some ToolbarContent {
        AccountsToolbarActions(
            leadingButtons: model.leadingToolbarButtons,
            trailingButtons: model.trailingToolbarButtons,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            onTriggerAction: onTriggerAction,
            onToggleCollapse: onToggleCollapse
        )
    }
}
#endif
