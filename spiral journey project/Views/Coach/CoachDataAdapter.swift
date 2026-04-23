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
    /// Localization bundle forwarded from the view environment. Defaults
    /// to `.main` so existing unit tests and plain-SwiftUI call sites
    /// keep working, but the Coach views pass `bundle` from
    /// `@Environment(\.languageBundle)` so in-app language override
    /// (which lives outside the system locale) resolves correctly.
    let bundle: Bundle

    init(store: SpiralStore, bundle: Bundle = .main) {
        self.store = store
        self.bundle = bundle
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

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
            todayLabel: loc("coach.hero.tonight"),
            insightTitle: localizedInsightTitle(),
            last7Bars: normalizeBars(durations),
            last7Subtitle: String(format: loc("coach.hero.last7Subtitle"), diffStr),
            accent: CoachTokens.accent(forScore: score))
    }

    /// CoachEngine produces titles as English fallback strings and
    /// stores the stable issueKey alongside. Resolve the key through
    /// `Localizable.xcstrings` (`coach.issue.<issueKey>.title`) so the
    /// hero bento shows the current locale's text instead of the raw
    /// English fallback the engine emits.
    private func localizedInsightTitle() -> String {
        let fallback = loc("coach.hero.insight.fallback")
        guard let insight = store.analysis.coachInsight else { return fallback }
        let key = "coach.issue.\(insight.issueKey.rawValue).title"
        let resolved = bundle.localizedString(forKey: key, value: insight.title, table: nil)
        // If the key is missing from the strings catalog, Foundation
        // echoes the key back unchanged — detect that and fall back to
        // the engine's English title so we never surface a raw key.
        if resolved == key { return insight.title }
        return resolved
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
            patternsValue: patterns > 0
                ? String(format: loc("coach.bento.patterns.count"), patterns)
                : loc("coach.bento.patterns.stable"),
            patternsSub: patterns > 0
                ? loc("coach.bento.patterns.thisWeek")
                : loc("coach.bento.patterns.noChanges"),
            habitValue: "\(streak)",
            habitSub: loc("coach.bento.habit.streak"),
            habitStripes: habitStripes)
    }

    var proposal: ProposalData? {
        // Optimal window from chronotype's ideal bed range.
        guard let chrono = store.chronotypeResult?.chronotype else { return nil }
        let (start, end) = chrono.idealBedRange
        let mid = (start + end) / 2.0
        let hh = Int(mid) % 24
        let mm = Int((mid - Double(Int(mid))) * 60)
        let midStr = String(format: "%02d:%02d", hh, mm)
        return ProposalData(
            title: String(format: loc("coach.proposal.title"), midStr),
            window: "\(formatHour(start)) – \(formatHour(end))",
            chronotypeSub: String(format: loc("coach.proposal.chronotypeSub"),
                                  chronotypeLocalizedLabel(chrono)),
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
        let labelFormat = diffMin < 0
            ? loc("coach.change.label.later")
            : loc("coach.change.label.earlier")
        let label = String(format: labelFormat, absMin / 60, absMin % 60)
        return ChangeData(
            headline: String(format: loc("coach.change.headline"), label),
            highlightedFragment: label,
            sparkValues: normalizeBars(durations).map { 1 - $0 },
            rangeLabel: "00:00 → 03:00")
    }

    var learn: LearnData {
        LearnData(
            title: loc("coach.learn.title"),
            subtitle: loc("coach.learn.subtitle"))
    }

    // MARK: - Helpers

    private func lastNDurations(n: Int) -> [Double] {
        let eps = store.sleepEpisodes.suffix(n)
        return eps.map { $0.duration }
    }

    /// Maps episode start hour to a 0..1 lateness score.
    /// 0 = 22:00 (early), 1 = 04:00 (late). Anything outside wraps sensibly.
    // internal for testing
    func lastNBedtimeLatenessNorm(n: Int) -> [Double] {
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

    // internal for testing
    func normalizeBars(_ values: [Double]) -> [Double] {
        guard let maxV = values.max(), maxV > 0 else { return values.map { _ in 0 } }
        return values.map { $0 / maxV }
    }

    private func durationSubtitle(durations: [Double]) -> String {
        guard let last = durations.last, durations.count >= 2 else {
            return loc("coach.bento.duration.lastNight")
        }
        let mean = durations.dropLast().reduce(0, +) / Double(durations.count - 1)
        let diff = last - mean
        return String(format: loc("coach.bento.duration.lastNightDelta"), diff)
    }

    // internal for testing
    func sriLabel(_ sri: Double) -> String {
        let key: String
        switch sri {
        case ...40:   key = "coach.sri.label.irregular"
        case 41...60: key = "coach.sri.label.variable"
        case 61...80: key = "coach.sri.label.consistent"
        default:      key = "coach.sri.label.solid"
        }
        return loc(key)
    }

    // internal for testing
    func formatHour(_ h: Double) -> String {
        let hh = Int(h), mm = Int((h - Double(hh)) * 60)
        let safeHH = (hh + 24) % 24
        let safeMM = (mm + 60) % 60
        return String(format: "%02d:%02d", safeHH, safeMM)
    }

    // internal for testing
    func chronotypeLabelEs(_ c: Chronotype) -> String {
        // Preserved for test compatibility — production code now routes
        // through `chronotypeLocalizedLabel` so the label follows the
        // user's language selection, not a hard-coded Spanish literal.
        switch c {
        case .definiteMorning:  return "matutino definido"
        case .moderateMorning:  return "matutino moderado"
        case .intermediate:     return "intermedio"
        case .moderateEvening:  return "nocturno moderado"
        case .definiteEvening:  return "nocturno definido"
        }
    }

    /// Localized chronotype label using the existing `chronotype.result.*`
    /// keys from the app xcstrings (same keys the questionnaire result
    /// screen and settings row already use).
    private func chronotypeLocalizedLabel(_ c: Chronotype) -> String {
        let key = "chronotype.result.\(c.rawValue)"
        return bundle.localizedString(forKey: key, value: c.label, table: nil)
    }
}
