import Foundation

extension AccountsPageModel {
    func refreshPoolActiveAccount() async {
        guard runtimePlatform == .macOS, let poolActiveAccountLoader else { return }
        do {
            let email = try await poolActiveAccountLoader()
            guard !Task.isCancelled else { return }
            poolActiveEmail = AccountIdentity.normalizedEmail(email)
        } catch {
            if !Task.isCancelled { poolActiveEmail = nil }
        }
    }
    func observePoolActiveAccount() async {
        guard runtimePlatform == .macOS, poolActiveAccountLoader != nil else { return }
        while !Task.isCancelled {
            await refreshPoolActiveAccount()
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    /// Opening the menu is an explicit freshness boundary. Refresh every
    /// visible local subscription instead of relying on the background policy,
    /// which intentionally prioritizes the active account between reset
    /// windows. The per-account set keeps the card state honest while partial
    /// results arrive and lets stale text return only after a failure.
    func refreshOnWindowOpen() async {
        await refreshAutomatically(provider: nil)
    }

    func refreshOnProviderSelection() async {
        await refreshAutomatically(provider: selectedProvider)
    }

    private func refreshAutomatically(provider: AccountProvider?) async {
        // A background read of the active card must not suppress the other
        // subscriptions. Claim this operation before loading the store so
        // simultaneous presentation callbacks cannot launch duplicate reads.
        guard !isManualRefreshing else { return }
        isManualRefreshing = true
        defer { isManualRefreshing = false }

        if !hasLoaded {
            await load()
        }

        guard case .content(let accounts) = state else { return }
        let targetIDs = accounts
            .filter(\.isVisibleInMainList)
            .filter { $0.provider == .codex || $0.provider == .antigravity }
            .filter { provider == nil || $0.provider == provider }
            .filter { !remoteUsageRefreshingAccountIDs.contains($0.id) && !refreshingAccountIDs.contains($0.id) }
            .map(\.id)
        guard !targetIDs.isEmpty else { return }

        refreshingAccountIDs.formUnion(targetIDs)
        defer {
            refreshingAccountIDs.subtract(targetIDs)
        }

        do {
            _ = try await coordinator.refreshUsage(
                accountIDs: targetIDs,
                force: true,
                serial: false,
                onPartialUpdate: { [weak self] accounts in
                    guard let self else { return }
                    await MainActor.run {
                        self.applyAccounts(accounts)
                        self.publishLocalAccounts(accounts)
                    }
                }
            )
            let latestAccounts = try await coordinator.listAccounts(refreshWorkspaceMetadata: false)
            applyAccounts(latestAccounts)
            await refreshPendingWorkspaceAuthorizations(from: latestAccounts)
            publishLocalAccounts(latestAccounts)
        } catch {
            // Keep the last snapshot visible. Once the per-account activity is
            // cleared by defer, its age/error is allowed to be shown again.
        }
    }

    func refreshUsage() async {
        guard !isRefreshing else { return }
        isManualRefreshing = true
        defer { isManualRefreshing = false }

        do {
            if let manualRefreshService {
                _ = try await manualRefreshService.performManualRefresh(onPartialUpdate: { _ in })
            } else {
                _ = try await coordinator.refreshUsage(
                    force: true,
                    onPartialUpdate: { [weak self] accounts in
                        guard let self else { return }
                        await MainActor.run {
                            self.applyAccounts(accounts)
                            self.publishLocalAccounts(accounts)
                        }
                    }
                )
            }
            let accounts = try await coordinator.listAccounts()
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts)
            if manualRefreshService == nil {
                publishLocalAccounts(accounts)
            }
            let noticeKey = manualRefreshService == nil
                ? "accounts.notice.usage_refreshed"
                : "accounts.notice.accounts_refreshed"
            notice = NoticeMessage(style: .info, text: L10n.tr(noticeKey))
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func refreshUsage(forAccountID id: String) async {
        guard !isRefreshing else { return }
        refreshingAccountIDs.insert(id)
        defer { refreshingAccountIDs.remove(id) }

        do {
            let accounts = try await coordinator.refreshUsage(
                accountIDs: [id],
                force: true,
                onPartialUpdate: { [weak self] accounts in
                    guard let self else { return }
                    await MainActor.run {
                        self.applyAccounts(accounts)
                        self.publishLocalAccounts(accounts)
                    }
                }
            )
            applyAccounts(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts)
            publishLocalAccounts(accounts)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

}
