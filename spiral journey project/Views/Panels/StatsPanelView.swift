import SwiftUI
import SpiralKit

/// Displays 9 computed statistics cards and circadian disorder signatures.
struct StatsPanelView: View {

    let records: [SleepRecord]
    @Environment(\.languageBundle) private var bundle

    private var stats: SleepStats {
        SleepStatistics.calculateStats(records)
    }

    private var signatures: [DisorderSignature] {
        DisorderDetection.detect(from: records)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelTitle(title: String(localized: "stats.title", bundle: bundle))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                StatCard(String(localized: "stats.card.acrophase", bundle: bundle),
                         value: SleepStatistics.formatHour(stats.meanAcrophase),
                         sub: String(localized: "stats.acrophase.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.acroSigma", bundle: bundle),
                         value: String(format: "±%.1fh", stats.stdAcrophase),
                         sub: String(localized: "stats.acroSigma.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.amplitude", bundle: bundle),
                         value: String(format: "%.2f", stats.meanAmplitude),
                         sub: String(localized: "stats.amplitude.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.rhythm", bundle: bundle),
                         value: String(format: "%.0f%%", stats.rhythmStability * 100),
                         sub: String(localized: "stats.rhythm.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.sri", bundle: bundle),
                         value: String(format: "%.0f%%", stats.sri),
                         sub: String(localized: "stats.sri.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.socialJL", bundle: bundle),
                         value: String(format: "%.0f min", stats.socialJetlag),
                         sub: String(localized: "stats.socialJL.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.wkndAmp", bundle: bundle),
                         value: String(format: "%.2f", stats.weekendAmp),
                         sub: String(format: "%.0f%% drop", max(0, stats.ampDrop)))
                StatCard(String(localized: "stats.card.sleep", bundle: bundle),
                         value: String(format: "%.1fh", stats.meanSleepDuration),
                         sub: String(localized: "stats.sleep.sub", bundle: bundle))
                StatCard(String(localized: "stats.card.r2", bundle: bundle),
                         value: String(format: "%.2f", stats.meanR2),
                         sub: String(localized: "stats.r2.sub", bundle: bundle))
            }

            if !signatures.isEmpty {
                Divider().background(SpiralColors.border)
                PanelTitle(title: String(localized: "stats.pattern.title", bundle: bundle))
                ForEach(signatures) { sig in
                    SignatureBadge(signature: sig)
                }
            }
        }
        .panelStyle()
    }
}

private struct SignatureBadge: View {
    let signature: DisorderSignature

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: signature.hexColor))
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(signature.fullLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Text(String(format: "%.0f%%", signature.confidence * 100))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)
                }
                Text(signature.description)
                    .font(.system(size: 9))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
