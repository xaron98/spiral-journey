import Foundation

/// Type of circadian zeitgeber event.
public enum EventType: String, Codable, CaseIterable, Sendable {
    case light       = "light"
    case exercise    = "exercise"
    case melatonin   = "melatonin"
    case caffeine    = "caffeine"
    case screenLight = "screenLight"
    case alcohol     = "alcohol"

    public var label: String {
        switch self {
        case .light:       return "Bright Light"
        case .exercise:    return "Exercise"
        case .melatonin:   return "Melatonin"
        case .caffeine:    return "Caffeine"
        case .screenLight: return "Screen Light"
        case .alcohol:     return "Alcohol"
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
        }
    }
}

/// A circadian event logged at a specific time on the spiral.
public struct CircadianEvent: Codable, Identifiable, Sendable {
    public var id: UUID
    public var type: EventType
    public var absoluteHour: Double   // position on the spiral timeline
    public var timestamp: Date
    public var note: String?

    public init(
        id: UUID = UUID(),
        type: EventType,
        absoluteHour: Double,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
    }
}
