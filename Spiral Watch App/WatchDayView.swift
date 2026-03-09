import SwiftUI
import SpiralKit

/// Today's sleep summary on the watch.
struct WatchDayView: View {

    @Environment(WatchStore.self) private var store

    private var today: SleepRecord? { store.records.last }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                if let record = today {
                    // Bedtime / wakeup
                    VStack(spacing: 4) {
                        timeRow(icon: "moon.fill",
                                label: "Bedtime",
                                value: formatHour(record.bedtimeHour),
                                color: Color(hex: "#6e3fa0"))
                        timeRow(icon: "sun.max.fill",
                                label: "Wakeup",
                                value: formatHour(record.wakeupHour),
                                color: Color(hex: "#f5c842"))
                        timeRow(icon: "clock.fill",
                                label: "Duration",
                                value: String(format: "%.1fh", record.sleepDuration),
                                color: Color(hex: "#5bffa8"))
                    }

                    Divider().background(Color(hex: "#1a1f2d"))

                    // Phase bar
                    PhaseBarWatch(phases: record.phases)
                        .frame(height: 12)

                    // Cosinor
                    HStack {
                        Text("R²")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Color(hex: "#555566"))
                        Spacer()
                        Text(String(format: "%.2f", record.cosinor.r2))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color(hex: "#c8cdd8"))
                    }
                } else {
                    Text("No sleep data yet")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(hex: "#555566"))
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Color(hex: "#0c0e14"))
        .navigationTitle("Today")
    }

    private func timeRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(color)
                .frame(width: 12)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color(hex: "#555566"))
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(hex: "#c8cdd8"))
        }
    }

    private func formatHour(_ h: Double) -> String {
        let h24 = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        return String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
    }
}

/// Compact phase bar for the watch.
struct PhaseBarWatch: View {
    let phases: [PhaseInterval]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                guard !phases.isEmpty else { return }
                let totalSpan = phases.reduce(0.0) { $0 + ($1.endHour - $1.startHour) }
                guard totalSpan > 0 else { return }
                var x = 0.0
                for phase in phases {
                    let w = (phase.endHour - phase.startHour) / totalSpan * size.width
                    let rect = CGRect(x: x, y: 0, width: max(w, 1), height: size.height)
                    let color = Color(hex: phase.phase.hexColor)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color))
                    x += w
                }
            }
        }
    }
}
