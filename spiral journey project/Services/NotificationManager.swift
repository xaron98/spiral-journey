import UserNotifications
import SpiralKit

// MARK: - Foreground Notification Delegate

/// Allows notifications to display as banners even when the app is in the foreground.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

/// Manages local notifications for the weekly sleep digest.
///
/// Schedules a recurring notification every Monday at 09:00 local time
/// with a summary of the previous week's sleep data.
actor NotificationManager {

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let weeklyDigestID = "spiral.weekly.digest"

    /// Install the foreground delegate. Call once at app launch.
    func installDelegate() {
        center.delegate = NotificationDelegate.shared
    }

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
        consistency: SpiralConsistencyScore?,
        localeIdentifier: String
    ) async {
        // Remove existing to avoid duplicates
        center.removePendingNotificationRequests(withIdentifiers: [weeklyDigestID])

        guard await isAuthorized() else { return }
        let bundle = languageBundle(for: localeIdentifier)

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("notification.digest.title", bundle: bundle, comment: "")
        content.body = buildDigestBody(analysis: analysis, consistency: consistency, bundle: bundle)
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
        consistency: SpiralConsistencyScore?,
        bundle: Bundle
    ) -> String {
        let loc = { (key: String) in NSLocalizedString(key, bundle: bundle, comment: "") }
        var parts: [String] = []

        // Consistency score
        if let c = consistency {
            let arrow: String
            if let delta = c.deltaVsPreviousWeek {
                arrow = delta > 2 ? " \u{2191}" : delta < -2 ? " \u{2193}" : ""
            } else {
                arrow = ""
            }
            parts.append(String(format: loc("notification.digest.consistency"), c.score) + arrow)
        }

        // Mean duration
        let dur = analysis.stats.meanSleepDuration
        if dur > 0 {
            parts.append(String(format: loc("notification.digest.duration"), String(format: "%.1fh", dur)))
        }

        // Composite score
        parts.append(String(format: loc("notification.digest.score"), analysis.composite))

        // Top recommendation
        if let rec = analysis.recommendations.first {
            parts.append(rec.title)
        }

        return parts.joined(separator: " · ")
    }

    // MARK: - Morning Summary

    private let morningSummaryID = "spiral.morning.summary"

    /// Schedule a morning summary notification.
    /// - Parameters:
    ///   - summary: The generated summary from MorningSummaryBuilder.
    ///   - wakeHour: Predicted wake hour (0-24). Notification fires 30 min after.
    func scheduleMorningSummary(_ summary: MorningSummaryBuilder.Summary, wakeHour: Double?) async {
        center.removePendingNotificationRequests(withIdentifiers: [morningSummaryID])
        guard await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        content.title = summary.title
        content.body = summary.body
        content.sound = .default

        // Schedule 30 min after predicted wake, or 08:00 fallback
        let triggerHour: Int
        let triggerMin: Int
        if let wake = wakeHour {
            let totalMin = Int(wake * 60) + 30
            triggerHour = (totalMin / 60) % 24
            triggerMin = totalMin % 60
        } else {
            triggerHour = 8
            triggerMin = 0
        }

        var dateComponents = DateComponents()
        dateComponents.hour = triggerHour
        dateComponents.minute = triggerMin

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: morningSummaryID, content: content, trigger: trigger)

        try? await center.add(request)
    }

    func cancelMorningSummary() {
        center.removePendingNotificationRequests(withIdentifiers: [morningSummaryID])
    }

    // MARK: - Predictive Alert

    private let predictiveAlertID = "spiral.predictive.alert"

    /// Schedule a predictive alert for 18:00 today if conditions are met.
    func schedulePredictiveAlert(_ alert: PredictiveAlertBuilder.Alert, localeIdentifier: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [predictiveAlertID])
        guard alert.shouldFire, await isAuthorized() else { return }

        let bundle = languageBundle(for: localeIdentifier)
        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("predictive.alert.title", bundle: bundle, comment: "")
        content.body = alert.body
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 18
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: predictiveAlertID, content: content, trigger: trigger)

        try? await center.add(request)
    }

    func cancelPredictiveAlert() {
        center.removePendingNotificationRequests(withIdentifiers: [predictiveAlertID])
    }
}
