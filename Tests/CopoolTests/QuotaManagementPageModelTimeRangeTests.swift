import XCTest
@testable import Copool

final class QuotaManagementPageModelTimeRangeTests: XCTestCase {
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

private struct EmptyQuotaManagementUsageService: QuotaManagementUsageServiceProtocol {
    func loadData(
        for provider: QuotaManagementProvider,
        historyDays: Int,
        now: Date
    ) async throws -> QuotaManagementData {
        .codex(.empty)
    }
}
