import SwiftUI
import SpiralKit

// MARK: - WeekComparisonCard

/// Side-by-side mini spiral comparison of the last two 7-day windows.
/// Both helixes are drawn in a single Canvas so the drag gesture feeds
/// values directly into the drawing closure — no SwiftUI re-layout on each frame.
struct WeekComparisonCard: View {

    let records: [SleepRecord]
    let spiralType: SpiralType
    let period: Double

    @Environment(\.languageBundle) private var bundle

    // MARK: - Camera — @GestureState for zero-lag live drag, @State for committed values

    @GestureState private var dragDelta: CGSize = .zero
    @State private var committedElevation: Double = 0.12   // nearly side-on: helix axis vertical, coils clearly visible
    @State private var committedAzimuth: Double   = 0.3    // slight angle so coil depth is visible

    private var liveElevation: Double {
        max(0.05, min(.pi / 2, committedElevation - dragDelta.height * 0.007))
    }
    private var liveAzimuth: Double {
        committedAzimuth + dragDelta.width * 0.007
    }

    // MARK: - Week Selection

    /// How many weeks back from the latest. 0 = most recent pair, 1 = one week earlier, etc.
    @State private var weekOffset: Int = 0

    // MARK: - Data

    /// Records eligible for the comparison. Previously this filter
    /// required `sleepDuration >= 3.0`, which silently dropped short
    /// nights and left users with ≥ 14 records staring at a "necesitas
    /// 14 días" placeholder because their count of *eligible* nights
    /// had fallen below the threshold. Now we only drop completely
    /// empty records (no duration at all) — short nights still count.
    private var meaningful: [SleepRecord] {
        records.filter { $0.sleepDuration > 0 }.sorted { $0.day < $1.day }
    }

    /// Total number of full week pairs available.
    private var totalWeekPairs: Int { max(0, meaningful.count / 7 - 1) }

    private var hasEnoughData: Bool { meaningful.count >= 14 }

    private var thisWeekRaw: [SleepRecord] {
        let dropFromEnd = weekOffset * 7
        let available = meaningful.dropLast(dropFromEnd)
        return Array(available.suffix(7))
    }
    private var prevWeekRaw: [SleepRecord] {
        let dropFromEnd = weekOffset * 7
        let available = meaningful.dropLast(dropFromEnd)
        return Array(available.dropLast(7).suffix(7))
    }

    private var thisWeekRecords: [SleepRecord] { reIndex(thisWeekRaw) }
    private var prevWeekRecords: [SleepRecord] { reIndex(prevWeekRaw) }

    private var thisStats: SleepStats { SleepStatistics.calculateStats(thisWeekRaw) }
    private var prevStats: SleepStats { SleepStatistics.calculateStats(prevWeekRaw) }

    private var durationDelta: Double    { thisStats.meanSleepDuration - prevStats.meanSleepDuration }
    private var consistencyDelta: Double { (prevStats.stdBedtime - thisStats.stdBedtime) * 60 }

    private var overallTint: Color {
        let durBetter = durationDelta    >= 0.15
        let conBetter = consistencyDelta >= 5
        let durWorse  = durationDelta    <= -0.15
        let conWorse  = consistencyDelta <= -5
        if durBetter || conBetter { return SpiralColors.good }
        if durWorse  || conWorse  { return SpiralColors.poor }
        return SpiralColors.accentDim
    }

