import SwiftUI
import SpiralKit
import WatchKit

/// Spiral view for Apple Watch.
///
/// Flat 2D archimedean spiral — identical to iPhone SpiralView in flat mode.
/// Uses direct (x, y) projection via radius + angle, no perspective.
/// All data always visible at full opacity. No zoom windowing.
///
/// Digital Crown moves the cursor along the spiral path.
/// Finer steps (0.25 h/detent) when marking sleep.
struct WatchSpiralView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    // Crown
    @State private var crownRaw: Double = 0
    @State private var lastCrownRaw: Double = 0

    // Spiral state
    @State private var cursorAbsHour: Double = 0
    @State private var maxReachedTurns: Double = 1.0
    @State private var visibleDays: Double = 4.0
    @State private var storeInitialised = false
    /// True once the user has physically turned the crown.
    /// When false, any new data arriving from iPhone is allowed to re-position the cursor.
    @State private var userHasMovedCrown = false

    // Sleep marking
    @State private var markingState: MarkingState = .idle
    @State private var sleepStartHour: Double? = nil
    @State private var flashConfirm = false

    @FocusState private var crownFocused: Bool
    // Last hour boundary crossed — used to fire a haptic tick once per hour
    @State private var lastHapticHour: Int = -1

    enum MarkingState { case idle, sleeping }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                Color(hex: "0c0e14").ignoresSafeArea().frame(maxWidth: .infinity, maxHeight: .infinity)

                WatchSpiralCanvas(
                    records: store.recentRecords,
                    events: store.events,
                    cursorAbsHour: cursorAbsHour,
                    sleepStartHour: sleepStartHour,
                    markingColor: markingState == .sleeping ? SpiralColors.sleep : SpiralColors.accent,
                    spiralExtentTurns: maxReachedTurns,
                    visibleDays: visibleDays,
                    period: store.period
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                // Mark button — below the system clock (top right)
                // .top 42 leaves room for the watchOS time display (~38pt tall)
                Button { handleMark() } label: {
                    ZStack {
                        Circle()
                            .fill(markingState == .sleeping
                                  ? SpiralColors.sleep.opacity(0.9)
                                  : SpiralColors.surface.opacity(0.9))
                            .frame(width: 28, height: 28)
                            .shadow(color: markingState == .sleeping
                                    ? SpiralColors.sleep.opacity(0.5) : .clear, radius: 6)
                        Image(systemName: markingState == .sleeping ? "moon.fill" : "moon")
                            .font(.system(size: 12))
                            .foregroundStyle(markingState == .sleeping ? .white : SpiralColors.muted)
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 42).padding(.trailing, 8)

                if flashConfirm {
                    VStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SpiralColors.accent)
                            Text(String(localized: "watch.spiral.saved", bundle: bundle))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        .padding(.bottom, 20)
                    }
                    .transition(.opacity)
                }

                // Empty-state overlay — guides the user when no data exists
                if store.isEmpty && markingState == .idle {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "moon.stars")
                            .font(.system(size: 24))
                            .foregroundStyle(SpiralColors.accent.opacity(0.7))
                        Text(String(localized: "watch.spiral.emptyTitle", bundle: bundle))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(SpiralColors.text)
                            .multilineTextAlignment(.center)
                        Text(String(localized: "watch.spiral.emptyHint", bundle: bundle))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }

                // Time label — bottom-left, just inside safe area
                VStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 0) {
                        let hh = Int(cursorAbsHour) % 24
                        let mm = Int((cursorAbsHour - Double(Int(cursorAbsHour))) * 60)
                        Text(String(format: "%02d:%02d", hh, mm))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(markingState == .sleeping ? SpiralColors.sleep : SpiralColors.accent)
                            .allowsHitTesting(false)
                            .padding(.leading, 26)
                            .padding(.bottom, 6)
                        Spacer()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .background(SpiralColors.bg)
        .focusable(true)
        .focused($crownFocused)
        .digitalCrownRotation(
            $crownRaw, from: -100000, through: 100000,
            by: 1.0, sensitivity: .high,
            isContinuous: true, isHapticFeedbackEnabled: false
        )
        .onChange(of: crownRaw) { _, newRaw in
            let delta = newRaw - lastCrownRaw
            lastCrownRaw = newRaw
            moveCursor(delta: delta)
        }
        .navigationTitle("")
        .onAppear { initFromStore(); crownFocused = true }
        .onChange(of: store.records.count) { _, _ in
            handleRecordsChange()
        }
        .onChange(of: store.recentRecords.last?.day) { _, _ in
            // Also re-check when the last day index changes without the count changing
            // (e.g. iPhone sends records with same count but more recent days).
            handleRecordsChange()
        }
    }

    // MARK: - Crown

    private func moveCursor(delta: Double) {
        userHasMovedCrown = true
        let hourDelta = markingState == .sleeping ? delta * 0.25 : delta * 0.5
        let newHour   = cursorAbsHour + hourDelta
        let maxHour   = maxReachedTurns * store.period + 24.0
        cursorAbsHour = max(0, min(newHour, maxHour))
        store.cursorAbsoluteHour = cursorAbsHour

        // Fire a haptic tick each time the cursor crosses an hour boundary
        let currentHour = Int(cursorAbsHour)
        if currentHour != lastHapticHour {
            lastHapticHour = currentHour
            WKInterfaceDevice.current().play(.click)
        }
        let newTurns = cursorAbsHour / store.period
        if newTurns > maxReachedTurns { maxReachedTurns = newTurns }
    }

    // MARK: - Sleep marking

    private func handleMark() {
        switch markingState {
        case .idle:
            sleepStartHour = cursorAbsHour
            withAnimation { markingState = .sleeping }
        case .sleeping:
            if let start = sleepStartHour {
                let end = cursorAbsHour > start + 0.25 ? cursorAbsHour : start + 0.5
                store.addEpisode(SleepEpisode(start: start, end: end, source: .manual))
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

    // MARK: - Init

    private func handleRecordsChange() {
        // Always re-init if the user hasn't manually moved the crown yet.
        // This ensures the cursor is correctly positioned regardless of whether
        // records arrived before or after onAppear, and whether the count changed.
        if !userHasMovedCrown {
            initFromStore()
            return
        }
        // User has moved the crown — only re-init if genuinely new days arrived
        // (iPhone sent more history than we had before) or cursor is still at origin.
        let latestDay = store.recentRecords.map { $0.day }.max() ?? 0
        let latestTurns = Double(latestDay + 1)
        if latestTurns > maxReachedTurns + 0.5 || cursorAbsHour == 0 {
            initFromStore()
        }
    }

    private func initFromStore() {
        guard !store.isEmpty else {
            // No data yet — place the cursor at the current wall-clock time so the
            // spiral backbone and cursor are visible on the outer edge, ready for
            // the user to tap the moon button and start logging sleep.
            let now = store.currentAbsoluteHour
            cursorAbsHour = now
            store.cursorAbsoluteHour = now
            maxReachedTurns = max(1.0, now / store.period)
            storeInitialised = false; return
        }
        // Use the same end-of-data logic as dataEndTurns() so the cursor lands
        // exactly on the visual tip of the drawn sleep arc.
        let sorted = store.recentRecords.sorted { $0.day < $1.day }
        var bestAbsHour = 0.0
        for r in sorted {
            guard r.sleepDuration > 0 || !r.phases.isEmpty else { continue }
            let dayStart = Double(r.day) * 24.0
            let endAbsH: Double
            if let lastSleep = r.phases.last(where: { $0.phase != .awake }) {
                endAbsH = dayStart + lastSleep.hour + 0.25
            } else {
                endAbsH = dayStart + r.wakeupHour
            }
            if endAbsH > bestAbsHour { bestAbsHour = endAbsH }
        }
        guard bestAbsHour > 0 else {
            storeInitialised = false; return
        }
        let endTurns = bestAbsHour / store.period
        cursorAbsHour = bestAbsHour
        store.cursorAbsoluteHour = bestAbsHour
        maxReachedTurns = max(1.0, endTurns)
        crownRaw = 0; lastCrownRaw = 0
        storeInitialised = true
        userHasMovedCrown = false
    }
}

// MARK: - Canvas

/// Flat 2D archimedean spiral canvas for Apple Watch.
///
/// Matches the iPhone SpiralView in archimedean 2D flat mode:
/// - Uses `SpiralGeometry.point()` directly — no perspective projection
/// - All data always visible at full opacity — no windowed fade
/// - Constant line widths — no perspective scaling
/// - Backbone from turn 0 to extentTurns, always visible
private struct WatchSpiralCanvas: View {
    let records: [SleepRecord]
    let events: [CircadianEvent]
    let cursorAbsHour: Double
    let sleepStartHour: Double?
    let markingColor: Color
    let spiralExtentTurns: Double
    let visibleDays: Double
    var period: Double = 24.0

    // MARK: - Flat Geometry (windowed, like iPhone)

    /// Flat archimedean geometry scaled to show a window of `span` turns
    /// centered on the cursor, matching iPhone behavior.
    private struct FlatGeo {
        let cx: Double
        let cy: Double
        let startRadius: Double
        let spacing: Double
        let period: Double
        let renderFrom: Double   // first turn to render
        let renderUpTo: Double   // last turn to render
        let maxTurns: Double

        let turnOffset: Double  // first visible turn maps to startRadius

        init(size: CGSize, cursorTurns: Double, span: Double, extentTurns: Double, period: Double) {
            self.cx = size.width / 2
            self.cy = size.height / 2
            self.period = period

            // Window: span turns behind cursor, 0.5 ahead
            let from = max(cursorTurns - span, 0)
            let upTo = cursorTurns + 0.5
            self.renderFrom = from
            self.renderUpTo = upTo
            self.maxTurns = max(upTo, extentTurns)
            self.turnOffset = from

            // Scale: visible window [from, upTo] maps to [startRadius, outerR]
            let outerR = min(size.width, size.height) / 2 * 0.85
            let inner: Double = 8
            self.startRadius = inner
            let visibleSpan = max(upTo - from, 1)
            self.spacing = max(3.0, (outerR - inner) / visibleSpan)
        }

        func radius(turns t: Double) -> Double {
            // Offset so renderFrom maps to startRadius. Clamp to avoid negative radii.
            max(0, startRadius + spacing * (t - turnOffset))
        }

        func point(turns t: Double) -> CGPoint {
            let theta = t * 2 * Double.pi
            let r = radius(turns: t)
            return CGPoint(x: cx + r * cos(theta - .pi / 2),
                           y: cy + r * sin(theta - .pi / 2))
        }

        func isVisible(turns t: Double) -> Bool {
            t >= renderFrom - 0.5 && t <= renderUpTo + 0.5
        }
    }

    // MARK: - Helpers

    private func dataEndTurns() -> Double {
        guard !records.isEmpty else { return 0.0 }
        var best = 0.0
        for r in records {
            let dayT = Double(r.day)
            let dayStart = dayT * 24.0
            let endAbsH: Double
            if let lastSleep = r.phases.last(where: { $0.phase != .awake }) {
                endAbsH = dayStart + lastSleep.hour + 0.25
            } else {
                endAbsH = dayStart + r.wakeupHour
            }
            let turns = dayT + (endAbsH - dayStart) / period
            if turns > best { best = turns }
        }
        return best
    }

    // MARK: - Drawing

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(hex: "0c0e14")))

            let cursorTurns = cursorAbsHour / period
            let extentTurns = max(spiralExtentTurns, 0.5)
            let geo = FlatGeo(size: size, cursorTurns: cursorTurns,
                              span: visibleDays, extentTurns: extentTurns, period: period)

            drawRadialLines(context: context, geo: geo, size: size)
            drawDayRings(context: context, geo: geo)
            drawSpiralPath(context: context, geo: geo)
            drawDataPoints(context: context, geo: geo)
            drawEventMarkers(context: context, geo: geo)
            drawSleepArc(context: context, geo: geo)
            drawCursor(context: context, geo: geo)
            drawHourLabels(context: context, geo: geo, size: size)
        }
    }

    // MARK: - Day rings

    private func drawDayRings(context: GraphicsContext, geo: FlatGeo) {
        let firstDay = max(1, Int(floor(geo.renderFrom)))
        let lastDay = Int(ceil(geo.renderUpTo))
        guard lastDay >= firstDay else { return }
        for day in firstDay...lastDay {
            let t = Double(day)
            guard geo.isVisible(turns: t) else { continue }
            let isWeek = day % 7 == 0
            let color = Color.white.opacity(isWeek ? 0.15 : 0.07)
            let lw: CGFloat = isWeek ? 0.6 : 0.3
            var path = Path()
            for i in 0...60 {
                let frac = Double(i) / 60.0
                let pt = geo.point(turns: t + frac)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: lw)
        }
    }

    // MARK: - Radial lines

    private func drawRadialLines(context: GraphicsContext, geo: FlatGeo, size: CGSize) {
        let canvasEdge = max(size.width, size.height)
        let minorStep: Double = period <= 24 ? 3 : (period / 8).rounded()
        let majorStep: Double = minorStep * 2
        var h = 0.0
        while h < period {
            let isMajor = h.truncatingRemainder(dividingBy: majorStep) < 0.001
            let angle = (h / period) * 2 * Double.pi - .pi / 2
            var path = Path()
            path.move(to: CGPoint(x: geo.cx, y: geo.cy))
            path.addLine(to: CGPoint(x: geo.cx + canvasEdge * cos(angle),
                                     y: geo.cy + canvasEdge * sin(angle)))
            context.stroke(path,
                           with: .color(Color.white.opacity(isMajor ? 0.12 : 0.06)),
                           lineWidth: isMajor ? 0.6 : 0.3)
            h += minorStep
        }
    }

    // MARK: - Backbone

    private func drawSpiralPath(context: GraphicsContext, geo: FlatGeo) {
        let backboneTo = geo.renderUpTo
        guard backboneTo > 0 else { return }
        let backboneFrom = max(geo.renderFrom - 0.5, 0)

        // Skip backbone where data arcs are drawn (they cover it)
        let dataEnd = dataEndTurns()
        let skipFrom: Double
        let skipTo: Double
        if !records.isEmpty && dataEnd > 0 {
            let firstDataDay = records.map(\.day).min() ?? 0
            skipFrom = Double(firstDataDay)
            skipTo = dataEnd
        } else {
            skipFrom = 0; skipTo = 0
        }
        let hasSkip = skipTo > skipFrom

        let step = 0.015
        var d = backboneFrom
        var path = Path()
        var first = true

        let backboneColor = Color(hex: "2e3248").opacity(0.4)
        let backboneWidth: CGFloat = 6.0

        func flush() {
            guard !first else { return }
            context.stroke(path, with: .color(backboneColor),
                           style: StrokeStyle(lineWidth: backboneWidth, lineCap: .round, lineJoin: .round))
            path = Path(); first = true
        }

        while d <= backboneTo {
            let t = min(d, backboneTo)
            if hasSkip && t >= skipFrom && t < skipTo {
                flush(); if d >= backboneTo { break }; d += step; continue
            }
            let pt = geo.point(turns: t)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            if d >= backboneTo { break }
            d += step
        }
        flush()
    }

    // MARK: - Data arcs

    private func drawDataPoints(context: GraphicsContext, geo: FlatGeo) {
        let globalCut = dataEndTurns()

        struct Run {
            var phase: SleepPhase
            var points: [(t: Double, pt: CGPoint)]
            var prevPhase: SleepPhase?
            var nextPhase: SleepPhase?
        }

        func isSleep(_ p: SleepPhase) -> Bool { p != .awake }

        func drawRun(_ run: Run) {
            guard run.points.count >= 2 else { return }
            let color = phaseColor(run.phase)
            let lw: CGFloat = 8.0

            for i in 0..<(run.points.count - 1) {
                let p0 = run.points[i]
                let p1 = run.points[i + 1]
                var seg = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(color),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // Round caps at sleep run boundaries
            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart {
                let pt = run.points[0].pt
                let r = lw * 0.5
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r,
                                                      width: lw, height: lw)),
                             with: .color(color))
            }
            if capEnd {
                let pt = run.points[run.points.count - 1].pt
                let r = lw * 0.5
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r,
                                                      width: lw, height: lw)),
                             with: .color(color))
            }
        }

        for record in records {
            let dayT = Double(record.day)
            // Skip records outside the visible window
            guard dayT + 1 >= geo.renderFrom && dayT <= geo.renderUpTo else { continue }
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let cutT = min(globalCut, dayT + 1.0)

            var runs: [Run] = []
            var runPhase = phases[0].phase
            var runPts: [(t: Double, pt: CGPoint)] = []
            var prevPhase: SleepPhase? = nil

            func flushRun(nextPhase: SleepPhase?) {
                guard runPts.count >= 2 else { runPts.removeAll(); return }
                runs.append(Run(phase: runPhase, points: runPts,
                                prevPhase: prevPhase, nextPhase: nextPhase))
                runPts.removeAll()
            }

            for (i, phase) in phases.enumerated() {
                let t = dayT + phase.hour / period
                if t > cutT { break }
                if phase.phase != runPhase {
                    let pt = geo.point(turns: t)
                    runPts.append((t, pt))
                    flushRun(nextPhase: phase.phase)
                    prevPhase = runPhase
                    runPhase = phase.phase
                    runPts.append((t, pt))
                } else {
                    runPts.append((t, geo.point(turns: t)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutT, dayT + 1.0)
                    runPts.append((tEnd, geo.point(turns: tEnd)))
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            // Draw awake first, sleep on top
            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
        }
    }

    // MARK: - Events

    private func drawEventMarkers(context: GraphicsContext, geo: FlatGeo) {
        for event in events {
            let t = event.absoluteHour / period
            guard geo.isVisible(turns: t) else { continue }
            let p = geo.point(turns: t)
            let color = Color(hex: event.type.hexColor)
            let r: CGFloat = 5.0
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color))
        }
    }

    // MARK: - Hour labels

    private func drawHourLabels(context: GraphicsContext, geo: FlatGeo, size: CGSize) {
        let step: Double = period <= 24 ? 6 : (period / 4).rounded()
        let labelR = min(geo.cx, geo.cy) - 6
        var h = 0.0
        while h < period {
            let angle = (h / period) * 2 * Double.pi - .pi / 2
            let pt = CGPoint(x: geo.cx + labelR * cos(angle),
                             y: geo.cy + labelR * sin(angle))
            let displayH = Int(h.rounded()) % 24
            let resolved = context.resolve(
                Text(String(format: "%02d", displayH))
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            )
            context.draw(resolved, at: pt)
            h += step
        }
    }

    // MARK: - Sleep marking arc

    private func drawSleepArc(context: GraphicsContext, geo: FlatGeo) {
        guard let startH = sleepStartHour else { return }
        let lo = min(startH, cursorAbsHour)
        let hi = max(startH, cursorAbsHour)
        guard hi - lo > 0.01 else { return }
        let arcColor = Color(hex: "7c3aed").opacity(0.85)
        let glowColor = Color.white.opacity(0.15)
        let style = StrokeStyle(lineWidth: 10, lineCap: .round)
        var path = Path()
        var started = false
        var h = lo

        while h <= hi {
            let t = h / period
            let pt = geo.point(turns: t)
            if !started { path.move(to: pt); started = true }
            else { path.addLine(to: pt) }
            h = min(h + 0.1, hi)
            if h >= hi { break }
        }
        if started {
            context.stroke(path, with: .color(arcColor), style: style)
            context.stroke(path, with: .color(glowColor), style: style)
        }
    }

    // MARK: - Cursor

    private func drawCursor(context: GraphicsContext, geo: FlatGeo) {
        let t = cursorAbsHour / period
        let p = geo.point(turns: t)
        let r: CGFloat = 7.0
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        // Glow
        context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)),
                     with: .color(markingColor.opacity(0.25)))
        // Ring
        context.stroke(Circle().path(in: rect),
                       with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        // Fill
        context.fill(Circle().path(in: rect.insetBy(dx: 1.5, dy: 1.5)),
                     with: .color(markingColor))
    }

    // MARK: - Phase colours

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "7c3aed")
        case .rem:   return Color(hex: "a78bfa")
        case .light: return Color(hex: "c4b5fd")
        case .awake: return Color(hex: "fbbf24")
        }
    }
}

