import Foundation
import XCTest
@testable import AILSA_SS

final class UsageCacheReuseTests: XCTestCase {
    func testMissingCacheIsUnknownButReportedZeroIsMeasured() {
        var a = UsageCacheReuse()
        a.observe(input: 100, cachedInput: nil)
        XCTAssertNil(a.fraction)
        XCTAssertEqual(a.samples, 0)
        a.observe(input: 200, cachedInput: 0)
        XCTAssertEqual(a.fraction, 0)
        XCTAssertEqual(a.samples, 1)
        a.observe(input: 50, cachedInput: 51)
        a.observe(input: 50, cachedInput: -1)
        XCTAssertEqual(a.samples, 1)
    }
    func testMergedRateUsesOnlyValidSampleInputAndDoesNotAddToTokenTotal() {
        var a = QuotaAggregate()
        a.reported = 2
        a.tokens = .init(input: 300, cachedInput: 75, cacheWriteInput: 0, output: 40, reasoningOutput: 10)
        a.cacheReuse.observe(input: 100, cachedInput: nil)
        a.cacheReuse.observe(input: 200, cachedInput: 75)
        var b = QuotaAggregate(); b.reported = 1
        b.tokens = .init(input: 100, cachedInput: 75, cacheWriteInput: 0, output: 10, reasoningOutput: 0)
        b.cacheReuse.observe(input: 100, cachedInput: 75)
        a.merge(b)
        XCTAssertEqual(a.cacheReuse.fraction, 0.5)
        XCTAssertEqual(a.cacheReuse.samples, 2)
        XCTAssertEqual(a.reported, 3)
        XCTAssertEqual(a.tokens.total, 450)
    }
    func testLedgerCachePresenceSurvivesCompactAggregationAndHoverBucket() throws {
        func row(_ id: String, cache: Int?) throws -> String {
            var usage = ["inputTokens": 100, "outputTokens": 20]
            if let cache { usage["cachedInputTokens"] = cache }
            let json: [String: Any] = ["requestId":id, "timestamp":"2026-10-13T02:00:00Z",
                "provider":"openai", "resolvedModel":"gpt-6-sol", "usageStatus":"reported", "usage":usage]
            return String(decoding: try JSONSerialization.data(withJSONObject:json), as:UTF8.self)
        }
        let records = AILSA_SSLedgerMeteringReader(pricingCatalog:.empty)
            .read(data: Data([try row("missing",cache:nil),try row("zero",cache:0),try row("hit",cache:50)].joined(separator:"\n").utf8)).records
        var bucket = QuotaBucket()
        for r in records { let c=QuotaDashboardSnapshot.contribution(r); bucket.add(c.value,key:c.key) }
        XCTAssertEqual(bucket.total.cacheReuse.samples,2)
        XCTAssertEqual(bucket.total.cacheReuse.fraction,0.25)
        XCTAssertEqual(bucket.models.values.first?.cacheReuse,bucket.total.cacheReuse)
        XCTAssertEqual(bucket.total.tokens.total,360)
    }
    func testStreamBoundsHugeLineAndPreservesChunkAndEOFBoundaries() throws {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:url) }
        try Data(("first\n"+String(repeating:"x",count:10_000)+"\nlast").utf8).write(to:url)
        var lines:[String?]=[]
        try UsageJSONLStream.read(url,chunkBytes:7,lineLimit:16) { lines.append($0.map { String(decoding:$0,as:UTF8.self) }) }
        XCTAssertEqual(lines,["first",nil,"last"])
    }
}
