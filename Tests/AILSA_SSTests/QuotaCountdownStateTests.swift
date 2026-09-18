import XCTest
@testable import AILSA_SS

final class QuotaCountdownStateTests: XCTestCase {
    func testCountdownWaitsForEvidenceOfFirstRequestAfterReset() {
        let previous = UsageSnapshot(
            fetchedAt: 100,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 100, windowSeconds: 18_000, resetAt: 100),
            oneWeek: nil
        )
        let refreshed = UsageSnapshot(
            fetchedAt: 110,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 0, windowSeconds: 18_000, resetAt: 500),
            oneWeek: nil
        )

        let reconciled = QuotaCountdownState.reconcile(
            previous: previous,
            refreshed: refreshed,
            observedAt: 110
        )

        XCTAssertNil(reconciled.fiveHour?.countdownStartedAt)
        XCTAssertNil(QuotaCountdownState.effectiveResetAt(
            resetAt: reconciled.fiveHour?.resetAt,
            countdownStartedAt: reconciled.fiveHour?.countdownStartedAt,
            now: 110
        ))
    }

    func testReadOnlyQuotaDoesNotArmFromNonZeroUsage() {
        let refreshed = UsageSnapshot(
            fetchedAt: 210,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 2, windowSeconds: 18_000, resetAt: 500),
            oneWeek: nil
        )

        let reconciled = QuotaCountdownState.reconcile(
            previous: nil,
            refreshed: refreshed,
            observedAt: 210
        )

        XCTAssertNil(reconciled.fiveHour?.countdownStartedAt)
        XCTAssertNil(QuotaCountdownState.effectiveResetAt(
            resetAt: reconciled.fiveHour?.resetAt,
            countdownStartedAt: reconciled.fiveHour?.countdownStartedAt,
            now: 210
        ))
    }

    func testReadOnlyCheckClearsLegacyActivationWithoutUsageEvidence() {
        let usage = UsageSnapshot(
            fetchedAt: 300,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 0, windowSeconds: 18_000, resetAt: 500, countdownStartedAt: 200),
            oneWeek: UsageWindow(usedPercent: 0, windowSeconds: 604_800, resetAt: 700, countdownStartedAt: 200),
            quotaFamilies: [UsageQuotaFamily(
                id: "gemini",
                displayName: "Gemini",
                buckets: [UsageQuotaBucket(
                    id: "5h",
                    displayName: "5h",
                    usedPercent: 0,
                    resetAt: 500,
                    windowSeconds: 18_000,
                    resetDescription: nil,
                    isUsageKnown: true
                )]
            )]
        )

        let checked = QuotaCountdownState.reconcile(previous: usage, refreshed: usage, observedAt: 300)

        XCTAssertNil(checked.fiveHour?.countdownStartedAt)
        XCTAssertNil(checked.oneWeek?.countdownStartedAt)
        XCTAssertNil(checked.quotaFamilies?.first?.buckets.first?.countdownStartedAt)
    }
    func testReadOnlyRefreshClearsBothWindowMarkers() {
        let previous = UsageSnapshot(
            fetchedAt: 100,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 100, windowSeconds: 18_000, resetAt: 110, countdownStartedAt: 50),
            oneWeek: UsageWindow(usedPercent: 40, windowSeconds: 604_800, resetAt: 700, countdownStartedAt: 50)
        )
        let refreshed = UsageSnapshot(
            fetchedAt: 120,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 0, windowSeconds: 18_000, resetAt: 500),
            oneWeek: UsageWindow(usedPercent: 40, windowSeconds: 604_800, resetAt: 700)
        )
        let checked = QuotaCountdownState.reconcile(previous: previous, refreshed: refreshed, observedAt: 120)
        XCTAssertNil(checked.fiveHour?.countdownStartedAt)
        XCTAssertNil(checked.oneWeek?.countdownStartedAt)
    }

    func testExplicitRequestEvidenceStartsCountdown() {
        let usage = UsageSnapshot(
            fetchedAt: 210,
            planType: "pro",
            fiveHour: UsageWindow(usedPercent: 2, windowSeconds: 18_000, resetAt: 500),
            oneWeek: nil
        )
        let marked = QuotaCountdownState.markRequestObserved(usage, observedAt: 210)
        XCTAssertEqual(marked.fiveHour?.countdownStartedAt, 210)
        XCTAssertEqual(marked.fiveHour?.countdownStartEvidence, .requestObserved)
    }

}
