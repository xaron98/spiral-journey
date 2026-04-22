# Tri-Modal Sleep Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform SpiralTab into a tri-modal sleep viewer (Torus/Spiral/DNA) with horizontal swipe navigation, each mode representing a temporal perspective (past/present/future).

**Architecture:** SpiralTab becomes a thin container with a fixed header (contextual text + pills selector) and a `TabView(.page)` pager housing 3 independent mode views. Each mode carries its own action bar. Torus uses SceneKit (iOS 17+), Spiral reuses existing Canvas, DNA reorganizes existing views into scrollable cards.

**Tech Stack:** SwiftUI, SceneKit, SpiralKit, SpiralGeometry

**Spec:** `docs/superpowers/specs/2026-04-13-tri-modal-sleep-viewer-design.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `Views/Tabs/ModePillsView.swift` | Segmented control pills (Torus/Spiral/DNA) |
| `Views/Tabs/ModeHeaderView.swift` | Contextual header text with crossfade |
| `Views/Tabs/SpiralModeView.swift` | Extracted spiral content + action bar |
| `Views/Tabs/TorusModeView.swift` | Torus 3D container + action bar |
| `Views/Tabs/TorusSceneiPhone.swift` | SceneKit scene for iPhone torus (based on Watch) |
| `Views/Tabs/DNAModeView.swift` | DNA cards ScrollView + action bar |
| `Views/DNA/DNACardView.swift` | Reusable card component (compact/large) |

### Modified Files
| File | Change |
|------|--------|
| `Views/Tabs/SpiralTab.swift` | Gutted to thin container: header + pills + pager |
| `Views/DNA/NeuroSpiralView.swift` | Content extracted into DNAModeView cards (file kept for backward compat, may become wrapper) |
| `SpiralGeometry/.../WearableMapping.swift` | Add 3 missing toroidal features to SleepTrajectoryAnalysis |

### Reused As Card Content (no changes)
| File | Used in |
|------|---------|
| `Views/DNA/SleepTriangleView.swift` | Large inline card |
| `Views/DNA/NeuroSpiralHistoryView.swift` | Large inline card |
| `Views/DNA/NeuroSpiralExportView.swift` | Compact export card |
| `Views/DNA/HelixSceneBuilder.swift` | Compact preview + fullscreen |

---

## Task 1: ModePillsView + ModeHeaderView (shared components)

**Files:**
- Create: `spiral journey project/Views/Tabs/ModePillsView.swift`
- Create: `spiral journey project/Views/Tabs/ModeHeaderView.swift`

- [ ] **Step 1: Create ModePillsView**

```swift
// spiral journey project/Views/Tabs/ModePillsView.swift
import SwiftUI

struct ModePillsView: View {
    @Binding var selectedMode: Int
    
