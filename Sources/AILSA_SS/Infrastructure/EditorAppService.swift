import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(AppKit)
import AppKit
#endif

final class EditorAppService: EditorAppServiceProtocol, @unchecked Sendable {
    private struct EditorSpec {
        let id: EditorAppID
        let label: String
        let bundleNames: [String]
        let processNames: [String]
    }

    private let specs: [EditorSpec] = [
        EditorSpec(
            id: .vscode,
            label: "VS Code",
            bundleNames: ["Visual Studio Code.app", "Code.app"],
            processNames: ["Code", "Visual Studio Code"]
        ),
        EditorSpec(
            id: .vscodeInsiders,
            label: "Visual Studio Code - Insiders",
            bundleNames: ["Visual Studio Code - Insiders.app", "Code - Insiders.app"],
            processNames: ["Code - Insiders", "Visual Studio Code - Insiders"]
        ),
        EditorSpec(
            id: .cursor,
            label: "Cursor",
            bundleNames: ["Cursor.app"],
            processNames: ["Cursor"]
        ),
        EditorSpec(
            id: .antigravity,
            label: "Antigravity",
            bundleNames: ["Antigravity.app", "Antigravity IDE.app"],
            processNames: ["Antigravity", "Antigravity IDE"]
        ),
        EditorSpec(
            id: .kiro,
            label: "Kiro",
            bundleNames: ["Kiro.app"],
            processNames: ["Kiro"]
        ),
        EditorSpec(
            id: .trae,
            label: "Trae",
            bundleNames: ["Trae.app"],
            processNames: ["Trae"]
        ),
        EditorSpec(
            id: .qoder,
            label: "Qoder",
            bundleNames: ["Qoder.app"],
            processNames: ["Qoder"]
        )
    ]

