import Foundation

enum UsageReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly, sixtyDays = "60-days", ninetyDays = "90-days", yearly
    var id: String { rawValue }
    var days: Int {
        switch self { case .daily: 1; case .weekly: 7; case .monthly: 30; case .sixtyDays: 60; case .ninetyDays: 90; case .yearly: 365 }
    }
    var chartGroupDays: Int { days > 90 ? 7 : 1 }
    var title: String {
        switch self {
        case .daily: return UsageReportText.text("日报", "Daily")
        case .weekly: return UsageReportText.text("周报 · 7 天", "Weekly · 7 days")
        case .monthly: return UsageReportText.text("月报 · 30 天", "Monthly · 30 days")
        case .sixtyDays: return UsageReportText.text("60 天", "60 days")
        case .ninetyDays: return UsageReportText.text("90 天", "90 days")
        case .yearly: return UsageReportText.text("一年 · 365 天", "Year · 365 days")
        }
    }
}

enum UsageReportText {
    static func text(_ chinese: String, _ english: String) -> String {
        L10n.currentLocale.identifier.hasPrefix("zh") ? chinese : english
    }
}

struct UsageReportRequest: Equatable, Sendable {
    let provider: QuotaManagementProvider
    let period: UsageReportPeriod
    let endingOn: Date

    func interval(calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: endingOn)
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: day)!
        let end = calendar.date(byAdding: .day, value: 1, to: day)!
        return DateInterval(start: start, end: end)
    }

    var providerName: String {
        switch provider { case .codex: "Codex"; case .cursor: "Cursor"; case .antigravity: "Antigravity"; case .claude: "Claude" }
    }
    func filename(calendar: Calendar = .current) -> String {
        let range = interval(calendar: calendar)
        let last = calendar.startOfDay(for: endingOn)
        let end = QuotaDashboardSnapshot.isoDay(last, calendar: calendar)
        let dates = period == .daily ? end : QuotaDashboardSnapshot.isoDay(range.start, calendar: calendar) + "_" + end
        return "AILSA-SubSwitch-\(providerName)-\(period.rawValue)-\(dates).png"
    }
}

enum UsageReportPreferences {
    static let hideUnpricedModelsKey = "ass.usageReport.hideUnpricedModels"
}

/// Only aggregates enter the renderer. No account labels, request IDs,
/// conversation text, credentials, local paths or routing details are exported.
struct UsageReport: Sendable {
    struct Row: Identifiable, Sendable {
        let name: String
        let value: QuotaAggregate
        let includesGrokBuildFast: Bool
        var id: String { name }
    }
    struct Point: Identifiable, Sendable {
        let date: Date
        let value: QuotaAggregate
        var id: Date { date }
    }
    let request: UsageReportRequest
    let interval: DateInterval
    let generatedAt: Date
    let total: QuotaAggregate
    let rows: [Row]
    let points: [Point]
    let partialPeriod: Bool
    let missingPriceRecords: Int

    /// Filters exported model details only. Totals and trends keep every record.
    /// An explicit zero-dollar amount is priced and remains visible.
    func visibleRows(hideUnpricedModels: Bool) -> [Row] {
        hideUnpricedModels ? rows.filter { $0.value.reference.usd != nil } : rows
    }

    static func build(snapshot: QuotaDashboardSnapshot, request: UsageReportRequest,
                      now: Date = Date(), calendar: Calendar = .current) -> Self {
        let interval = request.interval(calendar: calendar)
        let bucket = snapshot.bucket(from: interval.start, until: interval.end)
        var families: [String: QuotaAggregate] = [:]
        var fastFamilies = Set<String>()
        for (key, value) in bucket.models where value.reported > 0 || value.reference.count > 0 {
            let name = key.familyKey.model.isEmpty ? UsageReportText.text("未知模型", "Unknown model") : key.familyKey.model
            families[name, default: QuotaAggregate()].merge(value)
            if key.model.lowercased() == "grok-4.7-build-fast" { fastFamilies.insert(name) }
        }
        let rows = families.map { Row(name: $0.key, value: $0.value, includesGrokBuildFast: fastFamilies.contains($0.key)) }.sorted {
            if $0.value.tokens.total != $1.value.tokens.total { return $0.value.tokens.total > $1.value.tokens.total }
            return $0.name < $1.name
        }
        var points: [Point] = []
        var cursor = interval.start
        while cursor < interval.end && cursor <= now {
            let next = request.period == .daily ? cursor.addingTimeInterval(1800)
                : min(calendar.date(byAdding: .day, value: request.period.chartGroupDays, to: cursor)!, interval.end)
            let value = request.period == .daily
                ? snapshot.intradayBucket(from: cursor, intervalMinutes: 30).total
                : snapshot.bucket(from: cursor, until: next).total
            points.append(Point(date: cursor, value: value))
            cursor = next
        }
        return Self(request: request, interval: interval, generatedAt: now, total: bucket.total,
                    rows: rows, points: points, partialPeriod: now < interval.end,
                    missingPriceRecords: max(0, bucket.total.reported - bucket.total.reference.count))
    }
}
