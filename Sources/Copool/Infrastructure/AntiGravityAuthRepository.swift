import Foundation
import Security
#if canImport(Darwin)
import Darwin
#endif

/// Runs the same signed executable before SwiftUI/AppContainer initialization.
/// Process-wide Keychain interaction suppression must never affect the UI process.
enum AntigravityQuietKeychainBridge {
    static let argument = "--ass-quiet-antigravity-keychain"
    enum Operation: String, Codable { case read, write, preflight }
    struct Request: Codable { let operation: Operation; let data: Data? }
    struct Response: Codable { let data: Data?; let succeeded: Bool }
    private static let maximumBytes = 1_048_576

    private static func readBounded(_ handle: FileHandle) -> Data {
        var bytes = Data()
        while bytes.count <= maximumBytes {
            let chunk = handle.readData(ofLength: min(16_384, maximumBytes + 1 - bytes.count))
            if chunk.isEmpty { break }
            bytes.append(chunk)
        }
        return bytes
    }

    static func runChildIfRequested() {
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1] == argument else { return }
        // A second bound also covers malformed callers that never close stdin.
        DispatchQueue.global().asyncAfter(deadline: .now() + 8) { _exit(70) }
        guard SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { _exit(71) }
        var response = Response(data: nil, succeeded: false)
        do {
            let bytes = readBounded(FileHandle.standardInput)
            guard bytes.count <= maximumBytes else { _exit(72) }
            let request = try JSONDecoder().decode(Request.self, from: bytes)
            let store = NativeAntigravityKeychainStore()
            // Read and write permissions on a legacy item can differ. Never
            // mutate a record that this process cannot first read for recovery.
            let original = try store.readSecret(access: .userInitiated)
            switch request.operation {
            case .read:
                response = Response(data: original, succeeded: true)
            case .preflight:
                guard let original, original == request.data else { _exit(73) }
                try store.preflightWriteAccess(for: original, access: .userInitiated)
                response = Response(data: nil, succeeded: true)
            case .write:
                guard let original, let replacement = request.data else { _exit(73) }
                do {
                    try store.writeSecret(replacement, access: .userInitiated)
                    guard try store.readSecret(access: .userInitiated) == replacement else {
                        throw AntigravityNativeCredentialAccessError.unavailable
                    }
                    response = Response(data: nil, succeeded: true)
                } catch {
                    try store.writeSecret(original, access: .userInitiated)
                    guard try store.readSecret(access: .userInitiated) == original else { _exit(74) }
                    throw error
                }
            }
        } catch {
            // Never send native errors or credential values to stderr/logging.
        }
        guard let output = try? JSONEncoder().encode(response), output.count <= maximumBytes else { _exit(75) }
        FileHandle.standardOutput.write(output)
        _exit(response.succeeded ? 0 : 76)
    }

    /// Private pipes carry values, never command arguments, environment, or files.
    static func perform(_ operation: Operation, data: Data? = nil) throws -> Data? {
        guard let executable = Bundle.main.executableURL else {
            throw AntigravityNativeCredentialAccessError.unavailable
        }
        let request = try JSONEncoder().encode(Request(operation: operation, data: data))
        guard request.count <= maximumBytes else { throw AntigravityNativeCredentialAccessError.unavailable }
        let child = Process()
        child.executableURL = executable
        child.arguments = [argument]
        let input = Pipe(), output = Pipe()
        // A child may reject input or time out while a large request is still
        // being written. Scope SIGPIPE suppression to this pipe, not the app.
        guard fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw AntigravityNativeCredentialAccessError.unavailable
        }
        child.standardInput = input
        child.standardOutput = output
        child.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        child.terminationHandler = { _ in exited.signal() }
        try child.run()
        // Concurrent draining avoids a pipe-buffer deadlock for large secrets.
        let group = DispatchGroup()
        final class ResultBox: @unchecked Sendable { var bytes = Data() }
        let result = ResultBox()
        group.enter()
        DispatchQueue.global().async {
            result.bytes = readBounded(output.fileHandleForReading)
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            try? input.fileHandleForWriting.write(contentsOf: request)
            try? input.fileHandleForWriting.close()
            group.leave()
        }
        let deadline = DispatchTime.now() + 10
        guard exited.wait(timeout: deadline) == .success else {
            if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            _ = exited.wait(timeout: .now() + 1)
            throw AntigravityNativeCredentialAccessError.unavailable
        }
        guard group.wait(timeout: deadline) == .success,
              child.terminationStatus == 0, result.bytes.count <= maximumBytes,
              let response = try? JSONDecoder().decode(Response.self, from: result.bytes), response.succeeded else {
            throw AntigravityNativeCredentialAccessError.backgroundKeychainRequiresExplicitAction
        }
        return response.data
    }
}

