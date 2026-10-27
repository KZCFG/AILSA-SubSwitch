import SwiftUI
private struct WeeklyUsageActionKey: EnvironmentKey {
    static let defaultValue: ((String)->Void)? = nil
}
extension EnvironmentValues {
    var weeklyUsageActivationAction: ((String)->Void)? {
        get{self[WeeklyUsageActionKey.self]} set{self[WeeklyUsageActionKey.self]=newValue}
    }
}
struct WeeklyUsageActivationButton: View {
    let state: WeeklyUsageActivationState?
    let busy: Bool
    let available: Bool
    let action: ()->Void
    var body: some View {
        if let state {
            Button(action:action) {
                HStack(spacing:5) {
                    if busy {ProgressView().controlSize(.mini)}
                    else {Image(systemName:state == .active ? "checkmark.circle" : "bolt.circle")}
                    Text(L10n.tr(busy ? "accounts.weekly.activating" : state == .active ? "accounts.weekly.active" : state == .idle ? "accounts.weekly.idle" : "accounts.weekly.unknown"))
                        .font(.system(size:11,weight:.medium)).lineLimit(1)
                }
            }.ailsaSSActionButtonStyle(density:.compact)
                .disabled(busy || !available || state != .idle)
                .help(L10n.tr(state == .unknown ? "accounts.weekly.refresh_first" : "accounts.weekly.help"))
        }
    }
}
extension AccountsPageModel {
    func activateWeeklyUsage(forAccountID id:String) async {
        guard let activator=weeklyUsageActivator,weeklyActivatingAccountIDs.isEmpty,
              let card=makeAccountCardViewState(forAccountID:id),card.weeklyActivation == .idle,card.weeklyActivationAvailable else{return}
        weeklyActivatingAccountIDs.insert(id)
        defer{weeklyActivatingAccountIDs.remove(id)}
        do {
            _ = try await activator(card.account)
            notice=NoticeMessage(style:.success,text:L10n.tr("accounts.weekly.success"))
            await refreshUsage(forAccountID:id)
        } catch {notice=NoticeMessage(style:.error,text:L10n.tr("accounts.weekly.failed"))}
    }
}
