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
    let confidenceScore: Float // 0.0-1.0 aggregate confidence
    let qualityWarnings: [String] // Warnings about result quality
    let structuredAnswer: StructuredAnswer? // AppleRAG §6 structured output

    init(id: UUID = UUID(),
         queryId: UUID,
         retrievedChunks: [RetrievedChunk],
         generatedResponse: String,
         metadata: ResponseMetadata,
         confidenceScore: Float = 1.0,
         qualityWarnings: [String] = [],
         structuredAnswer: StructuredAnswer? = nil)
    {
        self.id = id
        self.queryId = queryId
        self.retrievedChunks = retrievedChunks
        self.generatedResponse = generatedResponse
        self.metadata = metadata
        self.confidenceScore = confidenceScore
        self.qualityWarnings = qualityWarnings
        self.structuredAnswer = structuredAnswer
    }
}

/// A document chunk retrieved for context with its similarity score
struct RetrievedChunk: Codable, Sendable {
    let chunk: DocumentChunk
    let similarityScore: Float
    let rank: Int
    let sourceDocument: String // Filename for citation
    let pageNumber: Int? // Page number if available

    nonisolated init(chunk: DocumentChunk, similarityScore: Float, rank: Int, sourceDocument: String = "", pageNumber: Int? = nil) {
        self.chunk = chunk
        self.similarityScore = similarityScore
        self.rank = rank
        self.sourceDocument = sourceDocument
        self.pageNumber = pageNumber
    }
}

/// Performance and execution metadata for a RAG response
struct ResponseMetadata: Codable, Sendable {
    let timeToFirstToken: TimeInterval?
    let totalGenerationTime: TimeInterval
    let tokensGenerated: Int
    let tokensPerSecond: Float?
    let modelUsed: String
    let retrievalTime: TimeInterval
    let retrievalConfigSummary: String // e.g., "Balanced", "High Accuracy", "Custom"
    let gatingDecision: String?
    let toolCallsMade: Int?
    let embeddingProvider: String? // e.g., "nl_embedding", "nl_contextual_embedding"

    /// Whether the agentic (multi-step reasoning) mode was used for this response.
    /// When false, single-pass retrieval was used. Users can request deeper analysis
    /// via the "Go Deeper" button if they want agentic processing.
    let usedAgenticMode: Bool

    /// The quality mode used: "Standard", "Deep Think", or "Maximum"
    let qualityModeName: String?

    /// The original query that triggered this response (for re-query with deeper mode)
    let originalQuery: String?

    /// Reasoning trace from chained sessions (shows how the AI "thought through" the problem)
    /// Each string is one step: ["🔍 Analyzing: found X...", "🧠 Patterns: theme is Y...", etc.]
    let reasoningTrace: [String]?

    init(timeToFirstToken: TimeInterval? = nil,
         totalGenerationTime: TimeInterval,
         tokensGenerated: Int,
         tokensPerSecond: Float? = nil,
         modelUsed: String,
         retrievalTime: TimeInterval,
         retrievalConfigSummary: String = "Balanced",
         gatingDecision: String? = nil,
         toolCallsMade: Int? = nil,
         embeddingProvider: String? = nil,
         usedAgenticMode: Bool = false,
         qualityModeName: String? = nil,
         originalQuery: String? = nil,
         reasoningTrace: [String]? = nil)
    {
        self.timeToFirstToken = timeToFirstToken
        self.totalGenerationTime = totalGenerationTime
        self.tokensGenerated = tokensGenerated
        self.tokensPerSecond = tokensPerSecond
        self.modelUsed = modelUsed
        self.retrievalTime = retrievalTime
        self.retrievalConfigSummary = retrievalConfigSummary
        self.gatingDecision = gatingDecision
        self.toolCallsMade = toolCallsMade
        self.embeddingProvider = embeddingProvider
        self.usedAgenticMode = usedAgenticMode
        self.qualityModeName = qualityModeName
        self.originalQuery = originalQuery
        self.reasoningTrace = reasoningTrace
    }

    // MARK: - Computed Properties

    /// True if using High Accuracy retrieval config (formerly "strict mode")
    var isHighAccuracyMode: Bool {
        retrievalConfigSummary == "High Accuracy"
    }

    /// True if this response used single-pass and could benefit from deeper analysis
    var canGoDeeper: Bool {
        !usedAgenticMode && originalQuery != nil
    }
}
