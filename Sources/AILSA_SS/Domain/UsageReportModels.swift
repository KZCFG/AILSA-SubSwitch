import Foundation

enum UsageReportPeriod: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly, monthly, sixtyDays = "60-days", ninetyDays = "90-days", custom
    var id: String { rawValue }
    var presetDays: Int? {
        switch self { case .daily: 1; case .weekly: 7; case .monthly: 30; case .sixtyDays: 60; case .ninetyDays: 90; case .custom: nil }
    }
    var title: String {
        switch self {
        case .daily: return UsageReportText.text("日报", "Daily")
        case .weekly: return UsageReportText.text("周报 · 7 天", "Weekly · 7 days")
        case .monthly: return UsageReportText.text("月报 · 30 天", "Monthly · 30 days")
        case .sixtyDays: return UsageReportText.text("60 天", "60 days")
        case .ninetyDays: return UsageReportText.text("90 天", "90 days")
        case .custom: return UsageReportText.text("自定义", "Custom")
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
    var startingOn: Date? = nil
    var customTitle: String = ""
    static let maximumTitleLength = 80

    /// Normalize a single-line display title; filenames are sanitized separately.
    var normalizedTitle: String {
        String(customTitle.components(separatedBy: .controlCharacters)
            .joined(separator: " ").split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ").prefix(Self.maximumTitleLength))
    }
    var displayTitle: String {
        if !normalizedTitle.isEmpty { return normalizedTitle }
        switch period {
        case .daily: return UsageReportText.text("日报", "Daily usage")
        case .weekly: return UsageReportText.text("周报", "Weekly usage")
        case .monthly: return UsageReportText.text("月报", "Monthly usage")
        case .sixtyDays: return UsageReportText.text("60 天用量报告", "60-day usage")
        case .ninetyDays: return UsageReportText.text("90 天用量报告", "90-day usage")
        case .custom: return UsageReportText.text("用量报告", "Usage report")
        }
    }
    func validate(now: Date, calendar: Calendar = .current) throws {
        if period == .custom {
            guard let startingOn, startingOn.timeIntervalSince1970.isFinite,
                  calendar.startOfDay(for: startingOn) <= calendar.startOfDay(for: endingOn) else {
                throw ValidationError.invalidRange
            }
        }
        guard endingOn.timeIntervalSince1970.isFinite,
              calendar.startOfDay(for: endingOn) <= calendar.startOfDay(for: now) else {
            throw ValidationError.futureDate
        }
    }
    enum ValidationError: LocalizedError {
        case invalidRange, futureDate
        var errorDescription: String? {
            switch self {
            case .invalidRange: return UsageReportText.text("请选择开始日期，且不得晚于截止日期。", "Choose a start date on or before the end date.")
            case .futureDate: return UsageReportText.text("截止日期不能晚于今天。", "The end date cannot be later than today.")
            }
        }
    }
    func dayCount(calendar: Calendar = .current) -> Int {
        let range = interval(calendar: calendar)
        return max(1, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1)
    }
    /// Keep long-range charts legible without dropping any days from totals.
    func chartGroupDays(calendar: Calendar = .current) -> Int {
        let days = dayCount(calendar: calendar)
        return days <= 90 ? 1 : max(7, ((days + 52) / 53 + 6) / 7 * 7)
    }
    func interval(calendar: Calendar = .current) -> DateInterval {
        let day = calendar.startOfDay(for: endingOn)
        // Invalid reversed ranges are rejected by validate before data loading.
        let start = period == .custom ? min(calendar.startOfDay(for: startingOn ?? endingOn), day)
            : calendar.date(byAdding: .day, value: -((period.presetDays ?? 1) - 1), to: day)!
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
        let dates = dayCount(calendar: calendar) == 1 ? end : QuotaDashboardSnapshot.isoDay(range.start, calendar: calendar) + "_" + end
        let forbidden = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let safeTitle = normalizedTitle.components(separatedBy: forbidden).filter { !$0.isEmpty }.joined(separator: "-")
        var filenameTitle = ""
        for character in safeTitle.prefix(60) {
            guard (filenameTitle + String(character)).utf8.count <= 160 else { break }
            filenameTitle.append(character)
        }
        let titlePart = filenameTitle.isEmpty ? "" : "-" + filenameTitle
        return "AILSA-SubSwitch-\(providerName)-\(period.rawValue)\(titlePart)-\(dates).png"
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
        for (key, value) in bucket.models where key.hasIdentifiedModel && (value.reported > 0 || value.reference.count > 0) {
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
            let next = request.dayCount(calendar: calendar) == 1 ? cursor.addingTimeInterval(1800)
                : min(calendar.date(byAdding: .day, value: request.chartGroupDays(calendar: calendar), to: cursor)!, interval.end)
            let value = request.dayCount(calendar: calendar) == 1
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
