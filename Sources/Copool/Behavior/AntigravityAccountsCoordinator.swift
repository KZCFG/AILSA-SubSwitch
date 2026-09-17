import Foundation

/// Compatibility shell for older call sites. The application no longer creates
/// this coordinator: AccountsCoordinator and its primary AccountsStore are the
/// single AntiGravity account authority. Keeping this shell side-effect-free
/// prevents old entry points from writing pseudo-native credentials.
@available(*, deprecated, message: "Use AccountsCoordinator's AntiGravity methods.")
final class AntigravityAccountsCoordinator: @unchecked Sendable {
    init(
        repository: AntigravityAuthRepository,
        editorAppService: EditorAppServiceProtocol,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        _ = repository
        _ = editorAppService
        _ = dateProvider
    }

    func bootstrapIfEmpty() throws -> [AntigravityAccountSummary] { [] }
    func importAllLocalSessions() throws -> [AntigravityAccountSummary] {
        throw AppError.invalidData(L10n.tr("error.antigravity.use_primary_accounts_store"))
    }
    func importFromCodexBar() throws -> [AntigravityAccountSummary] {
        throw AppError.invalidData(L10n.tr("error.antigravity.use_primary_accounts_store"))
    }
    func importOAuthFile(from url: URL) throws -> [AntigravityAccountSummary] {
        _ = url
        throw AppError.invalidData(L10n.tr("error.antigravity.use_primary_accounts_store"))
    }
    func listAccounts() throws -> [AntigravityAccountSummary] { [] }
    func importCurrentSession() throws -> AntigravityAccountSummary {
        throw AppError.invalidData(L10n.tr("error.antigravity.use_primary_accounts_store"))
    }
    func deleteAccount(id: String) throws {
        _ = id
        throw AppError.invalidData(L10n.tr("error.antigravity.use_primary_accounts_store"))
    }
    func switchAccount(id: String, restartIfRunning: Bool = true) throws -> AntigravitySwitchResult {
        _ = id
        _ = restartIfRunning
        throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
    }
}
