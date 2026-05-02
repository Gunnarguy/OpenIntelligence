//
//  OpenIntelligenceApp.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import BackgroundTasks
import Combine
import SwiftUI
import TipKit

@main
struct OpenIntelligenceApp: App {
    init() {
        #if DEBUG
        DebugRAGValidationHarness.runHeadlessIfNeeded()
        #endif

        configureIngestionRuntimeBridge()

        // Configure TipKit for contextual user guidance
        AppTipConfiguration.configure()

        // Register background tasks for index maintenance
        registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func configureIngestionRuntimeBridge() {
        IngestionRuntimeBridge.shared.configureContinuedIngestionHandler = { run, expiration in
            BackgroundTaskService.shared.configureContinuedIngestion(run: run, expiration: expiration)
        }
        IngestionRuntimeBridge.shared.beginUserInitiatedIngestionHandler = { title, subtitle in
            BackgroundTaskService.shared.beginUserInitiatedIngestion(title: title, subtitle: subtitle)
        }
        IngestionRuntimeBridge.shared.updateContinuedIngestionProgressHandler = { title, subtitle, fraction in
            BackgroundTaskService.shared.updateContinuedIngestionProgress(
                title: title,
                subtitle: subtitle,
                fraction: fraction
            )
        }
        IngestionRuntimeBridge.shared.restoreLiveActivityHandler = {
            if #available(iOS 17.0, *) {
                IngestionLiveActivityService.shared.restoreExistingActivityIfNeeded()
            }
        }
        IngestionRuntimeBridge.shared.syncLiveActivityHandler = { items, containerName in
            if #available(iOS 17.0, *) {
                IngestionLiveActivityService.shared.sync(items: items, containerName: containerName)
            }
        }
        IngestionRuntimeBridge.shared.finishLiveActivityHandler = { items, containerName in
            if #available(iOS 17.0, *) {
                IngestionLiveActivityService.shared.finish(items: items, containerName: containerName)
            }
        }
        IngestionRuntimeBridge.shared.endLiveActivityHandler = {
            if #available(iOS 17.0, *) {
                IngestionLiveActivityService.shared.endCurrentActivity(finalState: nil)
            }
        }
    }

    // MARK: - Background Tasks

    /// Register background processing and refresh tasks
    private func registerBackgroundTasks() {
        // Background index maintenance (vector DB compaction, entity index cleanup)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.openintelligence.index-maintenance",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            BackgroundTaskService.shared.handleIndexMaintenance(task: processingTask)
        }

        // Background Spotlight re-index (keeps system search up to date)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.openintelligence.spotlight-reindex",
            using: nil
        ) { task in
            guard let processingTask = task as? BGProcessingTask else { return }
            BackgroundTaskService.shared.handleSpotlightReindex(task: processingTask)
        }

        // Periodic app refresh (precompute embeddings, cache warmup)
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "com.openintelligence.app-refresh",
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            BackgroundTaskService.shared.handleAppRefresh(task: refreshTask)
        }

        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: "com.openintelligence.document-ingestion",
                using: nil
            ) { task in
                guard let continuedTask = task as? BGContinuedProcessingTask else { return }
                BackgroundTaskService.shared.handleContinuedIngestion(task: continuedTask)
            }
        }
    }
}
