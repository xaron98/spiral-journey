import Foundation

/// Stateless coach evaluation engine.
///
/// Evaluates sleep records against a SleepGoal and returns the single most
/// important CoachInsight for the user to act on right now.
///
/// Rule priority per mode:
///
///  generalHealth: delayedPhase > splitSleep > socialJetlag >
///                 irregularSchedule > insufficientDuration >
///                 fragmentedSleep > sufficientButMisaligned > maintenance
///
///  shiftWork:     offTargetForShift > irregularSchedule >
///                 fragmentedSleep > insufficientDuration > maintenance
///
///  customSchedule: offTargetForCustomSchedule > irregularSchedule >
///                  fragmentedSleep > insufficientDuration > maintenance
///
///  rephase:       rephaseInProgress > splitSleep > irregularSchedule >
///                 insufficientDuration > maintenance
public enum CoachEngine {

    // MARK: - Thresholds

    private static let delayThresholdMinutes     = 90.0   // midSleep or acrophase offset
    private static let advanceThresholdMinutes   = 90.0
    private static let jetlagThresholdMinutes    = 60.0
    private static let irregularThresholdMinutes = 60.0   // SD of bed or wake times
    private static let durationDeficitThreshold  = 60.0   // minutes below goal
    private static let fragmentationThreshold    = 35.0   // 0-100 score
    private static let splitSleepMinMinutes      = 60.0   // daytime block size
    // Acrophase (activity peak) past this hour signals delayed phase even with 1 record
    private static let delayedAcrophaseHour      = 18.5

    // MARK: - Public API

    /// Produce the single most relevant coaching insight for the given records + goal.
    public static func evaluate(
        records: [SleepRecord],
        stats: SleepStats,
        goal: SleepGoal,
        consistency: SpiralConsistencyScore?
    ) -> CoachInsight {
        guard !records.isEmpty else {
            return insufficientDataInsight()
        }

        let assessment = assess(records: records, stats: stats, goal: goal)

        switch goal.mode {
        case .generalHealth:
            return evaluateGeneralHealth(assessment: assessment, stats: stats,
                                         goal: goal, consistency: consistency)
        case .shiftWork:
            return evaluateShiftWork(assessment: assessment, stats: stats, goal: goal)
        case .customSchedule:
            return evaluateCustomSchedule(assessment: assessment, stats: stats, goal: goal)
        case .rephase:
            return evaluateRephase(assessment: assessment, stats: stats, goal: goal)
        }
    }

    /// Extended evaluation that considers context blocks (work, study, etc.) and their conflicts.
    ///
    /// Priority logic:
    /// - If no blocks are configured, delegates to the standard `evaluate()`.
    /// - If conflicts exist, they compete with the base circadian insight:
    ///   - Urgent circadian issues (moderate+) take priority over mild conflicts.
    ///   - Conflicts take priority over mild/info circadian insights.
    ///   - In shiftWork/customSchedule, only direct overlaps are reported (no "too close" messages).
    public static func evaluate(
        records: [SleepRecord],
        stats: SleepStats,
        goal: SleepGoal,
        consistency: SpiralConsistencyScore?,
        contextBlocks: [ContextBlock],
        conflicts: [ScheduleConflict]
    ) -> CoachInsight {
        // No blocks → standard evaluation (backward compatible)
        guard !contextBlocks.isEmpty else {
            return evaluate(records: records, stats: stats, goal: goal, consistency: consistency)
        }

        // Get standard circadian insight
        var baseInsight = evaluate(records: records, stats: stats, goal: goal, consistency: consistency)

        // Enrich with context-aware text (exercise for delayedPhase, SJL with block ref)
        let assessment = assess(records: records, stats: stats, goal: goal)
        if baseInsight.issueKey == .delayedPhase {
            baseInsight = enrichDelayedPhaseWithExercise(baseInsight, wakeHour: assessment.mainSleepEndHour)
        }
        if baseInsight.issueKey == .socialJetlag {
            baseInsight = enrichSocialJetlagWithContext(baseInsight, contextBlocks: contextBlocks)
        }

        // For shift workers: offer strategic light timing at maintenance, or
        // sleepiness risk warning when S is high during work blocks
        if goal.mode == .shiftWork && (baseInsight.issueKey == .maintenance || baseInsight.severity <= .mild) {
            // Check sleepiness risk during work blocks
            let risks = SleepinessRiskEngine.evaluate(records: records, contextBlocks: contextBlocks)
            if let highRisk = risks.first(where: { $0.riskLevel == .high }) {
                let label = highRisk.blockLabel.isEmpty ? highRisk.blockType.rawValue : highRisk.blockLabel
                let peakTime = SleepStatistics.formatHour(highRisk.peakSleepinessHour)
                return CoachInsight(
                    issueKey: .sleepinessRiskDuringWork,
                    title: "High sleepiness risk during work",
                    reason: "Your sleep pressure is elevated during your \(label) block, peaking around \(peakTime).",
                    action: "Consider a 15-min nap before your shift. Use bright light at the start of your shift to boost alertness.",
                    expectedOutcome: "Goal: reduce accident and error risk during high-demand hours.",
                    severity: .moderate,
                    args: [highRisk.meanS],
                    stringArgs: [label, peakTime]
                )
            }

            // Offer strategic light timing
            if baseInsight.issueKey == .maintenance {
                if let lightInsight = shiftContextRecommendation(
                    blocks: contextBlocks, assessment: assessment, goal: goal
                ) {
                    return lightInsight
                }
            }
        }

        // Get conflict insight (if any)
        guard let conflictInsight = evaluateConflicts(conflicts: conflicts, goal: goal) else {
            return baseInsight
        }

        // Priority: urgent circadian > conflict > mild circadian
        if baseInsight.severity.rawValue >= CoachSeverity.moderate.rawValue
           && baseInsight.severity.rawValue > conflictInsight.severity.rawValue {
            return baseInsight
        }

        return conflictInsight
    }

