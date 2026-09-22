import Foundation

/// The dashboard keeps quota information and local usage accounting separate.
/// A subscription reserve is not an API bill, and a locally-derived API-equivalent
/// estimate must never be displayed as an actual charge.
enum QuotaManagementProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case antigravity
    case cursor

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .codex:
            "accounts.provider.codex"
        case .antigravity:
            "accounts.provider.antigravity"
        case .cursor: "Cursor"
        }
    }
}

enum QuotaManagementSection: String, CaseIterable, Identifiable, Sendable {
    case overview
    case breakdown
    case ranking

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .overview:
            "quota.section.overview"
        case .breakdown:
            "quota.section.breakdown"
        case .ranking:
            "quota.section.ranking"
        }
    }
}

enum QuotaChartMetric: String, CaseIterable, Identifiable, Sendable {
    case tokens
    case apiEquivalentCost

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .tokens:
            "quota.metric.tokens"
        case .apiEquivalentCost:
            "quota.metric.api_equivalent_cost"
        }
    }
}

/// Ledger-primary OpenCodex has two distinct monetary disclosures. Keeping
/// this selector separate from the older session-derived chart prevents a
/// standard reference estimate from ever being rendered as confirmed-tier
/// pricing.
enum OpenCodexChartMetric: String, CaseIterable, Identifiable, Sendable {
    case reportedTokens
    case confirmedTierAPIEquivalent
    case standardReference

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .reportedTokens:
            "quota.opencodex.reported_tokens"
        case .confirmedTierAPIEquivalent:
            "quota.opencodex.confirmed_tier_api_equivalent"
        case .standardReference:
            "quota.opencodex.standard_reference"
        }
    }
}

enum UsageRankingDimension: String, CaseIterable, Identifiable, Sendable {
    case model
    case project
    case session

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .model:
            "quota.ranking.model"
        case .project:
            "quota.ranking.project"
        case .session:
            "quota.ranking.session"
        }
    }
}

struct UsageTokenBreakdown: Equatable, Sendable {
    var input: Int
    var cachedInput: Int
    var cacheWriteInput: Int
    var output: Int
    /// Reasoning tokens are reported by Codex as an output subset. They are
    /// shown for transparency but never added to the total a second time.
    var reasoningOutput: Int

    static let zero = UsageTokenBreakdown(
        input: 0,
        cachedInput: 0,
        cacheWriteInput: 0,
        output: 0,
        reasoningOutput: 0
    )

    var total: Int {
        max(0, input) + max(0, output)
    }

    var uncachedInput: Int {
        max(0, input - cachedInput - cacheWriteInput)
    }

    var hasUsage: Bool {
        total > 0 || cachedInput > 0 || cacheWriteInput > 0
    }

    func subtracting(_ previous: UsageTokenBreakdown) -> UsageTokenBreakdown {
        UsageTokenBreakdown(
            input: max(0, input - previous.input),
            cachedInput: max(0, cachedInput - previous.cachedInput),
            cacheWriteInput: max(0, cacheWriteInput - previous.cacheWriteInput),
            output: max(0, output - previous.output),
            reasoningOutput: max(0, reasoningOutput - previous.reasoningOutput)
        )
    }

    static func + (lhs: UsageTokenBreakdown, rhs: UsageTokenBreakdown) -> UsageTokenBreakdown {
        UsageTokenBreakdown(
            input: lhs.input + rhs.input,
            cachedInput: lhs.cachedInput + rhs.cachedInput,
            cacheWriteInput: lhs.cacheWriteInput + rhs.cacheWriteInput,
            output: lhs.output + rhs.output,
            reasoningOutput: lhs.reasoningOutput + rhs.reasoningOutput
        )
    }
}

struct APIEquivalentEstimate: Equatable, Sendable {
    var knownUSD: Double
    var unpricedRecordCount: Int

    static let unavailable = APIEquivalentEstimate(knownUSD: 0, unpricedRecordCount: 0)

    var hasKnownEstimate: Bool {
        knownUSD > 0 || unpricedRecordCount == 0
    }

    var isComplete: Bool {
        unpricedRecordCount == 0
    }
}

