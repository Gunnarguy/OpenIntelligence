//  KnowledgeContainer.swift
//  OpenIntelligence
//
//  Defines a per-topic/library container for documents and vectors.
//  Each container can choose its own embedding provider/dimension and vector DB backend.
//  Containers provide per-library tuning for chunking, retrieval, and embedding strategies.
//

import Foundation

enum VectorDBKind: String, Codable, CaseIterable, Sendable {
    case persistentJSON // Built-in JSON persistence (baseline)
    case vecturaHNSW // Optional VecturaKit ANN index (if available)
    case inMemory // Volatile (for testing)
}

struct KnowledgeContainer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var createdAt: Date
    var description: String?

    // Retrieval/Embedding configuration
    var embeddingProviderId: String // e.g. "nl_embedding", "nl_contextual_embedding"
    var embeddingDim: Int // Native Apple dimension is 512
    var vectorDBKind: VectorDBKind
    var autoAdaptDimension: Bool // Auto-orchestrate chunking/embedding when enabled
    var chunkingDirective: ChunkingDirective?
    var lastSelfTuneAt: Date?

    // Retrieval tuning - controls how search results are ranked and filtered
    var retrievalConfig: RetrievalConfig

    // DEPRECATED: strictMode removed - use retrievalConfig.minSimilarity instead
    // Migration: strictMode=true → minSimilarity=0.52, strictMode=false → minSimilarity=0.35

    // Stats for quick UI rendering
    var totalDocuments: Int
    var totalChunks: Int
    var dbSizeBytes: Int64
    var lastIndexedAt: Date?

    // MARK: - Coding Keys for Migration

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, colorHex, createdAt, description
        case embeddingProviderId, embeddingDim, vectorDBKind
        case autoAdaptDimension, chunkingDirective, lastSelfTuneAt
        case retrievalConfig
        case totalDocuments, totalChunks, dbSizeBytes, lastIndexedAt
        // Legacy key for migration
        case strictMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(String.self, forKey: .icon)
        colorHex = try container.decode(String.self, forKey: .colorHex)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        embeddingProviderId = try container.decode(String.self, forKey: .embeddingProviderId)
        embeddingDim = try container.decode(Int.self, forKey: .embeddingDim)
        vectorDBKind = try container.decode(VectorDBKind.self, forKey: .vectorDBKind)
        autoAdaptDimension = try container.decodeIfPresent(Bool.self, forKey: .autoAdaptDimension) ?? false
        chunkingDirective = try container.decodeIfPresent(ChunkingDirective.self, forKey: .chunkingDirective)
        lastSelfTuneAt = try container.decodeIfPresent(Date.self, forKey: .lastSelfTuneAt)
        totalDocuments = try container.decodeIfPresent(Int.self, forKey: .totalDocuments) ?? 0
        totalChunks = try container.decodeIfPresent(Int.self, forKey: .totalChunks) ?? 0
        dbSizeBytes = try container.decodeIfPresent(Int64.self, forKey: .dbSizeBytes) ?? 0
        lastIndexedAt = try container.decodeIfPresent(Date.self, forKey: .lastIndexedAt)

        // Migration: convert legacy strictMode to retrievalConfig
        if let config = try container.decodeIfPresent(RetrievalConfig.self, forKey: .retrievalConfig) {
            retrievalConfig = config
        } else if let strictMode = try container.decodeIfPresent(Bool.self, forKey: .strictMode) {
            // Migrate from strictMode
            retrievalConfig = RetrievalConfig.migrated(fromStrictMode: strictMode)
        } else {
            retrievalConfig = .default
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(icon, forKey: .icon)
        try container.encode(colorHex, forKey: .colorHex)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(embeddingProviderId, forKey: .embeddingProviderId)
        try container.encode(embeddingDim, forKey: .embeddingDim)
        try container.encode(vectorDBKind, forKey: .vectorDBKind)
        try container.encode(autoAdaptDimension, forKey: .autoAdaptDimension)
        try container.encodeIfPresent(chunkingDirective, forKey: .chunkingDirective)
        try container.encodeIfPresent(lastSelfTuneAt, forKey: .lastSelfTuneAt)
        try container.encode(retrievalConfig, forKey: .retrievalConfig)
        try container.encode(totalDocuments, forKey: .totalDocuments)
        try container.encode(totalChunks, forKey: .totalChunks)
        try container.encode(dbSizeBytes, forKey: .dbSizeBytes)
        try container.encodeIfPresent(lastIndexedAt, forKey: .lastIndexedAt)
    }

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#4F46E5",
        createdAt: Date = Date(),
        description: String? = nil,
        embeddingProviderId: String = "coreml_sentence_embedding", // Silver bullet: CoreML 384-dim
            embeddingDim: Int = 384, // Matches actual CoreMLSentenceEmbeddingProvider output
        vectorDBKind: VectorDBKind = .persistentJSON,
        autoAdaptDimension: Bool = false,
        chunkingDirective: ChunkingDirective? = nil,
        lastSelfTuneAt: Date? = nil,
        retrievalConfig: RetrievalConfig = .default,
        totalDocuments: Int = 0,
        totalChunks: Int = 0,
        dbSizeBytes: Int64 = 0,
        lastIndexedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.description = description
        self.embeddingProviderId = embeddingProviderId
        self.embeddingDim = embeddingDim
        self.vectorDBKind = vectorDBKind
        self.autoAdaptDimension = autoAdaptDimension
        self.chunkingDirective = chunkingDirective
        self.lastSelfTuneAt = lastSelfTuneAt
        self.retrievalConfig = retrievalConfig
        self.totalDocuments = totalDocuments
        self.totalChunks = totalChunks
        self.dbSizeBytes = dbSizeBytes
        self.lastIndexedAt = lastIndexedAt
    }

    // MARK: - Factory Methods

    /// Create a high-accuracy container using NLContextualEmbedding (iOS 17+)
    /// Uses BERT-like contextual embeddings for 15-25% better semantic accuracy
    /// Best for: research, medical, legal, or any high-stakes documents
    static func highAccuracy(
        name: String,
        icon: String = "sparkles",
        colorHex: String = "#10B981",
        description: String? = nil
    ) -> KnowledgeContainer {
        KnowledgeContainer(
            name: name,
            icon: icon,
            colorHex: colorHex,
            description: description ?? "High-accuracy container with contextual embeddings",
            embeddingProviderId: "nl_contextual_embedding",
            embeddingDim: 512, // NLContextualEmbedding outputs 512-dim
            vectorDBKind: .persistentJSON,
            autoAdaptDimension: true,
            retrievalConfig: .highAccuracy
        )
    }
}

