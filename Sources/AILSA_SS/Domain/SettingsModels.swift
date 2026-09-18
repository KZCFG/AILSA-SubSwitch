import Foundation

enum UsageProgressDisplayMode: String, Codable, Equatable, CaseIterable, Sendable {
    case used
    case remaining

    var localizationKey: String {
        switch self {
        case .used:
            return "settings.usage_progress_display.used"
        case .remaining:
            return "settings.usage_progress_display.remaining"
        }
    }
}

/// Controls optional read-only quota checks. Existing storage keys are kept
/// for compatibility; a quota check cannot activate a provider usage window.
enum QuotaWindowActivationMode: String, Codable, Equatable, CaseIterable, Sendable {
    case off
    case activeAccount
    case workHours

    var titleKey: String {
        switch self {
        case .off: return "settings.quota_activation.off"
        case .activeAccount: return "settings.quota_activation.active_account"
        case .workHours: return "settings.quota_activation.work_hours"
        }
    }

    var detailKey: String {
        switch self {
        case .off: return "settings.quota_activation.detail"
        case .activeAccount: return "settings.quota_activation.active_account.detail"
        case .workHours: return "settings.quota_activation.work_hours.detail"
        }
    }
}

/// Per-window presentation choices only.  The underlying `UsageSnapshot`
/// remains untouched so changing this preference can never influence refresh,
/// ranking, or automatic switching.
struct UsageQuotaVisibilityPreferences: Codable, Equatable, Sendable {
    private(set) var hiddenKeys: Set<String>

    init(hiddenKeys: Set<String> = []) {
        self.hiddenKeys = hiddenKeys
    }

    static let defaultValue = UsageQuotaVisibilityPreferences()

    func isVisible(_ key: String) -> Bool {
        !hiddenKeys.contains(key)
    }

    mutating func setVisible(_ visible: Bool, for key: String) {
        if visible {
            hiddenKeys.remove(key)
        } else {
            hiddenKeys.insert(key)
        }
    }
}

/// Stable keys for independently reported quota windows.  These are derived
/// from provider and server identifiers rather than a card ID, which keeps a
/// user's choice consistent across accounts of the same provider without
/// treating distinct pools (for example Spark) as one quota.
enum UsageQuotaVisibilityKey {
    static let codexFiveHour = "codex.standard.5h"
    static let codexOneWeek = "codex.standard.7d"

    static func codexAdditional(familyID: String, bucketID: String) -> String {
        "codex.additional.\(escaped(familyID)).\(escaped(bucketID))"
    }

    static func antigravity(familyID: String, bucketID: String) -> String {
        "antigravity.\(escaped(familyID)).\(escaped(bucketID))"
    }

    static func cursor(poolID: String) -> String {
        let stable = ["总计": "total", "Cursor": "cursor", "Third Party": "third-party", "Grok Bot": "grok-bot"]
        return "cursor.pool." + escaped(stable[poolID] ?? poolID)
    }

    private static func escaped(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: ".", with: "%2E")
    }
}

/// Describes whether the current native storage mode can participate in a
/// background AntiGravity switch. This deliberately says nothing about whether
/// an account is signed in: it is only a no-prompt transaction-safety check.
enum AntigravityAutomaticSwitchCapability: Equatable, Sendable {
    case available
    case requiresManualSmartSwitch
}

struct AppSettings: Codable, Equatable {
    var launchAtStartup: Bool
    var launchCodexAfterSwitch: Bool
    /// AntiGravity has a separate native session and must never be launched as a
    /// side effect of a Codex switch.  This opt-in only applies after a verified
    /// AntiGravity switch has completed.
    var launchAntigravityAfterSwitch: Bool
    /// Codex and AntiGravity have independent switch executors. Keeping their
    /// automatic policies separate prevents a legacy Codex preference from
    /// enabling native AntiGravity switching during migration.
    var autoSmartSwitchAntigravity: Bool
    var autoSmartSwitch: Bool
    var syncOpencodeOpenaiAuth: Bool
    /// When enabled, a verified AntiGravity account switch also selects the
    /// same account in OpenCodeX's `google-antigravity` provider.
    var syncOpencodeAntigravityAuth: Bool
    var restartEditorsOnSwitch: Bool
    var restartEditorTargets: [EditorAppID]
    var usageProgressDisplayMode: UsageProgressDisplayMode
    var quotaVisibility: UsageQuotaVisibilityPreferences
    var quotaWindowActivationMode: QuotaWindowActivationMode
    var quotaWindowActivationStartHour: Int
    var quotaWindowActivationEndHour: Int
    var locale: String
    /// Keys written by builds that still shipped the local/remote API proxy
    /// stack (`autoStartApiProxy`, `localProxyHostAPIOnly`, `proxyConfiguration`,
    /// `remoteServers`). They are no longer interpreted, but are carried through
    /// verbatim so an existing settings.json keeps loading in older builds.
    var legacyPassthrough: [String: JSONValue] = [:]

