import Foundation
import SpiralKit
import struct SpiralGeometry.WearableSleepSample
import struct SpiralGeometry.WearableTo4DMapper
import struct SpiralGeometry.SleepTrajectoryAnalysis
import enum SpiralGeometry.SleepStage

/// Headless helper that produces a NeuroSpiral 4D trajectory analysis for
/// the most recent sleep sessions and writes the summary into the App
/// Group UserDefaults where the Apple Watch app reads it.
///
/// The same logic exists inline inside `NeuroSpiralView.loadAndAnalyze()`
/// for the on-screen detail view — but that view is only mounted when the
/// user opens the DNA Insights sub-sheet, so the Watch summary never
/// refreshed after the DNA tab was redesigned. This helper lets any view
/// (currently `DNAModeView.task`) trigger the same update without having
/// to instantiate the heavy NeuroSpiral UI.
enum NeuroSpiralAnalyzer {

    /// App Group container identifier — must match the Watch target's
    /// `UserDefaults(suiteName:)` lookup in `WatchStore.updateFromDefaults`.
    private static let appGroupID = "group.xaron.spiral-journey-project"

    /// Compute the latest-night analysis and push the summary to the App
    /// Group so the Watch card renders real numbers instead of "no data".
    /// Runs off the main actor because the underlying `analyzeNight` is
    /// pure CPU work over synthesized samples.
    @discardableResult
    static func syncWatchSummary(records: [SleepRecord],
                                 hrvData: [NightlyHRV]) -> SleepTrajectoryAnalysis? {
        guard records.count >= 3 else { return nil }

        let samples = buildSamples(records: records, hrvData: hrvData)
        guard !samples.isEmpty else { return nil }

        var mapper = WearableTo4DMapper()
        let defaults = UserDefaults(suiteName: appGroupID)

        // Load an existing personal baseline if available, otherwise
        // seed it from the user's HRV history so the mapper has
        // something sensible to normalize against.
        if let data = defaults?.data(forKey: "neurospiral-baseline"),
           let saved = try? JSONDecoder().decode(WearableTo4DMapper.PersonalBaseline.self,
                                                  from: data) {
            mapper.baseline = saved
        } else if !hrvData.isEmpty {
            let meanHRV = hrvData.map(\.meanSDNN).reduce(0, +) / Double(hrvData.count)
            mapper.baseline.hrvMean = meanHRV
            mapper.baseline.hrvStd = hrvStandardDeviation(hrvData.map(\.meanSDNN))
        }

        let result = mapper.analyzeNight(samples)

        // Persist the (possibly updated) baseline for next time.
        if let encoded = try? JSONEncoder().encode(mapper.baseline) {
            defaults?.set(encoded, forKey: "neurospiral-baseline")
        }

        writeWatchData(analysis: result, defaults: defaults)
        return result
    }

    // MARK: - Sample synthesis

