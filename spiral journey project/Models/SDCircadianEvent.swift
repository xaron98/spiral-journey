import Foundation
import SwiftData
import SpiralKit

// MARK: - SDCircadianEvent

/// SwiftData model mirroring SpiralKit.CircadianEvent.
@Model
final class SDCircadianEvent {

    // MARK: Persisted Properties

    var eventID: UUID
    /// Stored as EventType.rawValue ("light" | "exercise" | "melatonin" | etc.).
    var type: String
    var absoluteHour: Double
    var timestamp: Date
    var note: String?
    /// Duration in hours for duration events (exercise, screen, etc.). Nil for instant events.
    var durationHours: Double?

    // MARK: Init

    init(
        eventID: UUID = UUID(),
        type: String,
        absoluteHour: Double,
        timestamp: Date = Date(),
        note: String? = nil,
        durationHours: Double? = nil
    ) {
        self.eventID = eventID
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
        self.durationHours = durationHours
    }

    // MARK: Converters

    /// Create an SDCircadianEvent from a SpiralKit CircadianEvent.
    convenience init(from event: CircadianEvent) {
        self.init(
            eventID: event.id,
            type: event.type.rawValue,
            absoluteHour: event.absoluteHour,
            timestamp: event.timestamp,
            note: event.note,
            durationHours: event.durationHours
        )
    }

    /// Convert back to a SpiralKit CircadianEvent.
    func toCircadianEvent() -> CircadianEvent {
        CircadianEvent(
            id: eventID,
            type: EventType(rawValue: type) ?? .light,
            absoluteHour: absoluteHour,
            timestamp: timestamp,
            note: note,
            durationHours: durationHours
        )
    }
}
