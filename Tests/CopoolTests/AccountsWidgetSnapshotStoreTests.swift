import SwiftUI
import WidgetKit
import XCTest
@testable import Copool

final class AccountsWidgetSnapshotStoreTests: XCTestCase {
    func testDisplayModeStorePersistsSharedMode() async {
        let defaultsSuite = "test.accounts-widget-display-mode.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        let store = AccountsWidgetDisplayModeStore(defaultsProvider: { UserDefaults(suiteName: defaultsSuite) })

        XCTAssertEqual(store.load(), .used)

        await withCheckedContinuation { continuation in
            store.save(rawValue: "remaining") { continuation.resume() }
        }

        XCTAssertEqual(store.load(), .remaining)
    }

    func testLoadReturnsEmptyForInvalidSnapshotData() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let snapshotURL = tempDirectory.appendingPathComponent("accounts-widget.json", isDirectory: false)
        try Data("not json".utf8).write(to: snapshotURL, options: .atomic)

        let store = AccountsWidgetSnapshotStore(
            fileManager: .default,
            snapshotURLProvider: { snapshotURL }
        )

        XCTAssertEqual(store.load(), .empty)
    }

    func testSaveWritesSnapshotToExplicitURL() throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let snapshotURL = tempDirectory.appendingPathComponent("accounts-widget.json", isDirectory: false)
        let snapshot = AccountsWidgetSnapshot(
            generatedAt: 1,
            usageProgressDisplayMode: .remaining,
            currentCard: AccountsWidgetCardSnapshot(
                id: "current",
                planLabel: "PRO",
                workspaceLabel: nil,
                accountLabel: "current@example.com",
                fiveHour: AccountsWidgetWindowSnapshot(
                    title: "5h",
                    progressFraction: 0.2,
                    usedText: "20%",
                    remainingText: "80%",
                    resetText: "--"
                ),
                oneWeek: AccountsWidgetWindowSnapshot(
                    title: "1w",
                    progressFraction: 0.3,
                    usedText: "30%",
                    remainingText: "70%",
                    resetText: "--"
                )
            ),
            secondaryCard: nil,
            rows: []
        )

        let store = AccountsWidgetSnapshotStore(
            fileManager: .default,
            snapshotURLProvider: { snapshotURL }
        )

        try store.save(snapshot)

        let data = try Data(contentsOf: snapshotURL)
        let decoded = try JSONDecoder().decode(AccountsWidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testWriterUsesExplicitUsageProgressDisplayModeOverride() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let snapshotURL = tempDirectory.appendingPathComponent("accounts-widget.json", isDirectory: false)
        let store = AccountsWidgetSnapshotStore(
            fileManager: .default,
            snapshotURLProvider: { snapshotURL }
        )
        let writer = AccountsWidgetSnapshotWriter(
            snapshotStore: store,
            localeProvider: { Locale(identifier: "en_US") },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! }
        )
        let accounts = [
            AccountSummary(
                id: "current",
                label: "current",
                email: "current@example.com",
                accountID: "current",
                planType: "team",
                teamName: nil,
                teamAlias: nil,
                addedAt: 0,
                updatedAt: 0,
                usage: UsageSnapshot(
                    fetchedAt: 0,
                    planType: "team",
                    fiveHour: UsageWindow(usedPercent: 25, windowSeconds: 18_000, resetAt: 1000),
                    oneWeek: UsageWindow(usedPercent: 40, windowSeconds: 604_800, resetAt: 2000),
                    credits: nil
                ),
                usageError: nil,
                isCurrent: true
            )
        ]

        await writer.write(
            accounts: accounts,
            usageProgressDisplayMode: .remaining
        )

        let snapshot = store.load()
        XCTAssertEqual(snapshot.usageProgressDisplayMode, .remaining)
    }

    @MainActor
    func testWriterReloadsCurrentWidgetKindAfterSave() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let snapshotURL = tempDirectory.appendingPathComponent("accounts-widget.json", isDirectory: false)
        let store = AccountsWidgetSnapshotStore(
            fileManager: .default,
            snapshotURLProvider: { snapshotURL }
        )
        let reloadExpectation = expectation(description: "reload timelines")
        var reloadedKind: String?
        let writer = AccountsWidgetSnapshotWriter(
            snapshotStore: store,
            localeProvider: { Locale(identifier: "en_US") },
            timeZoneProvider: { TimeZone(secondsFromGMT: 0)! },
            reloadTimelinesOfKind: { kind in
                reloadedKind = kind
                reloadExpectation.fulfill()
            }
        )
        let accounts = [
            AccountSummary(
                id: "current",
                label: "current",
                email: "current@example.com",
                accountID: "current",
                planType: "team",
                teamName: nil,
                teamAlias: nil,
                addedAt: 0,
                updatedAt: 0,
                usage: UsageSnapshot(
                    fetchedAt: 0,
                    planType: "team",
                    fiveHour: UsageWindow(usedPercent: 25, windowSeconds: 18_000, resetAt: 1000),
                    oneWeek: UsageWindow(usedPercent: 40, windowSeconds: 604_800, resetAt: 2000),
                    credits: nil
                ),
                usageError: nil,
                isCurrent: true
            )
        ]

        await writer.write(
            accounts: accounts,
            usageProgressDisplayMode: .used
        )

        await fulfillment(of: [reloadExpectation], timeout: 1)
        XCTAssertEqual(reloadedKind, AccountsWidgetConfiguration.kind)
    }

    func testSnapshotCarriesOwnDisplayModeForWidgetRendering() {
        let snapshot = AccountsWidgetSnapshot(
            generatedAt: 1,
            usageProgressDisplayMode: .remaining,
            currentCard: nil,
            secondaryCard: nil,
            rows: []
        )

        XCTAssertEqual(
            snapshot.resolvedUsageProgressDisplayMode(),
            .remaining
        )
    }

    func testPlanTagPaletteUsesMonochromeContrastInAccentedMode() {
        let palette = AccountsWidgetTagPaletteResolver.planTagPalette(
            for: "PRO",
            colorScheme: .light,
            renderingMode: .accented
        )

        XCTAssertEqual(palette.fill.red, 1, accuracy: 0.001)
        XCTAssertEqual(palette.fill.green, 1, accuracy: 0.001)
        XCTAssertEqual(palette.fill.blue, 1, accuracy: 0.001)
        XCTAssertEqual(palette.fill.opacity, 0.18, accuracy: 0.001)
        XCTAssertEqual(palette.text.red, 1, accuracy: 0.001)
        XCTAssertEqual(palette.text.green, 1, accuracy: 0.001)
        XCTAssertEqual(palette.text.blue, 1, accuracy: 0.001)
        XCTAssertEqual(palette.text.opacity, 0.98, accuracy: 0.001)
    }

    func testPlanTagPaletteUsesNeutralPaletteOutsideAccentedMode() {
        let palette = AccountsWidgetTagPaletteResolver.planTagPalette(
            for: "PRO",
            colorScheme: .light,
            renderingMode: .fullColor
        )

        XCTAssertEqual(palette.fill.red, 0.90, accuracy: 0.001)
        XCTAssertEqual(palette.fill.green, 0.90, accuracy: 0.001)
        XCTAssertEqual(palette.fill.blue, 0.90, accuracy: 0.001)
        XCTAssertEqual(palette.fill.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(palette.text.red, 0.09, accuracy: 0.001)
        XCTAssertEqual(palette.text.green, 0.09, accuracy: 0.001)
        XCTAssertEqual(palette.text.blue, 0.09, accuracy: 0.001)
        XCTAssertEqual(palette.text.opacity, 1, accuracy: 0.001)
    }

}
