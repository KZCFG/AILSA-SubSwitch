import Foundation
import SwiftUI

extension AccountsPageModel {
    func switchAccount(id: String) async {
        AccountSwitchDebugLog.write(
            "accountsPage.switchAccount.begin",
            "requestedCardID=\(id) displayed=\(AccountSwitchDebugLog.describe(accounts: debugDisplayedAccounts()))"
        )
        withAccountsSwitchAnimation {
            switchingAccountID = id
        }
        defer {
            withAccountsSwitchAnimation {
                switchingAccountID = nil
            }
        }

        do {
            let switchResult = try await coordinator.switchAccountAndReload(id: id)
            let accounts = switchResult.accounts
            let selectedAccount = switchResult.selectedAccount
            AccountSwitchDebugLog.write(
                "accountsPage.switchAccount.loaded",
                "selected=\(AccountSwitchDebugLog.describe(account: selectedAccount)) \(AccountSwitchDebugLog.describe(accounts: accounts))"
            )
            applyAccountsForAccountSwitch(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts, preferredSourceAccountID: selectedAccount.id)
            publishLocalAccounts(accounts)
            notice = buildSwitchNotice(execution: switchResult.execution)
        } catch {
            AccountSwitchDebugLog.write(
                "accountsPage.switchAccount.error",
                "requestedCardID=\(id) error=\(error.localizedDescription)"
            )
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleSmartSwitch() async {
        guard let settingsCoordinator else { return }
        do {
            let current = try await settingsCoordinator.currentSettings()
            let isAntigravity = selectedProvider == .antigravity
            let enabled = isAntigravity ? current.autoSmartSwitchAntigravity : current.autoSmartSwitch
            if isAntigravity && !enabled {
                // Probe the quiet path off the UI actor. Enabling must not claim
                // success when the currently installed identity lacks access.
                do {
                    try await Task.detached(priority: .userInitiated) {
                        let repository = AntigravityAuthRepository()
                        let snapshot = try repository.nativeCredentialSnapshot(access: .background)
                        try repository.preflightNativeCredentialTransaction(snapshot, access: .background)
                    }.value
                } catch {
                    notice = NoticeMessage(style: .info, text: error.localizedDescription)
                    return
                }
            }
            let patch = isAntigravity ? AppSettingsPatch(autoSmartSwitchAntigravity: !enabled) : AppSettingsPatch(autoSmartSwitch: !enabled)
            let settings = try await settingsCoordinator.updateSettings(patch)
            applySettings(settings)
            onSettingsUpdated?(settings)
        } catch { notice = NoticeMessage(style: .error, text: error.localizedDescription) }
    }

    func smartSwitch() async {
        do {
            let accountsBefore = try await coordinator.listAccounts()
            AccountSwitchDebugLog.write(
                "accountsPage.smartSwitch.begin",
                "before=\(AccountSwitchDebugLog.describe(accounts: accountsBefore))"
            )
            guard let switchResult = try await coordinator.smartSwitch(provider: selectedProvider) else {
                let currentBest = AccountRanking.pickBestAccount(
                    accountsBefore.filter { $0.provider == selectedProvider }
                )
                notice = NoticeMessage(
                    style: .info,
                    text: currentBest?.isCurrent == true
                        ? L10n.tr("accounts.notice.already_best")
                        : L10n.tr("accounts.notice.no_switch_target")
                )
                return
            }
            let accounts = try await coordinator.listAccounts(refreshWorkspaceMetadata: false)
            let selectedAccount = switchResult.0
            AccountSwitchDebugLog.write(
                "accountsPage.smartSwitch.loaded",
                "selected=\(AccountSwitchDebugLog.describe(account: selectedAccount)) \(AccountSwitchDebugLog.describe(accounts: accounts))"
            )
            applyAccountsForAccountSwitch(accounts)
            await refreshPendingWorkspaceAuthorizations(from: accounts, preferredSourceAccountID: selectedAccount.id)
            publishLocalAccounts(accounts)
            var switchNotice = buildSwitchNotice(execution: switchResult.1)
            switchNotice.text = L10n.tr("accounts.notice.smart_switched_prefix_format", selectedAccount.label, switchNotice.text)
            notice = switchNotice
        } catch {
            AccountSwitchDebugLog.write(
                "accountsPage.smartSwitch.error",
                "error=\(error.localizedDescription)"
            )
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    func toggleAllAccountsCollapsed() {
        guard case .content(let accounts) = state else { return }
        let ids = Set(accounts.filter { $0.provider == selectedProvider && !$0.isWorkspaceDeactivated }.map(\.id))
        guard !ids.isEmpty else {
            collapsedAccountIDs = []
            return
        }
        collapsedAccountIDs = collapsedAccountIDs.isSuperset(of: ids) ? [] : ids
    }

    private func applyAccountsForAccountSwitch(_ accounts: [AccountSummary]) {
        withAccountsSwitchAnimation {
            applyAccounts(accounts)
        }
    }

    private func withAccountsSwitchAnimation(_ updates: () -> Void) {
        withAnimation(AccountsAnimationRules.contentReorder) {
            updates()
        }
    }
}
