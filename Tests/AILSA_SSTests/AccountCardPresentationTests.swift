import XCTest
@testable import AILSA_SS

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
                fiveHour: UsageWindow(usedPercent: 72, windowSeconds: 18_000, resetAt: 1_763_216_000, countdownStartedAt: 1_763_000_000),
                oneWeek: UsageWindow(usedPercent: 30, windowSeconds: 604_800, resetAt: 1_763_820_800, countdownStartedAt: 1_763_000_000),
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
        XCTAssertEqual(presentation.compactUsage.items.first?.subtitle, "Gemini\n" + L10n.tr("accounts.window.five_hour"))
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

final class AccountCardCustomizationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let locale = Locale(identifier: "zh_Hans_CN")

    private func warningPresentation(
        age: Int64,
        error: String?,
        hasSnapshot: Bool = true,
        isRefreshing: Bool = false
    ) -> AccountCardPresentation {
        let fetchedAt = Int64(Date().timeIntervalSince1970) - age
        let usage = UsageSnapshot(fetchedAt: fetchedAt, planType: "pro",
            fiveHour: nil, oneWeek: UsageWindow(usedPercent: 30, windowSeconds: 604_800, resetAt: nil), credits: nil)
        let account = AccountSummary(id: "warning", label: "Warning", email: "test@example.invalid", accountID: "warning",
            planType: "pro", teamName: nil, teamAlias: nil, addedAt: 1, updatedAt: 1,
            usage: hasSnapshot ? usage : nil, usageError: error, isCurrent: false)
        return AccountCardPresentation(account: account, isCollapsed: true, locale: locale,
            usageProgressDisplayMode: .remaining, isRefreshing: isRefreshing)
    }

    func testCompactStaleSnapshotShowsWarningAndOriginalUpdateTime() {
        let p = warningPresentation(age: 3600, error: nil)
        XCTAssertTrue(p.compactQuotaWarningText?.contains(L10n.tr("accounts.quota.stale")) == true)
        XCTAssertTrue(p.compactQuotaWarningText?.contains(" · ") == true)
        XCTAssertEqual(p.compactUsage.oneWeekDisplayPercent, 70)
    }

    func testRefreshingSnapshotTakesPriorityOverStaleWarning() {
        let p = warningPresentation(age: 3600, error: "previous failure", isRefreshing: true)

        XCTAssertEqual(p.compactQuotaWarningText, L10n.tr("accounts.quota.refreshing"))
        XCTAssertFalse(p.quotaStatusIsStale)
        XCTAssertFalse(p.provenanceText?.contains(L10n.tr("accounts.quota.stale")) == true)
    }

    func testCompactRecentSnapshotStillExposesFailedRefresh() {
        let p = warningPresentation(age: 30, error: "Identity could not be verified")
        XCTAssertFalse(p.quotaStatusIsStale)
        XCTAssertTrue(p.compactQuotaWarningText?.contains("Identity could not be verified") == true)
        XCTAssertEqual(p.compactUsage.oneWeekDisplayPercent, 70)
    }

    func testCompactMissingSnapshotExposesErrorWithoutInventingQuota() {
        let p = warningPresentation(age: 0, error: "Sign in expired", hasSnapshot: false)
        XCTAssertEqual(p.compactQuotaWarningText, "Sign in expired")
        XCTAssertTrue(p.compactUsage.items.isEmpty)
    }

    func testCompactFreshSuccessfulSnapshotHasNoWarning() {
        XCTAssertNil(warningPresentation(age: 30, error: nil).compactQuotaWarningText)
        XCTAssertNil(warningPresentation(age: 30, error: "  ").compactQuotaWarningText)
    }

    private func presentation(hidden: Set<String> = [], mode: UsageProgressDisplayMode = .remaining) -> AccountCardPresentation {
        let families = ["gemini", "claude"].map { family in
            UsageQuotaFamily(id: family, displayName: family == "gemini" ? "Gemini" : "Claude",
                buckets: [UsageQuotaBucket(id: "5h", displayName: "5h", usedPercent: 20,
                    resetAt: nil, windowSeconds: 18_000, resetDescription: nil, isUsageKnown: true),
                    UsageQuotaBucket(id: "weekly", displayName: "weekly", usedPercent: 40,
                    resetAt: nil, windowSeconds: 604_800, resetDescription: nil, isUsageKnown: true)])
        }
        let usage = UsageSnapshot(fetchedAt: Int64(now.timeIntervalSince1970), planType: "pro",
            fiveHour: nil, oneWeek: nil, credits: nil, quotaFamilies: families,
            source: .antigravityNativeSummary, sourceAccountMatched: true)
        let account = AccountSummary(id: "a", label: "A", email: "a@example.invalid", accountID: "a",
            planType: "pro", teamName: nil, teamAlias: nil, addedAt: 1, updatedAt: 1,
            usage: usage, usageError: nil, isCurrent: true, provider: .antigravity)
        return AccountCardPresentation(account: account, isCollapsed: true, locale: locale,
            usageProgressDisplayMode: mode, quotaVisibility: UsageQuotaVisibilityPreferences(hiddenKeys: hidden))
    }
    func testFamilyNamesDisambiguateBothFiveHourRings() {
        let p = presentation()
        XCTAssertEqual(p.compactUsage.items.count, 2)
        XCTAssertTrue(p.compactUsage.items.contains { $0.subtitle.contains("Gemini") })
        XCTAssertTrue(p.compactUsage.items.contains { $0.subtitle.contains("Claude") })
        XCTAssertEqual(p.availableCompactItems.count, 4)
    }
    func testChoicesGroupGeminiWindowsBeforeClaudeWindows() {
        let p = presentation()
        XCTAssertEqual(p.availableCompactItems.map(\.id), ["antigravity.gemini.5h", "antigravity.gemini.weekly", "antigravity.claude.5h", "antigravity.claude.weekly"])
        XCTAssertEqual(p.compactUsage.items.map(\.id), ["antigravity.gemini.5h", "antigravity.claude.5h"])
    }
    func testCountdownCarriesEverySecondAndSupportsEnglishUnits() {
        let date = now.addingTimeInterval(86_400)
        XCTAssertEqual(AccountCountdown.duration(until: date, now: now.addingTimeInterval(1), units: .abbreviated), "0d 23h 59m 59s")
        XCTAssertEqual(AccountCountdown.duration(until: date, now: date.addingTimeInterval(-0.2), units: .abbreviated), "0d 0h 0m 1s")
        XCTAssertEqual(AccountCountdown.duration(until: date, now: date.addingTimeInterval(1), units: .abbreviated), "0d 0h 0m 0s")
    }
    func testOrderReconcilesDeletedAndNewAccountsWithoutDuplicates() {
        XCTAssertEqual(AccountOrderPreferences.reconcile(["b", "deleted", "a", "b"], available: ["a", "b", "new", "new"]), ["b", "a", "new"])
    }
    func testReorderPersistsPerProviderAndDoesNotChangeMembership() {
        var preferences = AccountOrderPreferences()
        preferences.orders["antigravity"] = AccountOrderPreferences.moving("a", to: "c", in: ["a", "b", "c"])
        preferences.orders["codex"] = ["a", "b", "c"]
        let decoded = AccountOrderPreferences.decode(preferences.encoded)
        XCTAssertEqual(decoded.ordered(["a", "b", "c"], provider: .antigravity), ["b", "c", "a"])
        XCTAssertEqual(decoded.ordered(["c", "b", "a"], provider: .codex), ["a", "b", "c"])
        XCTAssertEqual(AccountOrderPreferences.moving("a", to: "missing", in: ["a", "b"]), ["a", "b"])
        XCTAssertEqual(AccountOrderPreferences.moving("c", to: "a", in: ["a", "b", "c"]), ["c", "a", "b"])
    }
    func testCompactGridFitsThreeColumnsAndCodexKeepsRoomForCredits() {
        XCTAssertEqual(AccountCollectionLayout.columns(provider: .antigravity, compact: true, availableWidth: 512), 3)
        XCTAssertEqual(AccountCollectionLayout.columns(provider: .cursor, compact: true, availableWidth: 512), 3)
        XCTAssertEqual(AccountCollectionLayout.columns(provider: .codex, compact: true, availableWidth: 512), 2)
        XCTAssertEqual(AccountCollectionLayout.columns(provider: .antigravity, compact: false, availableWidth: 512), 2)
        XCTAssertEqual(AccountCollectionLayout.columns(provider: .antigravity, compact: true, availableWidth: 300), 1)
    }
    func testWeeklyCanBeSelectedWithoutChangingQuotaDataOrUsedMode() {
        let p = presentation(mode: .used)
        let weekly = p.availableCompactItems.first { $0.id == "antigravity.gemini.weekly" }!
        var prefs = CompactRingPreferences()
        prefs.selections[CompactRingPreferences.scope(provider: .antigravity)] = [CompactQuotaChoice(weekly), nil]
        XCTAssertEqual(prefs.items(for: p).map(\.id), [weekly.id])
        XCTAssertEqual(prefs.items(for: p).first?.displayPercent, 40)
        XCTAssertEqual(p.quotaFamilies.count, 2)
    }
    func testAccountOverrideAndProviderDefaultsSurviveRoundTrip() {
        let p = presentation()
        var prefs = CompactRingPreferences()
        prefs.selections[CompactRingPreferences.scope(provider: .antigravity)] = [CompactQuotaChoice(p.availableCompactItems[0]), nil]
        prefs.selections[CompactRingPreferences.scope(provider: .antigravity, accountID: "a")] = [CompactQuotaChoice(p.availableCompactItems[3]), nil]
        let decoded = CompactRingPreferences.decode(prefs.encoded)
        XCTAssertEqual(decoded, prefs)
        XCTAssertEqual(decoded.items(for: p).first?.id, p.availableCompactItems[3].id)
        XCTAssertEqual(decoded.choices(provider: .antigravity, accountID: "b")?.first??.id, p.availableCompactItems[0].id)
        XCTAssertNil(decoded.choices(provider: .codex, accountID: "a"))
    }
    func testDuplicateSelectionSwapsSlots() {
        let p = presentation()
        let first = CompactQuotaChoice(p.availableCompactItems[0]), second = CompactQuotaChoice(p.availableCompactItems[1])
        var prefs = CompactRingPreferences()
        let scope = CompactRingPreferences.scope(provider: .antigravity)
        prefs.set(second, at: 0, scope: scope, fallback: [first, second])
        XCTAssertEqual(prefs.selections[scope]!, [second, first])
    }
    func testUnavailableExplicitChoiceDoesNotBorrowAnotherQuota() {
        let p = presentation()
        var prefs = CompactRingPreferences()
        prefs.selections[CompactRingPreferences.scope(provider: .antigravity)] = [CompactQuotaChoice(id: "gone", title: "Missing pool\n5h"), nil]
        let selected = prefs.items(for: p)
        XCTAssertEqual(selected.first?.subtitle, "Missing pool\n5h")
        XCTAssertNil(selected.first?.displayPercent)
        XCTAssertEqual(selected.count, 1)
    }
    func testHiddenQuotaRemainsHiddenWithExplicitSelection() {
        let key = "antigravity.gemini.weekly"
        var prefs = CompactRingPreferences()
        prefs.selections[CompactRingPreferences.scope(provider: .antigravity)] = [CompactQuotaChoice(id: key, title: "Gemini weekly"), nil]
        XCTAssertTrue(prefs.items(for: presentation(hidden: [key])).isEmpty)
    }
    func testMalformedPreferencesUseAutomaticSelection() {
        let p = presentation()
        XCTAssertEqual(CompactRingPreferences.decode("bad json").items(for: p), p.compactUsage.items)
    }
    func testResetCardsSortAndNumberEachExpiry() {
        let inventory = ResetCreditInventory(availableCount: 3,
            expiresAt: [now.addingTimeInterval(4 * 86_400), now.addingTimeInterval(2 * 86_400 + 3 * 3600)], fetchedAt: now)
        let rows = ResetCreditPresentation.rows(inventory, mode: .remaining, now: now, locale: locale)
        XCTAssertEqual(rows.map(\.title), ["重置卡 1", "重置卡 2", "重置卡 3"])
        XCTAssertEqual(rows[0].timeText, "2 天 3 小时 0 分 0 秒 后到期")
        XCTAssertEqual(rows[1].timeText, "4 天 0 小时 0 分 0 秒 后到期")
        XCTAssertEqual(rows[2].timeText, "到期时间未知")
    }
    func testResetCountdownUpdatesAtHourAndMinuteBoundaries() {
        let inventory = ResetCreditInventory(availableCount: 1, expiresAt: [now.addingTimeInterval(86_400 + 3_600)], fetchedAt: now)
        XCTAssertEqual(ResetCreditPresentation.rows(inventory, mode: .remaining, now: now.addingTimeInterval(3600), locale: locale)[0].timeText, "1 天 0 小时 0 分 0 秒 后到期")
        let short = ResetCreditInventory(availableCount: 1, expiresAt: [now.addingTimeInterval(30)], fetchedAt: now)
        XCTAssertEqual(ResetCreditPresentation.rows(short, mode: .remaining, now: now, locale: locale)[0].timeText, "0 天 0 小时 0 分 30 秒 后到期")
        XCTAssertEqual(ResetCreditPresentation.rows(short, mode: .remaining, now: now.addingTimeInterval(30), locale: locale)[0].timeText, "已到期")
    }
    func testAbsoluteExpiryIsIndependentOfProgressModeAndClock() {
        let date = now.addingTimeInterval(86_400)
        let inventory = ResetCreditInventory(availableCount: 1, expiresAt: [date], fetchedAt: now)
        XCTAssertEqual(ResetCreditPresentation.rows(inventory, mode: .expiry, now: now, locale: locale),
            ResetCreditPresentation.rows(inventory, mode: .expiry, now: now.addingTimeInterval(7200), locale: locale))
    }
    func testZeroResetCardsDoesNotRenderOrInventExpiries() {
        let inventory = ResetCreditInventory(availableCount: 0, expiresAt: [now], fetchedAt: now)
        XCTAssertTrue(ResetCreditPresentation.rows(inventory, mode: .remaining, now: now, locale: locale).isEmpty)
    }
    func testEachProviderSupportsBothSkinsAndUnknownValuesPreserveBrand() {
        for style: UsageProgressFillStyle in [.codex, .antigravity, .cursor] {
            XCTAssertEqual(UsageProgressSkin.resolve(style, rawValue: "official"), style)
            XCTAssertEqual(UsageProgressSkin.resolve(style, rawValue: "ailsa"), .monochrome)
            XCTAssertEqual(UsageProgressSkin.resolve(style, rawValue: "future"), style)
        }
    }
}
