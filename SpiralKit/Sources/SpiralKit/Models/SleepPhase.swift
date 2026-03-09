import Foundation

/// Sleep phase types matching the web project's SLEEP_PHASES constant.
public enum SleepPhase: String, Codable, CaseIterable, Sendable {
    case deep  = "deep"
    case rem   = "rem"
    case light = "light"
    case awake = "awake"

    public var label: String {
        switch self {
        case .deep:  return "Deep (N3)"
        case .rem:   return "REM"
        case .light: return "Light (N1/2)"
        case .awake: return "Awake"
        }
    }

    public var hexColor: String {
        switch self {
        case .deep:  return "#1a1a6e"
        case .rem:   return "#6e3fa0"
        case .light: return "#5b8bd4"
        case .awake: return "#f5c842"
        }
    }

    public var description: String {
        switch self {
        case .deep:  return "Restorative, memory consolidation"
        case .rem:   return "Dreaming, emotional processing"
        case .light: return "Transitional, easily woken"
        case .awake: return "Wakefulness periods"
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
