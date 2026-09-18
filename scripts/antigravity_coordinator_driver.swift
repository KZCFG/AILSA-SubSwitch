import Darwin
import Foundation
@testable import AILSA_SS

/// A deliberately narrow command-line surface for validating the production
/// AntiGravity switch transaction.  It never serializes account e-mail,
/// access/refresh tokens, raw OAuth JSON, or error details.
@main
struct AntigravityCoordinatorDriver {
    private struct Options {
        var showStatus = false
        var nativeStatus = false
        var switchID: String?
        var refreshID: String?
        var refreshCredentialID: String?
        var importCurrent = false
        var nativeLogin = false
        var reauthenticateID: String?
        var launchAfterSwitch: Bool?
        var showHelp = false
    }

    private struct DriverOutput: Encodable {
        var ok: Bool
        var settings: DriverSettings?
        var accounts: [DriverAccount]
        var nativeReadback: DriverNativeReadback?
        var switchedID: String?
        var refreshedID: String?
        var refreshedCredential: DriverCredentialRefresh?
        var importedID: String?
        var loginID: String?
        var reauthenticatedID: String?
        var failure: DriverFailure?
    }

    private struct DriverFailure: Encodable {
        var phase: String
        var code: String
    }

    /// Intentionally excludes identity, raw OAuth fields, and client material.
    private struct DriverCredentialRefresh: Encodable {
        var id: String
        var mode: String
        var expiry: String?
        var verified: Bool
    }

    private struct DriverSettings: Encodable {
        var launchAntigravityAfterSwitch: Bool
    }

    private struct DriverAccount: Encodable {
        var id: String
        var provider: String
        var current: Bool
        var pendingNativeSwitch: Bool
        var plan: String?
        var quotaSource: String?
        var quotaFetchedAt: Int64?
        var quotaState: String
        var quotaFamilies: [DriverQuotaFamily]
        var failureCode: String?
    }

    private struct DriverQuotaFamily: Encodable {
        var id: String
        var name: String
        var buckets: [DriverQuotaBucket]
    }

    private struct DriverQuotaBucket: Encodable {
        var id: String
        var name: String
        var usedPercent: Double?
        var resetAt: Int64?
        var known: Bool
    }

    /// An ephemeral, read-only answer from the currently running native
    /// language server. `matchedAccountID` is an opaque AILSA_SS card ID; the
    /// native e-mail is used solely for an in-memory exact match and is never
    /// serialized.
    private struct DriverNativeReadback: Encodable {
        var available: Bool
        var matchedAccountID: String?
        var plan: String?
        var quotaSource: String?
        var quotaFetchedAt: Int64?
        var quotaState: String
        var quotaFamilies: [DriverQuotaFamily]
        var failureCode: String?
    }

