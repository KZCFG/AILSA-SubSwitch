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
                ASSegmentedControl(selection: $period, values: [.sixtyDays, .ninetyDays, .yearly], title: { $0.title })
            }.accessibilityLabel(UsageReportText.text("周期", "Period"))
            DatePicker(UsageReportText.text("截止日期", "Ending on"), selection: $endingOn, in: ...Date(), displayedComponents: .date)
            Text(UsageReportText.text("统计截至所选日期的 1、7、30、60、90 或 365 天。一年趋势按周汇总，其余长周期按天显示。仅使用已有记录，缺失历史不会补造；图片不含账号或聊天内容。", "Covers 1, 7, 30, 60, 90 or 365 days ending on the selected date. Annual trends group by week; other multi-day trends show days. Only available records are included; missing history is never reconstructed. No accounts or conversations are exported."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if generating { ProgressView().controlSize(.small); Text(UsageReportText.text("正在生成…", "Generating…")).font(.caption) }
                Spacer()
                Button(UsageReportText.text("取消", "Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                    .ailsaSSActionButtonStyle(density: .compact)
                    .disabled(generating)
                Button(UsageReportText.text("生成并保存…", "Generate and save…")) { Task { await generate() } }
                    .ailsaSSActionButtonStyle(prominent: true, density: .compact).keyboardShortcut(.defaultAction).disabled(generating)
            }
        }.padding(24).frame(width: 460).background(Color(nsColor: .windowBackgroundColor))
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
    @MainActor private func generate() async {
        generating = true; errorMessage = nil
        defer { generating = false }
        do {
            let request = UsageReportRequest(provider: provider, period: period, endingOn: endingOn)
            let report = try await model.makeUsageReport(request)
            guard !report.rows.isEmpty else {
                errorMessage = UsageReportText.text("所选时段暂无可导出的用量记录。", "No usage records are available for this period.")
                return
            }
            document = UsageReportPNG(data: try UsageReportRenderer.png(report, metric: chartMetric, tokenUnit: tokenUnit, hideUnpricedModels: hideUnpricedModels))
            filename = request.filename()
            saving = true
        } catch { errorMessage = error.localizedDescription }
    }
}