/// Narrow abstraction over the one credential record AntiGravity uses for its
/// native token storage. It deliberately has no search/list operation: the
/// integration must never inspect unrelated Keychain items.
protocol AntigravityKeychainStoreProtocol: Sendable {
    var supportsQuietBackgroundAccess: Bool { get }
    /// The required access purpose prevents a background caller from being
    /// silently upgraded into an interactive Keychain operation.
    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data?
    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws
    func removeSecret(access: AntigravityNativeCredentialAccess) throws
    /// Tests whether an existing secret can be updated with the supplied
    /// access intent, without changing its bytes. Background transactions use
    /// this before they stop the native app or stage any credential.
    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws
}

extension AntigravityKeychainStoreProtocol {
    var supportsQuietBackgroundAccess: Bool { false }
    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        guard let existingSecret else {
            if access == .background {
                throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
            }
            return
        }
        try writeSecret(existingSecret, access: access)
    }
}

final class MemoryAntigravityKeychainStore: AntigravityKeychainStoreProtocol, @unchecked Sendable {
    private var secret: Data?

    /// Test-only convenience; production code goes through the purpose-bound
    /// protocol method below.
    func readSecret() throws -> Data? { secret }
    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data? { secret }
    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws { secret = data }
    func removeSecret(access: AntigravityNativeCredentialAccess) throws { secret = nil }
    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        guard let existingSecret else {
            if access == .background {
                throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
            }
            return
        }
        guard secret == existingSecret else {
            throw AntigravityNativeCredentialAccessError.unavailable
        }
    }
}

/// Production access is restricted to the native 2.12.x generic-password
/// record `gemini` / `antigravity`.
final class NativeAntigravityKeychainStore: AntigravityKeychainStoreProtocol, @unchecked Sendable {
    var supportsQuietBackgroundAccess: Bool { true }
    private let service = "gemini"
    private let account = "antigravity"

    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data? {
        if access == .background {
            return try AntigravityQuietKeychainBridge.perform(.read)
        }
        try requireExplicitAction(access)
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw keychainError(status)
        }
        return data
    }

    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws {
        if access == .background {
            _ = try AntigravityQuietKeychainBridge.perform(.write, data: data)
            return
        }
        try requireExplicitAction(access)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(updateStatus)
        }

        var create = query
        create[kSecValueData as String] = data
        let createStatus = SecItemAdd(create as CFDictionary, nil)
        guard createStatus == errSecSuccess else {
            throw keychainError(createStatus)
        }
    }

    func removeSecret(access: AntigravityNativeCredentialAccess) throws {
        try requireExplicitAction(access)
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        if access == .background {
            guard let existingSecret else {
                throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
            }
            _ = try AntigravityQuietKeychainBridge.perform(.preflight, data: existingSecret)
            return
        }
        try requireExplicitAction(access)
        guard let existingSecret else {
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: existingSecret]
        let status = SecItemUpdate(
            baseQuery() as CFDictionary,
            attributes as CFDictionary
        )
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func requireExplicitAction(_ access: AntigravityNativeCredentialAccess) throws {
        guard access == .userInitiated else {
            // The isolated traditional-Keychain investigation established that
            // a locked legacy record can still invoke SecurityAgent despite a
            // per-query no-UI hint. Never risk that interaction in the app's
            // background process until a separately reviewed mechanism exists.
            throw AntigravityNativeCredentialAccessError.backgroundKeychainRequiresExplicitAction
        }
    }

    private func keychainError(_ status: OSStatus) -> AntigravityNativeCredentialAccessError {
        // Do not include queried attributes or values in errors or logs.
        switch status {
        case errSecUserCanceled:
            return .userCancelled
        case errSecAuthFailed:
            return .accessDenied
        case errSecInteractionNotAllowed, errSecInteractionRequired:
            return .interactionRequired
        case errSecNotAvailable:
            return .lockedOrInteractionUnavailable
        default:
            return .unavailable
        }
    }
}

/// Every native credential operation carries its caller's authorization
/// purpose. Background Keychain operations are isolated in a no-UI child;
/// FileTokenStorage continues to use native's explicit fallback marker.
enum AntigravityNativeCredentialAccess: Equatable, Sendable {
    case userInitiated
    case background
}

