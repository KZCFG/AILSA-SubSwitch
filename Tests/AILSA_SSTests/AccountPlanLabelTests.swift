import Foundation
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

final class AntigravityPlanEvidenceTests: XCTestCase {
    func testExplicitPaidMetadataWinsForNativeAndOAuthSources() throws {
        for (paid, expected) in [(#"{"id":"standard-tier"}"#, "paid"), (#"{"name":"Google AI Ultra"}"#, "ultra"), (#"{"preferredName":"Google AI Pro"}"#, "pro")] {
            let payload = try JSONDecoder().decode(JSONValue.self, from: Data((#"{"paidTier":"# + paid + #", "userTier":{"name":"Free"}, "currentTier":{"id":"free-tier"}}"#).utf8))
            XCTAssertEqual(AntigravityUsageService.planType(fromCodeAssist: payload), expected)
            XCTAssertEqual(AntigravityNativeUsageService.planType(fromUserStatus: payload), expected)
        }
        XCTAssertEqual(AccountPlanLabel.normalized(from: "paid", provider: .antigravity), "PAID")
    }

    func testStoredFreeCannotOverrideMeasuredQuotaButUnknownAndMismatchedCanNotPromote() throws {
        var account = try accountWithMeasuredQuota()
        XCTAssertNil(account.usage?.planType)
        XCTAssertEqual(account.normalizedPlanLabel, "GEMINI")
        account.usage?.sourceAccountMatched = false
        XCTAssertEqual(account.normalizedPlanLabel, "FREE")
        account.usage?.sourceAccountMatched = true
        account.usage?.quotaFamilies?[0].buckets[0].isUsageKnown = false
        XCTAssertEqual(account.normalizedPlanLabel, "FREE")
        account.usage?.quotaFamilies?[0].buckets[0].isUsageKnown = true
        account.usage?.quotaFamilies?[0].buckets[0].usedPercent = .nan
        XCTAssertEqual(account.normalizedPlanLabel, "FREE")
    }

    func testWidgetPreservesMeasuredResetWithRequestEvidenceOnly() throws {
        var account = try accountWithMeasuredQuota()
        account.usage?.quotaFamilies?[0].buckets[0].countdownStartedAt = 100
        account.usage?.quotaFamilies?[0].buckets[0].countdownStartEvidence = .requestObserved
        func widget() -> AccountsWidgetSnapshot {
            AccountsWidgetSnapshotBuilder().build(accounts: [account], usageProgressDisplayMode: .used,
                locale: Locale(identifier: "en_US"), timeZone: TimeZone(secondsFromGMT: 0)!, now: Date(timeIntervalSince1970: 100))
        }
        XCTAssertEqual(widget().currentCard?.planLabel, "GEMINI")
        XCTAssertEqual(widget().currentCard?.fiveHour.resetText, "26/3/20 15:23:45")
        account.usage?.quotaFamilies?[0].buckets[0].countdownStartedAt = nil
        XCTAssertNotEqual(widget().currentCard?.fiveHour.resetText, "26/3/20 15:23:45")
    }

    private func accountWithMeasuredQuota() throws -> AccountSummary {
        let payload = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"gemini-5h","window":"5h","remainingFraction":0.5,"resetTime":"2026-03-20T15:23:45Z"}]}]}"#.utf8))
        let usage = try AntigravityNativeUsageService.usageSnapshot(fromQuotaSummary: payload, fetchedAt: 100,
            planType: "free", source: .antigravityRemoteQuota, sourceAccountMatched: true)
        return AccountSummary(id: "test", label: "test", email: "test@example.com", accountID: "test",
            planType: "free", teamName: nil, teamAlias: nil, addedAt: 100, updatedAt: 100,
            usage: usage, usageError: nil, isCurrent: true, provider: .antigravity)
    }
}
