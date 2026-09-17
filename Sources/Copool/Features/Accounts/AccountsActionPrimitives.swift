import SwiftUI

struct AccountsActionStrip<Intent: Hashable>: View {
    let descriptors: [AccountsActionButtonDescriptor<Intent>]
    let onTrigger: (Intent) -> Void

    var body: some View {
        HStack(spacing: LayoutRules.listRowSpacing) {
            ForEach(descriptors) { descriptor in
                AccountsActionBarButton(
                    descriptor: descriptor,
                    onTrigger: onTrigger
                )
            }
        }
    }
}

struct AccountsToolbarButtonGroup<Intent: Hashable>: View {
    let descriptors: [AccountsActionButtonDescriptor<Intent>]
    let onTrigger: (Intent) -> Void

    var body: some View {
        ForEach(descriptors) { descriptor in
            AccountsToolbarButton(
                descriptor: descriptor,
                onTrigger: onTrigger
            )
        }
    }
}

private struct AccountsActionBarButton<Intent: Hashable>: View {
    let descriptor: AccountsActionButtonDescriptor<Intent>
    let onTrigger: (Intent) -> Void

    var body: some View {
        Group {
            if let value = descriptor.toggleValue {
                Toggle(isOn: Binding(get: { value }, set: { _ in onTrigger(descriptor.intent) })) {
                    AccountsActionLabel(descriptor: descriptor)
                }.toggleStyle(.button)
            } else if descriptor.menuItems.isEmpty {
                Button {
                    onTrigger(descriptor.intent)
                } label: {
                    AccountsActionLabel(descriptor: descriptor)
                }
            } else {
                Menu {
                    ForEach(descriptor.menuItems) { item in
                        Button {
                            onTrigger(item.intent)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                } label: {
                    AccountsActionLabel(descriptor: descriptor)
                }
            }
        }
        .disabled(!descriptor.isEnabled)
        .copoolActionButtonStyle(
            prominent: descriptor.surfaceStyle != .neutral,
            tint: tintColor,
            density: .compact
        )
        .accessibilityLabel(Text(descriptor.accessibilityLabel))
    }

    private var tintColor: Color? {
        switch descriptor.surfaceStyle {
        case .neutral, .prominent, .mint:
            nil
        }
    }
}

private struct AccountsToolbarButton<Intent: Hashable>: View {
    let descriptor: AccountsActionButtonDescriptor<Intent>
    let onTrigger: (Intent) -> Void

    var body: some View {
        Group {
            if descriptor.menuItems.isEmpty {
                Button {
                    onTrigger(descriptor.intent)
                } label: {
                    iconLabel
                }
            } else {
                Menu {
                    ForEach(descriptor.menuItems) { item in
                        Button {
                            onTrigger(item.intent)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                } label: {
                    iconLabel
                }
            }
        }
        .disabled(!descriptor.isEnabled)
        .accessibilityLabel(Text(descriptor.accessibilityLabel))
    }

    private var iconLabel: some View {
        ToolbarIconLabel(
            systemImage: descriptor.systemImage,
            isSpinning: descriptor.isSpinning,
            opticalScale: descriptor.systemImage == "arrow.trianglehead.clockwise.rotate.90"
                ? LayoutRules.toolbarRefreshIconOpticalScale
                : 1
        )
    }
}

private struct AccountsActionLabel<Intent: Hashable>: View {
    let descriptor: AccountsActionButtonDescriptor<Intent>

    var body: some View {
        switch descriptor.contentStyle {
        case .label:
            Label(descriptor.title ?? "", systemImage: descriptor.systemImage)
                .lineLimit(1)
        case .icon:
            ToolbarIconLabel(
                systemImage: descriptor.systemImage,
                isSpinning: descriptor.isSpinning,
                opticalScale: descriptor.systemImage == "arrow.trianglehead.clockwise.rotate.90"
                    ? LayoutRules.toolbarRefreshIconOpticalScale
                    : 1,
                usesInheritedForeground: true
            )
        }
    }
}
