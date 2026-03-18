import Foundation
import SwiftData

/// Persisted weekly mini-questionnaire response for scientific validation.
///
/// Captures subjective sleep quality, daytime sleepiness, pattern accuracy,
/// weekend differences, and free-text notes once per week.
@Model
final class SDQuestionnaireResponse {

    /// Start of the week this response covers (Monday 00:00).
    var weekDate: Date

    /// "How would you rate your sleep quality this week?" — 1 (very bad) to 5 (very good).
    var sleepQuality: Int

    /// "Have you felt sleepy during the day?" — 1 (not at all) to 5 (extremely).
    var daytimeSleepiness: Int

    /// "Does the pattern shown in the app reflect how you feel?" — "yes" / "no" / "partially".
    var patternAccuracy: String

    /// "Did you sleep differently on the weekend?"
    var weekendDifference: Bool

    /// "Anything unusual this week?" — optional free-text.
    var notes: String?

    /// When the user completed this questionnaire.
    var completedAt: Date

    init(
        weekDate: Date,
        sleepQuality: Int,
        daytimeSleepiness: Int,
        patternAccuracy: String,
        weekendDifference: Bool,
        notes: String? = nil,
        completedAt: Date = Date()
    ) {
        self.weekDate = weekDate
        self.sleepQuality = sleepQuality
        self.daytimeSleepiness = daytimeSleepiness
        self.patternAccuracy = patternAccuracy
        self.weekendDifference = weekendDifference
        self.notes = notes
        self.completedAt = completedAt
    }
}
