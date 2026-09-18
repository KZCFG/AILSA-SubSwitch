import Foundation
import SQLite3
import CryptoKit

struct CursorQuotaPool: Identifiable, Sendable {
    let id: String
    let usedPercent: Double?
    let reset: Date?
}
struct CursorUsageEventRecord: Sendable {
    let date: Date
    let model: String
    let tokens: UsageTokenBreakdown?
    let referenceUSD: Double?
    let chargedUSD: Double?
}
struct CursorAccountUsage: Sendable {
    let id: String
    let email: String
    let plan: String
    let pools: [CursorQuotaPool]
    let onDemandUSD: Double?
    let scannedAt: Date
}

enum CursorUsageError: LocalizedError {
    case notLoggedIn, invalidIdentity, invalidResponse, unavailable(Int), incompleteHistory
    var errorDescription: String? {
        switch self {
        case .notLoggedIn: "请先在 Cursor 登录，再导入当前账号。"
        case .invalidIdentity: "Cursor 返回的账号与本机登录不一致，已停止读取。"
        case .invalidResponse: "Cursor 返回的数据无法验证，请稍后刷新。"
        case .unavailable(let status): "Cursor 请求失败（HTTP \(status)）。"
        case .incompleteHistory: "Cursor 历史记录在分页期间发生变化，请重试。未展示不完整合计。"
        }
    }
}

