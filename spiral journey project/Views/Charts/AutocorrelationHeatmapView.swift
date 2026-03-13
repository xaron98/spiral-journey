import SwiftUI
import SpiralKit

/// Heatmap of radial autocorrelation: shows which hours of the day
/// are most stable across different time intervals.
///
/// Grid: 24 hours × N lags. Color: RdBu diverging scale (red = negative,
/// white = zero, blue = positive correlation). White dots mark p < 0.05.
struct AutocorrelationHeatmapView: View {

    let records: [SleepRecord]

    @Environment(\.languageBundle) private var bundle

    private let lags = [1, 2, 7, 14, 28]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "analysis.charts.autocorrelation", bundle: bundle))

            Text(String(localized: "analysis.charts.autocorrelation.desc", bundle: bundle))
                .font(.system(size: 10))
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)

            if records.count < 8 {
                Text(String(localized: "analysis.charts.needMoreData", bundle: bundle))
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                let data = Autocorrelation.computeExtended(records, lags: lags, permutations: 200)
                heatmapCanvas(data: data)
                legendBar
            }
        }
        .panelStyle()
    }

    // MARK: - Canvas

    private func heatmapCanvas(data: [Autocorrelation.SignificantCorrelation]) -> some View {
        let cellW: CGFloat = 12
        let cellH: CGFloat = 20
        let labelW: CGFloat = 30
        let headerH: CGFloat = 16

        let width = labelW + cellW * 24
        let height = headerH + cellH * CGFloat(lags.count)

        return Canvas { ctx, _ in
            // Hour labels (top)
            for h in stride(from: 0, to: 24, by: 3) {
                let x = labelW + CGFloat(h) * cellW
                ctx.draw(
                    Text("\(h)").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted),
                    at: CGPoint(x: x + cellW / 2, y: headerH / 2)
                )
            }

            // Lag labels (left) + cells
            for (li, lag) in lags.enumerated() {
                let y = headerH + CGFloat(li) * cellH

                ctx.draw(
                    Text("\(lag)d").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted),
                    at: CGPoint(x: labelW / 2, y: y + cellH / 2)
                )

                for h in 0..<24 {
                    guard let point = data.first(where: { $0.hour == h && $0.lag == lag }) else { continue }
                    let x = labelW + CGFloat(h) * cellW
                    let rect = CGRect(x: x, y: y, width: cellW, height: cellH)
                    ctx.fill(Path(rect), with: .color(SpiralColors.rdBu(point.correlation)))

                    // Significance dot
                    if point.isSignificant {
                        let dot = Path(ellipseIn: CGRect(
                            x: x + cellW / 2 - 2, y: y + cellH / 2 - 2, width: 4, height: 4))
                        ctx.fill(dot, with: .color(.white.opacity(0.9)))
                    }
                }
            }
        }
        .frame(width: width, height: height)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Legend

    private var legendBar: some View {
        HStack(spacing: 4) {
            Text("-1").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted)
            LinearGradient(
                colors: (0...10).map { SpiralColors.rdBu(Double($0) / 5.0 - 1.0) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text("+1").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted)
            Spacer()
            Circle().fill(.white).frame(width: 5, height: 5)
            Text("p<0.05").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted)
        }
    }
}
