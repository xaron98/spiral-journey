import SwiftUI
import SpiralKit

/// Trends tab — answers "¿esto es puntual o es patrón?".
/// Top section: 3 human-readable trend dimensions.
/// Bottom: full analysis for users who want more detail.
struct AnalysisTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var showFullAnalysis    = false
    @State private var showDrift          = false
    @State private var showSlidingCosinor = false
    @State private var showPRC            = false
    @State private var showActogram       = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                if store.records.isEmpty {
                    emptyState
                } else {
                    trendHeader

                    // ── 3 trend dimensions ───────────────────────────────────
                    consistencyTrendCard
                    driftTrendCard
                    durationTrendCard

                    // ── Week vs Week comparison ───────────────────────────────
                    WeekComparisonCard(
                        records: store.records,
                        spiralType: store.spiralType,
                        period: store.period
                    )

                    // ── Trend arrows (engine output) ─────────────────────────
                    let trends = store.analysis.trends
                    if !trends.improving.isEmpty || !trends.deteriorating.isEmpty {
                        trendArrowsCard(trends)
                    }

                    // ── Full analysis — collapsible ──────────────────────────
                    fullAnalysisToggle

                    if showFullAnalysis {
                        scoreCard
                        if !store.analysis.categories.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                PanelTitle(title: String(localized: "conclusions.categories.title", bundle: bundle))
                                ForEach(store.analysis.categories) { cat in
                                    CategoryRow(category: cat, bundle: bundle)
                                }
                            }
                            .panelStyle()
                        }
                        if !store.analysis.recommendations.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                PanelTitle(title: String(localized: "conclusions.recommendations.title", bundle: bundle))
                                ForEach(store.analysis.recommendations) { rec in
                                    RecommendationRow(rec: rec, bundle: bundle)
                                }
                            }
                            .panelStyle()
                        }
                        StatsPanelView(records: store.records)
                        if showDrift          { DriftChartView(records: store.records) }
                        if showSlidingCosinor { SlidingCosinorView(records: store.records) }
                        if showPRC            { PRCChartView() }
                        if showActogram       { ActogramView(records: store.records) }
                        chartToggles
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
    }

    // MARK: - Header

    private var trendHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "analysis.header.title", bundle: bundle))
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(SpiralColors.text)
                Text(String(format: String(localized: "analysis.header.subtitle", bundle: bundle), store.numDays))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }

    // MARK: - 3 Trend Dimensions

    private var consistencyTrendCard: some View {
        let cons = store.analysis.consistency
        let score = cons?.score ?? 0
        let label = cons?.label ?? .insufficient
        let delta = cons?.deltaVsPreviousWeek

        return TrendDimensionCard(
            title: String(localized: "analysis.trend.consistency", bundle: bundle),
            value: cons != nil ? "\(score)" : "--",
            valueUnit: "/100",
            description: consistencyDescription(label: label, delta: delta),
            trend: trendDirection(delta: delta),
            accentColor: Color(hex: label.hexColor)
        )
    }

    private func consistencyDescription(label: ConsistencyLabel, delta: Double?) -> String {
        var base: String
        switch label {
        case .veryStable:   base = String(localized: "analysis.trend.consistency.veryStable",   bundle: bundle)
        case .stable:       base = String(localized: "analysis.trend.consistency.stable",       bundle: bundle)
        case .variable:     base = String(localized: "analysis.trend.consistency.variable",     bundle: bundle)
        case .disorganized: base = String(localized: "analysis.trend.consistency.disorganized", bundle: bundle)
        case .insufficient: base = String(localized: "analysis.trend.consistency.insufficient", bundle: bundle)
        }
        if let d = delta {
            let change = abs(Int(d))
            if d >= 2 {
                base += " · " + String(format: String(localized: "analysis.trend.consistency.better", bundle: bundle), change)
            } else if d <= -2 {
                base += " · " + String(format: String(localized: "analysis.trend.consistency.worse", bundle: bundle), change)
            }
        }
        return base
    }

    private var driftTrendCard: some View {
        let stats = store.analysis.stats
        let std = stats.stdAcrophase
        let jetlag = stats.socialJetlag

        let value: String
        let desc: String
        let color: Color
        let trend: TrendDirection

        if std <= 0 {
            value = "--"
            desc = String(localized: "analysis.trend.drift.noData",          bundle: bundle)
            color = SpiralColors.muted
            trend = .neutral
        } else if std < 0.5 {
            value = String(format: "±%.0fm", std * 60)
            desc = String(localized: "analysis.trend.drift.veryStable",      bundle: bundle)
            color = SpiralColors.good
            trend = .up
        } else if std < 1.0 {
            value = String(format: "±%.0fm", std * 60)
            desc = String(localized: "analysis.trend.drift.someVariation",   bundle: bundle)
            color = SpiralColors.moderate
            trend = .neutral
        } else {
            value = String(format: "±%.1fh", std)
            desc = String(localized: "analysis.trend.drift.significant",     bundle: bundle)
            color = SpiralColors.poor
            trend = .down
        }

        let jetlagNote = jetlag > 45 ? " · " + String(format: String(localized: "analysis.trend.drift.jetlagNote", bundle: bundle), jetlag) : ""

        return TrendDimensionCard(
            title: String(localized: "analysis.trend.drift", bundle: bundle),
            value: value,
            valueUnit: "",
            description: desc + jetlagNote,
            trend: trend,
            accentColor: color
        )
    }

    private var durationTrendCard: some View {
        let stats = store.analysis.stats
        let dur = stats.meanSleepDuration

        let value = dur > 0 ? String(format: "%.1fh", dur) : "--"
        let desc: String
        let color: Color
        let trend: TrendDirection

        if dur <= 0 {
            desc = String(localized: "analysis.trend.duration.noData",        bundle: bundle)
            color = SpiralColors.muted
            trend = .neutral
        } else if dur >= 7 && dur <= 9 {
            desc = String(localized: "analysis.trend.duration.optimal",       bundle: bundle)
            color = SpiralColors.good
            trend = .up
        } else if dur >= 6 {
            desc = String(localized: "analysis.trend.duration.slightlyShort", bundle: bundle)
            color = SpiralColors.moderate
            trend = .neutral
        } else {
            desc = String(localized: "analysis.trend.duration.tooShort",      bundle: bundle)
            color = SpiralColors.poor
            trend = .down
        }

        return TrendDimensionCard(
            title: String(localized: "analysis.trend.duration", bundle: bundle),
            value: value,
            valueUnit: String(localized: "analysis.trend.duration.unit", bundle: bundle),
            description: desc,
            trend: trend,
            accentColor: color
        )
    }

    // MARK: - Trend Arrows

    private func trendArrowsCard(_ trends: TrendAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "analysis.recentTrends", bundle: bundle))
            ForEach(trends.deteriorating) { t in trendRow(t, color: SpiralColors.poor,  arrow: "arrow.down") }
            ForEach(trends.improving)     { t in trendRow(t, color: SpiralColors.good,  arrow: "arrow.up") }
        }
        .panelStyle()
    }

    // MARK: - Full Analysis Toggle

    private var fullAnalysisToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { showFullAnalysis.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showFullAnalysis ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                Text(showFullAnalysis
                    ? String(localized: "analysis.fullAnalysis.hide", bundle: bundle)
                    : String(localized: "analysis.fullAnalysis.show", bundle: bundle)
                )
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(SpiralColors.accentDim)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(SpiralColors.border, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Localization helper

    /// Resolve a dynamic key string against the current language bundle.
    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private func trendDirection(delta: Double?) -> TrendDirection {
        guard let d = delta else { return .neutral }
        if d >= 2  { return .up }
        if d <= -2 { return .down }
        return .neutral
    }

    // MARK: - Score card

    private var localizedScoreLabel: String {
        if let key = store.analysis.scoreKey {
            return loc("score.\(key.rawValue)")
        }
        return store.analysis.label
    }

    private var scoreCard: some View {
        HStack(spacing: 16) {
            ScoreGaugeView(
                score: store.analysis.composite,
                label: localizedScoreLabel,
                hexColor: store.analysis.hexColor
            )
            .frame(width: 90, height: 90)

            VStack(alignment: .leading, spacing: 6) {
                Text("Spiral Journey")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                Text(localizedScoreLabel)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: store.analysis.hexColor))
                Text(String(localized: "conclusions.score.composite", bundle: bundle))
                    .font(.system(size: 10))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 16).fill(SpiralColors.surface.opacity(0.5))
                RoundedRectangle(cornerRadius: 16).stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8)
            }
        )
    }

    // MARK: - Chart toggles

    private var chartToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(localized: "analysis.charts.title", bundle: bundle))
            HStack(spacing: 6) {
                PillButton(label: String(localized: "analysis.charts.drift",    bundle: bundle), isActive: showDrift)          { showDrift.toggle() }
                PillButton(label: String(localized: "spiral.controls.cosinor",  bundle: bundle), isActive: showSlidingCosinor) { showSlidingCosinor.toggle() }
                PillButton(label: "PRC",                                                          isActive: showPRC)            { showPRC.toggle() }
                PillButton(label: String(localized: "analysis.charts.actogram", bundle: bundle), isActive: showActogram)       { showActogram.toggle() }
            }
        }
        .panelStyle()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 44))
                .foregroundStyle(SpiralColors.muted)
            Text(String(localized: "analysis.empty.title", bundle: bundle))
                .font(.system(size: 15, design: .monospaced))
                .foregroundStyle(SpiralColors.text)
            Text(String(localized: "analysis.empty.subtitle", bundle: bundle))
                .font(.system(size: 12))
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 80)
    }

    // MARK: - Helpers

    private func localizedTrendLabel(_ t: TrendItem) -> String {
        if let key = t.labelKey { return loc("trend.\(key.rawValue)") }
        return t.label
    }

    private func localizedTrendDetail(_ t: TrendItem) -> String {
        guard let key = t.detailKey else { return t.detail }
        let fmt = loc("trend.detail.\(key.rawValue)")
        if t.detailArgs.isEmpty { return fmt }
        switch t.detailArgs.count {
        case 1: return String(format: fmt, t.detailArgs[0])
        case 2: return String(format: fmt, t.detailArgs[0], t.detailArgs[1])
        default: return fmt
        }
    }

    private func trendRow(_ t: TrendItem, color: Color, arrow: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: arrow)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(localizedTrendLabel(t)).font(.system(size: 11, weight: .medium)).foregroundStyle(SpiralColors.text)
                Text(localizedTrendDetail(t)).font(.system(size: 9)).foregroundStyle(SpiralColors.muted)
            }
        }
    }
}

