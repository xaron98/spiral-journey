import EventKit
import Foundation
import Observation
import SpiralKit

/// Manages EventKit calendar access and converts recurring events to `ContextBlock`s.
///
/// Pattern matches `HealthKitManager`: Observable singleton, async authorization,
/// graceful degradation when access is denied.
@MainActor
@Observable
final class CalendarManager {

    // MARK: - State

    private(set) var isAuthorized = false
    private(set) var availableCalendars: [EKCalendar] = []
    var selectedCalendarIDs: Set<String> = []
    private(set) var errorMessage: String?

    private let eventStore = EKEventStore()

    // MARK: - Singleton

    static let shared = CalendarManager()

    private init() {
        checkAuthorizationStatus()
    }

    // MARK: - Authorization

    private func checkAuthorizationStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        isAuthorized = (status == .fullAccess || status == .authorized)
        if isAuthorized {
            loadCalendars()
        }
    }

    func requestAuthorization() async {
        do {
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                isAuthorized = granted
            }
            if isAuthorized {
                loadCalendars()
                errorMessage = nil
            } else {
                errorMessage = "Calendar access not granted."
            }
        } catch {
            errorMessage = error.localizedDescription
            isAuthorized = false
        }
    }

    private func loadCalendars() {
        availableCalendars = eventStore.calendars(for: .event)
            .sorted { $0.title < $1.title }
        // If no calendars selected yet, default to all
        if selectedCalendarIDs.isEmpty {
            selectedCalendarIDs = Set(availableCalendars.map(\.calendarIdentifier))
        }
    }

    // MARK: - Import

    /// Import recurring and regular events from selected calendars as ContextBlocks.
    ///
    /// Scans events from the past 4 weeks to identify repeating patterns.
    /// Deduplicates by `calendarItemExternalIdentifier`.
    ///
    /// - Parameter existingBlocks: Current blocks in the store (for dedup by calendarEventID).
    /// - Returns: Array of new `ContextBlock` items not already in the store.
    func importBlocks(existingBlocks: [ContextBlock]) -> [ContextBlock] {
        guard isAuthorized else { return [] }

        let calendars = availableCalendars.filter { selectedCalendarIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else { return [] }

        let now = Date()
        let startDate = Calendar.current.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let endDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now) ?? now

        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: calendars
        )
        let events = eventStore.events(matching: predicate)

        // Group by calendarItemExternalIdentifier to find unique repeating series
        let existingExternalIDs = Set(existingBlocks.compactMap(\.calendarEventID))
        var seenExternalIDs = Set<String>()
        var blocks: [ContextBlock] = []

        for event in events {
            guard let externalID = event.calendarItemExternalIdentifier else { continue }
            // Skip duplicates and already-imported events
            guard !seenExternalIDs.contains(externalID),
                  !existingExternalIDs.contains(externalID) else { continue }
            seenExternalIDs.insert(externalID)

            // Extract time components
            let cal = Calendar.current
            let startComps = cal.dateComponents([.hour, .minute], from: event.startDate)
            let endComps = cal.dateComponents([.hour, .minute], from: event.endDate)

            let startHour = Double(startComps.hour ?? 9) + Double(startComps.minute ?? 0) / 60.0
            let endHour = Double(endComps.hour ?? 17) + Double(endComps.minute ?? 0) / 60.0

            // Skip all-day events or events longer than 16 hours
            guard !event.isAllDay else { continue }
            let duration = endHour >= startHour ? endHour - startHour : endHour - startHour + 24
            guard duration > 0.25 && duration <= 16 else { continue }

            // Extract active days from recurrence rules
            let activeDays: UInt8
            if let rules = event.recurrenceRules, let rule = rules.first,
               rule.frequency == .weekly {
                activeDays = daysFromRecurrenceRule(rule)
            } else {
                // Single event: just use the weekday of the event
                let weekday = cal.component(.weekday, from: event.startDate)
                activeDays = 1 << (weekday - 1)
            }

            // Infer block type from event title and calendar
            let blockType = inferBlockType(title: event.title ?? "", calendarTitle: event.calendar.title)

            let block = ContextBlock(
                type: blockType,
                label: event.title ?? event.calendar.title,
                startHour: startHour,
                endHour: endHour,
                activeDays: activeDays,
                calendarEventID: externalID,
                isEnabled: true,
                source: .calendar,
                confidence: 0.85
            )
            blocks.append(block)
        }

        return blocks
    }

    // MARK: - Helpers

    /// Convert EKRecurrenceRule daysOfTheWeek to bitmask.
    /// EKRecurrenceDayOfWeek: Sunday=1 … Saturday=7
    private func daysFromRecurrenceRule(_ rule: EKRecurrenceRule) -> UInt8 {
        guard let days = rule.daysOfTheWeek, !days.isEmpty else {
            // Weekly rule without specific days → assume Mon–Fri
            return ContextBlock.weekdays
        }
        var mask: UInt8 = 0
        for day in days {
            let bit = day.dayOfTheWeek.rawValue - 1  // EKWeekday: Sunday=1 → bit 0
            mask |= (1 << bit)
        }
        return mask
    }

    /// Heuristic type inference from event title and calendar name.
    private func inferBlockType(title: String, calendarTitle: String) -> ContextBlockType {
        let lower = (title + " " + calendarTitle).lowercased()

        // Study keywords (multiple languages)
        let studyKeywords = ["class", "clase", "cours", "study", "estudio", "seminar",
                             "lecture", "tutorial", "homework", "exam", "universidad",
                             "school", "escuela", "vorlesung", "klasse", "授業", "学习"]
        if studyKeywords.contains(where: { lower.contains($0) }) { return .study }

        // Exercise keywords
        let exerciseKeywords = ["gym", "run", "yoga", "workout", "exercise", "sport",
                                "entrenamiento", "training", "fitness", "pilates",
                                "swim", "bike", "cross", "deporte"]
        if exerciseKeywords.contains(where: { lower.contains($0) }) { return .exercise }

        // Commute keywords
        let commuteKeywords = ["commute", "transport", "drive", "bus", "train",
                               "trayecto", "desplazamiento", "trajet"]
        if commuteKeywords.contains(where: { lower.contains($0) }) { return .commute }

        // Social keywords
        let socialKeywords = ["social", "dinner", "lunch", "party", "meeting with",
                              "cena", "comida", "fiesta", "quedada"]
        if socialKeywords.contains(where: { lower.contains($0) }) { return .social }

        // Focus keywords
        let focusKeywords = ["focus", "deep work", "no meetings", "concentrate",
                             "foco", "concentración"]
        if focusKeywords.contains(where: { lower.contains($0) }) { return .focus }

        // Work keywords (broad match, last)
        let workKeywords = ["work", "meeting", "standup", "sync", "review", "sprint",
                            "trabajo", "reunión", "oficina", "bureau", "arbeit",
                            "office", "shift", "turno", "guardia"]
        if workKeywords.contains(where: { lower.contains($0) }) { return .work }

        // Default to work for calendar events
        return .work
    }
}
