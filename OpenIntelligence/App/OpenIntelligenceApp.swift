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
        configureQueryRuntimeBridge()

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
            BackgroundTaskService.shared.configureContinuedIngestion(
                run: run,
                expiration: expiration
            )
        }
        IngestionRuntimeBridge.shared.beginUserInitiatedIngestionHandler = { title, subtitle in
            BackgroundTaskService.shared.beginUserInitiatedIngestion(
                title: title,
                subtitle: subtitle
            )
        }
        IngestionRuntimeBridge.shared.updateContinuedIngestionProgressHandler = { title, subtitle, fraction in
            BackgroundTaskService.shared.updateContinuedIngestionProgress(
                title: title,
                subtitle: subtitle,
                fraction: fraction
            )
        }
        IngestionRuntimeBridge.shared.completeUserInitiatedIngestionHandler = { success in
            BackgroundTaskService.shared.completeUserInitiatedIngestion(success: success)
        }
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 17.0, *) {
            IngestionRuntimeBridge.shared.restoreLiveActivityHandler = {
                IngestionLiveActivityService.shared.restoreExistingActivityIfNeeded()
            }
            IngestionRuntimeBridge.shared.syncLiveActivityHandler = { items, containerName in
                IngestionLiveActivityService.shared.sync(items: items, containerName: containerName)
            }
            IngestionRuntimeBridge.shared.finishLiveActivityHandler = { items, containerName in
                IngestionLiveActivityService.shared.finish(items: items, containerName: containerName)
            }
            IngestionRuntimeBridge.shared.endLiveActivityHandler = {
                IngestionLiveActivityService.shared.endCurrentActivity(finalState: nil)
            }
        } else {
            IngestionRuntimeBridge.shared.restoreLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.syncLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.finishLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.endLiveActivityHandler = nil
        }
#else
        IngestionRuntimeBridge.shared.restoreLiveActivityHandler = nil
        IngestionRuntimeBridge.shared.syncLiveActivityHandler = nil
        IngestionRuntimeBridge.shared.finishLiveActivityHandler = nil
        IngestionRuntimeBridge.shared.endLiveActivityHandler = nil
#endif
    }

    private func configureQueryRuntimeBridge() {
        QueryRuntimeBridge.shared.configureContinuedQueryHandler = { run, expiration in
            BackgroundTaskService.shared.configureContinuedQuery(
                run: run,
                expiration: expiration
            )
        }
        QueryRuntimeBridge.shared.beginUserInitiatedQueryHandler = { title, subtitle in
            BackgroundTaskService.shared.beginUserInitiatedQuery(
                title: title,
                subtitle: subtitle
            )
        }
        QueryRuntimeBridge.shared.updateContinuedQueryProgressHandler = { title, subtitle, fraction in
            BackgroundTaskService.shared.updateContinuedQueryProgress(
                title: title,
                subtitle: subtitle,
                fraction: fraction
            )
        }
        QueryRuntimeBridge.shared.completeUserInitiatedQueryHandler = { success in
            BackgroundTaskService.shared.completeUserInitiatedQuery(success: success)
        }
        QueryRuntimeBridge.shared.beginForegroundFallbackQueryHandler = { reason in
            BackgroundTaskService.shared.beginForegroundFallbackQueryExtensionIfNeeded(reason: reason)
        }
        QueryRuntimeBridge.shared.endForegroundFallbackQueryHandler = {
            BackgroundTaskService.shared.endForegroundFallbackQueryExtension()
        }
    }

    // MARK: - Background Tasks

    /// Register background processing and refresh tasks
    private func registerBackgroundTasks() {
#if !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: BackgroundTaskService.continuedIngestionIdentifier,
                using: nil
            ) { task in
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }

                BackgroundTaskService.shared.handleContinuedIngestion(task: continuedTask)
            }

            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: BackgroundTaskService.continuedQueryIdentifier,
                using: nil
            ) { task in
                guard let continuedTask = task as? BGContinuedProcessingTask else {
                    task.setTaskCompleted(success: false)
                    return
                }

                BackgroundTaskService.shared.handleContinuedQuery(task: continuedTask)
            }
        }
#endif

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

    }
}