    // MARK: - Context-Enhanced Insight Enrichment

    /// Enrich a delayed-phase insight with exercise recommendation.
    ///
    /// Research: 5 days morning exercise → ΔDLMO ≈ 0.62h advance.
    /// Evening exercise has negligible effect (≈ -0.02h).
    private static func enrichDelayedPhaseWithExercise(
        _ insight: CoachInsight,
        wakeHour: Double
    ) -> CoachInsight {
        guard insight.issueKey == .delayedPhase else { return insight }
        let exerciseDeadline = SleepStatistics.formatHour(wakeHour + 3.0)
        var enriched = insight
        enriched.action += " Add 30 min of moderate exercise before \(exerciseDeadline) to reinforce the phase advance."
        return enriched
    }

    /// Enrich social-jetlag insight with reference to the specific Monday morning obligation.
    private static func enrichSocialJetlagWithContext(
        _ insight: CoachInsight,
        contextBlocks: [ContextBlock]
    ) -> CoachInsight {
        guard insight.issueKey == .socialJetlag, !contextBlocks.isEmpty else { return insight }

        guard let mondayBlock = firstMorningBlock(blocks: contextBlocks, weekday: 2) else {
            return insight
        }

        var enriched = insight
        let blockTime = SleepStatistics.formatHour(mondayBlock.startHour)
        let label = mondayBlock.label.isEmpty ? mondayBlock.type.rawValue : mondayBlock.label
        enriched.reason += " This means you're sleepier during your \(label) on Monday at \(blockTime)."
        return enriched
    }

    /// Produce a shift-specific light timing insight when a night work block is detected.
    ///
    /// Meta-analysis: bright light g ≈ 1.08 for phase shift (large effect).
    /// Rotatory shift interventions: g ≈ 0.86 subgroup.
    /// Includes cautious melatonin recommendation per AASM for daytime sleep.
    private static func shiftContextRecommendation(
        blocks: [ContextBlock],
        assessment: CircadianAssessment,
        goal: SleepGoal
    ) -> CoachInsight? {
        let workBlocks = blocks.filter { $0.isEnabled && ($0.type == .work || $0.type == .focus) }
        guard let primary = workBlocks.first else { return nil }

        // Determine if it's a night shift (block spans nighttime hours)
        let isNightShift = primary.startHour >= 20.0 || primary.endHour <= 8.0
        guard isNightShift else { return nil }

        // Calculate light window: first half of the shift
        let shiftMidpoint: Double
        if primary.endHour < primary.startHour {
            let duration = (primary.endHour + 24.0 - primary.startHour)
            shiftMidpoint = primary.startHour + duration / 2.0
        } else {
            shiftMidpoint = (primary.startHour + primary.endHour) / 2.0
        }
        let lightStart = SleepStatistics.formatHour(primary.startHour + 1.0)
        let lightEnd = SleepStatistics.formatHour(shiftMidpoint)
        let shiftEnd = SleepStatistics.formatHour(primary.endHour)

        var action = "Use bright light (≥10,000 lux or lightbox) during \(lightStart)–\(lightEnd). After your shift ends at \(shiftEnd), wear blue-light-blocking glasses on your commute home."

        // Add melatonin suggestion if sleep is daytime
        let sleepIsDaytime = assessment.mainSleepStartHour >= 5.0 && assessment.mainSleepStartHour <= 14.0
        if sleepIsDaytime {
            let melatoninTime = SleepStatistics.formatHour(assessment.mainSleepStartHour - 0.75)
            action += " Consider melatonin (0.5–3 mg) around \(melatoninTime) to support daytime sleep onset — consult a healthcare professional first."
        }

        let label = primary.label.isEmpty ? "shift" : primary.label
        return CoachInsight(
            issueKey: .shiftLightTiming,
            title: "Strategic light timing for your shift",
            reason: "Bright light during the first half of your \(label) block helps maintain alertness and supports circadian adaptation.",
            action: action,
            expectedOutcome: "Goal: reduce on-shift sleepiness and support your daytime sleep quality.",
            severity: .info,
            args: [],
            stringArgs: [lightStart, lightEnd, shiftEnd]
        )
    }

