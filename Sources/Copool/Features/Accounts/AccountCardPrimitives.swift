import SwiftUI

private enum AccountCardOverlayLayout {
    /// Space held back for the visible trailing action cluster. This keeps
    /// source/timestamp text readable without making the metadata column so
    /// narrow that it turns into a four-line stack.
    static let actionReservationWidth: CGFloat = 88
    static let compactActionControlHeight = LayoutRules.compactActionControlHeight
}

enum AccountCardMorphRules {
    static let response = 0.20
    static let dampingFraction = 1.0
    static let titleExpansionProgress = 0.68
    static let animation = AppDesign.contentTransition
    static let contentAnimation = AppDesign.interaction

    static var titleExpansionDelay: Duration {
        .seconds(response * titleExpansionProgress)
    }
}

enum AccountCardSwitchButtonLabelStyle {
    case iconOnly
    case expanded
}

struct AccountCardPalette {
    let toneColor: Color
    let surfaceTint: Color?
    let selectionBorderAccent: AccountCardAccent?

    init(accent: AccountCardAccent, isCurrent: Bool) {
        toneColor = isCurrent ? Self.currentColor : Self.color(for: accent)
        selectionBorderAccent = isCurrent ? accent : nil
        surfaceTint = selectionBorderAccent.map { _ in Self.currentColor.opacity(0.10) }
    }

    var selectionBorderColor: Color? {
        selectionBorderAccent.map { _ in Self.currentColor.opacity(0.48) }
    }

    private static let currentColor = Color.primary

    private static func color(for accent: AccountCardAccent) -> Color {
        _ = accent
        return .primary
    }
}

private struct AccountCardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        content.cardSurface(cornerRadius: cornerRadius, tint: tint)
    }
}

extension View {
    func accountCardSurface(
        cornerRadius: CGFloat = 12,
        tint: Color? = nil
    ) -> some View {
        modifier(AccountCardSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }
}

struct AccountCardHeaderSection: View {
    let presentation: AccountCardPresentation
    let isCollapsed: Bool
    let isCurrent: Bool
    let palette: AccountCardPalette
    let onDelete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    AccountTagView(
                        text: presentation.planLabel,
                        backgroundColor: palette.toneColor.opacity(0.18),
                        foregroundColor: palette.toneColor
                    )
                    if isCurrent {
                        AccountTagView(
                            text: L10n.tr("accounts.card.current"),
                            backgroundColor: palette.toneColor.opacity(0.16),
                            foregroundColor: palette.toneColor
                        )
                    }
                    if let teamNameTag = presentation.teamNameTag {
                        AccountTagView(
                            text: teamNameTag,
                            backgroundColor: palette.toneColor.opacity(0.18),
                            foregroundColor: palette.toneColor,
                            allowsCompression: true
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let statusLabel = presentation.statusLabel {
                        AccountTagView(
                            text: statusLabel,
                            backgroundColor: palette.toneColor.opacity(0.12),
                            foregroundColor: palette.toneColor
                        )
                    }
                    Spacer(minLength: 0)
                }
            }

            if !isCollapsed {
                AccountDeleteButton(action: onDelete)
            }
        }
    }
}

struct AccountDeleteButton: View {
    let action: () -> Void
    var isDisabled: Bool = false

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "trash")
        }
        .copoolActionButtonStyle(
            prominent: false,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .disabled(isDisabled)
        .accessibilityLabel(Text(L10n.tr("common.remove")))
    }
}

struct AccountCardExpandedUsageSection: View {
    let presentation: AccountCardPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(presentation.quotaWindows) { window in
                AccountWindowSection(
                    presentation: window,
                    fillStyle: presentation.usageProgressFillStyle
                )
            }

            ForEach(presentation.quotaFamilies) { family in
                AccountQuotaFamilySection(
                    family: family,
                    fillStyle: presentation.usageProgressFillStyle
                )
            }

