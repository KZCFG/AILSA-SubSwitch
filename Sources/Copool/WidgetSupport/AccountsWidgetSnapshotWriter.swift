import Foundation
import os
#if canImport(WidgetKit)
import WidgetKit
#endif

actor AccountsWidgetSnapshotWriter {
    private let logger = Logger(subsystem: "Copool", category: "AccountsWidgetSnapshotWriter")
    private let snapshotBuilder: AccountsWidgetSnapshotBuilder
    private let snapshotStore: AccountsWidgetSnapshotStore
    private let localeProvider: @Sendable () async -> Locale
    private let timeZoneProvider: @Sendable () async -> TimeZone
    private let reloadTimelinesOfKind: @MainActor @Sendable (String) -> Void

    init(
        snapshotBuilder: AccountsWidgetSnapshotBuilder = AccountsWidgetSnapshotBuilder(),
        snapshotStore: AccountsWidgetSnapshotStore = AccountsWidgetSnapshotStore(),
        localeProvider: @escaping @Sendable () async -> Locale,
        timeZoneProvider: @escaping @Sendable () async -> TimeZone = { .autoupdatingCurrent },
        reloadTimelinesOfKind: @escaping @MainActor @Sendable (String) -> Void = { kind in
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            #endif
        }
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.snapshotStore = snapshotStore
        self.localeProvider = localeProvider
        self.timeZoneProvider = timeZoneProvider
        self.reloadTimelinesOfKind = reloadTimelinesOfKind
    }

    init(
        snapshotBuilder: AccountsWidgetSnapshotBuilder = AccountsWidgetSnapshotBuilder(),
        snapshotStore: AccountsWidgetSnapshotStore = AccountsWidgetSnapshotStore(),
        localeProvider: @escaping @Sendable () async -> Locale,
        timeZoneProvider: @escaping @Sendable () async -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.snapshotBuilder = snapshotBuilder
        self.snapshotStore = snapshotStore
        self.localeProvider = localeProvider
        self.timeZoneProvider = timeZoneProvider
        self.reloadTimelinesOfKind = { kind in
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
            #endif
        }
    }

    func write(
        accounts: [AccountSummary],
        usageProgressDisplayMode: UsageProgressDisplayMode,
        quotaVisibility: UsageQuotaVisibilityPreferences = .defaultValue
    ) async {
        let locale = await localeProvider()
        let timeZone = await timeZoneProvider()
        let snapshot = snapshotBuilder.build(
            accounts: accounts,
            usageProgressDisplayMode: usageProgressDisplayMode,
            quotaVisibility: quotaVisibility,
            locale: locale,
            timeZone: timeZone
        )

        do {
            try snapshotStore.save(snapshot)
        } catch {
            logger.error("Widget snapshot save failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        #if canImport(WidgetKit)
        await MainActor.run {
            reloadTimelinesOfKind(AccountsWidgetConfiguration.kind)
        }
        #endif
    }
}
