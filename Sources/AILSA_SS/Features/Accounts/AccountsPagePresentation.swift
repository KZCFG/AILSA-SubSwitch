import Foundation

struct AccountsPageContentPresentation: Equatable {
    let state: ViewState<[String]>
    let pendingWorkspaceCards: [PendingWorkspaceAuthorizationCardViewState]
    let pendingWorkspaceError: String?
    let isOverviewMode: Bool

    var shouldShowPendingWorkspaceSection: Bool {
        !isOverviewMode && (!pendingWorkspaceCards.isEmpty || pendingWorkspaceError != nil)
    }
}

struct AccountsActionBarPresentation: Equatable {
    let descriptors: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let collapse: AccountsCollapsePresentation
    /// False while the panel is too short for expanded cards; the chevron
    /// stays visible (so the layout does not jump) but cannot expand.
    var isCollapseToggleEnabled = true
}

struct AccountCardViewState: Equatable, Identifiable {
    let account: AccountSummary
    let presentation: AccountCardPresentation
    let isCollapsed: Bool
    let switching: Bool
    let refreshing: Bool
    let showsRefreshButton: Bool
    let showsReauthenticateButton: Bool
    let isRefreshEnabled: Bool
    let isUsageRefreshActive: Bool
    let usageProgressDisplayMode: UsageProgressDisplayMode

    var id: String {
        account.id
    }

    static func == (lhs: AccountCardViewState, rhs: AccountCardViewState) -> Bool {
        lhs.isCollapsed == rhs.isCollapsed
            && lhs.switching == rhs.switching
            && lhs.refreshing == rhs.refreshing
            && lhs.showsRefreshButton == rhs.showsRefreshButton
            && lhs.showsReauthenticateButton == rhs.showsReauthenticateButton
            && lhs.isRefreshEnabled == rhs.isRefreshEnabled
            && lhs.isUsageRefreshActive == rhs.isUsageRefreshActive
            && lhs.usageProgressDisplayMode == rhs.usageProgressDisplayMode
            && lhs.account.id == rhs.account.id
            && lhs.account.label == rhs.account.label
            && lhs.account.email == rhs.account.email
            && lhs.account.accountID == rhs.account.accountID
            && lhs.account.planType == rhs.account.planType
            && lhs.account.teamName == rhs.account.teamName
            && lhs.account.teamAlias == rhs.account.teamAlias
            && lhs.account.usage == rhs.account.usage
            && lhs.account.usageError == rhs.account.usageError
            && lhs.account.workspaceStatus == rhs.account.workspaceStatus
            && lhs.account.displayStatus == rhs.account.displayStatus
            && lhs.account.isCurrent == rhs.account.isCurrent
            && lhs.account.isPendingNativeSwitch == rhs.account.isPendingNativeSwitch
            && lhs.account.provider == rhs.account.provider
    }
}

struct PendingWorkspaceAuthorizationCardViewState: Equatable, Identifiable {
    let id: String
    let workspaceID: String
    let workspaceName: String
    let email: String?
    let planType: String?
    let status: WorkspaceAuthorizationCandidateStatus
    let authorizing: Bool
}

/// Decides whether a quota-refresh failure means credentials are actually
/// invalid. A provider permission response or a transient transport failure is
/// actionable through Refresh, not evidence that the user must sign in again.
enum AccountUsageRecoveryRules {
    static func requiresReauthentication(for account: AccountSummary) -> Bool {
        guard let error = account.usageError?.trimmingCharacters(in: .whitespacesAndNewlines),
              !error.isEmpty
        else {
            return false
        }

        switch account.provider {
        case .cursor:
            return error.contains("401")
        case .codex:
            return error == L10n.tr("error.accounts.sign_in_expired")
        case .antigravity:
            let normalized = error.lowercased()
            // The native session itself missing/expired or an explicit 401 is
            // an authentication recovery case. Do not classify 403, quota
            // availability, network, or parse errors as sign-out.
            return normalized.contains("401")
                || normalized.contains("unauthorized")
                || normalized.contains("sign_in_expired")
                || normalized.contains("missing_refresh_token")
                || normalized.contains("native_session_unavailable")
        }
    }
}

enum PendingWorkspaceCardRules {
    static func sortedForDisplay(
        _ cards: [PendingWorkspaceAuthorizationCardViewState]
    ) -> [PendingWorkspaceAuthorizationCardViewState] {
        cards.sorted {
            sortsBefore(
                lhsStatus: $0.status,
                lhsName: $0.workspaceName,
                rhsStatus: $1.status,
                rhsName: $1.workspaceName
            )
        }
    }

    static func sortedCandidates(
        _ candidates: [WorkspaceAuthorizationCandidate]
    ) -> [WorkspaceAuthorizationCandidate] {
        candidates.sorted {
            sortsBefore(
                lhsStatus: $0.status,
                lhsName: $0.workspaceName,
                rhsStatus: $1.status,
                rhsName: $1.workspaceName
            )
        }
    }

    static func sortsBefore(
        lhsStatus: WorkspaceAuthorizationCandidateStatus,
        lhsName: String,
        rhsStatus: WorkspaceAuthorizationCandidateStatus,
        rhsName: String
    ) -> Bool {
        if lhsStatus != rhsStatus {
            return lhsStatus == .deactivated
        }
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
    }
}

