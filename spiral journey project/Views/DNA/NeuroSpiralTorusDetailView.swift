import SwiftUI
import SpiralKit
import struct SpiralGeometry.SleepTrajectoryAnalysis
import struct SpiralGeometry.TesseractVertex
import struct SpiralGeometry.VertexResidence
import enum SpiralGeometry.Tesseract
import enum SpiralGeometry.CliffordTorus

struct NeuroSpiralTorusDetailView: View {
    let analysis: SleepTrajectoryAnalysis

    @Environment(\.languageBundle) private var bundle
    @State private var show3D = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if show3D {
                    torus3DContent
                } else {
                    torusProjection
                }
                legendRow
                vertexResidenceCard
                oscillatorCard
                transitionCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.torus.title"))
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
    }

    // MARK: - 3D Content

    @ViewBuilder
    private var torus3DContent: some View {
        NeuroSpiralSceneKitTorusView(analysis: analysis, animated: false)
    }

    // MARK: - Torus Projection

    private var torusProjection: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let padX: CGFloat = 20, padY: CGFloat = 20
            let plotW = w - 2 * padX, plotH = h - 2 * padY

            let gridColor = Color.secondary.opacity(0.15)
            for i in 0...4 {
                let x = padX + CGFloat(i) / 4.0 * plotW
                let y = padY + CGFloat(i) / 4.0 * plotH
                context.stroke(Path { p in p.move(to: CGPoint(x: x, y: padY)); p.addLine(to: CGPoint(x: x, y: h - padY)) }, with: .color(gridColor), lineWidth: 0.5)
                context.stroke(Path { p in p.move(to: CGPoint(x: padX, y: y)); p.addLine(to: CGPoint(x: w - padX, y: y)) }, with: .color(gridColor), lineWidth: 0.5)
            }

            for point in analysis.trajectory {
                let (theta, phi) = CliffordTorus.angles(of: point)
                let x = padX + ((theta + .pi) / (2 * .pi)) * plotW
                let y = padY + ((phi + .pi) / (2 * .pi)) * plotH
                context.fill(Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4)), with: .color(.purple.opacity(0.5)))
            }

            for vertex in Tesseract.vertices {
                let (vt, vp) = vertex.torusAngles
                let x = padX + ((vt + .pi) / (2 * .pi)) * plotW
                let y = padY + ((vp + .pi) / (2 * .pi)) * plotH
                let isDominant = vertex.index == analysis.residence.dominantVertex.index
                context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(isDominant ? .green : .orange.opacity(0.6)))
            }
        }
        .frame(height: 280)
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            Label(loc("neurospiral.legend.samples"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.purple)
            Label(loc("neurospiral.legend.vertices"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.orange)
            Label(loc("neurospiral.legend.dominant"), systemImage: "circle.fill").font(.caption2).foregroundStyle(.green)
        }
    }

    // MARK: - Vertex Residence

    private var vertexResidenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("neurospiral.residence.title"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            let sorted = analysis.vertexFractions.sorted { $0.value > $1.value }.prefix(5)
            ForEach(Array(sorted), id: \.key) { vertexIdx, fraction in
                let vertex = Tesseract.vertices[vertexIdx]
                HStack {
                    Text("V\(String(format: "%02d", vertexIdx))")
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Text(formatCode(vertex.code))
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text("\(Int(fraction * 100))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SpiralColors.text)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.purple.opacity(0.3))
                            .frame(width: geo.size.width * fraction)
                    }
                    .frame(width: 60, height: 8)
                }
            }

            HStack {
                Label(loc("neurospiral.stability"), systemImage: "waveform.path")
                    .font(.caption).foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(String(format: "%.0f%%", analysis.residence.stabilityScore * 100))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(analysis.residence.stabilityScore > 0.6 ? SpiralColors.good : .orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Oscillators

    private var oscillatorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loc("neurospiral.oscillators.title"))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            HStack(spacing: 20) {
                oscColumn("ω₁", value: String(format: "%.3f", analysis.omega1Mean), label: loc("neurospiral.process_s"), color: .purple)
                Divider().frame(height: 50)
                oscColumn("ω₂", value: String(format: "%.3f", analysis.omega2Mean), label: loc("neurospiral.process_c"), color: .teal)
                Divider().frame(height: 50)
                oscColumn("ω₁/ω₂", value: analysis.windingRatio.map { String(format: "%.2f", $0) } ?? "—", label: "Winding", color: .orange)
            }

            Text(loc("neurospiral.oscillators.explanation"))
                .font(.caption2).foregroundStyle(SpiralColors.muted)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func oscColumn(_ symbol: String, value: String, label: String, color: Color) -> some View {
        VStack {
            Text(symbol).font(.caption2).foregroundStyle(SpiralColors.muted)
            Text(value).font(.title3.monospaced().weight(.medium)).foregroundStyle(SpiralColors.text)
            Text(label).font(.caption2).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Transitions

    private var transitionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(loc("neurospiral.transitions.title"))
                    .font(.subheadline.weight(.medium)).foregroundStyle(SpiralColors.text)
                Spacer()
                Text(String(format: loc("neurospiral.transitions.count"), analysis.residence.transitionCount))
                    .font(.caption).foregroundStyle(SpiralColors.muted)
            }

            let topEdges = analysis.edgeTraversals.sorted { $0.value > $1.value }.prefix(5)
            if topEdges.isEmpty {
                Text(loc("neurospiral.transitions.none"))
                    .font(.caption).foregroundStyle(SpiralColors.muted)
            } else {
                ForEach(Array(topEdges), id: \.key) { edge, count in
                    HStack {
                        Text(edge).font(.caption.monospaced()).foregroundStyle(SpiralColors.text)
                        Spacer()
                        Text("×\(count)").font(.caption.weight(.medium)).foregroundStyle(SpiralColors.muted)
                    }
                }
            }

            Text(loc("neurospiral.transitions.explanation"))
                .font(.caption2).foregroundStyle(SpiralColors.muted)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "[\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))]"
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
