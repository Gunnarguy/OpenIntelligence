//
//  RAGService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Combine
import Foundation
import NaturalLanguage

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Main orchestrator for the RAG (Retrieval-Augmented Generation) pipeline
/// Coordinates document processing, embedding, retrieval, and generation
class RAGService: ObservableObject {

    // MARK: - Dependencies

    private let documentProcessor: DocumentProcessor
    private let embeddingService: EmbeddingService
    let containerService: ContainerService
    private let vectorRouter: VectorStoreRouter
    private var cancellables = Set<AnyCancellable>()

    /// Helper to get document name by ID
    @MainActor
    func getDocumentName(for documentId: UUID) -> String {
        return documents.first(where: { $0.id == documentId })?.filename ?? "Unknown"
    }

    /// Enrich retrieved chunks with source information for citations
    @MainActor
    private func addSourceInfo(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        return chunks.map { retrieved in
            let docName =
                documents.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                ?? "Unknown"
            let pageNum = retrieved.chunk.metadata.pageNumber
            return RetrievedChunk(
                chunk: retrieved.chunk,
                similarityScore: retrieved.similarityScore,
                rank: retrieved.rank,
                sourceDocument: docName,
                pageNumber: pageNum
            )
        }
    }

    // MARK: - Published State (MainActor-isolated for SwiftUI)

    /// The container context for the currently executing query (if any).
    /// Used to scope agentic tool calls and document listings during an in-flight query.
    @MainActor private var currentQueryContainerId: UUID? = nil

    @MainActor @Published var documents: [Document] = []
    @MainActor @Published var isProcessing: Bool = false
    @MainActor @Published var processingStatus: String = ""
    @MainActor @Published var lastError: String? = nil  // User-facing error message
    @MainActor @Published var lastProcessingSummary: ProcessingSummary? = nil  // Detailed completion stats

    private(set) var totalChunksStored: Int = 0

    // MARK: - Public Access (for Settings)

    var llmService: LLMService {
        return _llmService
    }

    private var _llmService: LLMService
    private var _fallbackServices: [LLMService] = []

    // MARK: - Initialization

    init(
        documentProcessor: DocumentProcessor? = nil,
        embeddingService: EmbeddingService? = nil,
        vectorDatabase: VectorDatabase? = nil,
        llmService: LLMService? = nil,
        containerService: ContainerService? = nil,
        vectorRouter: VectorStoreRouter? = nil
    ) {
        self.documentProcessor = documentProcessor ?? DocumentProcessor()
        self.embeddingService = embeddingService ?? EmbeddingService()
        // Container + Vector store routing
        self.containerService = containerService ?? ContainerService()
        self.vectorRouter = vectorRouter ?? VectorStoreRouter()

        // Priority order for LLM selection:
        // 1. Custom service provided by caller
        // 2. OpenAI Direct (if API key configured)
        // 3. Apple ChatGPT Extension (iOS 18.1+ with user consent)
        // 4. On-Device Analysis (extractive QA, always available)

        if let service = llmService {
            // User provided custom service (e.g., from Settings)
            self._llmService = service
            Log.info("✓ Using custom LLM service: \(service.modelName)", category: .initialization)
        } else {
            // Check user's selected model from Settings
            let selectedModelRaw =
                UserDefaults.standard.string(forKey: "selectedLLMModel") ?? "apple_intelligence"

            Log.info(
                "🔧 Initializing with user's selected model: \(selectedModelRaw)",
                category: .initialization)

            // Try to instantiate the user's selected model first
            let primaryService = Self.instantiateService(for: selectedModelRaw)
            var fallbackServices = Self.buildFallbackChain(excluding: selectedModelRaw)

            let resolvedService: LLMService
            if let primaryService {
                resolvedService = primaryService
            } else if let fallback = fallbackServices.first {
                fallbackServices.removeFirst()
                Log.warning(
                    "Selected model \(selectedModelRaw) unavailable; falling back to \(fallback.modelName)",
                    category: .initialization
                )
                Log.info("✓ Using \(fallback.modelName) as active model", category: .initialization)
                resolvedService = fallback
                #if canImport(FoundationModels)
                    if #available(iOS 26.0, *),
                        let foundationFallback = resolvedService as? AppleFoundationLLMService
                    {
                        foundationFallback.startWarmup()
                        Log.debug(
                            "🔥 Preloading model in background for instant first query",
                            category: .initialization)
                    }
                #endif
            } else {
                Log.warning(
                    "No configured LLM available; defaulting to On-Device Analysis",
                    category: .initialization
                )
                resolvedService = OnDeviceAnalysisService()
            }

            self._llmService = resolvedService
            self._fallbackServices = fallbackServices

            // Connect tool handler for agentic RAG (Foundation Models only)
            self._llmService.toolHandler = self
            Log.info("🔗 Tool handler connected for agentic RAG", category: .initialization)
            #if os(iOS)
                if selectedModelRaw == LLMModelType.ggufLocal.rawValue {
                    Task { @MainActor in
                        self.activatePersistedGGUFModel(reason: "startup selection")
                    }
                }
            #endif
        }

        // Load persisted documents metadata
        loadDocumentsFromDisk()
    }

    // MARK: - Document Persistence

    private var documentsStorageURL: URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appDirectory = appSupportURL.appendingPathComponent("OpenIntelligence", isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("documents_metadata.json")
    }

