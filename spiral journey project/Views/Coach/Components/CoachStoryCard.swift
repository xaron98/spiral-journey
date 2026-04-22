import SwiftUI

/// Editorial card with colored dot + tag label in mono ALL CAPS, followed
/// by body content. `bright = true` paints a purple gradient background
/// (used for "LO QUE TE PROPONGO").
struct CoachStoryCard<Content: View>: View {
    let tag: String
    let tagColor: Color
    var bright: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(tagColor).frame(width: 4, height: 4)
                Text(tag)
                    .font(CoachTokens.mono(10, weight: .medium))
                    .foregroundStyle(tagColor)
                    .tracking(1.3)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous)
                .stroke(bright ? CoachTokens.purple.opacity(0.25) : CoachTokens.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous))
    }

    private var background: some View {
        Group {
            if bright {
                LinearGradient(
                    colors: [CoachTokens.purple.opacity(0.14), CoachTokens.card],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else {
                CoachTokens.card
            }
        }
    }
}

#Preview {
    ZStack {
        CoachTokens.bg.ignoresSafeArea()
        VStack(spacing: 10) {
            CoachStoryCard(tag: "LO QUE CAMBIÓ", tagColor: CoachTokens.yellow) {
                Text("Te acuestas **1h 47m más tarde** que la semana pasada.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            CoachStoryCard(tag: "LO QUE TE PROPONGO", tagColor: CoachTokens.purple, bright: true) {
                Text("Esta noche, antes de la 01:30.")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
