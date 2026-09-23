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
    case about

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .general: "settings.group.general"
        case .quotaDisplay: "settings.group.quota_display"
        case .switchBehavior: "settings.group.switch_behavior"
        case .language: "settings.group.language"
        case .about: "about.title"
        }
    }
}

#if os(macOS)
private struct MacSettingsPageContent: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.sectionSpacing) {
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
            case .about:
                AboutView()
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
    @AppStorage(ResetCreditTimeDisplay.defaultsKey) private var resetTimeDisplay = "remaining"
    @AppStorage(CountdownUnits.defaultsKey) private var countdownUnits = "abbreviated"
    @AppStorage("ass.tokenUnit") private var tokenUnit = "M"
    @AppStorage("ass.launchCursorAfterSwitch") private var launchCursorAfterSwitch = true
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.general")) {
            HStack {
                Text("Token 单位")
                    .font(.system(size: 13, weight: .medium))
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
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Toggle("", isOn: $launchCursorAfterSwitch)
                    .labelsHidden()
                    .toggleStyle(SettingsNeutralSwitchStyle())
                    .accessibilityLabel("切换后启动 Cursor")
            }

            if let usageProgressDisplayPicker = model.generalSectionPresentation.usageProgressDisplayPicker {
                SettingsPickerRow(
                    descriptor: usageProgressDisplayPicker,
                    onSelect: model.updateUsageProgressDisplayMode
                )
            }
            Picker(L10n.tr("settings.reset_credits.title"), selection: $resetTimeDisplay) {
                ForEach(ResetCreditTimeDisplay.allCases, id: \.rawValue) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .medium))
            Picker(L10n.tr("settings.countdown_units.title"), selection: $countdownUnits) {
                Text("d · h · m · s").tag("abbreviated")
                Text(L10n.tr("settings.countdown_units.chinese")).tag("chinese")
            }
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .medium))

            Picker(
                L10n.tr("settings.quota_activation.title"),
                selection: Binding(
                    get: { model.settings.quotaWindowActivationMode },
                    set: { model.updateQuotaWindowActivationMode($0) }
                )
            ) {
                ForEach(QuotaWindowActivationMode.allCases, id: \.self) { mode in
                    Text(L10n.tr(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .medium))

            Text(L10n.tr(model.settings.quotaWindowActivationMode.detailKey))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.settings.quotaWindowActivationMode == .workHours {
                HStack(spacing: 12) {
                    Text(L10n.tr("settings.quota_activation.hours"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settings.quotaWindowActivationStartHour },
                            set: { model.updateQuotaWindowActivationStartHour($0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text("–")
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settings.quotaWindowActivationEndHour },
                            set: { model.updateQuotaWindowActivationEndHour($0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsStatusItemRepairRow(model: model)
        }
    }
}

private struct SettingsStatusItemRepairRow: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "menubar.arrow.down.rectangle")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.tr("settings.status_item_repair.title"))
                        .font(.system(size: 13, weight: .medium))
                    Text(L10n.tr("settings.status_item_repair.detail"))
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button(L10n.tr("settings.status_item_repair.action")) {
                    model.repairStatusItemDisplay()
                }
                .ailsaSSActionButtonStyle(density: .compact)
            }
        }
        .padding(.top, 4)
    }
}

private struct SettingsSwitchBehaviorSection: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SectionCard(title: L10n.tr("settings.section.switch_behavior")) {
            SettingsToggleRows(
                descriptors: model.switchBehaviorSectionPresentation.toggles.filter {
                    $0.intent != .restartEditorsOnSwitch
                },
                onChange: model.updateToggle
            )

