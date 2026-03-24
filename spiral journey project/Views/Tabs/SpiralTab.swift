import SwiftUI
import SwiftData
import SpiralKit

/// Main spiral tab — full-screen spiral with contextual greeting, sleep logging,
/// consistency score card, mini stats, and event grid.
struct SpiralTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(\.modelContext) private var modelContext
    @Binding var selectedTab: AppTab

    @State private var selectedDay: Int? = nil
    @State private var showCosinor    = false
    @State private var showBiomarkers = false
    @State private var showTwoProcess = false
    @State private var showDNAInsights = false

    // Sleep logging
    @State private var cursorAbsHour: Double = 0
    @State private var cachedHasDream: Bool = false
    @State private var cachedDreamDate: Date?
    @State private var sleepStartHour: Double? = nil
    // Duration event logging
    @State private var eventLoggingType: EventType? = nil
    @State private var eventStartHour: Double? = nil
    /// True when the cursor tracks real-world time automatically.
    /// Set to false when the user drags the cursor to a past hour.
    @State private var isCursorLive: Bool = true
    @State private var maxReachedTurns: Double = 1.0
    @State private var visibleDays: Double = 1
    @State private var liveVisibleDays: Double = 1
    @State private var pinchBaseVisibleDays: Double = 1
    private let minVisibleDays: Double = 0.08
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
    // Dream entry state moved to ContentView to avoid re-rendering SpiralTab
    // Rephase editor sheet
    @State private var showRephaseEditor = false
    // Spiral growth animation — 0→1 drives the spiral's organic grow-from-center reveal
    @State private var spiralGrowthProgress: Double = 0
    // Staggered entry for floating UI overlays (date pill, action bar)
    @State private var floatingElementsVisible = false
    // Liquid Glass floating panels
    @State private var showStatsSheet = false
    @State private var showCoachTip = false
    // Tap info panel — shows details when user taps a spiral element
    @State private var selectedElementInfo: SpiralElementInfo? = nil
    @State private var elementInfoDismissTask: Task<Void, Never>? = nil

    // Drag tracking — tangent-based cursor advancement (smooth, no jitter).
    // On first touch: snap via nearestHour. Subsequent moves: tangent delta.
    @State private var dragPrevLocation: CGPoint = .zero
    @State private var dragIsNew: Bool = true
    #if os(macOS)
    // Frame of the spiral area in global coordinates — used to position the drag overlay.
    @State private var spiralFrameGlobal: CGRect = .zero
    #endif

    var body: some View {
        @Bindable var store = store
        let maxDays = max(store.numDays, 1)

        NavigationStack {
            GeometryReader { screen in
                ZStack(alignment: .bottom) {
                    SpiralColors.bg.ignoresSafeArea()

                    // ── Layer 1: Spiral — fills most of the screen ──────────
                    SpiralView(
                        records: store.records,
                        events: store.events,
                        spiralType: effectiveSpiralType,
                        period: store.period,
                        linkGrowthToTau: effectiveLinkGrowthToTau,
                        showCosinor: showCosinor,
                        showBiomarkers: showBiomarkers,
                        showTwoProcess: showTwoProcess,
                        selectedDay: selectedDay,
                        onSelectDay: { selectedDay = $0 },
                        contextBlocks: store.contextBlocksEnabled ? store.contextBlocks : [],
                        cursorAbsHour: cursorAbsHour,
                        sleepStartHour: sleepStartHour,
                        eventStartHour: eventStartHour,
                        eventLoggingType: eventLoggingType,
                        numDaysHint: effectiveNumDaysHint,
                        spiralExtentTurns: effectiveSpiralExtent,
                        viewportCenterTurns: smoothCameraCenterTurns - (0.5 - cameraFrontPadding),
                        visibleSpanTurns: liveVisibleDays,
                        depthScale: store.flatMode ? 0 : effectiveDepthScale,
                        perspectivePower: effectivePerspectivePower,
                        showGrid: store.showGrid,
                        startRadius: effectiveStartRadius,
                        predictedBedHour: store.predictionOverlayEnabled ? store.latestPrediction?.predictedBedtimeHour : nil,
                        predictedWakeHour: store.predictionOverlayEnabled ? store.latestPrediction?.predictedWakeHour : nil,
                        growthProgress: spiralGrowthProgress,
                        glowIntensity: store.glowIntensity
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spiralAccessibilityLabel)
                    .accessibilityHint(loc("spiral.a11y.hint"))
                    #if !os(macOS)
                    // Tangent-based cursor advancement: first touch snaps via nearestHour,
                    // subsequent movement advances smoothly along the spiral tangent.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isUserInteracting = true
                                interactionMode = .scrub
                                lastInteractionTime = Date()

                                let spiralSize = CGSize(
                                    width: screen.size.width,
                                    height: screen.size.height
                                )
                                let scaleDays = max(1, Int(ceil(maxReachedTurns)))
                                let maxHours = Double(maxDays) * store.period

                                if dragIsNew {
                                    // First touch: snap cursor to nearest position.
                                    dragIsNew = false
                                    dragPrevLocation = value.location
                                    let newHour = nearestHour(
                                        at: value.location,
                                        size: spiralSize,
                                        numDays: maxDays,
                                        scaleDays: scaleDays,
                                        period: store.period,
                                        spiralType: effectiveSpiralType,
                                        linkGrowthToTau: effectiveLinkGrowthToTau,
                                        totalHours: maxHours
                                    )
                                    cursorAbsHour = newHour
                                    smoothCameraCenterTurns = newHour / store.period
                                    return
                                }

                                // Subsequent moves: advance along spiral tangent — no jitter.
                                let dx = value.location.x - dragPrevLocation.x
                                let dy = value.location.y - dragPrevLocation.y
                                dragPrevLocation = value.location

                                let hoursStep = tangentHoursPerPixel(
                                    atHour: cursorAbsHour,
                                    spiralSize: spiralSize,
                                    scaleDays: scaleDays,
                                    period: store.period,
                                    spiralType: effectiveSpiralType,
                                    linkGrowthToTau: effectiveLinkGrowthToTau,
                                    mouseDx: dx, mouseDy: dy
                                )
                                let newHour = max(0, min(maxHours, cursorAbsHour + hoursStep))
                                cursorAbsHour = newHour
                                smoothCameraCenterTurns = newHour / store.period
                                showInfoForCursorPosition()
                                let nowH = Date().timeIntervalSince(store.startDate) / 3600
                                isCursorLive = abs(newHour - nowH) < 0.25
                                let newTurns = newHour / store.period
                                if newTurns > maxReachedTurns {
                                    maxReachedTurns = newTurns
                                }
                            }
                            .onEnded { value in
                                isUserInteracting = false
                                interactionMode = .none
                                dragIsNew = true
                                lastInteractionTime = Date()

                                let dist = hypot(value.translation.width, value.translation.height)
                                if dist < 8 {
                                    // Tap: cursor already jumped, show info
                                    showInfoForCursorPosition()
                                }
                                // After drag: keep showing info (auto-dismiss timer handles cleanup)
                            }
                    )
                    #endif
                    .simultaneousGesture(
                        MagnifyGesture(minimumScaleDelta: 0.01)
                            .onChanged { value in
                                isUserInteracting = true
                                interactionMode = .pinch
                                lastInteractionTime = Date()
                                if !pinchStarted {
                                    pinchStarted = true
                                    pinchBaseVisibleDays = visibleDays
                                }
                                let maxZoomOut = min(maxReachedTurns, 7.0)
                                let clamped = max(minVisibleDays, min(maxZoomOut, pinchBaseVisibleDays / Double(value.magnification)))
                                liveVisibleDays = clamped
                                visibleDays     = clamped
                                zoomNorm        = visibleDaysToNorm(clamped)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(spiralGrowthProgress > 0 ? 1.0 : 0)
                    .reportFrame(\.spiralArea)

                    // ── Layer 2: Top floating date pill ──────────────────────
                    VStack {
                        datePill
                            .padding(.top, screen.safeAreaInsets.top + 8)
                            .opacity(floatingElementsVisible ? 1 : 0)
                            .offset(y: floatingElementsVisible ? 0 : 20)
                        Spacer()
                    }

                    // ── Layer 3: DNA + Sleep log buttons ─────────────────────
                    VStack {
                        HStack {
                            Button { showDNAInsights = true } label: {
                                ZStack {
                                    Canvas { ctx, size in
                                        let w = size.width, h = size.height
                                        let midY = h / 2, amp = h * 0.3
                                        var p1 = Path(), p2 = Path()
                                        for x in stride(from: CGFloat(0), through: w, by: 1) {
                                            let t = (x / w) * 2 * .pi
                                            let y1 = midY + sin(t) * amp
                                            let y2 = midY + sin(t + .pi) * amp
                                            if x == 0 {
                                                p1.move(to: CGPoint(x: x, y: y1))
                                                p2.move(to: CGPoint(x: x, y: y2))
                                            } else {
                                                p1.addLine(to: CGPoint(x: x, y: y1))
                                                p2.addLine(to: CGPoint(x: x, y: y2))
                                            }
                                        }
                                        ctx.stroke(p1, with: .color(SpiralColors.accent.opacity(0.9)), lineWidth: 2)
                                        ctx.stroke(p2, with: .color(.orange.opacity(0.7)), lineWidth: 2)
                                    }
                                    .frame(width: 24, height: 18)
                                }
                                .frame(width: 44, height: 44)
                                .liquidGlass(circular: true)
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button {
                                if let info = cursorSleepInfo {
                                    NotificationCenter.default.post(
                                        name: .showDreamEntry,
                                        object: nil,
                                        userInfo: ["date": info.date, "timeRange": info.timeRange]
                                    )
                                } else {
                                    showEventSheet2 = true
                                }
                            } label: {
                                Image(systemName: addButtonIcon)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(addButtonColor)
                                    .frame(width: 44, height: 44)
                                    .liquidGlass(circular: true)
                            }
                            .buttonStyle(.plain)
                            .reportFrame(\.eventsBtn)
                        }
                        .padding(.top, screen.safeAreaInsets.top + 48)
                        .padding(.horizontal, 20)
                        .opacity(floatingElementsVisible ? 1 : 0)
                        .offset(y: floatingElementsVisible ? 0 : 20)
                        Spacer()
                    }

                    // ── Layer 4: Cursor time pill ────────────────────────────
                    VStack {
                        Spacer()
                        cursorBar
                            .padding(.horizontal, 20)
                            .liquidGlass(cornerRadius: 16)
                            .padding(.horizontal, 16)
                            .reportFrame(\.cursorBar)
                            .opacity(floatingElementsVisible ? 1 : 0)
                            .padding(.bottom, 188)
                    }

                    // ── Layer 4b: Tap info card ────────────────────────────
                    VStack {
                        if let info = selectedElementInfo {
                            spiralInfoCard(info)
                                .padding(.horizontal, 20)
                                .padding(.top, screen.safeAreaInsets.top + 90)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        Spacer()
                    }
                    .animation(.spring(response: 0.35), value: selectedElementInfo != nil)

                    // ── Layer 5: Coach tip overlay ───────────────────────────
                    VStack {
                        Spacer()
                        if showCoachTip, let insight = store.analysis.coachInsight {
                            CoachTipOverlay(insight: insight) {
                                withAnimation(.spring(response: 0.35)) {
                                    showCoachTip = false
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 180)
                        }
                    }
                    .animation(.spring(response: 0.35), value: showCoachTip)

                    // ── Layer 6: Empty state ─────────────────────────────────
                    if store.records.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "moon.zzz")
                                .font(.largeTitle)
                                .foregroundStyle(SpiralColors.muted)
                            Text(String(localized: "spiral.empty.hint", bundle: bundle))
                                .font(.footnote)
                                .foregroundStyle(SpiralColors.muted)
                                .multilineTextAlignment(.center)
                        }
                    }

                    // ── Layer 7: Bottom action bar ───────────────────────────
                    VStack {
                        Spacer()
                        actionBar
                            .padding(.bottom, screen.safeAreaInsets.bottom + 16)
                            .opacity(floatingElementsVisible ? 1 : 0)
                            .offset(y: floatingElementsVisible ? 0 : 30)
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
                                        if dragIsNew {
                                            dragIsNew = false
                                            dragPrevLocation = value.location
                                            return
                                        }

                                        // Compute incremental mouse delta (screen points).
                                        let dx = value.location.x - dragPrevLocation.x
                                        let dy = value.location.y - dragPrevLocation.y
                                        dragPrevLocation = value.location

                                        // Advance cursorAbsHour using the tangent of the spiral
                                        // at the current position. This maps each pixel of mouse
                                        // movement to the correct number of hours along the curve,
                                        // responding to every tiny movement without any search.
                                        let spiralSize = CGSize(width: screen.size.width,
                                                                height: screen.size.height)
                                        let scaleDays = max(1, Int(ceil(maxReachedTurns)))
                                        let maxHours  = Double(maxDays) * store.period
                                        let hoursStep = tangentHoursPerPixel(
                                            atHour: cursorAbsHour,
                                            spiralSize: spiralSize,
                                            scaleDays: scaleDays,
                                            period: store.period,
                                            spiralType: effectiveSpiralType,
                                            linkGrowthToTau: effectiveLinkGrowthToTau,
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
                                        dragIsNew = true
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
                    onRemove: { store.removeEvent(id: $0) },
                    onStartDuration: { type in
                        guard sleepStartHour == nil else { return }
                        eventLoggingType = type
                        showEventSheet2 = false
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            // Dream entry sheet presented from ContentView to avoid SpiralTab re-render
            .sheet(isPresented: $showRephaseEditor) {
                RephaseEditorView(plan: store.rephasePlan)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showStatsSheet) {
                SpiralHomeStatsSheet(
                    showConsistencyDetail: $showConsistencyDetail,
                    showRephaseEditor: $showRephaseEditor
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            #if !os(macOS)
            .fullScreenCover(isPresented: $showDNAInsights) {
                DNAInsightsView()
            }
            #else
            .sheet(isPresented: $showDNAInsights) {
                DNAInsightsView()
            }
            #endif
        }
        .onAppear {
            initCursor()
            // Animate the spiral path drawing from inner edge to cursor over 2s.
            if store.spiralRevealAnimation {
                let animDuration = 2.0
                let fps = 60.0
                let totalFrames = Int(animDuration * fps)
                var frame = 0
                Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { timer in
                    frame += 1
                    let t = Double(frame) / Double(totalFrames)
                    let eased = 1.0 - pow(1.0 - t, 3)
                    spiralGrowthProgress = min(eased, 1.0)
                    if frame >= totalFrames {
                        spiralGrowthProgress = 1.0
                        timer.invalidate()
                    }
                }
            } else {
                spiralGrowthProgress = 1.0
            }
            // Stagger floating UI elements: appear 1s after spiral starts
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.6)) {
                    floatingElementsVisible = true
                }
            }
        }
        .onChange(of: store.period) { _, _ in initCursor() }
        .onChange(of: store.flatMode) { _, _ in initCursor() }
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
                    .font(.title2.weight(.light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [SpiralColors.text, SpiralColors.accent.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text(currentDateString)
                    .font(.caption.monospaced())
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
        if let eventType = eventLoggingType {
            let evtColor = Color(hex: eventType.hexColor)
            if let es = eventStartHour {
                let dur = abs(absH - es)
                let mins = Int(dur * 60)
                let h = mins / 60
                let m = mins % 60
                let durStr = h > 0 ? "\(h)h\(m)m" : "\(m)m"
                statusText  = "\(eventType.label) (\(durStr))"
                statusColor = evtColor
            } else {
                statusText  = "Tap \u{25B6} \(eventType.label)"
                statusColor = evtColor
            }
        } else if let ss = sleepStartHour {
            let dur = abs(absH - ss)
            statusText  = String(format: String(localized: "spiral.cursor.saveWake", bundle: bundle), dur)
            statusColor = SpiralColors.awakeSleep
        } else {
            statusText  = String(localized: "spiral.cursor.sleepStart", bundle: bundle)
            statusColor = Color(hex: "a855f7")
        }

        return HStack(spacing: 8) {
            Text(df.string(from: date))
                .font(.caption.monospaced())
                .foregroundStyle(SpiralColors.subtle)
            Text(timeStr)
                .font(.subheadline.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.text)
            Spacer()
            Text(statusText)
                .font(.caption.monospaced())
                .foregroundStyle(statusColor)
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
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(Color(hex: c.label.hexColor))
                    } else {
                        Text("--")
                            .font(.subheadline.weight(.bold).monospaced())
                            .foregroundStyle(SpiralColors.muted)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(rhythmStateHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(rhythmStateSubtitle)
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
            }
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: 20).fill(SpiralColors.surface.opacity(0.4))
                    RoundedRectangle(cornerRadius: 20).stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8)
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

    // MARK: - Prediction Card

    private func predictionCard(_ pred: PredictionOutput) -> some View {
        HStack(spacing: 14) {
            // Moon icon
            ZStack {
                Circle()
                    .fill(Color(hex: "a78bfa").opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "moon.stars.fill")
                    .font(.title2)
                    .foregroundStyle(Color(hex: "a78bfa"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "prediction.card.title", bundle: bundle))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)

                HStack(spacing: 16) {
                    Label(formatClockHour(pred.predictedBedtimeHour), systemImage: "bed.double.fill")
                    Label(formatClockHour(pred.predictedWakeHour), systemImage: "alarm.fill")
                    Label(String(format: "%.1fh", pred.predictedDuration), systemImage: "hourglass")
                }
                .font(.footnote.monospaced())
                .foregroundStyle(SpiralColors.muted)

                HStack(spacing: 6) {
                    predictionConfidenceBadge(pred.confidence)
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 20).fill(SpiralColors.surface.opacity(0.4))
                RoundedRectangle(cornerRadius: 20).stroke(Color(hex: "a78bfa").opacity(0.3), lineWidth: 0.8)
            }
        )
    }

    private func predictionConfidenceBadge(_ confidence: PredictionConfidence) -> some View {
        let (text, color): (String, Color) = {
            switch confidence {
            case .high:   return ("●●●", Color(hex: "34d399"))
            case .medium: return ("●●○", Color(hex: "fbbf24"))
            case .low:    return ("●○○", Color(hex: "f87171"))
            }
        }()
        return Text(text)
            .font(.caption.monospaced())
            .foregroundStyle(color)
    }

    // MARK: - Add Button Icon (sleep detection + dream check)

    private var addButtonIcon: String {
        guard cursorSleepInfo != nil else { return "plus" }
        return cachedHasDream ? "eye" : "moon.zzz"
    }

    private var addButtonColor: Color {
        guard cursorSleepInfo != nil else { return SpiralColors.accent }
        return cachedHasDream ? SpiralColors.remSleep : SpiralColors.accent
    }

    /// Update dream cache only when the cursor moves to a different sleep date.
    /// Avoids SwiftData query on every frame.
    private func updateDreamCache() {
        guard let info = cursorSleepInfo else {
            cachedHasDream = false
            cachedDreamDate = nil
            return
        }
        let calendar = Calendar.current
        // Only re-query if date actually changed
        if let cached = cachedDreamDate, calendar.isDate(cached, inSameDayAs: info.date) { return }
        cachedDreamDate = info.date
        let start = calendar.startOfDay(for: info.date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<SDDreamEntry>(
            predicate: #Predicate { $0.sleepDate >= start && $0.sleepDate < end }
        )
        cachedHasDream = (try? modelContext.fetchCount(descriptor)) ?? 0 > 0
    }

    // MARK: - Sleep phase detection for dream entry

    /// Returns (date, sleepTimeRange) if cursor is on a sleep phase, nil otherwise.
    private var cursorSleepInfo: (date: Date, timeRange: String)? {
        let cursorH = cursorAbsHour
        guard cursorH > 0 else { return nil }
        let dayIndex = Int(cursorH / store.period)
        let clockHour = cursorH.truncatingRemainder(dividingBy: store.period)

        for candidateDay in [dayIndex, dayIndex - 1, dayIndex + 1] {
            guard let record = store.records.first(where: { $0.day == candidateDay }) else { continue }
            let phaseAtHour = record.phases.last(where: { $0.hour <= clockHour })
            let isSleepPhase = phaseAtHour != nil && phaseAtHour!.phase != .awake
            let bedH = record.bedtimeHour, wakeH = record.wakeupHour
            let inSleepRange: Bool
            if bedH > wakeH { inSleepRange = clockHour >= bedH || clockHour <= wakeH }
            else if bedH < wakeH { inSleepRange = clockHour >= bedH && clockHour <= wakeH }
            else { inSleepRange = false }

            if isSleepPhase || inSleepRange {
                return (record.date, "\(formatClockHour(bedH)) – \(formatClockHour(wakeH))")
            }
        }
        return nil
    }

    private func formatClockHour(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = ((total / 60) % 24 + 24) % 24
        let mm = abs(total % 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    // MARK: - Human Stats Row (replaces miniStatsRow)

    /// Compact inline stats — 3 values in a single row, minimal chrome.
    private var humanStatsRow: some View {
        let s = store.analysis.stats
        let durationVal  = s.meanSleepDuration > 0 ? String(format: "%.1fh", s.meanSleepDuration) : "--"
        let driftVal     = driftValue(s)
        let stabilityVal = s.rhythmStability > 0 ? String(format: "%.0f%%", s.rhythmStability * 100) : "--"

        return HStack(spacing: 0) {
            compactStat(
                icon: "bed.double.fill",
                value: durationVal,
                color: durationColor(s.meanSleepDuration)
            )
            Spacer()
            compactStat(
                icon: "waveform.path.ecg",
                value: driftVal,
                color: driftColor(s.stdBedtime > 0 ? s.stdBedtime : s.stdAcrophase)
            )
            Spacer()
            compactStat(
                icon: "metronome.fill",
                value: stabilityVal,
                color: stabilityColor(s.rhythmStability)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(SpiralColors.surface.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(SpiralColors.border.opacity(0.25), lineWidth: 0.6)
                )
        )
    }

    private func compactStat(icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color.opacity(0.7))
            Text(value)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(color)
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
                    .font(.body)
                    .foregroundStyle(plan.isEnabled ? SpiralColors.awakeSleep : SpiralColors.muted)

                if plan.isEnabled {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(String(format: String(localized: "rephase.spiral.wake", bundle: bundle),
                                        RephaseCalculator.formattedTargetWake(plan)))
                                .font(.footnote.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.awakeSleep)
                            Text("·")
                                .foregroundStyle(SpiralColors.muted)
                            Text(RephaseCalculator.delayString(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.caption.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                        }
                        if meanAcrophase > 0 {
                            Text(RephaseCalculator.todayActionText(plan: plan, meanAcrophase: meanAcrophase, bundle: bundle))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                } else {
                    Text(String(localized: "spiral.rephase.define", bundle: bundle))
                        .font(.footnote)
                        .foregroundStyle(SpiralColors.muted)
                }

                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
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

    // MARK: - Date Pill (Liquid Glass floating header)

    private var datePill: some View {
        HStack(spacing: 8) {
            Text(greetingText)
                .font(.caption.weight(.medium))
            Text("·")
                .foregroundStyle(SpiralColors.subtle)
            Text(currentDateString)
                .font(.caption.monospaced())
        }
        .foregroundStyle(SpiralColors.text)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 20)
    }

    // MARK: - Action Bar (Liquid Glass bottom controls)

    private var actionBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            // Stats button (left, small)
            Button { showStatsSheet = true } label: {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.title3)
                    .foregroundStyle(SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)

            // Central sleep/wake/event button — original style with liquid glass
            Button {
                if eventLoggingType != nil {
                    handleEventLogButton()
                } else {
                    handleLogButton()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(logButtonColor)
                        .frame(width: 64, height: 64)
                        .shadow(color: logButtonColor.opacity(0.5), radius: 10)
                    Image(systemName: logButtonIcon)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        sleepStartHour = nil
                        eventLoggingType = nil
                        eventStartHour = nil
                    }
            )

            // Coach tip button (right, small)
            Button {
                withAnimation(.spring(response: 0.35)) {
                    showCoachTip.toggle()
                }
            } label: {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(
                        store.analysis.coachInsight != nil
                            ? SpiralColors.accent
                            : SpiralColors.muted
                    )
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .disabled(store.analysis.coachInsight == nil)
        }
    }

    // MARK: - Log button

    private var logButtonIcon: String {
        if let eventType = eventLoggingType {
            return eventType.sfSymbol
        } else if sleepStartHour != nil {
            return "sun.max.fill"
        } else {
            return "moon.fill"
        }
    }

    private var logButtonColor: Color {
        if let eventType = eventLoggingType {
            return Color(hex: eventType.hexColor)
        } else if sleepStartHour != nil {
            return SpiralColors.awakeSleep
        } else {
            return Color(hex: "7c3aed")
        }
    }

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

    private func handleEventLogButton() {
        guard let eventType = eventLoggingType else { return }
        if eventStartHour == nil {
            // First tap: mark start
            eventStartHour = cursorAbsHour
        } else {
            // Second tap: create event with duration
            let start = min(eventStartHour!, cursorAbsHour)
            let end   = max(eventStartHour!, cursorAbsHour)
            let duration = end - start
            if duration >= 5.0 / 60.0 {  // Minimum 5 minutes
                let event = CircadianEvent(
                    type: eventType,
                    absoluteHour: start,
                    timestamp: Date(),
                    durationHours: duration
                )
                store.addEvent(event)
            }
            eventStartHour = nil
            eventLoggingType = nil
        }
    }

    // MARK: - Zoom slider helpers (log-space mapping)

    /// Log 3D scales geometry to actual data so arms fill 75→130pt over the visible range.
    /// Other modes use the fixed 30-day scale so spacing never shifts as data grows.
    private var effectiveNumDaysHint: Int {
        if store.spiralType == .logarithmic && !store.flatMode {
            return max(Int(ceil(maxReachedTurns)), 7)
        }
        return max(store.numDays, 1)
    }

    /// Start radius varies by mode:
    /// - Archimedean (any): 75 (CLAUDE.md standard)
    /// - Log 3D: 60 (wider radial range for cone effect)
    /// - Log 2D flat: 15 (small inner turns, exponential spread visible)
    private var effectiveStartRadius: Double {
        guard store.spiralType == .logarithmic else { return 75.0 }
        return store.flatMode ? 15.0 : 60.0
    }

    private var isLog3D: Bool {
        store.spiralType == .logarithmic && !store.flatMode
    }

    /// For logarithmic spirals, cap extent at actual data days so growthRate
    /// stays reasonable. Without this, scrolling to the future inflates
    /// scaleDays → tiny growthRate → all arms cluster at the same radius.
    private var effectiveSpiralExtent: Double {
        if store.spiralType == .logarithmic {
            let dataDays = max(Double(store.records.count), 1)
            return max(dataDays + 1, 7)
        }
        return maxReachedTurns
    }

    private var effectiveSpiralType: SpiralType {
        store.spiralType
    }

    /// Disable linkGrowthToTau for logarithmic spirals when it would
    /// produce growthRate ≈ 0 (period ≈ 24h), collapsing all arms to one circle.
    private var effectiveLinkGrowthToTau: Bool {
        if store.spiralType == .logarithmic && store.linkGrowthToTau {
            let tauRate = log(max(store.period, 23) / 24) / (2 * .pi)
            if abs(tauRate) < 0.001 { return false }
        }
        return store.linkGrowthToTau
    }

    private var effectiveDepthScale: Double {
        let ds = store.depthScale
        guard isLog3D else { return ds }
        // store.depthScale defaults to 0.15 — nearly flat, arms merge.
        // Log 3D needs ≥ 0.5 for a visible cone with separated arms.
        return max(ds, 0.5)
    }

    /// Sqrt perspective for log 3D — spreads arms more evenly (like the Watch).
    private var effectivePerspectivePower: Double {
        isLog3D ? 0.5 : 1.0
    }

    private var cameraFrontPadding: Double {
        0.5   // standard for all modes — prevents outer arm overflow
    }

    /// Max zoom-out: 7 turns for all modes.
    private var maxZoomOutTurns: Double {
        let cap = 7.0
        return min(maxReachedTurns, cap)
    }

    /// Convert visibleDays → normalised slider value [0,1] in log space.
    private func visibleDaysToNorm(_ vd: Double) -> Double {
        let lo = log(minVisibleDays)
        let hi = log(max(maxZoomOutTurns, minVisibleDays + 0.01))
        guard hi > lo else { return 1.0 }
        return (log(max(vd, minVisibleDays)) - lo) / (hi - lo)
    }

    /// Convert normalised slider value [0,1] → visibleDays.
    private func normToVisibleDays(_ n: Double) -> Double {
        let lo = log(minVisibleDays)
        let hi = log(max(maxZoomOutTurns, minVisibleDays + 0.01))
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
            // All modes show up to 7 turns initially.
            let maxInitialZoom: Double = (store.spiralType == .logarithmic && !store.flatMode) ? 7.0 : 7.0

            let initialZoom = min(maxReachedTurns, maxInitialZoom)
            visibleDays = initialZoom; liveVisibleDays = initialZoom
            pinchBaseVisibleDays = initialZoom
            zoomNorm = visibleDaysToNorm(initialZoom)
        }
        // Initialize camera to cursor position — no jump on first frame.
        smoothCameraCenterTurns = cursorAbsHour / store.period
    }

    // MARK: - Projection helpers (tangent-based drag tracking)

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
            startRadius: effectiveStartRadius, spiralType: spiralType,
            period: period, linkGrowthToTau: linkGrowthToTau
        )
        // Camera must match CameraState in SpiralView exactly.
        let effectiveDepth = store.flatMode ? 0.0 : effectiveDepthScale
        let span     = liveVisibleDays
        let focus    = smoothCameraCenterTurns - (0.5 - cameraFrontPadding)
        let camUpTo  = focus + 0.5       // matches SpiralView: focusTurns + cameraFrontPadding
        let camFrom  = max(focus - span, 0)
        let zStep    = geo.maxRadius * effectiveDepth
        let focalLen = geo.maxRadius * (zStep > 0 ? 1.6 : 1.2)
        let margin   = 0.5
        let tRef     = camUpTo + margin
        // Span-based camera zoom: match CameraState exactly
        let eSpan = max(camUpTo - camFrom, 0.5)
        let zFwd: Double = (zStep > 0 && eSpan < 7.0) ? focalLen * 0.5 * (1.0 - eSpan / 7.0) : 0
        let camZ     = margin * zStep - focalLen + zFwd

        let t   = absHour / period
        if zStep == 0 {
            // Flat mode: radial zoom matches CameraState.project()
            let tIn      = max(camFrom, 0)
            let tOut     = camUpTo
            let rInner   = max(geo.radius(turns: tIn), 1.0)
            let rOuter   = max(geo.radius(turns: tOut), rInner + 1.0)
            let r        = geo.radius(turns: t)
            let mappedR  = max(0.0, (r - rInner) / (rOuter - rInner) * geo.maxRadius)
            let theta    = t * 2 * Double.pi
            let ang      = theta - Double.pi / 2
            return CGPoint(x: geo.cx + mappedR * cos(ang),
                           y: geo.cy + mappedR * sin(ang))
        }
        // Use theta/r directly — must match CameraState.project exactly.
        // geo.point(day:hour:) recomputes t_inner=(day×24+hour)/period which
        // diverges from t when period≠24 (tau mode), causing cursor drift.
        let theta  = t * 2 * Double.pi
        let r      = geo.radius(turns: t)
        let wx     = r * cos(theta - Double.pi / 2)
        let wy     = r * sin(theta - Double.pi / 2)
        let wz     = (tRef - t) * zStep
        let safeDz = max(wz - camZ, focalLen * 0.05)
        let rawScale = focalLen / safeDz
        let pp = effectivePerspectivePower
        let scale  = pp == 1.0 ? rawScale : pow(rawScale, pp)
        return CGPoint(x: geo.cx + wx * scale, y: geo.cy + wy * scale)
    }

    // MARK: - Tap info panel

    /// Shows info for whatever is at the CURSOR position.
    /// Called on tap — the cursor already jumped to the tapped location.
    private func showInfoForCursorPosition() {
        updateDreamCache()
        let period = store.period
        let dayIndex = Int(cursorAbsHour / period)
        let clockHour = ((cursorAbsHour.truncatingRemainder(dividingBy: period))
            .truncatingRemainder(dividingBy: 24) + 24)
            .truncatingRemainder(dividingBy: 24)
        let cal = Calendar.current
        let tappedDate = cal.date(byAdding: .day, value: dayIndex, to: store.startDate) ?? store.startDate

        // 1. Context blocks
        let activeBlocks = (store.contextBlocksEnabled ? store.contextBlocks : [])
            .filter { $0.isEnabled && $0.isActive(on: tappedDate) }
        for block in activeBlocks {
            let s = block.startHour, e = block.endHour
            let inRange = s <= e ? (clockHour >= s && clockHour <= e) : (clockHour >= s || clockHour <= e)
            if inRange {
                showElementInfo(SpiralElementInfo(
                    label: block.label,
                    timeRange: block.timeRangeString,
                    duration: formatDurationCompact(block.durationHours),
                    color: Color(hex: block.type.hexColor)
                ))
                return
            }
        }

        // 2. Event logs (find nearest event within ±0.5h of cursor)
        let nearestEvent = store.events.min(by: {
            abs($0.absoluteHour - cursorAbsHour) < abs($1.absoluteHour - cursorAbsHour)
        })
        if let event = nearestEvent, abs(event.absoluteHour - cursorAbsHour) < 0.5 {
            let eventLabel = NSLocalizedString("event.type.\(event.type.rawValue)", bundle: bundle, comment: "")
            let timeStr = formatClockHour(event.absoluteHour.truncatingRemainder(dividingBy: 24))
            var durationStr = ""
            if let dur = event.durationHours {
                durationStr = formatDurationCompact(dur)
            }
            showElementInfo(SpiralElementInfo(
                label: eventLabel,
                timeRange: timeStr,
                duration: durationStr,
                color: Color(hex: event.type.hexColor)
            ))
            return
        }

        // 3. Sleep (search current + adjacent days)
        for candidateDay in [dayIndex, dayIndex - 1, dayIndex + 1] {
            guard let record = store.records.first(where: { $0.day == candidateDay }) else { continue }
            let phaseAtHour = record.phases.last(where: { $0.hour <= clockHour })
            let isSleepPhase = phaseAtHour != nil && phaseAtHour!.phase != .awake
            let bedH = record.bedtimeHour, wakeH = record.wakeupHour
            let inSleepRange: Bool
            if bedH > wakeH { inSleepRange = clockHour >= bedH || clockHour <= wakeH }
            else if bedH < wakeH { inSleepRange = clockHour >= bedH && clockHour <= wakeH }
            else { inSleepRange = false }

            if isSleepPhase || inSleepRange {
                showElementInfo(SpiralElementInfo(
                    label: loc("spiral.info.sleep"),
                    timeRange: "\(formatClockHour(bedH)) – \(formatClockHour(wakeH))",
                    duration: formatDurationCompact(record.sleepDuration),
                    color: Color(hex: "a855f7")
                ))
                return
            }
        }

        // 4. Awake (record exists but not sleeping)
        if let record = store.records.first(where: { $0.day == dayIndex }) {
            showElementInfo(SpiralElementInfo(
                label: loc("spiral.info.awake"),
                timeRange: "\(formatClockHour(record.wakeupHour)) – \(formatClockHour(record.bedtimeHour))",
                duration: formatDurationCompact(max(0, period - record.sleepDuration)),
                color: SpiralColors.awakeSleep
            ))
            return
        }

        // 5. Vigilia (no record, live day)
        let nowAbsHour = Date().timeIntervalSince(store.startDate) / 3600
        if dayIndex >= Int(nowAbsHour / period) - 1 {
            showElementInfo(SpiralElementInfo(
                label: loc("spiral.info.vigilia"),
                timeRange: "\(formatClockHour(clockHour)) → now",
                duration: "",
                color: SpiralColors.awakeSleep
            ))
        }
    }


    /// Shows the info card and schedules auto-dismiss after 3 seconds.
    private func showElementInfo(_ info: SpiralElementInfo) {
        elementInfoDismissTask?.cancel()
        withAnimation(.spring(response: 0.3)) {
            selectedElementInfo = info
        }
        elementInfoDismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.3)) {
                selectedElementInfo = nil
            }
        }
    }

    /// Formats hours as "Xh Ym".
    private func formatDurationCompact(_ hours: Double) -> String {
        let totalMinutes = Int((hours * 60).rounded())
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        if h == 0 { return "\(m) min" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m) min"
    }

    /// The info card shown when the user taps a spiral element.
    private func spiralInfoCard(_ info: SpiralElementInfo) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(info.color)
                .frame(width: 8, height: 8)
            Text(info.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SpiralColors.text)
            if !info.timeRange.isEmpty {
                Text("·")
                    .foregroundStyle(SpiralColors.subtle)
                Text(info.timeRange)
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.subtle)
            }
            if !info.duration.isEmpty {
                Text("·")
                    .foregroundStyle(SpiralColors.subtle)
                Text(info.duration)
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.subtle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .liquidGlass(cornerRadius: 16)
    }

    // MARK: - Accessibility

    /// Describes the current spiral state for VoiceOver.
    private var spiralAccessibilityLabel: String {
        let dayCount = store.records.count
        let cursorDay = Int(cursorAbsHour / 24.0) + 1
        return String(
            format: NSLocalizedString("spiral.a11y.label", bundle: bundle, comment: ""),
            dayCount, cursorDay
        )
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
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
        totalHours: Double,
        searchAll: Bool = false,
        searchRadius: Double? = nil
    ) -> Double {
        let geo = SpiralGeometry(
            totalDays: scaleDays, maxDays: scaleDays,
            width: Double(size.width), height: Double(size.height),
            startRadius: effectiveStartRadius, spiralType: spiralType,
            period: period, linkGrowthToTau: linkGrowthToTau
        )
        // Camera must match CameraState in SpiralView exactly.
        let effectiveDepth = store.flatMode ? 0.0 : effectiveDepthScale
        let span     = liveVisibleDays
        let focus    = smoothCameraCenterTurns - (0.5 - cameraFrontPadding)
        let camUpTo  = focus + 0.5       // matches SpiralView: focusTurns + cameraFrontPadding
        let camFrom  = max(focus - span, 0)
        let zStep    = geo.maxRadius * effectiveDepth
        let focalLen = geo.maxRadius * (zStep > 0 ? 1.6 : 1.2)
        let margin   = 0.5
        let tRef     = camUpTo + margin
        // Span-based camera zoom: match CameraState exactly
        let eSpan2 = max(camUpTo - camFrom, 0.5)
        let zFwd2: Double = (zStep > 0 && eSpan2 < 7.0) ? focalLen * 0.5 * (1.0 - eSpan2 / 7.0) : 0
        let camZ     = margin * zStep - focalLen + zFwd2
        let pp       = effectivePerspectivePower

        // Flat mode: precompute radial projection bounds (matches CameraState.init).
        let flatRInner: Double
        let flatROuter: Double
        if zStep == 0 {
            let tIn  = max(camFrom, 0)
            let tOut = camUpTo
            let rIn  = max(geo.radius(turns: tIn), 1.0)
            flatRInner = rIn
            flatROuter = max(geo.radius(turns: tOut), rIn + 1.0)
        } else {
            flatRInner = 0; flatROuter = 1
        }

        func project(turns t: Double) -> CGPoint {
            // Mirror CameraState.project exactly: use theta/r directly so the
            // projection is correct for any period (including tau ≠ 24).
            // geo.point(day:hour:) recomputes t via (day×24+hour)/period which
            // diverges from t when period≠24, causing cursor drift.
            let theta = t * 2 * Double.pi
            let r     = geo.radius(turns: t)
            if zStep == 0 {
                let mappedR = max(0.0, (r - flatRInner) / (flatROuter - flatRInner) * geo.maxRadius)
                let ang     = theta - Double.pi / 2
                return CGPoint(x: geo.cx + mappedR * cos(ang),
                               y: geo.cy + mappedR * sin(ang))
            }
            let wx     = r * cos(theta - Double.pi / 2)
            let wy     = r * sin(theta - Double.pi / 2)
            let wz     = (tRef - t) * zStep
            let safeDz = max(wz - camZ, focalLen * 0.05)
            let rawScale = focalLen / safeDz
            let scale  = pp == 1.0 ? rawScale : pow(rawScale, pp)
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
                .font(.caption2.weight(.semibold))
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.bold).monospaced())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(sub)
                .font(.caption2.weight(.medium))
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

// MARK: - Spiral Element Info

/// Describes a tapped element in the spiral for the info card overlay.
struct SpiralElementInfo {
    let label: String       // "Sleep", "Awake", "Work Meeting"
    let timeRange: String   // "23:15 – 07:30"
    let duration: String    // "8h 15 min"
    let color: Color        // phase color or event color
}

// MARK: - Event Sheet View

/// Sheet with full event grid — accessed via the + icon in the cursor bar.
struct EventSheetView: View {
    let events: [CircadianEvent]
    let cursorAbsHour: Double
    let bundle: Bundle
    let onAdd: (CircadianEvent) -> Void
    let onRemove: (UUID) -> Void
    var onStartDuration: ((EventType) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "events.log.title", bundle: bundle))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(format: String(localized: "events.logAt", bundle: bundle),
                                SleepStatistics.formatHour(cursorAbsHour.truncatingRemainder(dividingBy: 24))))
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            EventGridView(events: events, cursorAbsHour: cursorAbsHour, bundle: bundle,
                          onAdd: onAdd, onRemove: onRemove, onStartDuration: onStartDuration)
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
                .font(.subheadline)
                .foregroundStyle(typeColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(insight.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(insight.summary)
                    .font(.caption)
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
    var onStartDuration: ((EventType) -> Void)? = nil
    @State private var showLog = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(EventType.allCases.filter(\.isManuallyLoggable), id: \.self) { type in
                    GlassEventButton(type: type, bundle: bundle) {
                        if type.hasDuration, let startDuration = onStartDuration {
                            startDuration(type)
                        } else {
                            let event = CircadianEvent(
                                type: type,
                                absoluteHour: cursorAbsHour,
                                timestamp: Date()
                            )
                            onAdd(event)
                        }
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
                            .font(.caption2.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Image(systemName: showLog ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if showLog {
                    ForEach(events) { event in
                        HStack(spacing: 6) {
                            Image(systemName: event.type.sfSymbol)
                                .font(.caption2)
                                .foregroundStyle(Color(hex: event.type.hexColor))
                                .frame(width: 12)
                            Text(NSLocalizedString("event.type.\(event.type.rawValue)", bundle: bundle, comment: ""))
                                .font(.caption2.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Text(SleepStatistics.formatHour(event.absoluteHour.truncatingRemainder(dividingBy: 24)))
                                .font(.caption2.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                            if let dur = event.durationHours {
                                Text("\u{2192}")
                                    .font(.caption2)
                                    .foregroundStyle(SpiralColors.subtle)
                                Text(SleepStatistics.formatHour((event.absoluteHour + dur).truncatingRemainder(dividingBy: 24)))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Button {
                                onRemove(event.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption2)
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
    let bundle: Bundle
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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color(hex: type.hexColor))
                Text(NSLocalizedString("event.type.\(type.rawValue)", bundle: bundle, comment: ""))
                    .font(.caption2.weight(.medium).monospaced())
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
