import SwiftUI
import SpiralKit

/// Coach tab — answers "¿qué hago hoy?".
/// One insight, one habit, one action. No dashboards.
struct CoachTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

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
                    // Trend context — only if there's something notable
                    if hasTrendContext { trendContextCard }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
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
        let insight = primaryInsight
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
        let action = todayAction
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

    private var primaryInsight: CoachContent {
        let stats = store.analysis.stats
        let consistency = store.analysis.consistency

        // Global shift first (most urgent)
        if let c = consistency, !c.globalShiftDays.isEmpty {
            let n = c.globalShiftDays.count
            return CoachContent(
                title: loc("coach.insight.shift.title"),
                body: String(format: loc("coach.insight.shift.body"), n),
                icon: "arrow.left.and.right.circle",
                color: SpiralColors.poor
            )
        }

        // High social jetlag
        if stats.socialJetlag > 60 {
            let min = Int(stats.socialJetlag)
            return CoachContent(
                title: loc("coach.insight.jetlag.title"),
                body: String(format: loc("coach.insight.jetlag.body"), min),
                icon: "calendar.badge.exclamationmark",
                color: SpiralColors.moderate
            )
        }

        // High variability
        let bedStd = stats.stdBedtime > 0 ? stats.stdBedtime : stats.stdAcrophase
        if bedStd > 1.0 {
            return CoachContent(
                title: loc("coach.insight.irregular.title"),
                body: String(format: loc("coach.insight.irregular.body"), bedStd),
                icon: "waveform.path.ecg",
                color: SpiralColors.moderate
            )
        }

        // Short sleep
        if stats.meanSleepDuration > 0 && stats.meanSleepDuration < 6.5 {
            return CoachContent(
                title: loc("coach.insight.short.title"),
                body: String(format: loc("coach.insight.short.body"), stats.meanSleepDuration),
                icon: "bed.double",
                color: SpiralColors.poor
            )
        }

        // All good
        return CoachContent(
            title: loc("coach.insight.good.title"),
            body: loc("coach.insight.good.body"),
            icon: "checkmark.circle",
            color: SpiralColors.good
        )
    }

    private var primaryHabit: CoachContent {
        // Use top recommendation from the engine
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

    private var todayAction: String {
        let stats = store.analysis.stats

        // Rephase mode takes priority when active
        if store.rephasePlan.isEnabled, stats.meanAcrophase > 0 {
            return RephaseCalculator.todayActionText(plan: store.rephasePlan, meanAcrophase: stats.meanAcrophase, bundle: bundle)
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
