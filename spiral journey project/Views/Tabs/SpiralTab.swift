import SwiftUI
import SpiralKit

/// Main spiral tab — full-screen spiral with contextual greeting, sleep logging,
/// consistency score card, mini stats, and event grid.
struct SpiralTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Binding var selectedTab: AppTab

    @State private var selectedDay: Int? = nil
    @State private var showCosinor    = false
    @State private var showBiomarkers = false
    @State private var showTwoProcess = false

    // Sleep logging
    @State private var cursorAbsHour: Double = 0
    @State private var sleepStartHour: Double? = nil
    @State private var maxReachedTurns: Double = 1.0
    @State private var visibleDays: Double = 1
    @State private var liveVisibleDays: Double = 1
    @State private var pinchBaseVisibleDays: Double = 1
    private let minVisibleDays: Double = 0.15
    @State private var pinchStarted: Bool = false
    // Zoom slider: normalised 0→1 in log-space. Derived from visibleDays when not dragging.
    @State private var zoomNorm: Double = 1.0
    @State private var spiralType: SpiralType = .archimedean
    @State private var showEventSheet = false

    // Consistency detail navigation
    @State private var showConsistencyDetail = false
    // Event sheet
    @State private var showEventSheet2 = false
    // Rephase editor sheet
    @State private var showRephaseEditor = false

    var body: some View {
        @Bindable var store = store
        let maxDays = max(store.numDays, 1)

        NavigationStack {
            GeometryReader { screen in
                ZStack(alignment: .bottom) {
                    SpiralColors.bg.ignoresSafeArea()

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            // ── Greeting header ─────────────────────────────────────
                            greetingHeader
                                .padding(.top, screen.safeAreaInsets.top + 8)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 6)

                            // ── Spiral — ~57% of viewport height ────────────────────
                            ZStack(alignment: .topTrailing) {
                                SpiralView(
                                    records: store.records,
                                    events: store.events,
                                    spiralType: store.spiralType,
                                    period: store.period,
                                    linkGrowthToTau: store.linkGrowthToTau,
                                    showCosinor: showCosinor,
                                    showBiomarkers: showBiomarkers,
                                    showTwoProcess: showTwoProcess,
                                    selectedDay: selectedDay,
                                    onSelectDay: { selectedDay = $0 },
                                    cursorAbsHour: cursorAbsHour,
                                    sleepStartHour: sleepStartHour,
                                    numDaysHint: maxDays,
                                    cursorTurns: maxReachedTurns,
                                    visibleDays: liveVisibleDays,
                                    depthScale: store.depthScale,
                                    showGrid: store.showGrid
                                )
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            let searchMax = min(
                                                (maxReachedTurns + 1.5) * store.period,
                                                Double(maxDays) * store.period
                                            )
                                            let scaleDays = max(1, Int(ceil(maxReachedTurns)))
                                            let newHour = nearestHour(
                                                at: value.location,
                                                size: CGSize(
                                                    width: screen.size.width - 32,
                                                    height: screen.size.width - 32
                                                ),
                                                numDays: maxDays,
                                                scaleDays: scaleDays,
                                                period: store.period,
                                                spiralType: store.spiralType,
                                                linkGrowthToTau: store.linkGrowthToTau,
                                                totalHours: searchMax
                                            )
                                            cursorAbsHour = newHour
                                            let newTurns = newHour / store.period
                                            if newTurns > maxReachedTurns {
                                                // Cursor advanced past the frontier — expand zoom to follow.
                                                let wasAtMax = visibleDays >= maxReachedTurns * 0.95
                                                maxReachedTurns = newTurns
                                                if wasAtMax {
                                                    visibleDays = newTurns
                                                    liveVisibleDays = newTurns
                                                    if !pinchStarted {
                                                        pinchBaseVisibleDays = newTurns
                                                        zoomNorm = 1.0
                                                    }
                                                }
                                            } else if !pinchStarted {
                                                // Cursor moved back into history — contract zoom to match cursor position.
                                                let target = max(minVisibleDays, newTurns)
                                                visibleDays = target
                                                liveVisibleDays = target
                                                pinchBaseVisibleDays = target
                                            }
                                        }
                                )
                                .simultaneousGesture(
                                    MagnifyGesture(minimumScaleDelta: 0.01)
                                        .onChanged { value in
                                            // Capture base once at gesture start.
                                            if !pinchStarted {
                                                pinchStarted = true
                                                pinchBaseVisibleDays = visibleDays
                                            }
                                            let clamped = max(minVisibleDays, min(maxReachedTurns, pinchBaseVisibleDays / Double(value.magnification)))
                                            liveVisibleDays = clamped
                                            visibleDays     = clamped
                                            zoomNorm        = visibleDaysToNorm(clamped)
                                        }
                                        .onEnded { _ in
                                            pinchStarted = false
                                            pinchBaseVisibleDays = visibleDays
                                            zoomNorm = visibleDaysToNorm(visibleDays)
                                        }
                                )
                                .onTapGesture(count: 2) {
                                    withAnimation(.easeOut(duration: 0.3)) {
                                        visibleDays = maxReachedTurns
                                        liveVisibleDays = maxReachedTurns
                                        pinchBaseVisibleDays = maxReachedTurns
                                        zoomNorm = 1.0
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(width: screen.size.width,
                                       height: screen.size.height * 0.57)
                                .reportFrame(\.spiralArea)

                                // Sleep log button — top right over spiral
                                Button { handleLogButton() } label: {
                                    ZStack {
                                        Circle()
                                            .fill(sleepStartHour != nil ? SpiralColors.awakeSleep : Color(hex: "7c3aed"))
                                            .frame(width: 48, height: 48)
                                            .shadow(color: (sleepStartHour != nil ? SpiralColors.awakeSleep : Color(hex: "7c3aed")).opacity(0.5), radius: 10)
                                        Image(systemName: sleepStartHour != nil ? "sun.max.fill" : "moon.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 8)
                                .padding(.trailing, 24)
                                .reportFrame(\.moonButton)
                            }

                            // ── Cursor time bar ──────────────────────────────────────
                            cursorBar
                                .padding(.horizontal, 20)
                                .padding(.top, 6)
                                .reportFrame(\.cursorBar)

                            if !store.records.isEmpty {
                                // ── Rhythm state card ────────────────────────────────
                                rhythmStateCard
                                    .padding(.horizontal, 16)
                                    .padding(.top, 10)

                                // ── Human stats row ──────────────────────────────────
                                humanStatsRow
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                // ── Rephase pill ──────────────────────────────────────
                                rephasePill
                                    .padding(.horizontal, 16)
                                    .padding(.top, 8)

                                // ── Micro-coach action card ───────────────────────────
                                microCoachCard
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)
                                    .padding(.bottom, screen.safeAreaInsets.bottom + 80)
                            } else {
                                // Empty state hint
                                VStack(spacing: 8) {
                                    Image(systemName: "moon.zzz")
                                        .font(.system(size: 32))
                                        .foregroundStyle(SpiralColors.muted)
                                    Text(String(localized: "spiral.empty.hint", bundle: bundle))
                                        .font(.system(size: 13))
                                        .foregroundStyle(SpiralColors.muted)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.top, 40)
                                .padding(.bottom, screen.safeAreaInsets.bottom + 80)
                            }
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $showConsistencyDetail) {
                if let consistency = store.analysis.consistency {
                    ConsistencyDetailView(consistency: consistency, records: store.records)
                }
            }
            .sheet(isPresented: $showEventSheet2) {
                EventSheetView(events: $store.events, cursorAbsHour: cursorAbsHour, bundle: bundle)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showRephaseEditor) {
                RephaseEditorView(plan: store.rephasePlan)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear { initCursor() }
        .onChange(of: store.sleepEpisodes.count) { _, count in
            if count == 0 {
                cursorAbsHour = 0; maxReachedTurns = 1.0
                visibleDays = 1.0; liveVisibleDays = 1.0; pinchBaseVisibleDays = 1.0
            } else {
                let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
                let needed  = max(1.0, lastEnd / store.period)
                if needed > maxReachedTurns {
                    maxReachedTurns = needed
                    visibleDays = needed; liveVisibleDays = needed; pinchBaseVisibleDays = needed
                }
            }
        }
    }

    // MARK: - Greeting header

    private var greetingHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(greetingText)
                    .font(.system(size: 22, weight: .light, design: .default))
                    .foregroundStyle(SpiralColors.text)
                Text(currentDateString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }
            Spacer()
            // Current time
            Text(currentTimeString)
                .font(.system(size: 22, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(SpiralColors.accent)
        }
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return String(localized: "greeting.morning", bundle: bundle)
        case 12..<18: return String(localized: "greeting.afternoon", bundle: bundle)
        default:      return String(localized: "greeting.night", bundle: bundle)
        }
    }

    private var currentTimeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: Date())
    }

    private var currentDateString: String {
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return f.string(from: Date())
    }

    // MARK: - Cursor bar

    private var cursorBar: some View {
        let absH   = cursorAbsHour
        let period = store.period
        let day    = Int(absH / period)
        let hour   = absH.truncatingRemainder(dividingBy: period)
        let h24    = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        let timeStr = String(format: "%02d:%02d", Int(h24), Int((h24 * 60).truncatingRemainder(dividingBy: 60)))
        let cal    = Calendar.current
        let date   = cal.date(byAdding: .day, value: day, to: store.startDate) ?? store.startDate
        let df     = DateFormatter(); df.dateFormat = "EEE d MMM"

        let statusText: String
        let statusColor: Color
        if let ss = sleepStartHour {
            let dur = abs(absH - ss)
            statusText  = String(format: String(localized: "spiral.cursor.saveWake", bundle: bundle), dur)
            statusColor = SpiralColors.awakeSleep
        } else {
            statusText  = String(localized: "spiral.cursor.sleepStart", bundle: bundle)
            statusColor = Color(hex: "7c3aed")
        }

        return HStack(spacing: 8) {
            Text(df.string(from: date))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
            Text(timeStr)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
            Spacer()
            Text(statusText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(statusColor)
            // Event log shortcut
            Button { showEventSheet2 = true } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 13))
                    if !store.events.isEmpty {
                        Text("\(store.events.count)")
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .foregroundStyle(SpiralColors.accentDim)
            }
            .buttonStyle(.plain)
            .reportFrame(\.eventsBtn)
        }
    }

    // MARK: - Rhythm State Card (replaces consistency score card)

    /// Main state card: one-sentence rhythm status + tappable consistency ring.
    private var rhythmStateCard: some View {
        Button { showConsistencyDetail = true } label: {
            HStack(spacing: 14) {
                // Consistency ring
                ZStack {
                    Circle()
                        .stroke(SpiralColors.border, lineWidth: 3)
                        .frame(width: 52, height: 52)
                    if let c = store.analysis.consistency {
                        Circle()
                            .trim(from: 0, to: CGFloat(c.score) / 100)
                            .stroke(Color(hex: c.label.hexColor),
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .frame(width: 52, height: 52)
                            .rotationEffect(.degrees(-90))
                        Text("\(c.score)")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color(hex: c.label.hexColor))
                    } else {
                        Text("--")
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(rhythmStateHeadline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(rhythmStateSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(SpiralColors.muted)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 16).fill(SpiralColors.surface.opacity(0.4))
                    RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8)
                }
            )
        }
        .buttonStyle(.plain)
    }

    private var rhythmStateHeadline: String {
        guard let c = store.analysis.consistency else {
            return String(localized: "spiral.rhythm.noData", bundle: bundle)
        }
        switch c.label {
        case .veryStable:   return String(localized: "spiral.rhythm.veryStable",   bundle: bundle)
        case .stable:       return String(localized: "spiral.rhythm.stable",        bundle: bundle)
        case .variable:     return String(localized: "spiral.rhythm.variable",      bundle: bundle)
        case .disorganized: return String(localized: "spiral.rhythm.disorganized",  bundle: bundle)
        case .insufficient: return String(localized: "spiral.rhythm.insufficient",  bundle: bundle)
        }
    }

    private var rhythmStateSubtitle: String {
        let stats = store.analysis.stats
        guard let c = store.analysis.consistency else {
            return String(localized: "spiral.rhythm.subtitle.noData", bundle: bundle)
        }
        // Prioritize global shifts
        if !c.globalShiftDays.isEmpty {
            let n = c.globalShiftDays.count
            let plural = n > 1 ? "s" : ""
            return String(format: String(localized: "spiral.rhythm.subtitle.shift", bundle: bundle), n, plural)
        }
        // Social jetlag
        if stats.socialJetlag > 60 {
            let min = Int(stats.socialJetlag)
            return String(format: String(localized: "spiral.rhythm.subtitle.jetlag", bundle: bundle), min)
        }
        // Bedtime variability
        let bedStd = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if bedStd > 1.0 {
            return String(format: String(localized: "spiral.rhythm.subtitle.variability", bundle: bundle), bedStd)
        }
        // Good case
        if c.deltaVsPreviousWeek.map({ $0 >= 2 }) == true {
            return String(localized: "spiral.rhythm.subtitle.improving", bundle: bundle)
        }
        return String(format: String(localized: "spiral.rhythm.subtitle.stable", bundle: bundle),
                      c.nightsUsed, c.label.displayText.lowercased())
    }

    // MARK: - Human Stats Row (replaces miniStatsRow)

    /// 3 cards in plain language, no jargon.
    private var humanStatsRow: some View {
        let s = store.analysis.stats
        let durationVal  = s.meanSleepDuration > 0 ? String(format: "%.1fh", s.meanSleepDuration) : "--"
        let durationSub  = durationSubtitle(s.meanSleepDuration)
        let driftVal     = driftValue(s)
        let driftSub     = String(localized: "spiral.stats.variationSub", bundle: bundle)
        let stabilityVal = s.rhythmStability > 0 ? String(format: "%.0f%%", s.rhythmStability * 100) : "--"
        let stabilitySub = stabilitySubtitle(s.rhythmStability)

        return HStack(spacing: 8) {
            HumanStatCard(label: String(localized: "spiral.stats.slept",    bundle: bundle),
                          value: durationVal, sub: durationSub,
                          color: durationColor(s.meanSleepDuration))
            HumanStatCard(label: String(localized: "spiral.stats.variation", bundle: bundle),
                          value: driftVal, sub: driftSub,
                          color: driftColor(s.stdBedtime > 0 ? s.stdBedtime : s.stdAcrophase))
            HumanStatCard(label: String(localized: "spiral.stats.rhythm",   bundle: bundle),
                          value: stabilityVal, sub: stabilitySub,
                          color: stabilityColor(s.rhythmStability))
        }
    }

    private func durationSubtitle(_ h: Double) -> String {
        if h <= 0 { return String(localized: "spiral.stats.durationSub.avg",         bundle: bundle) }
        if h >= 7 { return String(localized: "spiral.stats.durationSub.good",         bundle: bundle) }
        if h >= 6 { return String(localized: "spiral.stats.durationSub.slightlyShort", bundle: bundle) }
        return String(localized: "spiral.stats.durationSub.insufficient", bundle: bundle)
    }

    private func driftValue(_ s: SleepStats) -> String {
        let v = s.stdBedtime > 0 ? s.stdBedtime : s.stdAcrophase
        if v <= 0 { return "--" }
        let mins = v * 60
        if mins < 60 {
            return String(format: "±%.0f min", mins)
        } else {
            return String(format: "±%.1fh", v)
        }
    }

    private func driftColor(_ std: Double) -> Color {
        // Use bedtime SD for color too (passed from humanStatsRow)
        if std <= 0   { return SpiralColors.muted }
        if std < 0.5  { return SpiralColors.good }
        if std < 1.0  { return SpiralColors.moderate }
        return SpiralColors.poor
    }

    private func stabilitySubtitle(_ v: Double) -> String {
        if v <= 0    { return String(localized: "spiral.stats.rhythmSub.circadian", bundle: bundle) }
        if v >= 0.75 { return String(localized: "spiral.stats.rhythmSub.strong",    bundle: bundle) }
        if v >= 0.5  { return String(localized: "spiral.stats.rhythmSub.moderate",  bundle: bundle) }
        return String(localized: "spiral.stats.rhythmSub.weak", bundle: bundle)
    }

    private func durationColor(_ h: Double) -> Color {
        if h >= 7 && h <= 9 { return SpiralColors.good }
        if h >= 6 { return SpiralColors.moderate }
        if h <= 0 { return SpiralColors.muted }
        return SpiralColors.poor
    }

    private func stabilityColor(_ v: Double) -> Color {
        if v >= 0.75 { return SpiralColors.good }
        if v >= 0.5  { return SpiralColors.moderate }
        if v <= 0    { return SpiralColors.muted }
        return SpiralColors.poor
    }

    // MARK: - Micro Coach Card (replaces InsightCard)

    /// 1 action card: what to do today, based on top recommendation.
    @ViewBuilder
    private var microCoachCard: some View {
        if let rec = store.analysis.recommendations.first {
            HStack(spacing: 12) {
                Image(systemName: "lightbulb.min")
                    .font(.system(size: 18))
                    .foregroundStyle(SpiralColors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text(String(localized: "coach.action.eyebrow", bundle: bundle))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(SpiralColors.muted)
                        .textCase(.uppercase)
                    Text(localizedRecTitle(rec))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                        .lineLimit(2)
                }
                Spacer()
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 14).fill(SpiralColors.accent.opacity(0.05))
                    RoundedRectangle(cornerRadius: 14).stroke(SpiralColors.accent.opacity(0.2), lineWidth: 0.8)
                }
            )
        }
    }

    // MARK: - Rephase Pill

    /// Compact rephase status pill shown on Home when rephase mode is active,
    /// or a subtle "Set a goal" prompt when inactive.
    @ViewBuilder
    private var rephasePill: some View {
        let plan = store.rephasePlan
        let meanAcrophase = store.analysis.stats.meanAcrophase

        Button { showRephaseEditor = true } label: {
            HStack(spacing: 10) {
                // Icon
                Image(systemName: plan.isEnabled ? "target" : "scope")
                    .font(.system(size: 14))
                    .foregroundStyle(plan.isEnabled ? SpiralColors.awakeSleep : SpiralColors.muted)

                if plan.isEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(String(format: String(localized: "rephase.spiral.wake", bundle: bundle),
                                        RephaseCalculator.formattedTargetWake(plan)))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.awakeSleep)
                            Text("·")
                                .foregroundStyle(SpiralColors.muted)
                            Text(RephaseCalculator.delayString(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                        }
                        if meanAcrophase > 0 {
                            Text(RephaseCalculator.todayActionText(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.system(size: 11))
                                .foregroundStyle(SpiralColors.text.opacity(0.7))
                        }
                    }
                } else {
                    Text(String(localized: "spiral.rephase.define", bundle: bundle))
                        .font(.system(size: 12))
                        .foregroundStyle(SpiralColors.muted)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, plan.isEnabled ? 10 : 8)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(SpiralColors.surface.opacity(0.3))
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(plan.isEnabled
                                ? SpiralColors.awakeSleep.opacity(0.3)
                                : SpiralColors.border.opacity(0.3),
                                lineWidth: 0.8)
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recommendation localization helper

    private func localizedRecTitle(_ rec: Recommendation) -> String {
        guard let key = rec.key else { return rec.title }
        let localized = NSLocalizedString("rec.\(key.rawValue).title", bundle: bundle, comment: "")
        return localized == "rec.\(key.rawValue).title" ? rec.title : localized
    }

    // MARK: - Log button

    private func handleLogButton() {
        if sleepStartHour == nil {
            sleepStartHour = cursorAbsHour
        } else {
            let start = min(sleepStartHour!, cursorAbsHour)
            let end   = max(sleepStartHour!, cursorAbsHour)
            if end - start >= 0.25 {
                let episode = SleepEpisode(start: start, end: end, source: .manual)
                store.sleepEpisodes.append(episode)
                store.sleepEpisodes.sort { $0.start < $1.start }
                store.recompute()
                let endTurns = end / store.period
                if endTurns > maxReachedTurns { maxReachedTurns = endTurns }
            }
            sleepStartHour = nil
        }
    }

    // MARK: - Zoom slider helpers (log-space mapping)

    /// Convert visibleDays → normalised slider value [0,1] in log space.
    private func visibleDaysToNorm(_ vd: Double) -> Double {
        let lo = log(minVisibleDays)
        let hi = log(max(maxReachedTurns, minVisibleDays + 0.01))
        guard hi > lo else { return 1.0 }
        return (log(max(vd, minVisibleDays)) - lo) / (hi - lo)
    }

    /// Convert normalised slider value [0,1] → visibleDays.
    private func normToVisibleDays(_ n: Double) -> Double {
        let lo = log(minVisibleDays)
        let hi = log(max(maxReachedTurns, minVisibleDays + 0.01))
        return exp(lo + n * (hi - lo))
    }

    // MARK: - Init

    private func initCursor() {
        if store.sleepEpisodes.isEmpty {
            cursorAbsHour = 0; maxReachedTurns = 1.0
            visibleDays = 1.0; liveVisibleDays = 1.0; pinchBaseVisibleDays = 1.0
            zoomNorm = visibleDaysToNorm(1.0)
        } else {
            let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
            cursorAbsHour = min(lastEnd, Double(store.numDays) * store.period)
            maxReachedTurns = max(1.0, cursorAbsHour / store.period)
            visibleDays = maxReachedTurns; liveVisibleDays = maxReachedTurns
            pinchBaseVisibleDays = maxReachedTurns
            zoomNorm = 1.0  // fully zoomed out = slider at max
        }
    }

    // MARK: - Nearest hour (with perspective projection matching SpiralView)

    private func nearestHour(
        at location: CGPoint,
        size: CGSize,
        numDays: Int,
        scaleDays: Int,
        period: Double,
        spiralType: SpiralType,
        linkGrowthToTau: Bool,
        totalHours: Double
    ) -> Double {
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(size.width), height: Double(size.height),
            startRadius: 20, spiralType: spiralType,
            period: period, linkGrowthToTau: linkGrowthToTau
        )
        let totalT   = max(maxReachedTurns, 0.5)
        let margin   = 0.35
        let tRef     = totalT + margin
        let visible  = max(liveVisibleDays + margin, 1.0 + margin)
        let zStep    = geo.maxRadius * store.depthScale
        let focalLen = geo.maxRadius * 1.2
        let tTarget  = min(visible, tRef)
        let rTarget  = max(geo.radius(turns: min(tTarget, totalT)), 1.0)
        let wzTarget = (tRef - tTarget) * zStep
        let dzTarget = focalLen * rTarget / geo.maxRadius
        let camZ     = wzTarget - dzTarget

        func project(turns t: Double) -> CGPoint {
            let day  = Int(t)
            let hr   = (t - Double(day)) * geo.period
            let flat = geo.point(day: day, hour: hr)
            let wx   = flat.x - geo.cx; let wy = flat.y - geo.cy
            let wz   = (tRef - t) * zStep
            let safeDz = max(wz - camZ, focalLen * 0.05)
            let scale  = focalLen / safeDz
            return CGPoint(x: geo.cx + wx * scale, y: geo.cy + wy * scale)
        }

        // Restrict search to ±0.6 turns around the current cursor position.
        let cursorTurns = cursorAbsHour / period
        let searchRadius = 0.6
        let searchFrom = max(0, cursorTurns - searchRadius) * period
        let searchTo   = min(totalHours, (cursorTurns + searchRadius) * period)

        var best = cursorAbsHour; var bestDist = Double.infinity
        var h = searchFrom
        while h <= searchTo {
            let p  = project(turns: h / period)
            let dx = Double(location.x) - p.x; let dy = Double(location.y) - p.y
            let d  = dx*dx + dy*dy
            if d < bestDist { bestDist = d; best = h }
            h += 0.25
        }
        return best
    }
}

