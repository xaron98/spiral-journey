import SwiftUI
import SpiralKit

/// Full-screen detail view for Spiral Consistency Score.
/// Accessed by tapping the consistency score card in SpiralTab.
struct ConsistencyDetailView: View {

    let consistency: SpiralConsistencyScore
    let records: [SleepRecord]

    @Environment(\.dismiss) private var dismiss

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
        .navigationTitle("Consistencia")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                        Color(hex: consistency.label.hexColor),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: consistency.score)

                VStack(spacing: 2) {
                    Text("\(consistency.score)")
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color(hex: consistency.label.hexColor))
                    Text(consistency.label.displayText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(SpiralColors.muted)
                }
            }

            // Confidence + nights used
            HStack(spacing: 8) {
                confidenceBadge
                Text("\(consistency.nightsUsed) noches")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(cardBackground)
    }

    private var confidenceBadge: some View {
        let (label, color): (String, Color) = switch consistency.confidence {
        case .high:   ("Alta confianza",  Color(hex: "5bffa8"))
        case .medium: ("Confianza media", Color(hex: "f5c842"))
        case .low:    ("Pocos datos",     Color(hex: "f05050"))
        }
        return Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: - Breakdown

    private var breakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Desglose de métricas")

            VStack(spacing: 8) {
                BreakdownRow(
                    label: "Hora de dormir",
                    value: consistency.breakdown.sleepOnsetRegularity,
                    weight: "30%"
                )
                BreakdownRow(
                    label: "Hora de despertar",
                    value: consistency.breakdown.wakeTimeRegularity,
                    weight: "25%"
                )
                BreakdownRow(
                    label: "Patrón de fragmentación",
                    value: consistency.breakdown.fragmentationPatternSimilarity,
                    weight: "25%"
                )
                BreakdownRow(
                    label: "Duración del sueño",
                    value: consistency.breakdown.sleepDurationStability,
                    weight: "10%"
                )

                let recLabel = consistency.breakdown.recoveryFromRealData
                    ? "Recuperación (HRV/FC)"
                    : "Recuperación (proxy)"
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
            sectionHeader("Últimas \(consistency.nightsUsed) noches")

            if nights.isEmpty {
                Text("Sin datos disponibles")
                    .font(.system(size: 12))
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
            sectionHeader("Insights detectados")

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
            sectionHeader("Esta semana vs semana anterior")

            HStack(spacing: 0) {
                // Current week
                weekBlock(label: "Esta semana", score: consistency.score, isCurrent: true)

                // Arrow + delta
                VStack(spacing: 4) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(delta >= 0 ? Color(hex: "5bffa8") : Color(hex: "f05050"))
                    Text(String(format: "%+.0f", delta))
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(delta >= 0 ? Color(hex: "5bffa8") : Color(hex: "f05050"))
                }
                .frame(maxWidth: .infinity)

                // Previous week
                let prevScore = max(0, min(100, consistency.score - Int(delta)))
                weekBlock(label: "Semana anterior", score: prevScore, isCurrent: false)
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private func weekBlock(label: String, score: Int, isCurrent: Bool) -> some View {
        let scoreLabel = ConsistencyLabel.from(score: score)
        return VStack(spacing: 6) {
            Text("\(score)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(isCurrent ? Color(hex: consistency.label.hexColor) : SpiralColors.muted)
            Text(scoreLabel.displayText)
                .font(.system(size: 10))
                .foregroundStyle(SpiralColors.muted)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

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
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                    .font(.system(size: 12))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text(weight)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                Text(String(format: "%.0f", value))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
        if v >= 70 { return Color(hex: "5bffa8") }
        if v >= 50 { return Color(hex: "f5c842") }
        return Color(hex: "f05050")
    }
}

// MARK: - Weekly Night Grid

private struct WeeklyNightGrid: View {
    let nights: [SleepRecord]
    let localDisruptionDays: [Int]
    let globalShiftDays: [Int]

    var body: some View {
        VStack(spacing: 6) {
            // Header row: day labels
            HStack(spacing: 4) {
                ForEach(Array(nights.enumerated()), id: \.offset) { idx, record in
                    VStack(spacing: 3) {
                        Text(dayLabel(record.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                            .frame(maxWidth: .infinity)

                        NightCell(
                            record: record,
                            isLocalDisruption: localDisruptionDays.contains(nights.count - 1 - idx),
                            isGlobalShift: globalShiftDays.contains(nights.count - 1 - idx)
                        )
                    }
                }
            }

            // Legend
            HStack(spacing: 12) {
                LegendDot(color: Color(hex: "5bffa8"), label: "Normal")
                LegendDot(color: Color(hex: "f5c842"), label: "Disrupción local")
                LegendDot(color: Color(hex: "f05050"), label: "Cambio global")
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EE"
        fmt.locale = Locale(identifier: "es")
        return fmt.string(from: date).prefix(2).uppercased()
    }
}

private struct NightCell: View {
    let record: SleepRecord
    let isLocalDisruption: Bool
    let isGlobalShift: Bool

    private var cellColor: Color {
        if isGlobalShift  { return Color(hex: "f05050") }
        if isLocalDisruption { return Color(hex: "f5c842") }
        return Color(hex: "5bffa8")
    }

    private var durationHeight: CGFloat {
        // Map 0–10h → 8–36 pt
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
            Text(String(format: "%.1fh", record.sleepDuration))
                .font(.system(size: 7, design: .monospaced))
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
                .font(.system(size: 9))
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
        case 3:     return Color(hex: "f05050")
        case 2:     return Color(hex: "f5c842")
        case 1:     return Color(hex: "a78bfa")
        default:    return Color(hex: "5bffa8")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 18))
                .foregroundStyle(accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SpiralColors.text)
                Text(insight.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if !insight.recommendedAction.isEmpty {
                    Text(insight.recommendedAction)
                        .font(.system(size: 11, design: .monospaced))
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
