import Foundation

/// Bounded streaming JSONL reader. Retains neither a file-sized buffer nor
/// conversation bodies between lines. An oversized line is skipped as a whole;
/// the consumer is notified so it can invalidate model attribution safely.
enum UsageJSONLStream {
    static let maximumLineBytes = 1_048_576

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
            var start = chunk.startIndex
            while start < chunk.endIndex {
                let end = chunk[start...].firstIndex(of: 0x0A) ?? chunk.endIndex
                if !oversized {
                    if end - start > limit - pending.count {
                        oversized = true
                        pending.removeAll(keepingCapacity: true)
                    } else { pending.append(contentsOf: chunk[start..<end]) }
                }
                if end < chunk.endIndex { finishLine(); start = end + 1 }
                else { break }
            }
        }
        // A complete JSON object without a trailing newline remains usable;
        // malformed partial JSON is rejected by the metadata parser.
        finishLine()
    }
}