    /// Find the first morning block (startHour < 14:00) active on the given weekday.
    private static func firstMorningBlock(blocks: [ContextBlock], weekday: Int) -> ContextBlock? {
        blocks
            .filter { $0.isEnabled && $0.isActive(weekday: weekday) && $0.startHour < 14.0 }
            .sorted { $0.startHour < $1.startHour }
            .first
    }

    // MARK: - Context Conflict Evaluation

    /// Evaluate schedule conflicts and produce an insight if warranted.
    ///
    /// In shiftWork/customSchedule modes, only direct overlaps are reported.
    /// No normative "too close" or "daytime sleep" messages for shift workers.
    private static func evaluateConflicts(
        conflicts: [ScheduleConflict],
        goal: SleepGoal
    ) -> CoachInsight? {
        // Filter by mode: shift/custom only see direct overlaps
        let filtered: [ScheduleConflict]
        switch goal.mode {
        case .shiftWork, .customSchedule:
            filtered = conflicts.filter { $0.type == .sleepOverlapsBlock }
        case .generalHealth, .rephase:
            filtered = conflicts
        }

        guard !filtered.isEmpty else { return nil }

        // Priority: overlap > tooClose > daytimeSleep
        if let overlap = filtered.first(where: { $0.type == .sleepOverlapsBlock }) {
            let label = overlap.blockLabel.isEmpty ? overlap.blockType.rawValue : overlap.blockLabel
            return CoachInsight(
                issueKey: .sleepOverlapsContext,
                title: "Sleep overlaps your schedule",
                reason: "About \(Int(overlap.overlapMinutes)) min of sleep overlap with \(label).",
                action: "Move bedtime earlier so sleep finishes before your block starts.",
                expectedOutcome: "Goal: clear separation between sleep and obligations.",
                severity: .moderate,
                args: [overlap.overlapMinutes],
                stringArgs: [label, SleepStatistics.formatHour(overlap.blockStartHour)]
            )
        }

        if let tooClose = filtered.first(where: { $0.type == .sleepTooCloseToBlockStart }) {
            let label = tooClose.blockLabel.isEmpty ? tooClose.blockType.rawValue : tooClose.blockLabel
            let actualGap = Int(ScheduleConflictDetector.defaultBufferMinutes - tooClose.overlapMinutes)
            return CoachInsight(
                issueKey: .sleepTooCloseToContext,
                title: "Waking too close to obligations",
                reason: "You wake up only \(actualGap) min before \(label).",
                action: "Shift bedtime \(Int(tooClose.overlapMinutes)) min earlier to create breathing room.",
                expectedOutcome: "Goal: at least 60 min between waking and your first obligation.",
                severity: .mild,
                args: [tooClose.overlapMinutes, Double(actualGap)],
                stringArgs: [label, SleepStatistics.formatHour(tooClose.blockStartHour)]
            )
        }

        if let daytime = filtered.first(where: { $0.type == .daytimeSleepConsumesWindow }) {
            let label = daytime.blockLabel.isEmpty ? daytime.blockType.rawValue : daytime.blockLabel
            return CoachInsight(
                issueKey: .daytimeSleepConsumesContext,
                title: "Napping into your schedule",
                reason: "About \(Int(daytime.overlapMinutes)) min of daytime sleep falls within your \(label) window.",
                action: "Limit naps to 20 min before 14:00 to preserve your operational window.",
                expectedOutcome: "Goal: keep daytime sleep outside your obligations.",
                severity: .mild,
                args: [daytime.overlapMinutes],
                stringArgs: [label]
            )
        }

        return nil
    }