struct LocalUsageRecord: Equatable, Identifiable, Sendable {
    var id: String
    var occurredAt: Date
    var model: String?
    /// A workspace basename only. Full filesystem paths and conversation
    /// contents are deliberately excluded from dashboard records.
    var projectName: String?
    var sessionLabel: String
    var tokens: UsageTokenBreakdown
    /// Nil means that the locally cached public rate catalog had no
    /// attributable price for this model/routing label.
    var apiEquivalentUSD: Double?

    var displayModel: String {
        let trimmed = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.tr("quota.value.unknown_model") : trimmed
    }

    var displayProject: String {
        let trimmed = projectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.tr("quota.value.this_mac") : trimmed
    }
}

struct UsageDailyTotal: Equatable, Identifiable, Sendable {
    var day: Date
    var tokens: UsageTokenBreakdown
    var estimate: APIEquivalentEstimate

    var id: Date { day }
}

struct UsageRankingRow: Equatable, Identifiable, Sendable {
    var label: String
    var tokens: UsageTokenBreakdown
    var estimate: APIEquivalentEstimate
    var recordCount: Int

    var id: String { label }
}

struct CodexUsageAnalytics: Equatable, Sendable {
    var records: [LocalUsageRecord]
    var scannedFileCount: Int
    var skippedFileCount: Int
    var scannedAt: Date
    var pricingCatalogUpdatedAt: Date?
    var pricingCatalogSource: String?
    var sourceDescription: String

    static let empty = CodexUsageAnalytics(
        records: [],
        scannedFileCount: 0,
        skippedFileCount: 0,
        scannedAt: Date(),
        pricingCatalogUpdatedAt: nil,
        pricingCatalogSource: nil,
        sourceDescription: ""
    )

    func dailyTotals(calendar: Calendar = .current) -> [UsageDailyTotal] {
        let grouped = Dictionary(grouping: records) { calendar.startOfDay(for: $0.occurredAt) }
        return grouped.map { day, records in
            UsageDailyTotal(
                day: day,
                tokens: records.reduce(.zero) { $0 + $1.tokens },
                estimate: Self.estimate(for: records)
            )
        }
        .sorted { $0.day < $1.day }
    }

    func totals(on day: Date?, calendar: Calendar = .current) -> UsageDailyTotal {
        let selected = records.filter { record in
            guard let day else { return true }
            return calendar.isDate(record.occurredAt, inSameDayAs: day)
        }
        return UsageDailyTotal(
            day: day.map(calendar.startOfDay(for:)) ?? calendar.startOfDay(for: scannedAt),
            tokens: selected.reduce(.zero) { $0 + $1.tokens },
            estimate: Self.estimate(for: selected)
        )
    }

    func rankings(
        by dimension: UsageRankingDimension,
        on day: Date?,
        calendar: Calendar = .current
    ) -> [UsageRankingRow] {
        let selected = records.filter { record in
            guard let day else { return true }
            return calendar.isDate(record.occurredAt, inSameDayAs: day)
        }
        let groups = Dictionary(grouping: selected) { record -> String in
            switch dimension {
            case .model:
                record.displayModel
            case .project:
                record.displayProject
            case .session:
                record.sessionLabel
            }
        }
        return groups.map { label, records in
            UsageRankingRow(
                label: label,
                tokens: records.reduce(.zero) { $0 + $1.tokens },
                estimate: Self.estimate(for: records),
                recordCount: records.count
            )
        }
        .sorted {
            if $0.tokens.total != $1.tokens.total {
                return $0.tokens.total > $1.tokens.total
            }
            return $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
    }

    private static func estimate(for records: [LocalUsageRecord]) -> APIEquivalentEstimate {
        APIEquivalentEstimate(
            knownUSD: records.reduce(0) { $0 + ($1.apiEquivalentUSD ?? 0) },
            unpricedRecordCount: records.filter { $0.apiEquivalentUSD == nil }.count
        )
    }
}

struct AntigravityQuotaObservation: Equatable, Identifiable, Sendable {
    var id: String
    var capturedAt: Date
    var resetAt: Date?
    var windowName: String
    var windowMinutes: Int
    var usedPercent: Double

    var displayName: String {
        let names = ["gemini-5h": "Gemini · 5h", "gemini-weekly": "Gemini · 7d", "3p-5h": "Claude / GPT · 5h", "3p-weekly": "Claude / GPT · 7d", "session": "5h", "weekly": "7d"]
        return names[windowName] ?? windowName
    }

