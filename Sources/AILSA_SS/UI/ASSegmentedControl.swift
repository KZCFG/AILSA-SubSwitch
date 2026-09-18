import SwiftUI

/// A shared fixed-height control: only the selection highlight animates.
/// The label's background gives the whole segment a hit-testable surface.
struct ASSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let values: [Value]
    let title: (Value) -> String
    var icon: (Value) -> String? = { _ in nil }
    @Namespace private var highlight
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    HStack(spacing: 7) {
                        Spacer(minLength: 0)
                        if let symbol = icon(value) { Image(systemName: symbol) }
                        Text(title(value)).lineLimit(1).minimumScaleFactor(0.75)
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .foregroundStyle(selection == value ? AppDesign.primaryActionText(for: scheme) : AppDesign.secondaryText(for: scheme))
                    .background {
                        if selection == value {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppDesign.primaryAction(for: scheme))
                                .matchedGeometryEffect(id: "selection", in: highlight)
                        } else { Color.primary.opacity(0.001) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(title(value))
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .padding(4)
        .background(AppDesign.surface(for: scheme), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(AppDesign.border(for: scheme), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: selection)
        .accessibilityElement(children: .contain)
    }
}
