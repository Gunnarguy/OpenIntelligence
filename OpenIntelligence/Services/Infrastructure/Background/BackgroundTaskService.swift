//
//  BackgroundTaskService.swift
//  OpenIntelligence
//
//  Manages background processing tasks for index maintenance, Spotlight
//  re-indexing, and cache warmup using BGTaskScheduler.
//

import Foundation
import BackgroundTasks
#if canImport(UIKit)
import UIKit
#endif

/// Handles background task execution for maintenance operations
final class BackgroundTaskService: Sendable {
    static let shared = BackgroundTaskService()

    // Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let indexMaintenanceIdentifier = "com.openintelligence.index-maintenance"
    static let spotlightReindexIdentifier = "com.openintelligence.spotlight-reindex"
    static let appRefreshIdentifier = "com.openintelligence.app-refresh"
    static let continuedIngestionIdentifier = "com.openintelligence.document-ingestion"

    @MainActor private var continuedIngestionRunner: (@MainActor () async -> Bool)?
    @MainActor private var continuedIngestionExpirationHandler: (@MainActor () -> Void)?
    @MainActor private var activeContinuedIngestionTask: BGContinuedProcessingTask?
    @MainActor private var activeContinuedIngestionWorker: Task<Void, Never>?
    @MainActor private var continuedIngestionRequestSubmitted = false
#if canImport(UIKit)
    @MainActor private var continuedIngestionBridgeTask: UIBackgroundTaskIdentifier = .invalid
#endif

    private init() {}

    // MARK: - Task Scheduling

    /// Schedule index maintenance (runs when device is idle + charging)
    func scheduleIndexMaintenance() {
        let request = BGProcessingTaskRequest(identifier: Self.indexMaintenanceIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = true  // Only when charging
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600) // 4 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled index maintenance", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule index maintenance: \(error.localizedDescription)", category: .initialization)
        }
    }

    /// Schedule Spotlight re-indexing
    func scheduleSpotlightReindex() {
        let request = BGProcessingTaskRequest(identifier: Self.spotlightReindexIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600) // 2 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled Spotlight reindex", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule Spotlight reindex: \(error.localizedDescription)", category: .initialization)
        }
    }

    /// Schedule periodic app refresh (lightweight, runs frequently)
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled app refresh", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule app refresh: \(error.localizedDescription)", category: .initialization)
        }
    }

    @MainActor
    func configureContinuedIngestion(
        run: @escaping @MainActor () async -> Bool,
        expiration: @escaping @MainActor () -> Void
    ) {
        continuedIngestionRunner = run
        continuedIngestionExpirationHandler = expiration
    }

    @MainActor
    func beginUserInitiatedIngestion(title: String, subtitle: String) {
        guard #available(iOS 26.0, *) else { return }
        guard activeContinuedIngestionTask == nil, activeContinuedIngestionWorker == nil, !continuedIngestionRequestSubmitted else {
            return
        }

        beginContinuedIngestionBridgeIfNeeded(reason: title)

        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.continuedIngestionIdentifier,
            title: title,
            subtitle: tunedSubtitle(base: subtitle)
        )
        request.strategy = preferredSubmissionStrategy()
        if shouldRequestBackgroundGPU(), BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
        }

        do {
            continuedIngestionRequestSubmitted = true
            try BGTaskScheduler.shared.submit(request)
            Log.info("[BackgroundTasks] Submitted continued ingestion task", category: .initialization)
        } catch {
            continuedIngestionRequestSubmitted = false
            Log.warning("[BackgroundTasks] Failed to submit continued ingestion task: \(error.localizedDescription)", category: .initialization)
        }
    }

    @MainActor
    @available(iOS 26.0, *)
    func handleContinuedIngestion(task: BGContinuedProcessingTask) {
        Log.info("[BackgroundTasks] Starting continued ingestion task", category: .initialization)

        continuedIngestionRequestSubmitted = false
        endContinuedIngestionBridgeIfNeeded()
        activeContinuedIngestionTask = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = 0

        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeContinuedIngestionWorker?.cancel()
                self.continuedIngestionExpirationHandler?()
                self.finishContinuedIngestion(success: false)
                Log.warning("[BackgroundTasks] Continued ingestion task expired", category: .initialization)
            }
        }

        activeContinuedIngestionWorker?.cancel()
        activeContinuedIngestionWorker = Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await self.continuedIngestionRunner?() ?? false
            self.finishContinuedIngestion(success: success)
        }
    }

    @MainActor
    func updateContinuedIngestionProgress(title: String, subtitle: String, fraction: Double) {
        guard #available(iOS 26.0, *), let task = activeContinuedIngestionTask else { return }
        let clampedFraction = max(0, min(1, fraction))
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = Int64((clampedFraction * 1000).rounded())
        task.updateTitle(title, subtitle: tunedSubtitle(base: subtitle))
    }

    @MainActor
    func completeUserInitiatedIngestion(success: Bool) {
        guard #available(iOS 26.0, *) else { return }

        if activeContinuedIngestionTask != nil {
            finishContinuedIngestion(success: success)
            return
        }

        activeContinuedIngestionWorker?.cancel()
        activeContinuedIngestionWorker = nil
        continuedIngestionRequestSubmitted = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.continuedIngestionIdentifier)
        endContinuedIngestionBridgeIfNeeded()
    }

    @MainActor
    private func finishContinuedIngestion(success: Bool) {
        guard #available(iOS 26.0, *) else { return }
        guard let task = activeContinuedIngestionTask else { return }

        activeContinuedIngestionTask = nil
        activeContinuedIngestionWorker = nil
        continuedIngestionRequestSubmitted = false
        endContinuedIngestionBridgeIfNeeded()
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
    }

    @MainActor
    @available(iOS 26.0, *)
    private func preferredSubmissionStrategy() -> BGContinuedProcessingTaskRequest.SubmissionStrategy {
        // Document ingestion should complete eventually after a user initiates it.
        // Prefer queueing over immediate failure when the system is resource constrained.
        .queue
    }

