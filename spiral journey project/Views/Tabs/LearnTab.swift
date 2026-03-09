import SwiftUI
import SpiralKit

/// Educational section — simplified explanations to help users understand their circadian data.
struct LearnTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                WhySpiralCard()
                CircadianBasicsCard()
                CosinorExplainerCard(records: store.records)
                PRCExplainerCard()
                SleepHygieneCard(analysis: store.analysis)
                StudySourcesCard()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
    }
}

// MARK: - Why the Spiral?

private struct WhySpiralCard: View {
    @State private var expanded = true
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        LearnCard(
            icon: "hurricane",
            iconColor: SpiralColors.accent,
            title: String(localized: "learn.whyspiral.title", bundle: bundle),
            expanded: $expanded
        ) {
            learnText(String(localized: "learn.whyspiral.body", bundle: bundle))
        }
    }
}

// MARK: - Circadian Basics

private struct CircadianBasicsCard: View {
    @State private var expanded = false
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        LearnCard(
            icon: "sun.and.horizon.fill",
            iconColor: SpiralColors.moderate,
            title: String(localized: "learn.circadian.title", bundle: bundle),
            expanded: $expanded
        ) {
            learnText(String(localized: "learn.circadian.body", bundle: bundle))
        }
    }
}

// MARK: - Cosinor Explainer

private struct CosinorExplainerCard: View {
    let records: [SleepRecord]
    @State private var expanded = false
    @State private var demoAmplitude: Double = 0.35
    @State private var demoAcrophase: Double = 15.0
    @State private var demoMesor: Double = 0.50
    @Environment(\.languageBundle) private var bundle

    private var curvePoints: [(x: Double, y: Double)] {
        (0..<48).map { i in
            let h = Double(i) * 0.5
            let omega = (2 * Double.pi) / 24
            let y = demoMesor + demoAmplitude * cos(omega * (h - demoAcrophase))
            return (x: h, y: max(0, min(1, y)))
        }
    }

    var body: some View {
        LearnCard(
            icon: "waveform.path.ecg",
            iconColor: SpiralColors.accent,
            title: String(localized: "learn.cosinor.title", bundle: bundle),
            expanded: $expanded
        ) {
            learnText(String(localized: "learn.cosinor.body", bundle: bundle))
            Canvas { context, size in
                let w = size.width, h = size.height
                guard curvePoints.count > 1 else { return }
                var path = Path()
                for (i, pt) in curvePoints.enumerated() {
                    let x = (pt.x / 24) * w
                    let y = (1 - pt.y) * h
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                context.stroke(path, with: .color(SpiralColors.accent), lineWidth: 2)
                var mesorLine = Path()
                let mesorY = (1 - demoMesor) * h
                mesorLine.move(to: CGPoint(x: 0, y: mesorY))
                mesorLine.addLine(to: CGPoint(x: w, y: mesorY))
                context.stroke(mesorLine, with: .color(SpiralColors.muted.opacity(0.5)),
                               style: StrokeStyle(lineWidth: 0.8, dash: [4, 4]))
            }
            .frame(height: 80)
            .background(SpiralColors.bg)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            paramSlider("MESOR",     value: $demoMesor,     range: 0.2...0.8,  format: "%.2f")
            paramSlider("Amplitude", value: $demoAmplitude, range: 0.05...0.5, format: "%.2f")
            paramSlider("Acrophase", value: $demoAcrophase, range: 8...20,     format: "%.0fh")

            if !records.isEmpty {
                let last = records.last!
                Divider().background(SpiralColors.border)
                Text("Your latest: MESOR \(String(format: "%.2f", last.cosinor.mesor)) · Amp \(String(format: "%.2f", last.cosinor.amplitude)) · Acrophase \(SleepStatistics.formatHour(last.cosinor.acrophase))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }
        }
    }

    private func paramSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
                .frame(width: 68, alignment: .leading)
            Slider(value: value, in: range).tint(SpiralColors.accent)
            Text(String(format: format, value.wrappedValue))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - PRC Explainer

private struct PRCExplainerCard: View {
    @State private var expanded = false
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        LearnCard(
            icon: "clock.arrow.2.circlepath",
            iconColor: SpiralColors.lightSleep,
            title: String(localized: "learn.prc.title", bundle: bundle),
            expanded: $expanded
        ) {
            learnText(String(localized: "learn.prc.body", bundle: bundle))
            PRCChartView()
        }
    }
}

// MARK: - Sleep Hygiene

private struct SleepHygieneCard: View {
    let analysis: AnalysisResult
    @State private var expanded = true
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        LearnCard(
            icon: "checkmark.seal.fill",
            iconColor: SpiralColors.good,
            title: String(localized: "learn.tips.title", bundle: bundle),
            expanded: $expanded
        ) {
            if analysis.recommendations.isEmpty {
                Text(String(localized: "learn.tips.noData", bundle: bundle))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
            } else {
                ForEach(analysis.recommendations) { rec in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(rec.priority == 1 ? SpiralColors.poor : rec.priority == 2 ? SpiralColors.moderate : SpiralColors.good)
                            .frame(width: 6, height: 6)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rec.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(SpiralColors.text)
                            Text(rec.text).font(.system(size: 10)).foregroundStyle(SpiralColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Study Sources

private struct StudySourcesCard: View {
    @State private var expanded = false
    @Environment(\.languageBundle) private var bundle

    private let sources: [(String, String, String)] = [
        ("Czeisler et al., 1999",       "Science",              "Human circadian period is ~24.18h on average. Morning light is the primary entraining signal."),
        ("Roenneberg et al., 2007",     "Current Biology",      "Social jetlag — the misalignment between biological and social clock — affects >65% of the population."),
        ("Walker, 2017",                "Why We Sleep",         "Comprehensive review of sleep science: memory consolidation, immune function, emotional regulation."),
        ("Khalsa et al., 2003",         "J. Physiology",        "Phase response curve for bright light in humans: largest advances in early morning, delays in evening."),
        ("Lewy et al., 2006",           "PNAS",                 "Melatonin phase-shifts the human circadian clock. 0.5mg is as effective as higher doses."),
        ("Phillips et al., 2019",       "Science Advances",     "Mathematical model linking sleep homeostasis and circadian rhythm accurately predicts sleep timing."),
        ("Wright et al., 2013",         "Current Biology",      "One week of camping without artificial light naturalizes circadian rhythms to solar time."),
    ]

    var body: some View {
        LearnCard(
            icon: "books.vertical.fill",
            iconColor: SpiralColors.accentDim,
            title: String(localized: "learn.sources.title", bundle: bundle),
            expanded: $expanded
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(sources, id: \.0) { source in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(source.0)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                            Text("·")
                                .foregroundStyle(SpiralColors.muted)
                            Text(source.1)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                        }
                        Text(source.2)
                            .font(.system(size: 10))
                            .foregroundStyle(SpiralColors.muted)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if source.0 != sources.last!.0 {
                        Divider().background(SpiralColors.border.opacity(0.5))
                    }
                }
            }
        }
    }
}

// MARK: - Reusable card container

private struct LearnCard<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(iconColor)
                        .frame(width: 20)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11))
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                content()
            }
        }
        .panelStyle()
    }
}

// MARK: - Helpers

private func learnText(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 11))
        .foregroundStyle(SpiralColors.muted)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
}