    var day: Date {
        Calendar.current.startOfDay(for: capturedAt)
    }

    /// Stable provider-family mapping for the native quota IDs. Display text
    /// can change with localization; the IDs remain the presentation contract.
    var familyKey: String {
        let id = windowName.lowercased()
        if id.hasPrefix("gemini-") || id == "gemini" { return "gemini" }
        if id.hasPrefix("3p-") || id.hasPrefix("claude-") || id.hasPrefix("gpt-") { return "third-party" }
        return "other"
    }

    var isFiveHourWindow: Bool {
        if windowMinutes > 0 { return windowMinutes <= 6 * 60 }
        let id = windowName.lowercased()
        return id.contains("5h") || id.contains("five_hour") || id.contains("session")
    }

    var cadenceLabel: String {
        isFiveHourWindow ? "5h" : windowMinutes >= 6 * 24 * 60 ? "7d" : "—"
    }
}

struct AntigravityUsageAnalytics: Equatable, Sendable {
    var observations: [AntigravityQuotaObservation]
    var sourceDescription: String
    var nativeVersion: String?
    var scannedAt: Date

    static let unavailable = AntigravityUsageAnalytics(
        observations: [],
        sourceDescription: "",
        nativeVersion: nil,
        scannedAt: Date()
    )

    func latestDailyUsedPercent(calendar: Calendar = .current) -> [(day: Date, usedPercent: Double)] {
        let grouped = Dictionary(grouping: observations) { calendar.startOfDay(for: $0.capturedAt) }
        return grouped.compactMap { day, observations in
            guard let latest = observations.max(by: { $0.capturedAt < $1.capturedAt }) else { return nil }
            return (day, latest.usedPercent)
        }
        .sorted { $0.day < $1.day }
    }
}

enum QuotaManagementData: Equatable, Sendable {
    case codex(CodexUsageAnalytics)
    /// Ledger-primary OpenCodex metering is deliberately separate from the
    /// legacy Codex-session fallback, so the two sources can never be summed.
    case openCodex(OpenCodexLedgerAnalytics)
    case antigravity(AntigravityUsageAnalytics)
}

// Compact presentation data. No request IDs or per-request records reach SwiftUI.
struct QuotaMoney: Equatable, Sendable {
    var pico: Int64 = 0
    var count = 0
    var overflow = false
    mutating func add(_ value: Int64?) {
        guard let value else { return }
        count += 1
        let result = pico.addingReportingOverflow(value)
        overflow = overflow || result.overflow
        if !overflow { pico = result.partialValue }
    }
    mutating func merge(_ other: Self) {
        let result = pico.addingReportingOverflow(other.pico)
        overflow = overflow || other.overflow || result.overflow
        count += other.count
        if !overflow { pico = result.partialValue }
    }
    var usd: Double? { count > 0 && !overflow ? Double(pico) / 1e12 : nil }
}

struct QuotaAggregate: Equatable, Sendable {
    var tokens = UsageTokenBreakdown.zero
    var requests = 0
    var reported = 0
    var aborted = 0
    var unknownRoute = 0
    var reference = QuotaMoney()
    var confirmed = QuotaMoney()
    var metered = QuotaMoney()
    var states: [String: Int] = [:]
    mutating func merge(_ other: Self) {
        tokens = tokens + other.tokens
        requests += other.requests; reported += other.reported
        aborted += other.aborted; unknownRoute += other.unknownRoute
        reference.merge(other.reference); confirmed.merge(other.confirmed); metered.merge(other.metered)
        for (key, value) in other.states { states[key, default: 0] += value }
    }
}
struct QuotaModelKey: Hashable, Sendable {
    var provider: String
    var model: String
    static let unknown = Self(provider: "", model: "")

