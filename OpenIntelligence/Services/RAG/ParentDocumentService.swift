//
//  ParentDocumentService.swift
//  OpenIntelligence
//
//  Parent Document Retrieval: When a chunk matches, expand to include
//  surrounding context from the same section/page for coherent multi-paragraph answers.
//
//  Paper: "Improving RAG with Parent Document Retrieval" (2024)
//  Benefit: Maintains coherence for answers that span multiple chunks
//

import Foundation

/// Service for expanding retrieved chunks to include sibling context.
/// When a chunk matches a query, we often want the surrounding chunks from
/// the same section/page to provide coherent multi-paragraph answers.
@MainActor
final class ParentDocumentService {
    // MARK: - Configuration

    struct Config: Sendable {
        /// Maximum number of sibling chunks to include on each side
        let maxSiblingsPerSide: Int

        /// Maximum total tokens after expansion (prevents context explosion)
        let maxExpandedTokens: Int

        /// Whether to expand across page boundaries
        let allowCrossPageExpansion: Bool

        /// Minimum relevance score to trigger expansion (skip for low-quality matches)
        let minRelevanceForExpansion: Float

        nonisolated static var `default`: Config {
            Config(
                maxSiblingsPerSide: 3, // Increased from 2 for better procedural coverage
                    maxExpandedTokens: 2500, // Increased from 2000
                allowCrossPageExpansion: false,
                minRelevanceForExpansion: 0.25 // Slightly more permissive
            )
        }

        /// More aggressive expansion for thorough mode (Deep Think, complex procedures)
        nonisolated static var thorough: Config {
            Config(
                maxSiblingsPerSide: 5, // Increased from 3 - captures full procedure sections
                    maxExpandedTokens: 4000, // Increased from 3000
                allowCrossPageExpansion: true,
                minRelevanceForExpansion: 0.15 // More permissive for related steps
            )
        }

        /// Maximum expansion for procedural/technical documents where sequence matters
        nonisolated static var procedural: Config {
            Config(
                maxSiblingsPerSide: 8, // Capture entire procedure sections
                maxExpandedTokens: 6000,
                allowCrossPageExpansion: true,
                minRelevanceForExpansion: 0.1
            )
        }
    }

    // MARK: - Result Types

    struct ExpansionResult: Sendable {
        let originalChunks: [RetrievedChunk]
        let expandedChunks: [RetrievedChunk]
        let addedSiblings: Int
        let tokensBeforeExpansion: Int
        let tokensAfterExpansion: Int

        var expansionRatio: Double {
            guard tokensBeforeExpansion > 0 else { return 1.0 }
            return Double(tokensAfterExpansion) / Double(tokensBeforeExpansion)
        }
    }

    // MARK: - Properties

    private let config: Config

    // MARK: - Initialization

    init(config: Config = .default) {
        self.config = config
    }

    // MARK: - Public API

