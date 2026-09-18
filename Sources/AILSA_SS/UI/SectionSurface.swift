import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct SectionCard<Content: View, HeaderTrailing: View>: View {
    let title: String
    @ViewBuilder let headerTrailing: HeaderTrailing
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) where HeaderTrailing == EmptyView {
        self.title = title
        self.headerTrailing = EmptyView()
        self.content = content()
    }

    init(
        title: String,
        @ViewBuilder headerTrailing: () -> HeaderTrailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.headerTrailing = headerTrailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.headline)
                Spacer(minLength: 0)
                headerTrailing
            }
            content
        }
        .padding(16)
        .cardSurface(cornerRadius: LayoutRules.cardRadius)
    }
}

struct CollapseChevronButton: View {
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
        }
        .ailsaSSActionButtonStyle(density: .compact)
    }
}

struct CloseGlassButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(L10n.tr("common.close"))
        .ailsaSSActionButtonStyle(density: .compact)
    }
}

struct LanguageMenuButton<Label: View>: View {
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    @ViewBuilder let label: Label

    init(
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void,
        @ViewBuilder label: () -> Label
    ) {
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        self.label = label()
    }

    var body: some View {
        Menu {
            ForEach(AppLocale.allCases) { locale in
                Button {
                    onSelectLocale(locale)
                } label: {
                    HStack {
                        Text(L10n.tr(locale.displayNameKey))
                        if locale == currentLocale {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            label
        }
        .accessibilityLabel(Text("settings.language"))
    }
}

struct ToolbarIconLabel: View {
    let systemImage: String
    var isSpinning = false
    var opticalScale = CGFloat(1)
    /// Action-bar icons inherit their enclosing button's contrast color. Native
    /// toolbar icons keep an explicit neutral foreground because they are not
    /// rendered by `FrostedCapsuleButtonStyle`.
    var usesInheritedForeground = false

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        baseIcon
            .modifier(ToolbarIconSpinModifier(isSpinning: isSpinning))
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.system(size: LayoutRules.toolbarIconPointSize, weight: .semibold))
            .scaleEffect(opticalScale)
    }

    @ViewBuilder
    private var baseIcon: some View {
        if usesInheritedForeground {
            icon
        } else {
            icon.foregroundStyle(AppDesign.primaryText(for: colorScheme))
        }
    }
}

private struct ToolbarIconSpinModifier: ViewModifier {
    let isSpinning: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content
                .symbolEffect(.rotate.byLayer, options: .repeating, isActive: isSpinning)
        } else {
            content
                .rotationEffect(.degrees(isSpinning ? 360 : 0))
                .animation(
                    isSpinning
                        ? .linear(duration: 1).repeatForever(autoreverses: false)
                        : .easeOut(duration: 0.2),
                    value: isSpinning
                )
        }
    }
}

struct CardSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(backgroundColor)
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppDesign.border(for: colorScheme), lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        tint == nil
            ? AppDesign.elevatedSurface(for: colorScheme)
            : AppDesign.selectedSurface(for: colorScheme)
    }
}

enum FrostedChromeTokens {
    static func tintedSurface(
        prominent: Bool,
        tint: Color?,
        colorScheme: ColorScheme
    ) -> Color {
        _ = tint
        return prominent
            ? AppDesign.elevatedSurface(for: colorScheme)
            : AppDesign.surface(for: colorScheme)
    }
}

struct FrostedCapsuleSurfaceModifier: ViewModifier {
    let prominent: Bool
    let tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(
                    FrostedChromeTokens.tintedSurface(
                        prominent: prominent,
                        tint: tint,
                        colorScheme: colorScheme
                    )
                )
            }
            .overlay {
                shape
                    .strokeBorder(AppDesign.border(for: colorScheme), lineWidth: 1)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppDesign.Metrics.radius, style: .continuous)
    }
}

struct FrostedRoundedSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let prominent: Bool
    let tint: Color?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(
                    FrostedChromeTokens.tintedSurface(
                        prominent: prominent,
                        tint: tint,
                        colorScheme: colorScheme
                    )
                )
            }
            .overlay {
                shape
                    .strokeBorder(AppDesign.border(for: colorScheme), lineWidth: 1)
            }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

struct FrostedRoundedInputModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frostedRoundedSurface(cornerRadius: cornerRadius)
    }
}

struct GlassSelectableCardModifier: ViewModifier {
    let selected: Bool
    let cornerRadius: CGFloat
    let tint: Color

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .cardSurface(
                cornerRadius: cornerRadius,
                tint: selected ? tint : nil
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        selected
                            ? AppDesign.primaryAction(for: colorScheme)
                            : AppDesign.border(for: colorScheme),
                        lineWidth: 1
                    )
            }
    }
}