    private func loadDocumentsFromDisk() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: documentsStorageURL.path) else {
            print("ℹ️  [RAGService] No existing documents metadata found")
            return
        }

        do {
            let data = try Data(contentsOf: documentsStorageURL)
            let decoder = JSONDecoder()
            let loadedDocuments = try decoder.decode([Document].self, from: data)

            Task { @MainActor in
                self.documents = loadedDocuments
                self.totalChunksStored = loadedDocuments.reduce(0) { $0 + $1.totalChunks }
                print(
                    "✅ [RAGService] Loaded \(loadedDocuments.count) documents (\(totalChunksStored) chunks)"
                )
            }
        } catch {
            print("❌ [RAGService] Failed to load documents metadata: \(error.localizedDescription)")
        }
    }

    private func saveDocumentsToDisk() {
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = try encoder.encode(documents)
                try data.write(to: documentsStorageURL, options: .atomic)
                print("💾 [RAGService] Saved \(documents.count) documents metadata")
            } catch {
                print(
                    "❌ [RAGService] Failed to save documents metadata: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Vector DB Access

    private func dbForActiveContainer() async -> VectorDatabase {
        let container = await MainActor.run { self.containerService.activeContainer }
        // ContainerService guarantees at least one container
        return self.vectorRouter.db(for: container!)
    }

    /// Return a database for a specific container id (falls back to active on miss)
    private func dbFor(_ containerId: UUID) async -> VectorDatabase {
        let container = await MainActor.run {
            self.containerService.containers.first { $0.id == containerId }
        }
        if let c = container {
            return self.vectorRouter.db(for: c)
        } else {
            return await dbForActiveContainer()
        }
    }

    /// Return all chunks stored for the active container.
    /// Used by visualization views to render embedding spaces and statistics.
    func allChunksForActiveContainer() async -> [DocumentChunk] {
        let db = await dbForActiveContainer()
        do {
            return try await db.allChunks()
        } catch {
            print(
                "❌ [RAGService] Failed to load all chunks for active container: \(error.localizedDescription)"
            )
            return []
        }
    }

    // MARK: - LLM Service Management

    /// Dynamically updates the LLM service (called from Settings)
    func updateLLMService(_ newService: LLMService) async {
        await MainActor.run {
            self._llmService = newService
            Log.info("✓ Switched to: \(newService.modelName)", category: .initialization)
        }
    }

    /// Run a lightweight semantic search against the active container.
    /// Returns ranked chunks enriched with document metadata for UI display.
    func semanticSearch(
        query: String,
        topK: Int = 6,
        minSimilarity: Float? = nil
    ) async throws -> [RetrievedChunk] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RAGServiceError.emptyQuery }

        let queryEmbedding = try await embeddingService.generateEmbedding(for: trimmed)
        let selectedId = await MainActor.run {
            self.currentQueryContainerId ?? self.containerService.activeContainerId
        }
        let database = await dbFor(selectedId)
        let searchCount = max(1, min(topK * 2, topK + 4))
        var candidates = try await database.search(embedding: queryEmbedding, topK: searchCount)

        if let threshold = minSimilarity {
            let engine = RAGEngine()
            candidates = await engine.filterBySimilarity(chunks: candidates, min: threshold)
        }

        if candidates.count > topK {
            candidates = Array(candidates.prefix(topK))
        }

        let ranked = candidates.enumerated().map { index, chunk in
            RetrievedChunk(
                chunk: chunk.chunk,
                similarityScore: chunk.similarityScore,
                rank: index + 1
            )
        }

        let enriched = await MainActor.run { self.addSourceInfo(ranked) }
        TelemetryCenter.emit(
            .retrieval,
            title: "Semantic search",
            metadata: [
                "query": String(trimmed.prefix(80)),
                "results": "\(enriched.count)",
                "topK": "\(topK)"
            ]
        )
        return enriched
    }

    // MARK: - Document Management

    /// Add a document to the knowledge base
    /// This performs the full ingestion pipeline: parse → chunk → embed → store
    func addDocument(at url: URL) async throws {
        let filename = url.lastPathComponent
        let activeContainerId = await MainActor.run { self.containerService.activeContainerId }
        let pipelineStartTime = Date()
        TelemetryCenter.emit(
            .ingestion,
            title: "Ingestion started",
            metadata: ["file": filename]
        )

        await MainActor.run {
            isProcessing = true
            processingStatus = "\(filename) • Loading"
        }

        // Give UI time to show the overlay (testing delay)
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 full second

        // Set up progress handler for real-time updates
        documentProcessor.progressHandler = { [weak self] progress in
            Task { @MainActor in
                self?.processingStatus = "\(filename) • Extracting (\(progress))"
            }
        }

        do {
            // Step 1: Parse document and extract chunks
            let extractionStartTime = Date()
            let (document, textChunks) = try await documentProcessor.processDocument(at: url)
            let extractionTime = Date().timeIntervalSince(extractionStartTime)
            let totalChars = textChunks.reduce(0) { $0 + $1.count }
            let totalWords = textChunks.reduce(0) { $0 + $1.split(separator: " ").count }

            TelemetryCenter.emit(
                .ingestion,
                title: "Extraction complete",
                metadata: [
                    "file": filename,
                    "chunks": "\(textChunks.count)",
                    "words": "\(totalWords)",
                ],
                duration: extractionTime
            )

            await MainActor.run {
                processingStatus =
                    "\(filename) • Chunking (\(textChunks.count) chunks, \(totalWords) words)"
            }

            print("\n🔢 [RAGService] Chunking complete:")
            print("   \(textChunks.count) chunks, \(totalChars) chars, \(totalWords) words")

            // Small delay to show the chunking message
            try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2s

            // Step 2: Generate embeddings with progress updates
            print("\n🧠 [RAGService] Generating embeddings...")
            var embeddings: [[Float]] = []
            let embeddingStartTime = Date()

            for (index, text) in textChunks.enumerated() {
                await MainActor.run {
                    processingStatus = "\(filename) • Embedding (\(index + 1)/\(textChunks.count))"
                }

                let chunkStartTime = Date()
                let embedding = try await embeddingService.generateEmbedding(for: text)
                let chunkTime = Date().timeIntervalSince(chunkStartTime)

                embeddings.append(embedding)
                print(
                    "   ✓ Chunk \(index + 1)/\(textChunks.count): \(embedding.count)-dim vector (\(String(format: "%.0f", chunkTime * 1000))ms)"
                )
            }

            let embeddingTime = Date().timeIntervalSince(embeddingStartTime)
            let avgTimePerChunk = embeddingTime / Double(textChunks.count)
            print(
                "   ✅ All embeddings generated in \(String(format: "%.2f", embeddingTime))s (avg \(String(format: "%.0f", avgTimePerChunk * 1000))ms/chunk)"
            )
            TelemetryCenter.emit(
                .embedding,
                title: "Embeddings generated",
                metadata: [
                    "file": filename,
                    "chunks": "\(textChunks.count)",
                    "dimensions": "\(embeddings.first?.count ?? 0)",
                ],
                duration: embeddingTime
            )

            await MainActor.run {
                processingStatus = "\(filename) • Storing"
            }

            // Step 3: Create DocumentChunk objects with embeddings
            let chunkingStartTime = Date()
            let documentChunks = zip(textChunks, embeddings).enumerated().map { index, pair in
                let (text, embedding) = pair
                return DocumentChunk(
                    documentId: document.id,
                    content: text,
                    embedding: embedding,
                    metadata: ChunkMetadata(
                        chunkIndex: index,
                        startPosition: 0,  // Could be enhanced with actual positions
                        endPosition: text.count
                    )
                )
            }
            let chunkingTime = Date().timeIntervalSince(chunkingStartTime)
            TelemetryCenter.emit(
                .storage,
                title: "Chunks prepared",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ],
                duration: chunkingTime
            )

            // Step 4: Store chunks in vector database (per active container)
            let db = await dbForActiveContainer()
            try await db.storeBatch(chunks: documentChunks)
            // Invalidate visualization cache for this container after data change
            ProjectionCache.shared.invalidate(forContainer: activeContainerId)
            TelemetryCenter.emit(
                .storage,
                title: "Chunks stored",
                metadata: [
                    "file": filename,
                    "count": "\(documentChunks.count)",
                ]
            )

            // Calculate total pipeline time
            let totalTime = Date().timeIntervalSince(pipelineStartTime)

            // Calculate chunk statistics
            let chunkSizes = textChunks.map { $0.count }
            let avgChunkSize = chunkSizes.reduce(0, +) / chunkSizes.count
            let minChunkSize = chunkSizes.min() ?? 0
            let maxChunkSize = chunkSizes.max() ?? 0

            // Get file size
            let fileSize =
                try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
            let fileSizeMB: Double
            let fileSizeStr: String
            if let size = fileSize {
                fileSizeMB = Double(size) / (1024.0 * 1024.0)
                if size < 1024 {
                    fileSizeStr = "\(size) B"
                } else if size < 1024 * 1024 {
                    fileSizeStr = String(format: "%.2f KB", Double(size) / 1024.0)
                } else {
                    fileSizeStr = String(format: "%.2f MB", fileSizeMB)
                }
            } else {
                fileSizeMB = 0
                fileSizeStr = "Unknown"
            }

            // Update document with embedding time and complete metadata
            var updatedDocument = document
            if let existingMetadata = document.processingMetadata {
                // Create new metadata with embedding time added
                let completeMetadata = ProcessingMetadata(
                    fileSizeMB: fileSizeMB,
                    totalCharacters: existingMetadata.totalCharacters,
                    totalWords: existingMetadata.totalWords,
                    extractionTimeSeconds: existingMetadata.extractionTimeSeconds,
                    chunkingTimeSeconds: existingMetadata.chunkingTimeSeconds,
                    embeddingTimeSeconds: embeddingTime,
                    totalProcessingTimeSeconds: totalTime,
                    pagesProcessed: existingMetadata.pagesProcessed,
                    ocrPagesCount: existingMetadata.ocrPagesCount,
                    chunkStats: existingMetadata.chunkStats
                )

                updatedDocument = Document(
                    id: document.id,
                    filename: document.filename,
                    fileURL: document.fileURL,
                    contentType: document.contentType,
                    addedAt: document.addedAt,
                    totalChunks: document.totalChunks,
                    processingMetadata: completeMetadata
                )
            }

            // Ensure document is associated with the active container
            let docWithContainer = Document(
                id: updatedDocument.id,
                filename: updatedDocument.filename,
                fileURL: updatedDocument.fileURL,
                contentType: updatedDocument.contentType,
                addedAt: updatedDocument.addedAt,
                totalChunks: updatedDocument.totalChunks,
                processingMetadata: updatedDocument.processingMetadata,
                containerId: activeContainerId
            )
            updatedDocument = docWithContainer

            // Create processing summary
            let summary = ProcessingSummary(
                filename: filename,
                fileSize: fileSizeStr,
                documentType: document.contentType,
                pageCount: nil,  // TODO: Extract from DocumentProcessor
                ocrPagesUsed: nil,  // TODO: Extract from DocumentProcessor
                totalChars: totalChars,
                totalWords: totalWords,
                chunksCreated: textChunks.count,
                extractionTime: extractionTime,
                chunkingTime: chunkingTime,
                embeddingTime: embeddingTime,
                totalTime: totalTime,
                chunkStats: ProcessingSummary.ChunkStatistics(
                    avgChars: avgChunkSize,
                    minChars: minChunkSize,
                    maxChars: maxChunkSize
                )
            )

            // Step 5: Update state
            await MainActor.run {
                documents.append(updatedDocument)
                totalChunksStored += documentChunks.count
                processingStatus = ""
                lastProcessingSummary = summary
            }

            TelemetryCenter.emit(
                .ingestion,
                title: "Document indexed",
                metadata: [
                    "file": filename,
                    "chunks": "\(documentChunks.count)",
                    "size": fileSizeStr,
                ],
                duration: totalTime
            )

            // Save documents metadata to disk
            saveDocumentsToDisk()

            // Small success flash
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1s

            await MainActor.run {
                isProcessing = false
            }

            print("✅ [RAGService] Document ingestion complete:")
            print("   Filename: \(updatedDocument.filename)")
            print("   Chunks created: \(textChunks.count)")
            print("   Total chunks in database: \(totalChunksStored)")

        } catch {
            // Reset processing state on error
            await MainActor.run {
                isProcessing = false
                processingStatus = ""

                // Set user-friendly error message
                lastError = error.localizedDescription
            }

            // Re-throw with context
            print("❌ [RAGService] Failed to add document: \(error.localizedDescription)")
            TelemetryCenter.emit(
                .ingestion,
                severity: .error,
                title: "Ingestion failed",
                metadata: [
                    "file": filename,
                    "error": error.localizedDescription,
                ]
            )
            throw error
        }
    }

    /// Remove a document from the knowledge base
    func removeDocument(_ document: Document) async throws {
        let db = await dbForActiveContainer()
        try await db.deleteChunks(forDocument: document.id)

        // Invalidate visualization cache for active container after removal
        let activeId = await MainActor.run { self.containerService.activeContainerId }
        ProjectionCache.shared.invalidate(forContainer: activeId)

        await MainActor.run {
            documents.removeAll { $0.id == document.id }
            totalChunksStored -= document.totalChunks
        }

        saveDocumentsToDisk()

        print("✓ Removed document: \(document.filename)")
    }

    /// Clear all documents from the knowledge base
    func clearAllDocuments() async throws {
        let db = await dbForActiveContainer()
        try await db.clear()

        let activeId = await MainActor.run { self.containerService.activeContainerId }
        // Invalidate visualization cache for the cleared container
        ProjectionCache.shared.invalidate(forContainer: activeId)

        await MainActor.run {
            documents.removeAll { $0.containerId == activeId }
            totalChunksStored = documents.reduce(0) { $0 + $1.totalChunks }
        }

        saveDocumentsToDisk()

        print("✓ Cleared all documents from knowledge base")
    }

    // MARK: - RAG Query Pipeline

    /// Execute a RAG query: expand query → embed → hybrid search → re-rank → generate response
    func query(
        _ question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        streamHandler: LLMStreamHandler? = nil
    ) async throws -> RAGResponse {
        return try await LLMStreamingContext.$handler.withValue(streamHandler) {
            try await self.queryInternal(
                question, topK: topK, config: config, containerId: containerId)
        }
    }

    private func queryInternal(
        _ question: String, topK: Int, config: InferenceConfig?, containerId: UUID?
    ) async throws -> RAGResponse {
        let inferenceConfig = config ?? InferenceConfig()
        let strictMode: Bool = await MainActor.run {
            if let id = containerId,
                let container = self.containerService.containers.first(where: { $0.id == id })
            {
                return container.strictMode
            } else {
                return self.containerService.activeContainer?.strictMode ?? false
            }
        }
        // Establish query-scoped container context for downstream tool calls and listings
        await MainActor.run {
            self.currentQueryContainerId = containerId ?? self.containerService.activeContainerId
        }
        // Optional DB warmup to ensure the vector store is loaded (prevents first-touch latency)
        let _ = try? await (containerId != nil ? dbFor(containerId!) : dbForActiveContainer())
            .count()
        // Ensure cleanup even if an error is thrown later in the pipeline
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }
        // Selected container context details (id/name/dimension)
        let (selectedId, selectedName, selectedDim) = await MainActor.run {
            () -> (UUID, String, Int) in
            let id = containerId ?? self.containerService.activeContainerId
            let container = self.containerService.containers.first { $0.id == id }
            let name = container?.name ?? "Unknown"
            let dim = container?.embeddingDim ?? 512
            return (id, name, dim)
        }
        // Query heuristics for short/generic prompts
        let queryWords = question.split(separator: " ").count
        let effectiveTopK = max(1, (queryWords <= 2) ? min(topK, 3) : min(topK, 10))
        // Fetch current stored chunk count from vector database (fallback to cached total)
        let vdb = await (containerId != nil ? dbFor(containerId!) : dbForActiveContainer())
        let totalStored = (try? await vdb.count()) ?? totalChunksStored

        Log.box(
            "ENHANCED RAG QUERY PIPELINE",
            level: .info,
            category: .pipeline,
            content: [
                "📝 Query: \(question)",
                "🎯 Retrieving top \(effectiveTopK) chunks from \(totalStored) total",
            ]
        )

        TelemetryCenter.emit(
            .system,
            title: "Query received",
            metadata: [
                "question": String(question.prefix(80)),
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "words": "\(queryWords)",
                "characters": "\(question.count)",
                "topK": "\(effectiveTopK)",
                "strictMode": strictMode ? "true" : "false",
            ]
        )

        do {
            // Clear any previous errors
            await MainActor.run {
                lastError = nil
            }

            // Edge case: Empty query
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.error("❌ [RAGService] Empty query string", category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    severity: .error,
                    title: "Query rejected",
                    metadata: ["reason": "Empty input"]
                )
                throw RAGServiceError.emptyQuery
            }

            let pipelineStartTime = Date()
            let ragQuery = RAGQuery(query: question, topK: effectiveTopK)

            // Small-talk/direct-chat bypass for trivial inputs (no RAG)
            let lowerQ = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if queryWords <= 2 {
                let smallTalkSet: Set<String> = [
                    "hi", "hello", "hey", "yo", "sup", "ok", "thanks", "thank you", "bye",
                    "goodbye", "hola", "hiya",
                ]
                if smallTalkSet.contains(lowerQ) {
                    return try await generateDirectChatResponse(
                        question: question,
                        ragQuery: ragQuery,
                        inferenceConfig: inferenceConfig,
                        pipelineStartTime: pipelineStartTime,
                        retrievalTime: 0,
                        fallbackNote: "Short greeting detected; replied without document retrieval."
                    )
                }
            }

            // Check if we have documents for RAG or just direct LLM chat (use live DB count)
            let hasDocuments = totalStored > 0

            if hasDocuments {
                // ENHANCED RAG pipeline with query expansion + hybrid search + re-ranking

                // Step 1: Query Expansion
                Log.section("Step 1: Query Expansion", level: .info, category: .pipeline)
                let expansionStartTime = Date()
                let queryEnhancer = QueryEnhancementService()
                let expandedQueries = queryEnhancer.expandQuery(question)
                let expansionTime = Date().timeIntervalSince(expansionStartTime)
                Log.info(
                    "✓ Expanded to \(expandedQueries.count) query variations in \(String(format: "%.0f", expansionTime * 1000))ms",
                    category: .pipeline)
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Query expanded",
                    metadata: [
                        "variants": "\(expandedQueries.count)"
                    ],
                    duration: expansionTime
                )

                // Step 2: Embed the user's query (primary query only)
                Log.section("Step 2: Query Embedding", level: .info, category: .pipeline)
                let embeddingStartTime = Date()
                let queryEmbedding = try await embeddingService.generateEmbedding(for: question)
                let embeddingTime = Date().timeIntervalSince(embeddingStartTime)

                let embeddingMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
                Log.info(
                    "✓ Generated \(queryEmbedding.count)-dimensional embedding",
                    category: .embedding)
                Log.debug(
                    "  Vector magnitude: \(String(format: "%.4f", embeddingMagnitude))",
                    category: .embedding)
                Log.debug(
                    "  Time: \(String(format: "%.0f", embeddingTime * 1000))ms",
                    category: .performance)
                TelemetryCenter.emit(
                    .embedding,
                    title: "Query embedding",
                    metadata: [
                        "dimensions": "\(queryEmbedding.count)"
                    ],
                    duration: embeddingTime
                )

                // Warn if embedding dimension doesn't match the selected library's index dimension
                if queryEmbedding.count != selectedDim {
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Embedding dimension mismatch",
                        metadata: [
                            "expected": "\(selectedDim)",
                            "got": "\(queryEmbedding.count)",
                            "container": selectedName,
                            "containerId": selectedId.uuidString,
                        ]
                    )
                }

                // Step 3: Hybrid Search (vector + BM25 keyword search with RRF fusion)
                Log.section(
                    "Step 3: Hybrid Search (Vector + BM25)", level: .info, category: .pipeline)
                let retrievalStartTime = Date()
                let hybridSearch = HybridSearchService(vectorDatabase: vdb)
                // Use expanded queries for keyword search (original for vector)
                let retrievedChunks = try await hybridSearch.search(
                    query: expandedQueries.joined(separator: " "),  // Combine expansions
                    embedding: queryEmbedding,
                    topK: effectiveTopK * 2  // Retrieve 2x for re-ranking (clamped)
                )

                // Measure retrieval time before any MainActor work
                let retrievalTime = Date().timeIntervalSince(retrievalStartTime)

                // Edge case: No relevant chunks found - gracefully fallback to direct chat
                if retrievedChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] No chunks retrieved (database may be empty)",
                        category: .retrieval)
                    TelemetryCenter.emit(
                        .retrieval,
                        severity: .warning,
                        title: "No chunks retrieved",
                        metadata: [
                            "question": String(question.prefix(60))
                        ],
                        duration: retrievalTime
                    )
                    // Fallback to direct LLM chat mode
                    return try await generateDirectChatResponse(
                        question: question,
                        ragQuery: ragQuery,
                        inferenceConfig: inferenceConfig,
                        pipelineStartTime: pipelineStartTime,
                        retrievalTime: retrievalTime,
                        fallbackNote:
                            "No relevant document context found; replied without RAG context."
                    )
                }

                // Add source information for citations with a safe MainActor snapshot
                let docsSnapshot = await snapshotDocuments()
                let chunksWithSources: [RetrievedChunk] = retrievedChunks.map { retrieved in
                    let docName =
                        docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                        ?? "Unknown"
                    let pageNum = retrieved.chunk.metadata.pageNumber
                    return RetrievedChunk(
                        chunk: retrieved.chunk,
                        similarityScore: retrieved.similarityScore,
                        rank: retrieved.rank,
                        sourceDocument: docName,
                        pageNumber: pageNum
                    )
                }

                let chunkWordCounts = chunksWithSources.map { wordCount(of: $0.chunk.content) }
                let totalChunkWords = chunkWordCounts.reduce(0, +)
                let topContextWords = chunkWordCounts.prefix(effectiveTopK).reduce(0, +)
                let averageChunkWords =
                    chunkWordCounts.isEmpty
                    ? 0.0
                    : Double(totalChunkWords) / Double(chunkWordCounts.count)

                TelemetryCenter.emit(
                    .retrieval,
                    title: "Hybrid retrieval",
                    metadata: [
                        "candidates": "\(chunksWithSources.count)",
                        "topK": "\(effectiveTopK * 2)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                        "totalWords": "\(totalChunkWords)",
                        "topWords": "\(topContextWords)",
                        "avgWords": String(format: "%.1f", averageChunkWords),
                    ],
                    duration: retrievalTime
                )

                Log.info(
                    "✓ Retrieved \(chunksWithSources.count) chunks with hybrid fusion",
                    category: .retrieval)
                Log.debug(
                    "  Time: \(String(format: "%.0f", retrievalTime * 1000))ms",
                    category: .performance)
                if let topChunk = chunksWithSources.first {
                    Log.debug(
                        "  Top semantic score: \(String(format: "%.4f", topChunk.similarityScore))",
                        category: .retrieval)
                    if !topChunk.sourceDocument.isEmpty {
                        Log.debug(
                            "  Source: \(topChunk.sourceDocument)\(topChunk.pageNumber.map { " (p. \($0))" } ?? "")",
                            category: .retrieval)
                    }
                    // BM25 and fusion scores would be displayed here once metadata storage is enhanced
                }

                // Step 4: Re-rank results with multiple signals
                Log.section("Step 4: Multi-Signal Re-ranking", level: .info, category: .pipeline)
                let engine = RAGEngine()
                let rerankStartTime = Date()
                let rerankedChunks = await engine.rerank(
                    chunks: chunksWithSources,
                    query: question,
                    topK: effectiveTopK * 3  // Get more candidates for MMR diversification (clamped)
                )
                let rerankTime = Date().timeIntervalSince(rerankStartTime)
                Log.info(
                    "✓ Re-ranked to top \(rerankedChunks.count) in \(String(format: "%.0f", rerankTime * 1000))ms",
                    category: .retrieval)
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Re-ranking complete",
                    metadata: [
                        "candidates": "\(rerankedChunks.count)"
                    ],
                    duration: rerankTime
                )

                if rerankedChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] Re-ranking yielded no candidates; falling back to direct chat",
                        category: .retrieval)
                    return try await generateDirectChatResponse(
                        question: question,
                        ragQuery: ragQuery,
                        inferenceConfig: inferenceConfig,
                        pipelineStartTime: pipelineStartTime,
                        retrievalTime: retrievalTime,
                        fallbackNote: "No re-ranked candidates; replied without RAG context."
                    )
                }

                // Step 4.3: Filter low-confidence chunks (critical for medical accuracy)
                // Adaptive gating: consider "lenient" mode and trivial/short queries
                let lenient = UserDefaults.standard.bool(forKey: "lenientRetrievalMode")
                let isTrivial =
                    (queryWords <= 2)
                    || ["test", "help", "hello", "hi", "hey", "ok", "okay"].contains(lowerQ)

                // Relative-score metrics (computed on reranked results)
                let topSim: Float = rerankedChunks.first?.similarityScore ?? 0
                let secondSim: Float = rerankedChunks.dropFirst().first?.similarityScore ?? 0
                let avgTop5: Float = {
                    let sims = rerankedChunks.prefix(5).map { $0.similarityScore }
                    guard !sims.isEmpty else { return 0 }
                    return sims.reduce(0, +) / Float(sims.count)
                }()

                // Dynamic threshold: strict by default, relaxed when lenient or trivial
                let dynamicMin: Float = (strictMode && !lenient && !isTrivial) ? 0.52 : 0.35
                var filteredChunks = await engine.filterBySimilarity(
                    chunks: rerankedChunks,
                    min: dynamicMin
                )

                // Acceptance override if relative signals are strong even with modest absolute scores
                let acceptanceOverride: Bool =
                    (topSim >= 0.50) || (topSim >= 0.38 && (topSim - avgTop5) >= 0.05)
                    || ((topSim - secondSim) >= 0.07)

                TelemetryCenter.emit(
                    .retrieval,
                    title: "Gating metrics",
                    metadata: [
                        "strictMode": strictMode ? "true" : "false",
                        "lenient": lenient ? "true" : "false",
                        "isTrivial": isTrivial ? "true" : "false",
                        "topSim": String(format: "%.3f", topSim),
                        "secondSim": String(format: "%.3f", secondSim),
                        "avgTop5": String(format: "%.3f", avgTop5),
                        "minSim": String(format: "%.2f", dynamicMin),
                        "override": acceptanceOverride ? "true" : "false",
                    ]
                )

                if filteredChunks.count < rerankedChunks.count {
                    let dropped = rerankedChunks.count - filteredChunks.count
                    Log.warning(
                        "   ⚠️  Filtered out \(dropped) low-confidence chunks (< \(String(format: "%.2f", dynamicMin)))",
                        category: .retrieval)
                    TelemetryCenter.emit(
                        .retrieval,
                        severity: .warning,
                        title: "Low-confidence filtered",
                        metadata: ["dropped": "\(dropped)"]
                    )
                }

                // Edge case: No high-confidence chunks
                if filteredChunks.isEmpty {
                    if acceptanceOverride || lenient || isTrivial {
                        // Use top reranked results directly under override/lenient conditions
                        filteredChunks = Array(rerankedChunks.prefix(effectiveTopK * 2))
                        Log.info(
                            "   ✅ Acceptance override applied; proceeding with top reranked results",
                            category: .retrieval)
                        TelemetryCenter.emit(
                            .retrieval,
                            title: "Acceptance override",
                            metadata: [
                                "topSim": String(format: "%.3f", topSim),
                                "secondSim": String(format: "%.3f", secondSim),
                                "avgTop5": String(format: "%.3f", avgTop5),
                            ]
                        )
                    } else {
                        // Graceful fallback: try On-Device Analysis with extracted context
                        Log.error(
                            "   ❌ No high-confidence chunks found (all below threshold) — falling back to On‑Device Analysis",
                            category: .retrieval)
                        TelemetryCenter.emit(
                            .retrieval,
                            severity: .error,
                            title: "No high-confidence context (fallback to On‑Device Analysis)",
                            metadata: [
                                "threshold": String(format: "%.2f", dynamicMin)
                            ]
                        )

                        // Assemble concise context from the best available reranked results
                        let (fallbackContext, usedCount) = await engine.assembleContext(
                            chunks: Array(rerankedChunks.prefix(max(effectiveTopK, 3))),
                            maxChars: (llmService is AppleFoundationLLMService) ? 1200 : 2500
                        )

                        let local = OnDeviceAnalysisService()
                        let fallbackResp = try await local.generate(
                            prompt: question,
                            context: fallbackContext.isEmpty ? nil : fallbackContext,
                            config: inferenceConfig
                        )

                        let meta = ResponseMetadata(
                            timeToFirstToken: fallbackResp.timeToFirstToken,
                            totalGenerationTime: fallbackResp.totalTime,
                            tokensGenerated: fallbackResp.tokensGenerated,
                            tokensPerSecond: fallbackResp.tokensPerSecond,
                            modelUsed: local.modelName,
                            retrievalTime: retrievalTime,
                            strictModeEnabled: strictMode,
                            gatingDecision: "fallback_ondevice_low_confidence"
                        )

                        return RAGResponse(
                            queryId: ragQuery.id,
                            retrievedChunks: Array(
                                rerankedChunks.prefix(usedCount > 0 ? usedCount : effectiveTopK)),
                            generatedResponse: fallbackResp.text,
                            metadata: meta,
                            confidenceScore: 0.0,
                            qualityWarnings: [
                                "Low-confidence retrieval: answered using extractive on‑device analysis"
                            ]
                        )
                    }
                }

                // Step 4.4: Ensure multiple documents are represented before diversification
                let uniqueDocCount = Set(rerankedChunks.map { $0.chunk.documentId }).count
                if uniqueDocCount > 1 {
                    let desiredDocCoverage = min(
                        uniqueDocCount,
                        max(2, min(effectiveTopK, 3))
                    )
                    let maxCandidates = max(effectiveTopK * 2, filteredChunks.count)
                    let (augmented, addedDocs) = ensureDocumentCoverage(
                        candidates: filteredChunks,
                        fallbackPool: rerankedChunks,
                        desiredDocuments: desiredDocCoverage,
                        maxCandidates: maxCandidates
                    )
                    if filteredChunks.count != augmented.count || addedDocs > 0 {
                        if addedDocs > 0 {
                            Log.info(
                                "   🔁 Expanded context to cover \(addedDocs) additional document(s)",
                                category: .retrieval)
                            TelemetryCenter.emit(
                                .retrieval,
                                title: "Document coverage boost",
                                metadata: [
                                    "addedDocs": "\(addedDocs)",
                                    "targetDocs": "\(desiredDocCoverage)",
                                    "uniqueDocs": "\(uniqueDocCount)",
                                ]
                            )
                        } else {
                            Log.info(
                                "   🔁 Normalized candidate pool to \(augmented.count) chunks",
                                category: .retrieval)
                        }
                        filteredChunks = augmented
                    }
                } else if filteredChunks.isEmpty {
                    filteredChunks = Array(rerankedChunks.prefix(max(effectiveTopK, 3)))
                }

                // Step 4.5: Apply MMR for diversity (critical for medical/comprehensive coverage)
                Log.section("Step 4.5: MMR Diversification", level: .info, category: .pipeline)
                let mmrStartTime = Date()
                let diverseChunks = await engine.applyMMR(
                    candidates: filteredChunks,
                    queryEmbedding: queryEmbedding,
                    topK: effectiveTopK,  // Clamped for short queries
                    lambda: strictMode ? 0.75 : 0.7  // Strict mode favors relevance slightly more
                )
                let mmrTime = Date().timeIntervalSince(mmrStartTime)
                Log.info(
                    "✓ Selected \(diverseChunks.count) diverse chunks in \(String(format: "%.0f", mmrTime * 1000))ms",
                    category: .retrieval)
                Log.debug("  λ=0.7 (70% relevance, 30% diversity)", category: .retrieval)
                let contextWordCounts = diverseChunks.map { wordCount(of: $0.chunk.content) }
                let totalContextWords = contextWordCounts.reduce(0, +)
                let maxContextWords = contextWordCounts.max() ?? 0
                let averageContextWords =
                    contextWordCounts.isEmpty
                    ? 0.0
                    : Double(totalContextWords) / Double(contextWordCounts.count)
                TelemetryCenter.emit(
                    .retrieval,
                    title: "MMR diversification",
                    metadata: [
                        "selected": "\(diverseChunks.count)",
                        "lambda": "0.7",
                        "totalWords": "\(totalContextWords)",
                        "avgWords": String(format: "%.1f", averageContextWords),
                        "maxWords": "\(maxContextWords)",
                    ],
                    duration: mmrTime
                )

                if diverseChunks.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] MMR returned no candidates; falling back to direct chat",
                        category: .retrieval)
                    return try await generateDirectChatResponse(
                        question: question,
                        ragQuery: ragQuery,
                        inferenceConfig: inferenceConfig,
                        pipelineStartTime: pipelineStartTime,
                        retrievalTime: retrievalTime,
                        fallbackNote:
                            "No diverse candidates after MMR; replied without RAG context."
                    )
                }

                Log.verbose("\nFinal diverse chunks:", category: .retrieval)
                for (index, chunk) in diverseChunks.enumerated() {
                    let preview = chunk.chunk.content.prefix(80).replacingOccurrences(
                        of: "\n", with: " ")
                    let source =
                        chunk.sourceDocument.isEmpty
                        ? ""
                        : " | \(chunk.sourceDocument)\(chunk.pageNumber.map { " p.\($0)" } ?? "")"
                    Log.verbose(
                        "  [\(index + 1)] Similarity: \(String(format: "%.4f", chunk.similarityScore))\(source)",
                        category: .retrieval)
                    Log.verbose("      \"\(preview)...\"", category: .retrieval)
                }

                // Strict Mode enforcement: require sufficient high-confidence evidence
                if strictMode && !(lenient || acceptanceOverride || isTrivial) {
                    let supporting = diverseChunks.filter { $0.similarityScore >= 0.52 }
                    if supporting.count < 3 {
                        // Build cautious response with citations of top candidates
                        let topSources = diverseChunks.prefix(3).enumerated().map { idx, r in
                            let src = r.sourceDocument.isEmpty ? "Unknown" : r.sourceDocument
                            let page = r.pageNumber.map { " (p.\($0))" } ?? ""
                            return
                                "- [\(idx + 1)] \(src)\(page) — \(String(format: "%.0f%%", r.similarityScore * 100))"
                        }.joined(separator: "\n")
                        let caution = """
                            Strict Mode is enabled. Not enough high-confidence evidence (>= 52% similarity) across at least 3 chunks was found to answer reliably.

                            Top sources retrieved:
                            \(topSources)
                            """

                        let metadata = ResponseMetadata(
                            timeToFirstToken: nil,
                            totalGenerationTime: 0,
                            tokensGenerated: 0,
                            tokensPerSecond: nil,
                            modelUsed: llmService.modelName,
                            retrievalTime: retrievalTime,
                            strictModeEnabled: strictMode,
                            gatingDecision: "strict_blocked"
                        )

                        return RAGResponse(
                            queryId: ragQuery.id,
                            retrievedChunks: diverseChunks,
                            generatedResponse: caution,
                            metadata: metadata,
                            confidenceScore: 0.0,
                            qualityWarnings: ["Strict mode: insufficient supporting evidence"]
                        )
                    }
                }

                // Step 5: Construct context from diverse chunks (off-main)
                // Note: rawContext assembly is handled via engine.assembleContext with size limits

                // Smart context assembly: Use as many chunks as fit within the model's context window
                // Apple Intelligence: ~3500 chars for on-device/PCC (leaves room for prompt + response)
                // OpenAI Context Windows:
                //   - GPT-4o: 128K tokens (~512K chars)
                //   - GPT-5: 400K tokens (~1.6M chars) 🚀
                let maxContextChars: Int
                if llmService is OpenAILLMService {
                    // GPT-5 has 400K token context (~1.6M chars theoretical)
                    // Use 200K chars conservatively (leaves ~200K for prompt + response)
                    maxContextChars = 200000  // 200K chars = ~50K tokens
                } else if llmService is AppleFoundationLLMService {
                    // Tighter context for Apple FM to leave room for tool scaffolding and output
                    maxContextChars = 1500
                } else {
                    maxContextChars = 3500
                }

                let (context, actualChunksUsed) = await engine.assembleContext(
                    chunks: diverseChunks,
                    maxChars: maxContextChars
                )
                Log.info(
                    "   ✓ Using \(actualChunksUsed)/\(diverseChunks.count) chunks (\(context.count) chars)",
                    category: .pipeline)

                let contextSize = context.count
                let contextWords = context.split(separator: " ").count

                Log.section("Step 5: Context Assembly Complete", level: .info, category: .pipeline)
                Log.info(
                    "✓ Final context: \(contextSize) chars, \(contextWords) words from \(actualChunksUsed) chunks",
                    category: .pipeline)
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Context assembled",
                    metadata: [
                        "chunks": "\(actualChunksUsed)",
                        "chars": "\(contextSize)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ]
                )

                // If context is empty, fallback to direct chat to avoid downstream failures
                if actualChunksUsed == 0 || context.isEmpty {
                    Log.warning(
                        "⚠️  [RAGService] Empty context after assembly; falling back to direct chat",
                        category: .retrieval)
                    return try await generateDirectChatResponse(
                        question: question,
                        ragQuery: ragQuery,
                        inferenceConfig: inferenceConfig,
                        pipelineStartTime: pipelineStartTime,
                        retrievalTime: retrievalTime,
                        fallbackNote: "Empty assembled context; replied without RAG context."
                    )
                }

                // Step 6: Generate response using LLM with augmented context
                Log.section("Step 6: LLM Generation", level: .info, category: .pipeline)
                let generationStartTime = Date()

                // Token budgeting for Apple FM (conservative ~4K window)
                var genConfig = inferenceConfig
                if strictMode {
                    genConfig.temperature = min(genConfig.temperature, 0.2)
                }
                do {
                    let window = 4000
                    let safety = 400
                    let estPromptTokens = max(0, (question.count + context.count) / 4)
                    let available = max(128, window - safety - estPromptTokens)
                    if genConfig.maxTokens > available {
                        genConfig.maxTokens = available
                    }
                }

                // Attempt generation with retry on context-overflow
                var llmResponse: LLMResponse
                do {
                    llmResponse = try await generateWithFallback(
                        prompt: question,
                        context: context,
                        config: genConfig
                    )
                } catch {
                    let message = error.localizedDescription.lowercased()
                    if message.contains("context")
                        && (message.contains("exceed") || message.contains("exceeded"))
                    {
                        // Retry with halved context and smaller maxTokens
                        let reducedMax = max(512, genConfig.maxTokens / 2)
                        let (context2, _) = await engine.assembleContext(
                            chunks: diverseChunks,
                            maxChars: max(800, maxContextChars / 2)
                        )
                        var retryConfig = genConfig
                        retryConfig.maxTokens = reducedMax
                        TelemetryCenter.emit(
                            .system,
                            severity: .warning,
                            title: "Retry due to context overflow",
                            metadata: [
                                "initialTokens": "\(genConfig.maxTokens)",
                                "reducedTokens": "\(reducedMax)",
                            ]
                        )
                        llmResponse = try await generateWithFallback(
                            prompt: question,
                            context: context2,
                            config: retryConfig
                        )
                    } else {
                        throw error
                    }
                }

                let generationTime = Date().timeIntervalSince(generationStartTime)
                let responseText = llmResponse.text
                let responseWordCount = wordCount(of: responseText)
                TelemetryCenter.emit(
                    .generation,
                    title: "Response generated",
                    metadata: [
                        "model": llmService.modelName,
                        "tokens": "\(llmResponse.tokensGenerated)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                        "words": "\(responseWordCount)",
                        "characters": "\(responseText.count)",
                    ],
                    duration: generationTime
                )

                // Wrap all printing in error handling to prevent crashes
                do {
                    Log.info("✓ Response generated", category: .llm)
                    Log.info("  Model: \(llmService.modelName)", category: .llm)
                    Log.info(
                        "  Generation time: \(String(format: "%.2f", generationTime))s",
                        category: .performance)

                    // Access response text safely
                    Log.debug("  Response length: \(responseText.count) chars", category: .llm)
                    Log.debug("  Words: \(responseWordCount)", category: .llm)

                    if llmResponse.tokensGenerated > 0 {
                        Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
                        if let tps = llmResponse.tokensPerSecond {
                            Log.debug(
                                "  Speed: \(String(format: "%.1f", tps)) tokens/sec",
                                category: .performance)
                        }
                    }

                    // Verify we got a response
                    guard !responseText.isEmpty else {
                        Log.warning("⚠️  Warning: LLM returned empty response", category: .llm)
                        throw RAGServiceError.modelNotAvailable
                    }

                    // Step 7: Calculate confidence score and quality warnings
                    Log.section("Step 7: Quality Assessment", level: .info, category: .pipeline)
                    let totalDocsCount = await snapshotDocumentsCount()
                    let (confidenceScore, qualityWarnings) = await engine.assessResponseQuality(
                        chunks: diverseChunks,
                        query: question,
                        totalDocs: totalDocsCount
                    )

                    if !qualityWarnings.isEmpty {
                        Log.warning("⚠️  Quality Warnings:", category: .pipeline)
                        for warning in qualityWarnings {
                            Log.warning("   • \(warning)", category: .pipeline)
                        }
                    }

                    Log.info(
                        "📊 Confidence Score: \(String(format: "%.1f", confidenceScore * 100))%",
                        category: .pipeline)
                    TelemetryCenter.emit(
                        .system,
                        title: "Response evaluated",
                        metadata: [
                            "confidence": String(format: "%.2f", confidenceScore)
                        ]
                    )

                    // Step 8: Package results
                    let pipelineTotalTime = Date().timeIntervalSince(pipelineStartTime)

                    Log.box(
                        "ENHANCED PIPELINE COMPLETE ✓",
                        level: .info,
                        category: .pipeline,
                        content: [
                            "Total time: \(String(format: "%.2f", pipelineTotalTime))s",
                            "  - Query Expansion: \(String(format: "%.0f", expansionTime * 1000))ms",
                            "  - Embedding: \(String(format: "%.0f", embeddingTime * 1000))ms",
                            "  - Hybrid Retrieval: \(String(format: "%.0f", retrievalTime * 1000))ms",
                            "  - Re-ranking: \(String(format: "%.0f", rerankTime * 1000))ms",
                            "  - MMR Diversification: \(String(format: "%.0f", mmrTime * 1000))ms",
                            "  - Quality Assessment: <1ms",
                            "  - Generation: \(String(format: "%.2f", generationTime))s",
                        ]
                    )
                    TelemetryCenter.emit(
                        .system,
                        title: "Query complete",
                        metadata: [
                            "duration": String(format: "%.2f", pipelineTotalTime),
                            "chunks": "\(diverseChunks.count)",
                            "container": selectedName,
                            "containerId": selectedId.uuidString,
                        ],
                        duration: pipelineTotalTime
                    )

                    // Step 9: Create response metadata
                    let gatingSummary: String? =
                        acceptanceOverride
                        ? "acceptance_override" : ((lenient || isTrivial) ? "lenient" : nil)
                    let metadata = ResponseMetadata(
                        timeToFirstToken: llmResponse.timeToFirstToken,
                        totalGenerationTime: llmResponse.totalTime,
                        tokensGenerated: llmResponse.tokensGenerated,
                        tokensPerSecond: llmResponse.tokensPerSecond,
                        modelUsed: llmResponse.modelName ?? llmService.modelName,
                        retrievalTime: retrievalTime,
                        strictModeEnabled: strictMode,
                        gatingDecision: gatingSummary
                    )

                    let response = RAGResponse(
                        queryId: ragQuery.id,
                        retrievedChunks: diverseChunks,
                        generatedResponse: responseText,
                        metadata: metadata,
                        confidenceScore: confidenceScore,
                        qualityWarnings: qualityWarnings
                    )

                    let totalTime = Date().timeIntervalSince(pipelineStartTime)
                    Log.info(
                        "✅ Enhanced RAG pipeline complete in \(String(format: "%.2f", totalTime))s",
                        category: .pipeline)
                    await self.logQueryStats(query: question, response: response)

                    return response

                } catch {
                    print("❌ Error during response processing: \(error)")
                    // Still try to return something
                    let metadata = ResponseMetadata(
                        timeToFirstToken: nil,
                        totalGenerationTime: generationTime,
                        tokensGenerated: 0,
                        tokensPerSecond: nil,
                        modelUsed: llmService.modelName,
                        retrievalTime: retrievalTime,
                        strictModeEnabled: strictMode
                    )

                    return RAGResponse(
                        queryId: ragQuery.id,
                        retrievedChunks: diverseChunks,
                        generatedResponse: "Error processing response",
                        metadata: metadata,
                        confidenceScore: 0.0,
                        qualityWarnings: ["Error occurred during response processing"]
                    )
                }

            } else {
                // Direct LLM chat without documents
                Log.info("ℹ️  No documents loaded - using direct LLM chat mode", category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    title: "Direct chat mode",
                    metadata: [
                        "model": llmService.modelName,
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ]
                )

                Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)
                let generationStartTime = Date()

                let llmResponse = try await generateWithFallback(
                    prompt: question,
                    context: nil,  // No document context
                    config: inferenceConfig
                )

                let generationTime = Date().timeIntervalSince(generationStartTime)
                TelemetryCenter.emit(
                    .generation,
                    title: "Response generated",
                    metadata: [
                        "model": llmService.modelName,
                        "tokens": "\(llmResponse.tokensGenerated)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ],
                    duration: generationTime
                )

                Log.info("✓ Response generated", category: .llm)
                Log.info("  Model: \(llmService.modelName)", category: .llm)
                Log.info(
                    "  Generation time: \(String(format: "%.2f", generationTime))s",
                    category: .performance)
                Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
                Log.debug(
                    "  Speed: \(String(format: "%.1f", llmResponse.tokensPerSecond ?? 0)) tokens/sec",
                    category: .performance)

                let metadata = ResponseMetadata(
                    timeToFirstToken: llmResponse.timeToFirstToken,
                    totalGenerationTime: llmResponse.totalTime,
                    tokensGenerated: llmResponse.tokensGenerated,
                    tokensPerSecond: llmResponse.tokensPerSecond,
                    modelUsed: llmResponse.modelName ?? llmService.modelName,  // Use actual execution location if available
                    retrievalTime: 0,  // No retrieval in direct chat mode
                    strictModeEnabled: strictMode
                )

                let response = RAGResponse(
                    queryId: ragQuery.id,
                    retrievedChunks: [],  // No chunks in direct chat mode
                    generatedResponse: llmResponse.text,
                    metadata: metadata
                )

                let totalTime = Date().timeIntervalSince(pipelineStartTime)
                Log.info(
                    "✅ [RAGService] Direct chat complete in \(String(format: "%.2f", totalTime))s",
                    category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    title: "Query complete",
                    metadata: [
                        "duration": String(format: "%.2f", totalTime),
                        "mode": "direct",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ],
                    duration: totalTime
                )

                return response
            }

        } catch {
            // Set user-friendly error message
            await MainActor.run {
                // Make error messages more user-friendly
                if error.localizedDescription.contains("No embedding vectors were returned") {
                    lastError =
                        "Could not understand your query. Try using common words or longer phrases (e.g., 'What is the document about?')"
                } else {
                    lastError = error.localizedDescription
                }
            }

            print("❌ [RAGService] Query failed: \(error.localizedDescription)")
            TelemetryCenter.emit(
                .error,
                severity: .error,
                title: "Query failed",
                metadata: ["reason": error.localizedDescription]
            )
            throw error
        }
    }

    // MARK: - Direct Chat Fallback Helper

    /// Generate a direct LLM response without document context.
    /// Used as a graceful fallback when retrieval returns no results or documents are unavailable.
    private func generateDirectChatResponse(
        question: String,
        ragQuery: RAGQuery,
        inferenceConfig: InferenceConfig,
        pipelineStartTime: Date,
        retrievalTime: TimeInterval,
        fallbackNote: String? = nil
    ) async throws -> RAGResponse {
        Log.info("ℹ️  Falling back to direct LLM chat mode", category: .pipeline)
        let strictMode = await MainActor.run {
            self.containerService.activeContainer?.strictMode ?? false
        }
        TelemetryCenter.emit(
            .system,
            title: "Direct chat mode",
            metadata: ["model": llmService.modelName]
        )

        Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)
        let generationStartTime = Date()

        let llmResponse = try await generateWithFallback(
            prompt: question,
            context: nil,  // No document context
            config: inferenceConfig
        )

        let generationTime = Date().timeIntervalSince(generationStartTime)
        TelemetryCenter.emit(
            .generation,
            title: "Response generated",
            metadata: [
                "model": llmService.modelName,
                "tokens": "\(llmResponse.tokensGenerated)",
            ],
            duration: generationTime
        )

        Log.info("✓ Response generated", category: .llm)
        Log.info("  Model: \(llmService.modelName)", category: .llm)
        Log.info(
            "  Generation time: \(String(format: "%.2f", generationTime))s", category: .performance)
        Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
        Log.debug(
            "  Speed: \(String(format: "%.1f", llmResponse.tokensPerSecond ?? 0)) tokens/sec",
            category: .performance)

        let metadata = ResponseMetadata(
            timeToFirstToken: llmResponse.timeToFirstToken,
            totalGenerationTime: llmResponse.totalTime,
            tokensGenerated: llmResponse.tokensGenerated,
            tokensPerSecond: llmResponse.tokensPerSecond,
            modelUsed: llmService.modelName,
            retrievalTime: retrievalTime,
            strictModeEnabled: strictMode
        )

        var warnings: [String] = []
        if let note = fallbackNote { warnings.append(note) }

        let response = RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: [],
            generatedResponse: llmResponse.text,
            metadata: metadata,
            confidenceScore: 1.0,
            qualityWarnings: warnings
        )

        let totalTime = Date().timeIntervalSince(pipelineStartTime)
        Log.info(
            "✅ [RAGService] Direct chat complete in \(String(format: "%.2f", totalTime))s",
            category: .pipeline)
        TelemetryCenter.emit(
            .system,
            title: "Query complete",
            metadata: [
                "duration": String(format: "%.2f", totalTime),
                "mode": "direct",
            ],
            duration: totalTime
        )

        return response
    }

    // MARK: - Model Management

    /// Update LLM service with optional fallback chain
    /// - Parameters:
    ///   - primary: The primary LLM service to use
    ///   - fallbacks: Optional array of fallback services to try if primary fails
    @MainActor
    func updateLLMService(_ primary: LLMService, fallbacks: [LLMService] = []) {
        self._llmService = primary
        self._fallbackServices = fallbacks
        Log.info(
            "✓ Updated model: \(primary.modelName) with \(fallbacks.count) fallback(s)",
            category: .initialization)
    }

    /// Switch to a different LLM implementation
    /// Note: Use updateLLMService() for async/MainActor-safe switching
    func switchModel(to service: LLMService) async {
        await MainActor.run {
            self._llmService = service
            Log.info("✓ Switched to model: \(service.modelName)", category: .initialization)
        }
    }

    /// Check if the current LLM is available
    var isLLMAvailable: Bool {
        llmService.isAvailable
    }

    var currentModelName: String {
        llmService.modelName
    }

    // MARK: - Fallback-Aware Generation

    /// Try to generate with primary service, automatically falling back to configured fallbacks on failure
    private func generateWithFallback(
        prompt: String,
        context: String?,
        config: InferenceConfig
    ) async throws -> LLMResponse {
        // Try primary first
        do {
            let response = try await _llmService.generate(
                prompt: prompt,
                context: context,
                config: config
            )
            if LLMStreamingContext.handler != nil {
                LLMStreamingContext.emit(text: "", isFinal: true)
            }
            return response
        } catch {
            Log.warning(
                "Primary model \(_llmService.modelName) failed: \(error.localizedDescription)",
                category: .llm)

            // Try fallbacks in order
            for (index, fallbackService) in _fallbackServices.enumerated() {
                Log.info(
                    "Attempting fallback #\(index + 1): \(fallbackService.modelName)",
                    category: .llm)
                do {
                    let response = try await fallbackService.generate(
                        prompt: prompt,
                        context: context,
                        config: config
                    )
                    Log.info(
                        "✓ Fallback #\(index + 1) succeeded: \(fallbackService.modelName)",
                        category: .llm)
                    if LLMStreamingContext.handler != nil {
                        LLMStreamingContext.emit(text: "", isFinal: true)
                    }
                    return response
                } catch {
                    Log.warning(
                        "Fallback #\(index + 1) failed: \(error.localizedDescription)",
                        category: .llm)
                    continue
                }
            }

            // All fallbacks exhausted - rethrow original error
            throw error
        }
    }

    // MARK: - Private Helpers

    /// Returns a configured service for the given settings key, if available.
    private static func instantiateService(for modelKey: String) -> LLMService? {
        switch modelKey {
        case "openai":
            #if os(macOS)
                guard
                    let storedKey = UserDefaults.standard.string(forKey: "openaiAPIKey")?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !storedKey.isEmpty
                else {
                    Log.warning(
                        "OpenAI Direct selected but API key is missing", category: .initialization)
                    return nil
                }
                let model = UserDefaults.standard.string(forKey: "openaiModel") ?? "gpt-4o-mini"
                if model.hasPrefix("gpt-5") {
                    Log.info(
                        "✓ Using OpenAI Direct (Responses API): \(model)", category: .initialization
                    )
                    return OpenAIResponsesAPIService(apiKey: storedKey, model: model)
                } else {
                    Log.info(
                        "✓ Using OpenAI Direct (Chat Completions): \(model)",
                        category: .initialization)
                    return OpenAILLMService(apiKey: storedKey, model: model)
                }
            #else
                Log.info(
                    "OpenAI Direct disabled on iOS for Apple-native configuration",
                    category: .initialization)
                return nil
            #endif
        case "apple_intelligence":
            #if canImport(FoundationModels)
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    guard foundationService.isAvailable else {
                        Log.warning(
                            "Apple Foundation Models unavailable on this device",
                            category: .initialization)
                        return nil
                    }
                    foundationService.startWarmup()
                    Log.info(
                        "✓ Using Apple Foundation Models (on-device + PCC)",
                        category: .initialization)
                    Log.debug(
                        "🔥 Preloading model in background for instant first query",
                        category: .initialization)
                    return foundationService
                } else {
                    Log.warning(
                        "Apple Intelligence requires iOS 26.0 or later", category: .initialization)
                }
            #endif
            return nil
        case "chatgpt_extension":
            if #available(iOS 18.1, *) {
                let chatGPTService = AppleChatGPTExtensionService()
                if chatGPTService.isAvailable {
                    Log.info(
                        "✓ Using ChatGPT Extension (Apple Intelligence)", category: .initialization)
                    return chatGPTService
                } else {
                    Log.warning(
                        "ChatGPT Extension not available - check Settings > Apple Intelligence & Siri",
                        category: .initialization)
                }
            } else {
                Log.warning(
                    "ChatGPT Extension requires iOS 18.1 or later", category: .initialization)
            }
            return nil
        case "on_device_analysis":
            Log.info("✓ Using On-Device Analysis (extractive QA)", category: .initialization)
            return OnDeviceAnalysisService()
        case "mlx_local":
            #if os(macOS)
                let model = UserDefaults.standard.string(forKey: "mlxModel") ?? "local-mlx-model"
                let stream = UserDefaults.standard.bool(forKey: "mlxStream")
                if let base = UserDefaults.standard.string(forKey: "mlxBaseURL"),
                    let url = URL(string: base)
                {
                    Log.info(
                        "✓ Using MLX Local: \(base) [model=\(model), stream=\(stream)]",
                        category: .initialization)
                    return MLXPresetLLMService(baseURL: url, model: model, stream: stream)
                } else if let defaultURL = URL(string: "http://127.0.0.1:17860") {
                    Log.info(
                        "✓ Using MLX Local (default): \(defaultURL.absoluteString) [model=\(model), stream=\(stream)]",
                        category: .initialization)
                    return MLXPresetLLMService(baseURL: defaultURL, model: model, stream: stream)
                }
                return nil
            #else
                Log.warning(
                    "MLX Local presets are only available on macOS", category: .initialization)
                return nil
            #endif
        case "coreml_local":
            if let coreMLService = CoreMLLLMService.loadFromDefaults() {
                Log.info(
                    "✓ Using Core ML Local: \(coreMLService.modelName)", category: .initialization)
                return coreMLService
            } else {
                Log.warning(
                    "Core ML Local selected but no model configured", category: .initialization)
                return nil
            }
        case "llama_cpp_local":
            #if os(macOS)
                Log.info("✓ Using llama.cpp Local (defaults)", category: .initialization)
                return LlamaCPPPresetLLMService()
            #else
                Log.warning(
                    "llama.cpp local preset is only available on macOS", category: .initialization)
                return nil
            #endif
        case "ollama_local":
            #if os(macOS)
                Log.info("✓ Using Ollama Local (defaults)", category: .initialization)
                return OllamaPresetLLMService()
            #else
                Log.warning(
                    "Ollama local preset is only available on macOS", category: .initialization)
                return nil
            #endif
        case "gguf_local":
            #if os(iOS)
                guard LlamaCPPiOSLLMService.runtimeAvailable else {
                    Log.warning(
                        "GGUF runtime not bundled; unable to activate immediately",
                        category: .initialization)
                    return nil
                }
                if let service = LlamaCPPiOSLLMService.fromRegistry() {
                    Log.info("✓ Using GGUF Local: \(service.modelName)", category: .initialization)
                    return service
                }
                Log.warning(
                    "GGUF Local selected but no installed model was found",
                    category: .initialization)
                return nil
            #else
                Log.warning("GGUF Local preset is only supported on iOS", category: .initialization)
                return nil
            #endif
        default:
            Log.warning("Unknown model type: \(modelKey)", category: .initialization)
            return nil
        }
    }

    /// Builds an ordered list of fallback services, excluding the user's primary selection.
    private static func buildFallbackChain(excluding modelKey: String) -> [LLMService] {
        var fallbacks: [LLMService] = []
        #if canImport(FoundationModels)
            if modelKey != "apple_intelligence" {
                if #available(iOS 26.0, *) {
                    let foundationService = AppleFoundationLLMService()
                    if foundationService.isAvailable {
                        fallbacks.append(foundationService)
                    }
                }
            }
        #endif
        if modelKey != "on_device_analysis" {
            fallbacks.append(OnDeviceAnalysisService())
        }
        return fallbacks
    }

    #if os(iOS)
        /// Reactivates the previously selected GGUF model once the runtime and registry entry are ready.
        @MainActor
        private func activatePersistedGGUFModel(reason: String) {
            if _llmService is LlamaCPPiOSLLMService {
                Log.debug("GGUF service already active (\(reason))", category: .initialization)
                return
            }
            guard LlamaCPPiOSLLMService.runtimeAvailable else {
                Log.warning("GGUF runtime unavailable (\(reason))", category: .initialization)
                return
            }
            guard let service = LlamaCPPiOSLLMService.fromRegistry() else {
                Log.warning(
                    "GGUF selection persisted but no model found (\(reason))",
                    category: .initialization)
                return
            }
            service.toolHandler = self
            self._llmService = service
            self._llmService.toolHandler = self
            AutoTuneService.tuneForSelection(selectedModel: .ggufLocal)
            TelemetryCenter.emit(
                .system,
                title: "GGUF model activated",
                metadata: [
                    "reason": reason,
                    "model": service.modelName,
                ]
            )
            Log.info(
                "✓ Activated GGUF Local model (\(service.modelName))", category: .initialization)
        }
    #endif

    /// Log structured query statistics for debugging and telemetry dashboards
    @MainActor
    private func logQueryStats(query: String, response: RAGResponse) async {
        let queryWords = wordCount(of: query)
        let responseWords = wordCount(of: response.generatedResponse)
        let chunkWordCounts = response.retrievedChunks.map { wordCount(of: $0.chunk.content) }
        let chunkWordTotal = chunkWordCounts.reduce(0, +)
        let averageChunkWords =
            chunkWordCounts.isEmpty
            ? 0.0
            : Double(chunkWordTotal) / Double(chunkWordCounts.count)

        var statsContent: [String] = [
            "Query: \(String(query.prefix(50)))… (≈\(queryWords) words)",
            "Chunks: \(response.retrievedChunks.count) (≈\(Int(averageChunkWords.rounded())) words avg)",
            "Retrieval: \(String(format: "%.2f", response.metadata.retrievalTime))s",
            "Generation: \(String(format: "%.2f", response.metadata.totalGenerationTime))s",
            "Response words: \(responseWords)",
            "Model: \(response.metadata.modelUsed)",
        ]

        if let ttft = response.metadata.timeToFirstToken {
            statsContent.append("Time to first token: \(String(format: "%.2f", ttft))s")
        }
        if let tps = response.metadata.tokensPerSecond {
            statsContent.append("Tokens per second: \(String(format: "%.1f", tps))")
        }

        Log.info("📊 RAG Query Statistics", category: .pipeline)
        for line in statsContent {
            Log.info("  • \(line)", category: .pipeline)
        }

        TelemetryCenter.emit(
            .system,
            title: "Query stats",
            metadata: [
                "queryWords": "\(queryWords)",
                "responseWords": "\(responseWords)",
                "chunkWords": "\(chunkWordTotal)",
                "chunkCount": "\(response.retrievedChunks.count)",
                "retrievalTime": String(format: "%.2f", response.metadata.retrievalTime),
                "generationTime": String(format: "%.2f", response.metadata.totalGenerationTime),
                "model": response.metadata.modelUsed,
            ]
        )
    }

    nonisolated private func wordCount(of text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// Guarantee that at least a subset of the retrieved chunks span multiple documents when available.
    private func ensureDocumentCoverage(
        candidates: [RetrievedChunk],
        fallbackPool: [RetrievedChunk],
        desiredDocuments: Int,
        maxCandidates: Int
    ) -> (chunks: [RetrievedChunk], addedDocuments: Int) {
        let limit = max(1, maxCandidates)
        if desiredDocuments <= 1 {
            let baseline = candidates.isEmpty ? fallbackPool : candidates
            return (Array(baseline.prefix(limit)), 0)
        }

        var augmented = candidates
        if augmented.count > limit {
            augmented = Array(augmented.prefix(limit))
        }

        var seenDocuments = Set(augmented.map { $0.chunk.documentId })
        var addedDocs = 0

        for candidate in fallbackPool {
            if augmented.count >= limit { break }
            let docId = candidate.chunk.documentId
            if seenDocuments.contains(docId) { continue }
            augmented.append(candidate)
            seenDocuments.insert(docId)
            addedDocs += 1
            if seenDocuments.count >= desiredDocuments { break }
        }

        if augmented.isEmpty {
            let fallback = Array(fallbackPool.prefix(limit))
            let coveredDocs = Set(fallback.map { $0.chunk.documentId }).count
            return (fallback, min(desiredDocuments, coveredDocs))
        }

        return (augmented, addedDocs)
    }

    // MARK: - MainActor snapshot helpers (async to avoid superfluous await warnings)

    nonisolated
        private func snapshotDocuments() async -> [Document]
    {
        await MainActor.run { self.documents }
    }

    nonisolated
        private func snapshotDocumentsCount() async -> Int
    {
        await MainActor.run { self.documents.count }
    }

    nonisolated
        private func documentName(for documentId: UUID) async -> String
    {
        await MainActor.run { self.getDocumentName(for: documentId) }
    }

    /// Run an async operation under a temporary query-scoped container context.
    /// Sets currentQueryContainerId for the duration of the operation so agentic tools
    /// like listDocuments/searchDocuments are scoped deterministically in diagnostics.
    func withQueryContainerContext<T>(
        containerId: UUID?,
        warmup: Bool = true,
        _ operation: () async throws -> T
    ) async rethrows -> T {
        // Resolve selected container id (override or active)
        let selectedId: UUID = await MainActor.run {
            containerId ?? self.containerService.activeContainerId
        }
        // Establish context
        await MainActor.run { self.currentQueryContainerId = selectedId }
        // Optional warmup to ensure DB loaded (avoids first-touch latency)
        if warmup {
            let _ = try? await dbFor(selectedId).count()
        }
        // Ensure cleanup
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }
        // Execute caller's operation
        return try await operation()
    }

    // MARK: - Response Quality Assessment

    /// Calculate confidence score and identify quality warnings
    /// Critical for medical/high-stakes information retrieval
    /// - Parameters:
    ///   - chunks: Retrieved chunks for this response
    ///   - query: Original user query
    /// - Returns: Tuple of (confidence score 0-1, array of warnings)
    @MainActor
    private func assessResponseQuality(
        chunks: [RetrievedChunk],
        query: String
    ) -> (Float, [String]) {
        var warnings: [String] = []

        // Factor 1: Semantic similarity of top chunks
        let topSimilarity = chunks.first?.similarityScore ?? 0

        if topSimilarity < 0.4 {
            warnings.append(
                "Low relevance: Best match only \(String(format: "%.1f", topSimilarity * 100))% similar"
            )
        } else if topSimilarity < 0.6 {
            warnings.append("Moderate relevance: Consider rephrasing query for better results")
        }

        // Factor 2: Number of supporting chunks
        let chunkCount = chunks.count
        if chunkCount < 3 {
            warnings.append("Limited context: Only \(chunkCount) relevant chunks found")
        }

        // Factor 3: Source diversity (multiple documents = higher confidence)
        let uniqueSources = Set(chunks.map { $0.sourceDocument })
        let sourceCount = uniqueSources.count

        if sourceCount == 1 && documents.count > 1 {
            warnings.append("Single source: Information from only one document")
        }

        // Factor 4: Query quality
        let queryWords = query.split(separator: " ").count
        if queryWords <= 2 {
            warnings.append("Generic query: Try more specific questions for better accuracy")
        }

        // Calculate aggregate confidence (weighted average)
        let similarityWeight: Float = 0.5
        let chunkCountWeight: Float = 0.2
        let sourceDiversityWeight: Float = 0.2
        let queryQualityWeight: Float = 0.1

        let similarityScore = min(topSimilarity / 0.8, 1.0)  // Normalize: 0.8+ = full confidence
        let chunkScore = min(Float(chunkCount) / 5.0, 1.0)  // 5+ chunks = full confidence
        let diversityScore = min(Float(sourceCount) / Float(max(documents.count, 1)), 1.0)
        let queryScore = min(Float(queryWords) / 5.0, 1.0)  // 5+ words = full confidence

        let confidence =
            (similarityScore * similarityWeight + chunkScore * chunkCountWeight + diversityScore
                * sourceDiversityWeight + queryScore * queryQualityWeight)

        return (confidence, warnings)
    }

    // MARK: - MMR (Maximal Marginal Relevance) for Diversity

}

