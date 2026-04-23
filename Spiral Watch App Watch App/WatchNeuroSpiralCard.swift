import SwiftUI

struct WatchNeuroSpiralCard: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private var app: String { store.appearance }

    var body: some View {
        ZStack {
            SpiralColors.bg(app).ignoresSafeArea()
            if let stability = store.neuroSpiralStability {
                VStack(spacing: 6) {
                    Text(String(localized: "watch.neurospiral.last_night", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted(app))

                    // Big percentage — keep the number (users understand %)
                    // but replace the abstract "Estabilidad" label with a
                    // qualitative word in plain Spanish.
                    Text(String(format: "%.0f%%", stability * 100))
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor(stability))

                    Text(qualitativeLabelKey(stability))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SpiralColors.text(app))

                    // Plain-language one-liner. Combines stability level +
                    // transitions count into a single sentence anyone can
                    // read — no vertex codes, no winding ratios, no Greek
                    // letters. The technical fields stay in the payload
                    // for whoever wants them, we just don't surface them
                    // on the tiny Watch screen.
                    Text(summarySentence(
                        stability: stability,
                        transitions: store.neuroSpiralTransitions ?? 0
                    ))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted(app))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Human copy

    private func scoreColor(_ s: Double) -> Color {
        switch s {
        case 0.75...:    return SpiralColors.good
        case 0.55..<0.75: return SpiralColors.accent
        case 0.35..<0.55: return SpiralColors.moderate
        default:          return SpiralColors.poor
        }
    }

    private func qualitativeLabelKey(_ s: Double) -> String {
        let key: String
        switch s {
        case 0.75...:    key = "watch.neurospiral.label.solid"
        case 0.55..<0.75: key = "watch.neurospiral.label.steady"
        case 0.35..<0.55: key = "watch.neurospiral.label.variable"
        default:          key = "watch.neurospiral.label.fragmented"
        }
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    /// Picks one of four pre-translated sentences based on stability and
    /// transitions. Keeps the copy short enough for the Watch screen and
    /// always lands on a concrete, actionable takeaway.
    private func summarySentence(stability: Double, transitions: Int) -> String {
        let stableLevel = stability >= 0.6
        let fewTransitions = transitions < 15
        let key: String
        switch (stableLevel, fewTransitions) {
        case (true,  true):  key = "watch.neurospiral.summary.consolidated"
        case (true,  false): key = "watch.neurospiral.summary.solidWithBreaks"
        case (false, true):  key = "watch.neurospiral.summary.unevenFewBreaks"
        case (false, false): key = "watch.neurospiral.summary.restless"
        }
        return String(
            format: String(localized: String.LocalizationValue(key), bundle: bundle),
            transitions
        )
    }
}
