import Foundation

/// Discovers the user's optimal sleep duration by correlating duration with next-day quality.
public enum OptimalDurationAnalyzer {

    public struct OptimalDurationResult: Codable, Sendable {
        /// Optimal duration in hours (e.g., 7.33 = 7h 20min).
        public let optimalHours: Double
        /// Formatted string (e.g., "7h 20min").
        public let formatted: String
        /// Quality score at optimal duration [0,1].
        public let qualityAtOptimal: Double
        /// Number of nights analyzed.
        public let nightsAnalyzed: Int
        /// True if enough data to be confident (≥14 nights with quality data).
        public let isConfident: Bool
    }

    /// Analyze sleep records to find the duration that maximizes next-day quality.
    ///
    /// - Parameter records: Sleep records sorted by day. Needs ≥14 with cosinor data.
    /// - Returns: The optimal duration result, or nil if insufficient data.
    public static func analyze(records: [SleepRecord]) -> OptimalDurationResult? {
        let sorted = records.sorted { $0.day < $1.day }
        guard sorted.count >= 14 else { return nil }

        // Build (duration, nextDayQuality) pairs
        var pairs: [(duration: Double, quality: Double)] = []
        for i in 0..<(sorted.count - 1) {
            let tonight = sorted[i]
            let tomorrow = sorted[i + 1]
            guard tonight.sleepDuration >= 3.0,  // skip very short nights
                  tonight.sleepDuration <= 14.0,  // skip unrealistic
                  tomorrow.cosinor.r2 > 0         // need quality proxy
            else { continue }

            // Quality = cosinor R² of next day (how well the rhythm held)
            // Combined with whether duration met a reasonable range
            let quality = tomorrow.cosinor.r2
            pairs.append((tonight.sleepDuration, quality))
        }

        guard pairs.count >= 10 else { return nil }

        // Group by 30-min buckets: 5.0-5.5, 5.5-6.0, ..., 10.0-10.5
        var buckets: [Int: (totalQuality: Double, count: Int)] = [:]
        for pair in pairs {
            let bucketIdx = Int(pair.duration * 2)  // 7.25h → bucket 14
            buckets[bucketIdx, default: (0, 0)].totalQuality += pair.quality
            buckets[bucketIdx, default: (0, 0)].count += 1
        }

        // Find bucket with highest average quality (minimum 3 nights in bucket)
        var bestBucket = -1
        var bestAvgQuality = -1.0
        for (idx, data) in buckets {
            guard data.count >= 3 else { continue }
            let avg = data.totalQuality / Double(data.count)
            if avg > bestAvgQuality {
                bestAvgQuality = avg
                bestBucket = idx
            }
        }

        guard bestBucket >= 0 else { return nil }

        let optimalHours = Double(bestBucket) / 2.0 + 0.25  // center of bucket
        let totalH = Int(optimalHours)
        let totalM = Int((optimalHours - Double(totalH)) * 60)
        let formatted = totalM == 0 ? "\(totalH)h" : "\(totalH)h \(totalM)min"

        return OptimalDurationResult(
            optimalHours: optimalHours,
            formatted: formatted,
            qualityAtOptimal: bestAvgQuality,
            nightsAnalyzed: pairs.count,
            isConfident: pairs.count >= 21  // 3+ weeks of data
        )
    }
}
