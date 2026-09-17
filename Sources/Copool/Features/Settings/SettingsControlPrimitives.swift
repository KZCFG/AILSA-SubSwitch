import SwiftUI

struct SettingsToggleRows<Intent: Hashable>: View {
    let descriptors: [SettingsToggleDescriptor<Intent>]
    let onChange: (Intent, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Metrics.groupSpacing) {
            ForEach(descriptors) { descriptor in
                Toggle(
                    isOn: Binding(
                        get: { descriptor.isOn },
                        set: { onChange(descriptor.intent, $0) }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(descriptor.titleKey))
                            .font(.subheadline)
                        if let detailKey = descriptor.detailKey {
                            Text(LocalizedStringKey(detailKey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .toggleStyle(SettingsNeutralSwitchStyle())
                .disabled(!descriptor.isEnabled)
            }
        }
    }
}

/// A deliberately compact two-state control for Settings. Keeping the label
/// column fluid and the control column fixed makes every row scan as a single
/// list, while the inverse black/white active state remains distinct from an
/// inactive gray track and a disabled control.
struct SettingsNeutralSwitchStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 16) {
                configuration.label
                    .frame(maxWidth: .infinity, alignment: .leading)

                SettingsNeutralSwitchTrack(
                    isOn: configuration.isOn,
                    isEnabled: isEnabled,
                    colorScheme: colorScheme,
                    reduceMotion: reduceMotion
                )
                .frame(width: 50, alignment: .trailing)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            configuration.isOn
                ? L10n.tr("settings.switch.on")
                : L10n.tr("settings.switch.off")
        )
    }
}

private struct SettingsNeutralSwitchTrack: View {
    let isOn: Bool
    let isEnabled: Bool
    let colorScheme: ColorScheme
    let reduceMotion: Bool

    private var activeTrackColor: Color {
        AppDesign.primaryAction(for: colorScheme)
    }

    private var inactiveTrackColor: Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.31)
        default:
            Color(white: 0.76)
        }
    }

    private var disabledTrackColor: Color {
        switch colorScheme {
        case .dark:
            Color(white: 0.22)
        default:
            Color(white: 0.88)
        }
    }

    private var trackColor: Color {
        isEnabled ? (isOn ? activeTrackColor : inactiveTrackColor) : disabledTrackColor
    }

    private var thumbColor: Color {
        if !isEnabled {
            switch colorScheme {
            case .dark:
                Color(white: 0.48)
            default:
                Color.white
            }
        } else if isOn {
            AppDesign.primaryActionText(for: colorScheme)
        } else {
            AppDesign.elevatedSurface(for: colorScheme)
        }
    }

    var body: some View {
        Capsule()
            .fill(trackColor)
            .overlay {
                Capsule()
                    .stroke(
                        isEnabled ? AppDesign.border(for: colorScheme) : disabledTrackColor,
                        lineWidth: isOn && isEnabled ? 0 : 1
                    )
            }
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(thumbColor)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
            .frame(width: 46, height: 26)
            .opacity(isEnabled ? 1 : 0.62)
            .animation(reduceMotion ? nil : AppDesign.interaction, value: isOn)
    }
}

struct SettingsPickerRow<Value: Hashable>: View {
    let descriptor: SettingsPickerDescriptor<Value>
    let onSelect: (Value) -> Void

    var body: some View {
        Picker(
            LocalizedStringKey(descriptor.titleKey),
            selection: Binding(
                get: { descriptor.selectedValue },
                set: { value in
                    onSelect(value)
                }
            )
        ) {
            ForEach(descriptor.options) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .disabled(!descriptor.isEnabled)
    }
}
