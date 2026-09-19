import Foundation

/// Owns the configuration written by AILSA SubSwitch itself.
///
/// Provider-native credentials (for example `~/.codex/auth.json` and
/// `~/.gemini/oauth_creds.json`) deliberately stay outside this boundary. The
/// backup contains sensitive account data by design, so the About screen warns
/// before writing it to disk.
struct LocalConfigurationManager {
    struct Backup: Codable, Equatable {
        let format: String
        let version: Int
        let exportedAt: Date
        let files: [String: JSONValue]

        static let currentFormat = "AILSA SubSwitch local configuration"
        static let currentVersion = 1
    }

    private let appSupportDirectory: URL
    private let fileManager: FileManager

    init(appSupportDirectory: URL, fileManager: FileManager = .default) {
        self.appSupportDirectory = appSupportDirectory
        self.fileManager = fileManager
    }

    static func live(fileManager: FileManager = .default) -> LocalConfigurationManager {
        let home = fileManager.homeDirectoryForCurrentUser
        return LocalConfigurationManager(
            appSupportDirectory: home.appendingPathComponent(
                "Library/Application Support/CodexToolsSwift",
                isDirectory: true
            ),
            fileManager: fileManager
        )
    }

    /// Files that are both owned by AILSA SubSwitch and safe to represent as
    /// structured JSON. Troubleshooting logs and historical recovery backups
    /// are intentionally excluded from exports because they are not needed to
    /// restore current app configuration and may contain stale sensitive data.
    private var configurationFiles: [String] {
        [
            "accounts.json",
            "settings.json",
            "antigravity-accounts.json",
            "cursor-profiles.json",
            "cursor-switch-recovery.json",
            "quota-history/antigravity-v1.json"
        ]
    }

    func backupData(exportedAt: Date = Date()) throws -> Data {
        var files: [String: JSONValue] = [:]
        for relativePath in configurationFiles {
            let url = appSupportDirectory.appendingPathComponent(relativePath, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw AppError.io("Unable to read (relativePath): (error.localizedDescription)")
            }

            do {
                let object = try JSONSerialization.jsonObject(with: data)
                files[relativePath] = try JSONValue.from(any: object)
            } catch {
                throw AppError.invalidData("Unable to export (relativePath): (error.localizedDescription)")
            }
        }

        let backup = Backup(
            format: Backup.currentFormat,
            version: Backup.currentVersion,
            exportedAt: exportedAt,
            files: files
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(backup)
        } catch {
            throw AppError.invalidData("Unable to serialize the configuration backup: (error.localizedDescription)")
        }
    }

    func writeBackup(to destination: URL, exportedAt: Date = Date()) throws {
        let data = try backupData(exportedAt: exportedAt)
        do {
            try data.write(to: destination, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            throw AppError.io("Unable to save the configuration backup: (error.localizedDescription)")
        }
    }

    func deleteLocalConfiguration() throws {
        let directory = appSupportDirectory.standardizedFileURL
        guard directory.lastPathComponent == "CodexToolsSwift",
              directory.pathComponents.count > 2 else {
            throw AppError.io("Refusing to delete an unexpected configuration directory.")
        }
        guard fileManager.fileExists(atPath: directory.path) else { return }
        do {
            try fileManager.removeItem(at: directory)
        } catch {
            throw AppError.io("Unable to delete local configuration: (error.localizedDescription)")
        }
    }
}
