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
    let createdAt: Date
    
    init(chunkIndex: Int, startPosition: Int, endPosition: Int, pageNumber: Int? = nil, createdAt: Date = Date()) {
        self.chunkIndex = chunkIndex
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.pageNumber = pageNumber
        self.createdAt = createdAt
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
