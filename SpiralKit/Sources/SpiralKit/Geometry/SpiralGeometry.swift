import Foundation

/// Spiral type selection.
public enum SpiralType: String, Codable, Sendable {
    case archimedean = "archimedean"
    case logarithmic = "logarithmic"
}

/// Core spiral geometry calculations.
/// Provides coordinate mapping from (day, hour) to (x, y) on an Archimedean or logarithmic spiral.
///
/// Archimedean:  r(θ) = startRadius + spacing × θ/(2π)   — constant turn spacing
/// Logarithmic:  r(θ) = startRadius × e^(growthRate × turns) — exponential spacing
///
/// Port of src/hooks/useSpiralGeometry.js from the Spiral Journey web project.
public struct SpiralGeometry: Sendable {
    public let totalDays: Int
    /// Maximum days used to fix the scale (spacing/growthRate).
    /// When animating growth, pass the final max here so scale never shifts.
    public let maxDays: Int
    public let width: Double
    public let height: Double
    public let startRadius: Double
    public let spiralType: SpiralType
    public let period: Double           // hours per revolution (usually 24)
    public let linkGrowthToTau: Bool
    /// Sliding window offset: shifts radius so `radius(turns: turnOffset) = startRadius`.
    /// This maps the visible window [turnOffset, turnOffset + maxDays] to [startRadius, maxRadius].
    public let turnOffset: Double

    public init(
        totalDays: Int,
        maxDays: Int? = nil,
        width: Double,
        height: Double,
        startRadius: Double = 20,
        spiralType: SpiralType = .archimedean,
        period: Double = 24,
        linkGrowthToTau: Bool = false,
        turnOffset: Double = 0
    ) {
        self.totalDays = totalDays
        self.maxDays = maxDays ?? totalDays
        self.width = width
        self.height = height
        self.startRadius = startRadius
        self.spiralType = spiralType
        self.period = period
        self.linkGrowthToTau = linkGrowthToTau
        self.turnOffset = turnOffset
    }

    // MARK: - Derived geometry

    public var cx: Double { width / 2 }
    public var cy: Double { height / 2 }
    public var maxRadius: Double { min(width, height) / 2 - 50 }

    public var spacing: Double {
        max(10, (maxRadius - startRadius) / max(Double(maxDays), 1))
    }

    /// tau-linked growth: b = ln(tau/24) / (2π), encodes circadian period into geometry
    private var tauLinkedGrowthRate: Double {
        log(max(period, 23) / 24) / (2 * Double.pi)
    }

    public var growthRate: Double {
        if linkGrowthToTau && spiralType == .logarithmic {
            return tauLinkedGrowthRate
        }
        return log(max(maxRadius, startRadius + 1) / startRadius) / max(Double(maxDays), 1)
    }

    // MARK: - Core Functions

    /// Convert (day, hour) → fractional turns on the spiral.
    /// For period=24: turns = day + hour/24  (one calendar day = one turn)
    /// For period=168: turns = (day*24 + hour) / 168  (one week = one turn)
    /// This ensures data always maps correctly regardless of τ.
    public func turns(day: Int, hour: Double) -> Double {
        (Double(day) * 24.0 + hour) / period
    }

    /// Radius at a given number of turns from center.
    /// When `turnOffset > 0`, the radius is shifted so that `radius(turns: turnOffset) = startRadius`.
    public func radius(turns: Double) -> Double {
        let t = turns - turnOffset
        switch spiralType {
        case .logarithmic:
            return startRadius * exp(growthRate * t)
        case .archimedean:
            return startRadius + spacing * t
        }
    }

    /// Map (day, hour) → (x, y) CGPoint on the spiral.
    /// Hour 0 is at the top (−π/2 offset).
    public func point(day: Int, hour: Double) -> (x: Double, y: Double) {
        let t     = turns(day: day, hour: hour)
        let theta = t * 2 * Double.pi
        let r     = radius(turns: t)
        return (
            x: cx + r * cos(theta - Double.pi / 2),
            y: cy + r * sin(theta - Double.pi / 2)
        )
    }

