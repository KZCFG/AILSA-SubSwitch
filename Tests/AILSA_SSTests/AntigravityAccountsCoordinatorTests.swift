import XCTest
@testable import AILSA_SS

final class AntigravityAccountsCoordinatorTests: XCTestCase {
    func testDeprecatedCoordinatorRejectsMutationWithoutRewritingNativeOrCLIFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-subswitch-ag-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        let first = ["refresh_token": "fixture-one", "access_token": "fixture-access"]
        try writeJSON(first, to: gemini.appendingPathComponent("oauth_creds.json"))
        try writeJSON(["active": "one@example.com", "old": []], to: gemini.appendingPathComponent("google_accounts.json"))

        let paths = AntigravityAuthPaths(
            geminiDirectory: gemini,
            oauthCredsPath: gemini.appendingPathComponent("oauth_creds.json"),
            googleAccountsPath: gemini.appendingPathComponent("google_accounts.json"),
            jetskiTokenPath: gemini.appendingPathComponent("jetski-standalone-oauth-token"),
            storePath: root.appendingPathComponent("antigravity-accounts.json"),
            relayCredentialsPath: root.appendingPathComponent("codexbar-oauth.json"),
            codexBarConfigPath: root.appendingPathComponent("codexbar-config.json")
        )
        let repository = AntigravityAuthRepository(
            paths: paths,
            keychainStore: MemoryAntigravityKeychainStore()
        )
        let editor = RecordingAntigravityEditorAppService()
        let coordinator = AntigravityAccountsCoordinator(
            repository: repository,
            editorAppService: editor
        )
        let originalOAuth = try Data(contentsOf: paths.oauthCredsPath)
        let originalAccounts = try Data(contentsOf: paths.googleAccountsPath)

        XCTAssertThrowsError(try coordinator.importCurrentSession())
        XCTAssertThrowsError(try coordinator.importOAuthFile(from: root.appendingPathComponent("second.json")))
        XCTAssertThrowsError(try coordinator.switchAccount(id: "opaque-id"))

        XCTAssertEqual(try Data(contentsOf: paths.oauthCredsPath), originalOAuth)
        XCTAssertEqual(try Data(contentsOf: paths.googleAccountsPath), originalAccounts)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.storePath.path))
        XCTAssertTrue(editor.restarted.isEmpty)
    }

    func testDeprecatedCodexBarImportIsReadOnlyAndRequiresPrimaryStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-subswitch-codexbar-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let gemini = root.appendingPathComponent(".gemini", isDirectory: true)
        try FileManager.default.createDirectory(at: gemini, withIntermediateDirectories: true)
        try writeJSON(["refresh_token": "fixture-live"], to: gemini.appendingPathComponent("oauth_creds.json"))
        try writeJSON(["active": "live@example.com", "old": []], to: gemini.appendingPathComponent("google_accounts.json"))

        let config = [
            "providers": [
                [
                    "id": "antigravity",
                    "tokenAccounts": [
                        "activeIndex": 1,
                        "accounts": [
                            [
                                "id": "a1",
                                "label": "one@example.com",
                                "externalIdentifier": "one@example.com",
                                "token": "fixture-one"
                            ],
                            [
                                "id": "a2",
                                "label": "two@example.com",
                                "externalIdentifier": "two@example.com",
                                "token": "fixture-two"
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let paths = AntigravityAuthPaths(
            geminiDirectory: gemini,
            oauthCredsPath: gemini.appendingPathComponent("oauth_creds.json"),
            googleAccountsPath: gemini.appendingPathComponent("google_accounts.json"),
            jetskiTokenPath: gemini.appendingPathComponent("jetski-standalone-oauth-token"),
            storePath: root.appendingPathComponent("antigravity-accounts.json"),
            relayCredentialsPath: root.appendingPathComponent("codexbar-oauth.json"),
            codexBarConfigPath: root.appendingPathComponent("codexbar-config.json")
        )
        try writeJSON(config, to: paths.codexBarConfigPath)

        let originalConfig = try Data(contentsOf: paths.codexBarConfigPath)
        let coordinator = AntigravityAccountsCoordinator(
            repository: AntigravityAuthRepository(paths: paths, keychainStore: MemoryAntigravityKeychainStore()),
            editorAppService: RecordingAntigravityEditorAppService()
        )
        XCTAssertThrowsError(try coordinator.importFromCodexBar())
        XCTAssertEqual(try Data(contentsOf: paths.codexBarConfigPath), originalConfig)
    }

    func testNormalizedPlanLabelsUseAILSANames() {
        XCTAssertEqual(AccountPlanLabel.normalized(from: "pro"), "PRO 20X")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "prolite"), "PRO 5X")
        XCTAssertEqual(AccountPlanLabel.normalized(from: "pro_5x"), "PRO 5X")
    }

    private func writeJSON(_ value: Any, to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted])
        try data.write(to: url)
    }
}

private final class RecordingAntigravityEditorAppService: EditorAppServiceProtocol, @unchecked Sendable {
    var restarted: [EditorAppID] = []

    func listInstalledApps() -> [InstalledEditorApp] {
        [InstalledEditorApp(id: .antigravity, label: "Antigravity")]
    }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        restarted = targets
        return (targets, nil)
    }
}