            if let quotaStatusText = presentation.quotaStatusText {
                Text(quotaStatusText)
                    .font(.caption2)
                    .foregroundStyle(presentation.quotaStatusIsStale ? Color.orange : .secondary)
                    .padding(.trailing, AccountCardOverlayLayout.actionReservationWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if presentation.isQuotaDisplayHidden {
                AccountQuotaDisplaySettingsLink()
            }

            if let text = presentation.resetCreditsText {
                Label(text, systemImage: "ticket")
                    .font(.caption2).fixedSize(horizontal: false, vertical: true)
            }
            if let creditsText = presentation.creditsText {
                AccountCreditsBalanceLabel(
                    displayText: creditsText,
                    rawText: presentation.creditsRawText
                )
                .padding(.trailing, AccountCardOverlayLayout.actionReservationWidth)
            }

            if let provenanceText = presentation.provenanceText {
                Text(provenanceText)
                    .font(.caption2)
                    .foregroundStyle(presentation.quotaStatusIsStale ? Color.orange : .secondary)
                    .padding(.trailing, AccountCardOverlayLayout.actionReservationWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

}

private struct AccountCreditsBalanceLabel: View {
    let displayText: String
    let rawText: String?

    private var visibleLabel: String {
        L10n.tr("accounts.card.credits_format", displayText)
    }

    private var fullAccessibilityLabel: String {
        L10n.tr("accounts.card.credits_format", rawText ?? displayText)
    }

    private var baseText: some View {
        Text(visibleLabel)
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        if let rawText {
            baseText
                .accessibilityLabel(Text(fullAccessibilityLabel))
                .accessibilityAction(named: Text(L10n.tr("common.copy"))) {
                    PlatformClipboard.copy(rawText)
                }
                .contextMenu {
                    Button {
                        PlatformClipboard.copy(rawText)
                    } label: {
                        Label(L10n.tr("common.copy"), systemImage: "doc.on.doc")
                    }
                }
                .help(fullAccessibilityLabel)
        } else {
            baseText
                .accessibilityLabel(Text(fullAccessibilityLabel))
        }
    }
}

struct AccountCardCompactUsageSection: View {
    let presentation: AccountCardPresentation

    var body: some View {
        if presentation.compactUsage.items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.quotaStatusText ?? L10n.tr("accounts.quota.unavailable"))
                    .font(.caption2)
                    .foregroundStyle(presentation.quotaStatusIsStale ? Color.orange : .secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if presentation.isQuotaDisplayHidden {
                    AccountQuotaDisplaySettingsLink(compact: true)
                }
            }
        } else {
            AccountCompactUsageRow(
                rings: presentation.compactUsage.items.map { item in
                    AccountCompactRingDescriptor(
                        id: item.id,
                        valueText: compactPercentText(item.displayPercent),
                        subtitleText: item.subtitle,
                        progress: compactProgress(item.displayPercent),
                        fillStyle: presentation.usageProgressFillStyle
                    )
                }
            )
        }
    }

    private func compactProgress(_ usedPercent: Double?) -> Double {
        guard let usedPercent else { return 0 }
        return max(0, min(1, usedPercent / 100))
    }

    private func compactPercentText(_ usedPercent: Double?) -> String {
        guard let usedPercent else { return "--" }
        return "\(Int(usedPercent.rounded()))%"
    }
}

private struct AccountQuotaDisplaySettingsLink: View {
    var compact = false

    var body: some View {
        Button {
            NotificationCenter.default.post(name: .copoolOpenQuotaDisplaySettings, object: nil)
        } label: {
            Label(
                L10n.tr("accounts.quota.open_display_settings"),
                systemImage: "slider.horizontal.3"
            )
            .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint(Text(L10n.tr("accounts.quota.open_display_settings_hint")))
    }
}

private struct AccountQuotaFamilySection: View {
    let family: AccountQuotaFamilyPresentation
    let fillStyle: UsageProgressFillStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(family.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            ForEach(family.windows) { window in
                AccountWindowSection(presentation: window, fillStyle: fillStyle)
            }
        }
    }
}

struct AccountCardBottomOverlay: View {
    let isCollapsed: Bool
    let isCurrent: Bool
    let switching: Bool
    let refreshing: Bool
    let showsRefreshButton: Bool
    let showsReauthenticateButton: Bool
    let isRefreshEnabled: Bool
    let usageError: String?
    let palette: AccountCardPalette
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onReauthenticate: () -> Void

    var body: some View {
        if !isCollapsed {
            HStack(alignment: .bottom, spacing: 10) {
                if let usageError, !usageError.isEmpty {
                    AccountUsageErrorOverlay(text: usageError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Spacer(minLength: 0)
                }

                AccountTrailingActionCluster(
                    isCurrent: isCurrent,
                    switching: switching,
                    refreshing: refreshing,
                    showsRefreshButton: showsRefreshButton,
                    showsReauthenticateButton: showsReauthenticateButton,
                    isRefreshEnabled: isRefreshEnabled,
                    palette: palette,
                    onSwitch: onSwitch,
                    onRefresh: onRefresh,
                    onReauthenticate: onReauthenticate
                )
            }
            .padding(8)
        }
    }
}

struct AccountCollapsedSwitchOverlay: View {
    let isVisible: Bool
    let switching: Bool
    let onDismiss: () -> Void
    let onSwitch: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if isVisible {
            ZStack {
                RoundedRectangle(cornerRadius: LayoutRules.cardRadius, style: .continuous)
                    .fill(AppDesign.elevatedSurface(for: colorScheme))
                    .overlay {
                        RoundedRectangle(cornerRadius: LayoutRules.cardRadius, style: .continuous)
                            .strokeBorder(AppDesign.border(for: colorScheme), lineWidth: 1)
                    }
                    .onTapGesture {
                        onDismiss()
                    }

                AccountSwitchButton(
                    switching: switching,
                    labelStyle: .expanded,
                    onSwitch: onSwitch
                )
            }
            .transition(.opacity)
        }
    }
}

private struct AccountWindowSection: View {
    let presentation: AccountWindowPresentation
    let fillStyle: UsageProgressFillStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(presentation.title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text(presentation.primaryText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }

            LiquidProgressBar(
                progress: presentation.isUsageKnown ? presentation.progressPercent / 100 : 0,
                fillStyle: fillStyle
            )

            Text(presentation.resetText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AccountSwitchButton: View {
    let switching: Bool
    let labelStyle: AccountCardSwitchButtonLabelStyle
    let onSwitch: () -> Void

    var body: some View {
        Button {
            onSwitch()
        } label: {
            if switching {
                ProgressView()
                    .controlSize(.small)
            } else {
                switch labelStyle {
                case .iconOnly:
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                case .expanded:
                    Label(L10n.tr("accounts.card.switch_to_this"), systemImage: "arrow.left.arrow.right.circle.fill")
                        .lineLimit(1)
                }
            }
        }
        .copoolActionButtonStyle(
            prominent: true,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .disabled(switching)
        .accessibilityLabel(Text(L10n.tr("accounts.card.switch_to_this")))
    }
}

private struct AccountRefreshButton: View {
    let refreshing: Bool
    let isEnabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        Button {
            onRefresh()
        } label: {
            if refreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .copoolActionButtonStyle(
            prominent: true,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .disabled(!isEnabled)
        .accessibilityLabel(Text(L10n.tr("common.refresh_usage")))
    }
}

private struct AccountReauthenticateButton: View {
    let onReauthenticate: () -> Void

    var body: some View {
        Button {
            onReauthenticate()
        } label: {
            Label(L10n.tr("accounts.card.sign_in_again"), systemImage: "person.crop.circle.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .copoolActionButtonStyle(
            prominent: true,
            density: .compact,
            iOSStyle: .liquidGlass
        )
        .accessibilityLabel(Text(L10n.tr("accounts.card.sign_in_again")))
    }
}

private struct AccountTrailingActionCluster: View {
    let isCurrent: Bool
    let switching: Bool
    let refreshing: Bool
    let showsRefreshButton: Bool
    let showsReauthenticateButton: Bool
    let isRefreshEnabled: Bool
    let palette: AccountCardPalette
    let onSwitch: () -> Void
    let onRefresh: () -> Void
    let onReauthenticate: () -> Void

    var body: some View {
        if showsReauthenticateButton {
            AccountReauthenticateButton(onReauthenticate: onReauthenticate)
        } else {
            HStack(spacing: 8) {
                AccountSwitchButton(
                    switching: switching,
                    labelStyle: .iconOnly,
                    onSwitch: onSwitch
                )
                .disabled(isCurrent)
                .opacity(isCurrent ? 0.35 : 1)

                if showsRefreshButton {
                    AccountRefreshButton(
                        refreshing: refreshing,
                        isEnabled: isRefreshEnabled,
                        onRefresh: onRefresh
                    )
                }
            }
        }
    }
}

struct AccountUsageErrorOverlay: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
            Text(text)
                .font(.caption2.weight(.medium))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(AppDesign.primaryText(for: colorScheme))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
            .background(
                AppDesign.surface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppDesign.Metrics.radius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppDesign.Metrics.radius, style: .continuous)
                .strokeBorder(AppDesign.primaryText(for: colorScheme).opacity(0.42), lineWidth: 1)
            }
    }
}
