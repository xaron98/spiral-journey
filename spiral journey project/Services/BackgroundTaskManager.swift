import Foundation
import BackgroundTasks
import SwiftData
import SpiralKit

/// Manages BGProcessingTasks for weekly model retraining and daily
/// SleepDNA profile refresh.
///
/// Schedules processing tasks that run when the device is idle
/// (typically overnight).  Registration must happen before the app
/// finishes launching.
enum BackgroundTaskManager {

    /// The identifier registered in Info.plist → BGTaskSchedulerPermittedIdentifiers.
    static let retrainTaskID = "com.spiral-journey.model-retrain"

    /// Daily SleepDNA profile refresh task identifier.
    static let dnaRefreshTaskID = "com.spiral-journey.dna-refresh"

    // MARK: - Registration

    /// Register all background task handlers.
    /// Call this once, early in the app lifecycle (before the end of
    /// `application(_:didFinishLaunchingWithOptions:)` or the first frame).
    @MainActor
    static func registerTasks(
        store: SpiralStore,
        modelContainer: ModelContainer,
        dnaService: SleepDNAService
    ) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: retrainTaskID,
            using: nil        // Main queue
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleRetrainTask(processingTask, store: store)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: dnaRefreshTaskID,
            using: nil        // Main queue
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            handleDNARefreshTask(
                processingTask,
                store: store,
                modelContainer: modelContainer,
                dnaService: dnaService
            )
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

    /// Schedule the next daily SleepDNA profile refresh.
    static func scheduleDNARefresh() {
        let request = BGProcessingTaskRequest(identifier: dnaRefreshTaskID)
        // Earliest: tomorrow at 4 AM
        request.earliestBeginDate = nextDNARefreshDate()
        // DNA computation is lightweight — no charger required
        request.requiresExternalPower = false
        // All data is on-device
        request.requiresNetworkConnectivity = false

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Non-fatal — will retry on next foreground.
        }
    }

    // MARK: - Task Handlers

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

    @MainActor
    private static func handleDNARefreshTask(
        _ task: BGProcessingTask,
        store: SpiralStore,
        modelContainer: ModelContainer,
        dnaService: SleepDNAService
    ) {
        let context = ModelContext(modelContainer)

        let refreshTask = Task {
            await dnaService.refreshIfNeeded(store: store, context: context)

            // Schedule next run
            scheduleDNARefresh()

            task.setTaskCompleted(success: true)
        }

        // Cancel the in-flight refresh when the system reclaims our time budget.
        task.expirationHandler = {
            refreshTask.cancel()
            task.setTaskCompleted(success: false)
        }
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

    /// Compute the next DNA refresh date: tomorrow at 4 AM local time.
    private static func nextDNARefreshDate() -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.date(
            bySettingHour: 4, minute: 0, second: 0, of: tomorrow
        ) ?? tomorrow
    }
}
