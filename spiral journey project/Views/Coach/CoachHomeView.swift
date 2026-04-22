import SwiftUI
import SpiralKit

/// Coach tab redesign — HybridA layout.
/// Scroll: header (with inline "Pregúntame…" pill), hero bento, 2×2
/// metrics, editorial feed. The system tab bar remains the navigation
/// chrome; this view does not render its own dock.
struct CoachHomeView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var showChat = false
    @State private var showPatterns = false
    @State private var showPlan = false

    private var adapter: CoachDataAdapter { CoachDataAdapter(store: store) }

    var body: some View {
        NavigationStack {
            ZStack {
                CoachTokens.bg.ignoresSafeArea()

                // Ambient purple glow top-right.
                RadialGradient(
                    colors: [CoachTokens.purple.opacity(0.18), .clear],
                    center: UnitPoint(x: 1.1, y: -0.05),
                    startRadius: 20, endRadius: 260)
                .ignoresSafeArea()
                .allowsHitTesting(false)

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header
                        if store.sleepEpisodes.isEmpty {
                            emptyState
                        } else {
                            heroBento
                            bentoGrid
                            divider
                            storyLoQueCambio
                            storyLoQuePropongo
                            storyAprende
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .sheet(isPresented: $showChat) { CoachChatView() }
            .sheet(isPresented: $showPlan) { CoachPlanView() }
            .navigationDestination(isPresented: $showPatterns) {
                CoachPatternsView()
            }
            .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayLabel)
                    .font(CoachTokens.mono(13))
                    .foregroundStyle(CoachTokens.textDim)
                    .tracking(0.4)
                Text(greeting)
                    .font(CoachTokens.sans(28, weight: .bold))
                    .foregroundStyle(.white)
                    .tracking(-0.5)
            }
            Spacer(minLength: 8)
            askPill
        }
        .padding(.top, 4)
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(CoachTokens.border).frame(height: 1)
            Text(String(localized: "coach.home.feed.divider", bundle: bundle))
                .font(CoachTokens.mono(10))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(1.5)
            Rectangle().fill(CoachTokens.border).frame(height: 1)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .padding(.horizontal, 4)
    }

    // Filled in Tasks 11–13.
    private var heroBento: some View {
        let h = adapter.hero
        return ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [CoachTokens.cardHi, CoachTokens.card],
                startPoint: .topLeading, endPoint: .bottomTrailing)

            RadialGradient(
                colors: [CoachTokens.purple.opacity(0.25), .clear],
                center: UnitPoint(x: 0.85, y: 0.30),
                startRadius: 10, endRadius: 160)
            .allowsHitTesting(false)

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    MiniSpiralView(size: 96, turns: 5, quality: Double(h.score) / 100, dotCount: 26)
                    VStack(spacing: 1) {
                        Text("\(h.score)")
                            .font(CoachTokens.mono(28, weight: .bold))
                            .foregroundStyle(.white)
                        Text("SCORE")
                            .font(CoachTokens.mono(8))
                            .foregroundStyle(CoachTokens.textDim)
                            .tracking(1)
                    }
                }
                .frame(width: 96, height: 96)

                VStack(alignment: .leading, spacing: 3) {
                    Text(h.todayLabel)
                        .font(CoachTokens.mono(10))
                        .foregroundStyle(CoachTokens.yellow)
                        .tracking(1)
                    Text(h.insightTitle)
                        .font(CoachTokens.sans(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(.top, 3)
                    CoachBarSeriesView(
                        values: h.last7Bars,
                        barHeight: 22,
                        color: CoachTokens.purple.opacity(0.7),
                        lowColor: CoachTokens.yellow.opacity(0.7),
                        highlightLast: h.accent)
                    .padding(.top, 8)
                    Text(h.last7Subtitle)
                        .font(CoachTokens.mono(10))
                        .foregroundStyle(CoachTokens.textDim)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .clipShape(RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CoachTokens.rLg, style: .continuous)
                .stroke(CoachTokens.borderHi, lineWidth: 1))
    }
    private var bentoGrid: some View {
        let b = adapter.bento
        return LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible())
        ], spacing: 10) {
            CoachMiniCard(title: String(localized: "coach.home.bento.duration.title", bundle: bundle),
                          value: b.durationValue, sub: b.durationSub,
                          valueColor: CoachTokens.yellow) {
                CoachSparklineView(values: b.durationSeries, color: CoachTokens.yellow,
                                   height: 26, showAxisDays: false)
                    .padding(.top, 6)
            }

            CoachMiniCard(title: String(localized: "coach.home.bento.consistency.title", bundle: bundle),
                          value: b.consistencyValue, sub: b.consistencySub,
                          valueColor: CoachTokens.purple) {
                CoachBarSeriesView(values: b.consistencyBars, barHeight: 22,
                                   color: CoachTokens.purple,
                                   lowColor: CoachTokens.yellow,
                                   highlightLast: CoachTokens.purple)
                    .padding(.top, 6)
            }

            Button {
                showPatterns = true
            } label: {
                CoachMiniCard(title: String(localized: "coach.home.bento.patterns.title", bundle: bundle),
                              value: b.patternsValue, sub: b.patternsSub,
                              valueColor: CoachTokens.blue, iconSystem: "waveform")
            }
            .buttonStyle(.plain)

            CoachMiniCard(title: String(localized: "coach.home.bento.habit.title", bundle: bundle),
                          value: b.habitValue, sub: b.habitSub,
                          valueColor: CoachTokens.yellow, accent: true) {
                HStack(spacing: 2) {
                    ForEach(0..<7, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(i < b.habitStripes.count && b.habitStripes[i]
                                  ? CoachTokens.yellow
                                  : Color.white.opacity(0.08))
                            .frame(height: 4)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
    private var storyLoQueCambio: some View {
        let c = adapter.change
        return CoachStoryCard(tag: String(localized: "coach.home.story.change.tag", bundle: bundle), tagColor: CoachTokens.yellow) {
            Text(c.headline)
                .font(CoachTokens.sans(16, weight: .semibold))
                .foregroundStyle(.white)
                .lineSpacing(2)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(String(localized: "coach.home.story.change.bedtime", bundle: bundle))
                    Spacer()
                    Text(c.rangeLabel)
                }
                .font(CoachTokens.mono(9))
                .foregroundStyle(CoachTokens.textDim)
                .tracking(0.5)
                .padding(.bottom, 6)

                CoachSparklineView(values: c.sparkValues, height: 48)
            }
            .padding(12)
            .background(Color.black.opacity(0.2))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var storyLoQuePropongo: some View {
        if let p = adapter.proposal {
            CoachStoryCard(tag: String(localized: "coach.home.story.propose.tag", bundle: bundle), tagColor: CoachTokens.purple, bright: true) {
                Text(p.title)
                    .font(CoachTokens.sans(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineSpacing(2)

                HStack(alignment: .center, spacing: 14) {
                    CoachTimeDialView(size: 72, windowStart: p.dialStart, windowEnd: p.dialEnd)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(localized: "coach.home.story.propose.window", bundle: bundle))
                            .font(CoachTokens.mono(9))
                            .foregroundStyle(CoachTokens.textDim)
                            .tracking(1)
                        Text(p.window)
                            .font(CoachTokens.mono(20, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(p.chronotypeSub)
                            .font(CoachTokens.sans(11))
                            .foregroundStyle(CoachTokens.textDim)
                            .padding(.top, 3)
                        HStack(spacing: 5) {
                            Button(String(localized: "coach.home.story.propose.remindMe", bundle: bundle)) { showPlan = true }
                                .buttonStyle(CoachPillButtonStyle(primary: true))
                            Button(String(localized: "coach.home.story.propose.adjust", bundle: bundle)) {
                                // Future: navigate to chronotype settings
                            }
                            .buttonStyle(CoachPillButtonStyle(primary: false))
                        }
                        .padding(.top, 9)
                    }
                }
                .padding(.top, 12)
            }
        }
    }

    private var storyAprende: some View {
        let l = adapter.learn
        return CoachStoryCard(tag: String(localized: "coach.home.story.learn.tag", bundle: bundle), tagColor: CoachTokens.blue) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(LinearGradient(
                            colors: [CoachTokens.blue.opacity(0.27), CoachTokens.purpleDeep.opacity(0.27)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14).stroke(CoachTokens.border, lineWidth: 1))
                    SparkSpiralView(size: 38, turns: 4, color: CoachTokens.blue, lineWidth: 1.5)
                }
                .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(l.title)
                        .font(CoachTokens.sans(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    Text(l.subtitle)
                        .font(CoachTokens.sans(11))
                        .foregroundStyle(CoachTokens.textDim)
                }
            }
        }
    }

    // MARK: - Ask pill (header trailing)

    private var askPill: some View {
        Button { showChat = true } label: {
            HStack(spacing: 6) {
                SparkSpiralView(size: 14, turns: 3, color: CoachTokens.purple, lineWidth: 1.3)
                Text(String(localized: "coach.dock.askPlaceholder", bundle: bundle))
                    .font(CoachTokens.sans(11, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                LinearGradient(
                    colors: [CoachTokens.purple.opacity(0.28), CoachTokens.purpleDeep.opacity(0.28)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                Capsule().stroke(CoachTokens.purple.opacity(0.45), lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            SparkSpiralView(size: 72, turns: 4, color: CoachTokens.purple, lineWidth: 2)
                .padding(.top, 60)
            Text(String(localized: "coach.home.empty.title", bundle: bundle))
                .font(CoachTokens.sans(20, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(String(localized: "coach.home.empty.body", bundle: bundle))
                .font(CoachTokens.sans(14))
                .foregroundStyle(CoachTokens.textDim)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Copy helpers

    private var todayLabel: String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "EEE · d MMM"
        return fmt.string(from: Date()).uppercased()
    }

    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        switch h {
        case 5..<12:  return String(localized: "coach.home.greeting.morning", bundle: bundle)
        case 12..<20: return String(localized: "coach.home.greeting.afternoon", bundle: bundle)
        default:      return String(localized: "coach.home.greeting.evening", bundle: bundle)
        }
    }
}

private struct CoachPillButtonStyle: ButtonStyle {
    let primary: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CoachTokens.sans(12, weight: .medium))
            .foregroundStyle(primary ? .white : CoachTokens.textDim)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background(primary ? CoachTokens.purple : Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
