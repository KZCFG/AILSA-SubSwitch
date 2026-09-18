import XCTest
@testable import AILSA_SS

final class UsageWindowSelectorTests: XCTestCase {
    func testPickNearestWindowPrefersFiveHour() {
        let windows = [
            UsageWindowRaw(usedPercent: 40, limitWindowSeconds: 5 * 60 * 60, resetAt: 123),
            UsageWindowRaw(usedPercent: 20, limitWindowSeconds: 7 * 24 * 60 * 60, resetAt: 456)
        ]

        let selected = UsageWindowSelector.pickNearestWindow(windows, targetSeconds: 5 * 60 * 60)

        XCTAssertEqual(selected?.limitWindowSeconds, 5 * 60 * 60)
    }

    func testPickNearestWindowReturnsNilForEmptyInput() {
        let selected = UsageWindowSelector.pickNearestWindow([], targetSeconds: 100)
        XCTAssertNil(selected)
    }

    func testPickExactWindowDoesNotRelabelWeekAsFiveHour() {
        let windows = [
            UsageWindowRaw(
                usedPercent: 40,
                limitWindowSeconds: 7 * 24 * 60 * 60,
                resetAt: 123
            )
        ]

        XCTAssertNil(UsageWindowSelector.pickExactWindow(windows, targetSeconds: 5 * 60 * 60))
        XCTAssertEqual(
            UsageWindowSelector.pickExactWindow(windows, targetSeconds: 7 * 24 * 60 * 60)?.limitWindowSeconds,
            7 * 24 * 60 * 60
        )
    }
}
