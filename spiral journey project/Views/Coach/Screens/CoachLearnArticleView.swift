import SwiftUI
import SpiralKit

/// Reading sheet shown when the user taps the "Aprende · 3 min" card on
/// the Coach home. Content is hardcoded for the initial release; future
/// iterations will load from a library keyed by article id.
struct CoachLearnArticleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.blue.opacity(0.18), .clear],
                           center: UnitPoint(x: -0.1, y: -0.05),
                           startRadius: 20, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    hero
                    bodyText
                    Spacer().frame(height: 120)
                }
            }

            bottomDismiss
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachTokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Spacer()
            Text(String(localized: "coach.home.story.learn.tag", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.blue)
                .tracking(1.3)
            Spacer()
            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(LinearGradient(
                        colors: [CoachTokens.blue.opacity(0.3), CoachTokens.purpleDeep.opacity(0.3)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .stroke(CoachTokens.border, lineWidth: 1))
                SparkSpiralView(size: 110, turns: 5, color: CoachTokens.blue, lineWidth: 2.2)
            }
            .frame(height: 160)

            Text(String(localized: "coach.home.story.learn.title", bundle: bundle))
                .font(CoachTokens.sans(22, weight: .bold))
                .foregroundStyle(.white)
                .lineSpacing(2)
                .padding(.top, 6)

            Text(String(localized: "coach.home.story.learn.subtitle", bundle: bundle))
                .font(CoachTokens.mono(11))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(0.5)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var bodyText: some View {
        let raw = String(localized: "coach.learn.jetlag.body", bundle: bundle)
        let styled = (try? AttributedString(markdown: raw, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(raw)
        return Text(styled)
            .font(CoachTokens.sans(15))
            .foregroundStyle(.white.opacity(0.88))
            .lineSpacing(6)
            .padding(.horizontal, 20)
            .padding(.top, 20)
    }

    private var bottomDismiss: some View {
        Button { dismiss() } label: {
            Text(String(localized: "coach.learn.dismiss", bundle: bundle))
                .font(CoachTokens.sans(14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(LinearGradient(
                    colors: [CoachTokens.blue, CoachTokens.purpleDeep],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .padding(6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 28).fill(.ultraThinMaterial)
                Color(hex: "1E1E3C").opacity(0.72)
            })
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
}
