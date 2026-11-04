//
//  AppServices.swift
//  OpenIntelligence
//
//  The app's engine and the services around it, built once per launch and shared by every window (5.8).
//
//  `ContentView.init` used to build its own engine, iCloud sync, library list, billing, plan and settings, and it runs
//  for each window and again whenever SwiftUI rebuilds the view. SwiftUI keeps the first set a window gets, but each set
//  starts its launch work as it is built (restoring the import queue, the passages check, a sync pass), so a set it
//  discarded kept working on the same files. On the owner's Mac on 2026-11-03, one launch with two windows logged the
//  relaunch check four times and started two rebuilds of the same 14 documents 29 ms apart, each clearing the same
//  document's passages. An iPad with two windows did the same.
//

import Foundation

@MainActor
final class AppServices {
    static let shared = AppServices()

    let workspaceSyncService: WorkspaceSyncService
    let containerService: ContainerService
    let entitlementStore: EntitlementStore
    let ragService: RAGService
    let settingsStore: SettingsStore
    let modelResolutionService: ModelResolutionService
    let screenshotMode: ScreenshotMode

    private init() {
        #if DEBUG
            DebugRAGValidationHarness.configureStorageIfNeeded()
        #endif
        let screenshotMode = ScreenshotMode.current
        self.screenshotMode = screenshotMode
        #if DEBUG
            if !screenshotMode.isEnabled {
                StoreKitTestHarness.startIfNeeded()
            }
        #endif
        workspaceSyncService = WorkspaceSyncService()
        containerService = ContainerService()
        let billingService = StoreKitBillingService()
        entitlementStore = EntitlementStore(billingService: billingService)
        let ragService = RAGService(containerService: containerService, entitlementStore: entitlementStore)
        // The app's engine is the one actions reach for imports, lists and conversations. It sets
        // itself here; an engine an action builds for one question registers only when none is set.
        RAGService.activePresentedInstance = ragService
        ragService.isTheAppsEngine = true
        // The app's guides don't count toward the plan's documents (5.8), wherever they were imported.
        ragService.isAppGuide = { SampleDocumentManager.shared.isGuide(filename: $0.filename) }
        self.ragService = ragService
        settingsStore = SettingsStore(ragService: ragService)
        modelResolutionService = ModelResolutionService(ragService: ragService, settingsStore: settingsStore)
    }
}
