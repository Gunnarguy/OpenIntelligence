//
//  DocumentLibraryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import StoreKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentLibraryView: View {
    @EnvironmentObject private var onboardingStore: OnboardingStateStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @EnvironmentObject private var settings: SettingsStore
    @ObservedObject var ragService: RAGService
    @ObservedObject var containerService: ContainerService
    @State private var showingFilePicker = false
    @State private var showingProcessingSummary = false
    @State private var lastProcessedSummary: ProcessingSummary?
    @State private var showingContainerSettings = false
    @State private var showingSemanticSearch = false
    @State private var isImportingSamples = false
    @State private var sampleImportError: String?
    @State private var sampleImportStatusMessage: String?
    @State private var showingPlanSheet = false
    @State private var activePaywallEntryPoint: PlanUpgradeEntryPoint = .documents

    // New library naming
    @State private var showingNewLibraryPrompt = false
    @State private var newLibraryName = ""

    let onViewVisualizations: (() -> Void)?

    private var documentLimit: Int { entitlementStore.documentLimit }
    private var isAtDocumentLimit: Bool {
        ragService.documents.count >= documentLimit
    }

    private var libraryLimit: Int { entitlementStore.libraryLimit }

    init(ragService: RAGService, containerService: ContainerService, onViewVisualizations: (() -> Void)? = nil) {
        _ragService = ObservedObject(wrappedValue: ragService)
        _containerService = ObservedObject(wrappedValue: containerService)
        self.onViewVisualizations = onViewVisualizations
    }

    private var filteredDocuments: [Document] {
        let activeId = containerService.activeContainerId
        let defaultId = containerService.containers.first?.id
        return ragService.documents.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                // Legacy docs without containerId appear only in the default container
                return activeId == defaultId
            }
        }
    }

    private var filteredTotalChunks: Int {
        filteredDocuments.reduce(0) { $0 + $1.totalChunks }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            ContainerPickerStrip(
                containerService: containerService,
                allowsCreation: true,
                onCreateLibrary: handleNewLibraryTapped
            )
            .padding(.horizontal)
            DocumentQuotaBanner(
                currentCount: ragService.documents.count,
                limit: documentLimit,
                tierName: entitlementStore.activeTier.displayName,
                addOnPacks: entitlementStore.addOnPacks,
                packCap: entitlementStore.documentPackCap,
                remainingPackCapacity: entitlementStore.remainingDocumentPackCapacity,
                hasReachedPackCap: entitlementStore.hasReachedDocumentPackCap,
                onUpgrade: { presentPlanSheet(for: .quotaBanner) },
                onRefillPack: refillDocumentPack
            )
            .padding(.horizontal)
            EmptyDocumentsView(
                isImportingSamples: isImportingSamples,
                hasImportedSamples: onboardingStore.hasImportedSamples,
                isAtDocumentLimit: isAtDocumentLimit,
                documentLimit: documentLimit,
                statusMessage: sampleImportStatusMessage,
                onImportSamples: importSampleWorkspace,
                onPickFiles: presentDocumentPickerOrUpgrade
            )
            .padding(.horizontal)
        }
    }

    private var documentListView: some View {
        VStack(spacing: 12) {
            ContainerPickerStrip(
                containerService: containerService,
                allowsCreation: true,
                onCreateLibrary: handleNewLibraryTapped
            )
            .padding(.horizontal)
            DocumentQuotaBanner(
                currentCount: ragService.documents.count,
                limit: documentLimit,
                tierName: entitlementStore.activeTier.displayName,
                addOnPacks: entitlementStore.addOnPacks,
                packCap: entitlementStore.documentPackCap,
                remainingPackCapacity: entitlementStore.remainingDocumentPackCapacity,
                hasReachedPackCap: entitlementStore.hasReachedDocumentPackCap,
                onUpgrade: { presentPlanSheet(for: .quotaBanner) },
                onRefillPack: refillDocumentPack
            )
            .padding(.horizontal)
            // Document list with modern styling
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredDocuments) { document in
                        NavigationLink(destination: DocumentDetailsView(
                            document: document,
                            embeddingProviderId: containerService.activeContainer?.embeddingProviderId
                        )) {
                            ModernDocumentCard(document: document, ragService: ragService)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()

                // Stats footer
                StatsFooter(totalDocuments: filteredDocuments.count, totalChunks: filteredTotalChunks)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
        }
    }

    var body: some View {
        ZStack {
            // Modern gradient background
            LinearGradient(
                colors: [
                    DSColors.background,
                    DSColors.surface.opacity(0.3),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if filteredDocuments.isEmpty {
                emptyStateView
            } else {
                documentListView
            }
        }
        .navigationTitle("Documents")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
        #endif
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: presentDocumentPickerOrUpgrade) {
                        Label("Add Document", systemImage: "plus")
                    }
                    .disabled(ragService.isProcessing)
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showingContainerSettings = true
                    } label: {
                        Label("Manage Library", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button {
                        showingSemanticSearch = true
                    } label: {
                        Label("Semantic Search", systemImage: "text.magnifyingglass")
                    }
                    .disabled(ragService.documents.isEmpty)
                }

                if filteredDocuments.count > 0 {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            onViewVisualizations?()
                        } label: {
                            Label("Visualize", systemImage: "cube.transparent")
                        }
                    }
                }

                if !ragService.documents.isEmpty {
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            Task {
                                try? await ragService.clearAllDocuments()
                            }
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { url in
                    enqueueDocumentIngestion(at: url)
                }
            }
            .alert("Sample Import Failed", isPresented: Binding(
                get: { sampleImportError != nil },
                set: { if !$0 { sampleImportError = nil } }
            )) {
                Button("OK", role: .cancel) { sampleImportError = nil }
            } message: {
                if let message = sampleImportError {
                    Text(message)
                }
            }
            .alert("Error Processing Document", isPresented: .constant(ragService.lastError != nil)) {
                Button("OK", role: .cancel) {
                    ragService.lastError = nil
                }
            } message: {
                if let error = ragService.lastError {
                    Text(error)
                }
            }
            .overlay {
                if ragService.isProcessing {
                    ProcessingOverlay(status: ragService.processingStatus)
                }
            }
            .sheet(isPresented: $showingContainerSettings) {
                ContainerSettingsSheet(containerService: containerService, ragService: ragService)
            }
            .sheet(isPresented: Binding(
                get: { ragService.lastProcessingSummary != nil },
                set: { if !$0 { ragService.lastProcessingSummary = nil } }
            )) {
                if let summary = ragService.lastProcessingSummary {
                    ProcessingSummaryView(summary: summary)
                }
            }
            .sheet(isPresented: $showingSemanticSearch) {
                SemanticSearchView(
                    ragService: ragService,
                    containerService: containerService
                )
            }
            .sheet(isPresented: $showingPlanSheet) {
                PlanUpgradeSheet(entryPoint: activePaywallEntryPoint)
                    .environmentObject(entitlementStore)
            }
.alert("New Library", isPresented: $showingNewLibraryPrompt) {
    TextField("Library name", text: $newLibraryName)
    Button("Cancel", role: .cancel) {
        newLibraryName = ""
    }
    Button("Create") {
        createNewLibrary()
    }
} message: {
    Text("Enter a name for your new library")
}
    }

    /// Launches the file picker if the user still has document quota remaining.
    @MainActor
    private func presentDocumentPickerOrUpgrade() {
        if !entitlementStore.canAddDocument(currentCount: ragService.documents.count) {
            presentPlanSheet(for: .documentLimit)
        } else {
            showingFilePicker = true
        }
    }

    /// Ingests a picked document and unlocks the onboarding step once any content exists.
    private func enqueueDocumentIngestion(at url: URL) {
        Task {
            do {
                try await ragService.addDocument(at: url)
                await MainActor.run {
                    onboardingStore.markSamplesImported()
                }
            } catch {
                // Errors are surfaced through ragService.lastError; no extra handling required here.
            }
        }
    }

    /// Imports the curated onboarding workspace so the document list is not empty.
    @MainActor
    private func importSampleWorkspace() {
        guard !isImportingSamples else { return }
        sampleImportError = nil
        sampleImportStatusMessage = nil

        let currentCount = ragService.documents.count
        let sampleCount = SampleDocumentManager.shared.sampleCount
        let remainingSlots = documentLimit - currentCount

        guard remainingSlots > 0 else {
            sampleImportStatusMessage =
                "Current workspace supports up to \(documentLimit) documents. Remove a document or upgrade to import the sample workspace."
            presentPlanSheet(for: .sampleImport)
            return
        }

        guard remainingSlots >= sampleCount else {
            let needed = sampleCount - remainingSlots
            sampleImportStatusMessage =
                "Importing the curated workspace requires \(sampleCount) slots, but only \(remainingSlots) remain. Remove \(needed) document\(needed == 1 ? "" : "s") or upgrade to proceed."
            presentPlanSheet(for: .sampleImport)
            return
        }

        isImportingSamples = true

        Task {
            defer { isImportingSamples = false }
            do {
                try await SampleDocumentManager.shared.importSamples(into: ragService)
                onboardingStore.markSamplesImported()
                sampleImportStatusMessage = "Sample workspace imported successfully."
            } catch {
                sampleImportError = "Could not import the sample workspace. Please try again."
            }
        }
    }

    @MainActor
    private func handleNewLibraryTapped() {
        let currentCount = containerService.containers.count
        guard entitlementStore.canAddLibrary(currentCount: currentCount) else {
            presentPlanSheet(for: .libraryCreation)
            return
        }

        // Suggest a default name but let user customize
        newLibraryName = "Library \(currentCount + 1)"
        showingNewLibraryPrompt = true
    }

    @MainActor
    private func createNewLibrary() {
        let trimmedName = newLibraryName.trimmingCharacters(in: .whitespacesAndNewlines)
        let libraryName = trimmedName.isEmpty ? "Library \(containerService.containers.count + 1)" : trimmedName

        // Use high-accuracy contextual embeddings if enabled in settings
        let embeddingProvider = settings.useHighAccuracyEmbeddings ? "nl_contextual_embedding" : "nl_embedding"

        let newContainer = containerService.createContainer(
            name: libraryName,
            embeddingProviderId: embeddingProvider
        )
        containerService.setActive(newContainer.id)
        newLibraryName = "" // Reset for next time
    }

    @MainActor
    private func presentPlanSheet(for entryPoint: PlanUpgradeEntryPoint) {
        activePaywallEntryPoint = entryPoint
        showingPlanSheet = true
        TelemetryCenter.emitBillingEvent(
            "Paywall presented",
            metadata: ["entryPoint": entryPoint.analyticsValue]
        )
    }

    @MainActor
    private func refillDocumentPack() {
        Task {
            do {
                TelemetryCenter.emitBillingEvent(
                    "Doc pack purchase initiated",
                    metadata: [
                        "currentCount": String(ragService.documents.count),
                        "limit": String(documentLimit),
                    ]
                )

                // Keep development/testing unblocked when StoreKit returns an empty product catalog.
                // In that scenario `billingService.purchase(...)` will throw `.productUnavailable`.
                // We mirror the paywall's DEBUG-only simulation behavior here.
                if entitlementStore.product(for: .documentPackAddOn) == nil {
                    #if DEBUG
                        if entitlementStore.isDebugBillingSimulationEnabled {
                            entitlementStore.simulateDebugPurchase(.documentPackAddOn)
                            TelemetryCenter.emitBillingEvent(
                                "Doc pack purchase simulated (DEBUG)",
                                severity: .warning,
                                metadata: [
                                    "product": BillingProduct.documentPackAddOn.rawValue,
                                    "reason": "storeKitProductNotLoaded",
                                ]
                            )
                            return
                        }
                    #endif
                }

                _ = try await entitlementStore.billingService.purchase(.documentPackAddOn)
                TelemetryCenter.emitBillingEvent(
                    "Doc pack purchase succeeded",
                    metadata: ["packs_active": String(entitlementStore.addOnPacks)]
                )
            } catch {
                // Error handling is managed by EntitlementStore
            }
        }
    }
}

#if DEBUG
    #Preview {
        let containerService = ContainerService()
        let billingService = PreviewBillingService()
        let entitlementStore = EntitlementStore(billingService: billingService)
        let ragService = RAGService(containerService: containerService, entitlementStore: entitlementStore)
        let settingsStore = SettingsStore(ragService: ragService)
        DocumentLibraryView(ragService: ragService, containerService: containerService)
            .environmentObject(OnboardingStateStore())
            .environmentObject(entitlementStore)
            .environmentObject(settingsStore)
    }

    @MainActor
    private final class PreviewBillingService: BillingService {
        let events: AsyncStream<BillingEvent>

        init() {
            events = AsyncStream { continuation in
                continuation.finish()
            }
        }

        func refreshProducts() async {}

        func purchase(_: BillingProduct) async throws -> StoreKit.Transaction? { nil }

        func restorePurchases() async {}
    }
#endif
