import SwiftUI
import Charts

private func qtext(_ chinese: String, _ english: String) -> String {
    L10n.currentLocale.identifier.hasPrefix("zh") ? chinese : english
}
/// Renders one pricing basis with its own verification date. Dates are never
/// merged across bases: the standard-rate table, the audited catalog, the
/// models.dev cache and vendor-reported amounts each carry their own.
enum QuotaPricingProvenanceText {
    static func line(_ item: QuotaPricingProvenance) -> String {
        let label: String
        switch item.basis {
        case .standardReference: label = qtext("参考价依据：官方标准价格表", "Reference basis: official standard rate table")
        case .verifiedCatalog: label = qtext("已确认档位依据：已审计定价目录", "Confirmed-tier basis: audited pricing catalog")
        case .modelsDevCache: label = qtext("参考价依据：models.dev 本地缓存", "Reference basis: models.dev local cache")
        case .vendorReported: label = qtext("金额依据：供应商用量接口报告", "Amount basis: vendor usage API")
        }
        guard let date = item.auditDate else { return label + qtext("（无核对日期）", " (no verification date)") }
        return label + qtext("（核对日期 \(date)）", " (checked \(date))")
    }
}
enum QuotaTokenFormatter {
    static func format(_ value: Int, unit: String) -> String {
        let divisor = unit == "B" ? 1e9 : 1e6
        return String(format: "%.3f%@", Double(value) / divisor, unit == "B" ? "B" : "M")
    }
}
private func qmoney(_ value: QuotaMoney) -> String {
    guard let usd = value.usd else { return "—" }
    return usd.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
}
private func qpercent(_ numerator: Int, _ denominator: Int) -> String {
    denominator > 0 ? "\(Int((Double(numerator) / Double(denominator) * 100).rounded()))%" : "—"
}

