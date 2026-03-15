import SwiftUI
import SpiralKit
import WatchKit

/// Spiral view for Apple Watch.
///
/// Identical rendering logic to iPhone SpiralView — same perspective projection,
/// same phase colours, same weekWindowOpacity fade, same backbone/cursor drawing.
///
/// startRadius = 15 (vs 75 on iPhone) so the spiral fits the smaller Watch screen.
///
/// Digital Crown = same as iPhone drag gesture: moves the cursor along the spiral
/// path and grows visibleDays to match, exactly replicating iPhone drag behaviour.
/// Finer steps (0.25 h/detent) when marking sleep.
struct WatchSpiralView: View {

    @Environment(WatchStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    // Crown
    @State private var crownRaw: Double = 0
    @State private var lastCrownRaw: Double = 0

    // Spiral state — same semantics as iPhone SpiralTab
    @State private var cursorAbsHour: Double = 0
    @State private var maxReachedTurns: Double = 1.0
    @State private var visibleDays: Double = 1.0
    @State private var storeInitialised = false
    /// True once the user has physically turned the crown.
    /// When false, any new data arriving from iPhone is allowed to re-position the cursor.
    @State private var userHasMovedCrown = false

    // Deferred visibleDays: the canvas reads this value so heavy redraws
    // don't block every single crown tick. We batch-flush it via a Task.
    @State private var deferredVisibleDays: Double = 1.0
    @State private var flushPending = false



    // Sleep marking
    @State private var markingState: MarkingState = .idle
    @State private var sleepStartHour: Double? = nil
    @State private var flashConfirm = false

    @FocusState private var crownFocused: Bool
    // Last hour boundary crossed — used to fire a haptic tick once per hour
    @State private var lastHapticHour: Int = -1

    enum MarkingState { case idle, sleeping }

    // startRadius=5 gives more room between the center and first turn on Watch's tiny screen.
    private static let startRadius: Double = 5

    private var totalDataDays: Int {
        max((store.recentRecords.map { $0.day }.max() ?? 0) + 1, 1)
    }

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
                    numDaysHint: max(totalDataDays, 1),
                    spiralExtentTurns: maxReachedTurns,
                    visibleDays: deferredVisibleDays,
                    depthScale: store.depthScale,
                    spiralType: store.spiralType,
                    period: store.period,
                    startRadius: Self.startRadius
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
        let hourDelta  = markingState == .sleeping ? delta * 0.25 : delta * 0.5
        let turnsDelta = hourDelta / store.period
        let newHour    = cursorAbsHour + hourDelta
        let maxHour    = maxReachedTurns * store.period + 24.0
        cursorAbsHour  = max(0, min(newHour, maxHour))
        store.cursorAbsoluteHour = cursorAbsHour

        // Fire a haptic tick each time the cursor crosses an hour boundary
        let currentHour = Int(cursorAbsHour)
        if currentHour != lastHapticHour {
            lastHapticHour = currentHour
            WKInterfaceDevice.current().play(.click)
        }
        let newTurns   = cursorAbsHour / store.period
        if newTurns > maxReachedTurns { maxReachedTurns = newTurns }
        // Move visibleDays by the same delta as the cursor — zoom level stays constant,
        // cursor and camera window move together like the iPhone drag behaviour.
        visibleDays = max(1.0, min(maxReachedTurns, visibleDays + turnsDelta))
        // Schedule a deferred canvas flush. The canvas uses deferredVisibleDays so
        // the heavy redraw doesn't block every single crown tick. We yield to the
        // run loop once (Task) so multiple rapid ticks coalesce into one redraw.
        if !flushPending {
            flushPending = true
            Task { @MainActor in
                deferredVisibleDays = visibleDays
                flushPending = false
            }
        }
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
            cursorAbsHour = 0; maxReachedTurns = 1; visibleDays = 2; deferredVisibleDays = 2
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
        cursorAbsHour      = bestAbsHour
        store.cursorAbsoluteHour = bestAbsHour
        maxReachedTurns    = max(1.0, endTurns)
        // Start with a 5-day window so the focus-fade effect is visible from the first load.
        // The user can scroll back with the crown to reveal older nights progressively.
        visibleDays        = min(endTurns, 5.0)
        deferredVisibleDays = visibleDays
        crownRaw = 0; lastCrownRaw = 0
        storeInitialised = true
        userHasMovedCrown = false
    }
}

// MARK: - Canvas

/// Faithful port of iPhone SpiralView's Canvas drawing code.
/// Uses the same project(), weekWindowOpacity(), perspectiveScale() math.
/// startRadius = 15 instead of 75 so the spiral fits a ~184px Watch screen.
private struct WatchSpiralCanvas: View {
    let records: [SleepRecord]
    let events: [CircadianEvent]
    let cursorAbsHour: Double
    let sleepStartHour: Double?
    let markingColor: Color
    let numDaysHint: Int
    let spiralExtentTurns: Double
    let visibleDays: Double
    let depthScale: Double
    var spiralType: SpiralType = .archimedean
    var period: Double = 24.0
    var startRadius: Double = 5

