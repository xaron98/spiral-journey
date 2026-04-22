import SwiftUI
import SpiralKit

/// Animated placeholder shown while a mode view is preparing its heavy
/// content for the first time (Canvas trees, SceneKit scenes, RealityView).
///
/// Uses `TimelineView(.animation)` so the progress advances from the
/// system's frame clock — it can't be stalled or "flattened" by an
/// ancestor's implicit `.animation(...)` modifier (which is what happened
/// in the earlier withAnimation-based implementation).
///
/// Visual: an Archimedean spiral whose visible fraction oscillates 0 ↔ 1
/// with a smooth ease-in-out curve, growing out from the origin to its
/// full turns and retracting back, with a bright leading-edge dot at the
/// tip.
struct SpiralLoaderView: View {
    var size: CGFloat = 140
    var turns: Double = 4
    var color: Color = SpiralColors.accent
    var lineWidth: CGFloat = 3.2
    /// Full breathe cycle (grow + shrink) in seconds.
    var cycle: Double = 1.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: cycle)) / cycle   // 0..1
            // Triangle wave 0→1→0, then softened with cosine for an
            // ease-in-out feel: matches the intent of the earlier
            // withAnimation(.easeInOut.repeatForever(autoreverses:true)).
            let triangle = phase < 0.5 ? phase * 2 : 2 - phase * 2           // 0..1..0
            let progress = 0.5 - 0.5 * cos(triangle * .pi)                   // smoothed

            canvas(progress: progress)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func canvas(progress: Double) -> some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let center = CGPoint(x: r, y: r)
            let maxRadius = Double(r) - lineWidth
            // Clamp to keep at least one visible segment so the tip dot
            // is always drawn.
            let frac = max(0.04, min(progress, 1.0))
            let steps = max(12, Int(220 * frac))

            var path = Path()
            for i in 0...steps {
                let f = Double(i) / Double(steps)
                let t = f * frac * turns * 2 * .pi
                let rr = f * frac * maxRadius
                let x = Double(center.x) + rr * cos(t - .pi / 2)
                let y = Double(center.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(
                path,
                with: .color(color.opacity(0.9)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

            // Leading-edge tip with glow.
            let tipT = frac * turns * 2 * .pi
            let tipR = frac * maxRadius
            let tipX = Double(center.x) + tipR * cos(tipT - .pi / 2)
            let tipY = Double(center.y) + tipR * sin(tipT - .pi / 2)
            let dotRect = CGRect(x: tipX - 4, y: tipY - 4, width: 8, height: 8)
            ctx.fill(Path(ellipseIn: dotRect.insetBy(dx: -3, dy: -3)),
                     with: .color(color.opacity(0.3)))
            ctx.fill(Path(ellipseIn: dotRect), with: .color(color))
        }
    }
}
