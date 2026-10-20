import XCTest
import Foundation
@testable import AILSA_SS

final class QuotaActivationTests: XCTestCase {
    func testLegacyReadOnlyPreferenceDoesNotAuthorizeRequests() throws {
        var settings = AppSettings.defaultValue
        settings.quotaWindowActivationMode = .workHours
        let data = try JSONEncoder().encode(settings)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "antigravityQuotaActivationMode")
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded.antigravityQuotaActivationMode, .off)
        settings.antigravityQuotaActivationMode = .poolAccounts
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testWorkingHoursHandleMidnightAndAllDay() {
        var settings = AppSettings.defaultValue
        settings.quotaWindowActivationStartHour = 5; settings.quotaWindowActivationEndHour = 1
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let date: (String) -> Date = { ISO8601DateFormatter().date(from: $0)! }
        XCTAssertTrue(QuotaActivationPlanner.withinHours(settings, now: date("2026-10-20T00:00:00+08:00"), calendar: calendar))
        XCTAssertFalse(QuotaActivationPlanner.withinHours(settings, now: date("2026-10-20T03:00:00+08:00"), calendar: calendar))
        XCTAssertTrue(QuotaActivationPlanner.withinHours(settings, now: date("2026-10-20T05:00:00+08:00"), calendar: calendar))
        settings.quotaWindowActivationEndHour = 5
        XCTAssertTrue(QuotaActivationPlanner.withinHours(settings, now: date("2026-10-20T03:00:00+08:00"), calendar: calendar))
    }

    func testFreshIdleFiveHourEvidenceOnly() {
        let bucket = UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: 0, resetAt: 19_000, windowSeconds: 18_000, isUsageKnown: true)
        let usage = UsageSnapshot(fetchedAt: 1000, fiveHour: nil, oneWeek: nil, credits: nil,
                                  quotaFamilies: [UsageQuotaFamily(id: "gemini", displayName: "Gemini", buckets: [bucket])])
        XCTAssertEqual(QuotaActivationPlanner.readyFamilies(usage, now: 1001), [.gemini])
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(usage, now: 1200).isEmpty)
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(usage, now: 999).isEmpty)
        var used = usage; used.quotaFamilies![0].buckets[0].usedPercent = 1
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(used, now: 1001).isEmpty)
        var unknown = usage; unknown.quotaFamilies![0].buckets[0].isUsageKnown = false
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(unknown, now: 1001).isEmpty)
        var weekly = usage; weekly.quotaFamilies![0].buckets[0].windowSeconds = 604_800
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(weekly, now: 1001).isEmpty)
        let marked = QuotaCountdownState.markRequestObserved(usage, observedAt: 1000)
        XCTAssertTrue(QuotaActivationPlanner.readyFamilies(marked, now: 1001).isEmpty)
    }

    func testDurableClaimPreventsRetriesAcrossRestartAndKeepsFamiliesIndependent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("activation.json")
        let planner = QuotaActivationPlanner(path: path, jitter: { 60 })
        XCTAssertFalse(try planner.claimIfDue(account: "fixture", family: .gemini, now: 1000))
        XCTAssertFalse(try planner.claimIfDue(account: "fixture", family: .gemini, now: 1059))
        XCTAssertTrue(try planner.claimIfDue(account: "fixture", family: .gemini, now: 1060))
        try planner.record(account: "fixture", family: .gemini, outcome: "failed_no_retry")
        let restarted = QuotaActivationPlanner(path: path, jitter: { 60 })
        XCTAssertFalse(try restarted.claimIfDue(account: "fixture", family: .gemini, now: 1061))
        XCTAssertFalse(try restarted.claimIfDue(account: "fixture", family: .gemini, now: 19_059))
        XCTAssertFalse(try restarted.claimIfDue(account: "fixture", family: .gemini, now: 19_060))
        XCTAssertTrue(try restarted.claimIfDue(account: "fixture", family: .gemini, now: 19_120))
        XCTAssertFalse(try restarted.claimIfDue(account: "fixture", family: .claude, now: 1000))
        XCTAssertTrue(try restarted.claimIfDue(account: "fixture", family: .claude, now: 1060))
        XCTAssertFalse(try String(contentsOf: path, encoding: .utf8).contains("fixture"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: path.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCorruptJournalFailsClosed() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("invalid".utf8).write(to: path)
        let planner = QuotaActivationPlanner(path: path, jitter: { 1 })
        XCTAssertThrowsError(try planner.claimIfDue(account: "fixture", family: .gemini, now: 1000))
        XCTAssertEqual(try String(contentsOf: path, encoding: .utf8), "invalid")
    }

    func testOneRealGenerationAndProviderOwnedCountdown() async throws {
        ActivationURLProtocol.reset()
        let service = makeService()
        var prepared = false, confirmed = false
        let fresh = try await service.activateQuota(authJSON: auth(), expectedEmail: "consumer@example.com", family: .gemini,
            credentialPrepared: { _ in prepared = true }, generationConfirmed: { model, input, output in
                confirmed = true; XCTAssertEqual(model, "gemini-3.8-flash"); XCTAssertEqual(input, 6); XCTAssertEqual(output, 1)
            }, admit: { XCTAssertTrue(prepared) })
        XCTAssertTrue(confirmed)
        XCTAssertEqual(ActivationURLProtocol.sends, 1)
        let window = fresh.quotaFamilies?.first?.buckets.first
        XCTAssertEqual(window?.resetAt, 1_800_018_000)
        XCTAssertNil(window?.countdownStartEvidence)
    }

    func testFailedInferenceDoesNotRetryOrClaimCountdownSuccess() async throws {
        ActivationURLProtocol.reset(status: 429)
        do {
            _ = try await makeService().activateQuota(authJSON: auth(), expectedEmail: "consumer@example.com", family: .gemini,
                credentialPrepared: { _ in }, generationConfirmed: { _, _, _ in XCTFail("must not confirm") }, admit: {})
            XCTFail("should fail")
        } catch {}
        XCTAssertEqual(ActivationURLProtocol.sends, 1)
    }

    func testIdentityMismatchAndAdmissionCancellationNeverGenerate() async throws {
        ActivationURLProtocol.reset()
        do {
            _ = try await makeService().activateQuota(authJSON: auth(), expectedEmail: "other@example.com", family: .gemini,
                credentialPrepared: { _ in XCTFail("must not commit") }, generationConfirmed: { _, _, _ in XCTFail("must not confirm") }, admit: {})
            XCTFail("should fail")
        } catch {}
        XCTAssertEqual(ActivationURLProtocol.sends, 0)
        do {
            _ = try await makeService().activateQuota(authJSON: auth(), expectedEmail: "consumer@example.com", family: .gemini,
                credentialPrepared: { _ in }, generationConfirmed: { _, _, _ in XCTFail("must not confirm") }, admit: { throw CancellationError() })
            XCTFail("should cancel")
        } catch {}
        XCTAssertEqual(ActivationURLProtocol.sends, 0)
    }

    func testResumeRearmsInsteadOfBurstingOverdueActivation() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        let planner = QuotaActivationPlanner(path: path, jitter: { 60 })
        XCTAssertFalse(try planner.claimIfDue(account: "fixture", family: .gemini, now: 1000))
        XCTAssertFalse(try planner.claimIfDue(account: "fixture", family: .gemini, now: 4000))
        XCTAssertFalse(try planner.claimIfDue(account: "fixture", family: .gemini, now: 4059))
        XCTAssertTrue(try planner.claimIfDue(account: "fixture", family: .gemini, now: 4060))
    }

    func testPoolClientUsesOnlyLoopbackAndDoesNotPutAdminTokenInPayload() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: path) }
        try Data("fixture-admin-token".utf8).write(to: path.appendingPathComponent("admin-api-token"))
        let service = OpenCodexPoolService(home: path, policyURL: path.appendingPathComponent("policy.json"), localQuotaURL: path.appendingPathComponent("local.json"), loader: { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            XCTAssertEqual(request.url?.port, 10100)
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-OpenCodex-API-Key"), "fixture-admin-token")
            XCTAssertFalse(String(data: request.httpBody ?? Data(), encoding: .utf8)!.contains("fixture-admin-token"))
            let data = Data(#"{"activeAccountId":"fixture","accounts":[{"id":"fixture","email":"fixture@example.com","paused":false}]}"#.utf8)
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        let snapshot = try await service.snapshot()
        XCTAssertFalse(snapshot.enabled)
        var managed = OpenCodexLocalPoolPolicy(); managed.managementEnabled = true
        try JSONEncoder().encode(managed).write(to: path.appendingPathComponent("policy.json"))
        try await service.setRange(id: "fixture", range: OpenCodexPoolRange(minimum: 4, maximum: 8))
        do {
            try await service.setRange(id: "fixture", range: OpenCodexPoolRange(minimum: 12, maximum: 5))
            XCTFail("inverted range must fail")
        } catch {}
    }

    func testConfirmedRequestSurvivesFailedQuotaReadWithoutMovingWeeklyReset() throws {
        let bucket = UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: 0, resetAt: 18_500, windowSeconds: 18_000, isUsageKnown: true)
        var previous = UsageSnapshot(fetchedAt: 900, fiveHour: nil, oneWeek: nil, credits: nil,
            quotaFamilies: [UsageQuotaFamily(id: "gemini", displayName: "Gemini", buckets: [bucket])])
        previous.quotaActivationRequests = ["gemini": 1000]
        let stillOld = QuotaCountdownState.reconcile(previous: previous, refreshed: previous, observedAt: 1001)
        XCTAssertNil(stillOld.quotaFamilies?[0].buckets[0].countdownStartedAt)
        var fresh = previous
        fresh.fetchedAt = 1002; fresh.sourceAccountMatched = true
        fresh.quotaFamilies![0].buckets[0].resetAt = 19_000
        fresh.oneWeek = UsageWindow(usedPercent: 20, windowSeconds: 604_800, resetAt: 45_000)
        let reconciled = QuotaCountdownState.reconcile(previous: previous, refreshed: fresh, observedAt: 1002)
        XCTAssertEqual(reconciled.quotaFamilies?[0].buckets[0].countdownStartedAt, 1000)
        XCTAssertEqual(reconciled.quotaFamilies?[0].buckets[0].resetAt, 19_000)
        XCTAssertEqual(reconciled.oneWeek?.resetAt, 45_000)
        XCTAssertNil(reconciled.oneWeek?.countdownStartedAt)
        var wrongCycle = fresh; wrongCycle.quotaFamilies![0].buckets[0].resetAt = 70_000
        XCTAssertNil(QuotaCountdownState.reconcile(previous: previous, refreshed: wrongCycle, observedAt: 1002).quotaFamilies?[0].buckets[0].countdownStartedAt)
    }

    func testPoolRangeIsStableAcrossRefreshAndRestartAndUsesOnlyFreshCycles() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let quota = OpenCodexPoolQuota(customWindows: [OpenCodexPoolWindow(label: "Gemini 5h", percent: 94, resetAt: 1_800_005_000, modelId: nil)], updatedAt: now.timeIntervalSince1970 * 1000)
        var policy = OpenCodexLocalPoolPolicy()
        policy.ranges["fixture"] = OpenCodexPoolRange(minimum: 5, maximum: 10)
        let draw = policy.threshold(id: "fixture", quota: quota, family: "gemini", now: now)!
        XCTAssertTrue((5...10).contains(draw))
        let restarted = try JSONDecoder().decode(OpenCodexLocalPoolPolicy.self, from: JSONEncoder().encode(policy))
        XCTAssertEqual(restarted.threshold(id: "fixture", quota: quota, family: "gemini", now: now.addingTimeInterval(30)), draw)
        XCTAssertNil(policy.threshold(id: "fixture", quota: quota, family: "claude", now: now))
        XCTAssertNil(policy.threshold(id: "fixture", quota: quota, family: "gemini", now: now.addingTimeInterval(901)))
        XCTAssertNil(policy.threshold(id: "fixture", quota: quota, family: "gemini", now: now.addingTimeInterval(-1)))
        var idle = quota
        idle.customWindows![0].percent = 0
        XCTAssertNil(policy.threshold(id: "fixture", quota: idle, family: "gemini", now: now))
        idle.customWindows!.append(OpenCodexPoolWindow(label: "Gemini week", percent: 0, resetAt: now.timeIntervalSince1970 + 86_400, modelId: nil))
        XCTAssertNotNil(policy.threshold(id: "fixture", quota: idle, family: "gemini", now: now))
        policy.ranges["fixture"] = OpenCodexPoolRange(minimum: 10, maximum: 10)
        XCTAssertEqual(policy.threshold(id: "fixture", quota: quota, family: "gemini", now: now), 10)
    }

    func testStockPoolSwitchUsesOnlyEligibleAccountAndPreservesManualChanges() async throws {
        let server = PoolFixture()
        let service = try server.service()
        defer { server.clean() }
        try await service.setEnabled(true)
        let switched = try await service.selectNextIfNeeded()
        XCTAssertTrue(switched)
        XCTAssertEqual(server.active, "ready")
        XCTAssertEqual(server.activeWrites, 1)
        XCTAssertFalse(server.nativeEnabled)
        try await service.setEnabled(false)
        XCTAssertFalse(server.nativeEnabled)
        try await service.setManagementEnabled(false)
        XCTAssertTrue(server.nativeEnabled)
        XCTAssertFalse(try service.policy().enabled)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: service.policyURL.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let raced = PoolFixture(); defer { raced.clean() }
        let racingService = try raced.service()
        try await racingService.setEnabled(true)
        raced.changeActiveOnRecheck = true
        let staleDecision = try await racingService.selectNextIfNeeded()
        XCTAssertFalse(staleDecision)
        XCTAssertEqual(raced.activeWrites, 0)
    }

    func testPoolUnknownOrStaleQuotaNeverCausesRotationAndCooldownCannotBeSelected() async throws {
        for mode in ["unknown", "stale", "cooldown"] {
            let server = PoolFixture(); defer { server.clean() }
            server.mode = mode
            let service = try server.service()
            try await service.setEnabled(true)
            let switched = try await service.selectNextIfNeeded()
            XCTAssertFalse(switched)
            XCTAssertEqual(server.activeWrites, 0)
        }
    }

    func testPoolMembershipUsesOriginalPauseAPIAndInvalidRangeNeverMutatesProxy() async throws {
        let server = PoolFixture(); defer { server.clean() }
        let service = try server.service()
        try await service.setSelected(id: "ready", selected: false)
        XCTAssertTrue(server.pausedReady)
        try await service.setRange(id: "ready", range: OpenCodexPoolRange(minimum: 9, maximum: 13))
        XCTAssertEqual(try service.policy().ranges["ready"], OpenCodexPoolRange(minimum: 9, maximum: 13))
        do { try await service.setRange(id: "ready", range: OpenCodexPoolRange(minimum: 8, maximum: 4)); XCTFail("invalid") } catch {}
        XCTAssertEqual(server.activeWrites, 0)
        XCTAssertFalse(server.nativeEnabled)
    }

    func testLocalQuotaBridgeRequiresIdentityEvidenceAndDoesNotRedrawIdleWindows() throws {
        let server = PoolFixture(); defer { server.clean() }
        let service = try server.service()
        let now = Int64(Date().timeIntervalSince1970)
        var usage = UsageSnapshot(fetchedAt: now, fiveHour: nil, oneWeek: nil, credits: nil, quotaFamilies: [
            UsageQuotaFamily(id: "gemini", displayName: "Gemini", buckets: [
                UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: 0, resetAt: now + 18_000, windowSeconds: 18_000, isUsageKnown: true),
                UsageQuotaBucket(id: "week", displayName: "1w", usedPercent: 10, resetAt: now + 86_400, windowSeconds: 604_800, isUsageKnown: true)])])
        usage.sourceAccountMatched = true
        func save(_ value: UsageSnapshot) throws {
            let row: [String: Any] = ["provider": "antigravity", "email": "verified@example.com", "usage": try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)), "authJson": ["secret": "not-decoded"]]
            try JSONSerialization.data(withJSONObject: ["accounts": [row]]).write(to: service.localQuotaURL)
        }
        try save(usage)
        let initial = service.localQuotas()["verified@example.com"]!
        XCTAssertNil(initial.customWindows?.first?.resetAt)
        usage.quotaFamilies![0].buckets[0].resetAt = now + 18_030
        try save(usage)
        XCTAssertEqual(initial, service.localQuotas()["verified@example.com"])
        usage.sourceAccountMatched = false
        try save(usage)
        XCTAssertTrue(service.localQuotas().isEmpty)
        usage.sourceAccountMatched = true; usage.fetchedAt = now - 901
        try save(usage)
        XCTAssertTrue(service.localQuotas().isEmpty)
    }

    private func auth() -> JSONValue {
        let p = AntigravityOAuthProfile.consumer
        return .object(["email": .string("consumer@example.com"), "access_token": .string("fixture-access"),
                        "refresh_token": .string("fixture-refresh"), "expiry": .string("2099-01-01T00:00:00Z"),
                        "auth_method": .string(p.nativeAuthMethod), AntigravityOAuthProfile.profileStorageKey: .string(p.rawValue),
                        "client_id": .string(p.publicClientID), AntigravityOAuthProfile.refreshVerificationStorageKey: .number(1)])
    }
    private func makeService() -> AntigravityUsageService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ActivationURLProtocol.self]
        return AntigravityUsageService(session: URLSession(configuration: config), dateProvider: ActivationClock(),
            userInfoLoader: { request in
                (Data(#"{"email":"consumer@example.com","email_verified":true}"#.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            })
    }
}

private struct ActivationClock: DateProviding {
    func unixSecondsNow() -> Int64 { 1_800_000_000 }
    func unixMillisecondsNow() -> Int64 { unixSecondsNow() * 1000 }
}
private final class ActivationURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var status = 200
    static var sends: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset(status: Int = 200) { lock.lock(); count = 0; Self.status = status; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload: [String: Any]
        var code = 200
        switch request.url!.path {
        case "/v1internal:loadCodeAssist": payload = ["cloudaicompanionProject": "fixture-project", "paidTier": ["id": "standard-tier"]]
        case "/v1internal:retrieveUserQuotaSummary":
            payload = ["groups": [["displayName": "Gemini", "buckets": [["bucketId": "gemini-5h", "window": "5h", "remainingFraction": 1.0, "resetTime": ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: 1_800_018_000))]]]]]
        case "/v1internal:fetchAvailableModels": payload = ["models": ["gemini-3.8-flash": ["quotaInfo": ["remainingFraction": 1.0]]]]
        case "/v1internal:generateContent":
            Self.lock.lock(); Self.count += 1; code = Self.status; Self.lock.unlock()
            payload = code == 200 ? ["response": ["candidates": [["content": ["parts": [["text": "OK"]]]]], "usageMetadata": ["promptTokenCount": 6, "candidatesTokenCount": 1]]] : ["error": ["message": "quota exhausted"]]
        default: code = 404; payload = [:]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class PoolFixture: @unchecked Sendable {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var active = "low", nativeEnabled = false, activeWrites = 0, pausedReady = false
    var mode = "normal", changeActiveOnRecheck = false
    private let lock = NSLock()
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func service() throws -> OpenCodexPoolService {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("fixture-admin".utf8).write(to: directory.appendingPathComponent("admin-api-token"))
        var policy = OpenCodexLocalPoolPolicy(); policy.managementEnabled = true; policy.previousNativePreference = true
        try JSONEncoder().encode(policy).write(to: directory.appendingPathComponent("policy.json"))
        return OpenCodexPoolService(home: directory, policyURL: directory.appendingPathComponent("policy.json"), localQuotaURL: directory.appendingPathComponent("local.json"), loader: { self.respond($0) })
    }
    private func respond(_ request: URLRequest) -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        XCTAssertEqual(request.url?.host, "127.0.0.1")
        XCTAssertFalse(request.url!.path.contains("ailsa"))
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        let path = request.url!.path
        var response: [String: Any] = ["ok": true]
        if path.hasSuffix("/pool") {
            if request.httpMethod == "PUT" { nativeEnabled = body["enabled"] as! Bool }
            response = ["enabled": nativeEnabled]
        } else if path.hasSuffix("/pause") {
            XCTAssertEqual(body["accountId"] as? String, "ready")
            pausedReady = body["paused"] as! Bool
        } else if path.hasSuffix("/active") {
            active = body["accountId"] as! String; activeWrites += 1
        } else {
            if changeActiveOnRecheck && !request.url!.absoluteString.contains("quota=1") { active = "manual" }
            let now = Date().timeIntervalSince1970 * 1000
            func row(_ id: String, used: Double, paused: Bool = false, health: String = "healthy") -> [String: Any] {
                var value: [String: Any] = ["id": id, "email": id + "@example.com", "paused": paused, "health": ["status": health]]
                if mode != "unknown" {
                    value["quota"] = ["updatedAt": now - (mode == "stale" ? 600_000 : 0), "customWindows": [["label": "Gemini 5h", "percent": used, "resetAt": now + 3_600_000]]]
                }
                return value
            }
            response = ["activeAccountId": active, "accounts": [row("low", used: 95), row("paused", used: 0, paused: true), row("empty", used: 100), row("ready", used: 10, paused: pausedReady, health: mode == "cooldown" ? "cooldown" : "healthy")]]
        }
        return (try! JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
