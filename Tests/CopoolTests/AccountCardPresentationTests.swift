import XCTest
@testable import Copool

final class AccountCardPresentationTests: XCTestCase {
    func testCurrentAccountPaletteUsesOwnAccentForSelectionHighlight() {
        let palette = AccountCardPalette(accent: .orange, isCurrent: true)

        XCTAssertEqual(palette.selectionBorderAccent, .orange)
        XCTAssertNotNil(palette.surfaceTint)
    }

    func testCollapsedPresentationUsesAliasAccentAndShortEmail() {
        let account = AccountSummary(
            id: "acct-1",
            label: "Primary",
            email: "dev@example.com",
            accountID: "account-1",
            planType: "business",
            teamName: "workspace-a",
            teamAlias: "Alias A",
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: 3,
                planType: "business",
                fiveHour: UsageWindow(usedPercent: 27.2, windowSeconds: 18_000, resetAt: 1_763_216_000),
                oneWeek: UsageWindow(usedPercent: 52.6, windowSeconds: 604_800, resetAt: 1_763_820_800),
                credits: CreditSnapshot(hasCredits: true, unlimited: false, balance: "128")
            ),
            usageError: nil,
            isCurrent: true
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: true,
            locale: Locale(identifier: "en_US_POSIX"),
            usageProgressDisplayMode: .used
        )

