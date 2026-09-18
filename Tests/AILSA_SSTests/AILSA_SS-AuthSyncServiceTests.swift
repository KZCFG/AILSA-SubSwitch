import Foundation
import XCTest
@testable import AILSA_SS

#if canImport(Darwin)
import Darwin
#endif

final class AILSA_SSAuthSyncServiceTests: XCTestCase {
    func testAntiGravitySyncUpdatesNestedProviderAndActiveAccount() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ailsa-ss-opencode-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("auth.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let previous = ProcessInfo.processInfo.environment["OPENCODE_AUTH_PATH"]
        setenv("OPENCODE_AUTH_PATH", path.path, 1)
        defer {
            if let previous {
                setenv("OPENCODE_AUTH_PATH", previous, 1)
            } else {
                unsetenv("OPENCODE_AUTH_PATH")
            }
        }

        let auth = JSONValue.object([
            "email": .string("selected@example.com"),
            "tokens": .object([
                "access_token": .string("access-secret"),
                "refresh_token": .string("refresh-secret"),
                "account_id": .string("selected-account"),
                "project_id": .string("aicode-consumers")
            ])
        ])

        try AILSA_SSAuthSyncService().syncFromAntigravityAuth(auth)

        let data = try Data(contentsOf: path)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let provider = try XCTUnwrap(object["google-antigravity"] as? [String: Any])
        let active = try XCTUnwrap(provider["activeAccountId"] as? String)
        let accounts = try XCTUnwrap(provider["accounts"] as? [[String: Any]])
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0]["id"] as? String, active)
        let credential = try XCTUnwrap(accounts[0]["credential"] as? [String: Any])
        XCTAssertEqual(credential["email"] as? String, "selected@example.com")
        XCTAssertEqual(credential["projectId"] as? String, "aicode-consumers")
        XCTAssertEqual(credential["source"] as? String, "oauth")
    }
}
