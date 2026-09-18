import Foundation

actor SettingsCoordinator {
    private let settingsRepository: SettingsRepository
    private let launchAtStartupService: LaunchAtStartupServiceProtocol

    init(
        settingsRepository: SettingsRepository,
        launchAtStartupService: LaunchAtStartupServiceProtocol
    ) {
        self.settingsRepository = settingsRepository
        self.launchAtStartupService = launchAtStartupService
    }

    func currentSettings() throws -> AppSettings {
        try settingsRepository.loadSettings()
    }

    func updateSettings(_ patch: AppSettingsPatch) throws -> AppSettings {
        let launchAtStartupPatch = patch.launchAtStartup

        var settings = try settingsRepository.loadSettings()

        if let value = patch.launchAtStartup { settings.launchAtStartup = value }
        if let value = patch.launchCodexAfterSwitch { settings.launchCodexAfterSwitch = value }
        if let value = patch.launchAntigravityAfterSwitch {
            settings.launchAntigravityAfterSwitch = value
        }
        if let value = patch.autoSmartSwitchAntigravity {
            settings.autoSmartSwitchAntigravity = value
        }
        if let value = patch.autoSmartSwitch { settings.autoSmartSwitch = value }
        if let value = patch.syncOpencodeOpenaiAuth { settings.syncOpencodeOpenaiAuth = value }
        if let value = patch.syncOpencodeAntigravityAuth { settings.syncOpencodeAntigravityAuth = value }
        if let value = patch.restartEditorsOnSwitch { settings.restartEditorsOnSwitch = value }
        if let value = patch.restartEditorTargets { settings.restartEditorTargets = value }
        if let value = patch.usageProgressDisplayMode { settings.usageProgressDisplayMode = value }
        if let value = patch.quotaVisibility { settings.quotaVisibility = value }
        if let value = patch.quotaWindowActivationMode { settings.quotaWindowActivationMode = value }
        if let value = patch.quotaWindowActivationStartHour {
            settings.quotaWindowActivationStartHour = min(max(value, 0), 23)
        }
        if let value = patch.quotaWindowActivationEndHour {
            settings.quotaWindowActivationEndHour = min(max(value, 0), 23)
        }
        if let value = patch.locale { settings.locale = AppLocale.resolve(value).identifier }

        try settingsRepository.saveSettings(settings)

        if let launchAtStartupPatch {
            try launchAtStartupService.setEnabled(launchAtStartupPatch)
        }

        return settings
    }

    func syncLaunchAtStartupFromStore() throws {
        let settings = try settingsRepository.loadSettings()
        try launchAtStartupService.syncWithStoreValue(settings.launchAtStartup)
    }
}
