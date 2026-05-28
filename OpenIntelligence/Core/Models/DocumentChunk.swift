//
//  DocumentChunk.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import CoreGraphics
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

    nonisolated init(
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

// MARK: - Chunk Abstraction Levels (RAPTOR-lite)

/// Hierarchy level for chunk abstraction (RAPTOR-lite implementation).
/// Level 0 = raw detail chunks, higher levels = progressively summarized content.
/// This enables efficient query routing: overview queries search summaries first.
enum ChunkAbstractionLevel: Int, Codable, Sendable, CaseIterable {
    /// Level 0: Original document chunks (280-400 words, semantic boundaries)
    case detail = 0

    /// Level 1: Document-level summary (1 per document, ~200 words)
    /// Created at ingestion by DocumentSummaryService via Apple FM
    case documentSummary = 1

    /// Level 2: Topic cluster summary (future - groups related documents)
    case clusterSummary = 2

    /// Level 3: Library-wide summary (future - entire knowledge base overview)
    case librarySummary = 3

    /// Human-readable description for logging
    nonisolated var description: String {
        switch self {
        case .detail: return "Detail (L0)"
        case .documentSummary: return "Document Summary (L1)"
        case .clusterSummary: return "Cluster Summary (L2)"
        case .librarySummary: return "Library Summary (L3)"
        }
    }

    /// Whether this level represents summarized content (L1+)
    nonisolated var isSummary: Bool { rawValue > 0 }
}

/// High-level semantic category inferred from document content.
/// Used to steer ingestion and retrieval policies for manuals, tables, papers, and regulatory docs.
enum DocumentSemanticCategory: String, Codable, Sendable, CaseIterable {
    case technicalManual = "technical_manual"
    case scientificPaper = "scientific_paper"
    case referenceTable = "reference_table"
    case regulatory = "regulatory"
    case general = "general"

    var isSpecificationHeavy: Bool {
        switch self {
        case .technicalManual, .referenceTable:
            return true
        case .scientificPaper, .regulatory, .general:
            return false
        }
    }
}

/// Fine-grained chunk role for retrieval and synthesis ordering.
enum ChunkSemanticType: String, Codable, Sendable, CaseIterable {
    case prose = "prose"
    case tableStructural = "table_structural"
    case tableSemantic = "table_semantic"
    case listItem = "list_item"
    case warning = "warning"
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

    // MARK: - Structured Document Parsing (Jan 2026)

    /// Type of document structure this chunk originated from (table, paragraph, list, title).
    /// Used to boost retrieval when query seeks structured data (specs, schedules, comparisons).
    /// nil for legacy chunks or when extracted via flat text (non-structured parsing).
    let structureType: String?

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

    // MARK: - Abbreviation Dictionary (Feb 2026)

    /// Abbreviation→expansion mappings extracted during chunking.
    /// Captures inline definitions like "Emotional Dysregulation (ED)" or "ED: Emotional Dysregulation"
    /// Injected into LLM context as a glossary to prevent abbreviation cross-contamination hallucinations.
    /// Example: ["ED": "Emotional Dysregulation", "ODD": "Oppositional Defiant Disorder"]
    let abbreviations: [String: String]

    // MARK: - Abstraction Level (RAPTOR-lite, Jun 2025)

    /// Hierarchy level for this chunk (0=detail, 1=docSummary, 2=cluster, 3=library)
    /// Default is .detail for backward compatibility with existing chunks
    let abstractionLevel: ChunkAbstractionLevel

    // MARK: - Section Path Hierarchy (AppleRAG CDM, Feb 2026)

    /// Hierarchical heading path for disambiguation
    /// Example: ["Chapter 5", "5.3 Fluids", "Engine Oil"] enables answering
    /// "What is the oil capacity in Chapter 5?" vs "What is the oil capacity in Chapter 8?"
    /// nil for legacy chunks or documents without clear heading structure
    let sectionPath: [String]?

    // MARK: - Bounding Box (AppleRAG CDM, Feb 2026)

    /// Normalized bounding box (0.0-1.0) for spatial retrieval queries
    /// Enables queries like "what's in the top-right of page 3" or "table at bottom of page"
    /// Stored as [x, y, width, height] array for Codable simplicity (CGRect not Codable)
    /// nil for non-spatial sources (plain text, audio transcriptions)
    let bboxArray: [CGFloat]?

    // MARK: - Document Semantics (Apr 2026)

    /// High-level document category inferred during ingestion.
    /// Helps route technical manuals and table-heavy docs differently from narrative prose.
    let documentCategory: DocumentSemanticCategory?

    /// Fine-grained chunk role used for retrieval weighting and synthesis ordering.
    let chunkType: ChunkSemanticType?

    /// Human-readable table title or heading associated with this chunk.
    /// Only populated for table-derived chunks.
    let tableTitle: String?

    // MARK: - Visual Content (May 2026)

    /// High-level image type for figure-derived chunks.
    let imageContentType: String?

    /// Nearby caption associated with a figure-derived chunk.
    let imageCaption: String?

    /// Best semantic description for a figure-derived chunk.
    let imageDescription: String?

    /// OCR labels or annotations extracted from inside a figure.
    let imageExtractedText: String?

    /// Top image classification labels used during visual understanding.
    let imageClassifications: [String]?

    /// Whether this chunk explicitly references other pages/sections/tables/figures.
    let hasCrossReferences: Bool

    /// Normalized list of cross-reference targets (for example, "page:15", "table:2").
    let resolvedReferences: [String]

    /// Convenience accessor to get CGRect from stored array
    var bbox: CGRect? {
        guard let arr = bboxArray, arr.count == 4 else { return nil }
        return CGRect(x: arr[0], y: arr[1], width: arr[2], height: arr[3])
    }

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
        structureType: String? = nil,
        siblingGroupId: String? = nil,
        siblingCount: Int? = nil,
        entities: [String] = [],
        abbreviations: [String: String] = [:],
        abstractionLevel: ChunkAbstractionLevel = .detail,
        sectionPath: [String]? = nil,
        bboxArray: [CGFloat]? = nil,
        documentCategory: DocumentSemanticCategory? = nil,
        chunkType: ChunkSemanticType? = nil,
        tableTitle: String? = nil,
        imageContentType: String? = nil,
        imageCaption: String? = nil,
        imageDescription: String? = nil,
        imageExtractedText: String? = nil,
        imageClassifications: [String]? = nil,
        hasCrossReferences: Bool = false,
        resolvedReferences: [String] = []
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
        self.structureType = structureType
        self.siblingGroupId = siblingGroupId
        self.siblingCount = siblingCount
        self.entities = entities
        self.abbreviations = abbreviations
        self.abstractionLevel = abstractionLevel
        self.sectionPath = sectionPath
        self.bboxArray = bboxArray
        self.documentCategory = documentCategory
        self.chunkType = chunkType
        self.tableTitle = tableTitle
        self.imageContentType = imageContentType
        self.imageCaption = imageCaption
        self.imageDescription = imageDescription
        self.imageExtractedText = imageExtractedText
        self.imageClassifications = imageClassifications
        self.hasCrossReferences = hasCrossReferences
        self.resolvedReferences = resolvedReferences
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
        case structureType
        case siblingGroupId
        case siblingCount
        case entities
        case abbreviations
        case abstractionLevel
        case sectionPath
        case bboxArray
        case documentCategory
        case chunkType
        case tableTitle
        case imageContentType
        case imageCaption
        case imageDescription
        case imageExtractedText
        case imageClassifications
        case hasCrossReferences
        case resolvedReferences
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
        // Structured document parsing (optional for backward compatibility with old chunks)
        structureType = try container.decodeIfPresent(String.self, forKey: .structureType)
        // Parent Document Retrieval fields (optional for backward compatibility)
        siblingGroupId = try container.decodeIfPresent(String.self, forKey: .siblingGroupId)
        siblingCount = try container.decodeIfPresent(Int.self, forKey: .siblingCount)
        // Entity extraction (optional for backward compatibility with old chunks)
        entities = try container.decodeIfPresent([String].self, forKey: .entities) ?? []
        // Abbreviation dictionary (optional for backward compatibility)
        abbreviations = try container.decodeIfPresent([String: String].self, forKey: .abbreviations) ?? [:]
        // Abstraction level (defaults to .detail for old chunks without this field)
        abstractionLevel = try container.decodeIfPresent(ChunkAbstractionLevel.self, forKey: .abstractionLevel) ?? .detail
        // Section path hierarchy (optional for backward compatibility)
        sectionPath = try container.decodeIfPresent([String].self, forKey: .sectionPath)
        // Bounding box (optional for backward compatibility)
        bboxArray = try container.decodeIfPresent([CGFloat].self, forKey: .bboxArray)
        documentCategory = try container.decodeIfPresent(DocumentSemanticCategory.self, forKey: .documentCategory)
        chunkType = try container.decodeIfPresent(ChunkSemanticType.self, forKey: .chunkType)
        tableTitle = try container.decodeIfPresent(String.self, forKey: .tableTitle)
        imageContentType = try container.decodeIfPresent(String.self, forKey: .imageContentType)
        imageCaption = try container.decodeIfPresent(String.self, forKey: .imageCaption)
        imageDescription = try container.decodeIfPresent(String.self, forKey: .imageDescription)
        imageExtractedText = try container.decodeIfPresent(String.self, forKey: .imageExtractedText)
        imageClassifications = try container.decodeIfPresent([String].self, forKey: .imageClassifications)
        hasCrossReferences = try container.decodeIfPresent(Bool.self, forKey: .hasCrossReferences) ?? false
        resolvedReferences = try container.decodeIfPresent([String].self, forKey: .resolvedReferences) ?? []
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
        // Structured document parsing
        try container.encodeIfPresent(structureType, forKey: .structureType)
        // Parent Document Retrieval fields
        try container.encodeIfPresent(siblingGroupId, forKey: .siblingGroupId)
        try container.encodeIfPresent(siblingCount, forKey: .siblingCount)
        // Entity extraction
        if !entities.isEmpty {
            try container.encode(entities, forKey: .entities)
        }
        // Abbreviation dictionary
        if !abbreviations.isEmpty {
            try container.encode(abbreviations, forKey: .abbreviations)
        }
        // Abstraction level (only encode if not .detail to save space)
        if abstractionLevel != .detail {
            try container.encode(abstractionLevel, forKey: .abstractionLevel)
        }
        // Section path hierarchy
        if let sectionPath = sectionPath, !sectionPath.isEmpty {
            try container.encode(sectionPath, forKey: .sectionPath)
        }
        // Bounding box
        try container.encodeIfPresent(bboxArray, forKey: .bboxArray)
        try container.encodeIfPresent(documentCategory, forKey: .documentCategory)
        try container.encodeIfPresent(chunkType, forKey: .chunkType)
        try container.encodeIfPresent(tableTitle, forKey: .tableTitle)
        try container.encodeIfPresent(imageContentType, forKey: .imageContentType)
        try container.encodeIfPresent(imageCaption, forKey: .imageCaption)
        try container.encodeIfPresent(imageDescription, forKey: .imageDescription)
        try container.encodeIfPresent(imageExtractedText, forKey: .imageExtractedText)
        try container.encodeIfPresent(imageClassifications, forKey: .imageClassifications)
        if hasCrossReferences { try container.encode(hasCrossReferences, forKey: .hasCrossReferences) }
        if !resolvedReferences.isEmpty {
            try container.encode(resolvedReferences, forKey: .resolvedReferences)
        }
    }
}

