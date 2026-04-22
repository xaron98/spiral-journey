import SceneKit

/// Torus surface geometry utilities for sleep visualization.
/// Maps sleep phases to positions on a torus surface.
enum TorusGeometry {

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

    /// Convert torus angles (θ, φ) to 3D position on the surface.
    /// Torus lies in the XZ plane with Y up.
    static func position(theta: Float, phi: Float) -> SCNVector3 {
        let x = (R + r * cos(phi)) * cos(theta)
        let z = (R + r * cos(phi)) * sin(theta)
        let y = -r * sin(phi)  // negated so deep sleep goes UP (visible from above)
        return SCNVector3(x, y, z)
    }

    /// Generate trajectory points from sleep epochs.
    /// Returns (points, stage per point).
    static func trajectory(
        from epochs: [SleepEpoch],
        numPoints: Int = 960,
        turns: Float = 4.5
    ) -> ([SCNVector3], [String]) {
        guard let first = epochs.first, let last = epochs.last else { return ([], []) }
        let totalDuration = last.end.timeIntervalSince(first.start)
        guard totalDuration > 0 else { return ([], []) }

        var points: [SCNVector3] = []
        var stages: [String] = []
        var currentPhi: Float = phiMap[epochs[0].stage] ?? 0.3

        // Maximum phi change per point — limits speed along the tube surface.
        // At 960 points, this allows a full Wake→N3 transition in ~40 points (~2% of night).
        let maxPhiStep: Float = 0.12

        for i in 0..<numPoints {
            let t = Float(i) / Float(numPoints)

            let currentTime = first.start.addingTimeInterval(Double(t) * totalDuration)
            let epoch = epochs.last(where: { $0.start <= currentTime }) ?? epochs[0]

            let theta = t * 2 * .pi * turns

            // Target phi for this stage + organic noise
            let phiTarget = (phiMap[epoch.stage] ?? 0.5 * 2 * .pi)
                + sin(Float(i) * 0.3) * 0.08
                + sin(Float(i) * 0.7) * 0.05

            // Move toward target at limited speed — never teleport
            let delta = phiTarget - currentPhi
            if abs(delta) > maxPhiStep {
                currentPhi += (delta > 0 ? maxPhiStep : -maxPhiStep)
            } else {
                currentPhi = phiTarget
            }

            points.append(position(theta: theta, phi: currentPhi))
            stages.append(epoch.stage)
        }

        return (points, stages)
    }

    /// Mock night data for testing.
    static func mockNight() -> [SleepEpoch] {
        let stages: [(String, Int)] = [
            ("W", 20), ("N1", 15), ("N2", 60), ("N3", 40), ("REM", 15),
            ("N2", 50), ("N3", 30), ("REM", 25), ("N2", 40), ("REM", 35),
            ("N1", 15), ("REM", 40), ("N1", 10), ("W", 10),
        ]
        var epochs: [SleepEpoch] = []
        var time = Calendar.current.date(bySettingHour: 23, minute: 0, second: 0, of: Date())
            ?? Date()
        for (stage, minutes) in stages {
            let end = time.addingTimeInterval(Double(minutes) * 60)
            epochs.append(SleepEpoch(start: time, end: end, stage: stage))
            time = end
        }
        return epochs
    }
}

/// A single sleep epoch with stage label and time range.
struct SleepEpoch {
    let start: Date
    let end: Date
    let stage: String  // "W", "N1", "N2", "N3", "REM"
}
