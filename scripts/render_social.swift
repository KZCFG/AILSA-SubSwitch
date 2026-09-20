import AppKit
import SwiftUI
@testable import AILSA_SS

// Only allowlisted timing fields enter the synthetic promotional view model.
private struct TimingFixture: Decodable {
    let activeResetAt: Double
    let otherResetAt: Double
    let creditExpiries: [Double]
}

@main struct RenderSocial {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        L10n.setLocale(identifier: "zh-Hans")
        // This bundle has a separate preferences domain from the installed app.
        UserDefaults.standard.set("official", forKey: "ass.progressSkin.codex")
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()
        let epoch = Int64(now.timeIntervalSince1970)
        let timing: TimingFixture
        if CommandLine.arguments.count > 2, !CommandLine.arguments[2].isEmpty {
            timing = try JSONDecoder().decode(TimingFixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2])))
        } else {
            timing = TimingFixture(activeResetAt: now.timeIntervalSince1970 + 36000,
                otherResetAt: now.timeIntervalSince1970 + 6 * 86400,
                creditExpiries: [1.0, 14, 15].map { now.timeIntervalSince1970 + $0 * 86400 })
        }
        let remaining = [10.0, 21, 42, 100]
        let accounts: [AccountSummary] = remaining.enumerated().map { index, percent in
            AccountSummary(id: "preview-\(index)", label: "Demo \(index + 1)", email: String(format: "account%02d@example.com", index + 1),
                accountID: "preview-\(index)", planType: "pro", teamName: nil, teamAlias: nil,
                addedAt: epoch, updatedAt: epoch,
                usage: UsageSnapshot(fetchedAt: epoch - 30, planType: "pro", fiveHour: nil,
                    oneWeek: UsageWindow(usedPercent: 100 - percent, windowSeconds: 604800,
                        resetAt: Int64(index == 0 ? timing.activeResetAt : timing.otherResetAt)),
                    credits: CreditSnapshot(hasCredits: false, unlimited: false, balance: "0"),
                    resetCredits: ResetCreditInventory(availableCount: index == 0 ? 0 : 3,
                        expiresAt: index == 0 ? [] : timing.creditExpiries.map { Date(timeIntervalSince1970: $0) }, fetchedAt: now)),
                usageError: nil, isCurrent: index == 0)
        }
        let accountsView = VStack(alignment: .leading, spacing: 18) {
            navigation("账号")
            ASSegmentedControl(selection: .constant("Codex"), values: ["Codex", "Antigravity", "Cursor"], title: { $0 },
                icon: { $0 == "Codex" ? "terminal" : ($0 == "Cursor" ? "cube" : "sparkles") })
            HStack(spacing: 10) {
                Button {} label: { Label("添加账号", systemImage: "plus") }.ailsaSSActionButtonStyle(density: .compact)
                Button {} label: { Label("导入账号", systemImage: "square.and.arrow.down") }.ailsaSSActionButtonStyle(density: .compact)
                Button {} label: { Label("智能切换", systemImage: "power") }.ailsaSSActionButtonStyle(density: .compact)
                Button {} label: { Image(systemName: "arrow.clockwise") }.ailsaSSActionButtonStyle(prominent: true, density: .compact)
                Spacer()
                Button {} label: { Image(systemName: "chevron.up") }.ailsaSSActionButtonStyle(density: .compact)
            }
            VStack(spacing: 14) {
                ForEach(0..<2) { row in
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(Array(accounts[(row * 2)..<(row * 2 + 2)])) { account in
                            card(account)
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
            }
            HStack {
                Text("AILSA SubSwitch").fontWeight(.semibold)
                Spacer()
                Text("脱敏演示 · 账号与额度为展示配置")
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
        }.padding(24).frame(width: 680).background(.white)
            .environmentObject(ASModalHost()).environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        try save(accountsView, to: output.appendingPathComponent("01-Codex-账号-脱敏.png"))

        let aboutView = VStack(spacing: 20) {
            navigation("设置")
            ASSegmentedControl(selection: .constant(SettingsPageSection.about), values: SettingsPageSection.allCases,
                title: { L10n.tr($0.titleKey) })
            AboutView()
        }.padding(24).frame(width: 680).background(.white)
            .environmentObject(ASModalHost()).environment(\.colorScheme, .light)
            .environment(\.locale, Locale(identifier: "zh-Hans"))
        try save(aboutView, to: output.appendingPathComponent("03-关于-AILSA-SubSwitch.png"))
    }

    @MainActor private static func card(_ account: AccountSummary) -> some View {
        AccountCardView(card: AccountCardViewState(account: account,
            presentation: AccountCardPresentation(account: account, isCollapsed: false,
                locale: Locale(identifier: "zh-Hans"), usageProgressDisplayMode: .remaining),
            isCollapsed: false, switching: false, refreshing: false,
            showsRefreshButton: true, showsReauthenticateButton: false,
            isRefreshEnabled: true, isUsageRefreshActive: false, usageProgressDisplayMode: .remaining),
            onSwitch: {}, onRefresh: {}, onReauthenticate: {}, onDelete: {})
    }

    @MainActor private static func navigation(_ selected: String) -> some View {
        HStack {
            Spacer()
            ASSegmentedControl(selection: .constant(selected), values: ["账号", "额度管理", "设置"], title: { $0 },
                icon: { $0 == "账号" ? "person.2" : ($0 == "设置" ? "gearshape" : "chart.bar") })
                .frame(width: 370)
            Spacer()
        }.padding(.bottom, 4)
    }

    @MainActor private static func save<V: View>(_ content: V, to url: URL) throws {
        let host = NSHostingView(rootView: content)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw NSError(domain: "SocialRender", code: 1) }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "SocialRender", code: 2) }
        try data.write(to: url)
        print("Rendered \(url.lastPathComponent) — \(bitmap.pixelsWide) × \(bitmap.pixelsHigh)")
        window.orderOut(nil)
    }
}