/// Read-only native session and HTTPS APIs, following CodexBar's published
/// endpoint contract. Does not read conversations or change Cursor's database.
actor CursorUsageService {
    static let shared = CursorUsageService()
    private var cachedEvents: (id: String, at: Date, events: [CursorUsageEventRecord])?
    private let session = BackgroundNetworkSession.shared

    private func nativeSession() throws -> (id: String, token: String) {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; throw CursorUsageError.notLoggedIn
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 1500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key='cursorAuth/accessToken' LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw CursorUsageError.notLoggedIn }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw CursorUsageError.notLoggedIn }
        let token = String(cString: bytes)
        return try Self.auth(token: token)
    }
    private static func auth(token: String) throws -> (id: String, token: String) {
        let pieces = token.split(separator: ".")
        guard pieces.count == 3 else { throw CursorUsageError.notLoggedIn }
        var encoded = String(pieces[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sub = payload["sub"] as? String,
              let id = sub.split(separator: "|").last.map(String.init), !id.isEmpty else { throw CursorUsageError.notLoggedIn }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard id.unicodeScalars.allSatisfy(allowed.contains) else { throw CursorUsageError.invalidIdentity }
        return (id, token)
    }
    private func request(_ path: String, auth: (id: String, token: String), body: [String: Any]? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://cursor.com" + path)!)
        request.timeoutInterval = 15
        request.setValue("WorkosCursorSessionToken=\(auth.id)%3A%3A\(auth.token)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CursorUsageError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 { throw CursorUsageError.notLoggedIn }
            throw CursorUsageError.unavailable(http.statusCode)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CursorUsageError.invalidResponse }
        return object
    }
    func loadAccount(values: [String: String]? = nil) async throws -> CursorAccountUsage {
        let auth: (id: String, token: String)
        if let values {
            guard let token = values["cursorAuth/accessToken"] else { throw CursorUsageError.notLoggedIn }
            auth = try Self.auth(token: token)
        } else { auth = try nativeSession() }
        let user = try await request("/api/auth/me", auth: auth)
        guard (user["sub"] as? String)?.split(separator: "|").last.map(String.init) == auth.id else { throw CursorUsageError.invalidIdentity }
        let summary = try await request("/api/usage-summary", auth: auth)
        let sand = try? await request("/api/dashboard/get-sand-usage-status", auth: auth, body: [:])
        let individual = summary["individualUsage"] as? [String: Any] ?? [:]
        let plan = individual["plan"] as? [String: Any] ?? [:]
        let reset = Self.date(summary["billingCycleEnd"])
        var pools = [("总计", "totalPercentUsed"), ("Cursor", "autoPercentUsed"), ("Third Party", "apiPercentUsed")].map { name, key in
            CursorQuotaPool(id: name, usedPercent: Self.number(plan[key]), reset: reset)
        }
        if sand?["hasNonZeroIncludedLimit"] as? Bool == true {
            pools.append(CursorQuotaPool(id: "Grok Bot", usedPercent: Self.number(sand?["usagePercent"]), reset: Self.date(sand?["nextResetTimestampUtc"])))
        }
        let demand = individual["onDemand"] as? [String: Any]
        if values == nil { guard try nativeSession().id == auth.id else { throw CursorUsageError.invalidIdentity } }
        return CursorAccountUsage(id: auth.id, email: user["email"] as? String ?? "Cursor", plan: summary["membershipType"] as? String ?? "Cursor", pools: pools, onDemandUSD: Self.number(demand?["used"]).map { $0 / 100 }, scannedAt: Date())
    }
    func loadSavedAccount(id: String) async throws -> CursorAccountUsage {
        guard let profile = try await CursorProfileRepository.shared.profiles().first(where: { $0.id == id }) else { throw CursorUsageError.notLoggedIn }
        let account = try await loadAccount(values: profile.values)
        guard account.id == id else { throw CursorUsageError.invalidIdentity }
        return account
    }

    private struct HistoryPage: Sendable {
        let records: [CursorUsageEventRecord]
        let count: Int
        let expected: Int
        let fingerprint: String
    }
    private func historyPage(_ page: Int, auth: (id: String, token: String), start: Date, end: Date) async throws -> HistoryPage {
        let payload = try await request("/api/dashboard/get-filtered-usage-events", auth: auth, body: ["page": page, "pageSize": 1000, "startDate": String(Int64(start.timeIntervalSince1970 * 1000)), "endDate": String(Int64(end.timeIntervalSince1970 * 1000))])
        if payload.isEmpty && page == 1 { return HistoryPage(records: [], count: 0, expected: 0, fingerprint: "empty") }
        guard let rows = payload["usageEventsDisplay"] as? [[String: Any]],
              let expected = Self.number(payload["totalUsageEventsCount"]), expected <= 200_000 else { throw CursorUsageError.invalidResponse }
        let records = rows.compactMap(Self.event)
        guard records.count == rows.count else { throw CursorUsageError.invalidResponse }
        let digest = SHA256.hash(data: try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys)).map { String(format: "%02x", $0) }.joined()
        return HistoryPage(records: records, count: rows.count, expected: Int(expected), fingerprint: digest)
    }
    func invalidateHistory() { cachedEvents = nil }
    private var pendingRefresh: HistoryRefresh?
    /// Applies to the next `dashboard(now:)` call only; `QuotaManagementPageModel`
    /// sets this so the shared protocol signature stays unchanged.
    func scheduleNextRefresh(_ refresh: HistoryRefresh) { pendingRefresh = refresh }

    /// How `loadEvents` may reuse the in-memory 30-day history.
    enum HistoryRefresh: Sendable {
        /// Return the cache when it is younger than five minutes.
        case cachedIfFresh
        /// Keep cached events older than yesterday and re-fetch only the tail
        /// (yesterday and today). Menu/window opens use this so a second look
        /// costs one small request instead of the full paged history.
        case incremental
        /// Discard the cache and page through the whole 30-day window.
        case full
    }

    /// Cached events at or after this instant are replaced on an incremental
    /// refresh. One extra day of overlap absorbs late-arriving events.
    static func incrementalWindowStart(cachedAt: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: cachedAt)) ?? cachedAt
    }

    /// Merges a freshly fetched tail into cached history: cached events older
    /// than `windowStart` survive, everything at or after it comes from `tail`,
    /// and events that fell out of the 30-day range (`rangeStart`) are dropped.
    static func mergeIncremental(cached: [CursorUsageEventRecord], tail: [CursorUsageEventRecord], windowStart: Date, rangeStart: Date) -> [CursorUsageEventRecord] {
        cached.filter { $0.date < windowStart && $0.date >= rangeStart } + tail
    }

    func loadEvents(now: Date = Date(), force: Bool = false) async throws -> [CursorUsageEventRecord] {
        try await loadEvents(now: now, refresh: force ? .full : .cachedIfFresh)
    }

    func loadEvents(now: Date = Date(), refresh: HistoryRefresh) async throws -> [CursorUsageEventRecord] {
        let auth = try nativeSession()
        let calendar = Calendar.current
        let rangeStart = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        let sameAccountCache = cachedEvents.flatMap { $0.id == auth.id ? $0 : nil }
        switch refresh {
        case .cachedIfFresh:
            if let sameAccountCache, now.timeIntervalSince(sameAccountCache.at) < 300 { return sameAccountCache.events }
        case .incremental:
            if let sameAccountCache, sameAccountCache.at <= now {
                let windowStart = max(rangeStart, Self.incrementalWindowStart(cachedAt: sameAccountCache.at, calendar: calendar))
                let tail = try await fetchRange(auth: auth, start: windowStart, end: now)
                guard try nativeSession().id == auth.id else { throw CursorUsageError.invalidIdentity }
                let merged = Self.mergeIncremental(cached: sameAccountCache.events, tail: tail, windowStart: windowStart, rangeStart: rangeStart)
                cachedEvents = (auth.id, now, merged)
                return merged
            }
        case .full:
            break
        }
        let output = try await fetchRange(auth: auth, start: rangeStart, end: now)
        guard try nativeSession().id == auth.id else { throw CursorUsageError.invalidIdentity }
        cachedEvents = (auth.id, now, output)
        return output
    }

    /// Pages through `[start, end]` and verifies the vendor's expected count.
    private func fetchRange(auth: (id: String, token: String), start: Date, end: Date) async throws -> [CursorUsageEventRecord] {
        let first = try await historyPage(1, auth: auth, start: start, end: end)
        let pages = max(1, (first.expected + 999) / 1000)
        var output = first.records, received = first.count
        var fingerprints: Set<String> = [first.fingerprint]
        if pages > 1 {
            // Four read-only requests at a time; never launch 200 unbounded requests.
            for startPage in stride(from: 2, through: pages, by: 4) {
                try Task.checkCancellation()
                let batch = try await withThrowingTaskGroup(of: HistoryPage.self) { group in
                    for page in startPage...min(pages, startPage + 3) {
                        group.addTask { try await self.historyPage(page, auth: auth, start: start, end: end) }
                    }
                    var results: [HistoryPage] = []
                    for try await result in group { results.append(result) }
                    return results
                }
                for result in batch {
                    guard result.expected == first.expected, result.count > 0,
                          fingerprints.insert(result.fingerprint).inserted else { throw CursorUsageError.incompleteHistory }
                    received += result.count; output.append(contentsOf: result.records)
                }
            }
        }
        guard received == first.expected else { throw CursorUsageError.incompleteHistory }
        return output
    }
    static func number(_ value: Any?) -> Double? {
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return number.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    }
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    static func event(_ object: [String: Any]) -> CursorUsageEventRecord? {
        guard let timestamp = number(object["timestamp"]), timestamp > 0 else { return nil }
        let raw = object["tokenUsage"] as? [String: Any]
        var tokens: UsageTokenBreakdown?
        if let input = number(raw?["inputTokens"]), let output = number(raw?["outputTokens"]), input < Double(Int.max) / 4, output < Double(Int.max) / 4 {
            let read = number(raw?["cacheReadTokens"]) ?? 0, write = number(raw?["cacheWriteTokens"]) ?? 0
            if read < Double(Int.max) / 4, write < Double(Int.max) / 4 {
                // Cursor counters are disjoint; normalize into the app's inclusive input convention.
                tokens = UsageTokenBreakdown(input: Int(input + read + write), cachedInput: Int(read), cacheWriteInput: Int(write), output: Int(output), reasoningOutput: 0)
            }
        }
        return CursorUsageEventRecord(date: Date(timeIntervalSince1970: timestamp / 1000), model: object["model"] as? String ?? "未知模型", tokens: tokens, referenceUSD: number(raw?["totalCents"]).map { $0 / 100 }, chargedUSD: number(object["chargedCents"]).map { $0 / 100 })
    }
}