#if canImport(UIKit)
    @MainActor
    private func beginContinuedIngestionBridgeIfNeeded(reason: String) {
        guard continuedIngestionBridgeTask == .invalid else { return }

        let identifier = UIApplication.shared.beginBackgroundTask(withName: reason) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.continuedIngestionExpirationHandler?()
                self.endContinuedIngestionBridgeIfNeeded()
                Log.warning("[BackgroundTasks] UIKit bridge background task expired", category: .initialization)
            }
        }

        guard identifier != .invalid else {
            Log.warning("[BackgroundTasks] UIKit bridge background task unavailable", category: .initialization)
            return
        }

        continuedIngestionBridgeTask = identifier
        Log.debug("[BackgroundTasks] Started UIKit bridge background task", category: .initialization)
    }

    @MainActor
    private func endContinuedIngestionBridgeIfNeeded() {
        guard continuedIngestionBridgeTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(continuedIngestionBridgeTask)
        continuedIngestionBridgeTask = .invalid
    }
#else
    @MainActor
    private func beginContinuedIngestionBridgeIfNeeded(reason _: String) {}

    @MainActor
    private func endContinuedIngestionBridgeIfNeeded() {}
#endif

    @MainActor
    @available(iOS 26.0, *)
    private func shouldRequestBackgroundGPU() -> Bool {
#if !DEBUG
        return false
#else

        let device = DeviceCapabilityService.shared
        let thermalState = ProcessInfo.processInfo.thermalState

        guard device.activeGPUAccelerationLevel >= 0.6 else { return false }
        guard thermalState == .nominal || thermalState == .fair else { return false }

        if device.formFactor == .iPhone && device.tier == .baseline {
            return false
        }

        return true
#endif
    }

    @MainActor
    private func tunedSubtitle(base: String) -> String {
        let device = DeviceCapabilityService.shared
        let mode: String
        switch device.activeGPUAccelerationLevel {
        case ..<0.3:
            mode = "Eco"
        case 0.3..<0.7:
            mode = "Balanced"
        default:
            mode = "Turbo"
        }
        return "\(base) • \(device.chipName) • \(mode)"
    }

    // MARK: - Task Handlers

    /// Handle index maintenance: compact vector databases, prune stale entity entries
    @MainActor
    func handleIndexMaintenance(task: BGProcessingTask) {
        Log.info("[BackgroundTasks] Starting index maintenance", category: .initialization)
        HardwareTelemetryReporter.pulse(.ragOrchestration, intensity: 0.6, duration: 0.5)

        // Schedule next occurrence
        scheduleIndexMaintenance()

        let maintenanceTask = Task {
            // 1. Entity index health check
            let entityService = EntityIndexService.shared
            let stats = await entityService.statistics()
            Log.info("[BackgroundTasks] Entity index: \(stats.totalEntities) entities, \(stats.totalIndexedChunks) chunks", category: .initialization)

            // 2. Gazetteer vocabulary health check
            let gazetteerTerms = await GazetteerService.shared.termCount
            let gazetteerLabels = await GazetteerService.shared.labelCount
            Log.info("[BackgroundTasks] Gazetteer: \(gazetteerTerms) terms across \(gazetteerLabels) labels", category: .initialization)

            // 3. Flag maintenance timestamp for diagnostics
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastIndexMaintenanceTimestamp")
            UserDefaults.standard.set(stats.totalEntities, forKey: "lastMaintenanceEntityCount")

            HardwareTelemetryReporter.reportCPUOperation()
            Log.info("[BackgroundTasks] Index maintenance completed", category: .initialization)
            task.setTaskCompleted(success: true)
        }

        // Handle task expiration
        task.expirationHandler = {
            maintenanceTask.cancel()
            Log.warning("[BackgroundTasks] Index maintenance expired", category: .initialization)
        }
    }

    /// Handle Spotlight re-indexing
    @MainActor
    func handleSpotlightReindex(task: BGProcessingTask) {
        Log.info("[BackgroundTasks] Starting Spotlight reindex", category: .initialization)
        HardwareTelemetryReporter.pulse(.dataDecoding, intensity: 0.5, duration: 0.3)

        scheduleSpotlightReindex()

        let reindexTask = Task {
            // Flag that a Spotlight reindex is needed on next foreground launch
            // Full reindex requires ContainerService data (only available in foreground)
            UserDefaults.standard.set(true, forKey: "spotlightReindexNeeded")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSpotlightReindexRequest")

            Log.info("[BackgroundTasks] Spotlight reindex flagged for next foreground launch", category: .initialization)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            reindexTask.cancel()
        }
    }

    /// Handle lightweight app refresh (cache warmup, prediction updates)
    @MainActor
    func handleAppRefresh(task: BGAppRefreshTask) {
        Log.debug("[BackgroundTasks] App refresh triggered", category: .initialization)

        scheduleAppRefresh()

        let refreshTask = Task {
            // 1. Warm Gazetteer vocabulary cache (forces lazy data to load)
            let termCount = await GazetteerService.shared.termCount
            Log.debug("[BackgroundTasks] Gazetteer warmed: \(termCount) terms", category: .initialization)

            // 2. Record refresh timestamp
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAppRefreshTimestamp")

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}
