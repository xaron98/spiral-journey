import SwiftUI

/// Animated 270-degree arc gauge displaying a score (0-100).
struct ScoreGaugeView: View {

    let score: Int
    let label: String
    let hexColor: String

    @State private var animatedProgress: Double = 0

    private var progress: Double { Double(score) / 100 }

    var body: some View {
        ZStack {
            // Track arc (270°, starts at -225° = 7 o'clock)
            Arc(startAngle: .degrees(-225), endAngle: .degrees(45))
                .stroke(SpiralColors.border, style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // Fill arc
            Arc(startAngle: .degrees(-225), endAngle: .degrees(-225 + 270 * animatedProgress))
                .stroke(Color(hex: hexColor),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .animation(.easeOut(duration: 1.0), value: animatedProgress)

            // Score text
            VStack(spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(hex: hexColor))
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .onAppear { animatedProgress = progress }
        .onChange(of: score) { animatedProgress = Double($1) / 100 }
    }
}

private struct Arc: Shape {
    var startAngle: Angle
    var endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: min(rect.width, rect.height) / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
