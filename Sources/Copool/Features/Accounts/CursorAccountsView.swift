import SwiftUI

struct CursorAccountsView: View {
    var progressMode: UsageProgressDisplayMode = .used
    var visibility: UsageQuotaVisibilityPreferences = .defaultValue
    @State private var account: CursorAccountUsage?
    @State private var profiles: [CursorSavedProfile] = []
    @State private var error: String?
    @State private var loading = false
    @State private var recovery = false
    @State private var page = 0
    @AppStorage("ass.launchCursorAfterSwitch") private var launchCursorAfterSwitch = true
    private var saved: [CursorSavedProfile] { profiles.filter { $0.id != account?.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { Task { await perform { _ = try await CursorProfileRepository.shared.captureCurrent() } } } label: {
                    Label("导入当前账号", systemImage: "square.and.arrow.down").frame(minHeight: 30)
                }
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button { Task { await refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 32, height: 30).contentShape(Rectangle())
                }.help("刷新 Cursor 登录和额度")
            }.disabled(loading)
            if recovery {
                Button("恢复上次切换前的账号") { Task { await perform { try await CursorNativeAccountSwitcher.shared.recover() } } }
                    .disabled(loading)
            }
            if let account { currentCard(account) }
            if !saved.isEmpty {
                let index = min(page, saved.count - 1)
                let profile = saved[index]
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.email).font(.subheadline.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        Text(launchCursorAfterSwitch ? "已保存 · 切换会退出并重新打开 Cursor" : "已保存 · 切换后保持 Cursor 关闭").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await perform { try await CursorNativeAccountSwitcher.shared.switchAccount(id: profile.id) } } } label: {
                        Image(systemName: "arrow.left.arrow.right.circle.fill").font(.title2).frame(width: 36, height: 36).contentShape(Rectangle())
                    }.disabled(loading || recovery).help("切换到 " + profile.email)
                }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                if saved.count > 1 {
                    HStack {
                        Button("上一页") { page = max(0, page - 1) }.disabled(page == 0)
                        Spacer(); Text("\(index + 1) / \(saved.count)").font(.caption); Spacer()
                        Button("下一页") { page = min(saved.count - 1, page + 1) }.disabled(page >= saved.count - 1)
                    }
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, LayoutRules.pagePadding)
        .task { if account == nil { await refresh() } }
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
                    Text(pool.reset.map { "重置 " + $0.formatted(.dateTime.month().day().hour().minute()) } ?? "重置时间未提供")
                        .font(.caption2).foregroundStyle(.secondary)
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
