import SwiftUI

/// Polar spiral as a single stroked path. No dots. Used for dock icon,
/// chat avatar, and learn-card thumbnails.
struct SparkSpiralView: View {
    var size: CGFloat = 22
    var turns: Int = 3
    var color: Color = CoachTokens.purple
    var lineWidth: CGFloat = 1.6

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let c = CGPoint(x: r, y: r)
            var path = Path()
            let steps = 160
            for i in 0...steps {
                let t = (Double(i) / Double(steps)) * Double(turns) * 2 * .pi
                let rr = (Double(i) / Double(steps)) * (Double(r) - 4)
                let x = Double(c.x) + rr * cos(t - .pi / 2)
                let y = Double(c.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        SparkSpiralView(size: 64, turns: 4, color: CoachTokens.purple)
    }
    .preferredColorScheme(.dark)
}
