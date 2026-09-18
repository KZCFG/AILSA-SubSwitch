import Foundation

/// Keeps provider reset timestamps separate from the local moment at which a
/// window was first observed as active. A provider can report the next reset
/// boundary even when no request has been made in the new window; showing a
/// live countdown in that state is misleading.
enum QuotaCountdownState {
    static func reconcile(
        previous: UsageSnapshot?,
        refreshed: UsageSnapshot,
        observedAt: Int64
    ) -> UsageSnapshot {
        var result = refreshed
        result.fiveHour = reconcile(
            previous: previous?.fiveHour,
            refreshed: refreshed.fiveHour,
            observedAt: observedAt
        )
        result.oneWeek = reconcile(
            previous: previous?.oneWeek,
            refreshed: refreshed.oneWeek,
            observedAt: observedAt
        )

        if let families = refreshed.quotaFamilies {
            result.quotaFamilies = reconcile(
                previous: previous?.quotaFamilies,
                refreshed: families,
                observedAt: observedAt
            )
        }
        if let families = refreshed.codexQuotaFamilies {
            result.codexQuotaFamilies = reconcile(
                previous: previous?.codexQuotaFamilies,
                refreshed: families,
                observedAt: observedAt
            )
        }
        return result
    }

    static func effectiveResetAt(
        resetAt: Int64?,
        countdownStartedAt: Int64?,
        now: Int64
    ) -> Int64? {
        guard let resetAt, resetAt > now, countdownStartedAt != nil else { return nil }
        return resetAt
    }

    private static func reconcile(
        previous: UsageWindow?,
        refreshed: UsageWindow?,
        observedAt: Int64
    ) -> UsageWindow? {
        guard var refreshed else { return nil }
        refreshed.countdownStartedAt = startedAt(
            previousStartedAt: previous?.countdownStartedAt,
            previousResetAt: previous?.resetAt,
            refreshedResetAt: refreshed.resetAt,
            refreshedUsedPercent: refreshed.usedPercent,
            observedAt: observedAt
        )
        return refreshed
    }

    private static func reconcile(
        previous: [UsageQuotaFamily]?,
        refreshed: [UsageQuotaFamily],
        observedAt: Int64
    ) -> [UsageQuotaFamily] {
        refreshed.map { family in
            let previousFamily = previous?.first { $0.id == family.id }
            return UsageQuotaFamily(
                id: family.id,
                displayName: family.displayName,
                buckets: family.buckets.map { bucket in
                    let previousBucket = previousFamily?.buckets.first { $0.id == bucket.id }
                    return reconcile(
                        previous: previousBucket,
                        refreshed: bucket,
                        observedAt: observedAt
                    )
                }
            )
        }
    }

    private static func reconcile(
        previous: UsageQuotaBucket?,
        refreshed: UsageQuotaBucket,
        observedAt: Int64
    ) -> UsageQuotaBucket {
        var result = refreshed
        result.countdownStartedAt = startedAt(
            previousStartedAt: previous?.countdownStartedAt,
            previousResetAt: previous?.resetAt,
            refreshedResetAt: refreshed.resetAt,
            refreshedUsedPercent: refreshed.isUsageKnown ? (refreshed.usedPercent ?? 0) : 0,
            observedAt: observedAt
        )
        return result
    }

    private static func startedAt(
        previousStartedAt: Int64?,
        previousResetAt: Int64?,
        refreshedResetAt: Int64?,
        refreshedUsedPercent: Double,
        observedAt: Int64
    ) -> Int64? {
        guard let refreshedResetAt, refreshedResetAt > observedAt,
              refreshedUsedPercent.isFinite, refreshedUsedPercent > 0
        else { return nil }

        // A still-running window keeps the original activation marker, even
        // when the provider returns a slightly different reset timestamp.
        if let previousStartedAt,
           let previousResetAt,
           previousResetAt > observedAt,
           refreshedResetAt > observedAt {
            return previousStartedAt
        }

        // A non-zero usage value is the only provider-reported evidence that a
        // request has happened in a new window. Treat the observation time as
        // a conservative lower bound for the first request.
        if refreshedResetAt > observedAt,
           refreshedUsedPercent.isFinite,
           refreshedUsedPercent > 0 {
            return observedAt
        }

        return nil
    }
}
