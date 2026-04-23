import SwiftUI
import SceneKit
import SpiralKit

/// 3D torus sleep visualization for iPhone — SceneKit wrapper with gesture controls.
///
/// Shows last night's sleep trajectory on a torus surface. Includes:
/// - Drag to rotate camera (minimumDistance: 15 to avoid pager swipe)
/// - Tap to toggle play/pause
/// - Continuous rewind/forward buttons (hold to scrub)
/// - Phase + time label overlay
struct TorusModeView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.languageBundle) private var bundle

    /// True when this mode is the one the user is currently looking at in
    /// the pager. When false, the scene is paused to avoid running a
    /// SceneKit render loop + SCNAction for a view that is offscreen —
    /// TabView(.page) keeps all children mounted so .onDisappear never
    /// fires and we need an explicit signal from the parent.
    var isActive: Bool = true

    @State private var scene = TorusSceneiPhone()
    @State private var isPaused = false
    @State private var wasPlayingBeforeBackground = false
    @State private var dataLoaded = false

    // Label overlay
    @State private var showLabel = false
    @State private var labelText = ""
    @State private var labelOpacity: Double = 0

    // Drag state for camera orbit
    @State private var lastDragLocation: CGPoint?

    // Scrub active (for label display)
    @State private var isScrubbing = false

    // Haptic generator
    #if canImport(UIKit)
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)
    #endif

    var body: some View {
        LazyModeView(isActive: isActive) {
            torusContent
        }
    }

    private var torusContent: some View {
        ZStack {
            // SceneKit view — transparent background
            TransparentSceneView(scene: scene.scene, pointOfView: scene.cameraNode)
                .ignoresSafeArea()

            // Gesture overlay — SCNView has isUserInteractionEnabled=false,
            // so we need a transparent overlay to capture SwiftUI gestures.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    togglePause()
                }
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { value in
                            if let last = lastDragLocation {
                                let dx = Float(value.location.x - last.x)
                                let dy = Float(value.location.y - last.y)
                                scene.orbitCamera(deltaAngle: dx * 0.012, deltaElevation: -dy * 0.008)
                            }
                            lastDragLocation = value.location
                        }
                        .onEnded { _ in
                            lastDragLocation = nil
                        }
                )

            // Phase + time label (shown when paused or scrubbing)
            if showLabel {
                VStack {
                    Spacer()
                    Text(labelText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(SpiralColors.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial, in: Capsule())
                        .opacity(labelOpacity)
                        .padding(.bottom, 130) // above action bar
                }
            }

            // Sample-data hint — the scene loads `TorusSceneiPhone.mockNight()`
            // when there are no real records yet (otherwise a brand-new user
            // would see a static empty torus and miss the feature entirely).
            // Without this badge, the animated demo could be mistaken for
            // the user's actual sleep trajectory.
            if store.records.first(where: { $0.sleepDuration >= 3.0 }) == nil {
                VStack {
                    HStack {
                        Spacer()
                        Text(String(localized: "torus.demo.badge",
                                    defaultValue: "Sample night — log sleep to see yours",
                                    bundle: bundle))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(SpiralColors.muted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.top, 12)
                        Spacer()
                    }
                    Spacer()
                }
            }

            // Bottom action bar
            VStack {
                Spacer()
                actionBar
                    .padding(.bottom, 24)
            }
        }
        .task {
            // Wire up haptic on stage transitions
            scene.onStageTransition = { _ in
                #if canImport(UIKit)
                hapticGenerator.impactOccurred()
                #endif
            }
            loadRealData()
            if isActive {
                scene.startAnimation()
                isPaused = false
            }
        }
        .onDisappear {
            scene.stopAnimation()
            scene.stopScrub()
        }
        .onChange(of: isActive) { _, active in
            // Pager kept the view alive but moved it offscreen. Pause to
            // stop burning CPU on a SceneKit render loop the user can't see.
            if active {
                if !isPaused {
                    scene.startAnimation()
                }
            } else {
                scene.stopAnimation()
                scene.stopScrub()
            }
        }
        .onChange(of: store.records.count) { _, _ in
            loadRealData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                if wasPlayingBeforeBackground && isActive {
                    scene.startAnimation()
                    isPaused = false
                    wasPlayingBeforeBackground = false
                }
            } else {
                if scene.isAnimating {
                    wasPlayingBeforeBackground = true
                    scene.stopAnimation()
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(alignment: .bottom, spacing: 24) {
            // Rewind — continuous scrub while held
            scrubButton(direction: -1, icon: "backward.fill")
                .accessibilityLabel(String(localized: "torus.rewind", defaultValue: "Rewind"))

            // Play / Pause — central button (64pt, accent fill, same style as SpiralTab)
            Button {
                togglePause()
            } label: {
                ZStack {
                    Circle()
                        .fill(SpiralColors.accent)
                        .frame(width: 64, height: 64)
                        .shadow(color: SpiralColors.accent.opacity(0.5), radius: 10)
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(
                localized: isPaused ? "torus.play" : "torus.pause",
                defaultValue: isPaused ? "Play" : "Pause"
            ))

            // Forward — continuous scrub while held
            scrubButton(direction: 1, icon: "forward.fill")
                .accessibilityLabel(String(localized: "torus.forward", defaultValue: "Forward"))
        }
    }

    /// A scrub button that moves the trajectory while held (DragGesture(minimumDistance: 0)).
    private func scrubButton(direction: Int, icon: String) -> some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundStyle(SpiralColors.text)
            .frame(width: 48, height: 48)
            .liquidGlass(circular: true)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isScrubbing {
                            isScrubbing = true
                            scene.startScrub(direction: direction)
                            // Show label during scrub
                            updateLabel()
                            withAnimation(.easeIn(duration: 0.2)) {
                                showLabel = true
                                labelOpacity = 1
                            }
                            // Update label at ~15fps during scrub
                            startLabelUpdateTimer()
                        }
                    }
                    .onEnded { _ in
                        isScrubbing = false
                        scene.stopScrub()
                        // Keep label visible briefly then fade
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            if !isScrubbing && isPaused {
                                // Keep showing if paused
                            } else if !isScrubbing {
                                withAnimation(.easeOut(duration: 0.3)) { labelOpacity = 0 }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    if !isScrubbing && !isPaused { showLabel = false }
                                }
                            }
                        }
                        stopLabelUpdateTimer()
                    }
            )
    }

    // MARK: - Label Update Timer

    @State private var labelTimer: Timer?

    private func startLabelUpdateTimer() {
        labelTimer?.invalidate()
        labelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { _ in
            Task { @MainActor in
                updateLabel()
            }
        }
    }

    private func stopLabelUpdateTimer() {
        labelTimer?.invalidate()
        labelTimer = nil
    }

    // MARK: - Play / Pause

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            scene.stopAnimation()
            updateLabel()
            withAnimation(.easeIn(duration: 0.3)) {
                showLabel = true
                labelOpacity = 1
            }
        } else {
            scene.startAnimation()
            withAnimation(.easeOut(duration: 0.3)) { labelOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if !isPaused { showLabel = false }
            }
        }

        #if canImport(UIKit)
        hapticGenerator.impactOccurred()
        #endif
    }

    // MARK: - Label

    private func updateLabel() {
        let stage = scene.currentStage
        let hour = scene.currentHour
        guard !stage.isEmpty else { return }

        let name: String
        switch stage {
        case "N3":  name = String(localized: "torus.stage.deep", defaultValue: "Deep")
        case "N2":  name = String(localized: "torus.stage.light", defaultValue: "Light")
        case "REM": name = String(localized: "torus.stage.rem", defaultValue: "REM")
        case "W":   name = String(localized: "torus.stage.wake", defaultValue: "Wake")
        default:    name = stage
        }
        labelText = "\(name) · \(hour)"
    }

    // MARK: - Data Loading

    private func loadRealData() {
        // Prefer the most recent record that actually looks like a full
        // sleep block (≥ 3h). Mirrors the same heuristic the header
        // uses so the trajectory and the header label always point at
        // the same night, not at a stray nap.
        let pick = store.records.last(where: { $0.sleepDuration >= 3.0 })
            ?? store.records.last
        guard let lastRecord = pick, !lastRecord.phases.isEmpty else {
            if !dataLoaded {
                scene.loadTrajectory(TorusSceneiPhone.mockNight())
                dataLoaded = true
            }
            return
        }

        // Does this sleep session wrap over midnight? SleepRecord
        // convention: record.date is the day of wake-up. If bedtime
        // is greater than wake-up (e.g. 23 > 7), the phases with a
        // high clock hour (near bedtime) actually belong to the
        // previous calendar day.
        let wrapsOverMidnight = lastRecord.bedtimeHour > lastRecord.wakeupHour
        let recordDayStart = Calendar.current.startOfDay(for: lastRecord.date)
        let previousDayStart = recordDayStart.addingTimeInterval(-86_400)

        // Convert PhaseInterval → SleepEpoch
        let epochs = lastRecord.phases.map { phase -> SleepEpoch in
            let stage: String
            switch phase.phase {
            case .deep:  stage = "N3"
            case .rem:   stage = "REM"
            case .light: stage = "N2"
            case .awake: stage = "W"
            }
            // Phases with a clock hour at or after bedtime belong to
            // the previous calendar day when the session wrapped. All
            // other phases (0…wakeupHour, or daytime sleep without
            // wrap) sit on the record's own day. This is what makes
            // the trajectory match the user's real wall-clock schedule
            // instead of showing the session as if it all happened on
            // the wake-up day.
            let dayAnchor: Date = (wrapsOverMidnight && phase.hour >= lastRecord.bedtimeHour)
                ? previousDayStart
                : recordDayStart
            let startDate = dayAnchor.addingTimeInterval(phase.hour * 3600)
            let endDate = startDate.addingTimeInterval(15 * 60)
            return SleepEpoch(start: startDate, end: endDate, stage: stage)
        }

        // Extract longest sleep window (exclude isolated wake)
        let sleepEpochs = extractSleepWindow(from: epochs)

        if sleepEpochs.count >= 5 {
            scene.loadTrajectory(sleepEpochs)
            dataLoaded = true
        } else if !dataLoaded {
            scene.loadTrajectory(TorusSceneiPhone.mockNight())
            dataLoaded = true
        }
    }

    /// Find the longest continuous sleep block (non-wake epochs, bridging isolated wakes).
    private func extractSleepWindow(from epochs: [SleepEpoch]) -> [SleepEpoch] {
        var blocks: [[SleepEpoch]] = []
        var current: [SleepEpoch] = []

        for (i, epoch) in epochs.enumerated() {
            if epoch.stage != "W" {
                current.append(epoch)
            } else {
                let nextIsSleep = i + 1 < epochs.count && epochs[i + 1].stage != "W"
                if nextIsSleep && !current.isEmpty {
                    // Bridge isolated wake within a sleep block
                    current.append(epoch)
                } else if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
            }
        }
        if !current.isEmpty { blocks.append(current) }

        return blocks.max(by: { $0.count < $1.count }) ?? []
    }
}

// MARK: - Transparent SceneKit View

/// SCNView wrapper with truly transparent background.
/// SwiftUI's SceneView always paints an opaque background;
/// this UIViewRepresentable sets backgroundColor = .clear directly.
#if canImport(UIKit)
struct TransparentSceneView: UIViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}
}
#elseif canImport(AppKit)
struct TransparentSceneView: NSViewRepresentable {
    let scene: SCNScene
    let pointOfView: SCNNode

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.pointOfView = pointOfView
        view.layer?.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {}
}
#endif
