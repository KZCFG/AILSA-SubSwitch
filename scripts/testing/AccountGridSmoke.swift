import AppKit
import SwiftUI
@testable import AILSA_SS

// Synthetic accounts only. This executable never starts AppContainer or provider services.
private struct AccountGridSmoke: View {
    @State private var compact = true
    @State private var provider: AccountProvider = .antigravity
    private var cards: [AccountCardViewState] {
        let now = Date()
        let epoch = Int64(now.timeIntervalSince1970)
        return (1...12).map { n in
            let families = ["gemini", "claude"].map { family in
                UsageQuotaFamily(id: family, displayName: family == "gemini" ? "Gemini" : "Claude",
                    buckets: [UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: Double(n * 4),
                        resetAt: epoch + 7200, windowSeconds: 18000, resetDescription: nil, isUsageKnown: true),
                        UsageQuotaBucket(id: "weekly", displayName: "weekly", usedPercent: Double(n * 3),
                        resetAt: epoch + 259200, windowSeconds: 604800, resetDescription: nil, isUsageKnown: true)])
            }
            let usage = UsageSnapshot(fetchedAt: epoch, planType: "pro", fiveHour: nil,
                oneWeek: provider == .codex ? UsageWindow(usedPercent: 28, windowSeconds: 604800, resetAt: epoch + 259200) : nil,
                credits: CreditSnapshot(hasCredits: true, unlimited: false, balance: "128.50"),
                quotaFamilies: provider == .antigravity ? families : [],
                source: provider == .antigravity ? .antigravityNativeSummary : nil, sourceAccountMatched: true,
                resetCredits: provider == .codex ? ResetCreditInventory(availableCount: 3,
                    expiresAt: [now.addingTimeInterval(90061), now.addingTimeInterval(180122), now.addingTimeInterval(270183)], fetchedAt: now) : nil)
            let account = AccountSummary(id: "smoke-\(n)", label: "Account \(n)", email: "account\(n)@example.invalid",
                accountID: "smoke-\(n)", planType: "pro", teamName: nil, teamAlias: nil, addedAt: epoch, updatedAt: epoch,
                usage: usage, usageError: nil, isCurrent: n == 1, provider: provider)
            return AccountCardViewState(account: account,
                presentation: AccountCardPresentation(account: account, isCollapsed: compact, locale: L10n.currentLocale, usageProgressDisplayMode: .remaining),
                isCollapsed: compact, switching: false, refreshing: false, showsRefreshButton: true,
                showsReauthenticateButton: false, isRefreshEnabled: true, isUsageRefreshActive: false, usageProgressDisplayMode: .remaining)
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            Text("A.S.S. · synthetic account interaction test").font(.headline)
            ASSegmentedControl(selection: $provider, values: [.codex, .antigravity], title: { $0 == .codex ? "Codex" : "Antigravity" })
            HStack {
                Text("12 synthetic accounts").font(.caption)
                Spacer()
                Button(compact ? "Expand" : "Collapse") { compact.toggle() }
            }
            ScrollView(.vertical) {
                ReorderableAccountGrid(items: cards, provider: provider,
                    columns: AccountCollectionLayout.columns(provider: provider, compact: compact, availableWidth: 512)) { card in
                    AccountCardView(card: card, onSwitch: {}, onRefresh: {}, onReauthenticate: {}, onDelete: {})
                }.padding(.vertical, 6)
            }.id(provider)
        }.padding(16).frame(width: 544, height: 700).background(.background)
            .environmentObject(ASModalHost())
            .defaultAppStorage(UserDefaults(suiteName: "com.ailsa.subswitch.account-grid-smoke")!)
    }
}
@main struct AccountGridSmokeApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        L10n.setLocale(identifier: "zh-Hans")
        let window = NSWindow(contentRect: NSRect(x: 80, y: 100, width: 544, height: 700),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "A.S.S. Account Grid Smoke"
        window.contentView = NSHostingView(rootView: AccountGridSmoke())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        app.run()
    }
}
