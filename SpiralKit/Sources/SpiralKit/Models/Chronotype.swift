import Foundation

// MARK: - Chronotype Classification

/// Chronotype derived from the reduced Morningness-Eveningness Questionnaire (MEQ-5).
///
/// Reference: Adan, A., & Almirall, H. (1991). Horne & Östberg
/// morningness-eveningness questionnaire: A reduced scale.
/// Personality and Individual Differences, 12(3), 241–253.
///
/// Score range 4–25 maps to five categories:
///   4–7   definite evening
///   8–11  moderate evening
///  12–17  intermediate
///  18–21  moderate morning
///  22–25  definite morning
public enum Chronotype: String, Codable, CaseIterable, Sendable {
    case definiteMorning
    case moderateMorning
    case intermediate
    case moderateEvening
    case definiteEvening

    /// Human-readable English label (used as fallback; UI should prefer localized keys).
    public var label: String {
        switch self {
        case .definiteMorning:  return "Definite Morning"
        case .moderateMorning:  return "Moderate Morning"
        case .intermediate:     return "Intermediate"
        case .moderateEvening:  return "Moderate Evening"
        case .definiteEvening:  return "Definite Evening"
        }
    }

    /// Emoji representing the chronotype for quick visual identification.
    ///
    /// Both `U+2600` (sun) and `U+26C5` (sun behind cloud) have ambiguous
    /// Unicode presentation defaults — without the `U+FE0F` variation
    /// selector they can render as monochrome text glyphs (the "tofu box"
    /// effect) depending on the system font context. Both carry VS16 here
    /// to force the color-emoji rendering reliably.
    public var emoji: String {
        switch self {
        case .definiteMorning:  return "\u{1F305}"              // 🌅
        case .moderateMorning:  return "\u{2600}\u{FE0F}"       // ☀️
        case .intermediate:     return "\u{26C5}\u{FE0F}"       // ⛅
        case .moderateEvening:  return "\u{1F319}"              // 🌙
        case .definiteEvening:  return "\u{1F303}"              // 🌃
        }
    }

    /// Ideal bedtime range as (start, end) clock hours.
    public var idealBedRange: (Double, Double) {
        switch self {
        case .definiteMorning:  return (21.5, 22.5)   // 21:30 – 22:30
        case .moderateMorning:  return (22.0, 23.0)   // 22:00 – 23:00
        case .intermediate:     return (23.0, 24.0)   // 23:00 – 00:00
        case .moderateEvening:  return (0.0, 1.0)     // 00:00 – 01:00
        case .definiteEvening:  return (1.0, 2.0)     // 01:00 – 02:00
        }
    }

    /// Ideal wake range as (start, end) clock hours.
    public var idealWakeRange: (Double, Double) {
        switch self {
        case .definiteMorning:  return (5.0, 6.0)
        case .moderateMorning:  return (6.0, 7.0)
        case .intermediate:     return (7.0, 8.0)
        case .moderateEvening:  return (8.0, 9.0)
        case .definiteEvening:  return (9.0, 10.0)
        }
    }

    /// Estimated Temperature Minimum (Tmin) clock hour.
    /// Tmin ≈ 2h before habitual wake time (Czeisler et al., 1999).
    public var tminEstimate: Double {
        switch self {
        case .definiteMorning:  return 3.5
        case .moderateMorning:  return 4.5
        case .intermediate:     return 5.0
        case .moderateEvening:  return 6.0
        case .definiteEvening:  return 7.5
        }
    }

    /// Score boundaries for classification.
    public static func from(score: Int) -> Chronotype {
        switch score {
        case 22...25: return .definiteMorning
        case 18...21: return .moderateMorning
        case 12...17: return .intermediate
        case  8...11: return .moderateEvening
        case  4...7:  return .definiteEvening
        default:
            // Clamp to valid range
            if score > 25 { return .definiteMorning }
            return .definiteEvening
        }
    }
}

// MARK: - Questionnaire Result

/// Complete result of the MEQ-5 chronotype questionnaire.
public struct ChronotypeResult: Codable, Sendable, Equatable {
    /// Individual answers (1–5 each), in question order.
    public var answers: [Int]

    /// Sum of answers (range 4–25 for 5-question version).
    public var totalScore: Int

    /// Derived chronotype classification.
    public var chronotype: Chronotype

    /// When the questionnaire was completed.
    public var completedAt: Date

    public init(answers: [Int], totalScore: Int, chronotype: Chronotype, completedAt: Date) {
        self.answers = answers
        self.totalScore = totalScore
        self.chronotype = chronotype
        self.completedAt = completedAt
    }
}
