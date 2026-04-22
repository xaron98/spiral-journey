import Foundation
import SwiftUI
import SpiralKit

/// Adapter that converts SpiralStore state into plain structs the new
/// Coach views can render. Keep this free of SwiftUI View types so it's
/// trivially testable.
/// Pure read-only data transformer. Views create a fresh instance per
/// body eval — invalidation is driven by the observed `SpiralStore` in
/// the environment, not by this class.
struct CoachDataAdapter {

    // MARK: - Output structs

    struct HeroData {
        let score: Int                // 0...100, composite
        let todayLabel: String        // "ESTA NOCHE"
        let insightTitle: String      // "Tu ritmo pide constancia"
        let last7Bars: [Double]       // 0...1 durations normalized
        let last7Subtitle: String     // "7 NOCHES · -1.2h MEDIA"
        let accent: Color             // purple / yellow / green
    }

    struct BentoData {
        let durationValue: String     // "4.5h"
        let durationSub: String       // "anoche · -1.2h"
        let durationSeries: [Double]  // 7 points bedtime lateness
        let consistencyValue: String  // "32"
        let consistencySub: String    // "/100 · irregular"
        let consistencyBars: [Double] // 0...1 (SRI daily)
        let patternsValue: String     // "3 tardes" or "estable"
        let patternsSub: String
        let habitValue: String        // "5"
        let habitSub: String          // "días seguidos"
        let habitStripes: [Bool]      // 7 days L-M-X-J-V-S-D
    }

    struct ProposalData {
        let title: String             // "Esta noche, antes de la 01:30."
        let window: String            // "01:15 – 01:45"
        let chronotypeSub: String     // "Cronotipo: nocturno moderado"
        let dialStart: Double         // hours 0..24
        let dialEnd: Double
    }

    struct ChangeData {
        let headline: String          // "Te acuestas 1h 47m más tarde..."
        let highlightedFragment: String  // "1h 47m más tarde"
        let sparkValues: [Double]
        let rangeLabel: String        // "00:00 → 03:00"
    }

    struct LearnData {
        let title: String
        let subtitle: String          // "Lectura breve"
    }

    // MARK: - Inputs

    let store: SpiralStore

    init(store: SpiralStore) { self.store = store }

    // MARK: - Derived

    var hero: HeroData {
        let score = store.analysis.composite
        let durations = lastNDurations(n: 7)
        let mean = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
        let yesterday = durations.last ?? mean
        let diff = yesterday - mean
        let diffStr = String(format: "%+0.1fh", diff)
        return HeroData(
            score: score,
            todayLabel: "ESTA NOCHE",
            insightTitle: store.analysis.coachInsight?.title ?? "Tu ritmo pide constancia",
            last7Bars: normalizeBars(durations),
            last7Subtitle: "7 NOCHES · \(diffStr) MEDIA",
            accent: CoachTokens.accent(forScore: score))
    }

    var bento: BentoData {
        let durations = lastNDurations(n: 7)
        let bedtimes = lastNBedtimeLatenessNorm(n: 7)
        let sri = store.analysis.stats.sri
        let sriDaily = lastNSRIDaily(n: 7)
        let streak = store.analysis.enhancedCoach?.streak.currentStreak ?? 0
        let habitStripes = lastNHabitCompleted(n: 7)
        let patterns = store.analysis.enhancedCoach?.temporalPatterns.count ?? 0
        return BentoData(
            durationValue: String(format: "%.1fh", durations.last ?? 0),
            durationSub: durationSubtitle(durations: durations),
            durationSeries: bedtimes,
            consistencyValue: "\(Int(sri))",
            consistencySub: "/100 · \(sriLabel(sri))",
            consistencyBars: sriDaily,
            patternsValue: patterns > 0 ? "\(patterns) patrones" : "estable",
            patternsSub: patterns > 0 ? "esta semana" : "sin cambios",
            habitValue: "\(streak)",
            habitSub: "días seguidos",
            habitStripes: habitStripes)
    }

    var proposal: ProposalData? {
        // Optimal window from chronotype's ideal bed range.
        guard let chrono = store.chronotypeResult?.chronotype else { return nil }
        let (start, end) = chrono.idealBedRange
        let mid = (start + end) / 2.0
        let hh = Int(mid) % 24
        let mm = Int((mid - Double(Int(mid))) * 60)
        return ProposalData(
            title: "Esta noche, antes de la \(String(format: "%02d:%02d", hh, mm)).",
            window: "\(formatHour(start)) – \(formatHour(end))",
            chronotypeSub: "Cronotipo: \(chronotypeLabelEs(chrono))",
            dialStart: start, dialEnd: end)
    }

