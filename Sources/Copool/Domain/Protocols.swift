import Foundation

protocol AccountsStoreRepository: Sendable {
    func loadStore() throws -> AccountsStore
    func saveStore(_ store: AccountsStore) throws
    func mutateStore(_ transform: (inout AccountsStore) throws -> Void) throws -> AccountsStore
}

extension AccountsStoreRepository {
    func mutateStore(_ transform: (inout AccountsStore) throws -> Void) throws -> AccountsStore {
        var store = try loadStore()
        try transform(&store)
        try saveStore(store)
        return store
    }
}

protocol SettingsRepository: Sendable {
    func loadSettings() throws -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
}

protocol AuthRepository: Sendable {
    func readCurrentAuth() throws -> JSONValue
    func readCurrentAuthOptional() throws -> JSONValue?
    func readAuth(from url: URL) throws -> JSONValue
    func writeCurrentAuth(_ auth: JSONValue) throws
    func removeCurrentAuth() throws
    func makeChatGPTAuth(from tokens: ChatGPTOAuthTokens) throws -> JSONValue
    func exchangeAuth(email: String, refreshToken: String) async throws -> JSONValue
    func extractAuth(from auth: JSONValue) throws -> ExtractedAuth
    func refreshChatGPTAuth(_ auth: JSONValue) async throws -> JSONValue
}

protocol UsageService: Sendable {
    func fetchUsage(accessToken: String, accountID: String) async throws -> UsageSnapshot
}

protocol WorkspaceMetadataService: Sendable {
    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata]
}

protocol DateProviding: Sendable {
    func unixSecondsNow() -> Int64
    func unixMillisecondsNow() -> Int64
}

extension DateProviding {
    func unixMillisecondsNow() -> Int64 {
        unixSecondsNow() * 1_000
    }
}

extension AuthRepository {
    func exchangeAuth(email: String, refreshToken: String) async throws -> JSONValue {
        _ = email
        _ = refreshToken
        throw AppError.invalidData(L10n.tr("error.opencode.missing_refresh_token"))
    }

    func readCurrentExtractedAuth() -> ExtractedAuth? {
        guard let auth = try? readCurrentAuthOptional(),
              let extracted = try? extractAuth(from: auth) else {
            return nil
        }
        return extracted
    }

    func currentAuthAccountKey() -> String? {
        readCurrentExtractedAuth()?.accountKey
    }

    func refreshChatGPTAuth(_ auth: JSONValue) async throws -> JSONValue {
        auth
    }
}

protocol CodexCLIServiceProtocol: Sendable {
    func launchApp(workspacePath: String?) throws -> Bool
}

protocol ChatGPTOAuthLoginServiceProtocol: Sendable {
    func signInWithChatGPT(timeoutSeconds: TimeInterval) async throws -> ChatGPTOAuthTokens
    func signInWithChatGPT(timeoutSeconds: TimeInterval, forcedWorkspaceID: String?) async throws -> ChatGPTOAuthTokens
}

extension ChatGPTOAuthLoginServiceProtocol {
    func signInWithChatGPT(timeoutSeconds: TimeInterval, forcedWorkspaceID: String?) async throws -> ChatGPTOAuthTokens {
        _ = forcedWorkspaceID
        return try await signInWithChatGPT(timeoutSeconds: timeoutSeconds)
    }
}

protocol EditorAppServiceProtocol: Sendable {
    func listInstalledApps() -> [InstalledEditorApp]
    func restartSelectedApps(_ targets: [EditorAppID]) -> (restarted: [EditorAppID], error: String?)
    /// Opens an installed app without terminating an existing instance.
    func launchApp(_ target: EditorAppID) -> (launched: Bool, error: String?)
    /// Checks a single editor's process state without changing it.
    func isAppRunning(_ target: EditorAppID) -> Bool
    /// Requests a normal application termination and waits for it to exit. It
    /// must never force-kill a process with unsaved editor state.
    func quitAppGracefully(
        _ target: EditorAppID,
        timeoutSeconds: TimeInterval
    ) -> (didQuit: Bool, error: String?)
}

extension EditorAppServiceProtocol {
    func launchApp(_ target: EditorAppID) -> (launched: Bool, error: String?) {
        _ = target
        return (false, nil)
    }

    func isAppRunning(_ target: EditorAppID) -> Bool {
        _ = target
        return false
    }

    func quitAppGracefully(
        _ target: EditorAppID,
        timeoutSeconds: TimeInterval
    ) -> (didQuit: Bool, error: String?) {
        _ = target
        _ = timeoutSeconds
        return (false, nil)
    }
}

protocol OpencodeAuthSyncServiceProtocol: Sendable {
    func syncFromCodexAuth(_ authJSON: JSONValue) throws
}

protocol LaunchAtStartupServiceProtocol: Sendable {
    func setEnabled(_ enabled: Bool) throws
    func syncWithStoreValue(_ enabled: Bool) throws
}

@MainActor
protocol AccountsManualRefreshServiceProtocol: AnyObject {
    func performManualRefresh() async throws -> [AccountSummary]
    func performManualRefresh(
        onPartialUpdate: @escaping @MainActor ([AccountSummary]) -> Void
    ) async throws -> [AccountSummary]
}

extension AccountsManualRefreshServiceProtocol {
    func performManualRefresh() async throws -> [AccountSummary] {
        try await performManualRefresh(onPartialUpdate: { _ in })
    }
}

@MainActor
protocol AccountsLocalMutationSyncServiceProtocol: AnyObject {
    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary])
    func syncLocalAccountsMutationNow() async
}
