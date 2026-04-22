import SceneKit

// SCNPlatformColor (UIColor / NSColor) is already defined in NeuroSpiralSceneKitTorusView.swift

// MARK: - SleepEpoch (local, not shared with Watch target)

/// A single sleep epoch with stage label and time range.
struct SleepEpoch: Sendable {
    let start: Date
    let end: Date
    let stage: String  // "W", "N1", "N2", "N3", "REM"
}

// MARK: - Torus Scene

/// SceneKit 3D torus sleep visualization for iPhone.
/// Adapted from the Watch `SleepTorusScene` + `TorusGeometry` with higher resolution,
/// transparent background, finer trails, 60fps animation, and continuous scrub support.
final class TorusSceneiPhone {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private var torusParent = SCNNode()
    private var dotNode = SCNNode()
    private var haloNode = SCNNode()
    private var trailNode = SCNNode()
    private(set) var trajectoryPoints: [SCNVector3] = []
    private(set) var trajectoryStages: [String] = []
    /// Wall-clock timestamp of the first epoch in the loaded trajectory.
    /// Used by `currentHour` to show the real hour at each dot position,
    /// not the hardcoded "night starts at 23:00" assumption.
    private(set) var trajectoryStartDate: Date?
    /// Wall-clock timestamp of the last epoch in the loaded trajectory.
    private(set) var trajectoryEndDate: Date?
    private(set) var currentIndex = 0
    private var animationTimer: Timer?
    private var previousStage: String?

    // Scrub direction: -1 rewind, 0 stopped, +1 forward
    private var scrubDirection: Int = 0
    private var scrubTimer: Timer?

    /// Called when the sleep stage changes during animation or scrubbing.
    var onStageTransition: ((String) -> Void)?

    // MARK: - Torus Geometry Constants

    /// Major radius (center of donut to center of tube).
    static let R: Float = 1.8
    /// Minor radius (radius of tube).
    static let r: Float = 0.6

    /// Phase-to-phi mapping: position around the tube cross-section.
    /// Wake at top, N3 at bottom, REM at ~62% depth.
    static let phiMap: [String: Float] = [
        "W":   0.05 * 2 * .pi,
        "N1":  0.25 * 2 * .pi,
        "N2":  0.55 * 2 * .pi,
        "REM": 0.62 * 2 * .pi,
        "N3":  0.85 * 2 * .pi,
    ]

