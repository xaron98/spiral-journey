import SwiftUI
import SceneKit
import struct SpiralGeometry.SleepTrajectoryAnalysis

#if os(macOS)
typealias SCNPlatformColor = NSColor
#else
typealias SCNPlatformColor = UIColor
#endif

// MARK: - SceneKit Torus Scene

/// Builds and manages the 3D torus visualization using SceneKit.
/// Adapted from the Watch implementation but uses 4D trajectory data from SleepTrajectoryAnalysis.
final class NeuroSpiralSceneKitScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private var torusParent = SCNNode()
    private var dotNode = SCNNode()
    private var haloNode = SCNNode()
    private var trailNode = SCNNode()
    private(set) var trajectoryPoints: [SCNVector3] = []
    private(set) var trajectoryColors: [SCNPlatformColor] = []
    private(set) var currentIndex = 0
    private var animationTimer: Timer?

    /// Torus radii — larger than Watch for iPhone display.
    private let R: Float = 2.2
    private let r: Float = 0.7

    /// Color from phi angle on the tube cross-section.
    /// Matches the Watch phiMap zones: W=0.05, N2=0.55, REM=0.62, N3=0.85 (×2π).
    private func colorForPhi(_ phi: Float) -> SCNPlatformColor {
        // Normalize phi to [0, 1] fraction of one turn
        let norm = (phi / (2 * .pi)).truncatingRemainder(dividingBy: 1.0)
        let t = norm < 0 ? norm + 1 : norm
        // Wake at top (t≈0.05) → Light (t≈0.25-0.55) → REM (t≈0.62) → Deep (t≈0.85)
        if t < 0.15 {
            // Wake — gold
            return SCNPlatformColor(red: 0.85, green: 0.72, blue: 0.30, alpha: 1)
        } else if t < 0.45 {
            // Light sleep — teal
            return SCNPlatformColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1)
        } else if t < 0.58 {
            // Core sleep — blue-teal
            return SCNPlatformColor(red: 0.36, green: 0.65, blue: 0.87, alpha: 1)
        } else if t < 0.72 {
            // REM zone — violet
            return SCNPlatformColor(red: 0.68, green: 0.33, blue: 0.82, alpha: 1)
        } else {
            // N3 deep — deep blue
            return SCNPlatformColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 1)
        }
    }

    /// Convert torus angles (θ, φ) to 3D position on the surface.
    private func torusPosition(theta: Float, phi: Float) -> SCNVector3 {
        let x = (R + r * cos(phi)) * cos(theta)
        let z = (R + r * cos(phi)) * sin(theta)
        let y = -r * sin(phi)
        return SCNVector3(x, y, z)
    }

    // MARK: - Init

    init(analysis: SleepTrajectoryAnalysis? = nil, animated: Bool = false) {
        scene.background.contents = SCNPlatformColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)
        setupCamera()
        setupTorus()
        if let analysis {
            loadFromAnalysis(analysis)
        }
        if animated {
            startAnimation()
        }
    }

    // MARK: - Camera

    private(set) var cameraAngle: Float = 0.3
    private(set) var cameraElevation: Float = 0.6
    private var cameraDistance: Float = 7.0

    private func setupCamera() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 50
        positionCamera()
        scene.rootNode.addChildNode(cameraNode)
    }

    private func positionCamera() {
        let elev = max(-1.2, min(1.4, cameraElevation))
        cameraElevation = elev
        cameraNode.position = SCNVector3(
            sin(cameraAngle) * cameraDistance * cos(elev),
            cameraDistance * sin(elev),
            cos(cameraAngle) * cameraDistance * cos(elev)
        )
        cameraNode.look(at: SCNVector3Zero)
    }

    func orbitCamera(deltaAngle: Float, deltaElevation: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.03
        cameraAngle += deltaAngle
        cameraElevation += deltaElevation
        positionCamera()
        SCNTransaction.commit()
    }

    func zoomCamera(scale: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        cameraDistance = max(3.5, min(14, cameraDistance / scale))
        positionCamera()
        SCNTransaction.commit()
    }

    // MARK: - Torus Wireframe

    private func setupTorus() {
        let torus = SCNTorus(ringRadius: CGFloat(R), pipeRadius: CGFloat(r))
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = SCNPlatformColor(red: 0.20, green: 0.22, blue: 0.35, alpha: 1)
        material.transparency = 0.25
        material.lightingModel = .constant
        material.isDoubleSided = true
        torus.materials = [material]
        torusParent.addChildNode(SCNNode(geometry: torus))

        // Solid back-face for depth
        let solidTorus = SCNTorus(ringRadius: CGFloat(R), pipeRadius: CGFloat(r))
        let solidMat = SCNMaterial()
        solidMat.diffuse.contents = SCNPlatformColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1)
        solidMat.transparency = 0.5
        solidMat.lightingModel = .phong
        solidMat.cullMode = .front
        solidTorus.materials = [solidMat]
        torusParent.addChildNode(SCNNode(geometry: solidTorus))

        // Slow auto-rotation
        let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)
        torusParent.runAction(.repeatForever(rotate))

        scene.rootNode.addChildNode(torusParent)

        // Lights
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = SCNPlatformColor(red: 0.6, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.intensity = 600
        rimLight.light?.color = SCNPlatformColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)
        rimLight.eulerAngles = SCNVector3(-0.5, 0.8, 0)
        scene.rootNode.addChildNode(rimLight)
    }

    // MARK: - Load from Analysis

    /// Compute sleep depth [0, 1] from a 4D Clifford torus point.
    ///
    /// The 4D coordinates are: (HRV_z, stillness, HR_slowing, circadian).
    /// Deep sleep → high HRV, high stillness, slow HR, night → all positive except circadian.
    /// Wake → low HRV, low stillness, fast HR, day → all negative except circadian.
    ///
    /// Depth = mean of the first 3 components (parasympathetic indicators),
    /// normalized from [-√2, √2] to [0, 1].
    private func sleepDepth(of p4: SIMD4<Double>) -> Float {
        // x=HRV, y=stillness, z=HR_slowing → higher = deeper sleep
        // w=circadian → negative at night, positive at day (don't use for depth)
        let depthSignal = (p4.x + p4.y + p4.z) / 3.0
        // Points are on Clifford torus of radius √2, so components ∈ [-√2, √2]
        let normalized = (depthSignal + sqrt(2.0)) / (2.0 * sqrt(2.0))
        return Float(max(0, min(1, normalized)))
    }

    func loadFromAnalysis(_ analysis: SleepTrajectoryAnalysis) {
        trailNode.removeFromParentNode()
        dotNode.removeFromParentNode()
        haloNode.removeFromParentNode()

        let trajectory = analysis.trajectory
        guard !trajectory.isEmpty else { return }

        // Map each 4D point to a sleep depth [0, 1] → phi on tube cross-section.
        // depth 0 (wake) → phi ≈ 0 (top of tube)
        // depth 1 (deep) → phi ≈ 0.85 × 2π (bottom of tube)
        // This matches the Watch's phiMap: W=0.05, N2=0.55, N3=0.85
        let rawPhis: [Float] = trajectory.map { p4 in
            let depth = sleepDepth(of: p4)
            return depth * 0.85 * 2 * .pi
        }

        // Generate smooth trajectory: linear theta (4.5 turns), smoothed phi
        let numPoints = max(trajectory.count, 960)
        let turns: Float = 4.5
        let maxPhiStep: Float = 0.12

        var points: [SCNVector3] = []
        var colors: [SCNPlatformColor] = []
        var currentPhi: Float = rawPhis[0]

        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints)

            // Theta: linear time progression wrapping around the torus
            let theta = t * 2 * .pi * turns

            // Target phi: sample from depth data + organic noise
            let srcIdx = min(Int(t * Float(rawPhis.count - 1)), rawPhis.count - 1)
            let phiTarget = rawPhis[srcIdx]
                + sin(Float(i) * 0.3) * 0.08
                + sin(Float(i) * 0.7) * 0.05

            // Smooth phi transition — never teleport (same as Watch)
            let delta = phiTarget - currentPhi
            if abs(delta) > maxPhiStep {
                currentPhi += (delta > 0 ? maxPhiStep : -maxPhiStep)
            } else {
                currentPhi = phiTarget
            }

            let pt = torusPosition(theta: theta, phi: currentPhi)
            points.append(pt)
            colors.append(colorForPhi(currentPhi))
        }

        trajectoryPoints = points
        trajectoryColors = colors
        currentIndex = 0

        // Full trajectory as faint colored line
        if points.count >= 2 {
            trailNode = createLineNode(points: points, colors: colors, alpha: 0.2)
            torusParent.addChildNode(trailNode)
        }

        // Bright dot
        let dot = SCNSphere(radius: 0.08)
        dot.firstMaterial?.lightingModel = .constant
        dot.firstMaterial?.diffuse.contents = SCNPlatformColor.white
        dotNode = SCNNode(geometry: dot)
        if let first = points.first { dotNode.position = first }
        torusParent.addChildNode(dotNode)

        // Halo glow
        let halo = SCNSphere(radius: 0.16)
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.diffuse.contents = SCNPlatformColor.white.withAlphaComponent(0.15)
        haloNode = SCNNode(geometry: halo)
        if let first = points.first { haloNode.position = first }
        torusParent.addChildNode(haloNode)
    }

    // MARK: - Animation

    func startAnimation() {
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.trajectoryPoints.count
            self.updateDotPosition()
        }
        // Resume the SCNAction rotation on the torus parent. Without this
        // the donut keeps spinning offscreen even after stopAnimation().
        torusParent.isPaused = false
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        // Pause the SCNAction rotation as well — not just the Timer-driven
        // trajectory scrubber. Prevents CPU drain when the view is not
        // visible (e.g. inside a dismissed sheet or offscreen pager child).
        torusParent.isPaused = true
    }

    var isAnimating: Bool { animationTimer?.isValid ?? false }

    func scrubTo(fraction: Double) {
        guard !trajectoryPoints.isEmpty else { return }
        let idx = Int(fraction * Double(trajectoryPoints.count - 1))
        currentIndex = max(0, min(trajectoryPoints.count - 1, idx))
        updateDotPosition()
    }

    /// Set visible count for trajectory animation (progressive reveal).
    func setVisibleCount(_ count: Int) {
        guard !trajectoryPoints.isEmpty else { return }
        currentIndex = max(0, min(trajectoryPoints.count - 1, count))
        updateDotPosition()
    }

    private func updateDotPosition() {
        let pt = trajectoryPoints[currentIndex]
        dotNode.position = pt
        haloNode.position = pt
        let color = trajectoryColors[currentIndex]
        dotNode.geometry?.firstMaterial?.diffuse.contents = color
        haloNode.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.15)
    }

    // MARK: - Line Geometry

    private func createLineNode(points: [SCNVector3], colors: [SCNPlatformColor], alpha: CGFloat) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        let parent = SCNNode()
        // iPhone can handle more segments than Watch
        let segmentStep = max(1, points.count / 500)

        for i in stride(from: segmentStep, to: points.count, by: segmentStep) {
            let prev = points[i - segmentStep]
            let curr = points[i]
            let mid = SCNVector3(
                (prev.x + curr.x) / 2,
                (prev.y + curr.y) / 2,
                (prev.z + curr.z) / 2
            )
            let dx = curr.x - prev.x
            let dy = curr.y - prev.y
            let dz = curr.z - prev.z
            let length = sqrt(dx * dx + dy * dy + dz * dz)
            guard length > 0.005 else { continue }

            let cyl = SCNCylinder(radius: 0.03, height: CGFloat(length))
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = colors[i].withAlphaComponent(alpha)
            mat.isDoubleSided = true
            cyl.materials = [mat]

            let node = SCNNode(geometry: cyl)
            node.position = mid

            let dir = SCNVector3(dx / length, dy / length, dz / length)
            let up = SCNVector3(0, 1, 0)
            let dot = up.x * dir.x + up.y * dir.y + up.z * dir.z
            if abs(dot) < 0.999 {
                let cross = SCNVector3(
                    up.y * dir.z - up.z * dir.y,
                    up.z * dir.x - up.x * dir.z,
                    up.x * dir.y - up.y * dir.x
                )
                let crossLen = sqrt(cross.x * cross.x + cross.y * cross.y + cross.z * cross.z)
                let angle = acos(max(-1, min(1, dot)))
                node.rotation = SCNVector4(cross.x / crossLen, cross.y / crossLen, cross.z / crossLen, angle)
            }

            parent.addChildNode(node)
        }

        return parent
    }
}

