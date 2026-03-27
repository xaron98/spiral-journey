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
        }
        .onDisappear {
            manager.stopDisplayLink()
        }
    }

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
            // Transform handled by CADisplayLink at 60fps — nothing to do here.
            // This closure only runs when observed state (selectedEpochIndex) changes.
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
                manager.zoomScale = max(0.3, min(3.0, manager.baseZoom * Float(value.magnification)))
            }
            .onEnded { _ in
                manager.isInteracting = false
                manager.baseZoom = manager.zoomScale
            }
    }
}
