import SwiftUI
import SpiralKit

/// Sheet presenting the rhythm state, prediction, stats row, and rephase controls
/// extracted from SpiralTab's previous inline cards.
struct SpiralHomeStatsSheet: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(\.dismiss) private var dismiss
    @Binding var showConsistencyDetail: Bool
    @Binding var showRephaseEditor: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    rhythmStateCard
                    if store.predictionEnabled, let pred = store.latestPrediction {
                        predictionCard(pred)
                    }
                    rephasePill
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(SpiralColors.bg)
            .navigationTitle(loc("spiral.stats.rhythm"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }

    // MARK: - Rhythm State Card

    private var rhythmStateCard: some View {
        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showConsistencyDetail = true
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(SpiralColors.border, lineWidth: 3)
                        .frame(width: 52, height: 52)
                    if let c = store.analysis.consistency {
                        Circle()
                            .trim(from: 0, to: CGFloat(c.score) / 100)
                            .stroke(Color(hex: c.label.hexColor),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                        Text("\(c.score)")
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(Color(hex: c.label.hexColor))
                    } else {
                        Text("--")
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(rhythmStateHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(rhythmStateSubtitle)
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
            }
            .padding(14)
            .liquidGlass(cornerRadius: 20)
        }
        .buttonStyle(.plain)
    }

    private var rhythmStateHeadline: String {
        guard let c = store.analysis.consistency else {
            return loc("spiral.rhythm.noData")
        }
        switch c.label {
        case .veryStable:   return loc("spiral.rhythm.veryStable")
        case .stable:       return loc("spiral.rhythm.stable")
        case .variable:     return loc("spiral.rhythm.variable")
        case .disorganized: return loc("spiral.rhythm.disorganized")
        case .insufficient: return loc("spiral.rhythm.insufficient")
        }
    }

    private var rhythmStateSubtitle: String {
        let stats = store.analysis.stats
        guard let c = store.analysis.consistency else {
            return loc("spiral.rhythm.subtitle.noData")
        }
        if !c.globalShiftDays.isEmpty {
            let n = c.globalShiftDays.count
            let plural = n > 1 ? "s" : ""
            return String(format: loc("spiral.rhythm.subtitle.shift"), n, plural)
        }
        if stats.socialJetlag > 60 {
            let formatted = formatJetlag(stats.socialJetlag)
            return String(format: loc("spiral.rhythm.subtitle.jetlag"), formatted)
        }
        let bedStd = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if bedStd > 1.0 {
            return String(format: loc("spiral.rhythm.subtitle.variability"), bedStd)
        }
        if c.deltaVsPreviousWeek.map({ $0 >= 2 }) == true {
            return loc("spiral.rhythm.subtitle.improving")
        }
        let localizedLabel = String(localized: String.LocalizationValue(c.label.localizationKey))
        return String(format: loc("spiral.rhythm.subtitle.stable"),
                      c.nightsUsed, localizedLabel.lowercased())
    }

    // MARK: - Prediction Card

    private func predictionCard(_ pred: PredictionOutput) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("prediction.card.title"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)

            Text("\(formatClockHour(pred.predictedBedtimeHour))  →  \(formatClockHour(pred.predictedWakeHour))")
                .font(.title2.weight(.bold).monospaced())
                .foregroundStyle(SpiralColors.text)

            HStack(spacing: 8) {
                Text(String(format: "~%.1fh", pred.predictedDuration))
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                Text("·")
                    .foregroundStyle(SpiralColors.subtle)
                Text(confidenceText(pred.confidence))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(confidenceColor(pred.confidence))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .liquidGlass(cornerRadius: 20)
    }

    private func confidenceText(_ c: PredictionConfidence) -> String {
        switch c {
        case .high:   return loc("prediction.confidence.high")
        case .medium: return loc("prediction.confidence.medium")
        case .low:    return loc("prediction.confidence.low")
        }
    }

    private func confidenceColor(_ c: PredictionConfidence) -> Color {
        switch c {
        case .high:   return SpiralColors.good
        case .medium: return SpiralColors.moderate
        case .low:    return SpiralColors.poor
        }
    }

    // MARK: - Human Stats Row

    private var humanStatsRow: some View {
        let s = store.analysis.stats
        let durationVal  = s.meanSleepDuration > 0 ? String(format: "%.1fh", s.meanSleepDuration) : "--"
        let driftVal     = driftValue(s)
        let stabilityVal = s.rhythmStability > 0 ? String(format: "%.0f%%", s.rhythmStability * 100) : "--"

        return HStack(spacing: 0) {
            compactStat(icon: "bed.double.fill", value: durationVal, color: durationColor(s.meanSleepDuration))
            Spacer()
            compactStat(icon: "waveform.path.ecg", value: driftVal, color: driftColor(s.stdBedtime > 0 ? s.stdBedtime : s.stdAcrophase))
            Spacer()
            compactStat(icon: "metronome.fill", value: stabilityVal, color: stabilityColor(s.rhythmStability))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .liquidGlass(cornerRadius: 14)
    }

    private func compactStat(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(color)
        }
    }

    // MARK: - Rephase Pill

    @ViewBuilder
    private var rephasePill: some View {
        let plan = store.rephasePlan
        let meanAcrophase = store.analysis.stats.meanAcrophase

        Button {
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                showRephaseEditor = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: plan.isEnabled ? "target" : "scope")
                    .font(.body)
                    .foregroundStyle(plan.isEnabled ? SpiralColors.awakeSleep : SpiralColors.muted)
                if plan.isEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(String(format: loc("rephase.spiral.wake"),
                                        RephaseCalculator.formattedTargetWake(plan)))
                                .font(.footnote.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.awakeSleep)
                            Text("·")
                                .foregroundStyle(SpiralColors.muted)
                            Text(RephaseCalculator.delayString(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.caption.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                        }
                        if meanAcrophase > 0 {
                            Text(RephaseCalculator.todayActionText(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                } else {
                    Text(loc("spiral.rephase.define"))
                        .font(.footnote)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, plan.isEnabled ? 10 : 8)
            .liquidGlass(cornerRadius: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func formatClockHour(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = ((total / 60) % 24 + 24) % 24
        let mm = abs(total % 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    private func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60; let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func driftValue(_ s: SleepStats) -> String {
        let v = s.stdBedtime > 0 ? s.stdBedtime : s.stdAcrophase
        if v <= 0 { return "--" }
        let mins = v * 60
        return mins < 60 ? String(format: "±%.0f min", mins) : String(format: "±%.1fh", v)
    }

    private func driftColor(_ std: Double) -> Color {
        if std <= 0  { return SpiralColors.muted }
        if std < 0.5 { return SpiralColors.good }
        if std < 1.0 { return SpiralColors.moderate }
        return SpiralColors.poor
    }

    private func durationColor(_ h: Double) -> Color {
        if h >= 7 && h <= 9 { return SpiralColors.good }
        if h >= 6 { return SpiralColors.moderate }
        if h <= 0 { return SpiralColors.muted }
        return SpiralColors.poor
    }

    private func stabilityColor(_ v: Double) -> Color {
        if v >= 0.75 { return SpiralColors.good }
        if v >= 0.5  { return SpiralColors.moderate }
        if v <= 0    { return SpiralColors.muted }
        return SpiralColors.poor
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
