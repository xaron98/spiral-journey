import SwiftUI
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralTrajectoryView: View {
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle
    @State private var visibleCount: Int = 0
    @State private var isPlaying = true
    @State private var speed: Double = 5
    @State private var show3D = false

    private var pointsPerFrame: Int { max(1, Int(speed)) }

    var body: some View {
        VStack(spacing: 16) {
            // Canvas: 2D or 3D
            if show3D {
                torus3DContent
            } else {
                torus2DContent
            }

            // Shared controls
            controlsCard

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.trajectory.title"))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Picker("", selection: $show3D) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "cube").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
        }
        .task { await advanceAnimation() }
    }

    // MARK: - 2D Canvas

    private var torus2DContent: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { _ in
            Canvas { context, size in
                drawTorus(context: context, size: size)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: - 3D RealityKit

    @ViewBuilder
    private var torus3DContent: some View {
        NeuroSpiralSceneKitTorusView(
            analysis: analysis,
            animated: true,
            visibleCount: $visibleCount
        )
    }

    // MARK: - Shared Controls

    private var controlsCard: some View {
        VStack(spacing: 12) {
            HStack {
                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(SpiralColors.accent)
                }
                Button {
                    visibleCount = 0
                    isPlaying = true
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Text("\(visibleCount)/\(analysis.trajectory.count)")
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
            }

            HStack {
                Text("1×").font(.caption2).foregroundStyle(SpiralColors.muted)
                Slider(value: $speed, in: 1...20, step: 1)
                    .tint(SpiralColors.accent)
                Text("20×").font(.caption2).foregroundStyle(SpiralColors.muted)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Animation

    private func advanceAnimation() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            guard isPlaying, visibleCount < analysis.trajectory.count else { continue }
            visibleCount = min(visibleCount + pointsPerFrame, analysis.trajectory.count)
        }
    }

    // MARK: - 2D Drawing

    private func drawTorus(context: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let padX: CGFloat = 20, padY: CGFloat = 20
        let plotW = w - 2 * padX, plotH = h - 2 * padY
        let trajectory = analysis.trajectory

        let gridColor = Color.secondary.opacity(0.12)
        for i in 0...4 {
            let x = padX + CGFloat(i) / 4.0 * plotW
            let y = padY + CGFloat(i) / 4.0 * plotH
            context.stroke(Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) }, with: .color(gridColor), lineWidth: 0.5)
            context.stroke(Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) }, with: .color(gridColor), lineWidth: 0.5)
        }

        for vertex in Tesseract.vertices {
            let (vt, vp) = vertex.torusAngles
            let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
            let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
            let isDominant = vertex.index == analysis.residence.dominantVertex.index
            context.fill(Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)), with: .color(isDominant ? .green : .orange.opacity(0.4)))
        }

        guard visibleCount > 0 else { return }

        let trailStart = max(0, visibleCount - 30)
        let trailSlice = trajectory[trailStart..<visibleCount]

        func toScreen(_ point: SIMD4<Double>) -> CGPoint {
            let (theta, phi) = CliffordTorus.angles(of: point)
            return CGPoint(
                x: padX + ((theta + .pi) / (2 * .pi)) * plotW,
                y: padY + ((phi + .pi) / (2 * .pi)) * plotH
            )
        }

        for i in 0..<trailStart {
            let pt = toScreen(trajectory[i])
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 1.5, y: pt.y - 1.5, width: 3, height: 3)), with: .color(.purple.opacity(0.2)))
        }

        let trailArray = Array(trailSlice)
        if trailArray.count >= 2 {
            for i in 1..<trailArray.count {
                let from = toScreen(trailArray[i - 1])
                let to = toScreen(trailArray[i])
                let opacity = Double(i) / Double(trailArray.count)
                var linePath = Path()
                linePath.move(to: from)
                linePath.addLine(to: to)
                context.stroke(linePath, with: .color(.purple.opacity(opacity * 0.8)), lineWidth: 1.5)
            }
        }

        if let last = trailArray.last {
            let pt = toScreen(last)
            context.fill(Path(ellipseIn: CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)), with: .color(.purple))
            context.stroke(Path(ellipseIn: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(.purple.opacity(0.3)), lineWidth: 2)
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
