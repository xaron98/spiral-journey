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
            // No data yet — place the cursor at the current wall-clock time so the
            // spiral backbone and cursor are visible on the outer edge, ready for
            // the user to tap the moon button and start logging sleep.
            let now = store.currentAbsoluteHour
            cursorAbsHour = now
            store.cursorAbsoluteHour = now
            maxReachedTurns = max(1.0, now / store.period)
            // Camera is centered on cursor; visibleDays is the backward span.
            // Keep it very tight on Watch's small screen — half turn at start.
            visibleDays = min(maxReachedTurns, 0.5)
            deferredVisibleDays = visibleDays
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
        // Camera is centered on cursor; visibleDays is the backward span.
        // Half turn keeps the spiral very large on Watch's small screen.
        visibleDays        = min(endTurns, 0.5)
        deferredVisibleDays = visibleDays
        crownRaw = 0; lastCrownRaw = 0
        storeInitialised = true
        userHasMovedCrown = false
    }
}

// MARK: - Canvas

/// Watch spiral canvas using the same CameraState projection model as iPhone.
/// Camera is centered on the cursor, looking back `visibleDays` turns.
/// Perspective depth makes recent turns large and older turns shrink away.
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

    // MARK: - CameraState (identical to iPhone SpiralView)

    private struct Cam {
        let tRef: Double
        let zStep: Double
        let focalLen: Double
        let camZ: Double

        init(fromTurns: Double, upToTurns: Double, geo: SpiralGeometry, depthScale: Double) {
            let zStep    = geo.maxRadius * depthScale
            let focalLen = geo.maxRadius * 1.2
            let nearPlane = focalLen * 0.1
            let safetyMargin = nearPlane * 1.0

            let margin = 0.5
            let tRef = upToTurns + margin

            let spanZ = max((upToTurns - fromTurns), 0.5) * zStep
            let maxRatio = 5.0
            let dzFarForRatio = spanZ / (maxRatio - 1.0)
            let dzFarMin = nearPlane + safetyMargin
            let dzFar = max(dzFarForRatio, dzFarMin)
            let camZ = margin * zStep - dzFar

            self.tRef     = tRef
            self.zStep    = zStep
            self.focalLen = focalLen
            self.camZ     = camZ
        }

        func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
            let theta = t * 2 * Double.pi
            let r     = geo.radius(turns: t)
            let flatX = geo.cx + r * cos(theta - Double.pi / 2)
            let flatY = geo.cy + r * sin(theta - Double.pi / 2)

            let wx = flatX - geo.cx
            let wy = flatY - geo.cy
            let wz = (tRef - t) * zStep
            let dz = max(wz - camZ, focalLen * 0.05)
            let scale = focalLen / dz

            return CGPoint(x: geo.cx + wx * scale,
                           y: geo.cy + wy * scale)
        }

        func perspectiveScale(turns t: Double) -> Double {
            let wz = (tRef - t) * zStep
            let dz = max(wz - camZ, focalLen * 0.05)
            return focalLen / dz
        }

        func isBehindCamera(turns t: Double) -> Bool {
            let wz = (tRef - t) * zStep
            let dz = wz - camZ
            return dz < focalLen * 0.1
        }

        var maxVisibleTurn: Double {
            tRef - camZ / zStep
        }
    }

    private func weekWindowOpacity(turns t: Double) -> Double {
        let cursorTurns = cursorAbsHour / period
        let dist = abs(cursorTurns - t)
        let curve: [Double] = [1.0, 0.75, 0.50, 0.30, 0.15, 0.06]
        if dist < Double(curve.count) {
            let idx = Int(dist)
            let frac = dist - Double(idx)
            let lo = curve[idx]
            let hi = idx + 1 < curve.count ? curve[idx + 1] : lo * 0.5
            return lo + (hi - lo) * frac
        }
        let base = curve.last ?? 0.06
        let extra = dist - Double(curve.count) + 1
        return base * pow(0.5, extra)
    }

    // MARK: - Drawing

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "0c0e14")))

            let turns     = max(spiralExtentTurns, 0.1)
            let scaleDays = max(1, Int(ceil(turns)))
            let geo = SpiralGeometry(
                totalDays: scaleDays,
                maxDays:   max(scaleDays, 7),
                width:     size.width,
                height:    size.height,
                startRadius: startRadius,
                spiralType: spiralType,
                period:    period
            )

            // Build camera centered on cursor, looking back visibleDays turns
            let cursorTurns = cursorAbsHour / period
            let span = min(visibleDays, 4.0)
            let camFrom = max(cursorTurns - span, 0)
            let camUpTo = cursorTurns + 0.5
            let cam = Cam(fromTurns: camFrom, upToTurns: camUpTo,
                          geo: geo, depthScale: depthScale)
            let maxVisible = min(turns, cam.maxVisibleTurn)

            drawDayRings(context: context, geo: geo, cam: cam, maxVisible: maxVisible)
            drawRadialLines(context: context, geo: geo)
            drawSpiralPath(context: context, geo: geo, cam: cam, maxVisible: maxVisible)
            drawDataPoints(context: context, geo: geo, cam: cam)
            drawEventMarkers(context: context, geo: geo, cam: cam)
            drawSleepArc(context: context, geo: geo, cam: cam)
            drawCursor(context: context, geo: geo, cam: cam)
            drawHourLabels(context: context, geo: geo)
        }
    }

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, cam: Cam, maxVisible: Double) {
        for ring in geo.dayRings() where ring.day > 0 && Double(ring.day) <= maxVisible {
            let opac = weekWindowOpacity(turns: Double(ring.day))
            guard opac > 0.01 else { continue }
            let color = ring.isWeekBoundary
                ? Color.white.opacity(0.18 * opac)
                : Color.white.opacity(0.09 * opac)
            let lw: CGFloat = ring.isWeekBoundary ? 0.8 : 0.4
            var path = Path()
            var started = false
            for i in 0...60 {
                let t  = Double(ring.day) + Double(i) / 60.0
                if cam.isBehindCamera(turns: t) || cam.perspectiveScale(turns: t) < 0.10 {
                    // Flush current segment and start fresh after the gap
                    if started {
                        context.stroke(path, with: .color(color), lineWidth: lw)
                        path = Path(); started = false
                    }
                    continue
                }
                let pt = cam.project(turns: t, geo: geo)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            }
            if started {
                context.stroke(path, with: .color(color), lineWidth: lw)
            }
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

    private func drawSpiralPath(context: GraphicsContext, geo: SpiralGeometry, cam: Cam, maxVisible: Double) {
        let cursorTurns = cursorAbsHour / period
        let backboneTo = min(cursorTurns + 0.15, maxVisible)
        let backboneFrom = max(backboneTo - 7.0, 0)
        guard backboneTo > backboneFrom else { return }

        let dataEnd = dataEndTurns(geo: geo)
        let skipFrom: Double
        let skipTo: Double
        if !records.isEmpty && dataEnd > backboneFrom {
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
        let backboneWidth: CGFloat = 1.5

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
            if cam.isBehindCamera(turns: t) {
                flush(); if d >= backboneTo { break }; d += step; continue
            }
            let pt = cam.project(turns: t, geo: geo)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            if d >= backboneTo { break }
            d += step
        }
        flush()
    }

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry, cam: Cam) {
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
            let maxLW = max(3.0, geo.spacing * 0.65)
            let opac  = weekWindowOpacity(turns: run.points[0].t)
            guard opac > 0.01 else { return }

            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                // Skip segment if either endpoint is behind the camera or too compressed
                guard !cam.isBehindCamera(turns: p0.t),
                      !cam.isBehindCamera(turns: p1.t) else { continue }
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = cam.perspectiveScale(turns: tSeg)
                guard sc >= 0.10 else { continue }
                let lw   = max(2.0, min(sc * maxLW, maxLW))

                var seg = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(color.opacity(opac)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart, !cam.isBehindCamera(turns: run.points[0].t) {
                let tFirst = run.points[0].t
                let sc = cam.perspectiveScale(turns: tFirst)
                let lw = max(2.0, min(sc * maxLW, maxLW))
                let r = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
            if capEnd, !cam.isBehindCamera(turns: run.points[run.points.count - 1].t) {
                let tLast = run.points[run.points.count - 1].t
                let sc = cam.perspectiveScale(turns: tLast)
                let lw = max(2.0, min(sc * maxLW, maxLW))
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
                let behind = cam.isBehindCamera(turns: t)
                if behind {
                    // Point is behind camera — flush the current run segment
                    // so we don't connect distant visible points with a straight line
                    if !runPts.isEmpty {
                        flushRun(nextPhase: phase.phase)
                        prevPhase = runPhase
                        runPhase = phase.phase
                    }
                    continue
                }
                if phase.phase != runPhase {
                    let edgePt = cam.project(turns: t, geo: geo)
                    runPts.append((t, edgePt))
                    flushRun(nextPhase: phase.phase)
                    prevPhase = runPhase
                    runPhase  = phase.phase
                    runPts.append((t, edgePt))
                } else {
                    runPts.append((t, cam.project(turns: t, geo: geo)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutT, dayT + 1.0)
                    if !cam.isBehindCamera(turns: tEnd) {
                        runPts.append((tEnd, cam.project(turns: tEnd, geo: geo)))
                    }
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
        }
    }

    private func drawEventMarkers(context: GraphicsContext, geo: SpiralGeometry, cam: Cam) {
        for event in events {
            let t = event.absoluteHour / geo.period
            guard !cam.isBehindCamera(turns: t) else { continue }
            let opac = weekWindowOpacity(turns: t)
            guard opac > 0.01 else { continue }
            let p = cam.project(turns: t, geo: geo)
            let color = Color(hex: event.type.hexColor)
            let sc = cam.perspectiveScale(turns: t)
            let r = max(1.5, min(sc * 3.0, 5.0))
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(opac)))
        }
    }

    private func drawHourLabels(context: GraphicsContext, geo: SpiralGeometry) {
        let step: Double = geo.period <= 24 ? 6 : (geo.period / 4).rounded()
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

    private func drawSleepArc(context: GraphicsContext, geo: SpiralGeometry, cam: Cam) {
        guard let startH = sleepStartHour else { return }
        let lo = min(startH, cursorAbsHour); let hi = max(startH, cursorAbsHour)
        guard hi - lo > 0.01 else { return }
        let arcColor = Color(hex: "7c3aed").opacity(0.85)
        let glowColor = Color.white.opacity(0.15)
        let style = StrokeStyle(lineWidth: 5, lineCap: .round)
        var path = Path(); var started = false; var h = lo

        func flushArc() {
            guard started else { return }
            context.stroke(path, with: .color(arcColor), style: style)
            context.stroke(path, with: .color(glowColor), style: style)
            path = Path(); started = false
        }

        while h <= hi {
            let t = h / geo.period
            if cam.isBehindCamera(turns: t) {
                flushArc()
            } else {
                let pt = cam.project(turns: t, geo: geo)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            }
            h = min(h + 0.1, hi); if h >= hi { break }
        }
        flushArc()
    }

    private func drawCursor(context: GraphicsContext, geo: SpiralGeometry, cam: Cam) {
        let t = cursorAbsHour / geo.period
        let p = cam.project(turns: t, geo: geo)
        let sc = cam.perspectiveScale(turns: t)
        // Scale cursor with perspective — large when close, min 4pt
        let r = max(4.0, min(sc * 5.0, 8.0))
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
        context.fill(Circle().path(in: rect.insetBy(dx: -3, dy: -3)),
                     with: .color(markingColor.opacity(0.25)))
        context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        context.fill(Circle().path(in: rect.insetBy(dx: 1.5, dy: 1.5)), with: .color(markingColor))
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

#Preview("With Data") {
    WatchSpiralCanvas(
        records: {
            // 7 nights of sample data
            var eps: [SleepEpisode] = []
            let beds: [Double] = [23, 23.5, 0, 23, 23.5, 1, 0.5]
            let durs: [Double] = [7.5, 8, 7, 7.5, 8, 6.5, 7]
            for i in 0..<7 {
                let base = Double(i) * 24.0
                eps.append(SleepEpisode(start: base + beds[i], end: base + beds[i] + durs[i], source: .manual))
            }
            return ManualDataConverter.convert(episodes: eps, numDays: 7)
        }(),
        events: [],
        cursorAbsHour: 6 * 24 + 7.5,  // cursor at end of last night
        sleepStartHour: nil,
        markingColor: Color(hex: "a78bfa"),
        numDaysHint: 7,
        spiralExtentTurns: 6.3,
        visibleDays: 5.0,
        depthScale: 0.3
    )
    .frame(width: 184, height: 224)
    .background(Color(hex: "0c0e14"))
}

#Preview("Empty State") {
    // Simulates first launch: no records, cursor at current time (~7 days from startDate)
    WatchSpiralCanvas(
        records: [],
        events: [],
        cursorAbsHour: 168,
        sleepStartHour: nil,
        markingColor: Color(hex: "a78bfa"),
        numDaysHint: 1,
        spiralExtentTurns: 7.0,
        visibleDays: 7.0,
        depthScale: 0.3
    )
    .frame(width: 184, height: 224)
    .background(Color(hex: "0c0e14"))
}