struct QuotaManagementPageView: View {
    @ObservedObject var model: QuotaManagementPageModel
    var isStandalone = false
    @State private var selectedProvider: QuotaManagementProvider = .codex
    /// Range/page/sort per provider survive provider switches; hover and
    /// detail state live inside `QuotaDashboard` and reset with `.id`.
    @State private var dashboardStates: [QuotaManagementProvider: QuotaDashboardUIState] = [:]
    private var isLoading: Bool { model.loadingProviders.contains(selectedProvider) }
    private var loadError: String? { model.errorsByProvider[selectedProvider] }
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 10) {
                header
                providerPicker
                if let data = model.dashboards[selectedProvider] {
                    QuotaDashboard(
                        data: data,
                        availableHeight: max(200, geometry.size.height - 114),
                        ui: Binding(
                            get: { dashboardStates[selectedProvider] ?? QuotaDashboardUIState() },
                            set: { dashboardStates[selectedProvider] = $0 }))
                        .id(selectedProvider)
                } else if isLoading {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text(selectedProvider == .cursor ? qtext("正在读取 Cursor 用量，首次可能需要约半分钟…", "Reading Cursor usage; the first load may take about 30 seconds…") : qtext("正在读取本机用量…", "Reading local usage…"))
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    ContentUnavailableView(qtext("暂无数据", "No data"), systemImage: "chart.bar", description: Text(loadError ?? qtext("点击刷新读取本机用量", "Refresh to read local usage")))
                }
                if let error = loadError, model.dashboards[selectedProvider] != nil {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1).help(error)
                }
            }
            .padding(.horizontal, LayoutRules.pagePadding).padding(.vertical, 10)
        }
        .task(id: selectedProvider) { await model.loadDashboard(for: selectedProvider) }
        .onAppear {
            if isStandalone {
                selectedProvider = model.expansionProvider
                Task { await model.refreshOnWindowOpen(provider: selectedProvider) }
            }
        }
        .onChange(of: model.expansionRequestID) { _, _ in
            if isStandalone {
                selectedProvider = model.expansionProvider
                Task { await model.refreshOnWindowOpen(provider: selectedProvider) }
            }
        }
        .appCanvas()
    }
    private var header: some View {
        HStack {
                    Text(L10n.tr("tab.quota_management")).font(.title3.bold())
                    Spacer()
                    if !isStandalone {
                        Button {
                            model.requestExpansion(of: selectedProvider)
                            #if os(macOS)
                            SubSwitchApplicationDelegate.current?.showQuotaWindow()
                            NSApp.activate(ignoringOtherApps: true)
                            #endif
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right").frame(width: 30, height: 28)
                        }.accessibilityLabel(qtext("展开额度管理", "Open usage window"))
                    }
                    if let data = model.dashboards[selectedProvider] {
                        Text(data.scannedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                    Button { Task { await model.loadDashboard(for: selectedProvider, force: true) } } label: {
                        Image(systemName: "arrow.clockwise").frame(width: 30, height: 28)
                    }.disabled(isLoading).accessibilityLabel(qtext("刷新额度", "Refresh usage"))
                    if isLoading { ProgressView().controlSize(.small) }
                }.frame(height: 32)
    }
    private var providerPicker: some View {
        ASSegmentedControl<QuotaManagementProvider>(
            selection: Binding(get: { selectedProvider }, set: { selectedProvider = $0 }),
            values: QuotaManagementProvider.allCases,
            title: { provider in
                switch provider { case .codex: "Codex"; case .antigravity: "Antigravity"; case .cursor: "Cursor" }
            },
            icon: { provider in
                switch provider { case .codex: "terminal"; case .antigravity: "sparkles"; case .cursor: "cube" }
            })
    }
}

/// Navigation state a provider keeps while another provider is shown.
struct QuotaDashboardUIState: Equatable {
    var range = 1
    var selectedDay: Date?
    var page = 0
    var chartPage = 0
    var quotaWindow = ""
    var sortUSD = false
}

private struct QuotaDashboard: View {
    let data: QuotaDashboardSnapshot
    let availableHeight: Double
    @Binding var ui: QuotaDashboardUIState
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    private var range: Int { get { ui.range } nonmutating set { ui.range = newValue } }
    private var selectedDay: Date? { get { ui.selectedDay } nonmutating set { ui.selectedDay = newValue } }
    private var page: Int { get { ui.page } nonmutating set { ui.page = newValue } }
    private var chartPage: Int { get { ui.chartPage } nonmutating set { ui.chartPage = newValue } }
    private var quotaWindow: String { get { ui.quotaWindow } nonmutating set { ui.quotaWindow = newValue } }
    private var sortUSD: Bool { get { ui.sortUSD } nonmutating set { ui.sortUSD = newValue } }
    @AppStorage("ass.trendStyle") private var trendStyle = "bar"
    // Transient pointer/detail state: intentionally not carried across providers.
    @State private var hoveredDay: Date?
    @State private var hoveredMinute: Date?
    @AppStorage("ass.intradayMinutes") private var interval = 5
    @State private var detail: QuotaDetailRequest?
    @EnvironmentObject private var modal: ASModalHost
    private func qtokens(_ value: Int) -> String { QuotaTokenFormatter.format(value, unit: tokenUnit) }
    private var calendar: Calendar { .current }
    private var today: Date { calendar.startOfDay(for: data.scannedAt) }
    private var start: Date { selectedDay ?? calendar.date(byAdding: .day, value: -(range - 1), to: today)! }
    private var end: Date { calendar.date(byAdding: .day, value: 1, to: selectedDay ?? today)! }
    private var isQuota: Bool { data.source == "Antigravity" }
    var body: some View {
        // At most 30 small day buckets and model rows; no records or I/O in body.
        let bucket = hoveredMinute.flatMap { range == 1 && !isQuota ? data.intradayBucket(from: $0, intervalMinutes: interval) : nil } ?? data.bucket(from: start, until: end)
        let layout = QuotaDashboardLayout(height: availableHeight, expandedIntraday: range == 1 && !isQuota)
        let families = bucket.models.reduce(into: [QuotaModelKey: QuotaAggregate]()) { result, entry in
            result[entry.key.familyKey, default: QuotaAggregate()].merge(entry.value)
        }
        let rows = families.sorted { left, right in
            if sortUSD {
                let a = left.value.reference.usd ?? -1, b = right.value.reference.usd ?? -1
                if a != b { return a > b }
            } else if left.value.tokens.total != right.value.tokens.total { return left.value.tokens.total > right.value.tokens.total }
            return (left.key.provider + left.key.model) < (right.key.provider + right.key.model)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ASSegmentedControl(
                    selection: Binding(get: { range }, set: { range = $0; selectedDay = nil; hoveredMinute = nil; page = 0; chartPage = 0 }),
                    values: [1, 7, 30],
                    title: { $0 == 1 ? (hoveredMinute != nil && range == 1 ? qtext("瞬时", "Instant") : qtext("今日", "Today")) : "\($0) " + qtext("天", "days") })
                if let day = selectedDay {
                    Button { selectedDay = nil; page = 0 } label: {
                        Text(day.formatted(.dateTime.month(.twoDigits).day(.twoDigits)) + " ×").font(.caption)
                    }.help(qtext("返回所选范围", "Return to range"))
                }
            }.frame(height: 42)
            if isQuota {
                Text(qtext("历史为每日最近一次额度快照，不等于当日实际消耗。", "History records the latest quota snapshot per day, not daily consumption.")).font(.caption2).foregroundStyle(.secondary)
                quotaContent(layout: layout)
            } else {
                HStack(spacing: 10) {
                    kpi("Token", value: bucket.total.reported > 0 ? qtokens(bucket.total.tokens.total) : "—", detail: qtext("输入", "In") + " " + qtokens(bucket.total.tokens.input) + " · " + qtext("输出", "Out") + " " + qtokens(bucket.total.tokens.output))
                    kpi(qtext("API 参考价 · 非账单", "API estimate · not billed"), value: qmoney(bucket.total.reference), detail: qtext("记录覆盖", "Coverage") + " " + qpercent(bucket.total.reference.count, bucket.total.reported))
                }.frame(height: 78)
                HStack {
                    Text(qtext("按模型", "Models")).font(.subheadline.bold())
                    Spacer()
                    Button("Token" + (!sortUSD ? " ↓" : "")) { sortUSD = false; page = 0 }.buttonStyle(.plain)
                        .frame(minWidth: 44, minHeight: 24).contentShape(Rectangle())
                        .accessibilityLabel(qtext("按 Token 排序", "Sort by tokens")).accessibilityAddTraits(sortUSD ? [] : .isSelected)
                    Button("USD" + (sortUSD ? " ↓" : "")) { sortUSD = true; page = 0 }.buttonStyle(.plain).frame(width: 90, alignment: .trailing)
                        .frame(minHeight: 24).contentShape(Rectangle())
                        .accessibilityLabel(qtext("按 USD 排序", "Sort by USD")).accessibilityAddTraits(sortUSD ? .isSelected : [])
                }.font(.caption).frame(height: 24)
                if rows.isEmpty {
                    Text(qtext("此范围暂无请求", "No requests in this range")).foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: CGFloat(layout.rows * 33))
                } else {
                    ScrollView(.vertical) {
                      LazyVStack(spacing: 0) {
                        ForEach(rows, id: \.key) { key, value in
                            Button { detail = QuotaDetailRequest(total: value, title: key == .unknown ? qtext("未解析路由", "Unresolved route") : key.provider.isEmpty ? key.model : key.provider + " / " + key.model, members: bucket.models.keys.filter { $0.familyKey == key }.map { $0.provider + " / " + $0.model }.sorted()) } label: {
                                HStack(spacing: 10) {
                                    Text(key == .unknown ? qtext("未解析路由", "Unresolved route") : key.model)
                                        .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(value.reported > 0 ? qtokens(value.tokens.total) : "—").monospacedDigit().frame(width: 72, alignment: .trailing)
                                    Text(qmoney(value.reference) + (value.reference.count > 0 && value.reference.count < value.reported ? "*" : "")).monospacedDigit().frame(width: 90, alignment: .trailing)
                                }.font(.system(size: 12)).frame(height: 32).contentShape(Rectangle())
                            }.buttonStyle(.plain).help(key.provider.isEmpty ? key.model : key.provider + " / " + key.model)
                            Divider()
                        }
                      }.padding(.horizontal, 10)
                    }
                    .scrollIndicators(.visible)
                    .frame(height: CGFloat(layout.rows * 33 + 10), alignment: .top)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
                    .accessibilityLabel(qtext("模型用量列表，可上下滚动", "Model usage list, scroll vertically"))
                }
                HStack {
                    Text(qtext("点击查看详情 · * 部分记录有价格", "Details · * partially priced")).foregroundStyle(.secondary)
                    Spacer()
                    Text(qtext("共 \(rows.count) 个模型", "\(rows.count) models"))
                    if rows.count > layout.rows {
                        Image(systemName: "arrow.up.arrow.down").foregroundStyle(.tertiary)
                    }
                }.font(.caption2).frame(height: 16)
            }
            if layout.showsTrend {
                if range == 1 && selectedDay == nil && !isQuota {
                    QuotaIntradayChart(minutes: data.minuteTokens, now: data.scannedAt, hovered: $hoveredMinute).frame(height: 180)
                } else { trend.frame(height: 76) }
            }
            else { Button(qtext("查看趋势", "Show trend")) { detail = QuotaDetailRequest(total: bucket.total, title: nil, trend: true) }.font(.caption) }
            Spacer(minLength: 0)
            HStack {
                Text(data.source).lineLimit(1)
                Spacer()
                if !isQuota { Text(qtext("计量", "Metered") + " " + qpercent(bucket.total.reported, bucket.total.requests - bucket.total.aborted)) }
                Button { detail = QuotaDetailRequest(total: bucket.total, title: nil) } label: { Label(qtext("数据说明", "Details"), systemImage: "info.circle") }
            }.font(.caption).foregroundStyle(.secondary).frame(height: 26)
        }
        .onChange(of: hoveredMinute) { _, _ in page = 0 }
        .onChange(of: detail?.id) { _, _ in
            guard let request = detail else { return }
            modal.present(onClose: { detail = nil }) {
                if request.trend {
                    VStack { trend; Button(qtext("关闭", "Close")) { modal.close() } }
                        .padding(20).frame(width: 430, height: 180)
                } else {
                    QuotaDetails(data: data, total: request.total, modelName: request.title, members: request.members, onClose: { modal.close() })
                }
            }
        }
    }

    /// Paging arrow with a 28×24 hit area and a VoiceOver name.
    private func pagerArrow(_ symbol: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(minWidth: 28, minHeight: 24).contentShape(Rectangle()) }
            .disabled(disabled).accessibilityLabel(label)
    }
    private func kpi(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            .background(Color.primary.opacity(0.035)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private var selectedQuotaWindowID: String { quotaWindow.isEmpty ? (data.quotaWindows.first?.windowName ?? "") : quotaWindow }
    @ViewBuilder private func quotaContent(layout: QuotaDashboardLayout) -> some View {
        let history = (data.quotaTrends[selectedQuotaWindowID] ?? [:]).filter { $0.key >= start && $0.key < end }.sorted { $0.key > $1.key }
        let name = data.quotaWindows.first { $0.windowName == selectedQuotaWindowID }?.displayName ?? "—"
        HStack(spacing: 10) {
            kpi(qtext("已记录天数", "Recorded days"), value: String(history.count), detail: name)
            kpi("Token / USD", value: "—", detail: qtext("来源仅提供额度百分比", "Source reports quota only"))
        }.frame(height: 78)
        HStack { Text(qtext("历史快照", "Quota history")).font(.subheadline.bold()); Spacer(); Text(qtext("已用额度", "Quota used")).font(.caption) }.frame(height: 24)
        let pageCount = max(1, (history.count + layout.rows - 1) / layout.rows)
        let safe = min(page, pageCount - 1)
        if history.isEmpty { Text(qtext("所选日期暂无快照；启用后逐日积累。", "No snapshots in this range; history accumulates after enabling.")).font(.caption).foregroundStyle(.secondary) }
        ForEach(Array(history.dropFirst(safe * layout.rows).prefix(layout.rows)), id: \.key) { day, used in
            HStack {
                Text(day.formatted(.dateTime.month().day())).frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f%%", used)).monospacedDigit()
            }.font(.caption).frame(height: 32)
        }
        HStack { Spacer(); Text("\(safe + 1) / \(pageCount)").accessibilityLabel(L10n.tr("common.page_format", String(safe + 1), String(pageCount)))
            pagerArrow("chevron.left", label: L10n.tr("common.previous_page"), disabled: safe == 0) { page = max(0, safe - 1) }
            pagerArrow("chevron.right", label: L10n.tr("common.next_page"), disabled: safe + 1 >= pageCount) { page = safe + 1 }
        }.font(.caption).frame(height: 26)
    }
    private var dates: [Date] {
        (0..<range).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
            .filter { $0 < end }
    }
    private var trend: some View {
        let days = dates
        let values = days.map { day -> Double? in
            if isQuota { return data.quotaTrends[selectedQuotaWindowID]?[day] }
            guard let total = data.days[day]?.total, total.reported > 0 else { return nil }
            return sortUSD ? total.reference.usd : Double(total.tokens.total)
        }
        return VStack(spacing: 4) {
            if isQuota {
                Picker("额度窗口", selection: Binding(get: { quotaWindow.isEmpty ? (data.quotaWindows.first?.windowName ?? "") : quotaWindow }, set: { quotaWindow = $0 })) {
                    ForEach(data.quotaWindows) { Text($0.displayName).tag($0.windowName) }
                }.font(.caption)
            }
            HStack {
                if let hoveredDay, let index = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: hoveredDay) }) {
                    Text(days[index].formatted(.dateTime.month().day()) + " · " + (values[index].map {
                        if isQuota { return String(format: "%.1f%%", $0) }
                        if sortUSD { return String(format: "$%.2f", $0) }
                        return String(format: "%.3f%@ Token", $0 / (tokenUnit == "B" ? 1e9 : 1e6), tokenUnit == "B" ? "B" : "M")
                    } ?? "—"))
                } else { Text(isQuota ? qtext("每日最新额度", "Latest quota per day") : "Token / USD") }
                Spacer()
                Picker("图表", selection: $trendStyle) {
                    Image(systemName: "chart.bar").tag("bar")
                    Image(systemName: "chart.xyaxis.line").tag("line")
                }.labelsHidden().pickerStyle(.segmented).frame(width: 70)
            }.font(.caption)
            Chart(Array(days.enumerated()), id: \.element) { index, day in
                if let value = values[index] {
                    if trendStyle == "line" {
                        LineMark(x: .value("日期", day), y: .value("用量", value)).foregroundStyle(.indigo).interpolationMethod(.linear)
                        PointMark(x: .value("日期", day), y: .value("用量", value)).foregroundStyle(.indigo).symbol(Circle()).symbolSize(20)
                    } else {
                        BarMark(x: .value("日期", day, unit: .day), y: .value("用量", value))
                            .foregroundStyle(.indigo.gradient).cornerRadius(2)
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if let frame = proxy.plotFrame { hoveredDay = proxy.value(atX: location.x - geometry[frame].minX) }
                        case .ended: hoveredDay = nil
                        }
                    }
                }
            }
        }
    }
}

