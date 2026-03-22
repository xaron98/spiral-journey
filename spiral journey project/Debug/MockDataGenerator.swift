import Foundation
import SpiralKit

#if targetEnvironment(simulator)

/// Generates realistic mock sleep data for App Store screenshots.
/// Episodes include HealthKit-style sleep phases (deep, REM, light, awake).
/// Only compiled in the simulator — zero impact on production builds.
enum MockDataGenerator {

    /// Generate 10 weeks of varied sleep data with distinct patterns.
    /// Returns (startDate, episodes, events).
    static func generate() -> (startDate: Date, episodes: [SleepEpisode], events: [CircadianEvent]) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let totalWeeks = 10
        let totalDays = totalWeeks * 7
        let startDate = calendar.date(byAdding: .day, value: -totalDays, to: today)!

        var episodes: [SleepEpisode] = []
        var events: [CircadianEvent] = []

        // 10 weeks with 3 distinct patterns:
        // Pattern A "early-bird": bed ~22:30, wake ~6:30, exercise, no caffeine late
        // Pattern B "night-owl": bed ~01:30, wake ~9:30, caffeine late, no exercise
        // Pattern C "stressed": bed ~00:00, wake ~7:00, high stress, alcohol, fragmented
        //
        // Week assignment: A, A, B, A, C, B, A, C, B, A
        // This ensures motif discovery finds 3 clusters
        let weekPatterns: [Character] = ["A", "A", "B", "A", "C", "B", "A", "C", "B", "A"]

