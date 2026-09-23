import XCTest
@testable import AILSA_SS

final class QuotaChartMetricTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var start: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23))!
    }
    private func bucket(tokens: Int, pico: Int64?) -> QuotaBucket {
        var value = QuotaAggregate()
        value.tokens = UsageTokenBreakdown(input: tokens, cachedInput: 0, cacheWriteInput: 0, output: 0, reasoningOutput: 0)
        value.reported = 1
        value.requests = 1
        value.reference.add(pico)
        // These are separate pricing bases, never added to reference USD.
        value.confirmed.add(900_000_000_000_000)
        value.metered.add(800_000_000_000_000)
        var bucket = QuotaBucket()
        bucket.add(value, key: QuotaModelKey(provider: "Demo", model: "test"))
        return bucket
    }

    func testIntradayUSDUsesSameIntervalAndPricingBasisAsHoveredSummary() {
        let minutes = [
            start.addingTimeInterval(60): bucket(tokens: 1_000, pico: 250_000_000_000),
            start.addingTimeInterval(240): bucket(tokens: 3_000, pico: 750_000_000_000),
            start.addingTimeInterval(300): bucket(tokens: 100, pico: 2_000_000_000_000),
            start.addingTimeInterval(-60): bucket(tokens: 9_000, pico: 99_000_000_000_000)
        ]
        let now = start.addingTimeInterval(360)
        let snapshot = QuotaDashboardSnapshot(scannedAt: now, days: [:], all: QuotaAggregate(), source: "Demo", pricingSources: [], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0, minuteBuckets: minutes)
        let usd = QuotaIntradaySeries.points(minutes: minutes, now: now, intervalMinutes: 5, metric: .apiEquivalentCost, calendar: calendar)
        let tokens = QuotaIntradaySeries.points(minutes: minutes, now: now, intervalMinutes: 5, metric: .tokens, calendar: calendar)
        XCTAssertEqual(usd.map(\.value), [1.0, 2.0])
        XCTAssertEqual(tokens.map(\.value), [4_000.0, 100.0])
        for point in usd {
            XCTAssertEqual(point.value, snapshot.intradayBucket(from: point.date, intervalMinutes: 5).total.reference.usd)
        }
    }

    func testUnpricedIntervalsRemainUnknownButEmptyAndFreeIntervalsAreZero() {
        let minutes = [
            start: bucket(tokens: 200, pico: 500_000_000_000),
            start.addingTimeInterval(300): bucket(tokens: 100, pico: nil),
            start.addingTimeInterval(900): bucket(tokens: 500, pico: 0)
        ]
        let points = QuotaIntradaySeries.points(minutes: minutes, now: start.addingTimeInterval(960), intervalMinutes: 5, metric: .apiEquivalentCost, calendar: calendar)
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points.map(\.value), [0.5, nil, 0.0, 0.0])
        let unpriced = [start: bucket(tokens: 100, pico: nil)]
        XCTAssertTrue(QuotaIntradaySeries.points(minutes: unpriced, now: start, intervalMinutes: 5, metric: .apiEquivalentCost, calendar: calendar).isEmpty)
        XCTAssertEqual(QuotaIntradaySeries.points(minutes: unpriced, now: start, intervalMinutes: 5, metric: .tokens, calendar: calendar).first?.value, 100)
    }

    func testHistoricalDailyAndWeeklyUSDMatchSummaryWithoutMixingPricingBases() {
        let days = (0..<30).reduce(into: [Date: QuotaBucket]()) { result, index in
            result[calendar.date(byAdding: .day, value: index, to: start)!] = bucket(tokens: 1_000, pico: Int64(index + 1) * 1_000_000_000_000)
        }
        let end = calendar.date(byAdding: .day, value: 30, to: start)!
        let snapshot = QuotaDashboardSnapshot(scannedAt: end, days: days, all: QuotaAggregate(), source: "Demo", pricingSources: [], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0)
        for grouping in QuotaHistoryGrouping.allCases {
            let periods = QuotaHistoryPeriodBuilder.build(start: start, end: end, grouping: grouping, calendar: calendar)
            let totals = periods.map { snapshot.bucket(from: $0.start, until: $0.end).total }
            XCTAssertEqual(totals.compactMap { QuotaChartMetric.apiEquivalentCost.value(in: $0) }.reduce(0, +), 465)
            XCTAssertEqual(totals.compactMap { QuotaChartMetric.tokens.value(in: $0) }.reduce(0, +), 30_000)
        }
    }

    func testUnknownAndOverflowingAmountsStayUnavailable() {
        XCTAssertNil(QuotaChartMetric.apiEquivalentCost.value(in: QuotaAggregate()))
        XCTAssertNil(QuotaChartMetric.tokens.value(in: QuotaAggregate()))
        var total = bucket(tokens: 100, pico: Int64.max).total
        total.reference.add(1)
        XCTAssertNil(QuotaChartMetric.apiEquivalentCost.value(in: total))
        XCTAssertEqual(QuotaChartMetric.tokens.value(in: total), 100)
    }
}
