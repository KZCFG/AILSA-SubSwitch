import XCTest
@testable import AILSA_SS

final class QuotaManagementPageModelTimeRangeTests: XCTestCase {
    @MainActor
    func testSelectingUsageRangesReloadsEveryProviderInsideCacheTTL() async {
        let service = RefreshProbeUsageService()
        let now = Date(timeIntervalSince1970: 2_000)
        let model = QuotaManagementPageModel(usageService: service, dateProvider: { now })
        for provider in QuotaManagementProvider.allCases {
            await model.loadDashboard(for: provider)
            await model.loadDashboard(for: provider)
            let cachedCalls = await service.calls(for: provider)
            XCTAssertEqual(cachedCalls, 1)
            // Today, 7 days, 30 days and re-clicking the selected range all
            // use the same explicit boundary, without a full Cursor re-page.
            for _ in [1, 7, 30, 30] { await model.refreshOnRangeSelection(for: provider) }
            let freshCalls = await service.calls(for: provider)
            XCTAssertEqual(freshCalls, 5)
            XCTAssertEqual(model.dashboards[provider]?.scannedAt, now)
        }
    }

    @MainActor
    func testRepeatedWindowOpenReloadsLoadedProvidersWithoutManualButton() async {
        let service = RefreshProbeUsageService()
        let now = Date(timeIntervalSince1970: 2_000)
        let model = QuotaManagementPageModel(usageService: service, dateProvider: { now })
        for provider in QuotaManagementProvider.allCases { await model.loadDashboard(for: provider) }
        await model.refreshOnWindowOpen()
        await model.refreshOnWindowOpen()
        for provider in QuotaManagementProvider.allCases {
            let calls = await service.calls(for: provider)
            XCTAssertEqual(calls, 3)
        }
    }

    @MainActor
    func testFailedRefreshKeepsSnapshotAndItsOriginalUpdateTime() async {
        let service = RefreshProbeUsageService()
        var now = Date(timeIntervalSince1970: 2_000)
        let model = QuotaManagementPageModel(usageService: service, dateProvider: { now })
        await model.loadDashboard(for: .codex)
        await service.failNextLoad()
        now = now.addingTimeInterval(10)
        await model.refreshOnRangeSelection(for: .codex)
        XCTAssertEqual(model.dashboards[.codex]?.scannedAt, Date(timeIntervalSince1970: 2_000))
        XCTAssertNotNil(model.errorsByProvider[.codex])
        XCTAssertFalse(model.loadingProviders.contains(.codex))
        await model.refreshOnRangeSelection(for: .codex)
        XCTAssertEqual(model.dashboards[.codex]?.scannedAt, now)
        XCTAssertNil(model.errorsByProvider[.codex])
    }