/// Deliberately redacted Keychain outcomes. These are terminal for one
/// operation so a cancel/deny/locked response cannot start a polling loop.
enum AntigravityNativeCredentialAccessError: LocalizedError, Equatable, Sendable {
    /// Retained for source compatibility with older callers.
    case backgroundReadDisallowed
    /// Retained for source compatibility with earlier preflight experiments.
    case backgroundWritePreflightUnavailable
    /// Traditional macOS Keychain cannot presently be proven non-interactive
    /// for this record. Background work must not call SecItem at all.
    case backgroundKeychainRequiresExplicitAction
    /// Native changed between Keychain and FileTokenStorage while a switch was
    /// being prepared. Do not stage into a storage mode we did not snapshot.
    case nativeCredentialStorageModeChanged
    case userCancelled
    case accessDenied
    case interactionRequired
    case lockedOrInteractionUnavailable
    case unavailable

    var errorDescription: String? {
        let zh = L10n.currentLocale.identifier.hasPrefix("zh")
        switch self {
        case .userCancelled, .accessDenied:
            return zh ? "钥匙串授权已取消或拒绝，账号未切换。需要切换时，请在系统窗口完成授权。" : "Keychain access was cancelled or denied. The account was not switched. Authorize in the system dialog to switch."
        case .backgroundReadDisallowed, .backgroundWritePreflightUnavailable, .backgroundKeychainRequiresExplicitAction:
            return zh ? "当前钥匙串登录模式需要手动授权，自动切换已暂停；请使用账号页切换。" : "This Keychain login mode requires manual authorization. Automatic switching is paused; switch from Accounts."
        case .nativeCredentialStorageModeChanged:
            return zh ? "Antigravity 凭据存储方式已变化，切换已停止，请重新尝试。" : "Antigravity credential storage changed. Switching stopped; please retry."
        case .interactionRequired, .lockedOrInteractionUnavailable:
            return zh ? "请先解锁登录钥匙串并完成系统授权，再切换账号。" : "Unlock the login Keychain and complete system authorization before switching."
        case .unavailable:
            return zh ? "暂时无法访问 Antigravity 钥匙串凭据，账号切换未完成。" : "Antigravity Keychain credentials are unavailable; account switching did not complete."
        }
    }

    var stopsAutomaticRetry: Bool {
        true
    }
}

struct AntigravityNativeCredentialSnapshot: Equatable, Sendable {
    /// Raw bytes are retained only in memory for rollback during one switch.
    /// They are never persisted or logged by Copool.
    var keychainSecret: Data?
    var fallbackFile: Data?
    /// When the native keyring-unavailable marker exists, AntiGravity selects
    /// FileTokenStorage. Copool preserves that marker and does not try to
    /// bypass its Keychain policy.
    var keychainIsBypassed: Bool = false
}

/// Native Antigravity uses go-keyring's text wrapper for its generic-password
/// data. The FileTokenStorage fallback is deliberately *not* passed through
/// this codec: it remains a raw JSON envelope. Snapshot/restore operates on
/// the pre-codec bytes so rollback never introduces a second wrapper.
enum AntigravityNativeKeychainCodec {
    private static let base64Prefix = "go-keyring-base64:"
    private static let legacyHexPrefix = "go-keyring-encoded:"

    static func decode(_ data: Data) throws -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            throw invalidPayloadError()
        }
        if text.hasPrefix(base64Prefix) {
            let encoded = String(text.dropFirst(base64Prefix.count))
            guard let decoded = Data(base64Encoded: encoded), !decoded.isEmpty else {
                throw invalidPayloadError()
            }
            return decoded
        }
        if text.hasPrefix(legacyHexPrefix) {
            let hex = String(text.dropFirst(legacyHexPrefix.count))
            guard let decoded = decodeHex(hex), !decoded.isEmpty else {
                throw invalidPayloadError()
            }
            return decoded
        }
        // Older native installations and memory fixtures may contain the raw
        // JSON envelope. Keep this compatibility read-only; new production
        // writes always use the native default base64 wrapper below.
        return data
    }

    static func encode(_ envelopeJSON: Data) -> Data {
        Data((base64Prefix + envelopeJSON.base64EncodedString()).utf8)
    }

    private static func decodeHex(_ text: String) -> Data? {
        guard text.count.isMultiple(of: 2) else { return nil }
        var bytes = Data()
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private static func invalidPayloadError() -> AppError {
        .invalidData(L10n.tr("error.antigravity.native_keychain_codec_unavailable"))
    }
}

