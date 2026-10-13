import XCTest
@testable import AILSA_SS

final class MenuBarAnchorPlacementTests: XCTestCase {
    private let main = MenuBarAnchorPlacement.Screen(
        frame: CGRect(x: 0, y: 0, width: 2056, height: 1329),
        visibleFrame: CGRect(x: 0, y: 70, width: 2056, height: 1229))
    private let upperLeft = MenuBarAnchorPlacement.Screen(
        frame: CGRect(x: -504, y: 1329, width: 2560, height: 1440),
        visibleFrame: CGRect(x: -504, y: 1329, width: 2560, height: 1410))

    func testRejectsVisibleButParkedControlCenterHost() {
        // Actual failure frame from the installed app on macOS 26.
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: 0, y: -22, width: 34, height: 22),
            windowVisible: true, screens: [main, upperLeft]))
    }

    func testUsesMenuBarOnMainDisplay() {
        XCTAssertEqual(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: 1700, y: 1299, width: 34, height: 30),
            windowVisible: true, screens: [main, upperLeft]), 0)
    }

    func testUsesMenuBarOnDisplayWithNegativeOrigin() {
        XCTAssertEqual(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: -200, y: 2739, width: 34, height: 30),
            windowVisible: true, screens: [main, upperLeft]), 1)
    }

    func testDoesNotMistakeAdjacentDisplayEdgeForMenuBar() {
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: -200, y: 1310, width: 34, height: 22),
            windowVisible: true, screens: [main, upperLeft]))
    }

    func testRejectsItemMovedOutsideDisplayByOrganizer() {
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: -12000, y: 1307, width: 34, height: 22),
            windowVisible: true, screens: [main, upperLeft]))
    }

    func testRejectsInvisibleHostEvenAtMenuBarCoordinates() {
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: 1700, y: 1299, width: 34, height: 30),
            windowVisible: false, screens: [main]))
    }

    func testSupportsAutoHiddenMenuBarWhenRevealed() {
        let autoHidden = MenuBarAnchorPlacement.Screen(frame: main.frame, visibleFrame: main.frame)
        XCTAssertEqual(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: 1700, y: 1307, width: 34, height: 22),
            windowVisible: true, screens: [autoHidden]), 0)
    }

    func testRejectsUninitializedAndNonFiniteAnchors() {
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(for: .zero, windowVisible: true, screens: [main]))
        XCTAssertNil(MenuBarAnchorPlacement.screenIndex(
            for: CGRect(x: CGFloat.infinity, y: 1307, width: 34, height: 22),
            windowVisible: true, screens: [main]))
    }
}
