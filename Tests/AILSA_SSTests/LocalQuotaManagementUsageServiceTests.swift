import Foundation
import XCTest
@testable import AILSA_SS

final class LocalQuotaManagementUsageServiceTests: XCTestCase {
    func testCodexCumulativeTokenRecordsUseDeltasAndLocalPricing() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write(
            """
            {"type":"session_meta","payload":{"session_id":"session-12345678","cwd":"/Users/example/ProjectA"}}
            {"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
            {"type":"event_msg","timestamp":"2026-09-14T02:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":10,"reasoning_output_tokens":3}}}}
            {"type":"event_msg","timestamp":"2026-09-14T03:00:00.000Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":160,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":25,"reasoning_output_tokens":5}}}}
            """,
            to: fixture.sessions.appendingPathComponent("rollout-2026-09-14.jsonl")
        )
        try write(
            """
            {"fetchedAt":"2026-09-14T00:00:00Z","catalog":{"providers":{"openai":{"models":{"gpt-5.6-sol":{"cost":{"input":4,"cache_read":0.4,"cache_write":5,"output":20}}}}}}}
            """,
            to: fixture.pricingCatalog
        )

        let service = LocalQuotaManagementUsageService(paths: fixture.paths)
        let data = try await service.loadData(
            for: .codex,
            historyDays: 30,
            now: date("2026-09-14T12:00:00Z")
        )
        guard case .codex(let analytics) = data else {
            return XCTFail("Expected Codex analytics")
        }

        XCTAssertEqual(analytics.records.count, 2)
        XCTAssertEqual(analytics.records.map(\.tokens.input), [100, 60])
        XCTAssertEqual(analytics.records.map(\.tokens.output), [10, 15])
        XCTAssertEqual(analytics.records.map(\.projectName), ["ProjectA", "ProjectA"])

