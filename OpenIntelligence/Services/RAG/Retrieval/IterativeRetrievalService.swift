//
//  IterativeRetrievalService.swift
//  OpenIntelligence
//
//  Multi-pass retrieval with self-correction for improved answer quality.
//
//  The idea: Instead of one-shot retrieval, we:
//  1. Retrieve initial chunks
//  2. Generate a preliminary answer
//  3. Assess if we have enough evidence
//  4. If not, refine the query and retrieve more
//  5. Repeat until confident or max iterations reached
//

import Foundation

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Result of a single retrieval iteration
struct RetrievalIteration: Sendable {
    let iteration: Int
    let query: String
    let chunks: [RetrievedChunk]
    let confidence: Float
    let needsMore: Bool
    let refinedQuery: String?
}

/// Final result of iterative retrieval
struct IterativeRetrievalResult: Sendable {
    /// All unique chunks collected across iterations
    let allChunks: [RetrievedChunk]

    /// The final, merged context
    let mergedContext: String

    /// Number of iterations performed
    let iterations: Int

    /// Final confidence score
    let confidence: Float

    /// Queries used (original + refined)
    let queriesUsed: [String]

    /// Whether we hit max iterations without full confidence
    let hitMaxIterations: Bool

    /// Total retrieval time across all iterations
    let totalTime: TimeInterval
}

/// Configuration for iterative retrieval
struct IterativeRetrievalConfig: Sendable {
    /// Maximum number of retrieval iterations
    let maxIterations: Int

    /// Minimum confidence to stop iterating
    let confidenceThreshold: Float

    /// Minimum number of chunks before considering complete
    let minChunks: Int

    /// Whether to use LLM for query refinement
    let useLLMRefinement: Bool

    nonisolated static let `default` = IterativeRetrievalConfig(
        maxIterations: 3,
        confidenceThreshold: 0.65,
        minChunks: 5,
        useLLMRefinement: true
    )

    nonisolated static let fast = IterativeRetrievalConfig(
        maxIterations: 2,
        confidenceThreshold: 0.5,
        minChunks: 3,
        useLLMRefinement: false
    )

    nonisolated static let thorough = IterativeRetrievalConfig(
        maxIterations: 4,
        confidenceThreshold: 0.75,
        minChunks: 8,
        useLLMRefinement: true
    )
}

/// Service for multi-pass retrieval with self-correction.
///
/// This implements a "retrieve-read-refine" loop:
/// 1. Initial retrieval based on user query
/// 2. Quick assessment of retrieved chunks
/// 3. If insufficient, generate a refined query
/// 4. Retrieve more with refined query
/// 5. Merge and deduplicate results
final class IterativeRetrievalService: @unchecked Sendable {
    // MARK: - Dependencies

    private let hybridSearchFactory: (VectorDatabase) -> HybridSearchService
    private var ragEngine: RAGEngine { RAGEngine.shared }
    private let embeddingService: EmbeddingService

    #if canImport(FoundationModels)
        @available(iOS 26.0, *)
        private var refinementSession: LanguageModelSession?
    #endif

    // MARK: - Initialization

    init(
        hybridSearchFactory: @escaping (VectorDatabase) -> HybridSearchService = { db in
            HybridSearchService(vectorDatabase: db, vectorWeight: 0.5, keywordWeight: 0.5)
        },
        embeddingService: EmbeddingService
    ) {
        self.hybridSearchFactory = hybridSearchFactory
        self.embeddingService = embeddingService
    }

    // MARK: - Public API

