import SwiftUI

enum AccountsAnimationRules {
    static let collapseToggle = AppDesign.contentTransition
    static let contentReorder = AppDesign.contentTransition
    static let cardHoverOverlay = AppDesign.interaction
    static let cardEntranceBase = AppDesign.contentTransition
    static let cardEntranceMaximumDelay = 0.20
    static let cardEntranceStepDelay = 0.03
    static let collapsedOverlayMinimumPressDuration = 0.35

    static func cardEntrance(index: Int) -> Animation {
        cardEntranceBase.delay(
            min(cardEntranceMaximumDelay, Double(index) * cardEntranceStepDelay)
        )
    }
}
