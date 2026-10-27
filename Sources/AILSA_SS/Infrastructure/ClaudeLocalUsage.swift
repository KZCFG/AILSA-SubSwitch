import Foundation
import CryptoKit
import Darwin

/// Offline API equivalence, not a subscription charge. No network client or
/// credential access is reachable from this reader or its bundled rate table.
enum ClaudeLocalPricing {
    static let source = "https://claude.com/pricing"
    static let auditDate = "2026-10-27"

    struct Usage: Decodable, Equatable, Sendable {
        struct Creation: Decodable, Equatable, Sendable {
            let ephemeral_5m_input_tokens: Int?
            let ephemeral_1h_input_tokens: Int?
        }
        struct Output: Decodable, Equatable, Sendable { let thinking_tokens: Int? }
        let input_tokens: Int
        let output_tokens: Int
        let cache_creation_input_tokens: Int
        let cache_read_input_tokens: Int
        let cache_creation: Creation?
        let output_tokens_details: Output?
        let speed: String?
        let inference_geo: String?

        var tokens: UsageTokenBreakdown? {
            let values = [input_tokens, cache_creation_input_tokens, cache_read_input_tokens, output_tokens]
            guard values.allSatisfy({ $0 >= 0 }),
                  let totalInput = ClaudeLocalPricing.sum(Array(values.prefix(3))),
                  ClaudeLocalPricing.sum([totalInput, output_tokens]) != nil,
                  (0...output_tokens).contains(output_tokens_details?.thinking_tokens ?? 0)
            else { return nil }
            return UsageTokenBreakdown(input: totalInput, cachedInput: cache_read_input_tokens,
                cacheWriteInput: cache_creation_input_tokens, output: output_tokens,
                reasoningOutput: output_tokens_details?.thinking_tokens ?? 0)
        }
    }

