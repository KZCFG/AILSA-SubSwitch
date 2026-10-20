import Foundation
import CryptoKit

enum QuotaActivationFamily: String, Codable, CaseIterable, Sendable {
    case gemini, claude

    static func identify(_ text: String) -> Self? {
        let text = text.lowercased()
        if text.contains("gemini") { return .gemini }
        if text.contains("claude") || text.contains("gpt") { return .claude }
        return nil
    }
}

/// One durable claim before sending, including ambiguous failures; refreshes never count as requests.
struct QuotaActivationPlanner {
    struct Entry: Codable, Equatable {
        var dueAt: Int64
        var attemptedAt: Int64?
        var outcome: String?
        var model: String?
        var inputTokens: Int64?
        var outputTokens: Int64?
    }
    let path: URL
    var jitter: () -> Int64 = { Int64.random(in: 60...300) }

    init(path: URL? = nil, jitter: @escaping () -> Int64 = { Int64.random(in: 60...300) }) {
        self.path = path ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/CodexToolsSwift/quota-activation.json")
        self.jitter = jitter
    }

    static func withinHours(_ settings: AppSettings, now: Date, calendar: Calendar = .autoupdatingCurrent) -> Bool {
        let hour = calendar.component(.hour, from: now)
        let start = settings.quotaWindowActivationStartHour
        let end = settings.quotaWindowActivationEndHour
        return start == end || (start < end ? hour >= start && hour < end : hour >= start || hour < end)
    }

    static func readyFamilies(_ usage: UsageSnapshot?, now: Int64) -> [QuotaActivationFamily] {
        guard let usage, now >= usage.fetchedAt, now - usage.fetchedAt <= 120 else { return [] }
        return (usage.quotaFamilies ?? []).compactMap { family in
            guard let kind = QuotaActivationFamily.identify(family.id + " " + family.displayName) else { return nil }
            let short = family.buckets.filter { $0.windowSeconds == QuotaCountdownState.fiveHourWindowSeconds }
            guard !short.isEmpty, short.allSatisfy({ $0.isUsageKnown && $0.usedPercent == 0 && $0.countdownStartEvidence == nil }),
                  !family.buckets.contains(where: { $0.isUsageKnown && ($0.usedPercent ?? 0) >= 100 && ($0.resetAt ?? 0) > now }) else { return nil }
            return kind
        }
    }

    private func key(_ account: String, _ family: QuotaActivationFamily) -> String {
        SHA256.hash(data: Data((account + "\u{0}" + family.rawValue).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func load() throws -> [String: Entry] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        return try JSONDecoder().decode([String: Entry].self, from: Data(contentsOf: path))
    }

    private func save(_ entries: [String: Entry]) throws {
        try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: path, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }

    /// Checks arm a staggered schedule. A pending task stores no request content or credentials.
    func claimIfDue(account: String, family: QuotaActivationFamily, now: Int64) throws -> Bool {
        var entries = try load()
        let id = key(account, family)
        if let last = entries[id]?.attemptedAt, now < last + 5 * 3600 { return false }
        if entries[id] == nil || entries[id]?.attemptedAt != nil {
            entries[id] = Entry(dueAt: now + max(1, jitter()))
            try save(entries)
            return false
        }
        guard let due = entries[id]?.dueAt, now >= due else { return false }
        // A sleeping Mac or closed work period must not release a catch-up burst on resume.
        if now > due + 5 * 60 {
            entries[id] = Entry(dueAt: now + max(1, jitter()))
            try save(entries)
            return false
        }
        entries[id]?.attemptedAt = now
        entries[id]?.outcome = "attempted"
        try save(entries)
        return true
    }

    func record(account: String, family: QuotaActivationFamily, outcome: String, model: String? = nil,
                inputTokens: Int64? = nil, outputTokens: Int64? = nil) throws {
        var entries = try load()
        entries[key(account, family)]?.outcome = outcome
        if let model { entries[key(account, family)]?.model = model }
        if let inputTokens { entries[key(account, family)]?.inputTokens = inputTokens }
        if let outputTokens { entries[key(account, family)]?.outputTokens = outputTokens }
        try save(entries)
    }
}
