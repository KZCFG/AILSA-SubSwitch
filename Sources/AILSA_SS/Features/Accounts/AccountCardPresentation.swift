import Foundation

enum AccountCardAccent: Equatable {
    case orange
    case pink
    case gray
    case indigo
    case teal
}

struct AccountWindowPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let progressPercent: Double
    let primaryText: String
    let secondaryText: String
    let resetText: String
    let isUsageKnown: Bool
    var resetAt: Date? = nil
}

/// A real quota family reported by AntiGravity. The server groups Gemini and
/// third-party pools independently, so the UI preserves the source group names
/// rather than relabeling them as fixed Pro/Flash bars.
struct AccountQuotaFamilyPresentation: Equatable, Identifiable {
    let id: String
    let title: String
    let windows: [AccountWindowPresentation]
}

struct AccountCompactQuotaPresentation: Equatable, Identifiable {
    let id: String
    let subtitle: String
    let displayPercent: Double?
}

struct AccountCompactUsagePresentation: Equatable {
    /// Kept for legacy Codex consumers and existing snapshots. New provider
    /// surfaces use `items`, which is based on real quota buckets.
    let fiveHourDisplayPercent: Double?
    let oneWeekDisplayPercent: Double?
    let items: [AccountCompactQuotaPresentation]
}

struct AccountCardPresentation: Equatable {
    let accountID: String
    let provider: AccountProvider
    let resetCreditInventory: ResetCreditInventory?
    let availableCompactItems: [AccountCompactQuotaPresentation]
    let hiddenQuotaKeys: Set<String>
    let accent: AccountCardAccent
    let planLabel: String
    let teamNameTag: String?
    let statusLabel: String?
    let statusIsPendingNativeSwitch: Bool
    let displayAccountName: String
    let resetCreditsText: String?
    let creditsText: String?
    /// Exact `credits.balance` string as returned by the provider. The card
    /// deliberately renders a compact display value, while accessibility and
    /// Copy retain this original value without changing the stored model.
    let creditsRawText: String?
    /// Only real, user-visible standard Codex windows.  The legacy two fixed
    /// properties below remain for compatibility with callers, but rendering
    /// is driven by this collection so a missing 5-hour limit is never shown
    /// as an invented full bar.
    let quotaWindows: [AccountWindowPresentation]
    let fiveHourWindow: AccountWindowPresentation
    let oneWeekWindow: AccountWindowPresentation
    let quotaFamilies: [AccountQuotaFamilyPresentation]
    let quotaStatusText: String?
    let isRefreshing: Bool
    let isQuotaDisplayHidden: Bool
    /// True when the usage snapshot behind the status/provenance metadata is
    /// stale, so views can tint that metadata instead of only appending a
    /// text marker.
    let quotaStatusIsStale: Bool
    /// Compact cards keep the last known rings, but must expose failed refreshes
    /// and aging snapshots just as expanded cards do.
    let compactQuotaWarningText: String?
    /// Provenance is deliberately secondary to the quota itself.  It is kept
    /// separate from `quotaStatusText` so Codex cards can show both bars and
    /// their update/source metadata at once.
    let provenanceText: String?
    let compactUsage: AccountCompactUsagePresentation
    let usageProgressFillStyle: UsageProgressFillStyle

