//
//  ContainerSettingsSheet.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation
import NaturalLanguage
import SwiftUI

struct ContainerSettingsSheet: View {
    @ObservedObject var containerService: ContainerService
    @ObservedObject var ragService: RAGService
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @EnvironmentObject private var workspaceSyncService: WorkspaceSyncService
    @Environment(\.dismiss) var dismiss
    @State var name: String = ""
    @State var icon: String = "folder.fill"
    @State var colorHex: String = "#4F46E5"
    @State var syncMode: LibrarySyncMode = .localOnly
    @State var providerId: String = "coreml_sentence_embedding"
    @State var dim: Int = 384
    @State var dbKind: VectorDBKind = .persistentJSON
    @State var autoAdaptDimension: Bool = true
    @State var pendingReembedContext: ReembedContext?
    @State var showingReembedConfirmation = false
    @State var isReembedding = false
    @State var reembedProgress: ReembedProgress?
    @State var reembedError: String?
    @State var hasInitialized = false
    @State var providerAvailability: [String: Bool] = [:]
    @State var showingDBChangeConfirmation = false
    @State var pendingDBChange: VectorDBKind?
    @State private var showingPlanSheet = false
    @State var showingDeleteConfirmation = false

    // Retrieval configuration
    @State var retrievalConfig: RetrievalConfig = .default

    // Chunking configuration
    @State var chunkingStrategy: String = "balanced"
    @State var targetWordWindow: Int = 350
    @State var overlapWords: Int = 60
    @State var chunkingSource: ChunkingDirective.Source = .baseline

    // Provider fallback tracking
    @State var actualProviderInUse: String?
    @State var providerFallbackReason: String?

    // Library Deep Stats (Nerd Mode)
    @State var showNerdStats: Bool = false
    @State var containerFTSStats: [SQLiteFullTextService.DocumentStat] = []
    @State var containerTopTerms: [SQLiteFullTextService.TermFrequency] = []
    @State var isLoadingNerdStats: Bool = false

    // Per-library AI feature overrides
    @State var autoTagOnIngestion: Bool = true
    @State var preferredTranslationLanguage: String = "auto"

    var activeContainer: KnowledgeContainer? {
        containerService.containers.first(where: { $0.id == containerService.activeContainerId })
    }

    var activeIntelligenceReport: LibraryIntelligenceCenter.IntelligenceReport? {
        ragService.intelligenceReport(for: activeContainer?.id)
    }

    private var deleteMessageText: String {
        guard let lib = activeContainer else {
            return "This will permanently delete this library and all documents inside it."
        }
        let docCount = ragService.documents.filter { $0.containerId == lib.id }.count
        let suffix = docCount == 1 ? "" : "s"
        if lib.syncMode == .iCloudShared {
            return "This will permanently delete \"\(lib.name)\" from iCloud Sync and remove it from every device using that shared library, along with all \(docCount) document\(suffix). This cannot be undone."
        } else {
            return "This will permanently delete \"\(lib.name)\" only on this device, along with all \(docCount) document\(suffix) inside it. This cannot be undone."
        }
    }

    private var hasICloudSyncAccess: Bool {
        entitlementStore.effectiveTier.isAtLeast(.pro)
    }



