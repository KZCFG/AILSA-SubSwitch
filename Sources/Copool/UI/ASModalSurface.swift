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
    @FocusState private var focused: Bool
    func body(content: Content) -> some View {
        ZStack {
            content.environmentObject(host)
                .allowsHitTesting(host.content == nil)
                .accessibilityHidden(host.content != nil)
            if let modal = host.content {
                ZStack {
                    Color.black.opacity(0.18).contentShape(Rectangle()).onTapGesture { host.close() }
                    modal
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.15), radius: 16, y: 5)
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
