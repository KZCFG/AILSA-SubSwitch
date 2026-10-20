import Foundation
import XCTest
@testable import AILSA_SS

final class OpenCodexPoolFreshnessTests: XCTestCase {
    func testFiveMinuteBoundaryAndStaleRetentionThroughFifteenMinutes() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("fixture-admin".utf8).write(to: folder.appendingPathComponent("admin-api-token"))
        var policy = OpenCodexLocalPoolPolicy(); policy.enabled = true
        try JSONEncoder().encode(policy).write(to: folder.appendingPathComponent("policy.json"))
        for age in [121.0, 299, 300, 301, 899, 900, 901, -1] {
            let quota = OpenCodexPoolQuota(customWindows: [
                .init(label: "Gemini 5h", percent: 30, resetAt: now.timeIntervalSince1970 + 3600, modelId: nil),
                .init(label: "Gemini 1w", percent: 97, resetAt: now.timeIntervalSince1970 + 7200, modelId: nil)
            ], updatedAt: (now.timeIntervalSince1970 - age) * 1000)
            let data = try JSONSerialization.data(withJSONObject: ["activeAccountId": "proxy-id", "accounts": [[
                "id": "proxy-id", "email": "fixture@example.com", "quota": try JSONSerialization.jsonObject(with: JSONEncoder().encode(quota))]]])
            var service = OpenCodexPoolService(home: folder, policyURL: folder.appendingPathComponent("policy.json"), localQuotaURL: folder.appendingPathComponent("missing.json"), loader: { request in
                (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
            service.dateProvider = { now }
            let account = try await service.snapshot().accounts[0]
            if (0...900).contains(age) {
                XCTAssertEqual(account.remainingPercent, 3)
                XCTAssertNotNil(account.effectiveThreshold)
                XCTAssertEqual(account.quotaIsStale, age > 300)
                XCTAssertEqual(account.limitingWindow, "1w")
                XCTAssertEqual(account.dataAgeSeconds, age)
            } else {
                XCTAssertNil(account.remainingPercent); XCTAssertNil(account.effectiveThreshold)
            }
        }
    }
    func testExpiredWindowCannotDominateFreshWeeklyQuota() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = OpenCodexPoolQuota(customWindows: [
            .init(label: "Gemini 5h", percent: 100, resetAt: now.timeIntervalSince1970, modelId: nil),
            .init(label: "Gemini week", percent: 40, resetAt: now.timeIntervalSince1970 + 6000, modelId: nil)
        ], updatedAt: now.timeIntervalSince1970 * 1000)
        XCTAssertEqual(quota.windows(for: "gemini", now: now).map(\.percent), [40])
    }
    func testStaleActiveMayLeaveButStaleCandidateCannotReceiveTraffic() {
        var pool = OpenCodexPoolSnapshot(provider: "antigravity-pool", enabled: true, activeAccountId: "a", accounts: [
            .init(id: "a", label: "A", selected: true, needsReauth: false, range: .init(), effectiveThreshold: 10, effectiveClaudeThreshold: 10, remainingPercent: 3, dataAgeSeconds: 450, quotaIsStale: true, limitingWindow: "1w"),
            .init(id: "b", label: "B", selected: true, needsReauth: false, range: .init(), effectiveThreshold: 10, effectiveClaudeThreshold: 10, remainingPercent: 80, dataAgeSeconds: 450, quotaIsStale: true)])
        XCTAssertEqual(OpenCodexPoolDecision.plan(pool).outcome, .noEligibleTarget)
        pool.accounts[1].quotaIsStale = false; pool.accounts[1].dataAgeSeconds = 180
        let decision = OpenCodexPoolDecision.plan(pool)
        XCTAssertEqual(decision.targetAccountId, "b"); XCTAssertEqual(decision.dataAgeSeconds, 450)
        XCTAssertTrue(decision.evalReason?.contains("stale") == true)
    }
    func testDecisionExplainsPreciseDeltaAndOldAuditStillDecodes() throws {
        let pool = OpenCodexPoolSnapshot(provider: "antigravity-pool", enabled: true, activeAccountId: "a", accounts: [
            .init(id: "a", label: "A", selected: true, needsReauth: false, range: .init(minimum: 8, maximum: 8), effectiveThreshold: 8, effectiveClaudeThreshold: 8, remainingPercent: 8.77, dataAgeSeconds: 180, quotaIsStale: false, limitingWindow: "5h")])
        let decision = OpenCodexPoolDecision.plan(pool)
        XCTAssertEqual(decision.outcome, .aboveThreshold)
        XCTAssertTrue(decision.evalReason?.contains("8.77%") == true)
        XCTAssertTrue(decision.evalReason?.contains("+0.77%") == true)
        let data = try JSONEncoder().encode(decision)
        var old = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["evalReason", "dataAgeSeconds", "quotaIsStale", "limitingWindow"] { old.removeValue(forKey: key) }
        let restored = try JSONDecoder().decode(OpenCodexPoolDecision.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.evalReason); XCTAssertEqual(restored.outcome, .aboveThreshold)
    }
    func testPoolBadgeLookupUsesRoutingPoolMetadataOnly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("fixture-admin".utf8).write(to: folder.appendingPathComponent("admin-api-token"))
        let service = OpenCodexPoolService(home: folder, loader: { request in
            XCTAssertEqual(request.url?.query, "provider=antigravity-pool")
            return (Data(#"{"activeAccountId":"proxy-id","accounts":[{"id":"proxy-id","email":"Pool@Example.com","paused":false}]}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let email = try await service.poolActiveEmail()
        XCTAssertEqual(email, "pool@example.com")
    }
}
