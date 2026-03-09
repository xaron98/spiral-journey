import SwiftUI
import SpiralKit

/// Per-day sleep breakdown panel.
struct DayDetailView: View {

    let record: SleepRecord
    let dayLabel: String
    @Environment(\.languageBundle) private var bundle

    private var phaseCounts: [SleepPhase: Int] {
        Dictionary(grouping: record.phases, by: \.phase).mapValues(\.count)
    }

    private var totalPhases: Double {
        Double(record.phases.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelTitle(title: dayLabel)

            // Sleep timing row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "day.bedtime", bundle: bundle)).font(.system(size: 9, design: .monospaced)).foregroundStyle(SpiralColors.muted)
                    Text(SleepStatistics.formatHour(record.bedtimeHour))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "day.wakeup", bundle: bundle)).font(.system(size: 9, design: .monospaced)).foregroundStyle(SpiralColors.muted)
                    Text(SleepStatistics.formatHour(record.wakeupHour))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "day.duration", bundle: bundle)).font(.system(size: 9, design: .monospaced)).foregroundStyle(SpiralColors.muted)
                    Text(String(format: "%.1fh", record.sleepDuration))
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                }
            }

            // Phase architecture bar
            if !record.phases.isEmpty {
                PhaseBar(phases: record.phases)
                    .frame(height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Phase distribution
            HStack(spacing: 8) {
                ForEach(SleepPhase.allCases, id: \.self) { phase in
                    if let count = phaseCounts[phase] {
                        let pct = totalPhases > 0 ? Double(count) / totalPhases * 100 : 0
                        HStack(spacing: 4) {
                            Circle().fill(phaseColor(phase)).frame(width: 6, height: 6)
                            Text(String(format: "%.0f%%", pct))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                }
            }

            Divider().background(SpiralColors.border)

            // Cosinor parameters
            HStack(spacing: 12) {
                cosinorStat("Acrophase", value: SleepStatistics.formatHour(record.cosinor.acrophase))
                cosinorStat("Amplitude", value: String(format: "%.2f", record.cosinor.amplitude))
                cosinorStat("MESOR",     value: String(format: "%.2f", record.cosinor.mesor))
                cosinorStat("R²",        value: String(format: "%.2f", record.cosinor.r2))
            }
        }
        .panelStyle()
    }

    private func cosinorStat(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.accent)
        }
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return SpiralColors.deepSleep
        case .rem:   return SpiralColors.remSleep
        case .light: return SpiralColors.lightSleep
        case .awake: return SpiralColors.awakeSleep
        }
    }
}

private struct PhaseBar: View {
    let phases: [PhaseInterval]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let total = Double(phases.count)
                guard total > 0 else { return }
                let stepWidth = size.width / total
                for (i, phase) in phases.enumerated() {
                    let color: Color
                    switch phase.phase {
                    case .deep:  color = SpiralColors.deepSleep
                    case .rem:   color = SpiralColors.remSleep
                    case .light: color = SpiralColors.lightSleep
                    case .awake: color = SpiralColors.awakeSleep
                    }
                    let rect = CGRect(x: Double(i) * stepWidth, y: 0, width: stepWidth + 0.5, height: size.height)
                    context.fill(Rectangle().path(in: rect), with: .color(color))
                }
            }
        }
    }
}
