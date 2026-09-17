import SwiftUI

struct SettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        #if os(macOS)
        MacSettingsPageContent(model: model)
        #else
        IOSSettingsPageContent(model: model)
        #endif
    }
}

enum SettingsPageSection: CaseIterable, Identifiable {
    case general
    case quotaDisplay
    case switchBehavior
    case language

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .general: "settings.group.general"
        case .quotaDisplay: "settings.group.quota_display"
        case .switchBehavior: "settings.group.switch_behavior"
        case .language: "settings.group.language"
        }
    }
}

#if os(macOS)
private struct MacSettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.sectionSpacing) {
            SettingsPageHeading()
            SettingsPageSectionPicker(selection: $model.selectedSection)

            switch model.selectedSection {
            case .general:
                SettingsGeneralSection(model: model)
            case .quotaDisplay:
                SettingsQuotaDisplaySection(model: model)
            case .switchBehavior:
                SettingsSwitchBehaviorSection(model: model)
            case .language:
                SettingsLanguageSection(model: model)
            }

            Spacer(minLength: 0)
            SettingsQuitFooter(onQuit: model.quitApp)
        }
        .padding(.top, LayoutRules.pagePadding)
        .padding(.horizontal, LayoutRules.pagePadding)
        .task {
            await model.loadIfNeeded()
        }
    }
}

private struct SettingsGeneralSection: View {
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    @AppStorage("ass.launchCursorAfterSwitch") private var launchCursorAfterSwitch = true
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.general")) {
            HStack {
                Text("Token 单位")
                Spacer()
                ASSegmentedControl(selection: $tokenUnit, values: ["M", "B"], title: { $0 })
                    .frame(width: 140)
            }
            SettingsToggleRows(
                descriptors: model.generalSectionPresentation.toggles.filter {
                    $0.intent == .launchAtStartup
                        || $0.intent == .launchCodexAfterSwitch
                        || $0.intent == .launchAntigravityAfterSwitch
                },
                onChange: model.updateToggle
            )

            HStack {
                Text("切换后启动 Cursor")
                Spacer()
                Toggle("切换后启动 Cursor", isOn: $launchCursorAfterSwitch)
                    .labelsHidden().toggleStyle(.switch).accessibilityLabel("切换后启动 Cursor")
            }

            if let usageProgressDisplayPicker = model.generalSectionPresentation.usageProgressDisplayPicker {
                SettingsPickerRow(
                    descriptor: usageProgressDisplayPicker,
                    onSelect: model.updateUsageProgressDisplayMode
                )
            }
        }
    }
}

private struct SettingsSwitchBehaviorSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.switch_behavior")) {
            SettingsToggleRows(
                descriptors: model.switchBehaviorSectionPresentation.toggles,
                onChange: model.updateToggle
            )

            SettingsPickerRow(
                descriptor: model.switchBehaviorSectionPresentation.restartEditorTargetPicker,
                onSelect: model.updateRestartEditorTarget
            )
        }
    }
}

private struct SettingsQuotaDisplaySection: View {
    @ObservedObject var model: SettingsPageModel
    @State private var selectedProvider: AccountProvider = .codex
    @State private var pageIndex = 0

    private let itemsPerPage = 5

    private var availableProviders: [AccountProvider] {
        AccountProvider.allCases.filter { provider in
            model.quotaVisibilityItems.contains { $0.provider == provider }
        }
    }

    private var resolvedProvider: AccountProvider? {
        if availableProviders.contains(selectedProvider) {
            return selectedProvider
        }
        return availableProviders.first
    }

    private var providerItems: [QuotaVisibilitySettingsItem] {
        guard let resolvedProvider else { return [] }
        return model.quotaVisibilityItems.filter { $0.provider == resolvedProvider }
    }

    private var pageCount: Int {
        max(1, (providerItems.count + itemsPerPage - 1) / itemsPerPage)
    }