    init(
        account: AccountSummary,
        isCollapsed: Bool,
        locale: Locale,
        usageProgressDisplayMode: UsageProgressDisplayMode,
        quotaVisibility: UsageQuotaVisibilityPreferences = .defaultValue,
        isRefreshing: Bool = false
    ) {
        accountID = account.id
        hiddenQuotaKeys = quotaVisibility.hiddenKeys
        provider = account.provider
        self.isRefreshing = isRefreshing
        resetCreditInventory = account.provider == .codex ? account.usage?.resetCredits : nil
        let planLabel = account.normalizedPlanLabel
        self.planLabel = planLabel
        usageProgressFillStyle = account.provider == .codex ? .codex : .antigravity
        accent = Self.accent(for: planLabel)
        let usageIsStale = account.usage?.isStale(now: Int64(Date().timeIntervalSince1970)) ?? false
        quotaStatusIsStale = !isRefreshing && usageIsStale
        let refreshError = account.usageError?.trimmingCharacters(in: .whitespacesAndNewlines)
        var compactWarnings: [String] = []
        if isRefreshing {
            compactWarnings.append(L10n.tr("accounts.quota.refreshing"))
        } else {
            if usageIsStale { compactWarnings.append(L10n.tr("accounts.quota.stale")) }
            if let refreshError, !refreshError.isEmpty { compactWarnings.append(refreshError) }
        }
        if !isRefreshing, !compactWarnings.isEmpty, let usage = account.usage, usage.fetchedAt > 0 {
            compactWarnings.append(Self.lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        compactQuotaWarningText = compactWarnings.isEmpty ? nil : compactWarnings.joined(separator: " · ")
        teamNameTag = account.shouldDisplayWorkspaceTag ? account.displayTeamName : nil
        if account.isPendingNativeSwitch {
            statusLabel = L10n.tr("accounts.card.pending_native_switch")
            statusIsPendingNativeSwitch = true
        } else {
            statusLabel = account.isWorkspaceDeactivated ? L10n.tr("accounts.card.status.deactivated") : nil
            statusIsPendingNativeSwitch = false
        }
        displayAccountName = Self.displayName(for: account, isCollapsed: isCollapsed)
        if account.provider == .codex, let inventory = account.usage?.resetCredits {
            let chinese = locale.identifier.hasPrefix("zh")
            resetCreditsText = chinese ? "重置卡 \(max(0, inventory.availableCount)) 张" : "Reset credits: \(max(0, inventory.availableCount))"
        } else {
            resetCreditsText = account.provider == .codex
                ? (locale.identifier.hasPrefix("zh") ? "重置卡 · 尚未读取，请刷新" : "Reset credits · refresh to load") : nil
        }
        let credits = Self.creditsPresentation(for: account, locale: locale)
        creditsText = credits.displayText
        creditsRawText = credits.rawText

        if account.provider == .antigravity {
            let antigravityQuota = Self.antigravityQuotaPresentation(
                usage: account.usage,
                locale: locale,
                usageProgressDisplayMode: usageProgressDisplayMode,
                quotaVisibility: quotaVisibility,
                showStale: !isRefreshing
            )
            quotaWindows = []
            quotaFamilies = antigravityQuota.families
            quotaStatusText = antigravityQuota.statusText
            isQuotaDisplayHidden = antigravityQuota.isHidden
            provenanceText = nil

            let representativeWindows = antigravityQuota.families.flatMap(\.windows)
            fiveHourWindow = representativeWindows.first ?? Self.unknownWindow(
                id: "antigravity-quota-primary",
                title: L10n.tr("accounts.quota.unavailable"),
                locale: locale
            )
            oneWeekWindow = representativeWindows.dropFirst().first ?? Self.unknownWindow(
                id: "antigravity-quota-secondary",
                title: L10n.tr("accounts.quota.unavailable"),
                locale: locale
            )
            availableCompactItems = antigravityQuota.compactItems
            compactUsage = AccountCompactUsagePresentation(
                fiveHourDisplayPercent: antigravityQuota.compactItems.first?.displayPercent,
                oneWeekDisplayPercent: antigravityQuota.compactItems.dropFirst().first?.displayPercent,
                items: CompactRingPreferences.automaticItems(antigravityQuota.compactItems)
            )
            return
        }

        let codexQuota = Self.codexQuotaPresentation(
            usage: account.usage,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode,
            quotaVisibility: quotaVisibility,
            showStale: !isRefreshing
        )
        quotaWindows = codexQuota.standardWindows
        quotaFamilies = codexQuota.additionalFamilies
        quotaStatusText = codexQuota.statusText
        isQuotaDisplayHidden = codexQuota.isHidden
        provenanceText = account.usage.flatMap {
            Self.provenanceText(for: $0, locale: locale, showStale: !isRefreshing)
        }
        fiveHourWindow = codexQuota.fiveHourWindow
        oneWeekWindow = codexQuota.oneWeekWindow
        compactUsage = codexQuota.compactUsage
        availableCompactItems = codexQuota.availableCompactItems
    }

    private struct AntigravityQuotaResult {
        let families: [AccountQuotaFamilyPresentation]
        let compactItems: [AccountCompactQuotaPresentation]
        let statusText: String?
        let isHidden: Bool
    }

    private static func antigravityQuotaPresentation(
        usage: UsageSnapshot?,
        locale: Locale,
        usageProgressDisplayMode: UsageProgressDisplayMode,
        quotaVisibility: UsageQuotaVisibilityPreferences,
        showStale: Bool = true
    ) -> AntigravityQuotaResult {
        guard let usage else {
            return AntigravityQuotaResult(
                families: [],
                compactItems: [],
                statusText: L10n.tr("accounts.quota.unavailable"),
                isHidden: false
            )
        }

        // Model discovery is not quota evidence. Likewise, a native result for
        // a different account must not be presented as this card's capacity.
        guard usage.hasAuthoritativeQuota, usage.sourceAccountMatched != false else {
            return AntigravityQuotaResult(
                families: [],
                compactItems: [],
                statusText: unavailableStatus(for: usage, locale: locale, showStale: showStale),
                isHidden: false
            )
        }

        let knownPairs = (usage.quotaFamilies ?? []).flatMap { family in
            family.buckets.compactMap { bucket -> (UsageQuotaFamily, UsageQuotaBucket)? in
                guard bucket.isUsageKnown,
                      validUsedPercent(bucket.usedPercent) != nil else {
                    return nil
                }
                return (family, bucket)
            }
        }
        let families = (usage.quotaFamilies ?? []).compactMap { family -> AccountQuotaFamilyPresentation? in
            let windows = family.buckets.compactMap { bucket -> AccountWindowPresentation? in
                guard bucket.isUsageKnown,
                      let usedPercent = validUsedPercent(bucket.usedPercent),
                      quotaVisibility.isVisible(
                        UsageQuotaVisibilityKey.antigravity(
                            familyID: family.id,
                            bucketID: bucket.id
                        )
                      ) else {
                    return nil
                }
                return windowPresentation(
                    id: "\(family.id)-\(bucket.id)",
                    title: UsageQuotaDisplayName.bucket(bucket),
                    usedPercent: usedPercent,
                    resetAt: bucket.resetAt,
                    countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                        windowSeconds: bucket.windowSeconds,
                        identifier: "\(bucket.id) \(bucket.displayName)"
                    ),
                    countdownStartedAt: bucket.countdownStartedAt,
                    locale: locale,
                    usageProgressDisplayMode: usageProgressDisplayMode,
                    unknownFallbackUsedPercent: nil
                )
            }
            guard !windows.isEmpty else { return nil }
            return AccountQuotaFamilyPresentation(
                id: family.id,
                title: UsageQuotaDisplayName.family(family),
                windows: windows
            )
        }

        guard !families.isEmpty else {
            let allKnownWereHidden = !knownPairs.isEmpty
            return AntigravityQuotaResult(
                families: [],
                compactItems: [],
                statusText: allKnownWereHidden
                    ? L10n.tr("accounts.quota.hidden")
                    : unavailableStatus(for: usage, locale: locale, showStale: showStale),
                isHidden: allKnownWereHidden
            )
        }

        let compactItems = knownPairs
            .filter { family, bucket in
                quotaVisibility.isVisible(
                    UsageQuotaVisibilityKey.antigravity(
                        familyID: family.id,
                        bucketID: bucket.id
                    )
                )
            }
            .sorted { left, right in
                if left.0.id != right.0.id {
                    let lhsGemini = left.0.id.lowercased().contains("gemini")
                    let rhsGemini = right.0.id.lowercased().contains("gemini")
                    if lhsGemini != rhsGemini { return lhsGemini }
                    return left.0.id < right.0.id
                }
                if left.1.cadenceRank != right.1.cadenceRank {
                    return left.1.cadenceRank < right.1.cadenceRank
                }
                return left.1.id.localizedCaseInsensitiveCompare(right.1.id) == .orderedAscending
            }
            .map { family, bucket in
                AccountCompactQuotaPresentation(
                    id: UsageQuotaVisibilityKey.antigravity(familyID: family.id, bucketID: bucket.id),
                    subtitle: "\(UsageQuotaDisplayName.family(family))\n\(UsageQuotaDisplayName.bucket(bucket))",
                    displayPercent: compactDisplayPercent(
                        bucket.usedPercent,
                        usageProgressDisplayMode: usageProgressDisplayMode
                    )
                )
            }

        return AntigravityQuotaResult(
            families: families,
            compactItems: compactItems,
            statusText: statusText(forVerifiedUsage: usage, locale: locale, showStale: showStale),
            isHidden: false
        )
    }

    private struct CodexQuotaResult {
        let availableCompactItems: [AccountCompactQuotaPresentation]
        let standardWindows: [AccountWindowPresentation]
        let additionalFamilies: [AccountQuotaFamilyPresentation]
        let fiveHourWindow: AccountWindowPresentation
        let oneWeekWindow: AccountWindowPresentation
        let compactUsage: AccountCompactUsagePresentation
        let statusText: String?
        let isHidden: Bool
    }

    private static func codexQuotaPresentation(
        usage: UsageSnapshot?,
        locale: Locale,
        usageProgressDisplayMode: UsageProgressDisplayMode,
        quotaVisibility: UsageQuotaVisibilityPreferences,
        showStale: Bool = true
    ) -> CodexQuotaResult {
        let fiveHourWindow = windowPresentation(
            id: UsageQuotaVisibilityKey.codexFiveHour,
            title: L10n.tr("accounts.window.five_hour"),
            usedPercent: usage?.fiveHour?.usedPercent,
            resetAt: usage?.fiveHour?.resetAt,
            countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                windowSeconds: usage?.fiveHour?.windowSeconds,
                identifier: "fiveHour"
            ),
            countdownStartedAt: usage?.fiveHour?.countdownStartedAt,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode,
            unknownFallbackUsedPercent: nil
        )
        let oneWeekWindow = windowPresentation(
            id: UsageQuotaVisibilityKey.codexOneWeek,
            title: L10n.tr("accounts.window.one_week"),
            usedPercent: usage?.oneWeek?.usedPercent,
            resetAt: usage?.oneWeek?.resetAt,
            countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                windowSeconds: usage?.oneWeek?.windowSeconds,
                identifier: "oneWeek"
            ),
            countdownStartedAt: usage?.oneWeek?.countdownStartedAt,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode,
            unknownFallbackUsedPercent: nil
        )