    static let legacyPassthroughKeys: [String] = [
        "localProxyHostAPIOnly",
        "autoStartApiProxy",
        "proxyConfiguration",
        "remoteServers",
    ]

    private struct LegacyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    enum CodingKeys: String, CodingKey {
        case launchAtStartup
        case launchCodexAfterSwitch
        case launchAntigravityAfterSwitch
        case autoSmartSwitchAntigravity
        case autoSmartSwitch
        case syncOpencodeOpenaiAuth
        case syncOpencodeAntigravityAuth
        case restartEditorsOnSwitch
        case restartEditorTargets
        case usageProgressDisplayMode
        case quotaVisibility
        case quotaWindowActivationMode
        case quotaWindowActivationStartHour
        case quotaWindowActivationEndHour
        case locale
    }

    init(
        launchAtStartup: Bool,
        launchCodexAfterSwitch: Bool,
        launchAntigravityAfterSwitch: Bool = false,
        autoSmartSwitchAntigravity: Bool = false,
        autoSmartSwitch: Bool,
        syncOpencodeOpenaiAuth: Bool,
        syncOpencodeAntigravityAuth: Bool = false,
        restartEditorsOnSwitch: Bool,
        restartEditorTargets: [EditorAppID],
        usageProgressDisplayMode: UsageProgressDisplayMode = .used,
        quotaVisibility: UsageQuotaVisibilityPreferences = .defaultValue,
        quotaWindowActivationMode: QuotaWindowActivationMode = .off,
        quotaWindowActivationStartHour: Int = 9,
        quotaWindowActivationEndHour: Int = 18,
        locale: String,
        legacyPassthrough: [String: JSONValue] = [:]
    ) {
        self.launchAtStartup = launchAtStartup
        self.launchCodexAfterSwitch = launchCodexAfterSwitch
        self.launchAntigravityAfterSwitch = launchAntigravityAfterSwitch
        self.autoSmartSwitchAntigravity = autoSmartSwitchAntigravity
        self.autoSmartSwitch = autoSmartSwitch
        self.syncOpencodeOpenaiAuth = syncOpencodeOpenaiAuth
        self.syncOpencodeAntigravityAuth = syncOpencodeAntigravityAuth
        self.restartEditorsOnSwitch = restartEditorsOnSwitch
        self.restartEditorTargets = restartEditorTargets
        self.usageProgressDisplayMode = usageProgressDisplayMode
        self.quotaVisibility = quotaVisibility
        self.quotaWindowActivationMode = quotaWindowActivationMode
        self.quotaWindowActivationStartHour = min(max(quotaWindowActivationStartHour, 0), 23)
        self.quotaWindowActivationEndHour = min(max(quotaWindowActivationEndHour, 0), 23)
        self.locale = AppLocale.resolve(locale).identifier
        self.legacyPassthrough = legacyPassthrough
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        launchAtStartup = try container.decode(Bool.self, forKey: .launchAtStartup)
        launchCodexAfterSwitch = try container.decode(Bool.self, forKey: .launchCodexAfterSwitch)
        // Existing settings files predate the AntiGravity launch control.  A
        // missing value must remain opt-out, rather than unexpectedly opening
        // an editor after migration.
        launchAntigravityAfterSwitch = try container.decodeIfPresent(
            Bool.self,
            forKey: .launchAntigravityAfterSwitch
        ) ?? false
        autoSmartSwitchAntigravity = try container.decodeIfPresent(
            Bool.self,
            forKey: .autoSmartSwitchAntigravity
        ) ?? false
        autoSmartSwitch = try container.decode(Bool.self, forKey: .autoSmartSwitch)
        syncOpencodeOpenaiAuth = try container.decode(Bool.self, forKey: .syncOpencodeOpenaiAuth)
        syncOpencodeAntigravityAuth = try container.decodeIfPresent(
            Bool.self,
            forKey: .syncOpencodeAntigravityAuth
        ) ?? false
        restartEditorsOnSwitch = try container.decode(Bool.self, forKey: .restartEditorsOnSwitch)
        restartEditorTargets = try container.decode([EditorAppID].self, forKey: .restartEditorTargets)
        let legacyContainer = try decoder.container(keyedBy: LegacyKey.self)
        var passthrough: [String: JSONValue] = [:]
        for key in Self.legacyPassthroughKeys {
            if let value = try legacyContainer.decodeIfPresent(JSONValue.self, forKey: LegacyKey(stringValue: key)) {
                passthrough[key] = value
            }
        }
        legacyPassthrough = passthrough
        usageProgressDisplayMode = try container.decodeIfPresent(
            UsageProgressDisplayMode.self,
            forKey: .usageProgressDisplayMode
        ) ?? .used
        quotaVisibility = try container.decodeIfPresent(
            UsageQuotaVisibilityPreferences.self,
            forKey: .quotaVisibility
        ) ?? .defaultValue
        quotaWindowActivationMode = try container.decodeIfPresent(
            QuotaWindowActivationMode.self,
            forKey: .quotaWindowActivationMode
        ) ?? .off
        quotaWindowActivationStartHour = min(max(
            try container.decodeIfPresent(Int.self, forKey: .quotaWindowActivationStartHour) ?? 9,
            0
        ), 23)
        quotaWindowActivationEndHour = min(max(
            try container.decodeIfPresent(Int.self, forKey: .quotaWindowActivationEndHour) ?? 18,
            0
        ), 23)
        locale = AppLocale.resolve(try container.decode(String.self, forKey: .locale)).identifier
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtStartup, forKey: .launchAtStartup)
        try container.encode(launchCodexAfterSwitch, forKey: .launchCodexAfterSwitch)
        try container.encode(launchAntigravityAfterSwitch, forKey: .launchAntigravityAfterSwitch)
        try container.encode(autoSmartSwitchAntigravity, forKey: .autoSmartSwitchAntigravity)
        try container.encode(autoSmartSwitch, forKey: .autoSmartSwitch)
        try container.encode(syncOpencodeOpenaiAuth, forKey: .syncOpencodeOpenaiAuth)
        try container.encode(syncOpencodeAntigravityAuth, forKey: .syncOpencodeAntigravityAuth)
        try container.encode(restartEditorsOnSwitch, forKey: .restartEditorsOnSwitch)
        try container.encode(restartEditorTargets, forKey: .restartEditorTargets)
        try container.encode(usageProgressDisplayMode, forKey: .usageProgressDisplayMode)
        try container.encode(quotaVisibility, forKey: .quotaVisibility)
        try container.encode(quotaWindowActivationMode, forKey: .quotaWindowActivationMode)
        try container.encode(quotaWindowActivationStartHour, forKey: .quotaWindowActivationStartHour)
        try container.encode(quotaWindowActivationEndHour, forKey: .quotaWindowActivationEndHour)
        try container.encode(locale, forKey: .locale)
        var legacyContainer = encoder.container(keyedBy: LegacyKey.self)
        for key in Self.legacyPassthroughKeys {
            if let value = legacyPassthrough[key] {
                try legacyContainer.encode(value, forKey: LegacyKey(stringValue: key))
            }
        }
    }

    static var defaultValue: AppSettings {
        AppSettings(
            launchAtStartup: false,
            launchCodexAfterSwitch: true,
            launchAntigravityAfterSwitch: false,
            autoSmartSwitchAntigravity: false,
            autoSmartSwitch: false,
            syncOpencodeOpenaiAuth: false,
            syncOpencodeAntigravityAuth: false,
            restartEditorsOnSwitch: false,
            restartEditorTargets: [],
            usageProgressDisplayMode: .used,
            quotaVisibility: .defaultValue,
            quotaWindowActivationMode: .off,
            quotaWindowActivationStartHour: 9,
            quotaWindowActivationEndHour: 18,
            locale: AppLocale.systemDefault.identifier
        )
    }
}

struct AppSettingsPatch {
    var launchAtStartup: Bool? = nil
    var launchCodexAfterSwitch: Bool? = nil
    var launchAntigravityAfterSwitch: Bool? = nil
    var autoSmartSwitchAntigravity: Bool? = nil
    var autoSmartSwitch: Bool? = nil
    var syncOpencodeOpenaiAuth: Bool? = nil
    var syncOpencodeAntigravityAuth: Bool? = nil
    var restartEditorsOnSwitch: Bool? = nil
    var restartEditorTargets: [EditorAppID]? = nil
    var usageProgressDisplayMode: UsageProgressDisplayMode? = nil
    var quotaVisibility: UsageQuotaVisibilityPreferences? = nil
    var quotaWindowActivationMode: QuotaWindowActivationMode? = nil
    var quotaWindowActivationStartHour: Int? = nil
    var quotaWindowActivationEndHour: Int? = nil
    var locale: String? = nil
}