    /// Compute intermediate circadian metrics. Public so tests can verify metrics directly.
    public static func assess(
        records: [SleepRecord],
        stats: SleepStats,
        goal: SleepGoal
    ) -> CircadianAssessment {
        guard !records.isEmpty else { return CircadianAssessment() }

        // --- Mean bed/wake/midSleep ---
        let validBed  = records.map(\.bedtimeHour).filter { $0 > 0 }
        let validWake = records.map(\.wakeupHour).filter { $0 > 0 }

        let meanBed  = validBed.isEmpty  ? stats.meanAcrophase - 8 : circularMeanHour(validBed)
        let meanWake = validWake.isEmpty ? stats.meanAcrophase - 8 + stats.meanSleepDuration
                                        : circularMeanHour(validWake)
        let meanMidSleep = circularMidSleep(bed: meanBed, wake: meanWake)

        // --- Deviations from goal (circular, positive = late) ---
        let bedDev  = circularDiffMinutes(actual: meanBed,      target: goal.targetBedHour)
        let wakeDev = circularDiffMinutes(actual: meanWake,     target: goal.targetWakeHour)
        let midDev  = circularDiffMinutes(actual: meanMidSleep, target: goal.targetMidSleepHour)

        // --- Variability (SDs in minutes) ---
        let bedSD  = validBed.count  > 1 ? circularSDHours(validBed)  * 60 : 0
        let wakeSD = validWake.count > 1 ? linearSDHours(validWake)   * 60 : 0

        // --- Social jetlag from stats (already computed, in minutes) ---
        let jetlag = stats.socialJetlag  // minutes

        // --- Duration ---
        let meanDur = stats.meanSleepDuration > 0 ? stats.meanSleepDuration : 0
        let durDeficit = max(0, goal.targetDuration - meanDur) * 60

        // --- Split sleep detection ---
        // Look across all records for significant daytime sleep (08:00–20:00)
        var totalDaytimeSleepMinutes = 0.0
        var splitDaysCount = 0
        for record in records {
            let daytimeAsleep = record.hourlyActivity
                .filter { $0.hour >= 8 && $0.hour < 20 && $0.activity < 0.3 }
            let daytimeMinutes = Double(daytimeAsleep.count) * 60
            if daytimeMinutes >= splitSleepMinMinutes {
                totalDaytimeSleepMinutes += daytimeMinutes
                splitDaysCount += 1
            }
        }
        let hasSplit = !goal.allowsSplitSleep
            && splitDaysCount > 0
            && (Double(splitDaysCount) / Double(records.count)) >= 0.4
        let avgDaytimeMinutes = records.isEmpty ? 0
            : totalDaytimeSleepMinutes / Double(records.count)

        // --- Fragmentation: count sleep→wake transitions within main sleep window ---
        var totalTransitions = 0
        var totalSleepHours = 0
        for record in records {
            let acts = record.hourlyActivity.sorted { $0.hour < $1.hour }
            var prev: Bool? = nil
            for act in acts {
                let sleeping = act.activity < 0.3
                if let p = prev, p != sleeping { totalTransitions += 1 }
                prev = sleeping
                if sleeping { totalSleepHours += 1 }
            }
        }
        let avgTransitions = records.isEmpty ? 0.0
            : Double(totalTransitions) / Double(records.count)
        // Normalize: 0 = no fragmentation, 100 = very fragmented (≥6 transitions/night)
        let fragmentationScore = min(100, (avgTransitions / 6.0) * 100)

        // --- Main sleep window ---
        let mainStart = meanBed
        let mainEnd   = meanWake

        return CircadianAssessment(
            midSleepDeviationMinutes: midDev,
            wakeDeviationMinutes:     wakeDev,
            bedDeviationMinutes:      bedDev,
            bedtimeStdMinutes:        bedSD,
            wakeStdMinutes:           wakeSD,
            socialJetlagMinutes:      jetlag,
            meanDurationHours:        meanDur,
            durationDeficitMinutes:   durDeficit,
            hasSplitSleep:            hasSplit,
            splitSleepDaytimeMinutes: avgDaytimeMinutes,
            fragmentationScore:       fragmentationScore,
            mainSleepStartHour:       mainStart,
            mainSleepEndHour:         mainEnd,
            recordCount:              records.count
        )
    }

    // MARK: - Mode Evaluators

