//  KnowledgeContainer.swift
//  OpenIntelligence
//
//  Defines a per-topic/library container for documents and vectors.
//  Each container can choose its own embedding provider/dimension and vector DB backend.
//  Containers enable strict scoping for high-accuracy use cases (e.g., medical topics).
//

import Foundation

enum VectorDBKind: String, Codable, CaseIterable, Sendable {
    case persistentJSON   // Built-in JSON persistence (baseline)
    case vecturaHNSW      // Optional VecturaKit ANN index (if available)
    case inMemory         // Volatile (for testing)
}

struct KnowledgeContainer: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: String
    var colorHex: String
    var createdAt: Date
    var description: String?
    
    // Retrieval/Embedding configuration
    var embeddingProviderId: String      // e.g. "nl_embedding", "coreml_e5_small", "apple_fm_embed" (future)
    var embeddingDim: Int                // e.g. 512, 384, 768
    var vectorDBKind: VectorDBKind
    var strictMode: Bool                 // Higher safety thresholds for medical/high-stakes
    
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
        self.totalDocuments = totalDocuments
        self.totalChunks = totalChunks
        self.dbSizeBytes = dbSizeBytes
        self.lastIndexedAt = lastIndexedAt
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
