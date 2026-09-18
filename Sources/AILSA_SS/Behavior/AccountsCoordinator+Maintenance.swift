import Foundation
import OSLog

/// Couples an asynchronously refreshed projection with the exact credential
/// snapshot it started from. AntiGravity refreshes use that snapshot as a CAS
/// condition instead of relying on second-resolution `updatedAt` timestamps.
private struct AccountUsageRefreshResult {
    var account: StoredAccount
    var sourceAuthJSON: JSONValue
}

extension AccountsCoordinator {
    private var authFlowLogger: Logger {
        Logger(subsystem: "AILSA_SS", category: "AccountsAuthFlow")
    }

    func listAccounts(refreshWorkspaceMetadata: Bool = true) async throws -> [AccountSummary] {
        var store = try storeRepository.loadStore()
        let didClearUnverifiedCountdowns = clearUnverifiedCountdownMarkers(in: &store)
        let didMigrateAntigravity = try migrateLegacyAntigravityAccountsIfNeeded(in: &store)
        let didReconcile = Self.reconcileStoredAccountMetadata(in: &store, authRepository: authRepository)
        if didClearUnverifiedCountdowns || didMigrateAntigravity || didReconcile {
            try storeRepository.saveStore(store)
            // The remote metadata lookup below may suspend. Start it from the
            // just-persisted store rather than carrying an earlier whole-store
            // snapshot into a later save.
            store = try storeRepository.loadStore()
        }

        var didEnrich = false
        if refreshWorkspaceMetadata {
            let metadataBaseline = store
            didEnrich = try await enrichStoredWorkspaceMetadataIfNeeded(
                in: &store,
                forceRemoteCheck: false
            )
            if didEnrich {
                store = try applyWorkspaceMetadataChanges(
                    from: store,
                    relativeTo: metadataBaseline
                )
            } else {
                store = try storeRepository.loadStore()
            }
        }
        let summaries = store.accountSummaries()
        AccountSwitchDebugLog.write(
            "listAccounts",
            "refreshWorkspaceMetadata=\(refreshWorkspaceMetadata) reconciled=\(didReconcile) enriched=\(didEnrich) \(AccountSwitchDebugLog.describe(store: store, currentAuthAccountKey: authRepository.currentAuthAccountKey())) \(AccountSwitchDebugLog.describe(accounts: summaries))"
        )
        return summaries
    }

    /// Remove markers written by older builds that treated a quota read as a
    /// first model request. A verified request marker is retained across reads.
    private func clearUnverifiedCountdownMarkers(in store: inout AccountsStore) -> Bool {
        let now = dateProvider.unixSecondsNow()
        var changed = false
        for index in store.accounts.indices {
            guard let usage = store.accounts[index].usage else { continue }
            let cleaned = QuotaCountdownState.reconcile(previous: usage, refreshed: usage, observedAt: now)
            if cleaned != usage {
                store.accounts[index].usage = cleaned
                changed = true
            }
        }
        return changed
    }

    /// The previous integration maintained a second AntiGravity account file.
    /// Read it only to preserve user-imported accounts, then keep all future
    /// state in AccountsStore. No legacy marker is trusted as native current.
    private func migrateLegacyAntigravityAccountsIfNeeded(in store: inout AccountsStore) throws -> Bool {
        guard let antigravityAuthRepository else { return false }
        let legacyAccounts = try antigravityAuthRepository.legacyAccountsForMigration()
        guard !legacyAccounts.isEmpty else { return false }
        let now = dateProvider.unixSecondsNow()
        var changed = false
        for legacy in legacyAccounts {
            guard let extracted = try? antigravityAuthRepository.extractAuth(from: legacy.oauthJSON),
                  let verifiedEmail = AccountIdentity.normalizedEmail(extracted.email)
            else { continue }

            // Older cards stored Google's opaque subject as `accountID`, while
            // native import now uses the verified e-mail as its stable account
            // identity. The generic key matcher therefore sees them as two
            // accounts. Migration has a narrower rule: within AntiGravity
            // only, an exact normalized e-mail is the dedupe key. Never merge
            // by label or subject ID, and never overwrite the already-primary
            // card's id, saved auth, plan, or current marker.
            let alreadyMigrated = store.accounts.contains { existing in
                existing.provider == .antigravity
                    && AccountIdentity.normalizedEmail(existing.email) == verifiedEmail
            }
            guard !alreadyMigrated else { continue }
            store.accounts.append(
                StoredAccount(
                    id: UUID().uuidString,
                    label: legacy.label,
                    email: extracted.email ?? legacy.email,
                    accountID: extracted.accountID,
                    planType: extracted.planType,
                    teamName: nil,
                    teamAlias: nil,
                    authJSON: legacy.oauthJSON,
                    addedAt: legacy.addedAt,
                    updatedAt: max(legacy.updatedAt, now),
                    usage: nil,
                    usageError: nil,
                    principalID: extracted.principalID,
                    provider: .antigravity
                )
            )
            changed = true
        }
        return changed
    }

    @discardableResult
    func importCurrentAuthAccount(
        customLabel: String?,
        provider: AccountProvider = .codex
    ) async throws -> AccountSummary {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        if provider == .antigravity {
            return try await importCurrentAntigravitySession(customLabel: customLabel)
        }
        let authJSON = try authRepository.readCurrentAuth()
        return try await importAccount(authJSON: authJSON, customLabel: customLabel)
    }

    @discardableResult
    func importAccountFile(from url: URL, customLabel: String?, setAsCurrent: Bool) async throws -> AccountSummary {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let authJSON = try authRepository.readAuth(from: url)
        let provider: AccountProvider = AntigravityAuthRepository.looksLikeGeminiOAuth(authJSON)
            ? .antigravity
            : .codex
        if setAsCurrent, runtimePlatform == .macOS {
            if provider == .codex {
                try authRepository.writeCurrentAuth(authJSON)
            }
        }
        return try await importAccount(authJSON: authJSON, customLabel: customLabel, provider: provider)
    }

    @discardableResult
    func addAccountViaLogin(customLabel: String?, timeoutSeconds: TimeInterval = 10 * 60) async throws -> AccountSummary {
        authFlowLogger.log("addAccountViaLogin started")
        AuthFlowDebugLog.write("AccountsAuthFlow", "addAccountViaLogin started")
        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(timeoutSeconds: timeoutSeconds)
        authFlowLogger.log("addAccountViaLogin received tokens with \(tokens.consentWorkspaces.count) consent workspaces")
        AuthFlowDebugLog.write("AccountsAuthFlow", "addAccountViaLogin received tokens with \(tokens.consentWorkspaces.count) consent workspaces")
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        AuthFlowDebugLog.write("AccountsAuthFlow", "addAccountViaLogin made auth json")
        let imported = try await importAccount(authJSON: authJSON, customLabel: customLabel)
        authFlowLogger.log("addAccountViaLogin imported account \(imported.accountID, privacy: .public)")
        AuthFlowDebugLog.write("AccountsAuthFlow", "addAccountViaLogin imported account \(imported.accountID)")
        try persistConsentWorkspaceDirectory(
            tokens.consentWorkspaces,
            authorizedWorkspaceID: imported.accountID,
            fallbackEmail: imported.email,
            fallbackPlanType: imported.planType
        )
        authFlowLogger.log("addAccountViaLogin persisted consent workspace directory")
        AuthFlowDebugLog.write("AccountsAuthFlow", "addAccountViaLogin persisted consent workspace directory")
        return imported
    }

