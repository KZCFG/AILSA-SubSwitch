import SwiftUI
import UniformTypeIdentifiers

struct AccountsPageView: View {
    @State private var areCardsPresented = false
    @State private var didRunInitialCardEntrance = false
    @State private var isImportingAuthFile = false

    @ObservedObject var model: AccountsPageModel
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        model: AccountsPageModel,
        currentLocale: AppLocale,
        onSelectLocale: @escaping (AppLocale) -> Void
    ) {
        self.model = model
        self.currentLocale = currentLocale
        self.onSelectLocale = onSelectLocale
        let hasResolvedInitialState = model.hasResolvedInitialState
        _areCardsPresented = State(initialValue: hasResolvedInitialState)
        _didRunInitialCardEntrance = State(initialValue: hasResolvedInitialState)
    }

    var body: some View {
        AccountsPageShell(
            model: model,
            currentLocale: currentLocale,
            onSelectLocale: onSelectLocale,
            // Cards must become visible whenever the store has resolved, even if
            // the entrance trigger was missed (MenuBarExtra can resolve the store
            // in the same update cycle as the first presentation, leaving
            // onAppear/onChange without a transition to observe).
            areCardsPresented: areCardsPresented || model.hasResolvedInitialState,
            onTriggerAction: triggerAction,
            onToggleCollapse: toggleCollapse,
            onSwitchAccount: switchAccount,
            onRefreshAccountUsage: refreshUsage,
            onReauthenticateAccount: reauthenticateAccount,
            onAuthorizeWorkspace: authorizeWorkspace,
            onCancelAuthorizeWorkspace: cancelAuthorizeWorkspace,
            onDeletePendingWorkspace: deletePendingWorkspace,
            onDeleteAccount: deleteAccount
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .fileImporter(
            isPresented: $isImportingAuthFile,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportAuthFile(result)
        }
        .onAppear {
            triggerInitialCardEntranceIfNeeded(for: contentAccountCount)
        }
        .onChange(of: contentAccountCount) { _, newValue in
            triggerInitialCardEntranceIfNeeded(for: newValue)
        }
    }

    private var contentAccountCount: Int? {
        guard case .content(let cards) = model.makeContentPresentation().state else { return nil }
        return cards.count
    }

    private func triggerInitialCardEntranceIfNeeded(for count: Int?) {
        guard count != nil, !didRunInitialCardEntrance else { return }
        didRunInitialCardEntrance = true
        areCardsPresented = true
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        Task { await model.handlePageAction(intent) }
    }

    private func handleImportAuthFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await model.importAuthDocument(from: url, setAsCurrent: false) }
        case .failure(let error):
            model.notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

    private func toggleCollapse() {
        #if os(macOS)
        // The MenuBarExtra host has a fixed presentation size. Avoid turning
        // an account-card layout update into an animated window transaction.
        model.toggleAllAccountsCollapsed()
        #else
        if reduceMotion {
            model.toggleAllAccountsCollapsed()
        } else {
            withAnimation(AccountsAnimationRules.collapseToggle) {
                model.toggleAllAccountsCollapsed()
            }
        }
        #endif
    }

    private func switchAccount(id: String) {
        Task { await model.switchAccount(id: id) }
    }

    private func refreshUsage(forAccountID id: String) {
        Task { await model.refreshUsage(forAccountID: id) }
    }

    private func reauthenticateAccount(id: String) {
        Task { await model.reauthenticateAccount(id: id) }
    }

    private func deleteAccount(id: String) {
        Task { await model.deleteAccount(id: id) }
    }

    private func authorizeWorkspace(id: String) {
        Task { await model.authorizePendingWorkspace(id: id) }
    }

    private func cancelAuthorizeWorkspace() {
        model.cancelPendingWorkspaceAuthorization()
    }

    private func deletePendingWorkspace(id: String) {
        Task { await model.deletePendingWorkspace(id: id) }
    }
}
