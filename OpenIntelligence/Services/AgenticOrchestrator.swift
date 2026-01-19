//
//  AgenticOrchestrator.swift
//  OpenIntelligence
//
//  Retrieval-first agentic reasoning that escalates based on confidence.
//  Key insight: Don't decide complexity upfront - let retrieval results guide the pipeline.
//

import Foundation

/// Represents one step in the agentic reasoning loop
struct ThinkingStep: Identifiable, Sendable {
    let id: UUID
    let type: StepType
    let input: String
    let output: String
    let tokensUsed: Int
    let duration: TimeInterval
    let timestamp: Date
    /// Live confidence level (0-1) for Maximum mode progress tracking
    var confidence: Float? = nil

    enum StepType: String, Sendable {
        case planning = "🎯 Planning approach"
        case searching = "🔍 Searching documents"
        case expanding = "🕸️ Expanding context"
        case analyzing = "🧠 Analyzing results"
        case synthesizing = "✨ Synthesizing answer"
        case refining = "🔧 Refining response"
        case reformulating = "🔄 Trying different angle"

        /// Display name for UI
        var displayName: String { rawValue }

        /// Map to ThinkingEvent.Kind for UI integration
        var thinkingKind: ThinkingEvent.Kind {
            switch self {
            case .planning: return .planning
            case .searching, .reformulating, .expanding: return .retrieval
            case .analyzing: return .rerank
            case .synthesizing, .refining: return .generation
            }
        }
    }
}

/// Configuration for the agentic loop
struct AgenticConfig: Sendable {
    /// Maximum thinking steps before forcing synthesis (use Int.max for "unlimited")
    let maxSteps: Int

    /// Maximum total tokens across all steps (use Int.max for "unlimited")
    let maxTotalTokens: Int

    /// Whether to stream intermediate results
    let streamIntermediateResults: Bool

    /// Minimum confidence threshold to stop early (high = good enough to answer)
    let confidenceThreshold: Float

    /// Similarity threshold below which we escalate to deeper retrieval
    let escalationThreshold: Float

    /// Whether this is an "unlimited" configuration (keep going until confident)
    var isUnlimited: Bool {
        maxSteps >= 50 // Practical "unlimited" - 50+ steps is extreme
    }

    nonisolated static let defaultConfig = AgenticConfig(
        maxSteps: 5,
        maxTotalTokens: 16000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.85,
        escalationThreshold: 0.35 // If top result < 35% similarity, try harder
    )

    nonisolated static let fast = AgenticConfig(
        maxSteps: 2,
        maxTotalTokens: 8000,
        streamIntermediateResults: false,
        confidenceThreshold: 0.7,
        escalationThreshold: 0.25
    )

    nonisolated static let thorough = AgenticConfig(
        maxSteps: 8,
        maxTotalTokens: 32000,
        streamIntermediateResults: true,
        confidenceThreshold: 0.95,
        escalationThreshold: 0.45 // Higher bar = more likely to escalate
    )

    /// Unlimited Deep Think - keeps reasoning until 98% confident or thermal limit
    /// Since Neural Engine uses disk-backed weights (not RAM), we can go much deeper
    /// Only thermal throttling and user patience are the real limits
    nonisolated static let unlimited = AgenticConfig(
        maxSteps: 50, // Realistically 5-15 minutes - thermal will stop us first
            maxTotalTokens: 200_000, // 50 sessions × 4K = 200K+ effective tokens
        streamIntermediateResults: true,
        confidenceThreshold: 0.98, // Only stop when VERY confident
        escalationThreshold: 0.50 // Aggressive escalation - always try harder
    )
}

/// Result of the agentic reasoning loop
struct AgenticResult: Sendable {
    let finalAnswer: String
    let steps: [ThinkingStep]
    let totalTokens: Int
    let totalDuration: TimeInterval
    let confidence: Float
    let sourcesUsed: Int
    /// All chunks retrieved across tool calls (for UnifiedMetricsBar)
    let retrievedChunks: [RetrievedChunk]

    /// Compressed summary of the reasoning chain (for UI display)
    var reasoningSummary: String {
        steps.map { "• \($0.type.rawValue): \($0.output.prefix(100))..." }.joined(separator: "\n")
    }
}

/// Retrieval-first agentic orchestrator
/// Key principle: Retrieve FIRST, then decide if escalation is needed based on results
@MainActor
final class AgenticOrchestrator: Sendable {
    private weak var ragService: RAGService?
    private let config: AgenticConfig

