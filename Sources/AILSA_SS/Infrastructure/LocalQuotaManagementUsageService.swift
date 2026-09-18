import Foundation

protocol QuotaManagementUsageServiceProtocol: Sendable {
    func loadDashboard(for provider: QuotaManagementProvider, now: Date) async throws -> QuotaDashboardSnapshot
    func loadData(
        for provider: QuotaManagementProvider,
        historyDays: Int,
        now: Date
    ) async throws -> QuotaManagementData
}

extension QuotaManagementUsageServiceProtocol {
    func loadDashboard(for provider: QuotaManagementProvider, now: Date) async throws -> QuotaDashboardSnapshot {
        QuotaDashboardSnapshot.build(try await loadData(for: provider, historyDays: 30, now: now), now: now)
    }
}

/// Only non-secret local metadata paths are reachable from the usage dashboard.
/// In particular, this deliberately excludes auth.json, native OAuth files,
/// conversation text, and any remote endpoint.
struct QuotaManagementDataPaths: Equatable, Sendable {
    var codexSessionsDirectory: URL
    var codexArchivedSessionsDirectory: URL
    var codexBarPricingCatalogURL: URL
    var opencodexUsageLedgerURL: URL
    /// Bundled, versioned ASS audit artifact for the strict ledger path.
    /// Nil is fail-closed: strict pricing stays unavailable while metering
    /// and standard-reference disclosure continue independently.
    var opencodexVerifiedPricingCatalogURL: URL? = nil
    var antigravityQuotaHistoryURL: URL
    var antigravityInfoPlistURL: URL

    static func live(fileManager: FileManager = .default) -> QuotaManagementDataPaths {
        let homeDirectory = fileManager.homeDirectoryForCurrentUser
        return QuotaManagementDataPaths(
            codexSessionsDirectory: homeDirectory
                .appendingPathComponent(".codex/sessions", isDirectory: true),
            codexArchivedSessionsDirectory: homeDirectory
                .appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            codexBarPricingCatalogURL: homeDirectory
                .appendingPathComponent(
                    "Library/Caches/CodexBar/model-pricing/models-dev-v1.json",
                    isDirectory: false
                ),
            opencodexUsageLedgerURL: homeDirectory
                .appendingPathComponent(".opencodex/usage.jsonl", isDirectory: false),
            opencodexVerifiedPricingCatalogURL: Bundle.main.url(
                forResource: "AILSA_SS-runtime-pricing-bindings-v1",
                withExtension: "json"
            ),
            antigravityQuotaHistoryURL: homeDirectory
                .appendingPathComponent(
                    "Library/Application Support/com.steipete.codexbar/history/antigravity.json",
                    isDirectory: false
                ),
            antigravityInfoPlistURL: URL(
                fileURLWithPath: "/Applications/Antigravity.app/Contents/Info.plist",
                isDirectory: false
            )
        )
    }
}