    var lastSelfTuneSummary: String? {
        guard let stamp = activeContainer?.lastSelfTuneAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: stamp, relativeTo: Date())
    }

    /// Check if current provider selection is actually available
    private var isCurrentProviderAvailable: Bool {
        providerAvailability[providerId] ?? true
    }

    /// Get warning message if provider is unavailable
    private var providerUnavailableWarning: String? {
        guard !isCurrentProviderAvailable else { return nil }
        switch providerId {
        case "apple_fm_embed":
            return "Apple Foundation Model embeddings are not yet available. Select a different provider."
        case "nl_contextual_embedding":
            return "Contextual embeddings require a one-time model download. Check network connection."
        case "coreml_sentence_embedding":
            return "No Core ML model found. Import a .mlpackage to use this provider."
        case "coreai_sentence_embedding":
            #if canImport(CoreAI)
            if #available(iOS 27.0, macOS 27.0, *) {
                if CoreAISentenceEmbeddingProvider.shared.isModelLoaded {
                    return nil
                } else if CoreAISentenceEmbeddingProvider.shared.isModelLoadingFailed {
                    return "Failed to load Core AI model. Check model asset presence in bundle."
                } else {
                    return "Core AI model is still loading..."
                }
            }
            #endif
            return "Core AI is not supported on this build/device."
        default:
            return "This provider is not available on your device."
        }
    }

    /// User-friendly name for the current provider
    private var currentProviderName: String {
        switch providerId {
        case "nl_embedding":
            return "Apple Natural Language"
        case "nl_contextual_embedding":
            return "Contextual Embeddings"
        case "coreml_sentence_embedding":
            return "Core ML Sentence"
        case "coreai_sentence_embedding":
            return "Core AI Sentence"
        case "apple_fm_embed":
            return "Apple Foundation Model"
        default:
            return "This provider"
        }
    }

    /// Get supported dimensions for a provider ID
    private func supportedDimensions(for provider: String) -> [Int] {
        guard let option = embeddingProviderOptions.first(where: { $0.id == provider && $0.isSelectable }) else {
            return [512] // Safe fallback
        }
        return option.supportedDimensions.sorted()
    }

    /// Validate and correct dimension if needed for current provider
    private func validateDimensionForProvider(_ newDim: Int) {
        let validDims = supportedDimensions(for: providerId)
        guard !validDims.contains(newDim) else { return }

        // Current dimension is invalid, auto-correct
        if let firstValid = validDims.first {
            Log.warning("[ContainerSettings] Dimension \(newDim) invalid for \(providerId), correcting to \(firstValid)", category: .embedding)
            // Use DispatchQueue to avoid state modification during view update
            DispatchQueue.main.async {
                self.dim = firstValid
            }
        }
    }

    /// Documents in the active container
    var activeContainerDocuments: [Document] {
        guard let containerId = activeContainer?.id else { return [] }
        return documents(for: containerId)
    }

    private func documents(for containerId: UUID) -> [Document] {
        let defaultContainerId = containerService.containers.first?.id
        return ragService.documents.filter { document in
            if let docContainer = document.containerId {
                return docContainer == containerId
            } else {
                return containerId == defaultContainerId
            }
        }
    }

    var body: some View {
        NavigationView {
            Form {
                identitySection
                storageSection
                accuracyDefaultsSection
                intelligenceSection
                privateCloudComputeSection
                chunkingSection
                aiFeatureOverridesSection
                // Search behavior presets removed — auto-tuned by AdaptivePipelineOptimizer
                if settings.developerRAGTuningEnabled {
                    retrievalTuningSection
                }
                embeddingProviderSection
                // Vector database section hidden — always uses persistent JSON storage
                // vectorDatabaseSection
                libraryNerdStatsSection
                deleteLibrarySection
            }
            .navigationTitle("Library Settings")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        handleSave()
                    }
                    .disabled(isReembedding)
                }
            }
            .onAppear {
                guard !hasInitialized else { return }
                hasInitialized = true

                if let c = activeContainer {
                    Log.info("[ContainerSettings] onAppear: Loading container '\(c.name)' with provider=\(c.embeddingProviderId), dim=\(c.embeddingDim)", category: .embedding)
                    name = c.name
                    icon = c.icon
                    colorHex = c.colorHex
                    syncMode = c.syncMode
                    providerId = c.embeddingProviderId
                    // Validate dimension for provider before setting
                    let validDims = supportedDimensions(for: c.embeddingProviderId)
                    if validDims.contains(c.embeddingDim) {
                        dim = c.embeddingDim
                    } else {
                        dim = validDims.first ?? 384
                        Log.warning("[ContainerSettings] Container dimension \(c.embeddingDim) invalid for provider \(c.embeddingProviderId), auto-correcting to \(dim)", category: .embedding)

                        // Auto-save the corrected dimension to prevent repeated mismatches
                        Task { @MainActor in
                            var updated = c
                            updated.embeddingDim = dim
                            containerService.updateContainer(updated)
                            Log.info("[ContainerSettings] Auto-saved corrected dimension \(dim) for container '\(c.name)'", category: .embedding)
                        }
                    }
                    dbKind = c.vectorDBKind
                    retrievalConfig = c.retrievalConfig
                    autoAdaptDimension = c.autoAdaptDimension

                    // Load per-library AI feature overrides
                    autoTagOnIngestion = c.autoTagOnIngestion ?? settings.enableContentTagging
                    preferredTranslationLanguage = c.preferredTranslationLanguage ?? "auto"

                    // Load chunking settings
                    if let directive = c.chunkingDirective {
                        chunkingStrategy = directive.strategy
                        targetWordWindow = directive.targetWordWindow
                        overlapWords = directive.overlapWords
                        chunkingSource = directive.source
                    } else {
                        chunkingStrategy = "balanced"
                        targetWordWindow = 350
                        overlapWords = 60
                        chunkingSource = .baseline
                    }
                } else {
                    Log.warning("[ContainerSettings] onAppear: No active container found", category: .embedding)
                }

                if let containerId = activeContainer?.id {
                    ragService.refreshIntelligence(for: containerId)
                } else {
                    ragService.refreshIntelligence(for: nil)
                }

                // Check provider availability asynchronously
                refreshProviderAvailability()
            }
