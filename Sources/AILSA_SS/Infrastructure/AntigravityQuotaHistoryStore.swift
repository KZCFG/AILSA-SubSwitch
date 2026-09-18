import Foundation
import CryptoKit

/// Contains quota observations only, never authentication JSON or email.
/// One latest observation per account / window / local day bounds storage.
enum AntigravityQuotaHistoryStore {
    private static let queue = DispatchQueue(label: "com.alick.copool.quota-history", qos: .utility)
    private struct Row: Codable {
        let account: String
        let window: String
        let captured: Date
        let reset: Date?
        let seconds: Int
        let percent: Double
    }
    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexToolsSwift/quota-history/antigravity-v1.json")
    }
    private static func identity(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func record(_ store: AccountsStore) {
        // Extract non-secret fields before crossing the asynchronous boundary.
        let rows = store.accounts.filter { $0.provider == .antigravity && $0.displayStatus != .deleted }.flatMap { account -> [Row] in
            guard let usage = account.usage, usage.hasAuthoritativeQuota, usage.sourceAccountMatched == true else { return [] }
            return usage.knownQuotaBuckets.compactMap { bucket in
                guard let percent = bucket.usedPercent, percent.isFinite, percent >= 0 else { return nil }
                return Row(account: identity(account.id), window: bucket.id, captured: Date(timeIntervalSince1970: Double(usage.fetchedAt)), reset: bucket.resetAt.map { Date(timeIntervalSince1970: Double($0)) }, seconds: Int(bucket.windowSeconds ?? 0), percent: percent)
            }
        }
        queue.async {
            let saved = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([Row].self, from: $0) } ?? []
            let start = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            var latest: [String: Row] = [:]
            for row in saved + rows where row.captured >= start {
                let key = row.account + "/" + row.window + "/" + String(Calendar.current.startOfDay(for: row.captured).timeIntervalSince1970)
                if latest[key].map({ $0.captured < row.captured }) ?? true { latest[key] = row }
            }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(Array(latest.values))
                try data.write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch { /* History failure never changes the saved account or its quota. */ }
        }
    }
    static func readCurrent(now: Date) throws -> [AntigravityQuotaObservation] {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CodexToolsSwift/accounts.json")
        let store = try JSONDecoder().decode(AccountsStore.self, from: Data(contentsOf: path))
        record(store)
        queue.sync {} // actor caller waits off the UI thread for pending observations.
        guard let id = store.currentAntigravityAccountID else { return [] }
        let rows = try JSONDecoder().decode([Row].self, from: Data(contentsOf: url))
        return rows.filter { $0.account == identity(id) }.map {
            AntigravityQuotaObservation(id: $0.account + $0.window + String($0.captured.timeIntervalSince1970), capturedAt: $0.captured, resetAt: $0.reset, windowName: $0.window, windowMinutes: $0.seconds / 60, usedPercent: $0.percent)
        }
    }
}
