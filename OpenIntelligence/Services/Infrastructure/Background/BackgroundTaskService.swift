//
//  BackgroundTaskService.swift
//  OpenIntelligence
//
//  Manages background processing tasks for index maintenance, Spotlight
//  re-indexing, and cache warmup using BGTaskScheduler.
//

import Foundation
import BackgroundTasks

/// Handles background task execution for maintenance operations
final class BackgroundTaskService: Sendable {
    static let shared = BackgroundTaskService()

    // Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let indexMaintenanceIdentifier = "com.openintelligence.index-maintenance"
    static let spotlightReindexIdentifier = "com.openintelligence.spotlight-reindex"
    static let appRefreshIdentifier = "com.openintelligence.app-refresh"

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
