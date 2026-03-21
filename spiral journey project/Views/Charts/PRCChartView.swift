import SwiftUI
import Charts
import SpiralKit

/// Interactive Phase Response Curve chart.
/// Pass `events` to overlay the user's real logged events as dots on the curve.
struct PRCChartView: View {

    var events: [CircadianEvent] = []

    @State private var selectedModel: EventType = .light
    @State private var showHelp = false
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

    /// User events matching the selected model, with their PRC response value.
    private var userEventPoints: [(hour: Double, response: Double)] {
        events
            .filter { $0.type == selectedModel }
            .compactMap { event -> (Double, Double)? in
                let h = event.absoluteHour.truncatingRemainder(dividingBy: 24)
                guard let r = PhaseResponse.models[selectedModel]?.fn(h) else { return nil }
                return (h, r)
            }
    }

    private var curveColor: Color {
        Color(hex: PhaseResponse.models[selectedModel]?.hexColor ?? "5bffa8")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                PanelTitle(title: String(localized: "prc.title", bundle: bundle))
                Spacer()
                Button {
                    showHelp = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(SpiralColors.subtle)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showHelp) {
                PRCHelpSheet(bundle: bundle)
            }

            // Model selector
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EventType.allCases, id: \.self) { type in
                        PillButton(label: localizedEventLabel(type), isActive: selectedModel == type) {
                            selectedModel = type
                        }
                    }
                }
            }

            // Reference label
            HStack(spacing: 4) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
                Text(String(localized: "prc.reference.label", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.subtle)
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
                            colors: [curveColor.opacity(0.3), curveColor.opacity(0)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    LineMark(
                        x: .value("Hour", point.hour),
                        y: .value("Response", point.response)
                    )
                    .foregroundStyle(curveColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                // User event dots — overlaid on the curve
                ForEach(Array(userEventPoints.enumerated()), id: \.offset) { _, pt in
                    PointMark(
                        x: .value("Hour", pt.hour),
                        y: .value("Response", pt.response)
                    )
                    .foregroundStyle(.white)
                    .symbolSize(28)
                    PointMark(
                        x: .value("Hour", pt.hour),
                        y: .value("Response", pt.response)
                    )
                    .foregroundStyle(curveColor)
                    .symbolSize(16)
                }
            }
            .chartXScale(domain: 0...24)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                    AxisGridLine().foregroundStyle(SpiralColors.border)
                    AxisValueLabel {
                        Text(String(format: "%02d:00", value.as(Int.self) ?? 0))
                            .font(.caption2.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                    }
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
            .frame(height: 110)

            HStack(spacing: 12) {
                legendZone(color: SpiralColors.poor,     label: String(localized: "prc.delay", bundle: bundle))
                legendZone(color: SpiralColors.good,     label: String(localized: "prc.advance", bundle: bundle))
                legendZone(color: SpiralColors.muted,    label: String(localized: "prc.dead", bundle: bundle))
                if !userEventPoints.isEmpty {
                    legendDot(color: curveColor, label: String(localized: "prc.your.events", bundle: bundle))
                }
            }
        }
        .glassPanel()
    }

    private func localizedEventLabel(_ type: EventType) -> String {
        switch type {
        case .light:       return String(localized: "event.type.light",       bundle: bundle)
        case .exercise:    return String(localized: "event.type.exercise",    bundle: bundle)
        case .melatonin:   return String(localized: "event.type.melatonin",   bundle: bundle)
        case .caffeine:    return String(localized: "event.type.caffeine",    bundle: bundle)
        case .screenLight: return String(localized: "event.type.screenLight", bundle: bundle)
        case .alcohol:     return String(localized: "event.type.alcohol",     bundle: bundle)
        case .meal:        return String(localized: "event.type.meal",        bundle: bundle)
        case .stress:      return String(localized: "event.type.stress",      bundle: bundle)
        }
    }

    private func legendZone(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.4)).frame(width: 10, height: 8)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
    }
}

// MARK: - PRC Help Sheet

private struct PRCHelpSheet: View {
    let bundle: Bundle
    @Environment(\.dismiss) private var dismiss

    private struct HelpSection: Identifiable {
        let id = UUID()
        let icon: String
        let iconColor: Color
        let title: String
        let body: String
    }

    private var sections: [HelpSection] {
        [
            HelpSection(
                icon: "clock.arrow.2.circlepath",
                iconColor: SpiralColors.accent,
                title: NSLocalizedString("prc.help.what.title", bundle: bundle, comment: ""),
                body: NSLocalizedString("prc.help.what.body", bundle: bundle, comment: "")
            ),
            HelpSection(
                icon: "arrow.up.circle.fill",
                iconColor: SpiralColors.good,
                title: NSLocalizedString("prc.help.advance.title", bundle: bundle, comment: ""),
                body: NSLocalizedString("prc.help.advance.body", bundle: bundle, comment: "")
            ),
            HelpSection(
                icon: "arrow.down.circle.fill",
                iconColor: SpiralColors.poor,
                title: NSLocalizedString("prc.help.delay.title", bundle: bundle, comment: ""),
                body: NSLocalizedString("prc.help.delay.body", bundle: bundle, comment: "")
            ),
            HelpSection(
                icon: "minus.circle.fill",
                iconColor: SpiralColors.subtle,
                title: NSLocalizedString("prc.help.dead.title", bundle: bundle, comment: ""),
                body: NSLocalizedString("prc.help.dead.body", bundle: bundle, comment: "")
            ),
            HelpSection(
                icon: "lightbulb.fill",
                iconColor: SpiralColors.moderate,
                title: NSLocalizedString("prc.help.use.title", bundle: bundle, comment: ""),
                body: NSLocalizedString("prc.help.use.body", bundle: bundle, comment: "")
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sections) { section in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: section.icon)
                                .font(.headline)
                                .foregroundStyle(section.iconColor)
                                .frame(width: 26)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(section.title)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(SpiralColors.text)
                                Text(section.body)
                                    .font(.footnote)
                                    .foregroundStyle(SpiralColors.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineSpacing(3)
                            }
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 20)
                        Divider()
                            .background(SpiralColors.border)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.bottom, 20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("prc.help.sheet.title", bundle: bundle, comment: ""))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("stats.glossary.done", bundle: bundle, comment: "")) {
                        dismiss()
                    }
                    .foregroundStyle(SpiralColors.accent)
                }
            }
        }
    }
}
