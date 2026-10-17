import Foundation
import Darwin

/// Bounded streaming JSONL reader. Retains neither a file-sized buffer nor
/// conversation bodies between lines. An oversized line is skipped as a whole;
/// the consumer is notified so it can invalidate model attribution safely.
enum UsageJSONLStream {
    static let maximumLineBytes = 1_048_576

    private static let metadataMarkers = ["session_meta", "turn_context", "token_count", "\\u"]
        .map { Array($0.utf8) }

    /// A cheap rejection filter, never a replacement for JSON parsing. Escaped
    /// JSON names and non-UTF8 encodings take the full parser path as before.
    static func mayContainCodexUsage(_ line: Data) -> Bool {
        if containsBytes(line, [0]) { return true }
        return metadataMarkers.contains { containsBytes(line, $0) }
    }

    /// Adapted from CodexBar #4552 (MIT). Raw offsets also work with Data slices
    /// whose collection indices do not start at zero. All reads are bounded.
    static func containsBytes(_ data: Data, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard needle.count <= data.count else { return false }
        return data.withUnsafeBytes { haystack in
            needle.withUnsafeBytes { pattern in
                guard let base = haystack.baseAddress, let patternBase = pattern.baseAddress else { return false }
                let limit = haystack.count - pattern.count + 1
                var offset = 0
                while offset < limit {
                    guard let candidate = memchr(base.advanced(by: offset), Int32(needle[0]), limit - offset) else { return false }
                    if memcmp(candidate, patternBase, pattern.count) == 0 { return true }
                    offset = base.distance(to: UnsafeRawPointer(candidate)) + 1
                }
                return false
            }
        }
    }

    static func read(_ url: URL, chunkBytes: Int = 65_536,
                     lineLimit: Int = maximumLineBytes,
                     consume: (Data?) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var pending = Data()
        var oversized = false
        let limit = max(1, lineLimit)
        func finishLine() {
            if oversized { consume(nil) }
            else if !pending.isEmpty { consume(pending) }
            pending.removeAll(keepingCapacity: true)
            oversized = false
        }
        while let chunk = try handle.read(upToCount: max(1, chunkBytes)), !chunk.isEmpty {
            chunk.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var start = 0
                while start < bytes.count {
                    let newline = memchr(base.advanced(by: start), 0x0A, bytes.count - start)
                    let end = newline.map { base.distance(to: UnsafeRawPointer($0)) } ?? bytes.count
                    if !oversized {
                        if end - start > limit - pending.count {
                            oversized = true
                            pending.removeAll(keepingCapacity: true)
                        } else {
                            pending.append(base.advanced(by: start).assumingMemoryBound(to: UInt8.self), count: end - start)
                        }
                    }
                    if newline != nil { finishLine(); start = end + 1 }
                    else { break }
                }
            }
        }
        // A complete JSON object without a trailing newline remains usable;
        // malformed partial JSON is rejected by the metadata parser.
        finishLine()
    }
}