.onChange(of: providerId) { oldProvider, newProvider in
    guard oldProvider != newProvider else { return }
    Log.info("[ContainerSettings] Provider changed: \(oldProvider) → \(newProvider)", category: .embedding)
                normalizeProviderAndDimension()
            }
            .onChange(of: containerService.activeContainerId) { _, newValue in
                ragService.refreshIntelligence(for: newValue)
                // Re-check availability when container changes
                refreshProviderAvailability()
            }
            .confirmationDialog(
                "Switch to In-Memory storage?",
                isPresented: $showingDBChangeConfirmation,
                presenting: pendingDBChange
            ) { _ in
                Button("Use In-Memory (data lost on restart)", role: .destructive) {
                    pendingDBChange = nil
                    showingDBChangeConfirmation = false
                }
                Button("Keep Persistent Storage", role: .cancel) {
                    if let container = activeContainer {
                        dbKind = container.vectorDBKind
                    } else {
                        dbKind = .persistentJSON
                    }
                    pendingDBChange = nil
                    showingDBChangeConfirmation = false
                }
            } message: { _ in
                Text("In-Memory storage doesn't persist between app launches. Your \(activeContainerDocuments.count) document(s) will need to be re-indexed every time you restart the app.")
            }
            .confirmationDialog(
                "Rebuild embeddings now?",
                isPresented: $showingReembedConfirmation,
                presenting: pendingReembedContext
            ) { context in
                Button("Rebuild now (\(context.documentCount) docs)") {
                    startReembedding(context)
                }
                Button("Later", role: .cancel) {
                    pendingReembedContext = nil
                    showingReembedConfirmation = false
                    dismiss()
                }
            } message: { context in
                Text("You changed the \(context.reason). We'll refresh \(context.documentCount) document\(context.documentCount == 1 ? "" : "s") so search quality stays sharp.")
            }
            .alert("Re-embed failed", isPresented: Binding(
                get: { reembedError != nil },
                set: { if !$0 { reembedError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let message = reembedError {
                    Text(message)
                }
            }
            .sheet(isPresented: $showingPlanSheet) {
                PlanUpgradeSheet(entryPoint: .iCloudSync)
                    .environmentObject(entitlementStore)
            }
            .alert("Delete Library?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                if activeContainer?.syncMode == .iCloudShared {
                    Button("Delete from iCloud", role: .destructive) {
                        confirmDeleteLibrary()
                    }
                } else {
                    Button("Delete Locally", role: .destructive) {
                        confirmDeleteLibrary()
                    }
                }
            } message: {
                Text(deleteMessageText)
            }
        }
    }

    @ViewBuilder
    private var storageSection: some View {
        Section("Storage & Sync") {
            Picker("Library Storage", selection: $syncMode) {
                ForEach(LibrarySyncMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(syncMode.shortDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if syncMode == .iCloudShared {
                Text("Only this library uses iCloud Sync. Local Only libraries in the app stay on-device and do not enter the shared iCloud workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("This library remains fully local on this device. It won't be copied into the shared iCloud workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var embeddingProviderOptions: [EmbeddingProviderOption] {
        var options = [
            // MARK: - CoreML Sentence Embedding (Primary)

            // Custom Core ML model: all-MiniLM-L6-v2 (sentence-transformers)
            // Converted to .mlmodelc via coremltools. 384-dim output.
            // Mean-pooled sentence embeddings with Neural Engine acceleration.
            EmbeddingProviderOption(
                id: "coreml_sentence_embedding",
                icon: "cpu.fill",
                title: "Neural Engine (MiniLM)",
                tagline: "all-MiniLM-L6-v2 • 384-dim",
                detail: "Sentence-transformer model fine-tuned for semantic similarity. Produces 384-dimensional vectors via mean-pooling, accelerated on Neural Engine.",
                isSelectable: true,
                badgeText: "✓ Default",
                supportedDimensions: [384],
                metrics: [
                    OptionMetric(icon: "bolt.fill", text: "ANE accelerated", tint: .orange),
                    OptionMetric(icon: "target", text: "High semantic accuracy"),
                    OptionMetric(icon: "iphone", text: "100% on-device"),
                ],
                alert: nil
            ),
        ]

        var coreAISelectable = false
        var coreAIBadge = "⚡ Native"
        let coreAIDetail = "Apple Intelligence-backed sentence embeddings. Runs zero-copy inference natively on Apple Silicon with 40%+ latency reduction."
        var coreAIAlertMessage: ProviderAvailabilityAlert? = nil

        #if canImport(CoreAI)
        if #available(iOS 27.0, macOS 27.0, *) {
            coreAISelectable = true
        } else {
            coreAIAlertMessage = ProviderAvailabilityAlert(
                id: "coreai_sentence_embedding_os_req",
                icon: "exclamationmark.triangle.fill",
                title: "iOS 27 Required",
                description: "Core AI features require iOS 27.0+ or macOS 27.0+ APIs.",
                bullets: ["Update your device to the latest OS version."],
                accent: .orange
            )
            coreAIBadge = "iOS 27+"
        }
        #else
        coreAIAlertMessage = ProviderAvailabilityAlert(
            id: "coreai_sentence_embedding_build_req",
            icon: "hammer.fill",
            title: "Build Toolchain Issue",
            description: "Core AI is not compiled into this application binary.",
            bullets: ["Rebuild the application using Xcode 27.0+ and the iOS 27 SDK."],
            accent: .red
        )
        coreAIBadge = "Unsupported build"
        #endif

        options.append(
            EmbeddingProviderOption(
                id: "coreai_sentence_embedding",
                icon: "sparkles",
                title: "Core AI Sentence",
                tagline: "Silicon-Native • 384-dim",
                detail: coreAIDetail,
                isSelectable: coreAISelectable,
                badgeText: coreAIBadge,
                supportedDimensions: [384],
                metrics: [
                    OptionMetric(icon: "bolt.fill", text: "Silicon-native ANE", tint: .indigo),
                    OptionMetric(icon: "memorychip", text: "Zero-copy memory"),
                    OptionMetric(icon: "gauge.with.needle", text: "40%+ faster"),
                ],
                alert: coreAIAlertMessage
            )
        )

        return options
    }

    var dimensionOptions: [DimensionOption] {
        [
            // 384D - Native dimension for CoreML Sentence Embedding (MiniLM-L6-v2)
            DimensionOption(
                value: 384,
                icon: "cpu.fill",
                title: "384D • MiniLM-L6-v2",
                caption: "Neural Engine optimized",
                detail: "Native output of the bundled all-MiniLM-L6-v2 sentence-transformer. Mean-pooled token embeddings produce dense 384-dim vectors optimized for cosine similarity.",
                metrics: [
                    OptionMetric(icon: "bolt.fill", text: "ANE accelerated", tint: .orange),
                    OptionMetric(icon: "cube.fill", text: "~0.58 MB / 100 docs"),
                    OptionMetric(icon: "checkmark.seal.fill", text: "Native format"),
                ]
            ),
        ]
    }

    var availableDimensionOptions: [DimensionOption] {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId && $0.isSelectable }) else {
            return []
        }
        return dimensionOptions.filter { option.supportedDimensions.contains($0.value) }
    }

    private var availableDimensionValues: [Int] {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId && $0.isSelectable }) else {
            return [512]
        }
        return option.supportedDimensions.sorted()
    }

    var providerAlerts: [ProviderAvailabilityAlert] {
        embeddingProviderOptions.compactMap { $0.alert }
    }

    var vectorDBOptions: [VectorDBOptionDescriptor] {
        [
            VectorDBOptionDescriptor(
                kind: .persistentJSON,
                icon: "doc.badge.gearshape.fill",
                title: "Persistent JSON",
                caption: "Exact k-NN • Durable",
                detail: "Brute-force cosine similarity over persisted vectors. O(n) search but 100% recall. Survives app restarts."
            ),
            VectorDBOptionDescriptor(
                kind: .vecturaHNSW,
                icon: "point.3.connected.trianglepath.dotted",
                title: "HNSW Graph",
                caption: "Approximate • O(log n)",
                detail: "Hierarchical Navigable Small World graph for sub-ms search on 10K+ vectors. ~95% recall tradeoff."
            ),
            VectorDBOptionDescriptor(
                kind: .inMemory,
                icon: "memorychip.fill",
                title: "In-Memory",
                caption: "Volatile • Testing",
                detail: "RAM-only storage, cleared on app termination. Use for quick experiments without disk I/O."
            ),
        ]
    }

    private func normalizeProviderAndDimension() {
        guard let option = embeddingProviderOptions.first(where: { $0.id == providerId }) else {
            if let fallback = embeddingProviderOptions.first(where: { $0.isSelectable }) {
                providerId = fallback.id
                dim = fallback.supportedDimensions.first ?? dim
            }
            return
        }

        guard option.isSelectable else {
            if let fallback = embeddingProviderOptions.first(where: { $0.isSelectable }) {
                if providerId != fallback.id {
                    providerId = fallback.id
                }
                dim = fallback.supportedDimensions.first ?? dim
            }
            return
        }

        if !option.supportedDimensions.contains(dim) {
            dim = option.supportedDimensions.first ?? dim
        }
    }

    /// Refresh provider availability by checking each embedding service
    private func refreshProviderAvailability() {
        Task {
            #if canImport(CoreAI)
            if #available(iOS 27.0, macOS 27.0, *) {
                await CoreAISentenceEmbeddingProvider.shared.awaitReady()
            }
            #endif

            var availability: [String: Bool] = [:]

            // Check each provider's runtime availability
            for option in embeddingProviderOptions {
                let service = EmbeddingService.forProvider(id: option.id, targetDimension: option.supportedDimensions.first, allowFallback: false)
                availability[option.id] = service.isAvailable
            }

            await MainActor.run {
                self.providerAvailability = availability
                Log.info("[ContainerSettings] Provider availability: \(availability)", category: .embedding)

                // If current provider is unavailable, suggest fallback
                if let currentAvailable = availability[self.providerId], !currentAvailable {
                    Log.warning("[ContainerSettings] Current provider \(self.providerId) is unavailable", category: .embedding)
                }
            }
        }
    }

    private func handleSave() {
        guard var container = activeContainer else { return }
        let previousSyncMode = container.syncMode

        if previousSyncMode != .iCloudShared,
           syncMode == .iCloudShared,
           !hasICloudSyncAccess
        {
            syncMode = previousSyncMode
            showingPlanSheet = true
            return
        }

        let previousProvider = container.embeddingProviderId
        let previousDim = container.embeddingDim
        let previousDB = container.vectorDBKind
        let previousAutoAdapt = container.autoAdaptDimension
        let previousChunking = container.chunkingDirective
        let previousTranslationLanguage = container.preferredTranslationLanguage

        container.name = name
        container.icon = icon
        container.colorHex = colorHex
        container.syncMode = syncMode
        container.embeddingProviderId = providerId
        container.embeddingDim = dim
        container.vectorDBKind = dbKind
        container.retrievalConfig = retrievalConfig
        container.autoAdaptDimension = autoAdaptDimension

        // Save per-library AI feature overrides
        container.autoTagOnIngestion = autoTagOnIngestion == settings.enableContentTagging ? nil : autoTagOnIngestion
        let resolvedTranslationLanguage = preferredTranslationLanguage == "auto" ? nil : preferredTranslationLanguage
        container.preferredTranslationLanguage = resolvedTranslationLanguage

        let resolvedChunkingDirective: ChunkingDirective?
        if autoAdaptDimension {
            resolvedChunkingDirective = previousChunking?.source == .auto ? previousChunking : nil
        } else {
            resolvedChunkingDirective = ChunkingDirective(
                source: .manual,
                strategy: chunkingStrategy,
                targetWordWindow: targetWordWindow,
                overlapWords: overlapWords,
                rationale: ["Manually configured by user"]
            )
        }
        container.chunkingDirective = resolvedChunkingDirective

        if autoAdaptDimension, !previousAutoAdapt {
            container.lastSelfTuneAt = nil
        }

        let providerChanged = previousProvider != providerId
        let syncModeChanged = previousSyncMode != syncMode
        let dimensionChanged = previousDim != dim
        let dbKindChanged = previousDB != dbKind
        let chunkingModeChanged = previousAutoAdapt != autoAdaptDimension
        let translationChanged = previousTranslationLanguage != resolvedTranslationLanguage
        let chunkingChanged = chunkingModeChanged ||
            previousChunking?.source != resolvedChunkingDirective?.source ||
            previousChunking?.targetWordWindow != resolvedChunkingDirective?.targetWordWindow ||
            previousChunking?.overlapWords != resolvedChunkingDirective?.overlapWords ||
            previousChunking?.strategy != resolvedChunkingDirective?.strategy

        // Mark as user-configured to prevent auto-adapt from immediately overriding
        let userConfiguredChunking = !autoAdaptDimension && chunkingChanged
        if providerChanged || dimensionChanged || userConfiguredChunking {
            container.lastSelfTuneAt = Date()
            var manualChanges: [String] = []
            if providerChanged || dimensionChanged {
                manualChanges.append("embeddings \(providerId) @ \(dim)D")
            }
            if userConfiguredChunking {
                manualChanges.append("chunking \(chunkingStrategy) \(targetWordWindow)w/\(overlapWords)w")
            }
            Log.info("[ContainerSettings] User manually configured \(manualChanges.joined(separator: " • "))", category: .ingestion)
        }

        // CRITICAL: Invalidate the cached vector store BEFORE updating the container, so the
        // router builds a fresh database with the correct dimensions.
        //
        // `clearStorage` is deliberately false here. It was `dimensionChanged || providerChanged`,
        // which reaches `VectorStoreRouter.invalidateAndClearStorage` and unlinks `_meta.json`,
        // `_vectors.bin` and `_norms.bin`. That ran roughly fifty lines before the "Rebuild
        // embeddings now?" dialog was even shown, and that dialog's "Later" button only
        // dismisses, so answering Later left the library holding documents with no vectors.
        // Recovery then depended on the self-healing rebuild, which is skipped whenever
        // `isSelfHealingSuppressed` is set for the container, and five separate dismissal paths
        // set it.
        //
        // Dropping the cache is not destructive and still has to happen now. Deleting the vectors
        // is destructive and now happens in `startReembedding`, after the user has agreed to
        // rebuild them.
        if dimensionChanged || providerChanged || dbKindChanged {
            Log.info("[ContainerSettings] Config changed - invalidating vector store cache for container \(container.id)", category: .vectorDB)
            ragService.invalidateVectorStore(for: container.id, clearStorage: false)
        }

        containerService.updateContainer(container)

        if syncModeChanged {
            Task { @MainActor in
                if syncMode == .iCloudShared {
                    _ = await workspaceSyncService.reconfigureForExplicitICloudOptIn()
                } else {
                    _ = await workspaceSyncService.reconfigureIfNeeded()
                }
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()
            }
        }

        if autoAdaptDimension, !previousAutoAdapt {
            ragService.refreshIntelligence(for: container.id, force: true)
        }

        if dimensionChanged {
            Log.info("[ContainerSettings] Embedding dimension changed from \(previousDim) to \(dim). Re-embedding required.", category: .embedding)
        }
        if dbKindChanged {
            Log.info("[ContainerSettings] Vector DB changed to \(dbKind.rawValue).", category: .vectorDB)
        }
        if translationChanged {
            let targetDisplay = resolvedTranslationLanguage ?? "none"
            Log.info("[ContainerSettings] Retrieval translation target changed to \(targetDisplay).", category: .retrieval)
        }

        let needsReembed = (providerChanged || dimensionChanged || translationChanged) && !activeContainerDocuments.isEmpty
        let needsRechunk = chunkingChanged && !activeContainerDocuments.isEmpty && !needsReembed

        if needsReembed {
            pendingReembedContext = ReembedContext(
                containerId: container.id,
                reason: reembedReason(providerChanged: providerChanged, dimensionChanged: dimensionChanged, translationChanged: translationChanged),
                documentCount: activeContainerDocuments.count
            )
            showingReembedConfirmation = true
        } else if needsRechunk {
            pendingReembedContext = ReembedContext(
                containerId: container.id,
                reason: "chunking settings",
                documentCount: activeContainerDocuments.count
            )
            showingReembedConfirmation = true
        } else {
            dismiss()
        }
    }

    @MainActor
    private func confirmDeleteLibrary() {
        guard let container = activeContainer else { return }
        guard containerService.containers.count > 1 else { return }

        DSHaptics.delete()
        dismiss()

        Task {
            if container.syncMode == .iCloudShared {
                do {
                    try await workspaceSyncService.deleteSharedLibrary(container)
                } catch {
                    Log.error("[ContainerSettings] Failed to delete shared library from iCloud: \(error.localizedDescription)", category: .vectorDB)
                }
            }

            let localContainerIDsToDelete: Set<UUID> = [container.id]

            for containerId in localContainerIDsToDelete {
                await ragService.cancelAndPurgeIngestion(for: containerId)
            }

            let docsToRemove = await MainActor.run {
                ragService.documents.filter { document in
                    guard let containerId = document.containerId else { return false }
                    return localContainerIDsToDelete.contains(containerId)
                }
            }

            for doc in docsToRemove {
                try? await ragService.removeDocument(doc)
            }

            await MainActor.run {
                for containerId in localContainerIDsToDelete {
                    containerService.deleteContainer(id: containerId)
                    LibraryVisualizationEngine.shared.invalidateCache(for: containerId)
                }
                containerService.reloadFromDisk()
                ragService.reloadWorkspaceData()
            }

            for containerId in localContainerIDsToDelete {
                await EntityIndexService.shared.removeContainer(containerId)
            }
        }
    }

    private func reembedReason(providerChanged: Bool, dimensionChanged: Bool, translationChanged: Bool) -> String {
        switch (providerChanged, dimensionChanged, translationChanged) {
        case (true, true, _):
            return "provider & resolution"
        case (true, false, true):
            return "embedding provider & translation target"
        case (true, false, false):
            return "embedding provider"
        case (false, true, true):
            return "vector resolution & translation target"
        case (false, true, false):
            return "vector resolution"
        case (false, false, true):
            return "translation target"
        default:
            return "configuration"
        }
    }

    private func startReembedding(_ context: ReembedContext) {
        pendingReembedContext = nil
        showingReembedConfirmation = false
        isReembedding = true
        reembedProgress = ReembedProgress(completed: 0, total: context.documentCount, currentFilename: "")

        // Delete the old vectors here, not in `handleSave`.
        //
        // They are unusable once the provider or dimension has changed, so they do have to go,
        // but only once the user has chosen to rebuild them. Doing it in `handleSave` meant
        // "Later" left the library with documents and no vectors.
        ragService.invalidateVectorStore(for: context.containerId, clearStorage: true)

        Task {
            do {
                try await ragService.reembedDocuments(in: context.containerId) { progress in
                    reembedProgress = progress
                }
                await MainActor.run {
                    isReembedding = false
                    dismiss()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    reembedError = error.localizedDescription
                    isReembedding = false
                }
            }
        }
    }

    // MARK: - Nerd Stats Loading

    /// Load comprehensive library statistics for power users
    func loadNerdStats() {
        guard let container = activeContainer else { return }
        isLoadingNerdStats = true

        Task {
            // Load FTS document stats for this container
            let ftsDocStats = await SQLiteFullTextService.shared.getDocumentStats(containerId: container.id)

            // Load top terms for this library only
            let topTerms = await SQLiteFullTextService.shared.getTopTermsForContainer(containerId: container.id, limit: 20)

            await MainActor.run {
                containerFTSStats = ftsDocStats
                containerTopTerms = topTerms
                isLoadingNerdStats = false
            }
        }
    }
}