// MARK: - Device Capability Detection

extension RAGService {

    /// Comprehensive device capability detection for Apple Intelligence ecosystem
    @MainActor
    static func checkDeviceCapabilities() -> DeviceCapabilities {
        var capabilities = DeviceCapabilities()

        // Get iOS version
        let systemVersion = ProcessInfo.processInfo.operatingSystemVersion
        capabilities.iOSVersion =
            "\(systemVersion.majorVersion).\(systemVersion.minorVersion).\(systemVersion.patchVersion)"
        capabilities.iOSMajor = systemVersion.majorVersion
        capabilities.iOSMinor = systemVersion.minorVersion
        let hasAppleIntelligenceOS =
            (systemVersion.majorVersion > 18)
            || (systemVersion.majorVersion == 18 && systemVersion.minorVersion >= 1)

        // Detect device/chip tier based on available features
        // This is an approximation since we can't directly query chip model
        capabilities.deviceChip = detectDeviceChip()

        // Check Apple Intelligence availability (requires A17 Pro+/M-series + iOS 18.1+)
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                // iOS 26+ with Foundation Models
                #if targetEnvironment(simulator)
                    // Simulator: Foundation Models not available
                    capabilities.supportsFoundationModels = false
                    capabilities.foundationModelUnavailableReason =
                        "Foundation Models not available in Simulator"
                    capabilities.supportsAppleIntelligence = false
                    capabilities.appleIntelligenceUnavailableReason = "Not available in Simulator"
                    print("ℹ️  Running in Simulator - Foundation Models unavailable")
                #else
                    // Real device: Check Foundation Models availability
                    // SystemLanguageModel.default must be accessed synchronously on main thread
                    guard Thread.isMainThread else {
                        // Fallback: not on main thread
                        capabilities.supportsFoundationModels = false
                        capabilities.foundationModelUnavailableReason =
                            "Internal error: not called from main thread"
                        capabilities.supportsAppleIntelligence = false
                        capabilities.appleIntelligenceUnavailableReason =
                            "Internal error: not called from main thread"
                        print("❌ checkDeviceCapabilities() not called from main thread")

                        // Skip Foundation Models check, continue with rest
                        capabilities.supportsPrivateCloudCompute = false
                        capabilities.supportsWritingTools = false
                        capabilities.supportsImagePlayground = false

                        // Jump to post-Foundation Models setup
                        if hasAppleIntelligenceOS {
                            capabilities.supportsAppleIntelligence =
                                capabilities.deviceChip.supportsAppleIntelligence
                            capabilities.supportsPrivateCloudCompute = true
                            capabilities.supportsWritingTools = true
                            capabilities.supportsImagePlayground =
                                capabilities.deviceChip.supportsAppleIntelligence
                            if !capabilities.supportsAppleIntelligence {
                                capabilities.appleIntelligenceUnavailableReason =
                                    "Requires A17 Pro+ or M-series"
                            }
                        }

                        // Skip to embedding check
                        capabilities.supportsEmbeddings = true
                        capabilities.supportsCoreML = true
                        capabilities.supportsAppIntents = true
                        capabilities.supportsVision = true
                        capabilities.supportsVisionKit = true
                        capabilities.deviceTier = determineDeviceTier(
                            chip: capabilities.deviceChip,
                            hasAppleIntelligence: capabilities.supportsAppleIntelligence,
                            hasEmbeddings: capabilities.supportsEmbeddings
                        )
                        return capabilities
                    }

                    let systemModel = SystemLanguageModel.default

                    switch systemModel.availability {
                    case .available:
                        capabilities.supportsFoundationModels = true
                        capabilities.foundationModelUnavailableReason = nil
                        capabilities.supportsAppleIntelligence = true
                        capabilities.appleIntelligenceUnavailableReason = nil
                        print("✅ Foundation Models available on device")

                    case .unavailable(let reason):
                        capabilities.supportsFoundationModels = false
                        capabilities.supportsAppleIntelligence = false

                        switch reason {
                        case .deviceNotEligible:
                            let message = "Device not eligible (requires A17 Pro+ or M-series)"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            print("❌ Device not eligible for Foundation Models")

                        case .appleIntelligenceNotEnabled:
                            let message =
                                "Apple Intelligence not enabled - go to Settings > Apple Intelligence & Siri"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            print("⚠️  Apple Intelligence not enabled in Settings")
                            print("   💡 Go to Settings > Apple Intelligence & Siri to enable")

                        case .modelNotReady:
                            let message = "Model downloading or initializing - check iPhone Storage"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            print("⏳ Foundation Models not ready (downloading or initializing)")
                            print(
                                "   💡 Check Settings > General > iPhone Storage for download progress"
                            )

                        @unknown default:
                            let message = "Foundation Models unavailable (unknown reason)"
                            capabilities.foundationModelUnavailableReason = message
                            capabilities.appleIntelligenceUnavailableReason = message
                            print("❌ Foundation Models unavailable (unknown reason)")
                        }
                    }
                #endif

                // iOS 26 includes all iOS 18.1+ features
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
            } else if hasAppleIntelligenceOS {
                // iOS 18.1+ has Apple Intelligence (PCC, Writing Tools, ChatGPT)
                // but no Foundation Models yet
                capabilities.supportsAppleIntelligence =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.foundationModelUnavailableReason = "Requires iOS 26"
                if !capabilities.supportsAppleIntelligence {
                    capabilities.appleIntelligenceUnavailableReason =
                        "Requires A17 Pro+ or M-series"
                }
            } else {
                capabilities.foundationModelUnavailableReason = "Requires iOS 26"
                capabilities.appleIntelligenceUnavailableReason = "Requires iOS 18.1+"
            }
        #else
            if hasAppleIntelligenceOS {
                capabilities.supportsAppleIntelligence =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.supportsPrivateCloudCompute = true
                capabilities.supportsWritingTools = true
                capabilities.supportsImagePlayground =
                    capabilities.deviceChip.supportsAppleIntelligence
                capabilities.foundationModelUnavailableReason = "Build with iOS 26 SDK to enable"
                if !capabilities.supportsAppleIntelligence {
                    capabilities.appleIntelligenceUnavailableReason =
                        "Requires A17 Pro+ or M-series"
                }
            } else {
                capabilities.foundationModelUnavailableReason = "Build with iOS 26 SDK to enable"
                capabilities.appleIntelligenceUnavailableReason = "Requires iOS 18.1+"
            }
        #endif

