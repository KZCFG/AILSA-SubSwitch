import SwiftUI
import Charts
import AppKit

/// Compact minute aggregates only; no ledger reads on the UI thread.
struct QuotaIntradayChart: View {
    let minutes: [Date: QuotaBucket]
    let now: Date
    let metric: QuotaChartMetric
    @Binding var hovered: Date?
    @AppStorage("ass.intradayMinutes") private var interval = 5
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    @State private var scrollPosition = Calendar.current.startOfDay(for: Date())
    private var step: Double { Double(max(1, interval) * 60) }
    private func text(_ chinese: String, _ english: String) -> String {
        L10n.currentLocale.identifier.hasPrefix("zh") ? chinese : english
    }
    private var start: Date { Calendar.current.startOfDay(for: now) }
    private var end: Date { Calendar.current.date(byAdding: .day, value: 1, to: start)! }
    // 48 evenly spaced marks is the same density as a full day at 30 minutes.
    private var visibleSeconds: Double { min(end.timeIntervalSince(start), step * 48) }
    private var points: [QuotaIntradayPoint] {
        QuotaIntradaySeries.points(minutes: minutes, now: now, intervalMinutes: interval, metric: metric)
    }
    var body: some View {
        let values = points
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(hovered.map { date in
                    let amount = values.first(where: { $0.date == date })?.value
                    return date.formatted(.dateTime.hour().minute().locale(L10n.currentLocale))
                        + " · " + (amount.map { metric.formatted($0, tokenUnit: tokenUnit) } ?? "—")
                        + text("（\(interval) 分钟）", " (\(interval) min)")
                } ?? L10n.tr(metric.titleKey))
                Spacer()
                Picker(text("间隔", "Interval"), selection: $interval) {
                    ForEach([1, 5, 10, 30, 60], id: \.self) { Text($0 == 60 ? text("1 小时", "1 hour") : text("\($0) 分钟", "\($0) min")).tag($0) }
                }.labelsHidden().frame(width: 95)
            }.font(.caption)
            if values.isEmpty {
                Text(metric == .tokens ? text("暂无分钟级记录", "No minute-level records") : text("暂无可用的分钟级美元金额", "No priced minute-level records")).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Chart(values) { point in
                    if let amount = point.value {
                        LineMark(x: .value(text("时间", "Time"), point.date), y: .value(L10n.tr(metric.titleKey), amount))
                            .foregroundStyle(.indigo).lineStyle(StrokeStyle(lineWidth: 1.5)).interpolationMethod(.linear)
                        PointMark(x: .value(text("时间", "Time"), point.date), y: .value(L10n.tr(metric.titleKey), amount))
                            .foregroundStyle(.indigo).symbol(Circle()).symbolSize(18)
                    }
                    if hovered == point.date {
                        RuleMark(x: .value(text("时间", "Time"), point.date)).foregroundStyle(.secondary.opacity(0.4))
                    }
                }
                .chartXScale(domain: start...end)
                .chartScrollableAxes(.horizontal)
                .chartXVisibleDomain(length: visibleSeconds)
                .chartScrollPosition(x: $scrollPosition)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let amount = value.as(Double.self) { Text(metric.formatted(amount, tokenUnit: tokenUnit)) } }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ChartTrackpadPan { delta in
                            guard let frame = proxy.plotFrame else { return }
                            let width = geometry[frame].width
                            guard width > 0 else { return }
                            let latest = end.addingTimeInterval(-visibleSeconds)
                            scrollPosition = min(latest, max(start,
                                scrollPosition.addingTimeInterval(-delta / width * visibleSeconds * 2)))
                            hovered = nil
                        }
                        .allowsHitTesting(false)
                        Color.clear.contentShape(Rectangle()).onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let frame = proxy.plotFrame else { hovered = nil; return }
                                let plot = geometry[frame]
                                guard location.y >= plot.minY, location.y <= plot.maxY,
                                      let date: Date = proxy.value(atX: location.x - plot.minX),
                                      let point = values.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }),
                                      abs(point.date.timeIntervalSince(date)) <= step / 2 else { hovered = nil; return }
                                if hovered != point.date { hovered = point.date }
                            case .ended: hovered = nil
                            }
                        }
                    }
                }
            }
        }
        .onAppear { scrollPosition = max(start, now.addingTimeInterval(-visibleSeconds)); hovered = nil }
        .onChange(of: interval) { _, _ in scrollPosition = max(start, now.addingTimeInterval(-visibleSeconds)); hovered = nil }
        .onChange(of: metric) { _, _ in hovered = nil }
        .onChange(of: scrollPosition) { _, _ in hovered = nil }
        .onDisappear { hovered = nil }
    }
}

/// Observe wheel events before the hover overlay / enclosing scroll view can
/// consume them. Only horizontal gestures inside this chart belong to us.
private struct ChartTrackpadPan: NSViewRepresentable {
    var onPan: (Double) -> Void
    func makeNSView(context: Context) -> PanView { PanView(onPan: onPan) }
    func updateNSView(_ view: PanView, context: Context) { view.onPan = onPan }
    static func dismantleNSView(_ view: PanView, coordinator: ()) { view.stop() }

    final class PanView: NSView {
        var onPan: (Double) -> Void
        private var monitor: Any?
        init(onPan: @escaping (Double) -> Void) {
            self.onPan = onPan
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      !self.isHiddenOrHasHiddenAncestor,
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                      abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return event }
                let scale = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
                self.onPan(Double(event.scrollingDeltaX) * scale)
                return nil
            }
        }
        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
