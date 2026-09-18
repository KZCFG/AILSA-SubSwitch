import Foundation

/// Keeps provider reset timestamps separate from the local moment at which a
/// model request was observed. A quota read must not mark a request-activated
/// window; fixed provider windows may still count down from their reset time.
enum QuotaCountdownState {
    static let fiveHourWindowSeconds: Int64 = 5 * 60 * 60

    /// A provider's five-hour pool is request-activated. Weekly pools are
    /// fixed provider windows and must count down from their reported reset
    /// time even when no request has been observed locally.
    static func requiresRequestEvidence(windowSeconds: Int64?, identifier: String? = nil) -> Bool {
        if windowSeconds == fiveHourWindowSeconds { return true }
        let normalized = (identifier ?? "").lowercased()
        return normalized.contains("5h")
            || normalized.contains("five_hour")
            || normalized.contains("five hour")
            || normalized.contains("pt5h")
    }

    static func reconcile(previous: UsageSnapshot?, refreshed: UsageSnapshot, observedAt: Int64) -> UsageSnapshot {
        var result = refreshed
        result.fiveHour = reconcile(
            previous: previous?.fiveHour,
            refreshed: refreshed.fiveHour,
            identifier: "fiveHour",
            observedAt: observedAt
        )
        result.oneWeek = reconcile(
            previous: previous?.oneWeek,
            refreshed: refreshed.oneWeek,
            identifier: "oneWeek",
            observedAt: observedAt
        )
        if let families = refreshed.quotaFamilies {
            result.quotaFamilies = reconcile(previous: previous?.quotaFamilies, refreshed: families, observedAt: observedAt)
        }
        if let families = refreshed.codexQuotaFamilies {
            result.codexQuotaFamilies = reconcile(previous: previous?.codexQuotaFamilies, refreshed: families, observedAt: observedAt)
        }
        return result
    }

    /// Future request-aware providers can call this after observing a real
    /// model request. Current read-only quota refreshes intentionally do not.
    static func markRequestObserved(_ snapshot: UsageSnapshot, observedAt: Int64) -> UsageSnapshot {
        var result = snapshot
        result.fiveHour = markRequestObserved(snapshot.fiveHour, identifier: "fiveHour", observedAt: observedAt)
        result.oneWeek = markRequestObserved(snapshot.oneWeek, identifier: "oneWeek", observedAt: observedAt)
        if let families = snapshot.quotaFamilies {
            result.quotaFamilies = families.map { family in
                UsageQuotaFamily(id: family.id, displayName: family.displayName,
                    buckets: family.buckets.map { markRequestObserved($0, observedAt: observedAt) })
            }
        }
        if let families = snapshot.codexQuotaFamilies {
            result.codexQuotaFamilies = families.map { family in
                UsageQuotaFamily(id: family.id, displayName: family.displayName,
                    buckets: family.buckets.map { markRequestObserved($0, observedAt: observedAt) })
            }
        }
        return result
    }

    static func effectiveResetAt(
        resetAt: Int64?,
        countdownStartedAt: Int64?,
        now: Int64,
        requiresRequestEvidence: Bool = true
    ) -> Int64? {
        guard let resetAt, resetAt > now else { return nil }
        guard !requiresRequestEvidence || countdownStartedAt != nil else { return nil }
        return resetAt
    }

    private static func reconcile(
        previous: UsageWindow?,
        refreshed: UsageWindow?,
        identifier: String,
        observedAt: Int64
    ) -> UsageWindow? {
        guard var refreshed else { return nil }
        guard requiresRequestEvidence(windowSeconds: refreshed.windowSeconds, identifier: identifier) else {
            refreshed.countdownStartedAt = nil
            refreshed.countdownStartEvidence = nil
            return refreshed
        }
        let preserve = isVerifiedMarker(startedAt: previous?.countdownStartedAt,
            evidence: previous?.countdownStartEvidence, previousResetAt: previous?.resetAt,
            refreshedResetAt: refreshed.resetAt, observedAt: observedAt)
        refreshed.countdownStartedAt = preserve ? previous?.countdownStartedAt : nil
        refreshed.countdownStartEvidence = preserve ? .requestObserved : nil
        return refreshed
    }

    private static func reconcile(previous: [UsageQuotaFamily]?, refreshed: [UsageQuotaFamily], observedAt: Int64) -> [UsageQuotaFamily] {
        refreshed.map { family in
            let previousFamily = previous?.first { $0.id == family.id }
            return UsageQuotaFamily(id: family.id, displayName: family.displayName,
                buckets: family.buckets.map { bucket in
                    reconcile(
                        previous: previousFamily?.buckets.first { $0.id == bucket.id },
                        refreshed: bucket,
                        observedAt: observedAt
                    )
                })
        }
    }

    private static func reconcile(previous: UsageQuotaBucket?, refreshed: UsageQuotaBucket, observedAt: Int64) -> UsageQuotaBucket {
        var result = refreshed
        let identifier = "\(refreshed.id) \(refreshed.displayName)"
        guard requiresRequestEvidence(windowSeconds: refreshed.windowSeconds, identifier: identifier) else {
            result.countdownStartedAt = nil
            result.countdownStartEvidence = nil
            return result
        }
        let preserve = isVerifiedMarker(startedAt: previous?.countdownStartedAt,
            evidence: previous?.countdownStartEvidence, previousResetAt: previous?.resetAt,
            refreshedResetAt: refreshed.resetAt, observedAt: observedAt)
        result.countdownStartedAt = preserve ? previous?.countdownStartedAt : nil
        result.countdownStartEvidence = preserve ? .requestObserved : nil
        return result
    }

    private static func isVerifiedMarker(startedAt: Int64?, evidence: QuotaCountdownStartEvidence?, previousResetAt: Int64?, refreshedResetAt: Int64?, observedAt: Int64) -> Bool {
        guard startedAt != nil, evidence == .requestObserved,
              let previousResetAt, previousResetAt > observedAt,
              let refreshedResetAt, refreshedResetAt > observedAt,
              previousResetAt == refreshedResetAt else { return false }
        return true
    }

    private static func markRequestObserved(
        _ window: UsageWindow?,
        identifier: String,
        observedAt: Int64
    ) -> UsageWindow? {
        guard var window,
              requiresRequestEvidence(windowSeconds: window.windowSeconds, identifier: identifier),
              let resetAt = window.resetAt,
              resetAt > observedAt else { return window }
        window.countdownStartedAt = observedAt
        window.countdownStartEvidence = .requestObserved
        return window
    }

    private static func markRequestObserved(_ bucket: UsageQuotaBucket, observedAt: Int64) -> UsageQuotaBucket {
        var bucket = bucket
        guard requiresRequestEvidence(
            windowSeconds: bucket.windowSeconds,
            identifier: "\(bucket.id) \(bucket.displayName)"
        ), let resetAt = bucket.resetAt, resetAt > observedAt else { return bucket }
        bucket.countdownStartedAt = observedAt
        bucket.countdownStartEvidence = .requestObserved
        return bucket
    }
}