        // Check NaturalLanguage embedding support
        // NLEmbedding is available on iOS 13+, so we can assume it's available
        // Rather than risk crashing by initializing the model here
        capabilities.supportsEmbeddings = true

        // Core ML is always available
        capabilities.supportsCoreML = true

        // App Intents (Siri) available on all iOS versions
        capabilities.supportsAppIntents = true

        // Vision framework available on all devices
        capabilities.supportsVision = true

        // VisionKit (document scanning) available on all devices
        capabilities.supportsVisionKit = true

        // Determine device tier
        capabilities.deviceTier = determineDeviceTier(
            chip: capabilities.deviceChip,
            hasAppleIntelligence: capabilities.supportsAppleIntelligence,
            hasEmbeddings: capabilities.supportsEmbeddings
        )

        // Note: canRunRAG is a computed property based on supportsEmbeddings

        return capabilities
    }

    /// Detect device chip based on available features
    private static func detectDeviceChip() -> DeviceChip {
        // Check for Neural Engine and performance characteristics
        // This is an approximation - we can't directly query the chip model in iOS

        // Simulator gets conservative capabilities to avoid crashes
        #if targetEnvironment(simulator)
            return .a14Bionic  // Don't claim Apple Intelligence support in simulator
        #else

            var systemInfo = utsname()
            guard uname(&systemInfo) == 0 else {
                // If uname fails, return conservative fallback
                return .a14Bionic
            }

            let modelCode = withUnsafeBytes(of: &systemInfo.machine) { bytes -> String? in
                guard let cString = bytes.baseAddress?.assumingMemoryBound(to: CChar.self) else {
                    return nil
                }
                return String(cString: cString)
            }

            let identifier = modelCode ?? "unknown"

            // iPhone identifiers
            if identifier.hasPrefix("iPhone") {
                let components = identifier.split(separator: ",")
                let family = components.first.map(String.init) ?? "iPhone"
                let variant = components.count > 1 ? String(components[1]) : ""
                switch family {
                case "iPhone17":
                    // iPhone 16 line (2024) – Pro models run A18 Pro, non-Pro run A18
                    if ["1", "2"].contains(variant) {
                        return .a18Pro
                    } else {
                        return .a18
                    }
                case "iPhone16":
                    // iPhone 15 line (2023) – Pro models run A17 Pro, non-Pro run A16
                    if ["1", "2"].contains(variant) {
                        return .a17Pro
                    } else {
                        return .a16Bionic
                    }
                case "iPhone15":
                    // iPhone 14 line (2022) – Pro models run A16, standard models run A15
                    if ["2", "3"].contains(variant) {
                        return .a16Bionic
                    } else {
                        return .a15Bionic
                    }
                case "iPhone14":
                    return .a15Bionic
                case "iPhone13":
                    return .a14Bionic
                case "iPhone12":
                    return .a13Bionic
                default:
                    return .older
                }
            }

            // iPad identifiers
            if identifier.hasPrefix("iPad") {
                if identifier.contains("iPad16") || identifier.contains("iPad17") {
                    return .mSeries
                } else if identifier.contains("iPad15") {
                    return .a17Pro
                } else if identifier.contains("iPad14") || identifier.contains("iPad13") {
                    return .a16Bionic
                } else {
                    return .a14Bionic
                }
            }

            // Mac identifiers (Mac Catalyst)
            if identifier.contains("Mac") || identifier.contains("x86")
                || identifier.contains("arm64")
            {
                return .mSeries
            }

            // Conservative fallback for devices we don't recognize
            return .a14Bionic
        #endif
    }

    /// Determine device performance tier
    private static func determineDeviceTier(
        chip: DeviceChip, hasAppleIntelligence: Bool, hasEmbeddings: Bool
    ) -> DeviceCapabilities.DeviceTier {
        if hasAppleIntelligence && chip.supportsAppleIntelligence {
            return .high  // A17 Pro+ or M-series with full Apple Intelligence
        } else if hasEmbeddings {
            return .medium  // A13+ with embedding support
        } else {
            return .low  // Older devices
        }
    }
}

