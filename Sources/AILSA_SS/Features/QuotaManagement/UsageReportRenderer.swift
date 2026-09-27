import AppKit
import SwiftUI
import Charts

struct UsageReportPoster: View {
    let report: UsageReport
    var metric: QuotaChartMetric = .tokens
    var tokenUnit = "M"
    private let ink = Color(white: 0.07)
    private let muted = Color(white: 0.44)
    private let surface = Color(white: 0.965)
    private func text(_ zh: String, _ en: String) -> String { UsageReportText.text(zh, en) }
    private func tokens(_ value: Int) -> String { QuotaTokenFormatter.format(value, unit: tokenUnit) }
    private func money(_ value: QuotaMoney) -> String {
        value.usd.map { $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US"))) } ?? "—"
    }
    private func modelName(_ name: String) -> String {
        let parts = name.split(separator: "-")
        if parts.count == 3 && parts[0] == "gpt" { return "GPT-\(parts[1]) \(parts[2].capitalized)" }
        return name
    }
    private func date(_ value: Date, compact: Bool = false) -> String {
        let f = DateFormatter(); f.locale = L10n.currentLocale
        if L10n.currentLocale.identifier.hasPrefix("zh") { f.dateFormat = compact ? "M 月 d 日" : "yyyy 年 M 月 d 日" }
        else { f.setLocalizedDateFormatFromTemplate(compact ? "MMMd" : "yyyyMMMMd") }
        return f.string(from: value)
    }
    private var title: String {
        report.request.period == .daily ? date(report.interval.start)
            : date(report.interval.start, compact: true) + " — " + date(report.request.endingOn)
    }
    private var timeLabel: String {
        let f = DateFormatter(); f.dateFormat = "ZZZZ"; f.locale = Locale(identifier: "en_US")
        let zone = f.string(from: report.interval.start)
        if report.partialPeriod {
            let time = report.generatedAt.formatted(.dateTime.hour().minute().locale(L10n.currentLocale))
            return text("截至 \(time) · \(zone)", "Through \(time) · \(zone)")
        }
        return report.request.period == .daily ? "00:00—24:00 · \(zone)" : "\(report.request.period.days) " + text("天", "days") + " · \(zone)"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 13) {
                if let url = Bundle.main.url(forResource: "AILSASubSwitch", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().frame(width: 53, height: 53)
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("AILSA SubSwitch").font(.system(size: 22, weight: .semibold))
                    Text(text("一眼看用量，一键切账户。", "Weekly usage at a glance. Switch accounts in a click."))
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                Spacer()
                Text(report.request.period.rawValue.uppercased() + " USAGE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(muted)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label(report.request.providerName + text(" 用量", " usage"), systemImage: report.request.provider == .cursor ? "cube" : "terminal")
                    .font(.system(size: 15, weight: .semibold))
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.system(size: report.request.period == .daily ? 31 : 25, weight: .bold))
                        .lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength: 12)
                    Text(timeLabel).font(.system(size: 11)).foregroundStyle(muted)
                }
            }
            HStack(spacing: 12) {
                card(text("Token 词元消耗", "Token usage"), report.total.reported > 0 ? tokens(report.total.tokens.total) : "—",
                     text("输入", "In") + " " + tokens(report.total.tokens.input) + " · " + text("输出", "Out") + " " + tokens(report.total.tokens.output))
                card(text("等效 API 消费金额（美元）", "Equivalent API cost (USD)"), money(report.total.reference),
                     text("可核算记录合计 · 非实际账单", "Priced records · Not an actual bill"))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(text("按模型", "Models")).font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("Token").frame(width: 126, alignment: .trailing)
                    Text("USD").frame(width: 100, alignment: .trailing)
                }.font(.system(size: 12)).foregroundStyle(muted).padding(.bottom, 12)
                ForEach(report.rows) { row in
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 2).fill(row.name == "Grok 4.7" ? Color.indigo : ink.opacity(0.22)).frame(width: 4, height: 22)
                        Text(modelName(row.name)).font(.system(size: 16, weight: row.name == "Grok 4.7" ? .semibold : .medium))
                            .lineLimit(1).minimumScaleFactor(0.7)
                        if row.includesGrokBuildFast {
                            Text(text("含 Fast", "incl. Fast")).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.indigo)
                                .padding(.horizontal, 7).padding(.vertical, 4).background(Color.indigo.opacity(0.08), in: Capsule())
                        }
                        Spacer(minLength: 0)
                        Text(row.value.reported > 0 ? tokens(row.value.tokens.total) : "—").frame(width: 126, alignment: .trailing)
                        Text(money(row.value.reference)).frame(width: 100, alignment: .trailing)
                    }.font(.system(size: 16, weight: .medium)).monospacedDigit().frame(height: 45)
                    if row.id != report.rows.last?.id { Rectangle().fill(ink.opacity(0.055)).frame(height: 1) }
                }
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(metric == .tokens ? text("Token 用量走势", "Token usage over time") : text("等效 API 金额走势", "Equivalent API cost over time"))
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(report.request.period == .daily ? text("每 30 分钟合计", "30-minute totals") : text("每日合计", "Daily totals"))
                        .font(.system(size: 12)).foregroundStyle(muted)
                }
                chart.frame(height: 218)
            }
            VStack(alignment: .leading, spacing: 9) {
                Rectangle().fill(ink.opacity(0.1)).frame(height: 1)
                Text(text("金额按可核算记录计算；未定价或字段矛盾的记录不估算金额。", "Amounts cover priced records only. Unpriced or inconsistent records are not estimated."))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(text("本地真实用量 · 账号与个人信息已移除", "Local usage · Accounts and personal details omitted"))
                    Spacer()
                    Text("AILSA SubSwitch").fontWeight(.medium)
                }
            }.font(.system(size: 11)).foregroundStyle(muted)
        }
        .padding(34).frame(width: 760).background(Color.white).foregroundStyle(ink)
        .environment(\.colorScheme, .light).environment(\.locale, L10n.currentLocale)
    }
    private var chart: some View {
        let divisor = metric == .tokens ? (tokenUnit == "B" ? 1e9 : 1e6) : 1
        let step = report.request.period == .daily ? 1800.0 : 86400
        return Chart(report.points) { point in
            // An empty interval is zero usage; a recorded but unpriced
            // interval remains a gap in a USD chart.
            let amount = point.value.requests == 0 ? 0 : metric.value(in: point.value)
            if let amount {
                BarMark(x: .value("Time", point.date.addingTimeInterval(step / 2)), y: .value("Usage", amount / divisor),
                        width: .fixed(report.request.period == .daily ? 9 : report.request.period == .weekly ? 46 : 13))
                    .foregroundStyle(Color.indigo).cornerRadius(2)
            }
        }
        .chartXScale(domain: report.interval.start...report.interval.end)
        .chartXAxis {
            AxisMarks(values: .stride(by: report.request.period == .daily ? .hour : .day,
                                      count: report.request.period == .daily ? 6 : report.request.period == .weekly ? 1 : 7)) { value in
                AxisValueLabel {
                    if let d = value.as(Date.self) {
                        Text(report.request.period == .daily ? clockLabel(d) : date(d, compact: true)).font(.system(size: 11))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3])).foregroundStyle(ink.opacity(0.13))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(metric == .tokens ? String(format: "%.1f%@", number, tokenUnit == "B" ? "B" : "M") : String(format: "$%.2f", number)).font(.system(size: 11))
                    }
                }
            }
        }
    }
    private func clockLabel(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    private func card(_ title: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13)).foregroundStyle(muted)
            Text(value).font(.system(size: 34, weight: .bold)).monospacedDigit().tracking(-0.8).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.system(size: 11)).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(19).background(surface, in: RoundedRectangle(cornerRadius: 15))
    }
}

enum UsageReportRenderer {
    @MainActor static func png(_ report: UsageReport, metric: QuotaChartMetric = .tokens, tokenUnit: String = "M") throws -> Data {
        let host = NSHostingView(rootView: UsageReportPoster(report: report, metric: metric, tokenUnit: tokenUnit))
        let size = host.fittingSize
        guard size.height > 0, size.height <= 16_000 else {
            throw NSError(domain: "AILSA.SubSwitch.UsageReport", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: UsageReportText.text("图片过大，请选择较短的统计周期。", "The image is too large. Choose a shorter period.")])
        }
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host; host.frame = NSRect(origin: .zero, size: size)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { throw CocoaError(.fileWriteUnknown) }
        bitmap.size = size
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
