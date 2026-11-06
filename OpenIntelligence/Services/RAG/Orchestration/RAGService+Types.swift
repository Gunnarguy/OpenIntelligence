//
//  RAGService+Types.swift
//  OpenIntelligence
//
//  Part of RAGService, moved unchanged from RAGService.swift on 2026-11-05 (5.8 split).
//

import Combine
import CryptoKit
import Foundation
import NaturalLanguage
import PDFKit

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    // For `NSApplication.isActive`, the AppKit equivalent of the foreground check that gates
    // Private Cloud Compute. Without it the macOS branch had no foreground check at all.
    import AppKit
#endif

#if canImport(FoundationModels)
    import FoundationModels
#endif
// MARK: - Async Collection Helpers

extension Array {
    /// Filter array with async predicate
    func asyncFilter(_ isIncluded: @escaping (Element) async -> Bool) async -> [Element] {
        var result: [Element] = []
        for element in self {
            if await isIncluded(element) {
                result.append(element)
            }
        }
        return result
    }
}

extension UUID {
    static func deterministic(from string: String) -> UUID {
        guard let data = string.data(using: .utf8) else {
            return UUID()
        }
        let hash = Insecure.MD5.hash(data: data)
        let bytes = Array(hash)
        guard bytes.count >= 16 else {
            return UUID()
        }
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3],
                bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11],
                bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }
}

struct RetrievalLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let containerId: UUID
    let containerName: String
    let chunks: [RetrievedChunk]
}

struct RAGAuditFeatureFlags: Sendable {
    let answerIntent: String
    let queryWasRewritten: Bool
    let queryExpansionCount: Int
    let usedHyDE: Bool
    let usedIterativeRetrieval: Bool
    let iterativePassCount: Int
    let usedQueryRouting: Bool
    let usedSummaryRouting: Bool
    let usedParentDocumentRetrieval: Bool
    let usedCorrectiveRetrieval: Bool
    let usedContextualCompression: Bool
    let usedGraphPacking: Bool
    let usedRetrievalCascade: Bool
    let usedSupplementaryVectorSearch: Bool
    let usedFullUnlimitedReasoning: Bool

    nonisolated static let empty = RAGAuditFeatureFlags(
        answerIntent: "unknown",
        queryWasRewritten: false,
        queryExpansionCount: 0,
        usedHyDE: false,
        usedIterativeRetrieval: false,
        iterativePassCount: 0,
        usedQueryRouting: false,
        usedSummaryRouting: false,
        usedParentDocumentRetrieval: false,
        usedCorrectiveRetrieval: false,
        usedContextualCompression: false,
        usedGraphPacking: false,
        usedRetrievalCascade: false,
        usedSupplementaryVectorSearch: false,
        usedFullUnlimitedReasoning: false
    )

    var enabledFeatures: [String] {
        var features: [String] = []
        if queryWasRewritten { features.append("Rewrite") }
        if queryExpansionCount > 0 { features.append("Expand \(queryExpansionCount)") }
        if usedHyDE { features.append("HyDE") }
        if usedIterativeRetrieval {
            let label = iterativePassCount > 0 ? "Iterative \(iterativePassCount)x" : "Iterative"
            features.append(label)
        }
        if usedQueryRouting { features.append("Routing") }
        if usedSummaryRouting { features.append("Summaries") }
        if usedParentDocumentRetrieval { features.append("Parent") }
        if usedCorrectiveRetrieval { features.append("Corrective") }
        if usedContextualCompression { features.append("Compression") }
        if usedGraphPacking { features.append("GraphPack") }
        if usedRetrievalCascade { features.append("Cascade") }
        if usedSupplementaryVectorSearch { features.append("MultiVector") }
        if usedFullUnlimitedReasoning { features.append("Unlimited") }
        return features
    }
}