    static func evaluateGeneralHealth(
        assessment: CircadianAssessment,
        stats: SleepStats,
        goal: SleepGoal,
        consistency: SpiralConsistencyScore?
    ) -> CoachInsight {

        // 1. Delayed phase (detectable from 1 record via acrophase or midSleep deviation)
        let isDelayed = assessment.midSleepDeviationMinutes >= delayThresholdMinutes
                     || stats.meanAcrophase > delayedAcrophaseHour
        if isDelayed {
            let estBed  = SleepStatistics.formatHour(assessment.mainSleepStartHour)
            let estWake = SleepStatistics.formatHour(assessment.mainSleepEndHour)
            let lightTime = SleepStatistics.formatHour(assessment.mainSleepEndHour + 0.5)
            return CoachInsight(
                issueKey: .delayedPhase,
                title: "Delayed sleep phase",
                reason: "Your sleep is shifted significantly later than a typical healthy window. Estimated sleep \(estBed)–\(estWake).",
                action: "Get bright light (sunlight or 10,000-lux lamp) at \(lightTime) for 20–30 min. Shift bedtime 15 min earlier every 2 days.",
                expectedOutcome: "Goal: gradually move your internal clock earlier.",
                severity: .moderate,
                args: [assessment.midSleepDeviationMinutes],
                stringArgs: [lightTime]
            )
        }

        // 2. Advanced phase
        if assessment.midSleepDeviationMinutes <= -advanceThresholdMinutes {
            return CoachInsight(
                issueKey: .advancedPhase,
                title: "Advanced sleep phase",
                reason: "Your sleep is shifted significantly earlier than a typical healthy window.",
                action: "Expose yourself to bright light in the evening (19:00–21:00) to shift your clock later.",
                expectedOutcome: "Goal: align sleep to a later, healthier window.",
                severity: .mild,
                args: [abs(assessment.midSleepDeviationMinutes)]
            )
        }

        // 3. Split sleep (check before social jetlag; it's a structural issue)
        if assessment.hasSplitSleep {
            return splitSleepInsight(daytimeMinutes: assessment.splitSleepDaytimeMinutes)
        }

        // 4. Social jetlag (needs weekday + weekend data)
        if assessment.socialJetlagMinutes > jetlagThresholdMinutes {
            let minutes = Int(assessment.socialJetlagMinutes)
            return CoachInsight(
                issueKey: .socialJetlag,
                title: "Social jetlag detected",
                reason: "Your sleep time differs by \(minutes) min between weekdays and weekends — like traveling across time zones every week.",
                action: "This weekend, try to sleep and wake within 30 min of your weekday schedule.",
                expectedOutcome: "Goal: reduce the weekday–weekend gap to under 30 min.",
                severity: .moderate,
                args: [Double(minutes)]
            )
        }

        // 4. Irregular schedule
        if assessment.bedtimeStdMinutes > irregularThresholdMinutes
        || assessment.wakeStdMinutes    > irregularThresholdMinutes {
            let stdMin = Int(max(assessment.bedtimeStdMinutes, assessment.wakeStdMinutes))
            let targetWake = SleepStatistics.formatHour(goal.targetWakeHour)
            return CoachInsight(
                issueKey: .irregularSchedule,
                title: "Irregular schedule",
                reason: "Your sleep and wake times vary by about \(stdMin) min day-to-day, which weakens your circadian rhythm.",
                action: "Fix your wake time first: aim for \(targetWake) every day, including weekends.",
                expectedOutcome: "Goal: reduce variability to under 30 min.",
                severity: .mild,
                args: [Double(stdMin)]
            )
        }

        // 5. Insufficient duration
        if assessment.durationDeficitMinutes >= durationDeficitThreshold {
            let deficit = Int(assessment.durationDeficitMinutes)
            return CoachInsight(
                issueKey: .insufficientDuration,
                title: "Not enough sleep",
                reason: "You're averaging \(String(format: "%.1f", assessment.meanDurationHours))h — about \(deficit) min less than recommended.",
                action: "Move bedtime \(min(deficit, 30)) min earlier tonight. Dim lights 1 h before bed.",
                expectedOutcome: "Goal: reach \(String(format: "%.0f", goal.targetDuration))h of sleep per night.",
                severity: .moderate,
                args: [assessment.meanDurationHours, Double(deficit)]
            )
        }

        // 6. Fragmented sleep
        if assessment.fragmentationScore > fragmentationThreshold {
            return CoachInsight(
                issueKey: .fragmentedSleep,
                title: "Fragmented sleep",
                reason: "Your sleep has multiple wake-ups. This reduces deep sleep and recovery quality.",
                action: "Limit fluids 2 h before bed, keep the room cool (18–20 °C), and avoid caffeine after 14:00.",
                expectedOutcome: "Goal: consolidate sleep into a single uninterrupted block.",
                severity: .mild
            )
        }

        // 7. Sufficient duration but timing slightly off
        if assessment.meanDurationHours >= goal.targetDuration - 0.5
        && abs(assessment.midSleepDeviationMinutes) > 45 {
            let estBed = SleepStatistics.formatHour(assessment.mainSleepStartHour)
            return CoachInsight(
                issueKey: .sufficientButMisaligned,
                title: "Good duration, shifted timing",
                reason: "You're sleeping enough, but your schedule is offset from the optimal circadian window. Duration isn't the problem — timing is.",
                action: "Don't try to sleep more. Set a fixed wake time at \(SleepStatistics.formatHour(goal.targetWakeHour)) and let bedtime adjust naturally.",
                expectedOutcome: "Goal: improve timing alignment without reducing total sleep.",
                severity: .mild,
                args: [assessment.midSleepDeviationMinutes]
            )
        }

        // 8. All within tolerance — maintenance
        return maintenanceInsight()
    }

