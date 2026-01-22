//
//  ContextPackingService.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Context packing per AppleRAG spec §5:
//  pack(R + parents(R) + neighbors(R,±1) + graphHops(R,1))
//
//  Packs retrieved chunks with their graph context to provide
//  the LLM with complete information for answering.
//
//  Ordering rules (per spec):
//  1. Section heading parent (if different from chunk)
//  2. Prev neighbor (±1 chunk)
//  3. Core chunk
//  4. Next neighbor
//  5. Referenced chunks (via cross-refs)
//
//  Token budget is enforced with priority-based trimming.
//

import Foundation

// MARK: - Packed Context

/// Result of context packing operation
struct PackedContext: Sendable {
    /// Ordered chunks ready for LLM prompt
    let chunks: [DocumentChunk]

    /// Total estimated tokens
    let estimatedTokens: Int

    /// Number of core chunks included
    let coreChunkCount: Int

    /// Number of context chunks added (parents, neighbors, refs)
    let contextChunkCount: Int

    /// Whether context was truncated due to token budget
    let wasTruncated: Bool

    /// IDs of chunks that were trimmed
    let trimmedChunkIds: [UUID]
}

// MARK: - Context Packing Service

/// Service for packing retrieved chunks with graph context
/// per AppleRAG spec §5.
actor ContextPackingService {

    /// Graph index for traversal
    private let graphIndex: GraphIndexService

    /// Estimated tokens per character (conservative estimate)
    private let tokensPerChar: Double = 0.3

    /// Default token budget (can be overridden per call)
    private let defaultTokenBudget: Int = 4000

    init(graphIndex: GraphIndexService? = nil) {
        self.graphIndex = graphIndex ?? GraphIndexService()
    }

    // MARK: - Main Packing Method

    /// Pack retrieved chunks with their graph context
    /// per AppleRAG spec §5: pack(R + parents(R) + neighbors(R,±1) + graphHops(R,1))
    ///
    /// - Parameters:
    ///   - retrievedChunks: Core retrieved chunks (ranked by relevance)
    ///   - graphEdges: Pre-built graph edges for the document(s)
    ///   - allChunks: Lookup table for all chunks by ID
    ///   - tokenBudget: Maximum tokens for context window
    ///   - neighborDistance: Distance for neighbor inclusion (default ±1)
    ///   - graphHopDistance: Distance for cross-reference hops (default 1)
    /// - Returns: Packed context with ordered chunks
    func pack(
        retrievedChunks: [DocumentChunk],
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk],
        tokenBudget: Int? = nil,
        neighborDistance: Int = 1,
        graphHopDistance: Int = 1
    ) async -> PackedContext {
        let budget = tokenBudget ?? defaultTokenBudget

        // Collect all chunks to include
        var coreChunks: [DocumentChunk] = []
        var parentChunks: [DocumentChunk] = []
        var neighborChunks: [DocumentChunk] = []
        var refChunks: [DocumentChunk] = []

        var seenIds: Set<UUID> = []

        // Process each retrieved chunk
        for chunk in retrievedChunks {
            guard !seenIds.contains(chunk.id) else { continue }
            seenIds.insert(chunk.id)
            coreChunks.append(chunk)

            // Get parent chain
            let parents = await graphIndex.parentChain(
                for: chunk.id,
                graphEdges: graphEdges,
                allChunks: allChunks
            )
            for parent in parents {
                if !seenIds.contains(parent.id) {
                    seenIds.insert(parent.id)
                    parentChunks.append(parent)
                }
            }

            // Get neighbors (±1)
            let neighbors = await graphIndex.neighbors(
                for: chunk.id,
                distance: neighborDistance,
                graphEdges: graphEdges,
                allChunks: allChunks
            )
            for neighbor in neighbors {
                if !seenIds.contains(neighbor.id) {
                    seenIds.insert(neighbor.id)
                    neighborChunks.append(neighbor)
                }
            }

            // Get graph hops (cross-references)
            if graphHopDistance > 0 {
                let refs = await graphIndex.graphHops(
                    from: [chunk.id],
                    maxHops: graphHopDistance,
                    graphEdges: graphEdges,
                    allChunks: allChunks
                )
                for ref in refs {
                    if !seenIds.contains(ref.id) {
                        seenIds.insert(ref.id)
                        refChunks.append(ref)
                    }
                }
            }
        }

        // Prioritized assembly with token budget
        return assembleWithBudget(
            coreChunks: coreChunks,
            parentChunks: parentChunks,
            neighborChunks: neighborChunks,
            refChunks: refChunks,
            tokenBudget: budget
        )
    }

    // MARK: - Budget-Aware Assembly

    /// Assemble chunks with priority-based token budget enforcement
    private func assembleWithBudget(
        coreChunks: [DocumentChunk],
        parentChunks: [DocumentChunk],
        neighborChunks: [DocumentChunk],
        refChunks: [DocumentChunk],
        tokenBudget: Int
    ) -> PackedContext {
        var result: [DocumentChunk] = []
        var usedTokens = 0
        var trimmedIds: [UUID] = []

        // Priority order: core > parents > neighbors > refs
        // Within each category, maintain original ordering

        // Phase 1: Add core chunks (highest priority)
        for chunk in coreChunks {
            let tokens = estimateTokens(chunk)
            if usedTokens + tokens <= tokenBudget {
                result.append(chunk)
                usedTokens += tokens
            } else {
                trimmedIds.append(chunk.id)
            }
        }

        // Phase 2: Add parent chunks (section context)
        for chunk in parentChunks {
            let tokens = estimateTokens(chunk)
            if usedTokens + tokens <= tokenBudget {
                result.append(chunk)
                usedTokens += tokens
            } else {
                trimmedIds.append(chunk.id)
            }
        }

        // Phase 3: Add neighbor chunks (local context)
        for chunk in neighborChunks {
            let tokens = estimateTokens(chunk)
            if usedTokens + tokens <= tokenBudget {
                result.append(chunk)
                usedTokens += tokens
            } else {
                trimmedIds.append(chunk.id)
            }
        }

        // Phase 4: Add referenced chunks (cross-ref context)
        for chunk in refChunks {
            let tokens = estimateTokens(chunk)
            if usedTokens + tokens <= tokenBudget {
                result.append(chunk)
                usedTokens += tokens
            } else {
                trimmedIds.append(chunk.id)
            }
        }

        // Sort result by document order within each document
        let sorted = sortByDocumentOrder(result)

        return PackedContext(
            chunks: sorted,
            estimatedTokens: usedTokens,
            coreChunkCount: coreChunks.count,
            contextChunkCount: parentChunks.count + neighborChunks.count + refChunks.count,
            wasTruncated: !trimmedIds.isEmpty,
            trimmedChunkIds: trimmedIds
        )
    }

    /// Estimate tokens for a chunk
    private func estimateTokens(_ chunk: DocumentChunk) -> Int {
        Int(Double(chunk.content.count) * tokensPerChar)
    }

    /// Sort chunks by document order (page number, then position)
    private func sortByDocumentOrder(_ chunks: [DocumentChunk]) -> [DocumentChunk] {
        chunks.sorted { (a: DocumentChunk, b: DocumentChunk) -> Bool in
            // Sort by document first
            if a.documentId != b.documentId {
                return a.documentId.uuidString < b.documentId.uuidString
            }

            // Then by page number
            let pageA = a.metadata.pageNumber ?? 0
            let pageB = b.metadata.pageNumber ?? 0
            if pageA != pageB {
                return pageA < pageB
            }

            // Then by chunk index
            return a.metadata.chunkIndex < b.metadata.chunkIndex
        }
    }

    // MARK: - Specialized Packing Modes

    /// Pack for procedure-type queries (emphasize sequential ordering)
    func packForProcedure(
        retrievedChunks: [DocumentChunk],
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk],
        tokenBudget: Int? = nil
    ) async -> PackedContext {
        // For procedures, include more neighbors (±2) for step continuity
        return await pack(
            retrievedChunks: retrievedChunks,
            graphEdges: graphEdges,
            allChunks: allChunks,
            tokenBudget: tokenBudget,
            neighborDistance: 2,  // More context for procedures
            graphHopDistance: 0   // No cross-ref hops for procedures
        )
    }

    /// Pack for comparison queries (include all compared items)
    func packForComparison(
        retrievedChunks: [DocumentChunk],
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk],
        tokenBudget: Int? = nil
    ) async -> PackedContext {
        // For comparisons, follow more cross-references
        return await pack(
            retrievedChunks: retrievedChunks,
            graphEdges: graphEdges,
            allChunks: allChunks,
            tokenBudget: tokenBudget,
            neighborDistance: 1,
            graphHopDistance: 2   // Follow more refs for comparison context
        )
    }

    /// Pack for summarization (broader coverage)
    func packForSummarization(
        retrievedChunks: [DocumentChunk],
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk],
        tokenBudget: Int? = nil
    ) async -> PackedContext {
        // For summarization, prioritize section parents for high-level context
        let budget = tokenBudget ?? defaultTokenBudget

        var result: [DocumentChunk] = []
        var usedTokens = 0
        var seenIds: Set<UUID> = []
        var trimmedIds: [UUID] = []

        // First pass: Add section heading parents only
        for chunk in retrievedChunks {
            let parents = await graphIndex.parentChain(
                for: chunk.id,
                graphEdges: graphEdges,
                allChunks: allChunks
            )

            // Add topmost parent first (most general)
            for parent in parents.reversed() {
                if !seenIds.contains(parent.id) {
                    let tokens = estimateTokens(parent)
                    if usedTokens + tokens <= budget / 2 {  // Reserve half for core
                        seenIds.insert(parent.id)
                        result.append(parent)
                        usedTokens += tokens
                    }
                }
            }
        }

        // Second pass: Add core chunks
        for chunk in retrievedChunks {
            if !seenIds.contains(chunk.id) {
                let tokens = estimateTokens(chunk)
                if usedTokens + tokens <= budget {
                    seenIds.insert(chunk.id)
                    result.append(chunk)
                    usedTokens += tokens
                } else {
                    trimmedIds.append(chunk.id)
                }
            }
        }

        let sorted = sortByDocumentOrder(result)

        return PackedContext(
            chunks: sorted,
            estimatedTokens: usedTokens,
            coreChunkCount: retrievedChunks.count,
            contextChunkCount: result.count - retrievedChunks.count,
            wasTruncated: !trimmedIds.isEmpty,
            trimmedChunkIds: trimmedIds
        )
    }
}

// MARK: - Convenience Extension

extension ContextPackingService {
    /// Pack based on answer intent (routes to specialized packing)
    func pack(
        for intent: AnswerIntent,
        retrievedChunks: [DocumentChunk],
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk],
        tokenBudget: Int? = nil
    ) async -> PackedContext {
        switch intent {
        case .procedure:
            return await packForProcedure(
                retrievedChunks: retrievedChunks,
                graphEdges: graphEdges,
                allChunks: allChunks,
                tokenBudget: tokenBudget
            )
        case .compare:
            return await packForComparison(
                retrievedChunks: retrievedChunks,
                graphEdges: graphEdges,
                allChunks: allChunks,
                tokenBudget: tokenBudget
            )
        case .summarize:
            return await packForSummarization(
                retrievedChunks: retrievedChunks,
                graphEdges: graphEdges,
                allChunks: allChunks,
                tokenBudget: tokenBudget
            )
        default:
            return await pack(
                retrievedChunks: retrievedChunks,
                graphEdges: graphEdges,
                allChunks: allChunks,
                tokenBudget: tokenBudget
            )
        }
    }
}
