//
//  ContentView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Combine
import CoreSpotlight
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var workspaceSyncService: WorkspaceSyncService
    @StateObject private var containerService: ContainerService
    @StateObject private var ragService: RAGService
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var modelResolutionService: ModelResolutionService
    @StateObject private var onboardingStore: OnboardingStateStore
    @StateObject private var whatsNewStore: WhatsNewStore
    @StateObject private var entitlementStore: EntitlementStore
    @State private var selectedTab: Tab = .chat
    @State private var previousScenePhase: ScenePhase = .inactive
    @State private var showVisualValidationDashboard = false
    private let screenshotMode: ScreenshotMode

    init() {
        #if DEBUG
            DebugRAGValidationHarness.configureStorageIfNeeded()
        #endif
        self.screenshotMode = ScreenshotMode.current
        #if DEBUG
            if !screenshotMode.isEnabled {
                StoreKitTestHarness.startIfNeeded()
            }
        #endif
        let workspaceSyncSvc = WorkspaceSyncService()
        let containerSvc = ContainerService()
        let billingSvc = StoreKitBillingService()
        let entitlementStore = EntitlementStore(billingService: billingSvc)
        let ragSvc = RAGService(containerService: containerSvc, entitlementStore: entitlementStore)
        _workspaceSyncService = StateObject(wrappedValue: workspaceSyncSvc)
        _containerService = StateObject(wrappedValue: containerSvc)
        _ragService = StateObject(wrappedValue: ragSvc)
        let settingsStoreObj = SettingsStore(ragService: ragSvc)
        _settingsStore = StateObject(wrappedValue: settingsStoreObj)
        _modelResolutionService = StateObject(wrappedValue: ModelResolutionService(ragService: ragSvc, settingsStore: settingsStoreObj))
        if screenshotMode.isEnabled {
            let suite = "OpenIntelligence.Screenshots"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            _onboardingStore = StateObject(wrappedValue: OnboardingStateStore(defaults: defaults))
            _whatsNewStore = StateObject(wrappedValue: WhatsNewStore(defaults: defaults))
        } else {
            _onboardingStore = StateObject(wrappedValue: OnboardingStateStore())
            _whatsNewStore = StateObject(wrappedValue: WhatsNewStore())
        }
        _entitlementStore = StateObject(wrappedValue: entitlementStore)

        if let initialTab = screenshotMode.initialTab {
            _selectedTab = State(initialValue: initialTab)
        }
    }

    enum Tab {
        case chat, documents, visualizations, database, settings
    }

    private var shouldShowChecklistLauncher: Bool {
        guard !screenshotMode.isEnabled else { return false }
        return onboardingStore.hasOutstandingSteps && !onboardingStore.isChecklistVisible
    }

    private var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    /// Computed accent color from settings, with system default fallback
    private var appAccentColor: Color {
        if let hex = settingsStore.appAccentColorHex, let color = Color(hex: hex) {
            return color
        }
        return .accentColor
    }

    var body: some View {
        ZStack {
            tabViewContent

            if onboardingStore.isChecklistVisible, !screenshotMode.isEnabled {
                OnboardingChecklistView(
                    ragService: ragService,
                    onOpenSettings: { selectedTab = .settings },
                    onOpenChat: { selectedTab = .chat }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(1)
            }
        }
        .tint(appAccentColor)
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            // Handle Spotlight search result tap — navigate to the document's container
            if activity.userInfo?[CSSearchableItemActivityIdentifier] is String {
                // The identifier is the document UUID; extract containerId from the activity
                if let containerIdString = activity.userInfo?["containerId"] as? String,
                   let containerId = UUID(uuidString: containerIdString) {
                    containerService.activeContainerId = containerId
                    selectedTab = .documents
                } else {
                    // Fallback: just navigate to documents tab
                    selectedTab = .documents
                }
            }
        }
        .onOpenURL { url in
            handleOpenURL(url)
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowChecklistLauncher {
                OnboardingChecklistLauncher(
                    completedSteps: onboardingStore.completedStepCount,
                    totalSteps: onboardingStore.totalStepCount,
                    action: onboardingStore.refreshChecklistVisibilityIfNeeded,
                    onDismissPermanently: onboardingStore.skipPermanently
                )
                .padding(.trailing, 24)
                .padding(.bottom, 28)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: onboardingStore.isChecklistVisible)
.animation(.spring(response: 0.35, dampingFraction: 0.82), value: onboardingStore.hasDismissedPermanently)
        .environmentObject(onboardingStore)
        .environmentObject(entitlementStore)
        .environmentObject(workspaceSyncService)
        .environmentObject(containerService)
        .sheet(isPresented: $showVisualValidationDashboard) {
            #if DEBUG
            ValidationDashboardView(ragService: ragService, settingsStore: settingsStore)
            #else
            EmptyView()
            #endif
        }
        // `DocumentLibraryView` (and other tabs) relies on SettingsStore via @EnvironmentObject.
        // Previously we only injected it on the Settings tab, which caused a runtime crash when
        // Documents tried to create a new library (it reads settings.useHighAccuracyEmbeddings).
        .environmentObject(settingsStore)
        .environmentObject(modelResolutionService)
        // Proactively refresh StoreKit products once the root view appears.
        // In production this fetches App Store Connect products; in DEBUG/simulator,
        // this will emit a single warning if no StoreKit configuration is present.
        // `onDismiss` rather than a callback from the Done button: a sheet can also be
        // swiped away, which is how most people close one, and that path never invoked
        // the button's action — so the sheet would return on the next launch. Marking
        // seen here covers every route out.
        .sheet(item: $whatsNewStore.pendingRelease, onDismiss: {
            whatsNewStore.markSeen()
        }) { release in
            WhatsNewView(release: release)
        }
        .task {
            // Screenshot runs wipe their defaults suite on launch, which would read as
            // a fresh install and stay silent anyway; skipping keeps captures clean.
            if !screenshotMode.isEnabled {
                whatsNewStore.evaluateOnLaunch()
            }
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let arguments = ProcessInfo.processInfo.arguments
            let shouldRunGenerationAudit = environment["OPENINTELLIGENCE_RUN_GENERATION_AUDIT"] == "1"
                || arguments.contains("-OPENINTELLIGENCE_RUN_GENERATION_AUDIT")
            if shouldRunGenerationAudit
            {
                Log.warning("[GenerationAudit] Startup audit flag ignored in this build configuration", category: .llm)
                exit(0)
            }

            if DebugRAGValidationHarness.isEnabled {
                if DebugRAGValidationHarness.isVisualModeEnabled {
                    ragService.clearIngestionQueue()
                    selectedTab = .documents
                    
                    Task.detached(priority: .userInitiated) {
                        do {
                            let _ = try await DebugRAGValidationHarness.runIfNeeded(
                                ragService: ragService,
                                settingsStore: settingsStore
                            )
                            await MainActor.run {
                                showVisualValidationDashboard = true
                            }
                        } catch {
                            await MainActor.run {
                                showVisualValidationDashboard = true
                            }
                        }
                    }
                } else {
                    // Whichever path wins the run gate is the one that must print and exit.
                    // `runHeadlessIfNeeded` in `App.init` does the same, and on macOS it is
                    // usually the winner. On the simulator this task claims the gate first, so
                    // without the exit here the process would finish the validation and then sit
                    // there forever, which is indistinguishable from a hung run to the caller
                    // driving it through `simctl launch`.
                    if let report = try? await DebugRAGValidationHarness.runIfNeeded(
                        ragService: ragService,
                        settingsStore: settingsStore
                    ) {
                        print(report)
                        fflush(stdout)
                        exit(0)
                    }
                    return
                }
            }
            #endif

            await entitlementStore.billingService.refreshProducts()
            // Auto-reconcile existing purchases on launch so paid users
            // are recognized immediately after reinstall or device change.
            await entitlementStore.reconcileEntitlementsOnLaunch()

            await refreshSharedWorkspaceIfNeeded(forceReload: true)

            if screenshotMode.shouldImportSamples {
                await importSamplesIfNeeded()
            }
        }
.onChange(of: scenePhase) { oldPhase, newPhase in
    handleScenePhaseChange(from: oldPhase, to: newPhase)
}
        .onChange(of: containerService.containers.map { "\($0.id.uuidString):\($0.syncMode.rawValue)" }.joined(separator: "|")) { _, _ in
            Task { @MainActor in
                await refreshSharedWorkspaceIfNeeded(forceReload: true)
            }
        }
        .onChange(of: workspaceSyncService.observedWorkspaceChangeCount) { _, _ in
            Task { @MainActor in
                await refreshSharedWorkspaceIfNeeded(forceReload: true)
            }
        }
        .onChange(of: selectedTab) { oldTab, newTab in
            // Stamp the tap so the destination can report how long it took to become
            // usable. Every previous measurement of the Documents tab timed work that
            // happens *after* the view appears, which is why they all came back fast
            // while the tab still felt slow.
            NavigationTiming.begin(String(describing: newTab))
            Log.warning("[TabBar] Selected tab changed from \(oldTab) to \(newTab)", category: .ui)
            DSHaptics.tabChanged()
        }
        .onReceive(settingsStore.$hasUserPrimaryOverride) { hasOverride in
            guard hasOverride else { return }
            onboardingStore.markModelSelectionAcknowledged()
        }
    }

    @ViewBuilder
    private var tabViewContent: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                ChatScreen(ragService: ragService)
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }
            .tag(Tab.chat)

            NavigationStack {
                DocumentLibraryView(
                    ragService: ragService,
                    containerService: containerService,
                    onViewVisualizations: { selectedTab = .visualizations }
                )
            }
            .tabItem {
                Label("Documents", systemImage: "doc.text.magnifyingglass")
            }
            .tag(Tab.documents)

            NavigationStack {
                AdaptiveVisualizationsView()
                    .environmentObject(ragService)
                    .environmentObject(containerService)
            }
            .tabItem {
                Label("Atlas", systemImage: "globe.americas")
            }
            .tag(Tab.visualizations)

            NavigationStack {
                DatabaseDashboardView()
                    .environmentObject(ragService)
                    .environmentObject(containerService)
            }
            .tabItem {
                Label("Database", systemImage: "cylinder.split.1x2")
            }
            .tag(Tab.database)

            NavigationStack {
                SettingsView(ragService: ragService)
            }
            .environmentObject(settingsStore)
            .environmentObject(entitlementStore)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(Tab.settings)
        }
    }

    @MainActor
    private func importSamplesIfNeeded() async {
        guard ragService.documents.isEmpty else { return }
        do {
            try await SampleDocumentManager.shared.importSamples(into: ragService)
        } catch {
            // Screenshot mode should never block the UI if samples fail.
        }
    }

    // MARK: - Scene Phase Handling for Transcript Persistence

    /// Handle app lifecycle transitions for transcript persistence.
    ///
    /// - Saves transcript when app backgrounds (preserves conversation state)
    /// - Restores transcript when app returns to foreground (resumes conversation)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Save the current session transcript before backgrounding
            // This ensures conversation state is preserved if the app is terminated
            Task { @MainActor in
                // Flush buffered vector-store writes FIRST. Everything else in this block was
                // already persisted on backgrounding — the transcript, the ingestion queue, an
                // FTS5 checkpoint — while the vector stores, whose writes are deliberately
                // deferred for batching, were not. A fresh import queried before ever being
                // flushed therefore lived only in memory, and if the process died back here the
                // library came back as documents-with-no-vector-store. Observed end to end on
                // 2026-08-20 (container FE9E86BF: 197 searchable chunks at night, `no vector
                // store yet` at next launch).
                await ragService.persistAllVectorStores()
                ragService.persistIngestionQueueState()
                ragService.saveSessionTranscript()
                Log.debug("[App] Scene entered background - persisted vector stores, saved transcript", category: .initialization)
            }

            // Begin ingestion handoff if processing
            if ragService.isProcessing {
                IngestionRuntimeBridge.shared.beginForegroundFallbackIngestion(reason: "Active Ingestion Handoff")
            }

            // Checkpoint and close database connection before app suspension
            Task {
                await SQLiteFullTextService.shared.shutdown()
            }

            // Schedule background tasks if enabled
            if settingsStore.enableBackgroundMaintenance {
                BackgroundTaskService.shared.scheduleIndexMaintenance()
                BackgroundTaskService.shared.scheduleAppRefresh()
                if settingsStore.enableSpotlightIndexing {
                    BackgroundTaskService.shared.scheduleSpotlightReindex()
                }
            }

        case .active:
            entitlementStore.refreshTransientState()
            Task { @MainActor in
                await refreshSharedWorkspaceIfNeeded(forceReload: workspaceSyncService.isUsingSharedWorkspace)
            }
            // Restore transcript when returning to foreground
            // Only restore if coming from background (not on initial launch)
            if oldPhase == .background {
                Task { @MainActor in
                    if ragService.restoreSessionTranscript() {
                        Log.debug("[App] Scene became active - restored transcript", category: .initialization)
                    }
                }
            }

        case .inactive:
            Task { @MainActor in
                ragService.persistIngestionQueueState()
                ragService.saveSessionTranscript()
                Log.debug("[App] Scene became inactive - checkpointed transcript and ingestion state", category: .initialization)
            }

        @unknown default:
            break
        }
    }

    @MainActor
    private func refreshSharedWorkspaceIfNeeded(forceReload: Bool = false) async {
        let didChangeWorkspaceRoots = await workspaceSyncService.reconfigureIfNeeded()
        guard didChangeWorkspaceRoots || forceReload || (hasICloudSyncAccess && workspaceSyncService.isUsingSharedWorkspace) else {
            return
        }

        let hasActiveIngestion = ragService.ingestionItems.contains { !$0.stage.isTerminal }
        guard !hasActiveIngestion else { return }

        let oldContainers = containerService.containers
        containerService.reloadFromDisk()
        let newContainers = containerService.containers
        let removedContainerIDs = Set(oldContainers.map(\.id)).subtracting(newContainers.map(\.id))
        for containerId in removedContainerIDs {
            LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
            await ClusterLabelService.shared.invalidateCache(for: containerId)
            await SuggestedQuestionsService.shared.invalidateCache(for: containerId)
            SpotlightIndexService.shared.deindexAllDocuments(in: containerId)
            SpotlightIndexService.shared.deindexContainer(id: containerId)
        }

        ragService.reloadWorkspaceData()
    }

    @MainActor
    private func handleOpenURL(_ url: URL) {
        Log.warning("[DeepLink] Received deep link URL: \(url.absoluteString)", category: .ui)
        Log.warning("[DeepLink] scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil"), path: \(url.path)", category: .ui)
        guard url.scheme == OpenIntelligenceDeepLink.scheme else {
            Log.warning("[DeepLink] URL scheme '\(url.scheme ?? "nil")' does not match expected '\(OpenIntelligenceDeepLink.scheme)'", category: .ui)
            return
        }

        if url.host == "documents" {
            Log.warning("[DeepLink] Routing to documents tab. Current tab was: \(selectedTab)", category: .ui)
            selectedTab = .documents
            if url.path == "/ingestion" {
                Log.warning("[DeepLink] Path matches '/ingestion'. Posting showIngestionQueue notification", category: .ui)
                NotificationCenter.default.post(name: NSNotification.Name("com.openintelligence.showIngestionQueue"), object: nil)
            }
        } else if url.host == "chat" {
            Log.warning("[DeepLink] Routing to chat tab. Current tab was: \(selectedTab)", category: .ui)
            selectedTab = .chat
        } else {
            Log.warning("[DeepLink] Host '\(url.host ?? "nil")' did not match any routing rules", category: .ui)
        }
    }
}

private struct ScreenshotMode {
    let isEnabled: Bool
    let initialTab: ContentView.Tab?
    let shouldImportSamples: Bool

    static var current: ScreenshotMode {
        #if DEBUG
            let enabled = LaunchArguments.has("--screenshot") || LaunchArguments.has("screenshot")
            let tabRaw = LaunchArguments.valueEither(for: "screenshot-tab")
                ?? LaunchArguments.valueEither(for: "tab")
            let initialTab: ContentView.Tab? = {
                guard let t = tabRaw?.lowercased() else { return nil }
                switch t {
                case "chat": return .chat
                case "documents", "docs": return .documents
                case "visualizations", "telemetry", "atlas": return .visualizations
                case "database", "db", "sqlite", "fts5": return .database
                case "settings": return .settings
                default: return nil
                }
            }()
            let importSamples = LaunchArguments.has("--screenshot-import-samples")
                || LaunchArguments.has("screenshot-import-samples")
            return ScreenshotMode(isEnabled: enabled, initialTab: initialTab, shouldImportSamples: enabled && importSamples)
        #else
            return ScreenshotMode(isEnabled: false, initialTab: nil, shouldImportSamples: false)
        #endif
    }
}

#Preview {
    ContentView()
}