    private struct Rate {
        // picoUSD per token; $1/MTok = 1,000,000 picoUSD/token.
        let input: Int64, output: Int64, read: Int64
    }
    private static let rates: [String: Rate] = [
        "claude-opus-5-5": Rate(input: 4_000_000, output: 20_000_000, read: 200_000),
        "claude-sonnet-5-5": Rate(input: 2_000_000, output: 10_000_000, read: 100_000),
        "claude-haiku-5-5": Rate(input: 100_000, output: 500_000, read: 10_000),
        "claude-fable-5-1": Rate(input: 10_000_000, output: 50_000_000, read: 250_000),
        "claude-mythos-5-1": Rate(input: 10_000_000, output: 50_000_000, read: 250_000),
        "claude-opus-5": Rate(input: 5_000_000, output: 25_000_000, read: 500_000),
        "claude-opus-4-8": Rate(input: 5_000_000, output: 25_000_000, read: 500_000),
        "claude-opus-4-7": Rate(input: 5_000_000, output: 25_000_000, read: 500_000),
        "claude-opus-4-6": Rate(input: 5_000_000, output: 25_000_000, read: 500_000),
        "claude-sonnet-5": Rate(input: 2_000_000, output: 10_000_000, read: 200_000),
        "claude-opus-4-5": Rate(input: 5_000_000, output: 25_000_000, read: 500_000),
        "claude-sonnet-4-5": Rate(input: 3_000_000, output: 15_000_000, read: 300_000),
        "claude-sonnet-4-6": Rate(input: 3_000_000, output: 15_000_000, read: 300_000),
        "claude-haiku-4-5": Rate(input: 1_000_000, output: 5_000_000, read: 100_000)
    ]
    static func canonical(_ model: String) -> String {
        // Antigravity exports effort options as suffixes of a known model.
        // Remove only documented option names, never a fuzzy model prefix.
        var parts=model.lowercased().split(separator:"-").map(String.init)
        let options:Set<String>=["none","low","medium","high","xhigh","max","ultra","thinking"]
        while let last=parts.last,options.contains(last) {parts.removeLast()}
        let name=parts.joined(separator:"-")
        if rates[name] != nil { return name }
        // Only an exact model followed by an eight-digit dated version.
        if let dash = name.lastIndex(of: "-") {
            let suffix = name[name.index(after: dash)...], base = String(name[..<dash])
            if suffix.count == 8, suffix.allSatisfy({ $0.isASCII && $0.isNumber }), rates[base] != nil { return base }
        }
        return name
    }
    static func referenceRate(_ model:String) -> (input:Int64,read:Int64,output:Int64)? {
        guard let rate=rates[canonical(model)] else{return nil}
        return (rate.input,rate.read,rate.output)
    }
    static func displayName(_ model: String) -> String {
        let id = canonical(model), parts = id.split(separator: "-")
        guard rates[id] != nil, parts.count >= 3 else { return model }
        return "Claude " + parts[1].capitalized + " " + parts.dropFirst(2).joined(separator: ".")
    }
    static func amount(model: String, usage: Usage) -> Int64? {
        guard let tokens = usage.tokens else { return nil }
        let id = canonical(model)
        guard let base = rates[id] else { return nil }
        let speed = usage.speed ?? "standard"
        guard ["standard", "fast"].contains(speed) else { return nil }
        let fastModels = ["claude-opus-5-5", "claude-opus-5", "claude-opus-4-8"]
        guard speed != "fast" || fastModels.contains(id) else { return nil }
        let geo = usage.inference_geo ?? "global"
        guard ["global", "not_available", "us"].contains(geo),
              geo != "us" || id != "claude-haiku-4-5" else { return nil }
        let creation = usage.cache_creation
        let five = creation?.ephemeral_5m_input_tokens ?? 0
        let hour = creation?.ephemeral_1h_input_tokens ?? 0
        guard five >= 0, hour >= 0, sum([five, hour]) == usage.cache_creation_input_tokens else { return nil }
        let contextMultiplier: Int64 = id == "claude-haiku-5-5" && tokens.input > 100_000 ? 5 : 1
        let multiplier = contextMultiplier * (speed == "fast" ? 2 : 1)
        let counts = [usage.input_tokens, usage.output_tokens, usage.cache_read_input_tokens, five, hour]
        let perToken = [base.input, base.output, base.read, base.input * 5 / 4, base.input * 2]
        var total: Int64 = 0
        for (count, rate) in zip(counts, perToken) {
            let value = Int64(count).multipliedReportingOverflow(by: rate * multiplier)
            guard !value.overflow else { return nil }
            let next = total.addingReportingOverflow(value.partialValue)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        if geo == "us" {
            let premium = total.multipliedReportingOverflow(by: 11)
            guard !premium.overflow else { return nil }
            return premium.partialValue / 10
        }
        return total
    }
    private static func sum(_ values: [Int]) -> Int? {
        var total = 0
        for value in values {
            let next = total.addingReportingOverflow(value)
            guard !next.overflow else { return nil }
            total = next.partialValue
        }
        return total
    }
}

struct ClaudeLocalUsageAnalytics: Equatable, Sendable {
    let contributions: [String: QuotaContribution]
    let discarded: Int
    let sourceAvailable: Bool

