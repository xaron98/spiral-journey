import SwiftUI
import SpiralKit

/// Sparkline chart of nightly HRV (SDNN) with trend indicator and interpretation.
///
/// Shows the relationship between autonomic nervous system health and sleep quality.
/// HRV SDNN during sleep is the best non-invasive proxy for deep sleep quality.
struct HRVTrendView: View {

    let hrvData: [NightlyHRV]

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "hrv.title", bundle: bundle))

            Text(String(localized: "hrv.description", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)

            if hrvData.count < 3 {
                Text(String(localized: "hrv.needMoreData", bundle: bundle))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                sparkline
                statsRow
            }
        }
        .panelStyle()
    }

    // MARK: - Sparkline

    private var sparkline: some View {
        let values = hrvData.map(\.meanSDNN)
        let minV = (values.min() ?? 0) * 0.9
        let maxV = (values.max() ?? 100) * 1.1
        let range = max(maxV - minV, 1)

        return Canvas { ctx, size in
            let w = size.width
            let h: CGFloat = 60
            let stepX = w / CGFloat(max(values.count - 1, 1))

            // Draw sparkline path
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = h - CGFloat((v - minV) / range) * h
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            ctx.stroke(path, with: .color(SpiralColors.accent), lineWidth: 1.5)

            // Draw dots
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = h - CGFloat((v - minV) / range) * h
                let dot = Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                ctx.fill(dot, with: .color(SpiralColors.accent))
            }
        }
        .frame(height: 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        let trend = HRVAnalysis.trend(hrvData)
        let mean = HRVAnalysis.meanSDNN(hrvData)
        let interp = HRVAnalysis.interpretation(meanSDNN: mean)

        return HStack(spacing: 16) {
            // Mean SDNN
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "hrv.meanSDNN", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(String(format: "%.0f ms", mean))
                    .font(.body.weight(.semibold).monospaced())
                    .foregroundStyle(SpiralColors.text)
            }

            // Trend arrow
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "hrv.trend", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                HStack(spacing: 4) {
                    Image(systemName: trendIcon(trend))
                        .font(.caption)
                        .foregroundStyle(trendColor(trend))
                    Text(trendLabel(trend))
                        .font(.caption.monospaced())
                        .foregroundStyle(trendColor(trend))
                }
            }

            // Interpretation
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "hrv.level", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(interpretLabel(interp))
                    .font(.caption.monospaced())
                    .foregroundStyle(interpretColor(interp))
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func trendIcon(_ trend: HRVTrend) -> String {
        switch trend {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .stable:  return "arrow.right"
        }
    }

    private func trendColor(_ trend: HRVTrend) -> Color {
        switch trend {
        case .rising:  return SpiralColors.good
        case .falling: return SpiralColors.poor
        case .stable:  return SpiralColors.muted
        }
    }

    private func trendLabel(_ trend: HRVTrend) -> String {
        switch trend {
        case .rising:  return String(localized: "hrv.trend.rising", bundle: bundle)
        case .falling: return String(localized: "hrv.trend.falling", bundle: bundle)
        case .stable:  return String(localized: "hrv.trend.stable", bundle: bundle)
        }
    }

    private func interpretLabel(_ interp: HRVInterpretation) -> String {
        switch interp {
        case .low:          return String(localized: "hrv.interp.low", bundle: bundle)
        case .belowAverage: return String(localized: "hrv.interp.belowAvg", bundle: bundle)
        case .average:      return String(localized: "hrv.interp.average", bundle: bundle)
        case .aboveAverage: return String(localized: "hrv.interp.aboveAvg", bundle: bundle)
        case .high:         return String(localized: "hrv.interp.high", bundle: bundle)
        }
    }

    private func interpretColor(_ interp: HRVInterpretation) -> Color {
        switch interp {
        case .low:          return SpiralColors.poor
        case .belowAverage: return SpiralColors.moderate
        case .average:      return SpiralColors.muted
        case .aboveAverage: return SpiralColors.good
        case .high:         return SpiralColors.good
        }
    }
}