// MARK: - Human Stat Card

struct HumanStatCard: View {
    let label: String
    let value: String
    let sub: String
    let color: Color

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(SpiralColors.muted)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 9))
                .foregroundStyle(color.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.05))
                RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.15), lineWidth: 0.6)
            }
        )
    }
}

// MARK: - Event Sheet View

/// Sheet with full event grid — accessed via the + icon in the cursor bar.
struct EventSheetView: View {
    @Binding var events: [CircadianEvent]
    let cursorAbsHour: Double
    let bundle: Bundle

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "events.log.title", bundle: bundle))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(format: String(localized: "events.logAt", bundle: bundle),
                                SleepStatistics.formatHour(cursorAbsHour.truncatingRemainder(dividingBy: 24))))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            EventGridView(events: $events, cursorAbsHour: cursorAbsHour, bundle: bundle)
                .padding(.horizontal, 16)

            Spacer()
        }
        .background(SpiralColors.bg.ignoresSafeArea())
    }
}

// MARK: - Insight Card

struct InsightCard: View {
    let insight: PatternInsight

    private var typeColor: Color {
        switch insight.type {
        case .none:   return SpiralColors.good
        case .local:  return SpiralColors.moderate
        case .global: return SpiralColors.poor
        case .mixed:  return SpiralColors.poor
        }
    }

