import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import RealityKit
import simd
import struct SpiralGeometry.SleepTrajectoryAnalysis
import struct SpiralGeometry.VertexResidence
import struct SpiralGeometry.TesseractVertex
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

/// Builds the RealityKit entity tree for the Clifford torus visualization:
/// wireframe mesh + sleep trajectory points + tesseract reference vertices.
@available(iOS 18.0, *)
enum NeuroSpiralTorusSceneBuilder {

    // MARK: - 4D → 3D Projection

    /// Major and minor radii for the 3D torus embedding.
    private static let majorRadius: Float = 0.35
    private static let minorRadius: Float = 0.15

    /// Torus embedding: maps Clifford torus angles (θ, φ) to a standard 3D donut.
    ///
    ///   x = (R + r·cos(φ)) · cos(θ)
    ///   y = r · sin(φ)
    ///   z = (R + r·cos(φ)) · sin(θ)
    ///
    /// θ = atan2(y4, x4) — angle in the xy-plane of ℝ⁴
    /// φ = atan2(w4, z4) — angle in the zw-plane of ℝ⁴
    ///
    /// The w4DAngle parameter rotates in the xw-plane before extracting angles,
    /// twisting the pattern on the donut surface.
    static func project4Dto3D(_ p: SIMD4<Float>, w4DAngle: Float) -> SIMD3<Float> {
        // Rotate in xw-plane to reveal different cross-sections
        let cosW = cos(w4DAngle), sinW = sin(w4DAngle)
        let rotated = SIMD4<Float>(
            p.x * cosW - p.w * sinW,
            p.y,
            p.z,
            p.x * sinW + p.w * cosW
        )

        // Extract torus angles from the 4D point
        let theta = atan2(rotated.y, rotated.x) // major angle (around the donut)
        let phi = atan2(rotated.w, rotated.z)     // minor angle (around the tube)

        // Standard 3D torus embedding
        let R = majorRadius
        let r = minorRadius
        let x = (R + r * cos(phi)) * cos(theta)
        let y = r * sin(phi)
        let z = (R + r * cos(phi)) * sin(theta)

        return SIMD3<Float>(x, y, z)
    }

    // MARK: - Build Scene

    /// Build the complete torus scene entity from analysis data.
    static func build(
        analysis: SleepTrajectoryAnalysis,
        w4DAngle: Float
    ) -> Entity {
        let root = Entity()

        // 1. Torus wireframe — semi-transparent reference grid
        addWireframe(to: root, w4DAngle: w4DAngle)

        // 2. Sleep trajectory — colored by discretized vertex quadrant
        addTrajectory(
            to: root,
            trajectory: analysis.trajectory,
            residence: analysis.residence,
            w4DAngle: w4DAngle
        )

        // 3. Tesseract vertices — reference spheres at sign-quadrant centers
        addVertices(
            to: root,
            dominantIndex: analysis.residence.dominantVertex.index,
            w4DAngle: w4DAngle
        )

        return root
    }

    // MARK: - Wireframe

    private static func addWireframe(to root: Entity, w4DAngle: Float) {
        let R: Float = sqrt(2.0)
        let ringPoints = 48  // smooth circles

        // 8 rings around the tube (major circles, fixed u, sweep v)
        for i in 0..<8 {
            let u = Float(i) / 8.0 * .pi * 2
            var points: [SIMD3<Float>] = []
            for j in 0...ringPoints {
                let v = Float(j) / Float(ringPoints) * .pi * 2
                let p4 = SIMD4<Float>(R * cos(u), R * sin(u), R * cos(v), R * sin(v))
                points.append(project4Dto3D(p4, w4DAngle: w4DAngle))
            }
            if let entity = lineEntity(points: points, color: .gray.withAlphaComponent(0.04), radius: 0.001) {
                root.addChild(entity)
            }
        }

        // 4 rings around the donut (minor circles, fixed v, sweep u)
        for j in 0..<4 {
            let v = Float(j) / 4.0 * .pi * 2
            var points: [SIMD3<Float>] = []
            for i in 0...ringPoints {
                let u = Float(i) / Float(ringPoints) * .pi * 2
                let p4 = SIMD4<Float>(R * cos(u), R * sin(u), R * cos(v), R * sin(v))
                points.append(project4Dto3D(p4, w4DAngle: w4DAngle))
            }
            if let entity = lineEntity(points: points, color: .gray.withAlphaComponent(0.03), radius: 0.001) {
                root.addChild(entity)
            }
        }
    }

    // MARK: - Trajectory