// MARK: - SwiftUI Wrapper

/// SceneKit-based 3D torus view for iPhone with drag-to-rotate and pinch-to-zoom.
struct NeuroSpiralSceneKitTorusView: View {
    let analysis: SleepTrajectoryAnalysis
    let animated: Bool

    /// For trajectory mode: bind to external visible count.
    var visibleCount: Binding<Int>?

    @State private var scene: NeuroSpiralSceneKitScene?
    @State private var lastDragLocation: CGPoint?

    var body: some View {
        GeometryReader { geo in
            if let scene {
                SceneView(
                    scene: scene.scene,
                    pointOfView: scene.cameraNode,
                    options: []
                )
                .gesture(dragGesture)
                .gesture(pinchGesture)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(
            Color(SCNPlatformColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .onAppear {
            if scene == nil {
                let s = NeuroSpiralSceneKitScene(analysis: analysis, animated: animated)
                scene = s
            }
        }
        .onDisappear {
            scene?.stopAnimation()
        }
        .onChange(of: visibleCount?.wrappedValue) { _, newValue in
            if let count = newValue {
                scene?.setVisibleCount(count)
            }
        }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if let last = lastDragLocation {
                    let dx = Float(value.location.x - last.x)
                    let dy = Float(value.location.y - last.y)
                    scene?.orbitCamera(deltaAngle: dx * 0.008, deltaElevation: -dy * 0.006)
                }
                lastDragLocation = value.location
            }
            .onEnded { _ in
                lastDragLocation = nil
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scene?.zoomCamera(scale: Float(value.magnification))
            }
    }
}