// MARK: - Settings Helpers

struct EmbeddingProviderOption: Identifiable {
    let id: String
    let icon: String
    let title: String
    let tagline: String
    let detail: String
    let isSelectable: Bool
    let badgeText: String?
    let supportedDimensions: [Int]
    let metrics: [OptionMetric]
    let alert: ProviderAvailabilityAlert?
}

struct DimensionOption: Identifiable {
    let value: Int
    let icon: String
    let title: String
    let caption: String
    let detail: String
    let metrics: [OptionMetric]

    var id: Int { value }
}

struct VectorDBOptionDescriptor: Identifiable {
    let kind: VectorDBKind
    let icon: String
    let title: String
    let caption: String
    let detail: String

    var id: VectorDBKind { kind }
}

struct ProviderAvailabilityAlert: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String
    let bullets: [String]
    let accent: Color
}

private struct LibraryThemePreset: Identifiable {
    let id: String
    let title: String
    let icon: String
    let colorHex: String
    let description: String
    let retrievalPreset: RetrievalConfig?

    var subtitle: String {
        retrievalPreset?.summary ?? "Balanced"
    }
}

struct ReembedContext: Identifiable {
    let containerId: UUID
    let reason: String
    let documentCount: Int

    var id: UUID { containerId }
}

struct SelectableOptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let detail: String
    let isActive: Bool
    var badgeText: String? = nil
    var isDisabled: Bool = false
    var metrics: [OptionMetric] = []
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(iconColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.headline)
                            .foregroundColor(primaryTextColor)

                        if isActive {
                            Pill(text: "ACTIVE", color: .accentColor)
                        } else if let badge = badgeText {
                            Pill(text: badge, color: .orange)
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(secondaryTextColor)

                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if !metrics.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(metrics) { metric in
                                HStack(spacing: 6) {
                                    Image(systemName: metric.icon)
                                        .font(.caption2)
                                        .foregroundColor(metric.tint)
                                    Text(metric.text)
                                        .font(.caption2)
                                        .foregroundColor(metric.tint)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : (isDisabled ? "lock.circle" : "circle"))
                    .foregroundColor(trailingIconColor)
                    .imageScale(.large)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) embedding provider. \(subtitle)")
        .accessibilityValue(isActive ? "Currently active" : (isDisabled ? "Unavailable" : "Available"))
        .accessibilityHint(isDisabled ? "This provider is not available on your device" : "Double tap to select this embedding provider")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var iconColor: Color {
        if isDisabled { return .secondary.opacity(0.4) }
        return isActive ? .accentColor : .secondary
    }

    private var primaryTextColor: Color {
        isDisabled ? .secondary.opacity(0.7) : .primary
    }

    private var secondaryTextColor: Color {
        isDisabled ? .secondary.opacity(0.6) : .secondary
    }

    private var trailingIconColor: Color {
        if isDisabled { return .secondary.opacity(0.6) }
        return isActive ? .accentColor : .secondary
    }

    private var backgroundColor: Color {
        if isActive { return Color.accentColor.opacity(0.08) }
        if isDisabled { return DSColors.surface.opacity(0.7) }
        return DSColors.surface
    }

    private var borderColor: Color {
        if isActive { return Color.accentColor.opacity(0.6) }
        if isDisabled { return Color.gray.opacity(0.2) }
        return Color.gray.opacity(0.15)
    }

    private struct Pill: View {
        let text: String
        let color: Color

        var body: some View {
            Text(text.uppercased())
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.12))
                .clipShape(Capsule())
        }
    }
}

