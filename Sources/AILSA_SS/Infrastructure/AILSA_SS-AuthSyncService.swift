import CryptoKit
import Foundation

final class AILSA_SSAuthSyncService: AILSA_SSAuthSyncServiceProtocol, @unchecked Sendable {
    private static let fallbackExpiresInMs: Int64 = 55 * 60 * 1000

    func syncFromCodexAuth(_ authJSON: JSONValue) throws {
        let tokens = try extractTokens(from: authJSON)
        try syncToDetectedPaths { path in
            try syncToPath(path, tokens: tokens)
        }
    }

    func syncFromAntigravityAuth(_ authJSON: JSONValue) throws {
        let tokens = try extractTokens(from: authJSON)
        try syncToDetectedPaths { path in
            try syncAntigravityToPath(path, tokens: tokens)
        }
    }

    private func syncToDetectedPaths(_ operation: (URL) throws -> Void) throws {
        let paths = detectAuthPaths()
        guard !paths.isEmpty else {
            throw AppError.fileNotFound(L10n.tr("error.opencode.auth_path_not_found"))
        }

        var success = 0
        var errors: [String] = []
        for path in paths {
            do {
                try operation(path)
                success += 1
            } catch {
                errors.append("\(path.path): \(error.localizedDescription)")
            }
        }

        guard success > 0 else {
            throw AppError.io(errors.joined(separator: " | "))
        }
    }

    private func syncToPath(_ path: URL, tokens: OAuthTokens) throws {
        let root = try readOrInitJSONObject(path)
        var openai = root["openai"] as? [String: Any] ?? [:]

        let expires = tokens.expiresAtMs ?? (nowUnixMillis() + Self.fallbackExpiresInMs)
        openai["type"] = (openai["type"] as? String) ?? "oauth"
        openai["access"] = tokens.accessToken
        openai["refresh"] = tokens.refreshToken
        openai["expires"] = expires
        if let accountID = tokens.accountID {
            openai["accountId"] = accountID
        }

        var merged = root
        merged["openai"] = openai

        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
        #if canImport(Darwin)
        _ = chmod(path.path, S_IRUSR | S_IWUSR)
        #endif
    }

