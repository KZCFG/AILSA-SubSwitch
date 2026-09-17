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
    let isQuotaDisplayHidden: Bool
    /// True when the usage snapshot behind the status/provenance metadata is
    /// stale, so views can tint that metadata instead of only appending a
    /// text marker.
    let quotaStatusIsStale: Bool
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
        quotaVisibility: UsageQuotaVisibilityPreferences = .defaultValue
    ) {
        let planLabel = account.normalizedPlanLabel
        self.planLabel = planLabel
        usageProgressFillStyle = account.provider == .codex ? .codex : .antigravity
        accent = Self.accent(for: planLabel)
        quotaStatusIsStale = account.usage?.isStale(now: Int64(Date().timeIntervalSince1970)) ?? false
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
            let expiries = inventory.expiresAt.map { $0.formatted(.dateTime.month().day().hour().minute().locale(locale)) }.joined(separator: " · ")
            let chinese = locale.identifier.hasPrefix("zh")
            resetCreditsText = (chinese ? "重置卡 \(inventory.availableCount) 张" : "Reset credits: \(inventory.availableCount)")
                + (expiries.isEmpty ? "" : (chinese ? " · 到期 " : " · Expires ") + expiries)
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
                quotaVisibility: quotaVisibility
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
            compactUsage = AccountCompactUsagePresentation(
                fiveHourDisplayPercent: antigravityQuota.compactItems.first?.displayPercent,
                oneWeekDisplayPercent: antigravityQuota.compactItems.dropFirst().first?.displayPercent,
                items: antigravityQuota.compactItems
            )
            return
        }

        let codexQuota = Self.codexQuotaPresentation(
            usage: account.usage,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode,
            quotaVisibility: quotaVisibility
        )
        quotaWindows = codexQuota.standardWindows
        quotaFamilies = codexQuota.additionalFamilies
        quotaStatusText = codexQuota.statusText
        isQuotaDisplayHidden = codexQuota.isHidden
        provenanceText = account.usage.flatMap {
            Self.provenanceText(for: $0, locale: locale)
        }
        fiveHourWindow = codexQuota.fiveHourWindow
        oneWeekWindow = codexQuota.oneWeekWindow
        compactUsage = codexQuota.compactUsage
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
        quotaVisibility: UsageQuotaVisibilityPreferences
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
                statusText: unavailableStatus(for: usage, locale: locale),
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
                    : unavailableStatus(for: usage, locale: locale),
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
                if left.1.cadenceRank != right.1.cadenceRank {
                    return left.1.cadenceRank < right.1.cadenceRank
                }
                return left.1.id.localizedCaseInsensitiveCompare(right.1.id) == .orderedAscending
            }
            .prefix(2)
            .map { family, bucket in
                AccountCompactQuotaPresentation(
                    id: "\(family.id)-\(bucket.id)",
                    subtitle: UsageQuotaDisplayName.bucket(bucket),
                    displayPercent: compactDisplayPercent(
                        bucket.usedPercent,
                        usageProgressDisplayMode: usageProgressDisplayMode
                    )
                )
            }

        return AntigravityQuotaResult(
            families: families,
            compactItems: compactItems,
            statusText: statusText(forVerifiedUsage: usage, locale: locale),
            isHidden: false
        )
    }

    private struct CodexQuotaResult {
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
        quotaVisibility: UsageQuotaVisibilityPreferences
    ) -> CodexQuotaResult {
        let fiveHourWindow = windowPresentation(
            id: UsageQuotaVisibilityKey.codexFiveHour,
            title: L10n.tr("accounts.window.five_hour"),
            usedPercent: usage?.fiveHour?.usedPercent,
            resetAt: usage?.fiveHour?.resetAt,
            locale: locale,
            usageProgressDisplayMode: usageProgressDisplayMode,
            unknownFallbackUsedPercent: nil
        )
        let oneWeekWindow = windowPresentation(
            id: UsageQuotaVisibilityKey.codexOneWeek,
            title: L10n.tr("accounts.window.one_week"),
            usedPercent: usage?.oneWeek?.usedPercent,
            resetAt: usage?.oneWeek?.resetAt,
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
        return AccountWindowPresentation(
            id: id,
            title: title,
            progressPercent: progress,
            primaryText: primaryText,
            secondaryText: secondaryText,
            resetText: formatResetCountdown(resetAt),
            isUsageKnown: validUsedPercent(usedPercent) != nil || unknownFallbackUsedPercent != nil
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
    private static func formatResetCountdown(_ epoch: Int64?) -> String {
        guard let epoch else { return L10n.tr("accounts.window.reset_at_format", "--") }
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

    private static func unavailableStatus(for usage: UsageSnapshot, locale: Locale) -> String {
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
        if usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
            parts.append(L10n.tr("accounts.quota.stale"))
        }
        if usage.fetchedAt > 0 {
            parts.append(lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private static func statusText(forVerifiedUsage usage: UsageSnapshot, locale: Locale) -> String? {
        var parts = [sourceDescription(usage.source)]
        if usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
            parts.append(L10n.tr("accounts.quota.stale"))
        }
        if usage.fetchedAt > 0 {
            parts.append(lastUpdatedText(usage.fetchedAt, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func provenanceText(for usage: UsageSnapshot, locale: Locale) -> String? {
        var parts: [String] = []
        if usage.source != nil {
            parts.append(sourceDescription(usage.source))
        }
        if usage.isStale(now: Int64(Date().timeIntervalSince1970)) {
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
