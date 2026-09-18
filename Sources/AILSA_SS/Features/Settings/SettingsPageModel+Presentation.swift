import Foundation

@MainActor
extension SettingsPageModel {
    var generalSectionPresentation: SettingsToggleSectionPresentation {
        SettingsControlPresentation.generalSection(settings: settings)
    }

    var switchBehaviorSectionPresentation: SettingsSwitchBehaviorSectionPresentation {
        SettingsControlPresentation.switchBehaviorSection(
            settings: settings,
            installedEditorApps: installedEditorApps,
            antigravityAutomaticSwitchCapability: antigravityAutomaticSwitchCapability
        )
    }

    var languageSectionPresentation: SettingsPickerSectionPresentation<AppLocale> {
        SettingsControlPresentation.languageSection(settings: settings)
    }
}
