//
//  OpenIntelligenceApp.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

#if os(iOS)
import BackgroundTasks
#endif
import Combine
import SwiftUI
import TipKit

@main
struct OpenIntelligenceApp: App {
    #if os(iOS)
    /// For Home Screen quick actions only; see `QuickActions.swift`.
    @UIApplicationDelegateAdaptor(OpenIntelligenceAppDelegate.self) private var appDelegate
    #elseif os(macOS)
    /// For the Services menu only; see `MacServicesProvider.swift`.
    @NSApplicationDelegateAdaptor(OpenIntelligenceMacAppDelegate.self) private var macAppDelegate
    /// The menu bar item, which Settings, Appearance turns off (`MenuBarAsk`).
    @AppStorage(MenuBarAsk.visibilityKey) private var showsMenuBarItem = true
    #endif

    init() {
        #if DEBUG
        DebugRAGValidationHarness.runHeadlessIfNeeded()
        DebugEmbeddingBench.runIfRequested()
        DebugEmbeddingBench.runProvidersIfRequested()
        UITestSupport.configure()
        #endif

        #if targetEnvironment(macCatalyst)
        // Disable automatic window tabbing on macOS to prevent duplicate window tabs
        if let nsWindowClass = NSClassFromString("NSWindow") as? NSObject.Type {
            nsWindowClass.setValue(false, forKey: "allowsAutomaticWindowTabbing")
        }
        #endif

        configureIngestionRuntimeBridge()
        configureQueryRuntimeBridge()

        // Routes a tapped notification to the screen its result is on.
        CompletionNotificationService.shared.install()

        // Starts the monitor that reads iOS 27's request to scale back, so the import and
        // reasoning loops see it from launch and not from the first screen that shows the HUD.
        _ = SystemStateMonitor.shared

        // Prepares the embedding model for this device when the system's cache has no entry for it.
        // Not under the validation harness, whose timings it would sit beside.
        #if DEBUG
            if !DebugRAGValidationHarness.isEnabled { EmbeddingModelWarmup.scheduleAfterLaunch() }
        #else
            EmbeddingModelWarmup.scheduleAfterLaunch()
        #endif

        // Configure TipKit for contextual user guidance
        AppTipConfiguration.configure()

        MetricDiagnostics.start()

        // Register background tasks for index maintenance
        #if os(iOS)
        registerBackgroundTasks()
        // "Scan into Library" on an iPhone that isn't locked runs in the app, not in its Lock Screen camera: it opens
        // the app's scanner then (5.7).
        ScanIntoLibraryIntent.openCaptureInApp = { AppNavigationRequest.post(.scanDocument) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            OpenIntelligenceCommands()
        }
        #if os(macOS)
        MenuBarExtra(isInserted: $showsMenuBarItem) {
            MenuBarAsk()
        } label: {
            Image(systemName: "sparkle.magnifyingglass")
                .accessibilityLabel("OpenIntelligence")
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    private func configureIngestionRuntimeBridge() {
        IngestionRuntimeBridge.shared.configureContinuedIngestionHandler = { run, expiration in
            BackgroundTaskService.shared.configureContinuedIngestion(
                run: run,
                expiration: expiration
            )
        }
        IngestionRuntimeBridge.shared.beginUserInitiatedIngestionHandler = { title, subtitle in
            AppStateReporting.importBegan()
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
            AppStateReporting.importEnded()
            BackgroundTaskService.shared.completeUserInitiatedIngestion(success: success)
            CompletionNotificationService.shared.importFinished(success: success)
        }
        IngestionRuntimeBridge.shared.beginForegroundFallbackIngestionHandler = { reason in
            BackgroundTaskService.shared.beginForegroundFallbackIngestionExtensionIfNeeded(reason: reason)
        }
        IngestionRuntimeBridge.shared.endForegroundFallbackIngestionHandler = {
            BackgroundTaskService.shared.endForegroundFallbackIngestionExtension()
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
                // Called when the import's tracked items are gone without finishing (stopped,
                // dismissed or cleared), where the complete handler is not, so the import's state
                // ends here too.
                AppStateReporting.importEnded()
                IngestionLiveActivityService.shared.endCurrentActivity(finalState: nil)
            }
        } else {
            IngestionRuntimeBridge.shared.restoreLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.syncLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.finishLiveActivityHandler = nil
            IngestionRuntimeBridge.shared.endLiveActivityHandler = { AppStateReporting.importEnded() }
        }
#else
        IngestionRuntimeBridge.shared.restoreLiveActivityHandler = nil
        IngestionRuntimeBridge.shared.syncLiveActivityHandler = nil
        IngestionRuntimeBridge.shared.finishLiveActivityHandler = nil
        // No Live Activity here; the hook still says the import's tracked items are gone.
        IngestionRuntimeBridge.shared.endLiveActivityHandler = { AppStateReporting.importEnded() }
#endif
    }

    private func configureQueryRuntimeBridge() {
        #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
            QueryLiveActivityService.shared.endLeftovers()
        #endif
        QueryRuntimeBridge.shared.configureContinuedQueryHandler = { run, expiration in
            BackgroundTaskService.shared.configureContinuedQuery(
                run: run,
                expiration: expiration
            )
        }
        QueryRuntimeBridge.shared.beginUserInitiatedQueryHandler = { title, subtitle in
            AppStateReporting.answerBegan()
            BackgroundTaskService.shared.beginUserInitiatedQuery(
                title: title,
                subtitle: subtitle
            )
            CompletionNotificationService.shared.answerBegan()
            #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
                QueryLiveActivityService.shared.begin(title: title, subtitle: subtitle)
            #endif
        }
        QueryRuntimeBridge.shared.updateContinuedQueryProgressHandler = { title, subtitle, fraction in
            BackgroundTaskService.shared.updateContinuedQueryProgress(
                title: title,
                subtitle: subtitle,
                fraction: fraction
            )
            #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
                QueryLiveActivityService.shared.update(title: title, subtitle: subtitle, fraction: fraction)
            #endif
        }
        QueryRuntimeBridge.shared.completeUserInitiatedQueryHandler = { success in
            AppStateReporting.answerEnded()
            BackgroundTaskService.shared.completeUserInitiatedQuery(success: success)
            CompletionNotificationService.shared.answerFinished(success: success)
            #if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
                QueryLiveActivityService.shared.complete(success: success)
            #endif
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
    #if os(iOS)
    private func registerBackgroundTasks() {
        #if !targetEnvironment(macCatalyst)
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
    #endif
}