    static func evaluateShiftWork(
        assessment: CircadianAssessment,
        stats: SleepStats,
        goal: SleepGoal
    ) -> CoachInsight {

        // 1. Off target for shift
        let bedOff  = abs(assessment.bedDeviationMinutes)  > goal.toleranceMinutes
        let wakeOff = abs(assessment.wakeDeviationMinutes) > goal.toleranceMinutes
        if bedOff || wakeOff {
            let offsetMin = Int(max(bedOff ? abs(assessment.bedDeviationMinutes) : 0,
                                   wakeOff ? abs(assessment.wakeDeviationMinutes) : 0))
            let targetBed  = SleepStatistics.formatHour(goal.targetBedHour)
            let targetWake = SleepStatistics.formatHour(goal.targetWakeHour)
            return CoachInsight(
                issueKey: .offTargetForShift,
                title: "Sleep outside shift schedule",
                reason: "Your sleep is about \(offsetMin) min off from your \(targetBed)–\(targetWake) shift window.",
                action: "Today, try to sleep as close to \(targetBed) as possible and wake at \(targetWake).",
                expectedOutcome: "Goal: align your sleep block with your shift schedule.",
                severity: .moderate,
                args: [Double(offsetMin)]
            )
        }

        // 2. Irregular schedule within shift
        if assessment.bedtimeStdMinutes > irregularThresholdMinutes
        || assessment.wakeStdMinutes    > irregularThresholdMinutes {
            let stdMin = Int(max(assessment.bedtimeStdMinutes, assessment.wakeStdMinutes))
            return CoachInsight(
                issueKey: .irregularSchedule,
                title: "Variable shift sleep",
                reason: "Your sleep times vary by about \(stdMin) min around your shift schedule.",
                action: "Keep sleep times consistent even on rest days — your body needs regularity.",
                expectedOutcome: "Goal: reduce variability to under 30 min.",
                severity: .mild,
                args: [Double(stdMin)]
            )
        }

        // 3. Fragmented sleep
        if assessment.fragmentationScore > fragmentationThreshold {
            return CoachInsight(
                issueKey: .fragmentedSleep,
                title: "Fragmented shift sleep",
                reason: "Your sleep block has multiple interruptions, reducing recovery quality.",
                action: "Use blackout curtains, earplugs, and a white noise source. Post a 'sleeping' sign if needed.",
                expectedOutcome: "Goal: consolidate the sleep block.",
                severity: .mild
            )
        }

        // 4. Insufficient duration
        if assessment.durationDeficitMinutes >= durationDeficitThreshold {
            let deficit = Int(assessment.durationDeficitMinutes)
            return CoachInsight(
                issueKey: .insufficientDuration,
                title: "Insufficient shift sleep",
                reason: "You're averaging \(deficit) min less than your target duration.",
                action: "Start winding down 30 min earlier than your current bedtime.",
                expectedOutcome: "Goal: reach \(String(format: "%.0f", goal.targetDuration))h of sleep per shift.",
                severity: .moderate,
                args: [Double(deficit)]
            )
        }

        // 5. Aligned with shift schedule
        return CoachInsight(
            issueKey: .maintenance,
            title: "Well aligned with your shift",
            reason: "Your sleep pattern fits your defined shift schedule.",
            action: "Keep this pattern consistent, especially on transition days between shift rotations.",
            expectedOutcome: "",
            severity: .info
        )
    }

