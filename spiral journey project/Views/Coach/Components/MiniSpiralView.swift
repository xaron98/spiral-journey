import SwiftUI

/// Polar spiral rendered via Canvas. Used by the hero bento, chat avatar,
/// and learn-card thumbnails. NOT a replacement for SpiralView — it's a
/// decorative mini widget with a deterministic point distribution.
///
/// - Parameters:
///   - size: width/height in points (square).
///   - turns: number of full spiral turns (default 5).
///   - quality: 0–1 fraction of points rendered as "good" (purple glow).
///   - dotCount: how many points to scatter along the path.
///   - animate: rotate the whole shape 360° over 60s (loop).
///   - seed: determinism — same seed = same point layout.
struct MiniSpiralView: View {
    var size: CGFloat = 96
    var turns: Int = 5
    var quality: Double = 0.5
    var dotCount: Int = 24
    var animate: Bool = false
    var seed: UInt64 = 42

    @State private var rotation: Angle = .zero

    var body: some View {
        Canvas { ctx, canvasSize in
            let r = canvasSize.width / 2
            let c = CGPoint(x: r, y: r)
            let steps = 200

            // Spiral path (Archimedean, offset -π/2 so it starts at top).
            var path = Path()
            for i in 0...steps {
                let t = (Double(i) / Double(steps)) * Double(turns) * 2 * .pi
                let rr = (Double(i) / Double(steps)) * (Double(r) - 8)
                let x = Double(c.x) + rr * cos(t - .pi / 2)
                let y = Double(c.y) + rr * sin(t - .pi / 2)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(CoachTokens.yellow.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 2.4, lineCap: .round))

            // Deterministic dot layout.
            var rng = SplitMix64(seed: seed)
            for i in 0..<dotCount {
                let base = 20 + Int((Double(i) / Double(dotCount)) * Double(steps - 40))
                let jitter = Int(rng.nextDouble() * 6 - 3)
                let idx = max(0, min(steps, base + jitter))
                let tIdx = (Double(idx) / Double(steps)) * Double(turns) * 2 * .pi
                let rIdx = (Double(idx) / Double(steps)) * (Double(r) - 8)
                let x = Double(c.x) + rIdx * cos(tIdx - .pi / 2)
                let y = Double(c.y) + rIdx * sin(tIdx - .pi / 2)
                let good = rng.nextDouble() < quality
                let rect = CGRect(x: x - (good ? 1.8 : 2.2),
                                  y: y - (good ? 1.8 : 2.2),
                                  width: (good ? 3.6 : 4.4),
                                  height: (good ? 3.6 : 4.4))
                if good {
                    // Glow: draw a larger soft circle behind.
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)),
                             with: .color(CoachTokens.purple.opacity(0.25)))
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(CoachTokens.purple.opacity(0.95)))
                } else {
                    ctx.fill(Path(ellipseIn: rect),
                             with: .color(CoachTokens.yellow.opacity(0.4)))
                }
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(rotation)
        .onAppear {
            guard animate else { return }
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                rotation = .degrees(360)
            }
        }
    }
}

/// Deterministic PRNG so dot layout is stable across renders.
private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

#Preview("MiniSpiral 55") {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        MiniSpiralView(size: 96, turns: 5, quality: 0.55, dotCount: 26)
    }
    .preferredColorScheme(.dark)
}
