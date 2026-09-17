import Foundation

enum AppError: LocalizedError, Sendable {
    case fileNotFound(String)
    case invalidData(String)
    case io(String)
    case network(String)
    case unauthorized(String)
    case workspaceDeactivated

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let message),
             .invalidData(let message),
             .io(let message),
             .network(let message),
             .unauthorized(let message):
            return message
        case .workspaceDeactivated:
            return Self.localizedString("error.accounts.workspace_deactivated")
        }
    }

    var isWorkspaceDeactivated: Bool {
        if case .workspaceDeactivated = self {
            return true
        }
        return false
    }

    static func workspaceDeactivatedIfMatched(_ error: Error) -> AppError? {
        if let appError = error as? AppError, appError.isWorkspaceDeactivated {
            return .workspaceDeactivated
        }

        let message = error.localizedDescription.lowercased()
        guard message.contains("deactivated_workspace")
            || message.contains("account deactivated")
            || message.contains("workspace deactivated") else {
            return nil
        }
        return .workspaceDeactivated
    }

    private static func localizedString(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }
}
