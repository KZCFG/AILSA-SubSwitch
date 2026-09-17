import SwiftUI

/// Provider progress follows its icon palette; neutral surfaces stay unchanged.
enum UsageProgressFillStyle: Equatable {
    case monochrome
    case codex
    case antigravity
    case cursor
}

private enum QuotaBrandPalette {
    static func flatTint(for style: UsageProgressFillStyle, fallback: Color) -> Color {
        switch style {
        case .codex: return Color(red: 0.35, green: 0.32, blue: 1)
        case .antigravity: return Color(red: 0.22, green: 0.55, blue: 1)
        case .cursor: return Color.gray
        case .monochrome: return fallback
        }
    }

    static func drawSpatialFill(
        _ context: inout GraphicsContext,
        clippedTo fillPath: Path,
        fillRect: CGRect,
        totalSize: CGSize,
        style: UsageProgressFillStyle,
        fallback: Color
    ) {
        if style == .cursor {
            context.fill(fillPath, with: .linearGradient(Gradient(colors: [.gray, .primary]), startPoint: .zero, endPoint: CGPoint(x: totalSize.width, y: totalSize.height)))
            return
        }
        guard style != .monochrome else {
            context.fill(fillPath, with: .color(fallback)); return
        }
        if style == .antigravity {
            // Preserve the icon's spatial arrangement: green → gold → red
            // across the top, fading down to its blue legs. A horizontal
            // rainbow alone incorrectly rotates the logo's vertical colors.
            context.fill(fillPath, with: .linearGradient(Gradient(colors: [
                Color(red: 0.27, green: 0.60, blue: 1),
                Color(red: 0.20, green: 0.48, blue: 1)
            ]), startPoint: .zero, endPoint: CGPoint(x: totalSize.width, y: 0)))
            context.drawLayer { layer in
                layer.fill(fillPath, with: .linearGradient(Gradient(colors: [
                    Color(red: 0.34, green: 0.72, blue: 0.43),
                    Color(red: 1, green: 0.70, blue: 0.13),
                    Color(red: 1, green: 0.28, blue: 0.29)
                ]), startPoint: .zero, endPoint: CGPoint(x: totalSize.width, y: 0)))
                layer.blendMode = .destinationIn
                layer.fill(Path(CGRect(origin: .zero, size: totalSize)), with: .linearGradient(
                    Gradient(colors: [.white, .clear]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: totalSize.height)))
            }
            return
        }
        // Anchor the palette to the entire track, never rotate it with usage.
        let colors: [Color] = style == .codex
            ? [Color(red: 0.74, green: 0.66, blue: 1), Color(red: 0.39, green: 0.44, blue: 1), Color(red: 0.20, green: 0.12, blue: 1)]
            : [Color(red: 0.27, green: 0.60, blue: 1), Color(red: 0.34, green: 0.72, blue: 0.43), Color(red: 1, green: 0.70, blue: 0.13), Color(red: 1, green: 0.28, blue: 0.29), Color(red: 0.27, green: 0.51, blue: 1)]
        context.fill(fillPath, with: .linearGradient(Gradient(colors: colors), startPoint: .zero,
            endPoint: style == .codex ? CGPoint(x: 0, y: totalSize.height) : CGPoint(x: totalSize.width, y: 0)))
    }
}

/// A compact static Canvas progress bar adapted from CodexBar's
/// `UsageProgressBar.swift` (MIT; attribution in `Resources/THIRD_PARTY_NOTICES.md`).
/// It intentionally has no border, highlight, shadow, or implicit animation.
struct LiquidProgressBar: View {
    let progress: Double
    let tint: Color
    let fillStyle: UsageProgressFillStyle
    var height: CGFloat = LayoutRules.liquidProgressHeight

    init(
        progress: Double,
        tint: Color = .primary,
        height: CGFloat = LayoutRules.liquidProgressHeight
    ) {
        self.progress = progress
        self.tint = tint
        fillStyle = .monochrome
        self.height = height
    }

