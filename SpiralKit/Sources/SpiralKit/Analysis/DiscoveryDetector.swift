import Foundation

/// Detects milestones and discoveries from the user's sleep data.
/// Stateless — scans current state and returns all milestones that apply.
/// The caller is responsible for filtering out already-seen discoveries.
public enum DiscoveryDetector {

    /// Scan all available data and return discovered milestones.
    ///
    /// - Parameters:
    ///   - records: All sleep records.
    ///   - dnaProfile: Current SleepDNA profile (nil if not yet computed).
    ///   - consistency: Current consistency score (nil if insufficient data).
    ///   - periodograms: Lomb-Scargle results (nil if < 14 days).
    ///   - healthProfiles: Day health profiles from HealthKit.
    ///   - events: All circadian events (for auto-workout detection).
    ///   - startDate: The store's epoch date.
    /// - Returns: Array of discoveries, sorted by date.
    public static func detect(
        records: [SleepRecord],
        dnaProfile: SleepDNAProfile?,
        consistency: SpiralConsistencyScore?,
        periodograms: [LombScargle.PeriodogramResult]?,
        healthProfiles: [DayHealthProfile],
        events: [CircadianEvent],
        startDate: Date
    ) -> [Discovery] {
        var discoveries: [Discovery] = []
        let calendar = Calendar.current

        func dateFor(day: Int) -> Date {
            calendar.date(byAdding: .day, value: day, to: startDate) ?? startDate
        }

        let count = records.count
        guard count > 0 else { return [] }

        // MARK: - Data milestones

        discoveries.append(Discovery(
            type: .firstRecord, date: dateFor(day: 0), dayIndex: 0,
            titleKey: "discovery.firstRecord.title",
            detailKey: "discovery.firstRecord.detail",
            icon: "star.fill"
        ))

        let dataMilestones: [(Int, DiscoveryType, String)] = [
            (7, .oneWeek, "discovery.oneWeek"),
            (14, .twoWeeks, "discovery.twoWeeks"),
            (30, .oneMonth, "discovery.oneMonth"),
            (60, .twoMonths, "discovery.twoMonths"),
            (90, .threeMonths, "discovery.threeMonths"),
            (365, .oneYear, "discovery.oneYear"),
        ]
        for (threshold, type, key) in dataMilestones where count >= threshold {
            discoveries.append(Discovery(
                type: type, date: dateFor(day: threshold - 1), dayIndex: threshold - 1,
                titleKey: "\(key).title", detailKey: "\(key).detail",
                icon: "calendar.badge.checkmark"
            ))
        }

        // MARK: - DNA tier milestones

        if count >= 28 {
            discoveries.append(Discovery(
                type: .intermediateTier, date: dateFor(day: 27), dayIndex: 27,
                titleKey: "discovery.intermediateTier.title",
                detailKey: "discovery.intermediateTier.detail",
                icon: "dna"
            ))
        }
        if count >= 56 {
            discoveries.append(Discovery(
                type: .fullTier, date: dateFor(day: 55), dayIndex: 55,
                titleKey: "discovery.fullTier.title",
                detailKey: "discovery.fullTier.detail",
                icon: "dna"
            ))
        }

        // MARK: - DNA analysis milestones

        if let profile = dnaProfile {
            if !profile.motifs.isEmpty, let firstMotifDay = profile.motifs.first?.instanceWeekIndices.first {
                discoveries.append(Discovery(
                    type: .firstMotif, date: dateFor(day: firstMotifDay * 7), dayIndex: firstMotifDay * 7,
                    titleKey: "discovery.firstMotif.title",
                    detailKey: "discovery.firstMotif.detail",
                    icon: "repeat"
                ))
            }

            if profile.prediction != nil {
                let predDay = max(count - 1, 28)
                discoveries.append(Discovery(
                    type: .firstPrediction, date: dateFor(day: predDay), dayIndex: predDay,
                    titleKey: "discovery.firstPrediction.title",
                    detailKey: "discovery.firstPrediction.detail",
                    icon: "sparkles"
                ))
            }
        }

        // MARK: - Quality milestones

        if let score = consistency, score.score > 80 {
            discoveries.append(Discovery(
                type: .consistencyRecord, date: dateFor(day: count - 1), dayIndex: count - 1,
                titleKey: "discovery.consistencyRecord.title",
                detailKey: "discovery.consistencyRecord.detail",
                icon: "trophy.fill"
            ))
        }

        if let profile = dnaProfile,
           profile.healthMarkers.circadianCoherence > 0.6 {
            discoveries.append(Discovery(
                type: .circadianStable, date: dateFor(day: count - 1), dayIndex: count - 1,
                titleKey: "discovery.circadianStable.title",
                detailKey: "discovery.circadianStable.detail",
                icon: "checkmark.seal.fill"
            ))
        }

        // MARK: - Periodogram milestones

        if let results = periodograms {
            let allPeaks = results.flatMap(\.peaks)
            if allPeaks.contains(where: { $0.label == .circadian }) {
                discoveries.append(Discovery(
                    type: .circadianRhythm, date: dateFor(day: count - 1), dayIndex: count - 1,
                    titleKey: "discovery.circadianRhythm.title",
                    detailKey: "discovery.circadianRhythm.detail",
                    icon: "waveform.path"
                ))
            }
            if allPeaks.contains(where: { $0.label == .weekly }) {
                discoveries.append(Discovery(
                    type: .weeklyPattern, date: dateFor(day: count - 1), dayIndex: count - 1,
                    titleKey: "discovery.weeklyPattern.title",
                    detailKey: "discovery.weeklyPattern.detail",
                    icon: "calendar"
                ))
            }
        }

        // MARK: - Health milestones

        if !healthProfiles.isEmpty {
            guard let firstProfile = healthProfiles.first else { return discoveries }
            let firstDay = firstProfile.day
            discoveries.append(Discovery(
                type: .firstHealthProfile, date: dateFor(day: firstDay), dayIndex: firstDay,
                titleKey: "discovery.firstHealthProfile.title",
                detailKey: "discovery.firstHealthProfile.detail",
                icon: "heart.text.square.fill"
            ))
        }

        if events.contains(where: { $0.source == .healthKit && $0.type == .exercise }) {
            discoveries.append(Discovery(
                type: .firstAutoWorkout, date: dateFor(day: count - 1), dayIndex: count - 1,
                titleKey: "discovery.firstAutoWorkout.title",
                detailKey: "discovery.firstAutoWorkout.detail",
                icon: "figure.run"
            ))
        }

        // Deduplicate by type (keep earliest)
        var seen = Set<DiscoveryType>()
        let unique = discoveries.filter { seen.insert($0.type).inserted }

        return unique.sorted { $0.dayIndex < $1.dayIndex }
    }
}
