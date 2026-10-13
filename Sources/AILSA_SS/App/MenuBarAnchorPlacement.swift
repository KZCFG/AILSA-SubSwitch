import Foundation

/// Control Center can report a visible status item while parking its window
/// outside every display. Only a button in an actual menu bar can anchor a panel.
enum MenuBarAnchorPlacement {
    struct Screen {
        let frame: CGRect
        let visibleFrame: CGRect
    }

    static func screenIndex(for buttonFrame: CGRect, windowVisible: Bool, screens: [Screen]) -> Int? {
        guard windowVisible, buttonFrame.width > 0, buttonFrame.height > 0,
              [buttonFrame.minX, buttonFrame.minY, buttonFrame.maxX, buttonFrame.maxY]
                .allSatisfy(\.isFinite) else { return nil }

        return screens.firstIndex { screen in
            let menuBarHeight = max(32, screen.frame.maxY - screen.visibleFrame.maxY)
            return buttonFrame.minX >= screen.frame.minX - 1
                && buttonFrame.maxX <= screen.frame.maxX + 1
                && buttonFrame.minY >= screen.frame.maxY - menuBarHeight - 1
                && buttonFrame.maxY <= screen.frame.maxY + 1
        }
    }
}
