import SwiftUI
import Charts
import SpiralKit

/// Interactive Phase Response Curve chart.
struct PRCChartView: View {

    @State private var selectedModel: EventType = .light
    @Environment(\.languageBundle) private var bundle

    private struct PRCPoint: Identifiable {
        let id = UUID()
        let hour: Double
        let response: Double
    }

    private var curveData: [PRCPoint] {
        PhaseResponse.curve(for: selectedModel, step: 0.5).map {
            PRCPoint(hour: $0.hour, response: $0.response)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "prc.title", bundle: bundle))

            // Model selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EventType.allCases, id: \.self) { type in
                        PillButton(label: type.label, isActive: selectedModel == type) {
                            selectedModel = type
                        }
                    }
                }
            }

            if let model = PhaseResponse.models[selectedModel] {
                Text(model.label)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }

            Chart {
                // Zone backgrounds
                RectangleMark(xStart: .value("h", 10), xEnd: .value("h", 20), yStart: nil, yEnd: nil)
                    .foregroundStyle(SpiralColors.poor.opacity(0.06))
                RectangleMark(xStart: .value("h", 20), xEnd: .value("h", 24), yStart: nil, yEnd: nil)
                    .foregroundStyle(SpiralColors.good.opacity(0.06))

                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(SpiralColors.border)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3, 3]))

                // PRC curve
                ForEach(curveData) { point in
                    AreaMark(
                        x: .value("Hour", point.hour),
                        y: .value("Response", point.response)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: PhaseResponse.models[selectedModel]?.hexColor ?? "5bffa8").opacity(0.3),
                                Color(hex: PhaseResponse.models[selectedModel]?.hexColor ?? "5bffa8").opacity(0)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Response", point.response)
                    )
                    .foregroundStyle(Color(hex: PhaseResponse.models[selectedModel]?.hexColor ?? "5bffa8"))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                    AxisGridLine().foregroundStyle(SpiralColors.border)
                    AxisValueLabel {
                        Text(String(format: "%02d:00", value.as(Int.self) ?? 0))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(SpiralColors.border.opacity(0.5))
                    AxisValueLabel()
                        .foregroundStyle(SpiralColors.muted)
                        .font(.system(size: 8, design: .monospaced))
                }
            }
            .chartBackground { _ in SpiralColors.bg }
            .frame(height: 100)

            HStack(spacing: 12) {
                legendZone(color: SpiralColors.poor,     label: String(localized: "prc.delay", bundle: bundle))
                legendZone(color: SpiralColors.good,     label: String(localized: "prc.advance", bundle: bundle))
                legendZone(color: SpiralColors.muted,    label: String(localized: "prc.dead", bundle: bundle))
            }
        }
        .panelStyle()
    }

    private func legendZone(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.4)).frame(width: 10, height: 8)
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
        }
    }
}
