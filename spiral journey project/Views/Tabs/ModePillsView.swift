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
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = index
                    }
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
