import Foundation

@MainActor
extension SettingsPageModel {
    func setLaunchAtStartup(_ value: Bool) {
        updateToggle(.launchAtStartup, to: value)
    }

    func setLaunchCodexAfterSwitch(_ value: Bool) {
        updateToggle(.launchCodexAfterSwitch, to: value)
    }

    func setLaunchAntigravityAfterSwitch(_ value: Bool) {
        updateToggle(.launchAntigravityAfterSwitch, to: value)
    }

    /// Compatibility for callers compiled against the old generic setting.  It
    /// intentionally continues to mean Codex only; AntiGravity is separately
    /// opt-in because it has a native session to verify first.
    func setLaunchAfterSwitch(_ value: Bool) {
        setLaunchCodexAfterSwitch(value)
    }

    func setAutoSmartSwitch(_ value: Bool) {
        updateToggle(.autoSmartSwitch, to: value)
    }

    func setAutoSmartSwitchAntigravity(_ value: Bool) {
        updateToggle(.autoSmartSwitchAntigravity, to: value)
    }

    func setLocale(_ value: String) {
        updateLocale(AppLocale.resolve(value))
    }

    func updateUsageProgressDisplayMode(_ value: UsageProgressDisplayMode) {
        Task { await update(AppSettingsPatch(usageProgressDisplayMode: value)) }
    }

    func updateQuotaWindowActivationMode(_ value: QuotaWindowActivationMode) {
        Task { await update(AppSettingsPatch(quotaWindowActivationMode: value)) }
    }

    func updateQuotaWindowActivationStartHour(_ value: Int) {
        Task { await update(AppSettingsPatch(quotaWindowActivationStartHour: value)) }
    }

    func updateQuotaWindowActivationEndHour(_ value: Int) {
        Task { await update(AppSettingsPatch(quotaWindowActivationEndHour: value)) }
    }

    /// Updates the display preference optimistically so every account card and
    /// widget snapshot recomputes in the same UI turn. The raw usage snapshots
    /// are not changed; a failed persistence write is rolled back visibly.
    func setQuotaVisibility(_ visible: Bool, for key: String) {
        var next = settings
        next.quotaVisibility.setVisible(visible, for: key)
        guard next.quotaVisibility != settings.quotaVisibility else { return }

        let previous = settings
        settings = next
        onSettingsUpdated(next)

        Task {
            do {
                let persisted = try await settingsCoordinator.updateSettings(
                    AppSettingsPatch(quotaVisibility: next.quotaVisibility)
                )
                settings = persisted
                onSettingsUpdated(persisted)
            } catch {
                settings = previous
                onSettingsUpdated(previous)
                notice = NoticeMessage(style: .error, text: error.localizedDescription)
            }
        }
    }

    func setSyncOpencodeOpenaiAuth(_ value: Bool) {
        updateToggle(.syncOpencodeOpenaiAuth, to: value)
    }

    func setSyncOpencodeAntigravityAuth(_ value: Bool) {
        updateToggle(.syncOpencodeAntigravityAuth, to: value)
    }

    func setRestartEditorsOnSwitch(_ value: Bool) {
        updateToggle(.restartEditorsOnSwitch, to: value)
    }

    func setRestartEditorTarget(_ target: EditorAppID?) {
        updateRestartEditorTarget(target)
    }

    func quitApp() {
        onQuitRequested()
    }

    func repairStatusItemDisplay() {
        #if os(macOS)
        let repaired = SubSwitchApplicationDelegate.current?.repairStatusItemDisplay() == true
        notice = NoticeMessage(
            style: repaired ? .success : .info,
            text: L10n.tr(
                repaired
                    ? "settings.notice.status_item_repaired"
                    : "settings.notice.status_item_repair_unavailable"
            )
        )
        #else
        notice = NoticeMessage(style: .info, text: L10n.tr("settings.notice.status_item_repair_unavailable"))
        #endif
    }

    func updateToggle(_ intent: SettingsToggleIntent, to value: Bool) {
        switch intent {
        case .launchAtStartup:
            Task { await update(AppSettingsPatch(launchAtStartup: value)) }
        case .launchCodexAfterSwitch:
            Task { await update(AppSettingsPatch(launchCodexAfterSwitch: value)) }
        case .launchAntigravityAfterSwitch:
            Task { await update(AppSettingsPatch(launchAntigravityAfterSwitch: value)) }
        case .autoSmartSwitch:
            Task { await update(AppSettingsPatch(autoSmartSwitch: value)) }
        case .autoSmartSwitchAntigravity:
            Task {
                if value {
                    do {
                        try await Task.detached(priority: .userInitiated) {
                            let repository = AntigravityAuthRepository()
                            let snapshot = try repository.nativeCredentialSnapshot(access: .background)
                            try repository.preflightNativeCredentialTransaction(snapshot, access: .background)
                        }.value
                    } catch {
                        notice = NoticeMessage(style: .info, text: error.localizedDescription)
                        return
                    }
                }
                await update(AppSettingsPatch(autoSmartSwitchAntigravity: value))
            }
        case .syncOpencodeOpenaiAuth:
            Task { await update(AppSettingsPatch(syncOpencodeOpenaiAuth: value)) }
        case .syncOpencodeAntigravityAuth:
            Task { await update(AppSettingsPatch(syncOpencodeAntigravityAuth: value)) }
        case .restartEditorsOnSwitch:
            applyRestartEditorsOnSwitch(value)
        }
    }

    func updateRestartEditorTarget(_ target: EditorAppID?) {
        let values = target.map { [$0] } ?? []
        Task {
            await update(
                AppSettingsPatch(restartEditorTargets: values),
                successText: L10n.tr("settings.notice.restart_target_updated")
            )
        }
    }

    func updateLocale(_ locale: AppLocale) {
        Task { await update(AppSettingsPatch(locale: locale.identifier)) }
    }

    private func applyRestartEditorsOnSwitch(_ value: Bool) {
        if value,
           settings.restartEditorTargets.isEmpty,
           let first = installedEditorApps.first?.id {
            Task {
                await update(
                    AppSettingsPatch(
                        restartEditorsOnSwitch: true,
                        restartEditorTargets: [first]
                    )
                )
            }
            return
        }

        Task { await update(AppSettingsPatch(restartEditorsOnSwitch: value)) }
    }

    private func update(
        _ patch: AppSettingsPatch,
        successText: String = L10n.tr("settings.notice.updated")
    ) async {
        do {
            settings = try await settingsCoordinator.updateSettings(patch)
            onSettingsUpdated(settings)
            notice = NoticeMessage(style: .success, text: successText)
        } catch {
            notice = NoticeMessage(style: .error, text: error.localizedDescription)
        }
    }
}