struct OptionMetric: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    var tint: Color = .secondary
}

struct SettingHelpCallout: View {
    let icon: String
    let title: String
    let description: String
    let bullets: [String]
    var accent: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(accent)
                Text(title)
                    .font(.headline)
            }

            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(accent)
                            .padding(.top, 1)
                        Text(bullet)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.08))
        )
    }
}

struct AutoIntelligencePanel: View {
    let report: LibraryIntelligenceCenter.IntelligenceReport
    let isAutoEnabled: Bool
    var onToggleAuto: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        isAutoEnabled ? "Auto Intelligence is orchestrating" : "Latest intelligence snapshot",
                        systemImage: "wand.and.stars"
                    )
                    .font(.subheadline.weight(.semibold))

                    Text(headline)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(relationshipSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let onToggleAuto {
                    Button(isAutoEnabled ? "Switch to manual" : "Use Auto Intelligence", action: onToggleAuto)
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .tint(isAutoEnabled ? .gray : .accentColor)
                }
            }

            Divider()

            InsightLine(
                icon: "square.stack.3d.down.right",
                title: "Chunking",
                value: "\(report.chunking.strategy.displayName) • \(report.chunking.targetWordWindow)w window / \(report.chunking.overlapWords) overlap",
                detail: report.chunking.rationales.joined(separator: " · ")
            )

            InsightLine(
                icon: "point.3.connected.trianglepath.dotted",
                title: "Embeddings",
                value: "\(friendlyProviderName(report.embedding.providerId)) • \(report.embedding.dimension)D",
                detail: report.embedding.rationale
            )

            InsightLine(
                icon: "line.3.horizontal.decrease.circle",
                title: "Retrieval",
                value: "\(report.retrieval.fusionStyle.displayName) • vector \(percentage(report.retrieval.vectorWeight)) / lexical \(percentage(report.retrieval.lexicalWeight))",
                detail: retrievalDetails
            )

            if let languageDetail = dominantLanguageDetail {
                InsightLine(
                    icon: "globe",
                    title: "Languages",
                    value: languageDetail,
                    detail: report.corpus.multilingualScore > 0.5
                        ? "We’re mapping cross-language references automatically."
                        : "Single-language focus detected, optimizing for nuance."
                )
            }

            if !report.documents.isEmpty {
                Divider()
                DocumentContextSummary(documents: report.documents)
            }

            if !report.alerts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(report.alerts, id: \.self) { alert in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text(alert)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.08)))
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var headline: String {
        let corpus = report.corpus
        guard corpus.documentCount > 0 else {
            return "No documents yet—ready to profile whatever you drop in."
        }
        if corpus.hasMath && corpus.technicalDensity > 0.55 {
            return "Treating this as a precision research stack with deep technical context."
        }
        if corpus.hasCode {
            return "Profiling the library as an engineering playbook that mixes prose and code."
        }
        if corpus.multilingualScore > 0.6 {
            return "Detected a multilingual knowledge base and widened the semantic space."
        }
        if corpus.documentCount >= 5 && corpus.vocabularyRichness < 0.35 {
            return "Blending diverse topics into a general knowledge base while tracking overlaps."
        }
        return "Dialed in as a focused library built around your recent uploads."
    }

    private var relationshipSummary: String {
        let corpus = report.corpus
        if corpus.documentCount == 0 {
            return "Auto Intelligence will relate documents as soon as the first batch lands."
        }
        let docWord = corpus.documentCount == 1 ? "document" : "documents"
        let chunkWord = corpus.chunkCount == 1 ? "chunk" : "chunks"
        var fragments = ["\(corpus.documentCount) \(docWord)", "\(corpus.chunkCount) \(chunkWord)"]
        if corpus.structuredRatio > 0.3 {
            fragments.append("structure-rich sections detected")
        }
        if corpus.hasMath {
            fragments.append("math-heavy passages linked")
        }
        if corpus.hasCode {
            fragments.append("code + prose blended")
        }
        return "Currently orchestrating " + fragments.joined(separator: " • ") + ". We'll keep rebalancing windows and embeddings as you add new domains."
    }

    private var retrievalDetails: String {
        var parts = report.retrieval.notes
        parts.append("MMR λ=\(String(format: "%.2f", report.retrieval.mmrLambda))")
        parts.append("Reranker: \(report.retrieval.reranker.displayName)")
        return parts.joined(separator: " · ")
    }

    private var dominantLanguageDetail: String? {
        guard let dominant = report.corpus.languageHypotheses.max(by: { $0.value < $1.value }) else {
            return nil
        }
        let code = dominant.key.rawValue
        let readable = Locale.current.localizedString(forLanguageCode: code) ?? code
        let extra = report.corpus.languageHypotheses.count > 1
            ? " + \(report.corpus.languageHypotheses.count - 1) others"
            : ""
        return "\(readable)\(extra) (\(percentage(dominant.value)))"
    }

    private func friendlyProviderName(_ providerId: String) -> String {
        switch providerId {
        case "coreml_sentence_embedding":
            return "Core ML Sentence"
        case "apple_fm_embed":
            return "Apple Foundation Model"
        default:
            return "Apple Natural Language"
        }
    }

    private func percentage(_ value: Double) -> String {
        let clamped = max(0, min(value, 1))
        return String(format: "%.0f%%", clamped * 100)
    }
}