extension CursorUsageService {
    func dashboard(now: Date) async throws -> QuotaDashboardSnapshot {
        let refresh = pendingRefresh ?? .cachedIfFresh
        pendingRefresh = nil
        let events = try await loadEvents(now: now, refresh: refresh)
        let calendar = Calendar.current, today = Calendar.current.startOfDay(for: now)
        var days: [Date: QuotaBucket] = [:], all = QuotaAggregate(), minutes: [Date: Int] = [:]
        var minuteBuckets: [Date: QuotaBucket] = [:]
        for event in events {
            var value = QuotaAggregate(); value.requests = 1
            if let tokens = event.tokens { value.tokens = tokens; value.reported = 1 }
            if let usd = event.referenceUSD, usd * 1e12 < Double(Int64.max) { value.reference.add(Int64((usd * 1e12).rounded())) }
            if let usd = event.chargedUSD, usd * 1e12 < Double(Int64.max) { value.metered.add(Int64((usd * 1e12).rounded())) }
            let day = calendar.startOfDay(for: event.date)
            days[day, default: QuotaBucket()].add(value, key: QuotaModelKey(provider: "Cursor", model: event.model))
            all.merge(value)
            if day == today {
                let minute = Date(timeIntervalSince1970: floor(event.date.timeIntervalSince1970 / 60) * 60)
                minutes[minute, default: 0] += value.tokens.total
                minuteBuckets[minute, default: QuotaBucket()].add(value, key: QuotaModelKey(provider: "Cursor", model: event.model))
            }
        }
        return QuotaDashboardSnapshot(scannedAt: cachedEvents?.at ?? now, days: days, all: all, source: "Cursor", pricingSources: ["https://cursor.com/dashboard"], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0, minuteTokens: minutes, minuteBuckets: minuteBuckets, pricingProvenance: [QuotaPricingProvenance(basis: .vendorReported, auditDate: nil)])
    }
}
