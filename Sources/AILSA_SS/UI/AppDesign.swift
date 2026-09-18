import SwiftUI

/// Shared visual language for the compact desktop tool. The application uses
/// a deliberately neutral black, white, and gray hierarchy; the public site's
/// green is not a persistent product-control color.
enum AppDesign {
    enum Metrics {
        static let radius = CGFloat(8)
        static let compactRadius = CGFloat(6)
        static let pageSpacing = CGFloat(16)
        static let sectionSpacing = CGFloat(16)
        static let groupSpacing = CGFloat(12)
        static let itemSpacing = CGFloat(8)
    }

    static let interaction = Animation.easeInOut(duration: 0.16)
    static let contentTransition = Animation.easeInOut(duration: 0.20)

    static func canvas(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.067) // #111111
        default:
            Color.white
        }
    }

    static func surface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.094) // #181818
        default:
            Color(white: 0.969) // #F7F7F7
        }
    }

    static func elevatedSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.129) // #212121
        default:
            Color.white
        }
    }

    static func primaryText(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.96)
        default:
            Color(white: 0.09) // #171717
        }
    }

    static func secondaryText(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.80)
        default:
            Color(white: 0.247) // #3F3F3F
        }
    }

    static func mutedText(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.65)
        default:
            Color(white: 0.443) // #717171
        }
    }

    static func border(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.23)
        default:
            Color(white: 0.898) // #E5E5E5
        }
    }

    static func accent(for colorScheme: ColorScheme) -> Color {
        primaryAction(for: colorScheme)
    }

    static func accentText(for colorScheme: ColorScheme) -> Color {
        primaryText(for: colorScheme)
    }

    static func primaryAction(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.96)
        default:
            Color(white: 0.067) // #111111
        }
    }

    static func primaryActionText(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.067)
        default:
            Color.white
        }
    }

    static func success(for colorScheme: ColorScheme) -> Color {
        primaryText(for: colorScheme)
    }

    static func warning(for colorScheme: ColorScheme) -> Color {
        primaryText(for: colorScheme)
    }

    static func danger(for colorScheme: ColorScheme) -> Color {
        primaryText(for: colorScheme)
    }

    static func selectedSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.16)
        default:
            Color(white: 0.945)
        }
    }
}

private struct AppCanvasModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.background(AppDesign.canvas(for: colorScheme))
    }
}

private struct AppAccentTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.tint(AppDesign.accent(for: colorScheme))
    }
}

extension View {
    /// Gives each top-level page an opaque canvas, so the website-derived
    /// light palette does not depend on the host window's material.
    func appCanvas() -> some View {
        modifier(AppCanvasModifier())
    }

    /// Applies the monochrome selection color to native controls and focus rings.
    func appAccentTint() -> some View {
        modifier(AppAccentTintModifier())
    }
}
