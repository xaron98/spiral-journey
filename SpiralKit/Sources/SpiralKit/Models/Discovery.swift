import Foundation

/// An automatically detected milestone in the user's sleep journey.
public struct Discovery: Codable, Identifiable, Sendable {
    public let id: UUID
    public let type: DiscoveryType
    public let date: Date
    public let dayIndex: Int
    public let titleKey: String      // localization key
    public let detailKey: String     // localization key
    public let icon: String          // SF Symbol

    public init(type: DiscoveryType, date: Date, dayIndex: Int,
                titleKey: String, detailKey: String, icon: String) {
        self.id = UUID()
        self.type = type
        self.date = date
        self.dayIndex = dayIndex
        self.titleKey = titleKey
        self.detailKey = detailKey
        self.icon = icon
    }
}

public enum DiscoveryType: String, Codable, Sendable {
    // Data milestones
    case firstRecord
    case oneWeek
    case twoWeeks
    case oneMonth
    case twoMonths
    case threeMonths
    case oneYear

    // DNA milestones
    case intermediateTier    // 4+ weeks → intermediate analysis
    case fullTier            // 8+ weeks → full analysis
    case firstMotif          // first recurring pattern found
    case firstPrediction     // first sleep prediction generated

    // Quality milestones
    case consistencyRecord   // new best consistency score
    case circadianStable     // coherence > 0.6 for 7+ consecutive days
    case circadianRecovery   // coherence improved after disruption

    // Periodogram milestones
    case circadianRhythm     // strong 24h peak detected
    case weeklyPattern       // weekly cycle detected

    // Health milestones
    case firstHealthProfile  // first fitness data from Watch
    case firstAutoWorkout    // first auto-imported workout
}