    init(
        progress: Double,
        fillStyle: UsageProgressFillStyle,
        height: CGFloat = LayoutRules.liquidProgressHeight
    ) {
        self.progress = progress
        tint = .primary
        self.fillStyle = fillStyle
        self.height = height
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let metrics = LiquidProgressMetrics(
                progress: progress,
                totalWidth: size.width,
                totalHeight: height
            )
            let rect = CGRect(origin: .zero, size: size)
            let cornerRadius = min(size.height * 0.22, 2)
            let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
            let trackPath = Path { path in
                path.addRoundedRect(in: rect, cornerSize: cornerSize)
            }

            // The complete bar is drawn in one Canvas, mirroring the reference
            // implementation's flat Core Graphics composition.
            context.clip(to: Path(rect))
            context.fill(trackPath, with: .color(trackColor))

            if metrics.visibleFillWidth > 0 {
                let fillRect = CGRect(
                    x: 0,
                    y: 0,
                    width: min(metrics.visibleFillWidth, size.width),
                    height: size.height
                )
                let fillPath = Path { path in
                    path.addRoundedRect(in: fillRect, cornerSize: cornerSize)
                }
                QuotaBrandPalette.drawSpatialFill(
                    &context,
                    clippedTo: fillPath,
                    fillRect: fillRect,
                    totalSize: size,
                    style: fillStyle,
                    fallback: tint
                )
            }
        }
        .frame(height: height)
        .accessibilityValue("\(Int((LiquidProgressMetrics.renderedFillScale(progress) * 100).rounded()))%")
    }

    private var trackColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.16)
        default:
            Color.black.opacity(0.10)
        }
    }
}

/// A compact, flat column for date-based history. Unlike a usage bar, this
/// remains a vertical chart mark: a small corner radius merely softens the
/// rectangle and never turns it into a capsule.
struct LiquidProgressColumn: View {
    let progress: Double
    let tint: Color
    let fillStyle: UsageProgressFillStyle
    var width: CGFloat = 12
    var height: CGFloat = 42

    init(
        progress: Double,
        tint: Color = .primary,
        width: CGFloat = 12,
        height: CGFloat = 42
    ) {
        self.progress = progress
        self.tint = tint
        fillStyle = .monochrome
        self.width = width
        self.height = height
    }

    init(
        progress: Double,
        fillStyle: UsageProgressFillStyle,
        width: CGFloat = 12,
        height: CGFloat = 42
    ) {
        self.progress = progress
        tint = .primary
        self.fillStyle = fillStyle
        self.width = width
        self.height = height
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            // This intentionally stays much smaller than half the width, so
            // the dated history retains flat rectangle geometry.
            let cornerRadius = min(2, max(0, size.width * 0.16))
            let cornerSize = CGSize(width: cornerRadius, height: cornerRadius)
            let trackPath = Path { path in
                path.addRoundedRect(in: rect, cornerSize: cornerSize)
            }
            context.fill(trackPath, with: .color(trackColor))

            let fillScale = LiquidProgressMetrics.renderedFillScale(progress)
            guard fillScale > 0 else { return }
            let fillHeight = min(size.height, max(0, size.height * fillScale))
            let fillRect = CGRect(
                x: 0,
                y: size.height - fillHeight,
                width: size.width,
                height: fillHeight
            )
            let fillPath = Path { path in
                path.addRoundedRect(
                    in: fillRect,
                    cornerSize: CGSize(
                        width: min(cornerRadius, fillRect.width * 0.5),
                        height: min(cornerRadius, fillRect.height * 0.5)
                    )
                )
            }
            QuotaBrandPalette.drawSpatialFill(
                &context,
                clippedTo: fillPath,
                fillRect: fillRect,
                totalSize: size,
                style: fillStyle,
                fallback: tint
            )
        }
        .frame(width: width, height: height)
        .accessibilityValue("\(Int((LiquidProgressMetrics.renderedFillScale(progress) * 100).rounded()))%")
    }

    private var trackColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.16)
        default:
            Color.black.opacity(0.10)
        }
    }
}

struct LiquidProgressRenderModel {
    let fillScale: Double

    init(progress: Double) {
        fillScale = LiquidProgressMetrics.renderedFillScale(progress)
    }

    var showsFill: Bool {
        fillScale > 0
    }
}

struct LiquidProgressMetrics {
    let progress: Double
    let totalWidth: CGFloat
    let totalHeight: CGFloat

