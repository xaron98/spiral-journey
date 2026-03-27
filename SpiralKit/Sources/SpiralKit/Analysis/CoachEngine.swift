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
                    title: "Stay sharp during work",
                    reason: "Your sleep pressure peaks around \(peakTime) during your \(label) block.",
                    action: "A 15-min nap before your shift and bright light at the start can boost alertness significantly.",
                    expectedOutcome: "Goal: feel more alert and focused during high-demand hours.",
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

        // Determine if it's a night shift (block starts late evening AND ends early morning,
        // meaning it crosses midnight — both conditions must hold).
        let isNightShift = primary.startHour >= 20.0 && primary.endHour <= 8.0
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
        let validBed  = records.map(\.bedtimeHour).filter { $0 >= 0 }
        let validWake = records.map(\.wakeupHour).filter { $0 >= 0 }

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
                reason: "Your sleep and wake times vary by about \(stdMin) min day-to-day. A more consistent schedule helps your body's internal clock.",
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
                reason: "Your sleep shows multiple wake-ups. Consolidating sleep can improve how rested you feel.",
                action: "Try limiting fluids 2 h before bed, keeping the room cool (18–20 °C), and shifting your last coffee to before 14:00.",
                expectedOutcome: "Goal: longer uninterrupted stretches of sleep.",
                severity: .mild
            )
        }

        // 7. Sufficient duration but timing slightly off
        if assessment.meanDurationHours >= goal.targetDuration - 0.5
        && abs(assessment.midSleepDeviationMinutes) > 45 {
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
            reason: "About \(minutes) min of your sleep is happening during the day. Consolidating to nighttime helps your body's rhythm.",
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

    // MARK: - Enhanced Evaluation (Sprint 4)

    /// Produce the full enhanced coaching result: primary insight + temporal patterns,
    /// celebrations, micro-habit, weekly digest, streak, and event acknowledgments.
    ///
    /// Calls the existing `evaluate()` internally so all base logic is preserved.
    public static func evaluateEnhanced(
        records: [SleepRecord],
        stats: SleepStats,
        goal: SleepGoal,
        consistency: SpiralConsistencyScore?,
        events: [CircadianEvent],
        previousStats: SleepStats?,
        previousCompositeScore: Int?,
        compositeScore: Int,
        streakHistory: StreakData,
        contextBlocks: [ContextBlock] = [],
        conflicts: [ScheduleConflict] = []
    ) -> EnhancedCoachResult {
        // 1. Base insight (reuse existing logic)
        let insight: CoachInsight
        if contextBlocks.isEmpty {
            insight = evaluate(records: records, stats: stats, goal: goal, consistency: consistency)
        } else {
            insight = evaluate(records: records, stats: stats, goal: goal,
                             consistency: consistency, contextBlocks: contextBlocks,
                             conflicts: conflicts)
        }

        // 2. Temporal patterns
        let patterns = detectTemporalPatterns(records: records)

        // 3. Streak computation
        let streak = computeStreaks(records: records, goal: goal, previousStreak: streakHistory)

        // 4. Celebrations
        let celebrations = detectCelebrations(
            stats: stats,
            previousStats: previousStats,
            streak: streak,
            compositeScore: compositeScore,
            previousCompositeScore: previousCompositeScore,
            goal: goal
        )

        // 5. Micro-habit
        let microHabit = generateMicroHabit(issueKey: insight.issueKey)

        // 6. Weekly digest
        let digest = generateWeeklyDigest(
            records: records,
            stats: stats,
            previousStats: previousStats,
            compositeScore: compositeScore,
            previousCompositeScore: previousCompositeScore ?? 0
        )

        // 7. Event acknowledgments
        let acknowledgments = acknowledgeEvents(events: events, records: records)

        return EnhancedCoachResult(
            insight: insight,
            temporalPatterns: patterns,
            celebrations: celebrations,
            microHabit: microHabit,
            weeklyDigest: digest,
            streak: streak,
            eventAcknowledgments: acknowledgments
        )
    }

    // MARK: - Temporal Pattern Detection

    /// Group records by weekday and compare each day's mean bedtime/duration against the overall mean.
    /// Returns patterns where the deviation is ≥30 min and backed by ≥2 samples.
    public static func detectTemporalPatterns(records: [SleepRecord]) -> [TemporalPattern] {
        guard records.count >= 7 else { return [] }

        // Overall circular means
        let allBed = records.map(\.bedtimeHour)
        let allDur = records.map(\.sleepDuration)
        let allWake = records.map(\.wakeupHour)
        let meanBed = circularMeanHour(allBed)
        let meanWake = circularMeanHour(allWake)
        let meanDur = allDur.reduce(0, +) / Double(allDur.count)

        // Group by ISO weekday (1=Sun … 7=Sat from Calendar)
        // SleepRecord.isWeekend tells us weekday info, but we need the actual day.
        // We'll infer weekday from the record index: day 0 = startDate, etc.
        // Since records are ordered by day and we need weekday, we'll use the isWeekend flag
        // and the pattern of records. For simplicity, map index to weekday.
        // Records don't carry a Date, but they have `isWeekend` and are ordered.
        // We'll reconstruct weekday from the index. The startDate isn't available here,
        // so we compute relative weekday from the sequence pattern.

        // Alternative approach: use pairs of (bedtime, wake, duration) grouped by
        // the record's day-of-week. Since records carry isWeekend, we at least know
        // weekday vs weekend. For richer patterns, we'll bucket by week position.
        // Records are 0-indexed. Group by (index % 7) as a proxy for recurring day.

        // Better approach: use a 7-bucket grouping from record indices.
        // We don't know the absolute weekday, but we DO have isWeekend.
        // Actually, Calendar stores records as (dayIndex, ...) — let's use the modular pattern.

        struct DaySamples {
            var bedtimes: [Double] = []
            var wakeups: [Double] = []
            var durations: [Double] = []
        }

        // Group by whether it's a "weekend type" day vs weekday, since that's what we have.
        // For better patterns, we'd need the actual weekday. Let's create 2 buckets.
        // Actually, for proper weekday pattern detection, the caller should provide startDate.
        // For now, we group into weekday bucket (5 days) vs weekend bucket (2 days).
        var weekdaySamples = DaySamples()
        var weekendSamples = DaySamples()
        for record in records {
            if record.isWeekend {
                weekendSamples.bedtimes.append(record.bedtimeHour)
                weekendSamples.wakeups.append(record.wakeupHour)
                weekendSamples.durations.append(record.sleepDuration)
            } else {
                weekdaySamples.bedtimes.append(record.bedtimeHour)
                weekdaySamples.wakeups.append(record.wakeupHour)
                weekdaySamples.durations.append(record.sleepDuration)
            }
        }

        var patterns: [TemporalPattern] = []

        // Weekday pattern (use weekday=2 as Monday representative)
        if weekdaySamples.bedtimes.count >= 2 {
            let wdBed = circularMeanHour(weekdaySamples.bedtimes)
            let wdWake = circularMeanHour(weekdaySamples.wakeups)
            let wdDur = weekdaySamples.durations.reduce(0, +) / Double(weekdaySamples.durations.count)
            let bedDev = circularDiffMinutes(actual: wdBed, target: meanBed)
            let wakeDev = circularDiffMinutes(actual: wdWake, target: meanWake)
            let durDev = (wdDur - meanDur) * 60
            let pattern = TemporalPattern(
                weekday: 2, // Monday (representative for weekdays)
                bedtimeDeviationMinutes: bedDev,
                wakeDeviationMinutes: wakeDev,
                durationDeviationMinutes: durDev,
                sampleCount: weekdaySamples.bedtimes.count
            )
            if pattern.isSignificant { patterns.append(pattern) }
        }

        // Weekend pattern (use weekday=7 as Saturday representative)
        if weekendSamples.bedtimes.count >= 2 {
            let weBed = circularMeanHour(weekendSamples.bedtimes)
            let weWake = circularMeanHour(weekendSamples.wakeups)
            let weDur = weekendSamples.durations.reduce(0, +) / Double(weekendSamples.durations.count)
            let bedDev = circularDiffMinutes(actual: weBed, target: meanBed)
            let wakeDev = circularDiffMinutes(actual: weWake, target: meanWake)
            let durDev = (weDur - meanDur) * 60
            let pattern = TemporalPattern(
                weekday: 7, // Saturday (representative for weekends)
                bedtimeDeviationMinutes: bedDev,
                wakeDeviationMinutes: wakeDev,
                durationDeviationMinutes: durDev,
                sampleCount: weekendSamples.bedtimes.count
            )
            if pattern.isSignificant { patterns.append(pattern) }
        }

        return patterns
    }

    // MARK: - Streak Computation

    /// Count consecutive recent nights where sleep was within the goal.
    /// "Within goal" = bedtime within tolerance AND duration within 1h of target.
    public static func computeStreaks(
        records: [SleepRecord],
        goal: SleepGoal,
        previousStreak: StreakData
    ) -> StreakData {
        guard !records.isEmpty else { return previousStreak }

        // Walk backwards from most recent record
        var currentStreak = 0
        for record in records.reversed() {
            let bedDev = abs(circularDiffMinutes(actual: record.bedtimeHour, target: goal.targetBedHour))
            let durOK = abs(record.sleepDuration - goal.targetDuration) <= 1.0
            let bedOK = bedDev <= goal.toleranceMinutes
            if bedOK && durOK {
                currentStreak += 1
            } else {
                break
            }
        }

        let bestStreak = max(previousStreak.bestStreak, currentStreak)
        let streakStart: Date? = currentStreak >= 2 ? Date() : nil
        let bestDate = currentStreak >= bestStreak ? Date() : previousStreak.bestStreakDate

        return StreakData(
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            streakStartDate: currentStreak >= 2 ? (previousStreak.streakStartDate ?? streakStart) : nil,
            bestStreakDate: bestDate
        )
    }

    // MARK: - Celebration Detection

    /// Detect positive achievements worth celebrating.
    public static func detectCelebrations(
        stats: SleepStats,
        previousStats: SleepStats?,
        streak: StreakData,
        compositeScore: Int,
        previousCompositeScore: Int?,
        goal: SleepGoal
    ) -> [ProgressCelebration] {
        var celebrations: [ProgressCelebration] = []

        guard let prev = previousStats else { return celebrations }

        // SRI improved ≥5 pts
        let sriDelta = stats.sri - prev.sri
        if sriDelta >= 5 {
            celebrations.append(ProgressCelebration(
                type: .sriImproved,
                message: "Your sleep regularity improved by \(Int(sriDelta)) points!",
                messageKey: "coach.celebration.sriImproved",
                args: [sriDelta]
            ))
        }

        // Consistency streak ≥3
        if streak.currentStreak >= 3 {
            celebrations.append(ProgressCelebration(
                type: .consistencyStreak,
                message: "\(streak.currentStreak)-night streak within your goal!",
                messageKey: "coach.celebration.consistencyStreak",
                args: [Double(streak.currentStreak)]
            ))
        }

        // New record streak
        if streak.isNewRecord {
            celebrations.append(ProgressCelebration(
                type: .bestWeekEver,
                message: "New personal record: \(streak.currentStreak) nights in a row!",
                messageKey: "coach.celebration.newRecord",
                args: [Double(streak.currentStreak)]
            ))
        }

        // Duration on target (mean within ±30 min)
        let durDelta = abs(stats.meanSleepDuration - goal.targetDuration) * 60
        let prevDurDelta = abs(prev.meanSleepDuration - goal.targetDuration) * 60
        if durDelta <= 30 && prevDurDelta > 30 {
            celebrations.append(ProgressCelebration(
                type: .durationOnTarget,
                message: "Your average sleep duration hit the target!",
                messageKey: "coach.celebration.durationOnTarget",
                args: [stats.meanSleepDuration]
            ))
        }

        // Composite score is best ever
        if let prevComp = previousCompositeScore, compositeScore > prevComp && compositeScore >= 80 {
            celebrations.append(ProgressCelebration(
                type: .bestWeekEver,
                message: "Best composite score so far: \(compositeScore)!",
                messageKey: "coach.celebration.bestScore",
                args: [Double(compositeScore)]
            ))
        }

        return celebrations
    }

    // MARK: - Micro-Habit Generation

    /// Generate today's micro-habit based on the current coach issue.
    /// Cycles through 7 variants so the user sees a fresh tip each day.
    public static func generateMicroHabit(issueKey: CoachIssueKey) -> MicroHabit {
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        let cycleDay = dayOfYear % 7

        let action: String
        switch issueKey {
        case .delayedPhase:
            let actions = [
                "Set a morning alarm and get outside for 5 min of sunlight.",
                "Dim all screens 1 hour before bed tonight.",
                "No caffeine after 14:00 today.",
                "Take a 10-min walk right after waking up.",
                "Set your bedroom lights to warm/dim at 21:00.",
                "Try a 5-min breathing exercise before bed.",
                "Move dinner 30 min earlier than yesterday."
            ]
            action = actions[cycleDay]
        case .insufficientDuration:
            let actions = [
                "Go to bed 15 min earlier than last night.",
                "Set a 'wind down' alarm 1 hour before target bedtime.",
                "No screens in the bedroom tonight.",
                "Write tomorrow's tasks before bed — clear your mind.",
                "Limit fluids 2 hours before bedtime.",
                "Keep the bedroom at 18–20°C tonight.",
                "Read a physical book for 20 min before sleep."
            ]
            action = actions[cycleDay]
        case .irregularSchedule:
            let actions = [
                "Set a fixed wake alarm — same time as yesterday.",
                "Eat breakfast within 1 hour of waking up.",
                "Expose yourself to bright light in the first 30 min.",
                "No snooze button today — feet on the floor immediately.",
                "Keep your wake time today identical to tomorrow's plan.",
                "Do a 5-min stretching routine at the same time each morning.",
                "Plan tomorrow's wake time now and set the alarm."
            ]
            action = actions[cycleDay]
        case .socialJetlag:
            let actions = [
                "Wake up within 30 min of your weekday time this weekend.",
                "Get morning light, even on days off.",
                "Eat meals at the same time as weekdays today.",
                "Avoid sleeping in more than 30 min today.",
                "Set a weekend wake alarm — consistency matters.",
                "Plan a morning activity to anchor your weekend wake time.",
                "Track your bedtime tonight — aim for your weekday window."
            ]
            action = actions[cycleDay]
        case .fragmentedSleep:
            let actions = [
                "Skip fluids 2 hours before bed.",
                "Set your bedroom to 18–20°C tonight.",
                "No caffeine after noon today.",
                "Try a progressive relaxation exercise in bed.",
                "Keep the room completely dark (blackout curtains or mask).",
                "If you wake up, don't check your phone.",
                "Use white noise or earplugs tonight."
            ]
            action = actions[cycleDay]
        case .maintenance:
            let actions = [
                "Great consistency! Protect your wake time today.",
                "Keep your sleep environment comfortable — you're in a groove.",
                "Stay active today to maintain your sleep quality.",
                "Check: is your bedroom still dark and cool enough?",
                "Maintain your wind-down routine tonight.",
                "You're on track — try adding 5 min of morning sunlight.",
                "Consistency is working! Stick with your current bedtime."
            ]
            action = actions[cycleDay]
        default:
            let actions = [
                "Log your sleep as soon as you wake up.",
                "Spend 10 min outside in natural light today.",
                "Keep a consistent bedtime tonight.",
                "Check your sleep environment: dark, cool, quiet?",
                "Avoid heavy meals 2 hours before bed.",
                "Try a relaxing activity before bedtime.",
                "Review your sleep data and notice any patterns."
            ]
            action = actions[cycleDay]
        }

        // For issue types without dedicated micro-habits, use "default" key.
        let keyBase: String
        switch issueKey {
        case .delayedPhase, .insufficientDuration, .irregularSchedule,
             .socialJetlag, .fragmentedSleep, .maintenance:
            keyBase = issueKey.rawValue
        default:
            keyBase = "default"
        }

        return MicroHabit(
            issueKey: issueKey,
            cycleDay: cycleDay,
            action: action,
            actionKey: "coach.microhabit.\(keyBase).\(cycleDay)"
        )
    }

    // MARK: - Weekly Digest

    /// Build a weekly digest comparing the last 7 records vs the 7 before that.
    public static func generateWeeklyDigest(
        records: [SleepRecord],
        stats: SleepStats,
        previousStats: SleepStats?,
        compositeScore: Int,
        previousCompositeScore: Int
    ) -> WeeklyDigest? {
        guard records.count >= 6 else { return nil }

        // Split: last 7 vs previous 7
        let count = records.count
        let thisWeek = Array(records.suffix(min(7, count)))
        let prevWeek: [SleepRecord]
        if count > 7 {
            let start = max(0, count - 14)
            let end = count - min(7, count)
            prevWeek = Array(records[start..<end])
        } else {
            return nil // Not enough for two-week comparison
        }
        guard prevWeek.count >= 3 else { return nil }

        // Compute per-week means
        let twBed = circularMeanHour(thisWeek.map(\.bedtimeHour))
        let pwBed = circularMeanHour(prevWeek.map(\.bedtimeHour))
        let twWake = circularMeanHour(thisWeek.map(\.wakeupHour))
        let pwWake = circularMeanHour(prevWeek.map(\.wakeupHour))
        let twDur = thisWeek.map(\.sleepDuration).reduce(0, +) / Double(thisWeek.count)
        let pwDur = prevWeek.map(\.sleepDuration).reduce(0, +) / Double(prevWeek.count)
        let twSRI = stats.sri
        let pwSRI = previousStats?.sri ?? 0

        // Best/worst day by duration (index within thisWeek)
        let bestIdx = thisWeek.enumerated().max(by: { $0.element.sleepDuration < $1.element.sleepDuration })
        let worstIdx = thisWeek.enumerated().min(by: { $0.element.sleepDuration < $1.element.sleepDuration })
        // Map to weekday: last record is "today", count back
        // Since we don't have dates, use relative position. Use isWeekend as a rough guide.
        let bestDay: Int? = bestIdx.map { $0.element.isWeekend ? 7 : 2 }
        let worstDay: Int? = worstIdx.map { $0.element.isWeekend ? 7 : 2 }

        return WeeklyDigest(
            meanBedtime: twBed,
            prevMeanBedtime: pwBed,
            meanWakeTime: twWake,
            prevMeanWakeTime: pwWake,
            meanDuration: twDur,
            prevMeanDuration: pwDur,
            sri: twSRI,
            prevSRI: pwSRI,
            compositeScore: compositeScore,
            prevCompositeScore: previousCompositeScore,
            bestDay: bestDay,
            worstDay: worstDay,
            thisWeekRecordCount: thisWeek.count,
            prevWeekRecordCount: prevWeek.count
        )
    }

    // MARK: - Event Acknowledgments

    /// Look at recent events (last 48h worth) and correlate with sleep quality.
    public static func acknowledgeEvents(
        events: [CircadianEvent],
        records: [SleepRecord]
    ) -> [EventAcknowledgment] {
        guard !events.isEmpty, records.count >= 2 else { return [] }
        var acknowledgments: [EventAcknowledgment] = []

        let lastRecord = records[records.count - 1]
        let prevRecord = records[records.count - 2]

        // Check for exercise events
        let recentExercise = events.filter { $0.type == .exercise }
        if !recentExercise.isEmpty {
            let durationDelta = (lastRecord.sleepDuration - prevRecord.sleepDuration) * 60
            let bedtimeDelta = circularDiffMinutes(actual: lastRecord.bedtimeHour, target: prevRecord.bedtimeHour)

            if bedtimeDelta < -10 || durationDelta > 15 {
                // Fell asleep earlier or slept longer after exercise
                acknowledgments.append(EventAcknowledgment(
                    eventType: .exercise,
                    effect: .positive,
                    message: "Yesterday's exercise may have helped — you fell asleep \(abs(Int(bedtimeDelta))) min earlier.",
                    messageKey: "coach.event.exercise.positive",
                    args: [abs(bedtimeDelta)]
                ))
            }
        }

        // Check for caffeine events
        let recentCaffeine = events.filter { $0.type == .caffeine }
        if !recentCaffeine.isEmpty {
            let bedtimeDelta = circularDiffMinutes(actual: lastRecord.bedtimeHour, target: prevRecord.bedtimeHour)
            if bedtimeDelta > 20 {
                acknowledgments.append(EventAcknowledgment(
                    eventType: .caffeine,
                    effect: .negative,
                    message: "Caffeine may have delayed your sleep by about \(Int(bedtimeDelta)) min.",
                    messageKey: "coach.event.caffeine.negative",
                    args: [bedtimeDelta]
                ))
            }
        }

        // Check for alcohol events
        let recentAlcohol = events.filter { $0.type == .alcohol }
        if !recentAlcohol.isEmpty {
            // Alcohol often increases fragmentation
            let lastFrag = lastRecord.hourlyActivity.filter { $0.activity > 0.3 }.count
            let prevFrag = prevRecord.hourlyActivity.filter { $0.activity > 0.3 }.count
            if lastFrag > prevFrag + 1 {
                acknowledgments.append(EventAcknowledgment(
                    eventType: .alcohol,
                    effect: .negative,
                    message: "Alcohol may have fragmented your sleep — more wake-ups than usual.",
                    messageKey: "coach.event.alcohol.negative",
                    args: [Double(lastFrag - prevFrag)]
                ))
            }
        }

        // Check for light events (positive for delayed phase)
        let recentLight = events.filter { $0.type == .light }
        if !recentLight.isEmpty {
            let bedtimeDelta = circularDiffMinutes(actual: lastRecord.bedtimeHour, target: prevRecord.bedtimeHour)
            if bedtimeDelta < -10 {
                acknowledgments.append(EventAcknowledgment(
                    eventType: .light,
                    effect: .positive,
                    message: "Morning light exposure may have helped you fall asleep \(abs(Int(bedtimeDelta))) min earlier.",
                    messageKey: "coach.event.light.positive",
                    args: [abs(bedtimeDelta)]
                ))
            }
        }

        // Check for melatonin events
        let recentMelatonin = events.filter { $0.type == .melatonin }
        if !recentMelatonin.isEmpty {
            let bedtimeDelta = circularDiffMinutes(actual: lastRecord.bedtimeHour, target: prevRecord.bedtimeHour)
            if bedtimeDelta < -15 {
                acknowledgments.append(EventAcknowledgment(
                    eventType: .melatonin,
                    effect: .positive,
                    message: "Melatonin may have advanced your bedtime by \(abs(Int(bedtimeDelta))) min.",
                    messageKey: "coach.event.melatonin.positive",
                    args: [abs(bedtimeDelta)]
                ))
            }
        }

        return acknowledgments
    }
}