    static func main() async {
        // AuthFlowDebugLog uses NSLog for the interactive app. In this narrow
        // automation surface that would leak an identity to stderr even though
        // the JSON result is redacted, so suppress it for the whole process.
        AuthFlowDebugLog.setEnabled(false)
        var phase = "arguments"
        do {
            let options = try parse(Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(usage)
                return
            }

            phase = "initialization"
            let paths = try FileSystemPaths.live()
            let storeRepository = StoreFileRepository(paths: paths)
            let settingsRepository = SettingsFileRepository(paths: paths)
            let antigravityUsageService = AntigravityUsageService()
            let coordinator = AccountsCoordinator(
                storeRepository: storeRepository,
                settingsRepository: settingsRepository,
                authRepository: AuthFileRepository(paths: paths),
                usageService: DefaultUsageService(configPath: paths.codexConfigPath),
                workspaceMetadataService: DefaultWorkspaceMetadataService(configPath: paths.codexConfigPath),
                chatGPTOAuthLoginService: OpenAIChatGPTOAuthLoginService(configPath: paths.codexConfigPath),
                codexCLIService: CodexCLIService(),
                editorAppService: EditorAppService(),
                opencodeAuthSyncService: AILSA_SSAuthSyncService(),
                antigravityAuthRepository: AntigravityAuthRepository(),
                antigravityUsageService: antigravityUsageService
            )

            if let launchAfterSwitch = options.launchAfterSwitch {
                phase = "settings"
                let settingsCoordinator = SettingsCoordinator(
                    settingsRepository: settingsRepository,
                    launchAtStartupService: LaunchAtStartupService()
                )
                _ = try await settingsCoordinator.updateSettings(
                    AppSettingsPatch(launchAntigravityAfterSwitch: launchAfterSwitch)
                )
            }

            var switchedID: String?
            var refreshedID: String?
            var refreshedCredential: DriverCredentialRefresh?
            var importedID: String?
            var loginID: String?
            var reauthenticatedID: String?
            if let targetID = options.switchID {
                phase = "switch_preflight"
                let preflightStore = try storeRepository.loadStore()
                guard preflightStore.accounts.contains(where: {
                    $0.id == targetID && $0.provider == .antigravity
                }) else {
                    throw DriverArgumentError.invalid
                }
                // This is intentionally the production coordinator transaction,
                // not an independently reimplemented credential swap.
                phase = "switch"
                _ = try await coordinator.switchAccountAndReload(id: targetID)
                switchedID = targetID
            }
            if let targetID = options.refreshID {
                phase = "refresh_preflight"
                let preflightStore = try storeRepository.loadStore()
                guard preflightStore.accounts.contains(where: {
                    $0.id == targetID && $0.provider == .antigravity
                }) else {
                    throw DriverArgumentError.invalid
                }
                phase = "refresh"
                _ = try await coordinator.refreshUsage(
                    accountIDs: [targetID],
                    force: true,
                    serial: true
                )
                refreshedID = targetID
            }
            if let targetID = options.refreshCredentialID {
                phase = "refresh_credential_preflight"
                let preflightStore = try storeRepository.loadStore()
                guard preflightStore.accounts.contains(where: {
                    $0.id == targetID && $0.provider == .antigravity
                }) else {
                    throw DriverArgumentError.invalid
                }
                phase = "refresh_credential"
                refreshedCredential = try await forceRefreshCredential(
                    id: targetID,
                    storeRepository: storeRepository,
                    usageService: antigravityUsageService
                )
            }
            if options.importCurrent {
                phase = "import_current"
                let imported = try await coordinator.importCurrentAntigravitySession(customLabel: nil)
                importedID = imported.id
            }
            if options.nativeLogin {
                // Exact same coordinator entry point as the app's
                // AntiGravity Add Account button. It performs the native Login
                // RPC, validates authResult, then imports/merges the observed
                // session without serializing its identity or credentials.
                phase = "native_login"
                let imported = try await coordinator.addAntigravityAccountViaNativeLogin(customLabel: nil)
                loginID = imported.id
            }
            if let targetID = options.reauthenticateID {
                phase = "reauthenticate_preflight"
                let preflightStore = try storeRepository.loadStore()
                guard preflightStore.accounts.contains(where: {
                    $0.id == targetID && $0.provider == .antigravity
                }) else {
                    throw DriverArgumentError.invalid
                }
                // Exact same coordinator entry point as the app's
                // reauthenticate action; no OAuth or native-RPC logic is
                // duplicated in this driver.
                phase = "reauthenticate"
                let reauthenticated = try await coordinator.reauthenticateAntigravityAccount(id: targetID)
                reauthenticatedID = reauthenticated.id
            }

            // Status is a direct, read-only snapshot of the primary account
            // store.  Do not call listAccounts here: that routine may run a
            // legacy migration, which would make a nominally read-only status
            // request write user data.
            phase = "status"
            let store = try storeRepository.loadStore()
            let settings = try settingsRepository.loadSettings()
            let nativeReadback = await makeNativeReadback(
                service: antigravityUsageService,
                accounts: store.accounts
            )
            let output = DriverOutput(
                ok: true,
                settings: DriverSettings(
                    launchAntigravityAfterSwitch: settings.launchAntigravityAfterSwitch
                ),
                accounts: store.accountSummaries().map(Self.makeSafeAccount),
                nativeReadback: nativeReadback,
                switchedID: switchedID,
                refreshedID: refreshedID,
                refreshedCredential: refreshedCredential,
                importedID: importedID,
                loginID: loginID,
                reauthenticatedID: reauthenticatedID,
                failure: nil
            )
            try write(output)
        } catch {
            // Error descriptions can contain an e-mail address, local path, or
            // server response. Keep this CLI's failure output intentionally
            // non-diagnostic; the app's local UI/debug log remains the place
            // for user-authorized troubleshooting.
            let output = DriverOutput(
                ok: false,
                settings: nil,
                accounts: [],
                nativeReadback: nil,
                switchedID: nil,
                refreshedID: nil,
                refreshedCredential: nil,
                importedID: nil,
                loginID: nil,
                reauthenticatedID: nil,
                failure: DriverFailure(
                    phase: phase,
                    code: failureCode(for: error)
                )
            )
            try? write(output)
            exit(1)
        }
    }

