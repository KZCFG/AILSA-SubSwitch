import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct UsageReportPNG: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct UsageReportExportSheet: View {
    @ObservedObject var model: QuotaManagementPageModel
    let provider: QuotaManagementProvider
    @State var period: UsageReportPeriod
    @State var endingOn: Date
    @State private var startingOn: Date
    @State private var customTitle = ""

    init(model: QuotaManagementPageModel, provider: QuotaManagementProvider, period: UsageReportPeriod, endingOn: Date) {
        self.model = model; self.provider = provider
        _period = State(initialValue: period); _endingOn = State(initialValue: endingOn)
        _startingOn = State(initialValue: Calendar.current.date(byAdding: .day, value: -6, to: endingOn) ?? endingOn)
    }
    @AppStorage(QuotaChartMetric.defaultsKey) private var chartMetric: QuotaChartMetric = .tokens
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    @AppStorage(UsageReportPreferences.hideUnpricedModelsKey) private var hideUnpricedModels = false
    @State private var generating = false
    @State private var saving = false
    @State private var document: UsageReportPNG?
    @State private var filename = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(UsageReportText.text("导出用量图", "Export usage image"), systemImage: "square.and.arrow.up")
                .font(.title3.bold())
            VStack(spacing: 6) {
                ASSegmentedControl(selection: $period, values: [.daily, .weekly, .monthly], title: { $0.title })
                ASSegmentedControl(selection: $period, values: [.sixtyDays, .ninetyDays, .custom], title: { $0.title })
            }.accessibilityLabel(UsageReportText.text("周期", "Period"))
            if period == .custom {
                DatePicker(UsageReportText.text("开始日期", "Starting on"), selection: $startingOn, in: ...endingOn, displayedComponents: .date)
                DatePicker(UsageReportText.text("截止日期", "Ending on"), selection: $endingOn, in: startingOn...max(startingOn, Date()), displayedComponents: .date)
            } else {
                DatePicker(UsageReportText.text("截止日期", "Ending on"), selection: $endingOn, in: ...Date(), displayedComponents: .date)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(UsageReportText.text("分享标题", "Share title")).font(.callout.weight(.medium))
                TextField(request.displayTitle, text: $customTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(UsageReportText.text("分享标题", "Share title"))
                    .onChange(of: customTitle) { _, value in
                        if value.count > UsageReportRequest.maximumTitleLength {
                            customTitle = String(value.prefix(UsageReportRequest.maximumTitleLength))
                        }
                    }
                Text(UsageReportText.text("可填写「美好周末」等标题，最多 80 字；留空使用默认标题。", "Use a title such as “A wonderful weekend”, up to 80 characters. Leave blank for the default."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(UsageReportText.text("开始与截止日期均包含在统计中，按本机时区计算。长时段趋势自动分组合计，总量覆盖完整时段。仅使用已有记录；图片不含账号或聊天内容。", "Both dates are included, using your local time zone. Longer trends are grouped automatically; totals cover the full range. Only available records are included. No accounts or conversations are exported."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if generating { ProgressView().controlSize(.small); Text(UsageReportText.text("正在生成…", "Generating…")).font(.caption) }
                Spacer()
                Button(UsageReportText.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    .ailsaSSActionButtonStyle(density: .compact)
                    .disabled(generating)
                Button(UsageReportText.text("生成并保存…", "Generate and save…")) { Task { await generate() } }
                    .ailsaSSActionButtonStyle(prominent: true, density: .compact).keyboardShortcut(.defaultAction).disabled(generating || (try? request.validate(now: Date())) == nil)
            }
        }.padding(24).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: endingOn) { _, value in startingOn = min(startingOn, value) }
        .fileExporter(isPresented: $saving, document: document, contentType: .png, defaultFilename: filename) { result in
            switch result {
            case .success(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
                dismiss()
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
            }
        }
    }
    private var request: UsageReportRequest {
        UsageReportRequest(provider: provider, period: period, endingOn: endingOn,
            startingOn: period == .custom ? startingOn : nil, customTitle: customTitle)
    }
    @MainActor private func generate() async {
        generating = true; errorMessage = nil
        defer { generating = false }
        do {
            let request = self.request
            let report = try await model.makeUsageReport(request)
            guard report.total.reported > 0 || report.total.reference.count > 0 else {
                errorMessage = UsageReportText.text("所选时段暂无可导出的用量记录。", "No usage records are available for this period.")
                return
            }
            document = UsageReportPNG(data: try UsageReportRenderer.png(report, metric: chartMetric, tokenUnit: tokenUnit, hideUnpricedModels: hideUnpricedModels))
            filename = request.filename()
            saving = true
        } catch { errorMessage = error.localizedDescription }
    }
}
