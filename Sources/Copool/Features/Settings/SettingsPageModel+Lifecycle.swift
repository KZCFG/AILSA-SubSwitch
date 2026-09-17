import Foundation

@MainActor
extension SettingsPageModel {
    func loadIfNeeded() async {
        if !hasLoaded {
            await load()
        }
    }

    func load() async {
        do {
            settings = try await settingsCoordinator.currentSettings()
            installedEditorApps = editorAppService.listInstalledApps()
            refreshAntigravityAutomaticSwitchCapability()
            onSettingsUpdated(settings)
            hasLoaded = true
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }

}
