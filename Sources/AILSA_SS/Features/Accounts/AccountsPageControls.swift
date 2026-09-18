import SwiftUI

struct AccountsActionBarView: View {
    let presentation: AccountsActionBarPresentation
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void

    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            AccountsActionStrip(
                descriptors: presentation.descriptors,
                onTrigger: onTriggerAction
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            CollapseChevronButton(isExpanded: presentation.collapse.isExpanded) {
                onToggleCollapse()
            }
            .disabled(!presentation.isCollapseToggleEnabled)
            .accessibilityLabel(Text(presentation.collapse.accessibilityLabel))
        }
    }
}

#if os(iOS)
struct AccountsToolbarActions: ToolbarContent {
    let leadingButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let trailingButtons: [AccountsActionButtonDescriptor<AccountsPageActionIntent>]
    let currentLocale: AppLocale
    let onSelectLocale: (AppLocale) -> Void
    let onTriggerAction: (AccountsPageActionIntent) -> Void
    let onToggleCollapse: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            LanguageMenuButton(
                currentLocale: currentLocale,
                onSelectLocale: onSelectLocale
            ) {
                ToolbarIconLabel(systemImage: "globe")
            }
        }

        ToolbarItemGroup(placement: .topBarLeading) {
            AccountsToolbarButtonGroup(
                descriptors: leadingButtons,
                onTrigger: triggerAction
            )
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            AccountsToolbarButtonGroup(
                descriptors: trailingButtons,
                onTrigger: triggerAction
            )
        }
    }

    private func triggerAction(_ intent: AccountsPageActionIntent) {
        if intent == .toggleCollapse {
            onToggleCollapse()
            return
        }
        onTriggerAction(intent)
    }
}
#endif
