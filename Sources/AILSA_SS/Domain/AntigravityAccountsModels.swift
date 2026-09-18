import Foundation

struct AntigravityGoogleAccountsFile: Codable, Equatable {
    var active: String
    var old: [String] = []
}

struct AntigravityAccountsStore: Codable, Equatable {
    var version: Int = 1
    var currentEmail: String?
    var currentAccountID: String?
    var accounts: [StoredAntigravityAccount] = []
}

typealias AntigravityStoredAccount = StoredAntigravityAccount

struct AntigravityRuntimePaths: Equatable {
    var geminiDirectory: URL
    var geminiOAuthPath: URL
    var geminiAccountsPath: URL
    var storePath: URL
    var codexBarOAuthMirrorPath: URL
    var codexBarConfigPath: URL

    static func live(fileManager: FileManager = .default) -> AntigravityRuntimePaths {
        let home = fileManager.homeDirectoryForCurrentUser
        let gemini = home.appendingPathComponent(".gemini", isDirectory: true)
        let appSupport = home.appendingPathComponent("Library/Application Support/CodexToolsSwift", isDirectory: true)
        let relay = home.appendingPathComponent(".codexbar/antigravity", isDirectory: true)
        let configHome = home.appendingPathComponent(".config/codexbar", isDirectory: true)
        return AntigravityRuntimePaths(
            geminiDirectory: gemini,
            geminiOAuthPath: gemini.appendingPathComponent("oauth_creds.json", isDirectory: false),
            geminiAccountsPath: gemini.appendingPathComponent("google_accounts.json", isDirectory: false),
            storePath: appSupport.appendingPathComponent("antigravity-accounts.json", isDirectory: false),
            codexBarOAuthMirrorPath: relay.appendingPathComponent("oauth_creds.json", isDirectory: false),
            codexBarConfigPath: configHome.appendingPathComponent("config.json", isDirectory: false)
        )
    }
}

struct StoredAntigravityAccount: Codable, Equatable, Identifiable {
    var id: String
    var email: String
    var label: String
    var oauthJSON: JSONValue
    var addedAt: Int64
    var updatedAt: Int64
}

struct AntigravityAccountSummary: Equatable, Identifiable {
    var id: String
    var email: String
    var label: String
    var isCurrent: Bool
    var addedAt: Int64
    var updatedAt: Int64
}

/// Deprecated compatibility result for the retired parallel coordinator. Live
/// switching is performed by AccountsCoordinator's verified native transaction.
struct AntigravitySwitchResult: Equatable {
    var account: AntigravityAccountSummary
    var restartedAntigravity: Bool

    var email: String { account.email }
}

struct AntigravityOAuthSnapshot: Equatable {
    var email: String
    var accessToken: String
    var refreshToken: String
    var idToken: String?
    var tokenType: String
    var scope: String?
    var expiryDateMilliseconds: Double

    var oauthObject: [String: JSONValue] {
        var object: [String: JSONValue] = [
            "access_token": .string(accessToken),
            "refresh_token": .string(refreshToken),
            "token_type": .string(tokenType),
            "expiry_date": .number(expiryDateMilliseconds)
        ]
        if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            object["email"] = .string(email)
        }
        if let idToken, !idToken.isEmpty {
            object["id_token"] = .string(idToken)
        }
        if let scope, !scope.isEmpty {
            object["scope"] = .string(scope)
        }
        return object
    }
}

enum AntigravityOAuthSnapshotCodec {
    static func parse(_ value: JSONValue) throws -> AntigravityOAuthSnapshot {
        guard let object = value.objectValue else {
            throw AppError.invalidData(L10n.tr("error.antigravity.malformed_oauth"))
        }

        let accessToken = object["access_token"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let refreshToken = object["refresh_token"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !accessToken.isEmpty, !refreshToken.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.antigravity.malformed_oauth"))
        }

        let expiry = object["expiry_date"]?.doubleValue
            ?? object["expiryDate"]?.doubleValue
            ?? Date().timeIntervalSince1970 * 1000
        let email = object["email"]?.stringValue
            ?? emailFromIDToken(object["id_token"]?.stringValue)
            ?? ""

        return AntigravityOAuthSnapshot(
            email: email,
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: object["id_token"]?.stringValue,
            tokenType: object["token_type"]?.stringValue ?? "Bearer",
            scope: object["scope"]?.stringValue,
            expiryDateMilliseconds: expiry
        )
    }

    static func emailFromIDToken(_ idToken: String?) -> String? {
        guard let idToken else { return nil }
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 {
            payload.append("=")
        }

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String
        else {
            return nil
        }

        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