    func listInstalledApps() -> [InstalledEditorApp] {
        specs.compactMap { spec in
            guard detectBundlePath(for: spec) != nil else { return nil }
            return InstalledEditorApp(id: spec.id, label: spec.label)
        }
    }

    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?) {
        guard !targets.isEmpty else {
            return ([], L10n.tr("error.editor.no_restart_target_selected"))
        }

        var restarted: [EditorAppID] = []
        var errors: [String] = []

        for target in targets {
            guard let spec = specs.first(where: { $0.id == target }) else {
                errors.append(L10n.tr("error.editor.unknown_editor_id_format", target.rawValue))
                continue
            }

            do {
                let path = try resolveBundlePath(for: spec)
                forceKillProcesses(spec.processNames)
                Thread.sleep(forTimeInterval: 0.22)
                _ = try CommandRunner.runChecked(
                    "/usr/bin/open",
                    arguments: ["-na", path.path],
                    errorPrefix: L10n.tr("error.editor.restart_app_failed")
                )
                restarted.append(spec.id)
            } catch {
                errors.append("\(spec.label): \(error.localizedDescription)")
            }
        }

        return (restarted, errors.isEmpty ? nil : errors.joined(separator: " | "))
    }

    func launchApp(_ target: EditorAppID) -> (launched: Bool, error: String?) {
        guard let spec = specs.first(where: { $0.id == target }) else {
            return (false, L10n.tr("error.editor.unknown_editor_id_format", target.rawValue))
        }
        do {
            let path = try resolveBundlePath(for: spec)
            // Unlike restartSelectedApps this intentionally does not pkill or
            // pass -n: a verified AntiGravity session must not lose unsaved work.
            _ = try CommandRunner.runChecked(
                "/usr/bin/open",
                arguments: ["-a", path.path],
                errorPrefix: L10n.tr("error.editor.restart_app_failed")
            )
            return (true, nil)
        } catch {
            return (false, "\(spec.label): \(error.localizedDescription)")
        }
    }

    func isAppRunning(_ target: EditorAppID) -> Bool {
        guard let spec = specs.first(where: { $0.id == target }) else { return false }
        #if canImport(AppKit)
        if !runningBundleApplications(for: spec).isEmpty {
            return true
        }
        #endif
        return spec.processNames.contains { processName in
            let result = try? CommandRunner.run(
                "/usr/bin/pgrep",
                arguments: ["-x", processName],
                timeout: 1
            )
            return result?.status == 0
        }
    }

    func quitAppGracefully(
        _ target: EditorAppID,
        timeoutSeconds: TimeInterval
    ) -> (didQuit: Bool, error: String?) {
        guard let spec = specs.first(where: { $0.id == target }) else {
            return (false, L10n.tr("error.editor.unknown_editor_id_format", target.rawValue))
        }

        #if canImport(AppKit)
        let runningApplications = runningBundleApplications(for: spec)
        let observedProcessIDs = runningApplications.map(\.processIdentifier)
        if runningApplications.isEmpty && !isAppRunning(target) {
            return (true, nil)
        }
        #else
        guard isAppRunning(target) else { return (true, nil) }
        #endif

        do {
            #if canImport(AppKit)
            if !runningApplications.isEmpty {
                for application in runningApplications {
                    // `terminate()` is the app's normal quit request. Do not
                    // force-kill it: completion is determined by this PID exiting.
                    _ = application.terminate()
                }
            } else {
                _ = try CommandRunner.runChecked(
                    "/usr/bin/osascript",
                    arguments: ["-e", "tell application \"\(spec.label)\" to quit"],
                    errorPrefix: L10n.tr("error.antigravity.native_session_unavailable")
                )
            }
            #else
            _ = try CommandRunner.runChecked(
                "/usr/bin/osascript",
                arguments: ["-e", "tell application \"\(spec.label)\" to quit"],
                errorPrefix: L10n.tr("error.antigravity.native_session_unavailable")
            )
            #endif
        } catch {
            return (false, "\(spec.label): \(error.localizedDescription)")
        }

        let deadline = Date().addingTimeInterval(max(0.5, min(timeoutSeconds, 30)))
        while Date() < deadline {
            #if canImport(AppKit)
            if !observedProcessIDs.isEmpty {
                if observedProcessIDs.allSatisfy({ !processIsAlive($0) }) {
                    return (true, nil)
                }
            } else if !isAppRunning(target) {
                return (true, nil)
            }
            #else
            if !isAppRunning(target) { return (true, nil) }
            #endif
            Thread.sleep(forTimeInterval: 0.2)
        }
        return (false, "\(spec.label): \(L10n.tr("error.antigravity.native_session_unavailable"))")
    }

    private func resolveBundlePath(for spec: EditorSpec) throws -> URL {
        guard let path = detectBundlePath(for: spec) else {
            throw AppError.fileNotFound(L10n.tr("error.editor.installation_path_not_found"))
        }
        return path
    }

    private func detectBundlePath(for spec: EditorSpec) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for bundle in spec.bundleNames {
            let systemPath = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundle)
            if FileManager.default.fileExists(atPath: systemPath.path) {
                return systemPath
            }
            let userPath = home.appendingPathComponent("Applications").appendingPathComponent(bundle)
            if FileManager.default.fileExists(atPath: userPath.path) {
                return userPath
            }
        }
        return nil
    }

    #if canImport(AppKit)
    private func runningBundleApplications(for spec: EditorSpec) -> [NSRunningApplication] {
        guard let path = detectBundlePath(for: spec),
              let bundleIdentifier = Bundle(url: path)?.bundleIdentifier else {
            return []
        }

        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == bundleIdentifier && processIsAlive($0.processIdentifier)
        }
    }
    #endif

    private func processIsAlive(_ processIdentifier: Int32) -> Bool {
        #if canImport(Darwin)
        guard processIdentifier > 0 else { return false }
        if kill(processIdentifier, 0) == 0 {
            return true
        }
        return errno == EPERM
        #else
        return false
        #endif
    }

    private func forceKillProcesses(_ processNames: [String]) {
        for name in processNames {
            _ = try? CommandRunner.run("/usr/bin/pkill", arguments: ["-9", "-x", name])
        }
    }
}
