import Foundation

// MARK: - Context Source

/// How a context block was created. Used for confidence hierarchy (Manual > Calendar > Inferred).
///
/// References: SleepViz design study recommends tracking data provenance for
/// contextual blocks, with manual entry as ground truth and calendar import
/// as high-confidence secondary source.
public enum ContextSource: String, Codable, Sendable, CaseIterable {
    /// User created or edited the block directly.
    case manual
    /// Imported from EventKit calendar events.
    case calendar
}

// MARK: - Context Block Type

/// The type of daily context block.
///
/// Each type carries a display color (hex), SF Symbol, and localization key.
/// Currently all types render in electric blue (#3B82F6); the per-type `hexColor`
/// property is wired so the palette can expand in the future without view changes.
public enum ContextBlockType: String, Codable, Sendable, CaseIterable {
    case work
    case study
    case commute
    case exercise
    case social
    case focus
    case custom

    /// Display color (hex) per block type.
    ///
    /// Each type gets a distinct hue for visual differentiation. All colors are chosen
    /// to meet WCAG 2.2 contrast requirements (≥ 4.5:1) against dark backgrounds
    /// when used at the border opacity (0.15+) in the spiral.
    public var hexColor: String {
        switch self {
        case .work:     return "3B82F6"  // electric blue
        case .study:    return "8B5CF6"  // violet
        case .commute:  return "F59E0B"  // amber
        case .exercise: return "10B981"  // emerald
        case .social:   return "EC4899"  // pink
        case .focus:    return "6366F1"  // indigo
        case .custom:   return "64748B"  // slate gray
        }
    }

    /// Dash pattern for the block's border stroke in the spiral.
    ///
    /// Per the research PDF (WCAG 2.2 / accessibility): "Don't depend on color alone;
    /// use patterns (dashed for study, solid for work) or discrete icons on tap."
    /// Each type has a distinct dash pattern so blocks are distinguishable even
    /// without color perception.
    ///
    /// Returns an empty array for solid strokes.
    public var dashPattern: [Double] {
        switch self {
        case .work:     return []              // solid
        case .study:    return [4, 3]          // short dashes
        case .commute:  return [2, 4]          // dotted
        case .exercise: return [6, 3, 2, 3]    // dash-dot
        case .social:   return [8, 4]          // long dashes
        case .focus:    return [3, 5]          // spaced short dashes
        case .custom:   return []              // solid
        }
    }

    /// SF Symbol for UI display.
    public var sfSymbol: String {
        switch self {
        case .work:     return "briefcase.fill"
        case .study:    return "book.fill"
        case .commute:  return "car.fill"
        case .exercise: return "figure.run"
        case .social:   return "person.2.fill"
        case .focus:    return "brain.head.profile"
        case .custom:   return "square.grid.2x2"
        }
    }

    /// Localization key suffix for the type label (e.g. "context.type.work").
    public var localizationKey: String {
        "context.type.\(rawValue)"
    }

    /// Whether this block type involves high cognitive demand.
    ///
    /// Used by `ScheduleConflictDetector` for two-tier buffer severity:
    /// high-demand blocks (work, study, commute, focus) trigger the extended
    /// 90-min "high risk" buffer threshold, justified by sleep inertia research
    /// showing 15–30 min typical dissipation but up to 2–4 h for full cognitive recovery.
    public var isHighCognitiveDemand: Bool {
        switch self {
        case .work, .study, .commute, .focus: return true
        case .exercise, .social, .custom:     return false
        }
    }
}

// MARK: - Context Block

/// A recurring daily time block representing a life obligation (work, study, commute, etc.).
///
/// Uses clock hours (0–24) for start/end, with a bitmask for active days of the week.
/// Follows the `TimeWindow` pattern from `JetLagPlan.swift` for time representation.
///
/// The `activeDays` bitmask is compact (1 byte, Codable) and efficient for Watch sync
/// within the 65 KB application-context budget.
///
/// - Note: Blocks imported from EventKit store the calendar event identifier in
///   `calendarEventID` for deduplication.
public struct ContextBlock: Codable, Identifiable, Sendable, Equatable, Hashable {

    /// Unique identifier.
    public var id: UUID

    /// Block type (work, study, commute, etc.).
    public var type: ContextBlockType

    /// User-facing label (e.g. "Morning shift", "Math class").
    public var label: String

    /// Start clock hour, 0–24 (e.g. 9.0 = 09:00, 22.5 = 22:30).
    public var startHour: Double

    /// End clock hour, 0–24 (e.g. 17.0 = 17:00). May be < startHour for overnight blocks.
    public var endHour: Double

    /// Active days as bitmask: bit 0 = Sunday, bit 1 = Monday, ..., bit 6 = Saturday.
    /// Example: `0b0111110` (62) = Monday–Friday.
    public var activeDays: UInt8

    /// Calendar event identifier for EventKit deduplication. Nil for manual blocks.
    public var calendarEventID: String?

    /// Specific date for one-off calendar events. When set, this block only
    /// renders on the exact calendar day (ignoring the `activeDays` bitmask).
    /// Nil for recurring blocks (manual or calendar-recurring), which use `activeDays`.
    public var specificDate: Date?

