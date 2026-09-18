import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Centralized layout inputs to avoid duplicated sizing logic across pages.
enum LayoutRules {
    static let pagePadding = CGFloat(16)
    static let sectionSpacing = CGFloat(16)
    static let cardRadius = AppDesign.Metrics.radius
    /// Mirrors CodexBar's compact 6pt Canvas usage bar. The bar itself owns
    /// its 3pt corner radius; no outer inset, border, or glass treatment is used.
    static let liquidProgressHeight = CGFloat(9)
    static let liquidProgressInset = CGFloat(0)
    static let listRowSpacing = CGFloat(8)
    static let tabSwitcherMaxWidth = CGFloat(360)
    static let minimumPanelHeight = CGFloat(520)
    static let defaultPanelHeight = CGFloat(620)
    static let quotaManagementContentMinimumHeight = CGFloat(360)
    static let quotaManagementCompactSpacing = CGFloat(6)
    static let accountsPanelHeight = CGFloat(760)
    /// Below this panel height an expanded account card row (header, name,
    /// four AntiGravity quota buckets, action cluster) plus the page chrome
    /// no longer fits without scrolling, so cards are forced into the
    /// compact/overview layout instead.
    static let accountsCompactCardsPanelHeight = CGFloat(640)
    static func accountsForcesCompactCards(panelHeight: CGFloat?) -> Bool {
        guard let panelHeight else { return false }
        return panelHeight < accountsCompactCardsPanelHeight
    }
    static let quotaManagementPanelHeight = CGFloat(760)
    static let settingsPanelHeight = CGFloat(580)
    /// A MenuBarExtra window must retain one content size while its tabs swap.
    /// On macOS 26, animating between per-tab heights can re-enter AppKit's
    /// display-cycle constraint update. Use the largest supported page height
    /// for every tab instead of asking SwiftUI to resize the hosting window.
    static let macOSMenuBarPanelHeight = max(
        accountsPanelHeight,
        quotaManagementPanelHeight,
        settingsPanelHeight
    )
    static let accountsRowSpacing = CGFloat(12)
    static let accountsExpandedColumns = 2
    static let accountsCollapsedColumns = 3
    static let accountsCardWidth = CGFloat(250)
    static let iOSAccountsExpandedColumns = 1
    static let iOSAccountsCollapsedColumns = 2
    static let iPadMiniAccountsExpandedColumnsPortrait = 2
    static let iPadMiniAccountsExpandedColumnsLandscape = 3
    static let iPadMiniAccountsCollapsedColumnsPortrait = 3
    static let iPadMiniAccountsCollapsedColumnsLandscape = 5
    static let iPadRegularAccountsExpandedColumnsPortrait = 3
    static let iPadRegularAccountsExpandedColumnsLandscape = 4
    static let iPadRegularAccountsCollapsedColumnsPortrait = 5
    static let iPadRegularAccountsCollapsedColumnsLandscape = 7
    static let accountsExpandedCardMinimumWidth = CGFloat(240)
    static let accountsCollapsedCardMinimumWidth = CGFloat(132)
    static let iPhoneAccountsExpandedCardMinimumWidth = CGFloat(280)
    static let iPhoneAccountsCollapsedCardMinimumWidth = CGFloat(160)
    static let iPadMiniShortestSideThreshold = CGFloat(780)
    static let iOSAccountsScrollBottomPadding = CGFloat(28)
    static let iOSBottomBarHorizontalPadding = CGFloat(16)
    static let iOSBottomBarTopInset = CGFloat(8)
    static let iOSBottomBarBottomInset = CGFloat(10)
    static let iOSNoticeCornerRadius = CGFloat(14)
    static let iOSToolbarButtonSize = CGFloat(44)
    static let toolbarIconPointSize = CGFloat(18)
    static let toolbarRefreshIconOpticalScale = CGFloat(0.82)
    static let compactActionControlHeight = CGFloat(30)

    static var accountsTwoColumnContentWidth: CGFloat {
        accountsCardWidth * CGFloat(accountsExpandedColumns) + accountsRowSpacing
    }

    static var accountsPageTargetWidth: CGFloat {
        accountsTwoColumnContentWidth + pagePadding * 2
    }

    static var accountsCollapsedCardWidth: CGFloat {
        (accountsPageTargetWidth - pagePadding * 2 - accountsRowSpacing * 2) / CGFloat(accountsCollapsedColumns)
    }

    static var minimumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var defaultPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static var maximumPanelWidth: CGFloat {
        accountsPageTargetWidth
    }

    static func iOSAccountsContentTopPadding(safeAreaTop: CGFloat) -> CGFloat {
        safeAreaTop + pagePadding
    }