// MARK: - Trend Dimension Components

enum TrendDirection {
    case up, down, neutral

    var icon: String {
        switch self {
        case .up:      return "arrow.up.right"
        case .down:    return "arrow.down.right"
        case .neutral: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up:      return SpiralColors.good
        case .down:    return SpiralColors.poor
        case .neutral: return SpiralColors.muted
        }
    }
}

struct TrendDimensionCard: View {
    let title: String
    let value: String
    let valueUnit: String
    let description: String
    let trend: TrendDirection
    let accentColor: Color

    var body: some View {
        HStack(spacing: 14) {
            // Trend arrow
            Image(systemName: trend.icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(trend.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                    .textCase(.uppercase)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 22, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                    if !valueUnit.isEmpty {
                        Text(valueUnit)
                            .font(.system(size: 11))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
            Spacer()
        }
        .padding(14)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 14).fill(accentColor.opacity(0.04))
                RoundedRectangle(cornerRadius: 14).stroke(accentColor.opacity(0.2), lineWidth: 0.7)
            }
        )
    }
}

// MARK: - Shared sub-views (used here and in ConclusionsPanelView)

struct CategoryRow: View {
    let category: CategoryScore
    var bundle: Bundle = .main

    private var statusColor: Color {
        switch category.status {
        case .good:     return SpiralColors.good
        case .moderate: return SpiralColors.moderate
        case .poor:     return SpiralColors.poor
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var localizedLabel: String {
        if let key = category.labelKey { return loc("category.\(key.rawValue)") }
        return category.label
    }

    private var localizedDetail: String {
        if let key = category.detailKey { return loc("category.detail.\(key.rawValue)") }
        return category.detail
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(SpiralColors.border).frame(width: 48, height: 6)
                RoundedRectangle(cornerRadius: 3)
                    .fill(statusColor)
                    .frame(width: CGFloat(category.score) / 100 * 48, height: 6)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(localizedLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Text(category.value)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(statusColor)
                    Text("\(category.score)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)
                }
                Text(localizedDetail)
                    .font(.system(size: 9))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct RecommendationRow: View {
    let rec: Recommendation
    var bundle: Bundle = .main

    private var priorityColor: Color {
        switch rec.priority {
        case 1:  return SpiralColors.poor
        case 2:  return SpiralColors.moderate
        default: return SpiralColors.accentDim
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    private var localizedTitle: String {
        if let key = rec.key { return loc("rec.\(key.rawValue).title") }
        return rec.title
    }

    private var localizedText: String {
        guard let key = rec.key else { return rec.text }
        let fmt = loc("rec.\(key.rawValue).text")
        if rec.args.isEmpty { return fmt }
        switch rec.args.count {
        case 1: return String(format: fmt, rec.args[0])
        case 2: return String(format: fmt, rec.args[0], rec.args[1])
        default: return fmt
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(priorityColor)
                .frame(width: 3)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(localizedTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(localizedText)
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
