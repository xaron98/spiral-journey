import Foundation
import SwiftData

/// A dream journal entry linked to a specific sleep record.
@Model
final class SDDreamEntry {
    /// The day index of the sleep record this dream belongs to.
    var day: Int
    /// When the entry was created.
    var createdAt: Date
    /// The dream description text.
    var text: String
    /// Optional mood/intensity tag (1-5, nil if not set).
    var intensity: Int?

    init(day: Int, createdAt: Date = Date(), text: String, intensity: Int? = nil) {
        self.day = day
        self.createdAt = createdAt
        self.text = text
        self.intensity = intensity
    }
}
