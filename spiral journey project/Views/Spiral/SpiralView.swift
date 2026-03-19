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
    /// Perspective power: 1.0 = standard 1/z, 0.5 = sqrt (softer cone, more even arm spacing).
    var perspectivePower: Double = 1.0
    /// Optional rephase target wake hour (0-24) — draws a subtle dashed radial line.
    var targetWakeHour: Double? = nil
    /// Optional rephase target bedtime hour (0-24) — draws a subtle dashed radial line.
    var targetBedHour: Double? = nil
    /// Whether to draw day ring and radial hour-line guides.
    var showGrid: Bool = true
    /// Inner radius of the spiral in points. Scale down for smaller screens (e.g. Watch: ~15).
    var startRadius: Double = 75
    /// Predicted bedtime hour for tonight (0-24). Draws dashed prediction arc if set.
    var predictedBedHour: Double? = nil
    /// Predicted wake hour for tonight (0-24). Draws dashed prediction arc if set.
    var predictedWakeHour: Double? = nil
    /// Growth animation progress (0→1). When < 1, the spiral draws only a fraction
    /// of its extent — creating an organic "growing from center" reveal on app launch.
    /// Default 1.0 = fully drawn (no animation).
    var growthProgress: Double = 1.0


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
        let perspPow: Double
        // Flat mode (zStep==0): radial zoom projection bounds, precomputed at init.
        let flatRInner: Double
        let flatROuter: Double
        let flatGeoMaxRadius: Double
        /// Minimum visible turn in flat mode — segments before this are culled
        /// by perspectiveScale() returning 0 so they don't pile up at radius 0.
        let flatCamFromTurns: Double

        /// Build camera that frames `[fromTurns, upToTurns]` with perspective.
        /// The outermost visible turn always projects at scale ≈ 1.0 so the
        /// spiral fills the clock-face grid area. depthScale only controls how
        /// much inner turns shrink (depth gradient).
        /// In flat mode (depthScale=0) a radial zoom projection is used instead:
        /// the visible band [fromTurns, upToTurns] is mapped to [0, maxRadius].
        init(fromTurns: Double, upToTurns: Double, focusTurns: Double,
             geo: SpiralGeometry, depthScale: Double, perspectivePower: Double = 1.0) {
            let zStep    = geo.maxRadius * depthScale
            let focalLen = geo.maxRadius * 1.2

            let margin = 0.5
            let tRef = upToTurns + margin

            // Anchor: outermost visible turn (upToTurns) → scale = 1.0
            // dz_front = margin * zStep - camZ  →  focalLen / dz_front = 1
            // ⇒ camZ = margin * zStep - focalLen
            let camZ = margin * zStep - focalLen

            self.tRef     = tRef
            self.zStep    = zStep
            self.focalLen = focalLen
            self.camZ     = camZ
            self.perspPow = perspectivePower

            // Flat mode: precompute radial projection bounds from the visible band.
            // Maps [rInner, rOuter] → [0, maxRadius] so the visible turns fill the canvas.
            if zStep == 0 {
                let tIn  = max(fromTurns, 0)
                let tOut = upToTurns                          // = tRef - margin
                let rIn  = max(geo.radius(turns: tIn), 1.0)
                let rOut = max(geo.radius(turns: tOut), rIn + 1.0)
                flatRInner       = rIn
                flatROuter       = rOut
                flatGeoMaxRadius = geo.maxRadius
                flatCamFromTurns = tIn
            } else {
                flatRInner = 0; flatROuter = 1; flatGeoMaxRadius = 0
                flatCamFromTurns = 0
            }
        }

        /// Project a turn value to screen coordinates.
        /// Pure perspective projection pivoting around geo.cx/cy — no XY offset.
        /// In flat mode uses radial zoom: visible band maps to [0, maxRadius].
        func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
            let theta = t * 2 * Double.pi
            let r     = geo.radius(turns: t)

            if zStep == 0 {
                // Flat mode: radial zoom — maps [rInner, rOuter] → [0, maxRadius]
                let mappedR = max(0.0, (r - flatRInner) / (flatROuter - flatRInner) * flatGeoMaxRadius)
                let ang     = theta - Double.pi / 2
                return CGPoint(x: geo.cx + mappedR * cos(ang),
                               y: geo.cy + mappedR * sin(ang))
            }

            let flatX = geo.cx + r * cos(theta - Double.pi / 2)
            let flatY = geo.cy + r * sin(theta - Double.pi / 2)

            let wx = flatX - geo.cx
            let wy = flatY - geo.cy
            let wz = (tRef - t) * zStep
            let dz = max(wz - camZ, focalLen * 0.05)
            let rawScale = focalLen / dz
            let scale = perspPow == 1.0 ? rawScale : pow(rawScale, perspPow)

            return CGPoint(x: geo.cx + wx * scale,
                           y: geo.cy + wy * scale)
        }

        /// Perspective scale factor at a given turn value (focalLen / dz).
        /// In flat mode returns 1.0 (normalized) so linewidths stay proportional
        /// to arm spacing, or 0.0 for turns before the visible band (culls them
        /// so they don't pile up at radius 0 and flood the canvas with colour).
        func perspectiveScale(turns t: Double) -> Double {
            if zStep == 0 {
                // Cull data that maps to negative radius (before visible window).
                if t < flatCamFromTurns { return 0.0 }
                return 1.0   // normalised — linewidth uses geo.spacing directly
            }
            let wz = (tRef - t) * zStep
            let dz = max(wz - camZ, focalLen * 0.05)
            let raw = focalLen / dz
            return perspPow == 1.0 ? raw : pow(raw, perspPow)
        }

        /// True when the given turn value is behind or too close to the camera.
        func isBehindCamera(turns t: Double) -> Bool {
            guard zStep > 0 else { return false }   // flat mode: nothing behind camera
            let wz = (tRef - t) * zStep
            let dz = wz - camZ
            return dz < focalLen * 0.1
        }

        /// Maximum turn value visible in front of the camera.
        var maxVisibleTurn: Double {
            guard zStep > 0 else { return .greatestFiniteMagnitude } // flat mode
            return tRef - camZ / zStep
        }

        /// Minimum perspectiveScale below which segments are culled.
        /// For sqrt perspective (perspPow < 1), the threshold is higher because
        /// scales are compressed into a narrower range.
        var cullThreshold: Double {
            perspPow == 1.0 ? 0.10 : pow(0.10, perspPow)
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
        // ── Simple model: camera follows cursor, opacity by distance ──
        let cursorT = cursorTurns ?? extentTurns
        let focusTurns = viewportCenterTurns ?? cursorT
        let span = visibleSpanTurns ?? 7.0
        let cameraZPadding = 0.5

        let camFrom = max(focusTurns - span, 0)
        // Camera follows cursor — zoom accompanies the focal point.
        let camUpTo = focusTurns + cameraZPadding

        let camera = CameraState(fromTurns: camFrom, upToTurns: camUpTo,
                                  focusTurns: focusTurns,
                                  geo: geo, depthScale: depthScale,
                                  perspectivePower: perspectivePower)

        let backboneCap = floor(cursorT) + 1.0   // extend backbone to midnight of cursor day

        // ── Growth animation clamp ──
        // growthProgress 0→1 limits how much of the spiral is drawn.
        // An ease-applied progress creates a smooth grow-from-center effect.
        let gp = min(max(growthProgress, 0), 1)
        let growthCutTurns = gp < 1.0 ? extentTurns * gp : Double.greatestFiniteMagnitude
        let growthBackboneCap = gp < 1.0 ? min(backboneCap, growthCutTurns) : backboneCap

        // Extend the viewport to always include all data so the spiral
        // never vanishes when scrolling to the past. The camera controls
        // perspective, but rendering covers the full extent.
        let renderUpTo = max(camUpTo, extentTurns + cameraZPadding)

        let state = SpiralVisibilityEngine.resolve(
            records: records,
            cursorAbsHour: cursorAbsHour,
            viewportFromTurns: camFrom,
            viewportUpToTurns: renderUpTo,
            cameraFromTurns: camFrom,
            cameraUpToTurns: renderUpTo,
            spiralExtentTurns: extentTurns,
            spiralPeriod: geo.period,
            cameraMaxTurn: camera.maxVisibleTurn,
            backboneCapTurn: growthBackboneCap
        )

        // ── Render pipeline ──
        // 1. Day rings — only draw rings within growth frontier
        drawDayRings(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        // 2. Radial lines
        if showGrid {
            let radialLimit = gp < 1.0 ? min(state.renderUpToTurns, growthCutTurns) : state.renderUpToTurns
            drawRadialLines(context: context, geo: geo, upToTurns: radialLimit)
        }
        // 3. Vigilia path — spiral structure always visible in camera range
        drawSpiralPath(context: context, geo: geo, camera: camera, state: state)
        // 4. Two-process model
        if showTwoProcess {
            drawTwoProcess(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        }
        // 5. Data points (phase strokes)
        drawDataPoints(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        // 6. Context blocks (blue bands) — visibility driven by render state
        if !contextBlocks.isEmpty && state.markerState.shouldRenderContextMarkers {
            drawContextBlocks(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        }
        // 7. Cosinor overlay
        if showCosinor {
            drawCosinorOverlay(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        }
        // 8. Events
        drawEventMarkers(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
        // 9. Biomarkers
        if showBiomarkers {
            drawBiomarkers(context: context, geo: geo, camera: camera, state: state, growthCutTurns: growthCutTurns)
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
        // 14. Cursor dot — only show when growth is complete (or nearly so)
        if gp > 0.95, let cursorSt = state.cursorState, cursorSt.shouldDraw {
            drawCursor(context: context, geo: geo, camera: camera, cursorState: cursorSt)
        }
        // 15. Rephase target markers
        if gp >= 1.0 {
            drawTargetMarkers(context: context, geo: geo, upToTurns: state.renderUpToTurns)
        }
        // 16. Prediction overlay — dashed arc for predicted sleep tonight
        if gp >= 1.0, let bedH = predictedBedHour, let wakeH = predictedWakeHour {
            drawPredictionOverlay(context: context, geo: geo, camera: camera, bedHour: bedH, wakeHour: wakeH)
        }

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

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        let edgeMargin = 1.5  // same as data segment fade
        let ringCameraSpan = upToTurns - fromTurns
        for ring in geo.dayRings() where ring.day > 0 && Double(ring.day) >= fromTurns - 2 && Double(ring.day) <= upToTurns && Double(ring.day) <= growthCutTurns {
            let vis = state.dayVisibility(for: ring.day)
            guard vis.isVisible, vis.opacity > 0.01 else { continue }
            let gridScale = colorScheme == .dark ? 1.0 : 1.3
            let baseOpacity = ring.isWeekBoundary ? 0.22 * gridScale : 0.11 * gridScale
            let lw: CGFloat = ring.isWeekBoundary ? 0.8 : 0.4

            // Draw per-segment with progressive edge fade (not per-day)
            var path = Path()
            var started = false
            var currentOpacity = 0.0
            let steps = 60
            for i in 0...steps {
                let t = Double(ring.day) + Double(i) / Double(steps)
                if t > growthCutTurns { break }
                if camera.isBehindCamera(turns: t) || camera.perspectiveScale(turns: t) < camera.cullThreshold {
                    if started {
                        context.stroke(path, with: .color(gridColor.opacity(baseOpacity * currentOpacity)), lineWidth: lw)
                        path = Path(); started = false
                    }
                    continue
                }
                // Per-point edge fade — skip only when zoomed in close to origin
                let edgeFade: Double
                if fromTurns <= 0.5 && ringCameraSpan <= 3.5 { edgeFade = 1.0 }
                else if t < fromTurns { edgeFade = 0.0 }
                else if t < fromTurns + edgeMargin { edgeFade = (t - fromTurns) / edgeMargin }
                else { edgeFade = 1.0 }
                let ptOpacity = vis.opacity * edgeFade

                // Flush when opacity changes significantly (creates gradient effect)
                if started && abs(ptOpacity - currentOpacity) > 0.08 {
                    context.stroke(path, with: .color(gridColor.opacity(baseOpacity * currentOpacity)), lineWidth: lw)
                    path = Path(); started = false
                }

                let pt = camera.project(turns: t, geo: geo)
                // 3D only: skip points too close to center (fragment rings in sqrt perspective)
                if camera.zStep > 0 && hypot(pt.x - geo.cx, pt.y - geo.cy) < 25 {
                    if started {
                        context.stroke(path, with: .color(gridColor.opacity(baseOpacity * currentOpacity)), lineWidth: lw)
                        path = Path(); started = false
                    }
                    continue
                }
                // Clip to canvas: break ring arc when projected point exits canvas bounds.
                if pt.x < -20 || pt.x > geo.width + 20 || pt.y < -20 || pt.y > geo.height + 20 {
                    if started {
                        context.stroke(path, with: .color(gridColor.opacity(baseOpacity * currentOpacity)), lineWidth: lw)
                        path = Path(); started = false
                    }
                    continue
                }
                if !started {
                    path.move(to: pt); started = true; currentOpacity = ptOpacity
                } else {
                    path.addLine(to: pt)
                }
            }
            if started { context.stroke(path, with: .color(gridColor.opacity(baseOpacity * currentOpacity)), lineWidth: lw) }
        }
    }

    private func drawRadialLines(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double) {
        // Lines go from center to the actual canvas edge.
        // Use the canvas diagonal so lines always reach the corner.
        let canvasEdge = max(geo.width, geo.height)
        // Major lines every 6h (00, 06, 12, 18) — more visible
        // Minor lines every 3h (03, 09, 15, 21) — more subtle, like the web version
        // Do NOT round for non-24h periods: rounding 25.4/8=3.175 → 3.0 allows h=24
        // into the loop, creating a duplicate 00:00 line at a slightly wrong angle.
        let minorStep: Double = geo.period <= 24 ? 3 : geo.period / 8
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
        // Backbone skip: only skip where data arcs are opaque enough to cover the backbone.
        // Where data is fading (camera edge, cursor distance), the backbone draws through,
        // creating the same smooth continuous path as when there are no records.
        let skipFrom: Double
        let skipTo: Double
        if state.dataBounds.hasData {
            let overlapFirst = max(state.dataBounds.firstDayIndex, state.visibleWindow.startIndex)
            let overlapLast  = min(state.dataBounds.lastDayIndex,  state.visibleWindow.endIndex)
            if overlapFirst <= overlapLast {
                // Narrow the skip to only days where data is prominently visible
                var first = overlapLast + 1
                var last  = overlapFirst - 1
                for d in overlapFirst...overlapLast {
                    let vis = state.dayVisibility(for: d)
                    if vis.opacity > 0.35 {
                        first = min(first, d)
                        last  = max(last, d)
                    }
                }
                if first <= last {
                    skipFrom = Double(first)
                    skipTo   = Double(last + 1)
                } else {
                    skipFrom = 0; skipTo = 0
                }
            } else {
                skipFrom = 0; skipTo = 0
            }
        } else {
            skipFrom = 0; skipTo = 0
        }
        // Backbone limited to 7 turns before cursor — never show more than a week
        let backboneFrom = max(state.backboneClipTurns - 7.0, 0)
        drawSpiralPath(context: context, geo: geo, camera: camera,
                       fromTurns: backboneFrom,
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
                ? Color(hex: "2e3248").opacity(0.4)
                : Color(red: 0.7, green: 0.72, blue: 0.78).opacity(0.3)
            context.stroke(path, with: .color(pathColor),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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
            // Skip behind-camera or extremely compressed points — prevents
            // disconnected backbone fragments floating at the spiral center.
            if camera.isBehindCamera(turns: t) || camera.perspectiveScale(turns: t) < camera.cullThreshold {
                flush()
                if d >= upToTurns { break }
                d += step; continue
            }
            let pt = camera.project(turns: t, geo: geo)
            // 3D only: skip points that project too close to center — prevents
            // disconnected fragments when sqrt perspective compresses old turns.
            // Use a dynamic threshold that scales with perspective: compressed
            // points (low perspScale) need a larger exclusion zone.
            if camera.zStep > 0 {
                let centerDist = hypot(pt.x - geo.cx, pt.y - geo.cy)
                let pScale = camera.perspectiveScale(turns: t)
                let dynamicThreshold = max(35.0, 25.0 / max(pScale, 0.05))
                if centerDist < dynamicThreshold {
                    flush()
                    if d >= upToTurns { break }
                    d += step; continue
                }
            }
            // Clip to canvas: Archimedean arms can extend far beyond canvas in 3D mode.
            // Break the path when projected point exits canvas bounds to prevent edge artifacts.
            if pt.x < -20 || pt.x > geo.width + 20 || pt.y < -20 || pt.y > geo.height + 20 {
                flush()
                if d >= upToTurns { break }
                d += step; continue
            }
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

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        // For the current (last) day, extend the cut to the cursor so awake phases
        // grow progressively as the day advances. For past days, stop at data end.
        let dataCutTurns = state.dataEndTurns
        let cursorCutTurns = cursorAbsHour.map { $0 / geo.period } ?? dataCutTurns
        let globalCutTurns = min(min(max(dataCutTurns, cursorCutTurns), upToTurns), growthCutTurns)

        // A run is a maximal sequence of 15-min phase intervals sharing the same SleepPhase.
        struct Run {
            var phase: SleepPhase
            var points: [(t: Double, pt: CGPoint)]
            var prevPhase: SleepPhase?
            var nextPhase: SleepPhase?
        }

        func isSleep(_ p: SleepPhase) -> Bool { p != .awake }

        // Per-segment edge fade: smooth progressive fade at the camera boundary,
        // matching the backbone's natural perspective fade (point-by-point, not per-day).
        // When zoomed in close to origin (small span), data is solid — no inner edge fade.
        // When zoomed out (large span), edge fade applies everywhere to prevent
        // orphan data fragments appearing as a chunk at the origin.
        let cameraSpan = upToTurns - fromTurns
        func segmentEdgeFade(t: Double) -> Double {
            // Only skip edge fade when zoomed in close to origin
            guard fromTurns > 0.5 || cameraSpan > 3.5 else { return 1.0 }
            let margin = 1.5
            if t < fromTurns { return 0.0 }
            if t < fromTurns + margin { return (t - fromTurns) / margin }
            return 1.0
        }

        func drawRun(_ run: Run, opacity: Double, applyEdgeFade: Bool = true) {
            guard run.points.count >= 2 else { return }

            let baseColor = phaseColor(run.phase)
            let nextColor = run.nextPhase.map { phaseColor($0) } ?? baseColor

            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                guard !camera.isBehindCamera(turns: p0.t),
                      !camera.isBehindCamera(turns: p1.t) else { continue }
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = camera.perspectiveScale(turns: tSeg)
                guard sc > 0.04 else { continue } // too compressed by perspective — skip
                // Cap stroke to 82% of projected arm spacing so adjacent arms
                // always have a visible dark gap, both in 2D and 3D.
                let lw   = max(2.0, min(sc * 20.0, geo.spacing * sc * 0.82))
                let segOpacity = applyEdgeFade ? opacity * segmentEdgeFade(t: tSeg) : opacity
                guard segOpacity > 0.01 else { continue }
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
                context.stroke(seg, with: .color(segColor.opacity(segOpacity)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart, !camera.isBehindCamera(turns: run.points[0].t) {
                let tFirst = run.points[0].t
                let sc = camera.perspectiveScale(turns: tFirst)
                guard sc > 0.04 else { return }
                let capFade = applyEdgeFade ? segmentEdgeFade(t: tFirst) : 1.0
                let lw = max(2.0, min(sc * 20.0, geo.spacing * sc * 0.82))
                let r  = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(baseColor.opacity(opacity * capFade)))
            }
            if capEnd, !camera.isBehindCamera(turns: run.points[run.points.count - 1].t) {
                let tLast = run.points[run.points.count - 1].t
                let sc = camera.perspectiveScale(turns: tLast)
                guard sc > 0.04 else { return }
                let capFade = applyEdgeFade ? segmentEdgeFade(t: tLast) : 1.0
                let lw = max(2.0, min(sc * 20.0, geo.spacing * sc * 0.82))
                let r  = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(nextColor.opacity(opacity * capFade)))
            }
        }

        // The last record with actual sleep data gets a live awake extension up to cursorAbsHour.
        let lastRecord = records.last(where: { $0.sleepDuration > 0 })

        for record in records {
            let isLastRecord = record.id == lastRecord?.id
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            let dayEndTurns = geo.turns(day: record.day + 1, hour: 0)
            // Widen range by 1 turn so partial days aren't skipped as chunks.
            // Per-segment isBehindCamera + edge fade handle the actual clipping.
            guard (dayEndTurns >= fromTurns - 1 && dayStartTurns <= upToTurns + 1) || isLastRecord else { continue }
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let vis = state.dayVisibility(for: record.day)
            guard (vis.isVisible && vis.opacity > 0.01) || isLastRecord else { continue }

            // Edge fade is now per-segment in drawRun — not per-day.
            // Last record always visible — it's the most recent sleep data.
            let dataOpacity = isLastRecord ? max(vis.opacity, 0.35) : vis.opacity
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

            // Build data runs — always for the last record (sleep data must not vanish)
            if (vis.isVisible && vis.opacity > 0.01) || isLastRecord {
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
            }

            // For the last (current) day, extend a live awake run from where the
            // recorded data ends to the cursor. Starting from cutTurns (not wakeup)
            // avoids drawing on top of recorded sleep data — the data already contains
            // awake phases from wakeup onwards.
            var liveAwakeRun: Run? = nil
            if isLastRecord, let cursorH = cursorAbsHour {
                let tCursor = cursorH / geo.period
                // Start where recorded data ends, not from wakeup — prevents
                // the awake extension from covering sleep data at the same turns.
                let tWakeRaw = geo.turns(day: record.day, hour: record.wakeupHour)
                let tDataEnd = cutTurns  // recorded data already covers up to here
                let tStart = max(tDataEnd, tWakeRaw)
                // Limit awake extension to 7 turns max — same as data visibility window
                let tWake = max(tStart, tCursor - 7.0)
                if tCursor > tWake + (0.25 / geo.period) {
                    var awakePoints: [(t: Double, pt: CGPoint)] = []
                    var t = tWake
                    let tStep = 0.25 / geo.period
                    while t <= tCursor {
                        guard !camera.isBehindCamera(turns: t) else { t += tStep; continue }
                        awakePoints.append((t, camera.project(turns: t, geo: geo)))
                        t += tStep
                    }
                    if let last = awakePoints.last?.t, last < tCursor, !camera.isBehindCamera(turns: tCursor) {
                        awakePoints.append((tCursor, camera.project(turns: tCursor, geo: geo)))
                    }
                    if awakePoints.count >= 2 {
                        liveAwakeRun = Run(phase: .awake, points: awakePoints, prevPhase: .light, nextPhase: nil)
                    }
                }
            }

            // Draw order: awake data → live awake extension → sleep data
            // Sleep phases render ON TOP so they're never hidden by yellow awake lines.
            let skipEdge = isLastRecord
            for run in runs where !isSleep(run.phase) { drawRun(run, opacity: dataOpacity, applyEdgeFade: !skipEdge) }

            // Live awake extension (yellow, full opacity) draws between awake data and sleep data.
            if let liveRun = liveAwakeRun {
                drawRun(liveRun, opacity: 1.0, applyEdgeFade: false)
            }

            // Sleep data always on top — never covered by awake extension
            for run in runs where  isSleep(run.phase) { drawRun(run, opacity: dataOpacity, applyEdgeFade: !skipEdge) }

        }
    }

    private func drawCosinorOverlay(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            guard geo.turns(day: record.day + 1, hour: 0) >= fromTurns, dayStartTurns <= upToTurns, dayStartTurns <= growthCutTurns else { continue }
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

    private func drawTwoProcess(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        let tpPoints = TwoProcessModel.compute(records)
        var prevDay = -1
        var path = Path()
        var prevVis: DayVisibilityState? = nil
        for tp in tpPoints {
            let tpTurns = geo.turns(day: tp.day, hour: Double(tp.hour))
            guard geo.turns(day: tp.day + 1, hour: 0) >= fromTurns, tpTurns <= upToTurns, tpTurns <= growthCutTurns else { continue }
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

    private func drawEventMarkers(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for event in events {
            let t = event.absoluteHour / geo.period
            guard Int(t) < geo.totalDays, t >= fromTurns, t <= upToTurns, t <= growthCutTurns else { continue }
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

    private func drawBiomarkers(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let fromTurns = state.renderFromTurns
        let upToTurns = state.renderUpToTurns
        for record in records {
            let dayStartTurns = geo.turns(day: record.day, hour: 0)
            guard geo.turns(day: record.day + 1, hour: 0) >= fromTurns, dayStartTurns <= upToTurns, dayStartTurns <= growthCutTurns else { continue }
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

    // MARK: - Prediction Overlay

    /// Draws a dashed prediction arc showing predicted sleep for tonight.
    /// Appears as a translucent purple dashed arc on the current/next spiral turn.
    private func drawPredictionOverlay(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState,
                                        bedHour: Double, wakeHour: Double) {
        // Place prediction on the cursor's current day
        guard let cursorH = cursorAbsHour else { return }
        let dayBase = floor(cursorH / geo.period) * geo.period

        let bedAbs = dayBase + bedHour
        let wakeAbs: Double = {
            let w = dayBase + wakeHour
            return w <= bedAbs ? w + geo.period : w
        }()

        let bedTurns = bedAbs / geo.period
        let wakeTurns = wakeAbs / geo.period

        // Perspective guard
        let sc = camera.perspectiveScale(turns: bedTurns)
        guard sc > 0.10 else { return }

        let steps = 40
        let tRange = wakeTurns - bedTurns
        guard tRange > 0 else { return }

        var path = Path()
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let t = bedTurns + frac * tRange
            let pt = camera.project(turns: t, geo: geo)
            if i == 0 { path.move(to: pt) }
            else { path.addLine(to: pt) }
        }

        let lw = max(4.0, min(sc * 14.0, 18.0))
        context.stroke(path, with: .color(Color(hex: "a78bfa").opacity(0.35)),
                       style: StrokeStyle(lineWidth: lw, lineCap: .round, dash: [6, 4]))
    }

    // MARK: - Context Blocks

    /// Draws context block arcs (work, study, etc.) as subtle electric-blue background fills
    /// behind sleep data. Each block is rendered for every visible day where it is active.
    ///
    /// Visual spec:
    /// - Wide arc (12–32 px, scaled by perspective) in block color at opacity 0.18
    /// - Thin border (1.5 px) in block color at opacity 0.55
    /// - Respects perspectiveScale() for 3D consistency
    private func drawContextBlocks(context: GraphicsContext, geo: SpiralGeometry, camera: CameraState, state: SpiralRenderState, growthCutTurns: Double = .greatestFiniteMagnitude) {
        let calendar = Calendar.current
        let enabledBlocks = contextBlocks.filter(\.isEnabled)
        guard !enabledBlocks.isEmpty else { return }

        let window = state.visibleWindow
        let upToTurns = state.renderUpToTurns

        // Iterate ONLY the effective visible day range from the render state,
        // not a loose 0..<maxDay loop. This ensures context blocks follow the
        // same visibility window as all other day-level rendering.
        for day in window.startIndex...window.endIndex {
            let dayTurns = Double(day)
            guard dayTurns <= growthCutTurns else { continue }
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
                // Clip context blocks to cursor position — don't draw ahead of cursor
                let cursorClipTurns = cursorAbsHour.map { $0 / geo.period } ?? upToTurns
                let clampedStart = max(tStart, 0)
                let clampedEnd = min(tEnd, upToTurns, cursorClipTurns)
                guard clampedEnd > clampedStart else { continue }

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

        // Structural border ring removed — visual noise at the origin.

        // Debug dot — only when explicitly opted in.
        if markers.shouldRenderOriginDebugDot {
            let debugR: Double = 2.0
            let debugRect = CGRect(x: p.x - debugR, y: p.y - debugR, width: debugR * 2, height: debugR * 2)
            context.fill(
                Circle().path(in: debugRect),
                with: .color(Color.red.opacity(0.8))
            )
        }

    }

    private func drawHourLabels(context: GraphicsContext, geo: SpiralGeometry, size: CGSize) {
        // Do NOT round for non-24h periods: same fix as drawRadialLines — prevents
        // a duplicate 00:00 label appearing at a slightly-offset angular position.
        let step: Double = geo.period <= 24 ? 3 : geo.period / 8
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
        guard !camera.isBehindCamera(turns: t) else { return }
        let p = camera.project(turns: t, geo: geo)
        let opacity = cursorState.opacity
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
