import SwiftUI
import RealityKit
import UIKit
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

/// 3D animated trajectory on the Clifford torus using RealityKit.
/// Points are pre-built invisible and revealed progressively.
@available(iOS 18.0, *)
struct NeuroSpiralTrajectory3DView: View {
    let analysis: SleepTrajectoryAnalysis
    @Binding var visibleCount: Int
    @Binding var isPlaying: Bool
    let speed: Double

    @State private var manager = NeuroSpiralTorusInteractionManager()
    /// Entity references for progressive reveal — NOT observed
    @State private var trajectoryEntities: [Entity] = []
    @State private var headEntity: Entity?

    var body: some View {
        RealityView { content in
            let root = Entity()

            // 1. Wireframe (always visible)
            addWireframe(to: root, w4DAngle: manager.w4DAngle)

            // 2. Tesseract vertices (always visible)
            let dominantIdx = analysis.residence.dominantVertex.index
            addVertices(to: root, dominantIndex: dominantIdx, w4DAngle: manager.w4DAngle)

            // 3. Pre-build ALL trajectory points as invisible
            let stride = max(1, analysis.trajectory.count / 500)
            var entities: [Entity] = []
            for i in Swift.stride(from: 0, to: analysis.trajectory.count, by: stride) {
                let point = analysis.trajectory[i]
                let p4 = SIMD4<Float>(Float(point.x), Float(point.y), Float(point.z), Float(point.w))
                let p3 = NeuroSpiralTorusSceneBuilder.project4Dto3D(p4, w4DAngle: manager.w4DAngle)

                let sphere = MeshResource.generateSphere(radius: 0.012)
                let vertex = Tesseract.discretize(point)
                let color = stageColor(for: vertex.index)
                var mat = PhysicallyBasedMaterial()
                mat.baseColor = .init(tint: color)
                mat.roughness = .init(floatLiteral: 0.3)
                mat.metallic = .init(floatLiteral: 0.1)
                mat.emissiveColor = .init(color: color.withAlphaComponent(0.3))

                let entity = ModelEntity(mesh: sphere, materials: [mat])
                entity.position = p3
                entity.isEnabled = false
                root.addChild(entity)
                entities.append(entity)
            }
            trajectoryEntities = entities

            // 4. Head marker (glowing, always hidden initially)
            let headSphere = MeshResource.generateSphere(radius: 0.035)
            var headMat = PhysicallyBasedMaterial()
            headMat.baseColor = .init(tint: .white)
            headMat.emissiveColor = .init(color: UIColor(white: 0.9, alpha: 1))
            headMat.emissiveIntensity = 2.5
            let head = ModelEntity(mesh: headSphere, materials: [headMat])
            head.isEnabled = false
            root.addChild(head)
            headEntity = head

            // 5. Lighting
            let anchor = AnchorEntity()
            anchor.addChild(root)
            let light = PointLight()
            light.light.intensity = 5000
            light.light.color = .white
            light.position = SIMD3(0, 2, 3)
            anchor.addChild(light)

            content.add(anchor)
            manager.rootEntity = root
            manager.startDisplayLink()
        } update: { _ in
            // Progressive reveal — driven by parent's visibleCount
            let stride = max(1, analysis.trajectory.count / 500)
            let entityCount = trajectoryEntities.count
            let targetVisible = min(visibleCount / max(stride, 1), entityCount)

            for i in 0..<entityCount {
                trajectoryEntities[i].isEnabled = i < targetVisible
            }

            // Move head to latest visible point
            if targetVisible > 0, let head = headEntity {
                head.isEnabled = true
                head.position = trajectoryEntities[targetVisible - 1].position
            } else {
                headEntity?.isEnabled = false
            }
        }
        .frame(height: 350)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .gesture(dragGesture)
        .gesture(pinchGesture)
        .onDisappear { manager.stopDisplayLink() }
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !manager.isInteracting {
                    manager.isInteracting = true
                    manager.dragStart = value.translation
                    return
                }
                let deltaX = Float(value.translation.width - manager.dragStart.width)
                let deltaY = Float(value.translation.height - manager.dragStart.height)
                manager.applyDrag(translationX: deltaX, translationY: deltaY)
                manager.dragStart = value.translation
            }
            .onEnded { _ in
                manager.isInteracting = false
                manager.dragStart = .zero
            }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !manager.isInteracting {
                    manager.isInteracting = true
                    manager.baseZoom = manager.zoomScale
                }
                manager.zoomScale = max(0.3, min(3.0, manager.baseZoom * Float(value.magnification)))
            }
            .onEnded { _ in
                manager.isInteracting = false
                manager.baseZoom = manager.zoomScale
            }
    }

    // MARK: - Scene Building Helpers

    private func stageColor(for vertexIndex: Int) -> UIColor {
        let colors: [UIColor] = [
            UIColor(red: 0.33, green: 0.29, blue: 0.72, alpha: 0.9),
            UIColor(red: 0.22, green: 0.54, blue: 0.87, alpha: 0.9),
            UIColor(red: 0.36, green: 0.79, blue: 0.65, alpha: 0.9),
            UIColor(red: 0.83, green: 0.33, blue: 0.49, alpha: 0.9),
        ]
        return colors[abs(vertexIndex) % colors.count]
    }

    private func addWireframe(to root: Entity, w4DAngle: Float) {
        let uSteps = 24
        let vSteps = 12
        let R: Float = sqrt(2.0)

        for i in 0..<uSteps {
            let u = Float(i) / Float(uSteps) * .pi * 2
            var points: [SIMD3<Float>] = []
            for j in 0...vSteps {
                let v = Float(j) / Float(vSteps) * .pi * 2
                let p4 = SIMD4<Float>(R * cos(u), R * sin(u), R * cos(v), R * sin(v))
                points.append(NeuroSpiralTorusSceneBuilder.project4Dto3D(p4, w4DAngle: w4DAngle))
            }
            if let entity = tubeEntity(points: points, color: .gray.withAlphaComponent(0.05), radius: 0.002) {
                root.addChild(entity)
            }
        }
    }

    private func addVertices(to root: Entity, dominantIndex: Int, w4DAngle: Float) {
        for vertex in Tesseract.vertices {
            let pos = vertex.position
            let p4 = SIMD4<Float>(Float(pos.x), Float(pos.y), Float(pos.z), Float(pos.w))
            let p3 = NeuroSpiralTorusSceneBuilder.project4Dto3D(p4, w4DAngle: w4DAngle)

            let isDominant = vertex.index == dominantIndex
            let sphere = MeshResource.generateSphere(radius: isDominant ? 0.03 : 0.018)
            var mat = PhysicallyBasedMaterial()
            if isDominant {
                mat.baseColor = .init(tint: UIColor(red: 0.35, green: 1.0, blue: 0.65, alpha: 1))
                mat.emissiveColor = .init(color: UIColor(red: 0.35, green: 1.0, blue: 0.65, alpha: 0.5))
                mat.emissiveIntensity = 1.5
            } else {
                mat.baseColor = .init(tint: UIColor.orange.withAlphaComponent(0.5))
            }
            mat.roughness = .init(floatLiteral: 0.2)
            let entity = ModelEntity(mesh: sphere, materials: [mat])
            entity.position = p3
            root.addChild(entity)
        }
    }

    private func tubeEntity(points: [SIMD3<Float>], color: UIColor, radius: Float) -> Entity? {
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
