import Foundation

extension AccountsCoordinator {
    /// Runs serially behind the native account-operation gate, but never changes native/current
    /// selection. Every decision is rechecked against persisted settings and fresh quota.
    func activateReadyQuotaWindows(planner: QuotaActivationPlanner = QuotaActivationPlanner()) async throws -> Bool {
        try await withExclusiveAntigravityOperation {
            let settings = try settingsRepository.loadSettings()
            let now = dateProvider.unixSecondsNow()
            guard settings.antigravityQuotaActivationMode != .off,
                  QuotaActivationPlanner.withinHours(settings, now: Date(timeIntervalSince1970: Double(now))),
                  let service = antigravityUsageService else { return false }
            // A reappearing external writer pauses activation as well as pool mutations.
            let poolControl = OpenCodexPoolService()
            let control = try poolControl.policy()
            if control.managedSince != nil && !control.managementEnabled { return false }
            if control.managementEnabled { try poolControl.ownership.requireNoLegacyWriter() }
            let store = try storeRepository.loadStore()
            let poolEmails: Set<String>?
            if settings.antigravityQuotaActivationMode == .poolAccounts {
                let pool = try await OpenCodexPoolService().snapshot()
                poolEmails = Set(pool.accounts.filter { $0.selected && !$0.needsReauth && $0.isAvailable }.compactMap { AccountIdentity.normalizedEmail($0.email) })
            } else { poolEmails = nil }
            for account in store.accounts where account.provider == .antigravity {
                if settings.antigravityQuotaActivationMode == .activeAccount && store.currentAntigravityAccountID != account.id { continue }
                guard account.authJSON["native_session"]?.boolValue != true, let email = account.email else { continue }
                if let poolEmails, !poolEmails.contains(AccountIdentity.normalizedEmail(email) ?? "") { continue }
                for family in QuotaActivationPlanner.readyFamilies(account.usage, now: now) {
                    guard try planner.claimIfDue(account: account.id, family: family, now: now) else { continue }
                    let currentSettings = try settingsRepository.loadSettings()
                    guard currentSettings.antigravityQuotaActivationMode == settings.antigravityQuotaActivationMode,
                          QuotaActivationPlanner.withinHours(currentSettings, now: Date(timeIntervalSince1970: Double(dateProvider.unixSecondsNow()))),
                          let live = try storeRepository.loadStore().accounts.first(where: { $0.id == account.id }),
                          live.authJSON == account.authJSON else { return false }
                    do {
                        let fresh = try await service.activateQuota(authJSON: live.authJSON, expectedEmail: email, family: family, credentialPrepared: { auth in
                            _ = try self.storeRepository.mutateStore { state in
                                guard let index = state.accounts.firstIndex(where: { $0.id == live.id }), state.accounts[index].authJSON == live.authJSON else {
                                    throw AppError.invalidData(L10n.tr("settings.quota_probe.unavailable"))
                                }
                                state.accounts[index].authJSON = auth
                            }
                        }, generationConfirmed: { model, input, output in
                            try planner.record(account: live.id, family: family, outcome: "request_confirmed", model: model,
                                               inputTokens: input, outputTokens: output)
                            _ = try self.storeRepository.mutateStore { state in
                                guard let index = state.accounts.firstIndex(where: { $0.id == live.id }), state.accounts[index].usage != nil else { return }
                                var receipts = state.accounts[index].usage!.quotaActivationRequests ?? [:]
                                receipts[family.rawValue] = self.dateProvider.unixSecondsNow()
                                state.accounts[index].usage!.quotaActivationRequests = receipts
                            }
                        }, admit: {
                            let latest = try self.settingsRepository.loadSettings()
                            let controlService = OpenCodexPoolService(), control = try controlService.policy()
                            guard control.managedSince == nil || control.managementEnabled else { throw CancellationError() }
                            if control.managementEnabled { try controlService.ownership.requireNoLegacyWriter() }
                            guard latest.antigravityQuotaActivationMode == settings.antigravityQuotaActivationMode,
                                  QuotaActivationPlanner.withinHours(latest, now: Date(timeIntervalSince1970: Double(self.dateProvider.unixSecondsNow()))),
                                  try self.storeRepository.loadStore().accounts.contains(where: { $0.id == live.id }) else {
                                throw CancellationError()
                            }
                            if latest.antigravityQuotaActivationMode == .poolAccounts {
                                let currentPool = try await OpenCodexPoolService().snapshot()
                                guard currentPool.accounts.contains(where: { $0.selected && !$0.needsReauth && $0.isAvailable && AccountIdentity.normalizedEmail($0.email) == AccountIdentity.normalizedEmail(email) }) else { throw CancellationError() }
                            }
                        })
                        _ = try storeRepository.mutateStore { state in
                            guard let index = state.accounts.firstIndex(where: { $0.id == live.id }) else { return }
                            // Preserve the other model family's request evidence.
                            let reconciled = QuotaCountdownState.reconcile(previous: state.accounts[index].usage, refreshed: fresh, observedAt: now)
                            state.accounts[index].usage = reconciled
                            state.accounts[index].usageError = nil
                        }
                        try planner.record(account: live.id, family: family, outcome: "provider_confirmed")
                        return true
                    } catch {
                        try? planner.record(account: live.id, family: family, outcome: "failed_no_retry")
                        throw AppError.network(L10n.tr("settings.quota_probe.failed"))
                    }
                }
            }
            return false
        }
    }
}
