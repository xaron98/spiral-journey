import SwiftUI

/// 7-point area chart with line on top and dots. Normalizes `values` to
/// fit the drawing bounds. Last point is rendered larger + stroked.
struct CoachSparklineView: View {
    var values: [Double]              // length N, arbitrary domain
    var color: Color = CoachTokens.yellow
    var height: CGFloat = 48
    var showAxisDays: Bool = true     // L M X J V S D labels

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let pts = points(in: geo.size)
                ZStack {
                    // Area fill.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: CGPoint(x: first.x, y: geo.size.height))
                        p.addLine(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: pts.last?.x ?? 0, y: geo.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(
                        colors: [color.opacity(0.45), color.opacity(0.0)],
                        startPoint: .top, endPoint: .bottom))

                    // Line.
                    Path { p in
                        guard let first = pts.first else { return }
                        p.move(to: first)
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Dots.
                    ForEach(Array(pts.enumerated()), id: \.offset) { idx, pt in
                        let isLast = idx == pts.count - 1
                        Circle()
                            .fill(color)
                            .overlay {
                                if isLast {
                                    Circle().stroke(CoachTokens.bg, lineWidth: 2)
                                }
                            }
                            .frame(width: isLast ? 7 : 4, height: isLast ? 7 : 4)
                            .position(pt)
                    }
                }
            }
            .frame(height: height)

            if showAxisDays {
                HStack {
                    ForEach(["L","M","X","J","V","S","D"], id: \.self) { d in
                        Text(d).frame(maxWidth: .infinity)
                    }
                }
                .font(CoachTokens.mono(9))
                .foregroundStyle(CoachTokens.textFaint)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !values.isEmpty else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let span = max(0.0001, maxV - minV)
        let stepX = size.width / CGFloat(max(1, values.count - 1))
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = (v - minV) / span
            let y = size.height - CGFloat(norm) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.card.ignoresSafeArea()
        CoachSparklineView(values: [8, 10, 18, 30, 38, 34, 40])
            .padding()
    }
    .preferredColorScheme(.dark)
}