    private let modes: [(icon: String, label: String)] = [
        ("circle.hexagonpath", "Torus"),
        ("spiral", "Spiral"),
        ("dnstrand.turn.2", "DNA"),  // SF Symbol: "line.3.crossed.swirl.circle" fallback
    ]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selectedMode = index
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: modes[index].icon)
                            .font(.caption2)
                        Text(modes[index].label)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        selectedMode == index
                            ? SpiralColors.accent.opacity(0.2)
                            : Color.clear,
                        in: Capsule()
                    )
                    .foregroundStyle(
                        selectedMode == index
                            ? SpiralColors.accent
                            : SpiralColors.muted
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 2: Create ModeHeaderView**

```swift
// spiral journey project/Views/Tabs/ModeHeaderView.swift
import SwiftUI
import SpiralKit

struct ModeHeaderView: View {
    let selectedMode: Int
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    
    var body: some View {
        Text(headerText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(SpiralColors.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .id(selectedMode) // forces view identity change for transition
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: selectedMode)
    }
    
    private var headerText: String {
        switch selectedMode {
        case 0: return torusHeader
        case 1: return spiralHeader
        case 2: return dnaHeader
        default: return ""
        }
    }
    
    private var torusHeader: String {
        guard let last = store.records.last else {
            return String(localized: "mode.torus.no_data", bundle: bundle)
        }
        let hours = String(format: "%.1f", last.sleepDuration)
        return "\(String(localized: "mode.torus.last_night", bundle: bundle)) · \(hours)h"
    }
    
    private var spiralHeader: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = store.userName ?? "Carlos"
        if hour >= 21 || hour < 6 {
            return String(format: String(localized: "mode.spiral.good_night", bundle: bundle), name)
        } else if hour < 12 {
            return String(format: String(localized: "mode.spiral.good_morning", bundle: bundle), name)
        } else {
            return String(format: String(localized: "mode.spiral.good_afternoon", bundle: bundle), name)
        }
    }
    
    private var dnaHeader: String {
        String(localized: "mode.dna.header", bundle: bundle)
    }
}
```

- [ ] **Step 3: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

- [ ] **Step 4: Add localization keys to Localizable.xcstrings**

Add keys for all 8 languages (ar, ca, de, en, es, fr, ja, zh-Hans):
- `mode.torus.no_data` → "No data" / "Sin datos" / etc.
- `mode.torus.last_night` → "Last night" / "Anoche" / etc.
- `mode.spiral.good_night` → "Good night, %@" / "Buenas noches, %@" / etc.
- `mode.spiral.good_morning` → "Good morning, %@" / "Buenos días, %@" / etc.
- `mode.spiral.good_afternoon` → "Good afternoon, %@" / "Buenas tardes, %@" / etc.
- `mode.dna.header` → "Your patterns" / "Tus patrones" / etc.

- [ ] **Step 5: Commit**

```
feat: add ModePillsView and ModeHeaderView for tri-modal viewer
```

---

## Task 2: TorusSceneiPhone (SceneKit scene for iPhone)

**Files:**
- Create: `spiral journey project/Views/Tabs/TorusSceneiPhone.swift`
- Reference: `Spiral Watch App Watch App/SleepTorusScene.swift`
- Reference: `Spiral Watch App Watch App/TorusGeometry.swift`

- [ ] **Step 1: Create TorusSceneiPhone.swift**

Port Watch's `SleepTorusScene` + `TorusGeometry` into a single iPhone-adapted class. Key differences from Watch:
- Transparent background (`UIColor.clear`)
- Higher resolution trail (~400 segments vs 200)
- Finer wireframe (pipe/ring radii smaller)
- Timer at 60fps (not 10fps) for smooth trail animation
- Larger camera distance for iPhone screen

```swift
// spiral journey project/Views/Tabs/TorusSceneiPhone.swift
import SceneKit
import SpiralKit

#if canImport(UIKit)
import UIKit
typealias SCNPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias SCNPlatformColor = NSColor
#endif

class TorusSceneiPhone {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private var torusParent = SCNNode()
    private var dotNode = SCNNode()
    private var haloNode = SCNNode()
    private var trailNode = SCNNode()
    private(set) var trajectoryPoints: [SCNVector3] = []
    private(set) var trajectoryStages: [String] = []
    private(set) var currentIndex = 0
    private var animationTimer: Timer?
    private var previousStage: String?
    
    // Scrub direction: -1 rewind, 0 stopped, +1 forward
    private var scrubDirection: Int = 0
    private var scrubTimer: Timer?

    var onStageTransition: ((String) -> Void)?

    // Torus geometry constants (same as Watch)
    static let R: Float = 1.8
    static let r: Float = 0.6

    // Phase-to-phi mapping
    static let phiMap: [String: Float] = [
        "W":   0.05 * 2 * .pi,
        "N1":  0.25 * 2 * .pi,
        "N2":  0.55 * 2 * .pi,
        "REM": 0.62 * 2 * .pi,
        "N3":  0.85 * 2 * .pi,
    ]

    private let stageColors: [String: SCNPlatformColor] = [
        "W":   SCNPlatformColor(red: 0.50, green: 0.47, blue: 0.87, alpha: 1),
        "N1":  SCNPlatformColor(red: 0.52, green: 0.72, blue: 0.92, alpha: 1),
        "N2":  SCNPlatformColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1),
        "N3":  SCNPlatformColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 1),
        "REM": SCNPlatformColor(red: 0.83, green: 0.33, blue: 0.49, alpha: 1),
    ]

    init() {
        scene.background.contents = SCNPlatformColor.clear
        setupCamera()
        setupTorus()
        setupLighting()
    }

    // MARK: - Camera

    private(set) var cameraAngle: Float = 0
    private(set) var cameraElevation: Float = 0.6

    private func setupCamera() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        positionCamera(angle: 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    func positionCamera(angle: Float, elevation: Float? = nil) {
        let distance: Float = 10.0
        cameraAngle = angle
        if let elevation { cameraElevation = elevation }
        let elev = min(max(cameraElevation, -1.2), 1.4)
        cameraElevation = elev
        cameraNode.position = SCNVector3(
            sin(angle) * distance * cos(elev),
            distance * sin(elev),
            cos(angle) * distance * cos(elev)
        )
        cameraNode.look(at: SCNVector3Zero)
    }

    func orbitCamera(deltaAngle: Float, deltaElevation: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        positionCamera(angle: cameraAngle + deltaAngle, elevation: cameraElevation + deltaElevation)
        SCNTransaction.commit()
    }

    // MARK: - Torus

    private func setupTorus() {
        let torus = SCNTorus(ringRadius: CGFloat(Self.R), pipeRadius: CGFloat(Self.r))
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = SCNPlatformColor(red: 0.20, green: 0.22, blue: 0.35, alpha: 1)
        material.transparency = 0.20
        material.lightingModel = .constant
        material.isDoubleSided = true
        torus.materials = [material]
        torusParent.addChildNode(SCNNode(geometry: torus))

        // Solid back-face
        let solidTorus = SCNTorus(ringRadius: CGFloat(Self.R), pipeRadius: CGFloat(Self.r))
        let solidMat = SCNMaterial()
        solidMat.diffuse.contents = SCNPlatformColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
        solidMat.transparency = 0.4
        solidMat.lightingModel = .phong
        solidMat.cullMode = .front
        solidTorus.materials = [solidMat]
        torusParent.addChildNode(SCNNode(geometry: solidTorus))

        // Slow auto-rotation
        let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)
        torusParent.runAction(.repeatForever(rotate))

        scene.rootNode.addChildNode(torusParent)
    }

    private func setupLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = SCNPlatformColor(red: 0.6, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 600
        rim.light?.color = SCNPlatformColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.5, 0.8, 0)
        scene.rootNode.addChildNode(rim)
    }

    // MARK: - Torus Geometry

    static func position(theta: Float, phi: Float) -> SCNVector3 {
        let x = (R + r * cos(phi)) * cos(theta)
        let y = r * sin(phi)
        let z = (R + r * cos(phi)) * sin(theta)
        return SCNVector3(x, y, z)
    }

    // MARK: - Trajectory

    func loadTrajectory(_ epochs: [SleepEpoch]) {
        trailNode.removeFromParentNode()
        dotNode.removeFromParentNode()
        haloNode.removeFromParentNode()

        let (points, stages) = Self.buildTrajectory(from: epochs)
        trajectoryPoints = points
        trajectoryStages = stages
        currentIndex = 0

        // Full trajectory faint line
        if points.count >= 2 {
            trailNode = createTrailNode(points: points, stages: stages, alpha: 0.12)
            torusParent.addChildNode(trailNode)
        }

        // Dot
        let dot = SCNSphere(radius: 0.06)
        dot.firstMaterial?.lightingModel = .constant
        dot.firstMaterial?.diffuse.contents = SCNPlatformColor.white
        dotNode = SCNNode(geometry: dot)
        if let first = points.first { dotNode.position = first }
        torusParent.addChildNode(dotNode)

        // Halo
        let halo = SCNSphere(radius: 0.12)
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.diffuse.contents = SCNPlatformColor.white.withAlphaComponent(0.15)
        haloNode = SCNNode(geometry: halo)
        if let first = points.first { haloNode.position = first }
        torusParent.addChildNode(haloNode)
    }

    static func buildTrajectory(
        from epochs: [SleepEpoch],
        numPoints: Int = 960,
        turns: Float = 4.5
    ) -> ([SCNVector3], [String]) {
        guard !epochs.isEmpty else { return ([], []) }
        let totalDuration = epochs.last!.end.timeIntervalSince(epochs.first!.start)
        guard totalDuration > 0 else { return ([], []) }

        var points: [SCNVector3] = []
        var stages: [String] = []
        let maxPhiStep: Float = 0.12
        var prevPhi: Float = phiMap[epochs.first!.stage] ?? 0

        for i in 0..<numPoints {
            let frac = Float(i) / Float(numPoints - 1)
            let time = epochs.first!.start.addingTimeInterval(Double(frac) * totalDuration)

            // Find current epoch
            let epoch = epochs.last(where: { $0.start <= time }) ?? epochs.first!
            let targetPhi = phiMap[epoch.stage] ?? prevPhi

            // Smooth phi transition
            var phi = targetPhi
            let deltaPhi = phi - prevPhi
            if abs(deltaPhi) > maxPhiStep {
                phi = prevPhi + maxPhiStep * (deltaPhi > 0 ? 1 : -1)
            }
            // Organic noise
            phi += Float.random(in: -0.03...0.03)
            prevPhi = phi

            let theta = frac * turns * 2 * .pi
            points.append(position(theta: theta, phi: phi))
            stages.append(epoch.stage)
        }
        return (points, stages)
    }

    // MARK: - Animation

    var isAnimating: Bool { animationTimer?.isValid ?? false }

    func startAnimation() {
        torusParent.isPaused = false
        animationTimer?.invalidate()
        // 60fps for smooth trail on iPhone
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.trajectoryPoints.count
            self.updateDotPosition()
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        torusParent.isPaused = true
    }

    // MARK: - Scrub (Rewind / Forward)

    /// Start continuous scrub in given direction. Called on button press.
    func startScrub(direction: Int) {
        scrubDirection = direction
        scrubTimer?.invalidate()
        // 60fps scrub with trail visible
        scrubTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            let step = self.scrubDirection * 2 // 2 points per frame for visible movement
            var newIdx = self.currentIndex + step
            // Clamp instead of wrap
            newIdx = max(0, min(self.trajectoryPoints.count - 1, newIdx))
            self.currentIndex = newIdx
            self.updateDotPosition()
        }
    }

    /// Stop continuous scrub. Called on button release.
    func stopScrub() {
        scrubDirection = 0
        scrubTimer?.invalidate()
        scrubTimer = nil
    }

    /// Scrub to exact fraction (0.0 to 1.0).
    func scrubTo(fraction: Double) {
        guard !trajectoryPoints.isEmpty else { return }
        currentIndex = max(0, min(trajectoryPoints.count - 1,
            Int(fraction * Double(trajectoryPoints.count - 1))))
        updateDotPosition()
    }

    // MARK: - State

    var currentStage: String {
        guard !trajectoryStages.isEmpty else { return "" }
        return trajectoryStages[min(currentIndex, trajectoryStages.count - 1)]
    }

    var currentHour: String {
        guard !trajectoryPoints.isEmpty else { return "" }
        let fraction = Double(currentIndex) / Double(max(1, trajectoryPoints.count - 1))
        let totalMinutes = fraction * 8 * 60
        let hour = (23 + Int(totalMinutes) / 60) % 24
        let min = Int(totalMinutes) % 60
        return String(format: "%02d:%02d", hour, min)
    }

    private func updateDotPosition() {
        guard currentIndex < trajectoryPoints.count else { return }
        let pt = trajectoryPoints[currentIndex]
        dotNode.position = pt
        haloNode.position = pt

        let stage = trajectoryStages[currentIndex]
        let color = stageColors[stage] ?? .white
        dotNode.geometry?.firstMaterial?.diffuse.contents = color
        haloNode.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.15)

        if stage != previousStage, previousStage != nil {
            onStageTransition?(stage)
        }
        previousStage = stage
    }

    // MARK: - Trail Line

    private func createTrailNode(points: [SCNVector3], stages: [String], alpha: CGFloat) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        let parent = SCNNode()
        let segStep = max(1, points.count / 400)

        for i in stride(from: segStep, to: points.count, by: segStep) {
            let prev = points[i - segStep]
            let curr = points[i]
            let mid = SCNVector3((prev.x + curr.x) / 2, (prev.y + curr.y) / 2, (prev.z + curr.z) / 2)
            let dx = curr.x - prev.x, dy = curr.y - prev.y, dz = curr.z - prev.z
            let length = sqrt(dx * dx + dy * dy + dz * dz)
            guard length > 0.01 else { continue }

            let cyl = SCNCylinder(radius: 0.018, height: CGFloat(length))
            let color = stageColors[stages[i]] ?? .gray
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = color.withAlphaComponent(alpha)
            mat.isDoubleSided = true
            cyl.materials = [mat]

            let node = SCNNode(geometry: cyl)
            node.position = mid

            let dir = SCNVector3(dx / length, dy / length, dz / length)
            let up = SCNVector3(0, 1, 0)
            let dotP = up.x * dir.x + up.y * dir.y + up.z * dir.z
            if abs(dotP) < 0.999 {
                let cross = SCNVector3(
                    up.y * dir.z - up.z * dir.y,
                    up.z * dir.x - up.x * dir.z,
                    up.x * dir.y - up.y * dir.x
                )
                let crossLen = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
                let angle = acos(max(-1, min(1, dotP)))
                node.rotation = SCNVector4(cross.x / crossLen, cross.y / crossLen, cross.z / crossLen, angle)
            }
            parent.addChildNode(node)
        }
        return parent
    }
}
```

- [ ] **Step 2: Build to verify**

Run: `xcodebuild build -scheme "spiral journey project" -destination "platform=iOS Simulator,id=58B00C42-E274-4903-8E91-84CCA65CBC3A"`

- [ ] **Step 3: Commit**

```
feat: add TorusSceneiPhone (SceneKit 3D torus for iPhone, based on Watch)
```

---

## Task 3: TorusModeView (Torus page with action bar)

**Files:**
- Create: `spiral journey project/Views/Tabs/TorusModeView.swift`
- Reference: `Spiral Watch App Watch App/SleepTorusView.swift`

- [ ] **Step 1: Create TorusModeView.swift**

```swift
// spiral journey project/Views/Tabs/TorusModeView.swift
import SwiftUI
import SceneKit
import SpiralKit

struct TorusModeView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var scene = TorusSceneiPhone()
    @State private var isPaused = false
    @State private var showLabel = false
    @State private var labelText = ""
    @State private var lastDragLocation: CGPoint?
    @State private var dataLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            // Main torus area
            ZStack {
                SceneView(
                    scene: scene.scene,
                    pointOfView: scene.cameraNode,
                    options: []
                )
                .background(Color.clear)

                // Phase + time label
                if showLabel {
                    VStack {
                        Spacer()
                        Text(labelText)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(.bottom, 16)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if let last = lastDragLocation {
                            let dx = Float(value.location.x - last.x)
                            let dy = Float(value.location.y - last.y)
                            scene.orbitCamera(deltaAngle: dx * 0.008, deltaElevation: -dy * 0.006)
                        }
                        lastDragLocation = value.location
                    }
                    .onEnded { _ in
                        lastDragLocation = nil
                    }
            )
            .onTapGesture {
                isPaused.toggle()
                if isPaused {
                    scene.stopAnimation()
                    updateLabel()
                    withAnimation(.easeIn(duration: 0.25)) { showLabel = true }
                } else {
                    scene.startAnimation()
                    withAnimation(.easeOut(duration: 0.25)) { showLabel = false }
                }
            }

            // Action bar
            torusActionBar
                .padding(.bottom, 8)
        }
        .task {
            #if canImport(UIKit)
            scene.onStageTransition = { _ in
                let gen = UIImpactFeedbackGenerator(style: .light)
                gen.impactOccurred()
            }
            #endif
            loadData()
        }
        .onChange(of: store.records.count) { _, _ in
            loadData()
        }
    }

    // MARK: - Action Bar

    private var torusActionBar: some View {
        HStack(spacing: 24) {
            // Rewind button — continuous scrub while held
            Button {} label: {
                Image(systemName: "backward.fill")
                    .font(.title3)
                    .foregroundStyle(SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in scene.startScrub(direction: -1) }
                    .onEnded { _ in scene.stopScrub() }
            )

            // Play/Pause
            Button {
                isPaused.toggle()
                if isPaused {
                    scene.stopAnimation()
                    updateLabel()
                    withAnimation(.easeIn(duration: 0.25)) { showLabel = true }
                } else {
                    scene.startAnimation()
                    withAnimation(.easeOut(duration: 0.25)) { showLabel = false }
                }
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

            // Forward button — continuous scrub while held
            Button {} label: {
                Image(systemName: "forward.fill")
                    .font(.title3)
                    .foregroundStyle(SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in scene.startScrub(direction: 1) }
                    .onEnded { _ in scene.stopScrub() }
            )
        }
    }

    // MARK: - Helpers

    private func updateLabel() {
        let stage = scene.currentStage
        let hour = scene.currentHour
        let name: String
        switch stage {
        case "N3":  name = String(localized: "torus.phase.deep", bundle: bundle)
        case "N2":  name = String(localized: "torus.phase.light", bundle: bundle)
        case "REM": name = "REM"
        case "W":   name = String(localized: "torus.phase.wake", bundle: bundle)
        default:    name = stage
        }
        labelText = "\(name) · \(hour)"
    }

    private func loadData() {
        guard let lastRecord = store.records.last, !lastRecord.phases.isEmpty else {
            if !dataLoaded {
                scene.loadTrajectory(TorusSceneiPhone.mockNight())
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
            scene.loadTrajectory(TorusSceneiPhone.mockNight())
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

// MARK: - Mock Data

extension TorusSceneiPhone {
    static func mockNight() -> [SleepEpoch] {
        let base = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        let stages = ["W", "N1", "N2", "N3", "N3", "N2", "REM", "N2", "N3", "N2", "REM",
                      "N2", "N3", "N2", "REM", "N1", "W"]
        return stages.enumerated().map { i, stage in
            let start = base.addingTimeInterval(Double(i) * 30 * 60)
            let end = start.addingTimeInterval(30 * 60)
            return SleepEpoch(start: start, end: end, stage: stage)
        }
    }
}
```

- [ ] **Step 2: Add localization keys for torus phase labels**

Add to `Localizable.xcstrings` for all 8 languages:
- `torus.phase.deep` → "Deep" / "Profundo"
- `torus.phase.light` → "Light" / "Ligero"
- `torus.phase.wake` → "Wake" / "Vigilia"

- [ ] **Step 3: Build to verify**

- [ ] **Step 4: Commit**

```
feat: add TorusModeView with SceneKit 3D torus, play/pause, continuous scrub
```

---

## Task 4: Extract SpiralModeView from SpiralTab

**Files:**
- Create: `spiral journey project/Views/Tabs/SpiralModeView.swift`
- Modify: `spiral journey project/Views/Tabs/SpiralTab.swift`

This is the most critical task. The goal is to extract the spiral content (Canvas + overlays + action bar) into a standalone view while keeping all state management working.

- [ ] **Step 1: Create SpiralModeView.swift**

Create `SpiralModeView` that wraps the spiral content. This view receives bindings to shared state from SpiralTab and owns the spiral-specific state. The exact content is the current SpiralTab body's ZStack layers 1–8 (background through action bar), MINUS the fixed header and DNA button (which move to the container).

The file should contain:
- All `@State` variables currently in SpiralTab related to spiral interaction (interaction manager, sleepStartHour, eventLogging, selectedElementInfo, etc.)
- The spiral Canvas (SpiralView) with all gestures
- Floating overlays (date pill, cursor bar, info card, coach tip, undo toast)
- The action bar (stats, log, coach buttons)
- All helper methods (handleLogButton, handleEventLogButton, nearestHour, projection helpers, etc.)
- All computed properties (logButtonIcon, logButtonColor, etc.)

What stays in SpiralTab container:
- `@State selectedMode: Int`
- `@Binding selectedTab: AppTab`
- The `NavigationStack` wrapper
- Sheet presentations (`.sheet(isPresented: $showDNAInsights)` etc.) — these move to container level

**Note**: Because SpiralTab.swift is 2119 lines, this step is a large extraction. The agent should read the full file, identify all state and body content, and move it. The key principle: SpiralModeView should work identically to the current SpiralTab when displayed alone.

- [ ] **Step 2: Stub SpiralTab as container**

Temporarily make SpiralTab show only SpiralModeView (no pager yet) to verify the extraction works:

```swift
// Temporary — Task 6 will add the full pager
var body: some View {
    NavigationStack {
        SpiralModeView(selectedTab: $selectedTab)
    }
}
```

- [ ] **Step 3: Build and verify**

Run build. The app should behave identically to before the refactor.

- [ ] **Step 4: Commit**

```
refactor: extract SpiralModeView from SpiralTab (no behavioral change)
```

---

## Task 5: DNAModeView + DNACardView (DNA cards page)

**Files:**
- Create: `spiral journey project/Views/Tabs/DNAModeView.swift`
- Create: `spiral journey project/Views/DNA/DNACardView.swift`

- [ ] **Step 1: Create DNACardView.swift**

Reusable card component with compact and large variants:

```swift
// spiral journey project/Views/DNA/DNACardView.swift
import SwiftUI

struct DNACardView<Content: View>: View {
    let title: String
    let icon: String
    let isLarge: Bool
    let content: Content

    init(
        _ title: String,
        icon: String,
        isLarge: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.isLarge = isLarge
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.accent)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                if !isLarge {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            content
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
```

- [ ] **Step 2: Create DNAModeView.swift**

```swift
// spiral journey project/Views/Tabs/DNAModeView.swift
import SwiftUI
import SpiralKit

struct DNAModeView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var analysis: SleepTrajectoryAnalysis?
    @State private var isAnalyzing = false
    @State private var showPatternArrows = false
    @State private var showHelixFullscreen = false
    @State private var showPatternDetail = false
    @State private var showMutationDetail = false
    @State private var showPredictionDetail = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    // Card 1: Patterns (compact)
                    DNACardView(
                        String(localized: "dna.card.patterns", bundle: bundle),
                        icon: "link"
                    ) {
                        patternsPreview
                    }
                    .onTapGesture { showPatternDetail = true }

                    // Card 2: Mutations (compact)
                    DNACardView(
                        String(localized: "dna.card.mutations", bundle: bundle),
                        icon: "bolt.trianglebadge.exclamationmark"
                    ) {
                        mutationsPreview
                    }
                    .onTapGesture { showMutationDetail = true }

                    // Card 3: Sleep Triangle (large inline)
                    DNACardView(
                        String(localized: "dna.card.triangle", bundle: bundle),
                        icon: "triangle",
                        isLarge: true
                    ) {
                        SleepTriangleView()
                            .frame(height: 280)
                    }

                    // Card 4: Helix 3D (compact preview)
                    DNACardView(
                        String(localized: "dna.card.helix", bundle: bundle),
                        icon: "dnstrand.turn.2"
                    ) {
                        helixPreview
                    }
                    .onTapGesture { showHelixFullscreen = true }

                    // Card 5: History sparklines (large inline)
                    DNACardView(
                        String(localized: "dna.card.history", bundle: bundle),
                        icon: "chart.xyaxis.line",
                        isLarge: true
                    ) {
                        historyContent
                    }

                    // Card 6: Circadian Health (large inline)
                    DNACardView(
                        String(localized: "dna.card.health", bundle: bundle),
                        icon: "heart.text.clipboard",
                        isLarge: true
                    ) {
                        healthMarkersContent
                    }

                    // Card 7: Prediction (compact)
                    DNACardView(
                        String(localized: "dna.card.prediction", bundle: bundle),
                        icon: "sparkles"
                    ) {
                        predictionPreview
                    }
                    .onTapGesture { showPredictionDetail = true }

                    // Card 8: Export (compact button)
                    DNACardView(
                        String(localized: "dna.card.export", bundle: bundle),
                        icon: "square.and.arrow.up"
                    ) {
                        Text(String(localized: "dna.card.export.subtitle", bundle: bundle))
                            .font(.caption)
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100) // space for action bar
            }

            // Action bar
            dnaActionBar
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showHelixFullscreen) {
            // Existing Helix3DView fullscreen
        }
        .sheet(isPresented: $showPatternDetail) {
            // Pattern detail sheet
        }
    }

    // MARK: - Action Bar

    private var dnaActionBar: some View {
        HStack(spacing: 24) {
            // Patterns — show animated arrows on helix
            Button {
                withAnimation(.spring(response: 0.5)) {
                    showPatternArrows.toggle()
                }
            } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(showPatternArrows ? SpiralColors.accent : SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .disabled(!isAnalyzing && analysis == nil)

            // Analyze
            Button {
                Task { await runAnalysis() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "7c3aed"))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(hex: "7c3aed").opacity(0.5), radius: 10)
                    if isAnalyzing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)

            // Mutations / Range
            Button {
                showMutationDetail = true
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .disabled(!isAnalyzing && analysis == nil)
        }
    }

    // MARK: - Card Previews (placeholders — populate with real data)

    private var patternsPreview: some View {
        HStack {
            Text(String(localized: "dna.patterns.none_yet", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
        }
    }

    private var mutationsPreview: some View {
        HStack {
            Text(String(localized: "dna.mutations.none_yet", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
        }
    }

    private var helixPreview: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(SpiralColors.bg.opacity(0.5))
            .frame(height: 80)
            .overlay {
                Image(systemName: "view.3d")
                    .font(.title2)
                    .foregroundStyle(SpiralColors.muted)
            }
    }

    private var historyContent: some View {
        // Reuse NeuroSpiralHistoryView content inline
        Text(String(localized: "dna.history.placeholder", bundle: bundle))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
    }

    private var healthMarkersContent: some View {
        Text(String(localized: "dna.health.placeholder", bundle: bundle))
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
    }

    private var predictionPreview: some View {
        HStack {
            Text(String(localized: "dna.prediction.placeholder", bundle: bundle))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
        }
    }

    // MARK: - Analysis

    private func runAnalysis() async {
        isAnalyzing = true
        // Trigger NeuroSpiral analysis from store data
        // This will be wired to the existing loadAndAnalyze() logic from NeuroSpiralView
        try? await Task.sleep(for: .seconds(1))
        isAnalyzing = false
    }
}
```

- [ ] **Step 3: Add all DNA card localization keys (8 languages)**

Keys: `dna.card.patterns`, `dna.card.mutations`, `dna.card.triangle`, `dna.card.helix`, `dna.card.history`, `dna.card.health`, `dna.card.prediction`, `dna.card.export`, `dna.card.export.subtitle`, `dna.patterns.none_yet`, `dna.mutations.none_yet`, `dna.history.placeholder`, `dna.health.placeholder`, `dna.prediction.placeholder`

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```
feat: add DNAModeView with scrollable cards + DNACardView component
```

---

## Task 6: Wire SpiralTab as Tri-Modal Pager

**Files:**
- Modify: `spiral journey project/Views/Tabs/SpiralTab.swift`

- [ ] **Step 1: Rewrite SpiralTab as container**

Replace the temporary stub from Task 4 with the full pager:

```swift
struct SpiralTab: View {
    @Binding var selectedTab: AppTab
    @Environment(SpiralStore.self) private var store
    @State private var selectedMode: Int = 1 // Default: Spiral (center)

    var body: some View {
        NavigationStack {
            GeometryReader { screen in
                VStack(spacing: 0) {
                    // Fixed header
                    VStack(spacing: 8) {
                        ModeHeaderView(selectedMode: selectedMode)
                            .padding(.top, screen.safeAreaInsets.top + 8)
                        ModePillsView(selectedMode: $selectedMode)
                    }

                    // Pager
                    TabView(selection: $selectedMode) {
                        TorusModeView()
                            .tag(0)
                        SpiralModeView(selectedTab: $selectedTab)
                            .tag(1)
                        DNAModeView()
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: selectedMode)
                }
                .ignoresSafeArea(edges: .top)
            }
        }
    }
}
```

- [ ] **Step 2: Remove the DNA Insights sheet**

The `showDNAInsights` flag and its `.sheet` presentation in SpiralModeView can be removed — DNA content is now in the pager. Remove the DNA button from SpiralModeView's Layer 3 (top-right corner). Keep the add/log button.

- [ ] **Step 3: Build and run in simulator**

Verify:
- Default view is Spiral (center)
- Swipe left → Torus with 3D rotating torus
- Swipe right → DNA with scrollable cards
- Pills sync with swipe and vice versa
- Header text changes with crossfade
- Each mode has its own action bar
- Spiral mode works identically to before
- Torus drag rotation doesn't trigger page swipe

- [ ] **Step 4: Commit**

```
feat: wire tri-modal pager in SpiralTab (Torus/Spiral/DNA)
```

---

## Task 7: Add Missing Toroidal Features (Experimental)

**Files:**
- Modify: `neurospiral-integration/SpiralGeometry/Sources/SpiralGeometry/WearableMapping.swift`

- [ ] **Step 1: Extend SleepTrajectoryAnalysis**

Add the 3 missing features from ClaudiaApp's 8-feature set. Currently has: omega1Mean, omega2Mean, stability (via residence). Missing: omega_ratio, theta_dispersion, phi_dispersion, residence_fraction, torus_deviation.

Add to the struct:

```swift
public struct SleepTrajectoryAnalysis: Sendable {
    // ... existing fields ...
    
    // Extended toroidal features (experimental)
    public let omegaRatio: Double           // arctan2(ω₁, ω₂)
    public let thetaDispersion: Double      // angular spread in θ
    public let phiDispersion: Double        // angular spread in φ
    public let residenceFraction: Double    // time at dominant vertex (0-1)
    public let torusDeviation: Double       // mean distance from ideal torus surface
}
```

- [ ] **Step 2: Compute features in analyzeNight()**

Add computation in `WearableTo4DMapper.analyzeNight()`:

```swift
let omegaRatio = atan2(omega1Mean, omega2Mean)

// Circular dispersion = 1 - |mean(e^{iθ})|
let thetaAngles = trajectory.map { atan2($0.y, $0.x) }
let thetaMeanVec = sqrt(
    pow(thetaAngles.map { cos($0) }.reduce(0, +) / Double(n), 2) +
    pow(thetaAngles.map { sin($0) }.reduce(0, +) / Double(n), 2)
)
let thetaDispersion = 1.0 - thetaMeanVec

let phiAngles = trajectory.map { atan2($0.w, $0.z) }
let phiMeanVec = sqrt(
    pow(phiAngles.map { cos($0) }.reduce(0, +) / Double(n), 2) +
    pow(phiAngles.map { sin($0) }.reduce(0, +) / Double(n), 2)
)
let phiDispersion = 1.0 - phiMeanVec

let residenceFraction = residence.dominantFraction

// Torus deviation: mean |r - R√2| where r = √(x²+y²+z²+w²)
let idealR = sqrt(2.0)
let deviations = trajectory.map { p in
    abs(sqrt(p.x*p.x + p.y*p.y + p.z*p.z + p.w*p.w) - idealR)
}
let torusDeviation = deviations.reduce(0, +) / Double(max(1, deviations.count))
```

- [ ] **Step 3: Add DEBUG logging**

```swift
#if DEBUG
print("[NeuroSpiral] 8 features: ω₁=\(omega1Mean) ω₂=\(omega2Mean) ratio=\(omegaRatio) θ-disp=\(thetaDispersion) φ-disp=\(phiDispersion) res=\(residenceFraction) stab=\(residence.stabilityScore) dev=\(torusDeviation)")
#endif
```

- [ ] **Step 4: Build to verify**

- [ ] **Step 5: Commit**

```
feat: add 5 missing toroidal features to SleepTrajectoryAnalysis (experimental)
```

---

## Task 8: Localization (all new keys, 8 languages)

**Files:**
- Modify: `spiral journey project/Localizable.xcstrings`

- [ ] **Step 1: Add all new localization keys**

Batch-add all keys from Tasks 1, 3, and 5. Total ~25 new keys across 8 languages.

Group by feature:
- `mode.*` — header/pills (6 keys)
- `torus.*` — phase labels (3 keys)
- `dna.card.*` — card titles (8 keys)
- `dna.*` — card content placeholders (5 keys)

- [ ] **Step 2: Build to verify no missing keys**

- [ ] **Step 3: Commit**

```
chore: add localization keys for tri-modal viewer (8 languages)
```

---

## Task 9: Polish + Gesture Conflict Resolution

**Files:**
- Modify: `spiral journey project/Views/Tabs/TorusModeView.swift`
- Modify: `spiral journey project/Views/Tabs/SpiralTab.swift`

- [ ] **Step 1: Test and fix gesture conflicts**

In simulator, verify:
- Torus drag (minimumDistance: 15) doesn't trigger pager swipe
- If it does: increase minimumDistance or add `.simultaneousGesture` with priority
- DNA vertical scroll doesn't trigger pager swipe (should work by default — orthogonal)
- Spiral pinch zoom doesn't trigger pager swipe

- [ ] **Step 2: Adjust transition animation**

If `TabView(.page)` default animation is too slow/fast, wrap in:
```swift
.animation(.easeInOut(duration: 0.25), value: selectedMode)
```

- [ ] **Step 3: Test transparent background**

Verify torus SceneKit background is truly transparent on device. If `UIColor.clear` doesn't work:
```swift
scene.background.contents = UIColor(white: 0, alpha: 0)
```

- [ ] **Step 4: Final build + visual inspection**

Run on simulator, verify all 3 modes, transitions, action bars, headers.

- [ ] **Step 5: Commit**

```
fix: polish tri-modal gesture handling and transitions
```

---

## Execution Order

```
Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6 → Task 7 → Task 8 → Task 9
  ↓         ↓        ↓        ↓        ↓        ↓        ↓        ↓        ↓
 pills    scene    torus   extract   cards    pager   features  i18n    polish
 header   iPhone   view    spiral    DNA      wire    8-feat
```

Tasks 1-3 are independent and can be parallelized.
Task 4 (extract Spiral) is critical path — must complete before Task 6.
Task 5 (DNA cards) can parallelize with Task 4.
Task 6 (pager wiring) depends on Tasks 1-5.
Tasks 7-9 can be done after Task 6.
