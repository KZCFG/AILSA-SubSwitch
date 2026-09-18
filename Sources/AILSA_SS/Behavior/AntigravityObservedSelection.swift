import Foundation

/// Synchronizes only the current-card marker with an observed native session.
/// This never stages credentials, changes quota, starts the provider, or chooses
/// an account to switch to. An unknown/ambiguous native identity clears the old
/// marker instead of making the wrong card look current.
enum AntigravityObservedSelection {
    @discardableResult
    static func reconcile(
        store: inout AccountsStore,
        baseline: AccountsStore,
        native: AntigravityNativeUsageResult,
        now: Int64
    ) -> Bool {
        guard baseline.pendingAntigravityAccountID == nil,
              store.pendingAntigravityAccountID == nil,
              store.currentAntigravityAccountID == baseline.currentAntigravityAccountID,
              native.usage.source == .antigravityNativeSummary || native.usage.source == .antigravityAgySummary,
              native.usage.isVerifiedForSwitch,
              !native.usage.isStale(now: now),
              let email = AccountIdentity.normalizedEmail(native.email)
        else { return false }

        func matches(in store: AccountsStore) -> [StoredAccount] {
            store.accounts.filter {
                $0.provider == .antigravity && $0.displayStatus != .deleted && $0.displayStatus != .pending
                    && AccountIdentity.normalizedEmail($0.email) == email
            }
        }
        let original = matches(in: baseline)
        let latest = matches(in: store)
        if let currentID = baseline.currentAntigravityAccountID {
            let previousCurrent = baseline.accounts.first { $0.id == currentID }
            let latestCurrent = store.accounts.first { $0.id == currentID }
            guard previousCurrent?.authJSON == latestCurrent?.authJSON,
                  previousCurrent?.email == latestCurrent?.email,
                  previousCurrent?.accountID == latestCurrent?.accountID,
                  previousCurrent?.provider == latestCurrent?.provider
            else { return false }
        }
        // A different account set or newly replaced credential belongs to a
        // newer transaction. Do not apply an observation started before it.
        guard Set(original.map(\.id)) == Set(latest.map(\.id)),
              latest.allSatisfy({ account in
                  original.contains { $0.id == account.id && $0.authJSON == account.authJSON }
              })
        else { return false }
        let observedID = latest.count == 1 ? latest[0].id : nil
        guard store.currentAntigravityAccountID != observedID else { return false }
        store.currentAntigravityAccountID = observedID
        return true
    }
}