struct RAGAuditSnapshot: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let query: String
    let containerId: UUID
    let containerName: String

    let embeddingProviderId: String
    let embeddingDim: Int
    let vectorDBKind: VectorDBKind
    let chunkingTargetWords: Int
    let chunkingOverlapWords: Int
    let chunkingSource: String
    let qualityModeName: String  // Changed from RAGQualityMode enum to String
    let retrievalConfig: RetrievalConfig

    let lenientRetrieval: Bool
    let dynamicMin: Float
    let topSim: Float
    let secondSim: Float
    let avgTop5: Float
    let acceptanceOverride: Bool

    let totalStoredChunks: Int
    let candidatesCount: Int
    let rerankedCount: Int
    let filteredCount: Int
    let droppedCount: Int
    let mmrSelectedCount: Int
    let uniqueDocCount: Int

    let contextStrategy: String

    let contextChars: Int
    let contextWords: Int
    let contextChunksUsed: Int
    let maxContextChars: Int
    let baseWindowTokens: Int
    let safetyTokens: Int
    let promptOverheadTokens: Int
    let questionTokens: Int
    let reservedOutputTokens: Int
    let availableContextTokens: Int

    let executionContext: ExecutionContext
    let allowPrivateCloudCompute: Bool
    let networkConnected: Bool
    let wantsCloudContext: Bool
    let reliabilityModeEnabled: Bool
    let allowUngroundedFallback: Bool
    let modelName: String
    let featureFlags: RAGAuditFeatureFlags

    // Recursive RAG metrics (for Deep Think / agentic mode)
    /// Whether this used recursive RAG (multiple small calls instead of one large call)
    let isRecursiveRAG: Bool
    /// Total tokens used across ALL LLM calls in recursive mode
    let totalTokensAcrossCalls: Int
    /// Number of individual LLM calls made
    let llmCallCount: Int

    // Default values for non-recursive mode
    init(
        timestamp: Date,
        query: String,
        containerId: UUID,
        containerName: String,
        embeddingProviderId: String,
        embeddingDim: Int,
        vectorDBKind: VectorDBKind,
        chunkingTargetWords: Int,
        chunkingOverlapWords: Int,
        chunkingSource: String,
        qualityModeName: String,
        retrievalConfig: RetrievalConfig,
        lenientRetrieval: Bool,
        dynamicMin: Float,
        topSim: Float,
        secondSim: Float,
        avgTop5: Float,
        acceptanceOverride: Bool,
        totalStoredChunks: Int,
        candidatesCount: Int,
        rerankedCount: Int,
        filteredCount: Int,
        droppedCount: Int,
        mmrSelectedCount: Int,
        uniqueDocCount: Int,
        contextStrategy: String,
        contextChars: Int,
        contextWords: Int,
        contextChunksUsed: Int,
        maxContextChars: Int,
        baseWindowTokens: Int,
        safetyTokens: Int,
        promptOverheadTokens: Int,
        questionTokens: Int,
        reservedOutputTokens: Int,
        availableContextTokens: Int,
        executionContext: ExecutionContext,
        allowPrivateCloudCompute: Bool,
        networkConnected: Bool,
        wantsCloudContext: Bool,
        reliabilityModeEnabled: Bool,
        allowUngroundedFallback: Bool,
        modelName: String,
        featureFlags: RAGAuditFeatureFlags = .empty,
        isRecursiveRAG: Bool = false,
        totalTokensAcrossCalls: Int = 0,
        llmCallCount: Int = 1
    ) {
        self.timestamp = timestamp
        self.query = query
        self.containerId = containerId
        self.containerName = containerName
        self.embeddingProviderId = embeddingProviderId
        self.embeddingDim = embeddingDim
        self.vectorDBKind = vectorDBKind
        self.chunkingTargetWords = chunkingTargetWords
        self.chunkingOverlapWords = chunkingOverlapWords
        self.chunkingSource = chunkingSource
        self.qualityModeName = qualityModeName
        self.retrievalConfig = retrievalConfig
        self.lenientRetrieval = lenientRetrieval
        self.dynamicMin = dynamicMin
        self.topSim = topSim
        self.secondSim = secondSim
        self.avgTop5 = avgTop5
        self.acceptanceOverride = acceptanceOverride
        self.totalStoredChunks = totalStoredChunks
        self.candidatesCount = candidatesCount
        self.rerankedCount = rerankedCount
        self.filteredCount = filteredCount
        self.droppedCount = droppedCount
        self.mmrSelectedCount = mmrSelectedCount
        self.uniqueDocCount = uniqueDocCount
        self.contextStrategy = contextStrategy
        self.contextChars = contextChars
        self.contextWords = contextWords
        self.contextChunksUsed = contextChunksUsed
        self.maxContextChars = maxContextChars
        self.baseWindowTokens = baseWindowTokens
        self.safetyTokens = safetyTokens
        self.promptOverheadTokens = promptOverheadTokens
        self.questionTokens = questionTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.availableContextTokens = availableContextTokens
        self.executionContext = executionContext
        self.allowPrivateCloudCompute = allowPrivateCloudCompute
        self.networkConnected = networkConnected
        self.wantsCloudContext = wantsCloudContext
        self.reliabilityModeEnabled = reliabilityModeEnabled
        self.allowUngroundedFallback = allowUngroundedFallback
        self.modelName = modelName
        self.featureFlags = featureFlags
        self.isRecursiveRAG = isRecursiveRAG
        self.totalTokensAcrossCalls = totalTokensAcrossCalls
        self.llmCallCount = llmCallCount
    }
}

struct VectorStoreAudit: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let containerId: UUID
    let containerName: String
    let expectedDimension: Int
    let totalChunks: Int
    let mismatchedDimensions: Int
    let uniqueDocuments: Int
    let averageChunkWords: Double
    let minChunkWords: Int
    let maxChunkWords: Int
}

struct ReembedProgress: Sendable {
    let completed: Int
    let total: Int
    let currentFilename: String

    var percentage: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }
}

enum IngestionContext: String, Codable, Sendable {
    case userInitiated
    case autoRebuild
    case onboarding  // Initial sample import - skip self-tuning

    var allowsSelfTuningScheduling: Bool {
        switch self {
        case .userInitiated:
            return false
        case .autoRebuild, .onboarding:
            return false
        }
    }
}

/// Where a library's rebuild is (5.8, `RAGService.libraryRebuildProgress`): `done` of `total` documents, and the one
/// being read now.
struct LibraryRebuildProgress: Equatable, Sendable {
    let libraryId: UUID
    let done: Int
    let total: Int
    let filename: String
}