    static func evaluateCustomSchedule(
        assessment: CircadianAssessment,
        stats: SleepStats,
        goal: SleepGoal
    ) -> CoachInsight {

        // 1. Off target
        let bedOff  = abs(assessment.bedDeviationMinutes)  > goal.toleranceMinutes
        let wakeOff = abs(assessment.wakeDeviationMinutes) > goal.toleranceMinutes
        if bedOff || wakeOff {
            let offsetMin = Int(max(bedOff ? abs(assessment.bedDeviationMinutes) : 0,
                                   wakeOff ? abs(assessment.wakeDeviationMinutes) : 0))
            let targetBed  = SleepStatistics.formatHour(goal.targetBedHour)
            let targetWake = SleepStatistics.formatHour(goal.targetWakeHour)
            return CoachInsight(
                issueKey: .offTargetForCustomSchedule,
                title: "Sleep drifting from your schedule",
                reason: "Your sleep is about \(offsetMin) min off from your custom goal (\(targetBed)–\(targetWake)).",
                action: "Today, aim for wake time \(targetWake) first — bedtime will follow naturally.",
                expectedOutcome: "Goal: close the gap with your planned schedule.",
                severity: .moderate,
                args: [Double(offsetMin)]
            )
        }

        // 2. Irregular
        if assessment.bedtimeStdMinutes > irregularThresholdMinutes
        || assessment.wakeStdMinutes    > irregularThresholdMinutes {
            let stdMin = Int(max(assessment.bedtimeStdMinutes, assessment.wakeStdMinutes))
            return CoachInsight(
                issueKey: .irregularSchedule,
                title: "Variable schedule",
                reason: "Your sleep varies about \(stdMin) min around your custom target.",
                action: "Pin your wake time to \(SleepStatistics.formatHour(goal.targetWakeHour)) — it's the strongest anchor.",
                expectedOutcome: "Goal: reduce variability to under 30 min.",
                severity: .mild,
                args: [Double(stdMin)]
            )
        }

        // 3. Fragmented
        if assessment.fragmentationScore > fragmentationThreshold {
            return CoachInsight(
                issueKey: .fragmentedSleep,
                title: "Fragmented sleep",
                reason: "Multiple interruptions within your sleep window reduce recovery.",
                action: "Optimize your sleep environment: temperature, darkness, and noise.",
                expectedOutcome: "Goal: uninterrupted sleep in your target window.",
                severity: .mild
            )
        }

        // 4. Short
        if assessment.durationDeficitMinutes >= durationDeficitThreshold {
            let deficit = Int(assessment.durationDeficitMinutes)
            return CoachInsight(
                issueKey: .insufficientDuration,
                title: "Below target duration",
                reason: "You're averaging \(deficit) min less than your target.",
                action: "Move bedtime \(min(deficit, 30)) min earlier tonight.",
                expectedOutcome: "Goal: reach \(String(format: "%.0f", goal.targetDuration))h.",
                severity: .moderate,
                args: [Double(deficit)]
            )
        }

        return maintenanceInsight()
    }

    static func evaluateRephase(
        assessment: CircadianAssessment,
        stats: SleepStats,
        goal: SleepGoal
    ) -> CoachInsight {
        let wakeDelay = assessment.wakeDeviationMinutes  // positive = still too late
        let step = goal.rephaseStepMinutes > 0 ? goal.rephaseStepMinutes : 30

        // 1. Still meaningfully behind target (more than 2 steps away)
        if wakeDelay > step * 2 {
            let remainingMin = Int(wakeDelay)
            let targetWake = SleepStatistics.formatHour(goal.targetWakeHour)
            return CoachInsight(
                issueKey: .rephaseInProgress,
                title: "Still behind your target",
                reason: "Your schedule is about \(remainingMin) min behind your goal of \(targetWake).",
                action: "Tomorrow wake at \(SleepStatistics.formatHour(goal.targetWakeHour + wakeDelay / 60 - step / 60)). Bright light immediately on waking.",
                expectedOutcome: "Goal: gain \(Int(step)) min per day until you reach \(targetWake).",
                severity: .moderate,
                args: [Double(remainingMin), step]
            )
        }

        // 2. Split sleep undermining rephase progress
        if assessment.hasSplitSleep {
            return splitSleepInsight(daytimeMinutes: assessment.splitSleepDaytimeMinutes)
        }

        // 3. Irregular schedule (variability slowing rephase)
        if assessment.bedtimeStdMinutes > irregularThresholdMinutes
        || assessment.wakeStdMinutes    > irregularThresholdMinutes {
            let stdMin = Int(max(assessment.bedtimeStdMinutes, assessment.wakeStdMinutes))
            return CoachInsight(
                issueKey: .irregularSchedule,
                title: "Variable schedule slowing rephase",
                reason: "Day-to-day variability (\(stdMin) min) resets progress and makes rephasing harder.",
                action: "Consistency is critical during rephase: keep wake time fixed even on off days.",
                expectedOutcome: "Goal: reduce variability to under 20 min.",
                severity: .moderate,
                args: [Double(stdMin)]
            )
        }

        // 4. Short sleep
        if assessment.durationDeficitMinutes >= durationDeficitThreshold {
            let deficit = Int(assessment.durationDeficitMinutes)
            return CoachInsight(
                issueKey: .insufficientDuration,
                title: "Short sleep during rephase",
                reason: "Sleeping \(deficit) min less than your target can increase social pressure to revert to old hours.",
                action: "Prioritize sleep opportunity. Go to bed when sleepy, not when the clock says so.",
                expectedOutcome: "Goal: maintain duration while shifting timing.",
                severity: .mild,
                args: [Double(deficit)]
            )
        }

        // 5. Close to target — maintenance
        return CoachInsight(
            issueKey: .maintenance,
            title: "Almost there",
            reason: "Your schedule is very close to your rephase target. \(wakeDelay > 0 ? "Just \(Int(wakeDelay)) min to go." : "You've reached it!")",
            action: "Maintain your new wake time strictly for the next 2 weeks to consolidate the shift.",
            expectedOutcome: "Goal: lock in the new schedule and prevent backsliding.",
            severity: .info,
            args: [wakeDelay]
        )
    }

