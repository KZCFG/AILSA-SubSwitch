import Foundation
import Combine

@MainActor
final class TrayMenuModel: ObservableObject, AccountsManualRefreshServiceProtocol, AccountsLocalMutationSyncServiceProtocol {
    struct BackgroundRefreshPolicy: Sendable {
        let initialRefreshDelay: Duration
        let usageRefreshInterval: Duration
        let refreshUsageOnRecurringTick: Bool

        init(
            initialRefreshDelay: Duration,
            usageRefreshInterval: Duration,
            refreshUsageOnRecurringTick: Bool
        ) {
            self.initialRefreshDelay = initialRefreshDelay
            self.usageRefreshInterval = usageRefreshInterval
            self.refreshUsageOnRecurringTick = refreshUsageOnRecurringTick
        }

        static func forPlatform(_ platform: RuntimePlatform) -> BackgroundRefreshPolicy {
            _ = platform
            return BackgroundRefreshPolicy(
                initialRefreshDelay: .milliseconds(700),
                usageRefreshInterval: .seconds(10),
                refreshUsageOnRecurringTick: true
            )
        }
    }

    let accountsCoordinator: AccountsCoordinator
    let settingsCoordinator: SettingsCoordinator
    let backgroundRefreshPolicy: BackgroundRefreshPolicy
    let dateProvider: DateProviding
    let snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy
    let usageRefreshPlanningPolicy: AccountsUsageRefreshPlanningPolicy
    var usageRefreshTask: Task<Void, Never>?
    var workspaceMetadataRefreshTask: Task<Void, Never>?
    /// Backward-compatible aggregate used by the refresh loop. The two source
    /// settings remain separate so enabling Codex automation never implicitly
    /// enables AntiGravity native switching.
    var autoSmartSwitchEnabled = false
    private(set) var autoSmartSwitchCodexEnabled = false
    private(set) var autoSmartSwitchAntigravityEnabled = false
    var accountsRefreshActivityCount = 0
    var remoteUsageRefreshActivityCount = 0
    var remoteUsageRefreshActivityCountsByID: [String: Int] = [:]

    @Published var accounts: [AccountSummary] = []
    @Published var notice: String?
    @Published var isRefreshingAccounts = false
    @Published var isFetchingRemoteUsage = false
    @Published var remoteUsageRefreshingAccountIDs: Set<String> = []

    init(
        accountsCoordinator: AccountsCoordinator,
        settingsCoordinator: SettingsCoordinator,
        backgroundRefreshPolicy: BackgroundRefreshPolicy,
        dateProvider: DateProviding = SystemDateProvider(),
        snapshotFreshnessPolicy: AccountsSnapshotFreshnessPolicy = AccountsSnapshotFreshnessPolicy(),
        usageRefreshPlanningPolicy: AccountsUsageRefreshPlanningPolicy = AccountsUsageRefreshPlanningPolicy(),
        initialAccounts: [AccountSummary] = []
    ) {
        self.accountsCoordinator = accountsCoordinator
        self.settingsCoordinator = settingsCoordinator
        self.backgroundRefreshPolicy = backgroundRefreshPolicy
        self.dateProvider = dateProvider
        self.snapshotFreshnessPolicy = snapshotFreshnessPolicy
        self.usageRefreshPlanningPolicy = usageRefreshPlanningPolicy
        self.accounts = initialAccounts
    }

    deinit {
        usageRefreshTask?.cancel()
        workspaceMetadataRefreshTask?.cancel()
    }

    func acceptLocalAccountsSnapshot(_ accounts: [AccountSummary]) {
        AccountSwitchDebugLog.write(
            "tray.acceptLocalSnapshot",
            "incoming=\(AccountSwitchDebugLog.describe(accounts: accounts))"
        )
        self.accounts = accounts
    }

    func applySettings(_ settings: AppSettings) {
        autoSmartSwitchCodexEnabled = settings.autoSmartSwitch
        autoSmartSwitchAntigravityEnabled = settings.autoSmartSwitchAntigravity
        autoSmartSwitchEnabled = autoSmartSwitchCodexEnabled || autoSmartSwitchAntigravityEnabled
    }

    var title: String {
        guard let current = accounts.first(where: { $0.isCurrent }) else {
            return L10n.tr("tray.title.placeholder")
        }

        let metrics = compactMetrics(for: current)
        return L10n.tr(
            "tray.title.format_dynamic",
            metrics[0].label,
            metrics[0].valueText,
            metrics[1].label,
            metrics[1].valueText
        )
    }

    func accountLine(_ account: AccountSummary) -> String {
        let prefix = account.isCurrent ? L10n.tr("tray.account.current_prefix") : ""
        let metrics = compactMetrics(for: account)
        return L10n.tr(
            "tray.account.line.format_dynamic",
            prefix,
            account.label,
            metrics[0].label,
            metrics[0].valueText,
            metrics[1].label,
            metrics[1].valueText
        )
    }

    private struct CompactMetric {
        let label: String
        let valueText: String
    }

    /// AntiGravity only exposes compact values when its named quota summary is
    /// authoritative, matched to this account, and fresh. A model list or a
    /// stale cache must not make the tray look like it has a full quota pool.
    private func compactMetrics(for account: AccountSummary) -> [CompactMetric] {
        if account.provider == .antigravity,
           let usage = account.usage,
           usage.hasAuthoritativeQuota,
           usage.sourceAccountMatched != false,
           !usage.isStale(now: dateProvider.unixSecondsNow()) {
            let actual = usage.compactQuotaWindows.prefix(2).map { bucket in
                CompactMetric(
                    label: UsageQuotaDisplayName.bucket(bucket),
                    valueText: percent(remainingValue(usedPercent: bucket.usedPercent))
                )
            }
            return paddedMetrics(actual)
        }

        let legacy = [
            CompactMetric(
                label: L10n.tr("accounts.window.five_hour"),
                valueText: percent(remainingValue(usedPercent: account.usage?.fiveHour?.usedPercent))
            ),
            CompactMetric(
                label: L10n.tr("accounts.window.one_week"),
                valueText: percent(remainingValue(usedPercent: account.usage?.oneWeek?.usedPercent))
            )
        ]
        return account.provider == .antigravity
            ? paddedMetrics([])
            : legacy
    }

    private func paddedMetrics(_ metrics: [CompactMetric]) -> [CompactMetric] {
        Array(metrics.prefix(2)) + Array(
            repeating: CompactMetric(label: "--", valueText: "--"),
            count: max(0, 2 - metrics.count)
        )
    }

    private func remainingValue(usedPercent: Double?) -> Double? {
        guard let usedPercent,
              usedPercent.isFinite,
              (0...100).contains(usedPercent) else {
            return nil
        }
        return max(0, 100 - usedPercent)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int(value.rounded()))%"
    }

}
