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

    // Delete library confirmation
    @State private var showingDeleteConfirmation = false
    @State private var libraryToDelete: KnowledgeContainer?

    // Vision Capture and Cached Docs
    @State private var showVisionCapture = false
    @State private var showCachedDocs = false

    let onViewVisualizations: (() -> Void)?

    private var documentLimit: Int { entitlementStore.documentLimit }
    private var isAtDocumentLimit: Bool {
        ragService.documents.count >= documentLimit
    }

    private var libraryLimit: Int { entitlementStore.libraryLimit }
    private var shouldShowQuotaBanner: Bool {
        !entitlementStore.hasUnlimitedDocuments
    }

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
        VStack(spacing: 0) {
            // Fixed header section
            VStack(spacing: 12) {
                ContainerPickerStrip(
                    containerService: containerService,
                    allowsCreation: true,
                    onCreateLibrary: handleNewLibraryTapped,
                    onDeleteLibrary: handleDeleteLibrary
                )
                .padding(.horizontal)

                if shouldShowQuotaBanner {
                    DocumentQuotaBanner(
                        currentCount: ragService.documents.count,
                        limit: documentLimit,
                        tierName: entitlementStore.currentPlanDisplayName,
                        addOnPacks: entitlementStore.addOnPacks,
                        packCap: entitlementStore.documentPackCap,
                        remainingPackCapacity: entitlementStore.remainingDocumentPackCapacity,
                        hasReachedPackCap: entitlementStore.hasReachedDocumentPackCap,
                        onUpgrade: { presentPlanSheet(for: .quotaBanner) }
                    )
                    .padding(.horizontal)
                }
            }

            // Expandable content section
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
.frame(maxHeight: .infinity)
    }

    private var documentListView: some View {
        VStack(spacing: 12) {
            ContainerPickerStrip(
                containerService: containerService,
                allowsCreation: true,
                onCreateLibrary: handleNewLibraryTapped,
                onDeleteLibrary: handleDeleteLibrary
            )
            .padding(.horizontal)

            if shouldShowQuotaBanner {
                    DocumentQuotaBanner(
                        currentCount: ragService.documents.count,
                        limit: documentLimit,
                        tierName: entitlementStore.currentPlanDisplayName,
                        addOnPacks: entitlementStore.addOnPacks,
                    packCap: entitlementStore.documentPackCap,
                    remainingPackCapacity: entitlementStore.remainingDocumentPackCapacity,
                    hasReachedPackCap: entitlementStore.hasReachedDocumentPackCap,
                    onUpgrade: { presentPlanSheet(for: .quotaBanner) }
                )
                .padding(.horizontal)
            }
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

                // Stats footer with Auto Intelligence indicator
                StatsFooter(
                    totalDocuments: filteredDocuments.count,
                    totalChunks: filteredTotalChunks,
                    autoIntelligenceEnabled: containerService.activeContainer?.autoAdaptDimension ?? true
                )
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

            // Motherboard HUD - Full-screen X-ray overlay
            // Shows glowing borders at the ACTUAL physical locations where
            // the Neural Engine, GPU, and CPU sit behind the screen
            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false) // Don't block touches
                    .transition(.opacity)
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
                }

                // MARK: - Vision Capture (v2 feature - disabled for v1 App Store release)
                // ToolbarItem(placement: .automatic) {
                //     Button {
                //         showVisionCapture = true
                //     } label: {
                //         Label("Scan Document", systemImage: "doc.viewfinder")
                //     }
                // }

                // Cached Documentation browser
                ToolbarItem(placement: .automatic) {
                    Button {
                        showCachedDocs = true
                    } label: {
                        Label("Cached Docs", systemImage: "doc.on.doc")
                    }
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
                DocumentPicker { urls in
                    enqueueDocumentIngestion(urls)
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
            .alert("Error Processing Document", isPresented: Binding(
                get: { ragService.lastError != nil },
                set: { if !$0 { ragService.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {
                    ragService.lastError = nil
                }
            } message: {
                if let error = ragService.lastError {
                    Text(error)
                }
            }
            .alert("Billing Error", isPresented: Binding(
                get: { entitlementStore.lastError != nil },
                set: { newValue in
                    if !newValue {
                        Task { @MainActor in
                            entitlementStore.lastError = nil
                        }
                    }
                }
            )) {
                Button("OK", role: .cancel) {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            } message: {
                if let error = entitlementStore.lastError {
                    Text(error)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                IngestionQueueOverlay(items: ragService.ingestionItems)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .sheet(isPresented: $showingContainerSettings) {
                ContainerSettingsSheet(containerService: containerService, ragService: ragService)
            }
            // ProcessingSummaryView sheet removed - IngestionQueueOverlay now handles upload status
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
            // MARK: - Vision Capture (v2 feature - disabled for v1 App Store release)
            // .fullScreenCover(isPresented: $showVisionCapture) {
            //     DocumentCaptureView(
            //         ragService: ragService,
            //         containerService: containerService
            //     )
            // }
            .sheet(isPresented: $showCachedDocs) {
                CachedDocsView(ragService: ragService)
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
.alert("Delete Library?", isPresented: $showingDeleteConfirmation) {
    Button("Cancel", role: .cancel) {
        libraryToDelete = nil
    }
    Button("Delete", role: .destructive) {
        confirmDeleteLibrary()
    }
} message: {
    if let lib = libraryToDelete {
        let docCount = ragService.documents.filter { $0.containerId == lib.id }.count
        Text("This will permanently delete \"\(lib.name)\" and all \(docCount) document\(docCount == 1 ? "" : "s") inside it. This cannot be undone.")
    } else {
        Text("This will permanently delete this library and all documents inside it.")
    }
}
// MARK: - NSUserActivity / Handoff
.userActivity("com.openintelligence.documents") { activity in
    activity.title = "Browse Document Library"
    activity.isEligibleForSearch = true
    activity.isEligibleForHandoff = true
    if let containerId = containerService.activeContainerId as UUID? {
        activity.userInfo = ["containerId": containerId]
    }
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
    private func enqueueDocumentIngestion(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        DSHaptics.drop()  // Files dropped/selected feedback
        ragService.enqueueDocuments(urls)
        Task { @MainActor in
            onboardingStore.markSamplesImported()
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

        // CoreML Sentence Embedding is the primary provider (384D, Neural Engine accelerated)
        let embeddingProvider = "coreml_sentence_embedding"

        let newContainer = containerService.createContainer(
            name: libraryName,
            embeddingProviderId: embeddingProvider
        )
        containerService.setActive(newContainer.id)
        newLibraryName = "" // Reset for next time
    }

    @MainActor
    private func handleDeleteLibrary(_ container: KnowledgeContainer) {
        // Can't delete the last library
        guard containerService.containers.count > 1 else { return }
        libraryToDelete = container
        showingDeleteConfirmation = true
    }

    @MainActor
    private func confirmDeleteLibrary() {
        guard let container = libraryToDelete else { return }

        // Haptic for destructive action
        DSHaptics.delete()

        // Get documents in this library before deletion
        let docsToRemove = ragService.documents.filter { $0.containerId == container.id }

        // Remove all documents in this library
        Task {
            for doc in docsToRemove {
                try? await ragService.removeDocument(doc)
            }
        }

        // Delete the container
        containerService.deleteContainer(id: container.id)

        // Invalidate visualization cache
        LibraryVisualizationEngine.shared.invalidateCache(for: container.id)

        // Clean up entity index for deleted container
        Task {
            await EntityIndexService.shared.removeContainer(container.id)
        }

        libraryToDelete = nil
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
