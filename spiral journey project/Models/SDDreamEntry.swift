import Foundation
import SwiftData

/// A dream journal entry linked to a specific sleep date.
@Model
final class SDDreamEntry {
    /// The date of the sleep night this dream belongs to.
    var sleepDate: Date
    /// When the entry was created.
    var createdAt: Date
    /// The dream description text.
    var text: String
    /// Optional mood/intensity tag (1-5, nil if not set).
    var intensity: Int?

    init(sleepDate: Date, createdAt: Date = Date(), text: String, intensity: Int? = nil) {
        self.sleepDate = sleepDate
        self.createdAt = createdAt
        self.text = text
        self.intensity = intensity
    }
}
