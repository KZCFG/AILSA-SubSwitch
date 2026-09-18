import Foundation
import Combine

struct QuotaManagementHistoryWindow: Equatable, Sendable {
    let currentDay: Date
    let start: Date
    let endExclusive: Date

    func contains(_ day: Date) -> Bool {
        day >= start && day < endExclusive
    }
}

@MainActor
final class QuotaManagementPageModel: ObservableObject {
    static let historyDayCount = 30
    static let chartDaysPerPage = 7
    // Four rows plus inline header paging is what the fixed 760pt panel can
    // carry next to the summary, chart, and day-detail segments; three made
    // paging feel mandatory, five overflowed the panel with real data.
    static let rankingRowsPerPage = 4

    private let usageService: QuotaManagementUsageServiceProtocol
    private let dateProvider: () -> Date
    private var cursorAccountObserver: AnyCancellable?
    private var cursorGeneration = 0
    private var lastCursorAccountID: String?

    @Published var selectedProvider: QuotaManagementProvider = .codex {
        didSet {
            chartPage = 0
            rankingPage = 0
            selectedDay = Calendar.current.startOfDay(for: dateProvider())
        }
    }
    private(set) var expansionProvider: QuotaManagementProvider = .codex
    @Published private(set) var expansionRequestID = UUID()
    func requestExpansion(of provider: QuotaManagementProvider) {
        expansionProvider = provider
        expansionRequestID = UUID()
    }

    @Published var selectedSection: QuotaManagementSection = .overview
    @Published var chartMetric: QuotaChartMetric = .tokens
    @Published var openCodexChartMetric: OpenCodexChartMetric = .reportedTokens {
        didSet { rankingPage = 0 }
    }
    @Published var rankingDimension: UsageRankingDimension = .model {
        didSet { rankingPage = 0 }
    }
    @Published private(set) var chartPage = 0
    @Published private(set) var rankingPage = 0
    @Published var selectedDay: Date
    @Published private(set) var dataByProvider: [QuotaManagementProvider: QuotaManagementData] = [:]
    @Published private(set) var dashboards: [QuotaManagementProvider: QuotaDashboardSnapshot] = [:]
    @Published private(set) var loadingProviders: Set<QuotaManagementProvider> = []
    @Published private(set) var errorsByProvider: [QuotaManagementProvider: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published var notice: NoticeMessage?

    init(
        usageService: QuotaManagementUsageServiceProtocol,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.usageService = usageService
        self.dateProvider = dateProvider
        selectedDay = Calendar.current.startOfDay(for: dateProvider())
        cursorAccountObserver = NotificationCenter.default.publisher(for: .assCursorAccountDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self else { return }
                if let id = notification.userInfo?["accountID"] as? String {
                    guard id != self.lastCursorAccountID else { return }
                    self.lastCursorAccountID = id
                }
                self.cursorGeneration += 1
                let hadData = self.dashboards.removeValue(forKey: .cursor) != nil
                self.errorsByProvider[.cursor] = nil
                if hadData && !self.loadingProviders.contains(.cursor) {
                    Task { await self.loadDashboard(for: .cursor, force: true) }
                }
            }
    }

    static func live() -> QuotaManagementPageModel {
        QuotaManagementPageModel(usageService: LocalQuotaManagementUsageService())
    }

    var currentData: QuotaManagementData? {
        dataByProvider[selectedProvider]
    }

    var codexData: CodexUsageAnalytics? {
        guard case .codex(let data)? = currentData else { return nil }
        return data
    }

    var antigravityData: AntigravityUsageAnalytics? {
        guard case .antigravity(let data)? = currentData else { return nil }
        return data
    }

    /// The OpenCodex reader deliberately retains a complete local ledger for
    /// coverage and dedupe evidence. Presentation uses this explicit window
    /// for every user-facing day selector and rolling summary instead of
    /// treating the full reader result as a 30-day aggregate.
    var historyWindow: QuotaManagementHistoryWindow {
        let calendar = Calendar.current
        let currentDay = calendar.startOfDay(for: dateProvider())
        let start = calendar.date(
            byAdding: .day,
            value: -(Self.historyDayCount - 1),
            to: currentDay
        ) ?? currentDay
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: currentDay)
            ?? currentDay
        return QuotaManagementHistoryWindow(
            currentDay: currentDay,
            start: start,
            endExclusive: endExclusive
        )
    }

    var chartDates: [Date] {
        chartDates(for: chartPage, in: historyWindow)
    }

    private func chartDates(
        for page: Int,
        in window: QuotaManagementHistoryWindow
    ) -> [Date] {
        let calendar = Calendar.current
        let end = calendar.date(
            byAdding: .day,
            value: -(page * Self.chartDaysPerPage),
            to: window.currentDay
        ) ?? window.currentDay
        return (0..<Self.chartDaysPerPage).compactMap { offset in
            calendar.date(byAdding: .day, value: -(Self.chartDaysPerPage - 1 - offset), to: end)
        }
        .filter(window.contains)
    }