extension AccountsPageModel {
    func makeAccountCardViewState(
        for account: AccountSummary,
        locale: Locale = .autoupdatingCurrent,
        forceCollapsed: Bool = false
    ) -> AccountCardViewState {
        let isCollapsed = forceCollapsed || isAccountCollapsed(account.id)
        return AccountCardViewState(
            account: account,
            presentation: AccountCardPresentation(
                account: account,
                isCollapsed: isCollapsed,
                locale: locale,
                usageProgressDisplayMode: usageProgressDisplayMode,
                quotaVisibility: quotaVisibilityPreferences
            ),
            isCollapsed: isCollapsed,
            switching: switchingAccountID == account.id,
            refreshing: isAccountRefreshing(account.id),
            showsRefreshButton: runtimePlatform == .macOS,
            showsReauthenticateButton: shouldShowReauthenticateButton(for: account),
            isRefreshEnabled: canRefreshAccount(account.id),
            isUsageRefreshActive: isUsageRefreshActive(forAccountID: account.id),
            usageProgressDisplayMode: usageProgressDisplayMode
        )
    }

    func makeAccountCardViewState(
        forAccountID accountID: String,
        locale: Locale = .autoupdatingCurrent
    ) -> AccountCardViewState? {
        guard case .content(let accounts) = state else { return nil }
        guard let account = accounts.first(where: { $0.id == accountID && $0.isVisibleInMainList }) else {
            return nil
        }
        return makeAccountCardViewState(for: account, locale: locale)
    }

    /// `forceCollapsed` is the small-panel layout override; it never touches
    /// the user's persisted per-account collapse choice.
    func makeAccountCardViewStates(locale: Locale = .autoupdatingCurrent, forceCollapsed: Bool = false) -> [AccountCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts
            .filter(\.isVisibleInMainList)
            .filter { $0.provider == selectedProvider }
            .map { makeAccountCardViewState(for: $0, locale: locale, forceCollapsed: forceCollapsed) }
    }

    func makeContentPresentation(forceOverview: Bool = false) -> AccountsPageContentPresentation {
        let contentState = state.mapContent { accounts in
            accounts
                .filter(\.isVisibleInMainList)
                .filter { $0.provider == selectedProvider }
                .map(\.id)
        }
        let accountPendingCards = currentPendingCards()
        let pendingAuthorizationCards = pendingWorkspaceAuthorizations.map { candidate in
            PendingWorkspaceAuthorizationCardViewState(
                id: candidate.id,
                workspaceID: candidate.workspaceID,
                workspaceName: candidate.workspaceName,
                email: candidate.email,
                planType: candidate.planType,
                status: candidate.status,
                authorizing: authorizingWorkspaceID == candidate.id
            )
        }
        let pendingCards = PendingWorkspaceCardRules.sortedForDisplay(
            accountPendingCards + pendingAuthorizationCards
        )
        let pendingError = pendingCards.isEmpty ? nil : pendingWorkspaceAuthorizationError
        let emptyMessage = selectedProvider == .antigravity
            ? L10n.tr("accounts.empty.message.no_antigravity_accounts")
            : L10n.tr("accounts.empty.message.no_accounts")
        let filteredState: ViewState<[String]>
        switch contentState {
        case .content(let ids) where ids.isEmpty && (selectedProvider != .codex || pendingCards.isEmpty):
            filteredState = .empty(message: emptyMessage)
        case .empty:
            filteredState = .empty(message: emptyMessage)
        default:
            filteredState = contentState
        }
        return AccountsPageContentPresentation(
            state: filteredState,
            pendingWorkspaceCards: selectedProvider == .codex ? pendingCards : [],
            pendingWorkspaceError: selectedProvider == .codex ? pendingError : nil,
            isOverviewMode: forceOverview || areAllAccountsCollapsed
        )
    }

    func makeMacActionBarPresentation(forceOverview: Bool = false) -> AccountsActionBarPresentation {
        AccountsActionBarPresentation(
            descriptors: desktopActionButtons,
            collapse: forceOverview
                ? AccountsActionPresentation.collapseControl(areAllAccountsCollapsed: true)
                : collapsePresentation,
            isCollapseToggleEnabled: !forceOverview
        )
    }

    private func currentPendingCards() -> [PendingWorkspaceAuthorizationCardViewState] {
        guard case .content(let accounts) = state else { return [] }
        return accounts.compactMap { account in
            guard account.provider == .codex else { return nil }
            guard account.isPendingDisplay || account.isWorkspaceDeactivated else { return nil }
            return PendingWorkspaceAuthorizationCardViewState(
                id: account.id,
                workspaceID: account.accountID,
                workspaceName: account.displayTeamName ?? account.teamName ?? account.label,
                email: account.email,
                planType: account.planType ?? account.usage?.planType,
                status: account.isWorkspaceDeactivated ? .deactivated : .pending,
                authorizing: false
            )
        }
    }

    private func shouldShowReauthenticateButton(for account: AccountSummary) -> Bool {
        AccountUsageRecoveryRules.requiresReauthentication(for: account)
    }
}

private extension ViewState {
    func mapContent<NewValue>(_ transform: (Value) -> NewValue) -> ViewState<NewValue> {
        switch self {
        case .loading:
            return .loading
        case .empty(let message):
            return .empty(message: message)
        case .content(let value):
            return .content(transform(value))
        case .error(let message):
            return .error(message: message)
        }
    }
}
