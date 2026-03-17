import SwiftUI
import SpiralKit

/// "Que afecta tu sueno" — top 3 base pairs as natural language descriptions.
/// Hidden when tier == .basic.
struct DNABasePairsSection: View {

    let profile: SleepDNAProfile

    // Feature index -> readable name
    private let contextFeatureNames: [Int: String] = [
        8: "cafeina", 9: "ejercicio", 10: "alcohol",
        11: "melatonina", 12: "estres", 13: "fin de semana",
        14: "deriva horaria", 15: "calidad del sueno"
    ]

    private let sleepFeatureNames: [Int: String] = [
        0: "hora de dormir", 1: "hora de despertar", 2: "duracion",
        3: "latencia", 4: "sueno profundo", 5: "REM",
        6: "fragmentacion", 7: "eficiencia"
    ]

    var body: some View {
        if profile.tier != .basic {
            VStack(spacing: 12) {
                // Section header
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(SpiralColors.accent)
                    Text("Que afecta tu sueno")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpiralColors.subtle)
                        .textCase(.uppercase)
                    Spacer()
                }

                if profile.basePairs.isEmpty {
                    Text("Sin datos de sincronizacion aun")
                        .font(.system(size: 14))
                        .foregroundStyle(SpiralColors.muted)
                } else {
                    VStack(spacing: 10) {
                        ForEach(Array(profile.basePairs.prefix(3).enumerated()), id: \.offset) { _, pair in
                            basePairRow(pair)
                        }
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(SpiralColors.surface)
            )
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func basePairRow(_ pair: BasePairSynchrony) -> some View {
        let context = contextFeatureNames[pair.contextFeatureIndex] ?? "factor \(pair.contextFeatureIndex)"
        let sleep   = sleepFeatureNames[pair.sleepFeatureIndex] ?? "sueno"
        let strength = pair.plv > 0.7 ? "fuerte" : "moderado"

        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(pair.plv > 0.7 ? SpiralColors.accent : SpiralColors.accentDim)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.capitalized) \u{2194} \(sleep)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SpiralColors.text)
                Text("Vinculo \(strength) (PLV \(String(format: "%.2f", pair.plv)))")
                    .font(.system(size: 12))
                    .foregroundStyle(SpiralColors.muted)
            }

            Spacer()
        }
    }
}
