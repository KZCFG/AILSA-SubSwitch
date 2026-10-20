import Foundation
import XCTest
@testable import AILSA_SS

final class OpenCodexUnifiedSyncTests: XCTestCase {
    func testLegacyPolicyDoesNotImplicitlyClaimManagement() throws {
        let old = Data(#"{"enabled":true,"provider":"antigravity-pool","ranges":{},"seed":"stable","revision":"old","previousNativePreference":true}"#.utf8)
        let value = try JSONDecoder().decode(OpenCodexLocalPoolPolicy.self, from: old)
        XCTAssertFalse(value.managementEnabled); XCTAssertNil(value.managedSince); XCTAssertEqual(value.seed, "stable")
        XCTAssertEqual(try JSONDecoder().decode(OpenCodexLocalPoolPolicy.self, from: JSONEncoder().encode(value)), value)
    }
    func testLeaseRejectsAnotherWriterAndReleasesAfterScope() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        var first: OpenCodexControlLease? = try OpenCodexControlLease(directory: folder)
        XCTAssertThrowsError(try OpenCodexControlLease(directory: folder))
        withExtendedLifetime(first) {}
        first = nil
        _ = try OpenCodexControlLease(directory: folder)
    }
    func testTakeoverBacksUpAndStopsOnlyRecognizedLegacyJob() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let before = try Data(contentsOf: f.script)
        let service = f.service()
        try await service.setManagementEnabled(true)
        XCTAssertFalse(f.legacyLoaded)
        XCTAssertFalse(f.nativeEnabled)
        XCTAssertEqual(f.active, "b")
        XCTAssertEqual(f.activeWrites, 0)
        XCTAssertTrue(try service.policy().managementEnabled)
        XCTAssertEqual(try Data(contentsOf: f.script), before)
        let copy = f.support.appendingPathComponent("legacy-sync-backup/com.example.legacy/codexbar-sync-creds.py")
        XCTAssertEqual(try Data(contentsOf: copy), before)
        XCTAssertEqual(f.jobCommands.filter { $0.first == "disable" }.count, 1)
        XCTAssertEqual(f.jobCommands.filter { $0.first == "bootout" }.count, 1)
        try await service.setManagementEnabled(false)
        XCTAssertTrue(f.nativeEnabled)
        XCTAssertFalse(f.legacyLoaded)
        XCTAssertFalse(f.jobCommands.contains { ["enable", "bootstrap"].contains($0.first ?? "") })
    }
    func testFailedLegacyStopDoesNotClaimOwnership() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }; f.refuseStop = true
        let service = f.service()
        do { try await service.setManagementEnabled(true); XCTFail("must fail") } catch {}
        XCTAssertFalse(try service.policy().managementEnabled)
        XCTAssertEqual(f.activeWrites, 0)
    }
    func testQuotaRefreshesAndFirstTickNeverPinTheCurrentPoolBackToDesktop() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        try await service.runManagedCycle()
        XCTAssertEqual(f.active, "b"); XCTAssertEqual(f.activeWrites, 0); XCTAssertEqual(f.workerCalls, 0)
        try f.saveDesktop("local-a", usageStamp: 99)
        try await service.runManagedCycle()
        XCTAssertEqual(f.active, "b"); XCTAssertEqual(f.activeWrites, 0)
    }
    func testActualDesktopSelectionChangeFollowsExactlyOnce() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        try f.saveDesktop("local-b")
        try await service.runManagedCycle()
        XCTAssertEqual(f.activeWrites, 1)
        try await service.runManagedCycle()
        XCTAssertEqual(f.activeWrites, 1)
    }
    func testVerifiedNativeIdentityChangeFollowsOnceAndNeverWritesNativeMarkers() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        f.nativeEmail = "a@example.com"
        let service = f.service(); try await service.setManagementEnabled(true)
        try await service.runManagedCycle(); XCTAssertEqual(f.activeWrites, 0)
        f.nativeEmail = "b@example.com"
        try await service.runManagedCycle(); XCTAssertEqual(f.activeWrites, 1)
        try await service.runManagedCycle(); XCTAssertEqual(f.activeWrites, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.folder.appendingPathComponent(".gemini/google_accounts.json").path))
    }
    func testUnchangedGrantDoesNotOverwriteProxyAccessRotationOrAutoAdmitAccounts() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        try await service.runManagedCycle()
        XCTAssertEqual(f.workerCalls, 0); XCTAssertEqual(f.validations, 0)
        let snapshot = try await service.snapshot()
        XCTAssertEqual(snapshot.candidates.map(\.id), ["local-c"])
    }
    func testChangedGrantCarriesExpectedGenerationAndNativeProjectWithoutSelecting() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        f.changedGrant = true; try f.saveDesktop("local-a")
        try await service.runManagedCycle()
        XCTAssertEqual(f.workerCalls, 1); XCTAssertEqual(f.validations, 1)
        let input = try JSONDecoder().decode(JSONValue.self, from: f.lastPayload!)
        let row = input["rows"]?.arrayValue?.first
        XCTAssertEqual(row?["id"]?.stringValue, "a")
        XCTAssertEqual(row?["expected"]?["refresh"]?.stringValue, "fixture-a")
        XCTAssertEqual(row?["credential"]?["projectId"]?.stringValue, "verified-project")
        XCTAssertEqual(f.activeWrites, 0)
    }
    func testAdmissionIsExplicitAndExternalWriterBlocksAllManagedMutations() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        try await service.importSavedAccount(id: "local-c")
        let input = try JSONDecoder().decode(JSONValue.self, from: f.lastPayload!)
        XCTAssertEqual(input["rows"]?.arrayValue?.first?["insert"]?.boolValue, true)
        f.legacyLoaded = true
        let before = f.workerCalls
        do { try await service.selectAccount(id: "a"); XCTFail("external writer") } catch {}
        do { try await service.runManagedCycle(); XCTFail("external writer") } catch {}
        let revision = try service.policy().revision
        do { try await service.setRange(id: "a", range: OpenCodexPoolRange(minimum: 5, maximum: 10)); XCTFail("external writer") } catch {}
        XCTAssertEqual(try service.policy().revision, revision)
        XCTAssertEqual(f.workerCalls, before); XCTAssertEqual(f.activeWrites, 0)
    }
    func testExactRemainingDoesNotCrossThreeButCrossesFour() throws {
        func make(_ threshold: Int) -> OpenCodexPoolSnapshot {
            OpenCodexPoolSnapshot(provider: "antigravity-pool", enabled: true, activeAccountId: "a", accounts: [
                OpenCodexPoolAccount(id: "a", label: "A", selected: true, needsReauth: false, range: .init(minimum: 3, maximum: 7), effectiveThreshold: threshold, effectiveClaudeThreshold: 8, remainingPercent: 3.0685266),
                OpenCodexPoolAccount(id: "b", label: "B", selected: true, needsReauth: false, range: .init(), effectiveThreshold: 10, effectiveClaudeThreshold: 10, remainingPercent: 70)])
        }
        let below = OpenCodexPoolDecision.plan(make(3)); XCTAssertEqual(below.outcome, .aboveThreshold)
        XCTAssertEqual(below.remainingPercent, 3.0685266); XCTAssertNil(below.targetAccountId)
        let crossed = OpenCodexPoolDecision.plan(make(4)); XCTAssertEqual(crossed.outcome, .candidateChosen); XCTAssertEqual(crossed.targetAccountId, "b")
    }
    func testPlanExplainsUnknownQuotaCycleAndMissingTargets() {
        var pool = OpenCodexPoolSnapshot(provider: "antigravity-pool", enabled: true, activeAccountId: "a", accounts: [
            OpenCodexPoolAccount(id: "a", label: "A", selected: true, needsReauth: false, range: .init(), effectiveThreshold: 10, effectiveClaudeThreshold: 10)])
        XCTAssertEqual(OpenCodexPoolDecision.plan(pool).outcome, .activeQuotaUnknown)
        pool.accounts[0].remainingPercent = 3; pool.accounts[0].effectiveThreshold = nil
        XCTAssertEqual(OpenCodexPoolDecision.plan(pool).outcome, .activeThresholdUnknown)
        pool.accounts[0].effectiveThreshold = 5
        XCTAssertEqual(OpenCodexPoolDecision.plan(pool).outcome, .noEligibleTarget)
        pool.enabled = false; XCTAssertEqual(OpenCodexPoolDecision.plan(pool).outcome, .disabled)
    }
    func testFailedCredentialSyncDoesNotBlockHealthyQuotaRotation() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }; f.active = "a"; f.provideQuota = true
        let service = f.service(); try await service.setManagementEnabled(true); try await service.setEnabled(true)
        f.changedGrant = true; f.workerFailure = true; try f.saveDesktop("local-a")
        try await service.runManagedCycle()
        XCTAssertEqual(f.active, "b"); XCTAssertEqual(f.workerCalls, 1); XCTAssertEqual(f.activeWrites, 1)
        let event = try OpenCodexPoolAudit.read(at: service.auditURL).last!
        XCTAssertEqual(event.outcome, .switched); XCTAssertTrue(event.credentialSyncDeferred)
        XCTAssertEqual(event.activeAccountId, "a"); XCTAssertEqual(event.targetAccountId, "b")
    }
    func testFailedCredentialSyncDoesNotAuthorizeRotationOnUnknownQuota() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }; f.active = "a"
        let service = f.service(); try await service.setManagementEnabled(true); try await service.setEnabled(true)
        f.changedGrant = true; f.workerFailure = true; try f.saveDesktop("local-a")
        try await service.runManagedCycle()
        XCTAssertEqual(f.activeWrites, 0)
        let event = try OpenCodexPoolAudit.read(at: service.auditURL).last!
        XCTAssertEqual(event.outcome, .activeQuotaUnknown); XCTAssertTrue(event.credentialSyncDeferred)
    }
    func testCredentialSyncCancellationNeverContinuesToRotation() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }; f.active = "a"; f.provideQuota = true
        let service = f.service(); try await service.setManagementEnabled(true); try await service.setEnabled(true)
        f.changedGrant = true; f.cancelWorker = true; try f.saveDesktop("local-a")
        do { try await service.runManagedCycle(); XCTFail("must cancel") } catch is CancellationError {} catch { XCTFail("wrong error") }
        XCTAssertEqual(f.activeWrites, 0)
    }
    func testAutomaticSwitchRequiresProviderReadback() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }; f.active = "a"; f.provideQuota = true
        let service = f.service(); try await service.setManagementEnabled(true); try await service.setEnabled(true)
        f.ignoreActiveWrite = true
        try await service.runManagedCycle()
        XCTAssertEqual(f.active, "a")
        XCTAssertEqual(try OpenCodexPoolAudit.read(at: service.auditURL).last?.outcome, .selectionUnconfirmed)
    }
    func testManualSelectionAndRangeChangesHaveSeparateReceipts() async throws {
        let f = try UnifiedFixture(); defer { f.clean() }
        let service = f.service(); try await service.setManagementEnabled(true)
        try await service.selectAccount(id: "a")
        XCTAssertEqual(try OpenCodexPoolAudit.read(at: service.auditURL).last?.outcome, .manualSelected)
        try await service.setRange(id: "a", range: .init(minimum: 3, maximum: 7))
        let event = try OpenCodexPoolAudit.read(at: service.auditURL).last!
        XCTAssertEqual(event.outcome, .rangeChanged); XCTAssertEqual(event.range, .init(minimum: 3, maximum: 7))
        XCTAssertEqual(event.previousRange, .init())
    }
    func testAuditPreservesExactNumbersWithoutCredentialsAndPolicyChanges() throws {
        let f = try UnifiedFixture(); defer { f.clean() }; let service = f.service()
        let before = try service.policy().revision
        // Create a stable policy before proving that diagnostic writes do not change its revision.
        try service.updatePolicy { _ in }; let revision = try service.policy().revision
        let event = OpenCodexPoolDecision(outcome: .aboveThreshold, family: "gemini", activeAccountId: "a", remainingPercent: 3.0685266, threshold: 3)
        try OpenCodexPoolAudit.append(event, at: service.auditURL)
        XCTAssertEqual(try OpenCodexPoolAudit.read(at: service.auditURL), [event]); XCTAssertEqual(try service.policy().revision, revision)
        let raw = try String(contentsOf: service.auditURL, encoding: .utf8)
        XCTAssertFalse(raw.contains("@")); XCTAssertFalse(raw.contains("fixture-admin")); XCTAssertFalse(raw.contains("refresh"))
        let mode = try FileManager.default.attributesOfItem(atPath: service.auditURL.path)[.posixPermissions] as! NSNumber
        XCTAssertEqual(mode.intValue & 0o777, 0o600); XCTAssertNotEqual(before, revision)
    }
    func testAuditIsBoundedAndCorruptionIsPreserved() throws {
        let f = try UnifiedFixture(); defer { f.clean() }; let service = f.service()
        for number in 0...OpenCodexPoolAudit.maximumEntries {
            var event = OpenCodexPoolDecision(outcome: .aboveThreshold); event.timestamp = Double(number)
            try OpenCodexPoolAudit.append(event, at: service.auditURL)
        }
        let rows = try OpenCodexPoolAudit.read(at: service.auditURL)
        XCTAssertEqual(rows.count, OpenCodexPoolAudit.maximumEntries); XCTAssertEqual(rows.first?.timestamp, 1)
        let malformed = Data("{broken".utf8); try malformed.write(to: service.auditURL)
        XCTAssertThrowsError(try OpenCodexPoolAudit.append(.init(outcome: .disabled), at: service.auditURL))
        XCTAssertEqual(try Data(contentsOf: service.auditURL), malformed)
    }

}