    /// Common stop words to exclude from repetition detection
    /// These inflate overlap ratios without indicating actual semantic repetition
    private static let commonStopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "from", "have", "has", "had",
        "are", "was", "were", "been", "being", "which", "their", "there", "they",
        "will", "would", "could", "should", "about", "into", "through", "during",
        "before", "after", "above", "below", "between", "under", "over", "such",
        "than", "then", "these", "those", "some", "more", "most", "other", "only",
        "also", "just", "first", "last", "very", "much", "many", "each", "every",
        "both", "either", "neither", "while", "where", "when", "what", "who", "how",
        "video", "games", "gaming", "study", "research", "found", "shows", "based",
        "according", "evidence", "results", "effects", "impact", "review", "analysis",
    ]

    init(ragService: RAGService, config: AgenticConfig = .defaultConfig) {
        self.ragService = ragService
        self.config = config
    }

    /// Get the appropriate ReasoningChainConfig based on AgenticConfig
    /// Uses unlimited reasoning chain when AgenticConfig.isUnlimited is true
    private var reasoningChainConfig: ReasoningChainConfig {
        if config.isUnlimited {
            Log.info("[Agentic] Using UNLIMITED reasoning chain (up to 50 sessions until 98% confident)", category: .llm)
            return .unlimited
        }
        // Map maxSteps to appropriate chain config
        if config.maxSteps >= 8 {
            return .deep
        } else if config.maxSteps >= 5 {
            return .standard
        } else {
            return .light
        }
    }

    /// Execute a retrieval-first reasoning loop
    ///
    /// STRATEGY (Enhanced with Self-RAG and Speculative RAG):
    /// 0. Self-RAG check: Does this query even need retrieval?
    /// 1. Initial retrieval with the ORIGINAL query (no decomposition)
    /// 2. EVALUATE results - are they good enough?
    /// 3. If yes → synthesize immediately
    /// 4. If no → Speculative RAG: generate multiple candidates, verify each
    /// 5. If still low → escalate: reformulate query OR decompose for multi-faceted questions
    /// 6. Final synthesis with accumulated context
    func execute(
        query: String,
        initialContext: String = "",
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 0: Self-RAG Check - Does this query need retrieval?
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (needsRetrieval, _) = try await decideIfRetrievalNeeded(query: query, ragService: ragService)

        if !needsRetrieval {
            Log.info("[Agentic] Self-RAG: Query can be answered without document retrieval", category: .llm)
            // Use Self-RAG path for simple queries
            return try await executeSelfRAG(query: query, onStep: onStep)
        }

        Log.info("[Agentic] Self-RAG: Document retrieval needed", category: .llm)

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        let startTime = Date()
        var allRetrievedChunks: [RetrievedChunk] = []

        // Per-step token tracking for detailed logging
        var stepTokenLog: [(step: String, tokens: Int, cumulative: Int)] = []
        func logStepTokens(_ stepName: String, _ tokens: Int) {
            totalTokens += tokens
            stepTokenLog.append((stepName, tokens, totalTokens))
            Log.debug("[Deep Think] \(stepName): +\(tokens) tokens (total: \(totalTokens))", category: .llm)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 0: Announce reasoning strategy (visible "hmm" moment)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let planningStep = ThinkingStep(
            id: UUID(),
            type: .planning,
            input: query,
            output: "Analyzing query to determine best search strategy...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date()
        )
        steps.append(planningStep)
        await onStep?(planningStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Initial Retrieval (with ORIGINAL query - no decomposition)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Agentic] Step 1: Initial retrieval with original query", category: .llm)

        let (initialSearchStep, initialChunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService
        )
        steps.append(initialSearchStep)
        logStepTokens("Initial Search", initialSearchStep.tokensUsed)
        allRetrievedChunks.append(contentsOf: initialChunks)
        await onStep?(initialSearchStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Evaluate Retrieval Quality (visible "hmm" moment)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        var retrievalQuality = evaluateRetrievalQuality(chunks: initialChunks, query: query)
        Log.info("[Agentic] Retrieval quality: \(retrievalQuality.description)", category: .llm)

        // Emit evaluation step so user sees the reasoning
        let evalStep = ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Evaluating \(initialChunks.count) results",
            output: "Confidence: \(retrievalQuality.description) (\(String(format: "%.0f%%", retrievalQuality.confidenceScore * 100)))",
            tokensUsed: 0,
            duration: 0.05,
            timestamp: Date()
        )
        steps.append(evalStep)
        await onStep?(evalStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2.5: Graph Expansion (GraphRAG-lite)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if retrievalQuality == .moderate || retrievalQuality == .low {
            let (expansionStep, expandedChunks) = try await executeGraphExpansion(
                query: query,
                initialChunks: initialChunks,
                ragService: ragService
            )

            if !expansionStep.output.isEmpty {
                steps.append(expansionStep)
                logStepTokens("Graph Expansion", expansionStep.tokensUsed)
                await onStep?(expansionStep)
            }

            if !expandedChunks.isEmpty {
                for chunk in expandedChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }
                retrievalQuality = evaluateRetrievalQuality(chunks: allRetrievedChunks, query: query)
                Log.info("[Agentic] Graph expansion updated quality: \(retrievalQuality.description)", category: .llm)
            }
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // DECISION POINT: Based on retrieval quality
        // Use REASONING CHAIN for excellent/good to multiply effective context
        // MAXIMUM MODE: Use MULTI-CHAIN for parallel processing across document clusters
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        switch retrievalQuality {
        case .excellent:
            // CRITICAL: Sort chunks by relevance before passing to reasoning chain
            // Merged chunks from multiple sources may not be in order
            let sortedChunks = allRetrievedChunks.sorted { $0.similarityScore > $1.similarityScore }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // MAXIMUM MODE: Use multi-chain for parallel cluster processing
            // This breaks the 4096 token ceiling by running multiple parallel chains
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if config.isUnlimited {
                Log.info("[Agentic] MAXIMUM MODE: Using multi-chain parallel reasoning", category: .llm)

                // First, gather ALL chunks from the library for comprehensive analysis
                let allChunksForMultiChain = try await gatherAllRelevantChunks(
                    query: query,
                    initialChunks: sortedChunks,
                    ragService: ragService
                )

                let multiChainResult = try await executeMultiChainReasoning(
                    query: query,
                    allChunks: allChunksForMultiChain,
                    config: .maximum,
                    onStep: onStep
                )

                // Convert cluster insights to thinking steps - include ALL session insights
                for clusterInsight in multiChainResult.clusterInsights {
                    // Add individual session insights (the detailed reasoning)
                    for (sessionIdx, sessionInsight) in clusterInsight.chainInsights.enumerated() {
                        let sessionStep = ThinkingStep(
                            id: UUID(),
                            type: sessionIdx == clusterInsight.chainInsights.count - 1 ? .synthesizing : .analyzing,
                            input: "[\(clusterInsight.clusterName)] Session \(sessionIdx + 1)",
                            output: sessionInsight,
                            tokensUsed: clusterInsight.tokensUsed / max(1, clusterInsight.sessionsRun),
                            duration: multiChainResult.totalDuration / Double(multiChainResult.totalSessions),
                            timestamp: Date()
                        )
                        steps.append(sessionStep)
                    }
                }

                totalTokens += multiChainResult.totalTokens
                logStepTokens("Multi-Chain (\(multiChainResult.totalSessions) sessions)", multiChainResult.totalTokens)

                return AgenticResult(
                    finalAnswer: multiChainResult.finalAnswer,
                    steps: steps,
                    totalTokens: totalTokens,
                    totalDuration: Date().timeIntervalSince(startTime),
                    confidence: multiChainResult.confidence,
                    sourcesUsed: allChunksForMultiChain.count,
                    retrievedChunks: allChunksForMultiChain
                )
            }

            // Standard mode: Single reasoning chain
            Log.info("[Agentic] Excellent retrieval → reasoning chain", category: .llm)

            let chainConfig = reasoningChainConfig
            Log.info("[Agentic] Using \(chainConfig.sessionCount)-session reasoning chain", category: .llm)

            let chainResult = try await executeReasoningChain(
                query: query,
                chunks: sortedChunks,
                config: chainConfig,
                onStep: onStep
            )

            // Convert chain steps to thinking steps
            for (idx, insight) in chainResult.chainInsights.enumerated() {
                let chainStep = ThinkingStep(
                    id: UUID(),
                    type: idx == chainResult.chainInsights.count - 1 ? .synthesizing : .analyzing,
                    input: "Chain session \(idx + 1)",
                    output: insight,
                    tokensUsed: chainResult.totalTokens / chainResult.sessionCount,
                    duration: 0.5,
                    timestamp: Date()
                )
                steps.append(chainStep)
            }

            totalTokens += chainResult.totalTokens
            logStepTokens("Reasoning Chain (\(chainResult.sessionCount) sessions)", chainResult.totalTokens)

            return AgenticResult(
                finalAnswer: chainResult.finalAnswer,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: chainResult.confidence,
                sourcesUsed: allRetrievedChunks.count,
                retrievedChunks: allRetrievedChunks
            )

        case .good:
            // GOOD CONFIDENCE: Use reasoning chain with additional retrieval
            Log.info("[Agentic] Good confidence → reasoning chain with refinement", category: .llm)

            // Try to refine the query based on what we found
            if let refinedQuery = try? await reformulateQuery(
                originalQuery: query,
                retrievedContext: initialSearchStep.output,
                ragService: ragService
            ), refinedQuery != query {
                let (refinedStep, refinedChunks) = try await executeSearchStepWithChunks(
                    subQuery: refinedQuery,
                    ragService: ragService
                )
                steps.append(refinedStep)
                logStepTokens("Refined Search", refinedStep.tokensUsed)

                // Merge unique chunks from refined search
                for chunk in refinedChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }
                Log.debug("[Agentic] Merged to \(allRetrievedChunks.count) total chunks", category: .retrieval)

                await onStep?(refinedStep)
            }


            // CRITICAL: Sort chunks by relevance before passing to reasoning chain
            // Merged chunks from multiple sources may not be in order
            let sortedChunks = allRetrievedChunks.sorted { $0.similarityScore > $1.similarityScore }

            // Use reasoning chain for multi-session deep thinking
            let chainConfig = reasoningChainConfig
            Log.info("[Agentic] Using \(chainConfig.sessionCount)-session reasoning chain", category: .llm)

            let chainResult = try await executeReasoningChain(
                query: query,
                chunks: sortedChunks,
                config: chainConfig,
                onStep: onStep
            )

            // Add chain insights to steps
            for (idx, insight) in chainResult.chainInsights.enumerated() {
                let chainStep = ThinkingStep(
                    id: UUID(),
                    type: idx == chainResult.chainInsights.count - 1 ? .synthesizing : .analyzing,
                    input: "Chain session \(idx + 1)",
                    output: insight,
                    tokensUsed: chainResult.totalTokens / chainResult.sessionCount,
                    duration: 0.5,
                    timestamp: Date()
                )
                steps.append(chainStep)
            }

            totalTokens += chainResult.totalTokens
            logStepTokens("Reasoning Chain (Good)", chainResult.totalTokens)

            return AgenticResult(
                finalAnswer: chainResult.finalAnswer,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: chainResult.confidence,
                sourcesUsed: allRetrievedChunks.count,
                retrievedChunks: allRetrievedChunks
            )

        case .moderate:
            // MEDIUM CONFIDENCE: We have usable results! Try to improve them, but don't give up
            Log.info("[Agentic] Moderate confidence → trying to improve retrieval", category: .llm)

            // First, try a HyDE-style reformulation to find better matches
            let reformulatedQuery = try await reformulateQuery(
                originalQuery: query,
                retrievedContext: initialSearchStep.output,
                ragService: ragService
            )

            if let reformulatedQuery = reformulatedQuery, reformulatedQuery != query {
                let reformulationStep = ThinkingStep(
                    id: UUID(),
                    type: .reformulating,
                    input: query,
                    output: "Reformulated: \(reformulatedQuery)",
                    tokensUsed: 20,
                    duration: 0.1,
                    timestamp: Date()
                )
                steps.append(reformulationStep)
                await onStep?(reformulationStep)

                // Search again with reformulated query
                let (reformulatedSearchStep, reformulatedChunks) = try await executeSearchStepWithChunks(
                    subQuery: reformulatedQuery,
                    ragService: ragService
                )
                steps.append(reformulatedSearchStep)
                logStepTokens("Reformulated Search", reformulatedSearchStep.tokensUsed)

                // Merge chunks (dedupe)
                for chunk in reformulatedChunks {
                    if !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                        allRetrievedChunks.append(chunk)
                    }
                }
                await onStep?(reformulatedSearchStep)

                // Re-evaluate
                let newQuality = evaluateRetrievalQuality(chunks: allRetrievedChunks, query: query)
                if newQuality.confidenceScore > retrievalQuality.confidenceScore {
                    Log.info("[Agentic] Reformulation improved results → synthesizing", category: .llm)

                    // Combine both search results
                    let combinedResults = initialSearchStep.output + "\n\n---\n\n" + reformulatedSearchStep.output

                    let synthesisStep = try await executeDirectSynthesis(
                        query: query,
                        searchResults: combinedResults,
                        ragService: ragService
                    )
                    steps.append(synthesisStep)
                    logStepTokens("Synthesis (Improved)", synthesisStep.tokensUsed)
                    await onStep?(synthesisStep)

                    return AgenticResult(
                        finalAnswer: synthesisStep.output,
                        steps: steps,
                        totalTokens: totalTokens,
                        totalDuration: Date().timeIntervalSince(startTime),
                        confidence: newQuality.confidenceScore,
                        sourcesUsed: allRetrievedChunks.count,
                        retrievedChunks: allRetrievedChunks
                    )
                }
            }

            // Reformulation didn't dramatically improve - but moderate is still USABLE!
            // Synthesize with what we have rather than giving up
            Log.info("[Agentic] Moderate confidence → synthesizing with available context", category: .llm)

            let combinedResults = initialSearchStep.output
            let synthesisStep = try await executeDirectSynthesis(
                query: query,
                searchResults: combinedResults,
                ragService: ragService
            )
            steps.append(synthesisStep)
            logStepTokens("Synthesis (Moderate)", synthesisStep.tokensUsed)
            await onStep?(synthesisStep)

            return AgenticResult(
                finalAnswer: synthesisStep.output,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: max(retrievalQuality.confidenceScore, 0.55), // Moderate is at least 55% useful
                sourcesUsed: allRetrievedChunks.count,
                retrievedChunks: allRetrievedChunks
            )

        case .low:
            // LOW CONFIDENCE: Use Speculative RAG for multi-path verification
            Log.info("[Agentic] Low confidence → using Speculative RAG for verification", category: .llm)

            // Speculative RAG: Generate multiple candidates, verify each against sources
            // This catches hallucinations through multi-path verification
            let speculativeResult = try await executeSpeculativeRAG(
                query: query,
                candidateCount: 3,
                onStep: onStep
            )

            // Only accept Speculative RAG if it meets the config's confidence threshold
            // Previously used 0.6 which was too low - answers were "grounded" but incomplete
            // Now we use the config threshold (e.g., 0.95 for thorough, 0.98 for unlimited)
            let acceptanceThreshold = max(config.confidenceThreshold - 0.1, 0.75)

            // Also check for query complexity - "what does X do" questions need exhaustive answers
            let isExhaustiveQuery = queryRequiresExhaustiveAnswer(query)
            let effectiveThreshold = isExhaustiveQuery ? max(acceptanceThreshold, 0.90) : acceptanceThreshold

            if speculativeResult.confidence >= effectiveThreshold {
                Log.info("[Agentic] Speculative RAG succeeded with \(String(format: "%.0f%%", speculativeResult.confidence * 100)) confidence (threshold: \(String(format: "%.0f%%", effectiveThreshold * 100)))", category: .llm)
                return speculativeResult
            }

            // Speculative RAG didn't meet threshold - fall back to deeper retrieval
            Log.info("[Agentic] Speculative RAG \(String(format: "%.0f%%", speculativeResult.confidence * 100)) < threshold \(String(format: "%.0f%%", effectiveThreshold * 100)) → escalating to deeper retrieval", category: .llm)

            // Try decomposition if it makes sense, otherwise do recursive search
            if queryBenefitsFromDecomposition(query) {
                return try await executeDecomposedPipeline(
                    query: query,
                    initialChunks: allRetrievedChunks,
                    initialSearchOutput: initialSearchStep.output,
                    steps: &steps,
                    totalTokens: &totalTokens,
                    ragService: ragService,
                    onStep: onStep,
                    startTime: startTime
                )
            } else {
                // Single-topic query - try harder with multiple reformulations
                Log.info("[Agentic] Single-topic, low confidence → trying alternative search strategies", category: .llm)

                // Try a broader search with lower threshold
                let broaderChunks = try await ragService.searchDocumentsRaw(
                    query: query,
                    topK: 20,
                    minSimilarity: 0.08 // Much lower threshold
                )

                if !broaderChunks.isEmpty {
                    for chunk in broaderChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                        allRetrievedChunks.append(chunk)
                    }
                }

                // Format expanded results
                var expandedResults = initialSearchStep.output
                if broaderChunks.count > initialChunks.count {
                    expandedResults = "Expanded search found \(broaderChunks.count) chunks:\n\n"
                    for (index, chunk) in broaderChunks.prefix(8).enumerated() {
                        expandedResults += "[\(index + 1)] From \(chunk.sourceDocument):\n"
                        let content = (chunk.chunk.parentContent ?? chunk.chunk.content).prefix(500)
                        expandedResults += String(content) + "\n\n"
                    }
                }

                // Synthesize with everything we found
                let synthesisStep = try await executeDirectSynthesis(
                    query: query,
                    searchResults: expandedResults,
                    ragService: ragService
                )
                steps.append(synthesisStep)
                totalTokens += synthesisStep.tokensUsed
                await onStep?(synthesisStep)

                return AgenticResult(
                    finalAnswer: synthesisStep.output,
                    steps: steps,
                    totalTokens: totalTokens,
                    totalDuration: Date().timeIntervalSince(startTime),
                    confidence: 0.4, // Low but we tried our best
                    sourcesUsed: allRetrievedChunks.count,
                    retrievedChunks: allRetrievedChunks
                )
            }
        }
    }

    // MARK: - Retrieval Quality Evaluation

    private enum RetrievalQuality {
        case excellent // Top results > 0.5 similarity, good coverage
        case good // Top results > 0.35 similarity
        case moderate // Top results 0.2-0.35 similarity
        case low // Top results < 0.2 similarity or no results

        var confidenceScore: Float {
            switch self {
            case .excellent: return 0.9
            case .good: return 0.75
            case .moderate: return 0.5
            case .low: return 0.3
            }
        }

        var description: String {
            switch self {
            case .excellent: return "Excellent (>50% match)"
            case .good: return "Good (35-50% match)"
            case .moderate: return "Moderate (20-35% match)"
            case .low: return "Low (<20% match)"
            }
        }
    }

    /// Evaluate retrieval quality based on similarity scores and coverage
    /// NOTE: Semantic similarity scores are inherently lower than people expect.
    /// 0.15-0.25 is often "good enough" for useful retrieval - don't give up too early!
    private func evaluateRetrievalQuality(chunks: [RetrievedChunk], query: String) -> RetrievalQuality {
        guard !chunks.isEmpty else { return .low }

        let topScore = chunks.first?.similarityScore ?? 0
        let top3Avg = chunks.prefix(3).map { $0.similarityScore }.reduce(0, +) / Float(min(3, chunks.count))
        let top5Avg = chunks.prefix(5).map { $0.similarityScore }.reduce(0, +) / Float(min(5, chunks.count))

        // After re-ranking and MMR, scores are more meaningful:
        // - 0.35+ is excellent - confident match
        // - 0.20-0.35 is good - solid retrieval
        // - 0.12-0.20 is moderate - usable with caveats
        // - <0.12 is low - might need reformulation
        //
        // IMPORTANT: Don't short-circuit on "good" - the full pipeline makes Deep Think valuable
        if topScore > 0.45, top3Avg > 0.35 {
            return .excellent
        } else if topScore > 0.30, top3Avg > 0.22 {
            return .good
        } else if topScore > 0.15 || top5Avg > 0.12 {
            return .moderate
        } else {
            return .low
        }
    }

    /// Check if a query would benefit from decomposition
    /// Only true for genuinely multi-faceted questions, not just low-confidence single-topic
    private func queryBenefitsFromDecomposition(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Multi-faceted indicators
        let multiFacetedPatterns = [
            "compare", "contrast", "versus", " vs ",
            "pros and cons", "advantages and disadvantages",
            "all the ways", "everything about", "complete overview",
            "relationship between .* and",
            "how does .* affect .* and",
            " and also ", " as well as ", " in addition to ",
        ]

        for pattern in multiFacetedPatterns {
            if pattern.contains(".*") {
                if lowercased.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            } else if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Check if a query requires an exhaustive/comprehensive answer
    /// These are "what does X do" or "tell me everything about X" type questions
    /// where we need to find ALL relevant info, not just the first confident match
    private func queryRequiresExhaustiveAnswer(_ query: String) -> Bool {
        let lowercased = query.lowercased()

        // Patterns that indicate user wants a complete/comprehensive answer
        let exhaustivePatterns = [
            "what does .* do",
            "what happens when",
            "what can .* do",
            "tell me about",
            "explain .* to me",
            "how does .* work",
            "what are all",
            "list all",
            "everything about",
            "all the features",
            "all the functions",
            "capabilities of",
            "what is .* capable of",
            "describe .*",
            "full explanation",
            "complete overview",
        ]

        for pattern in exhaustivePatterns {
            if pattern.contains(".*") {
                if lowercased.range(of: pattern, options: .regularExpression) != nil {
                    return true
                }
            } else if lowercased.contains(pattern) {
                return true
            }
        }

        return false
    }

    /// Reformulate query based on what we found (or didn't find) in initial retrieval
    private func reformulateQuery(
        originalQuery: String,
        retrievedContext: String,
        ragService: RAGService
    ) async throws -> String? {
        let prompt = """
        You are helping improve a search query.The original query found some results, but they may not be ideal.

        Original query: \(originalQuery)

        Content found(excerpt):
            \(retrievedContext.prefix(800))

        Based on the vocabulary and terminology in the retrieved content, suggest ONE improved search query.
            IMPORTANT: The improved query must be about the SAME topic as the original query.
            Use key terms from the documents that relate to the original question.
            Output ONLY the new query phrase, nothing else .
        """

        let response = try await ragService.generateWithFreshSession(prompt: prompt, maxTokens: 128)
        let reformulated = response.text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate it's actually different and reasonable
        if reformulated.count > 10, reformulated.count < 200, reformulated != originalQuery {
            return reformulated
        }
        return nil
    }

    /// Direct synthesis when retrieval confidence is high - comprehensive answer
    /// Uses the SAME formatting and consent flow as Standard mode
    /// CRITICAL: Respects 4096 token limit for Apple Foundation Models
    private func executeDirectSynthesis(
        query: String,
        searchResults: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Truncate search results to fit in context budget
        // At 1.4 chars/token, 3500 chars ≈ 2500 tokens (safe for 4096 limit)
        let truncatedResults = String(searchResults.prefix(3500))

        // Use SHORT system prompt to maximize context budget
        let systemPrompt = """
        Answer using ONLY the provided excerpts [S1], [S2], etc.
        Rules: 1) Use ONLY excerpts 2) Cite sources [S1], [S2] 3) Be thorough
        """

        // Generate using the main RAGService pipeline which handles:
        // - PCC consent prompts
        // - Cloud transmission recording
        // - Proper execution context routing
        // Use conservative maxTokens to fit in 4096 window
        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: truncatedResults,
            systemPrompt: systemPrompt,
            maxTokens: 800 // Conservative to stay within 4096 total
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Comprehensive synthesis with full chunk context - like Standard mode
    /// This formats chunks properly and provides maximum context to the LLM
    /// Uses the SAME context formatting and system prompt as Standard mode
    /// CRITICAL: Respects 4096 token limit for Apple Foundation Models
    private func executeComprehensiveSynthesis(
        query: String,
        chunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Format chunks EXACTLY like Standard mode's assembleContext with [S1], [S2] notation
        var contextBuilder = ""
        let maxChunks = min(chunks.count, 10) // Conservative chunk count
        var usedChunks = 0

        // CRITICAL: Apple FM has 4096 token limit (both on-device AND PCC)
        // Token budget breakdown:
        //   - System prompt: ~150 tokens
        //   - Query: ~50 tokens
        //   - Context: ~2800 tokens max (safe buffer)
        //   - Output: ~1000 tokens (we ask for more but system caps it)
        //   - Safety margin: ~100 tokens
        // At 1.4 chars/token (Apple FM ratio), 2800 tokens ≈ 3920 chars
        let maxContextChars = 3500 // Conservative to avoid overflow

        // Target at least 3 chunks for diverse context
        let minChunksTarget = min(3, chunks.count)
        let headerOverhead = 30 // Approximate header + separator size
        let targetCharsPerChunk = max(400, (maxContextChars - (minChunksTarget * headerOverhead)) / minChunksTarget)

        for (index, chunk) in chunks.prefix(maxChunks).enumerated() {
            let fullText = (chunk.chunk.parentContent ?? chunk.chunk.content)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Calculate remaining budget
            let remainingBudget = maxContextChars - contextBuilder.count

            // Truncate if needed to fit more chunks
            let truncatedText: String
            if usedChunks < minChunksTarget - 1 && fullText.count > targetCharsPerChunk {
                truncatedText = truncateAtSentence(fullText, maxChars: targetCharsPerChunk)
            } else {
                truncatedText = fullText
            }

            // Match Standard mode's compact format: [S1], [S2], etc.
            let source = chunk.sourceDocument.isEmpty ? "" : URL(fileURLWithPath: chunk.sourceDocument).lastPathComponent
            let sourceRef = source.isEmpty ? "" : "(\(source)) "
            let block = "[S\(index + 1)] \(sourceRef)\(truncatedText)" + (index < maxChunks - 1 ? "\n---\n" : "")

            // Respect context budget - but force-fit truncated versions for minimum chunks
            if contextBuilder.count + block.count <= maxContextChars || usedChunks == 0 {
                contextBuilder += block
                usedChunks += 1
            } else if usedChunks < minChunksTarget && remainingBudget > 300 {
                // Force-fit a truncated version
                let forceTruncated = truncateAtSentence(truncatedText, maxChars: remainingBudget - headerOverhead - 20)
                if forceTruncated.count >= 150 {
                    let forceBlock = "[S\(index + 1)] \(sourceRef)\(forceTruncated)" + (index < maxChunks - 1 ? "\n---\n" : "")
                    contextBuilder += forceBlock
                    usedChunks += 1
                } else {
                    break
                }
            } else {
                break
            }
        }

        Log.info("[Deep Think] Using \(usedChunks) chunks, \(contextBuilder.count) chars", category: .llm)

        // Use the SAME system prompt structure as Standard mode (RAGService line ~4433)
        // Keep it SHORT to maximize context budget
        let systemPrompt = """
        Answer using the excerpts [S1], [S2], etc.
        Rules: 1) Use excerpts 2) Cite [S1], [S2] 3) Connect user terms to related concepts 4) Be thorough
        """

        // Generate using the main RAGService pipeline which handles:
        // - PCC consent prompts
        // - Cloud transmission recording
        // - Proper execution context routing
        // Use conservative maxTokens to fit in 4096 window
        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: contextBuilder,
            systemPrompt: systemPrompt,
            maxTokens: 800 // Conservative to stay within 4096 total
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Truncate text at a sentence boundary, preferring to keep complete sentences
    private func truncateAtSentence(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }

        let truncated = String(text.prefix(maxChars))

        // Find last sentence-ending punctuation
        let sentenceEnders: [Character] = [".", "!", "?"]
        if let lastSentenceEnd = truncated.lastIndex(where: { sentenceEnders.contains($0) }) {
            let endIndex = truncated.index(after: lastSentenceEnd)
            let result = String(truncated[..<endIndex])
            // Only use sentence boundary if we keep at least 60% of the truncated text
            if result.count >= maxChars * 6 / 10 {
                return result
            }
        }

        // Fall back to word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }

        return truncated + "…"
    }

    /// Honest synthesis when confidence is low - acknowledges limitations
    /// Uses proper consent flow for PCC
    private func executeHonestSynthesis(
        query: String,
        searchResults: String,
        confidence: RetrievalQuality,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Truncate to fit in 4096 token budget
        let truncatedResults = String(searchResults.prefix(3500))

        // Short system prompt to maximize context budget
        let systemPrompt = """
        Answer using excerpts. Cite [S1], [S2]. Explain what excerpts DO cover that might help.
        """

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: truncatedResults,
            systemPrompt: systemPrompt,
            maxTokens: 800
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Decomposed pipeline for genuinely multi-faceted questions
    private func executeDecomposedPipeline(
        query: String,
        initialChunks: [RetrievedChunk],
        initialSearchOutput: String,
        steps: inout [ThinkingStep],
        totalTokens: inout Int,
        ragService: RAGService,
        onStep: ((ThinkingStep) async -> Void)?,
        startTime: Date
    ) async throws -> AgenticResult {
        var allRetrievedChunks = initialChunks

        // Planning step to decompose
        let planningStep = try await executePlanningStep(query: query, ragService: ragService)
        steps.append(planningStep)
        totalTokens += planningStep.tokensUsed
        await onStep?(planningStep)

        let subQueries = parseSubQueries(from: planningStep.output)

        // Execute sub-queries
        var searchResults: [(query: String, result: String)] = [(query, initialSearchOutput)]

        for subQuery in subQueries.prefix(config.maxSteps - 2) {


            guard totalTokens < config.maxTotalTokens else { break }

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: subQuery,
                ragService: ragService
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            searchResults.append((subQuery, searchStep.output))

            for chunk in chunks {
                if !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }
            }

            await onStep?(searchStep)
        }

        // Final synthesis
        _ = compressSearchResults(searchResults) // Compressed for potential future use
        let synthesisStep = try await executeSynthesisStep(
            query: query,
            steps: steps,
            ragService: ragService
        )
        steps.append(synthesisStep)
        totalTokens += synthesisStep.tokensUsed
        await onStep?(synthesisStep)

        return AgenticResult(
            finalAnswer: synthesisStep.output,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: 0.7,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    // MARK: - Individual Step Executors

    private func executePlanningStep(query: String, ragService: RAGService) async throws -> ThinkingStep {
        let startTime = Date()

        let planningPrompt = """
        You are a research planning assistant. Break down this query into 2-4 focused sub-questions that can be answered independently.

        Query: \(query)

        Output format:
        1. [First sub-question]
        2. [Second sub-question]
        ...

        Keep each sub-question focused and searchable. Do not answer the questions, just list them.
        """

        // Use a fresh, minimal session for planning
        let response = try await ragService.generateWithFreshSession(
            prompt: planningPrompt,
            maxTokens: 256
        )

        return ThinkingStep(
            id: UUID(),
            type: .planning,
            input: query,
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeSearchStep(subQuery: String, ragService: RAGService) async throws -> ThinkingStep {
        let startTime = Date()

        // Use the RAG pipeline to search documents
        let searchResult = try await ragService.searchDocuments(
            query: subQuery,
            topK: 12,
            minSimilarity: 0.25
        )

        return ThinkingStep(
            id: UUID(),
            type: .searching,
            input: subQuery,
            output: searchResult,
            tokensUsed: searchResult.split(separator: " ").count,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Search step using the FULL Standard pipeline (HyDE, re-ranking, MMR) - not just basic search
    private func executeSearchStepWithChunks(subQuery: String, ragService: RAGService) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        // Use the FULL hybrid search pipeline with re-ranking and MMR (like Standard mode)
        // This gives us HyDE, AI re-ranking, MMR diversification - everything Standard mode does
        let chunks = try await ragService.executeFullRetrievalPipeline(
            query: subQuery,
            topK: 20,
            minSimilarity: 0.08 // Low threshold - let re-ranker decide quality
        )

        // Format for LLM consumption - include more context since we have better chunks
        var searchResult = chunks.isEmpty
            ? "No relevant information found for: \(subQuery)"
            : "Found \(chunks.count) relevant chunks (re-ranked by relevance):\n\n"

            for (index, retrieved) in chunks.prefix(10).enumerated() {


            searchResult += "[\(index + 1)] From \(retrieved.sourceDocument)"
            if let page = retrieved.pageNumber {
                searchResult += " (Page \(page))"
            }
            searchResult += " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = (retrieved.chunk.parentContent ?? retrieved.chunk.content).trimmingCharacters(in: .whitespacesAndNewlines)
            // Include more text since our chunks are better quality now
            let preview = fullText.count > 1000 ? String(fullText.prefix(1000)) + " [...]" : fullText
            searchResult += preview
            searchResult += "\n\n"
        }

        let step = ThinkingStep(
            id: UUID(),
            type: .searching,
            input: subQuery,
            output: searchResult,
            tokensUsed: searchResult.split(separator: " ").count,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        return (step, chunks)
    }

    // MARK: - Graph Expansion (GraphRAG-lite)

    private func executeGraphExpansion(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()
        guard !initialChunks.isEmpty else {
            return (
                ThinkingStep(
                    id: UUID(),
                    type: .expanding,
                    input: query,
                    output: "",
                    tokensUsed: 0,
                    duration: Date().timeIntervalSince(startTime),
                    timestamp: startTime
                ),
                []
            )
        }

        let contextText = initialChunks
            .map { $0.chunk.parentContent ?? $0.chunk.content }
            .joined(separator: "\n")

        let entityPrompt = """
        Extract 3-5 important terms from this text that would be good search queries. Look for:
        - Product names, model numbers, or device names
        - Technical terms, features, or specifications
        - Actions, buttons, or UI elements mentioned
        - Error codes or status indicators

        Return a JSON array of strings, like: ["term1", "term2", "term3"]

        Text:
        \(contextText.prefix(2000))
        """

        let response = try await ragService.generateWithFreshSession(
            prompt: entityPrompt,
            maxTokens: 200
        )

        var entities = parseEntityList(from: response.text)
        entities = entities.filter { $0.count >= 3 }
        entities = Array(entities.prefix(3))

        if entities.isEmpty {
            entities = heuristicEntityFallback(from: contextText, excluding: query)
        }

        var expandedChunks: [RetrievedChunk] = []

        for entity in entities {
            if Task.isCancelled { break }
            let hopChunks = try await ragService.searchDocumentsRaw(
                query: entity,
                topK: 4,
                minSimilarity: 0.2
            )
            for chunk in hopChunks where !expandedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                expandedChunks.append(chunk)
            }
        }

        let output = entities.isEmpty
            ? "No graph entities identified"
            : "Entities: \(entities.joined(separator: ", ")) → +\(expandedChunks.count) chunks"

        let step = ThinkingStep(
            id: UUID(),
            type: .expanding,
            input: query,
            output: output,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        return (step, expandedChunks)
    }

    private func parseEntityList(from text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let list = try? JSONDecoder().decode([String].self, from: data)
        {
            return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }

        let cleaned = trimmed
            .replacingOccurrences(of: #"[\n\r]"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"[\[\]\"]"#, with: "", options: .regularExpression)

        return cleaned
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func heuristicEntityFallback(from text: String, excluding query: String) -> [String] {
        let pattern = #"\b[A-Z][A-Za-z0-9_]{2,}\b"#
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex?.matches(in: text, options: [], range: nsRange) ?? []

        var candidates: [String] = []
        for match in matches {
            if let range = Range(match.range, in: text) {
                let term = String(text[range])
                if !query.contains(term) && !candidates.contains(term) {
                    candidates.append(term)
                }
            }
        }

        return Array(candidates.prefix(3))
    }

    private func executeAnalysisStep(
        query: String,
        searchResults: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let analysisPrompt = """
        Analyze these search results to answer the original question.

        Original Question: \(query)

        Search Results:
        \(searchResults)

        Provide a comprehensive answer based on the evidence. Rate your confidence (0.0-1.0) at the end.
        Format: [Answer text] CONFIDENCE: [0.X]
        """

        let response = try await ragService.generateWithFreshSession(
            prompt: analysisPrompt,
            maxTokens: 1024
        )

        return ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Analyzing \(searchResults.prefix(50))...",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeRefinementStep(
        query: String,
        currentAnswer: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        let refinementPrompt = """
        The current answer may be incomplete or uncertain. Search for additional evidence to strengthen it.

        Question: \(query)
        Current Answer: \(currentAnswer.prefix(500))

        What additional information would make this answer more complete? Provide refined answer with updated confidence.
        """

        let response = try await ragService.generateWithFreshSession(
            prompt: refinementPrompt,
            maxTokens: 512
        )

        return ThinkingStep(
            id: UUID(),
            type: .refining,
            input: "Refining answer...",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    private func executeSynthesisStep(
        query: String,
        steps: [ThinkingStep],
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Compress all previous steps into a summary - truncate to fit 4096 token limit
        let stepSummary = steps.map { step in
            "\(step.type.rawValue): \(step.output.prefix(150))"
        } .joined(separator: "\n")

        // Truncate total context
        let truncatedContext = String(stepSummary.prefix(3000))

        let systemPrompt = """
        Synthesize findings into a comprehensive answer. Cite [S1], [S2] when available.
        """

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: "Research Steps:\n\(truncatedContext)",
            systemPrompt: systemPrompt,
            maxTokens: 800
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Final synthesis",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    // MARK: - Helpers

    private func parseSubQueries(from planningOutput: String) -> [String] {
        // Parse numbered list from planning output
        let lines = planningOutput.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match patterns like "1. ", "2. ", "- ", "• "
            if let range = trimmed.range(of: #"^(\d+\.|[-•])\s*"#, options: .regularExpression) {
                let query = String(trimmed[range.upperBound...])
                return query.isEmpty ? nil : query
            }
            return nil
        }
    }

    private func compressSearchResults(_ results: [(query: String, result: String)]) -> String {
        // Compress to fit within context window
        let maxPerResult = 800
        return results.map { pair in
            let truncated = String(pair.result.prefix(maxPerResult))
            return "[\(pair.query)]\n\(truncated)"
        }.joined(separator: "\n\n---\n\n")
    }

    private func extractConfidence(from text: String) -> Float {
        // Look for CONFIDENCE: 0.X pattern
        if let range = text.range(of: #"CONFIDENCE:\s*(0?\.\d+|1\.0)"#, options: .regularExpression) {
            let confidenceStr = text[range].replacingOccurrences(of: "CONFIDENCE:", with: "").trimmingCharacters(in: .whitespaces)
            return Float(confidenceStr) ?? 0.5
        }
        return 0.5 // Default confidence if not specified
    }

    private func countSources(in searchResult: String) -> Int {
        // Count citation patterns like [1], [Doc: X], etc.
        let pattern = #"\[(?:Doc:|Source:|\d+)"#
        let regex = try? NSRegularExpression(pattern: pattern)
        return regex?.numberOfMatches(in: searchResult, range: NSRange(searchResult.startIndex..., in: searchResult)) ?? 0
    }

    // MARK: - Recursive Research Loop

    /// Execute a recursive research loop that allows the LLM to autonomously search.
    ///
    /// ## Overview
    ///
    /// This implements a true autonomous research loop where the LLM can:
    /// 1. Analyze the question and current context
    /// 2. Decide whether to answer or search for more information
    /// 3. Output `[SEARCH: query]` to trigger additional retrieval
    /// 4. Output `[ANSWER]` when confident enough to respond
    ///
    /// ## Protocol
    ///
    /// The LLM responds with special tokens:
    /// - `[SEARCH: your search query]` - Request additional document search
    /// - `[ANSWER]` followed by the response - Provide final answer
    ///
    /// The loop continues until:
    /// - LLM outputs `[ANSWER]`
    /// - Maximum iterations reached (default: 7)
    /// - Token budget exhausted
    ///
    /// ## Example Flow
    ///
    /// ```
    /// User: "What is the relationship between CoreData and SwiftData?"
    ///
    /// Iteration 1:
    /// LLM: "[SEARCH: CoreData SwiftData migration]"
    /// → System retrieves chunks about CoreData/SwiftData migration
    ///
    /// Iteration 2:
    /// LLM: "[SEARCH: SwiftData @Model macro]"
    /// → System retrieves chunks about SwiftData modeling
    ///
    /// Iteration 3:
    /// LLM: "[ANSWER]
    /// CoreData and SwiftData share..."
    /// ```
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - maxIterations: Maximum number of search iterations (default: 7)
    ///   - onStep: Callback for streaming thinking steps to UI
    /// - Returns: AgenticResult with final answer and all thinking steps
    func executeRecursiveResearch(
        query: String,
        maxIterations: Int = 7,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        // Accumulate context across iterations
        var accumulatedContext = ""
        var iteration = 0

        Log.info("[RecursiveResearch] Starting recursive research loop for: \(query.prefix(50))...", category: .llm)

        // Initial retrieval to seed the context
        let (initialStep, initialChunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService
        )
        steps.append(initialStep)
        totalTokens += initialStep.tokensUsed
        allRetrievedChunks.append(contentsOf: initialChunks)
        accumulatedContext = initialStep.output
        await onStep?(initialStep)

        // Recursive loop
        while iteration < maxIterations && totalTokens < config.maxTotalTokens {
            iteration += 1

            if Task.isCancelled {
                Log.info("[RecursiveResearch] Task cancelled at iteration \(iteration)", category: .llm)
                break
            }

            Log.debug("[RecursiveResearch] Iteration \(iteration)/\(maxIterations)", category: .llm)

            // Ask the LLM to analyze context and decide next action
            let decision = try await getResearchDecision(
                query: query,
                currentContext: accumulatedContext,
                iteration: iteration,
                ragService: ragService
            )

            totalTokens += decision.tokensUsed

            // Parse the decision
            let (action, content) = parseResearchDecision(decision.text)

            switch action {
            case .answer:
                // LLM is confident - create final synthesis step
                let synthesisStep = ThinkingStep(
                    id: UUID(),
                    type: .synthesizing,
                    input: "Final answer after \(iteration) iterations",
                    output: content,
                    tokensUsed: decision.tokensUsed,
                    duration: decision.duration,
                    timestamp: Date()
                )
                steps.append(synthesisStep)
                await onStep?(synthesisStep)

                Log.info("[RecursiveResearch] Completed with answer at iteration \(iteration)", category: .llm)

                return AgenticResult(
                    finalAnswer: content,
                    steps: steps,
                    totalTokens: totalTokens,
                    totalDuration: Date().timeIntervalSince(startTime),
                    confidence: estimateConfidence(from: content),
                    sourcesUsed: allRetrievedChunks.count,
                    retrievedChunks: allRetrievedChunks
                )

            case let .search(searchQuery):
                // LLM wants more information - execute search
                Log.debug("[RecursiveResearch] LLM requested search: \(searchQuery)", category: .llm)

                let searchStep = ThinkingStep(
                    id: UUID(),
                    type: .searching,
                    input: searchQuery,
                    output: "Searching for: \(searchQuery)",
                    tokensUsed: 0,
                    duration: 0,
                    timestamp: Date()
                )
                steps.append(searchStep)
                await onStep?(searchStep)

                // Execute the search
                let (resultStep, chunks) = try await executeSearchStepWithChunks(
                    subQuery: searchQuery,
                    ragService: ragService
                )
                steps.append(resultStep)
                totalTokens += resultStep.tokensUsed
                await onStep?(resultStep)

                // Add new chunks to accumulated context
                for chunk in chunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allRetrievedChunks.append(chunk)
                }

                // Append to context (with deduplication)
                accumulatedContext += "\n\n--- Search '\(searchQuery)' ---\n\(resultStep.output)"

                // Trim context buffer if getting too long (we truncate to 2000 chars before sending to LLM anyway)
                if accumulatedContext.count > 8000 {
                    accumulatedContext = String(accumulatedContext.suffix(6000))
                }

            case let .thinking(thought):
                // LLM is thinking but hasn't decided - log and continue
                let thinkingStep = ThinkingStep(
                    id: UUID(),
                    type: .analyzing,
                    input: "Analyzing...",
                    output: thought,
                    tokensUsed: decision.tokensUsed,
                    duration: decision.duration,
                    timestamp: Date()
                )
                steps.append(thinkingStep)
                await onStep?(thinkingStep)
            }
        }

        // Reached max iterations - force synthesis
        Log.warning("[RecursiveResearch] Reached max iterations (\(maxIterations)), forcing synthesis", category: .llm)

        let forcedSynthesis = try await executeForcedSynthesis(
            query: query,
            accumulatedContext: accumulatedContext,
            ragService: ragService
        )
        steps.append(forcedSynthesis)
        totalTokens += forcedSynthesis.tokensUsed
        await onStep?(forcedSynthesis)

        return AgenticResult(
            finalAnswer: forcedSynthesis.output,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: 0.6, // Lower confidence since we hit iteration limit
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    // MARK: - Recursive Research Helpers

    /// Research action parsed from LLM output
    private enum ResearchAction {
        case answer(text: String)
        case search(query: String)
        case thinking(thought: String)
    }

    /// Ask LLM to decide whether to search or answer
    private func getResearchDecision(
        query: String,
        currentContext: String,
        iteration: Int,
        ragService: RAGService
    ) async throws -> (text: String, tokensUsed: Int, duration: TimeInterval) {
        let startTime = Date()

        // Truncate context to ~2000 chars (~1400 tokens) to leave room for prompt overhead
        let truncatedContext = String(currentContext.prefix(2000))

        let prompt = """
        QUESTION: \(query)

        CONTEXT:
        \(truncatedContext)

        Reply with [ANSWER] (your answer) OR [SEARCH: query] if you need more info.
        Iteration \(iteration)/7.
        """

        Log.debug("[RecursiveResearch] Decision prompt: \(prompt.count) chars", category: .llm)

        let response = try await ragService.generateWithProperConsent(
            prompt: prompt,
            context: "",
            systemPrompt: "You are a research assistant deciding whether to search or answer.",
            maxTokens: 600
        )

        let duration = Date().timeIntervalSince(startTime)
        return (response.text, response.tokensGenerated, duration)
    }

    /// Parse LLM output into action
    private func parseResearchDecision(_ text: String) -> (ResearchAction, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for [ANSWER] token
        if let answerRange = trimmed.range(of: "[ANSWER]", options: .caseInsensitive) {
            let answer = String(trimmed[answerRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.answer(text: answer), answer)
        }

        // Check for [SEARCH: query] token
        let searchPattern = #"\[SEARCH:\s*(.+?)\]"#
        if let regex = try? NSRegularExpression(pattern: searchPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
           let queryRange = Range(match.range(at: 1), in: trimmed)
        {
            let searchQuery = String(trimmed[queryRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (.search(query: searchQuery), searchQuery)
        }

        // Neither token found - treat as thinking
        return (.thinking(thought: trimmed), trimmed)
    }

    /// Force synthesis when iteration limit reached
    private func executeForcedSynthesis(
        query: String,
        accumulatedContext: String,
        ragService: RAGService
    ) async throws -> ThinkingStep {
        let startTime = Date()

        // Short system prompt to maximize context budget
        let systemPrompt = """
        Provide best answer with available data. Cite [S1], [S2]. Note any gaps.
        """

        // Truncate to fit 4096 token limit
        let contextToUse = String(accumulatedContext.prefix(3500))

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: contextToUse,
            systemPrompt: systemPrompt,
            maxTokens: 800
        )

        return ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Forced synthesis after max iterations",
            output: response.text,
            tokensUsed: response.tokensGenerated,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )
    }

    /// Estimate confidence from answer text (heuristic)
    private func estimateConfidence(from answer: String) -> Float {
        let lowConfidenceIndicators = [
            "i'm not sure", "i don't know", "unclear", "might be",
            "possibly", "perhaps", "uncertain", "limited information",
            "couldn't find", "no information",
        ]

        let lowercased = answer.lowercased()
        var confidence: Float = 0.8 // Base confidence

        for indicator in lowConfidenceIndicators {
            if lowercased.contains(indicator) {
                confidence -= 0.1
            }
        }

        // Length bonus (longer answers tend to be more complete)
        if answer.count > 500 { confidence += 0.05 }
        if answer.count > 1000 { confidence += 0.05 }

        return max(0.3, min(0.95, confidence))
    }

    // MARK: - Self-RAG (Adaptive Retrieval)

    /// Self-RAG: Model decides when to retrieve, what to retrieve, and self-critiques answers.
    /// Paper: Asai et al. 2023 - "Self-RAG: Learning to Retrieve, Generate, and Critique"
    ///
    /// Key insight: Not every query needs retrieval. Simple queries can be answered directly,
    /// while complex queries benefit from retrieval. The model decides.
    ///
    /// Flow:
    /// 1. Analyze query → decide if retrieval is needed
    /// 2. If yes → retrieve → generate with context → self-critique
    /// 3. If no → generate directly → self-critique
    /// 4. If critique fails → force retrieval and regenerate
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - onStep: Callback for streaming thinking steps
    /// - Returns: AgenticResult with final answer
    func executeSelfRAG(
        query: String,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        Log.info("[Self-RAG] Analyzing query to decide retrieval strategy", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Decide if retrieval is needed
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (needsRetrieval, retrievalReason) = try await decideIfRetrievalNeeded(
            query: query,
            ragService: ragService
        )

        let decisionStep = ThinkingStep(
            id: UUID(),
            type: .planning,
            input: query,
            output: needsRetrieval
                ? "📚 Retrieval needed: \(retrievalReason)"
                : "💡 Direct answer possible: \(retrievalReason)",
            tokensUsed: 50,
            duration: 0.1,
            timestamp: Date()
        )
        steps.append(decisionStep)
        totalTokens += 50
        await onStep?(decisionStep)

        var answer: String

        if needsRetrieval {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 2a: Retrieve and generate with context
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Log.info("[Self-RAG] Executing retrieval-augmented generation", category: .llm)

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: query,
                ragService: ragService
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            allRetrievedChunks.append(contentsOf: chunks)
            await onStep?(searchStep)

            // Generate with retrieved context
            let synthesisStep = try await executeComprehensiveSynthesis(
                query: query,
                chunks: allRetrievedChunks,
                ragService: ragService
            )
            steps.append(synthesisStep)
            totalTokens += synthesisStep.tokensUsed
            answer = synthesisStep.output
            await onStep?(synthesisStep)
        } else {
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // STEP 2b: Generate directly without retrieval
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            Log.info("[Self-RAG] Generating direct answer (no retrieval)", category: .llm)

            let directResponse = try await ragService.generateWithFreshSession(
                prompt: "Answer concisely: \(query)",
                maxTokens: 600
            )

            let directStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: query,
                output: directResponse.text,
                tokensUsed: directResponse.tokensGenerated,
                duration: 0.5,
                timestamp: Date()
            )
            steps.append(directStep)
            totalTokens += directResponse.tokensGenerated
            answer = directResponse.text
            await onStep?(directStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Self-Critique (hallucination check)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Self-RAG] Self-critiquing answer for quality", category: .llm)

        let (isGrounded, critiqueReason) = try await selfCritiqueAnswer(
            query: query,
            answer: answer,
            hadRetrieval: needsRetrieval,
            ragService: ragService
        )

        let critiqueStep = ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Self-critique",
            output: isGrounded
                ? "✅ Answer verified: \(critiqueReason)"
                : "⚠️ Needs improvement: \(critiqueReason)",
            tokensUsed: 50,
            duration: 0.1,
            timestamp: Date()
        )
        steps.append(critiqueStep)
        totalTokens += 50
        await onStep?(critiqueStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 4: If critique failed and we didn't retrieve, force retrieval
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if !isGrounded && !needsRetrieval {
            Log.info("[Self-RAG] Critique failed → forcing retrieval", category: .llm)

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: query,
                ragService: ragService
            )
            steps.append(searchStep)
            totalTokens += searchStep.tokensUsed
            allRetrievedChunks.append(contentsOf: chunks)
            await onStep?(searchStep)

            // Regenerate with retrieved context
            let retryStep = try await executeComprehensiveSynthesis(
                query: query,
                chunks: allRetrievedChunks,
                ragService: ragService
            )
            steps.append(retryStep)
            totalTokens += retryStep.tokensUsed
            answer = retryStep.output
            await onStep?(retryStep)
        }

        let confidence: Float = isGrounded ? 0.85 : 0.65

        return AgenticResult(
            finalAnswer: answer,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: confidence,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    /// Decide if the query needs document retrieval or can be answered directly
    private func decideIfRetrievalNeeded(
        query: String,
        ragService: RAGService
    ) async throws -> (needsRetrieval: Bool, reason: String) {
        // Heuristic approach (fast, no LLM call needed)
        let lowercased = query.lowercased()

        // Queries that likely need retrieval (document-specific)
        let retrievalIndicators = [
            "document", "file", "pdf", "manual", "guide", "spec",
            "what does", "how does", "according to", "based on",
            "in the", "from the", "find", "search", "look up",
            "where is", "which section", "page", "chapter",
        ]

        // Queries that can often be answered directly (general knowledge)
        let directIndicators = [
            "what is", "define", "explain", "who is", "when was",
            "how many", "calculate", "convert", "translate",
        ]

        let hasRetrievalIndicator = retrievalIndicators.contains { lowercased.contains($0) }
        let hasDirectIndicator = directIndicators.contains { lowercased.contains($0) }

        // If query mentions documents/files → definitely retrieve
        if hasRetrievalIndicator && !hasDirectIndicator {
            return (true, "Query references documents or requires lookup")
        }

        // If it's a pure definition/general knowledge question → try direct first
        if hasDirectIndicator && !hasRetrievalIndicator {
            return (false, "General knowledge question - can try direct answer")
        }

        // Ambiguous → default to retrieval (safer for RAG app)
        return (true, "Defaulting to retrieval for comprehensive answer")
    }

    /// Self-critique the answer for quality and grounding
    private func selfCritiqueAnswer(
        query: String,
        answer: String,
        hadRetrieval: Bool,
        ragService: RAGService
    ) async throws -> (isGrounded: Bool, reason: String) {
        // Heuristic critique (fast)
        let answerLower = answer.lowercased()

        // Check for hallucination indicators
        let uncertaintyMarkers = [
            "i don't have", "i cannot", "i'm not able",
            "no information", "not found", "unclear",
            "i think", "probably", "might be", "possibly",
        ]

        let hasUncertainty = uncertaintyMarkers.contains { answerLower.contains($0) }

        // Check for citation presence (if we retrieved)
        let hasCitations = answer.contains("[S") || answer.contains("[Doc")

        if hadRetrieval {
            // With retrieval, we expect citations
            if hasCitations && !hasUncertainty {
                return (true, "Answer cites sources and is confident")
            } else if hasCitations {
                return (true, "Answer cites sources but has some uncertainty")
            } else {
                return (false, "Answer lacks citations despite retrieval")
            }
        } else {
            // Without retrieval, just check for confidence
            if hasUncertainty {
                return (false, "Answer shows uncertainty - should verify with documents")
            } else if answer.count < 50 {
                return (false, "Answer too brief - may be incomplete")
            } else {
                return (true, "Answer appears confident and complete")
            }
        }
    }

    // MARK: - Speculative RAG (Multi-Path Verification)

    /// Speculative RAG: Generate multiple candidate answers, verify each against documents.
    /// Catches hallucinations through multi-path verification.
    ///
    /// Flow:
    /// 1. Retrieve relevant documents
    /// 2. Generate N candidate answers (with temperature variation)
    /// 3. Score each candidate against source documents
    /// 4. Return highest-scoring grounded answer
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - candidateCount: Number of candidate answers to generate (default: 3)
    ///   - onStep: Callback for streaming thinking steps
    /// - Returns: AgenticResult with best verified answer
    func executeSpeculativeRAG(
        query: String,
        candidateCount: Int = 3,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var steps: [ThinkingStep] = []
        var totalTokens = 0
        var allRetrievedChunks: [RetrievedChunk] = []
        let startTime = Date()

        Log.info("[Speculative-RAG] Starting multi-path verification with \(candidateCount) candidates", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Retrieve documents
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (searchStep, chunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService
        )
        steps.append(searchStep)
        totalTokens += searchStep.tokensUsed
        allRetrievedChunks.append(contentsOf: chunks)
        await onStep?(searchStep)

        // Build context from chunks
        let sourceContext = chunks.prefix(5).enumerated().map { index, chunk in
            "[S\(index + 1)] \(chunk.chunk.content.prefix(400))"
        }.joined(separator: "\n\n")

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Generate multiple candidate answers
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Speculative-RAG] Generating \(candidateCount) candidate answers", category: .llm)

        var candidates: [(answer: String, tokens: Int)] = []
        let temperatures: [Float] = [0.3, 0.6, 0.8] // Vary temperature for diversity

        for i in 0..<min(candidateCount, temperatures.count) {
            let temp = temperatures[i]

            let candidateStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: "Candidate \(i + 1) (temp=\(temp))",
                output: "Generating candidate answer...",
                tokensUsed: 0,
                duration: 0,
                timestamp: Date()
            )
            await onStep?(candidateStep)

            let response = try await generateCandidateAnswer(
                query: query,
                context: sourceContext,
                temperature: temp,
                ragService: ragService
            )

            candidates.append((response.text, response.tokensGenerated))
            totalTokens += response.tokensGenerated

            let resultStep = ThinkingStep(
                id: UUID(),
                type: .synthesizing,
                input: "Candidate \(i + 1)",
                output: "Generated: \(response.text.prefix(100))...",
                tokensUsed: response.tokensGenerated,
                duration: 0.5,
                timestamp: Date()
            )
            steps.append(resultStep)
            await onStep?(resultStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Score each candidate against source documents
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Speculative-RAG] Scoring candidates for grounding", category: .llm)

        var scoredCandidates: [(answer: String, score: Float, reason: String)] = []

        for (index, candidate) in candidates.enumerated() {
            let (score, reason) = scoreAnswerGrounding(
                answer: candidate.answer,
                sourceContext: sourceContext
            )
            scoredCandidates.append((candidate.answer, score, reason))

            let scoreStep = ThinkingStep(
                id: UUID(),
                type: .analyzing,
                input: "Scoring candidate \(index + 1)",
                output: "Score: \(String(format: "%.0f%%", score * 100)) - \(reason)",
                tokensUsed: 10,
                duration: 0.05,
                timestamp: Date()
            )
            steps.append(scoreStep)
            totalTokens += 10
            await onStep?(scoreStep)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 4: Select best candidate
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let best = scoredCandidates.max(by: { $0.score < $1.score }) ?? scoredCandidates[0]

        let selectionStep = ThinkingStep(
            id: UUID(),
            type: .refining,
            input: "Selecting best answer",
            output: "Selected answer with \(String(format: "%.0f%%", best.score * 100)) grounding score: \(best.reason)",
            tokensUsed: 5,
            duration: 0.02,
            timestamp: Date()
        )
        steps.append(selectionStep)
        totalTokens += 5
        await onStep?(selectionStep)

        Log.info("[Speculative-RAG] Selected best candidate with score \(best.score)", category: .llm)

        return AgenticResult(
            finalAnswer: best.answer,
            steps: steps,
            totalTokens: totalTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: best.score,
            sourcesUsed: allRetrievedChunks.count,
            retrievedChunks: allRetrievedChunks
        )
    }

    /// Generate a candidate answer with specific temperature
    private func generateCandidateAnswer(
        query: String,
        context: String,
        temperature: Float,
        ragService: RAGService
    ) async throws -> LLMResponse {
        // Note: We use generateWithFreshSession which uses default temperature
        // In a full implementation, we'd pass temperature to the LLM config
        // For now, we get diversity from multiple calls (LLM has inherent randomness)
        return try await ragService.generateWithFreshSession(
            prompt: """
            Using ONLY the excerpts below, answer the question. Cite [S1], [S2], etc.

            EXCERPTS:
            \(context)

            QUESTION: \(query)

            ANSWER:
            """,
            maxTokens: 500
        )
    }

    /// Score how well an answer is grounded in source documents
    private func scoreAnswerGrounding(
        answer: String,
        sourceContext: String
    ) -> (score: Float, reason: String) {
        var score: Float = 0.5 // Base score

        // Check for citations
        let citationPattern = #"\[S\d+\]"#
        let citationRegex = try? NSRegularExpression(pattern: citationPattern)
        let citationCount = citationRegex?.numberOfMatches(
            in: answer,
            range: NSRange(answer.startIndex..., in: answer)
        ) ?? 0

        if citationCount > 0 {
            score += 0.15 * Float(min(citationCount, 3)) // Up to +0.45 for citations
        }

        // Check for key term overlap with source
        let answerWords = Set(answer.lowercased().split(separator: " ").map(String.init))
        let sourceWords = Set(sourceContext.lowercased().split(separator: " ").map(String.init))
        let overlap = answerWords.intersection(sourceWords)
        let overlapRatio = Float(overlap.count) / Float(max(answerWords.count, 1))

        if overlapRatio > 0.3 {
            score += 0.1
        }
        if overlapRatio > 0.5 {
            score += 0.1
        }

        // Check for hedging language (reduces confidence)
        let hedgingWords = ["might", "possibly", "perhaps", "unclear", "uncertain"]
        let hasHedging = hedgingWords.contains { answer.lowercased().contains($0) }
        if hasHedging {
            score -= 0.15
        }

        // Check answer length (very short = suspicious)
        if answer.count < 50 {
            score -= 0.1
        } else if answer.count > 200 {
            score += 0.05
        }

        // Build reason
        var reasons: [String] = []
        if citationCount > 0 {
            reasons.append("\(citationCount) citations")
        }
        if overlapRatio > 0.3 {
            reasons.append("good term overlap")
        }
        if hasHedging {
            reasons.append("contains uncertainty")
        }

        let reason = reasons.isEmpty ? "baseline score" : reasons.joined(separator: ", ")

        return (max(0.2, min(0.95, score)), reason)
    }
}

// MARK: - Errors

enum AgenticError: LocalizedError {
    case serviceUnavailable
    case maxStepsExceeded
    case tokenLimitReached
    case planningFailed

    var errorDescription: String? {
        switch self {
        case .serviceUnavailable:
            return "RAG service unavailable"
        case .maxStepsExceeded:
            return "Maximum reasoning steps exceeded"
        case .tokenLimitReached:
            return "Token limit reached across sessions"
        case .planningFailed:
            return "Failed to decompose query into sub-questions"
        }
    }
}

// MARK: - Reasoning Chain Architecture

/// Configuration for chained reasoning sessions
/// Each session gets its own 4096 token budget, chained together for 16K+ effective context
struct ReasoningChainConfig: Sendable {
    /// Number of chained sessions (each has 4096 tokens)
    let sessionCount: Int

    /// Maximum context chars per session (~2800 tokens safe for 4096 limit)
    let maxContextPerSession: Int

    /// Maximum insight chars to pass between sessions
    let maxInsightLength: Int

    /// Light config for Standard mode - faster with 3 sessions
    /// 3 × 4096 = 12K+ effective tokens (vs single 4K)
    nonisolated static let light = ReasoningChainConfig(
        sessionCount: 3,        // 3 × 4096 = 12K+ effective tokens
        maxContextPerSession: 3200,
        maxInsightLength: 1500   // Keep full findings, not snippets
    )

    nonisolated static let standard = ReasoningChainConfig(
        sessionCount: 4,        // 4 × 4096 = 16K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 2000   // Keep full findings, not snippets
    )

    nonisolated static let deep = ReasoningChainConfig(
        sessionCount: 5,        // 5 × 4096 = 20K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 2500   // Keep full findings, not snippets
    )

    /// Unlimited config - Maximum mode: up to 50 sessions until 98% confident
    /// Since Neural Engine is disk-backed, memory isn't the limit - thermal/user patience is
    /// 50 sessions × 4K = 200K+ effective tokens (realistically takes 5-15 minutes)
    nonisolated static let unlimited = ReasoningChainConfig(
        sessionCount: 50, // 50 × 4096 = 200K+ effective tokens
        maxContextPerSession: 3500,
        maxInsightLength: 3000   // Preserve maximum detail between sessions
    )

    /// Per-cluster config for multi-chain Maximum mode
    /// Each cluster gets its own chain with focused context
    nonisolated static let clusterChain = ReasoningChainConfig(
        sessionCount: 8, // 8 sessions per cluster
        maxContextPerSession: 3200,
        maxInsightLength: 2000
    )
}

// MARK: - Multi-Chain Configuration

/// Configuration for parallel multi-chain reasoning
/// Splits documents into clusters, runs parallel chains, synthesizes results
struct MultiChainConfig: Sendable {
    /// Maximum number of parallel document clusters
    let maxClusters: Int

    /// Minimum documents per cluster (avoid tiny clusters)
    let minDocsPerCluster: Int

    /// Sessions per cluster chain
    let sessionsPerCluster: Int

    /// Sessions for final synthesis chain
    let synthesisSessions: Int

    /// Maximum parallel chains (thermal/CPU limit)
    let maxParallelChains: Int

    /// Default for Maximum mode: 4 clusters × 8 sessions + 3 synthesis = 35 chains
    nonisolated static let maximum = MultiChainConfig(
        maxClusters: 5,
        minDocsPerCluster: 2,
        sessionsPerCluster: 8,
        synthesisSessions: 4,
        maxParallelChains: 3 // Run 3 at a time to avoid thermal throttling
    )

    /// Light multi-chain for faster exploration
    nonisolated static let light = MultiChainConfig(
        maxClusters: 3,
        minDocsPerCluster: 2,
        sessionsPerCluster: 4,
        synthesisSessions: 2,
        maxParallelChains: 2
    )
}

/// Result from a multi-chain execution
struct MultiChainResult: Sendable {
    let finalAnswer: String
    let clusterInsights: [ClusterInsight]
    let totalTokens: Int
    let totalSessions: Int
    let totalDuration: TimeInterval
    let confidence: Float

    struct ClusterInsight: Sendable {
        let clusterName: String
        let documents: [String]
        let insight: String
        let chainInsights: [String] // Individual session insights for reasoning trace
        let tokensUsed: Int
        let sessionsRun: Int
    }
}

/// A cluster of documents for parallel processing
struct DocumentCluster {
    let name: String
    var documents: [String]
    var chunks: [RetrievedChunk]
}

/// Result from a reasoning chain
struct ReasoningChainResult: Sendable {
    let finalAnswer: String
    let chainInsights: [String]  // Insights from each session
    let totalTokens: Int
    let sessionCount: Int
    let confidence: Float
    let sources: [String]
}

extension AgenticOrchestrator {

    // MARK: - Reasoning Chain (Session Chaining)

    /// Execute a reasoning chain that multiplies effective context by chaining sessions
    ///
    /// ## Architecture (Per TN3193)
    ///
    /// Apple FM has a hard 4096 token limit per session. We outsmart this by:
    ///
    /// ```
    /// Session 1 (4096 tokens): Retrieve + First Pass Analysis
    ///    ↓ condensed insight (~500 chars)
    /// Session 2 (4096 tokens): New retrieval + Refine understanding
    ///    ↓ condensed insight
    /// Session 3 (4096 tokens): Pattern recognition across insights
    ///    ↓ condensed insight
    /// Session 4 (4096 tokens): Final synthesis with full reasoning
    /// ```
    ///
    /// **Effective context: 4 × 4096 = 16,384+ tokens** (vs single 4096)
    ///
    /// Each session:
    /// - Has fresh 4096 token budget
    /// - Receives previous insight as "priming" context
    /// - Focuses on a specific reasoning task
    /// - Outputs condensed insight for next session
    ///
    /// - Parameters:
    ///   - query: The user's question
    ///   - chunks: Retrieved document chunks
    ///   - config: Chain configuration (default: 4 sessions)
    ///   - onStep: Callback for streaming thinking steps
    /// - Returns: ReasoningChainResult with synthesized answer
    func executeReasoningChain(
        query: String,
        chunks: [RetrievedChunk],
        config: ReasoningChainConfig = .standard,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> ReasoningChainResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        var chainInsights: [String] = []
        var totalTokens = 0
        var allSources: Set<String> = []
        var cumulativeConfidence: Float = 0

        // Unlimited mode: use AgenticConfig's confidence threshold for early termination
        let isUnlimitedMode = config.sessionCount >= 20
        let confidenceThreshold: Float = isUnlimitedMode ? self.config.confidenceThreshold : 0.98
        var actualSessionCount = 0

        Log.info("[ReasoningChain] Starting \(config.sessionCount)-session chain for: \(query.prefix(40))...", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // CRITICAL: Use TOP-K chunks for ALL sessions, not distributed slices
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Previous approach distributed chunks: Session 1 gets top chunks, Session 2 gets
        // worse chunks, Session 3 gets even worse, etc. This is WRONG because:
        // 1. Later sessions analyze irrelevant content (web interface, shipping, etc.)
        // 2. The value of multi-session is reasoning DEPTH, not seeing MORE (worse) chunks
        // 3. Ranked chunks exist for a reason - lower-ranked = less relevant
        //
        // New approach: ALL sessions see the SAME top-K most relevant chunks.
        // Each session reasons DEEPER on the same high-quality context.

        // For unlimited mode, use smaller context to leave room for accumulated insights
        let maxChunksPerSession = isUnlimitedMode ? 4 : 6
        let contextBudget = isUnlimitedMode ? 2500 : (config.maxContextPerSession - 500)
        let topChunks = Array(chunks.prefix(maxChunksPerSession))

        // Pre-build the shared context from top chunks (used by all sessions)
        var sharedContext = ""
        for (idx, chunk) in topChunks.enumerated() {
            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            sharedContext += "[S\(idx + 1)] \(content)\n---\n"
            allSources.insert(chunk.sourceDocument)

            // Stay within session budget (tighter for unlimited mode)
            if sharedContext.count > contextBudget { break }
        }

        Log.debug("[ReasoningChain] Using top \(topChunks.count) chunks for ALL sessions (shared context: \(sharedContext.count) chars)", category: .retrieval)

        if isUnlimitedMode {
            Log.info("[ReasoningChain] UNLIMITED MODE: Will keep reasoning until \(Int(confidenceThreshold * 100))% confident or \(config.sessionCount) sessions max", category: .llm)
        }

        for sessionIndex in 0..<config.sessionCount {
            let sessionNum = sessionIndex + 1
            actualSessionCount = sessionNum

            if isUnlimitedMode {
                Log.debug("[ReasoningChain] Session \(sessionNum) (unlimited mode, confidence: \(Int(cumulativeConfidence * 100))%)", category: .llm)
            } else {
                Log.debug("[ReasoningChain] Session \(sessionNum)/\(config.sessionCount)", category: .llm)
            }

            if Task.isCancelled { break }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Unlimited mode: Check if we've reached confidence threshold
            // Require at least 8 sessions to build up meaningful reasoning depth
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if isUnlimitedMode, sessionIndex >= 8, cumulativeConfidence >= confidenceThreshold { 
                Log.info("[ReasoningChain] Unlimited mode: Stopping at \(Int(cumulativeConfidence * 100))% confidence (threshold: \(Int(confidenceThreshold * 100))%)", category: .llm)
                break
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // All sessions use the SAME top-ranked context
            // The multi-session value is reasoning depth, not chunk diversity
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let sessionContext = sharedContext

            // DEBUG: Log what context is actually being passed
            Log.debug("[ReasoningChain] Session \(sessionNum) context (\(sessionContext.count) chars): \(sessionContext.prefix(500))...", category: .retrieval)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Build session prompt based on position in chain
            // For unlimited mode, dynamically determine if this should be the "final" session
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let effectiveSessionCount = isUnlimitedMode ? max(config.sessionCount, sessionNum + 3) : config.sessionCount

            // For unlimited mode, use sliding window of recent insights to prevent context overflow
            // Keep only the last 3 insights (each ~500 chars) to stay well under 4096 token limit
            let insightsForPrompt: [String]
            if isUnlimitedMode && chainInsights.count > 3 {
                // Condense older insights into a brief summary + keep recent 2
                let oldInsightsCount = chainInsights.count - 2
                let condensedOld = "Previously discovered (\(oldInsightsCount) sessions): " +
                    chainInsights.prefix(oldInsightsCount)
                        .map { String($0.prefix(100)) }
                        .joined(separator: " | ")
                insightsForPrompt = [String(condensedOld.prefix(500))] + Array(chainInsights.suffix(2))
                Log.debug("[ReasoningChain] Unlimited mode: condensed \(chainInsights.count) insights to \(insightsForPrompt.count) for prompt", category: .llm)
            } else {
                insightsForPrompt = chainInsights
            }

            let (prompt, systemPrompt) = buildChainPrompt(
                sessionIndex: sessionIndex,
                sessionCount: effectiveSessionCount,
                query: query,
                context: sessionContext,
                previousInsights: insightsForPrompt,
                maxInsightLength: isUnlimitedMode ? 600 : config.maxInsightLength  // Shorter for unlimited
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Execute session with proper consent
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            // Maximum mode gets higher token limits for more detailed reasoning
            let sessionMaxTokens = isUnlimitedMode ? 1200 : 700

            let response = try await ragService.generateWithProperConsent(
                prompt: prompt,
                context: "", // Context is embedded in prompt
                systemPrompt: systemPrompt,
                maxTokens: sessionMaxTokens
            )

            totalTokens += response.tokensGenerated

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Extract insight to pass to next session
            // For FINAL session, keep FULL response (don't truncate!)
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            let isFinalSession = sessionIndex == config.sessionCount - 1
            let insight: String

            if isFinalSession {
                // For final synthesis, extract the full answer (not truncated)
                insight = extractFinalAnswer(from: response.text)
            } else {
                // For intermediate sessions, extract condensed insight
                insight = extractInsight(from: response.text, maxLength: config.maxInsightLength)
            }

            // Parse confidence if present, or estimate based on response quality
            // Do this BEFORE appending insight so we can compare with previous insights
            if let conf = parseConfidence(from: response.text) {
                cumulativeConfidence = (cumulativeConfidence + conf) / 2
            } else if isUnlimitedMode {
                // Heuristic confidence for Maximum mode:
                // Designed to require 8-15+ sessions before hitting 98%
                // Each component is conservative to ensure deep exploration

                // 1. Session contribution (up to 48%) - more sessions = more exploration
                // MAXIMUM MODE: Slower build (0.02/session vs 0.03) to encourage deeper exploration
                // At 8 sessions: 16%, at 15 sessions: 30%, at 20 sessions: 40%, at 24: 48% (cap)
                let sessionContributionRate: Float = isUnlimitedMode ? 0.02 : 0.03
                let sessionContribution = min(sessionContributionRate * Float(sessionNum), 0.48)

                // 2. Length contribution (up to 15%) - longer insights = more substance
                // Requires 3000+ chars for full bonus (conservative)
                let lengthContribution = min(Float(insight.count) / 3000.0, 0.15)

                // 3. Citation bonus (up to 10%) - grounded in sources
                let hasCitations = insight.contains("[S") || insight.contains("S1") || insight.contains("S2")
                let citationBonus: Float = hasCitations ? 0.10 : 0

                // 4. Repetition detection (up to 25%) - if repeating, we've exhausted the topic
                // Compare current insight with PREVIOUS insights (before appending)
                // MAXIMUM MODE: Much higher thresholds - designed for deep exploration with many documents
                var repetitionBonus: Float = 0

                // Require more sessions before checking repetition in Maximum mode
                let minSessionsForRepetitionCheck = isUnlimitedMode ? 8 : 4

                if chainInsights.count >= minSessionsForRepetitionCheck {
                    // Use more unique words (min 4 chars, take more words for better sampling)
                    let currentWords = Set(insight.lowercased().split(separator: " ")
                        .filter { $0.count > 4 && !Self.commonStopWords.contains(String($0)) }
                        .prefix(100))
                    var similarityCount = 0
                    var maxOverlapRatio: Float = 0
                    var consecutiveSimilar = 0
                    var lastWasSimilar = false

                    // Check last 4 previous insights (not including current)
                    for prevInsight in chainInsights.suffix(4) {
                        let prevWords = Set(prevInsight.lowercased().split(separator: " ")
                            .filter { $0.count > 4 && !Self.commonStopWords.contains(String($0)) }
                            .prefix(100))
                        let overlap = currentWords.intersection(prevWords).count
                        let overlapRatio = Float(overlap) / Float(max(currentWords.count, 1))
                        maxOverlapRatio = max(maxOverlapRatio, overlapRatio)

                        // Higher threshold for Maximum mode (65% vs 50%)
                        let similarityThreshold: Float = isUnlimitedMode ? 0.65 : 0.50
                        if overlapRatio > similarityThreshold { 
                            similarityCount += 1
                            if lastWasSimilar { consecutiveSimilar += 1 }
                            lastWasSimilar = true
                        } else {
                            lastWasSimilar = false
                        }
                    }

                    // MAXIMUM MODE: Require 3 consecutive similar OR 90%+ overlap before forcing termination
                    // Standard mode: 3+ similar OR 75%+ overlap
                    let forceTerminationThreshold: Float = isUnlimitedMode ? 0.90 : 0.75
                    let forceTerminationCount = isUnlimitedMode ? 3 : 3
                    let requireConsecutive = isUnlimitedMode // Maximum mode requires consecutive hits

                    let shouldForceTerminate = requireConsecutive
                        ? (consecutiveSimilar >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)
                        : (similarityCount >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)

                    if shouldForceTerminate { 
                        repetitionBonus = 0.25 // Strong repetition - topic exhausted
                        Log.info("[ReasoningChain] Strong repetition detected (\(similarityCount)/4 similar, consecutive: \(consecutiveSimilar), max overlap: \(Int(maxOverlapRatio * 100))%) - topic exhausted", category: .llm)

                        // IMMEDIATE TERMINATION: Force confidence to 99% to trigger stop
                        // But ONLY if we've done substantial exploration
                        let minSessionsBeforeForceStop = isUnlimitedMode ? 15 : 6
                        if sessionNum >= minSessionsBeforeForceStop {
                            cumulativeConfidence = 0.99
                            Log.info("[ReasoningChain] Forcing early termination due to severe repetition (after \(sessionNum) sessions)", category: .llm)
                        } else {
                            Log.info("[ReasoningChain] Repetition detected but continuing (session \(sessionNum) < \(minSessionsBeforeForceStop) minimum)", category: .llm)
                        }
                    } else if similarityCount >= 2 || maxOverlapRatio > 0.60 {
                        repetitionBonus = isUnlimitedMode ? 0.05 : 0.15 // Lower bonus in Maximum mode
                        Log.info("[ReasoningChain] Moderate repetition detected (overlap: \(Int(maxOverlapRatio * 100))%)", category: .llm)
                    }
                }

                // 5. Exhaustion bonus (up to 15%) - if we're deep in sessions, boost confidence
                // Only kicks in after 10+ sessions (conservative for Maximum mode)
                let exhaustionBonus: Float = sessionNum >= 15 ? 0.15 : (sessionNum >= 12 ? 0.10 : (sessionNum >= 10 ? 0.05 : 0))

                // Only calculate confidence normally if we haven't forced termination
                if cumulativeConfidence<0.99 { 
                    let estimatedConfidence = sessionContribution + lengthContribution + citationBonus + repetitionBonus + exhaustionBonus
                    cumulativeConfidence = max(cumulativeConfidence, min(estimatedConfidence, 0.99))
                }

                Log.info("[ReasoningChain] Confidence: \(Int(cumulativeConfidence * 100))% (session: \(Int(sessionContribution * 100))%, length: \(Int(lengthContribution * 100))%, citations: \(Int(citationBonus * 100))%, repetition: \(Int(repetitionBonus * 100))%, exhaustion: \(Int(exhaustionBonus * 100))%)", category: .llm)
            }

            // Append insight AFTER confidence check (so we compare with previous insights)
            chainInsights.append(insight)

            // Emit thinking step
            let stepType: ThinkingStep.StepType = switch sessionIndex {
            case 0: .searching
            case config.sessionCount - 1: .synthesizing
            default: .analyzing
            }

            let step = ThinkingStep(
                id: UUID(),
                type: stepType,
                input: "Session \(sessionNum): \(sessionPromptDescription(sessionIndex, config.sessionCount))",
                output: isFinalSession ? "Synthesizing final answer..." : insight,
                tokensUsed: response.tokensGenerated,
                duration: 0.5,
                timestamp: Date(),
                confidence: isUnlimitedMode ? cumulativeConfidence : nil
            )
            await onStep?(step)

            Log.debug("[ReasoningChain] Session \(sessionNum) insight: \(insight.prefix(80))...", category: .llm)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Final synthesis from chain
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // For UNLIMITED MODE: Run a dedicated exhaustive synthesis pass
        // This ensures we get a comprehensive answer, not just the last insight
        let finalAnswer: String
        if isUnlimitedMode, chainInsights.count >= 3 {
            Log.info("[ReasoningChain] Running exhaustive synthesis for Maximum mode (\(chainInsights.count) insights)...", category: .llm)

            // CRITICAL: Apple FM API enforces 4096 token limit for BOTH on-device AND PCC
            // (TN3193: The 65K server capacity is NOT exposed via FoundationModels framework)
            // Budget: ~1500 tokens for insights, ~500 for prompt overhead, ~2000 for output
            let maxInsightChars = 5000 // ~1250 tokens for insights (conservative)
            var condensedInsights: [String] = []
            var totalChars = 0

            // Take insights from end (most refined) to beginning, but include more
            for insight in chainInsights.reversed() {
                let trimmed = insight.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if totalChars + trimmed.count <= maxInsightChars {
                    condensedInsights.insert(trimmed, at: 0)
                    totalChars += trimmed.count
                } else if condensedInsights.isEmpty {
                    // At least include a truncated version of the last insight
                    condensedInsights.append(String(trimmed.prefix(maxInsightChars)))
                    break
                } else {
                    break
                }
            }

            Log.info("[ReasoningChain] Synthesis will use \(condensedInsights.count)/\(chainInsights.count) insights (\(totalChars) chars)", category: .llm)

            let insightsSummary = condensedInsights.enumerated()
                .map { "[\($0.offset + 1)] \($0.element)" }
.joined(separator: "\n\n")

            // PCC can handle much larger prompts (65K context)
            // Structure the prompt for comprehensive synthesis
            var exhaustivePrompt = "QUESTION: " + query + "\n\n"
            exhaustivePrompt += "RESEARCH FINDINGS (" + String(actualSessionCount) + " deep-dive sessions):\n"
            exhaustivePrompt += insightsSummary + "\n\n"
            exhaustivePrompt += "TASK: Synthesize a COMPREHENSIVE, SCHOLARLY answer integrating ALL findings.\n\n"
            exhaustivePrompt += "REQUIREMENTS:\n"
            exhaustivePrompt += "- Include EVERY detail, statistic, finding, and methodology mentioned\n"
            exhaustivePrompt += "- Use headers (##) to organize by major themes\n"
            exhaustivePrompt += "- Include bullet points for key findings within each section\n"
            exhaustivePrompt += "- Cite specific studies, authors, or sources when mentioned\n"
            exhaustivePrompt += "- Discuss implications, limitations, and future directions if relevant\n"
            exhaustivePrompt += "- Be EXHAUSTIVE - this is Maximum mode, the user wants depth\n"
            exhaustivePrompt += "- Target 800-1200 words minimum\n\n"
            exhaustivePrompt += "COMPREHENSIVE ANSWER:"

            var exhaustiveSystemPrompt = "You are a research synthesis expert. Your task is to produce an exhaustive, "
            exhaustiveSystemPrompt += "publication-quality summary. Include all specifics: study names, sample sizes, "
            exhaustiveSystemPrompt += "effect sizes, methodologies, limitations, and conclusions. "
            exhaustiveSystemPrompt += "Use markdown formatting with headers and bullets. Be thorough and scholarly."

            // Apple FM API: 4096 token limit applies to BOTH on-device and PCC
            // The 65K server capacity is internal to Apple, not exposed to developers (TN3193)
            // Budget: Total 4096 = ~1500 prompt + ~1500 insights + ~1000 buffer → leaves ~1000-1500 for output
            let synthesisMaxTokens = 1500 // Realistic within 4096 total budget

            do {
                Log.info("[ReasoningChain] Exhaustive synthesis: requesting up to \(synthesisMaxTokens) tokens (4096 total limit)", category: .llm)
                let synthesisResponse = try await ragService.generateWithProperConsent(
                    prompt: exhaustivePrompt,
                    context: "",
                    systemPrompt: exhaustiveSystemPrompt,
                    maxTokens: synthesisMaxTokens
                )
                finalAnswer = synthesisResponse.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                totalTokens += synthesisResponse.tokensGenerated
                Log.info("[ReasoningChain] Exhaustive synthesis: generated \(synthesisResponse.tokensGenerated) tokens (\(finalAnswer.count) chars)", category: .llm)
            } catch {
                Log.warning("[ReasoningChain] Exhaustive synthesis failed, using last insight: \(error)", category: .llm)
                finalAnswer = chainInsights.last ?? "Unable to synthesize answer from reasoning chain."
            }
        } else {
            // Standard mode: The last insight IS the final answer (session N is synthesis)
            finalAnswer = chainInsights.last ?? "Unable to synthesize answer from reasoning chain."
        }

        if isUnlimitedMode {
            Log.info("[ReasoningChain] UNLIMITED MODE completed: \(actualSessionCount) sessions, \(totalTokens) tokens, \(Int(cumulativeConfidence * 100))% confidence", category: .llm)
        } else {
            Log.info("[ReasoningChain] Completed \(actualSessionCount) sessions, \(totalTokens) total tokens", category: .llm)
        }

        return ReasoningChainResult(
            finalAnswer: finalAnswer,
            chainInsights: chainInsights,
            totalTokens: totalTokens,
            sessionCount: actualSessionCount,
            confidence: max(0.5, cumulativeConfidence),
            sources: Array(allSources)
        )
    }

    // MARK: - Multi-Chain Execution (Maximum Mode)

    /// Execute parallel reasoning chains across document clusters
    ///
    /// ## Architecture
    /// Instead of cramming everything into one 4096-token context, we:
    /// 1. Cluster documents by topic similarity
    /// 2. Run parallel reasoning chains per cluster (each gets full 4096 tokens)
    /// 3. Synthesize all cluster insights into final answer
    ///
    /// For 17 documents: 4 clusters × 8 sessions × 4096 = 130K+ effective tokens
    /// With 3-way parallelism, completes in ~4 minutes vs 15+ for sequential
    func executeMultiChainReasoning(
        query: String,
        allChunks: [RetrievedChunk],
        config: MultiChainConfig = .maximum,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> MultiChainResult {
        guard ragService != nil else { 
            throw AgenticError.serviceUnavailable
        }

        let startTime = Date()
        var totalTokens = 0
        var clusterInsights: [MultiChainResult.ClusterInsight] = []

        // Track progressive confidence for UI
        var progressiveConfidence: Float = 0.05

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Cluster documents by source
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let documentClusters = clusterChunksByDocument(
            chunks: allChunks,
            maxClusters: config.maxClusters,
            minDocsPerCluster: config.minDocsPerCluster
        )

        Log.info("[MultiChain] Created \(documentClusters.count) document clusters from \(allChunks.count) chunks", category: .llm)

        // Emit planning step with initial confidence
        let planStep = ThinkingStep(
            id: UUID(),
            type: .planning,
            input: "Multi-chain strategy",
            output: "Analyzing \(documentClusters.count) document clusters in parallel, then synthesizing",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: progressiveConfidence
        )
        await onStep?(planStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Run parallel reasoning chains per cluster
        // Use TaskGroup for controlled parallelism
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Process clusters in batches to avoid thermal throttling
        let batchSize = config.maxParallelChains
        var clusterIndex = 0

        for batchStart in stride(from: 0, to: documentClusters.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, documentClusters.count)
            let batch = Array(documentClusters[batchStart ..< batchEnd])

            Log.info("[MultiChain] Processing batch \(batchStart / batchSize + 1): clusters \(batchStart + 1)-\(batchEnd)", category: .llm)

            // Run this batch in parallel
            let batchResults = await withTaskGroup(of: (Int, MultiChainResult.ClusterInsight?).self) { group in
                for (localIdx, cluster) in batch.enumerated() {
                    let globalIdx = batchStart + localIdx
                    group.addTask {
                        do {
                            let insight = try await self.executeClusterChain(
                                query: query,
                                clusterName: cluster.name,
                                chunks: cluster.chunks,
                                clusterIndex: globalIdx,
                                sessionsPerCluster: config.sessionsPerCluster,
                                onStep: onStep
                            )
                            return (globalIdx, insight)
                        } catch {
                            Log.error("[MultiChain] Cluster \(globalIdx) failed: \(error)", category: .llm)
                            return (globalIdx, nil)
                        }
                    }
                }

                var results: [(Int, MultiChainResult.ClusterInsight?)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }

            // Collect successful results and update progressive confidence
            for (_, insight) in batchResults {
                if let insight = insight {
                    clusterInsights.append(insight)
                    totalTokens += insight.tokensUsed
                    clusterIndex += 1

                    // Update progressive confidence: each cluster adds toward 85% (synthesis adds final 15%)
                    progressiveConfidence = min(0.85, Float(clusterInsights.count) / Float(documentClusters.count) * 0.85)

                    // Emit progress step with updated confidence
                    let progressStep = ThinkingStep(
                        id: UUID(),
                        type: .analyzing,
                        input: insight.clusterName,
                        output: "Completed \(clusterInsights.count)/\(documentClusters.count) clusters",
                        tokensUsed: insight.tokensUsed,
                        duration: 0.5,
                        timestamp: Date(),
                        confidence: progressiveConfidence
                    )
                    await onStep?(progressStep)
                }
            }
        }

        Log.info("[MultiChain] Completed \(clusterInsights.count) cluster chains, \(totalTokens) tokens", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Final synthesis across all cluster insights
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        progressiveConfidence = 0.88 // Synthesis starting

        let synthesisStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Cross-cluster synthesis",
            output: "Integrating findings from \(clusterInsights.count) research clusters...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: progressiveConfidence
        )
        await onStep?(synthesisStep)

        let finalAnswer = try await synthesizeClusterInsights(
            query: query,
            clusterInsights: clusterInsights,
            synthesisSessions: config.synthesisSessions
        )

        totalTokens += finalAnswer.tokensUsed

        let totalDuration = Date().timeIntervalSince(startTime)
        let totalSessions = clusterInsights.reduce(0) { $0 + $1.sessionsRun } + config.synthesisSessions

        // Emit final completion step with 95% confidence
        let completionStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Multi-chain complete",
            output: "Synthesized \(clusterInsights.count) cluster analyses into comprehensive answer",
            tokensUsed: finalAnswer.tokensUsed,
            duration: totalDuration,
            timestamp: Date(),
            confidence: 0.95
        )
        await onStep?(completionStep)

        Log.info("[MultiChain] COMPLETE: \(totalSessions) sessions, \(totalTokens) tokens, \(String(format: "%.1f", totalDuration))s", category: .llm)

        return MultiChainResult(
            finalAnswer: finalAnswer.text,
            clusterInsights: clusterInsights,
            totalTokens: totalTokens,
            totalSessions: totalSessions,
            totalDuration: totalDuration,
            confidence: 0.95 // Multi-chain is inherently high confidence
        )
    }

    /// Cluster chunks by source document for parallel processing
    private func clusterChunksByDocument(
        chunks: [RetrievedChunk],
        maxClusters: Int,
        minDocsPerCluster: Int
    ) -> [DocumentCluster] {
        // Group chunks by source document
        var docToChunks: [String: [RetrievedChunk]] = [:]
        for chunk in chunks {
            let docName = chunk.sourceDocument
            docToChunks[docName, default: []].append(chunk)
        }

        // Sort documents by total relevance (sum of chunk scores)
        let sortedDocs = docToChunks.keys.sorted { doc1, doc2 in
            let score1 = docToChunks[doc1]!.reduce(0.0) { $0 + $1.similarityScore }
            let score2 = docToChunks[doc2]!.reduce(0.0) { $0 + $1.similarityScore }
            return score1 > score2
        }

        // Distribute documents into clusters
        let numClusters = min(maxClusters, max(1, sortedDocs.count / minDocsPerCluster))
        var clusters: [DocumentCluster] = (0 ..< numClusters).map { idx in
            DocumentCluster(name: "Research Cluster \(idx + 1)", documents: [], chunks: [])
        }

        // Round-robin distribution to balance cluster sizes
        for (idx, docName) in sortedDocs.enumerated() {
            let clusterIdx = idx % numClusters
            clusters[clusterIdx].documents.append(docName)
            clusters[clusterIdx].chunks.append(contentsOf: docToChunks[docName]!)
        }

        // Sort chunks within each cluster by relevance
        for i in 0 ..< clusters.count {
            clusters[i].chunks.sort { $0.similarityScore > $1.similarityScore }
        }

        return clusters.filter { !$0.chunks.isEmpty }
    }

    /// Execute a reasoning chain for a single document cluster
    private func executeClusterChain(
        query: String,
        clusterName: String,
        chunks: [RetrievedChunk],
        clusterIndex: Int,
        sessionsPerCluster: Int,
        onStep: ((ThinkingStep) async -> Void)?
    ) async throws -> MultiChainResult.ClusterInsight {
        guard ragService != nil else { 
            throw AgenticError.serviceUnavailable
        }

        Log.info("[MultiChain] Cluster \(clusterIndex + 1) (\(clusterName)): \(chunks.count) chunks, \(sessionsPerCluster) sessions", category: .llm)

        // Use the per-cluster chain config
        let clusterConfig = ReasoningChainConfig(
            sessionCount: sessionsPerCluster,
            maxContextPerSession: 3200,
            maxInsightLength: 2000
        )

        // Run the reasoning chain for this cluster
        let chainResult = try await executeReasoningChain(
            query: query,
            chunks: chunks,
            config: clusterConfig,
            onStep: { step in
                // Tag steps with cluster info
                let taggedStep = ThinkingStep(
                    id: step.id,
                    type: step.type,
                    input: "[\(clusterName)] \(step.input)",
                    output: step.output,
                    tokensUsed: step.tokensUsed,
                    duration: step.duration,
                    timestamp: step.timestamp,
                    confidence: step.confidence
                )
                await onStep?(taggedStep)
            }
        )

        let docNames = Array(Set(chunks.map { $0.sourceDocument }))

        return MultiChainResult.ClusterInsight(
            clusterName: clusterName,
            documents: docNames,
            insight: chainResult.finalAnswer,
            chainInsights: chainResult.chainInsights, // Preserve session-level insights
            tokensUsed: chainResult.totalTokens,
            sessionsRun: chainResult.sessionCount
        )
    }

    /// Synthesize insights from all clusters into final answer
    private func synthesizeClusterInsights(
        query: String,
        clusterInsights: [MultiChainResult.ClusterInsight],
        synthesisSessions: Int
    ) async throws -> (text: String, tokensUsed: Int) {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // Build synthesis prompt with all cluster insights
        var synthesisInput = "RESEARCH QUESTION: \(query)\n\n"
        synthesisInput += "FINDINGS FROM \(clusterInsights.count) RESEARCH CLUSTERS:\n\n"

        for (idx, cluster) in clusterInsights.enumerated() {
            synthesisInput += "━━━ CLUSTER \(idx + 1): \(cluster.clusterName) ━━━\n"
            synthesisInput += "Documents: \(cluster.documents.joined(separator: ", "))\n"
            synthesisInput += "Key Findings:\n\(cluster.insight)\n\n"
        }

        // Truncate if needed to fit in context (leave room for instructions)
        let maxChars = 6000 // ~1500 tokens
        if synthesisInput.count > maxChars {
            synthesisInput = String(synthesisInput.prefix(maxChars)) + "\n[...truncated for synthesis]"
        }

        let synthesisPrompt = """
        \(synthesisInput)

        TASK: Synthesize ALL cluster findings into ONE comprehensive, publication-quality answer.

        REQUIREMENTS:
        - Integrate findings across ALL clusters - don't just summarize each separately
        - Identify common themes, contradictions, and complementary evidence
        - Use headers (##) for major themes, bullets for details
        - Include specific statistics, study names, and methodologies
        - Discuss implications and limitations
        - Target 1000+ words for thorough coverage

        COMPREHENSIVE SYNTHESIS:
        """

        let systemPrompt = """
        You are a meta-analysis expert synthesizing research findings from multiple document clusters.
        Your goal is to produce an integrated, scholarly answer that weaves together all evidence.
        Be exhaustive and include all relevant details from every cluster.
        """

        var totalTokens = 0
        var finalAnswer = ""

        // Run synthesis sessions
        for sessionIdx in 0 ..< synthesisSessions {
            let isLast = sessionIdx == synthesisSessions - 1
            let prompt = sessionIdx == 0 ? synthesisPrompt : """
            Continue and deepen the synthesis. Previous progress:
            \(String(finalAnswer.suffix(2000)))

            Add more detail, identify additional connections, and ensure completeness.
            """

            let response = try await ragService.generateWithProperConsent(
                prompt: prompt,
                context: "",
                systemPrompt: systemPrompt,
                maxTokens: isLast ? 1500 : 1000
            )

            if sessionIdx == 0 {
                finalAnswer = response.text
            } else {
                finalAnswer += "\n\n" + response.text
            }
            totalTokens += response.tokensGenerated
        }

        return (finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines), totalTokens)
    }

    /// Gather ALL relevant chunks from the library for comprehensive multi-chain analysis
    /// This retrieves more chunks than the initial search to enable thorough cluster analysis
    private func gatherAllRelevantChunks(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> [RetrievedChunk] {
        Log.info("[MultiChain] Gathering comprehensive chunks for multi-chain analysis", category: .retrieval)

        // Start with initial chunks
        var allChunks = initialChunks

        // Get broader retrieval - up to 50 chunks for comprehensive coverage
        let broadChunks = try await ragService.searchDocumentsRaw(
            query: query,
            topK: 50,
            minSimilarity: 0.20 // Lower threshold to catch more relevant content
        )

        // Merge unique chunks
        for chunk in broadChunks {
            if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                allChunks.append(chunk)
            }
        }

        // Also try some query variations to catch different aspects
        let queryVariations = generateQueryVariations(query: query)
        for variation in queryVariations.prefix(3) { // Limit to 3 variations
            let variantChunks = try await ragService.searchDocumentsRaw(
                query: variation,
                topK: 20,
                minSimilarity: 0.25
            )
            for chunk in variantChunks {
                if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allChunks.append(chunk)
                }
            }
        }

        Log.info("[MultiChain] Gathered \(allChunks.count) total chunks for multi-chain processing", category: .retrieval)
        return allChunks
    }

    /// Generate query variations to improve retrieval coverage
    private func generateQueryVariations(query: String) -> [String] {
        var variations: [String] = []

        // Extract key terms for variation
        let words = query.lowercased().split(separator: " ").map(String.init)
        let stopWords = Set(["what", "are", "the", "all", "of", "in", "is", "a", "an", "for", "to", "and", "or"])
        let keyTerms = words.filter { !stopWords.contains($0) && $0.count > 3 }

        // Create focused variations
        if keyTerms.count >= 2 {
            variations.append(keyTerms.prefix(3).joined(separator: " "))
            variations.append(keyTerms.suffix(3).joined(separator: " "))
        }

        // Add common research-oriented variations
        let researchPrefixes = ["findings about", "research on", "evidence for", "studies of"]
        if let mainTopic = keyTerms.first {
            for prefix in researchPrefixes.prefix(2) {
                variations.append("\(prefix) \(mainTopic)")
            }
        }

        return variations
    }

    /// Build prompt for a specific position in the reasoning chain
    private func buildChainPrompt(
        sessionIndex: Int,
        sessionCount: Int,
        query: String,
        context: String,
        previousInsights: [String],
        maxInsightLength: Int
    ) -> (prompt: String, systemPrompt: String) {
        let insightSummary = previousInsights.isEmpty
            ? ""
            : "PRIOR INSIGHTS:\n" + previousInsights.enumerated()
                .map { "[\($0.offset + 1)] \($0.element)" }
                .joined(separator: "\n")

        switch sessionIndex {
        case 0:
            // SESSION 1: Initial Analysis - understand the question and context
            let systemPrompt = "You are analyzing documents to answer a question. Extract specific details: numbers, durations, steps."
            let prompt = """
            QUESTION: \(query)

            DOCUMENTS:
            \(context)

            TASK: Analyze these documents. What specific facts answer the question?
            Look for exact numbers, durations, steps, or procedures.

            Format: REASONING: [your analysis] → INSIGHT: [specific finding with details]
            """
            return (prompt, systemPrompt)

        case sessionCount - 1:
            // FINAL SESSION: Synthesis - combine all insights into complete answer
            let systemPrompt = """
            You synthesize research findings into exhaustive, comprehensive answers.
            Include ALL specific details from prior insights.
            Use bullet points and organized sections.
            Be thorough - include every responsibility, step, requirement, or specification found.
            """
            let prompt = """
            QUESTION: \(query)

            YOUR RESEARCH FINDINGS(synthesize ALL of these - do not omit any detail):
            \(insightSummary)

            SUPPORTING DOCUMENTS:
            \(context.prefix(3000))

            TASK: Write an EXHAUSTIVE answer that includes:
                - Every responsibility, duty, or task mentioned
                - All specific numbers, dates, durations, and deadlines
                - Complete step - by - step procedures(all steps, in order)
                - All requirements, qualifications, or criteria
                - Any exceptions, notes, or special cases

            Use bullet points and clear sections.Do NOT summarize - include the FULL detail.

            YOUR COMPREHENSIVE ANSWER:
            """
            return (prompt, systemPrompt)

        case 1:
            // SESSION 2: Pattern Recognition - look for connections
            let systemPrompt = "You find patterns and specific details. Look for exact specifications."
            let prompt = """
            QUESTION: \(query)

            \(insightSummary)

            NEW CONTEXT:
            \(context)

            TASK: What additional specific details do you find?
            Build on previous insights with new information.

            Format: REASONING: [new details found] → INSIGHT: [additional specifics]
            """
            return (prompt, systemPrompt)

        default:
            // MIDDLE SESSIONS: Deepen understanding
            let systemPrompt = "You deepen understanding by finding specific details others might miss."
            let prompt = """
            QUESTION: \(query)

            \(insightSummary)

            NEW CONTEXT:
            \(context)

            TASK: What new aspects or specific details do you notice?
            Add to previous insights.

            Format: REASONING: [observations] → INSIGHT: [refined understanding with specifics]
            """
            return (prompt, systemPrompt)
        }
    }

    /// Extract insight from response - keep FULL content, just clean up formatting
    /// We want ALL the details the model found, not truncated snippets!
    private func extractInsight(from text: String, maxLength: Int) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If there's an INSIGHT: marker, prefer that section but keep it full
        if let insightRange = result.range(of: "INSIGHT:", options: .caseInsensitive) {
            result = String(result[insightRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If there's REASONING: → INSIGHT:, skip the reasoning part
        else if let arrowRange = result.range(of: "→") {
            let afterArrow = String(result[arrowRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove "INSIGHT:" prefix if present
            if afterArrow.lowercased().hasPrefix("insight:") {
                result = String(afterArrow.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if afterArrow.count > 100 {
                result = afterArrow
            }
        }

        // Remove common prefixes that aren't useful
        let prefixesToRemove = ["REASONING:", "ANALYSIS:", "OBSERVATION:"]
        for prefix in prefixesToRemove {
            if result.lowercased().hasPrefix(prefix.lowercased()) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Only truncate if REALLY necessary (way over budget)
        // maxLength is now 1500-2500, so this is a safety valve not a bottleneck
        if result.count > maxLength {
            // Try to truncate at a sentence boundary
            let truncated = String(result.prefix(maxLength))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                return String(truncated[...lastPeriod])
            }
            return truncated + "..."
        }

        return result
    }

    /// Extract full final answer from synthesis session (no truncation!)
    private func extractFinalAnswer(from text: String) -> String {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Look for explicit answer markers (in priority order)
        let answerMarkers = [
            "YOUR COMPREHENSIVE ANSWER:",
            "YOUR ANSWER:",
            "FINAL ANSWER:",
            "Answer:",
            "ANSWER:"
        ]

        for marker in answerMarkers {
            if let answerRange = cleanedText.range(of: marker, options: .caseInsensitive) {
                return String(cleanedText[answerRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Look for content after "→" (arrow used in our formatting)
        if let arrowRange = cleanedText.range(of: "→") {
            let afterArrow = String(cleanedText[arrowRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if afterArrow.count > 50 { // Make sure there's substantial content
                return afterArrow
            }
        }

        // Remove any "REASONING:" prefix and return the rest
        if let reasoningRange = cleanedText.range(of: "REASONING:", options: .caseInsensitive) {
            // Check if there's content before REASONING (that's the answer)
            let beforeReasoning = String(cleanedText[..<reasoningRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeReasoning.count > 50 {
                return beforeReasoning
            }
        }

        // Just return the full text - it IS the answer
        return cleanedText
    }

    /// Parse confidence score from text
    private func parseConfidence(from text: String) -> Float? {
        // Look for patterns like "confidence: 85" or "85%"
        let patterns = [
            #"confidence[:\s]+(\d+)"#,
            #"(\d+)%\s*confidence"#,
            #"(\d+)/100"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let numRange = Range(match.range(at: 1), in: text),
               let value = Float(text[numRange])
            {
                return value > 1 ? value / 100 : value
            }
        }

        return nil
    }

    /// Description of what each session focuses on
    private func sessionPromptDescription(_ index: Int, _ total: Int) -> String {
        switch index {
        case 0: return "Initial Analysis"
        case total - 1: return "Final Synthesis"
        case 1: return "Pattern Recognition"
        default: return "Deepening Understanding"
        }
    }
}

// MARK: - RAGService Extension

extension RAGService {

    /// Execute a light reasoning chain for Standard mode
    /// Uses 3 sessions × 4096 = 12K+ effective tokens (vs single 4K)
    ///
    /// ## When to Use
    /// - Standard mode with good retrieval quality (top similarity > 0.5)
    /// - Complex multi-hop questions that benefit from deeper analysis
    /// - When context exceeds single session budget
    ///
    /// This is a lighter version of Deep Think's reasoning chain:
    /// - 3 sessions instead of 4-5
    /// - Faster execution for responsive Standard mode
    /// - Still multiplies effective context by 3×
    func executeStandardReasoningChain(
        query: String,
        chunks: [RetrievedChunk],
        onProgress: ((String, String) async -> Void)? = nil  // (title, detail)
    ) async throws -> ReasoningChainResult {
        let orchestrator = AgenticOrchestrator(ragService: self, config: .fast)
        let totalSessions = ReasoningChainConfig.light.sessionCount

        // Track session number for UI
        var sessionNum = 0

        // Emit progress for UI with meaningful descriptions
        let onStep: (ThinkingStep) async -> Void = { step in
            sessionNum += 1

            // Build a nice title showing progress
            let phaseEmoji: String
            let phaseName: String

            switch step.type {
            case .searching:
                phaseEmoji = "🔍"
                phaseName = "Analyzing evidence"
            case .analyzing:
                phaseEmoji = "🧠"
                phaseName = "Finding patterns"
            case .synthesizing:
                phaseEmoji = "✨"
                phaseName = "Synthesizing answer"
            default:
                phaseEmoji = "💭"
                phaseName = "Reasoning"
            }

            let title = "\(phaseEmoji) \(phaseName) (\(sessionNum)/\(totalSessions))"

            // Show a snippet of what the model discovered (first 80 chars of insight)
            let insightPreview = step.output
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = insightPreview.isEmpty
                ? "Processing..."
                : String(insightPreview.prefix(80)) + (insightPreview.count > 80 ? "..." : "")

            await onProgress?(title, detail)
        }

        return try await orchestrator.executeReasoningChain(
            query: query,
            chunks: chunks,
            config: .light, // 3 sessions for Standard mode
            onStep: onStep
        )
    }

    /// Generate with a fresh session (no accumulated context)
    /// Used by AgenticOrchestrator for each thinking step
    func generateWithFreshSession(prompt: String, maxTokens: Int) async throws -> LLMResponse {
        #if canImport(FoundationModels)
            // Create a temporary AppleFoundationLLMService for isolated generation
            let tempService = AppleFoundationLLMService()

            // Ensure cleanup on exit
            defer {
                tempService.resetSession(clearTools: true)
            }

            let config = InferenceConfig(
                maxTokens: maxTokens,
                temperature: 0.7,
                systemPrompt: "You are a focused research assistant. Be concise and precise."
            )

            return try await tempService.generate(
                prompt: prompt,
                context: nil,
                config: config
            )
        #else
            throw LLMError.modelUnavailable
        #endif
    }

    /// Generate with proper PCC consent flow - used for Deep Think final synthesis
    /// This goes through the main LLM service with full consent prompts and transmission recording
    /// Matches Standard mode's quality and consent behavior
    func generateWithProperConsent(
        prompt: String,
        context: String,
        systemPrompt: String,
        maxTokens: Int
    ) async throws -> LLMResponse {
        var config = InferenceConfig(
            maxTokens: maxTokens,
            temperature: 0.5, // Lower temperature for more focused answers
            systemPrompt: systemPrompt
        )
        // NOTE: Tools remain ENABLED for reasoning chain sessions
        // The model can autonomously call search_documents to gather more context as it reasons

        // Check network and PCC eligibility
        let networkAvailable = NetworkMonitor.shared.isConnected
        let pccSuppressed = await MainActor.run { self.isPCCSuppressedForDeepThink() }
        let isAppleFM = llmService is AppleFoundationLLMService

        // Determine if PCC is eligible for this request
        let pccEligible = isAppleFM && networkAvailable && !pccSuppressed

        if pccEligible {
            // Check current consent state
            let consentState = await MainActor.run { cloudConsent[.applePCC] ?? .notDetermined }
            let hasTransientGrant = await MainActor.run { self.hasTransientPCCGrant() }

            // Only prompt for consent if not already granted
            if consentState != .allowed && !hasTransientGrant {
                // Call ensureConsentForDeepThink to trigger the consent UI prompt
                // This matches Standard mode's behavior exactly
                do {
                    try await ensureConsentForDeepThink(
                        service: llmService,
                        prompt: prompt,
                        context: context,
                        sourceChunks: [], // Deep Think doesn't pass raw chunks here
                        allowPrivateCloudCompute: true
                    )
                } catch {
                    // If consent denied, fall back to on-device only
                    if case RAGServiceError.cloudConsentDenied = error {
                        config.allowPrivateCloudCompute = false
                        config.executionContext = .onDeviceOnly
                        Log.info("[DeepThink] PCC consent denied → on-device fallback", category: .pipeline)
                    } else {
                        throw error
                    }
                }
            }

            // Set PCC config based on consent outcome
            let finalConsentState = await MainActor.run { cloudConsent[.applePCC] ?? .notDetermined }
            let finalHasGrant = await MainActor.run { self.hasTransientPCCGrant() }

            if finalConsentState == .allowed || finalHasGrant {
                config.allowPrivateCloudCompute = true
                config.executionContext = .automatic
            } else {
                config.allowPrivateCloudCompute = false
                config.executionContext = .onDeviceOnly
            }
        } else {
            // Not PCC eligible - use on-device only
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
            if !networkAvailable {
                Log.info("[DeepThink] Offline → on-device only", category: .pipeline)
            }
        }

        return try await llmService.generate(
            prompt: prompt,
            context: context,
            config: config
        )
    }
}
