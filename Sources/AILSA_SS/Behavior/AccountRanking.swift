import Foundation

enum AccountRanking {
    private static let autoSwitchUsedThreshold = 100.0

    static func remainingScore(for account: AccountSummary, now: Int64? = nil) -> Double {
        if account.provider == .antigravity {
            return antigravityRemainingScore(for: account, now: now)
        }
        let oneWeek = account.usage?.oneWeek.map {
            windowScore(usedPercent: $0.usedPercent, windowSeconds: $0.windowSeconds, resetAt: $0.resetAt, now: now)
        } ?? 0
        let fiveHour = account.usage?.fiveHour.map {
            windowScore(usedPercent: $0.usedPercent, windowSeconds: $0.windowSeconds, resetAt: $0.resetAt, now: now)
        } ?? 0
        return oneWeek * 0.7 + fiveHour * 0.3
    }

    static func sortByRemaining(_ accounts: [AccountSummary]) -> [AccountSummary] {
        accounts.sorted { left, right in
            let leftScore = remainingScore(for: left)
            let rightScore = remainingScore(for: right)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
        }
    }

    static func sortForDisplay(_ accounts: [AccountSummary]) -> [AccountSummary] {
        accounts.sorted { left, right in
            if left.isCurrent != right.isCurrent {
                return left.isCurrent
            }
            let leftScore = remainingScore(for: left)
            let rightScore = remainingScore(for: right)
            if leftScore != rightScore {
                return leftScore > rightScore
            }
            if left.addedAt != right.addedAt {
                return left.addedAt < right.addedAt
            }
            return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
        }
    }

    static func pickBestAccount(_ accounts: [AccountSummary]) -> AccountSummary? {
        sortByRemaining(accounts).first
    }

    static func isQuotaExhausted(_ account: AccountSummary, now: Int64? = nil) -> Bool {
        if account.provider == .antigravity {
            // Gemini and Claude/GPT are independent native pools. Exhaustion
            // of either is actionable; waiting until *all* pools are empty
            // strands a caller whose active pool has already been blocked.
            let familyScores = antigravityFamilyRemainingScoresByID(for: account, now: now)
            return familyScores.values.contains { $0 <= 0 }
        }
        return isWindowExhausted(account.usage?.fiveHour, now: now)
            || isWindowExhausted(account.usage?.oneWeek, now: now)
    }

    static func pickAutoSwitchTarget(
        _ accounts: [AccountSummary],
        now: Int64? = nil
    ) -> AccountSummary? {
        guard let current = accounts.first(where: \.isCurrent),
              isEligibleForAutoSwitch(current, now: now),
              isQuotaExhausted(current, now: now)
        else {
            return nil
        }

        let alternatives = accounts.filter {
            $0.id != current.id
                && isEligibleForAutoSwitch($0, now: now)
                && hasUsableQuotaForAutomaticSwitch($0, now: now)
        }
        guard current.provider == .antigravity else {
            guard let bestAlternative = alternatives.max(by: {
                remainingScore(for: $0, now: now) < remainingScore(for: $1, now: now)
            }),
                  remainingScore(for: bestAlternative, now: now) > remainingScore(for: current, now: now)
            else { return nil }
            return bestAlternative
        }

        let exhaustedFamilies = antigravityFamilyRemainingScoresByID(for: current, now: now)
            .filter { $0.value <= 0 }
        guard !exhaustedFamilies.isEmpty else {
            return nil
        }
        let candidates = alternatives.filter {
            isImprovedAntigravityAutoTarget(
                $0,
                current: current,
                exhaustedFamilies: exhaustedFamilies
            )
        }
        return candidates.sorted {
            let leftWorstRecoveredPool = recoveredPoolScore(
                for: $0,
                exhaustedFamilies: exhaustedFamilies
            )
            let rightWorstRecoveredPool = recoveredPoolScore(
                for: $1,
                exhaustedFamilies: exhaustedFamilies
            )
            if leftWorstRecoveredPool != rightWorstRecoveredPool {
                return leftWorstRecoveredPool > rightWorstRecoveredPool
            }
            let leftScore = remainingScore(for: $0, now: now)
            let rightScore = remainingScore(for: $1, now: now)
            if leftScore != rightScore { return leftScore > rightScore }
            return $0.id.localizedCaseInsensitiveCompare($1.id) == .orderedAscending
        }.first
    }

    /// Errors and stale/unknown provider snapshots do not participate in an
    /// automatic decision. Passing nil preserves deterministic unit-test use.
    static func isEligibleForAutoSwitch(_ account: AccountSummary, now: Int64? = nil) -> Bool {
        guard let usage = account.usage, account.usageError == nil else { return false }
        if let now, usage.isStale(now: now) {
            return false
        }
        if account.provider == .antigravity {
            // Automatic native switching is safe only for a complete local,
            // identity-matched quota summary. Unknown/disabled buckets stay
            // visible to the user but cannot drive background side effects.
            return usage.isVerifiedForSwitch
        }
        // A missing half of the standard quota response is not evidence that
        // an account is safe for a background switch.
        return usage.fiveHour != nil && usage.oneWeek != nil
    }

