import SwiftUI

struct WatchNeuroSpiralCard: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private var app: String { store.appearance }

    var body: some View {
        ZStack {
            SpiralColors.bg(app).ignoresSafeArea()
            if let stability = store.neuroSpiralStability {
                VStack(spacing: 8) {
                    Text(String(localized: "watch.neurospiral.last_night", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted(app))

                    Text(String(format: "%.0f%%", stability * 100))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(stability > 0.6 ? SpiralColors.good : SpiralColors.moderate)

                    Text(String(localized: "watch.neurospiral.stability", bundle: bundle))
                        .font(.system(size: 11))
                        .foregroundStyle(SpiralColors.muted(app))

                    if let idx = store.neuroSpiralDominantIdx,
                       let code = store.neuroSpiralDominantCode {
                        Text("V\(String(format: "%02d", idx)) \(code)")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundStyle(SpiralColors.accent)
                    }

                    if let winding = store.neuroSpiralWinding {
                        Text("ω₁/ω₂ = \(String(format: "%.2f", winding))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted(app))
                    }

                    if let transitions = store.neuroSpiralTransitions {
                        Text(String(format: String(localized: "watch.neurospiral.transitions", bundle: bundle), transitions))
                            .font(.system(size: 10))
                            .foregroundStyle(SpiralColors.muted(app))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.title2)
                        .foregroundStyle(SpiralColors.muted(app))
                    Text("NeuroSpiral")
                        .font(.system(size: 12))
                        .foregroundStyle(SpiralColors.muted(app))
                    Text(String(localized: "watch.neurospiral.no_data", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted(app))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
