import XCTest
@testable import AILSA_SS

final class SettingsControlPresentationTests: XCTestCase {
    func testSwitchBehaviorSectionDisablesRestartTargetPickerWhenSwitchingIsOff() {
        let presentation = SettingsControlPresentation.switchBehaviorSection(
            settings: AppSettings.defaultValue,
            installedEditorApps: [
                InstalledEditorApp(id: .cursor, label: "Cursor")
            ]
        )

        XCTAssertEqual(
            presentation.toggles.map(\.intent),
            [.autoSmartSwitch, .autoSmartSwitchAntigravity, .syncOpencodeOpenaiAuth, .syncOpencodeAntigravityAuth, .restartEditorsOnSwitch]
        )
        XCTAssertFalse(presentation.restartEditorTargetPicker.isEnabled)
        XCTAssertEqual(
            presentation.restartEditorTargetPicker.options.map(\.title),
            [L10n.tr("common.none"), "Cursor"]
        )
    }

    func testGeneralSectionIncludesUsageProgressDisplayPicker() {
        let presentation = SettingsControlPresentation.generalSection(
            settings: AppSettings.defaultValue
        )

        XCTAssertEqual(
            presentation.usageProgressDisplayPicker?.selectedValue,
            .used
        )
        XCTAssertEqual(
            presentation.usageProgressDisplayPicker?.options.map(\.value),
            [.used, .remaining]
        )
        XCTAssertEqual(
            presentation.toggles.map(\.intent),
            [.launchAtStartup, .launchCodexAfterSwitch, .launchAntigravityAfterSwitch]
        )
        XCTAssertFalse(presentation.toggles[2].isOn)
    }

    func testGeneralSectionKeepsCodexAndAntigravityLaunchControlsIndependent() {
        var settings = AppSettings.defaultValue
        settings.launchCodexAfterSwitch = false
        settings.launchAntigravityAfterSwitch = true

        let presentation = SettingsControlPresentation.generalSection(settings: settings)

        XCTAssertEqual(presentation.toggles[1].intent, .launchCodexAfterSwitch)
        XCTAssertFalse(presentation.toggles[1].isOn)
        XCTAssertEqual(presentation.toggles[2].intent, .launchAntigravityAfterSwitch)
        XCTAssertTrue(presentation.toggles[2].isOn)
    }

    func testSwitchBehaviorKeepsCodexAndAntigravityAutomationIndependent() {
        var settings = AppSettings.defaultValue
        settings.autoSmartSwitch = false
        settings.autoSmartSwitchAntigravity = true

        let presentation = SettingsControlPresentation.switchBehaviorSection(
            settings: settings,
            installedEditorApps: []
        )

        XCTAssertEqual(presentation.toggles[0].intent, .autoSmartSwitch)
        XCTAssertFalse(presentation.toggles[0].isOn)
        XCTAssertEqual(presentation.toggles[1].intent, .autoSmartSwitchAntigravity)
        XCTAssertTrue(presentation.toggles[1].isOn)
        XCTAssertFalse(presentation.toggles[1].isEnabled)
        XCTAssertEqual(
            presentation.toggles[1].detailKey,
            "settings.auto_smart_switch_antigravity.restricted_reason"
        )
    }

    func testSwitchBehaviorEnablesAntigravityAutomationOnlyForAvailableCapability() {
        let presentation = SettingsControlPresentation.switchBehaviorSection(
            settings: AppSettings.defaultValue,
            installedEditorApps: [],
            antigravityAutomaticSwitchCapability: .available
        )

        XCTAssertTrue(presentation.toggles[1].isEnabled)
        XCTAssertEqual(
            presentation.toggles[1].detailKey,
            "settings.auto_smart_switch_antigravity.available_reason"
        )
    }

    func testSwitchBehaviorSectionEnablesRestartTargetPickerWhenConfigured() {
        let settings = AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            autoSmartSwitch: true,
            syncOpencodeOpenaiAuth: true,
            restartEditorsOnSwitch: true,
            restartEditorTargets: [.vscode],
            usageProgressDisplayMode: .used,
            locale: AppLocale.english.identifier
        )

        let presentation = SettingsControlPresentation.switchBehaviorSection(
            settings: settings,
            installedEditorApps: [
                InstalledEditorApp(id: .vscode, label: "VS Code")
            ]
        )

        XCTAssertTrue(presentation.restartEditorTargetPicker.isEnabled)
        XCTAssertEqual(
            presentation.restartEditorTargetPicker.selectedValue,
            EditorAppID?.some(.vscode)
        )
    }

    func testLanguageSectionNormalizesSelectedLocale() {
        let settings = AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            usageProgressDisplayMode: .used,
            locale: "zh_CN"
        )

        let presentation = SettingsControlPresentation.languageSection(settings: settings)

        XCTAssertEqual(presentation.picker.selectedValue, .simplifiedChinese)
        XCTAssertEqual(presentation.picker.options.count, AppLocale.allCases.count)
    }

}
