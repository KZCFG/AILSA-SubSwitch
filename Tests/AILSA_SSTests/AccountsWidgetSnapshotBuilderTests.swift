import Foundation
import Testing
@testable import AILSA_SS

struct AccountsWidgetSnapshotBuilderTests {
    @Test
    func currentAccountBecomesPrimaryCardAndSecondaryUsesNextDisplayAccount() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                account(id: "b", isCurrent: false, email: "second@example.com", fiveHourUsed: 35, oneWeekUsed: 45),
                account(id: "a", isCurrent: true, email: "current@example.com", fiveHourUsed: 15, oneWeekUsed: 25)
            ],
            usageProgressDisplayMode: .used,
            locale: Locale(identifier: "zh-Hans"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.currentCard?.id == "a")
        #expect(snapshot.currentCard?.accountLabel == "current")
        #expect(snapshot.secondaryCard?.id == "b")
        #expect(snapshot.secondaryCard?.accountLabel == "second")
    }

    @Test
    func rowsKeepWorkspaceAndAccountLabelsAndExposeWindowSnapshots() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                account(id: "current", isCurrent: true, email: "current@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
                account(
                    id: "team",
                    isCurrent: false,
                    email: "member@example.com",
                    teamName: "workspace",
                    fiveHourUsed: 45,
                    oneWeekUsed: 55
                )
            ],
            usageProgressDisplayMode: .used,
            locale: Locale(identifier: "zh-Hans"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.rows.count == 1)
        #expect(snapshot.rows[0].workspaceLabel == "workspace")
        #expect(snapshot.rows[0].accountLabel == "member")
        #expect(snapshot.rows[0].fiveHour.remainingText == "55%")
        #expect(snapshot.rows[0].oneWeek.remainingText == "45%")
    }

    @Test
    func resetTimeUsesStableWidgetFormat() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                account(
                    id: "current",
                    isCurrent: true,
                    email: "current@example.com",
                    fiveHourUsed: 12,
                    oneWeekUsed: 34,
                    fiveHourResetAt: 1_774_020_225,
                    oneWeekResetAt: 1_774_106_625,
                    fiveHourCountdownStartedAt: 100
                )
            ],
            usageProgressDisplayMode: .used,
            locale: Locale(identifier: "zh-Hans"),
            timeZone: TimeZone(secondsFromGMT: 8 * 3600)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.currentCard?.fiveHour.resetText == "26/3/20 23:23:45")
        #expect(snapshot.currentCard?.oneWeek.resetText == "26/3/21 23:23:45")
    }

    @Test
    func defaultBuilderLimitsLargeRowsToFourAccounts() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                account(id: "current", isCurrent: true, email: "current@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
                account(id: "a", isCurrent: false, email: "a@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
                account(id: "b", isCurrent: false, email: "b@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
                account(id: "c", isCurrent: false, email: "c@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
                account(id: "d", isCurrent: false, email: "d@example.com", fiveHourUsed: 10, oneWeekUsed: 20),
            ],
            usageProgressDisplayMode: .used,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.rows.count == 4)
    }

    @Test
    func snapshotCarriesUsageProgressDisplayMode() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                account(id: "current", isCurrent: true, email: "current@example.com", fiveHourUsed: 12, oneWeekUsed: 34)
            ],
            usageProgressDisplayMode: .remaining,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.usageProgressDisplayMode == .remaining)
        #expect(snapshot.currentCard?.fiveHour.usedText == "12%")
        #expect(snapshot.currentCard?.fiveHour.remainingText == "88%")
    }

    @Test
    func antigravityWidgetUsesRealNamedQuotaRepresentatives() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                antigravityAccount(
                    id: "ag-current",
                    isCurrent: true,
                    fetchedAt: 100
                )
            ],
            usageProgressDisplayMode: .remaining,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.currentCard?.fiveHour.title == "Gemini 5h")
        #expect(snapshot.currentCard?.fiveHour.usedText == "0%")
        #expect(snapshot.currentCard?.fiveHour.remainingText == "100%")
        #expect(snapshot.currentCard?.oneWeek.title == "Gemini weekly")
        #expect(snapshot.currentCard?.oneWeek.usedText == "15%")
        #expect(snapshot.currentCard?.oneWeek.remainingText == "85%")
    }

    @Test
    func antigravityWidgetShowsUnknownForAvailabilityOnlyOrStaleSnapshots() {
        let builder = AccountsWidgetSnapshotBuilder()
        let snapshot = builder.build(
            accounts: [
                AccountSummary(
                    id: "ag-incomplete",
                    label: "AntiGravity",
                    email: "ag@example.com",
                    accountID: "ag-incomplete",
                    planType: "pro",
                    teamName: nil,
                    teamAlias: nil,
                    addedAt: 0,
                    updatedAt: 0,
                    usage: UsageSnapshot(
                        fetchedAt: 100,
                        planType: "pro",
                        fiveHour: UsageWindow(usedPercent: 0, windowSeconds: 18_000, resetAt: nil),
                        oneWeek: UsageWindow(usedPercent: 0, windowSeconds: 604_800, resetAt: nil),
                        credits: nil,
                        quotaFamilies: nil,
                        source: .antigravityRemoteAvailability,
                        sourceAccountMatched: true
                    ),
                    usageError: nil,
                    isCurrent: true,
                    provider: .antigravity
                )
            ],
            usageProgressDisplayMode: .remaining,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )

        #expect(snapshot.currentCard?.fiveHour.title == "--")
        #expect(snapshot.currentCard?.fiveHour.usedText == "--")
        #expect(snapshot.currentCard?.fiveHour.remainingText == "--")
        #expect(snapshot.currentCard?.oneWeek.usedText == "--")
    }

    @Test
    func widgetUsesOnlyVisibleRealCodexWindows() {
        let account = AccountSummary(
            id: "week-only",
            label: "week-only",
            email: "week@example.com",
            accountID: "week-only",
            planType: "pro_20x",
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: 0,
                planType: "pro_20x",
                fiveHour: nil,
                oneWeek: UsageWindow(usedPercent: 25, windowSeconds: 604_800, resetAt: nil),
                credits: nil
            ),
            usageError: nil,
            isCurrent: true
        )

        let visible = AccountsWidgetSnapshotBuilder().build(
            accounts: [account],
            usageProgressDisplayMode: .used,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )
        #expect(visible.currentCard?.visibleWindows.map(\.title) == ["1w"])

        var hidden = UsageQuotaVisibilityPreferences.defaultValue
        hidden.setVisible(false, for: UsageQuotaVisibilityKey.codexOneWeek)
        let filtered = AccountsWidgetSnapshotBuilder().build(
            accounts: [account],
            usageProgressDisplayMode: .used,
            quotaVisibility: hidden,
            locale: Locale(identifier: "en_US"),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            now: Date(timeIntervalSince1970: 100)
        )
        #expect(filtered.currentCard?.visibleWindows.isEmpty == true)
        #expect(filtered.currentCard?.isQuotaDisplayHidden == true)
    }

    private func account(
        id: String,
        isCurrent: Bool,
        email: String,
        teamName: String? = nil,
        fiveHourUsed: Double,
        oneWeekUsed: Double,
        fiveHourResetAt: Int64 = 1_774_020_225,
        oneWeekResetAt: Int64 = 1_774_106_625,
        fiveHourCountdownStartedAt: Int64? = nil
    ) -> AccountSummary {
        AccountSummary(
            id: id,
            label: id,
            email: email,
            accountID: id,
            planType: "team",
            teamName: teamName,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: 0,
                planType: "team",
                fiveHour: UsageWindow(
                    usedPercent: fiveHourUsed,
                    windowSeconds: 18_000,
                    resetAt: fiveHourResetAt,
                    countdownStartedAt: fiveHourCountdownStartedAt,
                    countdownStartEvidence: fiveHourCountdownStartedAt == nil ? nil : .requestObserved
                ),
                oneWeek: UsageWindow(usedPercent: oneWeekUsed, windowSeconds: 604_800, resetAt: oneWeekResetAt),
                credits: nil
            ),
            usageError: nil,
            isCurrent: isCurrent
        )
    }

    private func antigravityAccount(
        id: String,
        isCurrent: Bool,
        fetchedAt: Int64
    ) -> AccountSummary {
        AccountSummary(
            id: id,
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: id,
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 0,
            updatedAt: 0,
            usage: UsageSnapshot(
                fetchedAt: fetchedAt,
                planType: "pro",
                fiveHour: nil,
                oneWeek: nil,
                credits: nil,
                quotaFamilies: [
                    UsageQuotaFamily(
                        id: "gemini",
                        displayName: "Gemini",
                        buckets: [
                            UsageQuotaBucket(
                                id: "gemini-5h",
                                displayName: "Gemini 5h",
                                usedPercent: 0,
                                resetAt: 1_789_999_999,
                                windowSeconds: 18_000,
                                resetDescription: nil,
                                isUsageKnown: true
                            ),
                            UsageQuotaBucket(
                                id: "gemini-weekly",
                                displayName: "Gemini weekly",
                                usedPercent: 14.71916,
                                resetAt: 1_790_099_999,
                                windowSeconds: 604_800,
                                resetDescription: nil,
                                isUsageKnown: true
                            )
                        ]
                    ),
                    UsageQuotaFamily(
                        id: "third-party",
                        displayName: "Claude and GPT",
                        buckets: [
                            UsageQuotaBucket(
                                id: "third-party-5h",
                                displayName: "Third-party 5h",
                                usedPercent: 0,
                                resetAt: 1_789_999_999,
                                windowSeconds: 18_000,
                                resetDescription: nil,
                                isUsageKnown: true
                            ),
                            UsageQuotaBucket(
                                id: "third-party-weekly",
                                displayName: "Third-party weekly",
                                usedPercent: 0,
                                resetAt: 1_790_199_999,
                                windowSeconds: 604_800,
                                resetDescription: nil,
                                isUsageKnown: true
                            )
                        ]
                    )
                ],
                source: .antigravityNativeSummary,
                sourceAccountMatched: true
            ),
            usageError: nil,
            isCurrent: isCurrent,
            provider: .antigravity
        )
    }
}