#Preview("With Data") {
    WatchSpiralCanvas(
        records: {
            var eps: [SleepEpisode] = []
            let beds: [Double] = [23, 23.5, 0, 23, 23.5, 1, 0.5]
            let durs: [Double] = [7.5, 8, 7, 7.5, 8, 6.5, 7]
            for i in 0..<7 {
                let base = Double(i) * 24.0
                eps.append(SleepEpisode(start: base + beds[i],
                                        end: base + beds[i] + durs[i],
                                        source: .manual))
            }
            return ManualDataConverter.convert(episodes: eps, numDays: 7)
        }(),
        events: [],
        cursorAbsHour: 6 * 24 + 7.5,
        sleepStartHour: nil,
        markingColor: Color(hex: "a78bfa"),
        spiralExtentTurns: 6.3,
        visibleDays: 7
    )
    .frame(width: 184, height: 224)
    .background(Color(hex: "0c0e14"))
}

#Preview("Empty State") {
    WatchSpiralCanvas(
        records: [],
        events: [],
        cursorAbsHour: 168,
        sleepStartHour: nil,
        markingColor: Color(hex: "a78bfa"),
        spiralExtentTurns: 7.0,
        visibleDays: 7
    )
    .frame(width: 184, height: 224)
    .background(Color(hex: "0c0e14"))
}