private struct InsightLine: View {
    let icon: String
    let title: String
    let value: String
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }

            Text(value)
                .font(.callout)
                .foregroundColor(.primary)

            if let detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct DocumentContextSummary: View {
    let documents: [LibraryIntelligenceCenter.DocumentProfile]

    private var featuredDocuments: [LibraryIntelligenceCenter.DocumentProfile] {
        Array(documents.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Document context", systemImage: "books.vertical")
                .font(.subheadline.weight(.semibold))

            ForEach(featuredDocuments) { profile in
                DocumentProfileRow(profile: profile)
                if profile.id != featuredDocuments.last?.id {
                    Divider()
                }
            }

            if documents.count > featuredDocuments.count {
                Text("+\(documents.count - featuredDocuments.count) more captured in this library")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct DocumentProfileRow: View {
    let profile: LibraryIntelligenceCenter.DocumentProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(profile.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer()
            }

            Text(profile.descriptor)
                .font(.caption)
                .foregroundColor(.secondary)

            if !profile.keyTopics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(profile.keyTopics.prefix(3), id: \.self) { topic in
                        TopicChip(text: topic)
                    }
                }
            }

            if !profile.preview.isEmpty {
                Text(profile.preview)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct TopicChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.15))
            )
            .foregroundColor(.accentColor)
    }
}

