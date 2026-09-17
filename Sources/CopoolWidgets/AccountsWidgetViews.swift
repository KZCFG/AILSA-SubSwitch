import SwiftUI
import WidgetKit
import Foundation
import os

private enum AccountsWidgetStyle {
    static func backgroundColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.09)
        default:
            Color.white
        }
    }

    static func primaryTextColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.96)
        default:
            Color(white: 0.09)
        }
    }

    static func secondaryTextColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.78)
        default:
            Color(white: 0.247)
        }
    }

    static func dividerColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.25)
        default:
            Color(white: 0.898)
        }
    }

    static func progressTintColor(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.96)
        default:
            Color(white: 0.09)
        }
    }

    static func layout(for family: WidgetFamily, size: CGSize) -> AccountsWidgetLayout {
        let width = size.width
        let scale = layoutScale(for: family, size: size)
        func scaled(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded(.toNearestOrEven)
        }

        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let compactSpacing: CGFloat
        let compactSectionSpacing: CGFloat
        let compactUsageSpacing: CGFloat
        let largeSectionSpacing: CGFloat
        let rowSpacing: CGFloat
        let compactRingSize: CGFloat
        let compactRingLineWidth: CGFloat
        let metricColumnWidth: CGFloat
        let rowMetricColumnWidth: CGFloat
        let chipFontSize: CGFloat
        let compactTitleFontSize: CGFloat
        let compactSubtitleFontSize: CGFloat
        let compactRingValueFontSize: CGFloat
        let compactRingTitleFontSize: CGFloat
        let metricValueFontSize: CGFloat
        let metricLabelFontSize: CGFloat
        let metricIconSize: CGFloat
        let metricResetFontSize: CGFloat
        let metricResetIconSize: CGFloat
        let rowMetricValueFontSize: CGFloat
        let rowMetricLabelFontSize: CGFloat
        let rowMetricIconSize: CGFloat
        let rowResetFontSize: CGFloat
        let rowResetIconSize: CGFloat
        let currentHeaderTitleFontSize: CGFloat
        let currentHeaderDetailFontSize: CGFloat

        switch family {
        case .systemSmall:
            horizontalPadding = 0
            verticalPadding = 0
            let contentWidth = max(width - (horizontalPadding * 2), 1)
            compactSpacing = scaled(14)
            compactSectionSpacing = scaled(8)
            compactUsageSpacing = scaled(8)
            largeSectionSpacing = scaled(14)
            rowSpacing = scaled(10)
            compactRingSize = min(max(contentWidth * 0.40, scaled(64)), scaled(82))
            compactRingLineWidth = scaled(7)
            metricColumnWidth = contentWidth
            rowMetricColumnWidth = contentWidth
            chipFontSize = scaled(11)
            compactTitleFontSize = scaled(15)
            compactSubtitleFontSize = scaled(11)
            compactRingValueFontSize = scaled(18)
            compactRingTitleFontSize = scaled(11)
            metricValueFontSize = scaled(14)
            metricLabelFontSize = scaled(13)
            metricIconSize = scaled(11)
            metricResetFontSize = scaled(11)
            metricResetIconSize = scaled(10)
            rowMetricValueFontSize = scaled(13)
            rowMetricLabelFontSize = scaled(12)
            rowMetricIconSize = scaled(10)
            rowResetFontSize = scaled(10)
            rowResetIconSize = scaled(9)
            currentHeaderTitleFontSize = scaled(17)
            currentHeaderDetailFontSize = scaled(12)
        case .systemMedium:
            horizontalPadding = 0
            verticalPadding = 0
            let contentWidth = max(width - (horizontalPadding * 2), 1)
            compactSpacing = scaled(14)
            compactSectionSpacing = scaled(8)
            compactUsageSpacing = scaled(10)
            largeSectionSpacing = scaled(14)
            rowSpacing = scaled(10)
            compactRingSize = min(max(contentWidth * 0.24, scaled(62)), scaled(80))
            compactRingLineWidth = scaled(7)
            metricColumnWidth = contentWidth
            rowMetricColumnWidth = contentWidth
            chipFontSize = scaled(11)
            compactTitleFontSize = scaled(15)
            compactSubtitleFontSize = scaled(11)
            compactRingValueFontSize = scaled(18)
            compactRingTitleFontSize = scaled(11)
            metricValueFontSize = scaled(14)
            metricLabelFontSize = scaled(13)
            metricIconSize = scaled(11)
            metricResetFontSize = scaled(11)
            metricResetIconSize = scaled(10)
            rowMetricValueFontSize = scaled(13)
            rowMetricLabelFontSize = scaled(12)
            rowMetricIconSize = scaled(10)
            rowResetFontSize = scaled(10)
            rowResetIconSize = scaled(9)
            currentHeaderTitleFontSize = scaled(18)
            currentHeaderDetailFontSize = scaled(12)
        default:
            horizontalPadding = 0
            verticalPadding = 0
            let contentWidth = max(width - (horizontalPadding * 2), 1)
            compactSpacing = scaled(14)
            compactSectionSpacing = scaled(12)
            compactUsageSpacing = scaled(16)
            largeSectionSpacing = scaled(16)
            rowSpacing = scaled(14)
            compactRingSize = min(max(contentWidth * 0.17, scaled(52)), scaled(68))
            compactRingLineWidth = scaled(7)
            metricColumnWidth = contentWidth
            rowMetricColumnWidth = contentWidth
            chipFontSize = scaled(12)
            compactTitleFontSize = scaled(18)
            compactSubtitleFontSize = scaled(13)
            compactRingValueFontSize = scaled(16)
            compactRingTitleFontSize = scaled(11)
            metricValueFontSize = scaled(15)
            metricLabelFontSize = scaled(14)
            metricIconSize = scaled(12)
            metricResetFontSize = scaled(11)
            metricResetIconSize = scaled(10)
            rowMetricValueFontSize = scaled(14)
            rowMetricLabelFontSize = scaled(13)
            rowMetricIconSize = scaled(11)
            rowResetFontSize = scaled(11)
            rowResetIconSize = scaled(10)
            currentHeaderTitleFontSize = scaled(19)
            currentHeaderDetailFontSize = scaled(13)
        }

        return AccountsWidgetLayout(
            family: family,
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            compactSpacing: compactSpacing,
            compactSectionSpacing: compactSectionSpacing,
            compactUsageSpacing: compactUsageSpacing,
            largeSectionSpacing: largeSectionSpacing,
            rowSpacing: rowSpacing,
            compactRingSize: compactRingSize,
            compactRingLineWidth: compactRingLineWidth,
            metricColumnWidth: metricColumnWidth,
            rowMetricColumnWidth: rowMetricColumnWidth,
            chipFontSize: chipFontSize,
            compactTitleFontSize: compactTitleFontSize,
            compactSubtitleFontSize: compactSubtitleFontSize,
            compactRingValueFontSize: compactRingValueFontSize,
            compactRingTitleFontSize: compactRingTitleFontSize,
            metricValueFontSize: metricValueFontSize,
            metricLabelFontSize: metricLabelFontSize,
            metricIconSize: metricIconSize,
            metricResetFontSize: metricResetFontSize,
            metricResetIconSize: metricResetIconSize,
            rowMetricValueFontSize: rowMetricValueFontSize,
            rowMetricLabelFontSize: rowMetricLabelFontSize,
            rowMetricIconSize: rowMetricIconSize,
            rowResetFontSize: rowResetFontSize,
            rowResetIconSize: rowResetIconSize,
            currentHeaderTitleFontSize: currentHeaderTitleFontSize,
            currentHeaderDetailFontSize: currentHeaderDetailFontSize
        )
    }

    private static func layoutScale(for family: WidgetFamily, size: CGSize) -> CGFloat {
        let referenceSize: CGSize

        switch family {
        case .systemSmall:
            referenceSize = CGSize(width: 158, height: 158)
        case .systemMedium:
            referenceSize = CGSize(width: 338, height: 158)
        default:
            referenceSize = CGSize(width: 338, height: 354)
        }

        let widthScale = size.width / max(referenceSize.width, 1)
        let heightScale = size.height / max(referenceSize.height, 1)
        return min(max(min(widthScale, heightScale), 0.72), 1.20)
    }

}
private struct AccountsWidgetLayout {
    let family: WidgetFamily
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let compactSpacing: CGFloat
    let compactSectionSpacing: CGFloat
    let compactUsageSpacing: CGFloat
    let largeSectionSpacing: CGFloat
    let rowSpacing: CGFloat
    let compactRingSize: CGFloat
    let compactRingLineWidth: CGFloat
    let metricColumnWidth: CGFloat
    let rowMetricColumnWidth: CGFloat
    let chipFontSize: CGFloat
    let compactTitleFontSize: CGFloat
    let compactSubtitleFontSize: CGFloat
    let compactRingValueFontSize: CGFloat
    let compactRingTitleFontSize: CGFloat
    let metricValueFontSize: CGFloat
    let metricLabelFontSize: CGFloat
    let metricIconSize: CGFloat
    let metricResetFontSize: CGFloat
    let metricResetIconSize: CGFloat
    let rowMetricValueFontSize: CGFloat
    let rowMetricLabelFontSize: CGFloat
    let rowMetricIconSize: CGFloat
    let rowResetFontSize: CGFloat
    let rowResetIconSize: CGFloat
    let currentHeaderTitleFontSize: CGFloat
    let currentHeaderDetailFontSize: CGFloat
}

