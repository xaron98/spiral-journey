import Foundation

/// Stateless engine for evaluating sleepiness risk during scheduled work/study blocks.
///
/// Uses the Two-Process Model (Process S: homeostatic sleep pressure + Process C: circadian)
/// to estimate when the user is most likely to experience reduced alertness during their
/// scheduled obligations.
///
/// The key problem for shift workers: sleeping by day with high S accumulation,
/// but the circadian component promotes wakefulness → premature awakening (4–6 h)
/// and elevated sleepiness during night-shift hours.
///
/// References:
///   - Boivin (2021): S/C misalignment framework for explaining shift-work sleep loss.
///   - Pedersen et al. (2022): PSG evidence of daytime sleep truncation after 3 nights.
///
/// Follows the same pattern as `NapOptimizer`, `DisorderDetection`: stateless enum,
/// static methods, fully testable.
public enum SleepinessRiskEngine {

    // MARK: - Types

    /// Risk level during a work block.
    public enum RiskLevel: String, Codable, Sendable, Comparable {
        case low
        case moderate
        case high

        public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
            let order: [RiskLevel: Int] = [.low: 0, .moderate: 1, .high: 2]
            return (order[lhs] ?? 0) < (order[rhs] ?? 0)
        }
    }

    /// Sleepiness risk assessment for a single context block.
    public struct WorkHourRisk: Codable, Sendable {
        /// ID of the assessed context block.
        public let blockID: UUID
        /// Denormalized block label for display.
        public let blockLabel: String
        /// Block type.
        public let blockType: ContextBlockType
        /// Clock hour within the block where sleepiness is highest.
        public let peakSleepinessHour: Double
        /// Mean Process S value during the block (0.0–1.0 scale).
        public let meanS: Double
        /// Overall risk classification.
        public let riskLevel: RiskLevel

        public init(blockID: UUID, blockLabel: String, blockType: ContextBlockType,
                    peakSleepinessHour: Double, meanS: Double, riskLevel: RiskLevel) {
            self.blockID = blockID
            self.blockLabel = blockLabel
            self.blockType = blockType
            self.peakSleepinessHour = peakSleepinessHour
            self.meanS = meanS
            self.riskLevel = riskLevel
        }
    }

    // MARK: - Thresholds

    /// S above this during a work block = high risk.
    /// Justified: NapOptimizer uses 0.55 for nap recommendation; 0.65 during active
    /// work represents significantly impaired performance.
    private static let highRiskThreshold: Double = 0.65

    /// S above this during a work block = moderate risk.
    private static let moderateRiskThreshold: Double = 0.50

    // MARK: - Public API

    /// Evaluate sleepiness risk during each context block on the most recent day.
    ///
    /// - Parameters:
    ///   - records: Sleep records used to compute the Two-Process Model curves.
    ///   - contextBlocks: Active context blocks to evaluate against.
    /// - Returns: Array of risk assessments, one per active block, sorted by risk level descending.
    public static func evaluate(
        records: [SleepRecord],
        contextBlocks: [ContextBlock]
    ) -> [WorkHourRisk] {
        let activeBlocks = contextBlocks.filter(\.isEnabled)
        guard !records.isEmpty, !activeBlocks.isEmpty else { return [] }

        // Compute Two-Process Model curves
        let points = TwoProcessModel.computeContinuous(records)
        guard !points.isEmpty else { return [] }

        // Focus on the most recent day
        let lastDay = records.count - 1

        // Determine date for filtering active blocks (specificDate-aware)
        let targetDate: Date = lastDay < records.count ? records[lastDay].date : Date()

        let lastDayPoints = points.filter { $0.day == lastDay }
        guard !lastDayPoints.isEmpty else { return [] }

        var risks: [WorkHourRisk] = []

        for block in activeBlocks {
            guard block.isActive(on: targetDate) else { continue }

            // Collect S values during this block's hours
            let startH = Int(block.startHour) % 24
            let endH = Int(block.endHour) % 24

            var blockHours: [Int] = []
            if startH < endH {
                blockHours = Array(startH..<endH)
            } else {
                // Overnight block (e.g. 22:00-06:00)
                blockHours = Array(startH..<24) + Array(0..<endH)
            }

            var sValues: [(hour: Int, s: Double)] = []
            for h in blockHours {
                if let p = lastDayPoints.first(where: { $0.hour == h }) {
                    sValues.append((hour: h, s: p.s))
                }
            }

            guard !sValues.isEmpty else { continue }

            let meanS = sValues.map(\.s).reduce(0, +) / Double(sValues.count)
            let peakEntry = sValues.max(by: { $0.s < $1.s })!

            let riskLevel: RiskLevel
            if meanS >= highRiskThreshold {
                riskLevel = .high
            } else if meanS >= moderateRiskThreshold {
                riskLevel = .moderate
            } else {
                riskLevel = .low
            }

            risks.append(WorkHourRisk(
                blockID: block.id,
                blockLabel: block.label,
                blockType: block.type,
                peakSleepinessHour: Double(peakEntry.hour),
                meanS: meanS,
                riskLevel: riskLevel
            ))
        }

        return risks.sorted { $0.riskLevel > $1.riskLevel }
    }
}