    /// OpenCodeX stores OAuth accounts in a provider-scoped account set. Keep
    /// the existing account identity when possible, then mark the matching
    /// account active. This preserves other AntiGravity accounts and avoids
    /// creating a new row on every ASS switch.
    private func syncAntigravityToPath(_ path: URL, tokens: OAuthTokens) throws {
        let root = try readOrInitJSONObject(path)
        let providerKey = "google-antigravity"
        var provider = root[providerKey] as? [String: Any] ?? [:]
        var accounts = provider["accounts"] as? [[String: Any]] ?? []

        let identity = tokens.accountID ?? tokens.email
        let matchingIndex = accounts.firstIndex { account in
            guard let credential = account["credential"] as? [String: Any] else { return false }
            if let accountID = tokens.accountID,
               let storedID = credential["accountId"] as? String,
               storedID == accountID {
                return true
            }
            if let email = tokens.email?.lowercased(),
               let storedEmail = credential["email"] as? String,
               storedEmail.lowercased() == email {
                return true
            }
            return false
        }

        let accountID: String
        if let matchingIndex,
           let existingID = accounts[matchingIndex]["id"] as? String {
            accountID = existingID
        } else {
            accountID = Self.stableAccountID(for: identity ?? tokens.refreshToken)
        }

        var credential: [String: Any] = [
            "access": tokens.accessToken,
            "refresh": tokens.refreshToken,
            "expires": tokens.expiresAtMs ?? (nowUnixMillis() + Self.fallbackExpiresInMs),
            "source": "oauth",
            "projectId": tokens.projectID ?? "aicode-consumers",
        ]
        if let email = tokens.email { credential["email"] = email }
        if let sourceAccountID = tokens.accountID { credential["accountId"] = sourceAccountID }

        var account: [String: Any] = [
            "id": accountID,
            "credential": credential,
            "addedAt": matchingIndex.flatMap { accounts[$0]["addedAt"] } ?? nowUnixMillis(),
        ]
        if let matchingIndex, let alias = accounts[matchingIndex]["alias"] {
            account["alias"] = alias
        } else if let email = tokens.email {
            account["alias"] = email
        }

        if let matchingIndex {
            accounts[matchingIndex] = account
        } else {
            accounts.append(account)
        }
        provider["accounts"] = accounts
        provider["activeAccountId"] = accountID

        var merged = root
        merged[providerKey] = provider
        let parent = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: path, options: .atomic)
        #if canImport(Darwin)
        _ = chmod(path.path, S_IRUSR | S_IWUSR)
        #endif
    }

    private static func stableAccountID(for identity: String) -> String {
        SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
            .prefix(32)
            .description
    }

    private func readOrInitJSONObject(_ path: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return [:]
        }
        let data = try Data(contentsOf: path)
        let obj = try JSONSerialization.jsonObject(with: data)
        return obj as? [String: Any] ?? [:]
    }

    private func detectAuthPaths() -> [URL] {
        if let custom = ProcessInfo.processInfo.environment["OPENCODE_AUTH_PATH"], !custom.isEmpty {
            return [URL(fileURLWithPath: custom)]
        }

        var candidates: [URL] = []
        let env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser

        if let configHome = env["OPENCODE_CONFIG_HOME"], !configHome.isEmpty {
            candidates.append(URL(fileURLWithPath: configHome).appendingPathComponent("auth.json"))
        }
        if let openCodexHome = env["OPENCODEX_HOME"], !openCodexHome.isEmpty {
            candidates.append(URL(fileURLWithPath: openCodexHome).appendingPathComponent("auth.json"))
        }
        if let xdgConfig = env["XDG_CONFIG_HOME"], !xdgConfig.isEmpty {
            candidates.append(URL(fileURLWithPath: xdgConfig).appendingPathComponent("opencode/auth.json"))
        }

        candidates.append(home.appendingPathComponent(".config/opencode/auth.json"))
        candidates.append(home.appendingPathComponent("Library/Application Support/opencode/auth.json"))

        if let xdgData = env["XDG_DATA_HOME"], !xdgData.isEmpty {
            candidates.append(URL(fileURLWithPath: xdgData).appendingPathComponent("opencode/auth.json"))
        }

        candidates.append(home.appendingPathComponent(".local/share/opencode/auth.json"))
        candidates.append(home.appendingPathComponent(".opencode/auth.json"))

        var unique: [URL] = []
        for url in candidates where !unique.contains(url) {
            unique.append(url)
        }

        let existing = unique.filter { FileManager.default.fileExists(atPath: $0.path) }
        return existing.isEmpty ? (unique.first.map { [$0] } ?? []) : existing
    }

    private func extractTokens(from authJSON: JSONValue) throws -> OAuthTokens {
        guard let tokenObject = tokenObject(from: authJSON) else {
            throw AppError.invalidData(L10n.tr("error.opencode.missing_tokens"))
        }

        guard let access = tokenObject["access_token"]?.stringValue else {
            throw AppError.invalidData(L10n.tr("error.auth.missing_access_token"))
        }
        guard let refresh = tokenObject["refresh_token"]?.stringValue else {
            throw AppError.invalidData(L10n.tr("error.opencode.missing_refresh_token"))
        }
        let accountID = tokenObject["account_id"]?.stringValue
            ?? tokenObject["accountId"]?.stringValue
        let idTokenPayload = tokenObject["id_token"]?.stringValue
            .flatMap { try? decodeJWTPayload($0) }
        let email = tokenObject["email"]?.stringValue
            ?? authJSON["email"]?.stringValue
            ?? idTokenPayload?["email"]?.stringValue
        let projectID = tokenObject["project_id"]?.stringValue
            ?? tokenObject["projectId"]?.stringValue

        let expiresAtMs = idTokenPayload
            .flatMap { payload -> Int64? in
                guard let exp = payload["exp"]?.int64Value else { return nil }
                return exp * 1000
            }

        return OAuthTokens(
            accessToken: access,
            refreshToken: refresh,
            accountID: accountID,
            email: email,
            projectID: projectID,
            expiresAtMs: expiresAtMs
        )
    }

    private func tokenObject(from auth: JSONValue) -> [String: JSONValue]? {
        if let tokens = auth["tokens"]?.objectValue {
            return tokens
        }
        if let object = auth.objectValue,
           object["access_token"]?.stringValue != nil {
            return object
        }
        return nil
    }

    private func decodeJWTPayload(_ token: String) throws -> JSONValue {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else {
            throw AppError.invalidData(L10n.tr("error.auth.id_token_invalid_format"))
        }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload) else {
            throw AppError.invalidData(L10n.tr("error.auth.decode_id_token_failed"))
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue.from(any: object)
    }

    private func nowUnixMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}

private struct OAuthTokens {
    var accessToken: String
    var refreshToken: String
    var accountID: String?
    var email: String?
    var projectID: String?
    var expiresAtMs: Int64?
}
