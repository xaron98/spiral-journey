import SwiftUI

struct ModePillsView: View {
    @Binding var selectedMode: Int
    @Environment(\.languageBundle) private var bundle

    private let modes: [(icon: String, label: String)] = [
        ("circle.hexagonpath", "Torus"),
        ("hurricane", "Spiral"),
        ("circle.dotted.and.circle", "DNA"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                modePill(at: index)
            }
        }
    }

    private func modePill(at index: Int) -> some View {
        let isSelected = selectedMode == index
        let label = modes[index].label

        return Button {
            // Assign directly — the parent TabView already animates
            // the page transition via its own .animation modifier on
            // `selectedMode`. Wrapping in withAnimation here stacked
            // a second implicit animation on top, which made rapid
            // taps queue up and register slowly (user had to tap
            // 2-3 times for the switch to land).
            selectedMode = index
        } label: {
            HStack(spacing: 6) {
                Image(systemName: modes[index].icon)
                    .font(.caption2)
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                isSelected
                    ? SpiralColors.accent.opacity(0.2)
                    : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(
                isSelected
                    ? SpiralColors.accent
                    : SpiralColors.muted
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(String(format: String(localized: "tabs.mode.pill.a11yHint", bundle: bundle), label))
    }
}
