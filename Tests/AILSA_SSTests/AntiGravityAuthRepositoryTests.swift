import XCTest
@testable import AILSA_SS

final class AntiGravityAuthRepositoryTests: XCTestCase {
    func testNativeKeychainCodecWritesBase64AndReadsLegacyHexAndRawJSON() throws {
        let envelope = Data(
            #"{"auth_method":"consumer","token":{"access_token":"fixture","expiry":"2099-01-01T00:00:00Z","refresh_token":"fixture"}}"#.utf8
        )
        let encoded = AntigravityNativeKeychainCodec.encode(envelope)
        XCTAssertTrue(String(data: encoded, encoding: .utf8)?.hasPrefix("go-keyring-base64:") == true)
        XCTAssertEqual(try AntigravityNativeKeychainCodec.decode(encoded), envelope)

        let legacyHex = envelope.map { String(format: "%02x", $0) }.joined()
        let legacy = Data(("go-keyring-encoded:" + legacyHex).utf8)
        XCTAssertEqual(try AntigravityNativeKeychainCodec.decode(legacy), envelope)
        XCTAssertEqual(try AntigravityNativeKeychainCodec.decode(envelope), envelope)
    }

    func testNativeCredentialSnapshotRestoreKeepsWrappedKeychainBytesExact() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let originalKeychain = AntigravityNativeKeychainCodec.encode(Data(#"{"auth_method":"consumer","token":{}}"#.utf8))
        let originalFallback = Data(#"{"auth_method":"consumer","token":{}}"#.utf8)
        let keychain = MemoryAntigravityKeychainStore()
        try keychain.writeSecret(originalKeychain, access: .userInitiated)
        let fallbackPath = gemini.appendingPathComponent("jetski-standalone-oauth-token")
        try originalFallback.write(to: fallbackPath)

        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )
        let snapshot = try repository.nativeCredentialSnapshot(access: .userInitiated)
        try keychain.writeSecret(Data("changed".utf8), access: .userInitiated)
        try Data("changed".utf8).write(to: fallbackPath)

        try repository.restoreNativeCredentials(snapshot, access: .userInitiated)
        XCTAssertEqual(try keychain.readSecret(), originalKeychain)
        XCTAssertEqual(try Data(contentsOf: fallbackPath), originalFallback)
    }

    func testStageWritesNativeKeychainWrapperButRawFallbackEnvelope() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-stage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let keychain = MemoryAntigravityKeychainStore()
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )
        let expiry = "2099-01-01T00:00:00Z"
        let auth = JSONValue.object([
            "email": .string("fixture@example.com"),
            "access_token": .string("fixture-access"),
            "refresh_token": .string("fixture-refresh"),
            "expiry": .string(expiry),
            "auth_method": .string("consumer"),
            AntigravityOAuthProfile.profileStorageKey: .string("consumer"),
            "client_id": .string(AntigravityOAuthProfile.consumer.publicClientID),
            AntigravityOAuthProfile.refreshVerificationStorageKey: .number(1),
            "antigravity_native_credential": .bool(true),
            "antigravity_native_credential_email": .string("fixture@example.com")
        ])
        try repository.stageNativeAuth(
            auth,
            preserving: try repository.nativeCredentialSnapshot(access: .userInitiated),
            access: .userInitiated
        )

        let keychainData = try XCTUnwrap(try keychain.readSecret())
        XCTAssertTrue(String(data: keychainData, encoding: .utf8)?.hasPrefix("go-keyring-base64:") == true)
        let keychainEnvelope = try JSONDecoder().decode(
            JSONValue.self,
            from: AntigravityNativeKeychainCodec.decode(keychainData)
        )
        XCTAssertEqual(keychainEnvelope["auth_method"]?.stringValue, "consumer")

