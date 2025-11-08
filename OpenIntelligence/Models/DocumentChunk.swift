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
    let content: String
    let embedding: [Float]
    let metadata: ChunkMetadata
    
    init(id: UUID = UUID(), documentId: UUID, content: String, embedding: [Float], metadata: ChunkMetadata) {
        self.id = id
        self.documentId = documentId
        self.content = content
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
        createdAt: Date = Date()
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
    
    init(
        id: UUID = UUID(),
        filename: String,
        fileURL: URL,
        contentType: DocumentType,
        addedAt: Date = Date(),
        totalChunks: Int = 0,
        processingMetadata: ProcessingMetadata? = nil,
        containerId: UUID? = nil
    ) {
        self.id = id
        self.filename = filename
        self.fileURL = fileURL
        self.contentType = contentType
        self.addedAt = addedAt
        self.totalChunks = totalChunks
        self.processingMetadata = processingMetadata
        self.containerId = containerId
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
    
    struct ChunkStatistics {
        let avgChars: Int
        let minChars: Int
        let maxChars: Int
    }
}
