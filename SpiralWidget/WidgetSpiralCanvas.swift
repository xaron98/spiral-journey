import SwiftUI
import SpiralKit

/// Static, display-only spiral canvas for the widget.
/// Ported from WatchSpiralCanvas — same projection math, no interactive elements.
struct WidgetSpiralCanvas: View {
    let records: [SleepRecord]
    var spiralType: SpiralType = .logarithmic
    var period: Double = 24.0
    var depthScale: Double = 1.5
    var numDays: Int = 7
    var showHourLabels: Bool = true

    // Auto-computed from data (end of the last sleep record)
    private var spiralExtentTurns: Double {
        guard !records.isEmpty else { return 1.0 }
        var best = 1.0
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

    // Show the most recent ~5 days (or all data if less)
    private var visibleDays: Double {
        min(spiralExtentTurns, 5.0)
    }

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(hex: "0c0e14"))
            )

            let turns = max(spiralExtentTurns, 0.1)
            let scaleDays = max(1, Int(ceil(turns)))
            let geo = SpiralGeometry(
                totalDays: scaleDays,
                maxDays:   max(scaleDays, 7),
                width:     size.width,
                height:    size.height,
                startRadius: 5,
                spiralType: spiralType,
                period:    period
            )
            let maxVisible = min(turns, cameraMaxVisibleTurn(geo: geo))

            // Scale the spiral up to fill the widget area (same as Watch)
            let spiralScale: CGFloat = 2.6
            let tx = geo.cx * (1 - spiralScale)
            let ty = geo.cy * (1 - spiralScale)
            var scaledCtx = context
            scaledCtx.concatenate(CGAffineTransform(a: spiralScale, b: 0, c: 0, d: spiralScale, tx: tx, ty: ty))

            drawDayRings(context: scaledCtx, geo: geo, upToTurns: maxVisible)
            drawRadialLines(context: scaledCtx, geo: geo)
            drawDataPoints(context: scaledCtx, geo: geo)
            if showHourLabels {
                drawHourLabels(context: context, geo: geo)
            }
        }
    }

    // MARK: - Projection (identical to WatchSpiralCanvas)

    private func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
        let day = Int(t)
        let hr  = (t - Double(day)) * geo.period
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

    private func drawDayRings(context: GraphicsContext, geo: SpiralGeometry, upToTurns: Double) {
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
            path.addLine(to: CGPoint(
                x: geo.cx + canvasEdge * cos(angle),
                y: geo.cy + canvasEdge * sin(angle)
            ))
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

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry) {
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
            let maxLW  = max(2.0, geo.spacing * 0.65)
            let opac   = weekWindowOpacity(turns: run.points[0].t)
            guard opac > 0.01 else { return }

            for i in 0..<(run.points.count - 1) {
                let p0   = run.points[i]
                let p1   = run.points[i + 1]
                let tSeg = (p0.t + p1.t) * 0.5
                let sc   = perspectiveScale(turns: tSeg, geo: geo)
                let lw   = max(1.5, min(sc * maxLW, maxLW))
                var seg  = Path()
                seg.move(to: p0.pt)
                seg.addLine(to: p1.pt)
                context.stroke(seg, with: .color(color.opacity(opac)),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
            }

            guard isSleep(run.phase) else { return }
            let capStart = run.prevPhase == nil || !isSleep(run.prevPhase!)
            let capEnd   = run.nextPhase == nil || !isSleep(run.nextPhase!)
            if capStart {
                let sc = perspectiveScale(turns: run.points[0].t, geo: geo)
                let lw = max(1.5, min(sc * maxLW, maxLW))
                let r  = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
            if capEnd {
                let sc = perspectiveScale(turns: run.points[run.points.count - 1].t, geo: geo)
                let lw = max(1.5, min(sc * maxLW, maxLW))
                let r  = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
        }

        for record in records {
            let dayT   = Double(record.day)
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            let cutT   = min(globalCut, dayT + 1.0)

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

            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
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
                    .foregroundStyle(Color.white.opacity(0.35))
            )
            context.draw(resolved, at: pt)
            h += step
        }
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
