import SwiftUI
import SpiralKit

/// "Deja vu" — sequence alignment similarity and prediction.
struct DNAAlignmentSection: View {

    let profile: SleepDNAProfile

    private var hasAlignments: Bool { !profile.alignments.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            // Section header
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundStyle(SpiralColors.accent)
                Text("Deja vu")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Spacer()
            }

            if hasAlignments {
                alignmentContent
            } else {
                Text("Necesitas mas semanas de datos")
                    .font(.system(size: 14))
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(SpiralColors.surface)
        )
    }

    // MARK: - Alignment Content

    @ViewBuilder
    private var alignmentContent: some View {
        let best = profile.alignments.sorted { $0.similarity > $1.similarity }.first!

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Similitud")
                    .font(.system(size: 14))
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text("\(Int(best.similarity * 100))%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(similarityColor(best.similarity))
            }

            if let pred = profile.prediction {
                Divider().overlay(SpiralColors.border)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Prediccion")
                            .font(.system(size: 12))
                            .foregroundStyle(SpiralColors.subtle)
                        Text("Dormir \(formatHour(pred.predictedBedtime))  \u{2192}  Despertar \(formatHour(pred.predictedWake))")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(SpiralColors.text)
                    }
                    Spacer()
                    Text("\(Int(pred.confidence * 100))%")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.accent)
                }
            }
        }
    }

    // MARK: - Helpers

    private func similarityColor(_ s: Double) -> Color {
        if s > 0.7 { return SpiralColors.good }
        if s >= 0.4 { return SpiralColors.awakeSleep }
        return SpiralColors.poor
    }

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h) % 24
        let min  = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hour, min)
    }
}
