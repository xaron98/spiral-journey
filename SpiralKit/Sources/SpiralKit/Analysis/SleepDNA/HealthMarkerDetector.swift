import Foundation

// MARK: - Types

/// Health markers derived from sleep data analysis over a 14-day window.
public struct HealthMarkers: Codable, Sendable {
    /// Mean cosinorR² over 14 days, [0,1].
    public let circadianCoherence: Double
    /// Awake transitions normalized, [0,1].
    public let fragmentationScore: Double
    /// abs(mean drift min/day).
    public let driftSeverity: Double
    /// Homeostasis balance: mean|C-S|, [0,1].
    public let homeostasisBalance: Double
    /// Slope of REM phase centers (linear regression), nil if < 3 REM phases.
    public let remDriftSlope: Double?
    /// Helical continuity index: 1 - breaks/total, [0,1].
    public let helicalContinuity: Double
    /// Shannon entropy of REM intervals, nil if < 3 intervals.
    public let remClusterEntropy: Double?
    /// Reserved for future use.
    public let paradoxicalInsomnia: Double?
    /// Generated alerts based on marker thresholds.
    public let alerts: [HealthAlert]
}

/// An alert generated when a health marker exceeds a threshold.
public struct HealthAlert: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: AlertType
    public let severity: AlertSeverity
    public let message: String

    public init(id: UUID = UUID(), type: AlertType, severity: AlertSeverity, message: String) {
        self.id = id
        self.type = type
        self.severity = severity
        self.message = message
    }
}

public enum AlertType: String, Codable, Sendable {
    case circadianAnarchy
    case highFragmentation
    case severeDrift
    case highDesynchrony
    case remDriftAbnormal
    case novelPattern
}

public enum AlertSeverity: String, Codable, Sendable {
    case info
    case warning
    case urgent
}

// MARK: - Detector

/// Analyzes sleep records and two-process model data to produce health markers and alerts.
public enum HealthMarkerDetector {

    // Alert thresholds — used by HealthInsightRules for proximity warnings
    public static let circadianCoherenceThreshold = 0.2
    public static let fragmentationScoreThreshold = 0.6
    public static let driftSeverityThreshold = 15.0
    public static let homeostasisBalanceThreshold = 0.3

    /// Analyze the most recent 14 records and optional two-process points.
    ///
    /// - Parameters:
    ///   - records: Sleep records (last 14 used).
    ///   - twoProcessPoints: Optional two-process model output for homeostasis balance.
    /// - Returns: Computed health markers with alerts.
    public static func analyze(
        records: [SleepRecord],
        twoProcessPoints: [TwoProcessPoint]? = nil
    ) -> HealthMarkers {
        let window = Array(records.suffix(14))
        guard !window.isEmpty else {
            return emptyMarkers()
        }

        let coherence = computeCircadianCoherence(window)
        let fragmentation = computeFragmentationScore(window)
        let drift = computeDriftSeverity(window)
        let hb = computeHomeostasisBalance(twoProcessPoints)
        let hci = computeHelicalContinuity(window)
        let rds = computeREMDriftSlope(window)
        let rce = computeREMClusterEntropy(window)

        var alerts: [HealthAlert] = []

        if coherence < 0.2 {
            alerts.append(HealthAlert(
                type: .circadianAnarchy,
                severity: .urgent,
                message: "Circadian coherence is very low (\(String(format: "%.2f", coherence))). Your rhythm may be destabilized."
            ))
        }
        if fragmentation > 0.6 {
            alerts.append(HealthAlert(
                type: .highFragmentation,
                severity: .warning,
                message: "Sleep fragmentation is high (\(String(format: "%.2f", fragmentation))). Frequent awakenings detected."
            ))
        }
        if drift > 15 {
            alerts.append(HealthAlert(
                type: .severeDrift,
                severity: .warning,
                message: "Circadian drift is severe (\(String(format: "%.1f", drift)) min/day). Schedule may be shifting rapidly."
            ))
        }
        if hb > 0.3 {
            alerts.append(HealthAlert(
                type: .highDesynchrony,
                severity: .warning,
                message: "Homeostatic-circadian desynchrony is elevated (\(String(format: "%.2f", hb)))."
            ))
        }

        return HealthMarkers(
            circadianCoherence: coherence,
            fragmentationScore: fragmentation,
            driftSeverity: drift,
            homeostasisBalance: hb,
            remDriftSlope: rds,
            helicalContinuity: hci,
            remClusterEntropy: rce,
            paradoxicalInsomnia: nil,
            alerts: alerts
        )
    }

    // MARK: - Computations

