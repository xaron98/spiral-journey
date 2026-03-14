import Foundation

/// Sleep statistics calculations.
/// Port of src/utils/sleepData.js from the Spiral Journey web project.
public enum SleepStatistics {

    /// Sleep Regularity Index (SRI): probability (0-100) that sleep/wake state is
    /// identical at the same time on consecutive days.
    /// Reference: Phillips et al. (2017)
    public static func sleepRegularityIndex(_ records: [SleepRecord]) -> Double {
        guard records.count >= 2 else { return 0 }
        var matches = 0
        var total = 0

        for d in 1..<records.count {
            let today = records[d].hourlyActivity
            let yesterday = records[d - 1].hourlyActivity
            let count = min(today.count, yesterday.count)
            for h in 0..<count {
                let todaySleep     = today[h].activity < 0.2
                let yesterdaySleep = yesterday[h].activity < 0.2
                if todaySleep == yesterdaySleep { matches += 1 }
                total += 1
            }
        }
        return total > 0 ? (Double(matches) / Double(total)) * 100 : 0
    }

    /// Calculate comprehensive sleep statistics from an array of SleepRecords.
    public static func calculateStats(_ records: [SleepRecord]) -> SleepStats {
        guard !records.isEmpty else { return SleepStats() }

        func mean(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            return arr.reduce(0, +) / Double(arr.count)
        }
        func std(_ arr: [Double]) -> Double {
            guard !arr.isEmpty else { return 0 }
            let m = mean(arr)
            return sqrt(arr.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(arr.count))
        }
        /// Circular standard deviation for hourly values (0–24), in hours.
        func circularStd(_ hours: [Double]) -> Double {
            guard hours.count > 1 else { return 0 }
            let toRad = Double.pi / 12.0        // hours → radians (24h = 2π)
            let sinMean = mean(hours.map { sin($0 * toRad) })
            let cosMean = mean(hours.map { cos($0 * toRad) })
            let R = sqrt(sinMean * sinMean + cosMean * cosMean)  // mean resultant length
            let R_clamped = min(max(R, 1e-9), 1)
            return sqrt(max(-2.0 * log(R_clamped), 0)) / toRad   // back to hours
        }

        let acrophases = records.map(\.cosinor.acrophase)
        let amplitudes = records.map(\.cosinor.amplitude)
        let bedtimes   = records.map(\.bedtimeHour).filter { $0 >= 0 }

        // Use acrophase (cosinor peak) for social jetlag — robust for biphasic/night-shift sleepers.
        // Acrophase is already circadian-phase-aware; no midnight wrap needed.
        // Require at least 2 records on each side for a meaningful comparison.
        let mainRecords  = records.filter { $0.sleepDuration >= 3.0 }
        let weekdayData  = (mainRecords.isEmpty ? records : mainRecords).filter { !$0.isWeekend }
        let weekendData  = (mainRecords.isEmpty ? records : mainRecords).filter { $0.isWeekend }

        let weekdayAcro  = weekdayData.map(\.cosinor.acrophase).filter { $0 > 0 }
        let weekendAcro  = weekendData.map(\.cosinor.acrophase).filter { $0 > 0 }
        let socialJetlag: Double
        if weekdayAcro.count >= 1 && weekendAcro.count >= 1 {
            // Circular difference capped at 12h to avoid wrap-around artefacts
            let rawDiff = abs(mean(weekendAcro) - mean(weekdayAcro))
            socialJetlag = min(rawDiff, 24 - rawDiff) * 60
        } else {
            socialJetlag = 0
        }

        let weekdayAmp = weekdayData.isEmpty ? 0 : mean(weekdayData.map(\.cosinor.amplitude))
        let weekendAmp = weekendData.isEmpty ? 0 : mean(weekendData.map(\.cosinor.amplitude))
        let ampDrop = weekdayAmp > 0 ? ((1 - weekendAmp / weekdayAmp) * 100) : 0

        let durations = records.map(\.sleepDuration).filter { $0 > 0 }

        return SleepStats(
            meanAcrophase:    mean(acrophases),
            stdAcrophase:     circularStd(acrophases),
            stdBedtime:       circularStd(bedtimes),
            meanAmplitude:    mean(amplitudes),
            rhythmStability:  CosinorAnalysis.rhythmStability(records.map(\.cosinor)),
            socialJetlag:     socialJetlag,
            weekdayAmp:       weekdayAmp,
            weekendAmp:       weekendAmp,
            ampDrop:          ampDrop,
            meanSleepDuration: mean(durations),
            meanR2:           mean(records.map(\.cosinor.r2)),
            sri:              sleepRegularityIndex(records)
        )
    }

    /// Format decimal hours to "HH:MM" string.
    public static func formatHour(_ h: Double) -> String {
        let adjusted = ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
        let hours = Int(adjusted)
        let mins  = Int((adjusted - Double(hours)) * 60)
        return String(format: "%02d:%02d", hours, mins)
    }
}
