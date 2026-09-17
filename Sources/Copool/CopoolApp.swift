import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
@MainActor
struct CopoolApp {
    private static var delegate: SubSwitchApplicationDelegate?

    static func main() {
        AntigravityQuietKeychainBridge.runChildIfRequested()
        migrateLegacyPreferences()
        let app = NSApplication.shared
        let container = AppContainer.liveOrCrash()
        SubSwitchApplicationDelegate.makeMainContent = {
            AnyView(RootScene(container: container, trayModel: container.trayModel))
        }
        SubSwitchApplicationDelegate.makeQuotaContent = {
            AnyView(QuotaManagementPageView(model: container.quotaManagementModel, isStandalone: true)
                .modifier(ASModalSurface()).frame(minWidth: 544, minHeight: 650))
        }
        let owner = SubSwitchApplicationDelegate()
        delegate = owner
        app.delegate = owner
        Task { @MainActor in
            container.trayModel.startBackgroundRefresh()
            await container.settingsModel.loadIfNeeded()
        }
        app.run()
    }

    // Copy only product preferences. Never carry forward stale system menu-bar
    // visibility/position state from Copool's application identity.
    private static func migrateLegacyPreferences() {
        let defaults = UserDefaults.standard
        let marker = "ass.legacyPreferencesMigrated"
        guard !defaults.bool(forKey: marker),
              Bundle.main.bundleIdentifier == "com.ailsa.subswitch" else { return }
        let legacy = defaults.persistentDomain(forName: "com.alick.copool") ?? [:]
        for key in ["ass.tokenUnit", "ass.trendStyle", "ass.intradayMinutes", "ass.launchCursorAfterSwitch"] {
            if defaults.object(forKey: key) == nil, let value = legacy[key] {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: marker)
    }

    static let productName = "AILSA SubSwitch"
    static var quotaWindowTitle: String {
        L10n.tr("tab.quota_management") + " · " + productName
    }

    #if canImport(AppKit)
    static func makeMenuBarSymbolImage() -> NSImage? {
        // Approved Draft 05: rounded chevrons, low-quota block plus two
        // thin dashes above a full bar. Vector template follows system tint.
        // Horizontal edges sit on integer points so both 1x and 2x menu bars
        // render the 1pt dashes and bar edges without half-covered rows.
        let canvas = NSImage(size: NSSize(width: 26, height: 18), flipped: false) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            let arrows = NSBezierPath()
            arrows.lineWidth = 3.0
            arrows.lineCapStyle = .round
            arrows.lineJoinStyle = .round
            arrows.move(to: NSPoint(x: 6.0, y: 15))
            arrows.line(to: NSPoint(x: 2.0, y: 9))
            arrows.line(to: NSPoint(x: 6.0, y: 3))
            arrows.move(to: NSPoint(x: 20.0, y: 15))
            arrows.line(to: NSPoint(x: 24.0, y: 9))
            arrows.line(to: NSPoint(x: 20.0, y: 3))
            arrows.stroke()
            NSBezierPath(roundedRect: NSRect(x: 7, y: 10, width: 4, height: 3),
                         xRadius: 1, yRadius: 1).fill()
            for x in [12.0, 16.0] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 11, width: 3, height: 1),
                             xRadius: 0.5, yRadius: 0.5).fill()
            }
            NSBezierPath(roundedRect: NSRect(x: 7, y: 5, width: 12, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        // Status items may be hosted out of process. Materialize the lazy drawing
        // representation before handing the image to the system menu bar.
        guard let data = canvas.tiffRepresentation, let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 26, height: 18)
        image.isTemplate = true
        return image
    }
    #endif
}

#if os(macOS)
@MainActor
final class SubSwitchApplicationDelegate: NSObject, NSApplicationDelegate {
    static var makeMainContent: (() -> AnyView)?
    static var makeQuotaContent: (() -> AnyView)?
    static weak var current: SubSwitchApplicationDelegate?
    private var quotaWindow: NSWindow?
    func showQuotaWindow() {
        popover.performClose(nil)
        if quotaWindow == nil, let content = Self.makeQuotaContent?() {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.title = CopoolApp.quotaWindowTitle
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 760, height: 780))
            window.isReleasedWhenClosed = false
            window.center()
            quotaWindow = window
        }
        quotaWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.current = self
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        if ProcessInfo.processInfo.environment["ASS_STATUS_DIAGNOSTICS"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, let item = self.statusItem else { return }
                let info: [String: Any] = [
                    "visible": item.isVisible,
                    "length": item.length,
                    "windowVisible": item.button?.window?.isVisible ?? false,
                    "frame": NSStringFromRect(item.button?.window?.frame ?? .zero),
                    "button": NSStringFromRect(item.button?.bounds ?? .zero),
                    "imageValid": item.button?.image?.isValid ?? false,
                    "screens": NSScreen.screens.map { NSStringFromRect($0.frame) }
                ]
                if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]),
                   let text = String(data: data, encoding: .utf8) { print("ASS_STATUS " + text); fflush(stdout) }
            }
        }
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: 34)
        // Keep the system-generated Item-0 identity stable. Renaming a live
        // status item can leave Control Center tracking a blocked host identity.
        item.isVisible = true
        if let button = item.button {
            button.image = CopoolApp.makeMenuBarSymbolImage()
            button.toolTip = CopoolApp.productName
            button.setAccessibilityLabel(CopoolApp.productName)
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item
        popover.behavior = .transient
        popover.animates = true
    }

    @objc private func togglePanel() {
        if popover.isShown { popover.performClose(nil) } else { showPanel() }
    }

    private func showPanel() {
        installStatusItem()
        guard let button = statusItem?.button else { return }
        if popover.contentViewController == nil, let content = Self.makeMainContent?() {
            let controller = NSHostingController(rootView: content)
            popover.contentViewController = controller
            let screen = button.window?.screen ?? NSScreen.main
            let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
            popover.contentSize = NSSize(
                width: min(LayoutRules.accountsPageTargetWidth, visible.width - 32),
                height: min(LayoutRules.macOSMenuBarPanelHeight, visible.height - 32))
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    // A menu bar utility must survive a dismissed window or a temporarily
    // unavailable Control Center status-item scene. Explicit Quit still works.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let safety = AppTerminationSafety.shared
        guard !safety.requestTermination() else { return .terminateNow }
        Task { @MainActor in
            while safety.hasActiveAccountSwitch {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
#endif
