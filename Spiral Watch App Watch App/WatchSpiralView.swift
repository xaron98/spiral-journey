import SwiftUI
import SpiralKit

/// Compact spiral with Digital Crown cursor and sleep/wake marking.
///
/// - Digital Crown  → moves cursor along the spiral (15-min steps)
/// - Button (top-right) → first tap = mark sleep start, second tap = mark wake → episode saved
/// The spiral always renders (even when empty) so the user can start logging from day 1.
struct WatchSpiralView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    // Crown: 0.0 … Double(maxDays * 24) absolute hours
    @State private var crownAbsHour: Double = 0
    @State private var markingState: MarkingState = .idle
    @State private var sleepStartHour: Double? = nil
    @State private var flashConfirm = false
    @FocusState private var crownFocused: Bool
    // Grows from 1 → maxDays as crown moves; frozen once we have real records
    @State private var visibleDays: Int = 1
    // True only when data came from iPhone/HealthKit — draw everything with no clip.
    @State private var dataFromPhone: Bool = false
    // Highest absHour the crown has ever reached — phases never draw beyond this for manual data.
    @State private var maxEverAbsHour: Double = 0

    enum MarkingState { case idle, sleeping }

    private let maxDays = 7

    private var absHour: Double { max(0, crownAbsHour) }
    private var cursorDay:  Int    { Int(absHour / 24) }
    private var cursorHour: Double { absHour.truncatingRemainder(dividingBy: 24) }

    private var displayDays: Int {
        // Use the number of days that actually have sleep data, capped by visibleDays
        // so the spiral doesn't suddenly expand after logging the first episode.
        let daysWithData = store.recentRecords.filter { $0.sleepDuration > 0 }.count
        if daysWithData == 0 {
            return visibleDays
        }
        // Show enough rings to cover all data, but respect what the user has scrolled to
        return max(daysWithData, visibleDays)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                SpiralColors.bg.ignoresSafeArea()

                // ── Spiral Canvas ──────────────────────────────────────────
                // Pass all dynamic values as explicit parameters so SwiftUI
                // re-evaluates the canvas whenever crown or marking state changes.
                SpiralCanvas(
                    records: store.recentRecords,
                    displayDays: displayDays,
                    maxDays: visibleDays,
                    absHour: absHour,
                    // nil = draw everything (iPhone/HK data); value = clip phases at that hour (manual)
                    phaseLimit: dataFromPhone ? nil : maxEverAbsHour,
                    cursorDay: cursorDay,
                    cursorHour: cursorHour,
                    cursorColor: cursorColor,
                    sleepStartHour: sleepStartHour
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())

                // ── Mark button (top-right) ────────────────────────────────
                Button { handleMark() } label: {
                    ZStack {
                        Circle()
                            .fill(markingState == .sleeping
                                  ? SpiralColors.sleep.opacity(0.9)
                                  : SpiralColors.surface.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .shadow(color: markingState == .sleeping
                                    ? SpiralColors.sleep.opacity(0.5) : .clear,
                                    radius: 6)
                        Image(systemName: markingState == .sleeping ? "moon.fill" : "moon")
                            .font(.system(size: 12))
                            .foregroundStyle(markingState == .sleeping
                                             ? .white
                                             : SpiralColors.muted)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.trailing, 4)

                // ── Confirm flash ──────────────────────────────────────────
                if flashConfirm {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(SpiralColors.accent)
                            Text(String(localized: "watch.spiral.saved", bundle: bundle))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        .padding(.bottom, 8)
                    }
                    .transition(.opacity)
                }
            }
        }
        // Digital Crown — unbounded so the user can keep scrolling indefinitely.
        // We clamp absHour manually in the computed property above.
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $crownAbsHour,
            from: 0,
            through: 365 * 24,   // ~1 year — effectively no upper limit
            by: 0.25,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        // Re-acquire crown focus after any tap (e.g. the mark button)
        .onTapGesture { crownFocused = true }
        .onChange(of: crownAbsHour) { _, newVal in
            if newVal < 0 { crownAbsHour = 0 }
            let clamped = max(0, newVal)
            // Track the furthest point the crown has reached
            if clamped > maxEverAbsHour { maxEverAbsHour = clamped }
            // Grow the visible spiral as crown moves into new days
            let daysWithData = store.recentRecords.filter { $0.sleepDuration > 0 }.count
            if daysWithData == 0 {
                let crownDay = Int(clamped / 24) + 1
                if crownDay >= visibleDays { visibleDays = crownDay + 1 }
            } else {
                visibleDays = max(visibleDays, daysWithData)
            }
        }
        .navigationTitle("")
        .onAppear {
            if store.isEmpty {
                crownAbsHour = 0
                visibleDays = 1
                dataFromPhone = false
            } else {
                crownAbsHour = currentAbsHour()
                // Data present at launch = came from iPhone/HealthKit → draw backbone fully
                let daysWithData = store.recentRecords.filter { $0.sleepDuration > 0 }.count
                visibleDays = max(daysWithData, 1)
                dataFromPhone = true
            }
            crownFocused = true
        }
    }

    // MARK: - Mark logic

    private func handleMark() {
        switch markingState {
        case .idle:
            sleepStartHour = absHour
            withAnimation { markingState = .sleeping }

        case .sleeping:
            if let start = sleepStartHour {
                let end = absHour > start + 0.25 ? absHour : start + 0.5
                let episode = SleepEpisode(start: start, end: end, source: .manual)
                store.addEpisode(episode)
                // Extend the phase limit to cover the full saved episode
                if end > maxEverAbsHour { maxEverAbsHour = end }
                sleepStartHour = nil
                withAnimation { markingState = .idle }
                showConfirmFlash()
            }
        }
    }

    private func showConfirmFlash() {
        withAnimation(.easeIn(duration: 0.2)) { flashConfirm = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.3)) { flashConfirm = false }
        }
    }

    // MARK: - Helpers

    private var cursorColor: Color {
        markingState == .sleeping ? SpiralColors.sleep : SpiralColors.accent
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h) % 24
        let mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    /// Position cursor near current time within the 7-day window.
    private func currentAbsHour() -> Double {
        let cal = Calendar.current
        let now = Date()
        let windowStart = cal.date(byAdding: .day, value: -(maxDays - 1), to: cal.startOfDay(for: now)) ?? now
        let dayOffset = cal.dateComponents([.day], from: windowStart, to: now).day ?? 0
        let clamped = max(0, min(dayOffset, maxDays - 1))
        let hour = Double(cal.component(.hour, from: now)) + Double(cal.component(.minute, from: now)) / 60.0
        return Double(clamped) * 24.0 + hour
    }
}