/// A read-only local implementation inspired by the published CodexBar data
/// boundary, but deliberately smaller: it derives aggregates from native
/// Codex event metadata rather than importing another app's cache database.
/// It never sends a request or uploads local session content.
actor LocalQuotaManagementUsageService: QuotaManagementUsageServiceProtocol {
    private let paths: QuotaManagementDataPaths
    private var incrementalLedger = OpenCodexIncrementalLedger()

    init(paths: QuotaManagementDataPaths = .live()) {
        self.paths = paths
    }

    func loadDashboard(for provider: QuotaManagementProvider, now: Date) async throws -> QuotaDashboardSnapshot {
        if provider == .cursor { return try await CursorUsageService.shared.dashboard(now: now) }
        if provider == .codex, FileManager.default.fileExists(atPath: paths.opencodexUsageLedgerURL.path) {
            return try incrementalLedger.snapshot(url: paths.opencodexUsageLedgerURL, catalogURL: paths.opencodexVerifiedPricingCatalogURL, now: now)
        }
        return QuotaDashboardSnapshot.build(try await loadData(for: provider, historyDays: 30, now: now), now: now)
    }

    func loadData(
        for provider: QuotaManagementProvider,
        historyDays: Int = 30,
        now: Date = Date()
    ) async throws -> QuotaManagementData {
        switch provider {
        case .cursor:
            throw CursorUsageError.invalidResponse // Legacy record API; Cursor uses loadDashboard.
        case .codex:
            if FileManager.default.fileExists(atPath: paths.opencodexUsageLedgerURL.path) {
                do {
                    // Ledger-primary mode is intentionally exclusive.  Its
                    // request-level identities and dedupe semantics cannot be
                    // safely merged with the older Codex session observations.
                    return .openCodex(
                        try incrementalLedger.load(url: paths.opencodexUsageLedgerURL, catalogURL: paths.opencodexVerifiedPricingCatalogURL)
                    )
                } catch {
                    // A missing, unreadable, or mid-replacement ledger must
                    // not poison the dashboard.  The fallback below remains a
                    // separate session-only source, never an additive merge.
                }
            }
            return .codex(try loadCodexUsage(historyDays: historyDays, now: now))
        case .antigravity:
            return .antigravity(try loadAntigravityQuotaHistory(now: now))
        }
    }

    private func loadCodexUsage(historyDays: Int, now: Date) throws -> CodexUsageAnalytics {
        let boundedDays = min(max(historyDays, 1), 365)
        let calendar = Calendar.current
        let start = calendar.date(
            byAdding: .day,
            value: -(boundedDays - 1),
            to: calendar.startOfDay(for: now)
        ) ?? calendar.startOfDay(for: now)
        let pricingCatalog = loadPricingCatalog()
        let files = sessionFiles(since: start)

        var records: [LocalUsageRecord] = []
        var recordIDs = Set<String>()
        var skippedFileCount = 0

        for file in files {
            do {
                let sessionRecords = try parseSessionFile(
                    file,
                    since: start,
                    pricingCatalog: pricingCatalog.rates
                )
                for record in sessionRecords where recordIDs.insert(record.id).inserted {
                    records.append(record)
                }
            } catch {
                // A partially written JSONL file must not poison usable rows
                // from another completed session. The UI exposes this count as
                // incomplete local coverage instead of reporting a false total.
                skippedFileCount += 1
            }
        }

        return CodexUsageAnalytics(
            records: records.sorted { $0.occurredAt < $1.occurredAt },
            scannedFileCount: files.count - skippedFileCount,
            skippedFileCount: skippedFileCount,
            scannedAt: now,
            pricingCatalogUpdatedAt: pricingCatalog.updatedAt,
            pricingCatalogSource: pricingCatalog.sourceName,
            sourceDescription: "local-codex-session-metadata"
        )
    }

    private func loadAntigravityQuotaHistory(now: Date) throws -> AntigravityUsageAnalytics {
        let observations: [AntigravityQuotaObservation]
        if paths == .live() { observations = try AntigravityQuotaHistoryStore.readCurrent(now: now) }
        else { observations = try parseAntigravityQuotaHistory() }
        return AntigravityUsageAnalytics(
            observations: observations.sorted { $0.capturedAt < $1.capturedAt },
            sourceDescription: "local-antigravity-quota-history",
            nativeVersion: installedAntigravityVersion(),
            scannedAt: now
        )
    }

    private func sessionFiles(since start: Date) -> [URL] {
        let roots = [paths.codexSessionsDirectory, paths.codexArchivedSessionsDirectory]
        let fileManager = FileManager.default
        var urls = Set<URL>()

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                if let inferredDate = inferredDate(from: url), inferredDate < start {
                    continue
                }
                urls.insert(url.standardizedFileURL)
            }
        }

        return urls.sorted { $0.path < $1.path }
    }

    private func parseSessionFile(
        _ url: URL,
        since start: Date,
        pricingCatalog: [String: UsagePricingRates]
    ) throws -> [LocalUsageRecord] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }

        var sessionID = url.deletingPathExtension().lastPathComponent
        var projectName: String?
        var activeModel: String?
        var previousTotals: UsageTokenBreakdown?
        var eventOrdinal = 0
        var records: [LocalUsageRecord] = []

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = object["type"] as? String
            else {
                // Codex may be appending a final line while the dashboard is
                // reading. Ignore that line rather than treating text content
                // as a parsable source.
                continue
            }

            let payload = object["payload"] as? [String: Any]
            if type == "session_meta" {
                if let sourceID = nonemptyString(payload?["session_id"]) {
                    sessionID = sourceID
                }
                if let cwd = nonemptyString(payload?["cwd"]) {
                    projectName = URL(fileURLWithPath: cwd).lastPathComponent
                }
                continue
            }

            if type == "turn_context" {
                activeModel = nonemptyString(payload?["model"]) ?? activeModel
                continue
            }

            guard type == "event_msg",
                  payload?["type"] as? String == "token_count",
                  let info = payload?["info"] as? [String: Any],
                  let totalObject = (info["total_token_usage"] as? [String: Any])
                    ?? (info["last_token_usage"] as? [String: Any])
            else {
                continue
            }

            let totals = tokenBreakdown(from: totalObject)
            let delta: UsageTokenBreakdown
            if let previousTotals,
               totals.total >= previousTotals.total {
                delta = totals.subtracting(previousTotals)
            } else {
                // A native event stream can reset its cumulative counter after
                // a resumed/forked run. A new epoch contributes its full first
                // total rather than a negative delta.
                delta = totals
            }
            previousTotals = totals
            eventOrdinal += 1

            guard delta.hasUsage,
                  let occurredAt = date(from: object["timestamp"]),
                  occurredAt >= start
            else {
                continue
            }

            let model = activeModel
            let price = model.flatMap { pricingCatalog[normalizedModelID($0)] }
            let estimatedCost = price.map { $0.estimate(for: delta) }
            let stableEventID = "\(sessionID)-\(eventOrdinal)-\(totals.total)-\(Int(occurredAt.timeIntervalSince1970 * 1_000))"
            records.append(
                LocalUsageRecord(
                    id: stableEventID,
                    occurredAt: occurredAt,
                    model: model,
                    projectName: projectName,
                    sessionLabel: Self.sessionLabel(for: sessionID),
                    tokens: delta,
                    apiEquivalentUSD: estimatedCost
                )
            )
        }

        return records
    }

    private func parseAntigravityQuotaHistory() throws -> [AntigravityQuotaObservation] {
        guard FileManager.default.fileExists(atPath: paths.antigravityQuotaHistoryURL.path) else {
            return []
        }
        let data = try Data(contentsOf: paths.antigravityQuotaHistoryURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accounts = root["accounts"] as? [String: Any]
        else {
            return []
        }

        var observations: [AntigravityQuotaObservation] = []
        for (accountKey, rawFamilies) in accounts {
            guard let families = rawFamilies as? [[String: Any]] else { continue }
            for family in families {
                let name = nonemptyString(family["name"]) ?? "Quota"
                let windowMinutes = integer(from: family["windowMinutes"]) ?? 0
                guard let entries = family["entries"] as? [[String: Any]] else { continue }
                for (entryIndex, entry) in entries.enumerated() {
                    guard let capturedAt = date(from: entry["capturedAt"]),
                          let usedPercent = double(from: entry["usedPercent"])
                    else {
                        continue
                    }
                    let resetAt = date(from: entry["resetsAt"])
                    observations.append(
                        AntigravityQuotaObservation(
                            id: "\(accountKey)-\(name)-\(entryIndex)-\(Int(capturedAt.timeIntervalSince1970))",
                            capturedAt: capturedAt,
                            resetAt: resetAt,
                            windowName: name,
                            windowMinutes: windowMinutes,
                            usedPercent: max(0, min(100, usedPercent))
                        )
                    )
                }
            }
        }
        return observations
    }

    private func installedAntigravityVersion() -> String? {
        guard let dictionary = NSDictionary(contentsOf: paths.antigravityInfoPlistURL) as? [String: Any] else {
            return nil
        }
        return nonemptyString(dictionary["CFBundleShortVersionString"])
    }

    private func loadPricingCatalog() -> PricingCatalogResult {
        guard let data = try? Data(contentsOf: paths.codexBarPricingCatalogURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let catalog = root["catalog"] as? [String: Any],
              let providers = catalog["providers"] as? [String: Any],
              let openAI = providers["openai"] as? [String: Any],
              let models = openAI["models"] as? [String: Any]
        else {
            return PricingCatalogResult(rates: [:], updatedAt: nil, sourceName: nil)
        }

        var rates: [String: UsagePricingRates] = [:]
        for (modelID, rawModel) in models {
            guard let model = rawModel as? [String: Any],
                  let cost = model["cost"] as? [String: Any],
                  let input = double(from: cost["input"]),
                  let output = double(from: cost["output"])
            else {
                continue
            }
            rates[normalizedModelID(modelID)] = UsagePricingRates(
                inputPerMillion: input,
                cacheReadPerMillion: double(from: cost["cache_read"]) ?? input,
                cacheWritePerMillion: double(from: cost["cache_write"]) ?? input,
                outputPerMillion: output
            )
        }

        return PricingCatalogResult(
            rates: rates,
            updatedAt: date(from: root["fetchedAt"]),
            sourceName: "models.dev cache (local)"
        )
    }

    private func inferredDate(from url: URL) -> Date? {
        let components = url.pathComponents
        for index in components.indices where index + 3 < components.endIndex {
            let year = components[index]
            let month = components[index + 1]
            let day = components[index + 2]
            guard year.count == 4,
                  month.count == 2,
                  day.count == 2,
                  let yearValue = Int(year),
                  let monthValue = Int(month),
                  let dayValue = Int(day)
            else {
                continue
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .current
            return calendar.date(from: DateComponents(year: yearValue, month: monthValue, day: dayValue))
        }
        return dateFromFilename(url.lastPathComponent)
    }

    private func dateFromFilename(_ filename: String) -> Date? {
        let pattern = "(\\d{4})-(\\d{2})-(\\d{2})"
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: filename,
                range: NSRange(filename.startIndex..., in: filename)
              ),
              let yearRange = Range(match.range(at: 1), in: filename),
              let monthRange = Range(match.range(at: 2), in: filename),
              let dayRange = Range(match.range(at: 3), in: filename),
              let year = Int(filename[yearRange]),
              let month = Int(filename[monthRange]),
              let day = Int(filename[dayRange])
        else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private func tokenBreakdown(from object: [String: Any]) -> UsageTokenBreakdown {
        UsageTokenBreakdown(
            input: integer(from: object["input_tokens"]) ?? 0,
            cachedInput: integer(from: object["cached_input_tokens"]) ?? 0,
            cacheWriteInput: integer(from: object["cache_write_input_tokens"]) ?? 0,
            output: integer(from: object["output_tokens"]) ?? 0,
            reasoningOutput: integer(from: object["reasoning_output_tokens"]) ?? 0
        )
    }

    private func normalizedModelID(_ model: String) -> String {
        model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "openai/", with: "")
    }

    private static func sessionLabel(for sessionID: String) -> String {
        let prefix = String(sessionID.prefix(8))
        return prefix.isEmpty ? "Session" : "Session \(prefix)"
    }

    private func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func integer(from value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func double(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func date(from value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue
            return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1_000 : seconds)
        }
        guard let string = value as? String else { return nil }
        return iso8601WithFractionalSeconds.date(from: string)
            ?? iso8601.date(from: string)
    }

    // These formatters stay actor-isolated: ISO8601DateFormatter is mutable
    // and does not conform to Sendable under Swift 6.2's concurrency checks.
    private let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct PricingCatalogResult {
    var rates: [String: UsagePricingRates]
    var updatedAt: Date?
    var sourceName: String?
}

private struct UsagePricingRates: Sendable {
    var inputPerMillion: Double
    var cacheReadPerMillion: Double
    var cacheWritePerMillion: Double
    var outputPerMillion: Double

    init(
        inputPerMillion: Double,
        cacheReadPerMillion: Double,
        cacheWritePerMillion: Double,
        outputPerMillion: Double
    ) {
        self.inputPerMillion = inputPerMillion
        self.cacheReadPerMillion = cacheReadPerMillion
        self.cacheWritePerMillion = cacheWritePerMillion
        self.outputPerMillion = outputPerMillion
    }

    init?(costObject: [String: Any]) {
        guard let input = LocalQuotaManagementUsageService.doubleStatic(from: costObject["input"]),
              let output = LocalQuotaManagementUsageService.doubleStatic(from: costObject["output"])
        else {
            return nil
        }
        self.init(
            inputPerMillion: input,
            cacheReadPerMillion: LocalQuotaManagementUsageService.doubleStatic(from: costObject["cache_read"]) ?? input,
            cacheWritePerMillion: LocalQuotaManagementUsageService.doubleStatic(from: costObject["cache_write"]) ?? input,
            outputPerMillion: output
        )
    }

    func estimate(for tokens: UsageTokenBreakdown) -> Double {
        let amount =
            Double(tokens.uncachedInput) * inputPerMillion
            + Double(max(0, tokens.cachedInput)) * cacheReadPerMillion
            + Double(max(0, tokens.cacheWriteInput)) * cacheWritePerMillion
            + Double(max(0, tokens.output)) * outputPerMillion
        return amount / 1_000_000
    }
}

private extension LocalQuotaManagementUsageService {
    static func doubleStatic(from value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}
