import Foundation

/// Two-Process Model of Sleep Regulation (Borbely, 1982).
///
/// Process S (Homeostatic): Sleep pressure builds during wake, dissipates during sleep.
/// Process C (Circadian): ~24h oscillation from SCN, modulates alertness.
///
/// Port of src/utils/twoProcess.js from the Spiral Journey web project.
/// References:
///   - Borbely (1982). A two process model of sleep regulation.
///   - Daan, Beersma, Borbely (1984). Timing of human sleep.
public enum TwoProcessModel {

    private static let tauRise = 18.2  // hours — S buildup time constant during wake
    private static let tauFall = 4.2   // hours — S decay time constant during sleep

    // MARK: - Core Functions

    /// Compute Process S (homeostatic sleep pressure).
    /// - Parameters:
    ///   - hoursSinceTransition: Hours elapsed since last sleep/wake transition
    ///   - isAwake: Whether currently in wake state
    ///   - s0: S value at the transition point
    /// - Returns: Current S value (0-1 range)
    public static func processS(hoursSinceTransition: Double, isAwake: Bool, s0: Double = 0.2) -> Double {
        if isAwake {
            // Saturating exponential rise toward 1
            return 1 - (1 - s0) * exp(-hoursSinceTransition / tauRise)
        }
        // Exponential decay toward 0
        return s0 * exp(-hoursSinceTransition / tauFall)
    }

    /// Compute Process C (circadian) from cosinor parameters.
    public static func processC(hour: Double, cosinor: CosinorResult) -> Double {
        let omega = (2 * Double.pi) / cosinor.period
        return cosinor.mesor + cosinor.amplitude * cos(omega * (hour - cosinor.acrophase))
    }

    // MARK: - Full Computation

    public struct TwoProcessPoint: Sendable {
        public let day: Int
        public let hour: Int
        public let s: Double
        public let c: Double
        public let isAwake: Bool
    }

    /// Compute S and C values for all hours across all days.
    public static func compute(_ records: [SleepRecord]) -> [TwoProcessPoint] {
        var result: [TwoProcessPoint] = []

        for d in 0..<records.count {
            let dayData = records[d]

            for h in 0..<24 {
                let actEntry = dayData.hourlyActivity.first { $0.hour == h }
                let isAwake = actEntry.map { $0.activity >= 0.2 } ?? true

                let transition: Double
                if isAwake {
                    let wakeup = dayData.wakeupHour
                    transition = h >= Int(wakeup) ? Double(h) - wakeup : Double(h) + 24 - wakeup
                } else {
                    let bedtime = dayData.bedtimeHour
                    transition = h >= Int(bedtime) ? Double(h) - bedtime : Double(h) + 24 - bedtime
                }
                let clamped = max(0, min(24, transition))
                let s0 = isAwake ? 0.15 : 0.85

                let s = processS(hoursSinceTransition: clamped, isAwake: isAwake, s0: s0)
                let c = processC(hour: Double(h), cosinor: dayData.cosinor)

                result.append(TwoProcessPoint(day: d, hour: h, s: s, c: c, isAwake: isAwake))
            }
        }
        return result
    }

    // MARK: - Continuous Process S (cross-day propagation)

    /// Compute S and C with sleep-debt memory across days.
    ///
    /// Unlike `compute()`, which resets s0 each day, this method propagates
    /// the final S value of each day as the starting S for the next.
    /// Captures cumulative sleep debt (e.g., 3 nights of 4h → rising S baseline)
    /// and recovery dynamics (e.g., long sleep → S drops below baseline).
    public static func computeContinuous(_ records: [SleepRecord]) -> [TwoProcessPoint] {
        guard !records.isEmpty else { return [] }
        var result: [TwoProcessPoint] = []
        var carryS = 0.15  // initial S at first day's wake

        for d in 0..<records.count {
            let dayData = records[d]
            var lastS = carryS
            var lastAwake = true

            for h in 0..<24 {
                let actEntry = dayData.hourlyActivity.first { $0.hour == h }
                let isAwake = actEntry.map { $0.activity >= 0.2 } ?? true

                if isAwake != lastAwake {
                    // State transition: use current S as new s0
                    lastAwake = isAwake
                }

                // Compute S for 1-hour step from lastS
                let s: Double
                if isAwake {
                    s = 1 - (1 - lastS) * exp(-1.0 / tauRise)
                } else {
                    s = lastS * exp(-1.0 / tauFall)
                }

                let c = processC(hour: Double(h), cosinor: dayData.cosinor)
                result.append(TwoProcessPoint(day: d, hour: h, s: s, c: c, isAwake: isAwake))
                lastS = s
            }

            // Carry last hour's S to next day
            carryS = lastS
        }
        return result
    }
}
