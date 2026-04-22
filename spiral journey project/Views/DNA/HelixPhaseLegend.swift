import SwiftUI
import SpiralKit

/// Standalone legend describing the two strands (today / yesterday / this
/// week / my best) and the phase color mapping used inside the 3D helix.
///
/// Previously this legend lived at the bottom of `HelixRealityView`'s
/// VStack, which forced the hero frame to reserve ~40pt for it and
/// pushed the model into a too-small vertical space. Moved out so
/// DNAModeView can pin it as an overlay above the action bar — always
/// visible, independent of scroll, and with the hero free to fill the
/// remaining vertical area.
@available(iOS 18.0, *)
struct HelixPhaseLegend: View {
    let comparisonMode: HelixComparisonMode
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(spacing: 4) {
            // Strand identity: gold = strand 1 (today / this week),
            // silver = strand 2 (yesterday / last week / best)
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "ebae33"))
                        .frame(width: 14, height: 4)
                    Text(String(localized: strand1Key, bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "b8bcc7"))
                        .frame(width: 14, height: 4)
                    Text(strand2Text)
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            // Phase colors
            HStack(spacing: 12) {
                legendDot(
                    String(localized: "dna.3d.legend.wake", bundle: bundle),
                    color: Color(hex: "d4a860"))
                legendDot(
                    String(localized: "dna.3d.legend.rem", bundle: bundle),
                    color: Color(hex: "a78bfa"))
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(hex: "4a7ab5"))
                        .frame(width: 6, height: 6)
                    Text("→")
                        .font(.system(size: 7))
                        .foregroundStyle(SpiralColors.muted)
                    Circle()
                        .fill(Color(hex: "1a2a6e"))
                        .frame(width: 6, height: 6)
                    Text(String(localized: "dna.3d.legend.nrem", bundle: bundle))
                        .font(.caption2)
                        .foregroundStyle(SpiralColors.muted)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(
            Capsule().fill(SpiralColors.surface.opacity(0.6))
        )
    }

    private var strand1Key: String.LocalizationValue {
        comparisonMode == .week ? "dna.3d.tooltip.this_week" : "dna.3d.tooltip.today"
    }

    private var strand2Text: String {
        switch comparisonMode {
        case .yesterday: return String(localized: "dna.3d.tooltip.yesterday", bundle: bundle)
        case .week:      return String(localized: "dna.3d.tooltip.last_week", bundle: bundle)
        case .best:      return String(localized: "dna.3d.tooltip.best", bundle: bundle)
        }
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
        }
    }
}