        let standardCandidates = [
            (UsageQuotaVisibilityKey.codexFiveHour, fiveHourWindow),
            (UsageQuotaVisibilityKey.codexOneWeek, oneWeekWindow)
        ].filter { $0.1.isUsageKnown }
        let visibleStandardWindows = standardCandidates
            .filter { quotaVisibility.isVisible($0.0) }
            .map(\.1)

        let knownAdditionalPairs = (usage?.codexQuotaFamilies ?? []).flatMap { family in
            family.buckets.compactMap { bucket -> (UsageQuotaFamily, UsageQuotaBucket)? in
                guard bucket.isUsageKnown,
                      validUsedPercent(bucket.usedPercent) != nil else {
                    return nil
                }
                return (family, bucket)
            }
        }
        let additionalFamilies = (usage?.codexQuotaFamilies ?? []).compactMap { family -> AccountQuotaFamilyPresentation? in
            let windows = family.buckets.compactMap { bucket -> AccountWindowPresentation? in
                guard bucket.isUsageKnown,
                      let usedPercent = validUsedPercent(bucket.usedPercent),
                      quotaVisibility.isVisible(
                        UsageQuotaVisibilityKey.codexAdditional(
                            familyID: family.id,
                            bucketID: bucket.id
                        )
                      ) else {
                    return nil
                }
                return windowPresentation(
                    id: UsageQuotaVisibilityKey.codexAdditional(
                        familyID: family.id,
                        bucketID: bucket.id
                    ),
                    title: UsageQuotaDisplayName.bucket(bucket),
                    usedPercent: usedPercent,
                    resetAt: bucket.resetAt,
                    countdownRequiresRequest: QuotaCountdownState.requiresRequestEvidence(
                        windowSeconds: bucket.windowSeconds,
                        identifier: "\(bucket.id) \(bucket.displayName)"
                    ),
                    countdownStartedAt: bucket.countdownStartedAt,
                    locale: locale,
                    usageProgressDisplayMode: usageProgressDisplayMode,
                    unknownFallbackUsedPercent: nil
                )
            }
            guard !windows.isEmpty else { return nil }
            return AccountQuotaFamilyPresentation(
                id: "codex-\(family.id)",
                title: UsageQuotaDisplayName.family(family),
                windows: windows
            )
        }