    // MARK: - Shared Insight Builders

    private static func splitSleepInsight(daytimeMinutes: Double) -> CoachInsight {
        let minutes = Int(daytimeMinutes)
        return CoachInsight(
            issueKey: .splitSleep,
            title: "Split sleep pattern",
            reason: "About \(minutes) min of your sleep is shifting to daytime. This can delay your nighttime rhythm.",
            action: "Today, avoid sleeping after 15:00. If very sleepy, limit naps to 20 min before 14:00.",
            expectedOutcome: "Goal: consolidate sleep into one main overnight block.",
            severity: .moderate,
            args: [Double(minutes)]
        )
    }

    private static func maintenanceInsight() -> CoachInsight {
        CoachInsight(
            issueKey: .maintenance,
            title: "Sleep looks consistent",
            reason: "Your timing, duration, and regularity are all within a healthy range for your goal.",
            action: "Keep your current schedule. Protect your wake time even on weekends.",
            expectedOutcome: "",
            severity: .info
        )
    }

    private static func insufficientDataInsight() -> CoachInsight {
        CoachInsight(
            issueKey: .insufficientData,
            title: "Not enough data yet",
            reason: "Add at least one sleep record to get a personalised insight.",
            action: "Log tonight's sleep in the spiral view.",
            expectedOutcome: "",
            severity: .info
        )
    }

    // MARK: - Circular Time Math

    /// Circular signed difference in minutes (actual − target), normalised to (−720, +720].
    /// Positive = actual is later than target.
    public static func circularDiffMinutes(actual: Double, target: Double) -> Double {
        var diff = (actual - target) * 60
        // Normalise to (−720, +720] (half of 24 h = 12 h = 720 min)
        while diff >  720 { diff -= 1440 }
        while diff <= -720 { diff += 1440 }
        return diff
    }

    /// Circular midpoint of a sleep window (bed → wake arc).
    public static func circularMidSleep(bed: Double, wake: Double) -> Double {
        var duration = wake - bed
        if duration < 0 { duration += 24 }
        var mid = bed + duration / 2
        if mid >= 24 { mid -= 24 }
        return mid
    }

    // MARK: - Private Stats Helpers

    /// Circular mean of clock hours (0–24).
    private static func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let toRad = Double.pi / 12.0
        let sinMean = hours.map { sin($0 * toRad) }.reduce(0, +) / Double(hours.count)
        let cosMean = hours.map { cos($0 * toRad) }.reduce(0, +) / Double(hours.count)
        var angle = atan2(sinMean, cosMean) / toRad
        if angle < 0 { angle += 24 }
        return angle
    }

    /// Circular standard deviation of clock hours (0–24), in hours.
    private static func circularSDHours(_ hours: [Double]) -> Double {
        guard hours.count > 1 else { return 0 }
        let toRad = Double.pi / 12.0
        let n = Double(hours.count)
        let sinMean = hours.map { sin($0 * toRad) }.reduce(0, +) / n
        let cosMean = hours.map { cos($0 * toRad) }.reduce(0, +) / n
        let R = sqrt(sinMean * sinMean + cosMean * cosMean)
        let R_clamped = min(max(R, 1e-9), 1)
        return sqrt(max(-2.0 * log(R_clamped), 0)) / toRad
    }

    /// Linear standard deviation of hours (for wake times which rarely wrap midnight).
    private static func linearSDHours(_ hours: [Double]) -> Double {
        guard hours.count > 1 else { return 0 }
        let mean = hours.reduce(0, +) / Double(hours.count)
        let variance = hours.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(hours.count)
        return sqrt(variance)
    }
}
