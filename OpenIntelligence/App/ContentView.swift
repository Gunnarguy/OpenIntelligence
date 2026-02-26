//
//  ContentView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Combine
import CoreSpotlight
import SwiftUI
import TipKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var containerService: ContainerService
    @StateObject private var ragService: RAGService
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var onboardingStore: OnboardingStateStore
    @StateObject private var entitlementStore: EntitlementStore
    @State private var selectedTab: Tab = .chat
    @State private var previousScenePhase: ScenePhase = .inactive
    private let screenshotMode: ScreenshotMode

    init() {
        self.screenshotMode = ScreenshotMode.current
        #if DEBUG
            if !screenshotMode.isEnabled {
                StoreKitTestHarness.startIfNeeded()
            }
        #endif
        let containerSvc = ContainerService()
        let billingSvc = StoreKitBillingService()
        let entitlementStore = EntitlementStore(billingService: billingSvc)
        let ragSvc = RAGService(containerService: containerSvc, entitlementStore: entitlementStore)
        _containerService = StateObject(wrappedValue: containerSvc)
        _ragService = StateObject(wrappedValue: ragSvc)
        _settingsStore = StateObject(wrappedValue: SettingsStore(ragService: ragSvc))
        if screenshotMode.isEnabled {
            let suite = "OpenIntelligence.Screenshots"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            _onboardingStore = StateObject(wrappedValue: OnboardingStateStore(defaults: defaults))
        } else {
            _onboardingStore = StateObject(wrappedValue: OnboardingStateStore())
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
        .glassTabBar()
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
        // `DocumentLibraryView` (and other tabs) relies on SettingsStore via @EnvironmentObject.
        // Previously we only injected it on the Settings tab, which caused a runtime crash when
        // Documents tried to create a new library (it reads settings.useHighAccuracyEmbeddings).
        .environmentObject(settingsStore)
        // Proactively refresh StoreKit products once the root view appears.
        // In production this fetches App Store Connect products; in DEBUG/simulator,
        // this will emit a single warning if no StoreKit configuration is present.
        .task {
            await entitlementStore.billingService.refreshProducts()

            if screenshotMode.shouldImportSamples {
                await importSamplesIfNeeded()
            }
        }
.onChange(of: scenePhase) { oldPhase, newPhase in
    handleScenePhaseChange(from: oldPhase, to: newPhase)
}
        .onChange(of: selectedTab) { _, _ in
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
                    .overlay(alignment: .top) {
                        InlineTipView(tip: FirstQueryTip())
                    }
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
                .overlay(alignment: .top) {
                    InlineTipView(tip: IngestDocumentTip())
                }
            }
            .tabItem {
                Label("Documents", systemImage: "doc.text.magnifyingglass")
            }
            .tag(Tab.documents)

            NavigationStack {
                AdaptiveVisualizationsView()
                    .environmentObject(ragService)
                    .environmentObject(containerService)
                    .overlay(alignment: .top) {
                        InlineTipView(tip: AtlasTip())
                    }
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
                    .overlay(alignment: .top) {
                        InlineTipView(tip: ModelConfigTip())
                    }
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
                ragService.saveSessionTranscript()
                Log.debug("[App] Scene entered background - saved transcript", category: .initialization)
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
            // Transitional state - no action needed
            break

        @unknown default:
            break
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
