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
    var cursorAbsHour: Double? = nil
    var sleepStartHour: Double? = nil
    /// Maximum days for scale — fixes spacing so it never shifts as spiral grows
    var numDaysHint: Int = 30
    /// Fractional turns the path is drawn up to (for continuous growth effect)
    var cursorTurns: Double? = nil
    /// Number of days (turns) visible in the temporal perspective window.
    var visibleDays: Double? = nil
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


    @State private var canvasSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let turns = max(cursorTurns ?? Double(numDaysHint), 0.1)
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

    // MARK: - Projection

    /// Perspective projection. Camera looks at the spiral from outside.
    ///
    /// Z layout (INVERTED so the spiral grows outward visually):
    ///   turn totalT (outermost, newest) → wz = 0       (nearest to camera)
    ///   turn 0      (innermost, oldest) → wz = totalT*zStep (farthest from camera)
    ///   wz(t) = (totalT - t) * zStep
    ///
    /// Camera at camZ = -focalLen (behind the wz=0 plane).
    /// dz(t) = wz(t) - camZ = (totalT - t)*zStep + focalLen  → always positive.
    ///
    /// Zoom via visible: position camera so ring at turn (totalT - visible + 1) fills canvas.
    ///   We want scale(t_target) * r(t_target) = maxRadius
    ///   t_target = totalT - visible + 1  (visible=1 → outermost, visible=N → Nth from outside)
    ///   focalLen = dz_target * maxRadius / r(t_target)
    ///   dz_target = (totalT - t_target)*zStep + focalLen  →  focalLen cancels out,
    ///   so use moving-camera: camZ positioned so dz(t_target) = focalLen * r(t_target)/maxRadius
    ///
    /// Simpler moving-camera form:
    ///   camZ = -(totalT - t_target)*zStep - focalLen * r(t_target)/maxRadius + ... (complex)
    ///
    /// Cleanest: fix focalLen, move camera so t_target projects to maxRadius:
    ///   dz_target = focalLen * r(t_target) / maxRadius
    ///   camZ = wz(t_target) - dz_target = (totalT - t_target)*zStep - focalLen*r(t_target)/maxRadius
    private func project(turns t: Double, geo: SpiralGeometry, size: CGSize) -> CGPoint {
        let day = Int(t)
        let hr  = (t - Double(day)) * geo.period
        let flat = geo.point(day: day, hour: hr)

        let totalT  = max(cursorTurns ?? 1, 0.5)
        // Add a small margin so the outermost turn is never right at the camera plane
        let margin  = 0.35
        let visible = max((visibleDays ?? totalT) + margin, 1.0 + margin)

        let cx = geo.cx, cy = geo.cy
        let wx = flat.x - cx
        let wy = flat.y - cy

        // wz: outermost turn nearest (wz=0), innermost farthest
        let zStep = geo.maxRadius * depthScale
        // Use totalT + margin as the depth reference so the cursor turn always has positive dz
        let tRef = totalT + margin
        let wz   = (tRef - t) * zStep

        let focalLen = geo.maxRadius * 1.2

        // Target turn: visible=1+margin → turn 1 fills canvas; visible=N+margin → turn N fills.
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget

        let dz     = wz - camZ
        let safeDz = max(dz, focalLen * 0.05)

        let scale = focalLen / safeDz
        return CGPoint(
            x: cx + wx * scale,
            y: cy + wy * scale
        )
    }

    /// Maximum turn value visible in front of the camera (same margin as project()).
    private func cameraMaxVisibleTurn(geo: SpiralGeometry) -> Double {
        let totalT   = max(cursorTurns ?? 1, 0.5)
        let margin   = 0.35
        let tRef     = totalT + margin
        let visible  = max((visibleDays ?? totalT) + margin, 1.0 + margin)
        let zStep    = geo.maxRadius * depthScale
        let focalLen = geo.maxRadius * 1.2
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget
        // turns with wz > camZ are in front: (tRef-t)*zStep > camZ → t < tRef - camZ/zStep
        return tRef - camZ / zStep
    }

    // MARK: - Drawing

    private func drawSpiral(context: GraphicsContext, size: CGSize, geo: SpiralGeometry, upToTurns: Double? = nil) {
        let totalT  = upToTurns ?? Double(geo.totalDays)
        // Clip drawing to turns visible in front of camera (turns 0…maxVisible)
        let maxVisible = min(totalT, cameraMaxVisibleTurn(geo: geo))

        // 1. Day rings — always visible (outer circular hour frame)
        drawDayRings(context: context, geo: geo, upToTurns: maxVisible, size: size)
        // 2. Radial lines — controlled by grid toggle
        if showGrid {
            drawRadialLines(context: context, geo: geo, upToTurns: maxVisible)
        }
        // 3. Spiral backbone — clipped to visible turns
        drawSpiralPath(context: context, geo: geo, upToTurns: maxVisible, size: size)
        // 4. Two-process model
        if showTwoProcess {
            drawTwoProcess(context: context, geo: geo, size: size)
        }
        // 5. Data points (phase strokes)
        drawDataPoints(context: context, geo: geo, size: size)
        // 6. Cosinor overlay
        if showCosinor {
            drawCosinorOverlay(context: context, geo: geo, size: size)
        }
        // 7. Events
        drawEventMarkers(context: context, geo: geo, size: size)
        // 8. Biomarkers
        if showBiomarkers {
            drawBiomarkers(context: context, geo: geo, size: size)
        }
        // 9. Hour labels — always visible
        drawHourLabels(context: context, geo: geo, size: size)
        // 10. Selected day ring
        if let day = selectedDay {
            drawSelectionRing(context: context, geo: geo, day: day, size: size)
        }
        // 11. Sleep arc
        if let cursor = cursorAbsHour, let sleepStart = sleepStartHour {
            drawSleepArc(context: context, geo: geo, from: sleepStart, to: cursor, size: size)
        }
        // 12. Cursor dot
        if let cursor = cursorAbsHour {
            drawCursor(context: context, geo: geo, absHour: cursor, size: size)
        }
        // 13. Rephase target markers (subtle dashed radial lines)
        drawTargetMarkers(context: context, geo: geo, upToTurns: maxVisible)
    }

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, upToTurns: Double, size: CGSize) {
        for ring in geo.dayRings() where ring.day > 0 && Double(ring.day) >= fromTurns - 1 && Double(ring.day) <= upToTurns {
            let ringOpac = weekWindowOpacity(turns: Double(ring.day))
            guard ringOpac > 0.01 else { continue }
            let color = ring.isWeekBoundary
                ? Color.white.opacity(0.18 * ringOpac)
                : Color.white.opacity(0.09 * ringOpac)
            let lw: CGFloat = ring.isWeekBoundary ? 0.8 : 0.4

            var path = Path()
            let steps = 60
            for i in 0...steps {
                let t = Double(ring.day) + Double(i) / Double(steps)
                let pt = project(turns: t, geo: geo, size: size)
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            context.stroke(path, with: .color(color), lineWidth: lw)
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
            let opacity: Double = isMajor ? 0.18 : 0.09
            let lw: CGFloat    = isMajor ? 1.0 : 0.6
            context.stroke(path, with: .color(Color.white.opacity(opacity)), lineWidth: lw)
            h += minorStep
        }
    }

    /// Opacity for a turn `t` based on which "week window" is in focus.
    ///
    /// Focus week = the 7-turn window ending at `visibleDays` (or `cursorTurns`).
    /// - Turns in the focus week [focusEnd-7 … focusEnd]:  opacity 1.0
    /// - Turns in the previous week [focusEnd-14 … focusEnd-7]: opacity 0.4
    /// - Turns older than 2 weeks from focus:  opacity 0.0
    ///
    /// Transition between bands is softened over ±0.5 turns to avoid a hard cut.
    private func weekWindowOpacity(turns t: Double) -> Double {
        let focusEnd   = visibleDays ?? cursorTurns ?? Double(numDaysHint)
        let focusStart = focusEnd - 7.0          // start of focus week

        // Soft-step helper: ramps 0→1 over [edge-half … edge+half]
        func softStep(_ x: Double, edge: Double, half: Double = 0.5) -> Double {
            max(0.0, min(1.0, (x - (edge - half)) / (2 * half)))
        }

        if t >= focusStart {
            // Focus week: full opacity (with a small ramp-in from focusStart)
            return softStep(t, edge: focusStart + 0.5)
        } else {
            // Older than 2 weeks: invisible
            return 0.0
        }
    }

    /// Returns the perspective scale factor at a given turn value.
    /// This is the same `focalLen / dz` used in project(), giving a smooth
    /// continuous value we can use for linewidth scaling.
    private func perspectiveScale(turns t: Double, geo: SpiralGeometry) -> Double {
        let totalT  = max(cursorTurns ?? 1, 0.5)
        let margin  = 0.35
        let visible = max((visibleDays ?? totalT) + margin, 1.0 + margin)
        let zStep   = geo.maxRadius * depthScale
        let tRef    = totalT + margin
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

    /// Returns the spiral turn value where recorded phase data ends.
    /// Uses the same day+offset formula as drawDataPoints so both functions
    /// agree on exactly where the data boundary is regardless of geo.period (τ).
    private func dataEndTurns(geo: SpiralGeometry) -> Double {
        guard !records.isEmpty else { return 0.0 }
        var best = 0.0
        for r in records {
            let dayT     = Double(r.day)
            let dayStart = dayT * 24.0
            // Last phase that is sleep (not awake) — +0.25 to include that interval
            let endAbsH: Double
            if let lastSleep = r.phases.last(where: { $0.phase != .awake }) {
                endAbsH = dayStart + lastSleep.hour + 0.25
            } else {
                endAbsH = dayStart + r.wakeupHour
            }
            // Same formula as cutTurns in drawDataPoints
            let offsetH = endAbsH - dayStart
            let turns   = dayT + offsetH / geo.period
            if turns > best { best = turns }
        }
        return best
    }

    private func drawSpiralPath(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, upToTurns: Double, size: CGSize) {
        guard upToTurns > 0 else { return }

        // Hide backbone where phase data is drawn; show it from data end to cursor.
        let dataEndTurns = self.dataEndTurns(geo: geo)

        let step = 0.015
        var d = max(fromTurns, 0.0)
        var path = Path()
        var first = true

        var flushTurn: Double = 0

        func flush() {
            guard !first else { return }
            let opac = weekWindowOpacity(turns: flushTurn)
            if opac > 0.01 {
                context.stroke(path, with: .color(Color(hex: "2e3248").opacity(opac)),
                               style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            path = Path(); first = true
        }

        while d <= upToTurns {
            let t = min(d, upToTurns)
            // Only skip backbone in the range covered by phase data
            if t < dataEndTurns {
                flush()
                if d >= upToTurns { break }
                d += step; continue
            }
            flushTurn = t
            let pt = project(turns: t, geo: geo, size: size)
            if first { path.move(to: pt); first = false } else { path.addLine(to: pt) }
            if d >= upToTurns { break }
            d += step
        }
        flush()
    }

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, size: CGSize) {
        let globalCutTurns = dataEndTurns(geo: geo)

        // A run is a maximal sequence of 15-min phase intervals sharing the same SleepPhase.
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
            let opac  = weekWindowOpacity(turns: run.points[0].t)
            guard opac > 0.01 else { return }

            // Draw segment-by-segment with .round caps so each segment's rounded ends
            // overlap the next one seamlessly — no gaps, and lw tracks perspective
            // smoothly even across the long awake arc.
            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = perspectiveScale(turns: tSeg, geo: geo)
                let lw   = max(3.0, min(sc * 20.0, 28.0))

                var seg = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(color.opacity(opac)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            // For sleep runs, paint a round cap at the true start of the sleep block
            // (when previous phase is awake or this is the very first point on the spiral)
            // and at the true end. Awake runs don't need caps — sleep caps cover the joint.
            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)

            if capStart {
                let tFirst = run.points[0].t
                let sc = perspectiveScale(turns: tFirst, geo: geo)
                let lw = max(3.0, min(sc * 20.0, 28.0))
                let r  = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
            if capEnd {
                let tLast = run.points[run.points.count - 1].t
                let sc = perspectiveScale(turns: tLast, geo: geo)
                let lw = max(3.0, min(sc * 20.0, 28.0))
                let r  = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
        }

        for record in records {
            let dayT = Double(record.day)
            guard dayT + 1.0 >= fromTurns else { continue }
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let cutTurns = min(globalCutTurns, dayT + 1.0)

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
                let t = dayT + phase.hour / geo.period
                if t > cutTurns { break }
                if phase.phase != runPhase {
                    let edgePt = project(turns: t, geo: geo, size: size)
                    runPoints.append((t, edgePt))
                    flushRun(nextPhase: phase.phase)
                    prevPhase = runPhase
                    runPhase  = phase.phase
                    runPoints.append((t, edgePt))
                } else {
                    runPoints.append((t, project(turns: t, geo: geo, size: size)))
                }
                if i == phases.count - 1 {
                    let tEnd = min(cutTurns, dayT + 1.0)
                    runPoints.append((tEnd, project(turns: tEnd, geo: geo, size: size)))
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            // Draw awake runs first, sleep runs on top so sleep caps always win at joints.
            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
        }
    }

    private func drawCosinorOverlay(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, size: CGSize) {
        for record in records {
            guard Double(record.day) + 1.0 >= fromTurns else { continue }
            let cosinor = record.cosinor
            let omega = (2 * Double.pi) / cosinor.period
            var path = Path()
            var started = false
            var h = 0.0
            while h <= period {
                let value = cosinor.mesor + cosinor.amplitude * cos(omega * (h - cosinor.acrophase))
                let offset = (value - 0.5) * 14.0
                let n = geo.normal(day: record.day, hour: h)
                let t = Double(record.day) + h / geo.period
                let projected = project(turns: t, geo: geo, size: size)
                // Apply normal offset in screen space
                let nx = CGFloat(n.nx * offset)
                let ny = CGFloat(n.ny * offset)
                let pt = CGPoint(x: projected.x + nx, y: projected.y + ny)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
                h += 1.0
            }
            context.stroke(path, with: .color(SpiralColors.accent.opacity(0.7)), lineWidth: 1.2)
        }
    }

    private func drawTwoProcess(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, size: CGSize) {
        let tpPoints = TwoProcessModel.compute(records)
        var prevDay = -1
        var path = Path()
        for tp in tpPoints {
            guard Double(tp.day) + 1.0 >= fromTurns else { continue }
            let offset = (tp.c - 0.5) * 12.0
            let n = geo.normal(day: tp.day, hour: Double(tp.hour))
            let t = Double(tp.day) + Double(tp.hour) / geo.period
            let proj = project(turns: t, geo: geo, size: size)
            let pt = CGPoint(x: proj.x + CGFloat(n.nx * offset), y: proj.y + CGFloat(n.ny * offset))
            let sColor = tp.s > 0.5 ? SpiralColors.poor : SpiralColors.good
            if tp.day != prevDay {
                if prevDay >= 0 { context.stroke(path, with: .color(sColor.opacity(0.5)), lineWidth: 1) }
                path = Path(); path.move(to: pt); prevDay = tp.day
            } else { path.addLine(to: pt) }
        }
    }

    private func drawEventMarkers(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, size: CGSize) {
        for event in events {
            let t = event.absoluteHour / geo.period
            guard Int(t) < geo.totalDays, t >= fromTurns else { continue }
            let p = project(turns: t, geo: geo, size: size)
            let color = Color(hex: event.type.hexColor)
            let r = 5.0
            let rect = CGRect(x: p.x - r/2, y: p.y - r/2, width: r, height: r)
            context.fill(Circle().path(in: rect), with: .color(color))
            context.stroke(Circle().path(in: rect.insetBy(dx: -1, dy: -1)),
                           with: .color(color.opacity(0.4)), lineWidth: 1)
        }
    }

    private func drawBiomarkers(context: GraphicsContext, geo: SpiralGeometry, fromTurns: Double = 0, size: CGSize) {
        for record in records {
            guard Double(record.day) + 1.0 >= fromTurns else { continue }
            for marker in BiomarkerEstimation.estimate(from: record) {
                let t = Double(record.day) + marker.hour / geo.period
                let p = project(turns: t, geo: geo, size: size)
                let color = Color(hex: marker.hexColor)
                let s = 5.0
                var path = Path()
                path.move(to: CGPoint(x: p.x, y: p.y - s))
                path.addLine(to: CGPoint(x: p.x + s, y: p.y))
                path.addLine(to: CGPoint(x: p.x, y: p.y + s))
                path.addLine(to: CGPoint(x: p.x - s, y: p.y))
                path.closeSubpath()
                context.fill(path, with: .color(color.opacity(0.8)))
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
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            )
            context.draw(resolved, at: pt)
            h += step
        }
    }

    private func drawSelectionRing(context: GraphicsContext, geo: SpiralGeometry, day: Int, size: CGSize) {
        var path = Path()
        let steps = 60
        for i in 0...steps {
            let pt = project(turns: Double(day) + Double(i) / Double(steps), geo: geo, size: size)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(SpiralColors.accent.opacity(0.4)), lineWidth: 1.5)
    }

    private func drawCursor(context: GraphicsContext, geo: SpiralGeometry, absHour: Double, size: CGSize) {
        let t = absHour / geo.period
        let p = project(turns: t, geo: geo, size: size)
        let r = 6.0
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)
        context.fill(Circle().path(in: rect.insetBy(dx: -4, dy: -4)),
                     with: .color(SpiralColors.accent.opacity(0.25)))
        context.stroke(Circle().path(in: rect), with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        context.fill(Circle().path(in: rect.insetBy(dx: 2, dy: 2)),
                     with: .color(SpiralColors.accent))
    }

    private func drawSleepArc(context: GraphicsContext, geo: SpiralGeometry, from startH: Double, to endH: Double, size: CGSize) {
        let lo = min(startH, endH), hi = max(startH, endH)
        guard hi - lo > 0.01 else { return }
        var path = Path()
        var started = false
        var h = lo
        while h <= hi {
            let t = h / geo.period
            let pt = project(turns: t, geo: geo, size: size)
            if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
            h = min(h + 0.1, hi)
            if h >= hi { break }
        }
        context.stroke(path, with: .color(Color(hex: "7c3aed").opacity(0.85)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
        context.stroke(path, with: .color(.white.opacity(0.15)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, size: CGSize) {
        guard !records.isEmpty else { return }
        let scaleDays = max(1, Int(ceil(cursorTurns ?? Double(numDaysHint))))
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(size.width), height: Double(size.height),
            startRadius: startRadius, spiralType: spiralType, period: period,
            linkGrowthToTau: linkGrowthToTau
        )
        var bestDay: Int? = nil
        var bestDist = Double.infinity
        for d in 0..<records.count {
            let p = project(turns: Double(d) + 0.5, geo: geo, size: size)
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
}
