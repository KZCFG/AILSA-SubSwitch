import XCTest
@testable import AILSA_SS

final class QuotaHistoryPeriodTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    func testThirtyDayWeeklyGroupingKeepsFourPeriodsAndCoversRange() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        let periods = QuotaHistoryPeriodBuilder.build(start: start, end: end, grouping: .week, calendar: calendar)

        XCTAssertEqual(periods.count, 4)
        XCTAssertEqual(periods.first?.start, start)
        XCTAssertEqual(periods.last?.end, end)
        XCTAssertEqual(periods.map { calendar.dateComponents([.day], from: $0.start, to: $0.end).day }, [7, 7, 8, 8])
        XCTAssertEqual(periods.map(\.anchor), periods.map { calendar.date(byAdding: .day, value: -1, to: $0.end)! })
    }

    func testDailyGroupingProducesOnePeriodPerDay() {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 25))!
        let periods = QuotaHistoryPeriodBuilder.build(start: start, end: end, grouping: .day, calendar: calendar)

        XCTAssertEqual(periods.count, 7)
        XCTAssertEqual(periods.map(\.anchor), (0..<7).map { calendar.date(byAdding: .day, value: $0, to: start)! })
        XCTAssertTrue(periods.allSatisfy { calendar.dateComponents([.day], from: $0.start, to: $0.end).day == 1 })
    }
}
