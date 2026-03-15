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
    /// True when the cursor tracks real-world time automatically.
    /// Set to false when the user drags the cursor to a past hour.
    @State private var isCursorLive: Bool = true
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

    // ── Smooth camera follow ──
    // The camera center always tends toward the cursor via lerp.
    // During gestures the lerp factor is reduced so the camera doesn't
    // fight the user. After gesture ends the lerp ramps back up smoothly.
    /// Smoothed camera center in turns — the value SpiralView actually uses.
    @State private var smoothCameraCenterTurns: Double = 0
    /// True while a drag or pinch gesture is physically active.
    @State private var isUserInteracting: Bool = false
    /// Interaction type for debug logging.
    enum InteractionMode: String { case none, scrub, pinch }
    @State private var interactionMode: InteractionMode = .none
    /// Timestamp of the last gesture event — used for post-gesture decay.
    @State private var lastInteractionTime: Date = .distantPast

    // Consistency detail navigation
    @State private var showConsistencyDetail = false
    // Event sheet
    @State private var showEventSheet2 = false
    // Rephase editor sheet
    @State private var showRephaseEditor = false
    #if os(macOS)
    // Frame of the spiral area in global coordinates — used to position the drag overlay.
    @State private var spiralFrameGlobal: CGRect = .zero
    // True until the first onChanged of a new gesture has been processed.
    @State private var macDragIsNew: Bool = true
    // Global location of the previous onChanged event — used for incremental delta.
    @State private var macDragPrevLocation: CGPoint = .zero
    // Projected spiral-local point of the cursor at the previous event.
    @State private var macDragPrevProjected: CGPoint = .zero
    #endif

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
                            #if DEBUG
                            let _ = {
                                let f = { (v: Double) -> String in String(format: "%.2f", v) }
                                let cursorTurns = cursorAbsHour / store.period
                                let vpFrom = max(cursorTurns - 7.0, 0.0)
                                print("[SpiralTab] cursor=\(f(cursorTurns)) vpFrom=\(f(vpFrom)) vpUpTo=\(f(cursorTurns)) span=7.0 camera=\(f(smoothCameraCenterTurns)) mode=\(isUserInteracting ? interactionMode.rawValue : "autoFollow")")
                            }()
                            #endif
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
                                    contextBlocks: store.contextBlocksEnabled ? store.contextBlocks : [],
                                    cursorAbsHour: cursorAbsHour,
                                    sleepStartHour: sleepStartHour,
                                    numDaysHint: maxDays,
                                    spiralExtentTurns: maxReachedTurns,
                                    viewportCenterTurns: smoothCameraCenterTurns,
                                    visibleSpanTurns: liveVisibleDays,
                                    depthScale: store.depthScale,
                                    showGrid: store.showGrid
                                )
                                #if !os(macOS)
                                // On macOS the overlay outside the ScrollView handles all cursor
                                // drag interactions. This gesture is iOS/iPadOS only.
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            isUserInteracting = true
                                            interactionMode = .scrub
                                            lastInteractionTime = Date()
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
                                            // Guard against erroneous nearestHour jumps near spiral origin.
                                            let maxDelta = store.period * 0.5
                                            guard abs(newHour - cursorAbsHour) <= maxDelta else { return }
                                            cursorAbsHour = newHour
                                            // During scrub, camera tracks cursor immediately.
                                            smoothCameraCenterTurns = newHour / store.period
                                            let nowH = Date().timeIntervalSince(store.startDate) / 3600
                                            isCursorLive = abs(newHour - nowH) < 0.25
                                            let newTurns = newHour / store.period
                                            if newTurns > maxReachedTurns {
                                                maxReachedTurns = newTurns
                                            }
                                        }
                                        .onEnded { _ in
                                            isUserInteracting = false
                                            interactionMode = .none
                                            lastInteractionTime = Date()
                                        }
                                )
                                #endif
                                .simultaneousGesture(
                                    MagnifyGesture(minimumScaleDelta: 0.01)
                                        .onChanged { value in
                                            isUserInteracting = true
                                            interactionMode = .pinch
                                            lastInteractionTime = Date()
                                            // Capture base zoom once at gesture start.
                                            if !pinchStarted {
                                                pinchStarted = true
                                                pinchBaseVisibleDays = visibleDays
                                            }
                                            let clamped = max(minVisibleDays, min(maxReachedTurns, pinchBaseVisibleDays / Double(value.magnification)))
                                            liveVisibleDays = clamped
                                            visibleDays     = clamped
                                            zoomNorm        = visibleDaysToNorm(clamped)
                                            // Camera keeps following cursor during pinch —
                                            // no freezing at a snapshot point.
                                        }
                                        .onEnded { _ in
                                            isUserInteracting = false
                                            interactionMode = .none
                                            pinchStarted = false
                                            pinchBaseVisibleDays = visibleDays
                                            zoomNorm = visibleDaysToNorm(visibleDays)
                                            lastInteractionTime = Date()
                                        }
                                )
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
                                VStack(spacing: 0) {
                                    // ── Rhythm state card ─────────────────────────────
                                    rhythmStateCard
                                        .padding(.horizontal, 16)
                                        .padding(.top, 10)

                                    // ── Human stats row ───────────────────────────────
                                    humanStatsRow
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)

                                    // ── Rephase pill ──────────────────────────────────
                                    rephasePill
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, screen.safeAreaInsets.bottom + 80)
                                }
                                .frame(maxWidth: 540)
                                .frame(maxWidth: .infinity)
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
                    #if os(macOS)
                    // Transparent drag overlay positioned over the spiral area.
                    // Placed outside the ScrollView so the scroll view never intercepts
                    // the drag. Coordinates are converted to the spiral's local space
                    // before passing to nearestHour.
                    if spiralFrameGlobal != .zero {
                        Color(white: 0, opacity: 0.001)
                            .frame(width: spiralFrameGlobal.width,
                                   height: spiralFrameGlobal.height)
                            .position(x: spiralFrameGlobal.midX,
                                      y: spiralFrameGlobal.midY)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        isUserInteracting = true
                                        interactionMode = .scrub
                                        lastInteractionTime = Date()
                                        if macDragIsNew {
                                            macDragIsNew = false
                                            macDragPrevLocation = value.location
                                            return
                                        }

                                        // Compute incremental mouse delta (screen points).
                                        let dx = value.location.x - macDragPrevLocation.x
                                        let dy = value.location.y - macDragPrevLocation.y
                                        macDragPrevLocation = value.location

                                        // Advance cursorAbsHour using the tangent of the spiral
                                        // at the current position. This maps each pixel of mouse
                                        // movement to the correct number of hours along the curve,
                                        // responding to every tiny movement without any search.
                                        let spiralSize = CGSize(width: screen.size.width - 32,
                                                                height: screen.size.width - 32)
                                        let scaleDays = max(1, Int(ceil(maxReachedTurns)))
                                        let maxHours  = Double(maxDays) * store.period
                                        let hoursStep = tangentHoursPerPixel(
                                            atHour: cursorAbsHour,
                                            spiralSize: spiralSize,
                                            scaleDays: scaleDays,
                                            period: store.period,
                                            spiralType: store.spiralType,
                                            linkGrowthToTau: store.linkGrowthToTau,
                                            mouseDx: dx, mouseDy: dy
                                        )
                                        let newHour = max(0, min(maxHours, cursorAbsHour + hoursStep))
                                        cursorAbsHour = newHour
                                        // During scrub, camera tracks cursor immediately.
                                        smoothCameraCenterTurns = newHour / store.period
                                        let nowH = Date().timeIntervalSince(store.startDate) / 3600
                                        isCursorLive = abs(newHour - nowH) < 0.25
                                        let newTurns = newHour / store.period
                                        if newTurns > maxReachedTurns {
                                            maxReachedTurns = newTurns
                                        }
                                    }
                                    .onEnded { _ in
                                        macDragIsNew = true
                                        isUserInteracting = false
                                        interactionMode = .none
                                        lastInteractionTime = Date()
                                    }
                            )
                            // Arrow keys for fine-grained cursor movement.
                            .focusable()
                            .focusEffectDisabled()
                            .onKeyPress(phases: [.down, .repeat]) { press in
                                let isShift = press.modifiers.contains(.shift)
                                let stepHours: Double = isShift ? 1.0 : 0.25
                                let maxHours = min((maxReachedTurns + 1.5) * store.period,
                                                   Double(maxDays) * store.period)
                                switch press.key {
                                case .leftArrow:
                                    let newHour = max(0, cursorAbsHour - stepHours)
                                    cursorAbsHour = newHour
                                    smoothCameraCenterTurns = newHour / store.period
                                    let nowH = Date().timeIntervalSince(store.startDate) / 3600
                                    isCursorLive = abs(newHour - nowH) < 0.25
                                    return .handled
                                case .rightArrow:
                                    let newHour = min(maxHours, cursorAbsHour + stepHours)
                                    cursorAbsHour = newHour
                                    smoothCameraCenterTurns = newHour / store.period
                                    let nowH = Date().timeIntervalSince(store.startDate) / 3600
                                    isCursorLive = abs(newHour - nowH) < 0.25
                                    let newTurns = newHour / store.period
                                    if newTurns > maxReachedTurns {
                                        maxReachedTurns = newTurns
                                    }
                                    return .handled
                                default:
                                    return .ignored
                                }
                            }
                    }
                    #endif
                }
                .ignoresSafeArea()
                #if os(macOS)
                .onPreferenceChange(OnboardingFramesKey.self) { frames in
                    spiralFrameGlobal = frames.spiralArea
                }
                #endif
            }
            .navigationDestination(isPresented: $showConsistencyDetail) {
                if let consistency = store.analysis.consistency {
                    ConsistencyDetailView(consistency: consistency, records: store.records)
                }
            }
            .sheet(isPresented: $showEventSheet2) {
                EventSheetView(
                    events: store.events,
                    cursorAbsHour: cursorAbsHour,
                    bundle: bundle,
                    onAdd: { store.addEvent($0) },
                    onRemove: { store.removeEvent(id: $0) }
                )
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
        .onChange(of: store.period) { _, _ in initCursor() }
        .task {
            // Smooth camera follow loop — runs at ~30fps.
            // Lerps smoothCameraCenterTurns toward cursorTurns.
            // During gestures the lerp is suppressed; after gesture ends
            // it ramps up smoothly, preventing snaps.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33)) // ~30fps
                let cursorTurns = cursorAbsHour / store.period

                if isUserInteracting && interactionMode == .scrub {
                    // During scrub: camera is set directly in gesture handler.
                    // No lerp here — gesture handler owns the value.
                } else {
                    // Smooth follow: lerp toward cursor.
                    // After gesture ends, ramp up lerp factor over ~0.5s.
                    let timeSinceGesture = Date().timeIntervalSince(lastInteractionTime)
                    let lerpFactor: Double
                    if isUserInteracting && interactionMode == .pinch {
                        // During pinch: gentle follow so camera doesn't fight zoom.
                        lerpFactor = 0.08
                    } else if timeSinceGesture < 0.5 {
                        // Post-gesture ramp: 0.05 → 0.25 over 0.5s
                        let t = timeSinceGesture / 0.5
                        lerpFactor = 0.05 + t * 0.20
                    } else {
                        // Normal follow: responsive but not instant.
                        lerpFactor = 0.25
                    }
                    let delta = cursorTurns - smoothCameraCenterTurns
                    smoothCameraCenterTurns += delta * lerpFactor
                }
            }
        }
        .task {
            // Advance the cursor every 60 seconds to track real-world time,
            // but only when the cursor is live and the user isn't interacting.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard isCursorLive, !isUserInteracting else { continue }
                cursorAbsHour = Date().timeIntervalSince(store.startDate) / 3600
            }
        }
        .onChange(of: store.sleepEpisodes.count) { _, count in
            let minTurns = max(1.0, store.period / 24.0)
            if count == 0 {
                let nowAbsHour = Date().timeIntervalSince(store.startDate) / 3600
                cursorAbsHour = nowAbsHour
                maxReachedTurns = minTurns
                visibleDays = minTurns; liveVisibleDays = minTurns; pinchBaseVisibleDays = minTurns
            } else {
                let nowAbsHour = Date().timeIntervalSince(store.startDate) / 3600
                let needed = max(minTurns, nowAbsHour / store.period)
                if needed > maxReachedTurns {
                    maxReachedTurns = needed
                    // Don't reset zoom to max — keep current zoom level.
                    // Only expand if current zoom was already at max.
                    if visibleDays >= maxReachedTurns * 0.95 {
                        let initialZoom = min(needed, 7.0)
                        visibleDays = initialZoom; liveVisibleDays = initialZoom
                        pinchBaseVisibleDays = initialZoom
                    }
                }
                cursorAbsHour = nowAbsHour
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
                    .foregroundStyle(SpiralColors.subtle)
            }
            Spacer()
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
                .foregroundStyle(SpiralColors.subtle)
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
                .foregroundStyle(SpiralColors.accent)
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
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.subtle)
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
            let formatted = formatJetlag(stats.socialJetlag)
            return String(format: String(localized: "spiral.rhythm.subtitle.jetlag", bundle: bundle), formatted)
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
        let localizedLabel = String(localized: String.LocalizationValue(c.label.localizationKey))
        return String(format: String(localized: "spiral.rhythm.subtitle.stable", bundle: bundle),
                      c.nightsUsed, localizedLabel.lowercased())
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

    /// Formats a social jetlag value (in minutes) as "Xh Ym" or "Xm".
    private func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func durationSubtitle(_ h: Double) -> String {
        if h <= 0 { return String(localized: "spiral.stats.durationSub.avg",         bundle: bundle) }
        if h >= 7 && h <= 9 { return String(localized: "spiral.stats.durationSub.good", bundle: bundle) }
        if h > 9  { return String(localized: "spiral.stats.durationSub.excessive",    bundle: bundle) }
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
                                .foregroundStyle(SpiralColors.muted)
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
                    .foregroundStyle(SpiralColors.subtle)
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
        // Minimum turns ensures the spiral always shows at least one full revolution's
        // ring structure. For period=168h (weekly), this is 7 turns so that partial-week
        // data (e.g. 2-3 days) renders as an arc within a visible spiral rather than a
        // short boomerang. For standard 24h period this stays at 1.0.
        let minTurns = max(1.0, store.period / 24.0)
        if store.sleepEpisodes.isEmpty {
            cursorAbsHour = Date().timeIntervalSince(store.startDate) / 3600
            maxReachedTurns = minTurns
            visibleDays = minTurns; liveVisibleDays = minTurns; pinchBaseVisibleDays = minTurns
            zoomNorm = visibleDaysToNorm(minTurns)
        } else {
            let nowAbsHour = Date().timeIntervalSince(store.startDate) / 3600
            let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
            cursorAbsHour = nowAbsHour
            maxReachedTurns = max(minTurns, max(nowAbsHour, lastEnd) / store.period)
            // Initial zoom: 7-turn retrospective window.
            // Camera, data, opacity all use this same span.
            let initialZoom = min(maxReachedTurns, 7.0)
            visibleDays = initialZoom; liveVisibleDays = initialZoom
            pinchBaseVisibleDays = initialZoom
            zoomNorm = visibleDaysToNorm(initialZoom)
        }
        // Initialize camera to cursor position — no jump on first frame.
        smoothCameraCenterTurns = cursorAbsHour / store.period
    }

    // MARK: - Projection helpers (macOS drag tracking)

    #if os(macOS)
    /// Returns how many hours to advance the cursor given a mouse delta (dx, dy).
    /// Projects two nearby points on the spiral (current and current+epsilon) to screen
    /// space, computes the tangent direction, then takes the dot product with the mouse
    /// delta.  This gives sub-pixel sensitivity with no search loop.
    private func tangentHoursPerPixel(
        atHour absHour: Double,
        spiralSize: CGSize,
        scaleDays: Int,
        period: Double,
        spiralType: SpiralType,
        linkGrowthToTau: Bool,
        mouseDx: Double, mouseDy: Double
    ) -> Double {
        let eps = 0.25  // hours — small enough to be smooth
        let p0  = projectedPoint(forHour: absHour,       spiralSize: spiralSize, scaleDays: scaleDays, period: period, spiralType: spiralType, linkGrowthToTau: linkGrowthToTau)
        let p1  = projectedPoint(forHour: absHour + eps, spiralSize: spiralSize, scaleDays: scaleDays, period: period, spiralType: spiralType, linkGrowthToTau: linkGrowthToTau)
        let tx = p1.x - p0.x  // tangent vector (eps hours → tx,ty pixels)
        let ty = p1.y - p0.y
        let lenSq = tx*tx + ty*ty
        guard lenSq > 1e-9 else { return 0 }
        // Project mouse delta onto the tangent, then scale to hours.
        let dot = mouseDx * tx + mouseDy * ty
        return dot / lenSq * eps  // hours
    }

    /// Returns the spiral-local screen point where `absHour` is projected,
    /// using the same perspective math as `nearestHour` / SpiralView.
    private func projectedPoint(
        forHour absHour: Double,
        spiralSize: CGSize,
        scaleDays: Int,
        period: Double,
        spiralType: SpiralType,
        linkGrowthToTau: Bool
    ) -> CGPoint {
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(spiralSize.width), height: Double(spiralSize.height),
            startRadius: 20, spiralType: spiralType,
            period: period, linkGrowthToTau: linkGrowthToTau
        )
        // Retrospective camera matching SpiralView (7-turn window)
        let span: Double = 7.0
        let camUpTo  = smoothCameraCenterTurns
        let camFrom  = max(camUpTo - span, 0)
        let zStep    = geo.maxRadius * store.depthScale
        let focalLen = geo.maxRadius * 1.2
        let margin   = 0.5
        let tRef     = camUpTo + margin
        let spanZ    = max((camUpTo - camFrom), 0.5) * zStep
        let maxRatio = 5.0
        let nearPlane = focalLen * 0.1
        let safetyMargin = nearPlane * 1.0
        let dzFar    = max(spanZ / (maxRatio - 1.0), nearPlane + safetyMargin)
        let camZ     = margin * zStep - dzFar

        let t   = absHour / period
        let day = Int(t)
        let hr  = (t - Double(day)) * geo.period
        let flat = geo.point(day: day, hour: hr)
        let wx   = flat.x - geo.cx; let wy = flat.y - geo.cy
        let wz   = (tRef - t) * zStep
        let safeDz = max(wz - camZ, focalLen * 0.05)
        let scale  = focalLen / safeDz
        return CGPoint(x: geo.cx + wx * scale, y: geo.cy + wy * scale)
    }
    #endif

    // MARK: - Nearest hour (with perspective projection matching SpiralView)

    private func nearestHour(
        at location: CGPoint,
        size: CGSize,
        numDays: Int,
        scaleDays: Int,
        period: Double,
        spiralType: SpiralType,
        linkGrowthToTau: Bool,
        totalHours: Double,
        searchAll: Bool = false,
        searchRadius: Double? = nil
    ) -> Double {
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(size.width), height: Double(size.height),
            startRadius: 20, spiralType: spiralType,
            period: period, linkGrowthToTau: linkGrowthToTau
        )
        // Retrospective camera matching SpiralView (7-turn window)
        let span: Double = 7.0
        let camUpTo  = smoothCameraCenterTurns
        let camFrom  = max(camUpTo - span, 0)
        let zStep    = geo.maxRadius * store.depthScale
        let focalLen = geo.maxRadius * 1.2
        let margin   = 0.5
        let tRef     = camUpTo + margin
        let spanZ    = max((camUpTo - camFrom), 0.5) * zStep
        let maxRatio = 5.0
        let nearPlane = focalLen * 0.1
        let safetyMargin = nearPlane * 1.0
        let dzFar    = max(spanZ / (maxRatio - 1.0), nearPlane + safetyMargin)
        let camZ     = margin * zStep - dzFar

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

        // Restrict search to a window around the current cursor position.
        // On macOS we use two radii:
        //  • isFirst=true  (new gesture / click): ±0.5 turns — lets the cursor snap to
        //    wherever you click within the current arm without jumping to a different arm.
        //  • isFirst=false (ongoing drag): ±2.0 turns — wide enough that fast mouse drags
        //    never escape the window.
        // searchAll keeps the parameter signature but is no longer used on macOS.
        let cursorTurns = cursorAbsHour / period
        let searchFrom: Double
        let searchTo: Double
        if searchAll {
            searchFrom = 0
            searchTo   = totalHours
        } else {
            #if os(macOS)
            let radius = searchRadius ?? 2.0
            #else
            let radius = searchRadius ?? 0.6
            #endif
            searchFrom = max(0, cursorTurns - radius) * period
            searchTo   = min(totalHours, (cursorTurns + radius) * period)
        }

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
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(SpiralColors.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12).fill(SpiralColors.surface)
                RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.12))
                RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.45), lineWidth: 1.0)
            }
        )
    }
}

// MARK: - Event Sheet View

/// Sheet with full event grid — accessed via the + icon in the cursor bar.
struct EventSheetView: View {
    let events: [CircadianEvent]
    let cursorAbsHour: Double
    let bundle: Bundle
    let onAdd: (CircadianEvent) -> Void
    let onRemove: (UUID) -> Void

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

            EventGridView(events: events, cursorAbsHour: cursorAbsHour, bundle: bundle,
                          onAdd: onAdd, onRemove: onRemove)
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
    let events: [CircadianEvent]
    let cursorAbsHour: Double
    let bundle: Bundle
    let onAdd: (CircadianEvent) -> Void
    let onRemove: (UUID) -> Void
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
                        onAdd(event)
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
                                onRemove(event.id)
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
                    .foregroundStyle(SpiralColors.subtle)
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