/// Candidate bytes are retained only in memory while the usage service binds
/// them to the running native session. Keychain and FileTokenStorage can differ
/// during a native token renewal, so a missing keyring marker is never enough
/// reason to automatically prefer an older Keychain copy.
struct AntigravityNativeCredentialCandidate: Equatable, Sendable {
    enum Source: String, Equatable, Sendable {
        case keychain
        case fallbackFile
    }

    var authJSON: JSONValue
    var source: Source
}

struct AntigravityAuthPaths: Equatable {
    /// Historical Gemini CLI locations remain read-only migration inputs. They
    /// are not written by this integration.
    var geminiDirectory: URL
    var oauthCredsPath: URL
    var googleAccountsPath: URL
    /// Native FileTokenStorage fallback paired with KeyringTokenStorage.
    var jetskiTokenPath: URL
    /// Native marker: ~/.gemini/cache/antigravity-keyring-unavailable. It is
    /// read only so the app's own Keyring/FileTokenStorage choice is preserved.
    var keyringUnavailableMarkerPath: URL? = nil
    /// The old duplicate Copool AntiGravity store, imported once only.
    var storePath: URL
    /// Historical CodexBar locations are imported read-only only.
    var relayCredentialsPath: URL
    var codexBarConfigPath: URL

    static func live(fileManager: FileManager = .default) -> AntigravityAuthPaths {
        let runtime = AntigravityRuntimePaths.live(fileManager: fileManager)
        return AntigravityAuthPaths(
            geminiDirectory: runtime.geminiDirectory,
            oauthCredsPath: runtime.geminiOAuthPath,
            googleAccountsPath: runtime.geminiAccountsPath,
            jetskiTokenPath: runtime.geminiDirectory.appendingPathComponent(
                "jetski-standalone-oauth-token",
                isDirectory: false
            ),
            keyringUnavailableMarkerPath: runtime.geminiDirectory
                .appendingPathComponent("cache", isDirectory: true)
                .appendingPathComponent("antigravity-keyring-unavailable", isDirectory: false),
            storePath: runtime.storePath,
            relayCredentialsPath: runtime.codexBarOAuthMirrorPath,
            codexBarConfigPath: runtime.codexBarConfigPath
        )
    }
}

/// Owns only native-token serialization and read-only account import. The
/// coordinator performs process lifecycle, verified RPC readback, marker
/// commit, and rollback; callers must not stage credentials outside that
/// transaction.
final class AntigravityAuthRepository: @unchecked Sendable {
    private let paths: AntigravityAuthPaths
    private let fileManager: FileManager
    private let decoder: JSONDecoder
    private let keychainStore: AntigravityKeychainStoreProtocol

    init(
        paths: AntigravityAuthPaths,
        fileManager: FileManager = .default,
        keychainStore: AntigravityKeychainStoreProtocol = NativeAntigravityKeychainStore()
    ) {
        self.paths = paths
        self.fileManager = fileManager
        self.decoder = JSONDecoder()
        self.keychainStore = keychainStore
    }

    convenience init() {
        self.init(paths: .live())
    }

    static func looksLikeGeminiOAuth(_ value: JSONValue) -> Bool {
        guard let object = value.objectValue else { return false }
        if object["auth_mode"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "chatgpt" {
            return false
        }
        if object["tokens"]?.objectValue != nil || object["native_session"]?.boolValue == true {
            return false
        }
        let refresh = trimmed(object["refresh_token"]?.stringValue)
        let access = trimmed(object["access_token"]?.stringValue)
        return !refresh.isEmpty || !access.isEmpty
    }

    /// Copool persists this marker only after the exact native credential's
    /// bearer token has been matched to the local-RPC identity via Google's
    /// read-only userinfo endpoint. It is the sole gate for staging a saved
    /// credential into the native token store.
    static func isNativeVerifiedCredential(_ value: JSONValue) -> Bool {
        guard let object = value.objectValue,
              AntigravityOAuthProfile.resolve(from: value) != nil,
              AntigravityOAuthProfile.hasRefreshVerifiedBinding(value),
              object["antigravity_native_credential"]?.boolValue == true,
              let markerEmail = normalizedEmail(
                object["antigravity_native_credential_email"]?.stringValue
              ),
              let credentialEmail = normalizedEmail(
                object["email"]?.stringValue
                    ?? AntigravityOAuthSnapshotCodec.emailFromIDToken(object["id_token"]?.stringValue)
              ),
              markerEmail == credentialEmail
        else {
            return false
        }
        return true
    }

    /// Reads only the native Keychain record, falling back to the verified
    /// FileTokenStorage location if the record is absent. It never reads or
    /// writes Gemini CLI or CodexBar credential files.
    func readCurrentAuth() throws -> JSONValue {
        guard let first = try readCurrentAuthCandidates(access: .userInitiated).first else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
        }
        return first.authJSON
    }