private final class UnifiedFixture: @unchecked Sendable {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var support: URL { folder.appendingPathComponent("support") }
    var script: URL { folder.appendingPathComponent(".local/bin/codexbar-sync-creds.py") }
    var legacyLoaded = true, refuseStop = false, nativeEnabled = true
    var nativeEmail: String? = nil
    var workerFailure = false, cancelWorker = false, provideQuota = false, ignoreActiveWrite = false
    var active = "b", activeWrites = 0, workerCalls = 0, validations = 0, changedGrant = false
    var jobCommands: [[String]] = [], lastPayload: Data?
    init() throws {
        for name in [".local/bin", "Library/LaunchAgents", ".opencodex", "support"] {
            try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try Data("SUBSWITCH_PATH = 1\nOPENCODEX_AUTH_PATH = 2\ndef sync_cycle(): pass\n".utf8).write(to: script)
        let plist: [String: Any] = ["Label": "com.example.legacy", "ProgramArguments": ["/usr/bin/python3", script.path]]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: folder.appendingPathComponent("Library/LaunchAgents/com.example.legacy.plist"))
        let p = folder.appendingPathComponent(".opencodex")
        try Data("fixture-admin".utf8).write(to: p.appendingPathComponent("admin-api-token"))
        let accounts = ["a", "b"].map { ["id": $0, "credential": ["email": $0 + "@example.com", "refresh": "fixture-" + $0, "access": "proxy-rotated", "expires": 4_000_000_000_000]] as [String: Any] }
        try JSONSerialization.data(withJSONObject: ["antigravity-pool": ["activeAccountId": active, "accounts": accounts], "other-provider": ["legacy": true]]).write(to: p.appendingPathComponent("auth.json"))
        var settings = AppSettings.defaultValue; settings.syncOpencodeAntigravityAuth = true
        try JSONEncoder().encode(settings).write(to: support.appendingPathComponent("settings.json"))
        try saveDesktop("local-a")
    }
    func clean() { try? FileManager.default.removeItem(at: folder) }
    func saveDesktop(_ id: String, usageStamp: Int = 0) throws {
        let rows = ["a", "b", "c"].map { name in
            ["id": "local-" + name, "label": name, "email": name + "@example.com", "provider": "antigravity", "authJson": ["refresh_token": changedGrant && name == "a" ? "fixture-new" : "fixture-" + name], "usageStamp": usageStamp] as [String: Any]
        }
        try JSONSerialization.data(withJSONObject: ["currentAntigravityAccountId": id, "accounts": rows]).write(to: support.appendingPathComponent("accounts.json"))
    }
    func service() -> OpenCodexPoolService {
        let owner = OpenCodexControlOwnership(home: folder, command: { args in
            self.jobCommands.append(args)
            if args.first == "print" { return (self.legacyLoaded ? 0 : 113, self.script.path) }
            if args.first == "bootout" {
                if self.refuseStop { return (1, "") }
                self.legacyLoaded = false
            }
            return (0, "")
        })
        return OpenCodexPoolService(home: folder.appendingPathComponent(".opencodex"), policyURL: support.appendingPathComponent("policy.json"), localQuotaURL: support.appendingPathComponent("accounts.json"), loader: { req in
            let object = req.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any] ?? [:]
            var response: [String: Any] = ["ok": true]
            if req.url!.path.hasSuffix("/pool") {
                if req.httpMethod == "PUT" { self.nativeEnabled = object["enabled"] as! Bool }
                response = ["enabled": self.nativeEnabled]
            } else if req.url!.path.hasSuffix("/active") {
                if !self.ignoreActiveWrite { self.active = object["accountId"] as! String }; self.activeWrites += 1
            } else {
                response = ["activeAccountId": self.active, "accounts": ["a", "b"].map { id in
                    var row: [String: Any] = ["id": id, "email": id + "@example.com", "paused": false]
                    if self.provideQuota {
                        let now = Date().timeIntervalSince1970 * 1000
                        row["quota"] = ["updatedAt": now, "customWindows": [["label": "Gemini 5h", "percent": id == "a" ? 99 : 30, "resetAt": now + 3_600_000]]]
                    }
                    return row
                }]
            }
            return (try JSONSerialization.data(withJSONObject: response), HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }, ownershipOverride: owner, nativeSelection: { self.nativeEmail }, syncWorker: { data in
            if (try? JSONDecoder().decode(JSONValue.self, from: data)["action"]?.stringValue) == "probe" { return Data(#"{"supported":true}"#.utf8) }
            self.workerCalls += 1; self.lastPayload = data
            if self.cancelWorker { throw CancellationError() }
            if self.workerFailure { throw AppError.io("fixture sync failed") }
            return Data(#"{"inserted":1,"updated":0,"superseded":0}"#.utf8)
        }, credentialValidator: { auth, email in
            self.validations += 1
            return (auth, .object(["email": .string(email), "refresh": auth["refresh_token"]!, "access": .string("verified-access"), "expires": .number(4_000_000_000_000), "projectId": .string("verified-project")]))
        })
    }
}