    /// Performs iterative retrieval with self-correction.
    ///
    /// - Parameters:
    ///   - query: The user's query (or rewritten query)
    ///   - vectorDatabase: The vector database to search
    ///   - config: Iteration configuration
    ///   - topK: Number of chunks to retrieve per iteration
    ///   - cachedChunks: Optional pre-fetched chunks for lexical recall (avoids redundant allChunks calls)
    /// - Returns: Merged results from all iterations
    func retrieve(
        query: String,
        originalQuery: String? = nil,
        vectorDatabase: VectorDatabase,
        config: IterativeRetrievalConfig = .default,
        topK: Int = 10,
        cachedChunks: [DocumentChunk]? = nil,
        isOverviewQuery: Bool = false
    ) async throws -> IterativeRetrievalResult {
        let startTime = Date()
        var allChunks: [RetrievedChunk] = []
        var seenChunkIds = Set<UUID>()
        var queriesUsed: [String] = [query]
        var currentQuery = query
        var iterations = 0
        var finalConfidence: Float = 0
        var hitMax = false
        let lexicalQuery = originalQuery ?? query

        Log.info("[IterativeRetrieval] Starting iterative retrieval (max \(config.maxIterations) iterations)", category: .retrieval)

        for i in 1 ... config.maxIterations {
            iterations = i

            // Generate embedding for current query
            let embedding = try await embeddingService.generateEmbedding(for: currentQuery)

            // Perform hybrid search (pass cached chunks to avoid redundant loading)
            let hybridSearch = hybridSearchFactory(vectorDatabase)
            let retrieved = try await hybridSearch.search(
                query: currentQuery,
                originalQuery: lexicalQuery,
                embedding: embedding,
                topK: topK,
                cachedChunks: cachedChunks,
                isOverviewQuery: isOverviewQuery
            )

            // Add new chunks (deduplicated)
            var newChunks: [RetrievedChunk] = []
            for chunk in retrieved {
                if seenChunkIds.insert(chunk.chunk.id).inserted {
                    newChunks.append(chunk)
                    allChunks.append(chunk)
                }
            }

            Log.debug(
                "[IterativeRetrieval] Iteration \(i): retrieved \(retrieved.count), new \(newChunks.count), total \(allChunks.count)",
                category: .retrieval
            )

            // Assess confidence based on:
            // 1. Number of chunks
            // 2. Similarity scores
            // 3. Diversity of sources
            let assessment = assessConfidence(
                chunks: allChunks,
                minChunks: config.minChunks,
                threshold: config.confidenceThreshold
            )

            finalConfidence = assessment.confidence

            // Check if we have enough
            if assessment.confidence >= config.confidenceThreshold &&
                allChunks.count >= config.minChunks
            {
                Log.info(
                    "[IterativeRetrieval] Sufficient confidence (\(String(format: "%.2f", assessment.confidence))) after \(i) iteration(s)",
                    category: .retrieval
                )
                break
            }

            // Check if we're at max iterations
            if i == config.maxIterations {
                hitMax = true
                Log.warning(
                    "[IterativeRetrieval] Hit max iterations with confidence \(String(format: "%.2f", assessment.confidence))",
                    category: .retrieval
                )
                break
            }

            // Generate refined query for next iteration
            if config.useLLMRefinement {
                do {
                    currentQuery = try await refineQuery(
                        originalQuery: query,
                        previousQuery: currentQuery,
                        retrievedChunks: allChunks,
                        gaps: assessment.gaps
                    )
                    queriesUsed.append(currentQuery)
                    Log.debug("[IterativeRetrieval] Refined query: \(currentQuery)", category: .retrieval)
                } catch {
                    // Fall back to keyword expansion
                    currentQuery = expandQueryWithKeywords(query, chunks: allChunks)
                    queriesUsed.append(currentQuery)
                }
            } else {
                // Simple keyword expansion without LLM
                currentQuery = expandQueryWithKeywords(query, chunks: allChunks)
                queriesUsed.append(currentQuery)
            }
        }

        // Re-rank all collected chunks
        let reranked = await ragEngine.rerank(
            chunks: allChunks,
            query: query,
            topK: min(allChunks.count, topK * 2)
        )

        // Build merged context
        let mergedContext = buildMergedContext(from: reranked)

        let totalTime = Date().timeIntervalSince(startTime)

        Log.info(
            "[IterativeRetrieval] Complete: \(iterations) iterations, \(reranked.count) chunks, confidence \(String(format: "%.2f", finalConfidence)) in \(String(format: "%.2f", totalTime))s",
            category: .retrieval
        )

        return IterativeRetrievalResult(
            allChunks: reranked,
            mergedContext: mergedContext,
            iterations: iterations,
            confidence: finalConfidence,
            queriesUsed: queriesUsed,
            hitMaxIterations: hitMax,
            totalTime: totalTime
        )
    }

    // MARK: - Confidence Assessment

    private struct ConfidenceAssessment {
        let confidence: Float
        let gaps: [String]
    }

    private func assessConfidence(
        chunks: [RetrievedChunk],
        minChunks: Int,
        threshold _: Float
    ) -> ConfidenceAssessment {
        guard !chunks.isEmpty else {
            return ConfidenceAssessment(confidence: 0, gaps: ["No chunks retrieved"])
        }

        var score: Float = 0
        var gaps: [String] = []

        // Factor 1: Chunk count (0-0.3)
        let countScore = min(Float(chunks.count) / Float(minChunks * 2), 1.0) * 0.3
        score += countScore
        if chunks.count < minChunks {
            gaps.append("Need more source documents")
        }

        // Factor 2: Top similarity scores (0-0.4)
        let topSims = chunks.prefix(5).map { $0.similarityScore }
        let avgTopSim = topSims.isEmpty ? 0 : topSims.reduce(0, +) / Float(topSims.count)
        let simScore = min(avgTopSim / 0.8, 1.0) * 0.4
        score += simScore
        if avgTopSim < 0.5 {
            gaps.append("Low semantic relevance")
        }

        // Factor 3: Source diversity (0-0.3)
        let uniqueSources = Set(chunks.compactMap { $0.sourceDocument }).count
        let diversityScore = min(Float(uniqueSources) / 3.0, 1.0) * 0.3
        score += diversityScore
        if uniqueSources < 2 {
            gaps.append("Single source - need corroboration")
        }

        return ConfidenceAssessment(confidence: score, gaps: gaps)
    }