    func snapshot(now: Date, historyDays: Int = 30) -> QuotaDashboardSnapshot {
        var result = QuotaDashboardSnapshot.compact(contributions.values, discarded: discarded,
            now: now, pricingProvenance: [.init(basis: .claudeLocalReference, auditDate: ClaudeLocalPricing.auditDate)],
            source: sourceAvailable ? "Claude App · Local logs" : "Claude App · No local Code logs", historyDays: historyDays)
        result = QuotaDashboardSnapshot(scannedAt: result.scannedAt, days: result.days, all: result.all,
            source: result.source, pricingSources: [ClaudeLocalPricing.source], discardedRows: result.discardedRows,
            quotaWindows: [], quotaTrend: [:], buildMilliseconds: result.buildMilliseconds,
            minuteTokens: result.minuteTokens, minuteBuckets: result.minuteBuckets, pricingProvenance: result.pricingProvenance)
        return result
    }
}

/// Reads only Code sessions vouched for by Claude Desktop's local session
/// index. Decodable projections skip conversation bodies and system prompts.
/// Cache entries retain metadata and numeric usage only. No auth, cookies,
/// keychain, quota endpoints, or Claude process control are used.
struct ClaudeLocalUsageReader: Sendable {
    private struct Session: Decodable { let cliSessionId: String? }
    private struct Frame: Decodable {
        struct Message: Decodable {
            let id: String?, model: String?, usage: ClaudeLocalPricing.Usage?
        }
        let type: String?, entrypoint: String?, sessionId: String?, requestId: String?, timestamp: String?
        let message: Message?
    }
    private struct Entry: Sendable {
        let at: Date, model: String
        let usage: ClaudeLocalPricing.Usage
        var contribution: QuotaContribution {
            var value = QuotaAggregate(); value.requests = 1; value.reported = 1
            value.tokens = usage.tokens!
            value.cacheReuse.observe(input: value.tokens.input, cachedInput: value.tokens.cachedInput)
            value.reference.add(ClaudeLocalPricing.amount(model: model, usage: usage))
            value.states[value.reference.count > 0 ? "reference_estimate" : "unknown_price"] = 1
            return QuotaContribution(minute: Date(timeIntervalSince1970: floor(at.timeIntervalSince1970 / 60) * 60),
                day: Calendar.current.startOfDay(for: at), key: .init(provider: "Claude", model: model), value: value)
        }
    }
    private struct FileState: Sendable {
        var identity = "", modified: Date?
        var offset: UInt64 = 0
        var boundaryHash = Data()
        var entries: [String: Entry] = [:]
        var discarded = 0
    }
    private var files: [URL: FileState] = [:]
    private var sessionIDs = Set<String>()
    private(set) var bytesRead: UInt64 = 0

    mutating func read(sessionsDirectory: URL?, projectsDirectory: URL?) throws -> ClaudeLocalUsageAnalytics {
        guard let sessionsDirectory, let projectsDirectory else {
            return .init(contributions: [:], discarded: 0, sourceAvailable: false)
        }
        let manager = FileManager.default
        guard manager.fileExists(atPath: sessionsDirectory.path), manager.fileExists(atPath: projectsDirectory.path) else {
            files = [:]; sessionIDs = []
            return .init(contributions: [:], discarded: 0, sourceAvailable: false)
        }
        let decoder = JSONDecoder()
        var allowed = Set<String>()
        for url in Self.regularFiles(sessionsDirectory, extension: "json") {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            guard size <= 1_048_576,
                  let data = try? Data(contentsOf: url), let session = try? decoder.decode(Session.self, from: data),
                  let id = session.cliSessionId, UUID(uuidString: id) != nil else { continue }
            allowed.insert(id)
        }
        if allowed != sessionIDs { files = [:]; sessionIDs = allowed }
        let urls = Self.regularFiles(projectsDirectory, extension: "jsonl")
        files = files.filter { urls.contains($0.key) }
        bytesRead = 0
        var unavailable = 0
        for url in urls {
            try Task.checkCancellation()
            // A subagent log is eligible only through its indexed parent. Its
            // own session and desktop entrypoint are still checked per frame.
            let parent = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            guard allowed.contains(url.deletingPathExtension().lastPathComponent) || allowed.contains(parent) else { continue }
            do { try readFile(url, allowed: allowed, decoder: decoder) }
            catch is CancellationError { throw CancellationError() }
            catch { files[url] = nil; unavailable += 1 }
        }
        var combined: [String: Entry] = [:]
        var discarded = unavailable
        for file in files.values {
            discarded += file.discarded
            for (id, entry) in file.entries {
                if let old = combined[id] {
                    discarded += 1
                    if entry.at >= old.at { combined[id] = entry }
                } else { combined[id] = entry }
            }
        }
        return .init(contributions: combined.mapValues(\.contribution), discarded: discarded, sourceAvailable: true)
    }