            VStack(alignment: .leading, spacing: 3) {
                Link(destination: SettingsExternalLinks.openCodexDashboard) {
                    HStack(spacing: 8) {
                        Label(L10n.tr("settings.opencodex.dashboard"), systemImage: "link")
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(SettingsExternalLinks.openCodexDashboard.absoluteString)

                Text(L10n.tr("settings.opencodex.dashboard.detail"))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            SettingsToggleRows(
                descriptors: model.switchBehaviorSectionPresentation.toggles.filter {
                    $0.intent == .restartEditorsOnSwitch
                },
                onChange: model.updateToggle
            )

            SettingsPickerRow(
                descriptor: model.switchBehaviorSectionPresentation.restartEditorTargetPicker,
                onSelect: model.updateRestartEditorTarget
            )
            Text(L10n.tr("settings.editor_restart_target.detail"))
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SettingsQuotaDisplaySection: View {
    @AppStorage(QuotaChartMetric.defaultsKey) private var quotaChartMetric: QuotaChartMetric = .tokens
    @ObservedObject var model: SettingsPageModel
    @State private var selectedProvider: AccountProvider = .codex
    @State private var pageIndex = 0
    @State private var pane = "windows"
    @State private var selectedAccountID = ""
    @AppStorage(CompactRingPreferences.defaultsKey) private var ringChoices = "{}"
    @AppStorage("ass.progressSkin.codex") private var codexSkin = "official"
    @AppStorage("ass.progressSkin.antigravity") private var antigravitySkin = "official"
    @AppStorage("ass.progressSkin.cursor") private var cursorSkin = "official"

    private let itemsPerPage = 5
    private var providerItems: [QuotaVisibilitySettingsItem] {
        model.quotaVisibilityItems.filter { $0.provider == selectedProvider }
    }
    private var pageCount: Int { max(1, (providerItems.count + itemsPerPage - 1) / itemsPerPage) }
    private var displayedItems: [QuotaVisibilitySettingsItem] {
        Array(providerItems.dropFirst(min(pageIndex, pageCount - 1) * itemsPerPage).prefix(itemsPerPage))
    }
    private var accounts: [QuotaDisplayAccount] {
        model.quotaDisplayAccounts.filter { $0.provider == selectedProvider }
    }
    private var preferences: CompactRingPreferences { .decode(ringChoices) }
    private var accountID: String? { selectedAccountID.isEmpty ? nil : selectedAccountID }
    private var scope: String { CompactRingPreferences.scope(provider: selectedProvider, accountID: accountID) }
    private var choices: [CompactQuotaChoice] {
        var seen = Set<String>()
        return accounts.filter { accountID == nil || $0.id == accountID }.flatMap(\.choices).filter {
            seen.insert($0.id).inserted && model.settings.quotaVisibility.isVisible($0.id)
        }
    }
    private var automaticChoices: [CompactQuotaChoice?] {
        guard selectedProvider == .antigravity else { return Array(choices.prefix(2)).map { Optional($0) } }
        var families = Set<String>()
        let firsts = choices.filter { families.insert($0.id.split(separator: ".").prefix(2).joined(separator: ".")).inserted }
        return Array((firsts + choices.filter { choice in !firsts.contains { $0.id == choice.id } }).prefix(2)).map { Optional($0) }
    }
    private var effectiveChoices: [CompactQuotaChoice?] {
        preferences.choices(provider: selectedProvider, accountID: accountID) ?? automaticChoices
    }
    private var skin: Binding<String> {
        switch selectedProvider {
        case .codex: return $codexSkin
        case .antigravity: return $antigravitySkin
        case .cursor: return $cursorSkin
        }
    }
    private var fillStyle: UsageProgressFillStyle {
        switch selectedProvider { case .codex: return .codex; case .antigravity: return .antigravity; case .cursor: return .cursor }
    }
    var body: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Picker(L10n.tr("settings.quota_chart_metric.title"), selection: $quotaChartMetric) {
                    ForEach(QuotaChartMetric.allCases) { metric in
                        Text(L10n.tr(metric.titleKey)).tag(metric)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 13, weight: .medium))
                .accessibilityIdentifier("settings.quotaChartMetric")
                Text(L10n.tr("settings.quota_chart_metric.detail"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: LayoutRules.cardRadius)
            SettingsQuotaProviderPicker(providers: AccountProvider.allCases, selection: $selectedProvider)
            ASSegmentedControl(selection: $pane,
                values: selectedProvider == .cursor ? ["windows", "skin"] : ["windows", "rings", "skin"],
                title: { paneTitle($0) })
            VStack(alignment: .leading, spacing: 12) {
                switch pane {
                case "skin": skinContent
                case "rings": ringsContent
                default: windowsContent
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(cornerRadius: LayoutRules.cardRadius)
        }
        .onChange(of: selectedProvider) { _, provider in
            pageIndex = 0
            selectedAccountID = ""
            if provider == .cursor && pane == "rings" { pane = "windows" }
        }
        .onChange(of: model.quotaVisibilityItems) { _, _ in pageIndex = min(pageIndex, pageCount - 1) }
        .onChange(of: model.quotaDisplayAccounts) { _, _ in
            if accountID != nil && !accounts.contains(where: { $0.id == accountID }) { selectedAccountID = "" }
        }
    }
    private var windowsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("settings.quota_display.hint")).font(.caption).foregroundStyle(.secondary)
            if providerItems.isEmpty { Text(L10n.tr("settings.quota_display.empty")).font(.caption) }
            ForEach(displayedItems) { item in
                Toggle(isOn: Binding(get: { model.settings.quotaVisibility.isVisible(item.id) },
                    set: { model.setQuotaVisibility($0, for: item.id) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.subheadline)
                        if let group = item.groupTitle { Text(group).font(.caption).foregroundStyle(.secondary) }
                    }
                }.toggleStyle(SettingsNeutralSwitchStyle())
            }
            if pageCount > 1 {
                HStack {
                    Button { pageIndex = max(0, pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(pageIndex == 0).accessibilityLabel(L10n.tr("common.previous_page"))
                    Spacer()
                    Text(L10n.tr("settings.quota_display.page_format", pageIndex + 1, pageCount)).font(.caption)
                    Spacer()
                    Button { pageIndex = min(pageCount - 1, pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(pageIndex >= pageCount - 1).accessibilityLabel(L10n.tr("common.next_page"))
                }.buttonStyle(.plain)
            }
        }
    }
    private var ringsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker(L10n.tr("settings.compact_rings.scope"), selection: $selectedAccountID) {
                Text(L10n.tr("settings.compact_rings.all_accounts")).tag("")
                ForEach(accounts) { account in Text(account.name).tag(account.id) }
            }.pickerStyle(.menu)
            ForEach(0..<2, id: \.self) { slot in
                HStack {
                    Text(L10n.tr(slot == 0 ? "settings.compact_rings.first" : "settings.compact_rings.second"))
                    Spacer(minLength: 8)
                    Menu {
                        Button(L10n.tr("settings.compact_rings.none")) { setChoice(nil, at: slot) }
                        ForEach(choices, id: \.id) { choice in
                            Button(choice.title.replacingOccurrences(of: "\n", with: " · ")) { setChoice(choice, at: slot) }
                        }
                    } label: {
                        Text(effectiveChoices.indices.contains(slot)
                            ? (effectiveChoices[slot]?.title.replacingOccurrences(of: "\n", with: " · ") ?? L10n.tr("settings.compact_rings.none"))
                            : L10n.tr("settings.compact_rings.none"))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth: 300).disabled(choices.isEmpty)
                }
            }
            Button(L10n.tr(accountID == nil ? "settings.compact_rings.reset" : "settings.compact_rings.inherit")) {
                var next = preferences
                next.selections.removeValue(forKey: scope)
                ringChoices = next.encoded
            }.disabled(preferences.selections[scope] == nil)
            Text(L10n.tr("settings.compact_rings.hint")).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func setChoice(_ choice: CompactQuotaChoice?, at slot: Int) {
        var next = preferences
        next.set(choice, at: slot, scope: scope, fallback: effectiveChoices)
        ringChoices = next.encoded
    }
    private func paneTitle(_ value: String) -> String {
        switch value {
        case "rings": return L10n.tr("settings.quota_pane.rings")
        case "skin": return L10n.tr("settings.quota_pane.skin")
        default: return L10n.tr("settings.quota_pane.windows")
        }
    }
    private func skinTitle(_ value: UsageProgressSkin) -> String {
        switch value {
        case .official: return L10n.tr("settings.progress_skin.official")
        case .ailsa: return L10n.tr("settings.progress_skin.ailsa")
        }
    }
    private var skinContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(UsageProgressSkin.allCases, id: \.rawValue) { value in
                Button { skin.wrappedValue = value.rawValue } label: {
                    HStack(spacing: 10) {
                        Image(systemName: skin.wrappedValue == value.rawValue ? "largecircle.fill.circle" : "circle")
                        Text(skinTitle(value))
                        Spacer()
                    }.frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(skin.wrappedValue == value.rawValue ? .isSelected : [])
            }
            LiquidProgressBar(progress: 0.65, fillStyle: fillStyle)
            HStack {
                LiquidProgressRing(progress: 0.65, fillStyle: fillStyle, lineWidth: 6).frame(width: 44, height: 44)
                Text(L10n.tr("settings.progress_skin.hint")).font(.caption).foregroundStyle(.secondary)
            }
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
            // Quit is a normal app action, not a destructive one; the red
            // role made it the loudest element on the settings page.
            Button {
                onQuit()
            } label: {
                Text("common.quit")
            }
            .ailsaSSActionButtonStyle()
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
