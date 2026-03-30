import WidgetKit
import Foundation

// MARK: - Entry

struct StateEntry: TimelineEntry {
    let date: Date
    let stateLabel: String       // "Sincronizado", "En transición", "Desalineado"
    let stateColorHex: String    // green, amber, red
    let predictedBed: String?    // "23:30"
    let predictedWake: String?   // "07:15"
    let duration: String?        // "7h 45m"
    let hasData: Bool
}

// MARK: - Stored data

private struct StoredState: Codable {
    var coherence: Double?
    var predictedBedtime: Double?
    var predictedWake: Double?
    var predictedDuration: Double?
}

private func loadStateEntry() -> StateEntry {
    let defaults = UserDefaults(suiteName: "group.xaron.spiral-journey-project")
    guard
        let data = defaults?.data(forKey: "spiral-journey-state"),
        let state = try? JSONDecoder().decode(StoredState.self, from: data)
    else {
        return StateEntry(
            date: .now, stateLabel: "--", stateColorHex: "a0a0b0",
            predictedBed: nil, predictedWake: nil, duration: nil, hasData: false
        )
    }

    let coherence = state.coherence ?? 0
    let label: String
    let colorHex: String
    if coherence > 0.7 {
        label = String(localized: "widget.state.synchronized", defaultValue: "Synchronized")
        colorHex = "5bffa8"
    } else if coherence >= 0.4 {
        label = String(localized: "widget.state.transition", defaultValue: "In Transition")
        colorHex = "f5c842"
    } else {
        label = String(localized: "widget.state.misaligned", defaultValue: "Misaligned")
        colorHex = "f05050"
    }

    var bed: String? = nil
    var wake: String? = nil
    var dur: String? = nil

    if let b = state.predictedBedtime {
        bed = formatHour(b)
    }
    if let w = state.predictedWake {
        wake = formatHour(w)
    }
    if let d = state.predictedDuration {
        let h = Int(d)
        let m = Int((d - Double(h)) * 60)
        dur = m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    return StateEntry(
        date: .now, stateLabel: label, stateColorHex: colorHex,
        predictedBed: bed, predictedWake: wake, duration: dur, hasData: true
    )
}

private func formatHour(_ h: Double) -> String {
    let hour = Int(h) % 24
    let min = Int((h - Double(Int(h))) * 60)
    return String(format: "%02d:%02d", hour, min)
}

// MARK: - Provider

struct StateTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StateEntry {
        StateEntry(date: .now, stateLabel: String(localized: "widget.state.synchronized", defaultValue: "Synchronized"), stateColorHex: "5bffa8",
                   predictedBed: "23:30", predictedWake: "07:15", duration: "7h 45m", hasData: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StateEntry) -> Void) {
        completion(loadStateEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StateEntry>) -> Void) {
        let entry = loadStateEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}