    /// Build `WearableSleepSample`s from `SleepRecord` phases + HRV.
    /// Copy of `NeuroSpiralView.buildSamplesFromRecords` — kept here so
    /// headless Watch-sync callers don't need to instantiate the full
    /// SwiftUI view to compute the same payload.
    private static func buildSamples(records: [SleepRecord],
                                     hrvData: [NightlyHRV]) -> [WearableSleepSample] {
        let recentRecords = records.suffix(7)
        let calendar = Calendar.current
        let isoFmt = ISO8601DateFormatter()
        var samples: [WearableSleepSample] = []

        var hrvByDate: [String: Double] = [:]
        for hrv in hrvData {
            hrvByDate[isoFmt.string(from: calendar.startOfDay(for: hrv.date))] = hrv.meanSDNN
        }

        let phaseTargets: [SleepPhase: (Double, Double, Double)] = [
            .deep:  (1.40, 0.82, 0.008),
            .light: (1.15, 0.90, 0.020),
            .rem:   (0.85, 0.97, 0.035),
            .awake: (0.65, 1.12, 0.18),
        ]
        let phaseStd: [SleepPhase: Double] = [
            .awake: 0.147, .light: 0.192, .deep: 0.152, .rem: 0.185
        ]

        for record in recentRecords {
            let nightHRV = hrvByDate[isoFmt.string(from: calendar.startOfDay(for: record.date))] ?? 50.0
            var currentHRV = nightHRV * 0.65
            var currentHR  = 65.0 * 1.12
            var currentMotion = 0.18
            var prevPhase: SleepPhase? = nil
            var transitionProgress = 0

            for phase in record.phases {
                let target = phaseTargets[phase.phase] ?? (1.0, 1.0, 0.05)
                let std = phaseStd[phase.phase] ?? 0.15
                let sleepStage = mapPhase(phase.phase)

                let isTransition = prevPhase != nil && prevPhase != phase.phase
                if isTransition { transitionProgress = 0 }
                let transitionEpochs = 4

                for epoch in 0..<30 {
                    let secondsOffset = phase.hour * 3600 + Double(epoch) * 30
                    let timestamp = calendar.startOfDay(for: record.date)
                        .addingTimeInterval(secondsOffset)

                    let targetHRV = nightHRV * target.0
                    let targetHR  = 65.0 * target.1
                    let targetMotion = target.2

                    let drift = 0.10

                    let noise = (Double.random(in: -1...1) + Double.random(in: -1...1)) / 2.0 * std

                    let transitionBlend: Double
                    if transitionProgress < transitionEpochs {
                        transitionBlend = Double(transitionProgress + 1) / Double(transitionEpochs)
                        transitionProgress += 1
                    } else {
                        transitionBlend = 1.0
                    }

                    let effectiveDrift = drift + (1.0 - transitionBlend) * 0.3

                    currentHRV = currentHRV * (1.0 - effectiveDrift) + targetHRV * effectiveDrift + noise * nightHRV * 0.1
                    currentHR  = currentHR  * (1.0 - effectiveDrift) + targetHR  * effectiveDrift + noise * 5.0
                    currentMotion = currentMotion * (1.0 - effectiveDrift) + targetMotion * effectiveDrift + abs(noise) * 0.03

                    let hrv = max(5, min(120, currentHRV))
                    let hr  = max(40, min(100, currentHR))
                    let motion = max(0, min(1.0, currentMotion))

                    samples.append(WearableSleepSample(
                        hrv: hrv,
                        heartRate: hr,
                        motionIntensity: motion,
                        sleepStage: sleepStage,
                        timestamp: timestamp
                    ))
                }
                prevPhase = phase.phase
            }
        }

        return samples
    }

    private static func mapPhase(_ phase: SleepPhase) -> SleepStage {
        switch phase {
        case .deep:  return .nrem
        case .light: return .nrem
        case .rem:   return .rem
        case .awake: return .active
        }
    }

    private static func hrvStandardDeviation(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 15.0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count - 1)
        return sqrt(variance)
    }

    // MARK: - Watch payload

    private static func writeWatchData(analysis: SleepTrajectoryAnalysis,
                                       defaults: UserDefaults?) {
        let vertex = analysis.residence.dominantVertex
        let watchData: [String: Any] = [
            "neurospiral_date": Date().timeIntervalSince1970,
            "neurospiral_stability": analysis.residence.stabilityScore,
            "neurospiral_dominant_idx": vertex.index,
            "neurospiral_dominant_code": formatCode(vertex.code),
            "neurospiral_winding": analysis.windingRatio ?? -1.0,
            "neurospiral_transitions": analysis.residence.transitionCount,
        ]
        defaults?.set(watchData, forKey: "neurospiral-last-night")
    }

    private static func formatCode(_ code: SIMD4<Int>) -> String {
        let fmt: (Int) -> String = { $0 > 0 ? "+" : "-" }
        return "\(fmt(code.x))\(fmt(code.y))\(fmt(code.z))\(fmt(code.w))"
    }
}
