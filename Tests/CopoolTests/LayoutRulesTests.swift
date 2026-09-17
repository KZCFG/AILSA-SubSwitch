import XCTest
import SwiftUI
@testable import Copool

final class LayoutRulesTests: XCTestCase {
    func testCompactActionControlHeightMatchesAccountCardBottomActionLayout() {
        XCTAssertEqual(LayoutRules.compactActionControlHeight, 30)
    }

    func testMacOSUsesFixedGridColumnCounts() {
        let expanded = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .macOS,
                isOverviewMode: false,
                viewportSize: CGSize(width: 2000, height: 1200)
            )
        )
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .macOS,
                isOverviewMode: true,
                viewportSize: CGSize(width: 2000, height: 1200)
            )
        )

        XCTAssertEqual(expanded, LayoutRules.accountsExpandedColumns)
        XCTAssertEqual(collapsed, LayoutRules.accountsCollapsedColumns)
    }

    func testMacOSUsesFixedCardWidthsForCollapseAnimation() {
        XCTAssertEqual(
            LayoutRules.accountsCardFrameWidth(
                context: .init(
                    platform: .macOS,
                    isOverviewMode: false,
                    viewportSize: CGSize(width: 1200, height: 800)
                )
            ),
            LayoutRules.accountsCardWidth
        )
        XCTAssertEqual(
            LayoutRules.accountsCardFrameWidth(
                context: .init(
                    platform: .macOS,
                    isOverviewMode: true,
                    viewportSize: CGSize(width: 1200, height: 800)
                )
            ),
            LayoutRules.accountsCollapsedCardWidth
        )
    }

    func testIOSKeepsAdaptiveCardWidths() {
        XCTAssertNil(
            LayoutRules.accountsCardFrameWidth(
                context: .init(
                    platform: .iPhone,
                    isOverviewMode: false,
                    viewportSize: CGSize(width: 390, height: 844)
                )
            )
        )
        XCTAssertNil(
            LayoutRules.accountsCardFrameWidth(
                context: .init(
                    platform: .iPadRegular,
                    isOverviewMode: true,
                    viewportSize: CGSize(width: 1180, height: 820)
                )
            )
        )
    }

    func testIOSGridColumnsStayFlexible() {
        let phoneColumns = LayoutRules.accountsGridColumns(
            context: .init(
                platform: .iPhone,
                isOverviewMode: true,
                viewportSize: CGSize(width: 390, height: 844)
            )
        )
        let iPadColumns = LayoutRules.accountsGridColumns(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: false,
                viewportSize: CGSize(width: 1180, height: 820)
            )
        )

        XCTAssertEqual(phoneColumns.count, LayoutRules.iOSAccountsCollapsedColumns)
        XCTAssertEqual(iPadColumns.count, LayoutRules.iPadRegularAccountsExpandedColumnsLandscape)
        XCTAssertTrue(phoneColumns.allSatisfy { gridItemWidth(for: $0) == nil })
        XCTAssertTrue(iPadColumns.allSatisfy { gridItemWidth(for: $0) == nil })
    }

    func testIPadMiniPortraitColumnCounts() {
        let expanded = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadMini,
                isOverviewMode: false,
                viewportSize: CGSize(width: 744, height: 1133)
            )
        )
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadMini,
                isOverviewMode: true,
                viewportSize: CGSize(width: 744, height: 1133)
            )
        )

        XCTAssertEqual(expanded, 2)
        XCTAssertEqual(collapsed, 3)
    }

    func testIPadMiniLandscapeColumnCounts() {
        let expanded = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadMini,
                isOverviewMode: false,
                viewportSize: CGSize(width: 1133, height: 744)
            )
        )
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadMini,
                isOverviewMode: true,
                viewportSize: CGSize(width: 1133, height: 744)
            )
        )

        XCTAssertEqual(expanded, 3)
        XCTAssertEqual(collapsed, 5)
    }

    func testRegularIPadPortraitColumnCounts() {
        let expanded = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: false,
                viewportSize: CGSize(width: 820, height: 1180)
            )
        )
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: true,
                viewportSize: CGSize(width: 820, height: 1180)
            )
        )

        XCTAssertEqual(expanded, 3)
        XCTAssertEqual(collapsed, 5)
    }

    func testRegularIPadLandscapeColumnCounts() {
        let expanded = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: false,
                viewportSize: CGSize(width: 1180, height: 820)
            )
        )
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: true,
                viewportSize: CGSize(width: 1180, height: 820)
            )
        )

        XCTAssertEqual(expanded, 4)
        XCTAssertEqual(collapsed, 7)
    }

    func testNarrowViewportCapsRequestedColumnCount() {
        let collapsed = LayoutRules.accountsGridColumnCount(
            context: .init(
                platform: .iPadRegular,
                isOverviewMode: true,
                viewportSize: CGSize(width: 680, height: 820)
            )
        )

        XCTAssertEqual(collapsed, 4)
    }

    private func gridItemWidth(for item: GridItem) -> CGFloat? {
        Mirror(reflecting: item.size).children
            .first(where: { $0.label == "fixed" })?
            .value as? CGFloat
    }
}
