import XCTest
@testable import AILSA_SS

final class AccountSummaryPresentationTests: XCTestCase {
    func testNormalizedPlanLabelFromRawPlanTypeFallsBackToTeam() {
        XCTAssertEqual(AccountPlanLabel.normalized(from: " business "), "BUSINESS")
        XCTAssertEqual(AccountPlanLabel.normalized(from: nil), "TEAM")
    }

    func testWorkspaceDisplayNameNormalizationTrimsWhitespaceAndDropsEmptyValues() {
        XCTAssertEqual(WorkspaceDisplayName.normalized(from: "  workspace-a  "), "workspace-a")
        XCTAssertNil(WorkspaceDisplayName.normalized(from: " \n "))
    }

    func testNormalizedPlanLabelPrefersLatestUsagePlanType() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Primary",
            email: "dev@example.com",
            accountID: "account-1",
            planType: "free",
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: 1,
                planType: "plus",
                fiveHour: nil,
                oneWeek: nil,
                credits: nil
            ),
            usageError: nil,
            isCurrent: false
        )

        XCTAssertEqual(account.normalizedPlanLabel, "PLUS")
    }

    func testWorkspaceTagIsShownForBusinessPlan() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Business",
            email: nil,
            accountID: "account-1",
            planType: "business",
            teamName: "workspace-a",
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: nil,
            usageError: nil,
            isCurrent: false
        )

        XCTAssertEqual(account.normalizedPlanLabel, "BUSINESS")
        XCTAssertTrue(account.shouldDisplayWorkspaceTag)
        XCTAssertEqual(account.displayTeamName, "workspace-a")
    }

    func testWorkspaceTagStaysHiddenForProPlan() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Pro",
            email: nil,
            accountID: "account-1",
            planType: "pro",
            teamName: "workspace-a",
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: nil,
            usageError: nil,
            isCurrent: false
        )

        XCTAssertEqual(account.normalizedPlanLabel, "PRO 20X")
        XCTAssertFalse(account.shouldDisplayWorkspaceTag)
    }

    func testProLiteStaysPro5XWhenUsageReportsTeam() {
        XCTAssertEqual(AccountPlanLabel.normalized(from: "prolite"), "PRO 5X")
        XCTAssertEqual(
            AccountPlanLabel.normalized(usagePlanType: "team", storedPlanType: "prolite"),
            "PRO 5X"
        )
        XCTAssertEqual(
            AccountPlanLabel.normalized(usagePlanType: "team", storedPlanType: "pro"),
            "PRO 20X"
        )
    }
}
