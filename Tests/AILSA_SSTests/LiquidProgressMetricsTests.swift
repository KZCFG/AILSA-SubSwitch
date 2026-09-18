import XCTest
import SwiftUI
@testable import AILSA_SS

final class LiquidProgressMetricsTests: XCTestCase {
    func testRenderModelClampsProgressIntoUnitRange() {
        XCTAssertEqual(LiquidProgressRenderModel(progress: -0.4).fillScale, 0)
        XCTAssertEqual(LiquidProgressRenderModel(progress: 0.45).fillScale, 0.45, accuracy: 0.001)
        XCTAssertEqual(LiquidProgressRenderModel(progress: 1.8).fillScale, 1, accuracy: 0.001)
    }

    func testRenderModelOnlyShowsFillForPositiveProgress() {
        XCTAssertFalse(LiquidProgressRenderModel(progress: 0).showsFill)
        XCTAssertTrue(LiquidProgressRenderModel(progress: 0.01).showsFill)
    }

    func testSubHalfPercentIsEmptyAndHalfPercentKeepsItsMeasuredWidth() {
        let empty = LiquidProgressMetrics(progress: 0.0049, totalWidth: 250)
        let barelyVisible = LiquidProgressMetrics(progress: 0.005, totalWidth: 250)

        XCTAssertEqual(empty.visibleFillWidth, 0, accuracy: 0.001)
        XCTAssertEqual(barelyVisible.rawFillWidth, 1.25, accuracy: 0.001)
        XCTAssertEqual(barelyVisible.visibleFillWidth, barelyVisible.rawFillWidth, accuracy: 0.001)
    }

    func testHigherProgressKeepsMeasuredFillWidth() {
        let metrics = LiquidProgressMetrics(progress: 0.3, totalWidth: 250)

        XCTAssertEqual(metrics.visibleFillWidth, metrics.rawFillWidth)
    }

    func testNinetyNinePointFivePercentUsesTheFullTrack() {
        let metrics = LiquidProgressMetrics(progress: 0.995, totalWidth: 250)

        XCTAssertEqual(metrics.visibleFillWidth, 250, accuracy: 0.001)
    }

    func testCompactRingUsesDotThresholdAboveOnePercent() {
        let metrics = LiquidRingMetrics(progress: 0.01, lineWidth: 7)
        let threshold = metrics.dotThreshold(in: CGSize(width: 54, height: 54))

        XCTAssertGreaterThan(threshold, 0.01)
        XCTAssertLessThan(threshold, 0.1)
    }

    func testProgressHeightUsesApprovedNinePointAccountBar() {
        XCTAssertEqual(LayoutRules.liquidProgressHeight, 9, accuracy: 0.001)
    }

    func testMacMenuBarPanelUsesOneStableLargestHeight() {
        XCTAssertEqual(LayoutRules.macOSMenuBarPanelHeight, 760, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(LayoutRules.macOSMenuBarPanelHeight, LayoutRules.accountsPanelHeight)
        XCTAssertGreaterThanOrEqual(LayoutRules.macOSMenuBarPanelHeight, LayoutRules.quotaManagementPanelHeight)
        XCTAssertGreaterThanOrEqual(LayoutRules.macOSMenuBarPanelHeight, LayoutRules.settingsPanelHeight)
    }
}
