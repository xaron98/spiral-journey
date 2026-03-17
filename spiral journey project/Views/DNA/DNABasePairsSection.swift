import SwiftUI
import SpiralKit

/// "Que afecta tu sueno" — top 3 base pairs as natural language descriptions.
/// Hidden when tier == .basic.
struct DNABasePairsSection: View {

    let profile: SleepDNAProfile

    @Environment(\.languageBundle) private var bundle

    // Feature index -> localization key
    private let contextFeatureKeys: [Int: String] = [
        8: "dna.basepair.caffeine", 9: "dna.basepair.exercise", 10: "dna.basepair.alcohol",
        11: "dna.basepair.melatonin", 12: "dna.basepair.stress", 13: "dna.basepair.weekend",
        14: "dna.basepair.hourlyDrift", 15: "dna.basepair.sleepQuality"
    ]

    private let sleepFeatureKeys: [Int: String] = [
        0: "dna.basepair.bedtime", 1: "dna.basepair.wakeTime", 2: "dna.basepair.duration",
        3: "dna.basepair.latency", 4: "dna.basepair.deepSleep", 5: "dna.basepair.rem",
        6: "dna.basepair.fragmentation", 7: "dna.basepair.efficiency"
    ]

    var body: some View {
        if profile.tier != .basic {
            VStack(spacing: 12) {
                // Section header
                HStack {
                    Image(systemName: "link")
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.basepair.header"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpiralColors.subtle)
                        .textCase(.uppercase)
                    Spacer()
                }

                if profile.basePairs.isEmpty {
                    Text(loc("dna.basepair.noData"))
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
        let contextKey = contextFeatureKeys[pair.contextFeatureIndex] ?? "dna.basepair.factor"
        let sleepKey   = sleepFeatureKeys[pair.sleepFeatureIndex] ?? "dna.basepair.sleep"
        let context = loc(contextKey)
        let sleep   = loc(sleepKey)
        let strength = pair.plv > 0.7 ? loc("dna.basepair.strong") : loc("dna.basepair.moderate")

        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(pair.plv > 0.7 ? SpiralColors.accent : SpiralColors.accentDim)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(context.capitalized) \u{2194} \(sleep)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SpiralColors.text)
                Text("\(loc("dna.basepair.bond")) \(strength) (PLV \(String(format: "%.2f", pair.plv)))")
                    .font(.system(size: 12))
                    .foregroundStyle(SpiralColors.muted)
            }

            Spacer()
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