    // MARK: - Query Refinement

    @MainActor
    private func refineQuery(
        originalQuery: String,
        previousQuery: String,
        retrievedChunks: [RetrievedChunk],
        gaps: [String]
    ) async throws -> String {
        #if canImport(FoundationModels)
            guard #available(iOS 26.0, *) else {
                throw IterativeRetrievalError.refinementUnavailable
            }

            guard SystemLanguageModel.default.isAvailable else {
                throw IterativeRetrievalError.refinementUnavailable
            }

            if refinementSession == nil {
                // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
                // Every service that used the bare initialiser failed deterministically with
                // ParsingError / "Session ended without producing a response", while every path built
                // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
                // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
                // retrieved chunks, which rules out content, guardrails, context size and token caps.
                // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
                // these responses, consistent with a session that never received its model assets.
                refinementSession = LanguageModelSession(
                    model: SystemLanguageModel.default,
                    instructions: Instructions("You refine search queries. Reply with the query only.")
                )
            }

            // Extract key terms from retrieved chunks to understand what we found
            let foundTerms = extractKeyTerms(from: retrievedChunks)

            let prompt = """
            I need to refine a search query to find more relevant information.

            Original question: "\(originalQuery)"
            Last search query: "\(previousQuery)"

            What we found so far (key terms): \(foundTerms.prefix(10).joined(separator: ", "))

            Gaps to address: \(gaps.joined(separator: "; "))

            Generate a refined search query that:
            1. Keeps the original intent
            2. Uses different keywords/phrasing
            3. Might find complementary information
            4. Is concise (under 30 words)

            Output ONLY the refined query, no explanation:
            """

            guard let session = refinementSession else {
                throw IterativeRetrievalError.invalidRefinement
            }
            let response = try await session.respond(to: prompt)
            let refined = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")

            guard refined.count > 5, refined.count < 200 else {
                throw IterativeRetrievalError.invalidRefinement
            }

            return refined
        #else
            throw IterativeRetrievalError.refinementUnavailable
        #endif
    }

    private func expandQueryWithKeywords(_ query: String, chunks: [RetrievedChunk]) -> String {
        // Extract keywords from chunks we've seen
        let keywords = extractKeyTerms(from: chunks)

        // Find keywords not in the original query
        let queryLower = query.lowercased()
        let newKeywords = keywords.filter { !queryLower.contains($0.lowercased()) }

        // Add top 3 new keywords to query
        let additions = newKeywords.prefix(3).joined(separator: " ")
        return "\(query) \(additions)"
    }

    private func extractKeyTerms(from chunks: [RetrievedChunk]) -> [String] {
        var termFreq: [String: Int] = [:]

        for chunk in chunks {
            for keyword in chunk.chunk.metadata.keywords {
                termFreq[keyword.lowercased(), default: 0] += 1
            }
        }

        return termFreq.sorted { $0.value > $1.value }.map { $0.key }
    }

    // MARK: - Context Building

    private func buildMergedContext(from chunks: [RetrievedChunk]) -> String {
        var contextParts: [String] = []

        for (i, chunk) in chunks.prefix(15).enumerated() {
            var header = "[\(i + 1)]"
            if !chunk.sourceDocument.isEmpty {
                header += " \(chunk.sourceDocument)"
            }
            if let page = chunk.pageNumber {
                header += " (p. \(page))"
            }

            contextParts.append("\(header)\n\(chunk.chunk.content)")
        }

        return contextParts.joined(separator: "\n\n---\n\n")
    }
}

// MARK: - Errors

enum IterativeRetrievalError: Error, LocalizedError {
    case refinementUnavailable
    case invalidRefinement
    case noChunksFound

    var errorDescription: String? {
        switch self {
        case .refinementUnavailable:
            return "LLM query refinement is not available"
        case .invalidRefinement:
            return "Query refinement produced invalid output"
        case .noChunksFound:
            return "No chunks found after all iterations"
        }
    }
}
