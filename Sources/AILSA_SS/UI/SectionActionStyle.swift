import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

extension View {
    func cardSurface(cornerRadius: CGFloat = LayoutRules.cardRadius, tint: Color? = nil) -> some View {
        modifier(CardSurfaceModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func frostedCapsuleSurface(
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(FrostedCapsuleSurfaceModifier(prominent: prominent, tint: tint))
    }

    func frostedRoundedSurface(
        cornerRadius: CGFloat = 12,
        prominent: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(FrostedRoundedSurfaceModifier(cornerRadius: cornerRadius, prominent: prominent, tint: tint))
    }

    func frostedRoundedInput(cornerRadius: CGFloat = 12) -> some View {
        modifier(FrostedRoundedInputModifier(cornerRadius: cornerRadius))
    }

    func glassSelectableCard(
        selected: Bool,
        cornerRadius: CGFloat = 12,
        tint: Color = .primary
    ) -> some View {
        modifier(
            GlassSelectableCardModifier(
                selected: selected,
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }

    func ailsaSSActionButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular,
        iOSStyle: AILSA_SSActionButtonIOSStyle = .system
    ) -> some View {
        // Keep one compact, opaque treatment across macOS and iOS.  The old
        // `iOSStyle` argument remains for call-site compatibility while the
        // visual language intentionally no longer switches to liquid glass.
        let _ = iOSStyle
        return self.buttonStyle(.frostedCapsule(prominent: prominent, tint: tint, density: density))
    }

    func liquidGlassActionButtonStyle(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular
    ) -> some View {
        ailsaSSActionButtonStyle(
            prominent: prominent,
            tint: tint,
            density: density,
            iOSStyle: .liquidGlass
        )
    }

    func frostedCapsuleInput() -> some View {
        modifier(FrostedCapsuleInputModifier())
    }
}

enum AILSA_SSActionButtonIOSStyle {
    case system
    case liquidGlass
}

struct FrostedCapsuleButtonStyle: ButtonStyle {
    enum Density {
        case regular
        case compact
    }

    let prominent: Bool
    let tint: Color?
    let density: Density

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let isEffectivelyPressed = isEnabled && configuration.isPressed

        configuration.label
            .font(font)
            .foregroundStyle(foregroundColor)
            .tint(foregroundColor)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: minimumHeight)
            .contentShape(shape)
            .background {
                shape.fill(backgroundColor)
            }
            .overlay {
                shape
                    .strokeBorder(borderColor, lineWidth: 1)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion || !isEffectivelyPressed ? 1 : 0.985)
            .animation(reduceMotion ? nil : AppDesign.interaction, value: isEffectivelyPressed)
    }

    private var font: Font {
        switch density {
        case .regular:
            return .subheadline.weight(prominent ? .semibold : .medium)
        case .compact:
            return .callout.weight(prominent ? .semibold : .medium)
        }
    }

    private var horizontalPadding: CGFloat {
        density == .compact ? 10 : 12
    }

    private var verticalPadding: CGFloat {
        density == .compact ? 5 : 7
    }

    private var minimumHeight: CGFloat {
        density == .compact ? LayoutRules.compactActionControlHeight : 34
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppDesign.Metrics.radius, style: .continuous)
    }

    private var backgroundColor: Color {
        guard isEnabled else { return AppDesign.surface(for: colorScheme) }
        if prominent {
            return AppDesign.primaryAction(for: colorScheme)
        }
        return AppDesign.elevatedSurface(for: colorScheme)
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return AppDesign.mutedText(for: colorScheme)
        }
        if prominent {
            return AppDesign.primaryActionText(for: colorScheme)
        }
        return AppDesign.primaryText(for: colorScheme)
    }

    private var borderColor: Color {
        if prominent {
            return AppDesign.primaryAction(for: colorScheme).opacity(0.92)
        }
        return AppDesign.border(for: colorScheme)
    }
}

extension ButtonStyle where Self == FrostedCapsuleButtonStyle {
    static func frostedCapsule(
        prominent: Bool = false,
        tint: Color? = nil,
        density: FrostedCapsuleButtonStyle.Density = .regular
    ) -> Self {
        FrostedCapsuleButtonStyle(prominent: prominent, tint: tint, density: density)
    }
}

private struct FrostedCapsuleInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frostedCapsuleSurface()
    }
}
