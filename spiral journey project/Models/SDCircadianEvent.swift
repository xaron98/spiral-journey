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

    // MARK: Init

    init(
        eventID: UUID = UUID(),
        type: String,
        absoluteHour: Double,
        timestamp: Date = Date(),
        note: String? = nil
    ) {
        self.eventID = eventID
        self.type = type
        self.absoluteHour = absoluteHour
        self.timestamp = timestamp
        self.note = note
    }

    // MARK: Converters

    /// Create an SDCircadianEvent from a SpiralKit CircadianEvent.
    convenience init(from event: CircadianEvent) {
        self.init(
            eventID: event.id,
            type: event.type.rawValue,
            absoluteHour: event.absoluteHour,
            timestamp: event.timestamp,
            note: event.note
        )
    }

    /// Convert back to a SpiralKit CircadianEvent.
    func toCircadianEvent() -> CircadianEvent {
        CircadianEvent(
            id: eventID,
            type: EventType(rawValue: type) ?? .light,
            absoluteHour: absoluteHour,
            timestamp: timestamp,
            note: note
        )
    }
}
