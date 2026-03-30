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
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.largeTitle.weight(.bold).monospaced())
                    .foregroundStyle(Color(hex: hexColor))
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 12)
            .offset(y: -4)
        }
        .onAppear { animatedProgress = progress }
        .onChange(of: score) { animatedProgress = Double($1) / 100 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "accessibility.gauge.label", defaultValue: "Score gauge") + ", \(score), \(label)")
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