        for dayIndex in 0..<totalDays {
            let weekIndex = dayIndex / 7
            let dayOfWeek = dayIndex % 7
            let pattern = weekPatterns[weekIndex]
            let dayAbsStart = Double(dayIndex) * 24.0
            let isWeekend = dayOfWeek >= 5

            let (bedH, wakeH, variation) = nightParams(
                pattern: pattern,
                dayOfWeek: dayOfWeek,
                isWeekend: isWeekend
            )

            // Calculate absolute hours
            let actualBedAbs: Double
            if bedH >= 24.0 {
                actualBedAbs = dayAbsStart + bedH
            } else if bedH < 12 {
                actualBedAbs = dayAbsStart + bedH + 24.0
            } else {
                actualBedAbs = dayAbsStart + bedH
            }
            let sleepDuration = wakeH < bedH ? (wakeH + 24.0 - bedH) : (wakeH - bedH)
            let actualWakeAbs = actualBedAbs + sleepDuration

            // Generate phases with pattern-specific architecture
            let phaseEpisodes = generatePhases(
                bedAbs: actualBedAbs,
                wakeAbs: actualWakeAbs,
                dayIndex: dayIndex,
                pattern: pattern
            )
            episodes.append(contentsOf: phaseEpisodes)

            // Events based on pattern
            generateEvents(
                pattern: pattern,
                dayAbsStart: dayAbsStart,
                dayIndex: dayIndex,
                isWeekend: isWeekend,
                events: &events
            )

            // Nap on some days
            if dayIndex % 3 == 1 {
                let napStart = dayAbsStart + Double.random(in: 14.0...15.0)
                let napDuration = Double.random(in: 0.33...0.67)
                let napEnd = napStart + napDuration
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

    // MARK: - Pattern-specific parameters

    private static func nightParams(
        pattern: Character,
        dayOfWeek: Int,
        isWeekend: Bool
    ) -> (bedH: Double, wakeH: Double, variation: Double) {
        let jitter = Double.random(in: -0.3...0.3)

        switch pattern {
        case "A": // Early bird — very early, consistent
            let bed = (isWeekend ? 21.5 : 21.0) + jitter
            let wake = (isWeekend ? 6.0 : 5.5) + jitter
            return (bed, wake, 0.1)

        case "B": // Night owl — very late, long sleep
            let bed = (isWeekend ? 3.5 : 3.0) + jitter
            let wake = (isWeekend ? 12.0 : 11.0) + jitter
            return (bed, wake, 0.15)

        case "C": // Stressed / irregular — short sleep, variable
            let bed = Double.random(in: 25.0...27.0) + jitter  // 01:00-03:00
            let wake = Double.random(in: 6.0...7.0) + jitter   // only 3-6h sleep
            return (bed, wake, 0.3)

        default:
            return (23.0, 7.0, 0.1)
        }
    }

    private static func generateEvents(
        pattern: Character,
        dayAbsStart: Double,
        dayIndex: Int,
        isWeekend: Bool,
        events: inout [CircadianEvent]
    ) {
        switch pattern {
        case "A": // Early bird — morning caffeine only, daily exercise, lots of light
            events.append(CircadianEvent(
                type: .caffeine,
                absoluteHour: dayAbsStart + Double.random(in: 6.0...7.0)
            ))
            events.append(CircadianEvent(
                type: .exercise,
                absoluteHour: dayAbsStart + Double.random(in: 6.0...7.5),
                durationHours: Double.random(in: 1.0...1.5)
            ))
            events.append(CircadianEvent(
                type: .light,
                absoluteHour: dayAbsStart + Double.random(in: 6.0...8.0),
                durationHours: Double.random(in: 1.5...3.0)
            ))

        case "B": // Night owl — 3-4 caffeine, no exercise, melatonin, no light
            for _ in 0..<Int.random(in: 3...4) {
                events.append(CircadianEvent(
                    type: .caffeine,
                    absoluteHour: dayAbsStart + Double.random(in: 12.0...22.0)
                ))
            }
            events.append(CircadianEvent(
                type: .melatonin,
                absoluteHour: dayAbsStart + Double.random(in: 25.0...26.0)
            ))

        case "C": // Stressed — max stress, alcohol daily, caffeine, no exercise
            for _ in 0..<Int.random(in: 2...3) {
                events.append(CircadianEvent(
                    type: .caffeine,
                    absoluteHour: dayAbsStart + Double.random(in: 8.0...18.0)
                ))
            }
            for _ in 0..<Int.random(in: 2...3) {
                events.append(CircadianEvent(
                    type: .stress,
                    absoluteHour: dayAbsStart + Double.random(in: 10.0...22.0)
                ))
            }
            events.append(CircadianEvent(
                type: .alcohol,
                absoluteHour: dayAbsStart + Double.random(in: 20.0...23.0)
            ))
            events.append(CircadianEvent(
                type: .alcohol,
                absoluteHour: dayAbsStart + Double.random(in: 21.0...24.0)
            ))

        default:
            break
        }
    }

    // MARK: - Phase generation

    /// Generate realistic sleep phase episodes for one night.
    /// Pattern affects sleep architecture:
    /// - "A" (early-bird): more deep sleep, less fragmentation
    /// - "B" (night-owl): more REM, shifted cycles
    /// - "C" (stressed): more awakenings, less deep sleep
    private static func generatePhases(
        bedAbs: Double, wakeAbs: Double,
        dayIndex: Int, pattern: Character
    ) -> [SleepEpisode] {
        let totalHours = wakeAbs - bedAbs
        guard totalHours > 0 else { return [] }

        var result: [SleepEpisode] = []
        var cursor = bedAbs

        let cycleCount = max(3, Int(totalHours / 1.5))

        for cycle in 0..<cycleCount {
            let remaining = wakeAbs - cursor
            guard remaining > 0.25 else { break }

            let cycleLen = min(remaining, Double.random(in: 1.3...1.7))
            let progress = Double(cycle) / Double(max(cycleCount - 1, 1))

            let (deepFrac, remFrac, awakeFrac): (Double, Double, Double)

            switch pattern {
            case "A": // Good sleeper — more deep, minimal awakenings
                deepFrac  = max(0.08, 0.40 * (1.0 - progress * 0.7))
                remFrac   = min(0.35, 0.10 + progress * 0.25)
                awakeFrac = 0.02

            case "B": // Night owl — more REM, less deep
                deepFrac  = max(0.05, 0.25 * (1.0 - progress * 0.8))
                remFrac   = min(0.45, 0.15 + progress * 0.35)
                awakeFrac = 0.03

            case "C": // Stressed — fragmented, less deep, more awakenings
                deepFrac  = max(0.03, 0.20 * (1.0 - progress * 0.9))
                remFrac   = min(0.30, 0.08 + progress * 0.20)
                awakeFrac = Double.random(in: 0.05...0.12)

            default:
                deepFrac  = 0.25
                remFrac   = 0.20
                awakeFrac = 0.03
            }

            let lightFrac = max(0.1, 1.0 - deepFrac - remFrac - awakeFrac)

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