    /// Color by geometric depth on the torus (natural 3-state model).
    /// Active pole (W/REM) → teal, Deep pole (NREM) → indigo, gradient between.
    private static func depthColor(for point: SIMD4<Double>) -> UIColor {
        // ω₁ proxy: angular velocity in xy-plane (Process S dimension)
        // Higher absolute angle from positive x-axis = deeper sleep
        let theta = atan2(point.y, point.x)
        let phi = atan2(point.w, point.z)

        // Depth: combine both angles into a 0-1 score
        // Points near (+,+,+,+) are active; points near (-,-,-,-) are deep
        let signSum = (point.x > 0 ? 1.0 : 0.0) + (point.y > 0 ? 1.0 : 0.0)
                    + (point.z > 0 ? 1.0 : 0.0) + (point.w > 0 ? 1.0 : 0.0)
        let depth = 1.0 - signSum / 4.0  // 0 = active pole, 1 = deep pole

        // Continuous gradient: teal (active) → blue → indigo (deep)
        let r = 0.36 - depth * 0.30   // 0.36 → 0.06
        let g = 0.79 - depth * 0.50   // 0.79 → 0.29
        let b = 0.65 + depth * 0.07   // 0.65 → 0.72
        return UIColor(red: r, green: g, blue: b, alpha: 0.9)
    }

    private static func addTrajectory(
        to root: Entity,
        trajectory: [SIMD4<Double>],
        residence: VertexResidence,
        w4DAngle: Float
    ) {
        guard !trajectory.isEmpty else { return }

        // Limit to ~400 points for performance
        let step = max(1, trajectory.count / 400)

        for i in Swift.stride(from: 0, to: trajectory.count, by: step) {
            let point = trajectory[i]
            let p4 = SIMD4<Float>(Float(point.x), Float(point.y), Float(point.z), Float(point.w))
            let p3 = project4Dto3D(p4, w4DAngle: w4DAngle)

            let sphere = MeshResource.generateSphere(radius: 0.012)
            let color = depthColor(for: point)

            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: color)
            material.roughness = .init(floatLiteral: 0.3)
            material.metallic = .init(floatLiteral: 0.1)
            material.emissiveColor = .init(color: color.withAlphaComponent(0.3))

            let entity = ModelEntity(mesh: sphere, materials: [material])
            entity.position = p3
            root.addChild(entity)
        }

        // Current position — larger glowing sphere as "you are here" marker
        if let last = trajectory.last {
            let p4 = SIMD4<Float>(Float(last.x), Float(last.y), Float(last.z), Float(last.w))
            let p3 = project4Dto3D(p4, w4DAngle: w4DAngle)
            let sphere = MeshResource.generateSphere(radius: 0.03)

            var mat = PhysicallyBasedMaterial()
            mat.baseColor = .init(tint: .white)
            mat.emissiveColor = .init(color: UIColor(white: 0.8, alpha: 1))
            mat.emissiveIntensity = 2.0

            let entity = ModelEntity(mesh: sphere, materials: [mat])
            entity.position = p3
            root.addChild(entity)
        }
    }

    // MARK: - Vertices

    private static func addVertices(
        to root: Entity,
        dominantIndex: Int,
        w4DAngle: Float
    ) {
        for vertex in Tesseract.vertices {
            let pos = vertex.position
            let p4 = SIMD4<Float>(Float(pos.x), Float(pos.y), Float(pos.z), Float(pos.w))
            let p3 = project4Dto3D(p4, w4DAngle: w4DAngle)

            let isDominant = vertex.index == dominantIndex
            let radius: Float = isDominant ? 0.02 : 0.008
            let sphere = MeshResource.generateSphere(radius: radius)

            var mat = PhysicallyBasedMaterial()
            if isDominant {
                mat.baseColor = .init(tint: UIColor(red: 0.35, green: 1.0, blue: 0.65, alpha: 1))
                mat.emissiveColor = .init(color: UIColor(red: 0.35, green: 1.0, blue: 0.65, alpha: 0.5))
                mat.emissiveIntensity = 1.5
            } else {
                mat.baseColor = .init(tint: UIColor.orange.withAlphaComponent(0.6))
            }
            mat.roughness = .init(floatLiteral: 0.2)

            let entity = ModelEntity(mesh: sphere, materials: [mat])
            entity.position = p3
            root.addChild(entity)
        }
    }

    // MARK: - Line Helper

    /// Create a tube (sequence of thin cylinders) connecting consecutive points.
    private static func lineEntity(
        points: [SIMD3<Float>],
        color: UIColor,
        radius: Float
    ) -> Entity? {
        guard points.count >= 2 else { return nil }
        let parent = Entity()

        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let mid = (a + b) / 2
            let diff = b - a
            let length = simd_length(diff)
            guard length > 0.001 else { continue }

            let mesh = MeshResource.generateCylinder(height: length, radius: radius)
            var mat = SimpleMaterial()
            mat.color = .init(tint: color)
            let entity = ModelEntity(mesh: mesh, materials: [mat])
            entity.position = mid

            // Orient cylinder from default Y-up to match the segment direction
            let up = SIMD3<Float>(0, 1, 0)
            let dir = simd_normalize(diff)
            if abs(simd_dot(up, dir)) < 0.999 {
                entity.transform.rotation = simd_quatf(from: up, to: dir)
            }
            parent.addChild(entity)
        }

        return parent
    }
}
