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
            .id(model.selectedProvider)
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
    @EnvironmentObject private var modal: ASModalHost

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AccountsActionBarView(
                presentation: model.makeMacActionBarPresentation(
                    forceOverview: LayoutRules.accountsForcesCompactCards(panelHeight: panelViewportSize?.height)),
                onTriggerAction: onTriggerAction,
                onToggleCollapse: onToggleCollapse
            )

            if let stage = model.addAccountProgressStage {
                AddAccountProgressCard(
                    stage: stage,
                    onCancel: model.cancelAddAccount,
                    onShowAuthorizationInfo: {
                        modal.present(onClose: {}) {
                            AddAccountAuthorizationInfoContent()
                        }
                    }
                )
            }
        }
    }
}

private struct AddAccountProgressCard: View {
    let stage: AccountAddProgressStage
    let onCancel: () -> Void
    let onShowAuthorizationInfo: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 22, height: 22)
                .padding(7)
                .background(
                    AppDesign.selectedSurface(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr(stage.titleKey))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppDesign.primaryText(for: colorScheme))
                Text(L10n.tr(stage.detailKey))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppDesign.secondaryText(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            if stage == .loginSucceeded || stage == .waitingForComputerAuthorization {
                Button(action: onShowAuthorizationInfo) {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppDesign.secondaryText(for: colorScheme))
                .accessibilityLabel(L10n.tr("accounts.add_progress.computer_authorization.info"))
            }

            Button(L10n.tr("common.cancel"), action: onCancel)
                .ailsaSSActionButtonStyle(density: .compact)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: 12)
        .accessibilityElement(children: .contain)
    }
}

private struct AddAccountAuthorizationInfoContent: View {
    @EnvironmentObject private var modal: ASModalHost
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppDesign.primaryText(for: colorScheme))
                    .frame(width: 34, height: 34)
                    .background(
                        AppDesign.selectedSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                Text(L10n.tr("accounts.add_progress.computer_authorization.info_title"))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppDesign.primaryText(for: colorScheme))
            }

            Text(L10n.tr("accounts.add_progress.computer_authorization.info_body"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppDesign.secondaryText(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer(minLength: 0)
                Button(L10n.tr("common.close")) { modal.close() }
                    .ailsaSSActionButtonStyle(prominent: true, density: .compact)
            }
        }
        .padding(24)
        .frame(width: 420)
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
        }
        .padding(.bottom, 12)
        .frame(width: pageContentWidth, alignment: .leading)
    }
}

private struct AccountsPageHeader: View {
    @Binding var selectedProvider: AccountProvider
    var body: some View {
        AccountsProviderSwitcher(selection: $selectedProvider)
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