    /// Presentation grouping only. Monetary values remain the sum of each
    /// record's independently audited price; never reprice an entire family.
    var familyKey: Self {
        let name = model.lowercased().replacingOccurrences(of: "_", with: "-")
        if name == "kimi-for-coding" { return Self(provider: provider, model: "Kimi K2.8 Preview") }
        if name == "kimi-for-coding-highspeed" { return Self(provider: provider, model: "Kimi K2.7 Code HighSpeed") }
        if name == "k3[1m]" { return Self(provider: "", model: "Kimi K3") }
        let families: [(String, String)] = [
            ("grok-4.7", "Grok 4.7"),
            ("grok-4.6", "Grok 4.6"), ("grok-4.5", "Grok 4.5"),
            ("gemini-3.8-flash", "Gemini 3.8 Flash"),
            ("deepseek-v4-flash", "DeepSeek Flash"), ("deepseek-flash", "DeepSeek Flash"),
            ("fable-5.1", "Fable 5.1"), ("fable-5-1", "Fable 5.1"),
            ("kimi-k3", "Kimi K3"), ("k3", "Kimi K3")
        ]
        if let family = families.first(where: { name == $0.0 || name.hasPrefix($0.0 + "-") || name.hasSuffix("-" + $0.0) || name.contains("-" + $0.0 + "-") }) {
            return Self(provider: "", model: family.1)
        }
        return self
    }
}
struct QuotaBucket: Equatable, Sendable {
    var total = QuotaAggregate()
    var models: [QuotaModelKey: QuotaAggregate] = [:]
    mutating func add(_ value: QuotaAggregate, key: QuotaModelKey) {
        total.merge(value); models[key, default: QuotaAggregate()].merge(value)
    }
    mutating func merge(_ other: Self) {
        total.merge(other.total)
        for (key, value) in other.models { models[key, default: QuotaAggregate()].merge(value) }
    }
}
/// One pricing basis that contributed to a dashboard's USD figures together
/// with the date that basis was last verified. Each basis keeps its own date;
/// the UI must never present them as a single "checked on" value.
struct QuotaPricingProvenance: Hashable, Sendable {
    enum Basis: String, Sendable {
        /// Hard-coded official standard rates (`OpenCodexStandardReferenceEstimator`).
        case standardReference
        /// Audited confirmed-tier catalog (`AILSA_SS-runtime-pricing-bindings-v1.json`).
        case verifiedCatalog
        /// models.dev cache read from CodexBar's local files (Codex sessions path).
        case modelsDevCache
        /// Amounts reported by the vendor's usage API (Cursor).
        case vendorReported
    }
    let basis: Basis
    /// ISO `yyyy-MM-dd`; nil when the source carries no verification date.
    let auditDate: String?
}

struct QuotaDashboardSnapshot: Equatable, Sendable {
    let scannedAt: Date
    let days: [Date: QuotaBucket]
    let all: QuotaAggregate
    let source: String
    let pricingSources: [String]
    let discardedRows: Int
    let quotaWindows: [AntigravityQuotaObservation]
    let quotaTrend: [Date: Double]
    let buildMilliseconds: Double
    var minuteTokens: [Date: Int] = [:]
    var minuteBuckets: [Date: QuotaBucket] = [:]
    var quotaTrends: [String: [Date: Double]] = [:]
    var pricingProvenance: [QuotaPricingProvenance] = []