// MARK: - SpiralCanvas

/// Separate view so SwiftUI tracks changes to absHour/sleepStartHour and re-renders.
/// Renders with the same perspective projection as the iPhone SpiralView.
private struct SpiralCanvas: View {
    let records: [SleepRecord]
    let displayDays: Int
    let maxDays: Int
    let absHour: Double
    /// nil = draw all phases (iPhone/HK data); value = clip phases at that absolute hour (manual data).
    let phaseLimit: Double?
    let cursorDay: Int
    let cursorHour: Double
    let cursorColor: Color
    let sleepStartHour: Double?
    /// 3D depth multiplier — same meaning as iPhone depthScale. Default 1.5.
    var depthScale: Double = 1.5

    var body: some View {
        Canvas { context, size in
            let cursorTurns = absHour / 24.0
            let scaleDays   = max(1, Int(ceil(cursorTurns)))
            let geometry = SpiralGeometry(
                totalDays: scaleDays,
                maxDays: maxDays,
                width: size.width, height: size.height,
                startRadius: 10, spiralType: .archimedean
            )

            // ── Perspective projection ────────────────────────────────────────
            // Matches SpiralView.project() exactly so the cursor aligns with the path.
            let totalT   = max(cursorTurns, 0.5)
            let margin   = 0.35
            let tRef     = totalT + margin
            // visible = show all turns (fully zoomed out on watch)
            let visible  = max(totalT + margin, 1.0 + margin)
            let zStep    = geometry.maxRadius * depthScale
            let focalLen = geometry.maxRadius * 1.2
            let tTarget  = min(visible, tRef)
            let rTarget  = max(geometry.radius(turns: min(tTarget, totalT)), 1.0)
            let wzTarget = (tRef - tTarget) * zStep
            let dzTarget = focalLen * rTarget / geometry.maxRadius
            let camZ     = wzTarget - dzTarget

            func project(turns t: Double) -> CGPoint {
                let day  = Int(t)
                let hr   = (t - Double(day)) * geometry.period
                let flat = geometry.point(day: day, hour: hr)
                let wx   = flat.x - geometry.cx
                let wy   = flat.y - geometry.cy
                let wz   = (tRef - t) * zStep
                let dz   = wz - camZ
                let safeDz = max(dz, focalLen * 0.05)
                let scale  = focalLen / safeDz
                return CGPoint(x: geometry.cx + wx * scale, y: geometry.cy + wy * scale)
            }

            // ── Day rings ─────────────────────────────────────────────────────
            for ring in geometry.dayRings() {
                var p = Path()
                let steps = 48
                for i in 0...steps {
                    let t = Double(ring.day) + Double(i) / Double(steps)
                    let pt = project(turns: t)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath()
                let alpha: Double = ring.isWeekBoundary ? 0.5 : 0.25
                context.stroke(p, with: .color(SpiralColors.border.opacity(alpha)),
                               lineWidth: ring.isWeekBoundary ? 0.8 : 0.4)
            }

            // ── Spiral backbone ───────────────────────────────────────────────
            // nil phaseLimit = iPhone data → draw full backbone; otherwise grow with maxEverAbsHour
            let backboneLimit = phaseLimit == nil ? totalT : (phaseLimit! / 24.0)
            if backboneLimit > 0 {
                var p = Path()
                var d = 0.0
                var first = true
                while d <= backboneLimit {
                    let t = min(d, backboneLimit)
                    let pt = project(turns: t)
                    if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                    if d >= backboneLimit { break }
                    d += 0.04
                }
                context.stroke(p, with: .color(SpiralColors.border.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                context.stroke(p, with: .color(SpiralColors.muted.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

            // ── Sleep arc overlay (mark-start → cursor) ───────────────────────
            if let startHour = sleepStartHour {
                let lo = min(startHour, absHour); let hi = max(startHour, absHour)
                if hi - lo > 0.01 {
                    var p = Path(); var first = true
                    var t = lo
                    while t <= hi {
                        let pt = project(turns: t / 24.0)
                        if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
                        t = min(t + 0.25, hi); if t >= hi { break }
                    }
                    context.stroke(p, with: .color(SpiralColors.sleep.opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    context.stroke(p, with: .color(.white.opacity(0.12)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
                }
            }

            // ── Sleep phase strokes ───────────────────────────────────────────
            let dayAbsLimit: Double? = phaseLimit   // nil = no clip; value = clip at maxEverAbsHour
            for record in records where record.sleepDuration > 0 {
                let phases = record.phases
                guard !phases.isEmpty else { continue }
                var runPhase = phases[0].phase
                var path = Path()
                var started = false
                var clipped = false

                func commitRun() {
                    guard started else { return }
                    let color = phaseColor(runPhase)
                    context.stroke(path, with: .color(color.opacity(0.25)),
                                   style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    context.stroke(path, with: .color(color.opacity(0.9)),
                                   style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    path = Path(); started = false
                }

                for (i, phase) in phases.enumerated() {
                    let phaseAbs = Double(record.day) * 24 + phase.hour
                    if let limit = dayAbsLimit, phaseAbs > limit {
                        clipped = true; commitRun(); break
                    }
                    let t = Double(record.day) + phase.hour / 24.0
                    if phase.phase != runPhase {
                        path.addLine(to: project(turns: t))
                        commitRun(); runPhase = phase.phase
                    }
                    let pt = project(turns: t)
                    if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
                    if i == phases.count - 1 && !clipped {
                        path.addLine(to: project(turns: Double(record.day) + 1.0))
                        commitRun()
                    }
                }
            }

            // ── Cursor dot ────────────────────────────────────────────────────
            let cp = project(turns: absHour / 24.0)
            var glow = Path()
            glow.addEllipse(in: CGRect(x: cp.x-8, y: cp.y-8, width: 16, height: 16))
            context.fill(glow, with: .color(cursorColor.opacity(0.25)))
            var dot = Path()
            dot.addEllipse(in: CGRect(x: cp.x-4, y: cp.y-4, width: 8, height: 8))
            context.fill(dot, with: .color(cursorColor))

            // Time label near cursor
            let timeText = context.resolve(
                Text(formatHour(cursorHour))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(cursorColor))
            context.draw(timeText, at: CGPoint(x: cp.x, y: cp.y - 13))
        }
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h) % 24
        let mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "6e3fa0")
        case .rem:   return Color(hex: "a855f7")
        case .light: return Color(hex: "9b72cc")
        case .awake: return Color(hex: "f5c842")
        }
    }
}
