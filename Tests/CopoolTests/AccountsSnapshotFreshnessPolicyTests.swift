import XCTest
@testable import Copool

final class AccountsSnapshotFreshnessPolicyTests: XCTestCase {
    func testShouldSkipRemoteUsageRefreshWhenRemoteSnapshotIsFresh() {
        let policy = AccountsSnapshotFreshnessPolicy(remoteSnapshotFreshnessWindowSeconds: 30)

        XCTAssertFalse(
            policy.shouldRefreshUsage(
                forceRefresh: false,
                remoteSyncedAt: 1_000,
                now: 1_029
            )
        )
    }

    func testShouldRefreshUsageWhenRemoteSnapshotIsStale() {
        let policy = AccountsSnapshotFreshnessPolicy(remoteSnapshotFreshnessWindowSeconds: 30)

        XCTAssertTrue(
            policy.shouldRefreshUsage(
                forceRefresh: false,
                remoteSyncedAt: 1_000,
                now: 1_031
            )
        )
    }

    func testForceRefreshAlwaysWins() {
        let policy = AccountsSnapshotFreshnessPolicy(remoteSnapshotFreshnessWindowSeconds: 30)

        XCTAssertTrue(
            policy.shouldRefreshUsage(
                forceRefresh: true,
                remoteSyncedAt: 1_029,
                now: 1_030
            )
        )
    }

    func testRemoteSnapshotFreshnessWindowIsInclusive() {
        let policy = AccountsSnapshotFreshnessPolicy(remoteSnapshotFreshnessWindowSeconds: 30)

        XCTAssertTrue(
            policy.isRemoteSnapshotFresh(
                remoteSyncedAt: 1_000,
                now: 1_030
            )
        )
    }
}
