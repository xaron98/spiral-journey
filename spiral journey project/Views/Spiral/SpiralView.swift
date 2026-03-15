import SwiftUI
import SpiralKit

/// Main spiral visualization rendered with SwiftUI Canvas.
/// Supports temporal perspective zoom: depth > 0 tilts the spiral so recent turns
/// appear large/close and older turns shrink toward a vanishing point — logarithmic
/// depth buffer effect driven by the `depth` parameter (0 = flat, 1 = full perspective).
struct SpiralView: View {

    let records: [SleepRecord]
    let events: [CircadianEvent]
    let spiralType: SpiralType
    let period: Double
    let linkGrowthToTau: Bool
    let showCosinor: Bool
    let showBiomarkers: Bool
    let showTwoProcess: Bool
    let selectedDay: Int?
    let onSelectDay: (Int?) -> Void
    var contextBlocks: [ContextBlock] = []
    var cursorAbsHour: Double? = nil
    var sleepStartHour: Double? = nil
    /// Maximum days for scale — fixes spacing so it never shifts as spiral grows
    var numDaysHint: Int = 30
    /// Fractional turns the spiral extends to (growth frontier).
    /// Governs total geometry size. NOT used for camera framing.
    var spiralExtentTurns: Double? = nil
    /// Center of the visible viewport in turns.  Derived as:
    ///   viewportCenterTurns = cursorTurns + userViewportOffsetTurns
    /// When offset == 0 the viewport is centered on the cursor (today).
    var viewportCenterTurns: Double? = nil
    /// Half-width of the visible viewport in turns (zoom level).
    /// The viewport spans [center - span/2, center + span/2], clamped to
    /// [0, spiralExtentTurns].
    var visibleSpanTurns: Double? = nil
    /// 3D depth multiplier: controls zStep = maxRadius * depthScale.
    /// Higher = more perspective separation between turns (stronger 3D effect).
    /// Range 0.2 (flat) … 4.0 (very deep). Default 1.5.
    var depthScale: Double = 1.5
    /// Optional rephase target wake hour (0-24) — draws a subtle dashed radial line.
    var targetWakeHour: Double? = nil
    /// Optional rephase target bedtime hour (0-24) — draws a subtle dashed radial line.
    var targetBedHour: Double? = nil
    /// Whether to draw day ring and radial hour-line guides.
    var showGrid: Bool = true
    /// Inner radius of the spiral in points. Scale down for smaller screens (e.g. Watch: ~15).
    var startRadius: Double = 75


    @Environment(\.colorScheme) private var colorScheme
    @State private var canvasSize: CGSize = .zero

