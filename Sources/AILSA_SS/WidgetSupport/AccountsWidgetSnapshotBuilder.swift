import Foundation

struct AccountsWidgetSnapshotBuilder {
    private let maxRowCount: Int

    init(maxRowCount: Int = 4) {
        self.maxRowCount = maxRowCount
    }

    func build(
        accounts: [AccountSummary],
        usageProgressDisplayMode: UsageProgressDisplayMode,
        quotaVisibility: UsageQuotaVisibilityPreferences = .defaultValue,
        locale: Locale,
        timeZone: TimeZone = .autoupdatingCurrent,
        now: Date = .now
    ) -> AccountsWidgetSnapshot {
        let sorted = AccountRanking.sortForDisplay(accounts)
        guard let current = sorted.first else {
            return .empty
        }

        let remaining = Array(sorted.dropFirst())
        return AccountsWidgetSnapshot(
            generatedAt: Int64(now.timeIntervalSince1970),
            usageProgressDisplayMode: usageProgressDisplayMode == .remaining ? .remaining : .used,
            currentCard: cardSnapshot(
                for: current,
                quotaVisibility: quotaVisibility,
                locale: locale,
                timeZone: timeZone,
                now: now
            ),
            secondaryCard: remaining.first.map {
                cardSnapshot(
                    for: $0,
                    quotaVisibility: quotaVisibility,
                    locale: locale,
                    timeZone: timeZone,
                    now: now
                )
            },
            rows: Array(remaining.prefix(maxRowCount)).map {
                rowSnapshot(
                    for: $0,
                    quotaVisibility: quotaVisibility,
                    locale: locale,
                    timeZone: timeZone,
                    now: now
                )
            }
        )
    }

    private func cardSnapshot(
        for account: AccountSummary,
        quotaVisibility: UsageQuotaVisibilityPreferences,
        locale: Locale,
        timeZone: TimeZone,
        now: Date
    ) -> AccountsWidgetCardSnapshot {
        let selection = compactWindows(
            for: account,
            quotaVisibility: quotaVisibility,
            locale: locale,
            timeZone: timeZone,
            now: now
        )
        return AccountsWidgetCardSnapshot(
            id: account.id,
            planLabel: account.normalizedPlanLabel,
            workspaceLabel: account.displayTeamName,
            accountLabel: AccountDisplayNameFormatter.format(account: account, style: .localPart),
            fiveHour: selection.windows[0],
            oneWeek: selection.windows[1],
            quotaDisplayHidden: selection.isQuotaDisplayHidden
        )
    }

    private func rowSnapshot(
        for account: AccountSummary,
        quotaVisibility: UsageQuotaVisibilityPreferences,
        locale: Locale,
        timeZone: TimeZone,
        now: Date
    ) -> AccountsWidgetRowSnapshot {
        let accountLabel = AccountDisplayNameFormatter.format(account: account, style: .localPart)
        let selection = compactWindows(
            for: account,
            quotaVisibility: quotaVisibility,
            locale: locale,
            timeZone: timeZone,
            now: now
        )
        return AccountsWidgetRowSnapshot(
            id: account.id,
            planLabel: account.normalizedPlanLabel,
            workspaceLabel: account.displayTeamName,
            accountLabel: accountLabel,
            fiveHour: selection.windows[0],
            oneWeek: selection.windows[1],
            quotaDisplayHidden: selection.isQuotaDisplayHidden
        )
    }

    private struct CompactWindowSelection {
        let windows: [AccountsWidgetWindowSnapshot]
        let isQuotaDisplayHidden: Bool
    }

    /// Widgets only have room for two metrics. The resulting windows are
    /// always real, visible provider values; invisible placeholders only keep
    /// the on-disk snapshot shape backward compatible.
    private func compactWindows(
        for account: AccountSummary,
        quotaVisibility: UsageQuotaVisibilityPreferences,
        locale: Locale,
        timeZone: TimeZone,
        now: Date
    ) -> CompactWindowSelection {
        if account.provider == .antigravity,
           let usage = account.usage,
           usage.hasAuthoritativeQuota,
           usage.sourceAccountMatched != false,
           !usage.isStale(now: Int64(now.timeIntervalSince1970)) {
            let knownPairs = (usage.quotaFamilies ?? []).flatMap { family in
                family.buckets.compactMap { bucket -> (UsageQuotaFamily, UsageQuotaBucket)? in
                    guard bucket.isUsageKnown,
                          validUsedPercent(bucket.usedPercent) != nil else {
                        return nil
                    }
                    return (family, bucket)
                }
            }
            let actual = knownPairs
                .filter { family, bucket in
                    quotaVisibility.isVisible(
                        UsageQuotaVisibilityKey.antigravity(
                            familyID: family.id,
                            bucketID: bucket.id
                        )
                    )
                }
                .sorted { left, right in
                    if left.1.cadenceRank != right.1.cadenceRank {
                        return left.1.cadenceRank < right.1.cadenceRank
                    }
                    return left.1.id.localizedCaseInsensitiveCompare(right.1.id) == .orderedAscending
                }
                .prefix(2)
                .map { _, bucket in
                    quotaBucketSnapshot(
                        title: UsageQuotaDisplayName.bucket(bucket),
                        usedPercent: bucket.usedPercent ?? 0,
                        resetAt: bucket.resetAt,
                        countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                            windowSeconds: bucket.windowSeconds,
                            identifier: "\(bucket.id) \(bucket.displayName)"
                        ),
                        countdownStartedAt: bucket.countdownStartedAt,
                        locale: locale,
                        timeZone: timeZone
                    )
                }
            return CompactWindowSelection(
                windows: paddedWindows(actual),
                isQuotaDisplayHidden: !knownPairs.isEmpty && actual.isEmpty
            )
        }

