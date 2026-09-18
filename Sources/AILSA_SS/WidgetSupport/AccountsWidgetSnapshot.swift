import Foundation
import SwiftUI
import WidgetKit

enum AccountsWidgetConfiguration {
    static let kind = "AILSA_SSAccountsWidget"
    // Moved off the legacy group.com.alick.copool container: its directory
    // became unopenable at the VFS level (2026-09-15), which wedged cfprefsd
    // and blocked app launch. A fresh identifier sidesteps the dead vnode.
    static let appGroupIdentifier = "group.com.alick.copool.g2"
    static let snapshotFilename = "accounts-widget-snapshot.json"
    static let usageProgressDisplayModeDefaultsKey = "accountsWidgetUsageProgressDisplayMode"
}

enum AccountsWidgetUsageProgressDisplayMode: String, Codable, Equatable, Sendable {
    case used
    case remaining
}

struct AccountsWidgetDisplayModeStore: Sendable {
    private static let writeQueue = DispatchQueue(label: "com.alick.copool.widget-preferences", qos: .utility)
    private let defaultsProvider: @Sendable () -> UserDefaults?

    init(
        defaultsProvider: @escaping @Sendable () -> UserDefaults? = {
            UserDefaults(suiteName: AccountsWidgetConfiguration.appGroupIdentifier)
        }
    ) {
        self.defaultsProvider = defaultsProvider
    }

    func load() -> AccountsWidgetUsageProgressDisplayMode {
        guard let rawValue = defaultsProvider()?
            .string(forKey: AccountsWidgetConfiguration.usageProgressDisplayModeDefaultsKey),
              let mode = AccountsWidgetUsageProgressDisplayMode(rawValue: rawValue) else {
            return .used
        }
        return mode
    }

    func save(rawValue: String, completion: @escaping @Sendable () -> Void = {}) {
        let normalizedRawValue = AccountsWidgetUsageProgressDisplayMode(rawValue: rawValue)?.rawValue
            ?? AccountsWidgetUsageProgressDisplayMode.used.rawValue
        // The app-group suite write can block indefinitely when cfprefsd or the
        // group container is unavailable, and AppContainer performs this on the
        // main thread during app init. Never let a widget preference wedge app
        // launch: perform the write off the calling thread.
        Self.writeQueue.async {
            self.defaultsProvider()?.set(
                normalizedRawValue,
                forKey: AccountsWidgetConfiguration.usageProgressDisplayModeDefaultsKey
            )
            completion()
        }
    }
}

struct AccountsWidgetSnapshot: Codable, Equatable, Sendable {
    var generatedAt: Int64
    var usageProgressDisplayMode: AccountsWidgetUsageProgressDisplayMode
    var currentCard: AccountsWidgetCardSnapshot?
    var secondaryCard: AccountsWidgetCardSnapshot?
    var rows: [AccountsWidgetRowSnapshot]

    static let empty = AccountsWidgetSnapshot(
        generatedAt: 0,
        usageProgressDisplayMode: .used,
        currentCard: nil,
        secondaryCard: nil,
        rows: []
    )

    func resolvedUsageProgressDisplayMode() -> AccountsWidgetUsageProgressDisplayMode {
        return usageProgressDisplayMode
    }
}

struct AccountsWidgetResolvedColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: opacity)
    }
}

struct AccountsWidgetTagPalette: Equatable, Sendable {
    let fill: AccountsWidgetResolvedColor
    let text: AccountsWidgetResolvedColor

    static let accentedContrast = AccountsWidgetTagPalette(
        fill: AccountsWidgetResolvedColor(red: 1, green: 1, blue: 1, opacity: 0.18),
        text: AccountsWidgetResolvedColor(red: 1, green: 1, blue: 1, opacity: 0.98)
    )
}

enum AccountsWidgetTagPaletteResolver {
    static func planTagPalette(
        for planLabel: String,
        colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode
    ) -> AccountsWidgetTagPalette {
        _ = planLabel
        guard renderingMode == .fullColor else {
            return .accentedContrast
        }

        return neutralPlanPalette(for: colorScheme)
    }

    static func accountTagPalette(
        for colorScheme: ColorScheme,
        renderingMode: WidgetRenderingMode
    ) -> AccountsWidgetTagPalette {
        guard renderingMode == .fullColor else {
            return .accentedContrast
        }

        return neutralAccountPalette(for: colorScheme)
    }

    private static func neutralPlanPalette(for colorScheme: ColorScheme) -> AccountsWidgetTagPalette {
        switch colorScheme {
        case .dark:
            AccountsWidgetTagPalette(
                fill: AccountsWidgetResolvedColor(red: 0.23, green: 0.23, blue: 0.23, opacity: 1),
                text: AccountsWidgetResolvedColor(red: 0.96, green: 0.96, blue: 0.96, opacity: 1)
            )
        default:
            AccountsWidgetTagPalette(
                fill: AccountsWidgetResolvedColor(red: 0.90, green: 0.90, blue: 0.90, opacity: 1),
                text: AccountsWidgetResolvedColor(red: 0.09, green: 0.09, blue: 0.09, opacity: 1)
            )
        }
    }

    private static func neutralAccountPalette(for colorScheme: ColorScheme) -> AccountsWidgetTagPalette {
        switch colorScheme {
        case .dark:
            AccountsWidgetTagPalette(
                fill: AccountsWidgetResolvedColor(red: 0.16, green: 0.16, blue: 0.16, opacity: 1),
                text: AccountsWidgetResolvedColor(red: 0.96, green: 0.96, blue: 0.96, opacity: 1)
            )
        default:
            AccountsWidgetTagPalette(
                fill: AccountsWidgetResolvedColor(red: 0.945, green: 0.945, blue: 0.945, opacity: 1),
                text: AccountsWidgetResolvedColor(red: 0.09, green: 0.09, blue: 0.09, opacity: 1)
            )
        }
    }
}

struct AccountsWidgetCardSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var planLabel: String
    var workspaceLabel: String?
    var accountLabel: String
    var fiveHour: AccountsWidgetWindowSnapshot
    var oneWeek: AccountsWidgetWindowSnapshot
    /// `nil` keeps pre-visibility snapshots readable as visible. New snapshots
    /// set this to false for an unavailable or user-hidden placeholder so the
    /// widget never draws it as a fabricated metric.
    var quotaDisplayHidden: Bool? = nil

    var visibleWindows: [AccountsWidgetWindowSnapshot] {
        [fiveHour, oneWeek].filter(\.isVisibleInWidget)
    }

    var isQuotaDisplayHidden: Bool {
        quotaDisplayHidden == true
    }
}

struct AccountsWidgetWindowSnapshot: Codable, Equatable, Sendable {
    var title: String
    var progressFraction: Double
    var usedText: String
    var remainingText: String
    var resetText: String
    var isVisible: Bool? = nil

    var isVisibleInWidget: Bool {
        isVisible ?? true
    }
}

struct AccountsWidgetRowSnapshot: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var planLabel: String
    var workspaceLabel: String?
    var accountLabel: String
    var fiveHour: AccountsWidgetWindowSnapshot
    var oneWeek: AccountsWidgetWindowSnapshot
    var quotaDisplayHidden: Bool? = nil

    var visibleWindows: [AccountsWidgetWindowSnapshot] {
        [fiveHour, oneWeek].filter(\.isVisibleInWidget)
    }

    var isQuotaDisplayHidden: Bool {
        quotaDisplayHidden == true
    }
}