// MARK: - Retrieval Configuration

/// Controls how search results are ranked, filtered, and fused.
/// This replaces the old strictMode boolean with granular tuning controls.
struct RetrievalConfig: Codable, Equatable, Sendable {
    /// Minimum cosine similarity required for a chunk to be considered relevant (0.0-1.0)
    /// Higher values = stricter filtering, fewer but more relevant results
    var minSimilarity: Float

    /// Weight given to vector (semantic) similarity in hybrid search (0.0-1.0)
    /// Higher = rely more on embeddings, lower = rely more on keywords
    var vectorWeight: Float

    /// Weight given to BM25 (keyword) matching in hybrid search (0.0-1.0)
    /// Should typically sum with vectorWeight to ~1.0
    var lexicalWeight: Float

    /// MMR (Maximal Marginal Relevance) lambda parameter (0.0-1.0)
    /// Higher = favor relevance, lower = favor diversity in results
    var mmrLambda: Float

    /// Minimum number of confident chunks required before generating a response
    /// If fewer chunks pass minSimilarity, the system may decline to answer
    var minConfidentChunks: Int

    /// Whether to apply stricter citation requirements
    /// When true, responses must cite sources more explicitly
    var requireExplicitCitations: Bool

    // MARK: - Presets

    /// Default balanced configuration for general use
    static let `default` = RetrievalConfig(
        minSimilarity: 0.28, // Lowered from 0.35 to avoid over-filtering technical terms
        vectorWeight: 0.4, // Slightly favor BM25 for keyword-heavy queries
        lexicalWeight: 0.6,
        mmrLambda: 0.6,
        minConfidentChunks: 1,
        requireExplicitCitations: false
    )

    /// High-accuracy preset for research, medical, legal content
    static let highAccuracy = RetrievalConfig(
        minSimilarity: 0.50,
        vectorWeight: 0.75,
        lexicalWeight: 0.25,
        mmrLambda: 0.8,
        minConfidentChunks: 2,
        requireExplicitCitations: true
    )

    /// Permissive preset for creative/exploratory queries
    static let exploratory = RetrievalConfig(
        minSimilarity: 0.25,
        vectorWeight: 0.6,
        lexicalWeight: 0.4,
        mmrLambda: 0.5,
        minConfidentChunks: 1,
        requireExplicitCitations: false
    )

    /// Optimized for technical manuals, specifications, and reference documents.
    /// Heavy keyword weighting to find exact terms (e.g., "oil", "engine", "5W-30").
    static let technicalManual = RetrievalConfig(
        minSimilarity: 0.22, // Very low threshold for domain-specific vocabulary
        vectorWeight: 0.3, // Strongly favor keyword (BM25) matching
        lexicalWeight: 0.7,
        mmrLambda: 0.5, // Favor diversity for multi-part answers
        minConfidentChunks: 1,
        requireExplicitCitations: false
    )

    /// Migration helper: convert legacy strictMode to RetrievalConfig
    static func migrated(fromStrictMode strictMode: Bool) -> RetrievalConfig {
        if strictMode {
            return RetrievalConfig(
                minSimilarity: 0.52,
                vectorWeight: 0.7,
                lexicalWeight: 0.3,
                mmrLambda: 0.75,
                minConfidentChunks: 3,
                requireExplicitCitations: true
            )
        } else {
            return .default
        }
    }

