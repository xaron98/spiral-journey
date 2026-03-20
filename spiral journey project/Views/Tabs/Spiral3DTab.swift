import SwiftUI
import SpiralKit

/// Tab wrapper for the 3D helix view.
struct Spiral3DTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @State private var maxReachedTurns: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(String(localized: "helix3d.title", bundle: bundle))
                    .font(.headline.weight(.light).monospaced())
                    .tracking(6)
                    .foregroundStyle(SpiralColors.accent)
                Text(String(localized: "helix3d.hint", bundle: bundle))
                    .font(.caption2.monospaced())
                    .tracking(2)
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Spiral3DView(
                records: store.records,
                episodes: store.sleepEpisodes,
                spiralType: store.spiralType,
                period: store.period,
                maxReachedTurns: maxReachedTurns
            )
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .padding(.horizontal, 16)

            // Elevation hint
            HStack {
                Image(systemName: "arrow.down.left.and.arrow.up.right")
                    .font(.caption)
                Text(String(localized: "helix3d.hint", bundle: bundle))
                    .font(.caption.monospaced())
            }
            .foregroundStyle(SpiralColors.muted)
            .padding(.top, 8)

            Spacer()
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .onAppear {
            if store.sleepEpisodes.isEmpty {
                maxReachedTurns = 1.0
            } else {
                let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
                maxReachedTurns = max(1.0, lastEnd / store.period)
            }
        }
        .onChange(of: store.records.count) { _, _ in
            if !store.sleepEpisodes.isEmpty {
                let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
                let turns = max(1.0, lastEnd / store.period)
                if turns > maxReachedTurns { maxReachedTurns = turns }
            }
        }
    }
}
