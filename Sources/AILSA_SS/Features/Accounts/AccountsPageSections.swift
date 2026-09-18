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
            ScrollView(.vertical) {
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
            }.padding(.vertical, 6)
            }.scrollIndicators(.automatic)
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
    private var provider: AccountProvider { cards.first?.account.provider ?? .codex }
    private var currentID: String? { cards.first(where: { $0.account.isCurrent })?.id }
    private var columnCount: Int {
        AccountCollectionLayout.columns(provider: provider, compact: isOverviewMode,
            availableWidth: availableViewportSize.width - LayoutRules.pagePadding * 2)
    }

    var body: some View {
        ReorderableAccountGrid(items: cards, provider: provider, columns: columnCount, pinnedID: currentID) { card in
            AccountCardGridItem(
                card: card, areCardsPresented: areCardsPresented, frameWidth: nil, index: 0,
                onSwitch: { onSwitchAccount(card.id) },
                onRefresh: { onRefreshAccountUsage(card.id) },
                onReauthenticate: { onReauthenticateAccount(card.id) },
                onDelete: { onDeleteAccount(card.id) }
            )
        }
        .padding(.horizontal, LayoutRules.pagePadding)
    }
}

/// Local, long-press sorting leaves the buttons and ordinary trackpad scrolling intact.
/// IDs (never credentials or the switching policy) are persisted separately per provider.
struct ReorderableAccountGrid<Item: Identifiable, Card: View>: View where Item.ID == String {
    let items: [Item]
    let provider: AccountProvider
    let columns: Int
    /// The native-current account is always rendered first and is excluded
    /// from the persisted/manual order. A current-account change therefore
    /// changes the lead card without rewriting the user's arrangement.
    var pinnedID: String?
    @ViewBuilder let card: (Item) -> Card
    @AppStorage(AccountOrderPreferences.defaultsKey) private var savedOrder = "{}"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var order: [String] = []
    @State private var frames: [String: CGRect] = [:]
    // Target geometry must stay stable while neighboring cards animate. If
    // the live frames are used here, the target moves under the pointer and
    // the same two cards can swap repeatedly.
    @State private var dragFrames: [String: CGRect] = [:]
    @State private var draggingID: String?
    @State private var liftedFrame: CGRect = .zero
    @State private var translation: CGSize = .zero
    @State private var lastTarget: String?
    @GestureState private var gestureActive = false
    private var space: String { "account-sort-" + provider.rawValue }
    private var availableIDs: [String] { items.map(\.id) }
    private var movableIDs: [String] { availableIDs.filter { $0 != pinnedID } }
    private var orderedIDs: [String] {
        let movable = AccountOrderPreferences.reconcile(order, available: movableIDs)
        guard let pinnedID, availableIDs.contains(pinnedID) else { return movable }
        return [pinnedID] + movable
    }
    private var orderedItems: [Item] {
        let lookup = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return orderedIDs.compactMap { lookup[$0] }
    }
    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.86) }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: columns),
                  alignment: .leading, spacing: 12) {
            ForEach(orderedItems) { item in
                card(item)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: AccountCardFrames.self,
                            value: [item.id: proxy.frame(in: .named(space))])
                    })
                    .contentShape(RoundedRectangle(cornerRadius: LayoutRules.cardRadius))
                    .scaleEffect(draggingID == item.id && !reduceMotion ? 1.025 : 1)
                    .shadow(color: .black.opacity(draggingID == item.id ? 0.18 : 0), radius: 12, y: 5)
                    .offset(offset(for: item.id))
                    .zIndex(draggingID == item.id ? 1 : 0)
                    // Keep the original card's gesture in charge when it
                    // overlaps a neighbor during a drag. Otherwise SwiftUI
                    // can start the neighbor's long-press sequence and the
                    // lifted card appears to exit or shake.
                    .allowsHitTesting(draggingID == nil || draggingID == item.id)
                    .simultaneousGesture(reorderGesture(item.id))
                    .accessibilityHint(L10n.tr("accounts.reorder.hint"))
                    .accessibilityAction(named: Text(L10n.tr("accounts.reorder.previous"))) { step(item.id, by: -1) }
                    .accessibilityAction(named: Text(L10n.tr("accounts.reorder.next"))) { step(item.id, by: 1) }
            }
        }
        .coordinateSpace(name: space)
        .onPreferenceChange(AccountCardFrames.self) { frames = $0 }
        .onAppear { loadOrder() }
        .onChange(of: provider) { _, _ in
            draggingID = nil; translation = .zero; lastTarget = nil; frames = [:]; dragFrames = [:]
            loadOrder()
        }
        .onChange(of: items.map(\.id)) { _, _ in loadOrder() }
        .onChange(of: pinnedID) { _, _ in loadOrder() }
        .onChange(of: savedOrder) { _, _ in if draggingID == nil { loadOrder() } }
        .onChange(of: gestureActive) { _, active in if !active { finishDrag() } }
        .onDisappear { finishDrag() }
    }
    private func loadOrder() {
        order = AccountOrderPreferences.decode(savedOrder).ordered(movableIDs, provider: provider)
    }
    private func persist(_ committedOrder: [String]? = nil) {
        var preferences = AccountOrderPreferences.decode(savedOrder)
        let orderToSave = committedOrder ?? orderedIDs
        preferences.orders[provider.rawValue] = orderToSave.filter { $0 != pinnedID }
        savedOrder = preferences.encoded
    }
    private func offset(for id: String) -> CGSize {
        // Keep the grid in its original slots for the whole gesture. Reflowing
        // a LazyVGrid while the pointer is over a neighbor makes the lifted
        // card inherit a new origin and appear to shake or jump. The order is
        // committed once, on drop, so this offset is calculated from one
        // immutable frame map.
        guard draggingID == id, let frame = dragFrames[id] ?? frames[id] else { return .zero }
        return CGSize(width: liftedFrame.minX - frame.minX + translation.width,
                      height: liftedFrame.minY - frame.minY + translation.height)
    }
    private func reorderGesture(_ id: String) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35, maximumDistance: 8)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(space)))
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                guard pinnedID != id else { return }
                switch value {
                case .second(true, let drag):
                    if draggingID == nil {
                        draggingID = id
                        dragFrames = frames
                        liftedFrame = frames[id] ?? .zero
                        order = orderedIDs
                    }
                    guard let drag else { return }
                    translation = drag.translation
                    // Use the lifted card's center against the frozen frame map.
                    // The live layout moves while sorting; using its current frames
                    // (or clearing the target in a gap) makes adjacent cards swap
                    // back and forth when the pointer hovers near a boundary.
                    let liftedCenter = CGPoint(
                        x: liftedFrame.midX + translation.width,
                        y: liftedFrame.midY + translation.height
                    )
                    let target = orderedIDs.first { candidate in
                        candidate != id
                            && candidate != pinnedID
                            && dragFrames[candidate]?.insetBy(dx: 8, dy: 8).contains(liftedCenter) == true
                    }
                    // Keep the last target while crossing a gap. This gives the
                    // pointer one stable decision instead of repeatedly undoing
                    // and reapplying the same move.
                    guard let target, target != lastTarget else { return }
                    lastTarget = target
                    // Do not mutate the grid during the gesture. The target is
                    // remembered and applied once on drop, which keeps every
                    // neighboring card's frame stable under the pointer.
                default: break
                }
            }
            .onEnded { _ in finishDrag() }
    }
    private func finishDrag() {
        guard let draggingID, pinnedID != draggingID else { return }
        let committedOrder = lastTarget.map { AccountOrderPreferences.moving(draggingID, to: $0, in: orderedIDs) }
        if let committedOrder {
            withAnimation(motion) {
                order = committedOrder
            }
        }
        persist(committedOrder)
        withAnimation(motion) {
            self.draggingID = nil
            translation = .zero
            lastTarget = nil
            dragFrames = [:]
        }
    }
    private func step(_ id: String, by delta: Int) {
        guard id != pinnedID else { return }
        guard let index = orderedIDs.firstIndex(of: id), orderedIDs.indices.contains(index + delta) else { return }
        let committedOrder = AccountOrderPreferences.moving(id, to: orderedIDs[index + delta], in: orderedIDs)
        withAnimation(motion) { order = committedOrder }
        persist(committedOrder)
    }
}
private struct AccountCardFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
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
        .ailsaSSCardEntrance(index: index, isPresented: areCardsPresented)
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
    func ailsaSSCardEntrance(index: Int, isPresented: Bool) -> some View {
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
                    .ailsaSSCardEntrance(index: 0, isPresented: areCardsPresented)
                    .modifier(AccountCardFrameModifier())
                    .padding(.horizontal, LayoutRules.pagePadding)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: LayoutRules.accountsRowSpacing, alignment: .top)],
                    alignment: .leading,
                    spacing: LayoutRules.accountsRowSpacing
                ) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        PendingWorkspaceAuthorizationCard(
                            card: card,
                            onAuthorize: { onAuthorizeWorkspace(card.id) },
                            onCancelAuthorize: onCancelAuthorizeWorkspace,
                            onDelete: { onDeletePendingWorkspace(card.id) }
                        )
                        .ailsaSSCardEntrance(index: index, isPresented: areCardsPresented)
                        .modifier(AccountCardFrameModifier())
                    }
                }
                .animation(
                    reduceMotion ? nil : AccountsAnimationRules.contentReorder,
                    value: cards.map(\.id)
                )
                .padding(.horizontal, LayoutRules.pagePadding)


            }
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
                    .ailsaSSActionButtonStyle(
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