private extension LibraryIntelligenceCenter.ChunkingPlan.Strategy {
    var displayName: String {
        switch self {
        case .balanced: return "Balanced"
        case .densePrecision: return "Precision"
        case .elastic: return "Elastic"
        }
    }
}

private extension LibraryIntelligenceCenter.RetrievalPlan.FusionStyle {
    var displayName: String {
        switch self {
        case .hybrid: return "Hybrid"
        case .vectorOnly: return "Vector-first"
        case .lexicalBoosted: return "Lexical boosted"
        }
    }
}

private extension LibraryIntelligenceCenter.RetrievalPlan.RerankerStrategy {
    var displayName: String {
        switch self {
        case .none: return "None"
        case .semantic: return "Semantic"
        case .structural: return "Structural"
        }
    }
}

struct ReembedStatusBanner: View {
    let progress: ReembedProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rebuilding embeddings", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if progress.total > 0 {
                    Text("\(progress.completed)/\(progress.total)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            ProgressView(value: progress.percentage)
                .tint(.orange)

            if !progress.currentFilename.isEmpty {
                Text(progress.currentFilename)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Text("We’ll refresh embeddings so retrieval quality matches your new configuration.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.08))
        )
    }
}

#Preview {
    ContainerSettingsSheet(
        containerService: ContainerService(),
        ragService: RAGService()
    )
    .environmentObject(SettingsStore(ragService: RAGService()))
}
