import Foundation

enum AppTab: String, CaseIterable, Identifiable {
    case accounts
    case quotaManagement
    case settings

    var id: String { rawValue }
}

enum EditorAppID: String, Codable, CaseIterable, Identifiable {
    case vscode
    case vscodeInsiders
    case cursor
    case antigravity
    case kiro
    case trae
    case qoder

    var id: String { rawValue }
}

struct InstalledEditorApp: Equatable, Identifiable {
    var id: EditorAppID
    var label: String
}

struct SwitchAccountExecutionResult: Equatable {
    var usedFallbackCLI: Bool
    var opencodeSynced: Bool
    var opencodeSyncError: String?
    var opencodeSyncSkipped: Bool
    var restartedEditorApps: [EditorAppID]
    var editorRestartError: String?

    static let idle = SwitchAccountExecutionResult(
        usedFallbackCLI: false,
        opencodeSynced: false,
        opencodeSyncError: nil,
        opencodeSyncSkipped: false,
        restartedEditorApps: [],
        editorRestartError: nil
    )
}
