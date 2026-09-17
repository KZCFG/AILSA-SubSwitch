import SwiftUI

struct AccountsPageContentSection: View {
    let presentation: AccountsPageContentPresentation
    let cards: [AccountCardViewState]
    let availableViewportSize: CGSize
    let areCardsPresented: Bool
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void
    let onDeleteAccount: (String) -> Void

    var body: some View {
        switch presentation.state {
        case .loading:
            ProgressView(L10n.tr("accounts.loading.message"))
                .frame(maxWidth: .infinity, minHeight: 180)
        case .empty(let message):
            EmptyStateView(title: L10n.tr("accounts.empty.title"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .error(let message):
            EmptyStateView(title: L10n.tr("accounts.error.load_failed"), message: message)
                .padding(.horizontal, LayoutRules.pagePadding)
        case .content:
            VStack(alignment: .leading, spacing: LayoutRules.sectionSpacing) {
                if presentation.shouldShowPendingWorkspaceSection {
                    PendingWorkspaceAuthorizationSection(
                        cards: presentation.pendingWorkspaceCards,
                        errorMessage: presentation.pendingWorkspaceError,
                        areCardsPresented: areCardsPresented,
                        onAuthorizeWorkspace: onAuthorizeWorkspace,
                        onCancelAuthorizeWorkspace: onCancelAuthorizeWorkspace,
                        onDeletePendingWorkspace: onDeletePendingWorkspace
                    )
                }

                AccountsGridSection(
                    cards: self.cards,
                    isOverviewMode: presentation.isOverviewMode,
                    availableViewportSize: availableViewportSize,
                    areCardsPresented: areCardsPresented,
                    onSwitchAccount: onSwitchAccount,
                    onRefreshAccountUsage: onRefreshAccountUsage,
                    onReauthenticateAccount: onReauthenticateAccount,
                    onDeleteAccount: onDeleteAccount
                )
            }
        }
    }
}

private struct AccountsGridSection: View {
    let cards: [AccountCardViewState]
    let isOverviewMode: Bool
    let availableViewportSize: CGSize
    let areCardsPresented: Bool
    let onSwitchAccount: (String) -> Void
    let onRefreshAccountUsage: (String) -> Void
    let onReauthenticateAccount: (String) -> Void
    let onDeleteAccount: (String) -> Void
    @State private var pageIndex = 0

    private var gridContext: LayoutRules.AccountsGridContext {
        #if os(iOS)
        LayoutRules.accountsGridContext(
            isOverviewMode: isOverviewMode,
            viewportSize: availableViewportSize
        )
        #else
        LayoutRules.AccountsGridContext(
            platform: .macOS,
            isOverviewMode: isOverviewMode,
            viewportSize: availableViewportSize
        )
        #endif
    }

    private var columns: [GridItem] {
        LayoutRules.accountsGridColumns(context: gridContext)
    }

    private var cardFrameWidth: CGFloat? {
        LayoutRules.accountsCardFrameWidth(context: gridContext)
    }

    private var cardsPerPage: Int {
        max(1, columns.count)
    }

    private var pageCount: Int {
        max(1, Int(ceil(Double(cards.count) / Double(cardsPerPage))))
    }

    private var displayedCards: [AccountCardViewState] {
        let safePage = min(max(pageIndex, 0), pageCount - 1)
        let start = safePage * cardsPerPage
        let end = min(start + cardsPerPage, cards.count)
        guard start < end else { return [] }
        return Array(cards[start..<end])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: columns,
                alignment: .leading,
                spacing: LayoutRules.accountsRowSpacing
            ) {
                ForEach(Array(displayedCards.enumerated()), id: \.element.id) { index, card in
                    AccountCardGridItem(
                        card: card,
                        areCardsPresented: areCardsPresented,
                        frameWidth: cardFrameWidth,
                        index: index,
                        onSwitch: { onSwitchAccount(card.id) },
                        onRefresh: { onRefreshAccountUsage(card.id) },
                        onReauthenticate: { onReauthenticateAccount(card.id) },
                        onDelete: { onDeleteAccount(card.id) }
                    )
                }
            }

            if pageCount > 1 {
                AccountsPagePager(
                    currentPage: pageIndex,
                    pageCount: pageCount,
                    onPrevious: { pageIndex -= 1 },
                    onNext: { pageIndex += 1 }
                )
            }
        }
        .padding(.horizontal, LayoutRules.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: cards.map(\.id)) { _, _ in
            pageIndex = min(pageIndex, pageCount - 1)
        }
    }
}

