import SwiftUI
import SpiralKit

/// "Tu codigo genetico" — active motifs, instance counts, and recent mutations.
struct DNAMotifSection: View {

    let profile: SleepDNAProfile

    @Environment(\.languageBundle) private var bundle

    private var hasMotifs: Bool { !profile.motifs.isEmpty }
    private var learningWeeks: Int { profile.dataWeeks }
    private let requiredWeeks = 8

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .foregroundStyle(SpiralColors.accent)
                Text(loc("dna.motif.header"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            if hasMotifs {
                motifContent
            } else {
                learningContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SpiralColors.surface)
        )
    }

    // MARK: - Motifs Found

    @ViewBuilder
    private var motifContent: some View {
        let topMotif = profile.motifs.sorted { $0.instanceCount > $1.instanceCount }.first!

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(localizedMotifName(topMotif.name))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text("\(topMotif.instanceCount) \(loc("dna.motif.weeks"))")
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
            }

            if profile.motifs.count > 1 {
                Text("+\(profile.motifs.count - 1) \(loc("dna.motif.morePatterns"))")
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.subtle)
            }

            // Recent mutation
            if let lastMut = profile.mutations.last {
                HStack(spacing: 6) {
                    mutationBadge(lastMut.classification)
                    Text(mutationLabel(lastMut.classification))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text(String(format: "%+.0f%%", lastMut.qualityDelta * 100))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(lastMut.qualityDelta >= 0 ? SpiralColors.good : SpiralColors.poor)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Learning State

    @ViewBuilder
    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("dna.motif.learning"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            ProgressView(value: Double(learningWeeks), total: Double(requiredWeeks))
                .tint(SpiralColors.accent)

            Text("\(learningWeeks) / \(requiredWeeks) \(loc("dna.motif.weeks"))")
                .font(.caption)
                .foregroundStyle(SpiralColors.subtle)
        }
    }

    // MARK: - Helpers

    private func mutationBadge(_ type: MutationType) -> some View {
        Circle()
            .fill(mutationColor(type))
            .frame(width: 8, height: 8)
    }

    private func mutationColor(_ type: MutationType) -> Color {
        switch type {
        case .silent:   return SpiralColors.good
        case .missense: return SpiralColors.awakeSleep
        case .nonsense: return SpiralColors.poor
        }
    }

    private func mutationLabel(_ type: MutationType) -> String {
        switch type {
        case .silent:   return loc("dna.motif.mutation.silent")
        case .missense: return loc("dna.motif.mutation.missense")
        case .nonsense: return loc("dna.motif.mutation.nonsense")
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    /// Translate motif engine keys (English) to localized names
    private func localizedMotifName(_ engineName: String) -> String {
        let key = "dna.motif.name.\(engineName.lowercased())"
        let result = loc(key)
        // If no translation found (key returned as-is), show the engine name
        return result == key ? engineName : result
    }
}