    private mutating func readFile(_ url: URL, allowed: Set<String>, decoder: JSONDecoder) throws {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let identity = "\(attrs[.systemNumber] ?? 0):\(attrs[.systemFileNumber] ?? 0):\(TimeZone.current.identifier)"
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = attrs[.modificationDate] as? Date
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var state = files[url] ?? FileState()
        var reset = state.identity != identity || size < state.offset
            || (size == state.offset && modified != state.modified)
        if !reset && state.offset > 0 {
            try handle.seek(toOffset: state.offset - min(state.offset, 256))
            let boundary = try handle.read(upToCount: Int(min(state.offset, 256))) ?? Data()
            reset = Data(SHA256.hash(data: boundary)) != state.boundaryHash
        }
        if reset { state = FileState(identity: identity) }
        state.modified = modified
        try handle.seek(toOffset: state.offset)
        var pending = Data(), oversized = false
        var position = state.offset, lineStart = state.offset
        while position < size {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: Int(min(262_144, size - position))), !chunk.isEmpty else { break }
            bytesRead += UInt64(chunk.count)
            chunk.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var start = 0
                while start < bytes.count {
                    let newline = memchr(base.advanced(by: start), 10, bytes.count - start)
                    let end = newline.map { base.distance(to: UnsafeRawPointer($0)) } ?? bytes.count
                    if !oversized {
                        if end - start > 4_194_304 - pending.count { pending.removeAll(keepingCapacity: true); oversized = true }
                        else { pending.append(base.advanced(by: start).assumingMemoryBound(to: UInt8.self), count: end - start) }
                    }
                    guard newline != nil else { break }
                    if oversized { state.discarded += 1 }
                    else { Self.consume(pending, state: &state, allowed: allowed, decoder: decoder) }
                    pending.removeAll(keepingCapacity: true); oversized = false
                    lineStart = position + UInt64(end + 1); state.offset = lineStart
                    start = end + 1
                }
            }
            position += UInt64(chunk.count)
        }
        // An unterminated live append is retried on the next refresh.
        if state.offset > 0 {
            try handle.seek(toOffset: state.offset - min(state.offset, 256))
            state.boundaryHash = Data(SHA256.hash(data: try handle.read(upToCount: Int(min(state.offset, 256))) ?? Data()))
        }
        files[url] = state
    }
    private static func consume(_ data: Data, state: inout FileState, allowed: Set<String>, decoder: JSONDecoder) {
        // Cheap rejection avoids parsing large user/tool/image frames.
        guard UsageJSONLStream.containsBytes(data, Array("usage".utf8))
                || UsageJSONLStream.containsBytes(data, Array("\\u".utf8)) else { return }
        guard let frame = try? decoder.decode(Frame.self, from: data) else { state.discarded += 1; return }
        guard frame.type == "assistant", frame.entrypoint == "claude-desktop",
              let session = frame.sessionId, allowed.contains(session),
              let message = frame.message, let model = message.model, model != "<synthetic>",
              let usage = message.usage else { return }
        guard let request = frame.requestId, !request.isEmpty, let id = message.id, !id.isEmpty,
              usage.tokens != nil, let timestamp = frame.timestamp,
              let date = parseDate(timestamp) else { state.discarded += 1; return }
        let key = "\(request.count):\(request)\(id)"
        if let old = state.entries[key] {
            state.discarded += 1
            if date >= old.at { state.entries[key] = Entry(at: date, model: model, usage: usage) }
        } else { state.entries[key] = Entry(at: date, model: model, usage: usage) }
    }
    private static func parseDate(_ value: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value))
            ?? (try? Date.ISO8601FormatStyle().parse(value))
    }
    private static func regularFiles(_ root: URL, extension suffix: String) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
            if values.isRegularFile == true && url.pathExtension == suffix { result.append(url) }
        }
        return result.sorted { $0.path < $1.path }
    }
}