        let fallbackData = try Data(contentsOf: gemini.appendingPathComponent("jetski-standalone-oauth-token"))
        XCTAssertFalse(String(data: fallbackData, encoding: .utf8)?.hasPrefix("go-keyring-base64:") == true)
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: fallbackData)["auth_method"]?.stringValue, "consumer")
    }

    func testBackgroundTransactionUsesOnlyNativeFileTokenStorageFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-background-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let keychain = CountingAntigravityKeychainStore(secret: Data("test-only-native-secret".utf8))
        let fallbackPath = gemini.appendingPathComponent("jetski-standalone-oauth-token")
        try Data("test-only-native-fallback".utf8).write(to: fallbackPath)
        try FileManager.default.createDirectory(
            at: gemini.appendingPathComponent("cache", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(
            to: gemini
                .appendingPathComponent("cache", isDirectory: true)
                .appendingPathComponent("antigravity-keyring-unavailable")
        )
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )

        let snapshot = try repository.nativeCredentialSnapshot(access: .background)
        try repository.preflightNativeCredentialTransaction(snapshot, access: .background)

        // Normal background refreshes still do not compare bearer credentials.
        XCTAssertNil(
            try repository.currentNativeCredentialMatches(
                .object([:]),
                access: .background
            )
        )
        XCTAssertTrue(snapshot.keychainIsBypassed)
        XCTAssertTrue(keychain.readAccesses.isEmpty)
        XCTAssertTrue(keychain.preflightAccesses.isEmpty)
        XCTAssertTrue(keychain.writeAccesses.isEmpty)
    }

    func testBackgroundKeychainStorageRequiresExplicitActionBeforeAnyKeychainCall() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-background-denied-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let keychain = CountingAntigravityKeychainStore(
            secret: Data("test-only-native-secret".utf8),
            readError: .interactionRequired
        )
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )

        XCTAssertThrowsError(try repository.nativeCredentialSnapshot(access: .background)) { error in
            XCTAssertEqual(
                error as? AntigravityNativeCredentialAccessError,
                .backgroundKeychainRequiresExplicitAction
            )
        }
        XCTAssertTrue(keychain.readAccesses.isEmpty)
        XCTAssertTrue(keychain.preflightAccesses.isEmpty)
        XCTAssertTrue(keychain.writeAccesses.isEmpty)
    }

    func testAutomaticSwitchCapabilityReadsOnlyNativeStorageMarker() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-capability-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let keychain = CountingAntigravityKeychainStore(
            secret: Data("test-only-native-secret".utf8)
        )
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )

        XCTAssertEqual(repository.automaticSwitchCapability(), .requiresManualSmartSwitch)
        XCTAssertTrue(keychain.readAccesses.isEmpty)
        XCTAssertTrue(keychain.preflightAccesses.isEmpty)

        let marker = gemini
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("antigravity-keyring-unavailable")
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: marker)

        XCTAssertEqual(repository.automaticSwitchCapability(), .available)
        XCTAssertTrue(keychain.readAccesses.isEmpty)
        XCTAssertTrue(keychain.preflightAccesses.isEmpty)
        XCTAssertTrue(keychain.writeAccesses.isEmpty)
    }

    func testFileTokenStorageModeChangeStopsBeforeAnyCredentialWrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-mode-change-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let marker = gemini
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("antigravity-keyring-unavailable")
        let fallback = gemini.appendingPathComponent("jetski-standalone-oauth-token")
        let originalFallback = Data("test-only-native-fallback".utf8)
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data().write(to: marker)
        try originalFallback.write(to: fallback)
        let keychain = CountingAntigravityKeychainStore(secret: Data("test-only-native-secret".utf8))
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )

        let snapshot = try repository.nativeCredentialSnapshot(access: .background)
        try FileManager.default.removeItem(at: marker)

        XCTAssertThrowsError(
            try repository.stageNativeAuth(.null, preserving: snapshot, access: .background)
        ) { error in
            XCTAssertEqual(
                error as? AntigravityNativeCredentialAccessError,
                .nativeCredentialStorageModeChanged
            )
        }
        XCTAssertEqual(try Data(contentsOf: fallback), originalFallback)
        XCTAssertTrue(keychain.readAccesses.isEmpty)
        XCTAssertTrue(keychain.writeAccesses.isEmpty)
    }

    func testExplicitNativeCredentialSnapshotReadsOnlyWithUserInitiatedPurpose() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-keyring-explicit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)

        let secret = Data("test-only-native-secret".utf8)
        let keychain = CountingAntigravityKeychainStore(secret: secret)
        let repository = AntigravityAuthRepository(
            paths: makePaths(gemini: gemini, support: support),
            keychainStore: keychain
        )

        let snapshot = try repository.nativeCredentialSnapshot(access: .userInitiated)
        XCTAssertEqual(snapshot.keychainSecret, secret)
        XCTAssertEqual(keychain.readAccesses, [.userInitiated])
    }

    func testNativeCredentialAccessErrorsStopAutomaticRetry() {
        for error in [
            AntigravityNativeCredentialAccessError.backgroundReadDisallowed,
            .backgroundWritePreflightUnavailable,
            .backgroundKeychainRequiresExplicitAction,
            .nativeCredentialStorageModeChanged,
            .userCancelled,
            .accessDenied,
            .interactionRequired,
            .lockedOrInteractionUnavailable,
            .unavailable
        ] {
            XCTAssertTrue(error.stopsAutomaticRetry)
        }
    }

    func testLooksLikeGeminiOAuthRejectsChatGPTAuthShape() {
        let chatgpt = JSONValue.object([
            "auth_mode": .string("chatgpt"),
            "tokens": .object([
                "access_token": .string("codex-access"),
                "refresh_token": .string("codex-refresh")
            ])
        ])
        XCTAssertFalse(AntigravityAuthRepository.looksLikeGeminiOAuth(chatgpt))
    }

    func testImportableSessionsDeduplicateByEmail() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-subswitch-\(UUID().uuidString)", isDirectory: true)
        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        let support = root.appendingPathComponent("support", isDirectory: true)
        let relayDir = root.appendingPathComponent(".codexbar/antigravity", isDirectory: true)
        let configDir = root.appendingPathComponent(".config/codexbar", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: relayDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)

        let first = JSONValue.object([
            "access_token": .string("access-one"),
            "refresh_token": .string("refresh-one"),
            "token_type": .string("Bearer"),
            "email": .string("one@example.com"),
            "expiry_date": .number(1_800_000_000_000),
            "projectId": .string("keep-me")
        ])
        let second = JSONValue.object([
            "access_token": .string("access-two"),
            "refresh_token": .string("refresh-two"),
            "token_type": .string("Bearer"),
            "email": .string("two@example.com"),
            "expiry_date": .number(1_800_000_000_000)
        ])

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(first).write(to: gemini.appendingPathComponent("oauth_creds.json"))
        try encoder.encode(JSONValue.object([
            "active": .string("one@example.com"),
            "old": .array([])
        ])).write(to: gemini.appendingPathComponent("google_accounts.json"))

        let config = JSONValue.object([
            "providers": .array([
                .object([
                    "id": .string("antigravity"),
                    "tokenAccounts": .object([
                        "activeIndex": .number(0),
                        "accounts": .array([
                            .object([
                                "label": .string("one@example.com"),
                                "externalIdentifier": .string("one@example.com"),
                                "token": .string(String(data: try encoder.encode(first), encoding: .utf8) ?? "")
                            ]),
                            .object([
                                "label": .string("two@example.com"),
                                "externalIdentifier": .string("two@example.com"),
                                "token": .string(String(data: try encoder.encode(second), encoding: .utf8) ?? "")
                            ])
                        ])
                    ])
                ])
            ])
        ])
        try encoder.encode(config).write(to: configDir.appendingPathComponent("config.json"))

        let paths = AntigravityAuthPaths(
            geminiDirectory: gemini,
            oauthCredsPath: gemini.appendingPathComponent("oauth_creds.json"),
            googleAccountsPath: gemini.appendingPathComponent("google_accounts.json"),
            jetskiTokenPath: gemini.appendingPathComponent("jetski-standalone-oauth-token"),
            keyringUnavailableMarkerPath: gemini
                .appendingPathComponent("cache", isDirectory: true)
                .appendingPathComponent("antigravity-keyring-unavailable"),
            storePath: support.appendingPathComponent("antigravity-accounts.json"),
            relayCredentialsPath: relayDir.appendingPathComponent("oauth_creds.json"),
            codexBarConfigPath: configDir.appendingPathComponent("config.json")
        )
        let repository = AntigravityAuthRepository(
            paths: paths,
            keychainStore: MemoryAntigravityKeychainStore()
        )

        let sessions = try repository.listImportableLocalSessions()
        XCTAssertEqual(sessions.count, 2)

        let extracted = try repository.extractAuth(from: second)
        XCTAssertEqual(extracted.email, "two@example.com")
        XCTAssertEqual(extracted.provider, .antigravity)

    }

    private func makePaths(gemini: URL, support: URL) -> AntigravityAuthPaths {
        AntigravityAuthPaths(
            geminiDirectory: gemini,
            oauthCredsPath: gemini.appendingPathComponent("oauth_creds.json"),
            googleAccountsPath: gemini.appendingPathComponent("google_accounts.json"),
            jetskiTokenPath: gemini.appendingPathComponent("jetski-standalone-oauth-token"),
            keyringUnavailableMarkerPath: gemini.appendingPathComponent("cache/antigravity-keyring-unavailable"),
            storePath: support.appendingPathComponent("antigravity-accounts.json"),
            relayCredentialsPath: support.appendingPathComponent("relay.json"),
            codexBarConfigPath: support.appendingPathComponent("config.json")
        )
    }
}

