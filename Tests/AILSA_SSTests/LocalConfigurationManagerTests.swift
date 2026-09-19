import Foundation
import XCTest
@testable import AILSA_SS

final class LocalConfigurationManagerTests: XCTestCase {
    func testBackupContainsCurrentConfigurationAsStructuredJSON() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"accounts":[{"id":"account-1"}]}"#.data(using: .utf8)!.write(
            to: directory.appendingPathComponent("accounts.json")
        )
        try #"{"locale":"zh-Hans"}"#.data(using: .utf8)!.write(
            to: directory.appendingPathComponent("settings.json")
        )

        let manager = LocalConfigurationManager(appSupportDirectory: directory)
        let data = try manager.backupData(exportedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let backup = try JSONDecoder.iso8601.decode(LocalConfigurationManager.Backup.self, from: data)

        XCTAssertEqual(backup.format, LocalConfigurationManager.Backup.currentFormat)
        XCTAssertEqual(backup.version, LocalConfigurationManager.Backup.currentVersion)
        XCTAssertEqual(backup.files["accounts.json"]?["accounts"]?.arrayValue?.count, 1)
        XCTAssertEqual(backup.files["settings.json"]?["locale"]?.stringValue, "zh-Hans")
    }

    func testBackupOmitsTroubleshootingAndHistoricalDirectories() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("backups"), withIntermediateDirectories: true)
        try Data("not exported".utf8).write(to: directory.appendingPathComponent("auth-flow-debug.log"))
        try Data("{}".utf8).write(to: directory.appendingPathComponent("backups/old.json"))

        let manager = LocalConfigurationManager(appSupportDirectory: directory)
        let backup = try JSONDecoder.iso8601.decode(
            LocalConfigurationManager.Backup.self,
            from: manager.backupData()
        )

        XCTAssertTrue(backup.files.isEmpty)
    }

    func testDeleteRemovesOnlyTheAILSAConfigurationDirectory() throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let directory = parent.appendingPathComponent("CodexToolsSwift", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("settings.json"))
        let external = parent.appendingPathComponent("external-auth.json")
        try Data("{}".utf8).write(to: external)

        try LocalConfigurationManager(appSupportDirectory: directory).deleteLocalConfiguration()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AILSA-SubSwitch-configuration-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
