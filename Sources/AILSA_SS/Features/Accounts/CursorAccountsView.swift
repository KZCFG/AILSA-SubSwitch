import SwiftUI

struct CursorAccountsView: View {
    var progressMode: UsageProgressDisplayMode = .used
    var visibility: UsageQuotaVisibilityPreferences = .defaultValue
    @State private var account: CursorAccountUsage?
    @State private var profiles: [CursorSavedProfile] = []
    @State private var error: String?
    @State private var loading = false
    @State private var recovery = false
    @AppStorage("ass.cursorCardsCompact") private var compact = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("ass.launchCursorAfterSwitch") private var launchCursorAfterSwitch = true
    private struct Tile: Identifiable { let id: String; let profile: CursorSavedProfile? }
    private var tiles: [Tile] {
        var result = profiles.map { Tile(id: $0.id, profile: $0) }
        if let account, !result.contains(where: { $0.id == account.id }) {
            result.insert(Tile(id: account.id, profile: nil), at: 0)
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { Task { await perform { _ = try await CursorProfileRepository.shared.captureCurrent() } } } label: {
                    Label("导入当前账号", systemImage: "square.and.arrow.down").frame(minHeight: 30)
                }.disabled(loading)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 32, height: 30).contentShape(Rectangle())
                }.disabled(loading).help("刷新 Cursor 登录和额度")
                Button {
                    withAnimation(reduceMotion ? nil : AppDesign.contentTransition) { compact.toggle() }
                } label: {
                    Image(systemName: compact ? "chevron.down" : "chevron.up").frame(width: 32, height: 30)
                }.help(compact ? "展开账号卡片" : "收起账号卡片")
                    .accessibilityLabel(compact ? "展开账号卡片" : "收起账号卡片")
            }
            if recovery {
                Button("恢复上次切换前的账号") { Task { await perform { try await CursorNativeAccountSwitcher.shared.recover() } } }
                    .disabled(loading)
            }
            ScrollView(.vertical) {
                ReorderableAccountGrid(items: tiles, provider: .cursor, columns: compact ? 3 : 2,
                    pinnedID: account?.id) { tile in
                    if let account, account.id == tile.id {
                        if compact { compactCurrentCard(account) }
                        else { currentCard(account) }
                    } else if let profile = tile.profile { savedCard(profile) }
                }.padding(.vertical, 6)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(.horizontal, LayoutRules.pagePadding)
        .task { if account == nil { await refresh() } }
    }
    private func savedCard(_ profile: CursorSavedProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("CURSOR").font(.caption.bold()); Spacer()
                Button { Task { await perform { try await CursorNativeAccountSwitcher.shared.switchAccount(id: profile.id) } } } label: {
                    Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2).frame(width: 28, height: 28)
                }.disabled(loading || recovery).help("切换到 " + profile.email)
            }
            Text(profile.email).font(.system(size: compact ? 12 : 15, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.75).help(profile.email)
            Text("已保存 · 切换后读取额度").font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !compact {
                Text(launchCursorAfterSwitch ? "切换会退出并重新打开 Cursor" : "切换后保持 Cursor 关闭")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, minHeight: compact ? 124 : 140, alignment: .topLeading)
            .padding(compact ? 10 : 14).cardSurface(cornerRadius: LayoutRules.cardRadius)
    }
    private func compactCurrentCard(_ account: CursorAccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(account.plan.uppercased()).font(.system(size: 9, weight: .bold)).lineLimit(1)
                Spacer(minLength: 0)
                Button {} label: { Image(systemName: "arrow.left.arrow.right").font(.caption) }
                    .disabled(true).help("当前 Cursor 账号")
            }
            Text(account.email).font(.system(size: 12, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75).help(account.email)
            AccountCompactUsageRow(rings: Array(account.pools.filter {
                visibility.isVisible(UsageQuotaVisibilityKey.cursor(poolID: $0.id))
            }.prefix(2)).map { pool in
                let percent = pool.usedPercent.map { progressMode == .used ? $0 : 100 - $0 }
                return AccountCompactRingDescriptor(id: pool.id,
                    valueText: percent.map { String(format: "%.0f%%", $0) } ?? "—", subtitleText: pool.id,
                    progress: min(1, max(0, (percent ?? 0) / 100)), fillStyle: .cursor)
            })
        }.frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .padding(10).cardSurface(cornerRadius: LayoutRules.cardRadius, tint: Color.primary.opacity(0.10))
    }
    private func currentCard(_ account: CursorAccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(account.plan.uppercased()).font(.caption.bold()); Spacer()
                Text("当前").font(.caption)
                Button {} label: { Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2) }
                    .disabled(true).help("当前 Cursor 账号")
            }
            Text(account.email).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            ForEach(account.pools.filter { visibility.isVisible(UsageQuotaVisibilityKey.cursor(poolID: $0.id)) }) { pool in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(pool.id); Spacer()
                        Text(pool.usedPercent.map { String(format: progressMode == .used ? "已用 %.0f%%" : "剩余 %.0f%%", progressMode == .used ? $0 : max(0, 100 - $0)) } ?? "—")
                    }.font(.caption)
                    if let used = pool.usedPercent {
                        LiquidProgressBar(progress: min(100, max(0, progressMode == .used ? used : 100 - used)) / 100, fillStyle: .cursor)
                    }
                    AccountResetCountdownLabel(date: pool.reset, fallback: "重置时间未提供")
                }
            }
            HStack {
                Text("本账期按需用量"); Spacer()
                Text(account.onDemandUSD.map { $0.formatted(.currency(code: "USD")) } ?? "—")
            }.font(.caption)
                .help("Cursor 报告的本账期 on-demand 用量，不等同于历史事件计费总额。")
            Text("更新于 " + account.scannedAt.formatted(date: .omitted, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
    @MainActor private func refresh() async { await perform {} }
    @MainActor private func perform(_ operation: () async throws -> Void) async {
        guard !loading else { return }; loading = true; error = nil
        defer { loading = false }
        do {
            try await operation()
            profiles = try await CursorProfileRepository.shared.profiles()
            recovery = try await CursorProfileRepository.shared.recoveryValues() != nil
            let updated = try await CursorUsageService.shared.loadAccount()
            let changed = account?.id != updated.id
            account = updated
            if changed { NotificationCenter.default.post(name: .assCursorAccountDidChange, object: nil, userInfo: ["accountID": updated.id]) }
        } catch {
            self.error = error.localizedDescription
            recovery = (try? await CursorProfileRepository.shared.recoveryValues()) != nil
        }
    }
}
