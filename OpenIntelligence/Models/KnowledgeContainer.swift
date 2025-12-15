//  KnowledgeContainer.swift
//  OpenIntelligence
//
//  Defines a per-topic/library container for documents and vectors.
//  Each container can choose its own embedding provider/dimension and vector DB backend.
//  Containers enable strict scoping for high-accuracy use cases (e.g., medical topics).
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
    var embeddingProviderId: String // e.g. "nl_embedding", "coreml_e5_small", "apple_fm_embed" (future)
    var embeddingDim: Int // e.g. 512, 384, 768
    var vectorDBKind: VectorDBKind
    var strictMode: Bool // Higher safety thresholds for medical/high-stakes
    var autoAdaptDimension: Bool // Auto-orchestrate chunking/embedding when enabled
    var chunkingDirective: ChunkingDirective?
    var lastSelfTuneAt: Date?

    // Stats for quick UI rendering
    var totalDocuments: Int
    var totalChunks: Int
    var dbSizeBytes: Int64
    var lastIndexedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "folder.fill",
        colorHex: String = "#4F46E5",
        createdAt: Date = Date(),
        description: String? = nil,
        embeddingProviderId: String = "nl_embedding",
        embeddingDim: Int = 512,
        vectorDBKind: VectorDBKind = .persistentJSON,
        strictMode: Bool = true,
        autoAdaptDimension: Bool = false,
        chunkingDirective: ChunkingDirective? = nil,
        lastSelfTuneAt: Date? = nil,
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
        self.strictMode = strictMode
        self.autoAdaptDimension = autoAdaptDimension
        self.chunkingDirective = chunkingDirective
        self.lastSelfTuneAt = lastSelfTuneAt
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
            embeddingDim: 512, // NLContextualEmbedding typically outputs 512-dim
            vectorDBKind: .persistentJSON,
            strictMode: true,
            autoAdaptDimension: true
        )
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
}
