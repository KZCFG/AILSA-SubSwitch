import AppKit
import SwiftUI
@testable import AILSA_SS

// Documentation only: the account IDs, usage and USD figures are synthetic.
// This driver never creates AppContainer.live or a live usage service.
private struct DemoUsageService: QuotaManagementUsageServiceProtocol {
    let snapshot: QuotaDashboardSnapshot
    func loadData(for provider: QuotaManagementProvider, historyDays: Int, now: Date) async throws -> QuotaManagementData { .codex(.empty) }
    func loadDashboard(for provider: QuotaManagementProvider, now: Date) async throws -> QuotaDashboardSnapshot { snapshot }
}

@main struct RenderDocumentation {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        L10n.setLocale(identifier: "en")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let calendar = Calendar.current
        let now = calendar.date(bySetting: .second, value: 0, of: Date())!
        let epoch = Int64(now.timeIntervalSince1970)
        let accounts = [
            AccountSummary(id: "demo-one", label: "Personal", email: "personal@example.invalid", accountID: "demo-one", planType: "pro_5x", teamName: nil, teamAlias: nil, addedAt: epoch, updatedAt: epoch,
                           usage: UsageSnapshot(fetchedAt: epoch, planType: "pro_5x", fiveHour: nil, oneWeek: UsageWindow(usedPercent: 28, windowSeconds: 604800, resetAt: epoch + 259200), credits: CreditSnapshot(hasCredits: true, unlimited: false, balance: "128.50"), resetCredits: ResetCreditInventory(availableCount: 2, expiresAt: [now.addingTimeInterval(604800), now.addingTimeInterval(1209600)], fetchedAt: now)), usageError: nil, isCurrent: true),
            AccountSummary(id: "demo-two", label: "Work", email: "work@example.invalid", accountID: "demo-two", planType: "pro", teamName: nil, teamAlias: nil, addedAt: epoch, updatedAt: epoch,
                           usage: UsageSnapshot(fetchedAt: epoch, planType: "pro", fiveHour: nil, oneWeek: UsageWindow(usedPercent: 9, windowSeconds: 604800, resetAt: epoch + 432000), credits: nil), usageError: nil, isCurrent: false)
        ]
        let accountPreview = VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Accounts").font(.title2.bold()); Spacer(); Text("Demo data").foregroundStyle(.secondary).font(.caption) }
            ASSegmentedControl(selection: .constant("Codex"), values: ["Codex", "Antigravity", "Cursor"], title: { $0 }, icon: { $0 == "Codex" ? "terminal" : ($0 == "Cursor" ? "cube" : "sparkles") })
            HStack(alignment: .top, spacing: 12) {
                ForEach(accounts) { account in
                    AccountCardView(card: AccountCardViewState(account: account,
                        presentation: AccountCardPresentation(account: account, isCollapsed: false, locale: Locale(identifier: "en"), usageProgressDisplayMode: .remaining),
                        isCollapsed: false, switching: false, refreshing: false, showsRefreshButton: true, showsReauthenticateButton: false, isRefreshEnabled: true, isUsageRefreshActive: false, usageProgressDisplayMode: .remaining),
                        onSwitch: {}, onRefresh: {}, onReauthenticate: {}, onDelete: {})
                }
            }
        }.padding(24).frame(width: 720).background(.white).environmentObject(ASModalHost()).environment(\.colorScheme, .light)
        try save(accountPreview, to: output.appendingPathComponent("accounts-demo.png"))

        let agUsage = UsageSnapshot(fetchedAt: epoch, planType: "pro", fiveHour: nil, oneWeek: nil, credits: nil,
            quotaFamilies: ["Gemini", "Claude"].map { family in
                UsageQuotaFamily(id: family.lowercased(), displayName: family,
                    buckets: [UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: family == "Gemini" ? 22 : 8,
                        resetAt: epoch + 7200, windowSeconds: 18_000, resetDescription: nil, isUsageKnown: true),
                        UsageQuotaBucket(id: "weekly", displayName: "weekly", usedPercent: 36,
                        resetAt: epoch + 259200, windowSeconds: 604_800, resetDescription: nil, isUsageKnown: true)])
            }, source: .antigravityNativeSummary, sourceAccountMatched: true)
        let ag = AccountSummary(id: "demo-gemini", label: "Gemini", email: "gemini@example.invalid", accountID: "demo-gemini", planType: "pro", teamName: nil, teamAlias: nil, addedAt: epoch, updatedAt: epoch, usage: agUsage, usageError: nil, isCurrent: false, provider: .antigravity)
        let compactPreview = HStack(alignment: .top, spacing: 12) {
            ForEach([accounts[0], ag]) { account in
                AccountCardView(card: AccountCardViewState(account: account,
                    presentation: AccountCardPresentation(account: account, isCollapsed: true, locale: Locale(identifier: "en"), usageProgressDisplayMode: .remaining),
                    isCollapsed: true, switching: false, refreshing: false, showsRefreshButton: true, showsReauthenticateButton: false, isRefreshEnabled: true, isUsageRefreshActive: false, usageProgressDisplayMode: .remaining),
                    onSwitch: {}, onRefresh: {}, onReauthenticate: {}, onDelete: {})
                    .frame(width: account.provider == .codex ? 250 : 163)
            }
        }.padding(24).background(.white).environmentObject(ASModalHost()).environment(\.colorScheme, .light)
        try save(compactPreview, to: output.appendingPathComponent("compact-demo.png"))

        var day = QuotaBucket()
        var minutes: [Date: Int] = [:]
        var minuteBuckets: [Date: QuotaBucket] = [:]
        let names = ["gpt-5.4", "grok-4.6", "kimi-for-coding"]
        for index in 0..<144 {
            let date = now.addingTimeInterval(Double(index - 143) * 300)
            let count = (index % 17 + 2) * 1200 + (index % 9 == 0 ? 140000 : 0)
            var value = QuotaAggregate()
            value.tokens = UsageTokenBreakdown(input: count, cachedInput: count / 2, cacheWriteInput: 0, output: count / 12, reasoningOutput: 0)
            value.requests = 1; value.reported = 1
            value.reference.add(Int64(count) * 1_000_000)
            let key = QuotaModelKey(provider: "Demo", model: names[index % names.count])
            day.add(value, key: key)
            minutes[date] = value.tokens.total
            minuteBuckets[date, default: QuotaBucket()].add(value, key: key)
        }
        let snapshot = QuotaDashboardSnapshot(scannedAt: now, days: [calendar.startOfDay(for: now): day], all: day.total, source: "Demo data", pricingSources: [], discardedRows: 0, quotaWindows: [], quotaTrend: [:], buildMilliseconds: 0, minuteTokens: minutes, minuteBuckets: minuteBuckets)
        let model = QuotaManagementPageModel(usageService: DemoUsageService(snapshot: snapshot), dateProvider: { now })
        await model.loadDashboard(for: .codex)
        let quotaPreview = QuotaManagementPageView(model: model).frame(width: 720, height: 690)
            .environmentObject(ASModalHost()).environment(\.colorScheme, .light)
        try save(quotaPreview, to: output.appendingPathComponent("usage-demo.png"))
        print("Rendered accounts-demo.png and usage-demo.png with synthetic data.")
    }

    @MainActor private static func save<V: View>(_ content: V, to url: URL) throws {
        // NSView-backed chart/picker components are omitted by ImageRenderer.
        // Attach the real view tree to an offscreen window and render it natively.
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw NSError(domain: "DocumentationRender", code: 1)
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "DocumentationRender", code: 2) }
        try data.write(to: url)
        window.orderOut(nil)
    }
}
