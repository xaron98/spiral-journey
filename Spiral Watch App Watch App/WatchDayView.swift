import SwiftUI
import SpiralKit

/// Today's sleep summary: bedtime, wakeup, duration, phase bar.
struct WatchDayView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private var today: SleepRecord? { store.records.last }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let record = today {
                    timeRow(icon: "moon.fill",    label: String(localized: "watch.day.bedtime",  bundle: bundle),  value: formatHour(record.bedtimeHour),  color: SpiralColors.sleep)
                    timeRow(icon: "sun.max.fill", label: String(localized: "watch.day.wakeup",   bundle: bundle),   value: formatHour(record.wakeupHour),   color: SpiralColors.wake)
                    timeRow(icon: "clock.fill",   label: String(localized: "watch.day.duration", bundle: bundle), value: String(format: "%.1fh", record.sleepDuration), color: SpiralColors.accent)

                    Divider().background(SpiralColors.border)

                    // Phase bar
                    PhaseBarWatch(phases: record.phases).frame(height: 10)

                    // Phase legend (compact)
                    HStack(spacing: 6) {
                        ForEach(SleepPhase.allCases, id: \.self) { phase in
                            HStack(spacing: 3) {
                                Circle().fill(Color(hex: phase.hexColor)).frame(width: 5, height: 5)
                                Text(phase.rawValue.prefix(1).uppercased())
                                    .font(.system(size: 7, design: .monospaced))
                                    .foregroundStyle(SpiralColors.muted)
                            }
                        }
                    }

                    Divider().background(SpiralColors.border)

                    // Cosinor R²
                    HStack {
                        Text("R²")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text(String(format: "%.2f", record.cosinor.r2))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                } else {
                    Text(String(localized: "watch.day.noData", bundle: bundle))
                        .font(.system(size: 11))
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding(.horizontal, 6)
        }
        .background(SpiralColors.bg)
        .navigationTitle(String(localized: "watch.today.title", bundle: bundle))
    }

    private func timeRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 11)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
        }
    }

    private func formatHour(_ h: Double) -> String {
        let h24 = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
    }
}

/// Compact horizontal phase bar for watchOS.
struct PhaseBarWatch: View {
    let phases: [PhaseInterval]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !phases.isEmpty else { return }
                let total = Double(phases.count)
                guard total > 0 else { return }
                let stepWidth = size.width / total
                for (i, phase) in phases.enumerated() {
                    let rect = CGRect(x: Double(i) * stepWidth, y: 0,
                                     width: stepWidth + 0.5, height: size.height)
                    context.fill(Rectangle().path(in: rect),
                                 with: .color(Color(hex: phase.phase.hexColor)))
                }
            }
        }
    }
}