// MARK: - Device Chip Detection

enum DeviceChip: String {
    case mSeries = "Apple Silicon (M1+)"
    case a18Pro = "A18 Pro"
    case a18 = "A18"
    case a17Pro = "A17 Pro"
    case a17 = "A17"
    case a16Bionic = "A16 Bionic"
    case a15Bionic = "A15 Bionic"
    case a14Bionic = "A14 Bionic"
    case a13Bionic = "A13 Bionic"
    case older = "A12 or Older"

    var supportsAppleIntelligence: Bool {
        switch self {
        case .mSeries, .a18Pro, .a18, .a17Pro:
            return true
        default:
            return false
        }
    }

    var supportsNeuralEngine: Bool {
        // A11+ has Neural Engine
        return self != .older
    }

    var performanceRating: String {
        switch self {
        case .mSeries:
            return "Exceptional"
        case .a18Pro:
            return "Elite"
        case .a18:
            return "Very Good"
        case .a17Pro:
            return "Excellent"
        case .a17:
            return "Very Good"
        case .a16Bionic:
            return "Very Good"
        case .a15Bionic, .a14Bionic:
            return "Good"
        case .a13Bionic:
            return "Moderate"
        case .older:
            return "Limited"
        }
    }

    var neuralEnginePerformance: String {
        switch self {
        case .mSeries:
            return "16-core, 15.8 TOPS"
        case .a18Pro:
            return "16-core, 45 TOPS"
        case .a18:
            return "16-core, 20 TOPS"
        case .a17Pro:
            return "16-core, 35 TOPS"
        case .a17:
            return "16-core, 18 TOPS"
        case .a16Bionic:
            return "16-core, 17 TOPS"
        case .a15Bionic:
            return "16-core, 15.8 TOPS"
        case .a14Bionic:
            return "16-core, 11 TOPS"
        case .a13Bionic:
            return "8-core, 6 TOPS"
        case .older:
            return "Not available"
        }
    }
}

