//
//  QueryRouterService.swift
//  OpenIntelligence
//
//  Intelligently routes queries to optimal retrieval strategies.
//  Part of RAPTOR-lite implementation for efficient token usage.
//
//  Query Types:
//  - Overview: "What is this document about?" → Search L1 summaries first
//  - Detail: "What is the battery capacity?" → Search L0 detail chunks
//  - Cross-topic: "Compare devices" → Search L1 summaries + L0 details
//
//  Created January 2026
//

import Foundation
import NaturalLanguage

// MARK: - Query Classification

/// Represents the type of query for routing decisions
enum QueryType: String, Sendable {
    /// High-level questions about document purpose/content
    /// Examples: "What is this about?", "Summarize the document", "Overview"
    case overview
    
    /// Specific factual questions requiring detail chunks
    /// Examples: "What is the battery capacity?", "How do I connect Bluetooth?"
    case detail
    
    /// Questions spanning multiple topics/documents
    /// Examples: "Compare the two devices", "What are all the features mentioned?"
    case crossTopic
    
    /// Optimal abstraction level to search first
    var primaryLevel: ChunkAbstractionLevel {
        switch self {
        case .overview: return .documentSummary
        case .detail: return .detail
        case .crossTopic: return .documentSummary
        }
    }
    
    /// Whether to also search detail chunks
    var includeDetailChunks: Bool {
        switch self {
        case .overview: return false  // Summaries sufficient
        case .detail: return true     // Only details
        case .crossTopic: return true // Both levels
        }
    }
    
    /// Recommended RAG quality mode for this query type
    var recommendedMode: RAGQualityMode {
        switch self {
        case .overview: return .fast    // Summaries are pre-computed
        case .detail: return .balanced  // Need accurate retrieval
        case .crossTopic: return .maximum // Multi-doc synthesis
        }
    }
}

/// Result of query classification with confidence
struct QueryClassification: Sendable {
    let queryType: QueryType
    let confidence: Float  // 0.0-1.0
    let reasoning: String
    
    /// Whether to use summaries (L1+) for this query
    var shouldUseSummaries: Bool {
        queryType == .overview || queryType == .crossTopic
    }
    
    /// Whether automatic mode selection is recommended
    var shouldOverrideMode: Bool {
        confidence >= 0.7
    }
}

// MARK: - Query Router Service

