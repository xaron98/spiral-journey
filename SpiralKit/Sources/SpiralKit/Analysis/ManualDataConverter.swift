import Foundation

/// Converts manually recorded sleep episodes into SleepRecord objects.
/// Port of src/utils/manualData.js from the Spiral Journey web project.
public enum ManualDataConverter {

    // MARK: - Sleep Block Grouping

    /// A contiguous block of sleep (gap tolerance: 5 min) with its constituent episodes.
    private struct SleepBlock {
        var start: Double
        var end: Double
        var episodes: [SleepEpisode]
        var duration: Double { end - start }

        /// True if this block has no useful stage variety.
        /// Covers two cases from Apple Watch:
        ///   1. `asleepUnspecified` samples → phase == nil
        ///   2. A nap/second block recorded as a single continuous `asleepCore` sample
        ///      → all episodes have phase == .light with no deep or REM segments.
        /// In both cases the block would render as a single flat colour; synthesizing
        /// a sleep cycle gives the user meaningful visual information instead.
        var lacksStageDetail: Bool {
            let nonAwake = episodes.filter { $0.phase != .awake }
            guard !nonAwake.isEmpty else { return false }
            // No stage data at all
            if nonAwake.allSatisfy({ $0.phase == nil }) { return true }
            // All episodes share the exact same phase (e.g. all .light)
            let firstPhase = nonAwake.first?.phase
            return nonAwake.allSatisfy { $0.phase == firstPhase }
        }
    }

    /// Group a sorted list of episodes into contiguous sleep blocks.
    /// Episodes within `gapTolerance` hours of each other are merged into one block.
    private static func groupIntoBlocks(_ episodes: [SleepEpisode], gapTolerance: Double = 5.0 / 60.0) -> [SleepBlock] {
        var blocks: [SleepBlock] = []
        for ep in episodes {
            if var last = blocks.last, ep.start <= last.end + gapTolerance {
                last.end = max(last.end, ep.end)
                last.episodes.append(ep)
                blocks[blocks.count - 1] = last
            } else {
                blocks.append(SleepBlock(start: ep.start, end: ep.end, episodes: [ep]))
            }
        }
        return blocks
    }

    // MARK: - Synthetic Sleep Cycle

    /// Synthesize a realistic sleep stage for a given offset within a sleep block.
    /// Uses a simplified 90-minute NREM/REM cycle model:
    ///   - Minutes  0-15  of cycle: light (transition into sleep)
    ///   - Minutes 15-50  of cycle: deep (slow-wave, dominant early in the night)
    ///   - Minutes 50-75  of cycle: light (transition out of slow-wave)
    ///   - Minutes 75-90  of cycle: REM
    ///
    /// Deep sleep weight diminishes with each successive cycle (realistic architecture).
    private static func syntheticPhase(offsetHours: Double, blockDurationHours: Double) -> SleepPhase {
        let cycleLength = 1.5 // 90 minutes
        let offsetInCycle = offsetHours.truncatingRemainder(dividingBy: cycleLength)
        let cycleIndex = Int(offsetHours / cycleLength)

        // Deep sleep becomes less dominant in later cycles (realistic)
        let deepEndFraction: Double = max(0.15, 0.55 - Double(cycleIndex) * 0.10)
        let deepEnd = cycleLength * deepEndFraction
        let lightTransitionEnd = cycleLength * 0.18

        if offsetInCycle < lightTransitionEnd {
            return .light
        } else if offsetInCycle < deepEnd {
            return .deep
        } else if offsetInCycle < cycleLength * 0.85 {
            return .light
        } else {
            return .rem
        }
    }

    // MARK: - Converter

