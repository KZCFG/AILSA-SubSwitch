import Foundation
import XCTest
@testable import AILSA_SS

final class ClaudeLocalUsageTests: XCTestCase {
    private let session = "E48F37DA-9893-469B-A517-ABF3E903257E"
    private func fixture() throws -> (URL, URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sessions = root.appendingPathComponent("desktop"), projects = root.appendingPathComponent("projects")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projects, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["cliSessionId": session, "title": "PRIVATE_TITLE"])
            .write(to: sessions.appendingPathComponent("index.json"))
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (sessions, projects, projects.appendingPathComponent(session + ".jsonl"))
    }
    private func usage(_ input: Int = 1000, read: Int = 4000, five: Int = 2000, hour: Int = 3000,
                       output: Int = 100, speed: String = "standard", geo: String = "global") -> [String: Any] {
        ["input_tokens": input, "output_tokens": output, "cache_read_input_tokens": read,
         "cache_creation_input_tokens": five + hour,
         "cache_creation": ["ephemeral_5m_input_tokens": five, "ephemeral_1h_input_tokens": hour],
         "output_tokens_details": ["thinking_tokens": 50], "speed": speed, "inference_geo": geo]
    }
    private func line(_ id: String = "one", at: String = "2026-10-22T10:00:00.123Z",
                      model: String = "claude-opus-5-5", entrypoint: String = "claude-desktop",
                      sourceSession: String? = nil, counts: [String: Any]? = nil) throws -> String {
        let root: [String: Any] = ["type": "assistant", "entrypoint": entrypoint,
            "sessionId": sourceSession ?? session, "requestId": "req-" + id, "timestamp": at,
            "message": ["id": "msg-" + id, "model": model, "usage": counts ?? usage(),
                        "content": [["type": "text", "text": "PRIVATE_CHAT_CONTENT"]]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self) + "\n"
    }
    private func decode(_ counts: [String: Any]) throws -> ClaudeLocalPricing.Usage {
        try JSONDecoder().decode(ClaudeLocalPricing.Usage.self, from: JSONSerialization.data(withJSONObject: counts))
    }
    func testNativeDisjointTokenCategoriesAndCacheWriteLifetimes() throws {
        let u = try decode(usage())
        XCTAssertEqual(u.tokens?.input, 10_000)
        XCTAssertEqual(u.tokens?.total, 10_100)
        XCTAssertEqual(u.tokens?.reasoningOutput, 50)
        // 1000*4 + 4000*.2 + 2000*5 + 3000*8 + 100*20 / 1M.
        XCTAssertEqual(ClaudeLocalPricing.amount(model: "claude-opus-5-5", usage: u), 40_800_000_000)
    }
    func testFastAndUSMultipliersAndExactModelVersions() throws {
        XCTAssertEqual(ClaudeLocalPricing.amount(model: "claude-opus-5-5", usage: try decode(usage(speed: "fast"))), 81_600_000_000)
        XCTAssertEqual(ClaudeLocalPricing.amount(model: "claude-opus-5-5-20261001", usage: try decode(usage(geo: "us"))), 44_880_000_000)
        XCTAssertNil(ClaudeLocalPricing.amount(model: "claude-opus-5-50", usage: try decode(usage())))
        XCTAssertNil(ClaudeLocalPricing.amount(model: "claude-sonnet-5-5", usage: try decode(usage(speed: "fast"))))
    }
    func testHaikuLongPromptUsesAllInputIncludingCacheReads() throws {
        let a = try decode(usage(1000, read: 99_000, five: 0, hour: 0))
        let b = try decode(usage(1000, read: 99_001, five: 0, hour: 0))
        XCTAssertEqual(ClaudeLocalPricing.amount(model: "claude-haiku-5-5", usage: a), 1_140_000_000)
        XCTAssertEqual(ClaudeLocalPricing.amount(model: "claude-haiku-5-5", usage: b), 5_700_050_000)
    }
    func testMissingCreationTTLDoesNotInventAmountAndInvalidUsageDoesNotInventTokens() throws {
        var missing = usage(); missing["cache_creation"] = nil
        let partial = try decode(missing)
        XCTAssertEqual(partial.tokens?.total, 10_100)
        XCTAssertNil(ClaudeLocalPricing.amount(model: "claude-opus-5-5", usage: partial))
        var negative = usage(); negative["cache_read_input_tokens"] = -1
        XCTAssertNil(try decode(negative).tokens)
        var overflow = usage(); overflow["input_tokens"] = Int.max
        XCTAssertNil(try decode(overflow).tokens)
    }
    func testDesktopProofAndStreamDeduplicationExcludeCLIAndSyntheticRows() throws {
        let (sessions, projects, log) = try fixture()
        let frame = try line()
        try (frame + frame + line("cli", entrypoint: "cli")
            + line("other", sourceSession: UUID().uuidString) + line("synthetic", model: "<synthetic>"))
            .write(to: log, atomically: true, encoding: .utf8)
        var reader = ClaudeLocalUsageReader()
        let result = try reader.read(sessionsDirectory: sessions, projectsDirectory: projects)
        XCTAssertEqual(result.contributions.count, 1)
        let value = try XCTUnwrap(result.contributions.values.first)
        XCTAssertEqual(value.value.tokens.total, 10_100)
        XCTAssertEqual(value.key.familyKey.model, "Claude Opus 5.5")
        XCTAssertEqual(result.discarded, 1)
        let snapshot = result.snapshot(now: ISO8601DateFormatter().date(from: "2026-10-23T00:00:00Z")!)
        XCTAssertEqual(snapshot.quotaWindows, [])
        XCTAssertEqual(snapshot.all.reference.pico, 40_800_000_000)
        XCTAssertFalse(String(describing: snapshot).contains("PRIVATE_"))
    }
    func testIncrementalAppendPartialTailReplacementAndSessionRemoval() throws {
        let (sessions, projects, log) = try fixture()
        try line().write(to: log, atomically: true, encoding: .utf8)
        var reader = ClaudeLocalUsageReader()
        XCTAssertEqual(try reader.read(sessionsDirectory: sessions, projectsDirectory: projects).contributions.count, 1)
        _ = try reader.read(sessionsDirectory: sessions, projectsDirectory: projects)
        XCTAssertEqual(reader.bytesRead, 0)
        let partial = String(try line("two").dropLast())
        let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd()
        try handle.write(contentsOf: Data(partial.utf8)); try handle.close()
        XCTAssertEqual(try reader.read(sessionsDirectory: sessions, projectsDirectory: projects).contributions.count, 1)
        let append = try FileHandle(forWritingTo: log); try append.seekToEnd(); try append.write(contentsOf: Data("\n".utf8)); try append.close()
        XCTAssertEqual(try reader.read(sessionsDirectory: sessions, projectsDirectory: projects).contributions.count, 2)
        try line("replacement").write(to: log, atomically: true, encoding: .utf8)
        XCTAssertEqual(try reader.read(sessionsDirectory: sessions, projectsDirectory: projects).contributions.count, 1)
        try FileManager.default.removeItem(at: sessions.appendingPathComponent("index.json"))
        XCTAssertEqual(try reader.read(sessionsDirectory: sessions, projectsDirectory: projects).contributions.count, 0)
    }
    func testUnknownModelRetainsTokensAndMissingSourceStaysEmpty() throws {
        let (sessions, projects, log) = try fixture()
        try line(model: "future-unknown").write(to: log, atomically: true, encoding: .utf8)
        var reader = ClaudeLocalUsageReader()
        let a = try reader.read(sessionsDirectory: sessions, projectsDirectory: projects)
        XCTAssertEqual(a.contributions.values.first?.value.tokens.total, 10_100)
        XCTAssertEqual(a.contributions.values.first?.value.reference.count, 0)
        XCTAssertFalse(try reader.read(sessionsDirectory: nil, projectsDirectory: nil).sourceAvailable)
    }
    func testNewerUsageSnapshotReplacesEarlierStreamFrameRatherThanSumming() throws {
        let (sessions, projects, log) = try fixture()
        try (line() + line(at: "2026-10-22T10:01:00Z", counts: usage(output: 200)))
            .write(to: log, atomically: true, encoding: .utf8)
        var reader = ClaudeLocalUsageReader()
        let result = try reader.read(sessionsDirectory: sessions, projectsDirectory: projects)
        XCTAssertEqual(result.contributions.count, 1)
        XCTAssertEqual(result.contributions.values.first?.value.tokens.output, 200)
    }
    func testServiceClaudeBranchNeedsOnlyLocalPathsAndDoesNotReadOtherProviders() async throws {
        let (sessions, projects, log) = try fixture()
        try line().write(to: log, atomically: true, encoding: .utf8)
        let absent = projects.appendingPathComponent("ABSENT")
        let paths = QuotaManagementDataPaths(codexSessionsDirectory: absent, codexArchivedSessionsDirectory: absent,
            codexBarPricingCatalogURL: absent, opencodexUsageLedgerURL: absent,
            antigravityQuotaHistoryURL: absent, antigravityInfoPlistURL: absent,
            claudeDesktopSessionsDirectory: sessions, claudeProjectsDirectory: projects)
        let snapshot = try await LocalQuotaManagementUsageService(paths: paths).loadDashboard(for: .claude,
            now: ISO8601DateFormatter().date(from: "2026-10-23T00:00:00Z")!)
        XCTAssertEqual(snapshot.all.tokens.total, 10_100)
        XCTAssertEqual(snapshot.quotaWindows, [])
    }
}
