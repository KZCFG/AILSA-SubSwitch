import SwiftUI

struct AccountCardView: View {
    let card: AccountCardViewState
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onReauthenticate: () -> Void
    let onDelete: () -> Void

    @State private var isHoveringCollapsedSwitch = false
    @State private var isCollapsedSwitchOverlayPresented = false
    @State private var isDeleteConfirmationPresented = false

    @EnvironmentObject private var modal: ASModalHost
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        card: AccountCardViewState,
        onSwitch: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onReauthenticate: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.card = card
        self.onSwitch = onSwitch
        self.onRefresh = onRefresh
        self.onReauthenticate = onReauthenticate
        self.onDelete = onDelete
    }

    private var palette: AccountCardPalette {
        AccountCardPalette(accent: card.presentation.accent, isCurrent: card.account.isCurrent)
    }

    private var interactionPresentation: AccountCardInteractionPresentation {
        AccountCardInteractionPresentation(
            isCollapsed: card.isCollapsed,
            isCurrent: card.account.isCurrent,
            switching: card.switching,
            isHoveringCollapsedSwitch: isHoveringCollapsedSwitch,
            isCollapsedSwitchOverlayPresented: isCollapsedSwitchOverlayPresented,
            platform: accountCardInteractionPlatform
        )
    }

    private var presentation: AccountCardPresentation {
        card.presentation
    }

    private var accountCardInteractionPlatform: AccountCardInteractionPlatform {
        .macOS
    }

    var body: some View {
        cardBody
            .onChange(of: card.isCollapsed) { _, collapsed in
                if !collapsed {
                    dismissCollapsedSwitchOverlay()
                }
            }
            .onChange(of: card.account.isCurrent) { _, isCurrent in
                if isCurrent {
                    dismissCollapsedSwitchOverlay()
                }
            }
            .onChange(of: isDeleteConfirmationPresented) { _, shown in
                guard shown else { return }
                modal.present(onClose: { isDeleteConfirmationPresented = false }) {
                    deleteConfirmationContent
                }
            }
    }

    private var deleteConfirmationContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppDesign.primaryText(for: colorScheme))
                    .frame(width: 36, height: 36)
                    .background(
                        AppDesign.selectedSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.tr("common.remove"))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppDesign.primaryText(for: colorScheme))
                    Text(presentation.displayAccountName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppDesign.secondaryText(for: colorScheme))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()
                .overlay(AppDesign.border(for: colorScheme))

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                Button(L10n.tr("common.cancel")) {
                    modal.close()
                }
                .ailsaSSActionButtonStyle(density: .compact)

                Button(role: .destructive) {
                    modal.close()
                    onDelete()
                } label: {
                    Label(L10n.tr("common.remove"), systemImage: "trash")
                }
                .ailsaSSActionButtonStyle(prominent: true, density: .compact)
            }
        }
        .padding(24)
        .frame(width: 390)
    }

    @ViewBuilder
    private var cardBody: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.itemSpacing) {
            if card.isCollapsed {
                VStack(alignment: .leading, spacing: AppDesign.Metrics.itemSpacing) {
                    AccountCompactHeaderContent(
                        planLabel: presentation.planLabel,
                        workspaceLabel: presentation.teamNameTag,
                        statusLabel: presentation.statusLabel,
                        accountName: presentation.displayAccountName,
                        accentColor: palette.toneColor,
                        titleFont: .system(size: 12, weight: .semibold),
                        titleColor: card.account.isCurrent
                            ? palette.toneColor
                            : AppDesign.primaryText(for: colorScheme),
                        spacing: AppDesign.Metrics.itemSpacing,
                        trailingReservation: 24
                    )
                    .overlay(alignment: .topTrailing) {
                        Button(action: onSwitch) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .disabled(card.account.isCurrent || card.switching)
                            .accessibilityLabel(card.account.isCurrent ? L10n.tr("accounts.card.current") : L10n.tr("accounts.card.switch_to_this"))
                    }
                    AccountCardCompactUsageSection(presentation: presentation)
                }
            } else {
                VStack(alignment: .leading, spacing: AppDesign.Metrics.itemSpacing) {
                    AccountCardHeaderSection(
                        presentation: presentation,
                        isCollapsed: card.isCollapsed,
                        isCurrent: card.account.isCurrent,
                        palette: palette,
                        onDelete: {
                            isDeleteConfirmationPresented = true
                        }
                    )

                    Text(presentation.displayAccountName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(
                            card.account.isCurrent
                                ? palette.toneColor
                                : AppDesign.primaryText(for: colorScheme)
                        )
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .minimumScaleFactor(0.85)
                        .textSelection(.enabled)

                    AccountCardExpandedUsageSection(presentation: presentation)
                    if !card.isUsageRefreshActive, let error = card.account.usageError, !error.isEmpty {
                        AccountUsageErrorOverlay(text: error)
                    }
                }
            }
        }
        .padding(card.isCollapsed ? 10 : 16)
        // Expanded cards reserve room for the lower action cluster so four
        // AntiGravity quota buckets retain their reset/source lines in full.
        .padding(.bottom, card.isCollapsed ? 0 : 42)
        .accountCardSurface(cornerRadius: LayoutRules.cardRadius, tint: palette.surfaceTint)
        .overlay(
            RoundedRectangle(cornerRadius: LayoutRules.cardRadius, style: .continuous)
                .strokeBorder(palette.selectionBorderColor ?? .clear, lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            AccountCardBottomOverlay(
                isCollapsed: card.isCollapsed,
                isCurrent: card.account.isCurrent,
                switching: card.switching,
                refreshing: card.refreshing,
                showsRefreshButton: card.showsRefreshButton,
                showsReauthenticateButton: card.showsReauthenticateButton,
                isRefreshEnabled: card.isRefreshEnabled,
                usageError: nil,
                palette: palette,
                onSwitch: onSwitch,
                onRefresh: onRefresh,
                onReauthenticate: onReauthenticate
            )
        }
        .animation(reduceMotion ? nil : AccountCardMorphRules.animation, value: card.isCollapsed)
        .animation(reduceMotion ? nil : AccountCardMorphRules.animation, value: card.account.isCurrent)
    }

    private func dismissCollapsedSwitchOverlay() {
        guard isCollapsedSwitchOverlayPresented else { return }
        if reduceMotion {
            isCollapsedSwitchOverlayPresented = false
        } else {
            withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                isCollapsedSwitchOverlayPresented = false
            }
        }
    }
}

private struct CollapsedSwitchHoverModifier: ViewModifier {
    let enabled: Bool
    @Binding var isHoveringCollapsedSwitch: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if enabled {
            content.onHover { hovering in
                guard isHoveringCollapsedSwitch != hovering else { return }
                if reduceMotion {
                    isHoveringCollapsedSwitch = hovering
                } else {
                    withAnimation(AccountsAnimationRules.cardHoverOverlay) {
                        isHoveringCollapsedSwitch = hovering
                    }
                }
            }
        } else {
            content
                .onAppear {
                    isHoveringCollapsedSwitch = false
                }
        }
    }
}

private extension View {
    func ailsaSSCollapsedSwitchHover(
        enabled: Bool,
        isHoveringCollapsedSwitch: Binding<Bool>
    ) -> some View {
        modifier(
            CollapsedSwitchHoverModifier(
                enabled: enabled,
                isHoveringCollapsedSwitch: isHoveringCollapsedSwitch
            )
        )
    }
}