    private var typeIcon: String {
        switch insight.type {
        case .none:   return "checkmark.circle"
        case .local:  return "exclamationmark.circle"
        case .global: return "arrow.left.and.right.circle"
        case .mixed:  return "exclamationmark.triangle"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: typeIcon)
                .font(.system(size: 16))
                .foregroundStyle(typeColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(insight.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 12).fill(typeColor.opacity(0.06))
                RoundedRectangle(cornerRadius: 12).stroke(typeColor.opacity(0.25), lineWidth: 0.8)
            }
        )
    }
}

// MARK: - Event Grid

/// Compact 3×2 glass-style event button grid shown below the spiral.
struct EventGridView: View {
    @Binding var events: [CircadianEvent]
    let cursorAbsHour: Double
    let bundle: Bundle
    @State private var showLog = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EventType.allCases, id: \.self) { type in
                    GlassEventButton(type: type) {
                        let event = CircadianEvent(
                            type: type,
                            absoluteHour: cursorAbsHour,
                            timestamp: Date()
                        )
                        events.append(event)
                        events.sort { $0.absoluteHour < $1.absoluteHour }
                    }
                }
            }

            // Logged events — compact inline list, toggle
            if !events.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(String(format: String(localized: "events.loggedCount", bundle: bundle), events.count))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Image(systemName: showLog ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showLog {
                    ForEach(events) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.type.sfSymbol)
                                .font(.system(size: 9))
                                .foregroundStyle(Color(hex: event.type.hexColor))
                                .frame(width: 12)
                            Text(event.type.label)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Text(SleepStatistics.formatHour(event.absoluteHour.truncatingRemainder(dividingBy: 24)))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            Button {
                                events.removeAll { $0.id == event.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7))
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Glass Event Button

private struct GlassEventButton: View {
    let type: EventType
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.12)) { pressed = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.12)) { pressed = false }
            }
            action()
        }) {
            VStack(spacing: 5) {
                Image(systemName: type.sfSymbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: type.hexColor))
                Text(type.label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(hex: type.hexColor).opacity(pressed ? 0.18 : 0.06))
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: type.hexColor).opacity(0.25), lineWidth: 0.8)
                }
            )
            .scaleEffect(pressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
    }
}
