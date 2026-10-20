import Foundation
import Darwin

/// One process may mutate the managed pool at a time, including across app copies.
final class OpenCodexControlLease: @unchecked Sendable {
    private let descriptor: Int32
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        descriptor = open(directory.appendingPathComponent("opencodex-controller.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw AppError.io(L10n.tr("settings.pool.control_busy")) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw AppError.io(L10n.tr("settings.pool.control_busy"))
        }
        _ = fchmod(descriptor, 0o600)
    }
    deinit { _ = flock(descriptor, LOCK_UN); close(descriptor) }
}

struct OpenCodexLegacySyncJob: Codable, Equatable, Sendable {
    var label: String
    var plistPath: String
    var scriptPath: String
    var loaded: Bool
}

/// Recognize only the specific legacy synchronizers; never stop arbitrary Python jobs.
struct OpenCodexControlOwnership: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var command: @Sendable ([String]) throws -> (Int32, String) = { args in
        let task = Process(), output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        task.arguments = args; task.standardOutput = output; task.standardError = FileHandle.nullDevice
        try task.run()
        // launchctl output is bounded for one known job. No environment values are surfaced.
        let data = output.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
        return (task.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
    func jobs() -> [OpenCodexLegacySyncJob] {
        let folder = home.appendingPathComponent("Library/LaunchAgents")
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "plist" }.compactMap { file in
            guard let data = try? Data(contentsOf: file), data.count < 256_000,
                  let object = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let label = object["Label"] as? String,
                  label.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]*$", options: .regularExpression) != nil,
                  file.lastPathComponent == label + ".plist",
                  let args = object["ProgramArguments"] as? [String],
                  let path = args.first(where: { ["codexbar-sync-creds.py", "subswitch-opencodex-sync.py"].contains(URL(fileURLWithPath: $0).lastPathComponent) }),
                  URL(fileURLWithPath: path).standardizedFileURL.deletingLastPathComponent() == home.appendingPathComponent(".local/bin").standardizedFileURL,
                  let script = try? String(contentsOfFile: path, encoding: .utf8),
                  script.contains("SUBSWITCH_PATH"), script.contains("OPENCODEX_AUTH_PATH"), script.contains("def sync_cycle") else { return nil }
            let state = try? command(["print", "gui/\(getuid())/" + label])
            let loaded = state?.0 == 0
            if loaded && state?.1.contains(path) != true { return nil }
            return OpenCodexLegacySyncJob(label: label, plistPath: file.path, scriptPath: path, loaded: loaded)
        }
    }
    func hasConflictingWriter() -> Bool {
        if jobs().contains(where: \.loaded) { return true }
        let process = Process(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-wwaxo", "command="]
        process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return true }
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let commands = (String(data: data, encoding: .utf8) ?? "").split(separator: "\n")
        let paths = ["codexbar-sync-creds.py", "subswitch-opencodex-sync.py"].map { home.appendingPathComponent(".local/bin/" + $0).path }
        return commands.contains { command in paths.contains { path in
            let escaped = NSRegularExpression.escapedPattern(for: path)
            let pattern = "(?i)^\\s*\\S*python(?:3(?:\\.[0-9]+)?)?\\s+(?:-\\S+\\s+)*(?:\"" + escaped + "\"|'" + escaped + "'|" + escaped + ")(?:\\s|$)"
            return command.range(of: pattern, options: .regularExpression) != nil
        } }
    }
    func requireNoLegacyWriter() throws {
        guard !hasConflictingWriter() else { throw AppError.invalidData(L10n.tr("settings.pool.control_conflict")) }
    }
    func takeOver(backupDirectory: URL) throws -> [String] {
        let existing = jobs()
        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        for job in existing {
            let folder = backupDirectory.appendingPathComponent(job.label)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for source in [job.plistPath, job.scriptPath] {
                let target = folder.appendingPathComponent(URL(fileURLWithPath: source).lastPathComponent)
                if !FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.copyItem(atPath: source, toPath: target.path)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                }
            }
            let domain = "gui/\(getuid())/" + job.label
            guard try command(["disable", domain]).0 == 0 else { throw AppError.io(L10n.tr("settings.pool.control_takeover_failed")) }
            if job.loaded {
                guard try command(["bootout", domain]).0 == 0 else { throw AppError.io(L10n.tr("settings.pool.control_takeover_failed")) }
            }
        }
        try requireNoLegacyWriter()
        return existing.map(\.label)
    }
}