    /// Mean of cosinor R² values.
    private static func computeCircadianCoherence(_ records: [SleepRecord]) -> Double {
        let values = records.map(\.cosinor.r2)
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of (awake phase count / 10, capped at 1.0) per night.
    private static func computeFragmentationScore(_ records: [SleepRecord]) -> Double {
        let values = records.map { record -> Double in
            let awakeCount = Double(record.phases.filter { $0.phase == .awake }.count)
            return min(awakeCount / 10.0, 1.0)
        }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of abs(driftMinutes).
    private static func computeDriftSeverity(_ records: [SleepRecord]) -> Double {
        let values = records.map { abs($0.driftMinutes) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of abs(c - s) from two-process points. Default 0.5 if no points.
    private static func computeHomeostasisBalance(_ points: [TwoProcessPoint]?) -> Double {
        guard let points = points, !points.isEmpty else { return 0.5 }
        let values = points.map { abs($0.c - $0.s) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Mean of (1 - awakePhases/totalPhases) per night.
    private static func computeHelicalContinuity(_ records: [SleepRecord]) -> Double {
        let values = records.map { record -> Double in
            let total = record.phases.count
            guard total > 0 else { return 1.0 }
            let awakeCount = record.phases.filter { $0.phase == .awake }.count
            return 1.0 - Double(awakeCount) / Double(total)
        }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Linear regression slope of REM phase `.hour` values across all records.
    /// Returns nil if fewer than 3 REM phases total.
    private static func computeREMDriftSlope(_ records: [SleepRecord]) -> Double? {
        // Collect all REM phases with an index for linear regression
        var remHours: [(x: Double, y: Double)] = []
        var index = 0.0
        for record in records {
            for phase in record.phases where phase.phase == .rem {
                remHours.append((x: index, y: phase.hour))
                index += 1
            }
        }

        guard remHours.count >= 3 else { return nil }

        // Simple linear regression: slope = (n*sum(xy) - sum(x)*sum(y)) / (n*sum(x²) - (sum(x))²)
        let n = Double(remHours.count)
        let sumX = remHours.reduce(0.0) { $0 + $1.x }
        let sumY = remHours.reduce(0.0) { $0 + $1.y }
        let sumXY = remHours.reduce(0.0) { $0 + $1.x * $1.y }
        let sumX2 = remHours.reduce(0.0) { $0 + $1.x * $1.x }

        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-14 else { return 0 }

        return (n * sumXY - sumX * sumY) / denom
    }

    /// Shannon entropy of intervals between consecutive REM phases.
    /// Returns nil if fewer than 3 intervals.
    private static func computeREMClusterEntropy(_ records: [SleepRecord]) -> Double? {
        // Collect all REM phase timestamps in order
        var remTimestamps: [Double] = []
        for record in records {
            for phase in record.phases where phase.phase == .rem {
                remTimestamps.append(phase.timestamp)
            }
        }

        // Compute intervals
        guard remTimestamps.count >= 4 else { return nil } // need at least 4 points for 3 intervals
        let intervals = (1..<remTimestamps.count).map { remTimestamps[$0] - remTimestamps[$0 - 1] }
        guard intervals.count >= 3 else { return nil }

        // Bin intervals into categories for entropy calculation
        // Use quantile-based binning: short (< median/2), medium, long (> median*2)
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let shortThreshold = median * 0.5
        let longThreshold = median * 2.0

        var bins: [String: Int] = ["short": 0, "medium": 0, "long": 0]
        for interval in intervals {
            if interval < shortThreshold {
                bins["short", default: 0] += 1
            } else if interval > longThreshold {
                bins["long", default: 0] += 1
            } else {
                bins["medium", default: 0] += 1
            }
        }

        // Shannon entropy: H = -sum(p * log2(p))
        let total = Double(intervals.count)
        var entropy = 0.0
        for (_, count) in bins {
            guard count > 0 else { continue }
            let p = Double(count) / total
            entropy -= p * log2(p)
        }

        return entropy
    }

    private static func emptyMarkers() -> HealthMarkers {
        HealthMarkers(
            circadianCoherence: 0,
            fragmentationScore: 0,
            driftSeverity: 0,
            homeostasisBalance: 0.5,
            remDriftSlope: nil,
            helicalContinuity: 1,
            remClusterEntropy: nil,
            paradoxicalInsomnia: nil,
            alerts: []
        )
    }
}

// MARK: - Convenience typealias

/// Alias for the nested TwoProcessPoint type used by HealthMarkerDetector.
public typealias TwoProcessPoint = TwoProcessModel.TwoProcessPoint
