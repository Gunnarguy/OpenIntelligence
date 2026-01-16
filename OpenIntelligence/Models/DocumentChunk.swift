//
//  DocumentChunk.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation

/// Represents a semantically meaningful chunk of a document with its embedding
struct DocumentChunk: Identifiable, Codable, Sendable {
    let id: UUID
    let documentId: UUID
    var content: String
    /// Optional expanded context window for hierarchical retrieval
    /// Used for LLM context assembly while embeddings remain on `content`.
    let parentContent: String?
    /// Contextual prefix prepended to content BEFORE embedding generation.
    /// Implements Anthropic's "Contextual Retrieval" technique (reduces retrieval failures 35-67%).
    /// Format: "[From {filename}] [{section}] " - stored separately so original content displays cleanly.
    /// The embedding vector captures this prefix, improving semantic matching for queries that mention
    /// document names or topics even when the chunk content itself doesn't contain those terms.
    let contextualPrefix: String?
    let embedding: [Float]
    let metadata: ChunkMetadata

    /// Alias for `content` - provides semantic clarity when working with text processing
    var text: String {
        get { content }
        set { content = newValue }
    }

    init(
        id: UUID = UUID(),
        documentId: UUID,
        content: String,
        parentContent: String? = nil,
        contextualPrefix: String? = nil,
        embedding: [Float],
        metadata: ChunkMetadata
    ) {
        self.id = id
        self.documentId = documentId
        self.content = content
        self.parentContent = parentContent
        self.contextualPrefix = contextualPrefix
        self.embedding = embedding
        self.metadata = metadata
    }
}

/// Metadata for tracking chunk provenance and semantics
struct ChunkMetadata: Codable, Sendable {
    let chunkIndex: Int
    let startPosition: Int
    let endPosition: Int
    let pageNumber: Int?
    let sectionTitle: String?
    let keywords: [String]
    let semanticDensity: Float?
    let hasNumericData: Bool
    let hasListStructure: Bool
    let wordCount: Int
    let characterCount: Int
    let createdAt: Date

    // MARK: - Parent Document Retrieval (Jan 2026)

    /// Unique identifier grouping chunks that belong to the same logical section.
    /// Chunks with the same siblingGroupId can be expanded together for parent context.
    /// Defaults to combining documentId + pageNumber + sectionTitle for backward compatibility.
    let siblingGroupId: String?

    /// Total number of chunks in this sibling group (for context expansion decisions)
    let siblingCount: Int?

    // MARK: - Entity Extraction (Jan 2026)

    /// Named entities extracted via NLTagger (persons, organizations, places, technical terms)
    /// Used by EntityIndexService for cross-document correlation and GraphRAG-lite expansion
    let entities: [String]

    init(
        chunkIndex: Int,
        startPosition: Int = 0,
        endPosition: Int = 0,
        pageNumber: Int? = nil,
        sectionTitle: String? = nil,
        keywords: [String] = [],
        semanticDensity: Float? = nil,
        hasNumericData: Bool = false,
        hasListStructure: Bool = false,
        wordCount: Int = 0,
        characterCount: Int = 0,
        createdAt: Date = Date(),
        siblingGroupId: String? = nil,
        siblingCount: Int? = nil,
        entities: [String] = []
    ) {
        self.chunkIndex = chunkIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.pageNumber = pageNumber
        self.sectionTitle = sectionTitle
        self.keywords = keywords
        self.semanticDensity = semanticDensity
        self.hasNumericData = hasNumericData
        self.hasListStructure = hasListStructure
        self.wordCount = wordCount
        self.characterCount = characterCount
        self.createdAt = createdAt
        self.siblingGroupId = siblingGroupId
        self.siblingCount = siblingCount
        self.entities = entities
    }

