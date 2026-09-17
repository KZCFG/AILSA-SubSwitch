import Foundation
import AppKit

extension Notification.Name {
    static let assCursorAccountDidChange = Notification.Name("com.alick.copool.cursor-account-did-change")
}

enum CursorSwitchError: LocalizedError {
    case busy, applicationStillRunning, pendingRecovery, verificationFailed, rollbackFailed
    var errorDescription: String? {
        switch self {
        case .busy: "正在切换 Cursor 账号，请稍候。"
        case .applicationStillRunning: "Cursor 尚未退出；请先保存未完成的工作。未写入账号。"
        case .pendingRecovery: "上次 Cursor 切换未完成，请先恢复原账号。"
        case .verificationFailed: "Cursor 登录身份未通过验证，已恢复原账号。"
        case .rollbackFailed: "Cursor 切换失败，原账号恢复尚未完成。请点击恢复原账号重试。"
        }
    }
}

/// No force quit, no writes while the app is running, and a durable recovery
/// record written before native changes. Verification reads native credentials
/// again and checks their subject against Cursor's authenticated /auth/me.
@MainActor
final class CursorNativeAccountSwitcher {
    static let shared = CursorNativeAccountSwitcher()
    private var busy = false
    private let repo = CursorProfileRepository.shared
    private let bundleID = "com.todesktop.230313mzl4w4u92"
    func switchAccount(id: String) async throws {
        try AppTerminationSafety.shared.beginAccountSwitch()
        defer { AppTerminationSafety.shared.endAccountSwitch() }
        guard !busy else { throw CursorSwitchError.busy }
        busy = true; defer { busy = false }
        guard try await repo.recoveryValues() == nil else { throw CursorSwitchError.pendingRecovery }
        guard let profile = try await repo.profiles().first(where: { $0.id == id }) else { throw CursorUsageError.notLoggedIn }
        let target = try await CursorUsageService.shared.loadAccount(values: profile.values)
        guard target.id == id else { throw CursorUsageError.invalidIdentity }
        let previous = try await repo.readNativeValues()
        try await repo.saveRecovery(previous)
        do { try await stop() } catch { try? await repo.clearRecovery(); throw error }
        do {
            try await repo.replaceNativeValues(profile.values)
            if UserDefaults.standard.object(forKey: "ass.launchCursorAfterSwitch") as? Bool ?? true { try await launch() }
            try await verify(id: id)
            try await repo.clearRecovery()
            await CursorUsageService.shared.invalidateHistory()
            NotificationCenter.default.post(name: .assCursorAccountDidChange, object: nil, userInfo: ["accountID": id])
        } catch {
            do {
                try await stop()
                try await repo.replaceNativeValues(previous)
                try await launch()
                let restored = try await CursorUsageService.shared.loadAccount(values: previous)
                try await verify(id: restored.id)
                try await repo.clearRecovery()
            } catch { throw CursorSwitchError.rollbackFailed }
            throw CursorSwitchError.verificationFailed
        }
    }
    func recover() async throws {
        guard !busy else { throw CursorSwitchError.busy }
        busy = true; defer { busy = false }
        guard let values = try await repo.recoveryValues() else { return }
        let expected = try await CursorUsageService.shared.loadAccount(values: values)
        try await stop()
        try await repo.replaceNativeValues(values)
        try await launch()
        try await verify(id: expected.id)
        try await repo.clearRecovery()
        await CursorUsageService.shared.invalidateHistory()
        NotificationCenter.default.post(name: .assCursorAccountDidChange, object: nil, userInfo: ["accountID": expected.id])
    }
    private func stop() async throws {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in apps { _ = app.terminate() }
        for _ in 0..<100 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CursorSwitchError.applicationStillRunning
    }
    private func launch() async throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { throw CursorUsageError.notLoggedIn }
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    private func verify(id: String) async throws {
        for _ in 0..<6 {
            try await Task.sleep(for: .seconds(1))
            if let account = try? await CursorUsageService.shared.loadAccount(), account.id == id { return }
        }
        throw CursorUsageError.invalidIdentity
    }
}