    // MARK: - Projection (identical to iPhone SpiralView)

    private func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
        let day  = Int(t)
        let hr   = (t - Double(day)) * geo.period
        let flat = geo.point(day: day, hour: hr)

        let totalT  = max(spiralExtentTurns, 0.5)
        let margin  = 0.35
        let visible = max(visibleDays + margin, 1.0 + margin)
        let cx = geo.cx, cy = geo.cy
        let wx = flat.x - cx, wy = flat.y - cy
        let zStep    = geo.maxRadius * depthScale
        let tRef     = totalT + margin
        let wz       = (tRef - t) * zStep
        let focalLen = geo.maxRadius * 1.2
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget
        let dz       = wz - camZ
        let safeDz   = max(dz, focalLen * 0.05)
        let scale    = focalLen / safeDz
        return CGPoint(x: cx + wx * scale, y: cy + wy * scale)
    }

    private func cameraMaxVisibleTurn(geo: SpiralGeometry) -> Double {
        let totalT   = max(spiralExtentTurns, 0.5)
        let margin   = 0.35
        let tRef     = totalT + margin
        let visible  = max(visibleDays + margin, 1.0 + margin)
        let zStep    = geo.maxRadius * depthScale
        let focalLen = geo.maxRadius * 1.2
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget
        return tRef - camZ / zStep
    }

    private func weekWindowOpacity(turns t: Double) -> Double {
        // Watch uses a tighter 3-turn focus window (vs 7 on iPhone) so the
        // fade effect is visible even with just a few nights of data.
        // Previous 3 turns show at reduced opacity (0.35) then fade to zero.
        let focusEnd   = visibleDays
        let focusStart = focusEnd - 3.0
        func softStep(_ x: Double, edge: Double, half: Double = 0.5) -> Double {
            max(0.0, min(1.0, (x - (edge - half)) / (2 * half)))
        }
        if t >= focusStart {
            return softStep(t, edge: focusStart + 0.5)
        } else if t >= focusStart - 3.0 {
            return 0.35 * softStep(t, edge: focusStart - 2.5)
        }
        return 0.0
    }

    private func perspectiveScale(turns t: Double, geo: SpiralGeometry) -> Double {
        let totalT   = max(spiralExtentTurns, 0.5)
        let margin   = 0.35
        let visible  = max(visibleDays + margin, 1.0 + margin)
        let zStep    = geo.maxRadius * depthScale
        let tRef     = totalT + margin
        let focalLen = geo.maxRadius * 1.2
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget
        let wz       = (tRef - t) * zStep
        let dz       = max(wz - camZ, focalLen * 0.05)
        return focalLen / dz
    }

    // MARK: - Drawing

    var body: some View {
        Canvas { context, size in
            // Fill background before any transform.
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "0c0e14")))

            let turns     = max(spiralExtentTurns, 0.1)
            let scaleDays = max(1, Int(ceil(turns)))
            // Use at least 7 days for maxDays so the spiral spacing stays small
            // and the arc fills the screen even with just 1-2 nights of data.
            let geo = SpiralGeometry(
                totalDays: scaleDays,
                maxDays:   max(scaleDays, 7),
                width:     size.width,
                height:    size.height,
                startRadius: startRadius,
                spiralType: spiralType,
                period:    period
            )
            let maxVisible = min(turns, cameraMaxVisibleTurn(geo: geo))

            // Scale the spiral content up so it fills the Watch screen better.
            // SpiralGeometry.maxRadius = min(w,h)/2 - 50, which on a 184×224 Watch
            // gives only 42 px of usable radius. Scaling by 1.8 gives ~75 px —
            // much closer to the visual fill seen on iPhone.
            // We apply the transform only to spiral drawing (rings, lines, data,
            // cursor); hour labels are drawn afterwards in the original context so
            // they remain at the screen edge regardless of the scale factor.
            let spiralScale: CGFloat = 2.6
            let tx = geo.cx * (1 - spiralScale)
            let ty = geo.cy * (1 - spiralScale)
            var scaledCtx = context
            scaledCtx.concatenate(CGAffineTransform(a: spiralScale, b: 0, c: 0, d: spiralScale, tx: tx, ty: ty))

            drawDayRings(context: scaledCtx, geo: geo, upToTurns: maxVisible, size: size)
            drawRadialLines(context: scaledCtx, geo: geo)
            drawSpiralPath(context: scaledCtx, geo: geo, upToTurns: maxVisible, size: size)
            drawDataPoints(context: scaledCtx, geo: geo, size: size)
            drawEventMarkers(context: scaledCtx, geo: geo)
            drawSleepArc(context: scaledCtx, geo: geo, size: size)
            drawCursor(context: scaledCtx, geo: geo)
            // Hour labels drawn in the original unscaled context so they stay at screen edge.
            drawHourLabels(context: context, geo: geo)
        }
    }

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double, size: CGSize) {
        for ring in geo.dayRings() where ring.day > 0 && Double(ring.day) <= upToTurns {
            let opac = weekWindowOpacity(turns: Double(ring.day))
            guard opac > 0.01 else { continue }
            let color = ring.isWeekBoundary
                ? Color.white.opacity(0.18 * opac)
                : Color.white.opacity(0.09 * opac)
            let lw: CGFloat = ring.isWeekBoundary ? 0.8 : 0.4
            var path = Path()
            for i in 0...60 {
                let t  = Double(ring.day) + Double(i) / 60.0
                let pt = project(turns: t, geo: geo)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: lw)
        }
    }

    private func drawRadialLines(context: GraphicsContext, geo: SpiralGeometry) {
        let canvasEdge = max(geo.width, geo.height)
        let minorStep: Double = geo.period <= 24 ? 3 : (geo.period / 8).rounded()
        let majorStep: Double = minorStep * 2
        var h = 0.0
        while h < geo.period {
            let isMajor = h.truncatingRemainder(dividingBy: majorStep) < 0.001
            let angle   = (h / geo.period) * 2 * Double.pi - Double.pi / 2
            var path = Path()
            path.move(to: CGPoint(x: geo.cx, y: geo.cy))
            path.addLine(to: CGPoint(x: geo.cx + canvasEdge * cos(angle),
                                     y: geo.cy + canvasEdge * sin(angle)))
            context.stroke(path,
                           with: .color(Color.white.opacity(isMajor ? 0.18 : 0.09)),
                           lineWidth: isMajor ? 1.0 : 0.6)
            h += minorStep
        }
    }

    private func dataEndTurns(geo: SpiralGeometry) -> Double {
        guard !records.isEmpty else { return 0.0 }
        var best = 0.0
        for r in records {
            let dayT     = Double(r.day)
            let dayStart = dayT * 24.0
            let endAbsH: Double
            if let lastSleep = r.phases.last(where: { $0.phase != .awake }) {
                endAbsH = dayStart + lastSleep.hour + 0.25
            } else {
                endAbsH = dayStart + r.wakeupHour
            }
            let turns = dayT + (endAbsH - dayStart) / geo.period
            if turns > best { best = turns }
        }
        return best
    }

    private func drawSpiralPath(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double, size: CGSize) {
        guard upToTurns > 0 else { return }
        let dataEnd = dataEndTurns(geo: geo)
        // Don't draw the grey backbone at all if the cursor hasn't gone past the last record
        guard dataEnd < upToTurns else { return }
        let step = 0.015
        var d = 0.0
        var path = Path()
        var first = true
        var flushTurn = 0.0

        let backboneWidth = max(1.5, geo.spacing * 0.55)
        func flush() {
            guard !first else { return }
            let opac = weekWindowOpacity(turns: flushTurn)
            if opac > 0.01 {
                context.stroke(path, with: .color(Color(hex: "2e3248").opacity(opac)),
                               style: StrokeStyle(lineWidth: backboneWidth, lineCap: .round, lineJoin: .round))
            }
            path = Path(); first = true
        }
        while d <= upToTurns {
            let t = min(d, upToTurns)
            if t < dataEnd { flush(); if d >= upToTurns { break }; d += step; continue }
            flushTurn = t
            let pt = project(turns: t, geo: geo)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            if d >= upToTurns { break }
            d += step
        }
        flush()
    }

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry, size: CGSize) {
        let globalCut = dataEndTurns(geo: geo)

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
            let maxLW = max(2.0, geo.spacing * 0.65)
            let opac  = weekWindowOpacity(turns: run.points[0].t)
            guard opac > 0.01 else { return }

            // Segment-by-segment with .round caps: lw follows perspective smoothly
            // along the full arc, and rounded ends overlap seamlessly (no gaps).
            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = perspectiveScale(turns: tSeg, geo: geo)
                let lw   = max(1.5, min(sc * maxLW, maxLW))

                var seg = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(color.opacity(opac)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // Round cap at sleep-block boundaries only (not at internal sleep→sleep joints).
            // Awake runs skip caps — adjacent sleep caps cover the joint.
            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart {
                let tFirst = run.points[0].t
                let sc = perspectiveScale(turns: tFirst, geo: geo)
                let lw = max(1.5, min(sc * maxLW, maxLW))
                let r = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
            if capEnd {
                let tLast = run.points[run.points.count - 1].t
                let sc = perspectiveScale(turns: tLast, geo: geo)
                let lw = max(1.5, min(sc * maxLW, maxLW))
                let r = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
        }

        for record in records {
            let dayT   = Double(record.day)
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let cutT = min(globalCut, dayT + 1.0)

            var runs: [Run] = []
            var runPhase  = phases[0].phase
            var runPts:   [(t: Double, pt: CGPoint)] = []
            var prevPhase: SleepPhase? = nil

            func flushRun(nextPhase: SleepPhase?) {
                guard runPts.count >= 2 else { runPts.removeAll(); return }
                runs.append(Run(phase: runPhase, points: runPts, prevPhase: prevPhase, nextPhase: nextPhase))
                runPts.removeAll()
            }

            for (i, phase) in phases.enumerated() {
                let t = dayT + phase.hour / geo.period
                if t > cutT { break }
                if phase.phase != runPhase {
                    let edgePt = project(turns: t, geo: geo)
                    runPts.append((t, edgePt))
                    flushRun(nextPhase: phase.phase)
                    prevPhase = runPhase
                    runPhase  = phase.phase
                    runPts.append((t, edgePt))
                } else {
                    runPts.append((t, project(turns: t, geo: geo)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutT, dayT + 1.0)
                    runPts.append((tEnd, project(turns: tEnd, geo: geo)))
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            // Draw awake first, sleep on top so sleep caps always win at shared endpoints.
            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
        }
    }

    private func drawEventMarkers(context: GraphicsContext, geo: SpiralGeometry) {
        for event in events {
            let t = event.absoluteHour / geo.period
            guard Int(t) < geo.totalDays else { continue }
            let opac = weekWindowOpacity(turns: t)
            guard opac > 0.01 else { continue }
            let p = project(turns: t, geo: geo)
            let color = Color(hex: event.type.hexColor)
            // Scale dot radius with perspective so near turns are larger, far turns are smaller.
            let sc = perspectiveScale(turns: t, geo: geo)
            let r = max(1.0, min(sc * 2.5, 4.0))
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(opac)))
        }
    }

    private func drawHourLabels(context: GraphicsContext, geo: SpiralGeometry) {
        let step: Double = geo.period <= 24 ? 6 : (geo.period / 4).rounded()
        // Place labels near the screen edge regardless of maxRadius (which is small on Watch).
        let labelR = min(geo.cx, geo.cy) - 10
        var h = 0.0
        while h < geo.period {
            let angle = (h / geo.period) * 2 * Double.pi - Double.pi / 2
            let pt = CGPoint(x: geo.cx + labelR * cos(angle), y: geo.cy + labelR * sin(angle))
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

    private func drawSleepArc(context: GraphicsContext, geo: SpiralGeometry, size: CGSize) {
        guard let startH = sleepStartHour else { return }
        let lo = min(startH, cursorAbsHour); let hi = max(startH, cursorAbsHour)
        guard hi - lo > 0.01 else { return }
        var path = Path(); var started = false; var h = lo
        while h <= hi {
            let pt = project(turns: h / geo.period, geo: geo)
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            h = min(h + 0.1, hi); if h >= hi { break }
        }
        context.stroke(path, with: .color(Color(hex: "7c3aed").opacity(0.85)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.stroke(path, with: .color(.white.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    private func drawCursor(context: GraphicsContext, geo: SpiralGeometry) {
        let t = cursorAbsHour / geo.period
        let p = project(turns: t, geo: geo)
        // r=3 → 6pt dot; after 1.8× canvas scale it renders as ~11pt on screen — compact but tappable.
        let r = 3.0
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
        context.fill(Circle().path(in: rect.insetBy(dx: -2.5, dy: -2.5)),
                     with: .color(markingColor.opacity(0.22)))
        context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.0)
        context.fill(Circle().path(in: rect.insetBy(dx: 1, dy: 1)), with: .color(markingColor))
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "7c3aed")
        case .rem:   return Color(hex: "a78bfa")
        case .light: return Color(hex: "c4b5fd")
        case .awake: return Color(hex: "fbbf24")
        }
    }
}

#Preview {
    WatchSpiralCanvas(
        records: {
            let eps = [SleepEpisode(start: 23, end: 31, source: .manual)]
            return ManualDataConverter.convert(episodes: eps, numDays: 1)
        }(),
        events: [],
        cursorAbsHour: 31,
        sleepStartHour: nil,
        markingColor: Color(hex: "a78bfa"),
        numDaysHint: 1,
        spiralExtentTurns: 31.0 / 24.0,
        visibleDays: 31.0 / 24.0,
        depthScale: 1.5
    )
    .frame(width: 184, height: 224)
    .background(Color(hex: "0c0e14"))
}