    var canShowOlderChartPage: Bool {
        !chartDates(for: chartPage + 1, in: historyWindow).isEmpty
    }

    var canShowNewerChartPage: Bool {
        chartPage > 0
    }

    /// Opening a surface refreshes existing dashboards without dropping them.
    /// Per-provider in-flight guards coalesce simultaneous menu/window opens.
    /// Menu/window open: every loaded provider refreshes, but Cursor reuses
    /// its cached history and fetches only the recent tail (see
    /// `CursorUsageService.HistoryRefresh.incremental`). Local providers are
    /// already incremental on disk, so "incremental" simply bypasses the TTL.
    func refreshOnWindowOpen(provider: QuotaManagementProvider? = nil) async {
        let providers = provider.map { Set([$0]) } ?? Set(dashboards.keys).union([.codex])
        await withTaskGroup(of: Void.self) { group in
            for provider in providers {
                group.addTask { await self.loadDashboard(for: provider, mode: .incremental) }
            }
        }
    }

    func loadIfNeeded() async {
        guard dashboards[selectedProvider] == nil else { return }
        await reloadCurrentProvider()
    }

    func refresh() async {
        await reloadCurrentProvider(force: true)
    }

    func selectProvider(_ provider: QuotaManagementProvider) {
        selectedProvider = provider
    }

    func selectSection(_ section: QuotaManagementSection) {
        selectedSection = section
    }

    func selectChartMetric(_ metric: QuotaChartMetric) {
        chartMetric = metric
    }

    func selectOpenCodexChartMetric(_ metric: OpenCodexChartMetric) {
        openCodexChartMetric = metric
    }

    func selectDay(_ day: Date) {
        let normalizedDay = Calendar.current.startOfDay(for: day)
        guard historyWindow.contains(normalizedDay) else { return }
        selectedDay = normalizedDay
        rankingPage = 0
    }

    func showOlderChartPage() {
        guard canShowOlderChartPage else { return }
        chartPage += 1
    }

    func showNewerChartPage() {
        guard canShowNewerChartPage else { return }
        chartPage -= 1
    }

    func selectRankingDimension(_ dimension: UsageRankingDimension) {
        rankingDimension = dimension
    }

    func showNextRankingPage(totalRows: Int) {
        showNextRankingPage(totalRows: totalRows, rowsPerPage: Self.rankingRowsPerPage)
    }

    func showNextRankingPage(totalRows: Int, rowsPerPage: Int) {
        guard rowsPerPage > 0,
              (rankingPage + 1) * rowsPerPage < totalRows
        else { return }
        rankingPage += 1
    }

    func showPreviousRankingPage() {
        guard rankingPage > 0 else { return }
        rankingPage -= 1
    }

    private func reloadCurrentProvider(force: Bool = false) async {
        await loadDashboard(for: selectedProvider, force: force)
    }

    enum RefreshMode: Sendable {
        /// Serve the in-memory dashboard while it is inside its TTL.
        case cachedIfFresh
        /// Reload now, letting Cursor reuse cached history for older days.
        case incremental
        /// Explicit user refresh: Cursor discards its cache and re-pages 30 days.
        case full
    }

    func loadDashboard(for provider: QuotaManagementProvider, force: Bool = false) async {
        await loadDashboard(for: provider, mode: force ? .full : .cachedIfFresh)
    }

    func loadDashboard(for provider: QuotaManagementProvider, mode: RefreshMode) async {
        guard !loadingProviders.contains(provider) else { return }
        if mode == .cachedIfFresh, let cached = dashboards[provider], dateProvider().timeIntervalSince(cached.scannedAt) < (provider == .cursor ? 300 : 60) { return }
        loadingProviders.insert(provider)
        isLoading = true
        errorsByProvider[provider] = nil
        loadError = nil
        defer {
            loadingProviders.remove(provider)
            isLoading = !loadingProviders.isEmpty
        }
        let generation = cursorGeneration
        do {
            if provider == .cursor {
                switch mode {
                case .cachedIfFresh: await CursorUsageService.shared.scheduleNextRefresh(.cachedIfFresh)
                case .incremental: await CursorUsageService.shared.scheduleNextRefresh(.incremental)
                case .full: await CursorUsageService.shared.scheduleNextRefresh(.full)
                }
            }
            let service = usageService
            let now = dateProvider()
            let snapshot = try await Task.detached(priority: .userInitiated) {
                try await service.loadDashboard(for: provider, now: now)
            }.value
            if provider == .cursor && generation != cursorGeneration {
                loadingProviders.remove(provider)
                await loadDashboard(for: provider, force: true)
                return
            }
            dashboards[provider] = snapshot
        } catch {
            if provider == .cursor && generation != cursorGeneration {
                loadingProviders.remove(provider)
                await loadDashboard(for: provider, force: true)
                return
            }
            errorsByProvider[provider] = error.localizedDescription
            if selectedProvider == provider { loadError = error.localizedDescription }
        }
    }
}