private struct QuotaDetailRequest: Identifiable {
    let id = UUID()
    let total: QuotaAggregate
    let title: String?
    var trend = false
    var members: [String] = []
}

private struct QuotaDetails: View {
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    let data: QuotaDashboardSnapshot
    let total: QuotaAggregate
    let modelName: String?
    var members: [String] = []
    private var pageCount: Int { 3 + (members.count + 5) / 6 }
    @State private var page = 0
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(modelName ?? qtext("数据说明", "Data details")).font(.headline).lineLimit(2); Spacer(); Button(qtext("关闭", "Close")) { onClose() } }
            if data.source == "Antigravity" {
                row(qtext("Token 用量", "Token usage"), qtext("来源未提供", "Not provided"))
                row(qtext("等效 USD", "Equivalent USD"), qtext("无法估算", "Unavailable"))
                row(qtext("额度窗口", "Quota windows"), String(data.quotaWindows.count))
                Text(qtext("此数据源仅提供额度百分比及重置时间，没有逐次请求的 Token 或价格数据。未知不等于零。", "This source reports quota percentages and resets, not per-request tokens or pricing. Unknown does not mean zero.")).font(.callout)
                Text(qtext("历史图按日期展示最近一次额度快照，不能视为每日实际消耗；重置后百分比可能下降。", "History shows the latest quota snapshot per day, not daily consumption; resets can reduce the percentage.")).font(.callout).foregroundStyle(.secondary)
            } else if page == 0 {
                if data.source == "Cursor" { row("Cursor-metered", qmoney(total.metered)) }
                row(qtext("输入 Token", "Input tokens"), QuotaTokenFormatter.format(total.tokens.input, unit: tokenUnit))
                row(qtext("缓存读取（包含在输入）", "Cached read (included in input)"), QuotaTokenFormatter.format(total.tokens.cachedInput, unit: tokenUnit))
                row(qtext("输出 Token", "Output tokens"), QuotaTokenFormatter.format(total.tokens.output, unit: tokenUnit))
                row(qtext("推理（包含在输出）", "Reasoning (included in output)"), QuotaTokenFormatter.format(total.tokens.reasoningOutput, unit: tokenUnit))
                row(qtext("API 参考价", "Standard API estimate"), qmoney(total.reference))
                row(qtext("已确认档位参考价", "Confirmed-tier equivalent"), qmoney(total.confirmed))
                Text(qtext("两种金额独立，不能相加。参考价不是实际账单，不包含无法确认的 Fast、工具、地区或订阅费用。", "Amounts are separate and must not be added. Estimates are not bills and exclude unverified Fast, tool, regional or subscription fees.")).font(.caption).foregroundStyle(.secondary)
            } else if page == 1 {
                row(qtext("当前范围请求", "Requests in range"), String(total.requests))
                row(qtext("已报告用量", "Usage reported"), "\(total.reported) / \(total.requests - total.aborted)")
                row(qtext("有参考价", "Reference priced"), "\(total.reference.count) / \(total.reported)")
                row(qtext("已中止", "Aborted"), String(total.aborted))
                row(qtext("未解析路由", "Unresolved routes"), String(total.unknownRoute))
                row(qtext("全量请求（非当前范围）", "All-time requests"), String(data.all.requests))
                row(qtext("丢弃重复／跳过", "Duplicates / skipped"), String(data.discardedRows))
            } else if page == 2 {
                Text(qtext("数据来自本机记录或供应商用量接口。未知金额显示 —，不会按请求别名猜测实际模型；未解析请求合并展示，仍保留真实用量。", "Data comes from local records or provider usage APIs. Unknown amounts show —. Requested aliases are not assumed to be resolved models; unresolved requests are grouped without discarding reported usage.")).font(.callout)
                Text(data.source == "Cursor" ? qtext("参考金额来自 Cursor 用量接口提供的供应商等效价格；Cursor-metered 单独展示接口报告的计费金额，二者不能相加。", "Reference amounts are vendor equivalents reported by Cursor. Cursor-metered is the separately reported charge; do not add them.") : qtext("已知价格生效日和峰谷时段按请求时间计算。参考价不是历史实付账单。", "Known effective dates and peak periods follow request time. Estimates are not historical bills.")).font(.callout)
                ForEach(data.pricingProvenance, id: \.self) { item in
                    Text(QuotaPricingProvenanceText.line(item)).font(.caption).foregroundStyle(.secondary)
                }
                Text(data.source).font(.caption).foregroundStyle(.secondary)
            } else {
                Text(qtext("合并的模型与来源", "Grouped models and providers")).font(.subheadline.bold())
                ForEach(Array(members.dropFirst((page - 3) * 6).prefix(6)), id: \.self) { Text($0).font(.caption).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
            if data.source != "Antigravity" { HStack { Button(qtext("上一页", "Previous")) { page -= 1 }.disabled(page == 0); Spacer(); Text("\(page + 1) / \(pageCount)"); Spacer(); Button(qtext("下一页", "Next")) { page += 1 }.disabled(page + 1 >= pageCount) }.font(.caption) }
        }.padding(20).frame(width: 430, height: 390)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit() }.font(.caption)
    }
}