    /// Stage colors matching the Watch spec.
    private let stageColors: [String: SCNPlatformColor] = [
        "W":   SCNPlatformColor(red: 0.50, green: 0.47, blue: 0.87, alpha: 1),
        "N1":  SCNPlatformColor(red: 0.52, green: 0.72, blue: 0.92, alpha: 1),
        "N2":  SCNPlatformColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 1),
        "N3":  SCNPlatformColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 1),
        "REM": SCNPlatformColor(red: 0.83, green: 0.33, blue: 0.49, alpha: 1),
    ]

    // MARK: - Init

    init() {
        scene.background.contents = SCNPlatformColor.clear
        setupCamera()
        setupTorus()
        setupLighting()
        // DON'T start animation here — wait for view to appear (.task).
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

    /// Orbit camera by delta angles (from drag gesture).
    func orbitCamera(deltaAngle: Float, deltaElevation: Float) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.05
        positionCamera(angle: cameraAngle + deltaAngle, elevation: cameraElevation + deltaElevation)
        SCNTransaction.commit()
    }

    // MARK: - Torus Wireframe

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

        // Solid back-face for depth perception
        let solidTorus = SCNTorus(ringRadius: CGFloat(Self.R), pipeRadius: CGFloat(Self.r))
        let solidMat = SCNMaterial()
        solidMat.diffuse.contents = SCNPlatformColor(red: 0.04, green: 0.04, blue: 0.10, alpha: 1)
        solidMat.transparency = 0.4
        solidMat.lightingModel = .phong
        solidMat.cullMode = .front
        solidTorus.materials = [solidMat]
        torusParent.addChildNode(SCNNode(geometry: solidTorus))

        // Slow auto-rotation: 90s per revolution (slower than Watch's 60s)
        let rotate = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 90)
        torusParent.runAction(.repeatForever(rotate))

        scene.rootNode.addChildNode(torusParent)
    }

    private func setupLighting() {
        // Ambient light (base visibility)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        ambient.light?.color = SCNPlatformColor(red: 0.6, green: 0.6, blue: 0.8, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Directional rim light (edge glow from above-right)
        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 600
        rim.light?.color = SCNPlatformColor(red: 0.4, green: 0.5, blue: 0.9, alpha: 1)
        rim.eulerAngles = SCNVector3(-0.5, 0.8, 0)
        scene.rootNode.addChildNode(rim)
    }

    // MARK: - Torus Geometry

    /// Convert torus angles (theta, phi) to 3D position on the surface.
    /// Torus lies in the XZ plane with Y up.
    static func position(theta: Float, phi: Float) -> SCNVector3 {
        let x = (R + r * cos(phi)) * cos(theta)
        let y = r * sin(phi)
        let z = (R + r * cos(phi)) * sin(theta)
        return SCNVector3(x, y, z)
    }

    // MARK: - Trajectory

    /// Load sleep epochs and build the 3D trajectory trail + dot + halo.
    func loadTrajectory(_ epochs: [SleepEpoch]) {
        trailNode.removeFromParentNode()
        dotNode.removeFromParentNode()
        haloNode.removeFromParentNode()

        let (points, stages) = Self.buildTrajectory(from: epochs)
        trajectoryPoints = points
        trajectoryStages = stages
        trajectoryStartDate = epochs.first?.start
        trajectoryEndDate = epochs.last?.end
        currentIndex = 0

        // Full trajectory as faint line
        if points.count >= 2 {
            trailNode = createTrailNode(points: points, stages: stages, alpha: 0.12)
            torusParent.addChildNode(trailNode)
        }

        // Bright dot
        let dot = SCNSphere(radius: 0.06)
        dot.firstMaterial?.lightingModel = .constant
        dot.firstMaterial?.diffuse.contents = SCNPlatformColor.white
        dotNode = SCNNode(geometry: dot)
        if let first = points.first { dotNode.position = first }
        torusParent.addChildNode(dotNode)

        // Halo glow
        let halo = SCNSphere(radius: 0.12)
        halo.firstMaterial?.lightingModel = .constant
        halo.firstMaterial?.diffuse.contents = SCNPlatformColor.white.withAlphaComponent(0.15)
        haloNode = SCNNode(geometry: halo)
        if let first = points.first { haloNode.position = first }
        torusParent.addChildNode(haloNode)
    }

    /// Generate trajectory points from sleep epochs.
    /// Returns (points, stage per point). No force unwraps.
    static func buildTrajectory(
        from epochs: [SleepEpoch],
        numPoints: Int = 960,
        turns: Float = 4.5
    ) -> ([SCNVector3], [String]) {
        guard let firstEpoch = epochs.first, let lastEpoch = epochs.last else { return ([], []) }
        let totalDuration = lastEpoch.end.timeIntervalSince(firstEpoch.start)
        guard totalDuration > 0 else { return ([], []) }

        var points: [SCNVector3] = []
        var stages: [String] = []
        let maxPhiStep: Float = 0.12
        var prevPhi: Float = phiMap[firstEpoch.stage] ?? 0

        for i in 0..<numPoints {
            let frac = Float(i) / Float(max(1, numPoints - 1))
            let time = firstEpoch.start.addingTimeInterval(Double(frac) * totalDuration)

            // Find current epoch
            let epoch = epochs.last(where: { $0.start <= time }) ?? firstEpoch
            let targetPhi = phiMap[epoch.stage] ?? prevPhi

            // Smooth phi transition — never teleport
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

    /// Whether the dot animation timer is running.
    var isAnimating: Bool { animationTimer?.isValid ?? false }

    /// Start 60fps dot animation along the trajectory.
    func startAnimation() {
        torusParent.isPaused = false // resume auto-rotation
        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            self.currentIndex = (self.currentIndex + 1) % self.trajectoryPoints.count
            self.updateDotPosition()
        }
    }

    /// Stop dot animation and pause auto-rotation.
    func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
        torusParent.isPaused = true
    }

    // MARK: - Scrub (Rewind / Forward)

    /// Start continuous scrub in given direction (-1 rewind, +1 forward).
    /// Called on button press; runs at 60fps while held.
    func startScrub(direction: Int) {
        scrubDirection = direction
        scrubTimer?.invalidate()
        scrubTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, !self.trajectoryPoints.isEmpty else { return }
            let step = self.scrubDirection * 2  // 2 points per frame for visible movement
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

    /// Current stage name at the dot position.
    var currentStage: String {
        guard !trajectoryStages.isEmpty else { return "" }
        return trajectoryStages[min(currentIndex, trajectoryStages.count - 1)]
    }

    /// Real clock hour for the current position, computed by
    /// interpolating between the trajectory's actual start and end
    /// timestamps. Falls back to a 23:00-anchored 8h night only when
    /// no date range was loaded (e.g. mock data).
    var currentHour: String {
        guard !trajectoryPoints.isEmpty else { return "" }
        let fraction = Double(currentIndex) / Double(max(1, trajectoryPoints.count - 1))
        if let start = trajectoryStartDate, let end = trajectoryEndDate {
            let total = end.timeIntervalSince(start)
            let date = start.addingTimeInterval(fraction * total)
            let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
        }
        // Fallback when we don't have real timestamps (mock trajectory).
        let totalMinutes = fraction * 8 * 60
        let hour = (23 + Int(totalMinutes) / 60) % 24
        let minute = Int(totalMinutes) % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    // MARK: - Dot Update

    private func updateDotPosition() {
        guard currentIndex < trajectoryPoints.count,
              currentIndex < trajectoryStages.count else { return }
        let pt = trajectoryPoints[currentIndex]
        dotNode.position = pt
        haloNode.position = pt

        let stage = trajectoryStages[currentIndex]
        let color = stageColors[stage] ?? SCNPlatformColor.white
        dotNode.geometry?.firstMaterial?.diffuse.contents = color
        haloNode.geometry?.firstMaterial?.diffuse.contents = color.withAlphaComponent(0.15)

        // Detect stage transition -> callback
        if stage != previousStage, previousStage != nil {
            onStageTransition?(stage)
        }
        previousStage = stage
    }

    // MARK: - Trail Line Geometry

    private func createTrailNode(points: [SCNVector3], stages: [String], alpha: CGFloat) -> SCNNode {
        guard points.count >= 2 else { return SCNNode() }
        let parent = SCNNode()
        // ~400 segments for iPhone (Watch uses ~200)
        let segStep = max(1, points.count / 400)

        for i in stride(from: segStep, to: points.count, by: segStep) {
            let prev = points[i - segStep]
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

            // Finer cylinders than Watch (0.018 vs 0.025)
            let cyl = SCNCylinder(radius: 0.018, height: CGFloat(length))
            let color = stageColors[stages[i]] ?? SCNPlatformColor.gray
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

// MARK: - Mock Data

extension TorusSceneiPhone {
    /// Mock night data for testing when no real data is available.
    static func mockNight() -> [SleepEpoch] {
        let base = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date()) ?? Date()
        let stages = [
            "W", "N1", "N2", "N3", "N3", "N2", "REM",
            "N2", "N3", "N2", "REM", "N2", "N3", "N2",
            "REM", "N1", "W",
        ]
        return stages.enumerated().map { i, stage in
            let start = base.addingTimeInterval(Double(i) * 30 * 60)
            let end = start.addingTimeInterval(30 * 60)
            return SleepEpoch(start: start, end: end, stage: stage)
        }
    }
}
