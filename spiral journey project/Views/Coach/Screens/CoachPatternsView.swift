import SwiftUI
import SpiralKit

struct CoachPatternsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ZStack {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.blue.opacity(0.18), .clear],
                           center: UnitPoint(x: -0.1, y: -0.05),
                           startRadius: 20, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    heatmapCard
                    correlationCard
                    insightsList
                    Spacer().frame(height: 40)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden()
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachTokens.card)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(CoachTokens.border))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "coach.patterns.header", bundle: bundle))
                    .font(CoachTokens.mono(10))
                    .foregroundStyle(CoachTokens.textDim)
                    .tracking(1)
                Text(String(localized: "coach.patterns.title", bundle: bundle))
                    .font(CoachTokens.sans(22, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "coach.patterns.heatmap.label", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.blue)
                .tracking(1)
            Text(String(localized: "coach.patterns.heatmap.insight", bundle: bundle))
                .font(CoachTokens.sans(15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 4)

            HStack(spacing: 3) {
                ForEach(Array(["L","M","X","J","V","S","D"].enumerated()), id: \.offset) { di, d in
                    VStack(spacing: 2) {
                        Text(d).font(CoachTokens.mono(9)).foregroundStyle(CoachTokens.textDim)
                        ForEach(0..<4, id: \.self) { wi in
                            let late = (di == 4 || di == 5)
                            let v = late
                                ? 0.7 + Double((wi * 17) % 30) / 100.0
                                : Double((wi * 23) % 55) / 100.0
                            Rectangle()
                                .fill(late
                                      ? CoachTokens.yellow.opacity(v)
                                      : CoachTokens.purple.opacity(v))
                                .frame(height: 22)
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 14)

            HStack {
                Text("00:30")
                Spacer()
                Text(String(localized: "coach.patterns.heatmap.arrow", bundle: bundle))
                Spacer()
                Text("03:30")
            }
            .font(CoachTokens.mono(9))
            .foregroundStyle(CoachTokens.textFaint)
            .padding(.top, 8)
        }
        .padding(16)
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private var correlationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "coach.patterns.correlation.tag", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.purple)
                .tracking(1)
            Text(String(localized: "coach.patterns.correlation.insight", bundle: bundle))
                .font(CoachTokens.sans(15, weight: .semibold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                correlationColumn(label: String(localized: "coach.patterns.correlation.with", bundle: bundle),
                                  value: "00:52",
                                  color: CoachTokens.green, barWidth: 1.0)
                correlationColumn(label: String(localized: "coach.patterns.correlation.without", bundle: bundle),
                                  value: "01:30",
                                  color: CoachTokens.yellow, barWidth: 0.75)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func correlationColumn(label: String, value: String, color: Color, barWidth: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(CoachTokens.mono(9))
                .foregroundStyle(CoachTokens.textDim)
            Text(value)
                .font(CoachTokens.mono(22, weight: .bold))
                .foregroundStyle(color)
            GeometryReader { g in
                RoundedRectangle(cornerRadius: 3)
                    .fill(color.opacity(0.6))
                    .frame(width: g.size.width * barWidth, height: 5)
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var insightsList: some View {
        VStack(spacing: 0) {
            insightRow(icon: "flame",
                       label: String(localized: "coach.patterns.insight.streak", bundle: bundle),
                       value: String(localized: "coach.patterns.insight.streak.value", bundle: bundle),
                       sub: String(localized: "coach.patterns.insight.streak.sub", bundle: bundle),
                       color: CoachTokens.yellow, isFirst: true)
            insightRow(icon: "moon.stars",
                       label: String(localized: "coach.patterns.insight.bestDay", bundle: bundle),
                       value: String(localized: "coach.patterns.insight.bestDay.value", bundle: bundle),
                       sub: String(localized: "coach.patterns.insight.bestDay.sub", bundle: bundle),
                       color: CoachTokens.purple)
            insightRow(icon: "chart.line.uptrend.xyaxis",
                       label: String(localized: "coach.patterns.insight.trend", bundle: bundle),
                       value: String(localized: "coach.patterns.insight.trend.value", bundle: bundle),
                       sub: String(localized: "coach.patterns.insight.trend.sub", bundle: bundle),
                       color: CoachTokens.green)
            insightRow(icon: "clock",
                       label: String(localized: "coach.patterns.insight.ideal", bundle: bundle),
                       value: String(localized: "coach.patterns.insight.ideal.value", bundle: bundle),
                       sub: String(localized: "coach.patterns.insight.ideal.sub", bundle: bundle),
                       color: CoachTokens.blue)
        }
        .background(CoachTokens.card)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(CoachTokens.border))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func insightRow(icon: String, label: String, value: String, sub: String,
                             color: Color, isFirst: Bool = false) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.13))
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(color)
            }
            .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(CoachTokens.sans(13, weight: .medium)).foregroundStyle(.white)
                Text(sub).font(CoachTokens.sans(10)).foregroundStyle(CoachTokens.textDim)
            }
            Spacer()
            Text(value).font(CoachTokens.mono(15, weight: .semibold)).foregroundStyle(color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle().fill(CoachTokens.border).frame(height: 1)
            }
        }
    }
}
