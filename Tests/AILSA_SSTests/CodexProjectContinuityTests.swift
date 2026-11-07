import Foundation
import XCTest
@testable import AILSA_SS

final class CodexProjectContinuityTests: XCTestCase {
    private let host = "local:/fixture/.codex"
    private func project(_ id: String, name: String = "Local project") -> JSONValue {
        .object(["id": .string(id), "name": .string(name), "rootPaths": .array([.string("/fixture/" + id)])])
    }
    private func fixture() -> JSONValue {
        .object([
            "electron-account-renderer-state-v1": .object([
                "owner": .string("source"), "inactive": .object([
                    "unrelated": .object(["atoms": .object(["private": .string("untouched")]), "globals": .object([:])])
                ])
            ]),
            "local-projects": .object(["p1": project("p1")]),
            "project-order": .array([.string("p1")]),
            "thread-project-assignments": .object([
                "t1": .object(["projectKind": .string("local"), "projectId": .string("p1")]),
                "cloud": .object(["projectKind": .string("cloud"), "projectId": .string("cloud-p")]),
                "remote": .object(["projectKind": .string("local"), "projectId": .string("p1")])
            ]),
            "thread-project-membership-host-ids": .object(["t1": .string("local"), "remote": .string("ssh:remote")]),
            "pinned-thread-ids": .array([.string("t1"), .string("cloud"), .string("remote")]),
            "sidebar-project-thread-orders": .object(["p1": .object([
                "threadIds": .array([.string("t1"), .string("cloud"), .string("remote")]), "sortKey": .string("0")
            ])]),
            "app-server-project-id-by-legacy-project-id-by-host": .object([
                host: .object(["p1": .string("core-p1"), "ghost": .string("excluded")]),
                "ssh:remote": .object(["remote-p": .string("remote-id")])
            ]),
            "app-server-projects-migration-by-host": .object([host: .object([
                "version": .number(1), "projectsMigrated": .bool(true),
                "threadAssignmentsMigrated": .bool(true), "threadAssignmentsReadMigrated": .bool(true)
            ])]),
            "electron-persisted-atom-state": .object(["private-identity": .string("source-only")]),
            "environment-catalog-cache-v2": .object(["account-private": .bool(true)]),
            "active-workspace-roots": .array([.string("do-not-copy")])
        ])
    }
    private func planned(_ state: JSONValue) throws -> JSONValue {
        try CodexLocalProjectContinuity.preserving(state, sourceOwner: "source", targetOwner: "target", localHost: host)
    }
    private func targetGlobals(_ state: JSONValue) -> JSONValue? {
        state[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["target"]?["globals"]
    }

    func testRestoresProjectsWhenNativeAccountOwnerSelectsPreviouslyEmptyTarget() throws {
        let before = fixture(), after = try planned(before)
        let globals = try XCTUnwrap(targetGlobals(after))
        XCTAssertEqual(globals["local-projects"]?["p1"], project("p1"))
        XCTAssertEqual(globals["project-order"], .array([.string("p1")]))
        XCTAssertEqual(globals["thread-project-assignments"]?["t1"], before["thread-project-assignments"]?["t1"])
        XCTAssertEqual(after[CodexLocalProjectContinuity.rendererKey]?["owner"], .string("source"))
        XCTAssertEqual(after["local-projects"], before["local-projects"])
        XCTAssertEqual(after[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["unrelated"], before[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["unrelated"])
        XCTAssertEqual(globals["app-server-project-id-by-legacy-project-id-by-host"]?[host]?["p1"], .string("core-p1"))
        XCTAssertEqual(globals["app-server-projects-migration-by-host"]?[host]?["projectsMigrated"], .bool(true))
        XCTAssertEqual(globals["app-server-projects-migration-by-host"]?[host]?["threadAssignmentsMigrated"], .bool(false))
        XCTAssertNil(globals["app-server-projects-migration-by-host"]?[host]?["threadAssignmentsReadMigrated"])
        XCTAssertEqual(globals["app-server-projects-migration-by-host"]?[host]?["pendingThreadAssignmentIds"], .array([.string("t1")]))
    }

    func testExcludesCloudRemoteAtomsIdentityAndWorkspaceSelection() throws {
        let state = try planned(fixture()), globals = try XCTUnwrap(targetGlobals(state))
        XCTAssertNil(globals["thread-project-assignments"]?["cloud"])
        XCTAssertNil(globals["thread-project-assignments"]?["remote"])
        XCTAssertNil(globals["app-server-project-id-by-legacy-project-id-by-host"]?["ssh:remote"])
        XCTAssertNil(globals["app-server-project-id-by-legacy-project-id-by-host"]?[host]?["ghost"])
        XCTAssertNil(globals["electron-persisted-atom-state"])
        XCTAssertNil(globals["environment-catalog-cache-v2"])
        XCTAssertNil(globals["active-workspace-roots"])
        XCTAssertEqual(globals["pinned-thread-ids"], .array([.string("t1")]))
        XCTAssertEqual(globals["sidebar-project-thread-orders"]?["p1"]?["threadIds"], .array([.string("t1")]))
        XCTAssertEqual(state[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["target"]?["atoms"], .object([:]))
    }

    func testPreservesExistingTargetEditsCloudDataAndExplicitUnassignment() throws {
        var root = fixture().objectValue!, renderer = root[CodexLocalProjectContinuity.rendererKey]!.objectValue!
        var inactive = renderer["inactive"]!.objectValue!
        inactive["target"] = .object(["atoms": .object(["identity": .string("target-private")]), "globals": .object([
            "local-projects": .object(["p1": project("p1", name: "Target renamed"), "p2": project("p2")]),
            "project-order": .array([.string("p2"), .string("p1")]),
            "projectless-thread-ids": .array([.string("t1")]),
            "thread-project-assignments": .object(["target-cloud": .object(["projectKind": .string("cloud")])]),
            "unknown-target-key": .string("untouched")
        ])])
        renderer["inactive"] = .object(inactive); root[CodexLocalProjectContinuity.rendererKey] = .object(renderer)
        let state = try planned(.object(root)), globals = try XCTUnwrap(targetGlobals(state))
        XCTAssertEqual(globals["local-projects"]?["p1"]?["name"], .string("Target renamed"))
        XCTAssertEqual(globals["project-order"], .array([.string("p2"), .string("p1")]))
        XCTAssertNil(globals["thread-project-assignments"]?["t1"])
        XCTAssertNotNil(globals["thread-project-assignments"]?["target-cloud"])
        XCTAssertEqual(globals["unknown-target-key"], .string("untouched"))
        XCTAssertEqual(state[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["target"]?["atoms"]?["identity"], .string("target-private"))
    }

    func testFailsClosedForMismatchedOwnerUnknownSchemaAndCorruptProjects() throws {
        XCTAssertThrowsError(try CodexLocalProjectContinuity.preserving(fixture(), sourceOwner: "wrong", targetOwner: "target", localHost: host))
        XCTAssertThrowsError(try planned(.object([CodexLocalProjectContinuity.rendererKey: .string("new-format")])))
        var root = fixture().objectValue!; root["local-projects"] = .object(["bad": .object([:])])
        XCTAssertThrowsError(try planned(.object(root)))
    }

    func testAlreadySelectedOwnerIsNoOpAndPlanningIsIdempotent() throws {
        let initial = fixture()
        XCTAssertEqual(try CodexLocalProjectContinuity.preserving(initial, sourceOwner: "source", targetOwner: "source", localHost: host), initial)
        let first = try planned(initial)
        XCTAssertEqual(try planned(first), first)
    }

    private func auth(_ user: String, _ account: String) -> JSONValue {
        let data = try! JSONSerialization.data(withJSONObject: ["sub": "not-the-renderer-user", "https://api.openai.com/auth": ["chatgpt_user_id": user, "chatgpt_account_id": account]])
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return .object(["tokens": .object(["access_token": .string("fixture-access"), "account_id": .string(account), "id_token": .string("test." + encoded + ".test")])])
    }

    func testOwnerMatchesDesktopHashAndRejectsMissingIdentity() throws {
        // SHA256 of the desktop's JSON.stringify([userId, accountId]).
        XCTAssertEqual(CodexLocalProjectContinuity.owner(from: auth("user-a", "account-a")), "567b1ccd06bd57086baaf486a2b8bb6f3bc056178d6ea5109162d06cd42b62f1")
        XCTAssertNil(CodexLocalProjectContinuity.owner(from: .object([:])))
    }

    func testPreservesAuthenticatedSourceSnapshotAfterDesktopHasArchivedOwner() throws {
        var root = fixture().objectValue!, renderer = root[CodexLocalProjectContinuity.rendererKey]!.objectValue!
        var inactive = renderer["inactive"]!.objectValue!
        inactive["source"] = .object(["atoms": .object([:]), "globals": .object(root.filter { $0.key != CodexLocalProjectContinuity.rendererKey })])
        renderer["owner"] = .null; renderer["inactive"] = .object(inactive)
        root = [CodexLocalProjectContinuity.rendererKey: .object(renderer)]
        XCTAssertEqual(try targetGlobals(planned(.object(root)))?["local-projects"]?["p1"], project("p1"))
        XCTAssertEqual(try CodexLocalProjectContinuity.preserving(.object(root), sourceOwner: nil, targetOwner: "target", localHost: host), .object(root))
    }

    private func transactionFixture() throws -> (URL, JSONValue, JSONValue, Data) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let current = auth("user-a", "account-a"), next = auth("user-b", "account-b")
        var root = fixture().objectValue!, renderer = root[CodexLocalProjectContinuity.rendererKey]!.objectValue!
        renderer["owner"] = .string(CodexLocalProjectContinuity.owner(from: current)!)
        root[CodexLocalProjectContinuity.rendererKey] = .object(renderer)
        let original = try JSONEncoder().encode(JSONValue.object(root))
        try original.write(to: dir.appendingPathComponent(".codex-global-state.json"))
        return (dir, current, next, original)
    }

    func testTransactionQuitsBeforeStateAndAuthAndCreatesPrivateBackup() throws {
        let (dir, current, next, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var events: [String] = [], running = true
        let service = CodexProjectContinuityService(home: dir, quit: { events.append("quit"); running = false }, isRunning: { running })
        try service.writeAuthPreservingProjects(current: current, next: next) { events.append("auth") }
        XCTAssertEqual(events, ["quit", "auth"])
        let backupRoot = dir.appendingPathComponent("subswitch-project-backups")
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0].appendingPathComponent("codex-global-state.json")), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: backups[0].appendingPathComponent("codex-global-state.json").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testRejectedQuitNeverWritesStateOrCredentials() throws {
        let (dir, current, next, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var wroteAuth = false
        let service = CodexProjectContinuityService(home: dir, quit: {}, isRunning: { true })
        XCTAssertThrowsError(try service.writeAuthPreservingProjects(current: current, next: next) { wroteAuth = true })
        XCTAssertFalse(wroteAuth)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
    }

    func testAuthFailureRollsBackExactStateBytes() throws {
        let (dir, current, next, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let service = CodexProjectContinuityService(home: dir, quit: {}, isRunning: { false })
        XCTAssertThrowsError(try service.writeAuthPreservingProjects(current: current, next: next) { throw NSError(domain: "fixture", code: 1) })
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
    }

    func testSameAccountTokenRefreshDoesNotQuitBackupOrRewriteState() throws {
        let (dir, current, _, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var quit = false, wrote = false
        let service = CodexProjectContinuityService(home: dir, quit: { quit = true }, isRunning: { true })
        try service.writeAuthPreservingProjects(current: current, next: current) { wrote = true }
        XCTAssertFalse(quit); XCTAssertTrue(wrote)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("subswitch-project-backups").path))
    }
    func testRealAuthRepositoryAndCardSelectionRemainUnchangedWhenQuitIsCancelled() throws {
        let (dir, current, next, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = FileSystemPaths(applicationSupportDirectory: dir,
            accountStorePath: dir.appendingPathComponent("accounts.json"), settingsStorePath: dir.appendingPathComponent("settings.json"),
            codexAuthPath: dir.appendingPathComponent("auth.json"), codexConfigPath: dir.appendingPathComponent("config.toml"))
        let originalAuth = try JSONEncoder().encode(current)
        try originalAuth.write(to: paths.codexAuthPath)
        let service = CodexProjectContinuityService(home: dir, quit: {}, isRunning: { true })
        let repo = AuthFileRepository(paths: paths, projectContinuity: service)
        let accounts = [current, next].enumerated().map { i, auth in
            StoredAccount(id: "card-\(i)", label: "Fixture", email: nil, accountID: "account-\(i)",
                planType: "pro", teamName: nil, teamAlias: nil, authJSON: auth, addedAt: 0, updatedAt: 0, usage: nil, usageError: nil)
        }
        let store = StoreFileRepository(paths: paths)
        let before = AccountsStore(accounts: accounts, currentAccountID: accounts[0].id,
            currentSelection: CurrentAccountSelection(cardID: accounts[0].id, selectedAt: 1, sourceDeviceID: "fixture"))
        try store.saveStore(before)
        let writer = CurrentAccountProjectionWriter(storeRepository: store, authRepository: repo,
            dateProvider: SystemDateProvider(), runtimePlatform: .macOS)
        XCTAssertThrowsError(try writer.apply(account: accounts[1]))
        XCTAssertEqual(try store.loadStore(), before)
        XCTAssertEqual(try Data(contentsOf: paths.codexAuthPath), originalAuth)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
    }

    func testNativeOwnerArchiveAndRestoreKeepProjectsAcrossRoundTrip() throws {
        let first = try planned(fixture())
        // Model Codex's selectRendererOwner: archive current globals, then load
        // target.globals. The production helper never alters renderer.owner.
        var root = first.objectValue!, renderer = root[CodexLocalProjectContinuity.rendererKey]!.objectValue!
        var inactive = renderer["inactive"]!.objectValue!
        inactive["source"] = .object(["atoms": root["electron-persisted-atom-state"]!, "globals": .object(root.filter { $0.key != CodexLocalProjectContinuity.rendererKey })])
        let target = inactive.removeValue(forKey: "target")!
        root = target["globals"]!.objectValue!
        renderer["owner"] = .string("target"); renderer["inactive"] = .object(inactive)
        root[CodexLocalProjectContinuity.rendererKey] = .object(renderer)
        root["electron-persisted-atom-state"] = target["atoms"]!
        XCTAssertNotNil(root["local-projects"]?["p1"])
        XCTAssertNotNil(root["thread-project-assignments"]?["t1"])
        let roundTrip = try CodexLocalProjectContinuity.preserving(.object(root), sourceOwner: "target", targetOwner: "source", localHost: host)
        XCTAssertEqual(roundTrip[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["source"]?["globals"]?["local-projects"]?["p1"], project("p1"))
        XCTAssertEqual(roundTrip[CodexLocalProjectContinuity.rendererKey]?["inactive"]?["source"]?["atoms"]?["private-identity"], .string("source-only"))
    }

    func testAppRestartDuringPreparationAbortsBeforeAuth() throws {
        let (dir, current, next, _) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        var checks = 0, wrote = false
        let service = CodexProjectContinuityService(home: dir, quit: {}, isRunning: { checks += 1; return checks > 1 })
        XCTAssertThrowsError(try service.writeAuthPreservingProjects(current: current, next: next) { wrote = true })
        XCTAssertFalse(wrote)
    }

    func testUnsupportedMigrationDoesNotModifySource() throws {
        var root = fixture().objectValue!
        root["app-server-projects-migration-by-host"] = .object([host: .object(["version": .number(99)])])
        XCTAssertThrowsError(try planned(.object(root)))
        XCTAssertEqual(root["local-projects"]?["p1"], project("p1"))
    }

    func testFreshSignInWithoutPreviousIdentityDoesNotInheritAnotherAccount() throws {
        let original = fixture()
        XCTAssertEqual(try CodexLocalProjectContinuity.preserving(original, sourceOwner: nil, targetOwner: "target", localHost: host), original)
    }

    func testBackgroundMaintenanceCannotQuitDesktopOrSilentlyChangeIdentity() throws {
        let (dir, current, next, original) = try transactionFixture()
        defer { try? FileManager.default.removeItem(at: dir) }
        let paths = FileSystemPaths(applicationSupportDirectory: dir,
            accountStorePath: dir.appendingPathComponent("accounts.json"), settingsStorePath: dir.appendingPathComponent("settings.json"),
            codexAuthPath: dir.appendingPathComponent("auth.json"), codexConfigPath: dir.appendingPathComponent("config.toml"))
        let originalAuth = try JSONEncoder().encode(current)
        try originalAuth.write(to: paths.codexAuthPath)
        var quit = false
        let service = CodexProjectContinuityService(home: dir, quit: { quit = true }, isRunning: { true })
        let repo = AuthFileRepository(paths: paths, projectContinuity: service)
        XCTAssertThrowsError(try repo.writeCurrentAuth(next))
        XCTAssertFalse(quit)
        XCTAssertEqual(try Data(contentsOf: paths.codexAuthPath), originalAuth)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
        try repo.writeCurrentAuth(current)
        XCTAssertFalse(quit)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent(".codex-global-state.json")), original)
    }

}
