import SwiftUI

/// The fixed size RootScene gives the MenuBarExtra panel. Pages read this
/// instead of assuming the 760pt design height, so a small display (or a
/// large Dock) can switch to denser layouts rather than clip or scroll.
private struct PanelViewportSizeKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

extension EnvironmentValues {
    var panelViewportSize: CGSize? {
        get { self[PanelViewportSizeKey.self] }
        set { self[PanelViewportSizeKey.self] = newValue }
    }
}
