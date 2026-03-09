import SwiftUI
import SpiralKit

/// Sleep logging screen controlled by the Digital Crown.
/// Workflow: pick BEDTIME → confirm → pick WAKEUP → confirm → episode saved.
struct WatchSleepLogView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    // Digital Crown binding
    @State private var crownValue: Double = 0.0

    // Step 0 = picking bedtime, Step 1 = picking wakeup
    @State private var step: LogStep = .bedtime
    @State private var bedtimeHour: Double = 23.5
    @State private var wakeupHour: Double = 7.5
    @State private var showConfirmation = false

    enum LogStep { case bedtime, wakeup, done }

    // Crown sensitivity: full rotation (1.0) = 12 hours
    private let crownScale = 12.0

    private var currentHour: Double {
        switch step {
        case .bedtime: return normalise(bedtimeHour + crownValue * crownScale)
        case .wakeup:  return normalise(wakeupHour  + crownValue * crownScale)
        case .done:    return 0
        }
    }

    var body: some View {
        ZStack {
            SpiralColors.bg.ignoresSafeArea()

            VStack(spacing: 10) {
                // Step label
                Text(step == .bedtime
                     ? String(localized: "watch.sleep.bedtime", bundle: bundle)
                     : step == .wakeup
                       ? String(localized: "watch.sleep.wakeup", bundle: bundle)
                       : String(localized: "watch.sleep.saved",  bundle: bundle))
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                    .tracking(1.5)

                // Big time display
                if step != .done {
                    Text(formatHour(currentHour))
                        .font(.system(size: 36, weight: .bold, design: .monospaced))
                        .foregroundStyle(step == .bedtime ? SpiralColors.sleep : SpiralColors.wake)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.1), value: currentHour)

                    // Arc showing position on 24h clock
                    ClockArc(hour: currentHour,
                             color: step == .bedtime ? SpiralColors.sleep : SpiralColors.wake)
                        .frame(height: 28)

                    // Confirm button
                    Button {
                        confirmStep()
                    } label: {
                        Text(step == .bedtime
                             ? String(localized: "watch.sleep.setBedtime", bundle: bundle)
                             : String(localized: "watch.sleep.setWakeup",  bundle: bundle))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(step == .bedtime ? SpiralColors.sleep.opacity(0.3) : SpiralColors.wake.opacity(0.3))
                            .foregroundStyle(step == .bedtime ? SpiralColors.sleep.opacity(1.4) : SpiralColors.wake)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                } else {
                    // Confirmation screen
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(SpiralColors.accent)
                        Text(String(localized: "watch.sleep.logged", bundle: bundle))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                        Text("\(formatHour(bedtimeHour)) → \(formatHour(wakeupHour))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    .onAppear {
                        // Auto-reset after 2 seconds
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { step = .bedtime; crownValue = 0 }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
        }
        // Bind Digital Crown
        .focusable()
        .digitalCrownRotation(
            $crownValue,
            from: -6.0, through: 6.0,
            by: 0.25 / crownScale,   // 15-min increments
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .navigationTitle(String(localized: "watch.sleep.logTitle", bundle: bundle))
    }

    // MARK: - Helpers

    private func confirmStep() {
        switch step {
        case .bedtime:
            bedtimeHour = currentHour
            crownValue  = 0
            withAnimation { step = .wakeup }

        case .wakeup:
            wakeupHour = currentHour
            crownValue = 0
            saveEpisode()
            withAnimation { step = .done }

        case .done:
            break
        }
    }

    private func saveEpisode() {
        // Convert clock hours to absolute hours relative to today
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let dayOffset = Double(cal.ordinality(of: .day, in: .era, for: todayStart) ?? 0)

        var absStart = dayOffset * 24 + bedtimeHour
        var absEnd   = dayOffset * 24 + wakeupHour
        // If wakeup is before bedtime, it crossed midnight
        if absEnd <= absStart { absEnd += 24 }

        let episode = SleepEpisode(start: absStart, end: absEnd, source: .manual)
        store.addEpisode(episode)
    }

    private func normalise(_ h: Double) -> Double {
        var h = h.truncatingRemainder(dividingBy: 24)
        if h < 0 { h += 24 }
        return h
    }

    private func formatHour(_ h: Double) -> String {
        let h = normalise(h)
        let hh = Int(h)
        let mm = Int((h - Double(hh)) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }
}

/// Thin arc indicating the current hour position on a 24h circle.
private struct ClockArc: View {
    let hour: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2, cy = h / 2
            let r = min(w, h) / 2 - 2

            Canvas { context, _ in
                // Track ring
                var track = Path()
                track.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                context.stroke(track, with: .color(SpiralColors.border), lineWidth: 2)

                // Filled arc from 0 to current hour
                let fraction = hour / 24.0
                let startAngle = Angle.degrees(-90)
                let endAngle   = Angle.degrees(-90 + fraction * 360)
                var arc = Path()
                arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                           startAngle: startAngle, endAngle: endAngle, clockwise: false)
                context.stroke(arc, with: .color(color),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))

                // Dot at current position
                let angle = (-90 + fraction * 360) * .pi / 180
                let dx = cx + r * cos(angle)
                let dy = cy + r * sin(angle)
                var dot = Path()
                dot.addEllipse(in: CGRect(x: dx - 3, y: dy - 3, width: 6, height: 6))
                context.fill(dot, with: .color(color))
            }
        }
    }
}
