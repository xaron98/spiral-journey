import SwiftUI
import SpiralKit

struct CoachPlanView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private var adapter: CoachDataAdapter { CoachDataAdapter(store: store) }

    var body: some View {
        ZStack(alignment: .bottom) {
            CoachTokens.bg.ignoresSafeArea()
            RadialGradient(colors: [CoachTokens.purple.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.5, y: -0.2),
                           startRadius: 40, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 0) {
                    header
                    dialSection
                    headline
                    preparationList
                    Spacer().frame(height: 100)
                }
            }

            bottomCTA
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
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
            Text(String(localized: "coach.plan.header", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
            Spacer()
            Color.clear.frame(width: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var dialSection: some View {
        if let p = adapter.proposal {
            ZStack {
                CoachTargetDialView(
                    size: 240,
                    windowStart: p.dialStart,
                    windowEnd: p.dialEnd,
                    targetHour: (p.dialStart + p.dialEnd) / 2)
                VStack(spacing: -2) {
                    Text(String(localized: "coach.plan.bedtimeAt", bundle: bundle))
                        .font(CoachTokens.mono(10))
                        .foregroundStyle(CoachTokens.purple)
                        .tracking(1.5)
                    Text(formatTarget((p.dialStart + p.dialEnd) / 2))
                        .font(CoachTokens.mono(56, weight: .bold))
                        .tracking(-2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, CoachTokens.purple],
                                startPoint: .top, endPoint: .bottom))
                    Text(countdownLabel(to: (p.dialStart + p.dialEnd) / 2))
                        .font(CoachTokens.mono(11))
                        .foregroundStyle(CoachTokens.textDim)
                }
            }
            .padding(.top, 30)
        }
    }

    private var headline: some View {
        VStack(spacing: 8) {
            Text(String(localized: "coach.plan.headline", bundle: bundle))
                .font(CoachTokens.sans(19, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text(String(localized: "coach.plan.description", bundle: bundle))
                .font(CoachTokens.sans(13))
                .multilineTextAlignment(.center)
                .foregroundStyle(CoachTokens.textDim)
                .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private var preparationList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "coach.plan.preparation", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1)
                .padding(.leading, 4)
                .padding(.bottom, 6)

            ForEach(steps, id: \.time) { step in
                HStack(spacing: 10) {
                    Text(step.time)
                        .font(CoachTokens.mono(13, weight: .semibold))
                        .foregroundStyle(step.color)
                        .frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.label)
                            .font(CoachTokens.sans(13, weight: .medium))
                            .foregroundStyle(.white)
                        Text(step.detail)
                            .font(CoachTokens.sans(11))
                            .foregroundStyle(CoachTokens.textDim)
                    }
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(stepBackground(step))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(step.highlight ? CoachTokens.purple.opacity(0.35) : CoachTokens.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func stepBackground(_ step: Step) -> some View {
        if step.highlight {
            LinearGradient(
                colors: [CoachTokens.purple.opacity(0.18), CoachTokens.card],
                startPoint: .leading, endPoint: .trailing)
        } else {
            CoachTokens.card
        }
    }

    private var bottomCTA: some View {
        HStack {
            Button { activateReminder() } label: {
                Text(String(localized: "coach.plan.cta.enableReminder", bundle: bundle))
                    .font(CoachTokens.sans(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(LinearGradient(
                        colors: [CoachTokens.purple, CoachTokens.purpleDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                    .clipShape(RoundedRectangle(cornerRadius: 22))
            }
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

    // MARK: Data

    private var steps: [Step] {
        [
            .init(time: "00:30",
                  label: String(localized: "coach.plan.step1.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step1.detail", bundle: bundle),
                  color: CoachTokens.yellow, highlight: false),
            .init(time: "01:00",
                  label: String(localized: "coach.plan.step2.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step2.detail", bundle: bundle),
                  color: CoachTokens.yellow, highlight: false),
            .init(time: "01:20",
                  label: String(localized: "coach.plan.step3.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step3.detail", bundle: bundle),
                  color: CoachTokens.purple, highlight: false),
            .init(time: "01:30",
                  label: String(localized: "coach.plan.step4.label", bundle: bundle),
                  detail: String(localized: "coach.plan.step4.detail", bundle: bundle),
                  color: CoachTokens.purple, highlight: true),
        ]
    }

    private struct Step {
        let time: String
        let label: String
        let detail: String
        let color: Color
        let highlight: Bool
    }

    // MARK: Helpers

    private func formatTarget(_ h: Double) -> String {
        let hh = Int(h) % 24
        let mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }

    private func countdownLabel(to hour: Double) -> String {
        let now = Date()
        let cal = Calendar.current
        let comps = cal.dateComponents([.hour, .minute], from: now)
        let nowHours = Double(comps.hour ?? 0) + Double(comps.minute ?? 0) / 60.0
        var diff = hour - nowHours
        if diff < 0 { diff += 24 }
        let h = Int(diff)
        let m = Int((diff - Double(h)) * 60)
        return String(format: String(localized: "coach.plan.countdown", bundle: bundle), h, m)
    }

    private func activateReminder() {
        // Future: wire to BackgroundTaskManager.scheduleBedtimeReminder.
        // Out of scope for this task — left as a single integration point.
    }
}