    /// An automatic OpenCode/native switch is allowed only with usable quota
    /// in every known 5-hour/7-day window. A reset that has already passed is
    /// treated as available even if the provider has not cleared the old
    /// percentage yet; an unknown reset never overrides an exhausted window.
    static func hasUsableQuotaForAutomaticSwitch(_ account: AccountSummary, now: Int64? = nil) -> Bool {
        guard let usage = account.usage, account.usageError == nil else { return false }
        if account.provider == .antigravity {
            let buckets = usage.quotaBuckets.filter { $0.isUsageKnown && $0.usedPercent?.isFinite == true }
            guard !buckets.isEmpty else { return false }
            return buckets.allSatisfy { bucket in
                guard let used = bucket.usedPercent else { return false }
                guard used >= autoSwitchUsedThreshold else { return true }
                guard let resetAt = bucket.resetAt, let now else { return false }
                return resetAt <= now
            }
        }
        guard let fiveHour = usage.fiveHour, let oneWeek = usage.oneWeek else { return false }
        return !isWindowExhausted(fiveHour, now: now) && !isWindowExhausted(oneWeek, now: now)
    }

    private static func isWindowExhausted(_ window: UsageWindow?, now: Int64? = nil) -> Bool {
        guard let window else { return false }
        guard window.usedPercent >= autoSwitchUsedThreshold else { return false }
        guard let now, let resetAt = window.resetAt else { return true }
        return resetAt > now
    }

    private static func antigravityRemainingScore(for account: AccountSummary, now: Int64? = nil) -> Double {
        let familyScores = antigravityFamilyRemainingScoresByID(for: account, now: now).values
        guard !familyScores.isEmpty else { return -1 }
        // Use the most constrained pool, not an average. A full Claude/GPT
        // pool must not make a Gemini-exhausted account look healthy, or vice
        // versa.
        return familyScores.min() ?? -1
    }

    /// A named pool is constrained by its least remaining known bucket. This
    /// keeps one fresh family from hiding another exhausted family.
    private static func antigravityFamilyRemainingScoresByID(
        for account: AccountSummary,
        now: Int64? = nil
    ) -> [String: Double] {
        guard let families = account.usage?.quotaFamilies else { return [:] }
        return Dictionary(uniqueKeysWithValues: families.compactMap { family -> (String, Double)? in
            let remaining = family.buckets.compactMap { bucket -> Double? in
                guard bucket.isUsageKnown, let used = bucket.usedPercent, used.isFinite else { return nil }
                return windowScore(
                    usedPercent: used,
                    windowSeconds: bucket.windowSeconds ?? 0,
                    resetAt: bucket.resetAt,
                    now: now
                )
            }
            guard let constrained = remaining.min() else { return nil }
            return (family.id, constrained)
        })
    }

    private static func isImprovedAntigravityAutoTarget(
        _ candidate: AccountSummary,
        current: AccountSummary,
        exhaustedFamilies: [String: Double]
    ) -> Bool {
        let candidateFamilies = antigravityFamilyRemainingScoresByID(for: candidate)
        // Do not replace one known blocked pool with another. This conservative
        // policy is deliberate: native summaries enumerate all pool buckets,
        // so an absent/unknown group is not a safe background choice.
        guard !candidateFamilies.isEmpty,
              candidateFamilies.values.allSatisfy({ $0 > 0 })
        else { return false }
        return exhaustedFamilies.allSatisfy { identifier, currentScore in
            guard let candidateScore = candidateFamilies[identifier] else { return false }
            return candidateScore > currentScore
        }
    }

    private static func recoveredPoolScore(
        for candidate: AccountSummary,
        exhaustedFamilies: [String: Double]
    ) -> Double {
        let families = antigravityFamilyRemainingScoresByID(for: candidate)
        return exhaustedFamilies.keys.compactMap { families[$0] }.min() ?? -1
    }

    private static func windowScore(
        usedPercent: Double,
        windowSeconds: Int64,
        resetAt: Int64?,
        now: Int64?
    ) -> Double {
        let remaining = max(0, min(100, 100 - usedPercent))
        guard let now, let resetAt, windowSeconds > 0 else { return remaining }
        let secondsUntilReset = resetAt - now
        if secondsUntilReset <= 0 { return 100 }
        // Preserve quota headroom as the main signal, while allowing a window
        // that resets imminently to recover part of its score. This prevents a
        // nearly-reset account from being rejected solely because its cached
        // percentage is still high.
        let resetReadiness = max(0, min(1, 1 - Double(secondsUntilReset) / Double(windowSeconds)))
        return remaining + (100 - remaining) * 0.35 * resetReadiness
    }
}