    private static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--status":
                options.showStatus = true
            case "--native-status":
                options.nativeStatus = true
            case "--switch":
                index += 1
                guard index < arguments.count,
                      !arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      options.switchID == nil
                else {
                    throw DriverArgumentError.invalid
                }
                options.switchID = arguments[index]
            case "--refresh-id":
                index += 1
                guard index < arguments.count,
                      !arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      options.refreshID == nil
                else {
                    throw DriverArgumentError.invalid
                }
                options.refreshID = arguments[index]
            case "--refresh-credential-id":
                index += 1
                guard index < arguments.count,
                      !arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      options.refreshCredentialID == nil
                else {
                    throw DriverArgumentError.invalid
                }
                options.refreshCredentialID = arguments[index]
            case "--import-current":
                guard !options.importCurrent else {
                    throw DriverArgumentError.invalid
                }
                options.importCurrent = true
            case "--login":
                guard !options.nativeLogin else {
                    throw DriverArgumentError.invalid
                }
                options.nativeLogin = true
            case "--reauthenticate-id":
                index += 1
                guard index < arguments.count,
                      !arguments[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      options.reauthenticateID == nil
                else {
                    throw DriverArgumentError.invalid
                }
                options.reauthenticateID = arguments[index]
            case "--set-launch-antigravity-after-switch":
                index += 1
                guard index < arguments.count,
                      options.launchAfterSwitch == nil
                else {
                    throw DriverArgumentError.invalid
                }
                switch arguments[index].lowercased() {
                case "true", "on", "1":
                    options.launchAfterSwitch = true
                case "false", "off", "0":
                    options.launchAfterSwitch = false
                default:
                    throw DriverArgumentError.invalid
                }
            case "--help", "-h":
                options.showHelp = true
            default:
                throw DriverArgumentError.invalid
            }
            index += 1
        }

        let mutatingActions = [
            options.switchID != nil,
            options.refreshID != nil,
            options.refreshCredentialID != nil,
            options.importCurrent,
            options.nativeLogin,
            options.reauthenticateID != nil
        ].filter { $0 }.count
        guard mutatingActions <= 1 else {
            throw DriverArgumentError.invalid
        }

        // No argument is the same safe, read-only operation as --status.
        if !options.showHelp && !options.showStatus && !options.nativeStatus
            && options.switchID == nil && options.refreshID == nil
            && options.refreshCredentialID == nil
            && !options.importCurrent && !options.nativeLogin
            && options.reauthenticateID == nil && options.launchAfterSwitch == nil {
            options.showStatus = true
        }
        return options
    }

    private static func makeSafeAccount(_ account: AccountSummary) -> DriverAccount {
        let snapshot = account.usage
        let quotaState: String
        if account.usageError != nil {
            quotaState = "error"
        } else if snapshot?.isVerifiedForSwitch == true {
            quotaState = "verified"
        } else if snapshot?.hasAuthoritativeQuota == true {
            quotaState = "partial"
        } else {
            quotaState = "unknown"
        }

        return DriverAccount(
            id: account.id,
            provider: account.provider.rawValue,
            current: account.isCurrent,
            pendingNativeSwitch: account.isPendingNativeSwitch,
            plan: snapshot?.planType ?? account.planType,
            quotaSource: snapshot?.source?.rawValue,
            quotaFetchedAt: snapshot?.fetchedAt,
            quotaState: quotaState,
            quotaFamilies: snapshot?.quotaFamilies?.map { family in
                DriverQuotaFamily(
                    id: family.id,
                    name: family.displayName,
                    buckets: family.buckets.map { bucket in
                        DriverQuotaBucket(
                            id: bucket.id,
                            name: bucket.displayName,
                            usedPercent: bucket.usedPercent,
                            resetAt: bucket.resetAt,
                            known: bucket.isUsageKnown
                        )
                    }
                )
            } ?? [],
            failureCode: account.usageError == nil ? nil : "usage_unavailable"
        )
    }

    /// Forces exactly one production profile-bound refresh and then commits the
    /// returned credential through the store's serialized mutation path.  If a
    /// concurrent re-authentication changed this card while the network call
    /// was in flight, do not overwrite it with the older snapshot.
    private static func forceRefreshCredential(
        id: String,
        storeRepository: StoreFileRepository,
        usageService: AntigravityUsageService
    ) async throws -> DriverCredentialRefresh {
        let preflight = try storeRepository.loadStore()
        guard let account = preflight.accounts.first(where: {
            $0.id == id && $0.provider == .antigravity
        }) else {
            throw DriverArgumentError.invalid
        }
        let originalAuth = account.authJSON
        let refreshedAuth = try await usageService.refreshStoredCredential(
            originalAuth,
            force: true
        )
        let savedStore = try storeRepository.mutateStore { store in
            guard let index = store.accounts.firstIndex(where: {
                $0.id == id && $0.provider == .antigravity
            }),
            store.accounts[index].authJSON == originalAuth
            else {
                throw DriverArgumentError.invalid
            }
            store.accounts[index].authJSON = refreshedAuth
            store.accounts[index].updatedAt = Int64(Date().timeIntervalSince1970)
        }
        guard let saved = savedStore.accounts.first(where: { $0.id == id }),
              let mode = saved.authJSON["auth_method"]?.stringValue,
              AntigravityOAuthProfile(rawValue: mode) != nil
        else {
            throw DriverArgumentError.invalid
        }
        return DriverCredentialRefresh(
            id: id,
            mode: mode,
            expiry: saved.authJSON["expiry"]?.stringValue,
            verified: AntigravityAuthRepository.isNativeVerifiedCredential(saved.authJSON)
        )
    }

    private static func makeNativeReadback(
        service: AntigravityUsageService,
        accounts: [StoredAccount]
    ) async -> DriverNativeReadback {
        do {
            let native = try await service.fetchCurrentNativeUsage()
            let normalizedEmail = native.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matchedID = accounts.first(where: {
                $0.provider == .antigravity
                    && $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedEmail
            })?.id
            let snapshot = native.usage
            return DriverNativeReadback(
                available: true,
                matchedAccountID: matchedID,
                plan: native.planType,
                quotaSource: snapshot.source?.rawValue,
                quotaFetchedAt: snapshot.fetchedAt,
                quotaState: snapshot.isVerifiedForSwitch ? "verified" : "partial",
                quotaFamilies: makeSafeFamilies(snapshot.quotaFamilies ?? []),
                failureCode: nil
            )
        } catch {
            return DriverNativeReadback(
                available: false,
                matchedAccountID: nil,
                plan: nil,
                quotaSource: nil,
                quotaFetchedAt: nil,
                quotaState: "unavailable",
                quotaFamilies: [],
                failureCode: failureCode(for: error)
            )
        }
    }

    private static func makeSafeFamilies(_ families: [UsageQuotaFamily]) -> [DriverQuotaFamily] {
        families.map { family in
            DriverQuotaFamily(
                id: family.id,
                name: family.displayName,
                buckets: family.buckets.map { bucket in
                    DriverQuotaBucket(
                        id: bucket.id,
                        name: bucket.displayName,
                        usedPercent: bucket.usedPercent,
                        resetAt: bucket.resetAt,
                        known: bucket.isUsageKnown
                    )
                }
            )
        }
    }

    private static func write<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DriverArgumentError.invalid
        }
        print(text)
    }

    /// Deliberately stable and redacted: localized error strings can include a
    /// local path, server body, or account identity. The phase/code pair is
    /// enough for an operator to distinguish setup, switch, and readback
    /// failures without leaking that data.
    private static func failureCode(for error: Error) -> String {
        let detail = error.localizedDescription.lowercased()
        for status in [401, 403, 404, 408, 429, 500, 502, 503, 504] {
            if detail.contains("\(status)") {
                return "http_\(status)"
            }
        }
        if detail.contains("native_quota") || detail.contains("quota unavailable") {
            return "native_quota_unavailable"
        }
        if detail.contains("native_identity") || detail.contains("identity unavailable") {
            return "native_identity_unavailable"
        }
        if detail.contains("native_session") || detail.contains("session unavailable") {
            return "native_session_unavailable"
        }
        guard let appError = error as? AppError else {
            return "unexpected"
        }
        switch appError {
        case .fileNotFound:
            return "not_found"
        case .invalidData:
            return "invalid_state"
        case .io:
            return "io_failed"
        case .network:
            return "network_failed"
        case .unauthorized:
            return "unauthorized"
        case .workspaceDeactivated:
            return "workspace_deactivated"
        }
    }

    private enum DriverArgumentError: Error {
        case invalid
    }

    private static let usage = """
    Usage: antigravity-coordinator-driver [--status] [--native-status] [--switch <opaque-account-id>] [--refresh-id <opaque-account-id>] [--refresh-credential-id <opaque-account-id>] [--import-current] [--login] [--reauthenticate-id <opaque-account-id>] [--set-launch-antigravity-after-switch <true|false>]

    --status  Print a read-only, redacted snapshot (default).
    --native-status  Query only the currently running native language server; no remote quota fallback.
    --switch  Run the production AccountsCoordinator switch transaction.
    --refresh-id  Force one stored AntiGravity card through the production refresh path.
    --refresh-credential-id  Force one stored credential through the production OAuth refresh/bind path and atomically save it. Output remains redacted.
    --import-current  Import the currently running native session through the production identity-binding path.
    --login  Run the same native Login/add-account coordinator path as the app; waits for the verified current session and merges it idempotently.
    --reauthenticate-id  Run the same native reauthenticate coordinator path as the app for one stored card.
    --set-launch-antigravity-after-switch  Persist the explicit launch preference.
    """
}
