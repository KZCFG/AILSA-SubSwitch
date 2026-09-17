import Foundation

enum UsageWindowSelector {
    /// A display label such as "5h" must correspond to a real five-hour
    /// window.  `pickNearestWindow` is retained for legacy callers, but should
    /// not be used to invent a standard window when an API only returned (for
    /// example) a seven-day limit.
    static func pickExactWindow(_ windows: [UsageWindowRaw], targetSeconds: Int64) -> UsageWindowRaw? {
        windows.first { $0.limitWindowSeconds == targetSeconds }
    }

    static func pickNearestWindow(_ windows: [UsageWindowRaw], targetSeconds: Int64) -> UsageWindowRaw? {
        windows.min { lhs, rhs in
            abs(lhs.limitWindowSeconds - targetSeconds) < abs(rhs.limitWindowSeconds - targetSeconds)
        }
    }
}