        if account.provider == .antigravity {
            return CompactWindowSelection(
                windows: paddedWindows([]),
                isQuotaDisplayHidden: false
            )
        }

        let standardCandidates: [(key: String, title: String, window: UsageWindow?)] = [
            (UsageQuotaVisibilityKey.codexFiveHour, "5h", account.usage?.fiveHour),
            (UsageQuotaVisibilityKey.codexOneWeek, "1w", account.usage?.oneWeek)
        ]
        let knownStandard = standardCandidates.filter { candidate in
            validUsedPercent(candidate.window?.usedPercent) != nil
        }
        let additionalCandidates = (account.usage?.codexQuotaFamilies ?? []).flatMap { family in
            family.buckets.compactMap { bucket -> (String, String, UsageQuotaBucket)? in
                guard bucket.isUsageKnown,
                      validUsedPercent(bucket.usedPercent) != nil else {
                    return nil
                }
                return (
                    UsageQuotaVisibilityKey.codexAdditional(
                        familyID: family.id,
                        bucketID: bucket.id
                    ),
                    UsageQuotaDisplayName.bucket(bucket),
                    bucket
                )
            }
        }
        let standardWindows = knownStandard.compactMap { candidate -> AccountsWidgetWindowSnapshot? in
            guard quotaVisibility.isVisible(candidate.key),
                  let window = candidate.window else {
                return nil
            }
            return windowSnapshot(
                title: candidate.title,
                window: window,
                countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                    windowSeconds: window.windowSeconds,
                    identifier: candidate.title
                ),
                locale: locale,
                timeZone: timeZone
            )
        }
        let additionalWindows = additionalCandidates.compactMap { key, title, bucket -> AccountsWidgetWindowSnapshot? in
            guard quotaVisibility.isVisible(key),
                  let usedPercent = validUsedPercent(bucket.usedPercent) else {
                return nil
            }
            return quotaBucketSnapshot(
                title: title,
                usedPercent: usedPercent,
                resetAt: bucket.resetAt,
                countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                    windowSeconds: bucket.windowSeconds,
                    identifier: "\(bucket.id) \(bucket.displayName)"
                ),
                countdownStartedAt: bucket.countdownStartedAt,
                locale: locale,
                timeZone: timeZone
            )
        }
        let actual = Array((standardWindows + additionalWindows).prefix(2))
        return CompactWindowSelection(
            windows: paddedWindows(actual),
            isQuotaDisplayHidden: (!knownStandard.isEmpty || !additionalCandidates.isEmpty) && actual.isEmpty
        )
    }

    private func paddedWindows(
        _ windows: [AccountsWidgetWindowSnapshot]
    ) -> [AccountsWidgetWindowSnapshot] {
        Array(windows.prefix(2)) + Array(
            repeating: unknownWindowSnapshot(),
            count: max(0, 2 - windows.count)
        )
    }

    private func quotaBucketSnapshot(
        title: String,
        usedPercent: Double,
        resetAt: Int64?,
        countdownRequiresRequest: Bool,
        countdownStartedAt: Int64?,
        locale: Locale,
        timeZone: TimeZone
    ) -> AccountsWidgetWindowSnapshot {
        let remaining = max(0, 100 - Int(usedPercent.rounded()))
        return AccountsWidgetWindowSnapshot(
            title: title,
            progressFraction: usedPercent / 100,
            usedText: "\(Int(usedPercent.rounded()))%",
            remainingText: "\(remaining)%",
            resetText: resetText(
                for: resetAt,
                countdownStartedAt: countdownStartedAt,
                requiresRequestEvidence: countdownRequiresRequest,
                locale: locale,
                timeZone: timeZone
            ),
            isVisible: true
        )
    }

    private func unknownWindowSnapshot() -> AccountsWidgetWindowSnapshot {
        AccountsWidgetWindowSnapshot(
            title: "--",
            progressFraction: 0,
            usedText: "--",
            remainingText: "--",
            resetText: "--",
            isVisible: false
        )
    }

    private func windowSnapshot(
        title: String,
        window: UsageWindow,
        countdownRequiresRequest: Bool,
        locale: Locale,
        timeZone: TimeZone
    ) -> AccountsWidgetWindowSnapshot {
        let usedPercent = clamped(window.usedPercent)
        let remaining = max(0, 100 - Int(usedPercent.rounded()))

        return AccountsWidgetWindowSnapshot(
            title: title,
            progressFraction: usedPercent / 100,
            usedText: "\(Int(usedPercent.rounded()))%",
            remainingText: "\(remaining)%",
            resetText: resetText(
                for: window.resetAt,
                countdownStartedAt: window.countdownStartedAt,
                requiresRequestEvidence: countdownRequiresRequest,
                locale: locale,
                timeZone: timeZone
            ),
            isVisible: true
        )
    }

    private func resetText(
        for resetAt: Int64?,
        countdownStartedAt: Int64?,
        requiresRequestEvidence: Bool,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        guard let resetAt else { return "--" }
        guard !requiresRequestEvidence || countdownStartedAt != nil else {
            return L10n.tr("accounts.window.awaiting_first_request")
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yy/M/d HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(resetAt)))
    }

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private func validUsedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
}
