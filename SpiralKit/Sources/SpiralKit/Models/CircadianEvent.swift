import Foundation

/// Type of circadian zeitgeber event.
public enum EventType: String, Codable, CaseIterable, Sendable {
    case light       = "light"
    case exercise    = "exercise"
    case melatonin   = "melatonin"
    case caffeine    = "caffeine"
    case screenLight = "screenLight"
    case alcohol     = "alcohol"
    case meal        = "meal"
    case stress      = "stress"

    public var label: String {
        switch self {
        case .light:       return "Bright Light"
        case .exercise:    return "Exercise"
        case .melatonin:   return "Melatonin"
        case .caffeine:    return "Caffeine"
        case .screenLight: return "Screen Light"
        case .alcohol:     return "Alcohol"
        case .meal:        return "Meal"
        case .stress:      return "Stress"
        }
    }

    public var hexColor: String {
        switch self {
        case .light:       return "#f5c842"
        case .exercise:    return "#5bffa8"
        case .melatonin:   return "#6e3fa0"
        case .caffeine:    return "#c08040"
        case .screenLight: return "#60a0ff"
        case .alcohol:     return "#e04040"
        case .meal:        return "#7cb342"
        case .stress:      return "#e57373"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .light:       return "sun.max.fill"
        case .exercise:    return "figure.run"
        case .melatonin:   return "pill.fill"
        case .caffeine:    return "cup.and.saucer.fill"
        case .screenLight: return "iphone"
        case .alcohol:     return "wineglass"
        case .meal:        return "fork.knife"
        case .stress:      return "brain.head.profile"
        }
    }

    /// Whether this event type supports duration logging (two-tap start/end).
    public var hasDuration: Bool {
        switch self {
        case .exercise, .screenLight, .light, .meal: return true
        case .caffeine, .melatonin, .alcohol, .stress: return false
        }
    }
}

/// A circadian event logged at a specific time on the spiral.
///
/// For duration events (exercise, screen, etc.), `durationHours` stores the span.
/// For instant events (caffeine, melatonin, etc.), `durationHours` is nil.
public struct CircadianEvent: Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: EventType
    public var absoluteHour: Double   // position on the spiral timeline
    public var timestamp: Date
    public var note: String?
    public var durationHours: Double? // nil = instant, >0 = duration event

    /// End position on the spiral timeline (nil for instant events).
    public var endAbsoluteHour: Double? {
        guard let dur = durationHours else { return nil }
        return absoluteHour + dur
    }

    public init(
        id: UUID = UUID(),
        type: EventType,
        absoluteHour: Double,
        timestamp: Date = Date(),
        note: String? = nil,
        durationHours: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
        self.durationHours = durationHours
    }
}
