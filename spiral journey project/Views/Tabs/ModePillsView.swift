import SwiftUI

struct ModePillsView: View {
    @Binding var selectedMode: Int

    private let modes: [(icon: String, label: String)] = [
        ("circle.hexagonpath", "Torus"),
        ("hurricane", "Spiral"),
        ("circle.dotted.and.circle", "DNA"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Button {
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
                        Text(modes[index].label)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        selectedMode == index
                            ? SpiralColors.accent.opacity(0.2)
                            : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(
                        selectedMode == index
                            ? SpiralColors.accent
                            : SpiralColors.muted
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
