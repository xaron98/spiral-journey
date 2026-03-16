import Foundation
import BackgroundTasks
import SpiralKit

/// Manages BGProcessingTask for weekly model retraining.
///
/// Schedules a processing task that runs when the device is plugged in
/// and idle (typically overnight).  The task evaluates new ground truth
/// and retrains the ML model if enough data has accumulated.
///
/// Registration must happen before the app finishes launching.
enum BackgroundTaskManager {

    /// The identifier registered in Info.plist → BGTaskSchedulerPermittedIdentifiers.
    static let retrainTaskID = "com.spiral-journey.model-retrain"

    // MARK: - Registration

    /// Register the background task handler.
    /// Call this once, early in the app lifecycle (before the end of
    /// `application(_:didFinishLaunchingWithOptions:)` or the first frame).
    @MainActor
    static func registerTasks(store: SpiralStore) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: retrainTaskID,
            using: nil        // Main queue
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleRetrainTask(processingTask, store: store)
        }
    }

    // MARK: - Scheduling

    /// Schedule the next background processing run.
    /// Called after each recompute() and after the background task completes.
    static func scheduleRetrainIfNeeded() {
        let request = BGProcessingTaskRequest(identifier: retrainTaskID)
        // Earliest: tomorrow at 3 AM
        request.earliestBeginDate = nextRetrainDate()
        // Require power — retraining uses CPU/Neural Engine
        request.requiresExternalPower = true
        // No network needed — everything is on-device
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Scheduling can fail if the identifier isn't registered or
            // the app has been backgrounded too recently.  Non-fatal.
        }
    }

    // MARK: - Task Handler

    @MainActor
    private static func handleRetrainTask(
        _ task: BGProcessingTask,
        store: SpiralStore
    ) {
        // Set up expiration handler — if the system kills us, mark as not completed
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // 1. Evaluate any new ground truth
        PredictionService.evaluatePastPredictions(store: store)

        // 2. Attempt retraining (checks eligibility internally)
        ModelTrainingService.retrainIfNeeded(store: store)

        // 3. Mark as completed and reschedule
        // Training runs async in ModelTrainingService, but the heavy
        // work (MLUpdateTask) is managed by Core ML's own queue.
        // We mark success and let the system reclaim time.
        task.setTaskCompleted(success: true)

        // Schedule next run
        scheduleRetrainIfNeeded()
    }

    // MARK: - Helpers

    /// Compute the next retrain date: tomorrow at 3 AM local time.
    private static func nextRetrainDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(
            bySettingHour: 3, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}