    /// Convert sleep episodes into an array of SleepRecord objects (one per day).
    /// - Parameters:
    ///   - episodes: Array of SleepEpisode with start/end as absolute hours from day 0 00:00
    ///   - numDays: Number of days to generate records for
    ///   - startDate: Date for day 0 (defaults to today)
    /// - Returns: Array of SleepRecord, one per day, with cosinor analysis applied
    public static func convert(
        episodes: [SleepEpisode],
        numDays: Int,
        startDate: Date = Date()
    ) -> [SleepRecord] {
        let calendar = Calendar.current
        var records: [SleepRecord] = []

        // Pre-group all episodes into contiguous blocks for efficient lookup.
        let allBlocks = groupIntoBlocks(episodes.sorted { $0.start < $1.start })

        for day in 0..<numDays {
            let dayStart = Double(day) * 24
            let dayDate  = calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
            let dow      = calendar.component(.weekday, from: dayDate)
            let isWeekend = (dow == 1 || dow == 7)

            // Activity: sleeping = 0.05, awake = 0.95
            func isSleeping(at absH: Double) -> Bool {
                episodes.contains { ep in absH >= ep.start && absH < ep.end }
            }

            var hourlyActivity: [HourlyActivity] = []
            for h in 0..<24 {
                let sleeping = isSleeping(at: dayStart + Double(h))
                hourlyActivity.append(HourlyActivity(hour: h, activity: sleeping ? 0.05 : 0.95))
            }

            // Find the main sleep block overlapping this day (largest total overlap).
            // For HealthKit data, episodes are per-stage samples — group them into blocks
            // first so we pick the longest *sleep session*, not the longest stage sample.
            var mainBlock: SleepBlock? = nil
            var totalSleep = 0.0
            var mainBlockOverlap = 0.0

            for block in allBlocks {
                let overlapStart = max(block.start, dayStart)
                let overlapEnd   = min(block.end, dayStart + 24)
                let overlap = max(0, overlapEnd - overlapStart)
                if overlap > 0 {
                    totalSleep += overlap
                    if overlap > mainBlockOverlap {
                        mainBlockOverlap = overlap
                        mainBlock = block
                    }
                }
            }

            let bedtime = mainBlock.map { $0.start.truncatingRemainder(dividingBy: 24) } ?? 23.5
            let wakeup  = mainBlock.map { $0.end.truncatingRemainder(dividingBy: 24) }   ?? 7.0

            // Phase intervals at 15-min resolution.
            // If the covering episode carries a HealthKit phase, use it directly.
            // For blocks with no stage detail (e.g. Apple Watch naps recorded as a single
            // asleepUnspecified or uniform asleepCore sample), synthesize a realistic
            // 90-min NREM/REM cycle so the block shows varied colors instead of flat lilac.
            // Manual episodes (phase == nil, no HK source) fall back to .deep.
            var phases: [PhaseInterval] = []
            var t = 0.0
            while t < 24 {
                let absT = dayStart + t
                let coveringEpisode = episodes.first { ep in absT >= ep.start && absT < ep.end }
                let phase: SleepPhase
                if let ep = coveringEpisode {
                    if ep.source == .healthKit,
                       let block = allBlocks.first(where: { absT >= $0.start && absT < $0.end }),
                       block.lacksStageDetail {
                        // HealthKit block with no stage variety (all asleepUnspecified or all
                        // same phase like asleepCore) — synthesize a realistic sleep cycle
                        // so the block shows varied colours instead of a flat stripe.
                        let offsetInBlock = absT - block.start
                        phase = syntheticPhase(offsetHours: offsetInBlock, blockDurationHours: block.duration)
                    } else if let explicitPhase = ep.phase {
                        // HealthKit block with real per-stage data — use it directly.
                        phase = explicitPhase
                    } else {
                        // Manual entry — solid deep (existing behaviour).
                        phase = .deep
                    }
                } else {
                    phase = .awake
                }
                phases.append(PhaseInterval(hour: t, phase: phase, timestamp: absT))
                t += 0.25
            }

            let cosinor = CosinorAnalysis.fit(hourlyActivity)

            records.append(SleepRecord(
                day:           day,
                date:          dayDate,
                isWeekend:     isWeekend,
                bedtimeHour:   bedtime,
                wakeupHour:    wakeup,
                sleepDuration: totalSleep,
                phases:        phases,
                hourlyActivity: hourlyActivity,
                cosinor:       cosinor,
                driftMinutes:  0
            ))
        }

        // Compute cumulative acrophase drift
        for i in 1..<records.count {
            var drift = records[i].cosinor.acrophase - records[i - 1].cosinor.acrophase
            if drift > 12  { drift -= 24 }
            if drift < -12 { drift += 24 }
            let prev = records[i - 1].driftMinutes
            records[i] = SleepRecord(
                id:            records[i].id,
                day:           records[i].day,
                date:          records[i].date,
                isWeekend:     records[i].isWeekend,
                bedtimeHour:   records[i].bedtimeHour,
                wakeupHour:    records[i].wakeupHour,
                sleepDuration: records[i].sleepDuration,
                phases:        records[i].phases,
                hourlyActivity: records[i].hourlyActivity,
                cosinor:       records[i].cosinor,
                driftMinutes:  prev + drift * 60
            )
        }

        return records
    }
}
