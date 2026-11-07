import CryptoKit
import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Darwin)
import Darwin
#endif

/// Carries only this computer's project navigation across an explicit account
/// switch. Account identities, renderer atoms, cloud/remote projects, auth and
/// server-side account isolation remain owned by Codex.
enum CodexLocalProjectContinuity {
    static let rendererKey = "electron-account-renderer-state-v1"

    static func owner(from auth: JSONValue?) -> String? {
        guard let auth, let tokens = AuthJWTDecoder.tokenObject(from: auth),
              let jwt = tokens["id_token"]?.stringValue,
              let claims = try? AuthJWTDecoder.decodePayload(jwt),
              let scope = claims["https://api.openai.com/auth"]?.objectValue,
              let user = scope["chatgpt_user_id"]?.stringValue
                ?? scope["user_id"]?.stringValue ?? claims["sub"]?.stringValue,
              let account = tokens["account_id"]?.stringValue
                ?? scope["chatgpt_account_id"]?.stringValue,
              !user.isEmpty, !account.isEmpty,
              scope["chatgpt_account_id"]?.stringValue.map({ $0 == account }) ?? true,
              let data = try? JSONSerialization.data(withJSONObject: [user, account], options: [.withoutEscapingSlashes])
        else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func preserving(_ state: JSONValue, sourceOwner: String?, targetOwner: String, localHost: String) throws -> JSONValue {
        guard var root = state.objectValue,
              var renderer = root[rendererKey]?.objectValue,
              var inactive = renderer["inactive"]?.objectValue,
              renderer["owner"] == .null || renderer["owner"]?.stringValue != nil
        else { throw failure("state_format") }
        let currentOwner = renderer["owner"]?.stringValue
        if currentOwner == targetOwner { return state }
        // A fresh sign-in without a known previous identity must not inherit
        // another account snapshot. Let Codex apply its normal isolation.
        guard sourceOwner != nil else { return state }
        if let currentOwner, currentOwner != sourceOwner { throw failure("identity_mismatch") }
        let source: [String: JSONValue]
        if currentOwner != nil {
            source = root
        } else if let sourceOwner, let saved = inactive[sourceOwner]?["globals"]?.objectValue {
            source = saved
        } else {
            // No authenticated source: never guess which inactive account owns
            // the user's projects or select the largest unrelated snapshot.
            return state
        }
        let sourceProjects = try dictionary(source, "local-projects")
        if sourceProjects.isEmpty { return state }
        for (id, project) in sourceProjects {
            guard project["id"]?.stringValue == id,
                  let roots = project["rootPaths"]?.arrayValue,
                  !roots.isEmpty, roots.allSatisfy({ $0.stringValue != nil })
            else { throw failure("project_format") }
        }
        var target = inactive[targetOwner]?.objectValue ?? ["atoms": .object([:]), "globals": .object([:])]
        guard target["atoms"]?.objectValue != nil, var globals = target["globals"]?.objectValue else {
            throw failure("target_format")
        }
        let targetProjects = try dictionary(globals, "local-projects")
        globals["local-projects"] = .object(sourceProjects.merging(targetProjects) { _, existing in existing })
        globals["project-order"] = .array(try union(
            strings(globals, "project-order"),
            strings(source, "project-order").filter { sourceProjects[$0.stringValue ?? ""] != nil }
        ))
        let sourceMembership = try dictionary(source, "thread-project-membership-host-ids")
        let existingAssignments = try dictionary(globals, "thread-project-assignments")
        var assignments = existingAssignments
        var members = try dictionary(globals, "thread-project-membership-host-ids")
        let explicitlyProjectless = Set(try strings(globals, "projectless-thread-ids").compactMap(\.stringValue))
        var carriedThreads = Set<String>()
        for (thread, assignment) in try dictionary(source, "thread-project-assignments") {
            let host = sourceMembership[thread]?.stringValue
            guard assignment["projectKind"]?.stringValue == "local",
                  let project = assignment["projectId"]?.stringValue, sourceProjects[project] != nil,
                  host == nil || host == "local" || host == localHost,
                  !explicitlyProjectless.contains(thread), assignments[thread] == nil else { continue }
            assignments[thread] = assignment
            carriedThreads.insert(thread)
            if let membership = sourceMembership[thread] { members[thread] = membership }
        }
        globals["thread-project-assignments"] = .object(assignments)
        globals["thread-project-membership-host-ids"] = .object(members)
        for key in ["thread-workspace-root-hints", "thread-projectless-output-directories"] {
            var existing = try dictionary(globals, key)
            for (id, value) in try dictionary(source, key) where carriedThreads.contains(id) && existing[id] == nil {
                existing[id] = value
            }
            globals[key] = .object(existing)
        }
        for key in ["sidebar-project-thread-orders", "project-appearances"] {
            var existing = try dictionary(globals, key)
            for (id, value) in try dictionary(source, key) where sourceProjects[id] != nil && existing[id] == nil {
                // Sidebar orders refer only to local assignments carried here.
                if key == "sidebar-project-thread-orders", var order = value.objectValue {
                    order["threadIds"] = .array((value["threadIds"]?.arrayValue ?? []).filter {
                        guard let id = $0.stringValue else { return false }
                        return carriedThreads.contains(id)
                    })
                    existing[id] = .object(order)
                } else { existing[id] = value }
            }
            globals[key] = .object(existing)
        }
        globals["pinned-thread-ids"] = .array(try union(strings(globals, "pinned-thread-ids"),
            strings(source, "pinned-thread-ids").filter { carriedThreads.contains($0.stringValue ?? "") }))
        let mapKey = "app-server-project-id-by-legacy-project-id-by-host"
        var maps = try dictionary(globals, mapKey)
        let sourceMap = try dictionary(source, mapKey)[localHost]?.objectValue ?? [:]
        let targetMap = maps[localHost]?.objectValue ?? [:]
        maps[localHost] = .object(sourceMap.filter { sourceProjects[$0.key] != nil }.merging(targetMap) { _, existing in existing })
        globals[mapKey] = .object(maps)
        let migrationKey = "app-server-projects-migration-by-host"
        var migrations = try dictionary(globals, migrationKey)
        var migration = try migrations[localHost]?.objectValue
            ?? dictionary(source, migrationKey)[localHost]?.objectValue ?? [:]
        if let version = migration["version"], version != .number(1) { throw failure("migration_format") }
        migration["version"] = .number(1)
        // Reconcile newly carried local assignments with the shared local
        // app-server DB. Do not reset cloud/remote migrations or recreate IDs.
        if !carriedThreads.isEmpty || Set(sourceProjects.keys).subtracting(targetProjects.keys).isEmpty == false {
            migration["threadAssignmentsMigrated"] = .bool(false)
            migration.removeValue(forKey: "threadAssignmentsReadMigrated")
            migration["pendingThreadAssignmentIds"] = .array(try union(
                strings(migration, "pendingThreadAssignmentIds"), carriedThreads.sorted().map(JSONValue.string)))
            migrations[localHost] = .object(migration)
            globals[migrationKey] = .object(migrations)
        }
        target["globals"] = .object(globals)
        inactive[targetOwner] = .object(target)
        renderer["inactive"] = .object(inactive)
        // In particular, do not replace `owner` to disguise the login change.
        root[rendererKey] = .object(renderer)
        return .object(root)
    }

    private static func dictionary(_ object: [String: JSONValue], _ key: String) throws -> [String: JSONValue] {
        guard let value = object[key] else { return [:] }
        guard let result = value.objectValue else { throw failure("field_format") }
        return result
    }

    private static func strings(_ object: [String: JSONValue], _ key: String) throws -> [JSONValue] {
        guard let value = object[key] else { return [] }
        guard let values = value.arrayValue, values.allSatisfy({ $0.stringValue != nil }) else { throw failure("field_format") }
        return values
    }

    private static func union(_ first: [JSONValue], _ second: [JSONValue]) -> [JSONValue] {
        var seen = Set<JSONValue>()
        return (first + second).filter { seen.insert($0).inserted }
    }

    static func failure(_ reason: String) -> AppError {
        .io(L10n.tr("error.codex_projects.preservation_failed_format", reason))
    }
}

/// All file mutations occur after the exact Codex desktop bundle exits. A
/// rejected quit, concurrent writer or unsupported schema aborts before auth.
final class CodexProjectContinuityService: @unchecked Sendable {
    let home: URL
    private let quit: () throws -> Void
    private let isRunning: () -> Bool
    private let fileManager: FileManager