struct AccountsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: AccountsWidgetEntry

    var body: some View {
        GeometryReader { proxy in
            let layout = AccountsWidgetStyle.layout(for: family, size: proxy.size)

            Group {
                switch family {
                case .systemSmall:
                    AccountsWidgetSmallView(
                        card: entry.snapshot.currentCard,
                        usageProgressDisplayMode: usageProgressDisplayMode,
                        layout: layout
                    )
                case .systemMedium:
                    AccountsWidgetMediumView(
                        current: entry.snapshot.currentCard,
                        secondary: entry.snapshot.secondaryCard,
                        usageProgressDisplayMode: usageProgressDisplayMode,
                        layout: layout
                    )
                default:
                    AccountsWidgetLargeView(
                        current: entry.snapshot.currentCard,
                        rows: entry.snapshot.rows,
                        usageProgressDisplayMode: usageProgressDisplayMode,
                        layout: layout
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .containerBackground(AccountsWidgetStyle.backgroundColor(for: colorScheme), for: .widget)
    }

    private var usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode {
        entry.snapshot.resolvedUsageProgressDisplayMode()
    }
}

private struct AccountsWidgetSmallView: View {
    let card: AccountsWidgetCardSnapshot?
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let layout: AccountsWidgetLayout

    var body: some View {
        Group {
            if let card {
                AccountsWidgetCompactCardContent(
                    card: card,
                    usageProgressDisplayMode: usageProgressDisplayMode,
                    layout: layout
                )
            } else {
                AccountsWidgetEmptyState()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }
}

private struct AccountsWidgetMediumView: View {
    @Environment(\.widgetContentMargins) private var widgetContentMargins
    let current: AccountsWidgetCardSnapshot?
    let secondary: AccountsWidgetCardSnapshot?
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let layout: AccountsWidgetLayout

    var body: some View {
        // WidgetKit's native margins can be much larger than the visual gap we
        // need around a one-point divider. Clamp the column gutter so both
        // cards retain enough horizontal room at the real systemMedium size.
        let nativeMargin = max(widgetContentMargins.leading, widgetContentMargins.trailing)
        let dividerSpacing = min(max(nativeMargin * 0.5, 8), 12)

        return HStack(spacing: dividerSpacing) {
            Group {
                if let current {
                    AccountsWidgetCompactCardContent(
                        card: current,
                        usageProgressDisplayMode: usageProgressDisplayMode,
                        layout: layout
                    )
                } else {
                    AccountsWidgetEmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AccountsWidgetMediumDivider()

            Group {
                if let secondary {
                    AccountsWidgetCompactCardContent(
                        card: secondary,
                        usageProgressDisplayMode: usageProgressDisplayMode,
                        layout: layout
                    )
                } else {
                    AccountsWidgetEmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }
}

private struct AccountsWidgetLargeView: View {
    @Environment(\.colorScheme) private var colorScheme
    let current: AccountsWidgetCardSnapshot?
    let rows: [AccountsWidgetRowSnapshot]
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let layout: AccountsWidgetLayout

    var body: some View {
        GeometryReader { proxy in
            let groups = largeGroups

            if groups.isEmpty {
                AccountsWidgetEmptyState()
            } else {
                let size = proxy.size
                let groupUnitHeight = size.height / CGFloat(max(groups.count, 1))
                let tagFontSize = min(max(groupUnitHeight * 0.13, 9), 12)
                let tagHorizontalPadding = min(max(size.width * 0.009, 5), 8)
                let tagVerticalPadding = min(max(groupUnitHeight * 0.045, 2), 3)
                let topRowSpacing = min(max(groupUnitHeight * 0.04, 2), 4)
                let metricSpacing = min(max(size.width * 0.028, 10), 18)
                let detailFontSize = min(max(groupUnitHeight * 0.12, 10), 13)
                let iconSize = min(max(groupUnitHeight * 0.11, 10), 13)
                let progressHeight = min(max(groupUnitHeight * 0.10, 7), 10)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        AccountsWidgetLargeGroupView(
                            group: group,
                            usageProgressDisplayMode: usageProgressDisplayMode,
                            tagFontSize: tagFontSize,
                            tagHorizontalPadding: tagHorizontalPadding,
                            tagVerticalPadding: tagVerticalPadding,
                            topRowSpacing: topRowSpacing,
                            metricSpacing: metricSpacing,
                            detailFontSize: detailFontSize,
                            iconSize: iconSize,
                            progressHeight: progressHeight
                        )
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                        if index < groups.count - 1 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding(.horizontal, layout.horizontalPadding)
        .padding(.vertical, layout.verticalPadding)
    }

    private var largeGroups: [AccountsWidgetLargeGroup] {
        var groups: [AccountsWidgetLargeGroup] = []

        if let current {
            groups.append(
                AccountsWidgetLargeGroup(
                    id: current.id,
                    planLabel: current.planLabel,
                    workspaceLabel: current.workspaceLabel,
                    accountLabel: current.accountLabel,
                    windows: current.visibleWindows,
                    isQuotaDisplayHidden: current.isQuotaDisplayHidden
                )
            )
        }

        groups.append(
            contentsOf: rows.map {
                AccountsWidgetLargeGroup(
                    id: $0.id,
                    planLabel: $0.planLabel,
                    workspaceLabel: $0.workspaceLabel,
                    accountLabel: $0.accountLabel,
                    windows: $0.visibleWindows,
                    isQuotaDisplayHidden: $0.isQuotaDisplayHidden
                )
            }
        )

        return Array(groups.prefix(5))
    }
}

private struct AccountsWidgetCompactCardContent: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    let card: AccountsWidgetCardSnapshot
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let layout: AccountsWidgetLayout

    private var planTagPalette: AccountsWidgetTagPalette {
        AccountsWidgetTagPaletteResolver.planTagPalette(
            for: card.planLabel,
            colorScheme: colorScheme,
            renderingMode: renderingMode
        )
    }

    private var accountTagPalette: AccountsWidgetTagPalette {
        AccountsWidgetTagPaletteResolver.accountTagPalette(
            for: colorScheme,
            renderingMode: renderingMode
        )
    }

    private var workspaceLabel: String? {
        guard let workspaceLabel = card.workspaceLabel, !workspaceLabel.isEmpty else {
            return nil
        }
        return workspaceLabel
    }

    private var displayAccountName: String {
        card.accountLabel
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let hasWorkspaceLabel = workspaceLabel != nil
            let groupSpacing = min(max(size.height * 0.045, 6), 10)
            let tagFontSize = min(max(size.height * 0.085, 11), 14)
            let tagHorizontalPadding = min(max(size.width * 0.04, 6), 12)
            let tagVerticalPadding = min(max(size.height * 0.018, 2), 4)
            let ringSpacing = min(max(size.width * 0.06, 10), 18)
            let visibleWindows = card.visibleWindows
            let metricCount = max(visibleWindows.count, 1)
            let tagCount = hasWorkspaceLabel ? 3 : 2
            // `Font` renders taller than its point size; reserve that line
            // height so a three-tag card cannot push a bottom-pinned ring
            // beyond the widget's actual bounds.
            let tagHeight = (tagFontSize * 1.20) + (tagVerticalPadding * 2)
            let tagAreaHeight = (tagHeight * CGFloat(tagCount))
                + (groupSpacing * CGFloat(tagCount - 1))
            let ringAreaHeight = max(size.height - tagAreaHeight - groupSpacing, 34)
            let mediumRingCap = layout.family == .systemMedium
                ? min(layout.compactRingSize, 70)
                : layout.compactRingSize
            let ringSize = min(
                (size.width - (ringSpacing * CGFloat(max(metricCount - 1, 0)))) / CGFloat(metricCount),
                ringAreaHeight,
                mediumRingCap
            )
            let ringLineWidth = min(max(ringSize * 0.13, 7), 12)
            let ringValueFontSize = min(max(ringSize * 0.18, 11), 18)
            let ringSubtitleFontSize = min(max(ringSize * 0.085, 8), 10)
            let maximumTagWidth = max(size.width - 6, 24)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: groupSpacing) {
                    AccountsWidgetTag(
                        text: card.planLabel,
                        backgroundColor: planTagPalette.fill.color,
                        foregroundColor: planTagPalette.text.color,
                        font: Font.system(size: tagFontSize, weight: .bold, design: .rounded),
                        horizontalPadding: tagHorizontalPadding,
                        verticalPadding: tagVerticalPadding,
                        maximumWidth: maximumTagWidth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)


                    if let workspaceLabel {
                        AccountsWidgetTag(
                            text: workspaceLabel,
                            backgroundColor: planTagPalette.fill.color,
                            foregroundColor: planTagPalette.text.color,
                            font: Font.system(size: tagFontSize, weight: .bold, design: .rounded),
                            horizontalPadding: tagHorizontalPadding,
                            verticalPadding: tagVerticalPadding,
                            maximumWidth: maximumTagWidth
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    AccountsWidgetTag(
                        text: displayAccountName,
                        backgroundColor: accountTagPalette.fill.color,
                        foregroundColor: accountTagPalette.text.color,
                        font: Font.system(size: tagFontSize, weight: .bold, design: .rounded),
                        horizontalPadding: tagHorizontalPadding,
                        verticalPadding: tagVerticalPadding,
                        maximumWidth: maximumTagWidth
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: groupSpacing)

                HStack(alignment: .bottom, spacing: ringSpacing) {
                    if visibleWindows.isEmpty {
                        AccountsWidgetQuotaMessage(isHidden: card.isQuotaDisplayHidden)
                    } else {
                        ForEach(visibleWindows.indices, id: \.self) { index in
                            let window = visibleWindows[index]
                            AccountsWidgetCompactRing(
                                valueText: displayText(for: window),
                                subtitleText: window.title,
                                progress: displayProgress(for: window),
                                tint: AccountsWidgetStyle.progressTintColor(for: colorScheme),
                                size: ringSize,
                                lineWidth: ringLineWidth,
                                valueFontSize: ringValueFontSize,
                                subtitleFontSize: ringSubtitleFontSize
                            )
                            .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .trailing)
                        }
                    }
                }
                .frame(height: ringSize, alignment: .bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func displayText(for window: AccountsWidgetWindowSnapshot) -> String {
        usageProgressDisplayMode == .remaining ? window.remainingText : window.usedText
    }

    private func displayProgress(for window: AccountsWidgetWindowSnapshot) -> Double {
        usageProgressDisplayMode == .remaining ? max(0, 1 - window.progressFraction) : window.progressFraction
    }
}

private struct AccountsWidgetTag: View {
    let text: String
    let backgroundColor: Color
    let foregroundColor: Color
    let font: Font
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    var maximumWidth: CGFloat? = nil

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .truncationMode(.tail)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(backgroundColor, in: Capsule())
            .frame(maxWidth: maximumWidth, alignment: .leading)
    }
}

private struct AccountsWidgetQuotaMessage: View {
    @Environment(\.colorScheme) private var colorScheme
    let isHidden: Bool

    var body: some View {
        Text(isHidden ? "Quota display hidden" : "Quota unavailable")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(AccountsWidgetStyle.secondaryTextColor(for: colorScheme))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountsWidgetMediumDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        AccountsWidgetStyle.dividerColor(for: colorScheme).opacity(0.4),
                        AccountsWidgetStyle.dividerColor(for: colorScheme),
                        AccountsWidgetStyle.dividerColor(for: colorScheme).opacity(0.4),
                        Color.white.opacity(0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 1)
            .padding(.vertical, 2)
    }
}

private struct AccountsWidgetCompactRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let valueText: String
    let subtitleText: String
    let progress: Double
    let tint: Color
    let size: CGFloat
    let lineWidth: CGFloat
    let valueFontSize: CGFloat
    let subtitleFontSize: CGFloat

    private var innerContentWidth: CGFloat {
        max(size - (lineWidth * 2) - 12, 20)
    }

    var body: some View {
        ZStack {
            LiquidProgressRing(
                progress: progress,
                tint: tint,
                lineWidth: lineWidth
            )

            VStack(spacing: 1) {
                Text(valueText)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(AccountsWidgetStyle.primaryTextColor(for: colorScheme))
                Text(subtitleText)
                    .font(.system(size: subtitleFontSize, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(AccountsWidgetStyle.secondaryTextColor(for: colorScheme))
            }
            .frame(width: innerContentWidth)
        }
        .frame(width: size, height: size)
    }
}

private struct AccountsWidgetLargeGroup: Identifiable {
    let id: String
    let planLabel: String
    let workspaceLabel: String?
    let accountLabel: String
    let windows: [AccountsWidgetWindowSnapshot]
    let isQuotaDisplayHidden: Bool
}

private struct AccountsWidgetLargeGroupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.widgetRenderingMode) private var renderingMode
    let group: AccountsWidgetLargeGroup
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let tagFontSize: CGFloat
    let tagHorizontalPadding: CGFloat
    let tagVerticalPadding: CGFloat
    let topRowSpacing: CGFloat
    let metricSpacing: CGFloat
    let detailFontSize: CGFloat
    let iconSize: CGFloat
    let progressHeight: CGFloat

    private var planTagPalette: AccountsWidgetTagPalette {
        AccountsWidgetTagPaletteResolver.planTagPalette(
            for: group.planLabel,
            colorScheme: colorScheme,
            renderingMode: renderingMode
        )
    }

    private var accountTagPalette: AccountsWidgetTagPalette {
        AccountsWidgetTagPaletteResolver.accountTagPalette(
            for: colorScheme,
            renderingMode: renderingMode
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: topRowSpacing) {
            HStack(spacing: 4) {
                AccountsWidgetTag(
                    text: group.planLabel,
                    backgroundColor: planTagPalette.fill.color,
                    foregroundColor: planTagPalette.text.color,
                    font: .system(size: tagFontSize, weight: .bold, design: .rounded),
                    horizontalPadding: tagHorizontalPadding,
                    verticalPadding: tagVerticalPadding
                )

                if let workspaceLabel = group.workspaceLabel {
                    AccountsWidgetTag(
                        text: workspaceLabel,
                        backgroundColor: planTagPalette.fill.color,
                        foregroundColor: planTagPalette.text.color,
                        font: .system(size: tagFontSize, weight: .bold, design: .rounded),
                        horizontalPadding: tagHorizontalPadding,
                        verticalPadding: tagVerticalPadding
                    )
                }

                AccountsWidgetTag(
                    text: group.accountLabel,
                    backgroundColor: accountTagPalette.fill.color,
                    foregroundColor: accountTagPalette.text.color,
                    font: .system(size: tagFontSize, weight: .bold, design: .rounded),
                    horizontalPadding: tagHorizontalPadding,
                    verticalPadding: tagVerticalPadding
                )
            }

            HStack(alignment: .top, spacing: metricSpacing) {
                if group.windows.isEmpty {
                    AccountsWidgetQuotaMessage(isHidden: group.isQuotaDisplayHidden)
                } else {
                    ForEach(group.windows.indices, id: \.self) { index in
                        AccountsWidgetLargeMetric(
                            window: group.windows[index],
                            usageProgressDisplayMode: usageProgressDisplayMode,
                            tint: AccountsWidgetStyle.progressTintColor(for: colorScheme),
                            detailFontSize: detailFontSize,
                            iconSize: iconSize,
                            progressHeight: progressHeight
                        )
                    }
                }
            }
        }
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct AccountsWidgetLargeMetric: View {
    @Environment(\.colorScheme) private var colorScheme
    let window: AccountsWidgetWindowSnapshot
    let usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    let tint: Color
    let detailFontSize: CGFloat
    let iconSize: CGFloat
    let progressHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(window.title)
                    .font(.system(size: detailFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(AccountsWidgetStyle.secondaryTextColor(for: colorScheme))

                LiquidProgressBar(
                    progress: displayProgress,
                    tint: tint,
                    height: progressHeight
                )
            }

            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: iconSize, weight: .medium))
                    Text(window.resetText)
                        .font(.system(size: detailFontSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "drop.halffull")
                        .font(.system(size: iconSize, weight: .medium))
                    Text(displayText)
                        .font(.system(size: detailFontSize, weight: .semibold, design: .rounded))
                }
            }
            .foregroundStyle(AccountsWidgetStyle.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayProgress: Double {
        usageProgressDisplayMode == .remaining ? max(0, 1 - window.progressFraction) : window.progressFraction
    }

    private var displayText: String {
        usageProgressDisplayMode == .remaining ? window.remainingText : window.usedText
    }
}

private struct AccountsWidgetEmptyState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Accounts")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AccountsWidgetStyle.primaryTextColor(for: colorScheme))
            Text("Open AILSA SubSwitch to sync account usage into the widget.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AccountsWidgetStyle.secondaryTextColor(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