private final class CountingAntigravityKeychainStore: AntigravityKeychainStoreProtocol, @unchecked Sendable {
    private var secret: Data?
    private let readError: AntigravityNativeCredentialAccessError?
    private let preflightError: AntigravityNativeCredentialAccessError?
    private(set) var readAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var writeAccesses: [AntigravityNativeCredentialAccess] = []
    private(set) var preflightAccesses: [AntigravityNativeCredentialAccess] = []

    init(
        secret: Data?,
        readError: AntigravityNativeCredentialAccessError? = nil,
        preflightError: AntigravityNativeCredentialAccessError? = nil
    ) {
        self.secret = secret
        self.readError = readError
        self.preflightError = preflightError
    }

    func readSecret(access: AntigravityNativeCredentialAccess) throws -> Data? {
        readAccesses.append(access)
        if let readError { throw readError }
        return secret
    }

    func writeSecret(_ data: Data, access: AntigravityNativeCredentialAccess) throws {
        writeAccesses.append(access)
        secret = data
    }

    func removeSecret(access: AntigravityNativeCredentialAccess) throws {
        writeAccesses.append(access)
        secret = nil
    }

    func preflightWriteAccess(
        for existingSecret: Data?,
        access: AntigravityNativeCredentialAccess
    ) throws {
        preflightAccesses.append(access)
        if let preflightError { throw preflightError }
        guard let existingSecret else {
            throw AntigravityNativeCredentialAccessError.backgroundWritePreflightUnavailable
        }
        XCTAssertEqual(secret, existingSecret)
    }
}