// MARK: - Device Capabilities Structure

struct DeviceCapabilities {
    // Device Information
    var deviceChip: DeviceChip = .a14Bionic
    var iOSVersion: String = "Unknown"
    var iOSMajor: Int = 0
    var iOSMinor: Int = 0

    // Apple Intelligence Features (iOS 18.1+)
    var supportsAppleIntelligence = false
    var supportsPrivateCloudCompute = false
    var supportsWritingTools = false
    var supportsImagePlayground = false
    var appleIntelligenceUnavailableReason: String? = nil

    // Foundation Models (iOS 26.0+)
    var supportsFoundationModels = false
    var foundationModelUnavailableReason: String? = nil

    // Core AI Frameworks
    var supportsEmbeddings = false
    var supportsCoreML = false
    var supportsAppIntents = false
    var supportsVision = false
    var supportsVisionKit = false

    // Hardware Features
    var hasNeuralEngine: Bool {
        return deviceChip.supportsNeuralEngine
    }

    // Computed Properties
    var deviceTier: DeviceTier = .low

    /// Estimated maximum context tokens Apple Intelligence can allocate on this hardware
    /// - Returns ≈50K tokens once Foundation Models are active (PCC available)
    /// - Returns ≈900 tokens for on-device-only execution while models download
    var appleIntelligenceContextTokens: Int {
        if supportsFoundationModels {
            return 50_000  // ≈200K characters before prompt+response overhead
        } else if supportsAppleIntelligence {
            return 900  // ≈3.5K characters processed purely on-device
        } else {
            return 0
        }
    }

