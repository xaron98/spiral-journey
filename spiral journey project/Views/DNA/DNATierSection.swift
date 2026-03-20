import SwiftUI
import SpiralKit

/// Tier indicator at the bottom of the DNA insights view.
struct DNATierSection: View {

    let profile: SleepDNAProfile

    @Environment(\.languageBundle) private var bundle

    private var tierLabel: String {
        switch profile.tier {
        case .basic:        return loc("dna.tier.basic")
        case .intermediate: return loc("dna.tier.intermediate")
        case .full:         return loc("dna.tier.full")
        }
    }

    private var tierIcon: String {
        switch profile.tier {
        case .basic:        return "1.circle.fill"
        case .intermediate: return "2.circle.fill"
        case .full:         return "3.circle.fill"
        }
    }

    private var tierColor: Color {
        switch profile.tier {
        case .basic:        return SpiralColors.subtle
        case .intermediate: return SpiralColors.accent
        case .full:         return SpiralColors.good
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: tierIcon)
                .font(.subheadline)
                .foregroundStyle(tierColor)

            Text("\(loc("dna.tier.analysisLevel")) \(tierLabel)")
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)

            Spacer()

            Text("\(profile.dataWeeks) \(loc("dna.tier.weeksOfData"))")
                .font(.footnote)
                .foregroundStyle(SpiralColors.subtle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(SpiralColors.surface.opacity(0.6))
        )
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
