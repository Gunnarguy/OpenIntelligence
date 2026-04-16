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
    }
}
