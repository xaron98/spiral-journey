import SwiftUI
import SpiralKit

/// "Tu ritmo hoy" — circadian coherence state with colored label and helix decoration.
struct DNAStateSection: View {

    let profile: SleepDNAProfile

    private var coherence: Double { profile.healthMarkers.circadianCoherence }
    private var hb: Double { profile.healthMarkers.homeostasisBalance }

    private var stateLabel: String {
        if coherence > 0.7 { return "sincronizado" }
        if coherence >= 0.4 { return "en transicion" }
        return "desalineado"
    }

    private var stateColor: Color {
        if coherence > 0.7 { return SpiralColors.good }
        if coherence >= 0.4 { return SpiralColors.awakeSleep }
        return SpiralColors.poor
    }

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .foregroundStyle(SpiralColors.accent)
                Text("Tu ritmo hoy")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(stateLabel)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(stateColor)

                    Text("Coherencia \(Int(coherence * 100))%  \u{00B7}  HB \(String(format: "%.2f", hb))")
                        .font(.system(size: 13))
                        .foregroundStyle(SpiralColors.muted)
                }

                Spacer()

                MiniHelixView(width: 80, height: 40)
                    .opacity(0.6)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SpiralColors.surface)
        )
    }
}