        let totals = analytics.totals(on: date("2026-09-14T00:00:00Z"))
        XCTAssertEqual(totals.tokens.input, 160)
        XCTAssertEqual(totals.tokens.output, 25)
        XCTAssertEqual(totals.tokens.reasoningOutput, 5)
        XCTAssertEqual(totals.estimate.knownUSD, 0.00114, accuracy: 0.000_001)
        XCTAssertEqual(totals.estimate.unpricedRecordCount, 0)
    }

    func testUnknownRouteDoesNotInventAnApiEquivalentPrice() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write(
            """
            {"type":"turn_context","payload":{"model":"unattributed/router-model"}}
            {"type":"event_msg","timestamp":"2026-09-14T02:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":80,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":20,"reasoning_output_tokens":0}}}}
            """,
            to: fixture.sessions.appendingPathComponent("unknown-2026-09-14.jsonl")
        )

        let service = LocalQuotaManagementUsageService(paths: fixture.paths)
        let data = try await service.loadData(
            for: .codex,
            historyDays: 30,
            now: date("2026-09-14T12:00:00Z")
        )
        guard case .codex(let analytics) = data else {
            return XCTFail("Expected Codex analytics")
        }

        XCTAssertNil(analytics.records.first?.apiEquivalentUSD)
        XCTAssertEqual(analytics.totals(on: nil).estimate.unpricedRecordCount, 1)
        XCTAssertFalse(analytics.totals(on: nil).estimate.hasKnownEstimate)
    }

    func testNativeMetadataIdAndMissingCacheDoNotInventZeroReuse() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try write("""
        {"type":"session_meta","payload":{"id":"real-native-session-id"}}
        {"type":"turn_context","payload":{"model":"gpt-6-sol"}}
        {"type":"event_msg","timestamp":"2026-09-14T02:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10}}}}
        {"type":"event_msg","timestamp":"2026-09-14T03:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":200,"cached_input_tokens":20,"output_tokens":20}}}}
        {"type":"event_msg","timestamp":"2026-09-14T04:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"cached_input_tokens":20,"output_tokens":30}}}}
        """,to:fixture.sessions.appendingPathComponent("native-2026-09-14.jsonl"))
        let data=try await LocalQuotaManagementUsageService(paths:fixture.paths).loadData(
            for:.codex,historyDays:30,now:date("2026-09-14T12:00:00Z"))
        guard case .codex(let analytics)=data else { return XCTFail("Expected native fallback") }
        XCTAssertEqual(analytics.records.map(\.cacheBreakdownReported),[false,false,true])
        XCTAssertTrue(analytics.records.allSatisfy { $0.id.hasPrefix("real-native-session-id-") })
        let snapshot=QuotaDashboardSnapshot.build(data,now:date("2026-09-14T12:00:00Z"))
        XCTAssertEqual(snapshot.all.cacheReuse.samples,1)
        XCTAssertEqual(snapshot.all.cacheReuse.fraction,0)
        XCTAssertEqual(snapshot.all.tokens.total,330)
    }

    func testMetadataFilterPreservesEscapedNamesUnicodeAndCumulativeUsage() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let body = #"{"type":"response_item","payload":{"text":""# + String(repeating: "普通聊天正文 ", count: 3000) + #""}}"#
        try write([
            #"{"type":"session_\u006deta","payload":{"id":"escaped-session","cwd":"/projects/音乐"}}"#,
            #"{"type":"turn_\u0063ontext","payload":{"model":"gpt-6-sol"}}"#,
            body,
            #"{"type":"event_msg","timestamp":"2026-09-14T02:00:00Z","payload":{"type":"token_\u0063ount","info":{"total_token_usage":{"input_tokens":100,"cached_input_tokens":20,"output_tokens":10}}}}"#,
            #"{"type":"event_msg","timestamp":"2026-09-14T03:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":150,"cached_input_tokens":30,"output_tokens":15}}}}"#
        ].joined(separator: "\n"), to: fixture.sessions.appendingPathComponent("escaped-2026-09-14.jsonl"))
        let data = try await LocalQuotaManagementUsageService(paths: fixture.paths).loadData(
            for: .codex, historyDays: 30, now: date("2026-09-14T12:00:00Z"))
        guard case .codex(let analytics) = data else { return XCTFail("Expected native usage") }
        XCTAssertEqual(analytics.records.map(\.tokens.input), [100, 50])
        XCTAssertEqual(analytics.records.map(\.tokens.cachedInput), [20, 10])
        XCTAssertEqual(analytics.records.map(\.model), ["gpt-6-sol", "gpt-6-sol"])
        XCTAssertEqual(analytics.records.map(\.projectName), ["音乐", "音乐"])
        XCTAssertTrue(analytics.records.allSatisfy { $0.id.hasPrefix("escaped-session-") })
    }

    func testAntigravityHistoryRemainsQuotaOnly() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write(
            """
            {"version":1,"accounts":{"opaque-account-key":[{"name":"Gemini","windowMinutes":300,"entries":[{"capturedAt":"2026-09-14T01:00:00Z","resetsAt":"2026-09-14T06:00:00Z","usedPercent":42.5}]}]}}
            """,
            to: fixture.antigravityHistory
        )

        let service = LocalQuotaManagementUsageService(paths: fixture.paths)
        let data = try await service.loadData(
            for: .antigravity,
            historyDays: 30,
            now: date("2026-09-14T12:00:00Z")
        )
        guard case .antigravity(let analytics) = data else {
            return XCTFail("Expected AntiGravity analytics")
        }

        XCTAssertEqual(analytics.observations.count, 1)
        XCTAssertEqual(analytics.observations[0].usedPercent, 42.5)
        XCTAssertEqual(analytics.observations[0].windowMinutes, 300)
        XCTAssertEqual(analytics.latestDailyUsedPercent().first?.usedPercent, 42.5)
    }

    func testReadableOpenCodexLedgerIsPrimaryAndNeverMergesCodexSessions() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try write(
            """
            {"type":"turn_context","payload":{"model":"gpt-5.6-sol"}}
            {"type":"event_msg","timestamp":"2026-09-14T02:00:00Z","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":999,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":99,"reasoning_output_tokens":0}}}}
            """,
            to: fixture.sessions.appendingPathComponent("legacy-2026-09-14.jsonl")
        )
        try write(
            """
            {"requestId":"opencodex-one","timestamp":"2026-09-14T02:00:00Z","provider":"openai","requestedModel":"router/gpt","resolvedModel":"gpt-5.6-sol","requestedServiceTier":"fast","confirmedServiceTier":"fast","fastGranted":true,"usageStatus":"reported","usage":{"inputTokens":100,"outputTokens":10,"totalTokens":110}}
            """ + "\n",
            to: fixture.opencodexLedger
        )

        let service = LocalQuotaManagementUsageService(paths: fixture.paths)
        let data = try await service.loadData(
            for: .codex,
            historyDays: 30,
            now: date("2026-09-14T12:00:00Z")
        )
        guard case .openCodex(let analytics) = data else {
            return XCTFail("Expected ledger-primary OpenCodex analytics")
        }

        XCTAssertEqual(analytics.records.count, 1)
        XCTAssertEqual(analytics.records.first?.requestID, "opencodex-one")
        XCTAssertEqual(analytics.records.first?.tokens.inputTokens, 100)
        XCTAssertEqual(analytics.records.first?.tokens.outputTokens, 10)
        XCTAssertEqual(analytics.records.first?.pricing.status.rawValue, "price_unknown")
        XCTAssertEqual(analytics.coverage.codexSessionRowsAdded, 0)
    }

    private func makeFixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-ss-local-quota-tests-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        let archived = root.appendingPathComponent("archived", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        let pricingCatalog = root.appendingPathComponent("pricing.json", isDirectory: false)
        let opencodexLedger = root.appendingPathComponent("opencodex-usage.jsonl", isDirectory: false)
        let antigravityHistory = root.appendingPathComponent("antigravity.json", isDirectory: false)
        return Fixture(
            root: root,
            sessions: sessions,
            pricingCatalog: pricingCatalog,
            opencodexLedger: opencodexLedger,
            antigravityHistory: antigravityHistory,
            paths: QuotaManagementDataPaths(
                codexSessionsDirectory: sessions,
                codexArchivedSessionsDirectory: archived,
                codexBarPricingCatalogURL: pricingCatalog,
                opencodexUsageLedgerURL: opencodexLedger,
                antigravityQuotaHistoryURL: antigravityHistory,
                antigravityInfoPlistURL: root.appendingPathComponent("Antigravity-Info.plist", isDirectory: false)
            )
        )
    }

    private func write(_ text: String, to url: URL) throws {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "LocalQuotaManagementUsageServiceTests", code: 1)
        }
        try data.write(to: url)
    }

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }
}