    /// Human-readable summary of the Apple Intelligence context behaviour for this device
    var appleIntelligenceContextDescription: String? {
        if supportsFoundationModels {
            return
                "≈3.5K characters on-device, automatically expanding to ≈200K characters (~50K tokens) via Private Cloud Compute when queries demand it."
        } else if supportsAppleIntelligence {
            return
                "≈3.5K characters (~900 tokens) handled fully on-device while Foundation Models finish downloading."
        } else {
            return nil
        }
    }

    var canRunRAG: Bool { supportsEmbeddings }

    var canRunAdvancedAI: Bool { supportsAppleIntelligence || supportsFoundationModels }

    var appleIntelligenceStatus: String {
        if supportsFoundationModels {
            return "Foundation Models Available"
        } else if supportsAppleIntelligence {
            return "Apple Intelligence Available"
        } else if let reason = appleIntelligenceUnavailableReason {
            return reason
        } else if iOSMajor >= 18 {
            return "Requires A17 Pro+ or M-series"
        } else {
            return "Requires iOS 18.1+"
        }
    }

    enum DeviceTier {
        case low  // Pre-A13, minimal AI support
        case medium  // A13-A16, embeddings + Core ML
        case high  // A17 Pro+ or M-series, full Apple Intelligence

        var description: String {
            switch self {
            case .high:
                return "Premium (Full AI Capabilities)"
            case .medium:
                return "Standard (Good AI Support)"
            case .low:
                return "Basic (Limited AI Support)"
            }
        }