    /// Opens the native app only in response to the user's Add Account action,
    /// then waits for a newly observed native session. Cancellation stops the
    /// wait and never alters the app or a credential file.
    @discardableResult
    func addAntigravityAccountViaNativeLogin(
        customLabel: String?,
        timeoutSeconds: TimeInterval = 10 * 60,
        onStage: (@Sendable @MainActor (AccountAddProgressStage) async -> Void)? = nil
    ) async throws -> AccountSummary {
        guard runtimePlatform == .macOS, let antigravityUsageService else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        return try await withExclusiveAntigravityOperation {
            try Task.checkCancellation()
            await onStage?(.starting)
            let launch = editorAppService.launchApp(.antigravity)
            if !launch.launched, let error = launch.error {
                throw AppError.io(error)
            }
            try Task.checkCancellation()
            await onStage?(.waitingForGoogleLogin)
            try await beginNativeBrowserLogin(
                using: antigravityUsageService,
                timeoutSeconds: timeoutSeconds
            )
            // The native Login RPC returns after Google has accepted the
            // account. The next native usage read can trigger macOS Keychain
            // authorization, so make that handoff explicit in the UI.
            await onStage?(.loginSucceeded)
            await onStage?(.waitingForComputerAuthorization)

            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var lastError: Error = AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
            while Date() < deadline {
                try Task.checkCancellation()
                do {
                    let native = try await antigravityUsageService.fetchCurrentNativeUsage()
                    try Task.checkCancellation()
                    // A valid Login response can intentionally reauthorize an
                    // account that already has a card. Import it either way:
                    // provider + verified e-mail then merges the fresh grant
                    // and quota into that existing card instead of waiting for
                    // an impossible "new" identity.
                    await onStage?(.importing)
                    return try await importNativeAntigravitySession(
                        native,
                        customLabel: customLabel,
                        usageService: antigravityUsageService
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as AntigravityNativeCredentialAccessError {
                    // Cancel/deny/lock is terminal for this explicit attempt.
                    // Do not poll once per second and recreate the prompt.
                    if error.stopsAutomaticRetry {
                        throw error
                    }
                    lastError = error
                } catch {
                    lastError = error
                }
                try await Task.sleep(for: .seconds(1))
            }
            throw lastError
        }
    }

    @discardableResult
    func importCurrentAntigravitySession(customLabel: String?) async throws -> AccountSummary {
        guard runtimePlatform == .macOS, let antigravityUsageService else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        return try await withExclusiveAntigravityOperation {
            try Task.checkCancellation()
            let native = try await antigravityUsageService.fetchCurrentNativeUsage()
            try Task.checkCancellation()
            return try await importNativeAntigravitySession(
                native,
                customLabel: customLabel,
                usageService: antigravityUsageService
            )
        }
    }

    @discardableResult
    func reauthenticateAntigravityAccount(
        id: String,
        timeoutSeconds: TimeInterval = 10 * 60
    ) async throws -> AccountSummary {
        guard runtimePlatform == .macOS, let antigravityUsageService else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        return try await withExclusiveAntigravityOperation {
            try Task.checkCancellation()
            let store = try storeRepository.loadStore()
            guard let target = store.accounts.first(where: { $0.id == id && $0.provider == .antigravity }),
                  let expectedEmail = target.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !expectedEmail.isEmpty
            else {
                throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
            }
            let repository = try resolvedAntigravityAuthRepository()
            let launch = editorAppService.launchApp(.antigravity)
            if !launch.launched, let error = launch.error {
                throw AppError.io(error)
            }
            try Task.checkCancellation()
            try await beginNativeBrowserLogin(
                using: antigravityUsageService,
                timeoutSeconds: timeoutSeconds
            )
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var lastError: Error = AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
            while Date() < deadline {
                try Task.checkCancellation()
                do {
                    let native = try await antigravityUsageService.fetchNativeUsage(expectedEmail: expectedEmail)
                    let credential = try await antigravityUsageService.verifyCurrentNativeCredential(
                        repository: repository,
                        matchingNativeEmail: native.email,
                        credentialAccess: .userInitiated
                    )
                    try Task.checkCancellation()
                    _ = try storeRepository.mutateStore { latest in
                        guard let index = latest.accounts.firstIndex(where: { $0.id == id && $0.provider == .antigravity }),
                              latest.accounts[index].authJSON == target.authJSON
                        else {
                            throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
                        }
                        latest.accounts[index].usage = native.usage
                        latest.accounts[index].usageError = nil
                        latest.accounts[index].usageStateUpdatedAt = dateProvider.unixSecondsNow()
                        latest.accounts[index].planType = native.planType ?? latest.accounts[index].planType
                        latest.accounts[index].authJSON = credential.authJSON
                        latest.accounts[index].updatedAt = dateProvider.unixSecondsNow()
                        latest.currentAntigravityAccountID = id
                        latest.pendingAntigravityAccountID = nil
                    }
                    let savedStore = try storeRepository.loadStore()
                    guard let saved = savedStore.accounts.first(where: { $0.id == id }) else {
                        throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
                    }
                    return toSummary(saved, in: savedStore)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as AntigravityNativeCredentialAccessError {
                    // The native browser flow may still be open, but a
                    // cancelled/denied Keychain request is terminal for this
                    // operation. Do not retry it on the next poll tick.
                    if error.stopsAutomaticRetry {
                        throw error
                    }
                    lastError = error
                } catch {
                    lastError = error
                }
                try await Task.sleep(for: .seconds(1))
            }
            throw lastError
        }
    }

    func syncWorkspaceDirectory() async throws -> [WorkspaceDirectoryEntry] {
        var store = try storeRepository.loadStore()
        guard let workspaceMetadataService else {
            return store.workspaceDirectory
        }

        let eligibleAccounts = try store.accounts.compactMap { account -> (StoredAccount, ExtractedAuth)? in
            // Workspace metadata uses the OpenAI/Codex auth protocol. Filter
            // before extraction so an AntiGravity account neither leaks into
            // the lookup nor prevents Codex workspace discovery.
            guard account.provider == .codex, account.displayStatus == .list else { return nil }
            let extracted = try authRepository.extractAuth(from: account.authJSON)
            guard shouldLookupRemoteWorkspaceMetadata(extracted: extracted) else { return nil }
            return (account, extracted)
        }
        guard !eligibleAccounts.isEmpty else {
            return store.workspaceDirectory
        }

        let now = dateProvider.unixSecondsNow()
        let authorizedWorkspaceIDs = Set(
            store.accounts
                .filter { $0.provider == .codex && $0.displayStatus == .list }
                .map { AccountIdentity.normalizedAccountID($0.accountID) }
        )
        var nextEntriesByID = Dictionary(
            uniqueKeysWithValues: store.workspaceDirectory.compactMap { entry -> (String, WorkspaceDirectoryEntry)? in
                let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(entry.workspaceID)
                guard !normalizedWorkspaceID.isEmpty else { return nil }
                return (normalizedWorkspaceID, entry)
            }
        )

        var discoveredWorkspaceIDs: Set<String> = []
        var discoveredWorkspacesByID: [String: (metadata: WorkspaceMetadata, sourceAccount: StoredAccount)] = [:]

        for (sourceAccount, extracted) in eligibleAccounts {
            try Task.checkCancellation()
            let metadata = try await workspaceMetadataService.fetchWorkspaceMetadata(
                accessToken: extracted.accessToken
            )
            try Task.checkCancellation()

            for workspace in metadata {
                let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspace.accountID)
                guard !normalizedWorkspaceID.isEmpty else { continue }
                discoveredWorkspaceIDs.insert(normalizedWorkspaceID)
                if discoveredWorkspacesByID[normalizedWorkspaceID] == nil {
                    discoveredWorkspacesByID[normalizedWorkspaceID] = (workspace, sourceAccount)
                }
            }
        }

        for (normalizedWorkspaceID, discoveredWorkspace) in discoveredWorkspacesByID {
            let workspace = discoveredWorkspace.metadata
            let sourceAccount = discoveredWorkspace.sourceAccount
            guard !authorizedWorkspaceIDs.contains(normalizedWorkspaceID) else {
                nextEntriesByID.removeValue(forKey: normalizedWorkspaceID)
                continue
            }
            guard let workspaceName = Self.visibleWorkspaceName(for: workspace) else {
                nextEntriesByID.removeValue(forKey: normalizedWorkspaceID)
                continue
            }

            let existingEntry = nextEntriesByID[normalizedWorkspaceID]
            let shouldPreserveDeactivated = existingEntry?.status == .deactivated
            let entry = WorkspaceDirectoryEntry(
                workspaceID: workspace.accountID,
                workspaceName: workspaceName,
                email: sourceAccount.email,
                planType: sourceAccount.planType,
                kind: workspaceDirectoryKind(for: workspace),
                source: .legacyMetadata,
                status: shouldPreserveDeactivated ? .deactivated : .active,
                visibility: existingEntry?.visibility ?? .visible,
                lastSeenAt: now,
                lastStatusCheckedAt: existingEntry?.lastStatusCheckedAt
            )
            nextEntriesByID[normalizedWorkspaceID] = entry
        }

        nextEntriesByID = nextEntriesByID.filter { workspaceID, entry in
            if entry.status == .deactivated {
                return true
            }
            if entry.visibility == .deleted {
                return true
            }
            if entry.source == .consent {
                return true
            }
            return discoveredWorkspaceIDs.contains(workspaceID)
        }

        let retainedEntries = nextEntriesByID.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .workspace
            }
            let lhsName = lhs.workspaceName ?? ""
            let rhsName = rhs.workspaceName ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        if store.workspaceDirectory != retainedEntries {
            store.workspaceDirectory = retainedEntries
            try storeRepository.saveStore(store)
        }

        return retainedEntries
    }

    @discardableResult
    func authorizeWorkspaceViaLogin(
        workspaceID: String,
        workspaceName: String,
        customLabel: String?,
        timeoutSeconds: TimeInterval = 10 * 60
    ) async throws -> AccountSummary {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        authFlowLogger.log("authorizeWorkspaceViaLogin started for workspace \(workspaceID, privacy: .public)")
        AuthFlowDebugLog.write("AccountsAuthFlow", "authorizeWorkspaceViaLogin started for workspace \(workspaceID)")
        let tokens = try await chatGPTOAuthLoginService.signInWithChatGPT(
            timeoutSeconds: timeoutSeconds,
            forcedWorkspaceID: workspaceID
        )
        authFlowLogger.log("authorizeWorkspaceViaLogin received tokens with \(tokens.consentWorkspaces.count) consent workspaces")
        AuthFlowDebugLog.write("AccountsAuthFlow", "authorizeWorkspaceViaLogin received tokens with \(tokens.consentWorkspaces.count) consent workspaces")
        let authJSON = try authRepository.makeChatGPTAuth(from: tokens)
        AuthFlowDebugLog.write("AccountsAuthFlow", "authorizeWorkspaceViaLogin made auth json")
        let imported = try await importAccount(
            authJSON: authJSON,
            customLabel: customLabel,
            prefetchedWorkspaceName: workspaceName
        )
        authFlowLogger.log("authorizeWorkspaceViaLogin imported account \(imported.accountID, privacy: .public)")
        AuthFlowDebugLog.write("AccountsAuthFlow", "authorizeWorkspaceViaLogin imported account \(imported.accountID)")
        try persistConsentWorkspaceDirectory(
            tokens.consentWorkspaces,
            authorizedWorkspaceID: imported.accountID,
            fallbackEmail: imported.email,
            fallbackPlanType: imported.planType
        )
        authFlowLogger.log("authorizeWorkspaceViaLogin persisted consent workspace directory")
        AuthFlowDebugLog.write("AccountsAuthFlow", "authorizeWorkspaceViaLogin persisted consent workspace directory")
        return imported
    }

    func refreshUsage(
        accountIDs: [String]? = nil,
        force: Bool = false,
        serial: Bool = false,
        onPartialUpdate: (@Sendable ([AccountSummary]) async -> Void)? = nil
    ) async throws -> [AccountSummary] {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        try await reconcilePendingAntigravitySessionIfVerified()
        try await reconcileObservedAntigravitySession(accountIDs: accountIDs)
        let now = dateProvider.unixSecondsNow()
        let snapshot = try storeRepository.loadStore()
        let authRepository = self.authRepository
        let usageService = self.usageService
        let targetIDSet = accountIDs.map(Set.init)
        let refreshTargets = snapshot.accounts.filter { account in
            guard account.provider == .codex || account.provider == .antigravity else { return false }
            guard account.displayStatus != .deleted, account.displayStatus != .pending else { return false }
            guard let targetIDSet else { return true }
            return targetIDSet.contains(account.id)
        }

        guard !refreshTargets.isEmpty else {
            return snapshot.accountSummaries()
        }

        var latest = snapshot
        let antigravityUsageService = self.antigravityUsageService
        let antigravityAuthRepository = self.antigravityAuthRepository
        // OAuth clients are scoped to the account being refreshed. Borrowing a
        // client/token-shaped object from an arbitrary saved account risks
        // crossing identities and must not occur.
        let antigravityClientFallback: JSONValue? = nil
        if serial {
            for account in refreshTargets {
                if account.provider == .antigravity {
                    latest = try await refreshAntigravityAccountExclusively(
                        id: account.id,
                        now: now,
                        force: force
                    )
                } else {
                    let refreshed = try await Self.refreshAccount(
                        account,
                        now: now,
                        forceRefresh: force,
                        authRepository: authRepository,
                        usageService: usageService,
                        antigravityUsageService: antigravityUsageService,
                        antigravityClientFallback: antigravityClientFallback
                    )
                    latest = try Self.mergeRefreshedAccount(
                        refreshed,
                        using: storeRepository,
                        authRepository: authRepository,
                        antigravityAuthRepository: antigravityAuthRepository
                    )
                }
                if let onPartialUpdate {
                    await onPartialUpdate(
                        latest.accountSummaries()
                    )
                }
            }
        } else {
            let codexTargets = refreshTargets.filter { $0.provider == .codex }
            try await withThrowingTaskGroup(of: AccountUsageRefreshResult.self, returning: Void.self) { group in
                for account in codexTargets {
                    group.addTask {
                        try await Self.refreshAccount(
                            account,
                            now: now,
                            forceRefresh: force,
                            authRepository: authRepository,
                            usageService: usageService,
                            antigravityUsageService: antigravityUsageService,
                            antigravityClientFallback: antigravityClientFallback
                        )
                    }
                }
                for try await refreshed in group {
                    latest = try Self.mergeRefreshedAccount(
                        refreshed,
                        using: storeRepository,
                        authRepository: authRepository,
                        antigravityAuthRepository: antigravityAuthRepository
                    )
                    if let onPartialUpdate {
                        await onPartialUpdate(
                            latest.accountSummaries()
                        )
                    }
                }
            }
            for account in refreshTargets where account.provider == .antigravity {
                latest = try await refreshAntigravityAccountExclusively(
                    id: account.id,
                    now: now,
                    force: force
                )
                if let onPartialUpdate {
                    await onPartialUpdate(
                        latest.accountSummaries()
                    )
                }
            }
        }

        return latest.accountSummaries()
    }

    /// Checks provider quota without sending an inference request. Only provider
    /// usage evidence can start a countdown; reading quota is not activation.
    @discardableResult
    func checkQuotaWindows(accountIDs: [String]) async throws -> [AccountSummary] {
        guard !accountIDs.isEmpty else {
            return try await listAccounts(refreshWorkspaceMetadata: false)
        }
        return try await refreshUsage(accountIDs: accountIDs, force: true, serial: false)
    }

    /// AntiGravity OAuth refreshes are account-store transactions rather than
    /// just writes guarded by a post-hoc CAS. Re-read inside the shared gate so
    /// a second caller never exchanges the grant snapshot that the first caller
    /// is rotating. Pending reconciliation deliberately remains outside this
    /// helper because it already owns the same gate.
    private func refreshAntigravityAccountExclusively(
        id: String,
        now: Int64,
        force: Bool
    ) async throws -> AccountsStore {
        try await withExclusiveAntigravityOperation {
            try Task.checkCancellation()
            let latestStore = try storeRepository.loadStore()
            guard let account = latestStore.accounts.first(where: {
                $0.id == id
                    && $0.provider == .antigravity
                    && $0.displayStatus != .deleted
                    && $0.displayStatus != .pending
            }) else {
                return latestStore
            }
            let refreshed = try await Self.refreshAccount(
                account,
                now: now,
                forceRefresh: force,
                authRepository: authRepository,
                usageService: usageService,
                antigravityUsageService: antigravityUsageService,
                antigravityClientFallback: nil
            )
            try Task.checkCancellation()
            return try Self.mergeRefreshedAccount(
                refreshed,
                using: storeRepository,
                authRepository: authRepository,
                antigravityAuthRepository: antigravityAuthRepository
            )
        }
    }

    /// Observe external native sign-ins without importing a grant or switching
    /// the provider. A transport/identity failure leaves the last marker alone;
    /// a verified different identity must not leave the wrong card disabled.
    private func reconcileObservedAntigravitySession(accountIDs: [String]?) async throws {
        try await withExclusiveAntigravityOperation {
            guard let antigravityUsageService else { return }
            let baseline = try storeRepository.loadStore()
            let targets = accountIDs.map(Set.init)
            guard baseline.pendingAntigravityAccountID == nil,
                  baseline.accounts.contains(where: {
                      $0.provider == .antigravity && $0.displayStatus != .deleted && $0.displayStatus != .pending
                          && (targets?.contains($0.id) ?? true)
                  })
            else { return }
            let native: AntigravityNativeUsageResult
            do {
                native = try await antigravityUsageService.fetchCurrentNativeUsage()
            } catch is CancellationError {
                throw CancellationError()
            } catch { return }
            try Task.checkCancellation()
            let now = dateProvider.unixSecondsNow()
            var preview = baseline
            guard AntigravityObservedSelection.reconcile(store: &preview, baseline: baseline, native: native, now: now)
            else { return }
            _ = try storeRepository.mutateStore { latest in
                _ = AntigravityObservedSelection.reconcile(store: &latest, baseline: baseline, native: native, now: now)
            }
        }
    }

    /// A pending native switch is intentionally inert while AntiGravity is
    /// closed. On a later refresh, a running language server can promote it
    /// only after the exact e-mail and complete quota summary are verified.
    /// This performs no process launch, quit, or credential write.
    private func reconcilePendingAntigravitySessionIfVerified() async throws {
        try await withExclusiveAntigravityOperation {
            try Task.checkCancellation()
            guard let antigravityUsageService else { return }
            let store = try storeRepository.loadStore()
            guard let pendingID = store.pendingAntigravityAccountID,
                  let account = store.accounts.first(where: {
                      $0.id == pendingID && $0.provider == .antigravity
                  }),
                  let expectedEmail = account.email?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !expectedEmail.isEmpty
            else {
                return
            }

            let native: AntigravityNativeUsageResult
            do {
                native = try await antigravityUsageService.fetchNativeUsage(expectedEmail: expectedEmail)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return
            }
            try Task.checkCancellation()
            guard native.usage.isVerifiedForSwitch else { return }

            // Pending-session reconciliation is a background observation. The
            // matching local RPC identity and authoritative quota are enough
            // to promote the pending marker; it must not read a native secret
            // in order to synchronize a portable grant.
            try Task.checkCancellation()

            do {
                try commitCurrentAntigravityProjection(
                    account: account,
                    native: native,
                    expectedAuthJSON: account.authJSON,
                    expectedPendingAccountID: pendingID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The pending marker or credential changed during readback;
                // that newer transaction owns the state and must not be
                // promoted by this stale observation.
            }
        }
    }

    func refreshWorkspaceMetadata(forceRemoteCheck: Bool) async throws -> [AccountSummary] {
        guard runtimePlatform == .macOS else {
            throw AppError.invalidData(PlatformCapabilities.unsupportedOperationMessage)
        }
        var store = try storeRepository.loadStore()
        let metadataBaseline = store
        let didChange = try await enrichStoredWorkspaceMetadataIfNeeded(
            in: &store,
            forceRemoteCheck: forceRemoteCheck
        )
        if didChange {
            store = try applyWorkspaceMetadataChanges(
                from: store,
                relativeTo: metadataBaseline
            )
        } else {
            store = try storeRepository.loadStore()
        }
        return store.accountSummaries()
    }

    /// Applies only the Codex workspace metadata fields produced by a
    /// suspended remote lookup. It never replaces the full store, so a native
    /// AntiGravity marker/pending state or a newly rotated credential written
    /// while the lookup was in flight survives unchanged.
    private func applyWorkspaceMetadataChanges(
        from proposed: AccountsStore,
        relativeTo baseline: AccountsStore
    ) throws -> AccountsStore {
        try storeRepository.mutateStore { latest in
            for baselineAccount in baseline.accounts where baselineAccount.provider == .codex {
                guard let proposedAccount = proposed.accounts.first(where: { $0.id == baselineAccount.id }),
                      let latestIndex = latest.accounts.firstIndex(where: {
                          $0.id == baselineAccount.id && $0.provider == .codex
                      }) else {
                    continue
                }
                if proposedAccount.teamName != baselineAccount.teamName {
                    latest.accounts[latestIndex].teamName = proposedAccount.teamName
                }
                if proposedAccount.workspaceStatus != baselineAccount.workspaceStatus {
                    latest.accounts[latestIndex].workspaceStatus = proposedAccount.workspaceStatus
                }
            }
        }
    }

    private func resolvedAntigravityAuthRepository() throws -> AntigravityAuthRepository {
        guard let antigravityAuthRepository else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.auth_file_not_found"))
        }
        return antigravityAuthRepository
    }

    private func importNativeAntigravitySession(
        _ native: AntigravityNativeUsageResult,
        customLabel: String?,
        usageService: AntigravityUsageService
    ) async throws -> AccountSummary {
        // A verified native identity is enough to construct a temporary
        // non-portable marker, but an explicit Add/Import/Reauthenticate
        // operation must stop if macOS cancels or denies the one permitted
        // native credential read. Silently succeeding after a denial makes the
        // user think the requested authorization was completed and used to
        // re-enter the polling loop on a later action.
        var authJSON = JSONValue.object([
            "native_session": .bool(true),
            "email": .string(native.email),
            "plan_type": native.planType.map(JSONValue.string) ?? .null
        ])
        let repository: AntigravityAuthRepository?
        do {
            repository = try resolvedAntigravityAuthRepository()
        } catch {
            repository = nil
        }
        if let repository {
            do {
                let verified = try await usageService.verifyCurrentNativeCredential(
                    repository: repository,
                    matchingNativeEmail: native.email,
                    credentialAccess: .userInitiated
                )
                try Task.checkCancellation()
                // A saved switch credential is retained only after userinfo and
                // the native RPC agree on the exact account identity.
                authJSON = verified.authJSON
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as AntigravityNativeCredentialAccessError {
                if error.stopsAutomaticRetry {
                    throw error
                }
            } catch {
                // The verified native marker above is the non-portable fallback.
            }
        }
        try Task.checkCancellation()
        return try await importAccount(
            authJSON: authJSON,
            customLabel: customLabel,
            provider: .antigravity,
            prefetchedUsage: native.usage,
            markAntigravityCurrent: true
        )
    }

    /// The service waits read-only for the app's local language server, then
    /// makes one Login RPC. It must not retry a Login failure here: a retry
    /// could open a second browser OAuth flow after the first endpoint was
    /// already confirmed.
    private func beginNativeBrowserLogin(
        using usageService: AntigravityUsageService,
        timeoutSeconds: TimeInterval
    ) async throws {
        try Task.checkCancellation()
        try await usageService.beginNativeBrowserLogin(
            readinessTimeout: min(max(1, timeoutSeconds), 35),
            responseTimeout: max(1, timeoutSeconds)
        )
    }

    private func importAccount(
        authJSON: JSONValue,
        customLabel: String?,
        prefetchedWorkspaceName: String? = nil,
        provider: AccountProvider = .codex,
        prefetchedUsage: UsageSnapshot? = nil,
        markAntigravityCurrent: Bool = false
    ) async throws -> AccountSummary {
        authFlowLogger.log("importAccount started")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount started")
        let now = dateProvider.unixSecondsNow()
        var authJSON = authJSON
        let resolvedProvider: AccountProvider = provider == .antigravity
            || AntigravityAuthRepository.looksLikeGeminiOAuth(authJSON)
            ? .antigravity
            : .codex
        var extracted = resolvedProvider == .antigravity
            ? try resolvedAntigravityAuthRepository().extractAuth(from: authJSON)
            : try authRepository.extractAuth(from: authJSON)
        authFlowLogger.log("importAccount extracted account \(extracted.accountID, privacy: .public)")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount extracted account \(extracted.accountID)")

        var usage: UsageSnapshot? = prefetchedUsage
        var usageError: String?

        if runtimePlatform == .macOS, resolvedProvider == .codex {
            do {
                authFlowLogger.log("importAccount fetching usage snapshot")
                AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount fetching usage snapshot")
                let refreshed = try await Self.fetchUsageSnapshot(
                    authJSON: authJSON,
                    authRepository: authRepository,
                    usageService: usageService,
                    now: now
                )
                authJSON = refreshed.authJSON
                extracted = refreshed.extractedAuth
                usage = refreshed.usage
                authFlowLogger.log("importAccount usage snapshot fetched for \(extracted.accountID, privacy: .public)")
                AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount usage snapshot fetched for \(extracted.accountID)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let deactivatedError = AppError.workspaceDeactivatedIfMatched(error) {
                    throw deactivatedError
                }
                usageError = error.localizedDescription
                authFlowLogger.error("importAccount usage snapshot failed: \(error.localizedDescription, privacy: .public)")
                AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount usage snapshot failed: \(error.localizedDescription)")
            }
        } else if runtimePlatform == .macOS, resolvedProvider == .antigravity,
                  usage == nil, let antigravityUsageService {
            do {
                let refreshed = try await antigravityUsageService.fetchUsage(
                    authJSON: authJSON,
                    clientFallback: nil,
                    expectedEmail: extracted.email
                )
                // A profile-bound refresh can rotate the portable grant even
                // when this import only needs a quota snapshot. Keep that
                // verified result so a repeated import never discards a newer
                // refresh token in favor of the preflight input.
                authJSON = refreshed.authJSON
                extracted = try resolvedAntigravityAuthRepository().extractAuth(from: authJSON)
                usage = refreshed.usage
                extracted.planType = refreshed.planType ?? extracted.planType
            } catch let error as AntigravityCredentialRefreshFailure {
                // OAuth and userinfo verification already completed; retain the
                // rotated, identity-bound grant even when remote quota fails.
                authJSON = error.verifiedAuthJSON
                extracted = try resolvedAntigravityAuthRepository().extractAuth(from: authJSON)
                usageError = Self.userFacingUsageErrorMessage(for: error.underlying)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                usageError = error.localizedDescription
            }
        }

        if let prefetchedWorkspaceName {
            extracted.teamName = prefetchedWorkspaceName
        } else if resolvedProvider == .codex,
                  runtimePlatform == .macOS,
                  let workspaceMetadataService,
                  shouldLookupRemoteWorkspaceMetadata(extracted: extracted) {
            authFlowLogger.log("importAccount fetching workspace metadata")
            AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount fetching workspace metadata")
            do {
                let directory = try await workspaceMetadataService.fetchWorkspaceMetadata(
                    accessToken: extracted.accessToken
                )
                if let remoteWorkspaceName = Self.remoteWorkspaceName(
                    for: extracted.accountID,
                    in: directory
                ) {
                    extracted.teamName = remoteWorkspaceName
                }
                authFlowLogger.log("importAccount workspace metadata fetched")
                AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount workspace metadata fetched")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if let deactivatedError = AppError.workspaceDeactivatedIfMatched(error) {
                    throw deactivatedError
                }
                authFlowLogger.error("importAccount workspace metadata failed: \(error.localizedDescription, privacy: .public)")
                AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount workspace metadata failed: \(error.localizedDescription)")
            }
        }

        try Task.checkCancellation()
        let generatedLabel = customLabel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedLabel = generatedLabel?.isEmpty == false ? generatedLabel : nil
        let label = requestedLabel
            ?? (extracted.email ?? "\(resolvedProvider == .antigravity ? "AntiGravity" : "Codex") \(String(extracted.accountID.prefix(8)))")

        var store = try storeRepository.loadStore()
        authFlowLogger.log("importAccount loaded store with \(store.accounts.count) accounts")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount loaded store with \(store.accounts.count) accounts")
        let account = StoredAccount(
            id: UUID().uuidString,
            label: label,
            email: extracted.email,
            accountID: extracted.accountID,
            planType: extracted.planType,
            teamName: extracted.teamName,
            teamAlias: nil,
            authJSON: authJSON,
            addedAt: now,
            updatedAt: now,
            usage: usage,
            usageError: usageError,
            usageStateUpdatedAt: usage == nil && usageError == nil ? 0 : now,
            workspaceStatus: .active,
            principalID: extracted.principalID,
            provider: resolvedProvider
        )

        // A native import's identity comes from local-RPC/userinfo verification.
        // AntiGravity's historical opaque subject accountID and its current
        // e-mail accountID therefore must converge by provider + verified
        // e-mail, rather than the generic accountID key.  This also repairs a
        // previous duplicate import atomically, keeping the earliest card ID
        // and its user-provided label/alias.
        let mayMergeAntigravityByVerifiedEmail = resolvedProvider == .antigravity
            && (markAntigravityCurrent || AntigravityAuthRepository.isNativeVerifiedCredential(authJSON))
        let matchingIndices: [Int]
        if mayMergeAntigravityByVerifiedEmail {
            let emailMatches = AccountIdentity.antigravityEmailMatchIndices(
                for: extracted,
                in: store.accounts
            )
            matchingIndices = emailMatches.isEmpty
                ? Self.matchingStoredAccountIndex(for: extracted, in: store.accounts).map { [$0] } ?? []
                : emailMatches
        } else {
            matchingIndices = Self.matchingStoredAccountIndex(for: extracted, in: store.accounts).map { [$0] } ?? []
        }

        let savedAccountID: String
        if let existingIndex = matchingIndices.min(by: { lhs, rhs in
            let left = store.accounts[lhs]
            let right = store.accounts[rhs]
            if left.addedAt != right.addedAt {
                return left.addedAt < right.addedAt
            }
            return lhs < rhs
        }) {
            let duplicateIndices = matchingIndices.filter { $0 != existingIndex }
            let duplicateAccounts = duplicateIndices.map { store.accounts[$0] }
            var existing = store.accounts[existingIndex]
            if requestedLabel != nil {
                existing.label = account.label
            }
            if existing.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let preservedLabel = duplicateAccounts
                .map(\.label)
                .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                existing.label = preservedLabel
            }
            existing.email = account.email ?? existing.email
            // The card ID remains stable, while the verified e-mail becomes
            // the canonical account identity for subsequent imports.
            existing.accountID = account.accountID
            existing.planType = account.planType ?? existing.planType
            if let teamName = WorkspaceDisplayName.normalized(from: account.teamName) {
                existing.teamName = teamName
            } else if existing.teamName == nil {
                existing.teamName = duplicateAccounts.compactMap(\.teamName).first
            }
            let importingNativeMarker = resolvedProvider == .antigravity
                && authJSON["native_session"]?.boolValue == true
            // A local-RPC import that could not read Keychain is evidence of
            // the *current* identity, not a replacement for a previously saved
            // portable OAuth credential. Keep the latter so a later native
            // transaction can still switch back to this account.
            if !importingNativeMarker {
                existing.authJSON = account.authJSON
            } else if existing.authJSON["native_session"]?.boolValue == true,
                      let savedPortableCredential = duplicateAccounts.first(where: {
                          $0.authJSON["native_session"]?.boolValue != true
                      })?.authJSON {
                existing.authJSON = savedPortableCredential
            }
            existing.updatedAt = now
            if let usage {
                existing.usage = usage
                existing.usageError = usageError
                existing.usageStateUpdatedAt = now
            } else if let usageError {
                existing.usageError = usageError
                existing.usageStateUpdatedAt = now
            } else if existing.usage == nil,
                      let duplicateUsage = duplicateAccounts
                        .sorted(by: { $0.usageStateUpdatedAt > $1.usageStateUpdatedAt })
                        .first(where: { $0.usage != nil }) {
                existing.usage = duplicateUsage.usage
                existing.usageError = duplicateUsage.usageError
                existing.usageStateUpdatedAt = duplicateUsage.usageStateUpdatedAt
            }
            existing.workspaceStatus = .active
            existing.principalID = extracted.principalID ?? existing.principalID
            existing.provider = resolvedProvider
            store.accounts[existingIndex] = existing

            let mergedAwayIDs = Set(duplicateAccounts.map(\.id))
            if let currentID = store.currentAntigravityAccountID,
               mergedAwayIDs.contains(currentID) {
                store.currentAntigravityAccountID = existing.id
            }
            if let pendingID = store.pendingAntigravityAccountID,
               mergedAwayIDs.contains(pendingID) {
                store.pendingAntigravityAccountID = existing.id
            }
            for duplicateIndex in duplicateIndices.sorted(by: >) {
                store.accounts.remove(at: duplicateIndex)
            }
            savedAccountID = existing.id
        } else {
            store.accounts.append(account)
            savedAccountID = account.id
        }
        if resolvedProvider == .codex {
            store.workspaceDirectory.removeAll {
                AccountIdentity.normalizedAccountID($0.workspaceID)
                    == AccountIdentity.normalizedAccountID(extracted.accountID)
            }
        } else if markAntigravityCurrent {
            store.currentAntigravityAccountID = savedAccountID
            store.pendingAntigravityAccountID = nil
        }
        authFlowLogger.log("importAccount saving store")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount saving store")
        try Task.checkCancellation()
        try storeRepository.saveStore(store)
        authFlowLogger.log("importAccount saved store")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount saved store")
        guard let savedAccount = store.accounts.first(where: { $0.id == savedAccountID }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }
        if savedAccount.provider == .codex, store.currentAccountID == savedAccount.id {
            try? authRepository.writeCurrentAuth(savedAccount.authJSON)
        }
        authFlowLogger.log("importAccount persisted current auth if needed")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount persisted current auth if needed")
        authFlowLogger.log("importAccount finished for \(savedAccount.accountID, privacy: .public)")
        AuthFlowDebugLog.write("AccountsAuthFlow", "importAccount finished for \(savedAccount.accountID)")
        return toSummary(savedAccount, in: store)
    }

