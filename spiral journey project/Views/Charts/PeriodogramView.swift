import SwiftUI
import Charts
import SpiralKit

/// Lomb-Scargle periodogram chart with signal picker.
///
/// Shows the power spectrum for a selected biological signal, highlighting
/// significant peaks at known periods (circadian, weekly, biweekly, menstrual).
struct PeriodogramView: View {

    let periodogramResults: [LombScargle.PeriodogramResult]?
    let healthProfiles: [DayHealthProfile]
    let recordCount: Int

    @Environment(\.languageBundle) private var bundle
    @State private var selectedSignal: LombScargle.Signal = .sleepMidpoint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "periodogram.title", bundle: bundle))

            if recordCount < 14 {
                insufficientDataView
            } else {
                signalPicker
                if let res = result(for: selectedSignal), !res.isEmpty {
                    chartView(res)
                    if !res.peaks.isEmpty {
                        peakList(res)
                    }
                    insightText(res)
                } else {
                    noDataForSignalView
                }
            }
        }
        .glassPanel()
    }

    // MARK: - Signal Picker

    private var signalPicker: some View {
        Picker(String(localized: "periodogram.signal", bundle: bundle), selection: $selectedSignal) {
            ForEach(availableSignals, id: \.self) { signal in
                Text(signalLabel(signal)).tag(signal)
            }
        }
        .pickerStyle(.menu)
        .tint(SpiralColors.accent)
    }

    // MARK: - Chart

    private func chartView(_ res: LombScargle.PeriodogramResult) -> some View {
        // Scale Y to whichever is larger: data or threshold, so the dashed line is always visible
        let dataMax = res.power.max() ?? 1
        let yMax = max(dataMax, res.significanceThreshold) * 1.1
        let chartData = zip(res.periods, res.power).map { (period: $0, power: $1) }

        return VStack(spacing: 4) {
        Chart {
            // Area fill
            ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                AreaMark(
                    x: .value("Period", point.period),
                    y: .value("Power", point.power)
                )
                .foregroundStyle(SpiralColors.accent.opacity(0.15))
            }

            // Line on top
            ForEach(Array(chartData.enumerated()), id: \.offset) { _, point in
                LineMark(
                    x: .value("Period", point.period),
                    y: .value("Power", point.power)
                )
                .foregroundStyle(SpiralColors.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            // Significance threshold (dashed line, no label to avoid clipping)
            RuleMark(y: .value("Threshold", res.significanceThreshold))
                .foregroundStyle(.red.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

            // Significant peaks
            ForEach(Array(res.peaks.enumerated()), id: \.offset) { _, peak in
                PointMark(
                    x: .value("Period", peak.period),
                    y: .value("Power", peak.power)
                )
                .foregroundStyle(.orange)
                .symbolSize(40)
            }
        }
        .chartXScale(type: .log)
        .chartXAxis {
            let maxP = res.periods.last ?? 720
            let ticks = [12.0, 24.0, 168.0, 336.0, 672.0].filter { $0 <= maxP * 1.1 }
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(axisLabel(for: v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYScale(domain: 0...yMax)
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
            }
        }
        .frame(height: 180)

        // Mini legend
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(.orange).frame(width: 6, height: 6)
                Text(String(localized: "periodogram.legend.peaks", bundle: bundle))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
            HStack(spacing: 4) {
                Rectangle()
                    .fill(.red.opacity(0.4))
                    .frame(width: 16, height: 1)
                    .overlay {
                        Rectangle()
                            .stroke(.red.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            .frame(width: 16, height: 1)
                    }
                Text(String(localized: "periodogram.legend.threshold", bundle: bundle))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        } // VStack
    }

    // MARK: - Peak List

    private func peakList(_ res: LombScargle.PeriodogramResult) -> some View {
        let maxPeakPower = res.peaks.map(\.power).max() ?? 1

        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(res.peaks.enumerated()), id: \.offset) { _, peak in
                HStack(spacing: 8) {
                    Circle()
                        .fill(peakColor(peak))
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            if let label = peak.label {
                                Text(peakLabelText(label))
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(SpiralColors.text)
                                Text("--")
                                    .font(.caption2)
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Text(formatPeriod(peak.period))
                                .font(.caption.monospaced())
                                .foregroundStyle(SpiralColors.text)
                        }
                    }

                    Spacer()

                    // Power bar
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(peakColor(peak))
                            .frame(width: geo.size.width * CGFloat(peak.power / maxPeakPower))
                    }
                    .frame(width: 60, height: 6)
                }
            }
        }
    }

    // MARK: - Insight Text

    private func insightText(_ res: LombScargle.PeriodogramResult) -> some View {
        Text(generateInsight(res))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }

    // MARK: - Empty States

    private var insufficientDataView: some View {
        VStack(spacing: 8) {
            Text(String(localized: "periodogram.insufficientData", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
            Text("\(recordCount)/14")
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.accent)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }

    private var noDataForSignalView: some View {
        Text(String(localized: "periodogram.noDataForSignal", bundle: bundle))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func result(for signal: LombScargle.Signal) -> LombScargle.PeriodogramResult? {
        periodogramResults?.first { $0.signal == signal }
    }

    private var availableSignals: [LombScargle.Signal] {
        var signals: [LombScargle.Signal] = [.sleepMidpoint, .sleepDuration, .cosinorAmplitude]
        if result(for: .restingHR) != nil { signals.append(.restingHR) }
        if result(for: .nocturnalHRV) != nil { signals.append(.nocturnalHRV) }
        return signals
    }

    private func signalLabel(_ signal: LombScargle.Signal) -> String {
        switch signal {
        case .sleepMidpoint:     return String(localized: "periodogram.signal.midpoint",  bundle: bundle)
        case .sleepDuration:     return String(localized: "periodogram.signal.duration",  bundle: bundle)
        case .cosinorAmplitude:  return String(localized: "periodogram.signal.amplitude", bundle: bundle)
        case .restingHR:         return String(localized: "periodogram.signal.restingHR", bundle: bundle)
        case .nocturnalHRV:      return String(localized: "periodogram.signal.hrv",       bundle: bundle)
        }
    }

    private func peakLabelText(_ label: LombScargle.PeakLabel) -> String {
        switch label {
        case .circadian: return String(localized: "periodogram.peak.circadian", bundle: bundle)
        case .weekly:    return String(localized: "periodogram.peak.weekly",    bundle: bundle)
        case .biweekly:  return String(localized: "periodogram.peak.biweekly", bundle: bundle)
        case .menstrual: return String(localized: "periodogram.peak.menstrual", bundle: bundle)
        }
    }

    private func peakColor(_ peak: LombScargle.Peak) -> Color {
        guard let label = peak.label else { return .orange }
        switch label {
        case .circadian: return SpiralColors.good
        case .weekly:    return SpiralColors.accent
        case .biweekly:  return SpiralColors.moderate
        case .menstrual: return .pink
        }
    }

    private func formatPeriod(_ hours: Double) -> String {
        if hours < 48 {
            return String(format: "%.0fh", hours)
        } else {
            let days = hours / 24.0
            return String(format: "%.1f %@", days, String(localized: "periodogram.days", bundle: bundle))
        }
    }

    private func axisLabel(for period: Double) -> String {
        switch period {
        case 12:  return "12h"
        case 24:  return "24h"
        case 168: return "7d"
        case 336: return "14d"
        case 672: return "28d"
        default:  return "\(Int(period))h"
        }
    }

    // MARK: - Insight Generation

    private func generateInsight(_ res: LombScargle.PeriodogramResult) -> String {
        guard let strongest = res.peaks.first else {
            return String(localized: "periodogram.insight.noPeaks", bundle: bundle)
        }

        let signal = res.signal
        let label = strongest.label

        // Midpoint insights
        switch (signal, label) {
        case (.sleepMidpoint, .circadian):
            return String(localized: "periodogram.insight.midpoint.circadian", bundle: bundle)
        case (.sleepMidpoint, .weekly):
            return String(localized: "periodogram.insight.midpoint.weekly", bundle: bundle)

        // Duration insights
        case (.sleepDuration, .circadian):
            return String(localized: "periodogram.insight.duration.circadian", bundle: bundle)
        case (.sleepDuration, .weekly):
            return String(localized: "periodogram.insight.duration.weekly", bundle: bundle)
        case (.sleepDuration, .menstrual):
            let hasMenstrualData = healthProfiles.filter { ($0.menstrualFlow ?? 0) > 0 }.count >= 3
            if hasMenstrualData {
                return String(localized: "periodogram.insight.duration.menstrual.withData", bundle: bundle)
            }
            return String(localized: "periodogram.insight.duration.menstrual.noData", bundle: bundle)

        // Amplitude insights
        case (.cosinorAmplitude, .weekly):
            return String(localized: "periodogram.insight.amplitude.weekly", bundle: bundle)
        case (.cosinorAmplitude, .biweekly):
            return String(localized: "periodogram.insight.amplitude.biweekly", bundle: bundle)

        // HR insights
        case (.restingHR, .weekly):
            return String(localized: "periodogram.insight.hr.weekly", bundle: bundle)
        case (.restingHR, .menstrual):
            return String(localized: "periodogram.insight.hr.menstrual", bundle: bundle)

        // HRV insights
        case (.nocturnalHRV, .weekly):
            return String(localized: "periodogram.insight.hrv.weekly", bundle: bundle)
        case (.nocturnalHRV, .menstrual):
            return String(localized: "periodogram.insight.hrv.menstrual", bundle: bundle)

        default:
            let periodStr = formatPeriod(strongest.period)
            return String(format: String(localized: "periodogram.insight.generic", bundle: bundle), periodStr)
        }
    }
}
