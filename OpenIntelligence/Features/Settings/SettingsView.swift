//
//  SettingsView.swift
//  OpenIntelligence
//
//  Comprehensive settings for the RAG pipeline and AI experience.
//  Optimized for Apple Intelligence with Private Cloud Compute.
//

import AppIntents
import SwiftUI
import TipKit

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(AppKit)
import AppKit
#endif

struct SettingsView: View {
    @ObservedObject var ragService: RAGService
    @EnvironmentObject var containerService: ContainerService
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var entitlementStore: EntitlementStore
    @EnvironmentObject var workspaceSyncService: WorkspaceSyncService
    @Environment(\.openURL) var openURL
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    // Note: SystemStateMonitor moved to LiveSystemMonitorWrapper to avoid full-view redraws

    @State var deviceCapabilities = DeviceCapabilities()
    @State var pipelineStages: [ModelPipelineStage] = []
    @State var settingsSearch = ""
    @State var showModelConfiguration = false
    @State var showPlanSheet = false
    @State var planEntryPoint: PlanUpgradeEntryPoint = .settings
    @State private var showAdvancedGeneration = false
    @State var isRefreshingSharedWorkspace = false
    @State var sharedWorkspaceRefreshMessage: String?
    @State var pccCapability: FoundationModelCapabilitySnapshot?
    #if os(macOS)
        /// Whether the menu bar item shows (`MenuBarAsk`); the app reads the same key.
        @AppStorage(MenuBarAsk.visibilityKey) var showsMenuBarItem = true
    #endif

    static let sharedWorkspaceRelativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    var iCloudLibraryCount: Int {
        containerService.containers.filter { $0.syncMode == .iCloudShared }.count
    }

    var hasConfiguredICloudLibraries: Bool {
        iCloudLibraryCount > 0
    }

    var localOnlyLibraryCount: Int {
        max(containerService.containers.count - iCloudLibraryCount, 0)
    }

    private var activeLibrary: KnowledgeContainer? {
        containerService.activeContainer
    }

    var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }

    var body: some View {
        ZStack {
            settingsList

            // Motherboard HUD - Full-screen X-ray overlay
            // Shows glowing borders at the ACTUAL physical locations where
            // the Neural Engine, GPU, and CPU sit behind the screen
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false) // Don't block touches
                    .transition(.opacity)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
.sheet(isPresented: $showPlanSheet) {
            PlanUpgradeSheet(entryPoint: planEntryPoint)
        }
        .onAppear {
            deviceCapabilities = RAGService.checkDeviceCapabilities()
            entitlementStore.refreshTransientState()
            updatePipelineStages()
            Task { await TourContext.settingsOpened.donate() }
        }
        .task { await refreshPCCCapability() }
        .onChange(of: settings.selectedModel) { _, _ in
            updatePipelineStages()
        }
    }


    // MARK: - Stored properties of the extension files (5.8 split: a property must stay in the class)
    @State var gpuProfile: GPUExecutionProfile = DeviceCapabilityService.shared.gpuExecutionProfile
}

// MARK: - Bundle Extension

extension Bundle {
    var appVersion: String {
        "\(infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(infoDictionary?["CFBundleVersion"] as? String ?? "1"))"
    }
}

#Preview {
    NavigationStack {
        SettingsView(ragService: RAGService())
            .environmentObject(SettingsStore(ragService: RAGService()))
            .environmentObject(EntitlementStore(billingService: StoreKitBillingService()))
    }
}