    init(
        progress: Double,
        totalWidth: CGFloat,
        totalHeight: CGFloat = LayoutRules.liquidProgressHeight
    ) {
        self.progress = progress
        self.totalWidth = totalWidth
        self.totalHeight = totalHeight
    }

    static func renderedFillScale(_ progress: Double) -> Double {
        let clamped = min(1, max(0, progress))
        let percent = clamped * 100
        let displayPercent = Int(percent.rounded())
        if displayPercent <= 0 { return 0 }
        if displayPercent >= 100 { return 1 }
        return clamped
    }

    var grooveHeight: CGFloat {
        totalHeight
    }

    var rawFillWidth: CGFloat {
        max(0, totalWidth) * Self.renderedFillScale(progress)
    }

    var visibleFillWidth: CGFloat {
        rawFillWidth
    }
}

/// Compact rings remain flat and monochrome; the neutral fill is never rotated
/// or treated as a provider-brand gradient.
struct LiquidProgressRing: View {
    let progress: Double
    let tint: Color
    let fillStyle: UsageProgressFillStyle
    let lineWidth: CGFloat

    init(progress: Double, tint: Color, lineWidth: CGFloat) {
        self.progress = progress
        self.tint = tint
        fillStyle = .monochrome
        self.lineWidth = lineWidth
    }

    init(progress: Double, fillStyle: UsageProgressFillStyle, lineWidth: CGFloat) {
        self.progress = progress
        tint = .primary
        self.fillStyle = fillStyle
        self.lineWidth = lineWidth
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let metrics = LiquidRingMetrics(progress: progress, lineWidth: lineWidth)
        ZStack {
            Circle()
                .inset(by: metrics.trackInset)
                .stroke(trackColor, lineWidth: metrics.trackWidth)

            if metrics.trimEnd > 0 {
                RingFill(
                    progress: metrics.trimEnd,
                    tint: QuotaBrandPalette.flatTint(for: fillStyle, fallback: tint),
                    metrics: metrics
                )
            }
        }
    }

    private var trackColor: Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.16)
        default:
            Color.black.opacity(0.10)
        }
    }
}

struct LiquidRingMetrics {
    let progress: Double
    let lineWidth: CGFloat

    var trimEnd: Double {
        LiquidProgressMetrics.renderedFillScale(progress)
    }

    var isFullCircle: Bool {
        trimEnd >= 1
    }

    var rotationDegrees: Double {
        -90
    }

    var trackInset: CGFloat {
        max(0, lineWidth * 0.04)
    }

    var trackWidth: CGFloat {
        max(1, lineWidth)
    }

    var fillInset: CGFloat {
        trackInset + trackWidth * 0.5
    }

    var fillWidth: CGFloat {
        max(1, lineWidth)
    }

    var dotDiameter: CGFloat {
        max(2, lineWidth * 0.75)
    }

    func dotThreshold(in size: CGSize) -> Double {
        let radius = max(0, min(size.width, size.height) * 0.5 - fillInset)
        let circumference = 2 * .pi * radius
        guard circumference > 0 else { return 0 }
        return min(1, Double(dotDiameter / circumference))
    }
}

private struct RingFill: View {
    let progress: Double
    let tint: Color
    let metrics: LiquidRingMetrics

    var body: some View {
        GeometryReader { geometry in
            if progress < metrics.dotThreshold(in: geometry.size) {
                startDot(in: geometry.size)
            } else {
                ringSegment
            }
        }
    }

    private var ringSegment: some View {
        let style = StrokeStyle(lineWidth: metrics.fillWidth, lineCap: .round)
        return Group {
            if metrics.isFullCircle {
                Circle().inset(by: metrics.fillInset).stroke(tint, style: style)
            } else {
                Circle()
                    .inset(by: metrics.fillInset)
                    .trim(from: 0, to: progress)
                    .rotation(.degrees(metrics.rotationDegrees))
                    .stroke(tint, style: style)
            }
        }
    }

    private func startDot(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        let angle = metrics.rotationDegrees * .pi / 180
        let radius = max(0, min(size.width, size.height) * 0.5 - metrics.fillInset)
        let point = CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
        return Circle()
            .fill(tint)
            .frame(width: metrics.dotDiameter, height: metrics.dotDiameter)
            .position(point)
    }
}