        XCTAssertEqual(presentation.accent, .indigo)
        XCTAssertEqual(presentation.planLabel, "BUSINESS")
        XCTAssertEqual(presentation.teamNameTag, "Alias A")
        XCTAssertEqual(presentation.displayAccountName, "dev")
        XCTAssertEqual(presentation.creditsText, "128" as String?)
        XCTAssertEqual(presentation.compactUsage.fiveHourDisplayPercent, 27)
        XCTAssertEqual(presentation.compactUsage.oneWeekDisplayPercent, 53)
    }

    func testExpandedPresentationFallsBackToTeamAccentAndMissingWindowDefaults() {
        let account = AccountSummary(
            id: "acct-2",
            label: "Backup",
            email: nil,
            accountID: "account-2",
            planType: nil,
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: 3,
                planType: nil,
                fiveHour: nil,
                oneWeek: nil,
                credits: CreditSnapshot(hasCredits: false, unlimited: true, balance: nil)
            ),
            usageError: nil,
            isCurrent: false
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .used
        )

        XCTAssertEqual(presentation.accent, .teal)
        XCTAssertEqual(presentation.planLabel, "TEAM")
        XCTAssertNil(presentation.teamNameTag)
        XCTAssertEqual(presentation.displayAccountName, "account-2")
        XCTAssertEqual(presentation.creditsText, L10n.tr("accounts.card.unlimited") as String?)
        XCTAssertFalse(presentation.fiveHourWindow.isUsageKnown)
        XCTAssertEqual(presentation.fiveHourWindow.progressPercent, 0)
        XCTAssertEqual(presentation.fiveHourWindow.resetText, L10n.tr("accounts.window.reset_at_format", "--"))
        XCTAssertTrue(presentation.quotaWindows.isEmpty)
        XCTAssertEqual(presentation.quotaStatusText, L10n.tr("accounts.quota.unavailable"))
    }

    func testPresentationShowsDeactivatedStatusTag() {
        let account = AccountSummary(
            id: "acct-3",
            label: "Workspace",
            email: "dev@example.com",
            accountID: "account-3",
            planType: "business",
            teamName: "workspace-a",
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: nil,
            usageError: nil,
            workspaceStatus: .deactivated,
            isCurrent: false
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US_POSIX"),
            usageProgressDisplayMode: .used
        )

        XCTAssertEqual(presentation.statusLabel, L10n.tr("accounts.card.status.deactivated"))
    }

    func testRemainingModeUsesRemainingForProgressAndCompactPercent() {
        let account = AccountSummary(
            id: "acct-4",
            label: "Primary",
            email: "dev@example.com",
            accountID: "account-4",
            planType: "team",
            teamName: "workspace-a",
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: 3,
                planType: "team",
                fiveHour: UsageWindow(usedPercent: 72, windowSeconds: 18_000, resetAt: 1_763_216_000),
                oneWeek: UsageWindow(usedPercent: 30, windowSeconds: 604_800, resetAt: 1_763_820_800),
                credits: nil
            ),
            usageError: nil,
            isCurrent: false
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .remaining
        )

        XCTAssertEqual(presentation.fiveHourWindow.progressPercent, 28)
        XCTAssertEqual(presentation.fiveHourWindow.primaryText, L10n.tr("accounts.window.remaining_format", "28%"))
        XCTAssertEqual(presentation.fiveHourWindow.secondaryText, L10n.tr("accounts.window.used_format", "72%"))
        XCTAssertEqual(
            presentation.fiveHourWindow.resetText,
            L10n.tr("accounts.window.reset_imminent")
        )
        XCTAssertEqual(presentation.compactUsage.fiveHourDisplayPercent, 28)
        XCTAssertEqual(presentation.compactUsage.oneWeekDisplayPercent, 70)
    }

    func testAntigravityUsesNamedAuthoritativeFamiliesRatherThanFixedModelBars() {
        let account = AccountSummary(
            id: "ag-current",
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: "ag-current",
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: Int64(Date().timeIntervalSince1970),
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
                            )
                        ]
                    )
                ],
                source: .antigravityNativeSummary,
                sourceAccountMatched: true
            ),
            usageError: nil,
            isCurrent: true,
            provider: .antigravity
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .remaining
        )

        XCTAssertEqual(presentation.quotaFamilies.map(\.title), ["Gemini", "Claude and GPT"])
        XCTAssertEqual(presentation.quotaFamilies.first?.windows.map(\.title), [L10n.tr("accounts.window.five_hour"), L10n.tr("accounts.window.one_week")])
        XCTAssertEqual(presentation.compactUsage.items.first?.subtitle, L10n.tr("accounts.window.five_hour"))
        XCTAssertEqual(presentation.compactUsage.items.first?.displayPercent, 100)
        XCTAssertFalse(presentation.quotaFamilies.flatMap(\.windows).contains {
            $0.title == L10n.tr("accounts.window.gemini_pro") || $0.title == L10n.tr("accounts.window.gemini_flash")
        })
        XCTAssertTrue(presentation.quotaStatusText?.contains(L10n.tr("accounts.quota.source.antigravity_native")) == true)
    }

    func testAntigravityWithoutCreditsOmitsCodexCreditPlaceholder() {
        let account = AccountSummary(
            id: "ag-no-credits",
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: "ag-no-credits",
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: 3,
                planType: "pro",
                fiveHour: nil,
                oneWeek: nil,
                credits: nil,
                quotaFamilies: nil,
                source: .antigravityNativeSummary,
                sourceAccountMatched: true
            ),
            usageError: nil,
            isCurrent: true,
            provider: .antigravity
        )

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .used
        )
        XCTAssertNil(presentation.creditsText)
    }

    func testAntigravityAvailabilityOnlyNeverRendersFakeFullQuota() {
        let account = AccountSummary(
            id: "ag-unverified",
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: "ag-unverified",
            planType: nil,
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: UsageSnapshot(
                fetchedAt: 1,
                planType: nil,
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

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .used
        )

        XCTAssertTrue(presentation.quotaFamilies.isEmpty)
        XCTAssertTrue(presentation.compactUsage.items.isEmpty)
        XCTAssertEqual(presentation.fiveHourWindow.primaryText, "--")
        XCTAssertEqual(presentation.fiveHourWindow.progressPercent, 0)
        XCTAssertTrue(presentation.quotaStatusText?.contains(L10n.tr("accounts.quota.unavailable")) == true)
    }

    func testAntigravityQuotaOrPermissionFailureKeepsRefreshRecoveryInsteadOfForcingLogin() {
        let account = AccountSummary(
            id: "ag-403",
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: "ag-403",
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: nil,
            usageError: "HTTP 403 remote quota unavailable",
            isCurrent: true,
            provider: .antigravity
        )

        XCTAssertFalse(AccountUsageRecoveryRules.requiresReauthentication(for: account))
    }

    func testAntigravity401StillOffersReauthentication() {
        let account = AccountSummary(
            id: "ag-401",
            label: "AntiGravity",
            email: "ag@example.com",
            accountID: "ag-401",
            planType: "pro",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 2,
            usage: nil,
            usageError: "HTTP 401 unauthorized",
            isCurrent: false,
            provider: .antigravity
        )

        XCTAssertTrue(AccountUsageRecoveryRules.requiresReauthentication(for: account))
    }

    func testCodexQuotaVisibilityKeepsAdditionalPoolIndependent() {
        let usage = UsageSnapshot(
            fetchedAt: 3,
            planType: "pro_20x",
            fiveHour: nil,
            oneWeek: UsageWindow(usedPercent: 24, windowSeconds: 604_800, resetAt: nil),
            credits: nil,
            codexQuotaFamilies: [
                UsageQuotaFamily(
                    id: "spark",
                    displayName: "Spark",
                    buckets: [
                        UsageQuotaBucket(
                            id: "weekly",
                            displayName: "1 week",
                            usedPercent: 18,
                            resetAt: nil,
                            windowSeconds: 604_800,
                            resetDescription: nil,
                            isUsageKnown: true
                        )
                    ]
                )
            ]
        )
        let account = AccountSummary(
            id: "codex-week-only",
            label: "Codex",
            email: nil,
            accountID: "codex-week-only",
            planType: "pro_20x",
            teamName: nil,
            teamAlias: nil,
            addedAt: 1,
            updatedAt: 1,
            usage: usage,
            usageError: nil,
            isCurrent: true
        )
        var visibility = UsageQuotaVisibilityPreferences.defaultValue
        visibility.setVisible(false, for: UsageQuotaVisibilityKey.codexOneWeek)

        let presentation = AccountCardPresentation(
            account: account,
            isCollapsed: false,
            locale: Locale(identifier: "en_US"),
            usageProgressDisplayMode: .used,
            quotaVisibility: visibility
        )

        XCTAssertFalse(presentation.fiveHourWindow.isUsageKnown)
        XCTAssertTrue(presentation.oneWeekWindow.isUsageKnown)
        XCTAssertTrue(presentation.quotaWindows.isEmpty)
        XCTAssertEqual(presentation.quotaFamilies.map(\.title), ["Spark"])
        XCTAssertEqual(presentation.compactUsage.items.map(\.id), [
            UsageQuotaVisibilityKey.codexAdditional(familyID: "spark", bucketID: "weekly")
        ])
        XCTAssertEqual(account.usage?.oneWeek?.usedPercent, 24)
    }
}