private struct Fixture {
    let root: URL
    let sessions: URL
    let pricingCatalog: URL
    let opencodexLedger: URL
    let antigravityHistory: URL
    let paths: QuotaManagementDataPaths
}

final class UsageJSONLScanTests: XCTestCase {
    func testByteSearchMatchesReferenceAcrossSlicesAndBinaryBoundaries() {
        let samples: [[UInt8]] = [[], [0], [1, 2, 3], Array("aaaaab 世界 token_count".utf8), [255, 0, 255, 10]]
        let needles: [[UInt8]] = [[], [0], [10], [255, 0], Array("aaaab".utf8), Array("世界".utf8), Array("token_count".utf8), Array("missing".utf8)]
        for bytes in samples {
            let padded = Data([17, 18] + bytes + [19])
            let slice = padded[2..<(2 + bytes.count)]
            for needle in needles {
                let expected = needle.isEmpty || (needle.count <= bytes.count && (0...(bytes.count - needle.count)).contains { Array(bytes[$0..<($0 + needle.count)]) == needle })
                XCTAssertEqual(UsageJSONLStream.containsBytes(slice, needle), expected)
            }
        }
    }

    func testStreamingBoundariesOversizeCRLFAndUnterminatedLastLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("abc\n\n123456\nx\r\nlast".utf8).write(to: url)
        for chunk in [1, 2, 3, 8, 65_536] {
            var rows: [String] = []
            try UsageJSONLStream.read(url, chunkBytes: chunk, lineLimit: 4) { data in
                rows.append(data.flatMap { String(data: $0, encoding: .utf8) } ?? "<oversize>")
            }
            XCTAssertEqual(rows, ["abc", "<oversize>", "x\r", "last"])
        }
    }

    func testFilterOnlySkipsRowsWithoutUsageOrEncodingMarkers() {
        XCTAssertFalse(UsageJSONLStream.mayContainCodexUsage(Data(#"{"type":"response_item","payload":{"text":"ordinary prose"}}"#.utf8)))
        XCTAssertTrue(UsageJSONLStream.mayContainCodexUsage(Data(#"{"type":"turn_\u0063ontext"}"#.utf8)))
        XCTAssertTrue(UsageJSONLStream.mayContainCodexUsage(Data(#"{"type":"event_msg","payload":{"type":"token_count"}}"#.utf8)))
        XCTAssertTrue(UsageJSONLStream.mayContainCodexUsage(Data([0, 123, 0, 125])))
    }
}
