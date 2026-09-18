import Foundation
#if os(macOS)
import Dispatch
#endif
#if os(macOS)
#if canImport(Darwin)
import Darwin
#endif
#endif

struct CommandResult {
    var status: Int32
    var stdout: String
    var stderr: String
}

#if os(macOS)
enum CommandRunner {
    private static let systemSearchPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "/usr/sbin",
        "/sbin",
    ]

    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        process.environment = runtimeEnvironment(overrides: environment)

        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutReader = CommandPipeReader(stdoutPipe.fileHandleForReading)
        let stderrReader = CommandPipeReader(stderrPipe.fileHandleForReading)
        let drainGroup = DispatchGroup()

        do {
            try process.run()
        } catch {
            let command = "\(launchPath) \(arguments.joined(separator: " "))"
            throw AppError.io(L10n.tr("error.shell.run_failed_format", command, error.localizedDescription))
        }

        // Start independent readers before waiting for process termination.
        // A production `ps -ax -o pid=,command=` observation was 271,140
        // bytes, well above a pipe buffer; waiting first can deadlock the
        // child before it exits. No stream contents are logged here.
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()
        stdoutReader.begin(in: drainGroup)
        stderrReader.begin(in: drainGroup)

        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning {
                if Date() >= deadline {
                    process.terminate()

                    let forceKillDeadline = Date().addingTimeInterval(1.2)
                    while process.isRunning, Date() < forceKillDeadline {
                        Thread.sleep(forTimeInterval: 0.05)
                    }

                    if process.isRunning {
                        #if canImport(Darwin)
                        _ = kill(process.processIdentifier, SIGKILL)
                        #endif

                        let settleDeadline = Date().addingTimeInterval(0.8)
                        while process.isRunning, Date() < settleDeadline {
                            Thread.sleep(forTimeInterval: 0.05)
                        }
                    }

                    // A child or grandchild can retain a pipe after the timed
                    // out Process exits. Closing our readers keeps timeout
                    // behavior bounded without exposing captured output.
                    stdoutReader.close()
                    stderrReader.close()
                    _ = drainGroup.wait(timeout: .now() + .milliseconds(250))

                    let command = "\(launchPath) \(arguments.joined(separator: " "))"
                    throw AppError.io(
                        L10n.tr("error.shell.timeout_format", String(Int(timeout)), command)
                    )
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        } else {
            process.waitUntilExit()
        }

        drainGroup.wait()
        let stdoutData = stdoutReader.collectedData()
        let stderrData = stderrReader.collectedData()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        let result = CommandResult(status: process.terminationStatus, stdout: stdout, stderr: stderr)
        return result
    }

    static func runChecked(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        errorPrefix: String
    ) throws -> CommandResult {
        let result = try run(
            launchPath,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            timeout: timeout
        )
        guard result.status == 0 else {
            let details = result.stderr.isEmpty ? result.stdout : result.stderr
            throw AppError.io("\(errorPrefix): \(details.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return result
    }

    static func resolveExecutable(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }

        for base in executableSearchPaths() {
            let candidate = (base as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        guard let result = try? run("/usr/bin/env", arguments: ["which", name]), result.status == 0 else {
            return nil
        }
        let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    private static func runtimeEnvironment(overrides: [String: String]?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        environment["HOME"] = home

        let existing = environment["PATH"] ?? ""
        let existingParts = existing
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }

        var merged: [String] = []
        var seen = Set<String>()
        for part in existingParts {
            if seen.insert(part).inserted {
                merged.append(part)
            }
        }

        for part in systemSearchPaths {
            if seen.insert(part).inserted {
                merged.append(part)
            }
        }

        let userToolPaths = [
            "\(home)/.cargo/bin",
            "\(home)/.local/bin",
        ]
        for part in userToolPaths where FileManager.default.fileExists(atPath: part) {
            if seen.insert(part).inserted {
                merged.append(part)
            }
        }

        environment["PATH"] = merged.joined(separator: ":")

        if let overrides {
            for (key, value) in overrides {
                environment[key] = value
            }
        }
        return environment
    }

    private static func executableSearchPaths() -> [String] {
        let env = runtimeEnvironment(overrides: nil)
        return (env["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { !$0.isEmpty }
    }
}

/// Blocks on one pipe only on a background queue, so stdout and stderr are
/// drained independently while the main thread observes process timeout.
private final class CommandPipeReader: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private var data = Data()

    init(_ handle: FileHandle) {
        self.handle = handle
    }

    func begin(in group: DispatchGroup) {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { group.leave() }
            let captured = handle.readDataToEndOfFile()
            lock.lock()
            data = captured
            lock.unlock()
        }
    }

    func close() {
        try? handle.close()
    }

    func collectedData() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
#else
enum CommandRunner {
    @discardableResult
    static func run(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil
    ) throws -> CommandResult {
        _ = launchPath
        _ = arguments
        _ = environment
        _ = currentDirectory
        _ = timeout
        throw AppError.io(PlatformCapabilities.unsupportedOperationMessage)
    }

    static func runChecked(
        _ launchPath: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval? = nil,
        errorPrefix: String
    ) throws -> CommandResult {
        _ = launchPath
        _ = arguments
        _ = environment
        _ = currentDirectory
        _ = timeout
        throw AppError.io("\(errorPrefix): \(PlatformCapabilities.unsupportedOperationMessage)")
    }

    static func resolveExecutable(_ name: String) -> String? {
        _ = name
        return nil
    }
}
#endif