    /// Grid line base color — white in dark mode, dark ink in light mode.
    private var gridColor: Color {
        colorScheme == .dark ? Color.white : Color(red: 0.1, green: 0.1, blue: 0.2)
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let turns = max(spiralExtentTurns ?? Double(numDaysHint), 0.1)
                let scaleDays = max(1, Int(ceil(turns)))
                let geo = SpiralGeometry(
                    totalDays: scaleDays,
                    maxDays: scaleDays,
                    width: Double(size.width),
                    height: Double(size.height),
                    startRadius: startRadius,
                    spiralType: spiralType,
                    period: period,
                    linkGrowthToTau: linkGrowthToTau
                )
                drawSpiral(context: context, size: size, geo: geo, upToTurns: turns)
            }
            .background(SpiralColors.bg)
            .onTapGesture { location in
                handleTap(at: location, size: geo.size)
            }
            .onAppear { canvasSize = geo.size }
            .onChange(of: geo.size) { canvasSize = $1 }
        }
    }

    // MARK: - Camera

    /// Perspective camera computed once per frame.
    ///
    /// **Invariant**: for every turn `t` in `[fromTurns, upToTurns]`,
    /// `dz(t) >= nearPlane + safetyMargin` — no near-plane culling inside
    /// the viewport.  `camZ` is derived from this geometric condition.
    ///
    /// The camera controls ONLY depth/zoom — it does NOT shift the scene XY.
    /// The spiral keeps its natural composition centered on geo.cx/cy.
    /// The cursor moves naturally along the spiral path; the camera follows
    /// by adjusting tRef and camZ so the cursor's depth region stays well-framed.
    private struct CameraState {
        let tRef: Double
        let zStep: Double
        let focalLen: Double
        let camZ: Double

        /// Build camera that frames `[fromTurns, upToTurns]` with depth
        /// centered around `focusTurns`. No XY recentering — the spiral
        /// keeps its natural screen-space composition.
        init(fromTurns: Double, upToTurns: Double, focusTurns: Double,
             geo: SpiralGeometry, depthScale: Double) {
            let zStep    = geo.maxRadius * depthScale
            let focalLen = geo.maxRadius * 1.2
            let nearPlane = focalLen * 0.1
            let safetyMargin = nearPlane * 1.0

            // tRef: depth-zero reference. Place it past the camera window's
            // far edge so all content is in front of the camera.
            let margin = 0.5
            let tRef = upToTurns + margin

            // camZ: position the camera so the visible span fits within
            // a controlled perspective ratio. This keeps the zoom level
            // proportional to the span without over-zooming.
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

        /// Project a turn value to screen coordinates.
        /// Pure perspective projection pivoting around geo.cx/cy — no XY offset.
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

        /// Perspective scale factor at a given turn value (focalLen / dz).
        func perspectiveScale(turns t: Double) -> Double {
            let wz = (tRef - t) * zStep
            let dz = max(wz - camZ, focalLen * 0.05)
            return focalLen / dz
        }

        /// True when the given turn value is behind or too close to the camera.
        func isBehindCamera(turns t: Double) -> Bool {
            let wz = (tRef - t) * zStep
            let dz = wz - camZ
            return dz < focalLen * 0.1
        }

        /// Maximum turn value visible in front of the camera.
        var maxVisibleTurn: Double {
            tRef - camZ / zStep
        }
    }

    /// Build camera that frames [fromTurns, upToTurns] with depth around focusTurns.
    private func buildCamera(geo: SpiralGeometry, fromTurns: Double, upToTurns: Double,
                             focusTurns: Double) -> CameraState {
        CameraState(fromTurns: fromTurns, upToTurns: upToTurns, focusTurns: focusTurns,
                    geo: geo, depthScale: depthScale)
    }

    // Old project/cameraMaxVisibleTurn/perspectiveScale eliminated — all callers use CameraState.

    // MARK: - Drawing

    private func drawSpiral(context: GraphicsContext, size: CGSize, geo: SpiralGeometry, upToTurns: Double? = nil) {
        let extentTurns = spiralExtentTurns ?? Double(max(records.count, 1))
        let cursorTurns: Double? = cursorAbsHour.map { $0 / max(geo.period, 1.0) }

        // ── RETROSPECTIVE WINDOW MODEL ──
        //
        // Single source of truth: the DrawCursor marks the END of the visible window.
        // The window extends `span` turns into the PAST. No future is shown.
        //
        // A) CAMERA FRAMING — retrospective: [focusTurns - span, focusTurns]
        // B) DATA VISIBILITY — retrospective: [cursorT - span, cursorT]
        // C) OPACITY — styling only, never hides real data.

        let cursorT = cursorTurns ?? extentTurns
        let focusTurns = viewportCenterTurns ?? cursorT  // smooth-follow target

        // ── Strict 7-turn window ──
        //
        // ALWAYS [cursor-7, cursor]. No exceptions.
        // Data outside this window is invisible — even if that means
        // all records disappear when cursor is 7+ turns past data.
        let span = 7.0
        let cameraZPadding = 0.5

        let totalRealDays = records.filter { !$0.phases.isEmpty }.count

        let vpFrom = max(cursorT - span, 0)
        let vpUpTo = cursorT

        let camFrom = max(focusTurns - span, 0)
        let camUpTo = focusTurns + cameraZPadding

        let camera = buildCamera(geo: geo, fromTurns: camFrom, upToTurns: camUpTo,
                                 focusTurns: focusTurns)

        let backboneVisualTailTurns = 0.15
        let backboneCap = cursorT + backboneVisualTailTurns

        let state = SpiralVisibilityEngine.resolve(
            records: records,
            cursorAbsHour: cursorAbsHour,
            viewportFromTurns: vpFrom,
            viewportUpToTurns: vpUpTo,
            cameraFromTurns: camFrom,
            cameraUpToTurns: camUpTo,
            spiralExtentTurns: extentTurns,
            spiralPeriod: geo.period,
            cameraMaxTurn: camera.maxVisibleTurn,
            backboneCapTurn: backboneCap
        )

        // All draw functions now read from `state` directly.

        // ── DEBUG: Single consolidated per-frame log ──
        #if DEBUG
        do {
            let f = { (v: Double) -> String in String(format: "%.2f", v) }
            let bounds = state.dataBounds

            // Count visible days
            var visibleCount = 0
            if bounds.hasData {
                for day in bounds.firstDayIndex...bounds.lastDayIndex {
                    if state.dayVisibility(for: day).isVisible { visibleCount += 1 }
                }
            }

            print("[SpiralFrame] cursor=\(f(cursorT)) vpFrom=\(f(vpFrom)) vpUpTo=\(f(vpUpTo)) span=\(f(span)) camZ=\(f(camera.camZ)) drawFrom=\(f(state.renderFromTurns)) drawTo=\(f(state.backboneClipTurns)) realDays=\(totalRealDays) visible=\(visibleCount) fallback=\(state.showNoDataFallback)")

            let cameraCursorDelta = abs(focusTurns - cursorT)
            if cameraCursorDelta > 1.0 {
                print("[SpiralFrame] FAIL_CAMERA_DESYNC focus=\(f(focusTurns)) cursor=\(f(cursorT)) delta=\(f(cameraCursorDelta))")
            }
        }
        #endif

        // ── Single render pipeline — no fallback path ──
        // The normal pipeline handles all cases correctly:
        // - With data: arcs draw within visible window, backbone fills the rest
        // - Without data: no arcs, backbone draws the spiral shape
        // A separate fallback path was removed because it drew gray from
        // turn 0 to extentTurns (the ENTIRE spiral), which caused the
        // "broken gray overlay" bug whenever it triggered.
        // 1. Day rings
        drawDayRings(context: context, geo: geo, camera: camera, state: state)
        // 2. Radial lines
        if showGrid {
            drawRadialLines(context: context, geo: geo, upToTurns: state.renderUpToTurns)
        }
        // 3. Backbone disabled
        // 4. Two-process model
        if showTwoProcess {
            drawTwoProcess(context: context, geo: geo, camera: camera, state: state)
        }
        // 5. Data points (phase strokes)
        drawDataPoints(context: context, geo: geo, camera: camera, state: state)
        // 6. Context blocks (blue bands) — visibility driven by render state
        if !contextBlocks.isEmpty && state.markerState.shouldRenderContextMarkers {
            drawContextBlocks(context: context, geo: geo, camera: camera, state: state)
        }
        // 7. Cosinor overlay
        if showCosinor {
            drawCosinorOverlay(context: context, geo: geo, camera: camera, state: state)
        }
        // 8. Events
        drawEventMarkers(context: context, geo: geo, camera: camera, state: state)
        // 9. Biomarkers
        if showBiomarkers {
            drawBiomarkers(context: context, geo: geo, camera: camera, state: state)
        }
        // 10. Origin anchor — uses its own zoom-based visibility from render state
        drawOrigin(context: context, geo: geo, camera: camera, originVis: state.originState, markers: state.markerState)
        // 11. Hour labels
        drawHourLabels(context: context, geo: geo, size: size)
        // 12. Selected day ring
        if let day = selectedDay {
            drawSelectionRing(context: context, geo: geo, camera: camera, day: day)
        }
        // 13. Sleep arc
        if let cursor = cursorAbsHour, let sleepStart = sleepStartHour {
            drawSleepArc(context: context, geo: geo, camera: camera, from: sleepStart, to: cursor)
        }
        // 14. Cursor dot — governed by render state
        if let cursorSt = state.cursorState, cursorSt.shouldDraw {
            drawCursor(context: context, geo: geo, camera: camera, cursorState: cursorSt)
        }
        // 15. Rephase target markers
        drawTargetMarkers(context: context, geo: geo, upToTurns: state.renderUpToTurns)


    }

    // MARK: - B: Radial vignette background

    /// Draws a soft radial gradient centered on the spiral: slightly lighter at center,
    /// fading to pure darkness at the edges — makes the spiral feel like it floats in space.
    private func drawRadialBackground(context: GraphicsContext, geo: SpiralGeometry, size: CGSize) {
        let center = CGPoint(x: geo.cx, y: geo.cy)
        let outerR = max(size.width, size.height) * 0.72

        // Inner glow: a faint indigo halo where the spiral lives
        let innerGlow = Path(ellipseIn: CGRect(
            x: center.x - outerR * 0.55, y: center.y - outerR * 0.55,
            width: outerR * 1.1, height: outerR * 1.1))
        context.fill(innerGlow, with: .radialGradient(
            Gradient(colors: [
                Color(hex: "1a1535").opacity(0.55),
                Color.clear
            ]),
            center: center,
            startRadius: 0,
            endRadius: outerR * 0.55
        ))

        // Outer vignette: dark overlay at the canvas corners
        let fullRect = Path(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        context.fill(fullRect, with: .radialGradient(
            Gradient(colors: [
                Color.clear,
                Color.black.opacity(0.45)
            ]),
            center: center,
            startRadius: outerR * 0.45,
            endRadius: outerR
        ))
    }

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for ring in geo.dayRings() where ring.day > 0 && Double(ring.day) >= fromTurns - 1 && Double(ring.day) <= upToTurns {
            // Day rings follow the same visibility window as data.
            // Out-of-window rings are invisible.
            let vis = state.dayVisibility(for: ring.day)
            guard vis.isVisible, vis.opacity > 0.01 else { continue }
            let ringOpacity = vis.opacity
            let gridScale = colorScheme == .dark ? 1.0 : 1.3
            let baseOpacity = ring.isWeekBoundary ? 0.22 * gridScale : 0.11 * gridScale
            let color = gridColor.opacity(baseOpacity * ringOpacity)
            let lw: CGFloat = ring.isWeekBoundary ? 0.8 : 0.4

            var path = Path()
            var started = false
            let steps = 60
            for i in 0...steps {
                let t = Double(ring.day) + Double(i) / Double(steps)
                // FIX: Skip behind-camera points in day rings
                if camera.isBehindCamera(turns: t) {
                    if started { context.stroke(path, with: .color(color), lineWidth: lw); path = Path(); started = false }
                    continue
                }
                let pt = camera.project(turns: t, geo: geo)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            }
            if started { context.stroke(path, with: .color(color), lineWidth: lw) }
        }
    }

    private func drawRadialLines(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double) {
        // Lines go from center to the actual canvas edge.
        // Use the canvas diagonal so lines always reach the corner.
        let canvasEdge = max(geo.width, geo.height)
        // Major lines every 6h (00, 06, 12, 18) — more visible
        // Minor lines every 3h (03, 09, 15, 21) — more subtle, like the web version
        let minorStep: Double = geo.period <= 24 ? 3 : (geo.period / 8).rounded()
        let majorStep: Double = minorStep * 2
        var h = 0.0
        while h < geo.period {
            let isMajor = h.truncatingRemainder(dividingBy: majorStep) < 0.001
            let angle = (h / geo.period) * 2 * Double.pi - Double.pi / 2
            var path = Path()
            path.move(to: CGPoint(x: geo.cx, y: geo.cy))
            path.addLine(to: CGPoint(x: geo.cx + canvasEdge * cos(angle), y: geo.cy + canvasEdge * sin(angle)))
            let gridScale = colorScheme == .dark ? 1.0 : 1.3
            let opacity: Double = isMajor ? 0.22 * gridScale : 0.11 * gridScale
            let lw: CGFloat    = isMajor ? 1.0 : 0.6
            context.stroke(path, with: .color(gridColor.opacity(opacity)), lineWidth: lw)
            h += minorStep
        }
    }

    // Old perspectiveScale eliminated — all callers use camera.perspectiveScale(turns:).

    private func drawSpiralPath(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        // Backbone skip = intersection of data days AND visible window.
        // This is where data arcs ACTUALLY render. The backbone must not
        // draw gray there (arcs would be hidden behind it).
        //
        // When the window has no overlap with data → skip is empty →
        // backbone draws continuously (including over data turns, which
        // is correct because no data arcs render there).
        let skipFrom: Double
        let skipTo: Double
        if state.dataBounds.hasData {
            let overlapFirst = max(state.dataBounds.firstDayIndex, state.visibleWindow.startIndex)
            let overlapLast  = min(state.dataBounds.lastDayIndex,  state.visibleWindow.endIndex)
            if overlapFirst <= overlapLast {
                skipFrom = Double(overlapFirst)
                skipTo   = Double(overlapLast + 1)
            } else {
                skipFrom = 0; skipTo = 0
            }
        } else {
            skipFrom = 0; skipTo = 0
        }
        drawSpiralPath(context: context, geo: geo, camera: camera,
                       fromTurns: state.renderFromTurns,
                       upToTurns: state.backboneClipTurns,
                       skipFrom: skipFrom, skipTo: skipTo)
    }

    private func drawSpiralPath(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState,
                                fromTurns: Double = 0, upToTurns: Double,
                                skipFrom: Double = 0, skipTo: Double = 0) {
        guard upToTurns > 0 else { return }

        let step = 0.015
        var d = max(fromTurns, 0.0)
        var path = Path()
        var first = true

        func flush() {
            guard !first else { return }
            let pathColor = colorScheme == .dark
                ? Color(hex: "2e3248")
                : Color(red: 0.7, green: 0.72, blue: 0.78)
            context.stroke(path, with: .color(pathColor),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            path = Path(); first = true
        }

        let hasSkip = skipTo > skipFrom

        while d <= upToTurns {
            let t = min(d, upToTurns)
            // Skip backbone where data arcs are actually rendered
            if hasSkip && t >= skipFrom && t < skipTo {
                flush()
                if d >= upToTurns { break }
                d += step; continue
            }
            // Skip behind-camera points to prevent path explosion
            if camera.isBehindCamera(turns: t) {
                flush()
                if d >= upToTurns { break }
                d += step; continue
            }
            let pt = camera.project(turns: t, geo: geo)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            if d >= upToTurns { break }
            d += step
        }
        flush()
    }

    // MARK: - A: Glow pass (drawn under crisp phase strokes)

    /// Draws a wide, very soft stroke under each sleep segment — creates a luminous halo effect.
    private func drawDataGlow(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        let dataCutTurns = state.dataEndTurns
        let cursorCutTurns = cursorAbsHour.map { $0 / geo.period } ?? dataCutTurns
        let globalCutTurns = min(max(dataCutTurns, cursorCutTurns), upToTurns)

        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            let dayEndTurns = geo.turns(day: record.day + 1, hour: 0)
            guard dayEndTurns >= fromTurns, dayStartTurns <= upToTurns else { continue }
            let vis = state.dayVisibility(for: record.day)
            guard vis.isVisible else { continue }
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let cutTurns = min(globalCutTurns, dayEndTurns)

            var runPhase  = phases[0].phase
            var runPoints: [(t: Double, pt: CGPoint)] = []

            func flushGlow() {
                guard runPhase != .awake, runPoints.count >= 2 else {
                    runPoints.removeAll(); return
                }
                let color = phaseGlowColor(runPhase)
                // Draw two glow layers: wide soft outer + tighter inner, faded by visibility
                for (glowLW, glowOpac) in [(38.0, 0.12), (22.0, 0.18)] as [(Double, Double)] {
                    for i in 0..<(runPoints.count - 1) {
                        let p0   = runPoints[i]
                        let p1   = runPoints[i + 1]
                        // FIX: Skip segments where either endpoint is behind camera
                        guard !camera.isBehindCamera(turns: p0.t),
                              !camera.isBehindCamera(turns: p1.t) else { continue }
                        let tSeg = (p0.t + p1.t) * 0.5
                        let sc   = camera.perspectiveScale(turns: tSeg)
                        let lw   = max(glowLW * 0.5, min(sc * glowLW, glowLW * 1.4))
                        var seg = Path()
                        seg.move(to: p0.pt)
                        seg.addLine(to: p1.pt)
                        context.stroke(seg, with: .color(color.opacity(glowOpac * vis.opacity)),
                                       style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    }
                }
                runPoints.removeAll()
            }

            for (i, phase) in phases.enumerated() {
                let t = geo.turns(day: record.day, hour: phase.hour)
                if t > cutTurns { break }
                if phase.phase != runPhase {
                    let edgePt = camera.project(turns: t, geo: geo)
                    runPoints.append((t, edgePt))
                    flushGlow()
                    runPhase = phase.phase
                    runPoints.append((t, edgePt))
                } else {
                    runPoints.append((t, camera.project(turns: t, geo: geo)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutTurns, dayEndTurns)
                    runPoints.append((tEnd, camera.project(turns: tEnd, geo: geo)))
                    flushGlow()
                }
            }
            flushGlow()
        }
    }

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        // Data arcs respect the same render window as everything else.
        // Days outside the 7-day viewport window fade to zero and disappear.
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        // For the current (last) day, extend the cut to the cursor so awake phases
        // grow progressively as the day advances. For past days, stop at data end.
        let dataCutTurns = state.dataEndTurns
        let cursorCutTurns = cursorAbsHour.map { $0 / geo.period } ?? dataCutTurns
        let globalCutTurns = min(max(dataCutTurns, cursorCutTurns), upToTurns)

        // A run is a maximal sequence of 15-min phase intervals sharing the same SleepPhase.
        struct Run {
            var phase: SleepPhase
            var points: [(t: Double, pt: CGPoint)]
            var prevPhase: SleepPhase?
            var nextPhase: SleepPhase?
        }

        func isSleep(_ p: SleepPhase) -> Bool { p != .awake }

        func drawRun(_ run: Run, opacity: Double) {
            guard run.points.count >= 2 else { return }

            // E: Draw segment-by-segment with interpolated color gradient.
            // For sleep phases, the final 20% of each run blends toward the next phase color.
            // Awake arcs use a plain solid stroke (original behavior).
            let baseColor = phaseColor(run.phase)
            let nextColor = run.nextPhase.map { phaseColor($0) } ?? baseColor

            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                // FIX: Skip segments where either endpoint is behind camera
                guard !camera.isBehindCamera(turns: p0.t),
                      !camera.isBehindCamera(turns: p1.t) else { continue }
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = camera.perspectiveScale(turns: tSeg)
                let lw   = max(3.0, min(sc * 20.0, 28.0))
                // Blend toward nextColor in the final 20% of sleep runs
                let isSleepRun = run.phase != .awake
                let progress = (isSleepRun && run.points.count > 2)
                    ? Double(i) / Double(run.points.count - 2)
                    : 0.0
                let segColor = (isSleepRun && progress > 0.8)
                    ? blendColor(baseColor, nextColor, t: (progress - 0.8) / 0.2)
                    : baseColor

                var seg = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(segColor.opacity(opacity)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // For sleep runs, paint a round cap at the true start of the sleep block
            // (when previous phase is awake or this is the very first point on the spiral)
            // and at the true end. Awake runs don't need caps — sleep caps cover the joint.
            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart, !camera.isBehindCamera(turns: run.points[0].t) {
                let tFirst = run.points[0].t
                let sc = camera.perspectiveScale(turns: tFirst)
                let lw = max(3.0, min(sc * 20.0, 28.0))
                let r  = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(baseColor.opacity(opacity)))
            }
            if capEnd, !camera.isBehindCamera(turns: run.points[run.points.count - 1].t) {
                let tLast = run.points[run.points.count - 1].t
                let sc = camera.perspectiveScale(turns: tLast)
                let lw = max(3.0, min(sc * 20.0, 28.0))
                let r  = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(nextColor.opacity(opacity)))
            }
        }

        // The last record with actual sleep data gets a live awake extension up to cursorAbsHour.
        let lastRecord = records.last(where: { $0.sleepDuration > 0 })

        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            let dayEndTurns = geo.turns(day: record.day + 1, hour: 0)
            guard dayEndTurns >= fromTurns, dayStartTurns <= upToTurns else { continue }
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let vis = state.dayVisibility(for: record.day)
            // Data opacity: in-window → use visibility gradient. Out-of-window → skip.
            guard vis.isVisible, vis.opacity > 0.01 else { continue }
            let dataOpacity = vis.opacity
            let cutTurns = min(globalCutTurns, dayEndTurns)

            // Build all runs for this record.
            var runs: [Run] = []
            var runPhase  = phases[0].phase
            var runPoints: [(t: Double, pt: CGPoint)] = []
            var prevPhase: SleepPhase? = nil

            func flushRun(nextPhase: SleepPhase?) {
                guard runPoints.count >= 2 else { runPoints.removeAll(); return }
                runs.append(Run(phase: runPhase, points: runPoints, prevPhase: prevPhase, nextPhase: nextPhase))
                runPoints.removeAll()
            }

            for (i, phase) in phases.enumerated() {
                let t = geo.turns(day: record.day, hour: phase.hour)
                if t > cutTurns { break }
                if phase.phase != runPhase {
                    let edgePt = camera.project(turns: t, geo: geo)
                    runPoints.append((t, edgePt))
                    flushRun(nextPhase: phase.phase)
                    prevPhase = runPhase
                    runPhase  = phase.phase
                    runPoints.append((t, edgePt))
                } else {
                    runPoints.append((t, camera.project(turns: t, geo: geo)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutTurns, dayEndTurns)
                    runPoints.append((tEnd, camera.project(turns: tEnd, geo: geo)))
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            // For the last (current) day, extend a live awake run from wakeupHour to the cursor.
            // cursorAbsHour may be on a later calendar day than record.day (e.g. woke up yesterday,
            // it is now today), so we use absolute turns directly instead of day-relative hours.
            if record.id == lastRecord?.id,
               let cursorH = cursorAbsHour {
                let tCursor = cursorH / geo.period
                let tWake   = geo.turns(day: record.day, hour: record.wakeupHour)
                if tCursor > tWake + (0.25 / geo.period) {
                    // Step every 15 min for smooth rendering
                    var awakePoints: [(t: Double, pt: CGPoint)] = []
                    var t = tWake
                    let tStep = 0.25 / geo.period
                    while t <= tCursor {
                        awakePoints.append((t, camera.project(turns: t, geo: geo)))
                        t += tStep
                    }
                    // Ensure last point lands exactly on cursor
                    if awakePoints.last?.t ?? 0 < tCursor {
                        awakePoints.append((tCursor, camera.project(turns: tCursor, geo: geo)))
                    }
                    if awakePoints.count >= 2 {
                        runs.append(Run(phase: .awake, points: awakePoints, prevPhase: .light, nextPhase: nil))
                    }
                }
            }

            // Draw awake runs first, sleep runs on top so sleep caps always win at joints.
            for run in runs where !isSleep(run.phase) { drawRun(run, opacity: dataOpacity) }
            for run in runs where  isSleep(run.phase) { drawRun(run, opacity: dataOpacity) }
        }
    }

    private func drawCosinorOverlay(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            guard geo.turns(day: record.day + 1, hour: 0) >= fromTurns, dayStartTurns <= upToTurns else { continue }
            let vis = state.dayVisibility(for: record.day)
            guard vis.isVisible else { continue }
            let cosinor = record.cosinor
            let omega = (2 * Double.pi) / cosinor.period
            var path = Path()
            var started = false
            var h = 0.0
            while h <= period {
                let value = cosinor.mesor + cosinor.amplitude * cos(omega * (h - cosinor.acrophase))
                let offset = (value - 0.5) * 14.0
                let n = geo.normal(day: record.day, hour: h)
                let t = geo.turns(day: record.day, hour: h)
                // FIX: Skip behind-camera points in cosinor overlay
                if camera.isBehindCamera(turns: t) {
                    if started {
                        context.stroke(path, with: .color(SpiralColors.accent.opacity(0.7 * vis.opacity)), lineWidth: 1.2)
                        path = Path(); started = false
                    }
                    h += 1.0; continue
                }
                let projected = camera.project(turns: t, geo: geo)
                // Apply normal offset in screen space
                let nx = CGFloat(n.nx * offset)
                let ny = CGFloat(n.ny * offset)
                let pt = CGPoint(x: projected.x + nx, y: projected.y + ny)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
                h += 1.0
            }
            context.stroke(path, with: .color(SpiralColors.accent.opacity(0.7 * vis.opacity)), lineWidth: 1.2)
        }
    }

    private func drawTwoProcess(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        let tpPoints = TwoProcessModel.compute(records)
        var prevDay = -1
        var path = Path()
        var prevVis: DayVisibilityState? = nil
        for tp in tpPoints {
            let tpTurns = geo.turns(day: tp.day, hour: Double(tp.hour))
            guard geo.turns(day: tp.day + 1, hour: 0) >= fromTurns, tpTurns <= upToTurns else { continue }
            let vis = state.dayVisibility(for: tp.day)
            guard vis.isVisible else { continue }
            let t = geo.turns(day: tp.day, hour: Double(tp.hour))
            // FIX: Skip behind-camera points in two-process overlay
            guard !camera.isBehindCamera(turns: t) else { continue }
            let offset = (tp.c - 0.5) * 12.0
            let n = geo.normal(day: tp.day, hour: Double(tp.hour))
            let proj = camera.project(turns: t, geo: geo)
            let pt = CGPoint(x: proj.x + CGFloat(n.nx * offset), y: proj.y + CGFloat(n.ny * offset))
            let sColor = tp.s > 0.5 ? SpiralColors.poor : SpiralColors.good
            if tp.day != prevDay {
                if prevDay >= 0, let pv = prevVis {
                    context.stroke(path, with: .color(sColor.opacity(0.5 * pv.opacity)), lineWidth: 1)
                }
                path = Path(); path.move(to: pt); prevDay = tp.day; prevVis = vis
            } else { path.addLine(to: pt) }
        }
    }

    private func drawEventMarkers(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for event in events {
            let t = event.absoluteHour / geo.period
            guard Int(t) < geo.totalDays, t >= fromTurns, t <= upToTurns else { continue }
            guard !camera.isBehindCamera(turns: t) else { continue }
            let vis = state.dayVisibility(for: Int(t))
            guard vis.isVisible else { continue }
            let p = camera.project(turns: t, geo: geo)
            let color = Color(hex: event.type.hexColor)
            let r = 5.0
            let rect = CGRect(x: p.x - r/2, y: p.y - r/2, width: r, height: r)
            context.fill(Circle().path(in: rect), with: .color(color.opacity(vis.opacity)))
            context.stroke(Circle().path(in: rect.insetBy(dx: -1, dy: -1)),
                           with: .color(color.opacity(0.4 * vis.opacity)), lineWidth: 1)
        }
    }

    private func drawBiomarkers(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            guard geo.turns(day: record.day + 1, hour: 0) >= fromTurns, dayStartTurns <= upToTurns else { continue }
            let vis = state.dayVisibility(for: record.day)
            guard vis.isVisible else { continue }
            for marker in BiomarkerEstimation.estimatePersonalized(from: record) {
                let t = geo.turns(day: record.day, hour: marker.hour)
                guard !camera.isBehindCamera(turns: t) else { continue }
                let p = camera.project(turns: t, geo: geo)
                let color = Color(hex: marker.hexColor)

                // Draw confidence arc if available
                if let low = marker.confidenceLow, let high = marker.confidenceHigh {
                    let tLow = geo.turns(day: record.day, hour: low)
                    let tHigh = geo.turns(day: record.day, hour: high)
                    let steps = max(8, Int((tHigh - tLow) / 0.02))
                    var arcPath = Path()
                    var arcStarted = false
                    for i in 0...steps {
                        let frac = Double(i) / Double(steps)
                        let tArc = tLow + frac * (tHigh - tLow)
                        // FIX: Skip behind-camera points in confidence arc
                        if camera.isBehindCamera(turns: tArc) {
                            if arcStarted {
                                context.stroke(arcPath, with: .color(color.opacity(0.3 * vis.opacity)), lineWidth: 4)
                                arcPath = Path(); arcStarted = false
                            }
                            continue
                        }
                        let pArc = camera.project(turns: tArc, geo: geo)
                        if !arcStarted {
                            arcPath.move(to: CGPoint(x: pArc.x, y: pArc.y)); arcStarted = true
                        } else {
                            arcPath.addLine(to: CGPoint(x: pArc.x, y: pArc.y))
                        }
                    }
                    if arcStarted {
                        context.stroke(arcPath, with: .color(color.opacity(0.3 * vis.opacity)), lineWidth: 4)
                    }
                }

                // Draw diamond marker
                let s = 5.0
                var path = Path()
                path.move(to: CGPoint(x: p.x, y: p.y - s))
                path.addLine(to: CGPoint(x: p.x + s, y: p.y))
                path.addLine(to: CGPoint(x: p.x, y: p.y + s))
                path.addLine(to: CGPoint(x: p.x - s, y: p.y))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.8 * vis.opacity)))
            }
        }
    }

    /// Draws subtle dashed radial lines at the target wake and bedtime hours
    /// to give the user a visual reference for their rephase goal.
    private func drawTargetMarkers(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double) {
        guard targetWakeHour != nil || targetBedHour != nil else { return }
        // Use maxRadius so markers always reach the canvas edge regardless of zoom/visible turns.
        let outerR = geo.maxRadius + 20
        let hours: [(hour: Double, color: Color)] = [
            targetWakeHour.map { ($0, SpiralColors.awakeSleep.opacity(0.7)) },
            targetBedHour.map  { ($0, Color(hex: "7c3aed").opacity(0.6)) }
        ].compactMap { $0 }

        for (hour, color) in hours {
            let angle = (hour / geo.period) * 2 * Double.pi - Double.pi / 2
            let innerR = 14.0
            var path = Path()
            path.move(to: CGPoint(x: geo.cx + innerR * cos(angle),
                                  y: geo.cy + innerR * sin(angle)))
            path.addLine(to: CGPoint(x: geo.cx + outerR * cos(angle),
                                     y: geo.cy + outerR * sin(angle)))
            context.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round,
                                              dash: [4, 5]))
        }
    }

    // MARK: - Context Blocks

    /// Draws context block arcs (work, study, etc.) as subtle electric-blue background fills
    /// behind sleep data. Each block is rendered for every visible day where it is active.
    ///
    /// Visual spec:
    /// - Wide arc (12–32 px, scaled by perspective) in block color at opacity 0.18
    /// - Thin border (1.5 px) in block color at opacity 0.55
    /// - Respects perspectiveScale() for 3D consistency
    private func drawContextBlocks(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState) {
        let calendar = Calendar.current
        let enabledBlocks = contextBlocks.filter(\.isEnabled)
        guard !enabledBlocks.isEmpty else { return }

        let window = state.visibleWindow
        let upToTurns = state.renderUpToTurns

        // Iterate ONLY the effective visible day range from the render state,
        // not a loose 0..<maxDay loop. This ensures context blocks follow the
        // same visibility window as all other day-level rendering.
        for day in window.startIndex...window.endIndex {
            let ctxVis = state.contextVisibility(for: day)
            guard ctxVis.isVisible else { continue }

            // Determine weekday for this day ring
            let weekday: Int
            if day < records.count {
                weekday = calendar.component(.weekday, from: records[day].date)
            } else if let first = records.first {
                let estimated = calendar.date(byAdding: .day, value: day, to: first.date) ?? first.date
                weekday = calendar.component(.weekday, from: estimated)
            } else {
                continue
            }

            // Determine the sleep window for this day (bedtime → wakeup in clock hours).
            let sleepBed:  Double? = day < records.count ? records[day].bedtimeHour  : nil
            let sleepWake: Double? = day < records.count ? records[day].wakeupHour   : nil

            for block in enabledBlocks {
                guard block.isActive(weekday: weekday) else { continue }

                let color = Color(hex: block.type.hexColor)

                // Convert block start/end to turns on this day
                let tStart = geo.turns(day: day, hour: block.startHour)
                let tEnd: Double
                if block.endHour > block.startHour {
                    tEnd = geo.turns(day: day, hour: block.endHour)
                } else {
                    tEnd = geo.turns(day: day, hour: block.endHour + 24.0)
                }

                guard tEnd > 0 && tStart < upToTurns else { continue }
                let clampedStart = max(tStart, 0)
                let clampedEnd = min(tEnd, upToTurns)

                // Reduce opacity when block overlaps with recorded sleep.
                let blockOpacity: Double
                if let bed = sleepBed, let wake = sleepWake, bed >= 0, wake >= 0 {
                    let bedH  = bed.truncatingRemainder(dividingBy: 24)
                    let bStart = block.startHour
                    let bEnd   = block.endHour > block.startHour ? block.endHour : block.endHour + 24.0
                    let wEnd   = wake > bedH ? wake : wake + 24.0
                    let overlaps = bStart < wEnd && bEnd > bedH
                    blockOpacity = overlaps ? 0.22 : 0.75
                } else {
                    blockOpacity = 0.75
                }

                let arcSteps = max(12, Int((clampedEnd - clampedStart) * 60))
                let dashPattern = block.type.dashPattern.map { CGFloat($0) }
                for i in 0..<arcSteps {
                    let t0 = clampedStart + (clampedEnd - clampedStart) * Double(i)     / Double(arcSteps)
                    let t1 = clampedStart + (clampedEnd - clampedStart) * Double(i + 1) / Double(arcSteps)
                    // FIX: Skip behind-camera segments in context blocks
                    guard !camera.isBehindCamera(turns: t0),
                          !camera.isBehindCamera(turns: t1) else { continue }
                    let pt0 = camera.project(turns: t0, geo: geo)
                    let pt1 = camera.project(turns: t1, geo: geo)
                    let sc  = camera.perspectiveScale(turns: (t0 + t1) * 0.5)
                    let lw  = max(3.0, min(sc * 20.0, 28.0))
                    var seg = Path()
                    seg.move(to: pt0)
                    seg.addLine(to: pt1)
                    context.stroke(seg, with: .color(color.opacity(blockOpacity * ctxVis.opacity)),
                                   style: StrokeStyle(lineWidth: lw, lineCap: .round,
                                                      dash: dashPattern))
                }
            }
        }
    }

    // MARK: - Origin Anchor

    /// Draws the spiral origin (turn 0) as a structural anchor point.
    ///
    /// This is independent of the day visibility window — the origin uses its
    /// own visibility state from `SpiralVisibilityEngine.computeOriginVisibility`.
    ///
    /// **Marker rendering separation:**
    /// - The structural anchor (subtle neutral border ring) always renders when
    ///   `originVis.isVisible == true`.
    /// - The accent-colored dot (glow + fill in `SpiralColors.accent`) only renders
    ///   when `markers.shouldRenderOriginAccent == true` (default: `false`).
    /// - A debug dot only renders when `markers.shouldRenderOriginDebugDot == true`.
    private func drawOrigin(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, originVis: OriginVisibilityState, markers: MarkerRenderingState) {
        guard originVis.isVisible else { return }
        // FIX: Don't draw origin if behind camera
        guard !camera.isBehindCamera(turns: 0) else { return }

        // Project the origin (turn 0) to screen space.
        let p = camera.project(turns: 0, geo: geo)

        let r = originVis.screenRadius
        let opacity = originVis.opacity

        // Accent-colored elements — only when explicitly opted in.
        if markers.shouldRenderOriginAccent {
            // Outer glow ring
            let glowRect = CGRect(
                x: p.x - r * 1.8, y: p.y - r * 1.8,
                width: r * 3.6, height: r * 3.6
            )
            context.fill(
                Circle().path(in: glowRect),
                with: .color(SpiralColors.accent.opacity(0.15 * opacity))
            )

            // Solid circle
            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
            context.fill(
                Circle().path(in: rect),
                with: .color(SpiralColors.accent.opacity(0.6 * opacity))
            )
        }

        // Structural border ring — always drawn when origin is visible.
        // Uses a neutral white color, not the accent, so it serves as a
        // subtle positional anchor without introducing unwanted color.
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        context.stroke(
            Circle().path(in: rect),
            with: .color(Color.white.opacity(0.35 * opacity)),
            lineWidth: 1.0
        )

        // Debug dot — only when explicitly opted in.
        if markers.shouldRenderOriginDebugDot {
            let debugR: Double = 2.0
            let debugRect = CGRect(x: p.x - debugR, y: p.y - debugR, width: debugR * 2, height: debugR * 2)
            context.fill(
                Circle().path(in: debugRect),
                with: .color(Color.red.opacity(0.8))
            )
        }

        #if DEBUG
        print("[SpiralView] origin drawn at screen=(\(String(format: "%.0f", p.x)),\(String(format: "%.0f", p.y))) r=\(String(format: "%.1f", r)) opacity=\(String(format: "%.2f", opacity)) accent=\(markers.shouldRenderOriginAccent) debug=\(markers.shouldRenderOriginDebugDot)")
        #endif
    }

    private func drawHourLabels(context: GraphicsContext, geo: SpiralGeometry, size: CGSize) {
        let step: Double = geo.period <= 24 ? 3 : (geo.period / 8).rounded()
        // Place labels in a fixed circle just outside the spiral's outermost ring.
        // Draw in flat (non-projected) screen space so they always form a clean circle
        // regardless of depthScale. radius matches drawRadialLines outer edge.
        let labelR = geo.maxRadius + 16
        var h = 0.0
        while h < geo.period {
            let angle = (h / geo.period) * 2 * Double.pi - Double.pi / 2
            let pt = CGPoint(
                x: geo.cx + labelR * cos(angle),
                y: geo.cy + labelR * sin(angle)
            )
            let displayH = Int(h.rounded()) % 24
            let resolved = context.resolve(
                Text(String(format: "%02d", displayH))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(SpiralColors.subtle)
            )
            context.draw(resolved, at: pt)
            h += step
        }
    }

    private func drawSelectionRing(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, day: Int) {
        var path = Path()
        var started = false
        let steps = 60
        for i in 0...steps {
            let t = Double(day) + Double(i) / Double(steps)
            // FIX: Skip behind-camera points in selection ring
            if camera.isBehindCamera(turns: t) {
                if started { context.stroke(path, with: .color(SpiralColors.accent.opacity(0.4)), lineWidth: 1.5); path = Path(); started = false }
                continue
            }
            let pt = camera.project(turns: t, geo: geo)
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
        }
        if started {
            path.closeSubpath()
            context.stroke(path, with: .color(SpiralColors.accent.opacity(0.4)), lineWidth: 1.5)
        }
    }

    private func drawCursor(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, cursorState: CursorRenderState) {
        let t = cursorState.turnsPosition
        // FIX: Don't draw cursor if behind camera
        guard !camera.isBehindCamera(turns: t) else { return }
        let p = camera.project(turns: t, geo: geo)
        let opacity = cursorState.opacity
        #if DEBUG
        print("[SpiralAudit] drawCursor turns=\(String(format: "%.2f", t)) opacity=\(String(format: "%.2f", opacity)) screenPos=(\(String(format: "%.0f", p.x)),\(String(format: "%.0f", p.y)))")
        #endif
        let r = 6.0
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
        context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)),
                     with: .color(SpiralColors.accent.opacity(0.25 * opacity)))
        context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9 * opacity)), lineWidth: 1.5)
        context.fill(Circle().path(in: rect.insetBy(dx: 2, dy: 2)),
                     with: .color(SpiralColors.accent.opacity(opacity)))
    }

    private func drawSleepArc(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, from startH: Double, to endH: Double) {
        let lo = min(startH, endH), hi = max(startH, endH)
        guard hi - lo > 0.01 else { return }
        var path = Path()
        var started = false
        var h = lo
        while h <= hi {
            let t = h / geo.period
            // FIX: Skip behind-camera points in sleep arc
            if camera.isBehindCamera(turns: t) {
                if started {
                    context.stroke(path, with: .color(Color(hex: "7c3aed").opacity(0.85)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    context.stroke(path, with: .color(.white.opacity(0.15)),
                                   style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    path = Path(); started = false
                }
                h = min(h + 0.1, hi)
                if h >= hi { break }
                continue
            }
            let pt = camera.project(turns: t, geo: geo)
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            h = min(h + 0.1, hi)
            if h >= hi { break }
        }
        guard started else { return }
        context.stroke(path, with: .color(Color(hex: "7c3aed").opacity(0.85)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.stroke(path, with: .color(.white.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, size: CGSize) {
        guard !records.isEmpty else { return }
        let scaleDays = max(1, Int(ceil(spiralExtentTurns ?? Double(numDaysHint))))
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(size.width), height: Double(size.height),
            startRadius: startRadius, spiralType: spiralType, period: period,
            linkGrowthToTau: linkGrowthToTau
        )
        // Same retrospective model as drawSpiral:
        // Camera window ends at focusTurns, extends span turns into the past.
        let extent = spiralExtentTurns ?? Double(max(records.count, 1))
        let tapCursorTurns: Double? = cursorAbsHour.map { $0 / max(period, 1.0) }
        let tapFocus = viewportCenterTurns ?? (tapCursorTurns ?? extent)

        let tapSpan = 7.0

        // Camera: 7-turn retrospective (matches drawSpiral)
        let tapCamFrom = max(tapFocus - tapSpan, 0)
        let tapCamUpTo = tapFocus

        let cam = buildCamera(geo: geo, fromTurns: tapCamFrom, upToTurns: tapCamUpTo,
                              focusTurns: tapFocus)
        var bestDay: Int? = nil
        var bestDist = Double.infinity
        for d in 0..<records.count {
            let t = Double(d) + 0.5
            guard !cam.isBehindCamera(turns: t) else { continue }
            let p = cam.project(turns: t, geo: geo)
            let dx = Double(location.x) - p.x
            let dy = Double(location.y) - p.y
            let dist = sqrt(dx*dx + dy*dy)
            if dist < bestDist { bestDist = dist; bestDay = d }
        }
        if let day = bestDay, bestDist < 30 {
            onSelectDay(day == selectedDay ? nil : day)
        }
    }

    // MARK: - Helpers

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "7c3aed")  // violeta puro (sueño profundo)
        case .rem:   return Color(hex: "a78bfa")  // violeta claro (REM)
        case .light: return Color(hex: "c4b5fd")  // lila (sueño ligero)
        case .awake: return Color(hex: "fbbf24")  // ámbar cálido (vigilia)
        }
    }

    /// Glow color per phase — slightly more saturated/warm than the crisp stroke color.
    private func phaseGlowColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "6d28d9")  // deep indigo glow
        case .rem:   return Color(hex: "8b5cf6")  // violet glow
        case .light: return Color(hex: "a78bfa")  // soft purple glow
        case .awake: return Color(hex: "fbbf24")  // amber (unused — awake excluded from glow)
        }
    }

    /// Linear interpolation between two SwiftUI Colors in RGB space.
    private func blendColor(_ a: Color, _ b: Color, t: Double) -> Color {
        // Resolve to CGColor for component access
        #if canImport(UIKit)
        let ca = UIColor(a).cgColor
        let cb = UIColor(b).cgColor
        #else
        let ca = NSColor(a).cgColor
        let cb = NSColor(b).cgColor
        #endif
        let compsA = ca.components ?? [0, 0, 0, 1]
        let compsB = cb.components ?? [0, 0, 0, 1]
        let n = min(compsA.count, compsB.count)
        guard n >= 3 else { return t < 0.5 ? a : b }
        let r = compsA[0] + (compsB[0] - compsA[0]) * t
        let g = compsA[1] + (compsB[1] - compsA[1]) * t
        let bl = compsA[2] + (compsB[2] - compsA[2]) * t
        return Color(red: Double(r), green: Double(g), blue: Double(bl))
    }
}
