import SwiftUI
import SpiralKit

/// Full-screen detail view for Spiral Consistency Score.
/// Accessed by tapping the consistency score card in SpiralTab.
struct ConsistencyDetailView: View {

    let consistency: SpiralConsistencyScore
    let records: [SleepRecord]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle
    @Environment(\.modelContext) private var modelContext
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(SpiralStore.self) private var store
    @Environment(OnDeviceAIService.self) private var aiService
    @State private var showLegendHelp = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // ── Hero Score ───────────────────────────────────────────
                heroSection

                // ── Breakdown Bars ───────────────────────────────────────
                breakdownSection

                // ── Weekly Heatmap ───────────────────────────────────────
                weeklyHeatmapSection

                // ── Insights ─────────────────────────────────────────────
                if !consistency.insights.isEmpty {
                    insightsSection
                }

                // ── Temporal Impact (Poisson + Hawkes) ─────────────────────
                if let profile = dnaService.latestProfile,
                   profile.poissonFragmentation != nil || profile.hawkesAnalysis != nil {
                    temporalImpactSection(profile: profile)
                }

                // ── Previous Week Comparison ─────────────────────────────
                if let delta = consistency.deltaVsPreviousWeek {
                    comparisonSection(delta: delta)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .task {
            // Auto-refresh DNA profile if Poisson/Hawkes fields are missing
            if let profile = dnaService.latestProfile,
               profile.poissonFragmentation == nil && profile.hawkesAnalysis == nil {
                await dnaService.forceRefresh(store: store, context: modelContext)
            } else if dnaService.latestProfile == nil {
                await dnaService.refreshIfNeeded(store: store, context: modelContext)
            }
        }
        .navigationTitle(String(localized: "consistency.title", bundle: bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 10) {
            ZStack {
                // Background ring track
                Circle()
                    .stroke(SpiralColors.border, lineWidth: 8)
                    .frame(width: 110, height: 110)

                // Score ring
                Circle()
                    .trim(from: 0, to: CGFloat(consistency.score) / 100)
                    .stroke(
                        consistencyLabelColor(consistency.label),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: consistency.score)

                VStack(spacing: 2) {
                    Text("\(consistency.score)")
                        .font(.largeTitle.weight(.bold).monospaced())
                        .foregroundStyle(consistencyLabelColor(consistency.label))
                    Text(String(localized: String.LocalizationValue(consistency.label.localizationKey)))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SpiralColors.muted)
                }
            }

            // Confidence + nights used
            HStack(spacing: 8) {
                confidenceBadge
                Text(String(format: String(localized: "consistency.nights", bundle: bundle), consistency.nightsUsed))
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(cardBackground)
    }

    private var confidenceBadge: some View {
        let (label, color): (String, Color) = switch consistency.confidence {
        case .high:   (String(localized: "consistency.confidence.high",   bundle: bundle), SpiralColors.good)
        case .medium: (String(localized: "consistency.confidence.medium", bundle: bundle), SpiralColors.moderate)
        case .low:    (String(localized: "consistency.confidence.low",    bundle: bundle), SpiralColors.poor)
        }
        return Text(label)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(String(localized: "consistency.breakdown.title", bundle: bundle))

            VStack(spacing: 8) {
                BreakdownRow(
                    label: String(localized: "consistency.breakdown.sleepOnset", bundle: bundle),
                    value: consistency.breakdown.sleepOnsetRegularity,
                    weight: "30%"
                )
                BreakdownRow(
                    label: String(localized: "consistency.breakdown.wakeTime", bundle: bundle),
                    value: consistency.breakdown.wakeTimeRegularity,
                    weight: "25%"
                )
                BreakdownRow(
                    label: String(localized: "consistency.breakdown.fragmentation", bundle: bundle),
                    value: consistency.breakdown.fragmentationPatternSimilarity,
                    weight: "25%"
                )
                BreakdownRow(
                    label: String(localized: "consistency.breakdown.duration", bundle: bundle),
                    value: consistency.breakdown.sleepDurationStability,
                    weight: "10%"
                )

                let recLabel = consistency.breakdown.recoveryFromRealData
                    ? String(localized: "consistency.breakdown.recovery.real",  bundle: bundle)
                    : String(localized: "consistency.breakdown.recovery.proxy", bundle: bundle)
                BreakdownRow(
                    label: recLabel,
                    value: consistency.breakdown.recoveryStability,
                    weight: "10%"
                )
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Weekly Heatmap

    private var weeklyHeatmapSection: some View {
        let nights = recentNights(count: consistency.nightsUsed)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(String(format: String(localized: "consistency.heatmap.title", bundle: bundle), consistency.nightsUsed))
                Spacer()
                Button { showLegendHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            .sheet(isPresented: $showLegendHelp) {
                ConsistencyLegendSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }

            if nights.isEmpty {
                Text(String(localized: "consistency.heatmap.noData", bundle: bundle))
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
            } else {
                WeeklyNightGrid(
                    nights: nights,
                    localDisruptionDays: consistency.localDisruptionDays,
                    globalShiftDays: consistency.globalShiftDays
                )
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Insights

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "consistency.insights.title", bundle: bundle))

            ForEach(consistency.insights) { insight in
                InsightDetailCard(insight: insight)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    // MARK: - Comparison

    private func comparisonSection(delta: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(String(localized: "consistency.comparison.title", bundle: bundle))

            HStack(spacing: 0) {
                // Current week
                weekBlock(label: String(localized: "consistency.comparison.thisWeek", bundle: bundle), score: consistency.score, isCurrent: true)

                // Arrow + delta
                VStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? SpiralColors.good : SpiralColors.poor)
                    Text(String(format: "%+.0f", delta))
                        .font(.footnote.weight(.bold).monospaced())
                        .foregroundStyle(delta >= 0 ? SpiralColors.good : SpiralColors.poor)
                }
                .frame(maxWidth: .infinity)

                // Previous week
                let prevScore = max(0, min(100, consistency.score - Int(delta)))
                weekBlock(label: String(localized: "consistency.comparison.prevWeek", bundle: bundle), score: prevScore, isCurrent: false)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func weekBlock(label: String, score: Int, isCurrent: Bool) -> some View {
        let scoreLabel = ConsistencyLabel.from(score: score)
        return VStack(spacing: 6) {
            Text("\(score)")
                .font(.title.weight(.bold).monospaced())
                .foregroundStyle(isCurrent ? consistencyLabelColor(consistency.label) : SpiralColors.muted)
            Text(String(localized: String.LocalizationValue(scoreLabel.localizationKey)))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Temporal Impact

    @State private var showTemporalHelp = false
    @State private var aiSummary: String?
    @State private var isGeneratingAI = false

    @ViewBuilder
    private func temporalImpactSection(profile: SleepDNAProfile) -> some View {
        let hasPoisson = profile.poissonFragmentation != nil
        let hasHawkes = profile.hawkesAnalysis != nil

        if hasPoisson || hasHawkes {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    sectionHeader(loc("consistency.temporal.title"))
                    Spacer()
                    Button { showTemporalHelp = true } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.muted)
                    }
                    .buttonStyle(.plain)
                }
                .sheet(isPresented: $showTemporalHelp) {
                    TemporalImpactHelpSheet()
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }

                // Poisson: baseline rate + anomalies
                if let poisson = profile.poissonFragmentation {
                    // Baseline
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path")
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.accent)
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: loc("consistency.temporal.baseline"), poisson.baselineRate))
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(SpiralColors.text)
                            Text(poisson.followsPoisson
                                 ? loc("consistency.temporal.random")
                                 : loc("consistency.temporal.pattern"))
                                .font(.caption)
                                .foregroundStyle(poisson.followsPoisson ? SpiralColors.muted : SpiralColors.accent)
                        }
                    }

                    // Anomalous nights
                    if !poisson.anomalousNights.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(SpiralColors.moderate)
                                .frame(width: 24)
                            Text(String(format: loc("consistency.temporal.anomalies"), poisson.anomalousNights.count))
                                .font(.caption)
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                }

                // Hawkes: event impacts
                if let hawkes = profile.hawkesAnalysis {
                    let significant = hawkes.eventImpacts.filter { $0.significantEffect }
                    if !significant.isEmpty {
                        Divider().background(SpiralColors.border.opacity(0.5))

                        ForEach(Array(significant.enumerated()), id: \.offset) { _, impact in
                            let isHarmful = impact.excitationStrength > 0
                            HStack(spacing: 8) {
                                Image(systemName: eventIcon(impact.eventType))
                                    .font(.subheadline)
                                    .foregroundStyle(isHarmful ? SpiralColors.poor : SpiralColors.good)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(String(format: isHarmful
                                                ? loc("consistency.temporal.impact")
                                                : loc("consistency.temporal.impact.positive"),
                                               eventName(impact.eventType),
                                               Int(abs(impact.excitationStrength) * 100)))
                                        .font(.footnote)
                                        .foregroundStyle(SpiralColors.text)
                                    Text(String(format: loc("consistency.temporal.delay"), Int(impact.delayHours)))
                                        .font(.caption)
                                        .foregroundStyle(SpiralColors.muted)
                                }
                            }
                        }
                    }
                }

                // AI Summary button
                if aiService.isAvailable {
                    Divider().background(SpiralColors.border.opacity(0.5))
                    if let summary = aiSummary {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.accent)
                                Text("AI")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Text(summary)
                                .font(.footnote)
                                .foregroundStyle(SpiralColors.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.opacity)
                    } else {
                        Button {
                            if #available(iOS 26, *) {
                                Task { await generateAISummary(profile: profile) }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                if isGeneratingAI {
                                    ProgressView().controlSize(.small).tint(SpiralColors.accent)
                                } else {
                                    Image(systemName: "sparkles")
                                        .font(.caption)
                                }
                                Text(loc("consistency.temporal.ai.button"))
                                    .font(.footnote.weight(.medium))
                            }
                            .foregroundStyle(SpiralColors.accent)
                        }
                        .buttonStyle(.plain)
                        .disabled(isGeneratingAI)
                    }
                }
            }
            .padding(14)
            .background(cardBackground)
        }
    }

    @available(iOS 26, *)
    private func generateAISummary(profile: SleepDNAProfile) async {
        isGeneratingAI = true
        defer { isGeneratingAI = false }

        let result = await aiService.interpretSleepInsights(
            poisson: profile.poissonFragmentation,
            hawkes: profile.hawkesAnalysis,
            healthMarkers: profile.healthMarkers,
            consistency: consistency,
            locale: bundle.preferredLocalizations.first ?? "es"
        )

        withAnimation(.easeInOut(duration: 0.3)) {
            aiSummary = result
        }
    }

    private func eventIcon(_ type: EventType) -> String {
        switch type {
        case .caffeine: return "cup.and.saucer.fill"
        case .exercise: return "figure.run"
        case .alcohol:  return "wineglass.fill"
        case .stress:   return "brain.head.profile"
        case .melatonin: return "moon.fill"
        case .light:    return "sun.max.fill"
        default:        return "circle.fill"
        }
    }

    private func eventName(_ type: EventType) -> String {
        switch type {
        case .caffeine: return loc("consistency.temporal.caffeine")
        case .exercise: return loc("consistency.temporal.exercise")
        case .alcohol:  return loc("consistency.temporal.alcohol")
        case .stress:   return loc("consistency.temporal.stress")
        case .melatonin: return loc("consistency.temporal.melatonin")
        case .light:    return loc("consistency.temporal.light")
        default:        return ""
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Helpers

    private func consistencyLabelColor(_ label: ConsistencyLabel) -> Color {
        switch label {
        case .veryStable, .stable:   return SpiralColors.good
        case .variable:              return SpiralColors.moderate
        case .disorganized:          return SpiralColors.poor
        case .insufficient:          return SpiralColors.muted
        }
    }

    private func recentNights(count: Int) -> [SleepRecord] {
        records
            .filter { $0.sleepDuration >= 3.0 }
            .sorted { $0.date < $1.date }
            .suffix(count)
            .reversed()
            .map { $0 }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold).monospaced())
            .foregroundStyle(SpiralColors.muted)
            .textCase(.uppercase)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(SpiralColors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(SpiralColors.border, lineWidth: 0.5)
            )
    }
}

