import SwiftUI
import SpiralKit

/// Compact 7-day spiral rendered on a watchOS Canvas.
struct WatchSpiralView: View {

    @Environment(WatchStore.self) private var store

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let records = store.recentRecords
                guard !records.isEmpty else {
                    // Empty state label
                    let text = context.resolve(Text("No data")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(hex: "#555566")))
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    return
                }

                let geometry = SpiralGeometry(
                    totalDays: max(records.count, 1),
                    width: size.width,
                    height: size.height,
                    startRadius: 12,
                    spiralType: .archimedean
                )

                // Draw concentric day rings
                for ring in geometry.dayRings() {
                    var path = Path()
                    path.addEllipse(in: CGRect(
                        x: geometry.cx - ring.r,
                        y: geometry.cy - ring.r,
                        width: ring.r * 2,
                        height: ring.r * 2
                    ))
                    context.stroke(path, with: .color(Color(hex: "#1a1f2d")), lineWidth: ring.isWeekBoundary ? 0.8 : 0.4)
                }

                // Draw spiral backbone
                let steps = geometry.spiralSteps(step: 0.05)
                if steps.count > 1 {
                    var path = Path()
                    path.move(to: CGPoint(x: steps[0].x, y: steps[0].y))
                    for step in steps.dropFirst() {
                        path.addLine(to: CGPoint(x: step.x, y: step.y))
                    }
                    context.stroke(path, with: .color(Color(hex: "#1a1f2d")), lineWidth: 0.6)
                }

                // Draw activity data points
                for (dayIdx, record) in records.enumerated() {
                    let day = dayIdx + 1
                    for ha in record.hourlyActivity {
                        let p = geometry.point(day: day, hour: Double(ha.hour))
                        let activity = ha.activity
                        let color = SpiralColors.viridis(activity)
                        var dot = Path()
                        dot.addEllipse(in: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3))
                        context.fill(dot, with: .color(color.opacity(0.7 + 0.3 * activity)))
                    }
                }
            }
        }
        .background(Color(hex: "#0c0e14"))
        .navigationTitle("Spiral")
    }
}
