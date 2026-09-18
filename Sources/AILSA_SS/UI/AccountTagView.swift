import SwiftUI

struct AccountTagView: View {
    let text: String
    let backgroundColor: Color
    let foregroundColor: Color
    var font: Font = .caption2.weight(.bold)
    var allowsCompression = false
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 4

    var body: some View {
        Text(text)
            .font(font)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .fixedSize(horizontal: !allowsCompression, vertical: false)
            .background(backgroundColor, in: Capsule())
    }
}

struct AccountCompactHeaderContent: View {
    let planLabel: String
    let workspaceLabel: String?
    let statusLabel: String?
    let accountName: String
    let accentColor: Color
    var statusColor: Color = .primary
    var tagFont: Font = .caption2.weight(.bold)
    var titleFont: Font = .headline
    var titleColor: Color = .primary
    var spacing: CGFloat = 8
    var tagHorizontalPadding: CGFloat = 8
    var tagVerticalPadding: CGFloat = 4
    var titleMinimumScaleFactor: CGFloat = 0.8
    var expandsHorizontally = true
    var trailingReservation: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            HStack(spacing: 6) {
                AccountTagView(
                    text: planLabel,
                    backgroundColor: accentColor.opacity(0.18),
                    foregroundColor: accentColor,
                    font: tagFont,
                    horizontalPadding: tagHorizontalPadding,
                    verticalPadding: tagVerticalPadding
                )

                if let workspaceLabel, !workspaceLabel.isEmpty {
                    AccountTagView(
                        text: workspaceLabel,
                        backgroundColor: accentColor.opacity(0.18),
                        foregroundColor: accentColor,
                        font: tagFont,
                        allowsCompression: true,
                        horizontalPadding: tagHorizontalPadding,
                        verticalPadding: tagVerticalPadding
                    )
                    .modifier(AccountCompactHorizontalExpansion(enabled: expandsHorizontally))
                }

                if let statusLabel, !statusLabel.isEmpty {
                    AccountTagView(
                        text: statusLabel,
                        backgroundColor: statusColor.opacity(0.16),
                        foregroundColor: statusColor,
                        font: tagFont,
                        horizontalPadding: tagHorizontalPadding,
                        verticalPadding: tagVerticalPadding
                    )
                } else if workspaceLabel == nil, expandsHorizontally {
                    Spacer(minLength: 0)
                }
            }.padding(.trailing, trailingReservation)

            Text(accountName)
                .font(titleFont)
                .foregroundStyle(titleColor)
                .lineLimit(1)
                .minimumScaleFactor(titleMinimumScaleFactor)
                .truncationMode(.tail)
        }
        .modifier(AccountCompactHorizontalExpansion(enabled: expandsHorizontally))
    }
}

struct AccountCompactUsageRow: View {
    let rings: [AccountCompactRingDescriptor]
    var spacing: CGFloat = 14
    var ringSize: CGFloat = 54
    var lineWidth: CGFloat = 7
    var valueFont: Font = .system(size: 10, weight: .bold)
    var subtitleFont: Font = .system(size: 9, weight: .semibold)
    var valueColor: Color = .primary
    var subtitleColor: Color = .secondary
    var expandsHorizontally = true

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(rings) { ring in
                AccountCompactUsageRing(
                    descriptor: ring,
                    size: ringSize,
                    lineWidth: lineWidth,
                    valueFont: valueFont,
                    subtitleFont: subtitleFont,
                    valueColor: valueColor,
                    subtitleColor: subtitleColor
                )
            }
        }
        .modifier(AccountCompactHorizontalExpansion(enabled: expandsHorizontally, alignment: .center))
    }
}

private struct AccountCompactHorizontalExpansion: ViewModifier {
    let enabled: Bool
    var alignment: Alignment = .leading

    func body(content: Content) -> some View {
        if enabled {
            content.frame(maxWidth: .infinity, alignment: alignment)
        } else {
            content
        }
    }
}

struct AccountCompactRingDescriptor: Identifiable {
    let id: String
    let valueText: String
    let subtitleText: String
    let progress: Double
    let fillStyle: UsageProgressFillStyle
}


private struct AccountCompactUsageRing: View {
    let descriptor: AccountCompactRingDescriptor
    let size: CGFloat
    let lineWidth: CGFloat
    let valueFont: Font
    let subtitleFont: Font
    let valueColor: Color
    let subtitleColor: Color

    var body: some View {
        VStack(spacing: 5) {
          ZStack {
            LiquidProgressRing(
                progress: descriptor.progress,
                fillStyle: descriptor.fillStyle,
                lineWidth: lineWidth
            )

            VStack(spacing: 1) {
                Text(descriptor.valueText)
                    .font(valueFont)
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
          }
          .frame(width: size, height: size)
          Text(descriptor.subtitleText)
              .font(subtitleFont).foregroundStyle(subtitleColor)
              .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
              .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(descriptor.subtitleText.replacingOccurrences(of: "\n", with: " · ") + ": " + descriptor.valueText)
    }
}