// MARK: - Breakdown Row

private struct BreakdownRow: View {
    let label: String
    let value: Double  // 0–100
    let weight: String

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text(weight)
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(String(format: "%.0f", value))
                    .font(.footnote.weight(.semibold).monospaced())
                    .foregroundStyle(barColor(value))
                    .frame(width: 28, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(SpiralColors.border)
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor(value))
                        .frame(width: geo.size.width * CGFloat(value / 100), height: 4)
                        .animation(.easeOut(duration: 0.5), value: value)
                }
            }
            .frame(height: 4)
        }
    }

    private func barColor(_ v: Double) -> Color {
        if v >= 70 { return SpiralColors.good }
        if v >= 50 { return SpiralColors.moderate }
        return SpiralColors.poor
    }
}

// MARK: - Weekly Night Grid

private struct WeeklyNightGrid: View {
    let nights: [SleepRecord]
    let localDisruptionDays: [Int]
    let globalShiftDays: [Int]

    @Environment(\.languageBundle) private var bundle
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 6) {
            // Header row: day labels
            HStack(spacing: 4) {
                ForEach(Array(nights.enumerated()), id: \.offset) { idx, record in
                    VStack(spacing: 3) {
                        Text(dayLabel(record.date))
                            .font(.caption2.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                            .frame(maxWidth: .infinity)

                        NightCell(
                            record: record,
                            isLocalDisruption: localDisruptionDays.contains(record.day),
                            isGlobalShift: globalShiftDays.contains(record.day)
                        )
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                LegendDot(color: SpiralColors.good,     label: String(localized: "consistency.legend.normal",          bundle: bundle))
                LegendDot(color: SpiralColors.moderate, label: String(localized: "consistency.legend.localDisruption", bundle: bundle))
                LegendDot(color: SpiralColors.poor,     label: String(localized: "consistency.legend.globalShift",     bundle: bundle))
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EE"
        fmt.locale = locale
        return fmt.string(from: date).prefix(2).uppercased()
    }
}

private struct NightCell: View {
    let record: SleepRecord
    let isLocalDisruption: Bool
    let isGlobalShift: Bool

    private var cellColor: Color {
        if isGlobalShift  { return SpiralColors.poor }
        if isLocalDisruption { return SpiralColors.moderate }
        return SpiralColors.good
    }

    private var hasBothIssues: Bool {
        isGlobalShift && isLocalDisruption
    }

    private var durationHeight: CGFloat {
        let clamped = min(max(record.sleepDuration, 0), 10)
        return 8 + CGFloat(clamped / 10) * 28
    }

    var body: some View {
        VStack(spacing: 2) {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 3)
                .fill(cellColor.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: durationHeight)
                .overlay(
                    // Yellow border when both global shift + local disruption
                    hasBothIssues ?
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(SpiralColors.moderate, lineWidth: 2)
                        : nil
                )
            Text(String(format: "%.1fh", record.sleepDuration))
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
        .frame(height: 50)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
        }
    }
}

// MARK: - Insight Detail Card

private struct InsightDetailCard: View {
    let insight: PatternInsight

    private var iconName: String {
        switch insight.type {
        case .local:  return "location.circle"
        case .global: return "arrow.triangle.2.circlepath"
        case .mixed:  return "exclamationmark.triangle"
        case .none:   return "checkmark.circle"
        }
    }

    private var accentColor: Color {
        switch insight.severity {
        case 3:     return SpiralColors.poor
        case 2:     return SpiralColors.moderate
        case 1:     return SpiralColors.accent
        default:    return SpiralColors.good
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.headline)
                .foregroundStyle(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(insight.summary)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.recommendedAction.isEmpty {
                    Text(insight.recommendedAction)
                        .font(.caption.monospaced())
                        .foregroundStyle(accentColor)
                        .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(accentColor.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(accentColor.opacity(0.2), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Legend Help Sheet

private struct ConsistencyLegendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    legendItem(
                        color: SpiralColors.good,
                        title: loc("consistency.help.normal.title"),
                        description: loc("consistency.help.normal.desc")
                    )
                    legendItem(
                        color: SpiralColors.moderate,
                        title: loc("consistency.help.local.title"),
                        description: loc("consistency.help.local.desc")
                    )
                    legendItem(
                        color: SpiralColors.poor,
                        title: loc("consistency.help.global.title"),
                        description: loc("consistency.help.global.desc")
                    )
                }
                .padding(20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("consistency.help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private func legendItem(color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(0.8))
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}

// MARK: - Preview Helpers

private func makeRecord(day: Int, daysAgo: Int, bedHour: Double, wakeHour: Double, duration: Double) -> SleepRecord {
    let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    let hourlyActivity = (0..<24).map { h -> HourlyActivity in
        let isAsleep = Double(h) >= bedHour || Double(h) < wakeHour
        return HourlyActivity(hour: h, activity: isAsleep ? 0.1 : 0.9)
    }
    return SleepRecord(
        day: day,
        date: date,
        isWeekend: daysAgo % 7 < 2,
        bedtimeHour: bedHour,
        wakeupHour: wakeHour,
        sleepDuration: duration,
        phases: [],
        hourlyActivity: hourlyActivity,
        cosinor: CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0.8)
    )
}

// MARK: - Preview

#Preview("Consistencia — Estable") {
    let records = [
        makeRecord(day: 0, daysAgo: 6, bedHour: 23.0, wakeHour: 7.0, duration: 8.0),
        makeRecord(day: 1, daysAgo: 5, bedHour: 23.2, wakeHour: 7.1, duration: 7.9),
        makeRecord(day: 2, daysAgo: 4, bedHour: 22.9, wakeHour: 6.9, duration: 8.0),
        makeRecord(day: 3, daysAgo: 3, bedHour: 23.1, wakeHour: 7.0, duration: 7.9),
        makeRecord(day: 4, daysAgo: 2, bedHour: 23.0, wakeHour: 7.0, duration: 8.0),
        makeRecord(day: 5, daysAgo: 1, bedHour: 23.3, wakeHour: 7.2, duration: 7.9),
        makeRecord(day: 6, daysAgo: 0, bedHour: 23.0, wakeHour: 7.0, duration: 8.0),
    ]
    let consistency = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
    return NavigationStack {
        ConsistencyDetailView(consistency: consistency, records: records)
    }
    .preferredColorScheme(.dark)
}

#Preview("Consistencia — Variable") {
    let records = [
        makeRecord(day: 0, daysAgo: 6, bedHour: 22.0, wakeHour: 6.0, duration: 8.0),
        makeRecord(day: 1, daysAgo: 5, bedHour: 00.5, wakeHour: 8.5, duration: 8.0),
        makeRecord(day: 2, daysAgo: 4, bedHour: 23.0, wakeHour: 5.5, duration: 6.5),
        makeRecord(day: 3, daysAgo: 3, bedHour: 01.0, wakeHour: 9.0, duration: 8.0),
        makeRecord(day: 4, daysAgo: 2, bedHour: 21.5, wakeHour: 5.0, duration: 7.5),
        makeRecord(day: 5, daysAgo: 1, bedHour: 02.0, wakeHour: 10.0, duration: 8.0),
        makeRecord(day: 6, daysAgo: 0, bedHour: 23.5, wakeHour: 7.0, duration: 7.5),
    ]
    let consistency = SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
    return NavigationStack {
        ConsistencyDetailView(consistency: consistency, records: records)
    }
    .preferredColorScheme(.dark)
}

// MARK: - Temporal Impact Help Sheet

private struct TemporalImpactHelpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpItem(
                        icon: "waveform.path",
                        title: loc("temporal.help.what.title"),
                        body: loc("temporal.help.what.body")
                    )
                    helpItem(
                        icon: "function",
                        title: loc("temporal.help.how.title"),
                        body: loc("temporal.help.how.body")
                    )
                    helpItem(
                        icon: "clock.arrow.2.circlepath",
                        title: loc("temporal.help.delay.title"),
                        body: loc("temporal.help.delay.body")
                    )
                    Text(loc("temporal.help.disclaimer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("temporal.help.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private func helpItem(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