/// Represents a source document in the RAG knowledge base
struct Document: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let filename: String
    private let legacyFileURL: URL?
    let storageRelativePath: String?
    let fileHash: String?
    let contentType: DocumentType
    let addedAt: Date
    let totalChunks: Int
    let processingMetadata: ProcessingMetadata?
    let containerId: UUID?

    /// Auto-generated content tags from Apple's content tagging model (iOS 26+)
    /// Contains topics, actions, emotions, and objects extracted from document content
    let contentTags: [String]?

    nonisolated var fileURL: URL {
        if let storageRelativePath {
            return AppSupportPaths.documentURL(forRelativePath: storageRelativePath)
        }

        if let legacyFileURL {
            return legacyFileURL
        }

        return AppSupportPaths.importedDocumentsDirectoryURL().appendingPathComponent(filename)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case filename
        case fileURL
        case storageRelativePath
        case fileHash
        case contentType
        case addedAt
        case totalChunks
        case processingMetadata
        case containerId
        case contentTags
    }

    nonisolated init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        storageRelativePath: String? = nil,
        fileHash: String? = nil,
        contentType: DocumentType,
        addedAt: Date = Date(),
        totalChunks: Int = 0,
        processingMetadata: ProcessingMetadata? = nil,
        containerId: UUID? = nil,
        contentTags: [String]? = nil
    ) {
        let resolvedRelativePath = storageRelativePath ?? AppSupportPaths.relativePath(for: fileURL)

        self.id = id
        self.filename = filename
        self.legacyFileURL = resolvedRelativePath == nil ? fileURL : nil
        self.storageRelativePath = resolvedRelativePath
        self.fileHash = fileHash
        self.contentType = contentType
        self.addedAt = addedAt
        self.totalChunks = totalChunks
        self.processingMetadata = processingMetadata
        self.containerId = containerId
        self.contentTags = contentTags
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        filename = try container.decode(String.self, forKey: .filename)
        let decodedLegacyURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        let decodedRelativePath = try container.decodeIfPresent(String.self, forKey: .storageRelativePath)
        let resolvedRelativePath = decodedRelativePath ?? decodedLegacyURL.flatMap { AppSupportPaths.relativePath(for: $0) }
        legacyFileURL = resolvedRelativePath == nil ? decodedLegacyURL : nil
        storageRelativePath = resolvedRelativePath
        fileHash = try container.decodeIfPresent(String.self, forKey: .fileHash)
        contentType = try container.decode(DocumentType.self, forKey: .contentType)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        totalChunks = try container.decodeIfPresent(Int.self, forKey: .totalChunks) ?? 0
        processingMetadata = try container.decodeIfPresent(ProcessingMetadata.self, forKey: .processingMetadata)
        containerId = try container.decodeIfPresent(UUID.self, forKey: .containerId)
        contentTags = try container.decodeIfPresent([String].self, forKey: .contentTags)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(filename, forKey: .filename)
        try container.encodeIfPresent(legacyFileURL, forKey: .fileURL)
        try container.encodeIfPresent(storageRelativePath, forKey: .storageRelativePath)
        try container.encodeIfPresent(fileHash, forKey: .fileHash)
        try container.encode(contentType, forKey: .contentType)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encode(totalChunks, forKey: .totalChunks)
        try container.encodeIfPresent(processingMetadata, forKey: .processingMetadata)
        try container.encodeIfPresent(containerId, forKey: .containerId)
        try container.encodeIfPresent(contentTags, forKey: .contentTags)
    }
}

/// Detailed processing information for a document
struct ProcessingMetadata: Codable, Equatable, Sendable {
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

    // === STRUCTURED DOCUMENT PARSING (Vision iOS 26+) ===
    var usedStructuredParsing: Bool = false
    var structuredParsingQuality: Double = 0
    var tablesExtracted: Int = 0
    var tableRowsTotal: Int = 0
    var tableColumnsMax: Int = 0
    var listsExtracted: Int = 0
    var listItemsTotal: Int = 0
    var titlesDetected: Int = 0
    var figureReferences: Int = 0
    var visionEntitiesDetected: Int = 0
    var sectionPathDepth: Int = 0
    var structuredParsingTimeSeconds: Double = 0
    var atomicTableChunks: Int = 0
    var atomicListChunks: Int = 0
    var documentCategory: DocumentSemanticCategory? = nil
}

struct ChunkStatistics: Codable, Equatable, Sendable {
    let averageChars: Int
    let minChars: Int
    let maxChars: Int
}

enum DocumentType: String, Codable, Sendable {
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