        var color: String {
            switch self {
            case .high:
                return "green"
            case .medium:
                return "blue"
            case .low:
                return "orange"
            }
        }
    }
}

// MARK: - Errors

enum RAGServiceError: LocalizedError {
    case emptyQuery
    case noDocumentsAvailable
    case retrievalFailed
    case modelNotAvailable
    case noRelevantContext

    var errorDescription: String? {
        switch self {
        case .emptyQuery:
            return "Query cannot be empty"
        case .noDocumentsAvailable:
            return "No documents have been added to the knowledge base"
        case .noRelevantContext:
            return "No relevant information found in documents. Try rephrasing your query."
        case .retrievalFailed:
            return "Failed to retrieve relevant chunks"
        case .modelNotAvailable:
            return "The selected LLM model is not available"
        }
    }
}

// MARK: - RAGService Tool Handler Implementation
// This enables agentic RAG where the LLM can decide when to search documents

extension RAGService: RAGToolHandler {

    /// Search documents for relevant information
    /// Called by the LLM when it needs information from the document library
    func searchDocuments(query: String) async throws -> String {
        print("🔧 [Tool Call] search_documents(query: \"\(query)\")")

        // Use the existing RAG pipeline to search
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

        let selectedId = await MainActor.run {
            self.currentQueryContainerId ?? self.containerService.activeContainerId
        }
        let db = await dbFor(selectedId)

        let retrievedChunks = try await db.search(
            embedding: queryEmbedding,
            topK: 3  // Return top 3 chunks for tool call
        )

        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Format retrieved chunks for LLM consumption
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"

        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview  // Truncated preview to control token usage
            result += "\n\n"
        }

        print("✅ [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// Agentic search with optional topK and minSimilarity (called by Function Calling)
    func searchDocuments(query: String, topK: Int?, minSimilarity: Float?) async throws -> String {
        print(
            "🔧 [Tool Call] search_documents(query: \"\(query)\", topK: \(topK?.description ?? "nil"), minSimilarity: \(minSimilarity?.description ?? "nil"))"
        )

        // Step 1: Embed the query
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

        // Step 2: Vector search with optional k
        let k = max(1, topK ?? 3)
        let selectedId = await MainActor.run {
            self.currentQueryContainerId ?? self.containerService.activeContainerId
        }
        let db = await dbFor(selectedId)
        var retrievedChunks = try await db.search(
            embedding: queryEmbedding,
            topK: k
        )

        // Step 3: Optional similarity filtering
        if let minSim = minSimilarity {
            let engine = RAGEngine()
            retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: minSim)
        }

        // Edge case: No results
        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Step 4: Format retrieved chunks for LLM consumption (citations + preview)
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"
        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview
            result += "\n\n"
        }

        print("✅ [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// List all available documents
    /// Called by the LLM when user asks what documents are available
    func listDocuments() async throws -> String {
        print("🔧 [Tool Call] list_documents()")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        if scopedDocs.isEmpty {
            return "No documents available in the selected library."
        }

        var result = "Available documents (\(scopedDocs.count)):\n\n"

        for (index, doc) in scopedDocs.enumerated() {
            result += "\(index + 1). \(doc.filename)\n"
            if let pages = doc.processingMetadata?.pagesProcessed {
                result += "   - Pages: \(pages)\n"
            }
            result += "   - Chunks: \(doc.totalChunks)\n"
            result += "   - Added: \(formatDate(doc.addedAt))\n"
            result += "\n"
        }

        print("✅ [Tool Call] Listed \(scopedDocs.count) documents (scoped)")
        return result
    }

    /// Get summary of a specific document
    /// Called by the LLM when user asks about a specific document
    func getDocumentSummary(documentName: String) async throws -> String {
        print("🔧 [Tool Call] get_document_summary(documentName: \"\(documentName)\")")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { d in
            if let cid = d.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        guard
            let doc = scopedDocs.first(where: {
                $0.filename.lowercased().contains(documentName.lowercased())
            })
        else {
            return "Document not found in selected library: \(documentName)"
        }

        var result = "Document: \(doc.filename)\n"
        if let pages = doc.processingMetadata?.pagesProcessed {
            result += "- Pages: \(pages)\n"
        }
        result += "- Chunks: \(doc.totalChunks)\n"
        result += "- Added: \(formatDate(doc.addedAt))\n"
        result += "- File Type: \(doc.contentType.rawValue)"

        print("✅ [Tool Call] Returned summary for \(doc.filename) (scoped)")
        return result
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
