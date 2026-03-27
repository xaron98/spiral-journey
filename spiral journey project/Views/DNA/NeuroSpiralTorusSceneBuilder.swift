import Foundation
import UIKit
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

    /// Stereographic projection from the Clifford torus in R4 to R3.
    /// The w4DAngle parameter rotates in the xw-plane before projecting,
    /// revealing different cross-sections of the 4D structure.
    static func project4Dto3D(_ p: SIMD4<Float>, w4DAngle: Float) -> SIMD3<Float> {
        let cosW = cos(w4DAngle), sinW = sin(w4DAngle)
        let rotated = SIMD4<Float>(
            p.x * cosW - p.w * sinW,
            p.y,
            p.z,
            p.x * sinW + p.w * cosW
        )
        let denom: Float = max(0.1, 2.0 - rotated.w * 0.3)
        let scale: Float = 2.0 / denom
        return SIMD3<Float>(rotated.x * scale, rotated.y * scale, rotated.z * scale)
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
        let uSteps = 32
        let vSteps = 16
        let R: Float = sqrt(2.0)  // Clifford torus radius (matches tesseract vertices)

        // Major circles (rings along u parameter)
        for i in 0..<uSteps {
            let u = Float(i) / Float(uSteps) * .pi * 2
            var points: [SIMD3<Float>] = []
            for j in 0...vSteps {
                let v = Float(j) / Float(vSteps) * .pi * 2
                let p4 = SIMD4<Float>(R * cos(u), R * sin(u), R * cos(v), R * sin(v))
                points.append(project4Dto3D(p4, w4DAngle: w4DAngle))
            }
            if let entity = lineEntity(
                points: points,
                color: .gray.withAlphaComponent(0.06),
                radius: 0.003
            ) {
                root.addChild(entity)
            }
        }

        // Minor circles (rings along v parameter) — fewer for visual clarity
        for j in stride(from: 0, to: vSteps, by: 2) {
            let v = Float(j) / Float(vSteps) * .pi * 2
            var points: [SIMD3<Float>] = []
            for i in 0...uSteps {
                let u = Float(i) / Float(uSteps) * .pi * 2
                let p4 = SIMD4<Float>(R * cos(u), R * sin(u), R * cos(v), R * sin(v))
                points.append(project4Dto3D(p4, w4DAngle: w4DAngle))
            }
            if let entity = lineEntity(
                points: points,
                color: .gray.withAlphaComponent(0.04),
                radius: 0.002
            ) {
                root.addChild(entity)
            }
        }
    }

    // MARK: - Trajectory

    /// Stage colors for the four quadrant families.
    /// Deep sleep → purple, Light/transition → blue, Wake → teal, REM → pink.
    private static let stageColors: [UIColor] = [
        UIColor(red: 0.33, green: 0.29, blue: 0.72, alpha: 0.9),
        UIColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 0.9),
        UIColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 0.9),
        UIColor(red: 0.83, green: 0.33, blue: 0.49, alpha: 0.9),
    ]

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
            let colorIdx = abs(Tesseract.discretize(point).index) % stageColors.count

            var material = PhysicallyBasedMaterial()
            material.baseColor = .init(tint: stageColors[colorIdx])
            material.roughness = .init(floatLiteral: 0.3)
            material.metallic = .init(floatLiteral: 0.1)
            material.emissiveColor = .init(color: stageColors[colorIdx].withAlphaComponent(0.3))

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
            let radius: Float = isDominant ? 0.035 : 0.02
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
