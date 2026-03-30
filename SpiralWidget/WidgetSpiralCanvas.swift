import SwiftUI
import SpiralKit

/// Static, display-only spiral canvas for the widget.
struct WidgetSpiralCanvas: View {
    let records: [SleepRecord]
    var spiralType: SpiralType = .archimedean
    var period: Double = 24.0
    var numDays: Int = 7
    var nowTurns: Double = 0
    var showHourLabels: Bool = true

    private var spiralExtentTurns: Double {
        guard !records.isEmpty else { return 1.0 }
        return Double(records.count)
    }

    var body: some View {
        Canvas { context, size in
            let turns = max(spiralExtentTurns, 0.1)
            let scaleDays = max(1, Int(ceil(turns)))
            let geo = SpiralGeometry(
                totalDays: scaleDays,
                maxDays:   max(scaleDays, 15),
                width:     size.width,
                height:    size.height,
                startRadius: 1,
                spiralType: .archimedean,
                period:    period
            )

            drawDayRings(context: context, geo: geo, upToTurns: turns)
            drawDataPoints(context: context, geo: geo)
            drawLiveAwakeExtension(context: context, geo: geo)
        }
    }

    // MARK: - Projection (flat 2D)

    private func project(turns t: Double, geo: SpiralGeometry) -> CGPoint {
        let day = Int(t)
        let hr  = (t - Double(day)) * geo.period
        let pt = geo.point(day: day, hour: hr)
        return CGPoint(x: pt.x, y: pt.y)
    }

    private func weekWindowOpacity(turns t: Double) -> Double {
        let extent = max(spiralExtentTurns, 1.0)
        let fraction = t / extent
        return 0.4 + fraction * 0.6
    }

    private func perspectiveScale(turns t: Double, geo: SpiralGeometry) -> Double {
        1.0
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

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return Color(hex: "7c3aed")
        case .rem:   return Color(hex: "a78bfa")
        case .light: return Color(hex: "c4b5fd")
        case .awake: return Color(hex: "fbbf24")
        }
    }

    private func dataEndTurns(geo: SpiralGeometry) -> Double {
        guard let last = records.last else { return 0 }
        let dayT = Double(last.day)
        if let lastPhase = last.phases.last {
            return lastPhase.timestamp / geo.period
        }
        return dayT + last.wakeupHour / geo.period
    }

    private func drawDataPoints(context: GraphicsContext, geo: SpiralGeometry) {

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
                let lw   = maxLW
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
                let lw = maxLW
                let r  = lw * 0.5; let pt = run.points[0].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
            if capEnd {
                let lw = maxLW
                let r  = lw * 0.5; let pt = run.points[run.points.count - 1].pt
                context.fill(Circle().path(in: CGRect(x: pt.x - r, y: pt.y - r, width: lw, height: lw)),
                             with: .color(color.opacity(opac)))
            }
        }

        // Clip phases past "now" so the last record doesn't extend to midnight
        let clipT = nowTurns > 0 ? nowTurns : Double.greatestFiniteMagnitude

        for record in records {
            let phases = record.phases
            guard !phases.isEmpty else { continue }

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
                // Use timestamp for continuous t — no midnight wrapping
                let t = phase.timestamp / geo.period
                // Stop drawing past the current time
                if t > clipT { flushRun(nextPhase: nil); break }

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
                    let tEnd = min(t + 0.25 / geo.period, clipT)
                    runPts.append((tEnd, project(turns: tEnd, geo: geo)))
                    flushRun(nextPhase: nil)
                }
            }
            flushRun(nextPhase: nil)

            for run in runs where !isSleep(run.phase) { drawRun(run) }
            for run in runs where  isSleep(run.phase) { drawRun(run) }
        }
    }

    // MARK: - Live awake extension (amber path from data end to now)

    private func drawLiveAwakeExtension(context: GraphicsContext, geo: SpiralGeometry) {
        guard nowTurns > 0 else { return }
        let endT = dataEndTurns(geo: geo)
        guard nowTurns > endT else { return }

        let steps = max(Int((nowTurns - endT) * 60), 2)
        let maxLW = max(2.0, geo.spacing * 0.65)
        let color = Color(hex: "fbbf24") // amber, same as awake phase

        var path = Path()
        for i in 0...steps {
            let t  = endT + (nowTurns - endT) * Double(i) / Double(steps)
            let pt = project(turns: t, geo: geo)
            let opac = weekWindowOpacity(turns: t)
            if i == 0 {
                path.move(to: pt)
            } else {
                path.addLine(to: pt)
            }
            // Draw segment by segment for opacity variation
            if i > 0 {
                var seg = Path()
                let prevT = endT + (nowTurns - endT) * Double(i - 1) / Double(steps)
                seg.move(to: project(turns: prevT, geo: geo))
                seg.addLine(to: pt)
                context.stroke(seg, with: .color(color.opacity(opac)),
                               style: StrokeStyle(lineWidth: maxLW, lineCap: .round))
            }
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
}