        let visibleAdditionalItems = knownAdditionalPairs
            .filter { family, bucket in
                quotaVisibility.isVisible(
                    UsageQuotaVisibilityKey.codexAdditional(
                        familyID: family.id,
                        bucketID: bucket.id
                    )
                )
            }
            .map { family, bucket in
                AccountCompactQuotaPresentation(
                    id: UsageQuotaVisibilityKey.codexAdditional(
                        familyID: family.id,
                        bucketID: bucket.id
                    ),
                    subtitle: "\(UsageQuotaDisplayName.family(family)) · \(UsageQuotaDisplayName.bucket(bucket))",
                    displayPercent: compactDisplayPercent(
                        bucket.usedPercent,
                        usageProgressDisplayMode: usageProgressDisplayMode
                    )
                )
            }

        let standardCompactItems = standardCandidates
            .filter { quotaVisibility.isVisible($0.0) }
            .map { key, window in
                AccountCompactQuotaPresentation(
                    id: key,
                    subtitle: window.title,
                    displayPercent: window.progressPercent
                )
            }
        let compactItems = Array((standardCompactItems + visibleAdditionalItems).prefix(2))
        let hasKnownQuota = !standardCandidates.isEmpty || !knownAdditionalPairs.isEmpty
        let hasVisibleQuota = !visibleStandardWindows.isEmpty || !additionalFamilies.isEmpty
        let isHidden = hasKnownQuota && !hasVisibleQuota
        let statusText: String? = isHidden
            ? L10n.tr("accounts.quota.hidden")
            : (hasKnownQuota ? nil : L10n.tr("accounts.quota.unavailable"))