    /// Outward-pointing normal vector at (day, hour).
    /// Used to offset cosinor curve from the spiral centerline.
    public func normal(day: Int, hour: Double) -> (nx: Double, ny: Double) {
        let p = point(day: day, hour: hour)
        let dx = p.x - cx
        let dy = p.y - cy
        let dist = sqrt(dx * dx + dy * dy)
        guard dist > 0 else { return (nx: 0, ny: -1) }
        // Perpendicular to radial direction
        return (nx: -dy / dist, ny: dx / dist)
    }

    // MARK: - Path Generation

    public struct SpiralStep {
        public let x: Double
        public let y: Double
    }

    /// Generate points along the spiral backbone for path rendering.
    /// - Parameters:
    ///   - step: Turn fraction per step (smaller = smoother)
    ///   - upToTurns: Stop at this fractional turn count (default: totalDays)
    public func spiralSteps(step: Double = 0.015, upToTurns: Double? = nil) -> [SpiralStep] {
        let limit = upToTurns ?? Double(totalDays)
        var steps: [SpiralStep] = []
        var d = 0.0
        while d <= limit {
            let t = min(d, limit)
            // Use turns directly — avoids day/hour round-trip that breaks for period≠24.
            let theta = t * 2 * Double.pi
            let r = radius(turns: t)
            steps.append(SpiralStep(
                x: cx + r * cos(theta - Double.pi / 2),
                y: cy + r * sin(theta - Double.pi / 2)
            ))
            if d >= limit { break }
            d += step
        }
        return steps
    }

    // MARK: - Annotation Helpers

    public struct HourLabel {
        public let x: Double
        public let y: Double
        public let hour: Double
        public let label: String
    }

    /// Positions for hour labels placed just outside the spiral's outermost turn.
    /// Always uses maxDays for placement so labels stay at the canvas edge
    /// regardless of how many nights have been recorded.
    public func hourLabels() -> [HourLabel] {
        var labels: [HourLabel] = []
        // Do NOT round for non-24h periods — rounding e.g. 25.4/8=3.175 → 3 allows
        // h=24 into the loop, producing a duplicate 00:00 label at the wrong angle.
        let step: Double = period <= 24 ? 3 : period / 8
        // Use at least 7 days so labels stay near the canvas edge with few records.
        let refDay = max(maxDays, 7) + Int(turnOffset)
        var h = 0.0
        while h < period {
            let p = point(day: refDay, hour: h + period / 2)
            let displayH = Int(h.rounded()) % 24
            labels.append(HourLabel(x: p.x, y: p.y, hour: h, label: String(format: "%02d:00", displayH)))
            h += step
        }
        return labels
    }

    public struct RadialLine {
        public let x1, y1, x2, y2: Double
    }

    /// Radial guide lines from center to edge.
    public func radialLines() -> [RadialLine] {
        let refTurns = Double(max(maxDays, 7)) + turnOffset + 1
        let outerR = radius(turns: refTurns) + 20
        var lines: [RadialLine] = []
        // Same fix as hourLabels: no rounding to prevent duplicate 00 radial line.
        let step: Double = period <= 24 ? 3 : period / 8
        var h = 0.0
        while h < period {
            let angle = (h / period) * 2 * Double.pi - Double.pi / 2
            lines.append(RadialLine(
                x1: cx + 12 * cos(angle), y1: cy + 12 * sin(angle),
                x2: cx + outerR * cos(angle), y2: cy + outerR * sin(angle)
            ))
            h += step
        }
        return lines
    }

    public struct DayMarker {
        public let x, y: Double
        public let day: Int
        public let isWeekStart: Bool
    }

    /// Marker positions for the start of each day.
    public func dayMarkers() -> [DayMarker] {
        (0..<totalDays).map { day in
            let p = point(day: day, hour: 0)
            return DayMarker(x: p.x, y: p.y, day: day, isWeekStart: day % 7 == 0)
        }
    }

    public struct DayRing {
        public let r: Double
        public let day: Int
        public let isWeekBoundary: Bool
    }

    /// Concentric ring radii for each day boundary.
    public func dayRings() -> [DayRing] {
        (0...totalDays).map { day in
            DayRing(r: radius(turns: turns(day: day, hour: 0)), day: day, isWeekBoundary: day % 7 == 0)
        }
    }
}
