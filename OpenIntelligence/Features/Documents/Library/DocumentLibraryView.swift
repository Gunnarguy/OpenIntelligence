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
    @State private var pendingImportURLs: [URL] = []
    @State private var pendingImportReview: DocumentImportReview?
    @State private var showingImportReview = false

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
        libraryAlertView
    }

    private var libraryAlertView: some View {
        librarySheetView
            .alert("Sample Import Failed", isPresented: sampleImportErrorBinding) {
                Button("OK", role: .cancel) { sampleImportError = nil }
            } message: {
                if let message = sampleImportError {
                    Text(message)
                }
            }
            .alert("Error Processing Document", isPresented: ragServiceErrorBinding) {
                Button("OK", role: .cancel) {
                    ragService.lastError = nil
                }
            } message: {
                if let error = ragService.lastError {
                    Text(error)
                }
            }
            .alert("Billing Error", isPresented: entitlementErrorBinding) {
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
            .alert("Review Import", isPresented: $showingImportReview) {
                Button("Cancel", role: .cancel) {
                    discardPendingImportFiles()
                    pendingImportReview = nil
                }
                Button("Import Anyway") {
                    confirmPendingImport()
                }
            } message: {
                if let review = pendingImportReview {
                    Text(review.message)
                }
            }
            .userActivity("com.openintelligence.documents") { activity in
                activity.title = "Browse Document Library"
                activity.isEligibleForSearch = true
                activity.isEligibleForHandoff = true
                if let containerId = containerService.activeContainerId as UUID? {
                    activity.userInfo = ["containerId": containerId]
                }
            }
    }

    private var librarySheetView: some View {
        libraryChromeView
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { urls in
                    reviewAndEnqueueDocuments(urls)
                }
            }
            .sheet(isPresented: $showingContainerSettings) {
                ContainerSettingsSheet(containerService: containerService, ragService: ragService)
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
            .sheet(isPresented: $showCachedDocs) {
                CachedDocsView(ragService: ragService)
            }
    }

    private var libraryChromeView: some View {
        libraryContentView
            .navigationTitle("Documents")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
            .toolbar {
                libraryToolbarContent
            }
            .overlay(alignment: .bottomTrailing) {
                IngestionQueueOverlay(items: ragService.ingestionItems)
                .padding(.trailing, 16)
                .padding(.bottom, 16)
            }
    }

    private var libraryContentView: some View {
        ZStack {
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

            if settings.showSiliconHUD {
                HardwareXRayOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
    }

    @ToolbarContentBuilder
    private var libraryToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button(action: presentDocumentPickerOrUpgrade) {
                Label("Add Document", systemImage: "plus")
            }
        }

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

        if !filteredDocuments.isEmpty {
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

    private var sampleImportErrorBinding: Binding<Bool> {
        Binding(
            get: { sampleImportError != nil },
            set: { if !$0 { sampleImportError = nil } }
        )
    }

    private var ragServiceErrorBinding: Binding<Bool> {
        Binding(
            get: { ragService.lastError != nil },
            set: { if !$0 { ragService.lastError = nil } }
        )
    }

    private var entitlementErrorBinding: Binding<Bool> {
        Binding(
            get: { entitlementStore.lastError != nil },
            set: { newValue in
                if !newValue {
                    Task { @MainActor in
                        entitlementStore.lastError = nil
                    }
                }
            }
        )
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

    @MainActor
    private func reviewAndEnqueueDocuments(_ urls: [URL]) {
        guard !urls.isEmpty else { return }

        let review = DocumentImportReview(urls: urls)
        if review.needsReview {
            pendingImportURLs = urls
            pendingImportReview = review
            showingImportReview = true
            return
        }

        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func confirmPendingImport() {
        let urls = pendingImportURLs
        pendingImportURLs = []
        pendingImportReview = nil
        enqueueDocumentIngestion(urls)
    }

    @MainActor
    private func discardPendingImportFiles() {
        let fileManager = FileManager.default
        for url in pendingImportURLs {
            try? fileManager.removeItem(at: url)
        }
        pendingImportURLs = []
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

        let embeddingService = EmbeddingService.forProvider(
            id: settings.defaultEmbeddingProvider,
            allowFallback: true
        )

        let newContainer = containerService.createContainer(
            name: libraryName,
            embeddingProviderId: embeddingService.actualProviderId,
            embeddingDim: embeddingService.outputDimension
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

private struct DocumentImportReview {
    private let transcriptOnlyFiles: [String]
    private let experimentalFiles: [String]
    private let convertFirstFiles: [String]

    init(urls: [URL]) {
        transcriptOnlyFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .transcriptOnly }
            .map(\ .lastPathComponent)
        experimentalFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .experimental }
            .map(\ .lastPathComponent)
        convertFirstFiles = urls
            .filter { DocumentImportReadiness.classify(url: $0) == .convertFirst }
            .map(\ .lastPathComponent)
    }

    var needsReview: Bool {
        !transcriptOnlyFiles.isEmpty || !experimentalFiles.isEmpty || !convertFirstFiles.isEmpty
    }

    var message: String {
        var parts: [String] = [
            "Strongest imports: PDF, DOCX/XLSX/PPTX, TXT/MD, CSV, images, and scans."
        ]

        if !transcriptOnlyFiles.isEmpty {
            parts.append("Transcript only: \(shortList(transcriptOnlyFiles)). Video and audio imports index spoken content, not full visual meaning.")
        }

        if !experimentalFiles.isEmpty {
            parts.append("Reduced-fidelity parsing: \(shortList(experimentalFiles)). These files often lose structure and usually need cleanup first.")
        }

        if !convertFirstFiles.isEmpty {
            parts.append("Convert first for the cleanest results: \(shortList(convertFirstFiles)). Exporting to PDF or modern Office usually gives cleaner retrieval.")
        }

        parts.append("Import anyway?")
        return parts.joined(separator: "\n\n")
    }

    private func shortList(_ files: [String]) -> String {
        let preview = files.prefix(3).joined(separator: ", ")
        if files.count > 3 {
            return "\(preview), +\(files.count - 3) more"
        }
        return preview
    }
}

private enum DocumentImportReadiness {
    case strong
    case transcriptOnly
    case experimental
    case convertFirst

    static func classify(url: URL) -> Self {
        switch url.pathExtension.lowercased() {
        case "pdf", "txt", "md", "markdown", "mdown", "rtf", "csv",
             "docx", "xlsx", "pptx",
             "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp":
            return .strong
        case "m4a", "aac", "mp3", "wav", "wave", "aiff", "aif", "caf", "mp4", "m4v", "mov":
            return .transcriptOnly
        case "doc", "xls", "ppt", "pages", "numbers", "key":
            return .convertFirst
        case "xml", "json", "jsonc", "html", "htm", "yaml", "yml", "css", "scss", "sass", "less",
             "sql", "sh", "bash", "zsh", "fish",
             "swift", "py", "pyw", "pyx", "js", "mjs", "cjs", "ts", "tsx", "java", "class",
             "cpp", "cc", "cxx", "c++", "c", "h", "m", "mm", "go", "rs", "rb", "php",
             "kt", "kts", "scala", "clj", "ex", "exs", "elm", "hs", "lua", "pl", "r", "dart", "vim",
             "avi", "mkv", "webm":
            return .experimental
        default:
            return .experimental
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
