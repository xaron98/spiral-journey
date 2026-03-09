import SwiftUI
import Charts
import SpiralKit

/// 7-day rolling cosinor parameters — 4 sparklines.
struct SlidingCosinorView: View {

    let records: [SleepRecord]
    @Environment(\.languageBundle) private var bundle

    private var sliding: [(dayIndex: Int, result: CosinorResult)] {
        CosinorAnalysis.slidingFit(records, windowDays: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "cosinor.rolling.title", bundle: bundle))

            if sliding.isEmpty {
                Text(String(localized: "learn.cosinor.needDays", bundle: bundle))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    sparkline(title: "Acrophase", values: sliding.map { ($0.dayIndex, $0.result.acrophase) }, color: SpiralColors.accent, format: "%.0fh")
                    sparkline(title: "Amplitude", values: sliding.map { ($0.dayIndex, $0.result.amplitude) }, color: SpiralColors.lightSleep, format: "%.2f")
                }
                HStack(spacing: 8) {
                    sparkline(title: "MESOR",     values: sliding.map { ($0.dayIndex, $0.result.mesor) },     color: SpiralColors.moderate, format: "%.2f")
                    sparkline(title: "R²",        values: sliding.map { ($0.dayIndex, $0.result.r2) },        color: SpiralColors.good,     format: "%.2f")
                }
            }
        }
        .panelStyle()
    }

    private func sparkline(title: String, values: [(Int, Double)], color: Color, format: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
            if let last = values.last {
                Text(String(format: format, last.1))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
            }
            Chart {
                ForEach(values.indices, id: \.self) { i in
                    LineMark(
                        x: .value("Day", values[i].0),
                        y: .value("Value", values[i].1)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.2))
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartBackground { _ in Color.clear }
            .frame(height: 32)
        }
        .frame(maxWidth: .infinity)
    }
}
