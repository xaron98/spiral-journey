import SwiftUI
import SceneKit
import SpiralKit
import WatchKit

/// 3D torus sleep visualization for Apple Watch.
///
/// Interactions:
/// - **Tap**: pause/resume animation. When paused, shows stage + time label.
/// - **Crown (playing)**: rotates camera around the torus.
/// - **Crown (paused)**: scrubs through the night (time travel).
/// - **Haptic**: vibrates on each sleep stage transition.
struct SleepTorusView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var scene = SleepTorusScene()
    @State private var crownValue: Double = 0.0
    @State private var lastCrownValue: Double = 0.0
    @State private var dataLoaded = false
    @State private var isPaused = false
    @State private var wasPlayingBeforeSleep = false
    @State private var showLabel = false
    @State private var labelText = ""
    @State private var labelOpacity: Double = 0
    @State private var lastDragLocation: CGPoint?

    var body: some View {
        ZStack {
            SceneView(
                scene: scene.scene,
                pointOfView: scene.cameraNode,
                options: []
            )
            .ignoresSafeArea()

            // Stage + time label (shown on tap when paused)
            if showLabel {
                VStack {
                    Spacer()
                    Text(labelText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial, in: Capsule())
                        .opacity(labelOpacity)
                    Spacer().frame(height: 16)
                }
            }
        }
        .focusable(true)
        .digitalCrownRotation($crownValue, from: 0, through: 1000, sensitivity: .high, isContinuous: true)
        .onChange(of: crownValue) { _, newValue in
            // Compute delta, handling wrap-around at 1000 boundary
            var delta = newValue - lastCrownValue
            if delta > 500 { delta -= 1000 }
            else if delta < -500 { delta += 1000 }
            lastCrownValue = newValue

            if isPaused {
                // Scrub mode: Crown moves through the night
                let fraction = (newValue.truncatingRemainder(dividingBy: 1000)) / 1000.0
                scene.scrubTo(fraction: abs(fraction))
                updateLabel()
            } else {
                // Rotate mode: apply incremental delta to avoid jump at wrap boundary
                let deltaRad = Float(delta * .pi / 180)
                scene.orbitCamera(deltaAngle: deltaRad, deltaElevation: 0)
            }
        }
        .onTapGesture {
            togglePause()
        }
        // Drag + tap overlay — ONLY active when paused.
        // When playing, allowsHitTesting(false) lets swipes/taps pass to TabView and ZStack.
        .overlay {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    togglePause()
                }
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            if let last = lastDragLocation {
                                let dx = Float(value.location.x - last.x)
                                let dy = Float(value.location.y - last.y)
                                scene.orbitCamera(deltaAngle: dx * 0.015, deltaElevation: -dy * 0.01)
                            }
                            lastDragLocation = value.location
                        }
                        .onEnded { _ in
                            lastDragLocation = nil
                        }
                )
                .allowsHitTesting(isPaused)
        }
        .task {
            // Haptic on stage transitions
            scene.onStageTransition = { _ in
                WKInterfaceDevice.current().play(.click)
            }
            loadRealData()
            // Start animation only when this tab is visible
            scene.startAnimation()
        }
        .onDisappear {
            // Stop everything when user swipes to another tab — save battery
            scene.stopAnimation()
        }
        .onChange(of: store.records.count) { _, _ in
            loadRealData()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Screen woke up — resume if it was playing before
                if wasPlayingBeforeSleep {
                    scene.startAnimation()
                    wasPlayingBeforeSleep = false
                }
            } else {
                // Screen off or background — stop animation + haptics
                if scene.isAnimating {
                    wasPlayingBeforeSleep = true
                    scene.stopAnimation()
                }
            }
        }
    }

    private func togglePause() {
        isPaused.toggle()
        if isPaused {
            scene.stopAnimation()
            updateLabel()
            withAnimation(.easeIn(duration: 0.3)) { showLabel = true; labelOpacity = 1 }
        } else {
            scene.startAnimation()
            withAnimation(.easeOut(duration: 0.3)) { labelOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showLabel = false }
        }
    }

    private func updateLabel() {
        let stage = scene.currentStage
        let hour = scene.currentHour
        let name: String
        switch stage {
        case "N3":  name = "Deep"
        case "N2":  name = "Light"
        case "REM": name = "REM"
        case "W":   name = "Wake"
        default:    name = stage
        }
        labelText = "\(name) · \(hour)"
    }

    private func loadRealData() {
        guard let lastRecord = store.records.last, !lastRecord.phases.isEmpty else {
            if !dataLoaded {
                scene.loadTrajectory(TorusGeometry.mockNight())
            }
            return
        }

        let epochs = lastRecord.phases.map { phase -> SleepEpoch in
            let stage: String
            switch phase.phase {
            case .deep:  stage = "N3"
            case .rem:   stage = "REM"
            case .light: stage = "N2"
            case .awake: stage = "W"
            }
            let startDate = Calendar.current.startOfDay(for: lastRecord.date)
                .addingTimeInterval(phase.hour * 3600)
            let endDate = startDate.addingTimeInterval(15 * 60)
            return SleepEpoch(start: startDate, end: endDate, stage: stage)
        }

        let sleepEpochs = extractSleepWindow(from: epochs)

        if sleepEpochs.count >= 5 {
            scene.loadTrajectory(sleepEpochs)
            dataLoaded = true
        } else if !dataLoaded {
            scene.loadTrajectory(TorusGeometry.mockNight())
        }
    }

    private func extractSleepWindow(from epochs: [SleepEpoch]) -> [SleepEpoch] {
        var blocks: [[SleepEpoch]] = []
        var current: [SleepEpoch] = []

        for (i, epoch) in epochs.enumerated() {
            if epoch.stage != "W" {
                current.append(epoch)
            } else {
                let nextIsSleep = i + 1 < epochs.count && epochs[i + 1].stage != "W"
                if nextIsSleep && !current.isEmpty {
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
