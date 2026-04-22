import SceneKit
import WatchKit

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// Builds and manages the 3D torus sleep visualization scene for Apple Watch.
class SleepTorusScene {
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

    /// Called when the sleep stage changes during animation or scrubbing.
    var onStageTransition: ((String) -> Void)?

    /// Stage colors matching the spec.
    private let stageColors: [String: UIColor] = [
        "W":   UIColor(red: 0.50, green: 0.47, blue: 0.87, alpha: 1),
        "N1":  UIColor(red: 0.52, green: 0.72, blue: 0.92, alpha: 1),
        "N2":  UIColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1),
        "N3":  UIColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 1),
        "REM": UIColor(red: 0.83, green: 0.33, blue: 0.49, alpha: 1),
    ]

    init() {
        scene.background.contents = UIColor(red: 0.02, green: 0.02, blue: 0.06, alpha: 1)
        setupCamera()
        setupTorus()
        loadTrajectory(TorusGeometry.mockNight())
        // DON'T start animation here — wait for view to appear.
        // Otherwise timer runs from app launch even when this tab isn't visible.
    }

    // MARK: - Camera

    private func setupCamera() {
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 45
        positionCamera(angle: 0)
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Current camera orbit angles (radians).
    private(set) var cameraAngle: Float = 0
    private(set) var cameraElevation: Float = 0.75

    func positionCamera(angle: Float, elevation: Float? = nil) {
        let distance: Float = 9.5
        cameraAngle = angle
        if let elevation { cameraElevation = elevation }
        let elev = cameraElevation.clamped(to: -1.2...1.4)
        cameraElevation = elev
        cameraNode.position = SCNVector3(
            sin(angle) * distance * cos(elev),
            distance * sin(elev),
            cos(angle) * distance * cos(elev)
        )
        cameraNode.look(at: SCNVector3Zero)
    }

    func rotateCameraTo(angle: Double) {
        let rad = Float(angle * .pi / 180)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.1
        positionCamera(angle: rad)
        SCNTransaction.commit()
    }

    /// Orbit camera by delta angles (from drag gesture).
    func orbitCamera(deltaAngle: Float, deltaElevation: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        positionCamera(angle: cameraAngle + deltaAngle, elevation: cameraElevation + deltaElevation)
        SCNTransaction.commit()
    }

    // MARK: - Torus Wireframe

    private func setupTorus() {
        let torus = SCNTorus(ringRadius: CGFloat(TorusGeometry.R), pipeRadius: CGFloat(TorusGeometry.r))
        let material = SCNMaterial()
        material.fillMode = .lines
        material.diffuse.contents = UIColor(red: 0.20, green: 0.22, blue: 0.35, alpha: 1)
        material.transparency = 0.25
        material.lightingModel = .constant
        material.isDoubleSided = true
        torus.materials = [material]

        let torusNode = SCNNode(geometry: torus)
        // Torus lies in XZ plane by default in SceneKit — correct orientation
        torusParent.addChildNode(torusNode)

        // Solid back-face for depth perception
        let solidTorus = SCNTorus(ringRadius: CGFloat(TorusGeometry.R), pipeRadius: CGFloat(TorusGeometry.r))
        let solidMat = SCNMaterial()
        solidMat.diffuse.contents = UIColor(red: 0.06, green: 0.06, blue: 0.12, alpha: 1)
        solidMat.transparency = 0.5
        solidMat.lightingModel = .phong
        solidMat.cullMode = .front
        solidTorus.materials = [solidMat]
        let solidNode = SCNNode(geometry: solidTorus)
        torusParent.addChildNode(solidNode)

        // Auto-rotation
        let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 60)
        torusParent.runAction(.repeatForever(rotate))

        scene.rootNode.addChildNode(torusParent)

        // Ambient light (base visibility)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 400
        ambient.light?.color = UIColor(red: 0.6, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Directional rim light (edge glow from above-right)
        let rimLight = SCNNode()
        rimLight.light = SCNLight()
        rimLight.light?.type = .directional
        rimLight.light?.intensity = 500
        rimLight.light?.color = UIColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)
        rimLight.eulerAngles = SCNVector3(-0.5, 0.8, 0)
        scene.rootNode.addChildNode(rimLight)
    }

    // MARK: - Trajectory

    func loadTrajectory(_ epochs: [SleepEpoch]) {
        // Remove old trajectory
        trailNode.removeFromParentNode()
        dotNode.removeFromParentNode()
        haloNode.removeFromParentNode()

        let (points, stages) = TorusGeometry.trajectory(from: epochs)
        trajectoryPoints = points
        trajectoryStages = stages
        currentIndex = 0

        // Full trajectory as faint line
        if points.count >= 2 {
            trailNode = createLineNode(points: points, stages: stages, alpha: 0.15)
            torusParent.addChildNode(trailNode)
        }

        // Bright dot
        let dot = SCNSphere(radius: 0.07)
        dot.firstMaterial?.lightingModel = .constant
        dot.firstMaterial?.diffuse.contents = UIColor.white
        dotNode = SCNNode(geometry: dot)
        if let first = points.first { dotNode.position = first }
        torusParent.addChildNode(dotNode)

        // Halo
        let halo = SCNSphere(radius: 0.14)
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.diffuse.contents = UIColor.white.withAlphaComponent(0.2)
        haloNode = SCNNode(geometry: halo)
        if let first = points.first { haloNode.position = first }
        torusParent.addChildNode(haloNode)
    }

    // MARK: - Animation

    func startAnimation() {
        torusParent.isPaused = false  // resume auto-rotation
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.trajectoryPoints.count
            self.updateDotPosition()
        }
    }

    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        torusParent.isPaused = true   // pause auto-rotation too
    }

    var isAnimating: Bool { animationTimer?.isValid ?? false }

    func toggleAnimation() {
        if isAnimating { stopAnimation() } else { startAnimation() }
    }

    /// Scrub to a specific position (0.0 to 1.0).
    func scrubTo(fraction: Double) {
        guard !trajectoryPoints.isEmpty else { return }
        let idx = Int(fraction * Double(trajectoryPoints.count - 1))
        currentIndex = max(0, min(trajectoryPoints.count - 1, idx))
        updateDotPosition()
    }

    /// Current stage name at the dot position.
    var currentStage: String {
        guard !trajectoryStages.isEmpty else { return "" }
        return trajectoryStages[min(currentIndex, trajectoryStages.count - 1)]
    }

    /// Estimated clock hour for the current position.
    var currentHour: String {
        guard !trajectoryPoints.isEmpty else { return "" }
        let fraction = Double(currentIndex) / Double(max(1, trajectoryPoints.count - 1))
        // Assume ~8h night starting at 23:00
        let totalMinutes = fraction * 8 * 60
        let hour = (23 + Int(totalMinutes) / 60) % 24
        let min = Int(totalMinutes) % 60
        return String(format: "%02d:%02d", hour, min)
    }

    private func updateDotPosition() {
        let pt = trajectoryPoints[currentIndex]
        dotNode.position = pt
        haloNode.position = pt

        let stage = trajectoryStages[currentIndex]
        let color = stageColors[stage] ?? .white
        dotNode.geometry?.firstMaterial?.diffuse.contents = color
        haloNode.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.2)

        // Detect stage transition → haptic callback
        if stage != previousStage, previousStage != nil {
            onStageTransition?(stage)
        }
        previousStage = stage
    }

    // MARK: - Line Geometry

    private func createLineNode(points: [SCNVector3], stages: [String], alpha: CGFloat) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }

        // Create colored line segments
        let parent = SCNNode()
        let segmentStep = max(1, points.count / 200)  // limit to ~200 segments for Watch perf

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
            guard length > 0.01 else { continue }

            let cyl = SCNCylinder(radius: 0.025, height: CGFloat(length))
            let color = stageColors[stages[i]] ?? .gray
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.diffuse.contents = color.withAlphaComponent(alpha)
            mat.isDoubleSided = true
            cyl.materials = [mat]

            let node = SCNNode(geometry: cyl)
            node.position = mid

            // Orient cylinder along segment direction
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
