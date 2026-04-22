import SwiftUI

/// Small 72-pt dial showing an optimal-window arc against a 24h clock.
/// - windowStart/windowEnd: hours in 0..24 (e.g. 1.25, 1.75).
struct CoachTimeDialView: View {
    var size: CGFloat = 72
    var windowStart: Double = 1.25
    var windowEnd: Double = 1.75
    var color: Color = CoachTokens.purple

    var body: some View {
        Canvas { ctx, _ in
            let r = size / 2
            let c = CGPoint(x: r, y: r)
            let trackRadius = r - 6

            // Track.
            ctx.stroke(
                Path(ellipseIn: CGRect(
                    x: c.x - trackRadius, y: c.y - trackRadius,
                    width: trackRadius * 2, height: trackRadius * 2)),
                with: .color(Color.white.opacity(0.08)),
                lineWidth: 3)

            // Optimal window arc.
            let toRad = { (h: Double) -> Double in (h / 24.0) * 2 * .pi - .pi / 2 }
            let a1 = toRad(windowStart), a2 = toRad(windowEnd)
            var arc = Path()
            arc.addArc(center: c, radius: trackRadius,
                       startAngle: .radians(a1), endAngle: .radians(a2),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round))

            // Quarter hour ticks.
            for h in [0.0, 6.0, 12.0, 18.0] {
                let a = toRad(h)
                let p = CGPoint(x: c.x + (r - 2) * cos(a),
                                y: c.y + (r - 2) * sin(a))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)),
                         with: .color(Color.white.opacity(0.3)))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            Image(systemName: "moon.stars.fill")
                .font(.system(size: 14))
                .foregroundStyle(color)
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        CoachTimeDialView()
    }
    .preferredColorScheme(.dark)
}
