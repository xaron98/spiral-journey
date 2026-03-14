import SwiftUI
import SpiralKit

/// Coach tab — answers "¿qué hago hoy?".
/// One insight, one habit, one action. No dashboards.
struct CoachTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @State private var showJetLagSetup = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if store.records.isEmpty {
                    emptyState
                } else {
                    header
                    insightCard
                    habitCard
                    actionCard
                    // Nap recommendation — only when Process S is high enough
                    if let nap = napRecommendation { napCard(nap) }
                    // Jet lag planner button
                    jetLagButton
                    // Trend context — only if there's something notable
                    if hasTrendContext { trendContextCard }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .sheet(isPresented: $showJetLagSetup) {
            JetLagSetupView()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "tab.coach", bundle: bundle))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(SpiralColors.text)
                Text(String(localized: "coach.header.subtitle", bundle: bundle))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }
            Spacer()
            Image(systemName: "lightbulb.min.fill")
                .font(.system(size: 20))
                .foregroundStyle(SpiralColors.accent)
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
            return localizedCoachString("coach.issue.\(ci.issueKey.rawValue).outcome", fallback: ci.expectedOutcome, args: ci.args)
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(String(localized: "coach.action.eyebrow", bundle: bundle))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SpiralColors.muted)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: "calendar.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.accent)
            }

            Text(action)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(SpiralColors.text)
                .fixedSize(horizontal: false, vertical: true)

            if let outcome, !outcome.isEmpty {
                Text(outcome)
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
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
                    .font(.system(size: 14))
                    .foregroundStyle(SpiralColors.poor)
                    .frame(width: 20)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 44))
                .foregroundStyle(SpiralColors.muted)
            Text(String(localized: "coach.empty.title", bundle: bundle))
                .font(.system(size: 15))
                .foregroundStyle(SpiralColors.text)
            Text(String(localized: "coach.empty.subtitle", bundle: bundle))
                .font(.system(size: 12))
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
        .padding(.horizontal, 20)
    }

    // MARK: - Nap Recommendation

    private var napRecommendation: NapOptimizer.NapRecommendation? {
        guard !store.records.isEmpty else { return nil }
        let lastRecord = store.records.last!
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
            case .circadianDip:  return loc("coach.nap.reason.circadianDip")
            case .highPressure:  return loc("coach.nap.reason.highPressure")
            case .debtRecovery:  return loc("coach.nap.reason.debtRecovery")
            }
        }()

        return HStack(spacing: 12) {
            Image(systemName: "moon.zzz")
                .font(.system(size: 22))
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(String(
                    format: loc("coach.nap.title"),
                    timeStr, nap.duration
                ))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpiralColors.text)
                Text(reasonStr)
                    .font(.system(size: 11))
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

    // MARK: - Jet Lag Planner Button

    private var jetLagButton: some View {
        Button {
            showJetLagSetup = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 18))
                    .foregroundStyle(SpiralColors.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "coach.jetlag.button.title", bundle: bundle))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(localized: "coach.jetlag.button.subtitle", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
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
        }
    }

    /// Primary insight sourced from `coachInsight` when available, with legacy fallback.
    private var resolvedInsight: CoachContent {
        if let ci = store.analysis.coachInsight {
            let localTitle = localizedCoachString("coach.issue.\(ci.issueKey.rawValue).title", fallback: ci.title, args: ci.args)
            let localReason = localizedCoachString("coach.issue.\(ci.issueKey.rawValue).reason", fallback: ci.reason, args: ci.args)
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
            return localizedCoachString("coach.issue.\(ci.issueKey.rawValue).action", fallback: ci.action, args: ci.args)
        }
        return legacyAction
    }

    /// Resolve a coach localization key with optional format args; falls back to English `fallback`.
    private func localizedCoachString(_ key: String, fallback: String, args: [Double]) -> String {
        let raw = NSLocalizedString(key, bundle: bundle, comment: "")
        let resolved = raw == key ? fallback : raw   // key == raw means no translation found
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
        switch rec.args.count {
        case 1: return String(format: resolved, rec.args[0])
        case 2: return String(format: resolved, rec.args[0], rec.args[1])
        default: return resolved
        }
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
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SpiralColors.muted)
                    .textCase(.uppercase)
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accentColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SpiralColors.text)

            Text(message)
                .font(.system(size: 12))
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
    }
}