    static func iOSAccountsContentBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom + iOSAccountsScrollBottomPadding
    }

    static func accountsGridColumns(isOverviewMode: Bool, isCompactWidth: Bool) -> [GridItem] {
        accountsGridColumns(
            context: AccountsGridContext(
                platform: isCompactWidth ? .iPhone : .macOS,
                isOverviewMode: isOverviewMode,
                viewportSize: CGSize(
                    width: isCompactWidth ? 390 : accountsPageTargetWidth,
                    height: isCompactWidth ? 844 : defaultPanelHeight
                )
            )
        )
    }

    struct AccountsGridContext: Equatable {
        enum Platform: Equatable {
            case macOS
            case iPhone
            case iPadMini
            case iPadRegular
        }

        let platform: Platform
        let isOverviewMode: Bool
        let viewportSize: CGSize
    }

    static func accountsGridColumns(context: AccountsGridContext) -> [GridItem] {
        if context.platform == .macOS {
            let width = context.isOverviewMode ? accountsCollapsedCardWidth : accountsCardWidth
            let count = accountsGridColumnCount(context: context)
            return Array(
                repeating: GridItem(
                    .fixed(width),
                    spacing: accountsRowSpacing,
                    alignment: .top
                ),
                count: count
            )
        }

        return Array(
            repeating: GridItem(
                .flexible(minimum: 0, maximum: .infinity),
                spacing: accountsRowSpacing,
                alignment: .top
            ),
            count: accountsGridColumnCount(context: context)
        )
    }

    static func accountsGridColumnCount(context: AccountsGridContext) -> Int {
        if context.platform == .macOS {
            return accountsGridTargetColumnCount(context: context)
        }

        return min(
            accountsGridTargetColumnCount(context: context),
            accountsGridMaximumColumnCount(context: context)
        )
    }

    #if os(iOS)
    @MainActor
    static func accountsGridContext(
        isOverviewMode: Bool,
        viewportSize: CGSize
    ) -> AccountsGridContext {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let shortestSide = min(viewportSize.width, viewportSize.height)
            let platform: AccountsGridContext.Platform = shortestSide < iPadMiniShortestSideThreshold
                ? .iPadMini
                : .iPadRegular
            return AccountsGridContext(
                platform: platform,
                isOverviewMode: isOverviewMode,
                viewportSize: viewportSize
            )
        }

        return AccountsGridContext(
            platform: .iPhone,
            isOverviewMode: isOverviewMode,
            viewportSize: viewportSize
        )
    }
    #endif

    static func accountsCardFrameWidth(isOverviewMode: Bool, isCompactWidth: Bool) -> CGFloat? {
        accountsCardFrameWidth(
            context: AccountsGridContext(
                platform: isCompactWidth ? .iPhone : .macOS,
                isOverviewMode: isOverviewMode,
                viewportSize: CGSize(
                    width: isCompactWidth ? 390 : accountsPageTargetWidth,
                    height: isCompactWidth ? 844 : defaultPanelHeight
                )
            )
        )
    }

    static func accountsCardFrameWidth(context: AccountsGridContext) -> CGFloat? {
        guard context.platform == .macOS else { return nil }
        return context.isOverviewMode ? accountsCollapsedCardWidth : accountsCardWidth
    }

    static func accountsPageContentWidth(isCompactWidth: Bool) -> CGFloat? {
        isCompactWidth ? nil : accountsPageTargetWidth
    }

    private static func accountsGridTargetColumnCount(context: AccountsGridContext) -> Int {
        switch context.platform {
        case .macOS:
            return context.isOverviewMode ? accountsCollapsedColumns : accountsExpandedColumns
        case .iPhone:
            return context.isOverviewMode ? iOSAccountsCollapsedColumns : iOSAccountsExpandedColumns
        case .iPadMini:
            if isLandscape(viewportSize: context.viewportSize) {
                return context.isOverviewMode
                    ? iPadMiniAccountsCollapsedColumnsLandscape
                    : iPadMiniAccountsExpandedColumnsLandscape
            } else {
                return context.isOverviewMode
                    ? iPadMiniAccountsCollapsedColumnsPortrait
                    : iPadMiniAccountsExpandedColumnsPortrait
            }
        case .iPadRegular:
            if isLandscape(viewportSize: context.viewportSize) {
                return context.isOverviewMode
                    ? iPadRegularAccountsCollapsedColumnsLandscape
                    : iPadRegularAccountsExpandedColumnsLandscape
            } else {
                return context.isOverviewMode
                    ? iPadRegularAccountsCollapsedColumnsPortrait
                    : iPadRegularAccountsExpandedColumnsPortrait
            }
        }
    }

    private static func accountsGridMaximumColumnCount(context: AccountsGridContext) -> Int {
        let availableWidth = max(0, context.viewportSize.width - pagePadding * 2)
        let minimumCardWidth: CGFloat
        switch context.platform {
        case .iPhone:
            minimumCardWidth = context.isOverviewMode
                ? iPhoneAccountsCollapsedCardMinimumWidth
                : iPhoneAccountsExpandedCardMinimumWidth
        default:
            minimumCardWidth = context.isOverviewMode
                ? accountsCollapsedCardMinimumWidth
                : accountsExpandedCardMinimumWidth
        }

        guard availableWidth > 0 else { return 1 }
        return max(
            1,
            Int(((availableWidth + accountsRowSpacing) / (minimumCardWidth + accountsRowSpacing)).rounded(.down))
        )
    }

    private static func isLandscape(viewportSize: CGSize) -> Bool {
        viewportSize.width > viewportSize.height
    }
}
