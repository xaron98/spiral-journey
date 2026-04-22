import SwiftUI
import SpiralKit

/// Animated placeholder shown while a mode view is preparing its heavy
/// content for the first time (big Canvas trees, RealityView scenes).
///
/// Draws an Archimedean spiral whose visible fraction oscillates smoothly
/// between 0 and 1 with `repeatForever(autoreverses: true)`, so the path
/// grows out from the origin, reaches its full length, and retracts back
/// — matching the visual language of the rest of the app.
struct SpiralLoaderView: View {
    var size: CGFloat = 80
    var turns: Double = 4
    var color: Color = SpiralColors.accent
    var lineWidth: CGFloat = 2.4
    var duration: Double = 1.3

    @State private var progress: Double = 0.02

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let center = CGPoint(x: r, y: r)
            let maxRadius = Double(r) - lineWidth
            // Clamp so the path always has at least one visible segment.
            let frac = max(0.02, min(progress, 1.0))
            let steps = max(6, Int(200 * frac))

            var path = Path()
            for i in 0...steps {
                let t = (Double(i) / Double(steps)) * frac * turns * 2 * .pi
                let rr = (Double(i) / Double(steps)) * frac * maxRadius
                let x = Double(center.x) + rr * cos(t - .pi / 2)
                let y = Double(center.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(
                path,
                with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Leading-edge dot — sits at the current tip of the drawn spiral.
            let tipT = frac * turns * 2 * .pi
            let tipR = frac * maxRadius
            let tipX = Double(center.x) + tipR * cos(tipT - .pi / 2)
            let tipY = Double(center.y) + tipR * sin(tipT - .pi / 2)
            let dotRect = CGRect(x: tipX - 3, y: tipY - 3, width: 6, height: 6)
            ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -2, dy: -2)),
                     with: .color(color.opacity(0.3)))
            ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
        .frame(width: size, height: size)
        .onAppear {
            progress = 0.02
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                progress = 1.0
            }
        }
    }
}
