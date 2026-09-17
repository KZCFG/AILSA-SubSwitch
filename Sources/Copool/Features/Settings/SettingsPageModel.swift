import Foundation
import Combine

@MainActor
final class SettingsPageModel: ObservableObject {
    let settingsCoordinator: SettingsCoordinator
    let editorAppService: EditorAppServiceProtocol
    let antigravityAutomaticSwitchCapabilityProvider: @MainActor () -> AntigravityAutomaticSwitchCapability
    let onSettingsUpdated: @MainActor (AppSettings) -> Void
    let onQuitRequested: @MainActor () -> Void

    private let noticeScheduler = NoticeAutoDismissScheduler()

    @Published var settings: AppSettings = .defaultValue
    @Published var selectedSection: SettingsPageSection = .general
    @Published private(set) var quotaVisibilityItems: [QuotaVisibilitySettingsItem] = []
    @Published var installedEditorApps: [InstalledEditorApp] = []
    @Published private(set) var antigravityAutomaticSwitchCapability: AntigravityAutomaticSwitchCapability = .requiresManualSmartSwitch
    @Published var notice: NoticeMessage? {
        didSet {
            noticeScheduler.schedule(notice) { [weak self] in
                self?.notice = nil
            }
        }
    }

    var hasLoaded = false

    init(
        settingsCoordinator: SettingsCoordinator,
        editorAppService: EditorAppServiceProtocol,
        antigravityAutomaticSwitchCapabilityProvider: @escaping @MainActor () -> AntigravityAutomaticSwitchCapability = {
            .requiresManualSmartSwitch
        },
        onSettingsUpdated: @escaping @MainActor (AppSettings) -> Void = { _ in },
        onQuitRequested: @escaping @MainActor () -> Void = {}
    ) {
        self.settingsCoordinator = settingsCoordinator
        self.editorAppService = editorAppService
        self.antigravityAutomaticSwitchCapabilityProvider = antigravityAutomaticSwitchCapabilityProvider
        self.onSettingsUpdated = onSettingsUpdated
        self.onQuitRequested = onQuitRequested
    }

    func refreshAntigravityAutomaticSwitchCapability() {
        antigravityAutomaticSwitchCapability = antigravityAutomaticSwitchCapabilityProvider()
    }

    func updateQuotaVisibilityCatalog(from accounts: [AccountSummary]) {
        let nextItems = QuotaVisibilitySettingsItem.catalog(from: accounts)
        guard nextItems != quotaVisibilityItems else { return }
        quotaVisibilityItems = nextItems
    }

    func openQuotaDisplaySettings() {
        selectedSection = .quotaDisplay
    }
}

extension Notification.Name {
    static let copoolOpenQuotaDisplaySettings = Notification.Name(
        "com.alick.copool.openQuotaDisplaySettings"
    )
}

/// Ephemeral settings-page catalog. Its source is the latest provider data;
/// it is intentionally not persisted and never feeds account ranking.
struct QuotaVisibilitySettingsItem: Identifiable, Equatable {
    let id: String
    let provider: AccountProvider
    let groupTitle: String?
    let title: String

    static func catalog(from accounts: [AccountSummary]) -> [QuotaVisibilitySettingsItem] {
        var seen = Set<String>()
        var result: [QuotaVisibilitySettingsItem] = []

        func append(_ item: QuotaVisibilitySettingsItem) {
            guard seen.insert(item.id).inserted else { return }
            result.append(item)
        }

        for account in accounts where account.provider == .codex {
            guard let usage = account.usage else { continue }
            if Self.isKnown(usage.fiveHour?.usedPercent) {
                append(
                    QuotaVisibilitySettingsItem(
                        id: UsageQuotaVisibilityKey.codexFiveHour,
                        provider: .codex,
                        groupTitle: nil,
                        title: L10n.tr("accounts.window.five_hour")
                    )
                )
            }
            if Self.isKnown(usage.oneWeek?.usedPercent) {
                append(
                    QuotaVisibilitySettingsItem(
                        id: UsageQuotaVisibilityKey.codexOneWeek,
                        provider: .codex,
                        groupTitle: nil,
                        title: L10n.tr("accounts.window.one_week")
                    )
                )
            }
            for family in usage.codexQuotaFamilies ?? [] {
                for bucket in family.buckets where bucket.isUsageKnown && Self.isKnown(bucket.usedPercent) {
                    append(
                        QuotaVisibilitySettingsItem(
                            id: UsageQuotaVisibilityKey.codexAdditional(
                                familyID: family.id,
                                bucketID: bucket.id
                            ),
                            provider: .codex,
                            groupTitle: UsageQuotaDisplayName.family(family),
                            title: UsageQuotaDisplayName.bucket(bucket)
                        )
                    )
                }
            }
        }

        for account in accounts where account.provider == .antigravity {
            guard let usage = account.usage,
                  usage.hasAuthoritativeQuota,
                  usage.sourceAccountMatched != false else {
                continue
            }
            for family in usage.quotaFamilies ?? [] {
                for bucket in family.buckets where bucket.isUsageKnown && Self.isKnown(bucket.usedPercent) {
                    append(
                        QuotaVisibilitySettingsItem(
                            id: UsageQuotaVisibilityKey.antigravity(
                                familyID: family.id,
                                bucketID: bucket.id
                            ),
                            provider: .antigravity,
                            groupTitle: UsageQuotaDisplayName.family(family),
                            title: UsageQuotaDisplayName.bucket(bucket)
                        )
                    )
                }
            }
        }

        for pool in ["总计", "Cursor", "Third Party", "Grok Bot"] {
            append(QuotaVisibilitySettingsItem(id: UsageQuotaVisibilityKey.cursor(poolID: pool), provider: .cursor, groupTitle: nil, title: pool))
        }
        return result
    }

    private static func isKnown(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && (0...100).contains(value)
    }
}
