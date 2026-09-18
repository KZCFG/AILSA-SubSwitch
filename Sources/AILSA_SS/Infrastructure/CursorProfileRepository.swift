import Foundation
import SQLite3
#if os(macOS)
import AppKit
#endif

struct CursorSavedProfile: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let savedAt: Date
    let values: [String: String]
}

/// Only Cursor authentication keys are captured. Chat history, workspaces,
/// machine IDs and the rest of the native SQLite database are never copied.
actor CursorProfileRepository {
    static let shared = CursorProfileRepository()
    static let keys = ["cursorAuth/accessToken", "cursorAuth/refreshToken", "cursorAuth/cachedEmail", "cursorAuth/cachedScopedProfile", "cursorAuth/cachedSignUpType", "cursorAuth/onboardingDate", "cursorAuth/stripeMembershipAuthId", "cursorAuth/stripeMembershipType", "cursorAuth/stripeSubscriptionStatus"]
    private let profileURL: URL
    let databaseURL: URL
    init(profileURL: URL? = nil, databaseURL: URL? = nil) {
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.profileURL = profileURL ?? home.appendingPathComponent("Library/Application Support/CodexToolsSwift/cursor-profiles.json")
        self.databaseURL = databaseURL ?? home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }
    func profiles() throws -> [CursorSavedProfile] {
        guard FileManager.default.fileExists(atPath: profileURL.path) else { return [] }
        return try JSONDecoder().decode([CursorSavedProfile].self, from: Data(contentsOf: profileURL))
    }
    func save(_ profile: CursorSavedProfile) throws {
        var values = try profiles().filter { $0.id != profile.id }; values.append(profile)
        try FileManager.default.createDirectory(at: profileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values)
        let temp = profileURL.deletingLastPathComponent().appendingPathComponent(".cursor-profiles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: temp) }
        guard FileManager.default.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CursorUsageError.invalidResponse }
        if FileManager.default.fileExists(atPath: profileURL.path) { _ = try FileManager.default.replaceItemAt(profileURL, withItemAt: temp) }
        else { try FileManager.default.moveItem(at: temp, to: profileURL) }
    }
    func readNativeValues() throws -> [String: String] {
        try withDatabase(writable: false) { db in
            var result: [String: String] = [:]
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT key,value FROM ItemTable WHERE key LIKE 'cursorAuth/%'", -1, &statement, nil) == SQLITE_OK else { throw CursorUsageError.invalidResponse }
            defer { sqlite3_finalize(statement) }
            var step = sqlite3_step(statement)
            while step == SQLITE_ROW {
                if let key = sqlite3_column_text(statement, 0), let value = sqlite3_column_text(statement, 1) {
                    let name = String(cString: key)
                    if Self.keys.contains(name) { result[name] = String(cString: value) }
                }
                step = sqlite3_step(statement)
            }
            guard step == SQLITE_DONE else { throw CursorUsageError.invalidResponse }
            return result
        }
    }
    /// Caller must gracefully stop Cursor before invoking this transaction.
    /// A missing key is deleted, so rollback restores absence as well as values.
    func replaceNativeValues(_ values: [String: String]) async throws {
        #if os(macOS)
        if databaseURL.path == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb").path {
            let running = await MainActor.run { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.todesktop.230313mzl4w4u92").isEmpty }
            guard !running else { throw CursorSwitchError.applicationStillRunning }
        }
        #endif
        try withDatabase(writable: true) { db in
            guard sqlite3_exec(db, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK else { throw CursorUsageError.invalidResponse }
            var committed = false
            defer { if !committed { sqlite3_exec(db, "ROLLBACK", nil, nil, nil) } }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            for key in Self.keys {
                var statement: OpaquePointer?
                let query = values[key] == nil ? "DELETE FROM ItemTable WHERE key=?" : "INSERT OR REPLACE INTO ItemTable(key,value) VALUES(?,?)"
                guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else { throw CursorUsageError.invalidResponse }
                defer { sqlite3_finalize(statement) }
                guard sqlite3_bind_text(statement, 1, key, -1, transient) == SQLITE_OK else { throw CursorUsageError.invalidResponse }
                if let value = values[key], sqlite3_bind_text(statement, 2, value, -1, transient) != SQLITE_OK { throw CursorUsageError.invalidResponse }
                guard sqlite3_step(statement) == SQLITE_DONE else { throw CursorUsageError.invalidResponse }
            }
            guard sqlite3_exec(db, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw CursorUsageError.invalidResponse }
            committed = true
        }
    }
    func captureCurrent() async throws -> CursorSavedProfile {
        let values = try readNativeValues()
        let usage = try await CursorUsageService.shared.loadAccount(values: values)
        guard try readNativeValues()["cursorAuth/accessToken"] == values["cursorAuth/accessToken"] else { throw CursorUsageError.invalidIdentity }
        let profile = CursorSavedProfile(id: usage.id, email: usage.email, savedAt: Date(), values: values)
        try save(profile)
        return profile
    }
    private var journalURL: URL { profileURL.deletingLastPathComponent().appendingPathComponent("cursor-switch-recovery.json") }
    func recoveryValues() throws -> [String: String]? {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: journalURL))
    }
    func saveRecovery(_ values: [String: String]) throws {
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw CursorSwitchError.pendingRecovery }
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values)
        guard FileManager.default.createFile(atPath: journalURL.path, contents: data, attributes: [.posixPermissions: 0o600]) else { throw CursorUsageError.invalidResponse }
    }
    func clearRecovery() throws {
        if FileManager.default.fileExists(atPath: journalURL.path) { try FileManager.default.removeItem(at: journalURL) }
    }

    private func withDatabase<T>(writable: Bool, _ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        let flags = (writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK, let database = db else {
            if let db { sqlite3_close(db) }; throw CursorUsageError.notLoggedIn
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1500)
        return try body(database)
    }
}