    private var displayedItems: [QuotaVisibilitySettingsItem] {
        let safeIndex = min(max(pageIndex, 0), pageCount - 1)
        let start = safeIndex * itemsPerPage
        let end = min(start + itemsPerPage, providerItems.count)
        guard start < end else { return [] }
        return Array(providerItems[start..<end])
    }

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.quota_display")) {
            Text(L10n.tr("settings.quota_display.hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if availableProviders.isEmpty {
                Text(L10n.tr("settings.quota_display.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                SettingsQuotaProviderPicker(
                    providers: availableProviders,
                    selection: Binding(
                        get: { resolvedProvider ?? .codex },
                        set: { provider in
                            selectedProvider = provider
                            pageIndex = 0
                        }
                    )
                )

                VStack(alignment: .leading, spacing: AppDesign.Metrics.groupSpacing) {
                    ForEach(displayedItems) { item in
                        Toggle(
                            isOn: Binding(
                                get: { model.settings.quotaVisibility.isVisible(item.id) },
                                set: { model.setQuotaVisibility($0, for: item.id) }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline)
                                if let groupTitle = item.groupTitle, !groupTitle.isEmpty {
                                    Text(groupTitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(SettingsNeutralSwitchStyle())
                    }
                }

                if pageCount > 1 {
                    HStack(spacing: 10) {
                        Button {
                            pageIndex = max(0, pageIndex - 1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .disabled(pageIndex == 0)

                        Text(L10n.tr(
                            "settings.quota_display.page_format",
                            pageIndex + 1,
                            pageCount
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Button {
                            pageIndex = min(pageCount - 1, pageIndex + 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.plain)
                        .disabled(pageIndex >= pageCount - 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .onChange(of: model.quotaVisibilityItems) { _, _ in
            if let first = availableProviders.first,
               !availableProviders.contains(selectedProvider) {
                selectedProvider = first
            }
            pageIndex = min(pageIndex, pageCount - 1)
        }
    }
}

private struct SettingsQuotaProviderPicker: View {
    let providers: [AccountProvider]
    @Binding var selection: AccountProvider
    var body: some View {
        ASSegmentedControl(selection: $selection, values: providers, title: { provider in
            switch provider { case .codex: "Codex"; case .antigravity: "AntiGravity"; case .cursor: "Cursor" }
        }, icon: { provider in
            switch provider { case .codex: "terminal"; case .antigravity: "sparkles"; case .cursor: "cube" }
        })
    }
}

private struct SettingsPageHeading: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(L10n.tr("tab.settings"))
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(AppDesign.primaryText(for: colorScheme))
    }
}

private struct SettingsPageSectionPicker: View {
    @Binding var selection: SettingsPageSection
    var body: some View {
        ASSegmentedControl(selection: $selection, values: SettingsPageSection.allCases,
                           title: { L10n.tr($0.titleKey) })
    }
}

private struct SettingsQuitFooter: View {
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            Text(AppVersion.current).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            Spacer(minLength: 0)
            Button(L10n.tr("about.title")) {
                SubSwitchApplicationDelegate.current?.showAboutWindow()
            }
            .copoolActionButtonStyle()

            // Quit is a normal app action, not a destructive one; the red
            // role made it the loudest element on the settings page.
            Button {
                onQuit()
            } label: {
                Text("common.quit")
            }
            .copoolActionButtonStyle()
        }
        .padding(.top, 6)
        .padding(.bottom, 10)
    }
}
#endif

private struct IOSSettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.sectionSpacing) {
            SettingsPageHeading()
            SettingsLanguageSection(model: model)
            Spacer(minLength: 0)
        }
        .padding(LayoutRules.pagePadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await model.loadIfNeeded()
        }
    }
}

private struct SettingsLanguageSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.language")) {
            SettingsPickerRow(
                descriptor: model.languageSectionPresentation.picker,
                onSelect: model.updateLocale
            )
        }
    }
}
