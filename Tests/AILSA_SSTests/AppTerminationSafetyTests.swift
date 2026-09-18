import XCTest
@testable import AILSA_SS

final class AppTerminationSafetyTests: XCTestCase {
    func testIdleQuitBlocksNewSwitches() {
        let guardState = AppTerminationSafety()
        XCTAssertTrue(guardState.requestTermination())
        XCTAssertThrowsError(try guardState.beginAccountSwitch())
    }

    func testQuitWaitsForAllTransactions() throws {
        let guardState = AppTerminationSafety()
        try guardState.beginAccountSwitch()
        try guardState.beginAccountSwitch()
        XCTAssertFalse(guardState.requestTermination())
        XCTAssertThrowsError(try guardState.beginAccountSwitch())
        guardState.endAccountSwitch()
        XCTAssertTrue(guardState.hasActiveAccountSwitch)
        guardState.endAccountSwitch()
        XCTAssertFalse(guardState.hasActiveAccountSwitch)
        XCTAssertTrue(guardState.requestTermination())
    }

    func testNormalFinishedSwitchAllowsAnother() throws {
        let guardState = AppTerminationSafety()
        try guardState.beginAccountSwitch()
        guardState.endAccountSwitch()
        try guardState.beginAccountSwitch()
        guardState.endAccountSwitch()
        XCTAssertFalse(guardState.hasActiveAccountSwitch)
    }
}