    private func weekLabelColor(isThisWeek: Bool) -> Color {
        let better = isThisWeek
            ? thisStats.stdBedtime < prevStats.stdBedtime
            : prevStats.stdBedtime < thisStats.stdBedtime
        if thisStats.stdBedtime == prevStats.stdBedtime { return SpiralColors.muted }
        return better ? SpiralColors.good : SpiralColors.poor
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Week navigation chevrons. The title was removed because the
            // parent `WeekVsWeekHero` already shows the section kicker
            // ("SEMANA VS SEMANA"), so duplicating it inside the card
            // produced two stacked headers saying the same thing.
            if totalWeekPairs > 0 {
                HStack(spacing: 12) {
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            weekOffset = min(weekOffset + 1, totalWeekPairs - 1)
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(weekOffset < totalWeekPairs - 1 ? SpiralColors.accent : SpiralColors.subtle)
                    }
                    .disabled(weekOffset >= totalWeekPairs - 1)

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            weekOffset = max(weekOffset - 1, 0)
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(weekOffset > 0 ? SpiralColors.accent : SpiralColors.subtle)
                    }
                    .disabled(weekOffset <= 0)
                }
            }

            if hasEnoughData {
                spiralRow
                statsRow
            } else {
                placeholderRow
            }
        }
        .padding(.vertical, 4)
        // No background — the card sits inside `WeekVsWeekHero`'s purple
        // gradient, so we let it show through instead of stacking a
        // second liquid-glass surface on top.
    }

    // MARK: - Spiral row (dual Canvas + drag)

    private var spiralRow: some View {
        // Capture mutable copies so the Canvas closure can read live values
        let prevRecs = prevWeekRecords
        let thisRecs = thisWeekRecords
        let elev     = liveElevation
        let az       = liveAzimuth

        return HStack(spacing: 0) {
            // Previous week label
            VStack(spacing: 6) {
                dualCanvas(prev: prevRecs, this: thisRecs, elevation: elev, azimuth: az)
                HStack(spacing: 0) {
                    Text(weekLabel(for: prevWeekRaw, isCurrent: false))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(weekLabelColor(isThisWeek: false))
                        .frame(width: 110, alignment: .center)
                    Spacer()
                    Text(weekLabel(for: thisWeekRaw, isCurrent: true))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(weekLabelColor(isThisWeek: true))
                        .frame(width: 110, alignment: .center)
                }
            }
        }
    }

    /// Single Canvas that draws both spirals side-by-side + delta column in the middle.
    /// The drag gesture lives here, one level above, feeding @GestureState → zero lag.
    @ViewBuilder
    private func dualCanvas(prev: [SleepRecord], this: [SleepRecord],
                             elevation: Double, azimuth: Double) -> some View {
        let spiralW: CGFloat = 110
        let spiralH: CGFloat = 165
        let gap:     CGFloat = 36   // space for delta column

        Canvas { ctx, size in
            // Left spiral (previous week)
            ctx.withCGContext { cg in
                cg.saveGState()
                cg.clip(to: CGRect(x: 0, y: 0, width: spiralW, height: spiralH)
                    .insetBy(dx: -0.5, dy: -0.5))
                cg.restoreGState()
            }

            // Draw previous week helix in left region
            var leftCtx = ctx
            leftCtx.translateBy(x: 0, y: 0)
            drawMiniHelix(in: &leftCtx,
                          canvasSize: CGSize(width: spiralW, height: spiralH),
                          records: prev,
                          elevation: elevation, azimuth: azimuth)

            // Draw this week helix in right region
            var rightCtx = ctx
            rightCtx.translateBy(x: spiralW + gap, y: 0)
            drawMiniHelix(in: &rightCtx,
                          canvasSize: CGSize(width: spiralW, height: spiralH),
                          records: this,
                          elevation: elevation, azimuth: azimuth)

            // Delta column — drawn directly in canvas coordinates
            let midX = spiralW + gap / 2
            drawDeltaColumn(in: &ctx, midX: midX, height: spiralH)
        }
        .frame(width: spiralW * 2 + gap, height: spiralH)
        .background(Color.clear)
        .gesture(
            DragGesture(minimumDistance: 2)
                .updating($dragDelta) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    committedElevation = max(0.05, min(.pi / 2,
                        committedElevation - value.translation.height * 0.007))
                    committedAzimuth  += value.translation.width * 0.007
                }
        )
    }

    // MARK: - Helix drawing (Canvas-level, no SwiftUI views)

    private func drawMiniHelix(in ctx: inout GraphicsContext,
                                canvasSize: CGSize,
                                records: [SleepRecord],
                                elevation: Double, azimuth: Double) {
        let w = canvasSize.width
        let h = canvasSize.height
        let cx = w / 2
        let cy = h / 2
        let fov = h * 2.2          // softer perspective so coils don't distort at low elevation
        let helixRadius = w * 0.38  // wider coils — clearly visible from the side
        let helixHeight = h * 0.88
        let turns: Double = 7.0

        // Rounded-rect clip
        ctx.clip(to: Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                          cornerRadius: 12))

        // Background
        ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                      cornerRadius: 12),
                 with: .color(SpiralColors.bg))

        // Cone taper: radius goes from small (bottom) to full (top)
        let minRadiusFrac = 0.35   // bottom of cone is 35% of max radius

        func coneRadius(_ frac: Double) -> Double {
            // frac 0 = bottom, 1 = top
            helixRadius * (minRadiusFrac + (1.0 - minRadiusFrac) * frac)
        }

        // Guide rings — flat circles in XZ plane at each day's Y position
        for day in 0...7 {
            let frac = Double(day) / turns          // 0 = bottom, 1 = top
            let yPos = (frac - 0.5) * helixHeight
            let r = coneRadius(frac)
            var ringPath = Path()
            let steps = 48
            for i in 0...steps {
                let angle = Double(i) / Double(steps) * 2 * .pi
                let pt = proj(r * cos(angle), yPos, r * sin(angle),
                              cx: cx, cy: cy, fov: fov,
                              elev: elevation, az: azimuth)
                if i == 0 { ringPath.move(to: pt) } else { ringPath.addLine(to: pt) }
            }
            ringPath.closeSubpath()
            ctx.stroke(ringPath,
                       with: .color(SpiralColors.border.opacity(day % 7 == 0 ? 0.4 : 0.18)),
                       lineWidth: day % 7 == 0 ? 0.8 : 0.4)
        }

        // Backbone — conical helix coils around Y axis
        let steps = Int(turns * 100)
        var backbone = Path()
        for i in 0...steps {
            let t = Double(i) / Double(steps) * turns
            let frac = t / turns
            let angle = t * 2 * .pi
            let yPos = (frac - 0.5) * helixHeight
            let r = coneRadius(frac)
            let pt = proj(r * cos(angle), yPos, r * sin(angle),
                          cx: cx, cy: cy, fov: fov,
                          elev: elevation, az: azimuth)
            if i == 0 { backbone.move(to: pt) } else { backbone.addLine(to: pt) }
        }
        ctx.stroke(backbone, with: .color(Color(hex: "3a4055")),
                   style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        ctx.stroke(backbone, with: .color(Color(hex: "8090b0").opacity(0.5)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // Phase overlay
        for record in records {
            let phases = record.phases
            guard !phases.isEmpty else { continue }
            var runPhase = phases[0].phase
            var path = Path()
            var started = false

            func commit() {
                guard started else { return }
                let c = phaseColor(runPhase)
                let lw: Double = runPhase == .awake ? 3.0 : 4.0
                ctx.stroke(path, with: .color(c.opacity(0.25)),
                           style: StrokeStyle(lineWidth: lw + 3, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(c.opacity(0.9)),
                           style: StrokeStyle(lineWidth: lw, lineCap: .round, lineJoin: .round))
                path = Path(); started = false
            }

            for (i, phase) in phases.enumerated() {
                if phase.phase != runPhase {
                    path.addLine(to: helixPt(day: record.day, hour: phase.hour,
                                             cx: cx, cy: cy, fov: fov,
                                             elev: elevation, az: azimuth,
                                             helixRadius: helixRadius,
                                             helixHeight: helixHeight, turns: turns))
                    commit(); runPhase = phase.phase
                }
                let pt = helixPt(day: record.day, hour: phase.hour,
                                 cx: cx, cy: cy, fov: fov,
                                 elev: elevation, az: azimuth,
                                 helixRadius: helixRadius,
                                 helixHeight: helixHeight, turns: turns)
                if !started { path.move(to: pt); started = true } else { path.addLine(to: pt) }
                if i == phases.count - 1 {
                    path.addLine(to: helixPt(day: record.day, hour: 24,
                                             cx: cx, cy: cy, fov: fov,
                                             elev: elevation, az: azimuth,
                                             helixRadius: helixRadius,
                                             helixHeight: helixHeight, turns: turns))
                    commit()
                }
            }
        }

        // Border overlay
        ctx.stroke(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: 12),
                   with: .color(SpiralColors.border.opacity(0.35)), lineWidth: 0.5)
    }

    /// Draw duration + consistency deltas as text in the gap between the two spirals.
    private func drawDeltaColumn(in ctx: inout GraphicsContext, midX: CGFloat, height: CGFloat) {
        // Duration
        let durColor: Color = abs(durationDelta) < 0.15 ? SpiralColors.muted
            : durationDelta > 0 ? SpiralColors.good : SpiralColors.poor
        let durText = abs(durationDelta) < 0.15 ? "—" : String(format: "%+.1fh", durationDelta)
        drawCenteredLabel(in: &ctx, text: "DUR", x: midX, y: height * 0.38,
                          style: .caption2, color: SpiralColors.muted)
        drawCenteredLabel(in: &ctx, text: durText, x: midX, y: height * 0.46,
                          style: .caption, color: durColor, bold: true)

        // Consistency
        let conColor: Color = abs(consistencyDelta) < 5 ? SpiralColors.muted
            : consistencyDelta > 0 ? SpiralColors.good : SpiralColors.poor
        let conText = abs(consistencyDelta) < 5 ? "—" : String(format: "%+.0fm", consistencyDelta)
        drawCenteredLabel(in: &ctx, text: "CON", x: midX, y: height * 0.56,
                          style: .caption2, color: SpiralColors.muted)
        drawCenteredLabel(in: &ctx, text: conText, x: midX, y: height * 0.64,
                          style: .caption, color: conColor, bold: true)
    }

    private func drawCenteredLabel(in ctx: inout GraphicsContext, text: String,
                                   x: CGFloat, y: CGFloat, style: Font,
                                   color: Color, bold: Bool = false) {
        let font = bold ? style.weight(.semibold).monospaced() : style.monospaced()
        let resolved = ctx.resolve(Text(text).font(font).foregroundStyle(color))
        ctx.draw(resolved, at: CGPoint(x: x, y: y))
    }

    // MARK: - Math helpers

    private func proj(_ x: Double, _ y: Double, _ z: Double,
                      cx: Double, cy: Double, fov: Double,
                      elev: Double, az: Double) -> CGPoint {
        let cosA = cos(az); let sinA = sin(az)
        let rx  = x * cosA + z * sinA
        let rz0 = -x * sinA + z * cosA
        let cosE = cos(elev); let sinE = sin(elev)
        let ry = y * cosE - rz0 * sinE
        let rz = y * sinE + rz0 * cosE
        let s = fov / (fov + rz)
        return CGPoint(x: cx + rx * s, y: cy - ry * s)
    }

    private func helixPt(day: Int, hour: Double,
                          cx: Double, cy: Double, fov: Double,
                          elev: Double, az: Double,
                          helixRadius: Double, helixHeight: Double, turns: Double) -> CGPoint {
        let t = Double(day) + hour / 24.0
        let frac = t / turns
        let angle = t * 2 * .pi
        let yPos = (frac - 0.5) * helixHeight
        let minRadiusFrac = 0.35
        let r = helixRadius * (minRadiusFrac + (1.0 - minRadiusFrac) * frac)
        return proj(r * cos(angle), yPos, r * sin(angle),
                    cx: cx, cy: cy, fov: fov, elev: elev, az: az)
    }

    private func phaseColor(_ phase: SleepPhase) -> Color {
        switch phase {
        case .deep:  return SpiralColors.deepSleep
        case .rem:   return SpiralColors.remSleep
        case .light: return SpiralColors.lightSleep
        case .awake: return SpiralColors.awakeSleep
        }
    }

    // MARK: - Stats + placeholder rows

    private var statsRow: some View {
        HStack(spacing: 0) {
            statsColumn(sleep: prevStats.meanSleepDuration,
                        bedtimeStdMin: prevStats.stdBedtime * 60,
                        alignment: .leading)
            Spacer()
            statsColumn(sleep: thisStats.meanSleepDuration,
                        bedtimeStdMin: thisStats.stdBedtime * 60,
                        alignment: .trailing)
        }
    }

    private var placeholderRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.headline)
                .foregroundStyle(SpiralColors.muted)
            Text(String(localized: "analysis.weekComparison.needMoreData", bundle: bundle))
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func statsColumn(sleep: Double, bedtimeStdMin: Double,
                              alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 3) {
            HStack(spacing: 4) {
                Text(String(localized: "analysis.weekComparison.avgSleep", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(sleep > 0 ? String(format: "%.1fh", sleep) : "—")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(SpiralColors.text)
            }
            HStack(spacing: 4) {
                Text(String(localized: "analysis.weekComparison.bedtimeStd", bundle: bundle))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(bedtimeStdMin > 0 ? String(format: "%.0fmin", bedtimeStdMin) : "—")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(SpiralColors.text)
            }
        }
    }

    // MARK: - Helpers

    private func reIndex(_ recs: [SleepRecord]) -> [SleepRecord] {
        recs.enumerated().map { idx, r in
            var copy = r; copy.day = idx; return copy
        }
    }

    /// Label for a week: "Esta semana" / "Anterior" when at offset 0,
    /// otherwise the date range (e.g. "3-9 mar").
    private func weekLabel(for recs: [SleepRecord], isCurrent: Bool) -> String {
        if weekOffset == 0 {
            return isCurrent
                ? String(localized: "analysis.weekComparison.thisWeek", bundle: bundle)
                : String(localized: "analysis.weekComparison.prevWeek", bundle: bundle)
        }
        guard let first = recs.first?.date, let last = recs.last?.date else {
            return "--"
        }
        let fmt = DateFormatter()
        fmt.dateFormat = "d"
        let startDay = fmt.string(from: first)
        fmt.dateFormat = "d MMM"
        let endDay = fmt.string(from: last)
        return "\(startDay)-\(endDay)"
    }
}
