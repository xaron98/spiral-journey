import SwiftUI
import SpiralKit

/// Polar heatmap of sector quality: reveals which hours of the day
/// are most predictable in the user's routine.
///
/// 24 angular sectors colored by consistency (viridis scale).
/// Includes a summary of the 3 most/least consistent hours.
struct SectorQualityHeatmapView: View {

    let records: [SleepRecord]

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "analysis.charts.sectorQuality", bundle: bundle))

            Text(String(localized: "analysis.charts.sectorQuality.desc", bundle: bundle))
                .font(.system(size: 10))
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)

            if records.count < 3 {
                Text(String(localized: "analysis.charts.needMoreData", bundle: bundle))
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
            } else {
                let sectors = SpiralDistance.sectorQualityHeatmap(records, numSectors: 24)
                polarChart(sectors: sectors)
                summaryText(sectors: sectors)
                viridisLegend
            }
        }
        .panelStyle()
    }

    // MARK: - Polar Chart

    private func polarChart(sectors: [SpiralDistance.SectorResult]) -> some View {
        let size: CGFloat = 180
        let cx = size / 2
        let cy = size / 2
        let outerR = size / 2 - 16
        let innerR: CGFloat = 20

        return Canvas { ctx, _ in
            for sector in sectors {
                let startAngle = Angle(degrees: (sector.startHour / 24.0) * 360 - 90)
                let endAngle   = Angle(degrees: (sector.endHour / 24.0) * 360 - 90)

                var path = Path()
                path.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
                            startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.addArc(center: CGPoint(x: cx, y: cy), radius: innerR,
                            startAngle: endAngle, endAngle: startAngle, clockwise: true)
                path.closeSubpath()

                ctx.fill(path, with: .color(SpiralColors.viridis(sector.consistency)))
            }

            // Hour labels
            for h in stride(from: 0, to: 24, by: 3) {
                let angle = (Double(h) / 24.0) * 2 * Double.pi - Double.pi / 2
                let labelR = outerR + 10
                let x = cx + CGFloat(cos(angle)) * labelR
                let y = cy + CGFloat(sin(angle)) * labelR
                ctx.draw(
                    Text(String(format: "%02d", h))
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted),
                    at: CGPoint(x: x, y: y)
                )
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Summary

    private func summaryText(sectors: [SpiralDistance.SectorResult]) -> some View {
        let sorted = sectors.sorted { $0.consistency > $1.consistency }
        let top3 = sorted.prefix(3).map { String(format: "%02d:00", Int($0.startHour)) }
        let bottom3 = sorted.suffix(3).reversed().map { String(format: "%02d:00", Int($0.startHour)) }

        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SpiralColors.good)
                Text(String(format: String(localized: "analysis.charts.sectorQuality.top3", bundle: bundle), top3.joined(separator: ", ")))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
            }
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(SpiralColors.moderate)
                Text(String(format: String(localized: "analysis.charts.sectorQuality.bottom3", bundle: bundle), bottom3.joined(separator: ", ")))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
            }
        }
    }

    // MARK: - Legend

    private var viridisLegend: some View {
        HStack(spacing: 4) {
            Text("0").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted)
            LinearGradient(
                colors: (0...10).map { SpiralColors.viridis(Double($0) / 10.0) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Text("1").font(.system(size: 7, design: .monospaced)).foregroundStyle(SpiralColors.muted)
            Spacer()
            Text(String(localized: "analysis.charts.sectorQuality.legendLabel", bundle: bundle))
                .font(.system(size: 7, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
        }
    }
}