    init(home: URL, fileManager: FileManager = .default,
         quit: @escaping () throws -> Void = CodexDesktopLifecycle.quitGracefully,
         isRunning: @escaping () -> Bool = CodexDesktopLifecycle.isRunning) {
        self.home = home
        self.fileManager = fileManager
        self.quit = quit
        self.isRunning = isRunning
    }

    func writeAuthPreservingProjects(current: JSONValue?, next: JSONValue, writeAuth: () throws -> Void) throws {
        let stateURL = home.appendingPathComponent(".codex-global-state.json")
        guard fileManager.fileExists(atPath: stateURL.path) else { try writeAuth(); return }
        let data = try Data(contentsOf: stateURL)
        let initial = try JSONDecoder().decode(JSONValue.self, from: data)
        guard initial[CodexLocalProjectContinuity.rendererKey] != nil else { try writeAuth(); return }
        guard let target = CodexLocalProjectContinuity.owner(from: next) else {
            throw CodexLocalProjectContinuity.failure("identity_unknown")
        }
        let source = CodexLocalProjectContinuity.owner(from: current)
        if source == target { try writeAuth(); return }
        try quit()
        guard !isRunning() else { throw CodexLocalProjectContinuity.failure("app_running") }
        // Serialize SubSwitch account writes across processes. Codex doesn't
        // use this lock, so also verify its absence and compare file bytes.
        let lockURL = home.appendingPathComponent(".subswitch-project-switch.lock")
        #if canImport(Darwin)
        let fd = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw CodexLocalProjectContinuity.failure("lock_failed") }
        defer { _ = close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw CodexLocalProjectContinuity.failure("switch_busy") }
        defer { _ = flock(fd, LOCK_UN) }
        #endif
        let original = try Data(contentsOf: stateURL)
        let state = try JSONDecoder().decode(JSONValue.self, from: original)
        let updated = try CodexLocalProjectContinuity.preserving(state, sourceOwner: source,
            targetOwner: target, localHost: "local:" + home.path)
        let changed = updated != state
        var written: Data?
        if changed {
            let backup = home.appendingPathComponent("subswitch-project-backups", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: backup.deletingLastPathComponent().path)
            try secureWrite(original, to: backup.appendingPathComponent("codex-global-state.json"))
            let oldBackup = stateURL.appendingPathExtension("bak")
            if fileManager.fileExists(atPath: oldBackup.path) {
                try secureWrite(Data(contentsOf: oldBackup), to: backup.appendingPathComponent("codex-global-state.json.bak"))
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let output = try encoder.encode(updated)
            guard !isRunning(), try Data(contentsOf: stateURL) == original else {
                throw CodexLocalProjectContinuity.failure("concurrent_change")
            }
            try secureWrite(output, to: stateURL)
            written = output
        }
        do {
            guard !isRunning() else { throw CodexLocalProjectContinuity.failure("app_running") }
            try writeAuth()
        } catch {
            if let written, !isRunning(), (try? Data(contentsOf: stateURL)) == written {
                try secureWrite(original, to: stateURL)
            }
            throw error
        }
    }

    private func secureWrite(_ data: Data, to path: URL) throws {
        try data.write(to: path, options: [.atomic])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}

/// Normal quit only; never SIGKILL, spoof identities or patch the desktop app.
enum CodexDesktopLifecycle {
    #if canImport(AppKit)
    private static var applications: [NSRunningApplication] {
        // Current Codex may be packaged as ChatGPT.app. Match its bundle ID,
        // not every unrelated process named ChatGPT or every Codex CLI worker.
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex")
    }
    #endif

    static func isRunning() -> Bool {
        #if canImport(AppKit)
        return !applications.isEmpty
        #else
        return false
        #endif
    }

    static func quitGracefully() throws {
        #if canImport(AppKit)
        let running = applications
        guard !running.isEmpty else { return }
        for app in running { _ = app.terminate() }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if running.allSatisfy(\.isTerminated) && !isRunning() { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw AppError.io(L10n.tr("error.codex_projects.quit_cancelled"))
        #endif
    }
}
