import XCTest
@testable import AILSA_SS

final class AntigravityObservedSelectionTests: XCTestCase {
    private let now: Int64 = 1_800_000_000
    private func account(_ id: String, email: String? = nil) -> StoredAccount {
        StoredAccount(id: id, label: id, email: email ?? "\(id)@example.invalid", accountID: id,
            planType: "pro", teamName: nil, teamAlias: nil,
            authJSON: .object(["access_token": .string("synthetic-\(id)")]),
            addedAt: 1, updatedAt: 1, usage: nil, usageError: nil, provider: .antigravity)
    }
    private func native(_ email: String = "b@example.invalid") -> AntigravityNativeUsageResult {
        AntigravityNativeUsageResult(email: email, planType: "pro",
            usage: UsageSnapshot(fetchedAt: now, planType: "pro", fiveHour: nil, oneWeek: nil, credits: nil,
                quotaFamilies: [UsageQuotaFamily(id: "gemini", displayName: "Gemini", buckets: [
                    UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: 25, resetAt: nil,
                        windowSeconds: 18_000, resetDescription: nil, isUsageKnown: true)
                ])], source: .antigravityNativeSummary, sourceAccountMatched: true))
    }
    private func baseline() -> AccountsStore {
        AccountsStore(accounts: [account("a"), account("b")], currentAntigravityAccountID: "a")
    }
    func testVerifiedExternalSwitchUpdatesOnlyTheCurrentMarker() {
        let before = baseline()
        var after = before
        XCTAssertTrue(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(" B@EXAMPLE.INVALID "), now: now))
        XCTAssertEqual(after.currentAntigravityAccountID, "b")
        XCTAssertEqual(after.accounts, before.accounts)
        XCTAssertEqual(after.currentAccountID, before.currentAccountID)
        XCTAssertFalse(after.accountSummaries()[0].isCurrent)
        XCTAssertTrue(after.accountSummaries()[1].isCurrent)
    }
    func testUnknownAndAmbiguousNativeIdentitiesClearTheOldMarker() {
        for email in ["unknown@example.invalid", "b@example.invalid"] {
            var before = baseline()
            if email == "b@example.invalid" { before.accounts.append(account("duplicate", email: email)) }
            var after = before
            XCTAssertTrue(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(email), now: now))
            XCTAssertNil(after.currentAntigravityAccountID)
            XCTAssertEqual(after.accounts, before.accounts)
        }
    }
    func testUnverifiedStalePartialAndRemoteEvidenceCannotChangeSelection() {
        let before = baseline()
        var unverified = native(); unverified.usage.sourceAccountMatched = false
        var stale = native(); stale.usage.fetchedAt = now - 901
        var partial = native(); partial.usage.quotaFamilies?[0].buckets[0].isUsageKnown = false
        var remote = native(); remote.usage.source = .antigravityRemoteQuota
        for evidence in [unverified, stale, partial, remote, native("")] {
            var after = before
            XCTAssertFalse(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: evidence, now: now))
            XCTAssertEqual(after, before)
        }
    }
    func testPendingSwitchIsNeverPromotedByExternalObservation() {
        var before = baseline(); before.pendingAntigravityAccountID = "a"
        var after = before
        XCTAssertFalse(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(), now: now))
        XCTAssertEqual(after, before)
    }
    func testConcurrentSelectionOrPendingChangeWins() {
        let before = baseline()
        var switched = before; switched.currentAntigravityAccountID = nil
        var pending = before; pending.pendingAntigravityAccountID = "b"
        for expected in [switched, pending] {
            var after = expected
            XCTAssertFalse(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(), now: now))
            XCTAssertEqual(after, expected)
        }
    }
    func testConcurrentReauthenticationOrAccountRemovalWins() {
        let before = baseline()
        var reauthenticated = before; reauthenticated.accounts[1].authJSON = .object(["access_token": .string("new-synthetic")])
        var currentReauthenticated = before; currentReauthenticated.accounts[0].authJSON = .object(["access_token": .string("new-current-synthetic")])
        var removed = before; removed.accounts.removeLast()
        for expected in [reauthenticated, currentReauthenticated, removed] {
            var after = expected
            XCTAssertFalse(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(), now: now))
            XCTAssertEqual(after, expected)
        }
    }
    func testAlreadyMatchedSessionDoesNotRequestAStoreWrite() {
        var before = baseline(); before.currentAntigravityAccountID = "b"
        var after = before
        XCTAssertFalse(AntigravityObservedSelection.reconcile(store: &after, baseline: before, native: native(), now: now))
        XCTAssertEqual(after, before)
    }
}
