//
//  RAGQuery.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import Foundation

/// Represents a user query in the RAG pipeline
struct RAGQuery: Sendable {
    let id: UUID
    let query: String
    let timestamp: Date
    let topK: Int
    
    init(id: UUID = UUID(), query: String, timestamp: Date = Date(), topK: Int = 3) {
        self.id = id
        self.query = query
        self.timestamp = timestamp
        self.topK = topK
    }
}

/// Result of a RAG query including retrieved context and generated response
struct RAGResponse: Sendable {
    let id: UUID
    let queryId: UUID
    let retrievedChunks: [RetrievedChunk]
    let generatedResponse: String
    let metadata: ResponseMetadata
    let confidenceScore: Float  // 0.0-1.0 aggregate confidence
    let qualityWarnings: [String]  // Warnings about result quality
    
    init(id: UUID = UUID(), 
         queryId: UUID, 
         retrievedChunks: [RetrievedChunk], 
         generatedResponse: String, 
         metadata: ResponseMetadata,
         confidenceScore: Float = 1.0,
         qualityWarnings: [String] = []) {
        self.id = id
        self.queryId = queryId
        self.retrievedChunks = retrievedChunks
        self.generatedResponse = generatedResponse
        self.metadata = metadata
        self.confidenceScore = confidenceScore
        self.qualityWarnings = qualityWarnings
    }
}

/// A document chunk retrieved for context with its similarity score
struct RetrievedChunk: Sendable {
    let chunk: DocumentChunk
    let similarityScore: Float
    let rank: Int
    let sourceDocument: String  // Filename for citation
    let pageNumber: Int?  // Page number if available
    
    nonisolated init(chunk: DocumentChunk, similarityScore: Float, rank: Int, sourceDocument: String = "", pageNumber: Int? = nil) {
        self.chunk = chunk
        self.similarityScore = similarityScore
        self.rank = rank
        self.sourceDocument = sourceDocument
        self.pageNumber = pageNumber
    }
}

/// Performance and execution metadata for a RAG response
struct ResponseMetadata: Sendable {
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let tokensGenerated: Int
    let tokensPerSecond: Float?
    let modelUsed: String
    let retrievalTime: TimeInterval
    let strictModeEnabled: Bool
    let gatingDecision: String?
    
    init(timeToFirstToken: TimeInterval? = nil,
         totalGenerationTime: TimeInterval,
         tokensGenerated: Int,
         tokensPerSecond: Float? = nil,
         modelUsed: String,
         retrievalTime: TimeInterval,
         strictModeEnabled: Bool = false,
         gatingDecision: String? = nil) {
        self.timeToFirstToken = timeToFirstToken
        self.totalGenerationTime = totalGenerationTime
        self.tokensGenerated = tokensGenerated
        self.tokensPerSecond = tokensPerSecond
        self.modelUsed = modelUsed
        self.retrievalTime = retrievalTime
        self.strictModeEnabled = strictModeEnabled
        self.gatingDecision = gatingDecision
    }
}