    static func build(_ data: QuotaManagementData, now: Date, calendar: Calendar = .current) -> Self {
        let started = Date()
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        var days: [Date: QuotaBucket] = [:]
        var all = QuotaAggregate()
        var sources = Set<String>()
        var discarded = 0
        var windows: [AntigravityQuotaObservation] = []
        var trend: [Date: Double] = [:]
        var trends: [String: [Date: Double]] = [:]
        var minutes: [Date: Int] = [:]
        var minuteBuckets: [Date: QuotaBucket] = [:]
        var provenance: [QuotaPricingProvenance] = []
        let scanned: Date
        let source: String
        func insert(_ value: QuotaAggregate, at date: Date, key: QuotaModelKey) {
            all.merge(value)
            guard date >= start && date < end else { return }
            let day = calendar.startOfDay(for: date)
            days[day, default: QuotaBucket()].add(value, key: key)
        }
        switch data {
        case .openCodex(let data):
            scanned = data.scannedAt; source = "OpenCodex"
            discarded = data.coverage.ledgerDuplicateRowsDiscarded
            provenance.append(QuotaPricingProvenance(basis: .standardReference, auditDate: OpenCodexStandardReferenceEstimator.auditDate))
            var catalogAuditDates = Set<String>()
            for record in data.records {
                let contribution = Self.contribution(record)
                if let url = record.pricing.officialSourceURL { sources.insert(url) }
                if let audit = OpenCodexPricingCatalog.auditDate(fromCatalogVersion: record.pricing.catalogVersion) { catalogAuditDates.insert(audit) }
                all.merge(contribution.value)
                if contribution.day == today, let minute = contribution.minute { minutes[minute, default: 0] += contribution.value.tokens.total; minuteBuckets[minute, default: QuotaBucket()].add(contribution.value, key: contribution.key) }
                if contribution.day >= start && contribution.day < end {
                    days[contribution.day, default: QuotaBucket()].add(contribution.value, key: contribution.key)
                }
            }
            for audit in catalogAuditDates.sorted() { provenance.append(QuotaPricingProvenance(basis: .verifiedCatalog, auditDate: audit)) }
        case .codex(let data):
            scanned = data.scannedAt; source = "Codex sessions"
            discarded = data.skippedFileCount
            if let pricing = data.pricingCatalogSource { sources.insert(pricing) }
            if data.pricingCatalogSource != nil {
                provenance.append(QuotaPricingProvenance(basis: .modelsDevCache, auditDate: data.pricingCatalogUpdatedAt.map { Self.isoDay($0, calendar: calendar) }))
            }
            for record in data.records {
                var value = QuotaAggregate()
                value.requests = 1; value.reported = 1; value.tokens = record.tokens
                if let usd = record.apiEquivalentUSD, usd.isFinite, usd >= 0, usd * 1e12 < Double(Int64.max) { value.reference.add(Int64((usd * 1e12).rounded())) }
                if calendar.isDate(record.occurredAt, inSameDayAs: today) {
                    let minute = Date(timeIntervalSince1970: floor(record.occurredAt.timeIntervalSince1970 / 60) * 60)
                    minutes[minute, default: 0] += value.tokens.total
                    minuteBuckets[minute, default: QuotaBucket()].add(value, key: QuotaModelKey(provider: "Codex", model: record.model ?? ""))
                }
                insert(value, at: record.occurredAt, key: QuotaModelKey(provider: "Codex", model: record.model ?? ""))
            }
        case .antigravity(let data):
            scanned = data.scannedAt; source = "Antigravity"
            var latest: [String: AntigravityQuotaObservation] = [:]
            var daily: [String: [Date: AntigravityQuotaObservation]] = [:]
            for value in data.observations {
                if latest[value.windowName].map({ $0.capturedAt < value.capturedAt }) ?? true { latest[value.windowName] = value }
                guard value.capturedAt >= start && value.capturedAt < end else { continue }
                let day = calendar.startOfDay(for: value.capturedAt)
                if (daily[value.windowName]?[day]?.capturedAt ?? .distantPast) < value.capturedAt { daily[value.windowName, default: [:]][day] = value }
            }
            windows = latest.values.sorted {
                if $0.isFiveHourWindow != $1.isFiveHourWindow {
                    return $0.isFiveHourWindow
                }
                if $0.familyKey != $1.familyKey {
                    return $0.familyKey < $1.familyKey
                }
                return $0.windowName < $1.windowName
            }
            trends = daily.mapValues { $0.mapValues(\.usedPercent) }
            trend = windows.first.flatMap { trends[$0.windowName] } ?? [:]
        }
        return Self(scannedAt: scanned, days: days, all: all, source: source,
                    pricingSources: sources.sorted(), discardedRows: discarded,
                    quotaWindows: windows, quotaTrend: trend,
                    buildMilliseconds: Date().timeIntervalSince(started) * 1000, minuteTokens: minutes, minuteBuckets: minuteBuckets, quotaTrends: trends,
                    pricingProvenance: provenance)
    }
    static func isoDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func contribution(_ record: OpenCodexLedgerMeteringRecord) -> QuotaContribution {
        var value = QuotaAggregate()
        value.requests = 1
        value.aborted = record.streamAborted ? 1 : 0
        let resolved = record.routeIdentityStatus == .resolved
        value.unknownRoute = resolved ? 0 : 1
        if !record.streamAborted {
            let reported = record.usageStatus == .reported && record.tokenSource == .upstreamReported && record.tokens.hasPrimaryTokens
            value.states[record.standardReferenceEstimate.status.rawValue] = 1
            if reported {
                value.reported = 1
                value.tokens = UsageTokenBreakdown(input: record.tokens.inputTokens ?? 0,
                    cachedInput: record.tokens.cacheReadInputTokens ?? record.tokens.cachedInputTokens ?? 0,
                    cacheWriteInput: record.tokens.cacheCreationInputTokens ?? 0,
                    output: record.tokens.outputTokens ?? 0, reasoningOutput: record.tokens.reasoningOutputTokens ?? 0)
                if record.standardReferenceEstimate.status == .referenceEstimate { value.reference.add(record.standardReferenceEstimate.picoUSD) }
                if record.pricing.valueKind == .exactDerived { value.confirmed.add(record.pricing.picoUSD) }
            }
        }
        return QuotaContribution(minute: Date(timeIntervalSince1970: floor(record.occurredAt.timeIntervalSince1970 / 60) * 60), day: Calendar.current.startOfDay(for: record.occurredAt), key: resolved ? QuotaModelKey(provider: record.routeProvider ?? "", model: record.resolvedModel ?? "") : .unknown, value: value)
    }
    static func compact(_ entries: Dictionary<String, QuotaContribution>.Values, discarded: Int, now: Date, pricingProvenance: [QuotaPricingProvenance] = []) -> Self {
        let started = Date(), calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -29, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        var days: [Date: QuotaBucket] = [:], all = QuotaAggregate()
        var minutes: [Date: Int] = [:]
        var minuteBuckets: [Date: QuotaBucket] = [:]
        for entry in entries {
            all.merge(entry.value)
            if entry.day == today, let minute = entry.minute {
                minutes[minute, default: 0] += entry.value.tokens.total
                minuteBuckets[minute, default: QuotaBucket()].add(entry.value, key: entry.key)
            }
            if entry.day >= start && entry.day < end {
                let day = entry.day
                days[day, default: QuotaBucket()].add(entry.value, key: entry.key)
            }
        }
        return Self(scannedAt: Date(), days: days, all: all, source: "OpenCodex", pricingSources: [], discardedRows: discarded, quotaWindows: [], quotaTrend: [:], buildMilliseconds: Date().timeIntervalSince(started) * 1000, minuteTokens: minutes, minuteBuckets: minuteBuckets, pricingProvenance: pricingProvenance)
    }
    func bucket(from start: Date, until end: Date) -> QuotaBucket {
        var result = QuotaBucket()
        for (day, bucket) in days where day >= start && day < end { result.merge(bucket) }
        return result
    }
    func intradayBucket(from start: Date, intervalMinutes: Int) -> QuotaBucket {
        let end = start.addingTimeInterval(Double(max(1, intervalMinutes) * 60))
        var result = QuotaBucket()
        for (minute, bucket) in minuteBuckets where minute >= start && minute < end { result.merge(bucket) }
        return result
    }
}

/// Content height excludes the host's tab bar. Reduce row count first; at
/// small heights put the trend on a separate page instead of clipping it.
struct QuotaDashboardLayout {
    let rows: Int
    let showsTrend: Bool
    let trendHeight: Double
    /// Codex historical charts use the same canvas as Today. Keep Cursor's
    /// existing layout and Antigravity's independent history layout intact.
    init(height: Double, provider: QuotaManagementProvider, range: Int) {
        self.init(height: height, expandedIntraday: range == 1 && provider != .antigravity,
                  largeTrend: provider != .cursor)
    }

    init(height: Double, expandedIntraday: Bool = true, largeTrend: Bool = false) {
        showsTrend = height >= 520
        trendHeight = expandedIntraday || largeTrend ? 180 : 76
        // Includes range, KPIs, table header, paging, chart, footer and stack gaps.
        let fixed: Double = showsTrend ? (expandedIntraday ? 494 : (largeTrend ? 514 : 410)) : 330
        rows = max(1, min(8, Int((height - fixed) / 33)))
    }
}

struct QuotaContribution: Equatable, Sendable {
    var minute: Date? = nil
    let day: Date
    let key: QuotaModelKey
    let value: QuotaAggregate
}
