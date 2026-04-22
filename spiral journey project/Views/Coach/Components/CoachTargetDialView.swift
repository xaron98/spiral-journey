import SwiftUI

/// Large 240pt dial for the Plan screen. Draws full 24-hour clock with
/// ticks, a glowing purple arc for the optimal window, and a pointer
/// dot at the target hour.
struct CoachTargetDialView: View {
    var size: CGFloat = 240
    var windowStart: Double = 1.25
    var windowEnd: Double = 1.75
    var targetHour: Double = 1.5
    var color: Color = CoachTokens.purple

    var body: some View {
        Canvas { ctx, _ in
            let r: CGFloat = 100
            let c = CGPoint(x: size / 2, y: size / 2)

            // Soft radial glow behind.
            let glowRect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: glowRect),
                     with: .radialGradient(
                        Gradient(colors: [.clear, color.opacity(0.2)]),
                        center: c, startRadius: r * 0.6, endRadius: r))

            // Outer hairline.
            ctx.stroke(Path(ellipseIn: glowRect),
                       with: .color(Color.white.opacity(0.06)), lineWidth: 1)

            // Track.
            let trackRect = glowRect.insetBy(dx: 4, dy: 4)
            ctx.stroke(Path(ellipseIn: trackRect),
                       with: .color(Color.white.opacity(0.08)), lineWidth: 6)

            // Optimal window arc.
            let toRad = { (h: Double) -> Double in (h / 24.0) * 2 * .pi - .pi / 2 }
            var arc = Path()
            arc.addArc(center: c, radius: r - 4,
                       startAngle: .radians(toRad(windowStart)),
                       endAngle: .radians(toRad(windowEnd)),
                       clockwise: false)
            ctx.stroke(arc, with: .color(color),
                       style: StrokeStyle(lineWidth: 6, lineCap: .round))

            // Hour ticks.
            for h in 0..<24 {
                let a = toRad(Double(h))
                let isMajor = h % 6 == 0
                let r1 = r - 4
                let r2 = isMajor ? r - 14 : r - 10
                let p1 = CGPoint(x: c.x + r1 * cos(a), y: c.y + r1 * sin(a))
                let p2 = CGPoint(x: c.x + r2 * cos(a), y: c.y + r2 * sin(a))
                var tick = Path()
                tick.move(to: p1)
                tick.addLine(to: p2)
                ctx.stroke(tick,
                           with: .color(isMajor ? Color.white.opacity(0.5) : Color.white.opacity(0.15)),
                           lineWidth: isMajor ? 1.5 : 1)
            }

            // Labels 00 / 06 / 12 / 18.
            for (h, label) in [(0, "00"), (6, "06"), (12, "12"), (18, "18")] {
                let a = toRad(Double(h))
                let lr = r - 24
                let p = CGPoint(x: c.x + lr * cos(a), y: c.y + lr * sin(a))
                ctx.draw(Text(label)
                    .font(CoachTokens.mono(9))
                    .foregroundColor(CoachTokens.textFaint),
                         at: p, anchor: .center)
            }

            // Target pointer.
            let a = toRad(targetHour)
            let p = CGPoint(x: c.x + (r - 4) * cos(a), y: c.y + (r - 4) * sin(a))
            let pointerRect = CGRect(x: p.x - 8, y: p.y - 8, width: 16, height: 16)
            ctx.fill(Path(ellipseIn: pointerRect), with: .color(color))
            ctx.stroke(Path(ellipseIn: pointerRect), with: .color(.white), lineWidth: 2)
        }
        .frame(width: size, height: size)
    }
}