    private enum CodingKeys: String, CodingKey {
        case chunkIndex
        case startPosition
        case endPosition
        case pageNumber
        case sectionTitle
        case keywords
        case semanticDensity
        case hasNumericData
        case hasListStructure
        case wordCount
        case characterCount
        case createdAt
        case siblingGroupId
        case siblingCount
        case entities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chunkIndex = try container.decode(Int.self, forKey: .chunkIndex)
        let decodedStart = try container.decodeIfPresent(Int.self, forKey: .startPosition)
        let decodedEnd = try container.decodeIfPresent(Int.self, forKey: .endPosition)
        pageNumber = try container.decodeIfPresent(Int.self, forKey: .pageNumber)
        sectionTitle = try container.decodeIfPresent(String.self, forKey: .sectionTitle)
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        semanticDensity = try container.decodeIfPresent(Float.self, forKey: .semanticDensity)
        hasNumericData = try container.decodeIfPresent(Bool.self, forKey: .hasNumericData) ?? false
        hasListStructure = try container.decodeIfPresent(Bool.self, forKey: .hasListStructure) ?? false
        wordCount = try container.decodeIfPresent(Int.self, forKey: .wordCount) ?? 0
        let decodedCharacterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 0
        characterCount = decodedCharacterCount
        let fallbackStart = decodedStart ?? 0
        startPosition = fallbackStart
        // Old persisted chunks will not contain explicit offsets. Fall back to a sensible range based on count.
        endPosition = decodedEnd ?? (fallbackStart + decodedCharacterCount)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        // Parent Document Retrieval fields (optional for backward compatibility)
        siblingGroupId = try container.decodeIfPresent(String.self, forKey: .siblingGroupId)
        siblingCount = try container.decodeIfPresent(Int.self, forKey: .siblingCount)
        // Entity extraction (optional for backward compatibility with old chunks)
        entities = try container.decodeIfPresent([String].self, forKey: .entities) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(chunkIndex, forKey: .chunkIndex)
        try container.encode(startPosition, forKey: .startPosition)
        try container.encode(endPosition, forKey: .endPosition)
        try container.encodeIfPresent(pageNumber, forKey: .pageNumber)
        try container.encodeIfPresent(sectionTitle, forKey: .sectionTitle)
        if !keywords.isEmpty {
            try container.encode(keywords, forKey: .keywords)
        }
        try container.encodeIfPresent(semanticDensity, forKey: .semanticDensity)
        if hasNumericData { try container.encode(hasNumericData, forKey: .hasNumericData) }
        if hasListStructure { try container.encode(hasListStructure, forKey: .hasListStructure) }
        if wordCount != 0 { try container.encode(wordCount, forKey: .wordCount) }
        if characterCount != 0 { try container.encode(characterCount, forKey: .characterCount) }
        try container.encode(createdAt, forKey: .createdAt)
        // Parent Document Retrieval fields
        try container.encodeIfPresent(siblingGroupId, forKey: .siblingGroupId)
        try container.encodeIfPresent(siblingCount, forKey: .siblingCount)
        // Entity extraction
        if !entities.isEmpty {
            try container.encode(entities, forKey: .entities)
        }
    }
}

/// Represents a source document in the RAG knowledge base
struct Document: Identifiable, Codable {
    let id: UUID
    let filename: String
    let fileURL: URL
    let contentType: DocumentType
    let addedAt: Date
    let totalChunks: Int
    let processingMetadata: ProcessingMetadata?
    let containerId: UUID?

    /// Auto-generated content tags from Apple's content tagging model (iOS 26+)
    /// Contains topics, actions, emotions, and objects extracted from document content
    let contentTags: [String]?

    init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        contentType: DocumentType,
        addedAt: Date = Date(),
        totalChunks: Int = 0,
        processingMetadata: ProcessingMetadata? = nil,
        containerId: UUID? = nil,
        contentTags: [String]? = nil
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.contentType = contentType
        self.addedAt = addedAt
        self.totalChunks = totalChunks
        self.processingMetadata = processingMetadata
        self.containerId = containerId
        self.contentTags = contentTags
    }
}

/// Detailed processing information for a document
struct ProcessingMetadata: Codable {
    let fileSizeMB: Double
    let totalCharacters: Int
    let totalWords: Int
    let extractionTimeSeconds: Double
    let chunkingTimeSeconds: Double
    let embeddingTimeSeconds: Double
    let totalProcessingTimeSeconds: Double
    let pagesProcessed: Int?
    let ocrPagesCount: Int?
    let chunkStats: ChunkStatistics
}

struct ChunkStatistics: Codable {
    let averageChars: Int
    let minChars: Int
    let maxChars: Int
}

enum DocumentType: String, Codable {
    case pdf
    case text
    case markdown
    case rtf

    // Image formats (will use OCR)
    case image
    case png
    case jpeg
    case heic
    case tiff
    case gif

    // Code files (treat as text with syntax preservation)
    case swift
    case python
    case javascript
    case typescript
    case java
    case cpp
    case c
    case objc
    case go
    case rust
    case ruby
    case php
    case html
    case css
    case json
    case xml
    case yaml
    case sql
    case shell
    case code // Generic code file

    // Office documents
    case word
    case excel
    case powerpoint
    case pages
    case numbers
    case keynote

    // Web and data formats
    case csv

    // Audio/Video formats (will use Speech transcription)
    case audio
    case video
    case m4a
    case mp3
    case wav
    case mp4
    case mov

    case unknown
}

/// Summary of document processing metrics shown after completion
struct ProcessingSummary: Identifiable {
    let id = UUID()
    let filename: String
    let fileSize: String
    let documentType: DocumentType
    let pageCount: Int?
    let ocrPagesUsed: Int?
    let totalChars: Int
    let totalWords: Int
    let chunksCreated: Int
    let extractionTime: Double
    let chunkingTime: Double
    let embeddingTime: Double
    let totalTime: Double
    let chunkStats: ChunkStatistics

    /// The embedding provider used for this ingestion (e.g., "nl_embedding", "nl_contextual_embedding")
    let embeddingProviderId: String?

    /// Human-readable name for the embedding provider
    var embeddingProviderDisplayName: String {
        switch embeddingProviderId {
        case "nl_contextual_embedding":
            return "Contextual Embedding"
        case "nl_embedding", nil:
            return "NLEmbedding"
        case "coreml_sentence_embedding":
            return "CoreML Sentence"
        case "apple_fm_embed":
            return "Apple FM"
        default:
            return embeddingProviderId ?? "NLEmbedding"
        }
    }

    /// Whether this is a high-accuracy provider
    var isHighAccuracyProvider: Bool {
        embeddingProviderId == "nl_contextual_embedding"
    }

    struct ChunkStatistics {
        let avgChars: Int
        let minChars: Int
        let maxChars: Int
    }
}