private struct AccountsPagePager: View {
    let currentPage: Int
    let pageCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left")
            }
            .copoolActionButtonStyle(density: .compact)
            .disabled(currentPage == 0)
            .accessibilityLabel(Text(L10n.tr("common.previous_page")))

            Text(L10n.tr("common.page_format", String(currentPage + 1), String(pageCount)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 68)

            Button(action: onNext) {
                Image(systemName: "chevron.right")
            }
            .copoolActionButtonStyle(density: .compact)
            .disabled(currentPage + 1 >= pageCount)
            .accessibilityLabel(Text(L10n.tr("common.next_page")))

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct AccountCardGridItem: View {
    let card: AccountCardViewState
    let areCardsPresented: Bool
    let frameWidth: CGFloat?
    let index: Int
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onReauthenticate: () -> Void
    let onDelete: () -> Void

    var body: some View {
        AccountCardView(
            card: card,
            onSwitch: onSwitch,
            onRefresh: onRefresh,
            onReauthenticate: onReauthenticate,
            onDelete: onDelete
        )
        .frame(width: frameWidth)
        .copoolCardEntrance(index: index, isPresented: areCardsPresented)
        .modifier(AccountCardFrameModifier())
    }
}

private struct CardEntranceModifier: ViewModifier {
    let index: Int
    let isPresented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: reduceMotion || isPresented ? 0 : 22)
            .animation(
                reduceMotion ? nil : AccountsAnimationRules.cardEntrance(index: index),
                value: isPresented
            )
    }
}

private extension View {
    func copoolCardEntrance(index: Int, isPresented: Bool) -> some View {
        modifier(CardEntranceModifier(index: index, isPresented: isPresented))
    }
}

private struct AccountCardFrameModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct PendingWorkspaceAuthorizationSection: View {
    let cards: [PendingWorkspaceAuthorizationCardViewState]
    let errorMessage: String?
    let areCardsPresented: Bool
    let onAuthorizeWorkspace: (String) -> Void
    let onCancelAuthorizeWorkspace: () -> Void
    let onDeletePendingWorkspace: (String) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pageIndex = 0

    private let cardsPerPage = 1

    private var pageCount: Int {
        max(1, Int(ceil(Double(cards.count) / Double(cardsPerPage))))
    }

