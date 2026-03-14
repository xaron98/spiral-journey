import UserNotifications
import SpiralKit

/// Manages local notifications for the weekly sleep digest.
///
/// Schedules a recurring notification every Monday at 09:00 local time
/// with a summary of the previous week's sleep data.
actor NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let weeklyDigestID = "spiral.weekly.digest"

    // MARK: - Permission

    /// Request notification permission. Returns true if granted.
    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            return false
        }
    }

    /// Check current authorization status.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Weekly Digest

    /// Schedule (or reschedule) the weekly digest notification for Monday 09:00.
    /// Generates the notification body from the provided analysis data.
    func scheduleWeeklyDigest(
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?
    ) async {
        // Remove existing to avoid duplicates
        center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])

        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Spiral Journey"
        content.body = buildDigestBody(analysis: analysis, consistency: consistency)
        content.sound = .default

        // Every Monday at 09:00 local time
        var dateComponents = DateComponents()
        dateComponents.weekday = 2  // Monday
        dateComponents.hour = 9
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: weeklyDigestID, content: content, trigger: trigger)

        do {
            try await center.add(request)
        } catch {
            // Silently fail — not critical
        }
    }

    /// Cancel all scheduled digest notifications.
    func cancelWeeklyDigest() {
        center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])
    }

    // MARK: - Body Builder

    private func buildDigestBody(
        analysis: AnalysisResult,
        consistency: SpiralConsistencyScore?
    ) -> String {
        var parts: [String] = []

        // Consistency score
        if let c = consistency {
            let arrow: String
            if let delta = c.deltaVsPreviousWeek {
                arrow = delta > 2 ? " \u{2191}" : delta < -2 ? " \u{2193}" : ""
            } else {
                arrow = ""
            }
            parts.append("Consistency \(c.score)/100\(arrow)")
        }

        // Mean duration
        let dur = analysis.stats.meanSleepDuration
        if dur > 0 {
            parts.append(String(format: "Avg %.1fh", dur))
        }

        // Composite score
        parts.append("Score \(analysis.composite)/100")

        // Top recommendation
        if let rec = analysis.recommendations.first {
            parts.append(rec.title)
        }

        return parts.joined(separator: " · ")
    }
}
