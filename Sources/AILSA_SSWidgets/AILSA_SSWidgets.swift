import SwiftUI
import WidgetKit

@main
struct AILSA_SSWidgets: WidgetBundle {
    var body: some Widget {
        AILSA_SSAccountsWidget()
    }
}

struct AILSA_SSAccountsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: AccountsWidgetConfiguration.kind,
            provider: AccountsWidgetTimelineProvider()
        ) { entry in
            AccountsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("AILSA SubSwitch Accounts")
        .description("See the current account and usage at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AccountsWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: AccountsWidgetSnapshot
}

struct AccountsWidgetTimelineProvider: TimelineProvider {
    private let store = AccountsWidgetSnapshotStore()

    func placeholder(in context: Context) -> AccountsWidgetEntry {
        AccountsWidgetEntry(date: .now, snapshot: sampleSnapshot)
    }

    func getSnapshot(in context: Context, completion: @escaping (AccountsWidgetEntry) -> Void) {
        let snapshot = store.load()
        completion(
            AccountsWidgetEntry(
                date: .now,
                snapshot: snapshot
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AccountsWidgetEntry>) -> Void) {
        _ = context
        let snapshot = store.load()
        let entry = AccountsWidgetEntry(
            date: .now,
            snapshot: snapshot
        )
        completion(
            Timeline(
                entries: [entry],
                policy: .after(.now.addingTimeInterval(60 * 15))
            )
        )
    }

    private var sampleSnapshot: AccountsWidgetSnapshot {
        AccountsWidgetSnapshot(
            generatedAt: Int64(Date().timeIntervalSince1970),
            usageProgressDisplayMode: .used,
            currentCard: AccountsWidgetCardSnapshot(
                id: "current",
                planLabel: "TEAM",
                workspaceLabel: "workspace",
                accountLabel: "current_account",
                fiveHour: AccountsWidgetWindowSnapshot(
                    title: "5h",
                    progressFraction: 0.42,
                    usedText: "42%",
                    remainingText: "58%",
                    resetText: "26/3/21 01:23:45"
                ),
                oneWeek: AccountsWidgetWindowSnapshot(
                    title: "1w",
                    progressFraction: 0.18,
                    usedText: "18%",
                    remainingText: "82%",
                    resetText: "26/3/27 01:23:45"
                )
            ),
            secondaryCard: AccountsWidgetCardSnapshot(
                id: "next",
                planLabel: "PRO",
                workspaceLabel: nil,
                accountLabel: "next_account",
                fiveHour: AccountsWidgetWindowSnapshot(
                    title: "5h",
                    progressFraction: 0.55,
                    usedText: "55%",
                    remainingText: "45%",
                    resetText: "26/3/21 03:11:22"
                ),
                oneWeek: AccountsWidgetWindowSnapshot(
                    title: "1w",
                    progressFraction: 0.31,
                    usedText: "31%",
                    remainingText: "69%",
                    resetText: "26/3/26 11:04:12"
                )
            ),
            rows: [
                AccountsWidgetRowSnapshot(
                    id: "row-1",
                    planLabel: "TEAM",
                    workspaceLabel: "abcdefg",
                    accountLabel: "account_name",
                    fiveHour: AccountsWidgetWindowSnapshot(
                        title: "5h",
                        progressFraction: 0.50,
                        usedText: "50%",
                        remainingText: "50%",
                        resetText: "26/3/21 01:23:45"
                    ),
                    oneWeek: AccountsWidgetWindowSnapshot(
                        title: "1w",
                        progressFraction: 0.02,
                        usedText: "2%",
                        remainingText: "98%",
                        resetText: "26/3/27 01:23:45"
                    )
                ),
                AccountsWidgetRowSnapshot(
                    id: "row-2",
                    planLabel: "PLUS",
                    workspaceLabel: nil,
                    accountLabel: "plus_account",
                    fiveHour: AccountsWidgetWindowSnapshot(
                        title: "5h",
                        progressFraction: 0.18,
                        usedText: "18%",
                        remainingText: "82%",
                        resetText: "26/3/21 08:54:12"
                    ),
                    oneWeek: AccountsWidgetWindowSnapshot(
                        title: "1w",
                        progressFraction: 0.36,
                        usedText: "36%",
                        remainingText: "64%",
                        resetText: "26/3/25 18:22:09"
                    )
                ),
            ]
        )
    }
}
