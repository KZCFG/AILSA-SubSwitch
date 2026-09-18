import SwiftUI

@MainActor
final class ASModalHost: ObservableObject {
    @Published var content: AnyView?
    private var onClose: (() -> Void)?
    func present<Content: View>(onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onClose = onClose
        self.content = AnyView(content())
    }
    func close() {
        content = nil
        let completion = onClose
        onClose = nil
        completion?()
    }
}

struct ASModalSurface: ViewModifier {
    @StateObject private var host = ASModalHost()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        ZStack {
            content.environmentObject(host)
                .allowsHitTesting(host.content == nil)
                .accessibilityHidden(host.content != nil)
            if let modal = host.content {
                ZStack {
                    // Keep the hierarchy visible in light mode. The old
                    // material-plus-dark-scrim combination turned both the
                    // card grid and the confirmation surface into the same
                    // muddy gray layer.
                    Color.black
                        .opacity(colorScheme == .dark ? 0.36 : 0.08)
                        .contentShape(Rectangle())
                        .onTapGesture { host.close() }
                    modal
                        .background(
                            AppDesign.elevatedSurface(for: colorScheme),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(AppDesign.border(for: colorScheme), lineWidth: 1)
                        }
                        .shadow(
                            color: .black.opacity(colorScheme == .dark ? 0.42 : 0.16),
                            radius: 24,
                            y: 10
                        )
                        .focusable().focused($focused).focusEffectDisabled()
                        .onKeyPress(.escape) { host.close(); return .handled }
                        .accessibilityAddTraits(.isModal)
                        .onAppear { focused = true }
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: host.content != nil)
        .onDisappear { host.close() }
    }
}