    /// Expand retrieved chunks to include sibling context from the same section/page.
    ///
    /// - Parameters:
    ///   - retrievedChunks: The chunks returned from hybrid search/reranking
    ///   - allChunks: All chunks in the database (for finding siblings)
    ///   - query: Original query (for logging)
    /// - Returns: ExpansionResult containing expanded chunks with siblings
    func expandWithSiblings(
        retrievedChunks: [RetrievedChunk],
        allChunks: [DocumentChunk],
        query _: String
    ) async -> ExpansionResult {
        let startTime = Date()

        // Build lookup structures
        let chunkById = Dictionary(uniqueKeysWithValues: allChunks.map { ($0.id, $0) })
        let chunksByDocument = Dictionary(grouping: allChunks) { $0.documentId }

        // Track which chunks we've already included to avoid duplicates
        var includedChunkIds = Set<UUID>()
        var expandedChunks: [RetrievedChunk] = []
        var addedSiblings = 0

        // Calculate initial token count
        let tokensBeforeExpansion = retrievedChunks.reduce(0) { $0 + estimateTokens($1.chunk.content) }
        var currentTokens = 0

        for retrieved in retrievedChunks {
            // Skip if already included (could happen with overlapping sibling groups)
            if includedChunkIds.contains(retrieved.chunk.id) {
                continue
            }

            // Check if we should expand this chunk
            let shouldExpand = retrieved.similarityScore >= config.minRelevanceForExpansion

            if shouldExpand {
                // Find siblings
                let siblings = findSiblings(
                    for: retrieved.chunk,
                    in: chunksByDocument[retrieved.chunk.documentId] ?? [],
                    chunkById: chunkById
                )

                // Add siblings in order (before, matched, after)
                for sibling in siblings.before.reversed() {
                    if currentTokens + estimateTokens(sibling.content) > config.maxExpandedTokens {
                        break
                    }
                    if !includedChunkIds.contains(sibling.id) {
                        let siblingRetrieved = RetrievedChunk(
                            chunk: sibling,
                            similarityScore: retrieved.similarityScore * 0.8, // Discount sibling score
                            rank: expandedChunks.count,
                            sourceDocument: retrieved.sourceDocument,
                            pageNumber: sibling.metadata.pageNumber
                        )
                        expandedChunks.append(siblingRetrieved)
                        includedChunkIds.insert(sibling.id)
                        currentTokens += estimateTokens(sibling.content)
                        addedSiblings += 1
                    }
                }

                // Add the matched chunk
                if !includedChunkIds.contains(retrieved.chunk.id) {
                    expandedChunks.append(retrieved)
                    includedChunkIds.insert(retrieved.chunk.id)
                    currentTokens += estimateTokens(retrieved.chunk.content)
                }

                // Add siblings after
                for sibling in siblings.after {
                    if currentTokens + estimateTokens(sibling.content) > config.maxExpandedTokens {
                        break
                    }
                    if !includedChunkIds.contains(sibling.id) {
                        let siblingRetrieved = RetrievedChunk(
                            chunk: sibling,
                            similarityScore: retrieved.similarityScore * 0.8, // Discount sibling score
                            rank: expandedChunks.count,
                            sourceDocument: retrieved.sourceDocument,
                            pageNumber: sibling.metadata.pageNumber
                        )
                        expandedChunks.append(siblingRetrieved)
                        includedChunkIds.insert(sibling.id)
                        currentTokens += estimateTokens(sibling.content)
                        addedSiblings += 1
                    }
                }
            } else {
                // Just add the matched chunk without expansion
                if !includedChunkIds.contains(retrieved.chunk.id) {
                    expandedChunks.append(retrieved)
                    includedChunkIds.insert(retrieved.chunk.id)
                    currentTokens += estimateTokens(retrieved.chunk.content)
                }
            }

            // Stop if we've hit the token limit
            if currentTokens >= config.maxExpandedTokens {
                break
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        Log.info(
            "Parent document expansion: \(retrievedChunks.count) → \(expandedChunks.count) chunks (+\(addedSiblings) siblings) in \(String(format: "%.0f", duration * 1000))ms",
            category: .retrieval
        )

        return ExpansionResult(
            originalChunks: retrievedChunks,
            expandedChunks: expandedChunks,
            addedSiblings: addedSiblings,
            tokensBeforeExpansion: tokensBeforeExpansion,
            tokensAfterExpansion: currentTokens
        )
    }

    // MARK: - Private Helpers

    private struct SiblingGroup {
        let before: [DocumentChunk]
        let after: [DocumentChunk]
    }

    /// Find sibling chunks for a given chunk (same document, same page/section, adjacent indices)
    private func findSiblings(
        for chunk: DocumentChunk,
        in documentChunks: [DocumentChunk],
        chunkById _: [UUID: DocumentChunk]
    ) -> SiblingGroup {
        // Sort chunks by index
        let sortedChunks = documentChunks.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }

        // Find the position of our chunk
        guard let currentIndex = sortedChunks.firstIndex(where: { $0.id == chunk.id }) else {
            return SiblingGroup(before: [], after: [])
        }

        var before: [DocumentChunk] = []
        var after: [DocumentChunk] = []

        // Look backward for siblings
        for i in stride(from: currentIndex - 1, through: max(0, currentIndex - config.maxSiblingsPerSide), by: -1) {
            let candidate = sortedChunks[i]

            // Check if same sibling group (explicit) or same page/section (fallback)
            if isSibling(chunk, candidate) {
                before.append(candidate)
            } else if !config.allowCrossPageExpansion {
                break // Stop at page/section boundary
            }
        }

        // Look forward for siblings
        for i in (currentIndex + 1) ..< min(sortedChunks.count, currentIndex + 1 + config.maxSiblingsPerSide) {
            let candidate = sortedChunks[i]

            if isSibling(chunk, candidate) {
                after.append(candidate)
            } else if !config.allowCrossPageExpansion {
                break
            }
        }

        return SiblingGroup(before: before, after: after)
    }

    /// Check if two chunks are siblings (same section/page)
    /// CRITICAL: Siblings must be topically related, not just physically adjacent!
    /// For a 542-page car manual, a chunk about "engine oil" should NOT pull in
    /// siblings about "driver assistance" just because they're on nearby pages.
    private func isSibling(_ a: DocumentChunk, _ b: DocumentChunk) -> Bool {
        // Must be same document
        guard a.documentId == b.documentId else { return false }

        // Check explicit sibling group ID first (most reliable)
        if let groupA = a.metadata.siblingGroupId, let groupB = b.metadata.siblingGroupId {
            return groupA == groupB
        }

        // STRICT requirement: Same section title (if available)
        // This prevents pulling chunks about "Driver Assistance" when query is about "Engine Oil"
        let sameSection = a.metadata.sectionTitle == b.metadata.sectionTitle &&
                          a.metadata.sectionTitle != nil

        // Same page is a secondary signal but NOT sufficient alone
        let samePage = a.metadata.pageNumber == b.metadata.pageNumber

        // If we have section titles, REQUIRE same section (even if same page)
        // A page can have multiple topics (e.g., end of "Engine Oil" section + start of "Transmission")
        if a.metadata.sectionTitle != nil || b.metadata.sectionTitle != nil {
            return sameSection
        }

        // If we only have page numbers (no sections), require same page AND close chunk index
        if a.metadata.pageNumber != nil || b.metadata.pageNumber != nil {
            // Must be same page AND within 2 chunks of each other
            let indexDistance = abs(a.metadata.chunkIndex - b.metadata.chunkIndex)
            return samePage && indexDistance <= 2
        }

        // Fallback: very strict chunk index proximity (adjacent chunks only)
        let indexDistance = abs(a.metadata.chunkIndex - b.metadata.chunkIndex)
        return indexDistance <= 1
    }

    /// Estimate token count from text (rough: ~4 chars per token)
    private func estimateTokens(_ text: String) -> Int {
        return max(1, text.count / 4)
    }

    // MARK: - Utility: Compute Sibling Group ID During Ingestion

    /// Generate a sibling group ID for a chunk during ingestion.
    /// Call this in SemanticChunker when creating chunks.
    static func computeSiblingGroupId(
        documentId: UUID,
        pageNumber: Int?,
        sectionTitle: String?
    ) -> String {
        var components = [documentId.uuidString]

        if let page = pageNumber {
            components.append("p\(page)")
        }

        if let section = sectionTitle {
            // Normalize section title
            let normalized = section.lowercased()
                .replacingOccurrences(of: " ", with: "_")
                .prefix(50)
            components.append(String(normalized))
        }

        return components.joined(separator: "-")
    }
}
