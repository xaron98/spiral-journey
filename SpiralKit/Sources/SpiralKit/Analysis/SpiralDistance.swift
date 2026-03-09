import Foundation

/// Spiral distance metric and sector quality heatmap.
/// Port of src/utils/spiralDistance.js from the Spiral Journey web project.
public enum SpiralDistance {

    /// Compute spiral distance between two points on the spiral.
    /// Combines angular (phase) proximity and radial (day) proximity.
    public static func distance(day1: Int, hour1: Double, day2: Int, hour2: Double, period: Double = 24) -> Double {
        let theta1 = (hour1 / period) * 2 * Double.pi
        let theta2 = (hour2 / period) * 2 * Double.pi
        let cosVal = max(-1, min(1, cos(theta1 - theta2)))
        let angularDist = acos(cosVal)
        let radialDist = Double(abs(day1 - day2))
        return angularDist / Double.pi + radialDist * 0.1
    }

    public struct SectorResult: Sendable {
        public let sector: Int
        public let startHour: Double
        public let endHour: Double
        public let consistency: Double   // 0-1
        public let meanActivity: Double
        public let variance: Double
    }

    /// Compute quality heatmap by angular sectors.
    /// Measures how consistent activity is across all days within each time-of-day sector.
    public static func sectorQualityHeatmap(_ records: [SleepRecord], numSectors: Int = 24) -> [SectorResult] {
        let sectorWidth = 24.0 / Double(numSectors)
        var sectors: [SectorResult] = []

        for s in 0..<numSectors {
            let startHour = Double(s) * sectorWidth
            let endHour   = Double(s + 1) * sectorWidth

            var values: [Double] = []
            for day in records {
                for ha in day.hourlyActivity {
                    let h = Double(ha.hour)
                    if h >= startHour && h < endHour {
                        values.append(ha.activity)
                    }
                }
            }

            if values.isEmpty {
                sectors.append(SectorResult(sector: s, startHour: startHour, endHour: endHour,
                                            consistency: 0, meanActivity: 0, variance: 0))
                continue
            }

            let mean = values.reduce(0, +) / Double(values.count)
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
            let cv = mean > 0 ? sqrt(variance) / mean : 1.0
            let consistency = max(0, min(1, 1 - cv))

            sectors.append(SectorResult(sector: s, startHour: startHour, endHour: endHour,
                                         consistency: consistency, meanActivity: mean, variance: variance))
        }
        return sectors
    }
}
