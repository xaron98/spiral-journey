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

    // Show the most recent 7 days
    private var visibleDays: Double {
        min(spiralExtentTurns, 7.0)
    }

    var body: some View {
        Canvas { context, size in
            // Background handled by .containerBackground on the widget —
            // no manual fill here to avoid a visible inner rectangle.

            let turns = max(spiralExtentTurns, 0.1)
            // Offset so only the last 7 turns fill the widget — no empty center
            let windowFrom = max(turns - 7, 0)
            let geo = SpiralGeometry(
                totalDays: max(Int(ceil(turns)), 7),
                maxDays:   7,
                width:     size.width,
                height:    size.height,
                startRadius: 0.5,
                spiralType: .archimedean,
                period:    period,
                turnOffset: windowFrom
            )

            drawDayRings(context: context, geo: geo, upToTurns: turns)
            drawRadialLines(context: context, geo: geo)
            drawDataPoints(context: context, geo: geo)
            if showHourLabels {
                drawHourLabels(context: context, geo: geo)
            }
        }
    }

    // MARK: - Projection (flat 2D — direct geometry)

    private func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
        let day = Int(t)
        let hr  = (t - Double(day)) * geo.period
        let pt = geo.point(day: day, hour: hr)
        return CGPoint(x: pt.x, y: pt.y)
    }

    private func weekWindowOpacity(turns t: Double) -> Double {
        // Widget shows all available data — no aggressive fading.
        // Only fade the very start slightly for visual depth.
        let extent = max(spiralExtentTurns, 1.0)
        let fraction = t / extent  // 0 = oldest, 1 = newest
        // Oldest data at 40% opacity, newest at 100%
        return 0.4 + fraction * 0.6
    }

    private func perspectiveScale(turns t: Double, geo: SpiralGeometry) -> Double {
        1.0  // Flat 2D — uniform line width
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
        // Limit to maxRadius so lines don't extend to the canvas edge
        // (which would create visible rectangular clipping at widget corners).
        let lineLen = geo.maxRadius
        let minorStep: Double = geo.period <= 24 ? 3 : (geo.period / 8).rounded()
        let majorStep: Double = minorStep * 2
        var h = 0.0
        while h < geo.period {
            let isMajor = h.truncatingRemainder(dividingBy: majorStep) < 0.001
            let angle   = (h / geo.period) * 2 * Double.pi - Double.pi / 2
            var path = Path()
            path.move(to: CGPoint(x: geo.cx, y: geo.cy))
            path.addLine(to: CGPoint(
                x: geo.cx + lineLen * cos(angle),
                y: geo.cy + lineLen * sin(angle)
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
            let cutT = dayT + 2.0  // allow overnight sleep

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
                let t = phase.timestamp / geo.period  // continuous, no midnight wrap
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
                    let tEnd = min(cutT, t + 0.25 / geo.period)  // extend 15 min past last phase
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
