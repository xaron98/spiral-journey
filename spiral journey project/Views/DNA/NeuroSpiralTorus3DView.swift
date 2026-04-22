import SwiftUI
import RealityKit
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import struct SpiralGeometry.VertexResidence
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

/// Interactive 3D Clifford torus view using RealityKit.
///
/// Follows the same CADisplayLink performance pattern as HelixRealityView:
/// transform applied at 60fps directly to the entity, all gesture state
/// is @ObservationIgnored to prevent SwiftUI re-renders during interaction.
@available(iOS 18.0, *)
struct NeuroSpiralTorus3DView: View {
    let analysis: SleepTrajectoryAnalysis

    @State private var manager = NeuroSpiralTorusInteractionManager()

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black.opacity(0.3)

                realityContent
            }
            .frame(height: 350)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .gesture(dragGesture)
            .gesture(pinchGesture)

            // 4D rotation angle slider
            w4DSlider

            // Legend
            torusLegend
        }
        .onDisappear {
            manager.stopDisplayLink()
        }
    }

    private var torusLegend: some View {
        VStack(spacing: 4) {
            HStack(spacing: 14) {
                legendDot(String(localized: "neurospiral.3d.legend.trajectory", defaultValue: "Your sleep journey", bundle: bundle), color: Color(hex: "4a7ab5"))
                legendDot(String(localized: "neurospiral.3d.legend.position", defaultValue: "Most visited", bundle: bundle), color: Color(red: 0.35, green: 1.0, blue: 0.65))
                legendDot(String(localized: "neurospiral.3d.legend.reference", defaultValue: "Reference", bundle: bundle), color: .orange.opacity(0.6))
            }
            Text(String(localized: "neurospiral.3d.legend.explanation", defaultValue: "Each dot is a moment of your night on the sleep surface. Drag to rotate, pinch to zoom.", bundle: bundle))
                .font(.system(size: 9))
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }

    private func legendDot(_ label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10)).foregroundStyle(SpiralColors.muted)
        }
    }

    @Environment(\.languageBundle) private var bundle

    // MARK: - RealityView

    @ViewBuilder
    private var realityContent: some View {
        RealityView { content in
            let root = NeuroSpiralTorusSceneBuilder.build(
                analysis: analysis,
                w4DAngle: manager.w4DAngle
            )

            let anchor = AnchorEntity()
            anchor.addChild(root)

            // Point light for material reflections
            let light = PointLight()
            light.light.intensity = 5000
            light.light.color = .white
            light.position = SIMD3(0, 2, 3)
            anchor.addChild(light)

            content.add(anchor)
            manager.rootEntity = root
            manager.startDisplayLink()
        } update: { _ in
            // Rebuild geometry when w4DAngle changes (slider interaction)
            guard let root = manager.rootEntity else { return }
            let oldChildren = Array(root.children)
            for child in oldChildren { child.removeFromParent() }
            let rebuilt = NeuroSpiralTorusSceneBuilder.build(
                analysis: analysis,
                w4DAngle: manager.w4DAngle
            )
            let newChildren = Array(rebuilt.children)
            for child in newChildren { root.addChild(child) }
        }
    }

    // MARK: - 4D Slider

    private var w4DSlider: some View {
        HStack {
            Text("4D")
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
            Slider(
                value: Binding(
                    get: { Double(manager.w4DAngle) },
                    set: { manager.w4DAngle = Float($0) }
                ),
                in: 0...Double.pi
            )
            .tint(.purple)
            Text(String(format: "%.1f", manager.w4DAngle))
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
        .padding(.horizontal)
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
                manager.zoomScale = max(0.15, min(4.0, manager.baseZoom * Float(value.magnification)))
            }
            .onEnded { _ in
                manager.isInteracting = false
                manager.baseZoom = manager.zoomScale
            }
    }
}