    func toSummary(_ account: StoredAccount, in store: AccountsStore) -> AccountSummary {
        guard let summary = store.accountSummaries().first(where: { $0.id == account.id }) else {
            preconditionFailure("Account summary requested for an account outside its store")
        }
        return summary
    }

    private func enrichStoredWorkspaceMetadataIfNeeded(
        in store: inout AccountsStore,
        forceRemoteCheck: Bool
    ) async throws -> Bool {
        guard let workspaceMetadataService else { return false }

        var didChange = false
        var cachedDirectories: [String: [WorkspaceMetadata]] = [:]

        for index in store.accounts.indices {
            let storedAccount = store.accounts[index]
            guard storedAccount.displayStatus != .deleted else { continue }
            guard storedAccount.provider != .antigravity else { continue }
            let extracted = try authRepository.extractAuth(from: storedAccount.authJSON)
            guard shouldLookupRemoteWorkspaceMetadata(extracted: extracted) else { continue }
            if !forceRemoteCheck,
               WorkspaceDisplayName.normalized(from: storedAccount.teamName) != nil {
                continue
            }

            let directory: [WorkspaceMetadata]
            if let cached = cachedDirectories[extracted.accessToken] {
                directory = cached
            } else {
                do {
                    let fetched = try await workspaceMetadataService.fetchWorkspaceMetadata(
                        accessToken: extracted.accessToken
                    )
                    cachedDirectories[extracted.accessToken] = fetched
                    directory = fetched
                } catch {
                    if let deactivatedError = AppError.workspaceDeactivatedIfMatched(error) {
                        if store.accounts[index].workspaceStatus != .deactivated {
                            store.accounts[index].workspaceStatus = .deactivated
                            didChange = true
                        }
                        authFlowLogger.error("workspace metadata lookup marked \(storedAccount.accountID, privacy: .public) deactivated: \(deactivatedError.localizedDescription, privacy: .public)")
                        continue
                    }
                    if forceRemoteCheck {
                        throw error
                    }
                    authFlowLogger.error("workspace metadata lookup skipped for \(storedAccount.accountID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continue
                }
            }

            guard let remoteWorkspace = Self.remoteWorkspaceSnapshot(
                for: extracted.accountID,
                in: directory
            ) else { continue }

            if let remoteWorkspaceName = remoteWorkspace.name,
               store.accounts[index].teamName != remoteWorkspaceName {
                store.accounts[index].teamName = remoteWorkspaceName
                didChange = true
            }

            if store.accounts[index].workspaceStatus != remoteWorkspace.status {
                store.accounts[index].workspaceStatus = remoteWorkspace.status
                didChange = true
            }
        }

        return didChange
    }

    private func shouldLookupRemoteWorkspaceMetadata(extracted: ExtractedAuth) -> Bool {
        let normalizedPlan = (extracted.planType ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedPlan == "team" || normalizedPlan == "business" || normalizedPlan == "enterprise"
    }

    private static func refreshAccount(
        _ account: StoredAccount,
        now: Int64,
        forceRefresh: Bool,
        authRepository: AuthRepository,
        usageService: UsageService,
        antigravityUsageService: AntigravityUsageService?,
        antigravityClientFallback: JSONValue?
    ) async throws -> AccountUsageRefreshResult {
        var account = account
        let sourceAuthJSON = account.authJSON
        guard forceRefresh || UsageRefreshPolicy.shouldRefresh(account.usage, now: now) else {
            UsageDebugLog.write(
                "refreshAccount.skip",
                "cardID=\(account.id) accountID=\(account.accountID) existing=\(describeUsage(account.usage))"
            )
            return AccountUsageRefreshResult(account: account, sourceAuthJSON: sourceAuthJSON)
        }

        if account.provider == .antigravity {
            guard let antigravityUsageService else {
                account.usageError = L10n.tr("error.antigravity.auth_file_not_found")
                account.usageStateUpdatedAt = now
                return AccountUsageRefreshResult(account: account, sourceAuthJSON: sourceAuthJSON)
            }
            do {
                let refreshed = try await antigravityUsageService.fetchUsage(
                    authJSON: account.authJSON,
                    clientFallback: antigravityClientFallback,
                    expectedEmail: account.email
                )
                let refreshedAuth = refreshed.authJSON
                // Background quota work uses only native RPC identity/quota
                // and this card's own verified remote grant. In particular it
                // never reads Keychain or FileTokenStorage, and a native
                // re-login cannot be silently promoted into a saved grant.
                // A remote availability-only response cannot erase a last known
                // verified native four-bucket snapshot for a non-current card.
                let reconciledUsage = QuotaCountdownState.reconcile(
                    previous: account.usage,
                    refreshed: refreshed.usage,
                    observedAt: refreshed.usage.fetchedAt > 0 ? refreshed.usage.fetchedAt : now
                )
                if reconciledUsage.hasAuthoritativeQuota {
                    account.authJSON = refreshedAuth
                    account.usage = reconciledUsage
                    account.usageError = nil
                } else if account.usage?.hasAuthoritativeQuota == true {
                    account.usageError = L10n.tr("error.antigravity.remote_quota_unavailable")
                } else {
                    account.authJSON = refreshedAuth
                    account.usage = reconciledUsage
                    account.usageError = L10n.tr("error.antigravity.remote_quota_unavailable")
                }
                account.usageStateUpdatedAt = now
                if refreshed.usage.hasAuthoritativeQuota {
                    account.planType = refreshed.planType ?? account.planType
                }
                account.workspaceStatus = .active
                if account.displayStatus != .deleted {
                    account.displayStatus = .list
                }
            } catch let error as AntigravityCredentialRefreshFailure {
                // The refresh and userinfo bind already succeeded; quota must
                // not decide whether a rotated grant is retained. The merge
                // below applies this only if the source credential still
                // matches, preventing a stale background request from
                // overwriting a newer reauthentication.
                account.authJSON = error.verifiedAuthJSON
                account.usageError = userFacingUsageErrorMessage(for: error.underlying)
                account.usageStateUpdatedAt = now
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                account.usageError = userFacingUsageErrorMessage(for: error)
                account.usageStateUpdatedAt = now
            }
            account.updatedAt = now
            return AccountUsageRefreshResult(account: account, sourceAuthJSON: sourceAuthJSON)
        }

        do {
            let refreshed = try await fetchUsageSnapshot(
                authJSON: account.authJSON,
                authRepository: authRepository,
                usageService: usageService,
                now: now
            )
            account.authJSON = refreshed.authJSON
            account.usage = QuotaCountdownState.reconcile(
                previous: account.usage,
                refreshed: refreshed.usage,
                observedAt: refreshed.usage.fetchedAt > 0 ? refreshed.usage.fetchedAt : now
            )
            account.usageError = nil
            account.usageStateUpdatedAt = now
            account.planType = refreshed.extractedAuth.planType ?? account.planType
        if let teamName = WorkspaceDisplayName.normalized(from: refreshed.extractedAuth.teamName) {
            account.teamName = teamName
        }
            account.email = refreshed.extractedAuth.email ?? account.email
            account.workspaceStatus = .active
            if account.displayStatus != .deleted {
                account.displayStatus = .list
            }
            account.principalID = refreshed.extractedAuth.principalID
            UsageDebugLog.write(
                "refreshAccount.success",
                "cardID=\(account.id) accountID=\(account.accountID) usage=\(describeUsage(account.usage)) usageStateUpdatedAt=\(account.usageStateUpdatedAt)"
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if let deactivatedError = AppError.workspaceDeactivatedIfMatched(error) {
                account.workspaceStatus = .deactivated
                if account.displayStatus != .deleted {
                    account.displayStatus = .deactivated
                }
                account.usageError = deactivatedError.localizedDescription
            } else {
                account.usageError = userFacingUsageErrorMessage(for: error)
            }
            account.usageStateUpdatedAt = now
            UsageDebugLog.write(
                "refreshAccount.failure",
                "cardID=\(account.id) accountID=\(account.accountID) oldUsage=\(describeUsage(account.usage)) error=\(account.usageError ?? "nil") usageStateUpdatedAt=\(account.usageStateUpdatedAt)"
            )
        }

        account.updatedAt = now
        return AccountUsageRefreshResult(account: account, sourceAuthJSON: sourceAuthJSON)
    }

    private static func mergeRefreshedAccount(
        _ refresh: AccountUsageRefreshResult,
        into store: AccountsStore
    ) -> AccountsStore {
        let refreshed = refresh.account
        var store = store
        store.accounts = store.accounts.map { existing in
            guard existing.id == refreshed.id else { return existing }
            guard existing.provider == refreshed.provider,
                  AccountIdentity.matches(existing, refreshed)
            else {
                return existing
            }
            if refreshed.provider == .antigravity,
               existing.authJSON != refresh.sourceAuthJSON {
                // A login/import/force-refresh changed this card while the
                // remote operation was suspended. Credential equality is the
                // CAS; seconds-resolution updatedAt is insufficient here.
                return existing
            }
            if refreshed.provider != .antigravity,
               existing.updatedAt > refreshed.updatedAt {
                // A newer import/re-authentication won the race. Keep it rather
                // than applying an async refresh built from stale credentials.
                return existing
            }
            var merged = existing
            merged.label = refreshed.label
            merged.email = refreshed.email
            merged.planType = refreshed.planType
            merged.teamName = refreshed.teamName
            merged.teamAlias = refreshed.teamAlias
            if refreshed.provider == .codex
                || (refreshed.provider == .antigravity
                    && refreshed.authJSON["native_session"]?.boolValue != true) {
                merged.authJSON = refreshed.authJSON
            }
            merged.updatedAt = refreshed.updatedAt
            merged.usage = refreshed.usage
            merged.usageError = refreshed.usageError
            merged.usageStateUpdatedAt = refreshed.usageStateUpdatedAt
            merged.workspaceStatus = refreshed.workspaceStatus
            merged.displayStatus = refreshed.displayStatus
            merged.principalID = refreshed.principalID
            return merged
        }
        reconcileWorkspaceDirectory(for: refreshed, in: &store)
        return store
    }

    private static func mergeRefreshedAccount(
        _ refresh: AccountUsageRefreshResult,
        using storeRepository: AccountsStoreRepository,
        authRepository: AuthRepository,
        antigravityAuthRepository: AntigravityAuthRepository?
    ) throws -> AccountsStore {
        let latestStore = try storeRepository.mutateStore { store in
            store = mergeRefreshedAccount(refresh, into: store)
        }
        try persistCurrentAuthIfNeeded(
            refreshedAccount: refresh.account,
            in: latestStore,
            authRepository: authRepository,
            antigravityAuthRepository: antigravityAuthRepository
        )
        return latestStore
    }

    private static func describeUsage(_ usage: UsageSnapshot?) -> String {
        guard let usage else { return "nil" }
        return "fetchedAt=\(usage.fetchedAt) fiveHourUsed=\(describePercent(usage.fiveHour?.usedPercent)) fiveHourReset=\(usage.fiveHour?.resetAt.map(String.init) ?? "nil") oneWeekUsed=\(describePercent(usage.oneWeek?.usedPercent)) oneWeekReset=\(usage.oneWeek?.resetAt.map(String.init) ?? "nil")"
    }

    private static func describePercent(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.2f", value)
    }

    private static func reconcileWorkspaceDirectory(
        for account: StoredAccount,
        in store: inout AccountsStore
    ) {
        guard account.provider == .codex else { return }
        let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(account.accountID)
        guard !normalizedWorkspaceID.isEmpty else { return }

        store.workspaceDirectory.removeAll {
            AccountIdentity.normalizedAccountID($0.workspaceID) == normalizedWorkspaceID
        }
    }

    private static func refreshAuthIfNeeded(
        _ authJSON: JSONValue,
        authRepository: AuthRepository,
        now: Int64
    ) async throws -> JSONValue {
        guard accessTokenIsExpired(in: authJSON, now: now) else {
            return authJSON
        }
        return try await authRepository.refreshChatGPTAuth(authJSON)
    }

    private static func fetchUsageSnapshot(
        authJSON: JSONValue,
        authRepository: AuthRepository,
        usageService: UsageService,
        now: Int64
    ) async throws -> (authJSON: JSONValue, extractedAuth: ExtractedAuth, usage: UsageSnapshot) {
        var authJSON = try await refreshAuthIfNeeded(
            authJSON,
            authRepository: authRepository,
            now: now
        )
        var extracted = try authRepository.extractAuth(from: authJSON)

        do {
            let usage = try await usageService.fetchUsage(
                accessToken: extracted.accessToken,
                accountID: extracted.accountID
            )
            return (authJSON, extracted, usage)
        } catch {
            guard isExpiredAuthenticationError(error) else {
                throw error
            }

            authJSON = try await authRepository.refreshChatGPTAuth(authJSON)
            extracted = try authRepository.extractAuth(from: authJSON)
            let usage = try await usageService.fetchUsage(
                accessToken: extracted.accessToken,
                accountID: extracted.accountID
            )
            return (authJSON, extracted, usage)
        }
    }

    private static func accessTokenIsExpired(in authJSON: JSONValue, now: Int64) -> Bool {
        guard let accessToken = AuthJWTDecoder.tokenObject(from: authJSON)?["access_token"]?.stringValue,
              let claims = try? AuthJWTDecoder.decodePayload(accessToken),
              let expiration = claims["exp"]?.int64Value else {
            return false
        }
        return expiration <= now
    }

    private static func isExpiredAuthenticationError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("provided authentication token is expired")
            || message.contains("token_expired")
            || message.contains("refresh token has already been used")
            || message.contains("signing in again")
    }

    private static func userFacingUsageErrorMessage(for error: Error) -> String {
        if isExpiredAuthenticationError(error) {
            return L10n.tr("error.accounts.sign_in_expired")
        }
        return error.localizedDescription
    }

    private static func persistCurrentAuthIfNeeded(
        refreshedAccount: StoredAccount,
        in store: AccountsStore,
        authRepository: AuthRepository,
        antigravityAuthRepository: AntigravityAuthRepository?
    ) throws {
        if refreshedAccount.provider == .antigravity { return }
        guard store.currentAccountID == refreshedAccount.id else {
            return
        }
        try authRepository.writeCurrentAuth(refreshedAccount.authJSON)
    }

    private static func reconcileStoredAccountMetadata(
        in store: inout AccountsStore,
        authRepository: AuthRepository
    ) -> Bool {
        var didChange = false

        for index in store.accounts.indices {
            let storedAccount = store.accounts[index]
            guard storedAccount.provider != .antigravity else { continue }
            guard let reconciled = try? authRepository.extractAuth(from: storedAccount.authJSON) else {
                continue
            }
            if store.accounts[index].email != reconciled.email {
                store.accounts[index].email = reconciled.email
                didChange = true
            }

            if store.accounts[index].principalID != reconciled.principalID {
                store.accounts[index].principalID = reconciled.principalID
                didChange = true
            }

            if store.accounts[index].planType != reconciled.planType {
                store.accounts[index].planType = reconciled.planType
                didChange = true
            }

            let reconciledTeamName = WorkspaceDisplayName.normalized(from: reconciled.teamName)
            let storedTeamName = WorkspaceDisplayName.normalized(from: store.accounts[index].teamName)
            if let reconciledTeamName, storedTeamName != reconciledTeamName {
                store.accounts[index].teamName = reconciledTeamName
                didChange = true
            }

        }

        if let currentAccountID = store.currentAccountID,
           !store.accounts.contains(where: { $0.id == currentAccountID }) {
            store.currentAccountID = nil
            didChange = true
        }

        if let currentAntigravityAccountID = store.currentAntigravityAccountID,
           !store.accounts.contains(where: {
               $0.id == currentAntigravityAccountID && $0.provider == .antigravity
           }) {
            store.currentAntigravityAccountID = nil
            didChange = true
        }

        if let pendingAntigravityAccountID = store.pendingAntigravityAccountID,
           !store.accounts.contains(where: {
               $0.id == pendingAntigravityAccountID && $0.provider == .antigravity
           }) {
            store.pendingAntigravityAccountID = nil
            didChange = true
        }

        if store.currentAntigravityAccountID != nil,
           store.pendingAntigravityAccountID != nil {
            // A verified current marker is authoritative; never present both
            // states for one native credential store.
            store.pendingAntigravityAccountID = nil
            didChange = true
        }

        return didChange
    }

    private static func remoteWorkspaceName(
        for accountID: String,
        in metadata: [WorkspaceMetadata]
    ) -> String? {
        remoteWorkspaceSnapshot(for: accountID, in: metadata)?.name
    }

    private static func remoteWorkspaceSnapshot(
        for accountID: String,
        in metadata: [WorkspaceMetadata]
    ) -> (name: String?, status: AccountWorkspaceStatus)? {
        guard let match = metadata.first(where: {
            AccountIdentity.normalizedAccountID($0.accountID) == AccountIdentity.normalizedAccountID(accountID)
        }) else {
            return nil
        }

        let trimmedName = WorkspaceDisplayName.normalized(from: match.workspaceName)
        if workspaceMetadataRepresentsInactiveWorkspace(match) {
            return (trimmedName, .deactivated)
        }

        guard let visibleName = visibleWorkspaceName(for: match) else {
            return nil
        }

        return (visibleName, .active)
    }

    private static func visibleWorkspaceName(for metadata: WorkspaceMetadata) -> String? {
        if workspaceMetadataRepresentsInactiveWorkspace(metadata) || workspaceMetadataIsPersonal(metadata) {
            return nil
        }

        guard let trimmedName = WorkspaceDisplayName.normalized(from: metadata.workspaceName) else {
            return nil
        }

        return trimmedName
    }

    private static func workspaceMetadataRepresentsInactiveWorkspace(_ metadata: WorkspaceMetadata) -> Bool {
        let inactiveKeywords = ["deactivat", "disabl", "archiv", "suspend", "inactive", "deleted"]
        return workspaceMetadataContainsAnyKeyword(metadata, keywords: inactiveKeywords)
    }

    private static func workspaceMetadataIsPersonal(_ metadata: WorkspaceMetadata) -> Bool {
        workspaceMetadataContainsAnyKeyword(metadata, keywords: ["personal"])
    }

    private static func workspaceMetadataContainsAnyKeyword(
        _ metadata: WorkspaceMetadata,
        keywords: [String]
    ) -> Bool {
        let searchableFields = [
            metadata.structure,
            metadata.workspaceName
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }

        for field in searchableFields where !field.isEmpty {
            if keywords.contains(where: { field.contains($0) }) {
                return true
            }
        }
        return false
    }

    private func workspaceDirectoryKind(for metadata: WorkspaceMetadata) -> WorkspaceDirectoryKind {
        let normalizedStructure = (metadata.structure ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedStructure == "personal" ? .personal : .workspace
    }

    private static func workspaceDirectoryKind(for account: StoredAccount) -> WorkspaceDirectoryKind {
        WorkspaceDisplayName.normalized(from: account.teamName) == nil ? .personal : .workspace
    }

    private func persistConsentWorkspaceDirectory(
        _ workspaces: [ConsentWorkspaceOption],
        authorizedWorkspaceID: String,
        fallbackEmail: String?,
        fallbackPlanType: String?
    ) throws {
        guard !workspaces.isEmpty else { return }

        var store = try storeRepository.loadStore()
        let now = dateProvider.unixSecondsNow()
        let normalizedAuthorizedWorkspaceID = AccountIdentity.normalizedAccountID(authorizedWorkspaceID)
        let authorizedWorkspaceIDs = Set(
            store.accounts
                .filter { $0.provider == .codex && $0.displayStatus == .list }
                .map { AccountIdentity.normalizedAccountID($0.accountID) }
        )

        var nextEntriesByID = Dictionary(
            uniqueKeysWithValues: store.workspaceDirectory.compactMap { entry -> (String, WorkspaceDirectoryEntry)? in
                let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(entry.workspaceID)
                guard !normalizedWorkspaceID.isEmpty else { return nil }
                guard entry.source != .consent else { return nil }
                return (normalizedWorkspaceID, entry)
            }
        )

        for workspace in workspaces {
            let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspace.workspaceID)
            guard !normalizedWorkspaceID.isEmpty else { continue }

            if normalizedWorkspaceID == normalizedAuthorizedWorkspaceID
                || authorizedWorkspaceIDs.contains(normalizedWorkspaceID) {
                nextEntriesByID.removeValue(forKey: normalizedWorkspaceID)
                continue
            }

            nextEntriesByID[normalizedWorkspaceID] = WorkspaceDirectoryEntry(
                workspaceID: workspace.workspaceID,
                workspaceName: workspace.workspaceName,
                email: fallbackEmail,
                planType: fallbackPlanType,
                kind: workspace.kind,
                source: .consent,
                status: .active,
                visibility: .visible,
                lastSeenAt: now,
                lastStatusCheckedAt: nil
            )
        }

        store.workspaceDirectory = nextEntriesByID.values.sorted { lhs, rhs in
            if lhs.kind != rhs.kind {
                return lhs.kind == .workspace
            }
            let lhsName = lhs.workspaceName ?? ""
            let rhsName = rhs.workspaceName ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
        try storeRepository.saveStore(store)
    }

}
