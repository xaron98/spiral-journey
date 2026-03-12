import Foundation

/// Phase Response Curve (PRC) models.
///
/// Models how zeitgebers (light, exercise, food) shift circadian phase
/// as a function of circadian time. Positive = advance (earlier), Negative = delay (later).
///
/// Port of src/utils/phaseResponse.js from the Spiral Journey web project.
/// Reference: Khalsa et al. (2003). A Phase Response Curve to Single Bright Light Pulses.
public enum PhaseResponse {

    // MARK: - Helpers

    /// Normalize circadian hour to [0, 24) range.
    private static func normalizeCircadianHour(_ h: Double) -> Double {
        ((h.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
    }

    // MARK: - Individual PRC Functions

    /// Light PRC (Type 1 — weak resetting). ~10,000 lux bright light.
    public static func light(_ circadianHour: Double) -> Double {
        let ct = normalizeCircadianHour(circadianHour)
        if ct >= 2 && ct <= 10 {
            return 0.05 * sin(((ct - 2) / 8) * Double.pi)
        }
        if ct > 10 && ct <= 20 {
            let phase = ((ct - 10) / 10) * Double.pi
            return -1.5 * sin(phase)
        }
        let adjusted = ct > 20 ? ct - 20 : ct + 4
        let phase = (adjusted / 6) * Double.pi
        return 1.2 * sin(phase)
    }

    /// Exercise PRC — weaker than light (~50%).
    public static func exercise(_ circadianHour: Double) -> Double {
        let ct = normalizeCircadianHour(circadianHour)
        if ct >= 4 && ct <= 12 { return 0 }
        if ct > 12 && ct <= 20 {
            return -0.5 * sin(((ct - 12) / 8) * Double.pi)
        }
        let adjusted = ct > 20 ? ct - 20 : ct + 4
        return 0.4 * sin((adjusted / 8) * Double.pi)
    }

    /// Melatonin PRC — opposite effect to light (~60%).
    public static func melatonin(_ circadianHour: Double) -> Double {
        -light(circadianHour) * 0.6
    }

    /// Caffeine PRC — blocks adenosine, delays phase. Reference: Burke et al. (2015).
    public static func caffeine(_ circadianHour: Double) -> Double {
        let ct = normalizeCircadianHour(circadianHour)
        if ct >= 14 && ct <= 22 {
            return -0.6 * sin(((ct - 14) / 8) * Double.pi)
        }
        return 0
    }

    /// Screen/Blue Light PRC — ~30% of bright light. Reference: Chang et al. (2015).
    public static func screenLight(_ circadianHour: Double) -> Double {
        light(circadianHour) * 0.3
    }

    /// Alcohol PRC — delays phase, disrupts second half of sleep.
    public static func alcohol(_ circadianHour: Double) -> Double {
        let ct = normalizeCircadianHour(circadianHour)
        if ct >= 18 || ct < 2 {
            let adjusted = ct >= 18 ? ct - 18 : ct + 6
            return -0.4 * sin((adjusted / 8) * Double.pi)
        }
        return 0
    }

    // MARK: - Model Registry

    public struct PRCModel: Sendable {
        public let fn: @Sendable (Double) -> Double
        public let label: String
        public let hexColor: String
        public let halfLifeDays: Double
        public let maxDays: Int
    }

    public static let models: [EventType: PRCModel] = [
        .light:       PRCModel(fn: light,       label: "Bright Light",  hexColor: "#f5c842", halfLifeDays: 2,   maxDays: 5),
        .exercise:    PRCModel(fn: exercise,     label: "Exercise",      hexColor: "#5bffa8", halfLifeDays: 0.5, maxDays: 1),
        .melatonin:   PRCModel(fn: melatonin,    label: "Melatonin",     hexColor: "#6e3fa0", halfLifeDays: 1,   maxDays: 3),
        .caffeine:    PRCModel(fn: caffeine,     label: "Caffeine",      hexColor: "#c08040", halfLifeDays: 0.5, maxDays: 1),
        .screenLight: PRCModel(fn: screenLight,  label: "Screen Light",  hexColor: "#60a0ff", halfLifeDays: 1,   maxDays: 2),
        .alcohol:     PRCModel(fn: alcohol,      label: "Alcohol",       hexColor: "#e04040", halfLifeDays: 2,   maxDays: 5),
    ]

    // MARK: - Impulse Response

    /// Compute the propagated phase shift remaining at N days after an event.
    /// - Parameters:
    ///   - eventType: The type of zeitgeber event
    ///   - circadianHour: Circadian hour of the event (0-24)
    ///   - daysForward: Days elapsed after the event
    /// - Returns: Remaining phase shift in hours
    public static func impulseResponse(eventType: EventType, circadianHour: Double, daysForward: Double) -> Double {
        guard let model = models[eventType] else { return 0 }
        guard daysForward <= Double(model.maxDays) else { return 0 }
        let initialShift = model.fn(circadianHour)
        return initialShift * exp(-0.693 * daysForward / model.halfLifeDays)
    }

    /// Generate PRC curve data points for visualization.
    public static func curve(for eventType: EventType, step: Double = 0.25) -> [(hour: Double, response: Double)] {
        guard let model = models[eventType] else { return [] }
        var points: [(hour: Double, response: Double)] = []
        var h = 0.0
        while h < 24 {
            points.append((hour: h, response: model.fn(h)))
            h += step
        }
        return points
    }
}
