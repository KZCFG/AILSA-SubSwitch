import Foundation
import XCTest
@testable import AILSA_SS

final class UsageReportTests: XCTestCase {
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private func value(_ count: Int, price: Int64? = nil) -> QuotaAggregate {
        var v = QuotaAggregate(); v.reported = 1; v.requests = 1
        v.tokens = UsageTokenBreakdown(input: count, cachedInput: 0, cacheWriteInput: 0, output: 0, reasoningOutput: 0)
        v.reference.add(price); return v
    }
    private func snapshot(days: [Date: QuotaBucket], minutes: [Date: QuotaBucket] = [:]) -> QuotaDashboardSnapshot {
        QuotaDashboardSnapshot(scannedAt: date("2026-09-28T00:00:00Z"), days: days, all: QuotaAggregate(), source: "OpenCodex", pricingSources: [], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0, minuteBuckets: minutes)
    }
    func testRollingRangesAndSafeFilenames() {
        let end = date("2026-09-27T12:34:00Z")
        let weekly = UsageReportRequest(provider: .codex, period: .weekly, endingOn: end)
        XCTAssertEqual(weekly.interval(calendar: calendar).start, date("2026-09-21T00:00:00Z"))
        XCTAssertEqual(weekly.interval(calendar: calendar).end, date("2026-09-28T00:00:00Z"))
        XCTAssertEqual(weekly.filename(calendar: calendar), "AILSA-SubSwitch-Codex-weekly-2026-09-21_2026-09-27.png")
        let month = UsageReportRequest(provider: .cursor, period: .monthly, endingOn: end)
        XCTAssertEqual(month.interval(calendar: calendar).start, date("2026-08-29T00:00:00Z"))
    }
    func testDailyRangeUsesCalendarAcrossDST() {
        var c = calendar; c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let request = UsageReportRequest(provider: .codex, period: .daily, endingOn: date("2026-03-08T12:00:00Z"))
        XCTAssertEqual(request.interval(calendar: c).duration, 23 * 3600)
        let report = UsageReport.build(snapshot: snapshot(days: [:]), request: request, now: date("2026-03-09T12:00:00Z"), calendar: c)
        XCTAssertEqual(report.points.count, 46)
    }
    func testWindowExcludesBothOutsideBoundariesAndMergesGrokFamily() {
        let start = date("2026-09-21T00:00:00Z"), last = date("2026-09-27T00:00:00Z")
        var first = QuotaBucket(), final = QuotaBucket(), outside = QuotaBucket()
        first.add(value(100, price: 1_000), key: .init(provider: "xai", model: "grok-4.7-build-fast"))
        final.add(value(300, price: 3_000), key: .init(provider: "xai", model: "grok-4.7"))
        outside.add(value(999_999, price: 999_999), key: .init(provider: "openai", model: "gpt-6-sol"))
        let data = snapshot(days: [start:first,last:final,date("2026-09-20T00:00:00Z"):outside,date("2026-09-28T00:00:00Z"):outside])
        let request = UsageReportRequest(provider: .codex, period: .weekly, endingOn: last)
        let report = UsageReport.build(snapshot: data, request: request, now: date("2026-09-29T00:00:00Z"), calendar: calendar)
        XCTAssertEqual(report.total.tokens.total, 400)
        XCTAssertEqual(report.total.reference.pico, 4_000)
        XCTAssertEqual(report.rows.count, 1)
        XCTAssertEqual(report.rows.first?.name, "Grok 4.7")
        XCTAssertEqual(report.rows.first?.includesGrokBuildFast, true)
        XCTAssertEqual(report.points.reduce(0) { $0 + $1.value.tokens.total }, 400)
        XCTAssertFalse(report.partialPeriod)
    }
    func testDailyMinuteTotalsRetainUnknownPriceAndFullCanvas() {
        let day = date("2026-09-27T00:00:00Z")
        var a = QuotaBucket(), b = QuotaBucket(), sum = QuotaBucket()
        a.add(value(10), key: .init(provider: "openai", model: "unknown"))
        b.add(value(20, price: 0), key: .init(provider: "openai", model: "known"))
        sum.merge(a); sum.merge(b)
        let data = snapshot(days: [day:sum], minutes: [day:a,day.addingTimeInterval(86340):b])
        let request = UsageReportRequest(provider: .codex, period: .daily, endingOn: day)
        let report = UsageReport.build(snapshot: data, request: request, now: day.addingTimeInterval(86400), calendar: calendar)
        XCTAssertEqual(report.points.count, 48)
        XCTAssertEqual(report.points.reduce(0) { $0 + $1.value.tokens.total }, 30)
        XCTAssertEqual(report.missingPriceRecords, 1)
        XCTAssertNil(report.points.first?.value.reference.usd)
        XCTAssertEqual(report.points.last?.value.reference.usd, 0)
    }
    func testCurrentDayIsLabeledPartialAndDoesNotInventFuturePoints() {
        let day = date("2026-09-27T00:00:00Z")
        let report = UsageReport.build(snapshot: snapshot(days: [:]), request: .init(provider: .codex, period: .daily, endingOn: day), now: day.addingTimeInterval(3600), calendar: calendar)
        XCTAssertTrue(report.partialPeriod)
        XCTAssertEqual(report.points.count, 3)
        XCTAssertTrue(report.rows.isEmpty)
    }

    @MainActor func testPageModelLoadsHistoricalMinutesWithoutReplacingDashboard() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let ledger = root.appendingPathComponent("usage.jsonl")
        let rows = """
        {"requestId":"yesterday","timestamp":"2026-09-27T10:00:00Z","provider":"openai","resolvedModel":"gpt-6-sol","usageStatus":"reported","usage":{"inputTokens":100,"outputTokens":10,"cachedInputTokens":0}}
        {"requestId":"today","timestamp":"2026-09-28T10:00:00Z","provider":"openai","resolvedModel":"gpt-6-sol","usageStatus":"reported","usage":{"inputTokens":900,"outputTokens":90,"cachedInputTokens":0}}

        """
        try Data(rows.utf8).write(to: ledger)
        let absent = root.appendingPathComponent("absent")
        let paths = QuotaManagementDataPaths(codexSessionsDirectory: absent,
            codexArchivedSessionsDirectory: absent, codexBarPricingCatalogURL: absent,
            opencodexUsageLedgerURL: ledger, antigravityQuotaHistoryURL: absent, antigravityInfoPlistURL: absent)
        let model = QuotaManagementPageModel(usageService: LocalQuotaManagementUsageService(paths: paths),
                                            dateProvider: { self.date("2026-09-28T12:00:00Z") })
        let report = try await model.makeUsageReport(.init(provider: .codex, period: .daily, endingOn: date("2026-09-27T12:00:00Z")))
        XCTAssertEqual(report.total.tokens.total, 110)
        XCTAssertEqual(report.points.reduce(0) { $0 + $1.value.tokens.total }, 110)
        XCTAssertTrue(model.dashboards.isEmpty)
    }
}
