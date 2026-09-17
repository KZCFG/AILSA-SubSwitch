import Foundation

enum AccountRanking {
    private static let autoSwitchUsedThreshold = 100.0

    static func remainingScore(for account: AccountSummary) -> Double {
        if account.provider == .antigravity {
            return antigravityRemainingScore(for: account)
        }
        let oneWeekUsed = account.usage?.oneWeek?.usedPercent ?? 100
        let fiveHourUsed = account.usage?.fiveHour?.usedPercent ?? 100
        let oneWeekRemaining = max(0, 100 - oneWeekUsed)
        let fiveHourRemaining = max(0, 100 - fiveHourUsed)
        return oneWeekRemaining * 0.7 + fiveHourRemaining * 0.3
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

    static func isQuotaExhausted(_ account: AccountSummary) -> Bool {
        if account.provider == .antigravity {
            // Gemini and Claude/GPT are independent native pools. Exhaustion
            // of either is actionable; waiting until *all* pools are empty
            // strands a caller whose active pool has already been blocked.
            let familyScores = antigravityFamilyRemainingScoresByID(for: account)
            return familyScores.values.contains { $0 <= 0 }
        }
        return isWindowExhausted(account.usage?.fiveHour) || isWindowExhausted(account.usage?.oneWeek)
    }

    static func pickAutoSwitchTarget(
        _ accounts: [AccountSummary],
        now: Int64? = nil
    ) -> AccountSummary? {
        guard let current = accounts.first(where: \.isCurrent),
              isEligibleForAutoSwitch(current, now: now),
              isQuotaExhausted(current)
        else {
            return nil
        }

        let alternatives = accounts.filter {
            $0.id != current.id && isEligibleForAutoSwitch($0, now: now)
        }
        guard current.provider == .antigravity else {
            guard let bestAlternative = pickBestAccount(alternatives),
                  remainingScore(for: bestAlternative) > remainingScore(for: current)
            else { return nil }
            return bestAlternative
        }

        let exhaustedFamilies = antigravityFamilyRemainingScoresByID(for: current)
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
            let leftScore = remainingScore(for: $0)
            let rightScore = remainingScore(for: $1)
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
        return usage.fiveHour != nil || usage.oneWeek != nil
    }

    private static func isWindowExhausted(_ window: UsageWindow?) -> Bool {
        guard let window else { return false }
        return window.usedPercent >= autoSwitchUsedThreshold
    }

    private static func antigravityRemainingScore(for account: AccountSummary) -> Double {
        let familyScores = antigravityFamilyRemainingScoresByID(for: account).values
        guard !familyScores.isEmpty else { return -1 }
        // Use the most constrained pool, not an average. A full Claude/GPT
        // pool must not make a Gemini-exhausted account look healthy, or vice
        // versa.
        return familyScores.min() ?? -1
    }

    /// A named pool is constrained by its least remaining known bucket. This
    /// keeps one fresh family from hiding another exhausted family.
    private static func antigravityFamilyRemainingScoresByID(
        for account: AccountSummary
    ) -> [String: Double] {
        guard let families = account.usage?.quotaFamilies else { return [:] }
        return Dictionary(uniqueKeysWithValues: families.compactMap { family -> (String, Double)? in
            let remaining = family.buckets.compactMap { bucket -> Double? in
                guard bucket.isUsageKnown, let used = bucket.usedPercent, used.isFinite else { return nil }
                return max(0, min(100, 100 - used))
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
}
