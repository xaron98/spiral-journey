import SwiftUI

/// One cell of the 2×2 metric bento. Mono title + large value + sub +
/// optional bottom slot (sparkline, bars, habit stripes). `accent = true`
/// paints the whole card with a yellow gradient (for HÁBITO).
struct CoachMiniCard<Bottom: View>: View {
    let title: String          // ALL CAPS — "DURACIÓN"
    let value: String          // "4.5h"
    let sub: String            // "anoche · -1.2h"
    var valueColor: Color = CoachTokens.yellow
    var iconSystem: String? = nil
    var accent: Bool = false
    @ViewBuilder var bottom: () -> Bottom

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top) {
                Text(title)
                    .font(CoachTokens.mono(9))
                    .foregroundStyle(CoachTokens.textDim)
                    .tracking(1)
                Spacer()
                if let sys = iconSystem {
                    Image(systemName: sys)
                        .font(.system(size: 13))
                        .foregroundStyle(valueColor)
                }
            }
            Text(value)
                .font(CoachTokens.mono(20, weight: .bold))
                .foregroundStyle(valueColor)
                .padding(.top, 4)
            Text(sub)
                .font(CoachTokens.sans(10))
                .foregroundStyle(CoachTokens.textDim)
                .padding(.top, 2)
            bottom()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rMd, style: .continuous)
                .stroke(accent ? CoachTokens.yellow.opacity(0.22) : CoachTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rMd, style: .continuous))
    }

    private var cardBackground: some View {
        Group {
            if accent {
                LinearGradient(
                    colors: [CoachTokens.yellow.opacity(0.15), CoachTokens.yellow.opacity(0.03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                CoachTokens.card
            }
        }
    }
}

extension CoachMiniCard where Bottom == EmptyView {
    init(title: String, value: String, sub: String,
         valueColor: Color = CoachTokens.yellow,
         iconSystem: String? = nil, accent: Bool = false) {
        self.init(title: title, value: value, sub: sub,
                  valueColor: valueColor, iconSystem: iconSystem, accent: accent,
                  bottom: { EmptyView() })
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            CoachMiniCard(title: "DURACIÓN", value: "4.5h", sub: "anoche · -1.2h") {
                CoachSparklineView(values: [8,10,18,30,38,34,40], height: 26, showAxisDays: false)
                    .padding(.top, 6)
            }
            CoachMiniCard(title: "CONSISTENCIA", value: "32", sub: "/100 · irregular",
                          valueColor: CoachTokens.purple) {
                CoachBarSeriesView(values: [0.7, 0.9, 0.4, 0.3, 0.85, 0.5, 0.4],
                                   barHeight: 22,
                                   color: CoachTokens.purple,
                                   highlightLast: CoachTokens.purple)
                    .padding(.top, 6)
            }
            CoachMiniCard(title: "PATRONES", value: "3 tardes", sub: "esta semana",
                          valueColor: CoachTokens.blue, iconSystem: "waveform")
            CoachMiniCard(title: "HÁBITO", value: "5", sub: "días seguidos",
                          valueColor: CoachTokens.yellow, accent: true) {
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < 5 ? CoachTokens.yellow : Color.white.opacity(0.08))
                            .frame(height: 4)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
