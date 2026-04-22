import SwiftUI
import SpiralKit

struct NeuroSpiralHistoryView: View {
    let nights: [NightAnalysis]

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                if nights.count >= 2 {
                    stabilitySparkline
                    windingSparkline
                }
                nightList
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(loc("neurospiral.history.title"))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Stability Sparkline

    private var stabilitySparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("neurospiral.history.stability_trend"))
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Canvas { context, size in
                let w = size.width, h = size.height
                let pad: CGFloat = 4
                let values = nights.map(\.stability)
                guard values.count >= 2 else { return }

                let points: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: pad + CGFloat(i) / CGFloat(values.count - 1) * (w - 2 * pad),
                        y: pad + (1 - v) * (h - 2 * pad)
                    )
                }

                // Threshold line at 60%
                let threshY = pad + (1 - 0.6) * (h - 2 * pad)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: pad, y: threshY)); p.addLine(to: CGPoint(x: w - pad, y: threshY)) },
                    with: .color(.orange.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                var path = Path()
                path.move(to: points[0])
                for pt in points.dropFirst() { path.addLine(to: pt) }
                context.stroke(path, with: .color(SpiralColors.good), lineWidth: 2)

                for pt in points {
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(SpiralColors.good))
                }
            }
            .frame(height: 80)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Winding Sparkline

    private var windingSparkline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ω₁/ω₂")
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.text)

            Canvas { context, size in
                let w = size.width, h = size.height
                let pad: CGFloat = 4
                let values = nights.compactMap(\.windingRatio)
                guard values.count >= 2 else { return }

                let maxVal = max(values.max() ?? 2, 2.0)
                let points: [CGPoint] = values.enumerated().map { i, v in
                    CGPoint(
                        x: pad + CGFloat(i) / CGFloat(values.count - 1) * (w - 2 * pad),
                        y: pad + (1 - v / maxVal) * (h - 2 * pad)
                    )
                }

                var path = Path()
                path.move(to: points[0])
                for pt in points.dropFirst() { path.addLine(to: pt) }
                context.stroke(path, with: .color(.teal), lineWidth: 2)

                for pt in points {
                    context.fill(Path(ellipseIn: CGRect(x: pt.x - 3, y: pt.y - 3, width: 6, height: 6)), with: .color(.teal))
                }
            }
            .frame(height: 60)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Night List

    private var nightList: some View {
        VStack(spacing: 8) {
            ForEach(nights.reversed()) { night in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(night.date, style: .date)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SpiralColors.text)
                        Text(String(format: loc("neurospiral.history.transitions_fmt"), night.transitionCount))
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                    }

                    Spacer()

                    Text(String(format: "%.0f%%", night.stability * 100))
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(night.stability > 0.6 ? SpiralColors.good : .orange)

                    Text("V\(String(format: "%02d", night.dominantVertexIdx))")
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.purple.opacity(0.15), in: Capsule())
                        .foregroundStyle(.purple)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
