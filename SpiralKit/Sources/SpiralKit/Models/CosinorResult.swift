import Foundation

/// Result of a single cosinor fit: Y(t) = MESOR + Amplitude × cos(ω(t − acrophase))
public struct CosinorResult: Codable, Sendable {
    /// Baseline activity level (midline estimating statistic of rhythm)
    public var mesor: Double
    /// Rhythm strength — half the total range of the fitted curve
    public var amplitude: Double
    /// Time of peak activity (hours, 0-24)
    public var acrophase: Double
    /// Period of the rhythm in hours (usually 24)
    public var period: Double
    /// Goodness of fit (0-1)
    public var r2: Double

    public init(mesor: Double, amplitude: Double, acrophase: Double, period: Double, r2: Double) {
        self.mesor = mesor
        self.amplitude = amplitude
        self.acrophase = acrophase
        self.period = period
        self.r2 = r2
    }

    public static let empty = CosinorResult(mesor: 0.5, amplitude: 0.3, acrophase: 15, period: 24, r2: 0)
}