    @MainActor
    func testConcurrentRangeAndWindowRefreshCoalesce() async {
        let service = RefreshProbeUsageService(delay: .milliseconds(60))
        let model = QuotaManagementPageModel(usageService: service)
        async let range: Void = model.refreshOnRangeSelection(for: .codex)
        async let window: Void = model.refreshOnWindowOpen(provider: .codex)
        _ = await (range, window)
        let calls = await service.calls(for: .codex)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testFinalChartPageAndSelectedDayStayInsideRollingThirtyDayWindow() {
        let fixedNow = ISO8601DateFormatter().date(from: "2026-09-15T12:00:00Z")!
        let model = QuotaManagementPageModel(
            usageService: EmptyQuotaManagementUsageService(),
            dateProvider: { fixedNow }
        )
        let calendar = Calendar.current
        let window = model.historyWindow

        XCTAssertEqual(model.chartDates.count, QuotaManagementPageModel.chartDaysPerPage)
        XCTAssertTrue(model.chartDates.allSatisfy(window.contains))

        for _ in 0..<4 {
            XCTAssertTrue(model.canShowOlderChartPage)
            model.showOlderChartPage()
        }

        let finalPageDates = model.chartDates
        XCTAssertEqual(finalPageDates.count, 2)
        XCTAssertEqual(finalPageDates.first, window.start)
        XCTAssertEqual(
            finalPageDates.last,
            calendar.date(byAdding: .day, value: 1, to: window.start)
        )
        XCTAssertTrue(finalPageDates.allSatisfy(window.contains))
        XCTAssertFalse(model.canShowOlderChartPage)

        let originalSelection = model.selectedDay
        model.selectDay(calendar.date(byAdding: .day, value: -1, to: window.start)!)
        XCTAssertEqual(model.selectedDay, originalSelection)

        model.selectDay(window.start)
        XCTAssertEqual(model.selectedDay, window.start)
    }
}

private actor RefreshProbeUsageService: QuotaManagementUsageServiceProtocol {
    private var counts: [QuotaManagementProvider: Int] = [:]
    private var failNext = false
    let delay: Duration
    init(delay: Duration = .zero) { self.delay = delay }
    func calls(for provider: QuotaManagementProvider) -> Int { counts[provider, default: 0] }
    func failNextLoad() { failNext = true }
    func loadDashboard(for provider: QuotaManagementProvider, now: Date) async throws -> QuotaDashboardSnapshot {
        counts[provider, default: 0] += 1
        try await Task.sleep(for: delay)
        if failNext { failNext = false; throw CursorUsageError.unavailable(504) }
        return QuotaDashboardSnapshot(scannedAt: now, days: [:], all: QuotaAggregate(), source: "Fixture",
            pricingSources: [], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0)
    }
    func loadData(for provider: QuotaManagementProvider, historyDays: Int, now: Date) async throws -> QuotaManagementData {
        .codex(.empty)
    }
}

@MainActor
final class CursorAccountsRefreshTests: XCTestCase {
    func testRepeatedPresentationRefreshesCachedAccountAndPreservesIdentity() async {
        var count = 0
        var notifications: [String] = []
        let model = CursorAccountsModel(loadProfiles: { [] }, hasRecovery: { false }, loadAccount: {
            count += 1
            return self.account(at: count)
        }, onAccountChanged: { notifications.append($0) })
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(count, 2)
        XCTAssertEqual(model.account?.scannedAt, Date(timeIntervalSince1970: 2))
        XCTAssertEqual(notifications, ["fixture"])
    }

    func testFailedCursorRefreshRetainsLastQuotaAndUpdateTime() async {
        var fail = false
        let model = CursorAccountsModel(loadProfiles: { [] }, hasRecovery: { false }, loadAccount: {
            if fail { throw CursorUsageError.unavailable(504) }
            return self.account(at: 1)
        }, onAccountChanged: { _ in })
        await model.refresh()
        fail = true
        await model.refresh()
        XCTAssertEqual(model.account?.scannedAt, Date(timeIntervalSince1970: 1))
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.loading)
    }

    func testConcurrentCursorPresentationCallbacksOnlyQueryOnce() async {
        var count = 0
        let model = CursorAccountsModel(loadProfiles: { [] }, hasRecovery: { false }, loadAccount: {
            count += 1
            try await Task.sleep(for: .milliseconds(60))
            return self.account(at: 1)
        }, onAccountChanged: { _ in })
        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        _ = await (first, second)
        XCTAssertEqual(count, 1)
        XCTAssertFalse(model.loading)
    }

    private func account(at seconds: Int) -> CursorAccountUsage {
        CursorAccountUsage(id: "fixture", email: "fixture@example.com", plan: "pro",
            pools: [CursorQuotaPool(id: "total", usedPercent: Double(seconds), reset: nil)],
            onDemandUSD: 0, scannedAt: Date(timeIntervalSince1970: Double(seconds)))
    }
}

private struct EmptyQuotaManagementUsageService: QuotaManagementUsageServiceProtocol {
    func loadData(
        for provider: QuotaManagementProvider,
        historyDays: Int,
        now: Date
    ) async throws -> QuotaManagementData {
        .codex(.empty)
    }
}
