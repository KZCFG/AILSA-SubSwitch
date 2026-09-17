import Foundation

/// All mutable state is protected by the lock. Account switching spans awaits;
/// the app must finish those transactions before Quit terminates it.
final class AppTerminationSafety: @unchecked Sendable {
    static let shared = AppTerminationSafety()
    private let lock = NSLock()
    private var active = 0
    private var terminationRequested = false

    func beginAccountSwitch() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !terminationRequested else { throw CancellationError() }
        active += 1
    }

    func endAccountSwitch() {
        lock.lock()
        defer { lock.unlock() }
        precondition(active > 0)
        active -= 1
    }

    /// Stops new switches atomically with deciding whether it is safe to exit.
    func requestTermination() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        terminationRequested = true
        return active == 0
    }

    var hasActiveAccountSwitch: Bool {
        lock.lock()
        defer { lock.unlock() }
        return active > 0
    }
}
