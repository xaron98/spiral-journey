import Foundation

/// Conclusions Engine.
///
/// Synthesizes all analysis data into user-friendly scores and recommendations.
/// Port of src/utils/conclusions.js from the Spiral Journey web project.
public enum ConclusionsEngine {

    // MARK: - Helpers

    private static func safe(_ v: Double, fallback: Double = 0) -> Double {
        v.isFinite ? v : fallback
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, safe(v, fallback: lo)))
    }

    private static func mapScore(_ v: Double, inLo: Double, inHi: Double) -> Double {
        guard inHi != inLo else { return 50 }
        return clamp((v - inLo) / (inHi - inLo) * 100, 0, 100)
    }

    /// Duration score: 7-8h = 100, tapering to 0 below 4h or above 10h.
    private static func durationScore(_ hours: Double) -> Double {
        if hours >= 7 && hours <= 8 { return 100 }
        if hours < 7  { return mapScore(hours, inLo: 4, inHi: 7) }
        return mapScore(10 - hours, inLo: 0, inHi: 2)
    }

    private static func statusOf(_ score: Double) -> ScoreStatus {
        if score >= 70 { return .good }
        if score >= 40 { return .moderate }
        return .poor
    }

    /// Formats minutes as "Xh Ym" (e.g. 78 → "1h 18m", 45 → "45m").
    private static func formatMinutesAsHM(_ minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total)m" }
        let h = total / 60
        let m = total % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: - Composite Score

    /// Composite sleep quality score (0-100).
    /// Weights: SRI 25% | stability 20% | duration 20% | jetlag 15% | R² 10% | ampDrop 10%
    public static func compositeScore(stats: SleepStats) -> Int {
        let sriScore      = clamp(stats.sri, 0, 100)
        let stabilityScore = clamp(stats.rhythmStability * 100, 0, 100)
        let durScore      = durationScore(stats.meanSleepDuration)
        let jetlagScore   = clamp(100 - stats.socialJetlag, 0, 100)
        let r2Score       = clamp(stats.meanR2 * 100, 0, 100)
        let ampScore      = clamp(100 - abs(stats.ampDrop), 0, 100)

        let composite = sriScore * 0.25 + stabilityScore * 0.20 + durScore * 0.20
                      + jetlagScore * 0.15 + r2Score * 0.10 + ampScore * 0.10

        return Int(clamp(composite, 0, 100).rounded())
    }

    public static func scoreLabel(_ score: Int) -> String {
        switch score {
        case 85...: return "Excellent"
        case 70...: return "Good"
        case 50...: return "Moderate"
        default:    return "Needs Attention"
        }
    }

    public static func scoreLabelKey(_ score: Int) -> ScoreLabel {
        switch score {
        case 85...: return .excellent
        case 70...: return .good
        case 50...: return .moderate
        default:    return .needsAttention
        }
    }

    public static func scoreHexColor(_ score: Int) -> String {
        if score >= 70 { return "#5bffa8" }
        if score >= 40 { return "#f5c842" }
        return "#f05050"
    }

    // MARK: - Categories

    public static func evaluateCategories(stats: SleepStats, signatures: [DisorderSignature]) -> [CategoryScore] {
        var categories: [CategoryScore] = []

        // 1. Sleep Duration
        let dur = safe(stats.meanSleepDuration)
        let durSc = durationScore(dur)
        let durDetailKey: CategoryDetailKey
        let durDetail: String
        if dur == 0 { durDetailKey = .noData; durDetail = "No sleep data recorded" }
        else if dur < 7 { durDetailKey = .belowRecommended; durDetail = "Below the recommended 7h" }
        else if dur > 9 { durDetailKey = .excessive; durDetail = "Excessive duration (may indicate hypersomnia)" }
        else { durDetailKey = .healthy; durDetail = "Within healthy range (7-9h)" }
        categories.append(CategoryScore(
            id: "duration", label: "Duration",
            value: dur > 0 ? String(format: "%.1fh", dur) : "--",
            score: Int(durSc.rounded()), status: statusOf(durSc), detail: durDetail,
            labelKey: .duration, detailKey: durDetailKey, detailArgs: [dur]
        ))

        // 2. Regularity (SRI)
        let sri = safe(stats.sri)
        let sriSc = clamp(sri, 0, 100)
        let sriDetailKey: CategoryDetailKey
        let sriDetail: String
        if sri >= 80 { sriDetailKey = .veryConsistent; sriDetail = "Very consistent day-to-day pattern" }
        else if sri >= 60 { sriDetailKey = .someVariability; sriDetail = "Some variability between days" }
        else { sriDetailKey = .highVariability; sriDetail = "High variability — shifting schedules" }
        categories.append(CategoryScore(
            id: "regularity", label: "Regularity",
            value: sri > 0 ? String(format: "%.0f%%", sri) : "--",
            score: Int(sriSc.rounded()), status: statusOf(sriSc), detail: sriDetail,
            labelKey: .regularity, detailKey: sriDetailKey, detailArgs: [sri]
        ))

        // 3. Rhythm Strength
        let stab = safe(stats.rhythmStability)
        let stabSc = clamp(stab * 100, 0, 100)
        let stabDetailKey: CategoryDetailKey
        let stabDetail: String
        if stabSc >= 70 { stabDetailKey = .strongRhythm; stabDetail = "Strong, well-defined circadian rhythm" }
        else if stabSc >= 40 { stabDetailKey = .moderateRhythm; stabDetail = "Moderate rhythm — room for improvement" }
        else { stabDetailKey = .weakRhythm; stabDetail = "Weak or fragmented rhythm" }
        categories.append(CategoryScore(
            id: "rhythm", label: "Rhythm",
            value: String(format: "%.0f%%", stabSc),
            score: Int(stabSc.rounded()), status: statusOf(stabSc), detail: stabDetail,
            labelKey: .rhythm, detailKey: stabDetailKey, detailArgs: [stabSc]
        ))

        // 4. Social Jetlag
        let jl = safe(stats.socialJetlag)
        let jetlagSc = clamp(100 - jl, 0, 100)
        let jlDetailKey: CategoryDetailKey
        let jlDetail: String
        if jl < 45 { jlDetailKey = .minimalJetlag; jlDetail = "Minimal difference between weekdays and weekend" }
        else if jl < 90 { jlDetailKey = .moderateJetlag; jlDetail = "Moderate difference — try to reduce it" }
        else { jlDetailKey = .highJetlag; jlDetail = "High social jetlag — metabolic risk" }
        categories.append(CategoryScore(
            id: "jetlag", label: "Social Jetlag",
            value: formatMinutesAsHM(jl),
            score: Int(jetlagSc.rounded()), status: statusOf(jetlagSc), detail: jlDetail,
            labelKey: .jetlag, detailKey: jlDetailKey, detailArgs: [jl]
        ))

        // 5. Circadian Pattern
        let topSig = signatures.first
        let patternSc: Double
        if let sig = topSig {
            patternSc = sig.id == "normal"
                ? clamp(sig.confidence * 100, 50, 100)
                : clamp((1 - sig.confidence) * 100, 0, 60)
        } else {
            patternSc = 50
        }
        categories.append(CategoryScore(
            id: "pattern", label: "Pattern",
            value: topSig?.label ?? "--",
            score: Int(patternSc.rounded()), status: statusOf(patternSc),
            detail: topSig?.description ?? "Insufficient data",
            labelKey: .pattern, detailKey: .patternInsufficient, detailArgs: []
        ))

        // 6. Sleep Timing
        let acro = safe(stats.meanAcrophase, fallback: 15)
        let timingSc: Double = (acro >= 13 && acro <= 17) ? 100 : clamp(100 - abs(acro - 15) * 15, 0, 100)
        let h = Int(acro); let m = Int((acro - Double(h)) * 60)
        let timingDetailKey: CategoryDetailKey
        let timingDetail: String
        if acro >= 13 && acro <= 17 { timingDetailKey = .normalTiming; timingDetail = "Activity peak in normal range (13-17h)" }
        else if acro < 13 { timingDetailKey = .earlyTiming; timingDetail = "Early activity peak (advanced phase pattern)" }
        else { timingDetailKey = .lateTiming; timingDetail = "Late activity peak (delayed phase pattern)" }
        categories.append(CategoryScore(
            id: "timing", label: "Timing",
            value: String(format: "%02d:%02d", h, m),
            score: Int(timingSc.rounded()), status: statusOf(timingSc), detail: timingDetail,
            labelKey: .timing, detailKey: timingDetailKey, detailArgs: [acro]
        ))

        return categories
    }

    // MARK: - Trends

    public static func analyzeTrends(records: [SleepRecord]) -> TrendAnalysis {
        var improving:    [TrendItem] = []
        var deteriorating: [TrendItem] = []
        var stable:        [TrendItem] = []

        guard records.count >= 6 else {
            stable.append(TrendItem(label: "Insufficient data",
                                    detail: "At least 6 days needed to see trends",
                                    labelKey: .insufficientData, detailKey: .needMoreDays))
            return TrendAnalysis(improving: improving, deteriorating: deteriorating, stable: stable)
        }

        let mid = records.count / 2
        let first = Array(records[..<mid])
        let second = Array(records[mid...])
        func mean(_ arr: [Double]) -> Double { arr.isEmpty ? 0 : arr.reduce(0, +) / Double(arr.count) }

        // Amplitude trend
        let amp1 = mean(first.map(\.cosinor.amplitude))
        let amp2 = mean(second.map(\.cosinor.amplitude))
        let ampDelta = amp1 > 0.01 ? ((amp2 - amp1) / amp1) * 100 : 0
        if ampDelta > 10 {
            improving.append(TrendItem(label: "Rhythm Strength",
                detail: String(format: "Amplitude up %.0f%%", ampDelta),
                labelKey: .rhythmStrength, detailKey: .amplitudeUp, detailArgs: [ampDelta]))
        } else if ampDelta < -10 {
            deteriorating.append(TrendItem(label: "Rhythm Strength",
                detail: String(format: "Amplitude down %.0f%%", abs(ampDelta)),
                labelKey: .rhythmStrength, detailKey: .amplitudeDown, detailArgs: [abs(ampDelta)]))
        } else {
            stable.append(TrendItem(label: "Rhythm Strength",
                detail: "Amplitude stable",
                labelKey: .rhythmStrength, detailKey: .amplitudeStable))
        }

        // Duration trend
        let dur1 = mean(first.map(\.sleepDuration))
        let dur2 = mean(second.map(\.sleepDuration))
        let durDelta = dur2 - dur1
        if durDelta > 0.3 {
            improving.append(TrendItem(label: "Sleep Duration",
                detail: String(format: "+%.0f min/night", durDelta * 60),
                labelKey: .sleepDuration, detailKey: .durationUp, detailArgs: [durDelta * 60]))
        } else if durDelta < -0.3 {
            deteriorating.append(TrendItem(label: "Sleep Duration",
                detail: String(format: "%.0f min/night", durDelta * 60),
                labelKey: .sleepDuration, detailKey: .durationDown, detailArgs: [durDelta * 60]))
        } else {
            stable.append(TrendItem(label: "Sleep Duration",
                detail: "No significant changes",
                labelKey: .sleepDuration, detailKey: .durationStable))
        }

        // R² trend
        let r21 = mean(first.map(\.cosinor.r2))
        let r22 = mean(second.map(\.cosinor.r2))
        let r2Delta = r22 - r21
        if r2Delta > 0.05 {
            improving.append(TrendItem(label: "Rhythm Clarity",
                detail: String(format: "R² improved (%.2f → %.2f)", r21, r22),
                labelKey: .rhythmClarity, detailKey: .r2Up, detailArgs: [r21, r22]))
        } else if r2Delta < -0.05 {
            deteriorating.append(TrendItem(label: "Rhythm Clarity",
                detail: String(format: "R² worsened (%.2f → %.2f)", r21, r22),
                labelKey: .rhythmClarity, detailKey: .r2Down, detailArgs: [r21, r22]))
        } else {
            stable.append(TrendItem(label: "Rhythm Clarity",
                detail: "No significant changes",
                labelKey: .rhythmClarity, detailKey: .r2Stable))
        }

        return TrendAnalysis(improving: improving, deteriorating: deteriorating, stable: stable)
    }

    // MARK: - Recommendations

    public static func generateRecommendations(stats: SleepStats, signatures: [DisorderSignature], trends: TrendAnalysis) -> [Recommendation] {
        var recs: [Recommendation] = []

        let dur  = safe(stats.meanSleepDuration)
        let acro = safe(stats.meanAcrophase)
        // SRI is only meaningful when ≥2 records exist; value of 0 can be a
        // data-insufficiency artifact rather than genuinely low regularity.
        let sri  = stats.sri > 0 ? safe(stats.sri) : 100.0
        let jl   = safe(stats.socialJetlag)
        let stab = safe(stats.rhythmStability)

        // Delayed phase — detectable even from a single record.
        // Takes priority over generic "consistent schedule" advice because
        // the schedule may already BE consistent, just consistently too late.
        let isDelayedPhase = acro > 18.5 || signatures.contains(where: { $0.id == "dswpd" })
        if isDelayedPhase {
            recs.append(Recommendation(priority: 1,
                title: "Advance circadian phase",
                text: "Your sleep timing is significantly delayed. Bright morning light (10,000 lux or sunlight) for 20-30 min on waking is the most effective treatment. Shift bedtime 15 min earlier every 2 days. Avoid blue light after 21:00.",
                key: .advancePhase))
        }

        if dur > 0 && dur < 6.5 {
            recs.append(Recommendation(priority: 1,
                title: "Increase sleep hours",
                text: String(format: "You average %.1fh of sleep. Aim for 7-8h by setting a fixed bedtime and disconnecting screens 1h before bed.", dur),
                key: .increaseSleep, args: [dur]))
        } else if dur > 0 && dur < 7 {
            recs.append(Recommendation(priority: 2,
                title: "Improve sleep duration",
                text: String(format: "At %.1fh you're close to optimal. Try going to bed 30 min earlier to reach 7h.", dur),
                key: .improveDuration, args: [dur]))
        }

        // Only flag low regularity when we have enough data (sri > 0 means ≥2 records)
        // and the issue isn't just delayed phase (which needs phase-advance, not generic schedule advice)
        if !isDelayedPhase {
            if sri < 60 {
                recs.append(Recommendation(priority: 1,
                    title: "Maintain consistent schedules",
                    text: "Your regularity is low. Set a fixed wake-up time (even on weekends) with less than 30 minutes variation.",
                    key: .consistentSchedule))
            } else if sri < 80 {
                recs.append(Recommendation(priority: 3,
                    title: "Stabilize sleep schedules",
                    text: "Good regularity, but room to improve. Reduce the weekday/weekend difference to under 1 hour.",
                    key: .stabilizeSchedule))
            }
        }

        if jl > 90 {
            recs.append(Recommendation(priority: 1,
                title: "Reduce social jetlag",
                text: String(format: "%.0f minutes of difference between weekdays and weekend — equivalent to crossing time zones every week. Affects metabolism and cognition.", jl),
                key: .reduceSocialJetlag, args: [jl]))
        } else if jl > 45 {
            recs.append(Recommendation(priority: 2,
                title: "Minimize weekend lag",
                text: String(format: "%.0f min of lag. Try keeping weekend schedules closer to weekdays.", jl),
                key: .minimizeWeekendLag, args: [jl]))
        }

        if stab < 0.4 {
            recs.append(Recommendation(priority: 1,
                title: "Strengthen circadian rhythm",
                text: "Your circadian rhythm is weak. Bright light exposure in the morning (20-30 min) and darkness at night are the strongest zeitgebers.",
                key: .strengthenRhythm))
        } else if stab < 0.7 {
            recs.append(Recommendation(priority: 2,
                title: "Reinforce circadian cues",
                text: "Moderate rhythm. Enhance zeitgebers: morning light, regular meals, daytime exercise (not in the evening).",
                key: .reinforceZeitgebers))
        }

        if let topSig = signatures.first(where: { $0.id != "normal" && $0.id != "dswpd" }) {
            switch topSig.id {
            case "n24swd":
                recs.append(Recommendation(priority: 1,
                    title: "Stabilize circadian period",
                    text: "Progressive drift detected. Combining bright morning light + low-dose melatonin (0.5 mg) 5-7 h before sleep can anchor the rhythm to 24 h.",
                    key: .stabilizePeriod))
            case "iswrd":
                recs.append(Recommendation(priority: 1,
                    title: "Structure daily routine",
                    text: "Highly fragmented rhythm. Set fixed anchors: wake-up time, meals, and exercise at the same time each day. Social structure reinforces the biological clock.",
                    key: .structureRoutine))
            default: break
            }
        }

        if !trends.deteriorating.isEmpty {
            let names = trends.deteriorating.map { $0.label.lowercased() }.joined(separator: ", ")
            recs.append(Recommendation(priority: 2,
                title: "Address negative trends",
                text: "Deterioration observed in: \(names). Review recent habit changes that may explain this trend.",
                key: .addressNegativeTrends))
        }

        let composite = compositeScore(stats: stats)
        if composite < 70 && recs.count < 5 {
            recs.append(Recommendation(priority: 3,
                title: "Review stimulant intake",
                text: "Caffeine has a half-life of 5-7 h. Avoiding coffee after 14:00 can improve sleep latency and depth.",
                key: .reviewStimulants))
        }

        return recs.sorted { $0.priority < $1.priority }.prefix(5).map { $0 }
    }

    // MARK: - Full Report

    /// Generate the complete analysis result evaluated against the provided SleepGoal.
    /// The result's `coachInsight` is populated based on the goal mode.
    public static func generate(from records: [SleepRecord], goal: SleepGoal) -> AnalysisResult {
        var result = generate(from: records)
        let meaningful = records.filter { $0.sleepDuration >= 3.0 }
        result.coachInsight = CoachEngine.evaluate(
            records: meaningful.isEmpty ? records : meaningful,
            stats: result.stats,
            goal: goal,
            consistency: result.consistency
        )
        return result
    }

    /// Generate the complete analysis result from a set of sleep records.
    /// `coachInsight` will be `nil`; use `generate(from:goal:)` to populate it.
    public static func generate(from records: [SleepRecord]) -> AnalysisResult {
        // Only use records with meaningful sleep (≥3h) for statistics and analysis.
        // Stub records (< 3h) are artefacts of ManualDataConverter when an episode crosses midnight.
        let meaningfulRecords = records.filter { $0.sleepDuration >= 3.0 }
        let stats      = SleepStatistics.calculateStats(meaningfulRecords.isEmpty ? records : meaningfulRecords)
        let signatures = DisorderDetection.detect(from: records)
        let trends     = analyzeTrends(records: records)
        let composite  = compositeScore(stats: stats)
        let categories = evaluateCategories(stats: stats, signatures: signatures)
        let recs       = generateRecommendations(stats: stats, signatures: signatures, trends: trends)

        // Compute Spiral Consistency Score (nil if < 2 nights with data)
        let consistency: SpiralConsistencyScore? = records.filter { $0.sleepDuration > 0 }.count >= 2
            ? SpiralConsistencyCalculator.compute(records: records, windowDays: 7)
            : nil

        return AnalysisResult(
            composite:       composite,
            label:           scoreLabel(composite),
            hexColor:        scoreHexColor(composite),
            scoreKey:        scoreLabelKey(composite),
            categories:      categories,
            trends:          trends,
            recommendations: recs,
            signatures:      signatures,
            stats:           stats,
            consistency:     consistency
        )
    }
}