    /// Whether this block is included in conflict detection and spiral rendering.
    /// Users can toggle blocks off without deleting them.
    public var isEnabled: Bool

    /// How this block was created. Nil for legacy blocks (treated as `.manual`).
    ///
    /// Part of the confidence hierarchy: Manual (1.0) > Calendar (0.85) > Inferred (0.65).
    public var source: ContextSource?

    /// Confidence that this block accurately represents the user's actual schedule (0.0–1.0).
    /// Nil for legacy blocks (treated as 1.0 for manual, 0.85 for calendar).
    ///
    /// Calendar-imported blocks may be stale or represent intention rather than reality.
    /// Manual blocks reflect explicit user declaration and are treated as ground truth.
    public var confidence: Double?

    /// Effective confidence accounting for defaults when `confidence` is nil.
    public var effectiveConfidence: Double {
        if let confidence { return confidence }
        switch source {
        case .calendar: return 0.85
        case .manual, .none: return 1.0
        }
    }

    public init(
        id: UUID = UUID(),
        type: ContextBlockType = .work,
        label: String = "",
        startHour: Double = 9.0,
        endHour: Double = 17.0,
        activeDays: UInt8 = 0b0111110,     // Mon–Fri
        calendarEventID: String? = nil,
        specificDate: Date? = nil,
        isEnabled: Bool = true,
        source: ContextSource? = nil,
        confidence: Double? = nil
    ) {
        self.id = id
        self.type = type
        self.label = label
        self.startHour = startHour
        self.endHour = endHour
        self.activeDays = activeDays
        self.calendarEventID = calendarEventID
        self.specificDate = specificDate
        self.isEnabled = isEnabled
        self.source = source
        self.confidence = confidence
    }

    // MARK: - Helpers

    /// Whether this block is active on a given weekday (legacy — does NOT check `specificDate`).
    /// - Parameter weekday: Calendar weekday (1 = Sunday, 2 = Monday, ..., 7 = Saturday).
    /// - Note: Prefer `isActive(on:)` when you have a full `Date`, as it correctly
    ///   restricts one-off calendar events to their exact day.
    public func isActive(weekday: Int) -> Bool {
        guard weekday >= 1 && weekday <= 7 else { return false }
        let bit = weekday - 1  // 0-based
        return activeDays & (1 << bit) != 0
    }

    /// Whether this block is active on a given calendar date.
    ///
    /// - For one-off events (`specificDate != nil`): only returns `true` on the exact calendar day.
    /// - For recurring blocks (`specificDate == nil`): delegates to the weekday bitmask.
    ///
    /// - Parameter date: The calendar date to check.
    public func isActive(on date: Date) -> Bool {
        if let specific = specificDate {
            return Calendar.current.isDate(date, inSameDayAs: specific)
        }
        let weekday = Calendar.current.component(.weekday, from: date)
        return isActive(weekday: weekday)
    }

    /// Duration in hours. Handles overnight blocks (e.g. 22:00–06:00 = 8h).
    public var durationHours: Double {
        let d = endHour - startHour
        return d >= 0 ? d : d + 24.0
    }

    /// Convert to `TimeWindow` for interop with JetLag and analysis code.
    public var timeWindow: TimeWindow {
        TimeWindow(start: startHour, end: endHour)
    }

    /// Short formatted time string (e.g. "09:00–17:00").
    public var timeRangeString: String {
        let fmt = { (h: Double) -> String in
            let hh = Int(h) % 24
            let mm = Int((h - Double(Int(h))) * 60)
            return String(format: "%02d:%02d", hh, mm)
        }
        return "\(fmt(startHour))–\(fmt(endHour))"
    }

    /// Short formatted active-days string using locale-aware day abbreviations.
    /// Returns nil if no days are active.
    /// For one-off events with `specificDate`, returns the formatted date (e.g. "26 Mar").
    public var activeDaysShort: String? {
        // One-off event: show the specific date instead of weekday pattern
        if let specific = specificDate {
            let fmt = DateFormatter()
            fmt.dateStyle = .medium
            fmt.timeStyle = .none
            return fmt.string(from: specific)
        }
        // veryShortWeekdaySymbols: index 0 = Sunday, 1 = Monday, …, 6 = Saturday
        let labels = Calendar.current.veryShortWeekdaySymbols
        var active: [String] = []
        for i in 0..<7 {
            if activeDays & (1 << i) != 0 {
                active.append(labels[i])
            }
        }
        guard !active.isEmpty else { return nil }

        // Detect Mon-Fri pattern
        if activeDays == 0b0111110 {
            return "\(labels[1])-\(labels[5])"  // Mon-Fri
        }
        // Detect every day
        if activeDays == 0b1111111 {
            return "\(labels[1])-\(labels[0])"  // Mon-Sun
        }
        // Detect weekends
        if activeDays == 0b1000001 {
            return "\(labels[6])-\(labels[0])"  // Sat-Sun
        }

        return active.joined(separator: " ")
    }

    // MARK: - Day mask helpers

    /// Bitmask for Monday–Friday.
    public static let weekdays: UInt8 = 0b0111110

    /// Bitmask for Saturday–Sunday.
    public static let weekends: UInt8 = 0b1000001

    /// Bitmask for every day.
    public static let everyDay: UInt8 = 0b1111111
}
