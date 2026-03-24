import Foundation

/// Source of a circadian event — manual user entry or automatic HealthKit import.
public enum EventSource: String, Codable, Sendable {
    case manual
    case healthKit
}

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
    case highHR      = "highHR"

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
        case .highHR:      return "High Heart Rate"
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
        case .highHR:      return "#ff6b6b"
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
        case .highHR:      return "heart.fill"
        }
    }

    /// Whether this event type supports duration logging (two-tap start/end).
    public var hasDuration: Bool {
        switch self {
        case .exercise, .screenLight, .light, .meal: return true
        case .caffeine, .melatonin, .alcohol, .stress, .highHR: return false
        }
    }

    /// Whether this event type can be logged manually by the user.
    /// `.highHR` is auto-generated from HealthKit only.
    public var isManuallyLoggable: Bool {
        self != .highHR
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
    public var source: EventSource

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
        durationHours: Double? = nil,
        source: EventSource = .manual
    ) {
        self.id = id
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
        self.durationHours = durationHours
        self.source = source
    }

    // MARK: - Custom Codable (backward compatible)

    private enum CodingKeys: String, CodingKey {
        case id, type, absoluteHour, timestamp, note, durationHours, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(EventType.self, forKey: .type)
        absoluteHour = try container.decode(Double.self, forKey: .absoluteHour)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        durationHours = try container.decodeIfPresent(Double.self, forKey: .durationHours)
        source = try container.decodeIfPresent(EventSource.self, forKey: .source) ?? .manual
    }

    // encode(to:) is synthesized — all properties are Codable and CodingKeys match
}
