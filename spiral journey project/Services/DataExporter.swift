import Foundation
import SwiftData
import SpiralKit

/// Exports app data to CSV files for offline scientific analysis.
///
/// Generates: predictions.csv, healthmarkers.csv, motifs.csv, blosum.csv, questionnaire.csv
/// Returns a temporary directory URL suitable for sharing via UIActivityViewController.
@MainActor
enum DataExporter {

    // MARK: - Public API

    /// Export all validation data to a temporary directory.
    ///
    /// - Parameters:
    ///   - store: The app's SpiralStore (for prediction history).
    ///   - dnaProfile: The latest SleepDNA profile (for health markers, motifs, BLOSUM).
    ///   - context: SwiftData model context (for historical snapshots and questionnaire responses).
    /// - Returns: URL of the temporary directory containing CSV files, or `nil` on failure.
    static func exportAll(
        store: SpiralStore,
        dnaProfile: SleepDNAProfile?,
        context: ModelContext
    ) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("spiral-export-\(dateStamp())", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            try writePredictions(store.predictionHistory, to: dir)
            try writeHealthMarkers(dnaProfile: dnaProfile, context: context, to: dir)
            try writeMotifs(dnaProfile: dnaProfile, to: dir)
            try writeBLOSUM(dnaProfile: dnaProfile, to: dir)
            try writeQuestionnaire(context: context, to: dir)

            return dir
        } catch {
            print("[DataExporter] Export failed: \(error)")
            return nil
        }
    }

    // MARK: - Predictions CSV

    private static func writePredictions(_ history: [PredictionResult], to dir: URL) throws {
        var rows = ["date,predicted_bed,predicted_wake,predicted_duration,actual_bed,actual_wake,actual_duration,error_bed_min,error_wake_min,engine,confidence"]

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        for result in history {
            let p = result.prediction
            let dateStr = df.string(from: p.targetDate)
            let predBed = fmt(p.predictedBedtimeHour)
            let predWake = fmt(p.predictedWakeHour)
            let predDur = fmt(p.predictedDuration)

            let actBed = result.actual.map { fmt($0.bedtimeHour) } ?? ""
            let actWake = result.actual.map { fmt($0.wakeHour) } ?? ""
            let actDur = result.actual.map { fmt($0.duration) } ?? ""

            let errBed = result.errorBedtimeMinutes.map { fmt($0) } ?? ""
            let errWake = result.errorWakeMinutes.map { fmt($0) } ?? ""

            rows.append("\(dateStr),\(predBed),\(predWake),\(predDur),\(actBed),\(actWake),\(actDur),\(errBed),\(errWake),\(p.engine.rawValue),\(p.confidence.rawValue)")
        }

        let url = dir.appendingPathComponent("predictions.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Health Markers CSV

    private static func writeHealthMarkers(
        dnaProfile: SleepDNAProfile?,
        context: ModelContext,
        to dir: URL
    ) throws {
        var rows = ["date,coherence,fragmentation,drift,hb,hci,rds,rce,tier,data_weeks"]

        // Historical snapshots from SwiftData
        let descriptor = FetchDescriptor<SDSleepDNASnapshot>(
            sortBy: [SortDescriptor(\.computedAt, order: .forward)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        for snapshot in snapshots {
            guard let jsonData = snapshot.profileJSON,
                  let profile = try? JSONDecoder().decode(SleepDNAProfile.self, from: jsonData) else {
                continue
            }
            let hm = profile.healthMarkers
            let dateStr = df.string(from: snapshot.computedAt)
            rows.append(healthMarkerRow(dateStr: dateStr, hm: hm, tier: profile.tier, dataWeeks: profile.dataWeeks))
        }

        // If no snapshot matches the current profile, append it
        if let profile = dnaProfile {
            let dateStr = df.string(from: profile.computedAt)
            let alreadyIncluded = rows.contains { $0.hasPrefix(dateStr) }
            if !alreadyIncluded {
                let hm = profile.healthMarkers
                rows.append(healthMarkerRow(dateStr: dateStr, hm: hm, tier: profile.tier, dataWeeks: profile.dataWeeks))
            }
        }

        let url = dir.appendingPathComponent("healthmarkers.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func healthMarkerRow(dateStr: String, hm: HealthMarkers, tier: AnalysisTier, dataWeeks: Int) -> String {
        let rds = hm.remDriftSlope.map { fmt($0) } ?? ""
        let rce = hm.remClusterEntropy.map { fmt($0) } ?? ""
        return "\(dateStr),\(fmt(hm.circadianCoherence)),\(fmt(hm.fragmentationScore)),\(fmt(hm.driftSeverity)),\(fmt(hm.homeostasisBalance)),\(fmt(hm.helicalContinuity)),\(rds),\(rce),\(tier.rawValue),\(dataWeeks)"
    }

    // MARK: - Motifs CSV

    private static func writeMotifs(dnaProfile: SleepDNAProfile?, to dir: URL) throws {
        var rows = ["name,instance_count,avg_quality"]

        if let motifs = dnaProfile?.motifs {
            for motif in motifs {
                let name = csvEscape(motif.name)
                rows.append("\(name),\(motif.instanceCount),\(fmt(motif.avgQuality))")
            }
        }

        let url = dir.appendingPathComponent("motifs.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - BLOSUM CSV

    private static func writeBLOSUM(dnaProfile: SleepDNAProfile?, to dir: URL) throws {
        let featureNames: [String] = DayNucleotide.Feature.allCases.map { feature in
            switch feature {
            case .bedtimeSin:        return "bedtime_sin"
            case .bedtimeCos:        return "bedtime_cos"
            case .wakeupSin:         return "wakeup_sin"
            case .wakeupCos:         return "wakeup_cos"
            case .sleepDuration:     return "sleep_duration"
            case .processS:          return "process_s"
            case .cosinorAcrophase:  return "cosinor_acrophase"
            case .cosinorR2:         return "cosinor_r2"
            case .caffeine:          return "caffeine"
            case .exercise:          return "exercise"
            case .alcohol:           return "alcohol"
            case .melatonin:         return "melatonin"
            case .stress:            return "stress"
            case .isWeekend:         return "is_weekend"
            case .driftMinutes:      return "drift_minutes"
            case .sleepQuality:      return "sleep_quality"
            }
        }

        var rows = ["feature,weight"]

        if let weights = dnaProfile?.scoringMatrix.weights {
            for (i, name) in featureNames.enumerated() where i < weights.count {
                rows.append("\(name),\(fmt(weights[i]))")
            }
        }

        let url = dir.appendingPathComponent("blosum.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Questionnaire CSV

    private static func writeQuestionnaire(context: ModelContext, to dir: URL) throws {
        var rows = ["week_date,sleep_quality,daytime_sleepiness,pattern_accuracy,weekend_difference,notes,completed_at"]

        let descriptor = FetchDescriptor<SDQuestionnaireResponse>(
            sortBy: [SortDescriptor(\.weekDate, order: .forward)]
        )
        let responses = (try? context.fetch(descriptor)) ?? []

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]

        let dtf = ISO8601DateFormatter()
        dtf.formatOptions = [.withFullDate, .withTime, .withTimeZone]

        for r in responses {
            let weekStr = df.string(from: r.weekDate)
            let completedStr = dtf.string(from: r.completedAt)
            let notesStr = r.notes.map { csvEscape($0) } ?? ""
            rows.append("\(weekStr),\(r.sleepQuality),\(r.daytimeSleepiness),\(r.patternAccuracy),\(r.weekendDifference),\(notesStr),\(completedStr)")
        }

        let url = dir.appendingPathComponent("questionnaire.csv")
        try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func dateStamp() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmmss"
        return df.string(from: Date())
    }

    private static func fmt(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e9 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    /// Escape a string for CSV: wrap in quotes if it contains commas, quotes, or newlines.
    private static func csvEscape(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return string
    }
}
