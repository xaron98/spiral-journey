import Foundation

/// Nightly heart rate variability (SDNN) data point.
///
/// HRV SDNN measured during sleep windows is the best non-invasive proxy
/// for deep sleep quality and vagal tone (Shaffer & Ginsberg, 2017).
public struct NightlyHRV: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var meanSDNN: Double    // milliseconds
    public var sampleCount: Int

    public init(id: UUID = UUID(), date: Date, meanSDNN: Double, sampleCount: Int) {
        self.id = id
        self.date = date
        self.meanSDNN = meanSDNN
        self.sampleCount = sampleCount
    }
}

/// Direction of HRV trend over the analysis window.
public enum HRVTrend: String, Codable, Sendable {
    case rising   // improving autonomic balance
    case falling  // declining — may indicate stress or poor recovery
    case stable   // no significant change
}

/// Utility methods for HRV data analysis.
public enum HRVAnalysis {

    /// Compute the trend direction from a series of nightly HRV values.
    /// Uses simple linear regression slope on the SDNN values.
    public static func trend(_ data: [NightlyHRV]) -> HRVTrend {
        guard data.count >= 3 else { return .stable }

        let values = data.map(\.meanSDNN)
        let n = Double(values.count)
        let xs = (0..<values.count).map { Double($0) }

        let meanX = xs.reduce(0, +) / n
        let meanY = values.reduce(0, +) / n

        var num: Double = 0
        var den: Double = 0
        for i in 0..<values.count {
            let dx = xs[i] - meanX
            let dy = values[i] - meanY
            num += dx * dy
            den += dx * dx
        }

        guard den > 1e-9 else { return .stable }
        let slope = num / den

        // Threshold: ±0.5 ms/night is considered significant
        if slope > 0.5 { return .rising }
        if slope < -0.5 { return .falling }
        return .stable
    }

    /// Compute the mean SDNN across all data points.
    public static func meanSDNN(_ data: [NightlyHRV]) -> Double {
        guard !data.isEmpty else { return 0 }
        return data.map(\.meanSDNN).reduce(0, +) / Double(data.count)
    }

    /// Interpret HRV level qualitatively.
    /// Based on normative ranges from Shaffer & Ginsberg (2017).
    public static func interpretation(meanSDNN: Double) -> HRVInterpretation {
        switch meanSDNN {
        case ..<20:    return .low
        case ..<50:    return .belowAverage
        case ..<100:   return .average
        case ..<150:   return .aboveAverage
        default:       return .high
        }
    }
}

/// Qualitative HRV interpretation.
public enum HRVInterpretation: String, Codable, Sendable {
    case low           // SDNN < 20ms — significant autonomic dysfunction
    case belowAverage  // 20-50ms — reduced variability
    case average       // 50-100ms — typical adult range
    case aboveAverage  // 100-150ms — good autonomic health
    case high          // > 150ms — excellent (often athletes)
}
