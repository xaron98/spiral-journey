import Foundation

/// Sleep phase types from HealthKit / manual entry.
///
/// Natural sleep geometry (validated with 142+13 subjects) shows 2 poles:
///   Active pole: awake + rem (< 3.5° apart on Clifford torus)
///   Deep pole:   light + deep (NREM continuum, ~12-14° apart)
///
/// Colors reflect this geometry: awake ≈ rem (both active pole),
/// light → deep as continuous NREM gradient.
public enum SleepPhase: String, Codable, CaseIterable, Sendable {
    case deep  = "deep"
    case rem   = "rem"
    case light = "light"
    case awake = "awake"

    public var label: String {
        switch self {
        case .deep:  return "Deep Sleep"
        case .rem:   return "REM"
        case .light: return "Light Sleep"
        case .awake: return "Awake"
        }
    }

    /// Colors: 3 clear visual identities reflecting natural geometry.
    /// Active pole shares brightness family but distinct hues:
    ///   Wake = amber/gold (external consciousness)
    ///   REM = soft violet (internal consciousness / dreams)
    /// Deep pole = continuous blue gradient (NREM depth):
    ///   Light = medium blue, Deep = deep indigo
    public var hexColor: String {
        switch self {
        case .deep:  return "#1a2a6e"   // deep indigo (NREM deep)
        case .rem:   return "#a78bfa"   // soft violet (dreams / internal consciousness)
        case .light: return "#4a7ab5"   // medium blue (NREM light)
        case .awake: return "#d4a860"   // warm gold (wake / external consciousness)
        }
    }

    public var description: String {
        switch self {
        case .deep:  return "Restorative, memory consolidation"
        case .rem:   return "Active pole — dreaming, emotional processing"
        case .light: return "NREM depth gradient — lighter restoration"
        case .awake: return "Active pole — wakefulness"
        }
    }
}

/// 15-minute phase interval within a sleep record.
public struct PhaseInterval: Codable, Sendable {
    public var hour: Double       // clock time 0-24
    public var phase: SleepPhase
    public var timestamp: Double  // absolute hours from day 0

    public init(hour: Double, phase: SleepPhase, timestamp: Double) {
        self.hour = hour
        self.phase = phase
        self.timestamp = timestamp
    }
}

/// Hourly activity level (0 = fully asleep, 1 = fully active).
public struct HourlyActivity: Codable, Sendable {
    public var hour: Int          // 0-23
    public var activity: Double   // 0.0–1.0

    public init(hour: Int, activity: Double) {
        self.hour = hour
        self.activity = activity
    }
}
