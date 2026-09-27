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
            ASSegmentedControl(selection: $period, values: UsageReportPeriod.allCases, title: { $0.title })
                .accessibilityLabel(UsageReportText.text("周期", "Period"))
            DatePicker(UsageReportText.text("截止日期", "Ending on"), selection: $endingOn, in: ...Date(), displayedComponents: .date)
            Text(UsageReportText.text("日报统计所选日期；周报和月报统计截至该日的 7 天和 30 天。图片包含用量、模型明细和趋势，不含账号或聊天内容。", "Daily covers the selected date. Weekly and monthly cover the 7 and 30 days ending on that date. Images include usage, models and trends, without accounts or conversations."))
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
            document = UsageReportPNG(data: try UsageReportRenderer.png(report, metric: chartMetric, tokenUnit: tokenUnit))
            filename = request.filename()
            saving = true
        } catch { errorMessage = error.localizedDescription }
    }
}
