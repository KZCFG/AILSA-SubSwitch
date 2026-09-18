import XCTest
@testable import AILSA_SS

final class AccountPlanLabelTests: XCTestCase {
    func testCodexProAndProLiteDisplayLabels() {
        XCTAssertEqual(AccountPlanLabel.normalized(from: "pro"), "PRO 20X")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "prolite"), "PRO 5X")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "pro_lite"), "PRO 5X")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "team"), "TEAM")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "plus"), "PLUS")
        XCTAssertEqual(AccountPlanLabel.normalized(from: nil), "TEAM")
    }

    func testAntigravityPlanLabelsStaySeparateFromCodex() {
        XCTAssertEqual(AccountPlanLabel.normalized(from: "pro", provider: .antigravity), "GEMINI PRO")
        XCTAssertEqual(AccountPlanLabel.normalized(from: nil, provider: .antigravity), "GEMINI")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "ultra", provider: .antigravity), "ULTRA")
    }

    func testUsagePlanTypeWinsOverStoredPlanType() {
        XCTAssertEqual(
            AccountPlanLabel.normalized(usagePlanType: "prolite", storedPlanType: "team"),
            "PRO 5X"
        )
        XCTAssertEqual(
            AccountPlanLabel.normalized(usagePlanType: "pro", storedPlanType: "plus"),
            "PRO 20X"
        )
        XCTAssertEqual(
            AccountPlanLabel.normalized(usagePlanType: "team", storedPlanType: "prolite"),
            "PRO 5X"
        )
    }
}
