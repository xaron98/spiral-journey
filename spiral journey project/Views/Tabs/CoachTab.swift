import SwiftUI
import SpiralKit

/// Coach tab — answers "¿qué hago hoy?".
/// One insight, one habit, one action. No dashboards.
struct CoachTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @State private var showJetLagSetup = false
    @State private var showCoachChat = false
    @State private var showPeerComparison = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if store.records.isEmpty {
                    emptyState
                } else {
                    header
                    // ⚠️ Trend context — alert banner at the top
                    if hasTrendContext { trendContextCard }
                    // 🎉 Celebration card (only if there's a positive achievement)
                    if let celebration = store.analysis.enhancedCoach?.celebrations.first {
                        celebrationCard(celebration)
                    }
                    insightCard
                    // 🔥 Streak card (only if active streak ≥2)
                    if let streak = store.analysis.enhancedCoach?.streak, streak.isActive {
                        streakCard(streak)
                    }
                    habitCard
                    actionCard
                    // ✅ Micro-habit card
                    if let habit = store.analysis.enhancedCoach?.microHabit {
                        microHabitCard(habit)
                    }
                    // 📊 Weekly digest card
                    if let digest = store.analysis.enhancedCoach?.weeklyDigest, digest.isValid {
                        weeklyDigestCard(digest)
                    }
                    // 📅 Temporal pattern cards
                    ForEach(store.analysis.enhancedCoach?.temporalPatterns ?? []) { pattern in
                        temporalPatternCard(pattern)
                    }
                    // 🏃 Event acknowledgments
                    ForEach(store.analysis.enhancedCoach?.eventAcknowledgments ?? []) { ack in
                        eventAcknowledgmentCard(ack)
                    }
                    // Nap recommendation — only when Process S is high enough
                    if let nap = napRecommendation { napCard(nap) }
                    // Optimal sleep duration suggestion
                    if let optimal = optimalDuration { optimalDurationCard(optimal) }
                    // Jet lag planner button
                    jetLagButton
                    // Conflict trend — if we have enough history
                    if let trend = store.conflictTrend { conflictTrendCard(trend) }

                    // 📚 Learn about sleep
                    LearnView()
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .sheet(isPresented: $showJetLagSetup) {
            JetLagSetupView()
        }
        .sheet(isPresented: $showCoachChat) {
            CoachChatView()
        }
        .sheet(isPresented: $showPeerComparison) {
            PeerComparisonView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "tab.coach", bundle: bundle))
                    .font(.title2.weight(.light))
                    .foregroundStyle(SpiralColors.text)
                Text(String(localized: "coach.header.subtitle", bundle: bundle))
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.subtle)
            }
            Spacer()
            Button {
                showPeerComparison = true
            } label: {
                Image(systemName: "person.2.wave.2")
                    .font(.headline)
                    .foregroundStyle(SpiralColors.accent)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle()
                            .stroke(SpiralColors.accent.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            if store.llmEnabled {
                Button {
                    showCoachChat = true
                } label: {
                    Image(systemName: "brain.head.profile")
                        .font(.headline)
                        .foregroundStyle(SpiralColors.accent)
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(SpiralColors.accent.opacity(0.4), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "lightbulb.min.fill")
                    .font(.title2)
                    .foregroundStyle(SpiralColors.accent)
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Insight Card (qué está pasando)

    private var insightCard: some View {
        let insight = resolvedInsight
        return CoachSectionCard(
            eyebrow: String(localized: "coach.insight.eyebrow", bundle: bundle),
            title: insight.title,
            message: insight.body,
            icon: insight.icon,
            accentColor: insight.color
        )
    }

    // MARK: - Habit Card (qué hábito trabajar)

    private var habitCard: some View {
        let habit = primaryHabit
        return CoachSectionCard(
            eyebrow: String(localized: "coach.habit.eyebrow", bundle: bundle),
            title: habit.title,
            message: habit.body,
            icon: "repeat.circle",
            accentColor: SpiralColors.moderate
        )
    }

    // MARK: - Action Card (qué hacer hoy)

    private var actionCard: some View {
        let action = resolvedAction
        let outcome: String? = {
            guard let ci = store.analysis.coachInsight, !ci.expectedOutcome.isEmpty else { return nil }
            return localizedCoachString("coach.issue.\(ci.issueKey.rawValue).outcome", fallback: ci.expectedOutcome, args: ci.args, stringArgs: ci.stringArgs)
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(String(localized: "coach.action.eyebrow", bundle: bundle))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.accent)
            }

            Text(action)
                .font(.headline.weight(.semibold))
                .foregroundStyle(SpiralColors.text)
                .fixedSize(horizontal: false, vertical: true)

            if let outcome, !outcome.isEmpty {
                Text(outcome)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(SpiralColors.accent.opacity(0.07))
                RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.accent.opacity(0.25), lineWidth: 0.8)
            }
        )
    }

    // MARK: - Trend Context Card (si hay algo notable en tendencias)

    private var hasTrendContext: Bool {
        !store.analysis.trends.deteriorating.isEmpty || store.analysis.stats.socialJetlag > 45
    }

    @ViewBuilder
    private var trendContextCard: some View {
        let text = trendContextText
        if !text.isEmpty {
            HStack(spacing: 10) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.body)
                    .foregroundStyle(SpiralColors.poor)
                    .frame(width: 20)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(SpiralColors.poor.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SpiralColors.poor.opacity(0.15), lineWidth: 0.6)
                    )
            )
        }
    }

    // MARK: - Conflict Trend Card

    private func conflictTrendCard(_ trend: ConflictTrendEngine.ConflictTrend) -> some View {
        let icon: String
        let tint: Color
        let text: String

        switch trend.direction {
        case .improving:
            icon = "chart.line.downtrend.xyaxis"
            tint = SpiralColors.good
            text = String(
                format: loc("coach.trend.conflicts.improving"),
                trend.previousWeekConflicts, trend.currentWeekConflicts
            )
        case .worsening:
            icon = "chart.line.uptrend.xyaxis"
            tint = SpiralColors.poor
            text = String(
                format: loc("coach.trend.conflicts.worsening"),
                trend.previousWeekConflicts, trend.currentWeekConflicts
            )
        case .stable:
            icon = "equal.circle"
            tint = SpiralColors.muted
            text = String(
                format: loc("coach.trend.conflicts.stable"),
                trend.currentWeekConflicts
            )
        }

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(text)
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.15), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.largeTitle)
                .foregroundStyle(SpiralColors.muted)
            Text(String(localized: "coach.empty.title", bundle: bundle))
                .font(.subheadline)
                .foregroundStyle(SpiralColors.text)
            Text(String(localized: "coach.empty.subtitle", bundle: bundle))
                .font(.footnote)
                .foregroundStyle(SpiralColors.subtle)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 20)
    }

    // MARK: - Nap Recommendation

    private var napRecommendation: NapOptimizer.NapRecommendation? {
        guard let lastRecord = store.records.last else { return nil }
        return NapOptimizer.recommend(
            records: store.records,
            wakeHour: lastRecord.wakeupHour,
            chronotype: store.chronotypeResult?.chronotype
        )
    }

    private func napCard(_ nap: NapOptimizer.NapRecommendation) -> some View {
        let timeStr = String(format: "%02d:00", Int(nap.suggestedStart))
        let reasonStr: String = {
            switch nap.reason {
            case .circadianDip:     return loc("coach.nap.reason.circadianDip")
            case .highPressure:     return loc("coach.nap.reason.highPressure")
            case .debtRecovery:     return loc("coach.nap.reason.debtRecovery")
            case .contextAdjusted:  return loc("coach.nap.reason.contextAdjusted")
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.title2)
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(
                    format: loc("coach.nap.title"),
                    timeStr, nap.duration
                ))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SpiralColors.text)
                Text(reasonStr)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SpiralColors.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(SpiralColors.accent.opacity(0.18), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Optimal Duration

    private var optimalDuration: OptimalDurationAnalyzer.OptimalDurationResult? {
        OptimalDurationAnalyzer.analyze(records: store.records)
    }

    private func optimalDurationCard(_ result: OptimalDurationAnalyzer.OptimalDurationResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bed.double.fill")
                .font(.title2)
                .foregroundStyle(SpiralColors.good)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: loc("coach.optimal.title"), result.formatted))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(result.isConfident
                     ? loc("coach.optimal.confident")
                     : loc("coach.optimal.preliminary"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SpiralColors.good.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(SpiralColors.good.opacity(0.18), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Jet Lag Planner Button

    private var jetLagButton: some View {
        Button {
            showJetLagSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplane.departure")
                    .font(.headline)
                    .foregroundStyle(SpiralColors.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "coach.jetlag.button.title", bundle: bundle))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(localized: "coach.jetlag.button.subtitle", bundle: bundle))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.muted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(SpiralColors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(SpiralColors.border, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Celebration Card

    private func celebrationCard(_ celebration: ProgressCelebration) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "star.fill")
                .font(.title2)
                .foregroundStyle(.yellow)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("coach.celebration.eyebrow"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Text(localizedCoachString(celebration.messageKey, fallback: celebration.message, args: celebration.args))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
            }
            Spacer()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(Color.yellow.opacity(0.08))
                RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.25), lineWidth: 0.8)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "accessibility.celebration", defaultValue: "Achievement"))
    }

    // MARK: - Streak Card

    private func streakCard(_ streak: StreakData) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(loc("coach.streak.eyebrow"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                HStack(spacing: 6) {
                    Text(String(format: loc("coach.streak.current"), streak.currentStreak))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    if streak.bestStreak > streak.currentStreak {
                        Text("·")
                            .foregroundStyle(SpiralColors.muted)
                        Text(String(format: loc("coach.streak.best"), streak.bestStreak))
                            .font(.caption)
                            .foregroundStyle(SpiralColors.muted)
                    } else if streak.isNewRecord {
                        Text("🏆")
                            .font(.footnote)
                    }
                }
            }
            Spacer()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.06))
                RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.18), lineWidth: 0.8)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(localized: "accessibility.streak", defaultValue: "Streak") + ", \(streak.currentStreak)")
    }

    // MARK: - Micro-Habit Card

    private func microHabitCard(_ habit: MicroHabit) -> some View {
        let isCompleted = store.isMicroHabitCompleted(habit)
        return HStack(spacing: 12) {
            Button {
                store.toggleMicroHabit(habit)
            } label: {
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCompleted ? SpiralColors.good : SpiralColors.muted)
                    .frame(width: 36)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: loc("coach.microhabit.eyebrow"), habit.cycleDay + 1))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
                Text(localizedCoachString(habit.actionKey, fallback: habit.action, args: []))
                    .font(.footnote.weight(isCompleted ? .regular : .semibold))
                    .foregroundStyle(isCompleted ? SpiralColors.muted : SpiralColors.text)
                    .strikethrough(isCompleted)
            }
            Spacer()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(SpiralColors.good.opacity(isCompleted ? 0.08 : 0.03))
                RoundedRectangle(cornerRadius: 14).stroke(SpiralColors.good.opacity(0.15), lineWidth: 0.8)
            }
        )
    }

    // MARK: - Weekly Digest Card

    private func weeklyDigestCard(_ digest: WeeklyDigest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(loc("coach.digest.eyebrow"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "chart.bar.fill")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.accent)
            }

            // Grid: bedtime, duration, SRI with delta arrows
            VStack(spacing: 8) {
                digestRow(
                    label: loc("coach.digest.bedtime"),
                    value: SleepStatistics.formatHour(digest.meanBedtime),
                    delta: digest.bedtimeDeltaMinutes,
                    unit: "min",
                    invertColor: true // earlier bedtime = positive
                )
                digestRow(
                    label: loc("coach.digest.duration"),
                    value: String(format: "%.1fh", digest.meanDuration),
                    delta: digest.durationDeltaMinutes,
                    unit: "min",
                    invertColor: false
                )
                digestRow(
                    label: "SRI",
                    value: String(format: "%.0f", digest.sri),
                    delta: digest.sriDelta,
                    unit: "pts",
                    invertColor: false
                )
                digestRow(
                    label: loc("coach.digest.score"),
                    value: "\(digest.compositeScore)",
                    delta: Double(digest.compositeDelta),
                    unit: "pts",
                    invertColor: false
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(SpiralColors.accent.opacity(0.04))
                RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.accent.opacity(0.18), lineWidth: 0.8)
            }
        )
    }

    private func digestRow(label: String, value: String, delta: Double, unit: String, invertColor: Bool) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
                .frame(width: 65, alignment: .leading)
            Text(value)
                .font(.footnote.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.text)
            Spacer()
            if abs(delta) >= 1 {
                let positive = invertColor ? (delta < 0) : (delta > 0)
                let arrow = delta > 0 ? "↑" : "↓"
                let color = positive ? SpiralColors.good : SpiralColors.poor
                Text("\(arrow)\(Int(abs(delta)))\(unit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(color)
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
    }

    // MARK: - Temporal Pattern Card

    private func temporalPatternCard(_ pattern: TemporalPattern) -> some View {
        let bedDir = pattern.bedtimeDeviationMinutes > 0 ? loc("coach.pattern.later") : loc("coach.pattern.earlier")
        let absMin = Int(abs(pattern.bedtimeDeviationMinutes))
        let message: String
        if abs(pattern.bedtimeDeviationMinutes) >= 30 {
            message = String(format: loc("coach.pattern.bedtime"), pattern.weekdayName, absMin, bedDir)
        } else {
            let durDir = pattern.durationDeviationMinutes > 0 ? loc("coach.pattern.longer") : loc("coach.pattern.shorter")
            let durMin = Int(abs(pattern.durationDeviationMinutes))
            message = String(format: loc("coach.pattern.duration"), pattern.weekdayName, durMin, durDir)
        }

        return HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.body)
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 20)
            Text(message)
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SpiralColors.accent.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(SpiralColors.accent.opacity(0.12), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Event Acknowledgment Card

    private func eventAcknowledgmentCard(_ ack: EventAcknowledgment) -> some View {
        let icon: String
        let tint: Color
        switch ack.effect {
        case .positive: icon = "hand.thumbsup.fill"; tint = SpiralColors.good
        case .negative: icon = "exclamationmark.triangle"; tint = SpiralColors.moderate
        case .neutral:  icon = "info.circle"; tint = SpiralColors.muted
        }

        return HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(localizedCoachString(ack.messageKey, fallback: ack.message, args: ack.args))
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(tint.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(tint.opacity(0.15), lineWidth: 0.6)
                )
        )
    }

    // MARK: - Floating Chat Button

    private var chatFloatingButton: some View {
        Button {
            showCoachChat = true
        } label: {
            Image(systemName: "brain.head.profile")
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(SpiralColors.accent.opacity(0.9), in: Circle())
                .shadow(color: SpiralColors.accent.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 110)
    }

    // MARK: - Data helpers

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private struct CoachContent {
        let title: String
        let body: String
        let icon: String
        let color: Color
    }

    /// Maps a `CoachSeverity` to the appropriate UI color.
    private func color(for severity: CoachSeverity) -> Color {
        switch severity {
        case .urgent:   return SpiralColors.poor
        case .moderate: return SpiralColors.moderate
        case .mild:     return SpiralColors.accent
        case .info:     return SpiralColors.good
        }
    }

    /// Maps a `CoachIssueKey` to a system image name.
    private func icon(for issue: CoachIssueKey) -> String {
        switch issue {
        case .delayedPhase:                return "moon.circle"
        case .advancedPhase:               return "sunrise.circle"
        case .splitSleep:                  return "moon.haze"
        case .socialJetlag:                return "calendar.badge.exclamationmark"
        case .irregularSchedule:           return "waveform.path.ecg"
        case .insufficientDuration:        return "bed.double"
        case .fragmentedSleep:             return "waveform.badge.exclamationmark"
        case .sufficientButMisaligned:     return "arrow.left.and.right.circle"
        case .maintenance:                 return "checkmark.circle"
        case .offTargetForShift:           return "deskclock"
        case .offTargetForCustomSchedule:  return "calendar.badge.clock"
        case .rephaseInProgress:           return "arrow.clockwise.circle"
        case .insufficientData:            return "moon.zzz"
        // Context block conflicts
        case .sleepOverlapsContext:         return "bed.double.circle"
        case .sleepTooCloseToContext:       return "alarm"
        case .daytimeSleepConsumesContext:  return "sun.max.trianglebadge.exclamationmark"
        // Shift-specific context-aware coaching
        case .shiftLightTiming:            return "sun.max.fill"
        case .sleepinessRiskDuringWork:    return "exclamationmark.triangle.fill"
        }
    }

    /// Primary insight sourced from `coachInsight` when available, with legacy fallback.
    private var resolvedInsight: CoachContent {
        if let ci = store.analysis.coachInsight {
            let localTitle = localizedCoachString("coach.issue.\(ci.issueKey.rawValue).title", fallback: ci.title, args: ci.args, stringArgs: ci.stringArgs)
            let localReason = localizedCoachString("coach.issue.\(ci.issueKey.rawValue).reason", fallback: ci.reason, args: ci.args, stringArgs: ci.stringArgs)
            return CoachContent(title: localTitle, body: localReason, icon: icon(for: ci.issueKey), color: color(for: ci.severity))
        }
        return legacyInsight
    }

    /// Today's action sourced from `coachInsight` when available, with legacy fallback.
    private var resolvedAction: String {
        // Rephase mode takes priority when active
        if store.rephasePlan.isEnabled, store.analysis.stats.meanAcrophase > 0 {
            return RephaseCalculator.todayActionText(plan: store.rephasePlan, meanAcrophase: store.analysis.stats.meanAcrophase, bundle: bundle)
        }
        if let ci = store.analysis.coachInsight {
            return localizedCoachString("coach.issue.\(ci.issueKey.rawValue).action", fallback: ci.action, args: ci.args, stringArgs: ci.stringArgs)
        }
        return legacyAction
    }

    /// Resolve a coach localization key with optional format args; falls back to English `fallback`.
    /// `stringArgs` takes priority over `args` when present — used for pre-formatted values like "HH:MM" times.
    private func localizedCoachString(_ key: String, fallback: String, args: [Double], stringArgs: [String] = []) -> String {
        let raw = NSLocalizedString(key, bundle: bundle, comment: "")
        let resolved = raw == key ? fallback : raw   // key == raw means no translation found
        if !stringArgs.isEmpty {
            switch stringArgs.count {
            case 1: return String(format: resolved, stringArgs[0])
            case 2: return String(format: resolved, stringArgs[0], stringArgs[1])
            default: return resolved
            }
        }
        guard !args.isEmpty else { return resolved }
        switch args.count {
        case 1: return String(format: resolved, args[0])
        case 2: return String(format: resolved, args[0], args[1])
        case 3: return String(format: resolved, args[0], args[1], args[2])
        default: return resolved
        }
    }

    // MARK: - Habit Card logic (unchanged — driven by recommendations engine)

    private var primaryHabit: CoachContent {
        if let rec = store.analysis.recommendations.first {
            let localizedTitle = localizedRecTitle(rec)
            let localizedText  = localizedRecText(rec)
            return CoachContent(title: localizedTitle, body: localizedText, icon: "repeat.circle", color: SpiralColors.moderate)
        }
        return CoachContent(
            title: loc("coach.habit.default.title"),
            body: loc("coach.habit.default.body"),
            icon: "repeat.circle",
            color: SpiralColors.moderate
        )
    }

    private var trendContextText: String {
        let trends = store.analysis.trends
        if let t = trends.deteriorating.first {
            return String(format: loc("coach.trend.deteriorating"), t.detail)
        }
        if store.analysis.stats.socialJetlag > 45 {
            return loc("coach.trend.socialJetlag")
        }
        return ""
    }

    // MARK: - Legacy fallbacks (used only when coachInsight is nil)

    private var legacyInsight: CoachContent {
        let stats = store.analysis.stats
        let consistency = store.analysis.consistency

        if let c = consistency, !c.globalShiftDays.isEmpty {
            let n = c.globalShiftDays.count
            return CoachContent(
                title: loc("coach.insight.shift.title"),
                body: String(format: loc("coach.insight.shift.body"), n),
                icon: "arrow.left.and.right.circle",
                color: SpiralColors.poor
            )
        }
        if stats.socialJetlag > 60 {
            let min = Int(stats.socialJetlag)
            return CoachContent(
                title: loc("coach.insight.jetlag.title"),
                body: String(format: loc("coach.insight.jetlag.body"), min),
                icon: "calendar.badge.exclamationmark",
                color: SpiralColors.moderate
            )
        }
        let bedStd = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if bedStd > 1.0 {
            return CoachContent(
                title: loc("coach.insight.irregular.title"),
                body: String(format: loc("coach.insight.irregular.body"), bedStd),
                icon: "waveform.path.ecg",
                color: SpiralColors.moderate
            )
        }
        if stats.meanSleepDuration > 0 && stats.meanSleepDuration < 6.5 {
            return CoachContent(
                title: loc("coach.insight.short.title"),
                body: String(format: loc("coach.insight.short.body"), stats.meanSleepDuration),
                icon: "bed.double",
                color: SpiralColors.poor
            )
        }
        if stats.meanAcrophase > 18.5 {
            let bedApprox = SleepStatistics.formatHour(stats.meanAcrophase - 8)
            let wakeApprox = SleepStatistics.formatHour(stats.meanAcrophase - 8 + stats.meanSleepDuration)
            return CoachContent(
                title: loc("coach.insight.delayed.title"),
                body: String(format: loc("coach.insight.delayed.body"), bedApprox, wakeApprox),
                icon: "moon.circle",
                color: SpiralColors.moderate
            )
        }
        return CoachContent(
            title: loc("coach.insight.good.title"),
            body: loc("coach.insight.good.body"),
            icon: "checkmark.circle",
            color: SpiralColors.good
        )
    }

    private var legacyAction: String {
        let stats = store.analysis.stats
        if stats.meanAcrophase > 18.5 {
            let lightTime = SleepStatistics.formatHour(stats.meanAcrophase - 8 + 0.5)
            return String(format: loc("coach.action.morningLight"), lightTime)
        }
        if stats.socialJetlag > 60 {
            let advance = Int(min(stats.socialJetlag / 7, 20))
            return String(format: loc("coach.action.advanceBedtime"), advance)
        }
        let bedStdForAction = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if bedStdForAction > 1.0 {
            let targetHour = SleepStatistics.formatHour(stats.meanAcrophase - 8)
            return String(format: loc("coach.action.targetBedtime"), targetHour)
        }
        if stats.meanSleepDuration > 0 && stats.meanSleepDuration < 6.5 {
            return loc("coach.action.sleepEarlier")
        }
        if let c = store.analysis.consistency, c.score >= 75 {
            return loc("coach.action.keepSchedule")
        }
        return loc("coach.action.chooseTime")
    }

    private func localizedRecTitle(_ rec: Recommendation) -> String {
        guard let key = rec.key else { return rec.title }
        let localized = NSLocalizedString("rec.\(key.rawValue).title", bundle: bundle, comment: "")
        return localized == "rec.\(key.rawValue).title" ? rec.title : localized
    }

    private func localizedRecText(_ rec: Recommendation) -> String {
        guard let key = rec.key else { return rec.text }
        let fmt = NSLocalizedString("rec.\(key.rawValue).text", bundle: bundle, comment: "")
        let resolved = fmt == "rec.\(key.rawValue).text" ? rec.text : fmt
        if rec.args.isEmpty { return resolved }
        // Jetlag recs pass minutes — format as hours for display
        if key == .reduceSocialJetlag || key == .minimizeWeekendLag {
            return String(format: resolved, formatJetlag(rec.args[0]))
        }
        switch rec.args.count {
        case 1: return String(format: resolved, rec.args[0])
        case 2: return String(format: resolved, rec.args[0], rec.args[1])
        default: return resolved
        }
    }

    /// Formats minutes as "Xh Ym" or "Xm" for display.
    private func formatJetlag(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

// MARK: - Coach Section Card

private struct CoachSectionCard: View {
    let eyebrow: String
    let title: String
    let message: String
    let icon: String
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SpiralColors.subtle)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(accentColor)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SpiralColors.text)

            Text(message)
                .font(.footnote)
                .foregroundStyle(SpiralColors.muted)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(accentColor.opacity(0.04))
                RoundedRectangle(cornerRadius: 16).stroke(accentColor.opacity(0.18), lineWidth: 0.8)
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(eyebrow), \(title)")
    }
}
