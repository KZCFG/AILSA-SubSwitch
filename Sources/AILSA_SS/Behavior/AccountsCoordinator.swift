import Foundation

/// Holds the complete native AntiGravity transaction across network/local-RPC
/// awaits. Actor isolation alone is not enough: it is re-entrant at every
/// await and can otherwise let an older switch commit after a newer session.
private actor AntigravityOperationGate {
    private struct Waiter {
        var id: UUID
        var continuation: CheckedContinuation<UInt64, Error>
    }

    private var activeGeneration: UInt64?
    private var nextGeneration: UInt64 = 0
    private var waiters: [Waiter] = []

    func acquire() async throws -> UInt64 {
        try Task.checkCancellation()
        if activeGeneration == nil {
            return issueGeneration()
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: waiterID, continuation: continuation))
                }
            }
        }, onCancel: {
            Task { await self.cancelWaiter(id: waiterID) }
        })
    }

    func release(_ generation: UInt64) {
        guard activeGeneration == generation else { return }
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            let generation = issueGeneration()
            waiter.continuation.resume(returning: generation)
        } else {
            activeGeneration = nil
        }
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func issueGeneration() -> UInt64 {
        nextGeneration &+= 1
        activeGeneration = nextGeneration
        return nextGeneration
    }
}

actor AccountsCoordinator {
    enum UsageRefreshPolicy {
        static let minimumRefreshIntervalSeconds: Int64 = 25

        static func shouldRefresh(_ snapshot: UsageSnapshot?, now: Int64) -> Bool {
            guard let snapshot else { return true }
            return now - snapshot.fetchedAt >= minimumRefreshIntervalSeconds
        }
    }

    let storeRepository: AccountsStoreRepository
    let settingsRepository: SettingsRepository
    let authRepository: AuthRepository
    let usageService: UsageService
    let workspaceMetadataService: WorkspaceMetadataService?
    let chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol
    let codexCLIService: CodexCLIServiceProtocol
    let editorAppService: EditorAppServiceProtocol
    let opencodeAuthSyncService: AILSA_SSAuthSyncServiceProtocol
    let antigravityAuthRepository: AntigravityAuthRepository?
    let antigravityUsageService: AntigravityUsageService?
    let dateProvider: DateProviding
    let runtimePlatform: RuntimePlatform
    private let antigravityOperationGate = AntigravityOperationGate()
    /// A background refresh can report a safe, non-modal explanation to the
    /// tray without treating it as a failed switch or escalating its native
    /// credential authority.
    private var pendingAutoSmartSwitchNotice: String?
    /// A permission/interaction outcome is terminal for this app session.
    /// Subsequent refresh ticks do not probe the Keychain again; an explicit
    /// native action clears the block and is the only route that may show UI.
    private var backgroundAntigravityCredentialBlock: AntigravityNativeCredentialAccessError?

    private var currentAccountProjectionWriter: CurrentAccountProjectionWriter {
        CurrentAccountProjectionWriter(
            storeRepository: storeRepository,
            authRepository: authRepository,
            dateProvider: dateProvider,
            runtimePlatform: runtimePlatform
        )
    }

    init(
        storeRepository: AccountsStoreRepository,
        settingsRepository: SettingsRepository,
        authRepository: AuthRepository,
        usageService: UsageService,
        workspaceMetadataService: WorkspaceMetadataService? = nil,
        chatGPTOAuthLoginService: ChatGPTOAuthLoginServiceProtocol,
        codexCLIService: CodexCLIServiceProtocol,
        editorAppService: EditorAppServiceProtocol,
        opencodeAuthSyncService: AILSA_SSAuthSyncServiceProtocol,
        antigravityAuthRepository: AntigravityAuthRepository? = nil,
        antigravityUsageService: AntigravityUsageService? = nil,
        dateProvider: DateProviding = SystemDateProvider(),
        runtimePlatform: RuntimePlatform = PlatformCapabilities.currentPlatform
    ) {
        self.storeRepository = storeRepository
        self.settingsRepository = settingsRepository
        self.authRepository = authRepository
        self.usageService = usageService
        self.workspaceMetadataService = workspaceMetadataService
        self.chatGPTOAuthLoginService = chatGPTOAuthLoginService
        self.codexCLIService = codexCLIService
        self.editorAppService = editorAppService
        self.opencodeAuthSyncService = opencodeAuthSyncService
        self.antigravityAuthRepository = antigravityAuthRepository
        self.antigravityUsageService = antigravityUsageService
        self.dateProvider = dateProvider
        self.runtimePlatform = runtimePlatform
    }

    func deleteAccount(id: String) throws {
        var store = try storeRepository.loadStore()
        store.accounts.removeAll { $0.id == id }
        if store.currentAccountID == id {
            store.currentAccountID = nil
        }
        if store.currentAntigravityAccountID == id {
            store.currentAntigravityAccountID = nil
        }
        if store.pendingAntigravityAccountID == id {
            store.pendingAntigravityAccountID = nil
        }
        try storeRepository.saveStore(store)
    }

    func listWorkspaceDirectory() throws -> [WorkspaceDirectoryEntry] {
        try storeRepository.loadStore().workspaceDirectory
    }

    func updateWorkspaceDirectoryVisibility(
        workspaceID: String,
        visibility: WorkspaceDirectoryVisibility
    ) throws {
        var store = try storeRepository.loadStore()
        let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspaceID)
        guard !normalizedWorkspaceID.isEmpty else { return }
        guard let index = store.workspaceDirectory.firstIndex(where: {
            AccountIdentity.normalizedAccountID($0.workspaceID) == normalizedWorkspaceID
        }) else {
            return
        }
        store.workspaceDirectory[index].visibility = visibility
        try storeRepository.saveStore(store)
    }

    func updateWorkspaceDirectoryStatus(
        workspaceID: String,
        workspaceName: String,
        email: String?,
        planType: String?,
        kind: WorkspaceDirectoryKind,
        status: WorkspaceDirectoryStatus
    ) throws {
        var store = try storeRepository.loadStore()
        let normalizedWorkspaceID = AccountIdentity.normalizedAccountID(workspaceID)
        guard !normalizedWorkspaceID.isEmpty else { return }
        let now = dateProvider.unixSecondsNow()
        let entry = WorkspaceDirectoryEntry(
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            email: email,
            planType: planType,
            kind: kind,
            source: status == .deactivated ? .deactivated : .consent,
            status: status,
            visibility: .visible,
            lastSeenAt: now,
            lastStatusCheckedAt: now
        )

        if let index = store.workspaceDirectory.firstIndex(where: {
            AccountIdentity.normalizedAccountID($0.workspaceID) == normalizedWorkspaceID
        }) {
            store.workspaceDirectory[index] = entry
        } else {
            store.workspaceDirectory.append(entry)
        }
        try storeRepository.saveStore(store)
    }

    func updateTeamAlias(id: String, alias: String?) throws -> AccountSummary {
        var store = try storeRepository.loadStore()
        guard let index = store.accounts.firstIndex(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }

        store.accounts[index].teamAlias = normalizeTeamAlias(alias)
        store.accounts[index].updatedAt = dateProvider.unixSecondsNow()
        try storeRepository.saveStore(store)

        return toSummary(store.accounts[index], in: store)
    }

    func updateAccountDisplayStatus(id: String, status: AccountDisplayStatus) throws -> AccountSummary {
        var store = try storeRepository.loadStore()
        guard let index = store.accounts.firstIndex(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_update"))
        }

        store.accounts[index].displayStatus = status
        store.accounts[index].updatedAt = dateProvider.unixSecondsNow()
        try storeRepository.saveStore(store)

        return toSummary(store.accounts[index], in: store)
    }

    func switchAccount(
        id: String,
        credentialAccess: AntigravityNativeCredentialAccess = .userInitiated
    ) async throws {
        try AppTerminationSafety.shared.beginAccountSwitch()
        defer { AppTerminationSafety.shared.endAccountSwitch() }
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        if account.provider == .antigravity {
            if credentialAccess == .userInitiated {
                backgroundAntigravityCredentialBlock = nil
            }
            try await withExclusiveAntigravityOperation {
                try Task.checkCancellation()
                let latestStore = try storeRepository.loadStore()
                guard let latestAccount = latestStore.accounts.first(where: {
                    $0.id == id && $0.provider == .antigravity
                }) else {
                    throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
                }
                let settings = try settingsRepository.loadSettings()
                try await updateCurrentAntigravityProjection(
                    account: latestAccount,
                    settings: settings,
                    credentialAccess: credentialAccess
                )
            }
            return
        }
        try updateCurrentAccountProjection(account: account)
    }

    func switchAccountAndApplySettings(
        id: String,
        workspacePath: String? = nil,
        credentialAccess: AntigravityNativeCredentialAccess = .userInitiated
    ) async throws -> SwitchAccountExecutionResult {
        try AppTerminationSafety.shared.beginAccountSwitch()
        defer { AppTerminationSafety.shared.endAccountSwitch() }
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        AccountSwitchDebugLog.write(
            "switchAccountAndApplySettings.begin",
            "requestedCardID=\(id) \(AccountSwitchDebugLog.describe(account: account)) \(AccountSwitchDebugLog.describe(store: store, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
        if account.provider == .antigravity {
            if credentialAccess == .userInitiated {
                backgroundAntigravityCredentialBlock = nil
            }
            return try await withExclusiveAntigravityOperation {
                try Task.checkCancellation()
                let latestStore = try storeRepository.loadStore()
                guard let latestAccount = latestStore.accounts.first(where: {
                    $0.id == id && $0.provider == .antigravity
                }) else {
                    throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
                }
                let settings = try settingsRepository.loadSettings()
                try await updateCurrentAntigravityProjection(
                    account: latestAccount,
                    settings: settings,
                    credentialAccess: credentialAccess
                )
                return try applyAntigravitySwitchSideEffects(for: latestAccount, settings: settings)
            }
        }
        try updateCurrentAccountProjection(account: account)
        let settings = try settingsRepository.loadSettings()
        let result = try applySwitchSideEffects(
            for: account,
            settings: settings,
            workspacePath: workspacePath
        )
        let latestStore = try storeRepository.loadStore()
        let restartedEditorNames = result.restartedEditorApps.map(\.rawValue).joined(separator: ",")
        AccountSwitchDebugLog.write(
            "switchAccountAndApplySettings.end",
            "requestedCardID=\(id) \(AccountSwitchDebugLog.describe(store: latestStore, currentAuthAccountKey: authRepository.currentAuthAccountKey())) opencodeSynced=\(result.opencodeSynced) restartedEditors=\(restartedEditorNames) usedFallbackCLI=\(result.usedFallbackCLI)"
        )
        return result
    }

    func applyCurrentSelection(
        cardID: String,
        selection: CurrentAccountSelection,
        writeAuth: Bool = false
    ) throws {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == cardID }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }
        guard account.provider == .codex else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
        }

        AccountSwitchDebugLog.write(
            "applyCurrentSelection.begin",
            "cardID=\(cardID) selection=\(AccountSwitchDebugLog.describe(selection: selection)) before=\(AccountSwitchDebugLog.describe(store: store, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
        let latestStore = try currentAccountProjectionWriter.apply(
            selection: selection,
            account: account,
            writeAuth: writeAuth
        )
        AccountSwitchDebugLog.write(
            "applyCurrentSelection.end",
            "cardID=\(cardID) after=\(AccountSwitchDebugLog.describe(store: latestStore, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
    }

    func applyCurrentCardID(_ cardID: String) throws {
        let store = try storeRepository.loadStore()
        guard let account = store.accounts.first(where: { $0.id == cardID }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }
        guard account.provider == .codex else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
        }
        let latestStore = try storeRepository.mutateStore { store in
            store.currentAccountID = cardID
        }
        AccountSwitchDebugLog.write(
            "applyCurrentCardID",
            "cardID=\(cardID) after=\(AccountSwitchDebugLog.describe(store: latestStore, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
    }

    func switchAccountAndReload(
        id: String,
        workspacePath: String? = nil,
        credentialAccess: AntigravityNativeCredentialAccess = .userInitiated
    ) async throws -> (
        selectedAccount: AccountSummary,
        accounts: [AccountSummary],
        execution: SwitchAccountExecutionResult
    ) {
        let execution = try await switchAccountAndApplySettings(
            id: id,
            workspacePath: workspacePath,
            credentialAccess: credentialAccess
        )
        let accounts = try await listAccounts(refreshWorkspaceMetadata: false)
        guard let selectedAccount = accounts.first(where: { $0.id == id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }
        AccountSwitchDebugLog.write(
            "switchAccountAndReload.end",
            "requestedCardID=\(id) selected=\(AccountSwitchDebugLog.describe(account: selectedAccount)) \(AccountSwitchDebugLog.describe(accounts: accounts))"
        )
        return (selectedAccount, accounts, execution)
    }

    func smartSwitch(provider: AccountProvider = .codex) async throws -> (AccountSummary, SwitchAccountExecutionResult)? {
        let now = dateProvider.unixSecondsNow()
        let eligible = try await listAccounts(refreshWorkspaceMetadata: false).filter {
            $0.provider == provider && AccountRanking.isEligibleForAutoSwitch($0, now: now)
        }
        guard let best = AccountRanking.pickBestAccount(eligible), !best.isCurrent else {
            // Unknown/stale/error states and an already-best current account
            // must never create a manual native side effect either.
            return nil
        }
        let switchResult = try await switchAccountAndReload(id: best.id)
        return (switchResult.selectedAccount, switchResult.execution)
    }

    func autoSmartSwitchIfNeeded() async throws -> (
        selectedAccount: AccountSummary,
        accounts: [AccountSummary],
        execution: SwitchAccountExecutionResult
    )? {
        pendingAutoSmartSwitchNotice = nil
        let now = dateProvider.unixSecondsNow()
        let allAccounts = try await listAccounts(refreshWorkspaceMetadata: false)
        let settings = try settingsRepository.loadSettings()
        for provider in AccountProvider.allCases {
            let providerEnabled = provider == .codex
                ? settings.autoSmartSwitch
                : settings.autoSmartSwitchAntigravity
            guard providerEnabled else {
                AccountSwitchDebugLog.write(
                    "autoSmartSwitchIfNeeded.disabled",
                    "provider=\(provider.rawValue)"
                )
                continue
            }
            let accounts = allAccounts.filter { $0.provider == provider }
            let decisionLog = AccountSwitchDebugLog.describeAutoSwitch(accounts: accounts)
            AccountSwitchDebugLog.write(
                "autoSmartSwitchIfNeeded.inspect",
                "provider=\(provider.rawValue) \(decisionLog)"
            )
            guard let target = AccountRanking.pickAutoSwitchTarget(accounts, now: now) else {
                AccountSwitchDebugLog.write(
                    "autoSmartSwitchIfNeeded.skip",
                    "provider=\(provider.rawValue) \(decisionLog)"
                )
                continue
            }
            AccountSwitchDebugLog.write(
                "autoSmartSwitchIfNeeded.target",
                "provider=\(provider.rawValue) target=\(AccountSwitchDebugLog.describe(account: target)) \(decisionLog)"
            )
            if provider == .antigravity,
               let blocked = backgroundAntigravityCredentialBlock {
                // A prior marker-only preflight established that this session
                // uses traditional Keychain storage. Do not retry on every
                // refresh; an explicit native action clears this block and may
                // request user authentication if necessary.
                AccountSwitchDebugLog.write(
                    "autoSmartSwitchIfNeeded.antigravity_background_blocked",
                    "target=\(target.id) reason=\(String(describing: blocked))"
                )
                continue
            }
            do {
                let access: AntigravityNativeCredentialAccess = provider == .antigravity
                    ? .background
                    : .userInitiated
                let result = try await switchAccountAndReload(
                    id: target.id,
                    credentialAccess: access
                )
                if provider == .antigravity {
                    backgroundAntigravityCredentialBlock = nil
                }
                return result
            } catch {
                // AntiGravity's native identity guard is intentionally strict.
                // Do not let a background tick promote a mismatched account or
                // repeatedly flap the tray; leave the verified cache intact.
                if provider == .antigravity {
                    if let credentialError = error as? AntigravityNativeCredentialAccessError {
                        let wasAlreadyBlocked = backgroundAntigravityCredentialBlock != nil
                        backgroundAntigravityCredentialBlock = credentialError
                        if !wasAlreadyBlocked {
                            pendingAutoSmartSwitchNotice = L10n.tr(
                                "accounts.notice.antigravity_manual_switch_required"
                            )
                        }
                        AccountSwitchDebugLog.write(
                            "autoSmartSwitchIfNeeded.antigravity_keychain_requires_explicit_action",
                            "target=\(target.id) reason=\(String(describing: credentialError))"
                        )
                        continue
                    }
                    AccountSwitchDebugLog.write(
                        "autoSmartSwitchIfNeeded.antigravity_guarded",
                        "target=\(target.id) error=\(error.localizedDescription)"
                    )
                    continue
                }
                throw error
            }
        }
        return nil
    }

    /// Consumed by the tray after its background refresh. The message is
    /// intentionally generic and never includes an account identity or any
    /// credential detail.
    func consumeAutoSmartSwitchNotice() -> String? {
        defer { pendingAutoSmartSwitchNotice = nil }
        return pendingAutoSmartSwitchNotice
    }

    private func updateCurrentAntigravityProjection(
        account: StoredAccount,
        settings: AppSettings,
        credentialAccess: AntigravityNativeCredentialAccess
    ) async throws {
        try Task.checkCancellation()
        guard account.provider == .antigravity else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }
        guard let antigravityUsageService,
              let expectedEmail = account.email?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedEmail.isEmpty
        else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        // Fast path: the requested account is already the verified native
        // session. No credential write, quit, or launch is needed.
        let native: AntigravityNativeUsageResult?
        do {
            native = try await antigravityUsageService.fetchNativeUsage(expectedEmail: expectedEmail)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            native = nil
        }
        try Task.checkCancellation()
        if let native,
           native.usage.isVerifiedForSwitch {
            let synchronizedAuth: JSONValue?
            if credentialAccess == .userInitiated,
               let antigravityAuthRepository {
                do {
                    let credential = try await antigravityUsageService.verifyCurrentNativeCredential(
                        repository: antigravityAuthRepository,
                        matchingNativeEmail: native.email,
                        credentialAccess: .userInitiated
                    )
                    try Task.checkCancellation()
                    synchronizedAuth = credential.authJSON
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    synchronizedAuth = nil
                }
            } else {
                // A successful native readback can mean the app refreshed its
                // own token. Keep a newly verified native credential when it
                // is available, but do not discard authoritative quota data if
                // optional Keychain/userinfo verification is unavailable.
                synchronizedAuth = nil
            }
            try commitCurrentAntigravityProjection(
                account: account,
                native: native,
                persistedAuthJSON: synchronizedAuth,
                expectedAuthJSON: account.authJSON
            )
            return
        }
        try await switchNativeAntigravitySession(
            account: account,
            expectedEmail: expectedEmail,
            settings: settings,
            usageService: antigravityUsageService,
            credentialAccess: credentialAccess
        )
    }

    func withExclusiveAntigravityOperation<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        let generation = try await antigravityOperationGate.acquire()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            await antigravityOperationGate.release(generation)
            return result
        } catch {
            await antigravityOperationGate.release(generation)
            throw error
        }
    }

    private func applyAntigravitySwitchSideEffects(
        for account: StoredAccount,
        settings: AppSettings
    ) throws -> SwitchAccountExecutionResult {
        // The native transaction has already restored the prior running state
        // or launched the app solely when the dedicated setting allowed it.
        // Never send AntiGravity through the generic force-restart service.
        var result = SwitchAccountExecutionResult.idle
        guard settings.syncOpencodeAntigravityAuth else { return result }

        // The native transaction above is the source of truth for the
        // selected account's current quota. Re-read the committed projection
        // instead of ranking the pre-switch snapshot, which may be stale.
        let store = try storeRepository.loadStore()
        guard let storedAccount = store.accounts.first(where: { $0.id == account.id }),
              let summary = store.accountSummaries().first(where: { $0.id == account.id }) else {
            result.opencodeSyncSkipped = true
            return result
        }
        let now = dateProvider.unixSecondsNow()
        guard AccountRanking.isEligibleForAutoSwitch(summary, now: now),
              AccountRanking.hasUsableQuotaForAutomaticSwitch(summary, now: now)
        else {
            // Unknown, stale, or exhausted 5-hour/7-day data must never
            // replace a working OpenCode account by guesswork.
            result.opencodeSyncSkipped = true
            return result
        }

        do {
            try opencodeAuthSyncService.syncFromAntigravityAuth(storedAccount.authJSON)
            result.opencodeSynced = true
        } catch {
            result.opencodeSyncError = error.localizedDescription
        }
        return result
    }

    /// Performs the actual native AntiGravity account transaction. The primary
    /// store's current marker is deliberately outside this method's write path
    /// until the restarted local language server returns the target identity and
    /// a complete, authoritative quota summary.
    private func switchNativeAntigravitySession(
        account: StoredAccount,
        expectedEmail: String,
        settings: AppSettings,
        usageService: AntigravityUsageService,
        credentialAccess: AntigravityNativeCredentialAccess
    ) async throws {
        try Task.checkCancellation()
        guard let antigravityAuthRepository else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
        }

        // Reject all deterministic credential failures before inspecting or
        // changing the running app. In particular, a stale saved access token
        // must not cause us to quit the currently authenticated native editor
        // merely to discover that it cannot be staged.
        let stagedAuthJSON = try await usageService.refreshStoredCredentialIfNeeded(account.authJSON)
        try Task.checkCancellation()
        try antigravityAuthRepository.validateNativeSwitchCredential(stagedAuthJSON)

        // The marker/snapshot preflight happens before querying or changing the
        // native process. Background Keychain access runs only in the quiet
        // child, and a read/write permission failure stops before native quits.
        let snapshot = try antigravityAuthRepository.nativeCredentialSnapshot(access: credentialAccess)
        try antigravityAuthRepository.preflightNativeCredentialTransaction(
            snapshot,
            access: credentialAccess
        )
        try Task.checkCancellation()
        let wasRunning = editorAppService.isAppRunning(.antigravity)

        // A stopped app has no local RPC to prove the staged account. When the
        // user disabled launch-after-switch, prepare the verified credential
        // for the next native launch and record an explicit pending state. Do
        // not retain a stale "current" marker or claim the app is running.
        if !wasRunning && !settings.launchAntigravityAfterSwitch {
            var staged = false
            do {
                try Task.checkCancellation()
                staged = true
                do {
                    try antigravityAuthRepository.stageNativeAuth(
                        stagedAuthJSON,
                        preserving: snapshot,
                        access: credentialAccess
                    )
                } catch let error as AntigravityNativeCredentialAccessError
                    where error == .nativeCredentialStorageModeChanged {
                    // `stageNativeAuth` checks this before writing, so recovery
                    // must not rewrite bytes in a mode native just changed.
                    staged = false
                    throw error
                }
                try Task.checkCancellation()
                try commitPendingAntigravityProjection(
                    account: account,
                    stagedAuthJSON: stagedAuthJSON,
                    expectedAuthJSON: account.authJSON
                )
                return
            } catch let originalError {
                if staged {
                    do {
                        try antigravityAuthRepository.restoreNativeCredentials(
                            snapshot,
                            access: credentialAccess
                        )
                    } catch let rollbackError {
                        throw rollbackError
                    }
                }
                throw originalError
            }
        }

        let originalNative: AntigravityNativeUsageResult?
        do {
            originalNative = try await usageService.fetchCurrentNativeUsage()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            originalNative = nil
        }
        try Task.checkCancellation()
        let originalEmail = originalNative?.email
        var stageAttempted = false

        do {
            // Recheck immediately before an app quit. Native owns the marker,
            // so a storage-mode flip is a no-side-effect exit rather than a
            // best-effort write into whichever backend used to be selected.
            try antigravityAuthRepository.preflightNativeCredentialTransaction(
                snapshot,
                access: credentialAccess
            )
            if wasRunning {
                try Task.checkCancellation()
                let quit = editorAppService.quitAppGracefully(
                    .antigravity,
                    timeoutSeconds: 20
                )
                guard quit.didQuit else {
                    throw AppError.io(quit.error ?? L10n.tr("error.antigravity.native_session_unavailable"))
                }
            }

            try Task.checkCancellation()
            stageAttempted = true
            do {
                try antigravityAuthRepository.stageNativeAuth(
                    stagedAuthJSON,
                    preserving: snapshot,
                    access: credentialAccess
                )
            } catch let error as AntigravityNativeCredentialAccessError
                where error == .nativeCredentialStorageModeChanged {
                // No bytes were written: `stageNativeAuth` checks the marker
                // first. The outer recovery only relaunches a process that was
                // already stopped by us.
                stageAttempted = false
                throw error
            }
            try Task.checkCancellation()

            let launch = editorAppService.launchApp(.antigravity)
            guard launch.launched else {
                throw AppError.io(launch.error ?? L10n.tr("error.antigravity.native_session_unavailable"))
            }
            try Task.checkCancellation()

            let native = try await waitForVerifiedNativeUsage(
                expectedEmail: expectedEmail,
                usageService: usageService,
                timeoutSeconds: 35
            )
            try Task.checkCancellation()
            try commitCurrentAntigravityProjection(
                account: account,
                native: native,
                persistedAuthJSON: stagedAuthJSON,
                expectedAuthJSON: account.authJSON
            )
        } catch {
            if stageAttempted {
                // A cancelled switch must still restore native bytes and the
                // previous process state. Run recovery from a fresh task so
                // Task.checkCancellation in its readback wait is not poisoned
                // by the caller's cancellation flag.
                let rollbackTask = Task.detached { [self, snapshot, wasRunning, originalEmail, usageService, antigravityAuthRepository, credentialAccess] in
                    await self.rollbackNativeAntigravitySession(
                        snapshot: snapshot,
                        wasRunning: wasRunning,
                        originalEmail: originalEmail,
                        usageService: usageService,
                        authRepository: antigravityAuthRepository,
                        credentialAccess: credentialAccess
                    )
                }
                if let rollbackError = await rollbackTask.value {
                    throw rollbackError
                }
            } else if wasRunning, !editorAppService.isAppRunning(.antigravity) {
                // No credentials were written, but a graceful quit succeeded
                // before a later preflight error. Restore the previous process
                // state without touching any credential storage.
                _ = editorAppService.launchApp(.antigravity)
            }
            throw error
        }
    }

    private func waitForVerifiedNativeUsage(
        expectedEmail: String,
        usageService: AntigravityUsageService,
        timeoutSeconds: TimeInterval
    ) async throws -> AntigravityNativeUsageResult {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        var lastError: Error = AppError.network(L10n.tr("error.antigravity.native_quota_unavailable"))
        while Date() < deadline {
            try Task.checkCancellation()
            do {
                let native = try await usageService.fetchNativeUsage(expectedEmail: expectedEmail)
                guard native.usage.isVerifiedForSwitch else {
                    lastError = AppError.invalidData(L10n.tr("error.antigravity.native_quota_unavailable"))
                    continue
                }
                return native
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .seconds(1))
        }
        throw lastError
    }

    /// Stops a failed target normally before restoring bytes, then restores the
    /// original process state. Returning an error prevents the caller from
    /// reporting a clean rollback that could not be verified.
    private func rollbackNativeAntigravitySession(
        snapshot: AntigravityNativeCredentialSnapshot,
        wasRunning: Bool,
        originalEmail: String?,
        usageService: AntigravityUsageService,
        authRepository: AntigravityAuthRepository,
        credentialAccess: AntigravityNativeCredentialAccess
    ) async -> Error? {
        if editorAppService.isAppRunning(.antigravity) {
            let quit = editorAppService.quitAppGracefully(.antigravity, timeoutSeconds: 20)
            guard quit.didQuit else {
                return AppError.io(quit.error ?? L10n.tr("error.antigravity.native_session_unavailable"))
            }
        }

        do {
            try authRepository.restoreNativeCredentials(
                snapshot,
                access: credentialAccess
            )
        } catch {
            return error
        }

        guard wasRunning else { return nil }
        let launch = editorAppService.launchApp(.antigravity)
        guard launch.launched else {
            return AppError.io(launch.error ?? L10n.tr("error.antigravity.native_session_unavailable"))
        }
        guard let originalEmail else {
            return AppError.network(L10n.tr("error.antigravity.native_session_unavailable"))
        }
        do {
            _ = try await waitForVerifiedNativeUsage(
                expectedEmail: originalEmail,
                usageService: usageService,
                timeoutSeconds: 35
            )
        } catch {
            return error
        }
        return nil
    }

    func commitCurrentAntigravityProjection(
        account: StoredAccount,
        native: AntigravityNativeUsageResult,
        persistedAuthJSON: JSONValue? = nil,
        expectedAuthJSON: JSONValue? = nil,
        expectedPendingAccountID: String? = nil
    ) throws {
        guard native.usage.isVerifiedForSwitch else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_quota_unavailable"))
        }
        let now = dateProvider.unixSecondsNow()
        _ = try storeRepository.mutateStore { store in
            guard let index = store.accounts.firstIndex(where: { $0.id == account.id }),
                  store.accounts[index].provider == .antigravity,
                  AccountIdentity.normalizedEmail(store.accounts[index].email)
                    == AccountIdentity.normalizedEmail(account.email),
                  AccountIdentity.normalizedAccountID(store.accounts[index].accountID)
                    == AccountIdentity.normalizedAccountID(account.accountID)
            else {
                throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
            }
            if let expectedAuthJSON,
               store.accounts[index].authJSON != expectedAuthJSON {
                throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
            }
            if let expectedPendingAccountID,
               (store.pendingAntigravityAccountID != expectedPendingAccountID
                    || store.currentAntigravityAccountID != nil) {
                throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
            }
            // Switch/import commits reach this write only after identity and
            // complete quota readback. Read-only external-session observation
            // can separately synchronize the marker without changing grants.
            store.currentAntigravityAccountID = account.id
            store.pendingAntigravityAccountID = nil
            if let persistedAuthJSON {
                store.accounts[index].authJSON = persistedAuthJSON
            }
            store.accounts[index].usage = native.usage
            store.accounts[index].usageError = nil
            store.accounts[index].usageStateUpdatedAt = now
            store.accounts[index].planType = native.planType ?? store.accounts[index].planType
            store.accounts[index].updatedAt = now
        }
    }

    /// Records an offline native switch preparation. The native credentials are
    /// already staged, but no running process has proven them yet; therefore
    /// `currentAntigravityAccountID` must remain nil until a later local-RPC
    /// identity plus complete quota readback succeeds.
    func commitPendingAntigravityProjection(
        account: StoredAccount,
        stagedAuthJSON: JSONValue,
        expectedAuthJSON: JSONValue? = nil
    ) throws {
        let now = dateProvider.unixSecondsNow()
        _ = try storeRepository.mutateStore { store in
            guard let index = store.accounts.firstIndex(where: { $0.id == account.id }),
                  store.accounts[index].provider == .antigravity,
                  AccountIdentity.normalizedEmail(store.accounts[index].email)
                    == AccountIdentity.normalizedEmail(account.email),
                  AccountIdentity.normalizedAccountID(store.accounts[index].accountID)
                    == AccountIdentity.normalizedAccountID(account.accountID)
            else {
                throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
            }
            if let expectedAuthJSON,
               store.accounts[index].authJSON != expectedAuthJSON {
                throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
            }
            store.currentAntigravityAccountID = nil
            store.pendingAntigravityAccountID = account.id
            store.accounts[index].authJSON = stagedAuthJSON
            store.accounts[index].updatedAt = now
        }
    }

    private func updateCurrentAccountProjection(account: StoredAccount) throws {
        let store = try storeRepository.loadStore()
        guard store.accounts.contains(where: { $0.id == account.id }) else {
            throw AppError.invalidData(L10n.tr("error.accounts.account_not_found_for_switch"))
        }

        AccountSwitchDebugLog.write(
            "updateCurrentAccountProjection.begin",
            "target=\(AccountSwitchDebugLog.describe(account: account)) before=\(AccountSwitchDebugLog.describe(store: store, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
        let latestStore = try currentAccountProjectionWriter.apply(account: account)
        AccountSwitchDebugLog.write(
            "updateCurrentAccountProjection.end",
            "target=\(AccountSwitchDebugLog.describe(account: account)) after=\(AccountSwitchDebugLog.describe(store: latestStore, currentAuthAccountKey: authRepository.currentAuthAccountKey()))"
        )
    }

    private func normalizeTeamAlias(_ alias: String?) -> String? {
        guard let alias else { return nil }
        let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func applySwitchSideEffects(
        for account: StoredAccount,
        settings: AppSettings,
        workspacePath: String?
    ) throws -> SwitchAccountExecutionResult {
        var result = SwitchAccountExecutionResult.idle

        if account.provider == .codex, settings.syncOpencodeOpenaiAuth {
            do {
                try opencodeAuthSyncService.syncFromCodexAuth(account.authJSON)
                result.opencodeSynced = true
            } catch {
                result.opencodeSyncError = error.localizedDescription
            }
        }

        guard runtimePlatform == .macOS else {
            return result
        }

        if settings.restartEditorsOnSwitch {
            // Generic editor restarts are a Codex-only behavior. AntiGravity
            // owns credential persistence and has its own graceful transaction.
            let codexEditorTargets = settings.restartEditorTargets.filter { $0 != .antigravity }
            let restart = editorAppService.restartSelectedApps(codexEditorTargets)
            result.restartedEditorApps = restart.restarted
            result.editorRestartError = restart.error
        }

        if account.provider == .codex, settings.launchCodexAfterSwitch {
            result.usedFallbackCLI = try codexCLIService.launchApp(workspacePath: workspacePath)
        }

        return result
    }

    static func matchingStoredAccountIndex(
        for extracted: ExtractedAuth,
        in accounts: [StoredAccount]
    ) -> Int? {
        AccountIdentity.preferredMatchIndex(for: extracted, in: accounts)
    }

    static func matchingStoredAccount(
        for extracted: ExtractedAuth,
        in accounts: [StoredAccount]
    ) -> StoredAccount? {
        guard let index = matchingStoredAccountIndex(for: extracted, in: accounts) else {
            return nil
        }
        return accounts[index]
    }
}