    private var displayedCards: [PendingWorkspaceAuthorizationCardViewState] {
        let safePage = min(max(pageIndex, 0), pageCount - 1)
        let start = safePage * cardsPerPage
        let end = min(start + cardsPerPage, cards.count)
        guard start < end else { return [] }
        return Array(cards[start..<end])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("accounts.pending.title"))
                    .font(.headline)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.primary)
                } else {
                    Text(L10n.tr("accounts.pending.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, LayoutRules.pagePadding)

            if let errorMessage, cards.isEmpty {
                PendingWorkspaceAuthorizationFailureCard(message: errorMessage)
                    .copoolCardEntrance(index: 0, isPresented: areCardsPresented)
                    .modifier(AccountCardFrameModifier())
                    .padding(.horizontal, LayoutRules.pagePadding)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: LayoutRules.accountsRowSpacing, alignment: .top)],
                    alignment: .leading,
                    spacing: LayoutRules.accountsRowSpacing
                ) {
                    ForEach(Array(displayedCards.enumerated()), id: \.element.id) { index, card in
                        PendingWorkspaceAuthorizationCard(
                            card: card,
                            onAuthorize: { onAuthorizeWorkspace(card.id) },
                            onCancelAuthorize: onCancelAuthorizeWorkspace,
                            onDelete: { onDeletePendingWorkspace(card.id) }
                        )
                        .copoolCardEntrance(index: index, isPresented: areCardsPresented)
                        .modifier(AccountCardFrameModifier())
                    }
                }
                .animation(
                    reduceMotion ? nil : AccountsAnimationRules.contentReorder,
                    value: cards.map(\.id)
                )
                .padding(.horizontal, LayoutRules.pagePadding)

                if pageCount > 1 {
                    AccountsPagePager(
                        currentPage: pageIndex,
                        pageCount: pageCount,
                        onPrevious: { pageIndex -= 1 },
                        onNext: { pageIndex += 1 }
                    )
                    .padding(.horizontal, LayoutRules.pagePadding)
                }
            }
        }
        .onChange(of: cards.map(\.id)) { _, _ in
            pageIndex = min(pageIndex, pageCount - 1)
        }
    }
}

private struct PendingWorkspaceAuthorizationCard: View {
    let card: PendingWorkspaceAuthorizationCardViewState
    let onAuthorize: () -> Void
    let onCancelAuthorize: () -> Void
    let onDelete: () -> Void

    private var isDeactivated: Bool {
        card.status == .deactivated
    }

    private var planLabel: String {
        AccountPlanLabel.normalized(from: card.planType)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AccountTagView(
                            text: planLabel,
                            backgroundColor: Color.primary.opacity(0.18),
                            foregroundColor: .primary
                        )
                        AccountTagView(
                            text: card.workspaceName,
                            backgroundColor: Color.primary.opacity(0.18),
                            foregroundColor: .primary,
                            allowsCompression: true
                        )
                    }

                    if let email = card.email, !email.isEmpty {
                        Text(email)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                AccountTagView(
                    text: isDeactivated ? L10n.tr("accounts.card.status.deactivated") : L10n.tr("accounts.pending.tag"),
                    backgroundColor: Color.primary.opacity(0.12),
                    foregroundColor: .primary
                )
            }

            Text(isDeactivated ? L10n.tr("error.accounts.workspace_deactivated") : L10n.tr("accounts.pending.hint"))
                .font(.caption)
                .foregroundStyle(isDeactivated ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: 10) {
                if !isDeactivated {
                    Button(action: card.authorizing ? onCancelAuthorize : onAuthorize) {
                        Label(
                            card.authorizing ? L10n.tr("common.cancel") : L10n.tr("accounts.pending.action.authorize"),
                            systemImage: card.authorizing ? "xmark.circle" : "checkmark.shield"
                        )
                        .lineLimit(1)
                    }
                    .copoolActionButtonStyle(
                        prominent: !card.authorizing,
                        density: .compact,
                        iOSStyle: .liquidGlass
                    )
                }

                Spacer(minLength: 0)

                AccountDeleteButton(action: onDelete, isDisabled: card.authorizing)
                    .accessibilityLabel(L10n.tr("accounts.pending.action.delete"))
            }
        }
        .padding(12)
        .frostedRoundedSurface(
            cornerRadius: 12,
            prominent: true
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct PendingWorkspaceAuthorizationFailureCard: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                AccountTagView(
                    text: L10n.tr("accounts.pending.error.tag"),
                    backgroundColor: Color.primary.opacity(0.18),
                    foregroundColor: .primary
                )
                Spacer(minLength: 0)
            }

            Text(L10n.tr("accounts.pending.error.title"))
                .font(.headline)
                .foregroundStyle(.primary)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.tr("accounts.pending.error.hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frostedRoundedSurface(cornerRadius: 12, prominent: true)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
        }
    }
}