    // MARK: - Comparison Helpers

    /// Checks if this config is approximately equal to another preset (within tolerance).
    /// Useful for detecting which preset the user is currently using.
    func isCloseTo(_ other: RetrievalConfig, tolerance: Float = 0.08) -> Bool {
        abs(minSimilarity - other.minSimilarity) <= tolerance &&
            abs(vectorWeight - other.vectorWeight) <= tolerance &&
            abs(mmrLambda - other.mmrLambda) <= tolerance
    }

    /// Human-readable summary of the current configuration
    var summary: String {
        if isCloseTo(.default) { return "Balanced" }
        if isCloseTo(.highAccuracy) { return "High Precision" }
        if isCloseTo(.technicalManual) { return "Technical Manual" }
        if isCloseTo(.exploratory) { return "Exploratory" }
        return "Custom"
    }

    // MARK: - Content-Aware Config Recommendation

    /// Recommends optimal RetrievalConfig based on document types in the container.
    /// Call this after ingestion to auto-tune retrieval settings.
    static func recommended(forDocumentTypes types: [DocumentType]) -> RetrievalConfig {
        guard !types.isEmpty else { return .default }

        // Count document categories
        var technicalCount = 0
        var codeCount = 0
        var narrativeCount = 0

        for type in types {
            switch type {
            case .pdf:
                // PDFs are often technical manuals, specs, or reports
                technicalCount += 1

            case .swift, .python, .javascript, .typescript, .java,
                 .cpp, .c, .objc, .go, .rust, .ruby, .php, .html,
                 .css, .json, .xml, .yaml, .sql, .shell, .code:
                // Code files benefit from exact keyword matching
                codeCount += 1

            case .markdown, .text, .rtf:
                // Could be narrative or technical, count as balanced
                narrativeCount += 1

            case .word, .excel, .powerpoint, .pages, .numbers, .keynote:
                // Office docs are often reports/presentations
                narrativeCount += 1

            case .image, .png, .jpeg, .heic, .tiff, .gif:
                // OCR'd images - treat as potentially technical
                technicalCount += 1

            case .csv:
                // CSV data files benefit from exact keyword matching
                technicalCount += 1

            case .audio, .video, .m4a, .mp3, .wav, .mp4, .mov:
                // Transcribed audio/video - treat as narrative
                narrativeCount += 1

            case .unknown:
                narrativeCount += 1
            }
        }

        let total = types.count

        // Determine dominant category
        if codeCount > total / 2 {
            // Majority code: use technical manual preset (heavy keyword matching)
            Log.debug(
                "[RetrievalConfig] Auto-recommended: technicalManual (code-heavy corpus: \(codeCount)/\(total))",
                category: .retrieval
            )
            return .technicalManual
        } else if technicalCount > total / 2 {
            // Majority technical: use technical manual preset
            Log.debug(
                "[RetrievalConfig] Auto-recommended: technicalManual (technical corpus: \(technicalCount)/\(total))",
                category: .retrieval
            )
            return .technicalManual
        } else if narrativeCount > total * 2 / 3 {
            // Mostly narrative: use default balanced
            Log.debug(
                "[RetrievalConfig] Auto-recommended: default (narrative corpus: \(narrativeCount)/\(total))",
                category: .retrieval
            )
            return .default
        }

        // Mixed content: use default
        Log.debug(
            "[RetrievalConfig] Auto-recommended: default (mixed corpus)",
            category: .retrieval
        )
        return .default
    }
}

struct ChunkingDirective: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case baseline
        case auto
        case manual
    }

    let source: Source
    let strategy: String
    let targetWordWindow: Int
    let overlapWords: Int
    let rationale: [String]
    let updatedAt: Date

    init(
        source: Source,
        strategy: String,
        targetWordWindow: Int,
        overlapWords: Int,
        rationale: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.source = source
        self.strategy = strategy
        self.targetWordWindow = targetWordWindow
        self.overlapWords = overlapWords
        self.rationale = rationale
        self.updatedAt = updatedAt
    }
}

// MARK: - App Support Paths

enum AppSupportPaths {
    static func baseDir() -> URL {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("OpenIntelligence", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func containersListURL() -> URL {
        baseDir().appendingPathComponent("containers.json")
    }

    static func documentsListURL(containerId: UUID) -> URL {
        baseDir().appendingPathComponent("documents_\(containerId.uuidString).json")
    }

    static func vectorsFileURL(containerId: UUID) -> URL {
        // Persistent JSON vector DB file per container
        baseDir().appendingPathComponent("vector_database_\(containerId.uuidString).json")
    }

    static func chatHistoryURL(containerId: UUID) -> URL {
        baseDir().appendingPathComponent("chat_history_\(containerId.uuidString).json")
    }
}