        return CodexQuotaResult(
            availableCompactItems: standardCompactItems + visibleAdditionalItems,
            standardWindows: visibleStandardWindows,
            additionalFamilies: additionalFamilies,
            fiveHourWindow: fiveHourWindow,
            oneWeekWindow: oneWeekWindow,
            compactUsage: AccountCompactUsagePresentation(
                fiveHourDisplayPercent: standardCandidates.first(where: {
                    $0.0 == UsageQuotaVisibilityKey.codexFiveHour
                        && quotaVisibility.isVisible($0.0)
                })?.1.progressPercent,
                oneWeekDisplayPercent: standardCandidates.first(where: {
                    $0.0 == UsageQuotaVisibilityKey.codexOneWeek
                        && quotaVisibility.isVisible($0.0)
                })?.1.progressPercent,
                items: compactItems
            ),
            statusText: statusText,
            isHidden: isHidden
        )
    }

    private static func accent(for planLabel: String) -> AccountCardAccent {
        switch planLabel {
        case "PRO", "PRO 20X", "PRO 5X", "GEMINI PRO", "ULTRA":
            .orange
        case "PLUS":
            .pink
        case "FREE":
            .gray
        case "ENTERPRISE", "BUSINESS":
            .indigo
        default:
            .teal
        }
    }

    private static func displayName(for account: AccountSummary, isCollapsed: Bool) -> String {
        AccountDisplayNameFormatter.format(
            account: account,
            style: isCollapsed ? .localPart : .full
        )
    }

    private struct CreditsPresentation {
        let displayText: String?
        let rawText: String?
    }

    private static func creditsPresentation(
        for account: AccountSummary,
        locale: Locale
    ) -> CreditsPresentation {
        // AntiGravity's quota summary has no Codex-style credit balance. Do
        // not render the inherited "Credits: --" placeholder on those cards.
        if account.provider == .antigravity,
           (account.usage?.credits == nil || account.usage?.credits?.hasCredits != true) {
            return CreditsPresentation(displayText: nil, rawText: nil)
        }
        guard let credits = account.usage?.credits else {
            return CreditsPresentation(displayText: "--", rawText: nil)
        }
        if credits.unlimited {
            return CreditsPresentation(
                displayText: L10n.tr("accounts.card.unlimited"),
                rawText: nil
            )
        }
        guard let rawBalance = credits.balance?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawBalance.isEmpty
        else {
            return CreditsPresentation(displayText: "--", rawText: nil)
        }
        return CreditsPresentation(
            displayText: formattedCreditsBalance(rawBalance, locale: locale),
            rawText: rawBalance
        )
    }

    private static func formattedCreditsBalance(_ rawBalance: String, locale: Locale) -> String {
        // Credit balance is an API-provided unit, not a currency amount. Limit
        // the on-card precision for legibility, but retain `rawBalance` above
        // for VoiceOver and the Copy action.
        guard let decimal = Decimal(
            string: rawBalance,
            locale: Locale(identifier: "en_US_POSIX")
        ) else {
            return rawBalance
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: decimal)) ?? rawBalance
    }

    private static func windowPresentation(
        id: String,
        title: String,
        usedPercent: Double?,
        resetAt: Int64?,
        countdownRequiresRequest: Bool,
        countdownStartedAt: Int64?,
        locale: Locale,
        usageProgressDisplayMode: UsageProgressDisplayMode,
        unknownFallbackUsedPercent: Double?
    ) -> AccountWindowPresentation {
        guard let used = validUsedPercent(usedPercent) ?? unknownFallbackUsedPercent else {
            return unknownWindow(id: id, title: title, locale: locale)
        }

        let roundedUsed = roundedPercent(used)
        let remaining = max(0, 100 - roundedUsed)
        let progress = usageProgressDisplayMode == .remaining ? remaining : roundedUsed
        let primaryText = usageProgressDisplayMode == .remaining
            ? L10n.tr("accounts.window.remaining_format", percent(remaining))
            : L10n.tr("accounts.window.used_format", percent(roundedUsed))
        let secondaryText = usageProgressDisplayMode == .remaining
            ? L10n.tr("accounts.window.used_format", percent(roundedUsed))
            : L10n.tr("accounts.window.remaining_format", percent(remaining))
        let effectiveResetAt = QuotaCountdownState.effectiveResetAt(
            resetAt: resetAt,
            countdownStartedAt: countdownStartedAt,
            now: Int64(Date().timeIntervalSince1970),
            requiresRequestEvidence: countdownRequiresRequest
        )
        return AccountWindowPresentation(
            id: id,
            title: title,
            progressPercent: progress,
            primaryText: primaryText,
            secondaryText: secondaryText,
            resetText: formatResetCountdown(
                resetAt,
                countdownStartedAt: countdownStartedAt,
                requiresRequestEvidence: countdownRequiresRequest
            ),
            isUsageKnown: validUsedPercent(usedPercent) != nil || unknownFallbackUsedPercent != nil,
            resetAt: effectiveResetAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    private static func unknownWindow(
        id: String,
        title: String,
        locale: Locale
    ) -> AccountWindowPresentation {
        _ = locale
        return AccountWindowPresentation(
            id: id,
            title: title,
            progressPercent: 0,
            primaryText: "--",
            secondaryText: L10n.tr("accounts.quota.unknown"),
            resetText: L10n.tr("accounts.window.reset_at_format", "--"),
            isUsageKnown: false
        )
    }

    private static func compactDisplayPercent(
        _ usedPercent: Double?,
        usageProgressDisplayMode: UsageProgressDisplayMode
    ) -> Double? {
        guard let usedPercent = validUsedPercent(usedPercent) else { return nil }
        return usageProgressDisplayMode == .remaining ? max(0, 100 - usedPercent) : usedPercent
    }

    private static func validUsedPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }

    private static func roundedPercent(_ value: Double) -> Double {
        Double(Int(value.rounded()))
    }

    private static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// Reset moments read better as a live countdown ("Resets in 4 hours")
    /// than as an absolute timestamp the user has to mentally diff.
    /// The formatter follows the in-app language (not the system locale) so
    /// countdown words and the surrounding template can never mix languages.
    private static func formatResetCountdown(
        _ epoch: Int64?,
        countdownStartedAt: Int64?,
        requiresRequestEvidence: Bool
    ) -> String {
        guard let epoch else { return L10n.tr("accounts.window.reset_at_format", "--") }
        guard !requiresRequestEvidence || countdownStartedAt != nil else {
            return L10n.tr("accounts.window.awaiting_first_request")
        }
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        if date <= Date() {
            return L10n.tr("accounts.window.reset_imminent")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.currentLocale
        formatter.unitsStyle = .full
        return L10n.tr(
            "accounts.window.reset_in_format",
            formatter.localizedString(for: date, relativeTo: Date())
        )
    }

    private static func unavailableStatus(for usage: UsageSnapshot, locale: Locale, showStale: Bool = true) -> String {
        // A legacy availability-only snapshot must never expose internal
        // implementation wording such as model availability/account status.
        // New r3 code does not create these snapshots, but old stores remain
        // readable with the same concise, user-facing result.
        let isAvailabilityOnly = usage.source == .antigravityRemoteAvailability
        var parts = isAvailabilityOnly
            ? [L10n.tr("accounts.quota.unavailable")]
            : [sourceDescription(usage.source), L10n.tr("accounts.quota.unavailable")]
        if usage.sourceAccountMatched == false && !isAvailabilityOnly {
            parts.append(L10n.tr("accounts.quota.account_unverified"))
        }
        if showStale, usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
            parts.append(L10n.tr("accounts.quota.stale"))
        }
        if usage.fetchedAt > 0 {
            parts.append(lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private static func statusText(forVerifiedUsage usage: UsageSnapshot, locale: Locale, showStale: Bool = true) -> String? {
        var parts = [sourceDescription(usage.source)]
        if showStale, usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
            parts.append(L10n.tr("accounts.quota.stale"))
        }
        if usage.fetchedAt > 0 {
            parts.append(lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func provenanceText(for usage: UsageSnapshot, locale: Locale, showStale: Bool = true) -> String? {
        var parts: [String] = []
        if usage.source != nil {
            parts.append(sourceDescription(usage.source))
        }
        if showStale, usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
            parts.append(L10n.tr("accounts.quota.stale"))
        }
        if usage.fetchedAt > 0 {
            parts.append(lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func sourceDescription(_ source: UsageSnapshotSource?) -> String {
        switch source {
        case .antigravityNativeSummary:
            L10n.tr("accounts.quota.source.antigravity_native")
        case .antigravityAgySummary:
            L10n.tr("accounts.quota.source.antigravity_agy")
        case .antigravityRemoteQuota:
            L10n.tr("accounts.quota.source.antigravity_remote")
        case .antigravityRemoteAvailability:
            L10n.tr("accounts.quota.source.model_availability")
        case .codexRemote:
            L10n.tr("accounts.quota.source.codex_remote")
        case .unknown, .none:
            L10n.tr("accounts.quota.source.unknown")
        }
    }

    private static func lastUpdatedText(_ epoch: Int64, locale: Locale) -> String {
        // "Updated 3 minutes ago" answers the real question (can I trust
        // this number?) faster than an absolute date + time pair.
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = L10n.currentLocale
        formatter.unitsStyle = .full
        return L10n.tr(
            "accounts.quota.last_updated_format",
            formatter.localizedString(
                for: min(Date(timeIntervalSince1970: TimeInterval(epoch)), Date()),
                relativeTo: Date()
            )
        )
    }
}

/// Display-only preferences. Stable quota IDs survive refreshes and account
/// switches; unknown selections retain their label and never borrow another pool.
struct CompactQuotaChoice: Codable, Equatable {
    let id: String
    let title: String
    init(id: String, title: String) { self.id = id; self.title = title }
    init(_ item: AccountCompactQuotaPresentation) { id = item.id; title = item.subtitle }
}

struct CompactRingPreferences: Codable, Equatable {
    static func automaticItems(_ items: [AccountCompactQuotaPresentation]) -> [AccountCompactQuotaPresentation] {
        var families = Set<String>()
        let representatives = items.filter { families.insert(String($0.id.split(separator: ".").prefix(2).joined(separator: "."))).inserted }
        return Array((representatives + items.filter { item in !representatives.contains { $0.id == item.id } }).prefix(2))
    }

    static let defaultsKey = "ass.compactRingChoices.v1"
    var selections: [String: [CompactQuotaChoice?]] = [:]

    static func decode(_ raw: String) -> Self {
        (try? JSONDecoder().decode(Self.self, from: Data(raw.utf8))) ?? Self()
    }
    var encoded: String {
        guard let data = try? JSONEncoder().encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
    static func scope(provider: AccountProvider, accountID: String? = nil) -> String {
        provider.rawValue + (accountID.map { "/account/" + $0 } ?? "/default")
    }
    func choices(provider: AccountProvider, accountID: String?) -> [CompactQuotaChoice?]? {
        if let accountID, let specific = selections[Self.scope(provider: provider, accountID: accountID)] {
            return specific
        }
        return selections[Self.scope(provider: provider)]
    }
    mutating func set(_ choice: CompactQuotaChoice?, at slot: Int, scope: String, fallback: [CompactQuotaChoice?]) {
        guard (0...1).contains(slot) else { return }
        var slots = Array((selections[scope] ?? fallback).prefix(2))
        while slots.count < 2 { slots.append(nil) }
        let old = slots[slot]
        let other = 1 - slot
        if let choice, slots[other]?.id == choice.id { slots[other] = old }
        slots[slot] = choice
        selections[scope] = slots
    }
    func items(for presentation: AccountCardPresentation) -> [AccountCompactQuotaPresentation] {
        guard let choices = choices(provider: presentation.provider, accountID: presentation.accountID) else {
            return presentation.compactUsage.items
        }
        var seen = Set<String>()
        return choices.prefix(2).compactMap { choice in
            guard let choice, !presentation.hiddenQuotaKeys.contains(choice.id), seen.insert(choice.id).inserted else { return nil }
            return presentation.availableCompactItems.first { $0.id == choice.id }
                ?? AccountCompactQuotaPresentation(id: choice.id, subtitle: choice.title, displayPercent: nil)
        }
    }
}

enum ResetCreditTimeDisplay: String, CaseIterable {
    case remaining, expiry
    static let defaultsKey = "ass.resetCreditTimeDisplay"
    var title: String {
        switch self {
        case .remaining: return L10n.tr("settings.reset_credits.remaining")
        case .expiry: return L10n.tr("settings.reset_credits.expiry")
        }
    }
}

struct ResetCreditRow: Identifiable, Equatable {
    let id: Int
    let title: String
    let timeText: String
}

enum CountdownUnits: String, CaseIterable {
    case abbreviated, chinese
    static let defaultsKey = "ass.countdownUnits"
}

enum AccountCountdown {
    /// Ceil preserves a positive final second; zero never implies refreshed quota.
    static func duration(until date: Date, now: Date, units: CountdownUnits) -> String {
        let total = max(0, Int(ceil(date.timeIntervalSince(now))))
        let d = total / 86_400, h = total / 3_600 % 24, m = total / 60 % 60, s = total % 60
        if units == .chinese { return "\(d) 天 \(h) 小时 \(m) 分 \(s) 秒" }
        return "\(d)d \(h)h \(m)m \(s)s"
    }
}

enum ResetCreditPresentation {
    static func rows(_ inventory: ResetCreditInventory, mode: ResetCreditTimeDisplay, now: Date,
                     locale: Locale, units: CountdownUnits = .chinese) -> [ResetCreditRow] {
        let chinese = locale.identifier.hasPrefix("zh")
        let dates = inventory.expiresAt.sorted()
        return (0..<max(0, inventory.availableCount)).map { index in
            let title = chinese ? "重置卡 \(index + 1)" : "Reset \(index + 1)"
            guard dates.indices.contains(index) else {
                return ResetCreditRow(id: index, title: title, timeText: chinese ? "到期时间未知" : "Expiry unknown")
            }
            let date = dates[index]
            let text: String
            if mode == .expiry {
                text = date.formatted(.dateTime.month().day().hour().minute().second().locale(locale))
            } else if date <= now {
                text = chinese ? "已到期" : "Expired"
            } else {
                let duration = AccountCountdown.duration(until: date, now: now, units: units)
                text = units == .chinese ? duration + " 后到期" : duration
            }
            return ResetCreditRow(id: index, title: title, timeText: text)
        }
    }
}

struct AccountOrderPreferences: Codable, Equatable {
    static let defaultsKey = "ass.accountOrder.v1"
    var orders: [String: [String]] = [:]
    static func decode(_ value: String) -> Self {
        (try? JSONDecoder().decode(Self.self, from: Data(value.utf8))) ?? Self()
    }
    var encoded: String { (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}" }
    func ordered(_ available: [String], provider: AccountProvider) -> [String] {
        Self.reconcile(orders[provider.rawValue] ?? [], available: available)
    }
    static func reconcile(_ saved: [String], available: [String]) -> [String] {
        let allowed = Set(available)
        var seen = Set<String>()
        return (saved + available).filter { allowed.contains($0) && seen.insert($0).inserted }
    }
    static func moving(_ id: String, to target: String, in order: [String]) -> [String] {
        guard id != target, let from = order.firstIndex(of: id), let to = order.firstIndex(of: target) else { return order }
        var result = order
        result.remove(at: from); result.insert(id, at: to)
        return result
    }
}

enum AccountCollectionLayout {
    static func columns(provider: AccountProvider, compact: Bool, availableWidth: CGFloat) -> Int {
        let desired = compact && provider != .codex ? 3 : 2
        let minimum: CGFloat = compact && provider != .codex ? 145 : 230
        return max(1, min(desired, Int((max(0, availableWidth) + 12) / (minimum + 12))))
    }
}
