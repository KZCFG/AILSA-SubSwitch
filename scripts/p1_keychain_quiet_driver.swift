import Foundation

/// Focused P1 regression driver. It uses only synthetic OAuth-looking bytes,
/// never touches the user's Keychain, and emits no credential material.
@main
struct P1KeychainQuietDriver {
    static func main() {
        do {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("ailsa-p1-keychain-quiet-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
            let support = root.appendingPathComponent("support", isDirectory: true)
            try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

            let keychain = CountingKeychainStore(secret: Data("p1-synthetic-secret".utf8))
            try Data("p1-synthetic-fallback".utf8).write(
                to: gemini.appendingPathComponent("jetski-standalone-oauth-token")
            )
            let keyringUnavailableMarker = gemini.appendingPathComponent("keyring-unavailable")
            try Data().write(to: keyringUnavailableMarker)
            let repository = AntigravityAuthRepository(
                paths: AntigravityAuthPaths(
                    geminiDirectory: gemini,
                    oauthCredsPath: gemini.appendingPathComponent("oauth_creds.json"),
                    googleAccountsPath: gemini.appendingPathComponent("google_accounts.json"),
                    jetskiTokenPath: gemini.appendingPathComponent("jetski-standalone-oauth-token"),
                    keyringUnavailableMarkerPath: gemini.appendingPathComponent("keyring-unavailable"),
                    storePath: support.appendingPathComponent("antigravity-accounts.json"),
                    relayCredentialsPath: support.appendingPathComponent("relay.json"),
                    codexBarConfigPath: support.appendingPathComponent("config.json")
                ),
                keychainStore: keychain
            )

            // Ordinary recurring refreshes still never inspect a native bearer
            // credential. The dedicated auto-switch transaction below uses
            // native's FileTokenStorage marker and must not touch Keychain.
            for _ in 0..<3 {
                guard try repository.currentNativeCredentialMatches(.object([:]), access: .background) == nil else {
                    throw DriverFailure.backgroundComparisonDidNotDefer
                }
            }
            guard keychain.readAccesses.isEmpty else {
                throw DriverFailure.backgroundReadReachedKeychain
            }

            let backgroundSnapshot = try repository.nativeCredentialSnapshot(access: .background)
            try repository.preflightNativeCredentialTransaction(backgroundSnapshot, access: .background)
            guard backgroundSnapshot.keychainIsBypassed,
                  keychain.readAccesses.isEmpty,
                  keychain.preflightAccesses.isEmpty,
                  keychain.writeAccesses.isEmpty
            else {
                throw DriverFailure.silentTransactionPurposeWasNotPreserved
            }

            try FileManager.default.removeItem(at: keyringUnavailableMarker)
            _ = try repository.nativeCredentialSnapshot(access: .userInitiated)
            guard keychain.readAccesses == [.userInitiated] else {
                throw DriverFailure.explicitReadWasNotPerformed
            }
            // Unreviewed stores retain the old fail-before-read boundary.
            do {
                _ = try repository.nativeCredentialSnapshot(access: .background)
                throw DriverFailure.backgroundReadReachedKeychain
            } catch AntigravityNativeCredentialAccessError.backgroundKeychainRequiresExplicitAction {}
            keychain.supportsQuietBackgroundAccess = true
            guard repository.automaticSwitchCapability() == .available else {
                throw DriverFailure.silentTransactionPurposeWasNotPreserved
            }
            let quietSnapshot = try repository.nativeCredentialSnapshot(access: .background)
            try repository.preflightNativeCredentialTransaction(quietSnapshot, access: .background)
            guard keychain.readAccesses == [.userInitiated, .background],
                  keychain.preflightAccesses == [.background], keychain.writeAccesses.isEmpty else {
                throw DriverFailure.silentTransactionPurposeWasNotPreserved
            }
            keychain.denyPreflight = true
            do {
                try repository.preflightNativeCredentialTransaction(quietSnapshot, access: .background)
                throw DriverFailure.silentTransactionPurposeWasNotPreserved
            } catch AntigravityNativeCredentialAccessError.accessDenied {}
            guard keychain.writeAccesses.isEmpty else { throw DriverFailure.silentTransactionPurposeWasNotPreserved }
            guard AntigravityNativeCredentialAccessError.userCancelled.stopsAutomaticRetry,
                  AntigravityNativeCredentialAccessError.accessDenied.stopsAutomaticRetry,
                  AntigravityNativeCredentialAccessError.interactionRequired.stopsAutomaticRetry
            else {
                throw DriverFailure.terminalErrorWouldRetry
            }
            print("p1-keychain-quiet: PASS 3 credential-free polls, fallback bypass, unreviewed-store refusal, quiet snapshot/preflight, denied preflight without writes")
        } catch {
            // Error descriptions may accidentally include a test path. Keep
            // this QA surface deliberately redacted.
            FileHandle.standardError.write(Data("p1-keychain-quiet: fail\n".utf8))
            exit(1)
        }
    }

    private enum DriverFailure: Error {
        case backgroundComparisonDidNotDefer
        case backgroundReadReachedKeychain
        case silentTransactionPurposeWasNotPreserved
        case explicitReadWasNotPerformed
        case terminalErrorWouldRetry
    }
}

private final class CountingKeychainStore: AntigravityKeychainStoreProtocol, @unchecked Sendable {
    var supportsQuietBackgroundAccess = false
    var denyPreflight = false
    private let secret: Data
    private(set) var readAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var preflightAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var writeAccesses: [AntigravityNativeCredentialAccess] = []

    init(secret: Data) {
        self.secret = secret
    }

    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data? {
        readAccesses.append(access)
        return secret
    }

    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws {
        writeAccesses.append(access)
    }

    func removeSecret(access: AntigravityNativeCredentialAccess) throws {
        writeAccesses.append(access)
    }

    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        preflightAccesses.append(access)
        if denyPreflight { throw AntigravityNativeCredentialAccessError.accessDenied }
        guard existingSecret == secret else {
            throw AntigravityNativeCredentialAccessError.unavailable
        }
    }
}
