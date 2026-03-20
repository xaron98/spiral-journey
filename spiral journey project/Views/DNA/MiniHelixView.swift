import SwiftUI

/// Animated double-helix decoration using Canvas + TimelineView.
/// Purple strand (sleep) and orange strand (context) with base-pair connectors.
/// Pauses animation when the app is backgrounded to save battery.
struct MiniHelixView: View {

    var width: CGFloat = 120
    var height: CGFloat = 60

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Colors
    private let strandPurple = Color(hex: "7c3aed")
    private let strandOrange = Color(hex: "f59e0b")
    private let pairColor    = Color.white.opacity(0.15)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: scenePhase != .active)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 0.6
            Canvas { ctx, size in
                drawHelix(ctx: &ctx, size: size, phase: phase)
            }
            .frame(width: width, height: height)
        }
        .allowsHitTesting(false)
    }

    // MARK: - Drawing

    private func drawHelix(ctx: inout GraphicsContext, size: CGSize, phase: Double) {
        let midY   = size.height / 2
        let amp    = size.height * 0.35
        let steps  = 40
        let dx     = size.width / Double(steps)

        // Build strand paths
        var pathA = Path()
        var pathB = Path()
        var pointsA: [CGPoint] = []
        var pointsB: [CGPoint] = []

        for i in 0...steps {
            let x = Double(i) * dx
            let t = Double(i) / Double(steps) * 3.0 * .pi + phase
            let yA = midY + amp * sin(t)
            let yB = midY - amp * sin(t)

            let ptA = CGPoint(x: x, y: yA)
            let ptB = CGPoint(x: x, y: yB)
            pointsA.append(ptA)
            pointsB.append(ptB)

            if i == 0 {
                pathA.move(to: ptA)
                pathB.move(to: ptB)
            } else {
                pathA.addLine(to: ptA)
                pathB.addLine(to: ptB)
            }
        }

        // Draw base-pair connectors every 5 steps
        for i in stride(from: 0, through: steps, by: 5) {
            let a = pointsA[i]
            let b = pointsB[i]
            var line = Path()
            line.move(to: a)
            line.addLine(to: b)
            ctx.stroke(line, with: .color(pairColor), lineWidth: 1)
        }

        // Draw strands with depth-based ordering
        // The strand closer to the viewer at each point should be drawn on top.
        // We approximate by drawing full back strand first, then front strand.
        let sinMid = sin(Double(steps / 2) / Double(steps) * 3.0 * .pi + phase)
        if sinMid >= 0 {
            // Purple is in front at midpoint
            ctx.stroke(pathB, with: .color(strandOrange.opacity(0.7)), lineWidth: 2)
            ctx.stroke(pathA, with: .color(strandPurple), lineWidth: 2.5)
        } else {
            ctx.stroke(pathA, with: .color(strandPurple.opacity(0.7)), lineWidth: 2)
            ctx.stroke(pathB, with: .color(strandOrange), lineWidth: 2.5)
        }
    }
}

#Preview {
    MiniHelixView()
        .padding()
        .background(Color.black)
}