    var change: ChangeData {
        let durations = lastNDurations(n: 7)
        let lastThree = Array(durations.suffix(3))
        let firstThree = Array(durations.prefix(3))
        let deltaThis = lastThree.isEmpty ? 0 : lastThree.reduce(0, +) / Double(lastThree.count)
        let deltaPrev = firstThree.isEmpty ? 0 : firstThree.reduce(0, +) / Double(firstThree.count)
        let diffMin = Int((deltaThis - deltaPrev) * 60)
        let absMin = abs(diffMin)
        let label = diffMin < 0
            ? "\(absMin / 60)h \(absMin % 60)m más tarde"
            : "\(diffMin / 60)h \(diffMin % 60)m antes"
        return ChangeData(
            headline: "Te acuestas \(label) que la semana pasada.",
            highlightedFragment: label,
            sparkValues: normalizeBars(durations).map { 1 - $0 },
            rangeLabel: "00:00 → 03:00")
    }

    var learn: LearnData {
        LearnData(
            title: "Jet lag social: por qué el domingo te pasa factura el martes",
            subtitle: "Lectura breve")
    }

    // MARK: - Helpers

    private func lastNDurations(n: Int) -> [Double] {
        let eps = store.sleepEpisodes.suffix(n)
        return eps.map { $0.duration }
    }

    /// Maps episode start hour to a 0..1 lateness score.
    /// 0 = 22:00 (early), 1 = 04:00 (late). Anything outside wraps sensibly.
    private func lastNBedtimeLatenessNorm(n: Int) -> [Double] {
        let eps = store.sleepEpisodes.suffix(n)
        return eps.map { ep in
            // ep.start is absolute hours from epoch day 0 — take clock hour.
            let clock = ep.start.truncatingRemainder(dividingBy: 24)
            // Map 22 → 0, 28 (= 04 next day) → 1.
            let shifted = clock >= 18 ? clock - 22 : clock + 2
            return min(max(shifted / 6.0, 0), 1)
        }
    }

    /// Approximate per-day consistency score by proximity to personal mean.
    private func lastNSRIDaily(n: Int) -> [Double] {
        let durations = lastNDurations(n: n)
        guard !durations.isEmpty else { return Array(repeating: 0.5, count: n) }
        let mean = durations.reduce(0, +) / Double(durations.count)
        guard mean > 0 else { return Array(repeating: 0.5, count: durations.count) }
        return durations.map { 1 - min(abs($0 - mean) / mean, 1) }
    }

    private func lastNHabitCompleted(n: Int) -> [Bool] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (0..<n).map { offset in
            guard let date = cal.date(byAdding: .day, value: -(n - 1 - offset), to: today)
            else { return false }
            let dayComp = cal.component(.day, from: date)
            return store.microHabitCompletions.contains { key, value in
                value && key.contains("\(dayComp)")
            }
        }
    }

    private func normalizeBars(_ values: [Double]) -> [Double] {
        guard let maxV = values.max(), maxV > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / maxV }
    }

    private func durationSubtitle(durations: [Double]) -> String {
        guard let last = durations.last, durations.count >= 2 else {
            return "anoche"
        }
        let mean = durations.dropLast().reduce(0, +) / Double(durations.count - 1)
        let diff = last - mean
        return String(format: "anoche · %+0.1fh", diff)
    }

    private func sriLabel(_ sri: Double) -> String {
        switch sri {
        case ...40: return "irregular"
        case 41...60: return "variable"
        case 61...80: return "consistente"
        default: return "sólido"
        }
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        let safeHH = (hh + 24) % 24
        let safeMM = (mm + 60) % 60
        return String(format: "%02d:%02d", safeHH, safeMM)
    }

    private func chronotypeLabelEs(_ c: Chronotype) -> String {
        switch c {
        case .definiteMorning:  return "matutino definido"
        case .moderateMorning:  return "matutino moderado"
        case .intermediate:     return "intermedio"
        case .moderateEvening:  return "nocturno moderado"
        case .definiteEvening:  return "nocturno definido"
        }
    }
}
