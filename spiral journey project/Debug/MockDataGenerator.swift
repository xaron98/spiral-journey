import Foundation
import SpiralKit

#if targetEnvironment(simulator)

/// Generates realistic mock sleep data for App Store screenshots.
/// Episodes include HealthKit-style sleep phases (deep, REM, light, awake).
/// Only compiled in the simulator — zero impact on production builds.
enum MockDataGenerator {

    /// Generate 7 nights of realistic sleep with phases.
    /// Returns (startDate, episodes, events).
    static func generate() -> (startDate: Date, episodes: [SleepEpisode], events: [CircadianEvent]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        // Start 7 days ago
        let startDate = calendar.date(byAdding: .day, value: -7, to: today)!

        var episodes: [SleepEpisode] = []
        var events: [CircadianEvent] = []

        // 7 nights of sleep data — slightly variable but consistent
        let nights: [(bedH: Double, wakeH: Double, isWeekend: Bool)] = [
            (23.2, 7.1, false),   // day 0 Mon — bed 23:12, wake 07:06
            (23.5, 7.3, false),   // day 1 Tue
            (23.0, 6.8, false),   // day 2 Wed
            (23.8, 7.5, false),   // day 3 Thu
            (0.5,  8.2, true),    // day 4 Fri→Sat (late night)
            (1.0,  9.0, true),    // day 5 Sat→Sun (latest)
            (23.3, 7.0, false),   // day 6 Sun — back to normal
        ]

        for (dayIndex, night) in nights.enumerated() {
            let dayAbsStart = Double(dayIndex) * 24.0
            let bedAbs = dayAbsStart + night.bedH
            let wakeAbs = dayAbsStart + night.wakeH + (night.bedH >= 24.0 ? 0 : 24.0)
            // Adjust: if bedH < 12, it's already next day
            let actualBedAbs = night.bedH < 12 ? dayAbsStart + night.bedH + 24.0 : dayAbsStart + night.bedH
            let actualWakeAbs = actualBedAbs + (night.wakeH < night.bedH ? night.wakeH + 24.0 - night.bedH : night.wakeH - night.bedH)

            // Generate phase breakdown for this night
            let phaseEpisodes = generatePhases(
                bedAbs: actualBedAbs,
                wakeAbs: actualWakeAbs,
                dayIndex: dayIndex
            )
            episodes.append(contentsOf: phaseEpisodes)

            // Add some circadian events
            // Caffeine in the morning
            let caffeineHour = dayAbsStart + Double.random(in: 8.0...9.5)
            events.append(CircadianEvent(
                type: .caffeine,
                absoluteHour: caffeineHour
            ))

            // Exercise on some days
            if dayIndex % 2 == 0 {
                let exerciseHour = dayAbsStart + Double.random(in: 17.0...19.0)
                events.append(CircadianEvent(
                    type: .exercise,
                    absoluteHour: exerciseHour
                ))
            }

            // Light exposure morning
            let lightHour = dayAbsStart + Double.random(in: 7.5...9.0)
            events.append(CircadianEvent(
                type: .light,
                absoluteHour: lightHour
            ))

            // Siesta on some days (20-40 min, early afternoon)
            if dayIndex == 1 || dayIndex == 3 || dayIndex == 5 {
                let napStart = dayAbsStart + Double.random(in: 14.0...15.0)
                let napDuration = Double.random(in: 0.33...0.67) // 20-40 min
                let napEnd = napStart + napDuration
                // Naps are mostly light sleep with a bit of deep
                let lightEnd = napStart + napDuration * 0.7
                episodes.append(SleepEpisode(
                    start: napStart, end: lightEnd,
                    source: .healthKit,
                    healthKitSampleID: "mock-nap-\(dayIndex)-light",
                    phase: .light
                ))
                episodes.append(SleepEpisode(
                    start: lightEnd, end: napEnd,
                    source: .healthKit,
                    healthKitSampleID: "mock-nap-\(dayIndex)-deep",
                    phase: .deep
                ))
            }
        }

        events.sort { $0.absoluteHour < $1.absoluteHour }
        return (startDate, episodes, events)
    }

    // MARK: - Phase generation

    /// Generate realistic sleep phase episodes for one night.
    /// Follows typical sleep architecture:
    /// - First cycle: mostly deep + light
    /// - Middle cycles: deep decreases, REM increases
    /// - Last cycle: mostly REM + light
    /// - Brief awakenings between cycles
    private static func generatePhases(bedAbs: Double, wakeAbs: Double, dayIndex: Int) -> [SleepEpisode] {
        let totalHours = wakeAbs - bedAbs
        guard totalHours > 0 else { return [] }

        var result: [SleepEpisode] = []
        var cursor = bedAbs

        // Sleep cycles (~90 min each)
        let cycleCount = max(3, Int(totalHours / 1.5))

        for cycle in 0..<cycleCount {
            let remaining = wakeAbs - cursor
            guard remaining > 0.25 else { break }

            let cycleLen = min(remaining, Double.random(in: 1.3...1.7))
            let progress = Double(cycle) / Double(max(cycleCount - 1, 1))

            // Phase distribution shifts across the night:
            // Early: more deep, less REM
            // Late: less deep, more REM
            let deepFrac  = max(0.05, 0.35 * (1.0 - progress * 0.8))
            let remFrac   = min(0.40, 0.10 + progress * 0.30)
            let awakeFrac = 0.03  // brief arousal
            let lightFrac = 1.0 - deepFrac - remFrac - awakeFrac

            // Order within cycle: light → deep → light → REM → (brief awake)
            let phases: [(SleepPhase, Double)] = [
                (.light, lightFrac * 0.4),
                (.deep,  deepFrac),
                (.light, lightFrac * 0.6),
                (.rem,   remFrac),
                (.awake, awakeFrac),
            ]

            for (phase, frac) in phases {
                let dur = cycleLen * frac
                guard dur > 0.05 else { continue }
                let end = min(cursor + dur, wakeAbs)
                result.append(SleepEpisode(
                    start: cursor,
                    end: end,
                    source: .healthKit,
                    healthKitSampleID: "mock-\(dayIndex)-\(cycle)-\(phase.rawValue)",
                    phase: phase
                ))
                cursor = end
            }
        }

        // Fill any remaining gap as light sleep
        if cursor < wakeAbs - 0.05 {
            result.append(SleepEpisode(
                start: cursor,
                end: wakeAbs,
                source: .healthKit,
                healthKitSampleID: "mock-\(dayIndex)-tail-light",
                phase: .light
            ))
        }

        return result
    }
}

#endif
