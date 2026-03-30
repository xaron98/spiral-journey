import SwiftUI
import Charts
import SpiralKit

/// Cumulative circadian phase drift chart using Swift Charts.
struct DriftChartView: View {

    let records: [SleepRecord]
    @Environment(\.languageBundle) private var bundle

    private struct DriftPoint: Identifiable {
        let id = UUID()
        let day: Int
        let drift: Double
        let amplitude: Double
        let isWeekend: Bool
    }

    private var driftData: [DriftPoint] {
        records.map { r in
            DriftPoint(
                day: r.day,
                drift: r.driftMinutes,
                amplitude: r.cosinor.amplitude,
                isWeekend: r.isWeekend
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "drift.title", bundle: bundle))

            Chart {
                // Weekend bands
                ForEach(driftData.filter(\.isWeekend)) { point in
                    RectangleMark(
                        xStart: .value("Day", point.day),
                        xEnd:   .value("Day", point.day + 1),
                        yStart: nil,
                        yEnd:   nil
                    )
                    .foregroundStyle(SpiralColors.weekend.opacity(0.2))
                }

                // Zero baseline
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(SpiralColors.border)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                // Drift area
                ForEach(driftData) { point in
                    AreaMark(
                        x: .value("Day", point.day),
                        y: .value("Drift", point.drift)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SpiralColors.accent.opacity(0.3), SpiralColors.accent.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Day", point.day),
                        y: .value("Drift", point.drift)
                    )
                    .foregroundStyle(SpiralColors.accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                // Amplitude bars (secondary axis approximation via scaled values)
                ForEach(driftData) { point in
                    BarMark(
                        x: .value("Day", point.day),
                        y: .value("Amplitude", point.amplitude * 20 - 40)
                    )
                    .foregroundStyle(SpiralColors.accentDim.opacity(0.3))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 7)) { _ in
                    AxisGridLine().foregroundStyle(SpiralColors.border)
                    AxisTick().foregroundStyle(SpiralColors.border)
                    AxisValueLabel().foregroundStyle(SpiralColors.muted)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(SpiralColors.border.opacity(0.5))
                    AxisValueLabel()
                        .foregroundStyle(SpiralColors.muted)
                        .font(.caption2.monospaced())
                }
            }
            .chartBackground { _ in Color.clear }
            .chartPlotStyle { plotArea in plotArea.background(Color.clear) }
            .frame(height: 100)

            HStack(spacing: 12) {
                legendItem(color: SpiralColors.accent, label: String(localized: "drift.legend.acrophase", bundle: bundle))
                legendItem(color: SpiralColors.accentDim, label: String(localized: "drift.legend.amplitude", bundle: bundle))
            }
        }
        .glassPanel()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "accessibility.chart.drift", defaultValue: "Sleep timing drift chart"))
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(color).frame(width: 12, height: 2)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
    }
}
