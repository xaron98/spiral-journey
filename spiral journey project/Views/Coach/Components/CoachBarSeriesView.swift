import SwiftUI

/// 7 vertical bars with height proportional to value (0–1). Last bar
/// highlighted. Bar color switches to `lowColor` when value < 0.5.
struct CoachBarSeriesView: View {
    var values: [Double]              // 0...1
    var barHeight: CGFloat = 22
    var color: Color = CoachTokens.purple.opacity(0.7)
    var lowColor: Color = CoachTokens.yellow.opacity(0.7)
    var highlightLast: Color = CoachTokens.yellow
    var gap: CGFloat = 3
    var cornerRadius: CGFloat = 2

    var body: some View {
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(Array(values.enumerated()), id: \.offset) { idx, v in
                let isLast = idx == values.count - 1
                let clamped = min(max(v, 0), 1)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isLast ? highlightLast : (v < 0.5 ? lowColor : color))
                    .frame(height: max(2, barHeight * CGFloat(clamped)))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: barHeight, alignment: .bottom)
    }
}

#Preview {
    ZStack {
        CoachTokens.cardHi.ignoresSafeArea()
        CoachBarSeriesView(values: [0.6, 0.4, 0.35, 0.9, 0.7, 0.5, 0.45])
            .padding()
    }
    .preferredColorScheme(.dark)
}