/// Service for classifying queries and routing to optimal retrieval strategies.
/// Part of RAPTOR-lite implementation to reduce token waste.
actor QueryRouterService {
    
    // MARK: - Configuration
    
    /// Patterns that indicate overview queries
    private let overviewPatterns: [String] = [
        "what is this",
        "what's this",
        "summarize",
        "summary",
        "overview",
        "about this",
        "main topic",
        "main point",
        "tell me about",
        "describe this",
        "what does this document",
        "purpose of this",
        "key points",
        "high level",
        "high-level",
        "in general",
        "overall",
    ]
    
    /// Patterns that indicate detail/specific queries
    private let detailPatterns: [String] = [
        "how do i",
        "how to",
        "what is the",
        "what's the",
        "where is",
        "when did",
        "who is",
        "which",
        "step by step",
        "specifically",
        "exact",
        "battery",
        "capacity",
        "specifications",
        "spec",
        "setting",
        "configure",
        "connect",
        "setup",
        "set up",
    ]
    
    /// Patterns that indicate cross-topic queries
    private let crossTopicPatterns: [String] = [
        "compare",
        "difference between",
        "all of",
        "every",
        "across",
        "throughout",
        "various",
        "different",
        "multiple",
        "all documents",
        "all files",
        "everything",
        "comprehensive",
    ]
    
    // MARK: - Classification
    
    /// Classifies a query to determine optimal retrieval strategy
    func classifyQuery(_ query: String) -> QueryClassification {
        let lowercaseQuery = query.lowercased()
        
        // Count pattern matches for each type
        var overviewScore: Float = 0
        var detailScore: Float = 0
        var crossTopicScore: Float = 0
        
        // Check overview patterns
        for pattern in overviewPatterns {
            if lowercaseQuery.contains(pattern) {
                overviewScore += 1.0
            }
        }
        
        // Check detail patterns
        for pattern in detailPatterns {
            if lowercaseQuery.contains(pattern) {
                detailScore += 1.0
            }
        }
        
        // Check cross-topic patterns
        for pattern in crossTopicPatterns {
            if lowercaseQuery.contains(pattern) {
                crossTopicScore += 1.0
            }
        }
        
        // Analyze query structure
        let queryLength = query.split(separator: " ").count
        
        // Short queries (<5 words) often indicate detail lookups
        if queryLength < 5 && overviewScore == 0 {
            detailScore += 0.5
        }
        
        // Long queries (>15 words) often indicate complex/cross-topic
        if queryLength > 15 {
            crossTopicScore += 0.3
        }
        
        // Questions starting with specific interrogatives favor detail
        if lowercaseQuery.hasPrefix("what is the ") ||
           lowercaseQuery.hasPrefix("how much ") ||
           lowercaseQuery.hasPrefix("how long ") {
            detailScore += 0.5
        }
        
        // Determine winning type
        let maxScore = max(overviewScore, max(detailScore, crossTopicScore))
        let totalScore = overviewScore + detailScore + crossTopicScore
        
        // Default to detail if no strong signals (conservative approach)
        if maxScore == 0 {
            return QueryClassification(
                queryType: .detail,
                confidence: 0.3,
                reasoning: "No strong signals detected; defaulting to detail search"
            )
        }
        
        let confidence = min(maxScore / max(totalScore, 1.0), 1.0)
        
        if overviewScore >= detailScore && overviewScore >= crossTopicScore {
            return QueryClassification(
                queryType: .overview,
                confidence: confidence,
                reasoning: "Matched \(Int(overviewScore)) overview patterns"
            )
        } else if crossTopicScore >= detailScore {
            return QueryClassification(
                queryType: .crossTopic,
                confidence: confidence,
                reasoning: "Matched \(Int(crossTopicScore)) cross-topic patterns"
            )
        } else {
            return QueryClassification(
                queryType: .detail,
                confidence: confidence,
                reasoning: "Matched \(Int(detailScore)) detail patterns"
            )
        }
    }
    
    /// Determines which abstraction levels to search based on query classification
    func abstractionLevelsToSearch(for classification: QueryClassification) -> [ChunkAbstractionLevel] {
        switch classification.queryType {
        case .overview:
            // For overview queries, search summaries first
            // Only include details if confidence is low
            if classification.confidence >= 0.6 {
                return [.documentSummary]
            } else {
                return [.documentSummary, .detail]
            }
            
        case .detail:
            // For detail queries, only search detail chunks
            return [.detail]
            
        case .crossTopic:
            // For cross-topic, search both levels
            // Summaries first for breadth, then details for depth
            return [.documentSummary, .detail]
        }
    }
    
    /// Suggests whether to use Maximum mode based on query type
    func shouldUseMaximumMode(for classification: QueryClassification, currentMode: RAGQualityMode) -> Bool {
        // Only suggest Maximum for cross-topic queries that benefit from multi-doc synthesis
        if classification.queryType == .crossTopic && classification.confidence >= 0.6 {
            return true
        }
        
        // For overview queries, suggest NOT using Maximum (waste of tokens)
        if classification.queryType == .overview && currentMode == .maximum {
            Log.info("[QueryRouter] Recommending Fast mode instead of Maximum for overview query", category: .retrieval)
            return false
        }
        
        // Keep current mode for detail queries
        return currentMode == .maximum
    }
    
    /// Generates a filter predicate for chunk abstraction level
    func levelFilter(for classification: QueryClassification) -> (DocumentChunk) -> Bool {
        let levels = abstractionLevelsToSearch(for: classification)
        return { chunk in
            levels.contains(chunk.metadata.abstractionLevel)
        }
    }
}

// MARK: - Query Intent Detection (Advanced)

extension QueryRouterService {
    
    /// Extracts named entities from the query to help with retrieval
    func extractQueryEntities(_ query: String) -> [String] {
        var entities: [String] = []
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = query
        
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation]
        
        tagger.enumerateTags(in: query.startIndex..<query.endIndex, unit: .word, scheme: .nameType, options: options) { tag, range in
            if let tag = tag, [.personalName, .organizationName, .placeName].contains(tag) {
                let entity = String(query[range])
                if entity.count > 2 {
                    entities.append(entity)
                }
            }
            return true
        }
        
        return entities
    }
    
    /// Detects if query is asking about a specific document
    func detectDocumentReference(_ query: String, documentNames: [String]) -> String? {
        let lowercaseQuery = query.lowercased()
        
        for docName in documentNames {
            let cleanName = docName.lowercased()
                .replacingOccurrences(of: ".pdf", with: "")
                .replacingOccurrences(of: ".txt", with: "")
                .replacingOccurrences(of: "_", with: " ")
            
            if lowercaseQuery.contains(cleanName) {
                return docName
            }
        }
        
        return nil
    }
}
