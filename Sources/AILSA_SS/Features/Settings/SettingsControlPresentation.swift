import Foundation

enum SettingsExternalLinks {
    static let openCodexDashboard = URL(string: "http://127.0.0.1:10100/")!
}

enum SettingsToggleIntent: String, Hashable {
    case launchAtStartup
    case launchCodexAfterSwitch
    case launchAntigravityAfterSwitch
    case autoSmartSwitch
    case autoSmartSwitchAntigravity
    case syncOpencodeOpenaiAuth
    case syncOpencodeAntigravityAuth
    case restartEditorsOnSwitch
}

struct SettingsToggleDescriptor<Intent: Hashable>: Identifiable, Equatable {
    let intent: Intent
    let titleKey: String
    var detailKey: String? = nil
    var isOn: Bool
    var isEnabled: Bool = true

    var id: String {
        String(describing: intent)
    }
}

struct SettingsPickerOptionDescriptor<Value: Hashable>: Identifiable, Equatable {
    let value: Value
    let title: String

    var id: String {
        String(describing: value)
    }
}

struct SettingsPickerDescriptor<Value: Hashable>: Equatable {
    let titleKey: String
    let selectedValue: Value
    let options: [SettingsPickerOptionDescriptor<Value>]
    let isEnabled: Bool
}

struct SettingsToggleSectionPresentation: Equatable {
    let toggles: [SettingsToggleDescriptor<SettingsToggleIntent>]
    let usageProgressDisplayPicker: SettingsPickerDescriptor<UsageProgressDisplayMode>?
}

struct SettingsSwitchBehaviorSectionPresentation: Equatable {
    let toggles: [SettingsToggleDescriptor<SettingsToggleIntent>]
    let restartEditorTargetPicker: SettingsPickerDescriptor<EditorAppID?>
}

struct SettingsPickerSectionPresentation<Value: Hashable>: Equatable {
    let picker: SettingsPickerDescriptor<Value>
}

enum SettingsControlPresentation {
    static func generalSection(
        settings: AppSettings
    ) -> SettingsToggleSectionPresentation {
        SettingsToggleSectionPresentation(
            toggles: [
                SettingsToggleDescriptor(
                    intent: .launchAtStartup,
                    titleKey: "settings.launch_at_startup",
                    isOn: settings.launchAtStartup
                ),
                SettingsToggleDescriptor(
                    intent: .launchCodexAfterSwitch,
                    titleKey: "settings.launch_codex_after_switch",
                    isOn: settings.launchCodexAfterSwitch
                ),
                SettingsToggleDescriptor(
                    intent: .launchAntigravityAfterSwitch,
                    titleKey: "settings.launch_antigravity_after_switch",
                    isOn: settings.launchAntigravityAfterSwitch
                )
            ],
            usageProgressDisplayPicker: SettingsPickerDescriptor(
                titleKey: "settings.usage_progress_display",
                selectedValue: settings.usageProgressDisplayMode,
                options: [
                    SettingsPickerOptionDescriptor(
                        value: .used,
                        title: L10n.tr("settings.usage_progress_display.used")
                    ),
                    SettingsPickerOptionDescriptor(
                        value: .remaining,
                        title: L10n.tr("settings.usage_progress_display.remaining")
                    )
                ],
                isEnabled: true
            )
        )
    }

    static func switchBehaviorSection(
        settings: AppSettings,
        installedEditorApps: [InstalledEditorApp],
        antigravityAutomaticSwitchCapability: AntigravityAutomaticSwitchCapability = .requiresManualSmartSwitch
    ) -> SettingsSwitchBehaviorSectionPresentation {
        let restartTargetOptions = [
            SettingsPickerOptionDescriptor<EditorAppID?>(
                value: .none,
                title: L10n.tr("common.none")
            )
        ] + installedEditorApps.map { app in
            SettingsPickerOptionDescriptor(
                value: .some(app.id),
                title: app.label
            )
        }

        return SettingsSwitchBehaviorSectionPresentation(
            toggles: [
                SettingsToggleDescriptor(
                    intent: .autoSmartSwitch,
                    titleKey: "settings.auto_smart_switch_codex",
                    isOn: settings.autoSmartSwitch
                ),
                SettingsToggleDescriptor(
                    intent: .autoSmartSwitchAntigravity,
                    titleKey: "settings.auto_smart_switch_antigravity",
                    detailKey: antigravityAutomaticSwitchCapability == .available
                        ? "settings.auto_smart_switch_antigravity.available_reason"
                        : "settings.auto_smart_switch_antigravity.restricted_reason",
                    isOn: settings.autoSmartSwitchAntigravity,
                    isEnabled: antigravityAutomaticSwitchCapability == .available
                ),
                SettingsToggleDescriptor(
                    intent: .syncOpencodeOpenaiAuth,
                    titleKey: "settings.sync_opencode_openai_auth",
                    isOn: settings.syncOpencodeOpenaiAuth
                ),
                SettingsToggleDescriptor(
                    intent: .syncOpencodeAntigravityAuth,
                    titleKey: "settings.sync_opencode_antigravity_auth",
                    detailKey: "settings.sync_opencode_antigravity_auth.detail",
                    isOn: settings.syncOpencodeAntigravityAuth
                ),
                SettingsToggleDescriptor(
                    intent: .restartEditorsOnSwitch,
                    titleKey: "settings.restart_editors_on_switch",
                    isOn: settings.restartEditorsOnSwitch
                )
            ],
            restartEditorTargetPicker: SettingsPickerDescriptor(
                titleKey: "settings.editor_restart_target",
                selectedValue: settings.restartEditorTargets.first,
                options: restartTargetOptions,
                isEnabled: settings.restartEditorsOnSwitch && !installedEditorApps.isEmpty
            )
        )
    }

    static func languageSection(
        settings: AppSettings
    ) -> SettingsPickerSectionPresentation<AppLocale> {
        SettingsPickerSectionPresentation(
            picker: SettingsPickerDescriptor(
                titleKey: "settings.language",
                selectedValue: AppLocale.resolve(settings.locale),
                options: AppLocale.allCases.map { locale in
                    SettingsPickerOptionDescriptor(
                        value: locale,
                        title: L10n.tr(locale.displayNameKey)
                    )
                },
                isEnabled: true
            )
        )
    }
}