    /// Returns only the two exact native storage locations so the caller can
    /// bind each candidate to the observed native identity/profile.  This is
    /// not a generic Keychain search and it performs no write.
    func readCurrentAuthCandidates(
        access: AntigravityNativeCredentialAccess
    ) throws -> [AntigravityNativeCredentialCandidate] {
        // Background refreshes do not call this method. A background native
        // switch can reach it only when native's own FileTokenStorage marker
        // bypasses Keychain entirely.
        let snapshot = try nativeCredentialSnapshot(access: access)
        var candidates: [AntigravityNativeCredentialCandidate] = []
        if !snapshot.keychainIsBypassed,
           let secret = snapshot.keychainSecret,
           let token = try? nativeToken(
                fromEnvelopeData: AntigravityNativeKeychainCodec.decode(secret)
           ) {
            candidates.append(.init(authJSON: token, source: .keychain))
        }
        if let fallback = snapshot.fallbackFile,
           let token = try? nativeToken(fromEnvelopeData: fallback),
           !candidates.contains(where: { $0.authJSON == token }) {
            candidates.append(.init(authJSON: token, source: .fallbackFile))
        }
        guard !candidates.isEmpty else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
        }
        return candidates
    }

    /// Compares a stored portable grant with the live native credential only
    /// for an explicit user action. Background callers receive `nil` without
    /// reading Keychain or FileTokenStorage, so they preserve an existing
    /// verified binding rather than starting a credential-polling loop.
    func currentNativeCredentialMatches(
        _ storedAuthJSON: JSONValue,
        access: AntigravityNativeCredentialAccess
    ) throws -> Bool? {
        // A running native RPC may establish current identity and quota, but
        // it never authorizes a polling task to compare bearer credentials.
        // Returning nil asks callers to preserve their existing binding rather
        // than inspecting Keychain or FileTokenStorage in the background.
        guard access == .userInitiated else {
            return nil
        }
        guard let stored = storedAuthJSON.objectValue,
              let storedProfile = AntigravityOAuthProfile.resolve(from: storedAuthJSON),
              !Self.trimmed(stored["access_token"]?.stringValue).isEmpty
        else {
            return false
        }

        let candidates: [AntigravityNativeCredentialCandidate]
        do {
            candidates = try readCurrentAuthCandidates(access: access)
        } catch {
            return nil
        }

        let storedAccess = Self.trimmed(stored["access_token"]?.stringValue)
        let storedRefresh = Self.trimmed(stored["refresh_token"]?.stringValue)
        for candidate in candidates {
            guard AntigravityOAuthProfile.resolve(from: candidate.authJSON) == storedProfile,
                  let candidateObject = candidate.authJSON.objectValue,
                  Self.trimmed(candidateObject["access_token"]?.stringValue) == storedAccess
            else {
                continue
            }
            let candidateRefresh = Self.trimmed(candidateObject["refresh_token"]?.stringValue)
            if storedRefresh.isEmpty || candidateRefresh.isEmpty || candidateRefresh == storedRefresh {
                return true
            }
        }
        return false
    }

    /// Compatibility entry point. Live switching must instead snapshot, stage,
    /// verify via local RPC, then either commit the marker or roll back.
    func writeCurrentAuth(_ authJSON: JSONValue) throws {
        let snapshot = try nativeCredentialSnapshot(access: .userInitiated)
        try stageNativeAuth(authJSON, preserving: snapshot, access: .userInitiated)
    }

    func nativeCredentialSnapshot(
        access: AntigravityNativeCredentialAccess
    ) throws -> AntigravityNativeCredentialSnapshot {
        let keychainIsBypassed = try readKeyringUnavailableMarker() != nil
        guard access == .userInitiated || keychainIsBypassed || keychainStore.supportsQuietBackgroundAccess else {
            // Legacy/injected stores must explicitly support the no-UI boundary.
            throw AntigravityNativeCredentialAccessError.backgroundKeychainRequiresExplicitAction
        }
        return AntigravityNativeCredentialSnapshot(
            keychainSecret: keychainIsBypassed ? nil : try keychainStore.readSecret(access: access),
            fallbackFile: try readFallbackFile(),
            keychainIsBypassed: keychainIsBypassed
        )
    }

    /// Capability only: UI rendering must never probe credentials. Explicit
    /// enable actions perform the permission preflight on a background task.
    func automaticSwitchCapability() -> AntigravityAutomaticSwitchCapability {
        do {
            return try readKeyringUnavailableMarker() != nil || keychainStore.supportsQuietBackgroundAccess
                ? .available : .requiresManualSmartSwitch
        } catch {
            return .requiresManualSmartSwitch
        }
    }

    /// Verify original bytes remain readable/writable before stopping native.
    /// FileTokenStorage skips Keychain entirely; the other path uses a child
    /// with process-wide interaction disabled, never a main-process UI hint.
    func preflightNativeCredentialTransaction(
        _ snapshot: AntigravityNativeCredentialSnapshot,
        access: AntigravityNativeCredentialAccess
    ) throws {
        try verifyNativeCredentialStorageMode(snapshot)
        guard access == .background else { return }
        if !snapshot.keychainIsBypassed {
            guard keychainStore.supportsQuietBackgroundAccess else {
                throw AntigravityNativeCredentialAccessError.backgroundKeychainRequiresExplicitAction
            }
            guard let original = snapshot.keychainSecret else {
                throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
            }
            try keychainStore.preflightWriteAccess(for: original, access: access)
        }
    }

    /// Checks whether a stored credential can be safely staged into the native
    /// token store without reading or writing any live native credential. This
    /// is intentionally callable before the coordinator asks AntiGravity to
    /// quit, so a stale, unverified, or malformed saved record cannot disrupt
    /// an otherwise healthy current native session.
    func validateNativeSwitchCredential(_ authJSON: JSONValue) throws {
        _ = try portableToken(from: authJSON)
    }

    /// Writes the precise Keychain record and its native fallback file. If
    /// either step fails, the supplied in-memory snapshot is restored before
    /// the error returns. Credential values are never logged.
    func stageNativeAuth(
        _ authJSON: JSONValue,
        preserving snapshot: AntigravityNativeCredentialSnapshot,
        access: AntigravityNativeCredentialAccess
    ) throws {
        // Do not trust a marker read earlier in the transaction. Native owns
        // the storage-mode marker; Copool never creates or changes it.
        try verifyNativeCredentialStorageMode(snapshot)
        let token = try portableToken(from: authJSON)
        let envelope = try makeNativeEnvelope(token: token, targetAuthJSON: authJSON)
        let data = try encoder().encode(envelope)

        do {
            // The app has already exited before this method is called. Keep
            // both native backends coherent for the keyring-unavailable path.
            if !snapshot.keychainIsBypassed {
                try keychainStore.writeSecret(
                    AntigravityNativeKeychainCodec.encode(data),
                    access: access
                )
            }
            try writeFallbackFile(data)
        } catch let stageError {
            // Never suppress a failed restore. The coordinator will make one
            // more recovery attempt before it reports the transaction
            // failure, but a caller must never see a clean stage failure when
            // exact original bytes could not be restored.
            do {
                try restoreNativeCredentials(snapshot, access: access)
            } catch {
                throw error
            }
            throw stageError
        }
    }

    /// Restores only the one Keychain record and fallback file captured in the
    /// snapshot. It is used by the surrounding verified-switch transaction.
    func restoreNativeCredentials(
        _ snapshot: AntigravityNativeCredentialSnapshot,
        access: AntigravityNativeCredentialAccess
    ) throws {
        var firstError: Error?
        if !snapshot.keychainIsBypassed {
            do {
                if let keychainSecret = snapshot.keychainSecret {
                    try keychainStore.writeSecret(keychainSecret, access: access)
                } else {
                    try keychainStore.removeSecret(access: access)
                }
            } catch {
                firstError = error
            }
        }

        do {
            if let fallbackFile = snapshot.fallbackFile {
                try writeFallbackFile(fallbackFile)
            } else if fileManager.fileExists(atPath: paths.jetskiTokenPath.path) {
                try fileManager.removeItem(at: paths.jetskiTokenPath)
            }
        } catch where firstError == nil {
            firstError = error
        } catch {
            // Keep the first error, but still try both recovery locations.
        }

        if let firstError { throw firstError }
    }

    func extractAuth(from authJSON: JSONValue) throws -> ExtractedAuth {
        guard let object = authJSON.objectValue else {
            throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
        }
        let email = normalizedIdentity(object["email"]?.stringValue)
            ?? AntigravityOAuthSnapshotCodec.emailFromIDToken(object["id_token"]?.stringValue)
        guard let email else {
            throw AppError.invalidData(L10n.tr("error.antigravity.missing_identity"))
        }

        if object["native_session"]?.boolValue == true {
            return ExtractedAuth(
                accountID: email,
                accessToken: "",
                email: email,
                planType: normalizedIdentity(object["plan_type"]?.stringValue),
                teamName: nil,
                principalID: email,
                provider: .antigravity
            )
        }

        guard Self.looksLikeGeminiOAuth(authJSON) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
        }
        return ExtractedAuth(
            accountID: email,
            accessToken: Self.trimmed(object["access_token"]?.stringValue),
            email: email,
            planType: normalizedIdentity(object["plan_type"]?.stringValue),
            teamName: nil,
            principalID: email,
            provider: .antigravity
        )
    }

    /// The only automatic import source is CodexBar's saved token list. This
    /// method performs no writeback or active-index change.
    func listImportableLocalSessions() throws -> [JSONValue] {
        sessionsFromCodexBar()
    }

    /// Read-only bridge used once to retain accounts from the retired duplicate
    /// AntiGravity store.
    func legacyAccountsForMigration() throws -> [StoredAntigravityAccount] {
        guard fileManager.fileExists(atPath: paths.storePath.path) else { return [] }
        let data = try Data(contentsOf: paths.storePath)
        return try decoder.decode(AntigravityAccountsStore.self, from: data).accounts
    }

    private func portableToken(from authJSON: JSONValue) throws -> JSONValue {
        guard authJSON["native_session"]?.boolValue != true,
              Self.isNativeVerifiedCredential(authJSON),
              Self.looksLikeGeminiOAuth(authJSON),
              let object = authJSON.objectValue,
              !Self.trimmed(object["access_token"]?.stringValue).isEmpty,
              !Self.trimmed(object["refresh_token"]?.stringValue).isEmpty,
              Self.hasUsableAccessToken(object)
        else {
            throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
        }
        _ = try extractAuth(from: authJSON)

        // The native reader accepts its stored envelope and an old raw
        // `oauth2.Token`. Do not place Copool/CodexBar metadata in that token:
        // preserve only fields understood by oauth2.Token and normalize the
        // legacy millisecond expiry into its RFC3339 `expiry` field.
        guard let expiry = Self.nativeExpiry(from: object) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.malformed_oauth"))
        }
        var token: [String: JSONValue] = [
            "access_token": object["access_token"]!,
            "refresh_token": object["refresh_token"]!,
            "token_type": .string(Self.normalizedTokenType(object["token_type"]?.stringValue)),
            "expiry": .string(expiry)
        ]
        if let expiresIn = object["expires_in"]?.doubleValue,
           expiresIn.isFinite,
           expiresIn > 0 {
            token["expires_in"] = .number(expiresIn)
        }
        return .object(token)
    }

    private func nativeToken(fromEnvelopeData data: Data) throws -> JSONValue {
        let value: JSONValue
        do {
            value = try decoder.decode(JSONValue.self, from: data)
        } catch {
            throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
        }
        guard let object = value.objectValue else {
            throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
        }
        let token = object["token"] ?? value
        guard var tokenObject = token.objectValue,
              Self.looksLikeGeminiOAuth(token) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
        }
        // Native `auth_method` lives on the outer envelope. Keep it with the
        // token in memory so no later code guesses its OAuth client.
        if let method = object["auth_method"]?.stringValue,
           !Self.trimmed(method).isEmpty {
            tokenObject["auth_method"] = .string(method)
        }
        return .object(tokenObject)
    }

    private func makeNativeEnvelope(
        token: JSONValue,
        targetAuthJSON: JSONValue
    ) throws -> JSONValue {
        guard let profile = AntigravityOAuthProfile.resolve(from: targetAuthJSON) else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        return .object([
            "token": token,
            "auth_method": .string(profile.nativeAuthMethod)
        ])
    }

    private func readFallbackFile() throws -> Data? {
        guard fileManager.fileExists(atPath: paths.jetskiTokenPath.path) else { return nil }
        do {
            return try Data(contentsOf: paths.jetskiTokenPath)
        } catch {
            throw AppError.io(L10n.tr("error.antigravity.native_session_unavailable"))
        }
    }

    private func readKeyringUnavailableMarker() throws -> Data? {
        guard let markerPath = paths.keyringUnavailableMarkerPath,
              fileManager.fileExists(atPath: markerPath.path)
        else { return nil }
        do {
            return try Data(contentsOf: markerPath)
        } catch {
            throw AppError.io(L10n.tr("error.antigravity.native_session_unavailable"))
        }
    }

    private func verifyNativeCredentialStorageMode(
        _ snapshot: AntigravityNativeCredentialSnapshot
    ) throws {
        let currentKeychainIsBypassed = try readKeyringUnavailableMarker() != nil
        guard currentKeychainIsBypassed == snapshot.keychainIsBypassed else {
            throw AntigravityNativeCredentialAccessError.nativeCredentialStorageModeChanged
        }
    }

    private func writeFallbackFile(_ data: Data) throws {
        do {
            try fileManager.createDirectory(
                at: paths.jetskiTokenPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: paths.jetskiTokenPath, options: .atomic)
            #if canImport(Darwin)
            _ = chmod(paths.jetskiTokenPath.path, S_IRUSR | S_IWUSR)
            #endif
        } catch {
            throw AppError.io(L10n.tr("error.antigravity.native_session_unavailable"))
        }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func sessionsFromCodexBar() -> [JSONValue] {
        guard fileManager.fileExists(atPath: paths.codexBarConfigPath.path),
              let data = try? Data(contentsOf: paths.codexBarConfigPath),
              let root = try? decoder.decode(JSONValue.self, from: data),
              let providers = root["providers"]?.arrayValue
        else {
            return []
        }

        var sessions: [JSONValue] = []
        var seen = Set<String>()
        for provider in providers where provider["id"]?.stringValue == "antigravity" {
            let accounts = provider["tokenAccounts"]?["accounts"]?.arrayValue ?? []
            for account in accounts {
                let rawToken: JSONValue?
                if let object = account["token"]?.objectValue {
                    rawToken = .object(object)
                } else if let text = account["token"]?.stringValue,
                          let data = text.data(using: .utf8) {
                    rawToken = try? decoder.decode(JSONValue.self, from: data)
                } else {
                    rawToken = nil
                }
                guard var token = rawToken?.objectValue else { continue }
                if normalizedIdentity(token["email"]?.stringValue) == nil,
                   let fallbackEmail = normalizedIdentity(
                    account["externalIdentifier"]?.stringValue
                        ?? account["email"]?.stringValue
                        ?? account["label"]?.stringValue
                   ) {
                    token["email"] = .string(fallbackEmail)
                }
                let value = JSONValue.object(token)
                guard Self.looksLikeGeminiOAuth(value),
                      let extracted = try? extractAuth(from: value),
                      let email = extracted.email?.lowercased(),
                      seen.insert(email).inserted
                else { continue }
                sessions.append(value)
            }
        }
        return sessions
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedTokenType(_ value: String?) -> String {
        let value = trimmed(value)
        return value.isEmpty ? "Bearer" : value
    }

    private static func nativeExpiry(from object: [String: JSONValue]) -> String? {
        if let text = object["expiry"]?.stringValue {
            let text = trimmed(text)
            if !text.isEmpty { return text }
        }

        let numericCandidates = [
            object["expiry"]?.doubleValue,
            object["expiry_date"]?.doubleValue,
            object["expiryDate"]?.doubleValue
        ]
        for candidate in numericCandidates.compactMap({ $0 }) where candidate.isFinite && candidate > 0 {
            let seconds = candidate > 10_000_000_000 ? candidate / 1_000 : candidate
            let date = Date(timeIntervalSince1970: seconds)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        return nil
    }

    private static func hasUsableAccessToken(_ object: [String: JSONValue]) -> Bool {
        guard let expirySeconds = nativeExpirySeconds(from: object) else {
            return false
        }
        return expirySeconds > Date().timeIntervalSince1970 + 300
    }

    private static func nativeExpirySeconds(from object: [String: JSONValue]) -> Double? {
        if let value = object["expiry"]?.doubleValue {
            return value > 10_000_000_000 ? value / 1_000 : value
        }
        if let value = object["expiry"]?.stringValue {
            let trimmed = Self.trimmed(value)
            if let numeric = Double(trimmed) {
                return numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: trimmed) {
                return date.timeIntervalSince1970
            }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: trimmed) {
                return date.timeIntervalSince1970
            }
        }
        for key in ["expiry_date", "expiryDate"] {
            if let value = object[key]?.doubleValue {
                return value > 10_000_000_000 ? value / 1_000 : value
            }
        }
        return nil
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        let value = trimmed(value).lowercased()
        return value.contains("@") ? value : nil
    }

    private func normalizedIdentity(_ value: String?) -> String? {
        let value = Self.trimmed(value)
        return value.isEmpty ? nil : value
    }
}
