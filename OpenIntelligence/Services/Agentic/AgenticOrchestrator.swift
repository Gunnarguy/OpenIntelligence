//
//  AgenticOrchestrator.swift
//  OpenIntelligence
//
//  Retrieval-first agentic reasoning that escalates based on confidence.
//  Key insight: Don't decide complexity upfront - let retrieval results guide the pipeline.
//

import Foundation
import os

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
        case verifying = "✅ Verifying answer"

        /// Display name for UI
        var displayName: String { rawValue }

        /// Map to ThinkingEvent.Kind for UI integration
        /// Every step type here maps to the kind that describes what it actually
        /// does. It previously collapsed eight step types onto four kinds, and two
        /// of those collapses were wrong in a user-visible way:
        ///
        ///   - `.analyzing` is a multi-session reasoning pass, and it mapped to
        ///     `.rerank`. Device traces and the live UI therefore showed
        ///     "RE-RANKING · Session 6/50" for work that never touched the reranker,
        ///     fifteen or twenty rows in a row.
        ///   - `.verifying` is the verification gate, and it mapped to `.rerank` too,
        ///     which is why `.verification` never appeared in any trace despite the
        ///     gates running on every query.
        ///
        /// `.reformulating` and `.expanding` were also folded into plain `.retrieval`,
        /// hiding query rewriting and iterative expansion as undifferentiated
        /// "Retrieval". Each now reports itself.
        var thinkingKind: ThinkingEvent.Kind {
            switch self {
            case .planning: return .planning
            case .searching: return .retrieval
            case .reformulating: return .queryRewrite
            case .expanding: return .iterative
            case .analyzing: return .reasoning
            case .verifying: return .verification
            case .synthesizing: return .generation
            case .refining: return .selfRag
            }
        }
    }
}

/// Extension to map ThinkingEvent.Kind back to ThinkingStep.StepType for verbose pipeline events
extension ThinkingEvent.Kind {
    /// Convert ThinkingEvent.Kind to ThinkingStep.StepType for detailed event forwarding
    nonisolated var toStepType: ThinkingStep.StepType {
        switch self {
        case .planning, .agentic:
            return .planning
        case .embedding, .retrieval, .hyde, .queryRewrite, .bm25, .vectorSearch, .parentDoc, .iterative:
            return .searching
        case .rerank, .rrf, .mmr:
            return .analyzing
        case .gating, .grounding, .selfRag, .factBank, .verification, .confidence, .reasoning:
            return .analyzing
        case .context, .compression, .lostInMiddle, .graphPack:
            return .expanding
        case .generation, .toolCall, .extractive:
            return .synthesizing
        case .fallback, .warning:
            return .refining
        case .intentRoute:
            return .planning
        case .imagePlayground:
            return .synthesizing
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
    /// Quality mode from user settings — controls retrieval parameters (topK, minSimilarity,
    /// mmrLambda, parent doc retrieval, compression, etc.) across all pipeline steps.
    /// Without this, Deep Think/Maximum use hardcoded defaults that ignore user's mode selection.
    let qualityMode: RAGQualityMode

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

    init(ragService: RAGService, config: AgenticConfig = .defaultConfig, qualityMode: RAGQualityMode = .deepThink) {
        self.ragService = ragService
        self.config = config
        self.qualityMode = qualityMode
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

    /// Create a detailed event forwarder that emits verbose ThinkingView events
    /// This bridges the onStep callback to the detailed event format used by executeFullRetrievalPipeline
    private func makeDetailedEventForwarder(
        onStep: ((ThinkingStep) async -> Void)?
    ) -> (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? {
        guard let onStep = onStep else { return nil }
        return { @Sendable kind, title, detail in
            // Create a lightweight ThinkingStep for detailed pipeline events
            // These are verbose sub-steps that show retrieval internals
            // IMPORTANT: Encode the original ThinkingEvent.Kind in the output so we can
            // recover it in RAGService.onStep. Format: "KIND|Title: Detail"
            // This preserves specific kinds like .vectorSearch, .bm25, .mmr which would
            // otherwise be lost when mapped through the coarse ThinkingStep.StepType
            let detailStep = ThinkingStep(
                id: UUID(),
                type: kind.toStepType,
                input: "",
                output: "\(kind.rawValue)|\(title): \(detail)",
                tokensUsed: 0, // No tokens for pipeline events
                duration: 0,
                timestamp: Date()
            )
            await onStep(detailStep)
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
        let __spAgenticExecute = PipelineSignposts.synthesis.beginInterval("AgenticExecute")
        defer { PipelineSignposts.synthesis.endInterval("AgenticExecute", __spAgenticExecute) }
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
        // Removed redundant planning step that was breaking ThinkingStreamView.
        // executeFullRetrievalPipeline already emits .planning as the first pipeline event.

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Multi-Query Retrieval (universal semantic coverage)
        // Generate diverse search queries to find relevant content from ANY angle
        // This is the key fix for "oil type" vs "oil pressure" mismatches
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        Log.info("[Agentic] Step 1: Multi-query retrieval for universal coverage", category: .llm)

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        // Generate diverse search queries using LLM
        let searchQueries = try await generateSearchQueries(originalQuery: query, ragService: ragService)

        // Announce planning phase via detailed forwarder (console spirit)
        await detailedForwarder?(.planning, "Planning", "Searching with \(searchQueries.count) query variations")
        logStepTokens("Query Generation", 50)

        // Execute multi-query search with RRF fusion
        let (multiQueryStep, initialChunks) = try await executeMultiQuerySearch(
            queries: searchQueries,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
        )
        steps.append(multiQueryStep)
        logStepTokens("Multi-Query Search", multiQueryStep.tokensUsed)
        allRetrievedChunks.append(contentsOf: initialChunks)
        await onStep?(multiQueryStep)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Hard Relevance Gate (CRITICAL - prevents hallucination)
        // Check that retrieved content actually addresses the question
        // If not, exit early with "not found" instead of hallucinating
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        var retrievalQuality = evaluateRetrievalQuality(chunks: initialChunks, query: query)

        // HARD CHECK 1: Lexical relevance - do query keywords appear in chunks?
        let lexicalRelevance = checkLexicalRelevance(query: query, chunks: initialChunks)

        // HARD CHECK 2: Semantic intent - does content address the question?
        let (intentValid, intentReason) = try await validateSemanticIntent(
            query: query,
            chunks: initialChunks,
            ragService: ragService
        )

        Log.info("[Agentic] Relevance check: lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), intent=\(intentValid)", category: .retrieval)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // HARD EXIT: If both checks fail, don't try to salvage - just say "not found"
        // This prevents the "8 sessions of philosophical rambling" problem
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if lexicalRelevance < AgenticPolicyService.hardIrrelevanceLexicalThreshold() && !intentValid {
            Log.warning("[Agentic] HARD EXIT: Retrieved content is irrelevant (lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), intent=false)", category: .retrieval)

            let notFoundStep = ThinkingStep(
                id: UUID(),
                type: .analyzing,
                input: "Relevance check",
                output: "Retrieved content doesn't match the query. The documents may not contain information about this topic.",
                tokensUsed: 0,
                duration: 0.1,
                timestamp: Date()
            )
            steps.append(notFoundStep)
            await onStep?(notFoundStep)

            // Return honest "not found" instead of hallucinating
            let notFoundAnswer = """
            I couldn't find information about "\(query)" in your documents.

            The retrieved content didn't match your question.

            **Suggestions:**
            - Check if your documents contain information about this topic
            - Try rephrasing your question with different keywords
            """

            return AgenticResult(
                finalAnswer: notFoundAnswer,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: 0.0, // Honest: we found nothing
                sourcesUsed: 0,
                retrievedChunks: []
            )
        }

        // Downgrade quality if semantic intent doesn't match but lexical has some overlap
        if !intentValid && (retrievalQuality == .excellent || retrievalQuality == .good) {
            Log.info("[Agentic] Semantic intent mismatch - downgrading from \(retrievalQuality.description) to moderate", category: .llm)
            retrievalQuality = AgenticPolicyService.downgradedForSemanticMismatch(retrievalQuality)
        }

        Log.info("[Agentic] Retrieval quality: \(retrievalQuality.description), Intent valid: \(intentValid)", category: .llm)

        // Emit evaluation step so user sees the reasoning
        let evalStep = ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Evaluating \(initialChunks.count) results",
            output: "Confidence: \(retrievalQuality.description) (\(String(format: "%.0f%%", retrievalQuality.confidenceScore * 100)))\nSemantic match: \(intentValid ? "✓" : "✗") \(intentReason)",
            tokensUsed: 0,
            duration: 0.05,
            timestamp: Date()
        )
        steps.append(evalStep)
        await onStep?(evalStep)

        // NOTE: ExtractiveQA pre-check removed. Never skip multi-session reasoning.
        // The heuristic extractor produced false positives (e.g., "three-quarters" for
        // "fuel tank capacity") and short-circuited LLM reasoning entirely. All queries
        // now proceed through multi-session reasoning for reliable answers.

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2.5: Graph Expansion (GraphRAG-lite)
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if retrievalQuality == .moderate || retrievalQuality == .low {
            let (expansionStep, expandedChunks) = try await executeGraphExpansion(
                query: query,
                initialChunks: initialChunks,
                ragService: ragService,
                onDetailedEvent: detailedForwarder
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
        // STEP 2.7: Cross-Reference Resolution
        // Technical documents often say "see section X on page Y" — the actual
        // data (spec tables, procedures) lives in the referenced section but
        // the reranker scores the prose cross-reference higher than the table.
        // Follow ALL cross-references to ensure the answer chunk is in the pool.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let crossRefChunks = try await resolveCrossReferences(
            chunks: allRetrievedChunks,
            query: query,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
        )
        if !crossRefChunks.isEmpty {
            for chunk in crossRefChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                allRetrievedChunks.append(chunk)
            }
            // Re-evaluate quality with cross-referenced chunks included
            retrievalQuality = evaluateRetrievalQuality(chunks: allRetrievedChunks, query: query)
            Log.info("[Agentic] Cross-reference resolution added \(crossRefChunks.count) chunks, quality: \(retrievalQuality.description)", category: .llm)
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
            // MAXIMUM MODE: TRUE UNLIMITED - runs until 98% confident
            // NOT a fixed pipeline - an adaptive loop that keeps going
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if config.isUnlimited {
                Log.info("[Agentic] MAXIMUM MODE: TRUE UNLIMITED reasoning until 98% confident", category: .llm)

                // First, gather ALL chunks from the library for comprehensive analysis
                // Pass detailedForwarder for full pipeline visibility in console
                let allChunksForMultiChain = try await gatherAllRelevantChunks(
                    query: query,
                    initialChunks: sortedChunks,
                    ragService: ragService,
                    onDetailedEvent: detailedForwarder
                )

                let unlimitedResult = try await executeTrueUnlimitedReasoning(
                    query: query,
                    allChunks: allChunksForMultiChain,
                    targetConfidence: config.confidenceThreshold, // 0.98 for unlimited
                    maxSessions: config.maxSteps, // 50 for unlimited
                    onStep: onStep
                )

                // Add all steps to result
                steps.append(contentsOf: unlimitedResult.steps)
                totalTokens += unlimitedResult.totalTokens
                logStepTokens("Unlimited (\(unlimitedResult.sessionsRun) sessions)", unlimitedResult.totalTokens)

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // SELF-RAG 2.0: Verify Maximum mode actually answered the question
                // 41 sessions means nothing if the answer is off-topic garbage
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                do {
                    Log.info("[Agentic] Maximum Mode: Running Self-RAG 2.0 verification", category: .llm)

                    let verification = await verifySelfRAG(
                        query: query,
                        answer: unlimitedResult.finalAnswer,
                        sourceChunks: allChunksForMultiChain,
                        ragService: ragService
                    )

                    let verifyStep = ThinkingStep(
                        id: UUID(),
                        type: .verifying,
                        input: "Self-RAG verification",
                        output: verification.summary,
                        tokensUsed: 0,
                        duration: 0.1,
                        timestamp: Date(),
                        confidence: verification.calibratedConfidence
                    )
                    steps.append(verifyStep)
                    await onStep?(verifyStep)

                    // Use calibrated confidence, but respect the work done
                    // If 41 sessions achieved 98%, don't crash to 40% unless answer is truly bad
                    // FIXED 2026-01: Previous version was too aggressive, discarding valid answers
                    let sessionConfidence = unlimitedResult.confidence
                    let verifyConfidence = verification.calibratedConfidence
                    let finalConfidence = AgenticPolicyService.blendVerifiedFinalConfidence(
                        sessionConfidence: sessionConfidence,
                        verificationConfidence: verifyConfidence,
                        addressesQuestion: verification.addressesQuestion
                    )

                    Log.info("[Agentic] Maximum Mode: Calibrated confidence \(Int(sessionConfidence * 100))% → \(Int(finalConfidence * 100))% (addresses question: \(verification.addressesQuestion))", category: .llm)

                    return AgenticResult(
                        finalAnswer: unlimitedResult.finalAnswer,
                        steps: steps,
                        totalTokens: totalTokens,
                        totalDuration: Date().timeIntervalSince(startTime),
                        confidence: finalConfidence,
                        sourcesUsed: allChunksForMultiChain.count,
                        retrievedChunks: allChunksForMultiChain
                    )
                }
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

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // FALLBACK: If reasoning chain indicates retrieval miss, try recursive research
            // This catches cases where initial retrieval grabbed wrong content (e.g., "oil pressure" vs "oil type")
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if answerIndicatesRetrievalMiss(chainResult.finalAnswer) {
                Log.info("[Agentic] Answer indicates retrieval miss - falling back to recursive research", category: .llm)

                let recursiveResult = try await executeRecursiveResearch(
                    query: query,
                    maxIterations: 5,
                    onStep: onStep
                )

                // If recursive research found a better answer, use it
                // The dump guard matters as much as the miss guard: this branch only
                // asked whether the replacement was *also* flagged as a miss, never
                // whether it was actually an answer. A raw evidence dump is flagged
                // by neither, so it won every time it appeared.
                let cleanRecursiveAnswer = recursiveResult.finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanRecursiveAnswer.isEmpty
                    && !answerIndicatesRetrievalMiss(recursiveResult.finalAnswer)
                    && !looksLikeRawEvidenceDump(cleanRecursiveAnswer) {
                    Log.info("[Agentic] Recursive research found answer after \(recursiveResult.steps.count) steps", category: .llm)
                    steps.append(contentsOf: recursiveResult.steps)
                    return AgenticResult(
                        finalAnswer: recursiveResult.finalAnswer,
                        steps: steps,
                        totalTokens: totalTokens + recursiveResult.totalTokens,
                        totalDuration: Date().timeIntervalSince(startTime),
                        confidence: recursiveResult.confidence,
                        sourcesUsed: recursiveResult.sourcesUsed,
                        retrievedChunks: recursiveResult.retrievedChunks
                    )
                }
                Log.debug("[Agentic] Recursive research also couldn't find answer - using original chain result", category: .llm)
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // SELF-RAG 2.0: Verify answer before returning (Deep Think mode only)
            // 2026 best practice: Don't just generate — verify citations and relevance
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let isDeepThinkMode = config.maxSteps >= 8 && !config.isUnlimited
            if isDeepThinkMode {
                return try await runVerificationLoop(
                    query: query,
                    initialAnswer: chainResult.finalAnswer,
                    initialSteps: steps,
                    initialTokens: totalTokens,
                    initialConfidence: chainResult.confidence,
                    initialSources: allRetrievedChunks,
                    ragService: ragService,
                    startTime: startTime,
                    onStep: onStep
                )
            }

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
                retrievedContext: multiQueryStep.output,
                ragService: ragService
            ), refinedQuery != query {
                let (refinedStep, refinedChunks) = try await executeSearchStepWithChunks(
                    subQuery: refinedQuery,
                    ragService: ragService,
                    onDetailedEvent: detailedForwarder
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

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // SELF-RAG 2.0: Verify answer before returning (Deep Think mode)
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let isDeepThinkMode = config.maxSteps >= 8 && !config.isUnlimited
            if isDeepThinkMode {
                return try await runVerificationLoop(
                    query: query,
                    initialAnswer: chainResult.finalAnswer,
                    initialSteps: steps,
                    initialTokens: totalTokens,
                    initialConfidence: chainResult.confidence,
                    initialSources: allRetrievedChunks,
                    ragService: ragService,
                    startTime: startTime,
                    onStep: onStep
                )
            }

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
                retrievedContext: multiQueryStep.output,
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
                    ragService: ragService,
                    onDetailedEvent: detailedForwarder
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
                    let combinedResults = multiQueryStep.output + "\n\n---\n\n" + reformulatedSearchStep.output

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

            let combinedResults = multiQueryStep.output
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
                confidence: AgenticPolicyService.moderateReturnConfidence(for: retrievalQuality),
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
            let isExhaustiveQuery = queryRequiresExhaustiveAnswer(query)
            let effectiveThreshold = AgenticPolicyService.speculativeAcceptanceThreshold(
                config: config,
                requiresExhaustiveAnswer: isExhaustiveQuery
            )

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
                    initialSearchOutput: multiQueryStep.output,
                    steps: &steps,
                    totalTokens: &totalTokens,
                    ragService: ragService,
                    onStep: onStep,
                    startTime: startTime
                )
            } else {
                // Single-topic query - try harder with multiple reformulations
                Log.info("[Agentic] Single-topic, low confidence → trying alternative search strategies", category: .llm)

                await detailedForwarder?(.retrieval, "Fallback search", "Broadening with lower threshold")

                // Try a broader search with lower threshold - use full pipeline for event visibility
                let broaderChunks = try await ragService.executeFullRetrievalPipeline(
                    query: query,
                    topK: 20,
                    minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .fallback),
                    qualityMode: qualityMode,
                    onDetailedEvent: detailedForwarder
                )

                if !broaderChunks.isEmpty {
                    for chunk in broaderChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                        allRetrievedChunks.append(chunk)
                    }
                }

                // Format expanded results
                var expandedResults = multiQueryStep.output
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

    private typealias RetrievalQuality = AgenticRetrievalQuality

    // MARK: - Lexical Relevance Check

    /// Stop words to exclude from keyword matching
    private static let stopWords: Set<String> = [
        "a", "an", "the", "is", "are", "was", "were", "be", "been", "being",
        "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
        "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
        "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
        "through", "during", "before", "after", "above", "below", "between",
        "under", "again", "further", "then", "once", "here", "there", "when",
        "where", "why", "how", "all", "each", "few", "more", "most", "other",
        "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
        "too", "very", "just", "also", "now", "what", "which", "who", "whom",
        "this", "that", "these", "those", "am", "it", "its", "i", "me", "my",
        "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
        "he", "him", "his", "she", "her", "hers", "they", "them", "their"
    ]

    /// Check if query keywords appear in retrieved chunks (simple but effective)
    /// Returns 0.0-1.0 representing what fraction of query keywords appear in chunks
    private func checkLexicalRelevance(query: String, chunks: [RetrievedChunk]) -> Float {
        // Extract meaningful keywords from query (non-stopwords, 3+ chars)
        let queryWords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !Self.stopWords.contains($0) }

        guard !queryWords.isEmpty else { return 0.5 } // Can't evaluate, assume ok

        // Build combined chunk text
        let chunkText = chunks.prefix(5)
            .map { ($0.chunk.parentContent ?? $0.chunk.content).lowercased() }
            .joined(separator: " ")

        // Count how many query keywords appear in chunks
        var matchCount = 0
        for word in queryWords {
            if chunkText.contains(word) {
                matchCount += 1
            }
        }

        let relevance = Float(matchCount) / Float(queryWords.count)
        Log.debug("[LexicalRelevance] \(matchCount)/\(queryWords.count) keywords found = \(String(format: "%.0f%%", relevance * 100))", category: .retrieval)

        return relevance
    }
    /// Evaluate retrieval quality based on similarity scores and coverage
    /// NOTE: Semantic similarity scores are inherently lower than people expect.
    /// 0.15-0.25 is often "good enough" for useful retrieval - don't give up too early!
    private func evaluateRetrievalQuality(chunks: [RetrievedChunk], query: String) -> RetrievalQuality {
        AgenticPolicyService.retrievalQuality(chunks: chunks, config: config)
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
        let __spSynthesisDirect = PipelineSignposts.synthesis.beginInterval("SynthesisDirect")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisDirect", __spSynthesisDirect) }
        let startTime = Date()

        // Truncate search results to fit in context budget
        // System prompt is now ~370 tokens, query ~50, output ~800 = 1220 tokens overhead
        // Remaining: 4096 - 1220 = 2876 tokens ≈ 4000 chars at 1.4 chars/token
        // Use 3000 chars for safety margin
        //
        // SENTENCE-LEVEL EXTRACTION: When searchResults come from pre-assembled chunks,
        // they’re already formatted. But we still truncate to budget.
        let truncatedResults = String(searchResults.prefix(3000))

        // Deep Think mode: thorough synthesis with actionable details
        let systemPrompt = """
        Answer using ONLY the provided excerpts [S1], [S2], etc.
        Rules:
        1) Cite sources as [S1], [S2] etc. (NOT URLs)
        2) Extract specific values: numbers, measurements, specs, ratings when present
        3) Be thorough — pull every relevant detail from the excerpts
        4) Write naturally and intelligently — match your format to what the user actually asked
        5) Read OCR'd text carefully for model numbers, specs, and data
        6) NEVER say "I don't have information" — always provide what IS there
        7) ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions. Never expand an abbreviation differently than the glossary defines it.
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
            maxTokens: 800, // Conservative to stay within 4096 total
            disableTools: true
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
        let __spSynthesisComprehensive = PipelineSignposts.synthesis.beginInterval("SynthesisComprehensive")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisComprehensive", __spSynthesisComprehensive) }
        let startTime = Date()

        // Format chunks EXACTLY like Standard mode's assembleContext with [S1], [S2] notation
        var contextBuilder = ""
        let maxContextChars = 2800 // Reduced to account for enhanced prompt

        // SENTENCE-LEVEL EXTRACTION: Instead of packing 3-4 whole chunks and
        // hoping the answer is in one of them, extract only query-relevant
        // sentences from ALL candidates. With 2800 chars, this fits targeted
        // data from 8-12 sources instead of 3 whole chunks.
        // Universal across all document types.
        let extraction = await ragService.extractRelevantSentences(
            from: chunks,
            query: query,
            maxChars: maxContextChars,
            compact: true
        )
        contextBuilder = extraction.context
        let usedChunks = extraction.sourcesUsed

        Log.info("[Deep Think] Sentence extraction: \(extraction.sentencesIncluded) sentences from \(usedChunks) sources, \(contextBuilder.count) chars", category: .llm)

        // Deep Think mode: comprehensive multi-source synthesis
        let systemPrompt = """
        Answer using excerpts [S1], [S2]. Extract ALL specific values, numbers, specs.
        Read OCR'd text carefully. Write naturally. Cite [S1], [S2] only.
        NEVER say "I don't have information" — provide what IS there.
        ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions.
        If vague, interpret based on document topics.
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
            maxTokens: 800, // Conservative to stay within 4096 total
            disableTools: true,
            // This path renders `chunks` into `contextBuilder`, so the rendered-evidence
            // fallback already keeps it from abstaining. Passing the chunks themselves
            // upgrades that from a synthetic "there is some evidence" signal to the real
            // count and similarity scores, which is what the planner is meant to judge.
            sourceChunks: chunks
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
        let __spSynthesisHonest = PipelineSignposts.synthesis.beginInterval("SynthesisHonest")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisHonest", __spSynthesisHonest) }
        let startTime = Date()

        // Truncate to fit in 4096 token budget
        // Enhanced prompt ~250 tokens, query ~50, output ~800 = 1100 overhead
        // Remaining: 4096 - 1100 = 2996 tokens ≈ 4200 chars, use 3000 for safety
        let truncatedResults = String(searchResults.prefix(3000))

        // Even for low-confidence, extract maximum value from available excerpts
        let systemPrompt = """
        The available excerpts may not directly answer the query, but extract MAXIMUM value:
        - Cite sources [S1], [S2] for everything mentioned
        - Include ANY procedures, specifications, or actions found
        - Note related topics that might help the user
        - Be specific about what the excerpts DO cover
        - Include all technical details found, even if tangential
        - ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT expansions
        """

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: truncatedResults,
            systemPrompt: systemPrompt,
            maxTokens: 800,
            disableTools: true
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
        let __spSynthesisDecomposed = PipelineSignposts.synthesis.beginInterval("SynthesisDecomposed")
        defer { PipelineSignposts.synthesis.endInterval("SynthesisDecomposed", __spSynthesisDecomposed) }
        var allRetrievedChunks = initialChunks

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        let plannedSubQueries = await plannerSubQueries(for: query)
        let planningStep: ThinkingStep
        let subQueries: [String]

        if !plannedSubQueries.isEmpty {
            planningStep = ThinkingStep(
                id: UUID(),
                type: .planning,
                input: query,
                output: plannedSubQueries.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"),
                tokensUsed: 0,
                duration: 0,
                timestamp: Date()
            )
            subQueries = plannedSubQueries
        } else {
            planningStep = try await executePlanningStep(query: query, ragService: ragService)
            subQueries = parseSubQueries(from: planningStep.output)
        }

        steps.append(planningStep)
        totalTokens += planningStep.tokensUsed
        await onStep?(planningStep)

        // Execute sub-queries
        var searchResults: [(query: String, result: String)] = [(query, initialSearchOutput)]

        for subQuery in subQueries.prefix(config.maxSteps - 2) {


            guard totalTokens < config.maxTotalTokens else { break }

            let (searchStep, chunks) = try await executeSearchStepWithChunks(
                subQuery: subQuery,
                ragService: ragService,
                onDetailedEvent: detailedForwarder
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
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .focusedSubquery)
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
    /// - Parameter onDetailedEvent: Optional callback to emit verbose thinking events (for ThinkingView)
    private func executeSearchStepWithChunks(
        subQuery: String,
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        // Emit: Starting this search
        await onDetailedEvent?(.retrieval, "Searching", "Query: \"\(subQuery.prefix(40))...\"")

        // Use the FULL hybrid search pipeline with re-ranking and MMR (like Standard mode)
        // This gives us HyDE, AI re-ranking, MMR diversification - everything Standard mode does
        let chunks = try await ragService.executeFullRetrievalPipeline(
            query: subQuery,
            topK: 20,
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .search),
            qualityMode: qualityMode,
            onDetailedEvent: onDetailedEvent
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

    // MARK: - Multi-Query Search (Universal Semantic Coverage)

    /// Generate diverse search queries using LLM to cover all semantic angles of the question.
    /// This is the key to universal retrieval - we don't hardcode synonyms, we let the LLM
    /// understand the user's INTENT and generate queries that would find relevant content.
    ///
    /// For "What dosage should I take?", the LLM might generate:
    /// - "recommended dosage amount"
    /// - "dose quantity milligrams"
    /// - "administration instructions"
    /// - "prescribing guidelines"
    private func generateSearchQueries(
        originalQuery: String,
        ragService: RAGService
    ) async throws -> [String] {
        let planningProfile = await QueryProfileService.shared.buildProfile(
            for: originalQuery,
            routingEnabled: false
        )
        let executionPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: originalQuery,
            profile: planningProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )

        var queries = executionPlan.searchQueries
        if executionPlan.executionMode == .directLookup || queries.count >= 3 {
            Log.info("[MultiQuery] Planner generated \(queries.count) search queries: \(queries)", category: .retrieval)
            return Array(queries.prefix(5))
        }

        let prompt = """
        Write concrete search phrases for the exact question below.

        Rules:
        - Keep the same entities, units, and objects from the question.
        - Do not add placeholders, brackets, examples, or unknown make/model text.
        - Return only search phrases, one per line.

        Question: \(originalQuery)

        1. \(originalQuery)
        2.
        3.
        4.
        """

        // Multi-query expansion is an *optimization*: it widens retrieval with
        // extra search phrasings. It is not load-bearing — `deterministicSearchQueries`
        // already covers the case where the model returns nothing useful.
        //
        // Previously this used `try await`, so any generation failure propagated
        // out and killed the whole Deep Think query. Observed on macOS: Apple's
        // SDK threw `GenerationError` ("Failed to parse generated content") in
        // this step, and the user's entire request failed with it — despite
        // retrieval being perfectly capable of proceeding on the deterministic
        // phrasings. A helper step must not be able to take down the answer.
        let response: LLMResponse?
        do {
            response = try await ragService.generateWithFreshSession(
                prompt: prompt,
                maxTokens: 200
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.warning(
                "[MultiQuery] Expansion generation failed; continuing with deterministic "
                    + "search phrases. type=\(type(of: error)) "
                    + "full=\(String(describing: error))",
                category: .retrieval
            )
            response = nil
        }

        // Parse numbered lines or JSON array from response
        if queries.isEmpty {
            queries = deterministicSearchQueries(for: originalQuery)
        }

        guard let response else {
            Log.info("[MultiQuery] Using \(queries.count) deterministic search queries", category: .retrieval)
            return Array(queries.prefix(5))
        }

        func appendIfUseful(_ candidate: String) {
            let queryText = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isUsableGeneratedSearchQuery(queryText, originalQuery: originalQuery) else { return }
            guard !queries.contains(where: { $0.caseInsensitiveCompare(queryText) == .orderedSame }) else { return }
            queries.append(queryText)
        }

        // Try JSON array first
        if let jsonStart = response.text.firstIndex(of: "["),
           let jsonEnd = response.text.lastIndex(of: "]") {
            let jsonString = String(response.text[jsonStart...jsonEnd])
            if let data = jsonString.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String] {
                for q in parsed { appendIfUseful(q) }
            }
        }

        // Fallback: parse numbered lines (e.g., "2. some query", "3. another query")
        if queries.count <= 4 {
            // Apple FM often puts ALL queries on one line: "query1? 2. query2 3. query3 4. query4"
            // First, try splitting on mid-line numbered patterns before falling back to newline split
            let fullText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let midLinePattern = #"\s*\d+[\.\)]\s+"#
            if let regex = try? NSRegularExpression(pattern: midLinePattern) {
                let range = NSRange(fullText.startIndex..., in: fullText)
                let matches = regex.matches(in: fullText, range: range)
                if matches.count >= 2 {
                    // Found multiple numbered items on potentially one line — split on them
                    var splitQueries: [String] = []
                    var lastEnd = fullText.startIndex
                    for match in matches {
                        if let matchRange = Range(match.range, in: fullText) {
                            let segment = String(fullText[lastEnd..<matchRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !segment.isEmpty && segment.count > 3 {
                                splitQueries.append(segment)
                            }
                            lastEnd = matchRange.upperBound
                        }
                    }
                    // Don't forget the last segment after the final number
                    let lastSegment = String(fullText[lastEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !lastSegment.isEmpty && lastSegment.count > 3 {
                        splitQueries.append(lastSegment)
                    }
                    for q in splitQueries { appendIfUseful(q) }
                }
            }

            // If mid-line split didn't work, try line-by-line
            if queries.count <= 4 {
                let lines = response.text.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    // Match "2. query text" or "- query text" patterns
                    if let dotRange = trimmed.range(of: #"^\d+[\.\)]\s*"#, options: .regularExpression) {
                        let queryText = String(trimmed[dotRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                        appendIfUseful(queryText)
                    } else if trimmed.hasPrefix("- ") {
                        let queryText = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                        appendIfUseful(queryText)
                    }
                }
            }
        }

        Log.info("[MultiQuery] Generated \(queries.count) search queries: \(queries)", category: .retrieval)
        return Array(queries.prefix(5)) // Cap at 5 to limit latency
    }

    private func plannerSubQueries(for query: String) async -> [String] {
        let planningProfile = await QueryProfileService.shared.buildProfile(
            for: query,
            routingEnabled: false
        )
        let executionPlan = await QueryExecutionPlannerService.shared.buildPlan(
            for: query,
            profile: planningProfile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )
        return Array(executionPlan.subqueries.prefix(4))
    }

    private func deterministicSearchQueries(for originalQuery: String) -> [String] {
        let original = originalQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return [] }

        let lower = original.lowercased()
        var queries: [String] = [original]

        let hasFuelTerm = ["gas", "gasoline", "fuel"].contains { lower.contains($0) }
        let hasCapacityTerm = ["capacity", "capacities", "hold", "holds", "holding", "volume", "amount", "how many", "how much"].contains { lower.contains($0) }
        let hasLiquidUnit = ["gallon", "gallons", "gal", "liter", "liters", "litre", "litres"].contains { lower.contains($0) }

        if hasFuelTerm && (hasCapacityTerm || hasLiquidUnit) {
            queries.append("fuel gasoline gal capacity")
            queries.append("fuel tank capacity US gal")
            queries.append("gasoline fuel capacity liters gallons")
        } else if hasCapacityTerm || hasLiquidUnit {
            queries.append("\(original) capacity volume")
            if hasLiquidUnit {
                queries.append("\(original) gal liters")
            }
        }

        let stopWords: Set<String> = [
            "what", "which", "when", "where", "why", "how", "many", "much",
            "does", "this", "that", "these", "those", "the", "and", "for",
            "with", "from", "can", "could", "would", "should", "have", "has",
            "had", "its", "into", "about"
        ]
        let keyTerms = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 && !stopWords.contains($0) }

        if keyTerms.count >= 2 {
            queries.append(keyTerms.prefix(6).joined(separator: " "))
        }

        return uniqueSearchQueries(queries)
    }

    private func isUsableGeneratedSearchQuery(_ candidate: String, originalQuery: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3, trimmed.count <= 160 else { return false }

        let lower = trimmed.lowercased()
        let rejectedFragments = [
            "[", "]", "{", "}", "<", ">",
            "make and model", "car make", "specific make", "specific model",
            "insert", "placeholder", "example", "your query", "search phrase"
        ]
        guard !rejectedFragments.contains(where: { lower.contains($0) }) else { return false }
        guard lower != originalQuery.lowercased() else { return false }

        let originalTerms = Set(
            originalQuery.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )
        let candidateTerms = Set(
            lower
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )

        if originalTerms.isEmpty || candidateTerms.isEmpty {
            return true
        }

        let overlap = originalTerms.intersection(candidateTerms)
        if !overlap.isEmpty { return true }

        // Allow safe concept normalizations for common specification language.
        if originalTerms.contains("gas") && candidateTerms.intersection(["fuel", "gasoline"]).isEmpty == false {
            return true
        }
        if originalTerms.contains("gallons") && candidateTerms.intersection(["gal", "liters", "capacity"]).isEmpty == false {
            return true
        }
        if originalTerms.contains("hold") && candidateTerms.intersection(["capacity", "volume"]).isEmpty == false {
            return true
        }

        return false
    }

    private func uniqueSearchQueries(_ queries: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for query in queries {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    /// Execute multi-query search: search with multiple query variations and fuse results.
    /// Uses Reciprocal Rank Fusion (RRF) to combine rankings from different queries.
    /// - Parameter onDetailedEvent: Optional callback to emit verbose thinking events (for ThinkingView)
    private func executeMultiQuerySearch(
        queries: [String],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> (ThinkingStep, [RetrievedChunk]) {
        let startTime = Date()

        await onDetailedEvent?(.retrieval, "Multi-query search", "Searching \(queries.count) query variations")

        var allResults: [[RetrievedChunk]] = []

        // Search with each query variation - show FULL pipeline for ALL queries
        // This gives Deep Think/Maximum the same granular console output as Standard mode
        for (index, query) in queries.enumerated() {
            if Task.isCancelled { break }

            await onDetailedEvent?(.retrieval, "Query \(index + 1)/\(queries.count)", "\"\(query.prefix(40))...\"")

            // Show full pipeline details for ALL queries (not just first)
            // Deep Think users want to see VECTOR, BM25, RRF, MMR, RERANK for each search
            let chunks = try await ragService.executeFullRetrievalPipeline(
                query: query,
                topK: 15,
                minSimilarity: 0.05, // Very low - we'll use RRF to rank
                qualityMode: qualityMode,
                onDetailedEvent: onDetailedEvent  // Always forward events
            )
            allResults.append(chunks)

            // Show result count for each query
            await onDetailedEvent?(.retrieval, "Query \(index + 1) done", "\(chunks.count) chunks retrieved")
        }

        await onDetailedEvent?(.rrf, "Fusing results", "RRF across \(allResults.count) result sets")

        // Reciprocal Rank Fusion across all query results
        // Track both RRF score (for multi-query consensus) AND original reranker score (for relevance)
        var chunkScores: [UUID: (chunk: RetrievedChunk, rrfScore: Float, maxRerankerScore: Float)] = [:]
        let k: Float = 60.0 // RRF constant

        for results in allResults {
            for (rank, chunk) in results.enumerated() {
                let rrfScore = 1.0 / (k + Float(rank + 1))

                if let existing = chunkScores[chunk.chunk.id] {
                    // Chunk seen in multiple queries - boost RRF score, keep max reranker score
                    chunkScores[chunk.chunk.id] = (
                        existing.chunk,
                        existing.rrfScore + rrfScore,
                        max(existing.maxRerankerScore, chunk.similarityScore)
                    )
                } else {
                    chunkScores[chunk.chunk.id] = (chunk, rrfScore, chunk.similarityScore)
                }
            }
        }

        // Sort by BLENDED score: 60% reranker (relevance) + 40% RRF (multi-query consensus)
        // CRITICAL: Pure reranker sorting lets a single high-scoring irrelevant chunk dominate.
        // E.g., a "radiator overheating" chunk scores 0.78 reranker for "fuel tank capacity"
        // because it mentions fuel gauge + engine + vehicle (lots of term overlap).
        // But the actual spec table only appears in 1-2 queries with lower reranker score.
        // RRF consensus rewards chunks that appear across MULTIPLE differently-worded queries,
        // which is a strong signal that the chunk actually addresses the topic.
        let maxRRF = chunkScores.values.map { $0.rrfScore }.max() ?? 1.0
        let fusedResults = chunkScores.values
            .sorted {
                let normRRF0 = $0.rrfScore / max(maxRRF, 0.001)
                let normRRF1 = $1.rrfScore / max(maxRRF, 0.001)
                let blended0 = $0.maxRerankerScore * 0.6 + normRRF0 * 0.4
                let blended1 = $1.maxRerankerScore * 0.6 + normRRF1 * 0.4
                return blended0 > blended1
            }
            .prefix(20)
            .enumerated()
            .map { (index, retrieved) -> RetrievedChunk in
                // Use the reranker score as the similarity - this is what the reasoning chain needs
                return RetrievedChunk(
                    chunk: retrieved.chunk.chunk,
                    similarityScore: retrieved.maxRerankerScore,  // Actual relevance from reranker
                    rank: index + 1,
                    sourceDocument: retrieved.chunk.sourceDocument,
                    pageNumber: retrieved.chunk.pageNumber
                )
            }

        let resultChunks = Array(fusedResults)

        // Log top chunk for debugging - this should now show the most RELEVANT chunk
        if let topChunk = resultChunks.first {
            let preview = String(topChunk.chunk.content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
            Log.debug("[MultiQuery] Top chunk (reranker score \(String(format: "%.2f", topChunk.similarityScore))): \(preview)...", category: .retrieval)
        }

        // Format for logging
        var searchResult = "Multi-query search with \(queries.count) variations:\n"
        searchResult += "Queries: \(queries.joined(separator: " | "))\n\n"
        searchResult += "Found \(resultChunks.count) unique chunks after RRF fusion\n"

        let step = ThinkingStep(
            id: UUID(),
            type: .searching,
            input: queries.first ?? "",
            output: searchResult,
            tokensUsed: 0,
            duration: Date().timeIntervalSince(startTime),
            timestamp: startTime
        )

        Log.info("[MultiQuery] Fused \(allResults.map { $0.count }.reduce(0, +)) results into \(resultChunks.count) unique chunks", category: .retrieval)

        return (step, resultChunks)
    }

    /// Validate that retrieved chunks actually address the semantic intent of the question.
    /// This catches cases where retrieval grabbed related but wrong content.
    /// Returns (isValid, reason) - if invalid, reason explains what's missing.
    private func validateSemanticIntent(
        query: String,
        chunks: [RetrievedChunk],
        ragService: RAGService
    ) async throws -> (isValid: Bool, reason: String) {
        guard !chunks.isEmpty else {
            return (false, "No chunks retrieved")
        }

        // Quick heuristic check first - if top chunks have high scores, likely good
        let topScore = chunks.first?.similarityScore ?? 0
        if topScore > 0.6 {
            return (true, "High confidence match")
        }

        // Fast path: Check lexical overlap first (cheaper than LLM call)
        let lexicalScore = checkLexicalRelevance(query: query, chunks: chunks)
        if lexicalScore >= 0.5 {
            // At least half the query keywords found - likely relevant
            return (true, "Good keyword overlap (\(Int(lexicalScore * 100))%)")
        }

        if lexicalScore < 0.1 {
            // Almost no keyword overlap - clearly irrelevant
            return (false, "No keyword overlap with query")
        }

        // For borderline cases (10-50% overlap), ask LLM to verify
        let chunkPreviews = chunks.prefix(3).map { chunk in
            let content = (chunk.chunk.parentContent ?? chunk.chunk.content)
            return String(content.prefix(300))
        }.joined(separator: "\n---\n")

        let prompt = """
        Question: \(query)

        Retrieved content:
        \(chunkPreviews)

        Does this content contain information to answer the question?
        Reply with ONLY one word: YES or NO
        """

        let response = try await ragService.generateWithFreshSession(
            prompt: prompt,
            maxTokens: 10
        )

        let answer = response.text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let isValid = answer.contains("yes")

        Log.debug("[SemanticValidation] Query '\(query.prefix(40))...' → \(isValid ? "VALID" : "INVALID")", category: .retrieval)

        return (isValid, isValid ? "Content matches intent" : "Content does not address the question")
    }

    // MARK: - Cross-Reference Resolution

    /// Resolve cross-references found in retrieved chunks.
    /// Technical documents frequently say "see page X" or "given in 'Section Name'".
    /// The actual data (spec tables, procedures) lives in the referenced section, but
    /// the reranker consistently scores prose descriptions higher than structured tables.
    /// This method follows those references to retrieve the actual data chunks.
    ///
    /// Example: A chunk says "The fuel tank capacity is given in 'Recommended lubricants
    /// and capacities' on page 9-7." — this method retrieves chunks from that section.
    private func resolveCrossReferences(
        chunks: [RetrievedChunk],
        query: String,
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> [RetrievedChunk] {
        // Cross-reference patterns common in technical documents
        // Each captures the section name or page reference
        // Use try?/compactMap instead of try! to prevent crashes from invalid regex
        let crossRefPatterns: [(regex: NSRegularExpression, captureGroup: Int)] = [
            // QUOTED: "given in 'Recommended lubricants and capacities' on page 9-7"
            // NOTE: In raw strings #"..."#, \u{} is literal text, NOT a Unicode escape.
            // ICU regex (NSRegularExpression) uses \x{HHHH} for Unicode code points.
            (pattern: #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
             options: NSRegularExpression.Options.caseInsensitive, group: 1),
            // QUOTED: "see 'Section Name'" or "refer to 'Section Name'"
            (pattern: #"(?:see|refer\s+to|check|consult)\s+['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]"#,
             options: .caseInsensitive, group: 1),
            // QUOTED: "in the 'Section Name' section/table/chapter"
            (pattern: #"in\s+(?:the\s+)?['"\x{201C}\x{201D}]([^'"\x{201C}\x{201D}\n]{3,80})['"\x{201C}\x{201D}]\s+(?:section|table|chapter|page)"#,
             options: .caseInsensitive, group: 1),
            // UNQUOTED (case-insensitive): "given in recommended lubricants and capacities on page 9-7"
            (pattern: #"(?:given|found|listed|shown|described|specified|provided|included|explained)\s+(?:in|under|at)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
             options: .caseInsensitive, group: 1),
            // UNQUOTED: "see section name on page X" or "refer to section name on page X"
            (pattern: #"(?:see|refer\s+to|check|consult)\s+(?:the\s+)?([a-z][a-z]+(?:\s+[a-z&,]+){2,10})\s+on\s+page"#,
             options: .caseInsensitive, group: 1),
            // CATCH-ALL: "given in <any text> on page" — most permissive fallback
            (pattern: #"(?:given|found|listed|shown|described|specified|provided)\s+(?:in|under|at)\s+(?:the\s+)?(.{5,80})\s+on\s+page"#,
             options: .caseInsensitive, group: 1),
        ].compactMap { item -> (regex: NSRegularExpression, captureGroup: Int)? in
            let (pattern, options, group) = item
            guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
                Log.error("[CrossRef] Failed to compile regex: \(pattern.prefix(60))...", category: .retrieval)
                return nil
            }
            return (regex, group)
        }

        var referencedSections: Set<String> = []
        let existingIds = Set(chunks.map { $0.chunk.id })

        // Scan top chunks for cross-references
        for chunk in chunks.prefix(12) {
            let content = chunk.chunk.content
            let range = NSRange(content.startIndex..., in: content)

            for (regex, group) in crossRefPatterns {
                let matches = regex.matches(in: content, range: range)
                for match in matches {
                    guard match.numberOfRanges > group,
                          let captureRange = Range(match.range(at: group), in: content) else { continue }
                    let reference = String(content[captureRange])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    // Skip very short references or pure page numbers
                    if reference.count >= 5,
                       reference.range(of: #"^\d+[-–]?\d*$"#, options: .regularExpression) == nil {
                        referencedSections.insert(reference)
                    }
                }
            }
        }

        guard !referencedSections.isEmpty else { return [] }

        Log.info("[CrossRef] Found \(referencedSections.count) cross-references: \(referencedSections.joined(separator: ", "))", category: .retrieval)
        await onDetailedEvent?(.retrieval, "Cross-references", "Following \(referencedSections.count) document references")

        var additionalChunks: [RetrievedChunk] = []

        // Follow each cross-reference (limit to 3 to bound latency)
        for section in referencedSections.prefix(3) {
            await onDetailedEvent?(.retrieval, "Following ref", "Retrieving: \"\(section.prefix(40))\"")

            // Search for the referenced section using the full retrieval pipeline
            let sectionChunks = try await ragService.executeFullRetrievalPipeline(
                query: section,
                topK: 5,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .crossReference),
                qualityMode: qualityMode,
                onDetailedEvent: nil  // Don't spam detailed events for sub-searches
            )

            var addedFromSection = 0
            for chunk in sectionChunks where !existingIds.contains(chunk.chunk.id) {
                // Boost cross-referenced chunks: the DOCUMENT itself said to look here.
                // Floor at 0.55 ensures these compete with reranker-favored prose chunks.
                // Cap preserves ordering among cross-ref results.
                let boostedScore = max(chunk.similarityScore, 0.55)
                let boosted = RetrievedChunk(
                    chunk: chunk.chunk,
                    similarityScore: boostedScore,
                    rank: chunk.rank,
                    sourceDocument: chunk.sourceDocument,
                    pageNumber: chunk.pageNumber
                )
                additionalChunks.append(boosted)
                addedFromSection += 1
            }

            Log.info("[CrossRef] '\(section.prefix(40))': retrieved \(sectionChunks.count) chunks, \(addedFromSection) new", category: .retrieval)
        }

        if !additionalChunks.isEmpty {
            await onDetailedEvent?(.retrieval, "Cross-ref resolved", "+\(additionalChunks.count) chunks from referenced sections")

            let crossRefStep = ThinkingStep(
                id: UUID(),
                type: .searching,
                input: "Cross-reference resolution",
                output: "Followed \(referencedSections.count) document references → +\(additionalChunks.count) chunks",
                tokensUsed: 0,
                duration: 0.3,
                timestamp: Date()
            )
            // Log only, don't append to steps (caller handles that)
            Log.info("[CrossRef] \(crossRefStep.output)", category: .retrieval)
        }

        return additionalChunks
    }

    // MARK: - Graph Expansion (GraphRAG-lite)

    private func executeGraphExpansion(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
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

        await onDetailedEvent?(.agentic, "Graph expansion", "Extracting entities for hop search")

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

        await onDetailedEvent?(.parentDoc, "Entity hop", "Searching \(entities.count) entities: \(entities.prefix(3).joined(separator: ", "))")

        var expandedChunks: [RetrievedChunk] = []

        for (idx, entity) in entities.enumerated() {
            if Task.isCancelled { break }
            await onDetailedEvent?(.parentDoc, "Hop \(idx + 1)/\(entities.count)", "\"\(entity)\"")

            // Use full pipeline for entity hop searches (shows VECTOR, BM25, RRF, MMR)
            let hopChunks = try await ragService.executeFullRetrievalPipeline(
                query: entity,
                topK: 4,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .graphExpansion),
                qualityMode: qualityMode,
                onDetailedEvent: onDetailedEvent
            )
            for chunk in hopChunks where !expandedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                expandedChunks.append(chunk)
            }
        }

        await onDetailedEvent?(.parentDoc, "Graph complete", "+\(expandedChunks.count) chunks from entity hops")

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
            maxTokens: 700
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
        Format with ### section headers, bullets only for actual lists, **bold** sparingly for key terms.
        Separate sections with blank lines for readability.
        """

        let response = try await ragService.generateWithProperConsent(
            prompt: query,
            context: "Research Steps:\n\(truncatedContext)",
            systemPrompt: systemPrompt,
            maxTokens: 800,
            disableTools: true
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

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        // Accumulate context across iterations
        var accumulatedContext = ""
        var iteration = 0

        Log.info("[RecursiveResearch] Starting recursive research loop for: \(query.prefix(50))...", category: .llm)

        // Initial retrieval to seed the context
        let (initialStep, initialChunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
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
                ragService: ragService,
                sourceChunks: allRetrievedChunks
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
                    ragService: ragService,
                    onDetailedEvent: detailedForwarder
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
        ragService: RAGService,
        /// Everything retrieved so far in this recursive loop, for post-retrieval
        /// planning. `currentContext` is embedded in the prompt below and `context`
        /// is passed empty to avoid double-rendering, which left the planner seeing
        /// no evidence at all: it abstained, and the abstention text came back in
        /// place of an `[ANSWER]`/`[SEARCH:]` decision the loop could parse.
        sourceChunks: [RetrievedChunk]
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
            maxTokens: 600,
            disableTools: true,
            sourceChunks: sourceChunks,
            // A routing decision, not an evidence synthesis. Keep it local.
            forceOnDevice: true
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
            maxTokens: 800,
            disableTools: true
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

    /// True when an "answer" is really just retrieved chunks pasted back.
    ///
    /// Recursive research can return the evidence it gathered rather than a written
    /// answer. That output is worthless to a user and, because it contains no
    /// hedging language, it slips past `answerIndicatesRetrievalMiss` and is allowed
    /// to replace a perfectly good synthesis. Seen on device: a 91%-confidence
    /// eight-session answer swapped for text beginning `[S1] Apple Intelligence
    /// powers OpenIntelligence via WWDC26 FoundationModels...`, copied verbatim out
    /// of the source document.
    ///
    /// A real synthesis never opens with a source marker — every synthesis prompt
    /// asks for prose with `###` headers — so requiring both a leading marker and
    /// several source-prefixed blocks keeps this narrow.
    private func looksLikeRawEvidenceDump(_ answer: String) -> Bool {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[S") else { return false }
        let sourcePrefixedBlocks = trimmed
            .components(separatedBy: "\n")
            .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[S") }
            .count
        return sourcePrefixedBlocks >= 2
    }

    /// Detect if an answer indicates the initial retrieval missed relevant content
    /// This catches cases where the model says "I cannot find" but the answer exists in different chunks
    /// that weren't retrieved because of semantic mismatch (e.g., "oil pressure" vs "oil type/viscosity")
    private func answerIndicatesRetrievalMiss(_ answer: String) -> Bool {
        let lowercased = answer.lowercased()

        // A grounded answer is *allowed* to say what the documents do not cover.
        // `buildSessionObjective` explicitly instructs the final session to "state
        // that the documents do not fully resolve them instead of inferring beyond
        // the evidence", and both "documents do not" and "do not specify" appear in
        // the list below — so the app was telling the model to hedge and then
        // classifying that hedge as a retrieval failure.
        //
        // Observed on device: an 8-session synthesis at 91% confidence tripped this,
        // was discarded, and recursive research replaced it with raw retrieved chunks
        // pasted back to the user. The replacement passed the guard at the call site
        // precisely because an evidence dump contains no hedging language.
        //
        // The original intent — catching retrieval that grabbed the wrong content,
        // "oil pressure" instead of "oil type" — produces a short, uncited answer.
        // A long answer carrying source citations is the opposite of that: it is a
        // grounded synthesis that happens to note a gap, which is the behaviour the
        // reasoning chain is designed to produce.
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        let citationMarkers = trimmedAnswer.components(separatedBy: "[S").count - 1
        if trimmedAnswer.count >= 800 && citationMarkers >= 2 {
            return false
        }

        // Strong indicators that retrieval grabbed wrong content
        let retrievalMissIndicators = [
            "cannot determine",
            "cannot find",
            "not able to find",
            "no information about",
            "does not specify",
            "does not explicitly",
            "doesn't specify",
            "doesn't explicitly",
            "do not specify",
            "do not explicitly",
            "doesn't contain",
            "does not contain",
            "not mentioned",
            "no mention of",
            "unable to locate",
            "unable to find",
            "not provided in",
            "not stated in",
            "documents don't",
            "documents do not",
        ]

        for indicator in retrievalMissIndicators {
            if lowercased.contains(indicator) {
                Log.debug("[Agentic] Answer contains retrieval miss indicator: '\(indicator)'", category: .llm)
                return true
            }
        }

        return false
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

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        Log.info("[Self-RAG] Analyzing query to decide retrieval strategy", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
                ragService: ragService,
                onDetailedEvent: detailedForwarder
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
                ragService: ragService,
                onDetailedEvent: detailedForwarder
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
        _ = ragService

        let profile = await QueryProfileService.shared.buildProfile(
            for: query,
            routingEnabled: false
        )
        let plan = await QueryExecutionPlannerService.shared.buildPlan(
            for: query,
            profile: profile,
            requestedQualityMode: qualityMode,
            allowToolCalling: true
        )

        return (plan.needsRetrieval, plan.reasoning)
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

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - Self-RAG 2.0: Answer Verification & Citation Grounding
    // 2026 RAG Best Practice: Don't just generate — VERIFY before returning
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Result of Self-RAG verification
    struct SelfRAGVerification: Sendable {
        /// Does the answer actually address the user's question?
        let addressesQuestion: Bool
        /// Are citations grounded in actual source content?
        let citationsVerified: Bool
        /// Number of citations that were verified
        let verifiedCitationCount: Int
        /// Number of citations that couldn't be verified (hallucinated)
        let unverifiedCitationCount: Int
        /// Calibrated confidence score (0-1) based on semantic + lexical signals
        let calibratedConfidence: Float
        /// Human-readable summary of verification
        let summary: String
        /// Suggested action: "accept", "retry", "escalate"
        let action: String
    }

    private func semanticDelta(_ text1: String, _ text2: String) -> Double {
        let words1 = Set(text1.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })
        let words2 = Set(text2.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 })

        guard !words1.isEmpty || !words2.isEmpty else { return 0.0 }

        let intersection = words1.intersection(words2).count
        let union = words1.union(words2).count

        let jaccardSimilarity = Double(intersection) / Double(union)
        return 1.0 - jaccardSimilarity
    }

    private func runVerificationLoop(
        query: String,
        initialAnswer: String,
        initialSteps: [ThinkingStep],
        initialTokens: Int,
        initialConfidence: Float,
        initialSources: [RetrievedChunk],
        ragService: RAGService,
        startTime: Date,
        onStep: ((ThinkingStep) async -> Void)?
    ) async throws -> AgenticResult {
        var currentAnswer = initialAnswer
        var currentSteps = initialSteps
        var currentTokens = initialTokens
        var currentConfidence = initialConfidence
        var currentSources = initialSources

        var strikeCount = 0
        let maxStrikes = 3

        while strikeCount < maxStrikes {
            let verification = await verifySelfRAG(
                query: query,
                answer: currentAnswer,
                sourceChunks: currentSources,
                ragService: ragService
            )

            let verifyStep = ThinkingStep(
                id: UUID(),
                type: .verifying,
                input: "Self-RAG verification",
                output: verification.summary,
                tokensUsed: 0,
                duration: 0.1,
                timestamp: Date(),
                confidence: verification.calibratedConfidence
            )
            currentSteps.append(verifyStep)
            await onStep?(verifyStep)

            currentConfidence = verification.calibratedConfidence

            if verification.action == "retry" && !answerIndicatesRetrievalMiss(currentAnswer) {
                strikeCount += 1
                Log.info("[Agentic] Self-RAG: Verification suggests retry (Strike \(strikeCount)/\(maxStrikes))", category: .llm)

                if strikeCount >= maxStrikes {
                    Log.warning("[Agentic] Self-RAG: Max verification strikes reached. Refusing further retries.", category: .llm)
                    break
                }

                // Try recursive research as backup
                let recursiveResult = try await executeRecursiveResearch(
                    query: query,
                    maxIterations: 3,
                    onStep: onStep
                )

                let newAnswer = recursiveResult.finalAnswer

                // Check if the retry returned an empty response
                let cleanNewAnswer = newAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleanNewAnswer.isEmpty {
                    Log.warning("[Agentic] Self-RAG: Retry returned an empty answer. Keeping the previous non-empty answer.", category: .llm)
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    // Do NOT update currentAnswer to empty. Leave currentAnswer as it was.
                    break
                }

                // Check semantic delta
                let delta = semanticDelta(newAnswer, currentAnswer)
                Log.debug("[Agentic] Semantic delta between verification attempts: \(String(format: "%.4f", delta))", category: .llm)

                if delta < 0.10 {
                    Log.warning("[Agentic] Self-RAG: Semantic delta too low (\(String(format: "%.4f", delta)) < 0.10). Refusing further retries.", category: .llm)
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    currentAnswer = newAnswer
                    break
                }

                if !answerIndicatesRetrievalMiss(newAnswer) {
                    currentSteps.append(contentsOf: recursiveResult.steps)
                    currentTokens += recursiveResult.totalTokens
                    currentAnswer = newAnswer
                    // Update sources/chunks
                    for chunk in recursiveResult.retrievedChunks {
                        if !currentSources.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                            currentSources.append(chunk)
                        }
                    }
                } else {
                    break
                }
            } else {
                break
            }
        }

        return AgenticResult(
            finalAnswer: currentAnswer,
            steps: currentSteps,
            totalTokens: currentTokens,
            totalDuration: Date().timeIntervalSince(startTime),
            confidence: currentConfidence,
            sourcesUsed: currentSources.count,
            retrievedChunks: currentSources
        )
    }

    /// Full Self-RAG verification: answer relevance + citation grounding + confidence calibration
    /// Called after Deep Think synthesis to ensure quality before returning to user
    func verifySelfRAG(
        query: String,
        answer: String,
        sourceChunks: [RetrievedChunk],
        ragService: RAGService
    ) async -> SelfRAGVerification {
        Log.info("[Self-RAG 2.0] Starting verification: query=\(query.prefix(50))..., answer=\(answer.count) chars", category: .llm)

        // 1. Check if answer addresses the question (semantic relevance)
        let addressScore = computeAnswerRelevance(query: query, answer: answer)
        let addressesQuestion = AgenticPolicyService.addressesQuestion(for: addressScore)

        // 2. Verify citations are grounded in sources
        let citationResult = verifyCitations(answer: answer, sources: sourceChunks)

        // 3. Compute calibrated confidence
        let calibrated = AgenticPolicyService.calibrateSelfRAGConfidence(
            answerRelevance: addressScore,
            citationScore: citationResult.groundingScore,
            answerLength: answer.count,
            sourceCount: sourceChunks.count
        )

        let action = AgenticPolicyService.verificationAction(
            addressesQuestion: addressesQuestion,
            groundingScore: citationResult.groundingScore,
            totalCitations: citationResult.totalCitations,
            calibratedConfidence: calibrated
        )

        let summary = buildVerificationSummary(
            addressesQuestion: addressesQuestion,
            addressScore: addressScore,
            citationResult: citationResult,
            calibrated: calibrated,
            action: action
        )

        Log.info("[Self-RAG 2.0] Verification complete: \(action) (relevance=\(Int(addressScore * 100))%, citations=\(citationResult.verified)/\(citationResult.totalCitations), confidence=\(Int(calibrated * 100))%)", category: .llm)

        return SelfRAGVerification(
            addressesQuestion: addressesQuestion,
            citationsVerified: citationResult.verified == citationResult.totalCitations && citationResult.totalCitations > 0,
            verifiedCitationCount: citationResult.verified,
            unverifiedCitationCount: citationResult.totalCitations - citationResult.verified,
            calibratedConfidence: calibrated,
            summary: summary,
            action: action
        )
    }

    /// Compute semantic relevance between query and answer using lexical overlap + key term matching
    /// UNIVERSAL: No domain-specific logic - works for any document type
    /// FIXED 2026-01: Previous version was too strict, rejecting valid answers with technical specs
    private func computeAnswerRelevance(query: String, answer: String) -> Float {
        let queryLower = query.lowercased()
        let answerLower = answer.lowercased()

        // Extract key terms from query (remove stop words)
        let stopWords: Set<String> = ["what", "how", "why", "when", "where", "who", "which",
                                       "does", "do", "is", "are", "was", "were", "the", "a", "an",
                                       "of", "in", "to", "for", "and", "or", "on", "with", "this", "that",
                                       "kind", "type", "take", "use", "need", "require", "should", "can"]
        let queryTerms = queryLower.split(separator: " ")
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count > 2 && !stopWords.contains($0) }

        // CRITICAL FIX: If query is about specs/types, check if answer has technical content
        // E.g., "what oil" → answer has "0W-20", "SAE", viscosity = GREAT match
        let isSpecQuery = queryLower.contains("what") || queryLower.contains("which") ||
                          queryLower.contains("type") || queryLower.contains("kind") ||
                          queryLower.contains("specification") || queryLower.contains("grade")

        // Technical content patterns (indicates answer is providing actual specs)
        let technicalPatterns = [
            #"\d+[wW]-\d+"#,           // Oil viscosity: 0W-20, 5W-30
            #"[A-Z]{2,}[\s-]?\d+"#,    // Spec codes: SAE, API SN, ACEA
            #"\d+\.?\d*\s*(mm|cm|l|L|gal|qt|oz|psi|bar|kpa|°|degrees)"#,  // Measurements
            #"\d+\.?\d*\s*(hp|kw|nm|lb|kg|mph|km/h)"#,  // Power/speed units
            #"[A-Z]\d{1,3}[A-Z]?"#,    // Part codes: M5, B48, etc.
        ]

        var hasTechnicalContent = false
        for pattern in technicalPatterns {
            if answer.range(of: pattern, options: .regularExpression) != nil {
                hasTechnicalContent = true
                break
            }
        }

        // If it's a spec query and answer has technical content, that's a strong signal
        let technicalBonus: Float = (isSpecQuery && hasTechnicalContent) ? 0.40 : 0

        // Score 1: Key term coverage (what % of query terms appear in answer?)
        // Relaxed: even 1 match is meaningful for short queries
        var matchedTerms = 0
        for term in queryTerms {
            if answerLower.contains(term) {
                matchedTerms += 1
            }
        }
        let termCoverage: Float
        if queryTerms.isEmpty {
            termCoverage = 0.5  // Can't evaluate without terms, neutral
        } else if matchedTerms > 0 {
            // At least one match = base relevance
            termCoverage = 0.3 + (Float(matchedTerms) / Float(queryTerms.count)) * 0.7
        } else {
            termCoverage = 0.1  // No direct matches, but don't zero out
        }

        // Score 2: Answer has concrete specifics (numbers, citations)
        let hasNumbers = answer.range(of: #"\d+\.?\d*"#, options: .regularExpression) != nil
        let hasCitations = answer.contains("[S") || answer.contains("[Doc")
        let specificityBonus: Float = (hasNumbers ? 0.10 : 0) + (hasCitations ? 0.10 : 0)

        // Score 3: Penalty for hedging/non-answers (UNIVERSAL patterns)
        // RELAXED: Only penalize strong hedging, not normal caveats
        let hedgingMarkers = [
            "isn't explicitly",
            "not explicitly",
            "remains speculative",
            "without specific information",
            "insufficient information",
            "not enough information",
            "cannot be determined",
            "no information available"
        ]
        let hedgingCount = hedgingMarkers.filter { answerLower.contains($0) }.count
        let hedgingPenalty: Float = min(Float(hedgingCount) * 0.15, 0.40)

        // Score 4: Length-to-substance ratio
        // Long answers that hedge a lot are worse than short direct answers
        let lengthPenalty: Float
        if answer.count > 4000 && hedgingCount >= 3 {
            lengthPenalty = 0.15  // Long AND heavily hedging = bad
        } else {
            lengthPenalty = 0
        }

        // Score 5: Refusal detection - STRONG penalty only for clear refusals
        let refusalMarkers = ["i cannot answer", "no information found", "unable to determine"]
        let hasRefusal = refusalMarkers.contains { answerLower.contains($0) }
        let refusalPenalty: Float = hasRefusal ? 0.30 : 0

        // Score 6: URL hallucination detection
        // If model generates URLs instead of [S1] citations, that's a hallucination
        let urlPattern = #"https?://[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}"#
        let hasURLs = answer.range(of: urlPattern, options: .regularExpression) != nil
        let urlHallucinationPenalty: Float = hasURLs ? 0.25 : 0

        // FIXED FORMULA: Start with base relevance, add bonuses, then subtract penalties
        // Technical content bonus is additive, not just term-based
        let baseRelevance = termCoverage * 0.50 + technicalBonus + specificityBonus
        let penalties = hedgingPenalty + lengthPenalty + refusalPenalty + urlHallucinationPenalty
        let relevance = min(1.0, max(0.1, baseRelevance - penalties))  // Floor at 10% if we have any answer

        return relevance
    }

    /// Citation verification result
    private struct CitationVerificationResult {
        let verified: Int           // Citations that exist in sources
        let totalCitations: Int     // Total [S1], [S2], etc. found
        let groundingScore: Float   // 0-1, how well citations are grounded
        let details: [String]       // Per-citation verification details
    }

    /// Verify that citations [S1], [S2], etc. actually reference content from sources
    private func verifyCitations(answer: String, sources: [RetrievedChunk]) -> CitationVerificationResult {
        // Extract citation markers from answer
        let citationPattern = #"\[S(\d+)\]"#
        guard let regex = try? NSRegularExpression(pattern: citationPattern, options: []) else {
            return CitationVerificationResult(verified: 0, totalCitations: 0, groundingScore: 1.0, details: [])
        }

        let matches = regex.matches(in: answer, options: [], range: NSRange(answer.startIndex..., in: answer))

        // Get unique citation numbers
        var citationNumbers: Set<Int> = []
        for match in matches {
            if let range = Range(match.range(at: 1), in: answer),
               let num = Int(answer[range]) {
                citationNumbers.insert(num)
            }
        }

        guard !citationNumbers.isEmpty else {
            // No citations = can't verify, but not necessarily bad
            return CitationVerificationResult(verified: 0, totalCitations: 0, groundingScore: 0.5, details: ["No citations found"])
        }

        // Verify each citation exists in sources
        var verified = 0
        var details: [String] = []

        for citationNum in citationNumbers.sorted() {
            let sourceIndex = citationNum - 1  // [S1] = sources[0]
            if sourceIndex >= 0 && sourceIndex < sources.count {
                // Source exists — now verify the claim is actually in the source
                let sourceContent = sources[sourceIndex].chunk.content.lowercased()

                // Find text near the citation in the answer
                let citationMarker = "[S\(citationNum)]"
                if let markerRange = answer.range(of: citationMarker) {
                    // Extract ~50 chars before the citation marker
                    let start = answer.index(markerRange.lowerBound, offsetBy: -50, limitedBy: answer.startIndex) ?? answer.startIndex
                    let claimText = String(answer[start..<markerRange.lowerBound]).lowercased()

                    // Check if key words from the claim appear in the source
                    let claimWords = claimText.split(separator: " ")
                        .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
                        .filter { $0.count > 3 }

                    var matchedWords = 0
                    for word in claimWords.prefix(10) {
                        if sourceContent.contains(word) {
                            matchedWords += 1
                        }
                    }

                    let claimGrounded = claimWords.isEmpty || Float(matchedWords) / Float(max(claimWords.count, 1)) >= 0.3
                    if claimGrounded {
                        verified += 1
                        details.append("[S\(citationNum)]: ✓ Verified in source")
                    } else {
                        details.append("[S\(citationNum)]: ⚠ Claim not found in source")
                    }
                } else {
                    // Citation marker found via regex but not simple search — weird but accept
                    verified += 1
                    details.append("[S\(citationNum)]: ✓ Source exists")
                }
            } else {
                details.append("[S\(citationNum)]: ✗ Source index out of range")
            }
        }

        let groundingScore = citationNumbers.isEmpty ? 0.5 : Float(verified) / Float(citationNumbers.count)
        return CitationVerificationResult(
            verified: verified,
            totalCitations: citationNumbers.count,
            groundingScore: groundingScore,
            details: details
        )
    }

    /// Build human-readable verification summary
    private func buildVerificationSummary(
        addressesQuestion: Bool,
        addressScore: Float,
        citationResult: CitationVerificationResult,
        calibrated: Float,
        action: String
    ) -> String {
        var parts: [String] = []

        parts.append("Relevance: \(Int(addressScore * 100))%")
        if citationResult.totalCitations > 0 {
            parts.append("Citations: \(citationResult.verified)/\(citationResult.totalCitations) verified")
        }
        parts.append("Confidence: \(Int(calibrated * 100))%")
        parts.append("Action: \(action)")

        return parts.joined(separator: " | ")
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

        // Create detailed event forwarder for verbose ThinkingView events
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        Log.info("[Speculative-RAG] Starting multi-path verification with \(candidateCount) candidates", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Retrieve documents
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let (searchStep, chunks) = try await executeSearchStepWithChunks(
            subQuery: query,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
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

private struct DocumentSemanticProfile {
    let documentName: String
    let chunks: [RetrievedChunk]
    let totalScore: Float
    let weightedTerms: [String: Int]
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
    ///   - forceConfidenceReporting: When true, always include confidence in steps (for multi-chain mode)
    /// - Returns: ReasoningChainResult with synthesized answer
    func executeReasoningChain(
        query: String,
        chunks: [RetrievedChunk],
        config: ReasoningChainConfig = .standard,
        onStep: ((ThinkingStep) async -> Void)? = nil,
        forceConfidenceReporting: Bool = false
    ) async throws -> ReasoningChainResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        let reasoningPolicy = AgenticPolicyService.reasoningPolicy(
            for: config,
            agenticConfig: self.config,
            forceConfidenceReporting: forceConfidenceReporting
        )

        var chainInsights: [String] = []
        var totalTokens = 0
        var allSources: Set<String> = []
        var actualSessionCount = 0
        var cumulativeConfidence: Float = reasoningPolicy.initialConfidence
        let queryEnhancer = QueryEnhancementService()
        var evidenceTracker = FactBank()
        if reasoningPolicy.usesEvidenceDrivenStopping {
            evidenceTracker.queryIntent = queryEnhancer.classifyIntent(query)
            evidenceTracker.initializeWithQuery(query)
        }
        var lowNoveltyStreak = 0
        var saturationStreak = 0
        var usedWindowSources: Set<String> = []

        Log.info("[ReasoningChain] Starting \(reasoningPolicy.isDeepThinkMode ? "dynamic 4-8" : String(config.sessionCount))-session chain for: \(query.prefix(40))... (confidence reporting: \(reasoningPolicy.shouldReportConfidence), threshold: \(Int(reasoningPolicy.confidenceThreshold * 100))%)", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // CHUNK ROTATION: Each session sees a sliding window of chunks
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Session 1: chunks [0..3], Session 2: [2..5], Session 3: [4..7], etc.
        // This ensures the answer gets found even when the reranker is wrong.
        // Multi-session value = depth (repeated reasoning) + breadth (more chunks).

        // For multi-session modes, use smaller context to leave room for accumulated insights
        // Deep Think (4-8 sessions) and Maximum (up to 50) both need room for insight chains
        //
        // FIXED TOKEN BUDGET (context no longer doubled):
        // 4096 total - 80 (system) - 30 (LLM wrapper) - 500 (output) = 3486 tokens ≈ 4880 chars
        // Session 1 (no insights): context up to 4000 chars, prompt text ~300 chars = 4300 (fits)
        // Session 2+ (with insights): context ≤ 2200 + insights ≤ 1200 + prompt ~300 = 3700 (fits)
        // buildChainPrompt handles the per-session budget split (4000 for S1, 2200 for S2+)
        let maxChunksPerSession = (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) ? 4 : 6
        let contextBudget = reasoningPolicy.isUnlimitedMode ? 3000 : (reasoningPolicy.isDeepThinkMode ? 3500 : (config.maxContextPerSession - 500))

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SESSION CONTEXT ROTATION: Different sessions see different chunks
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Previous approach: ALL sessions see the same top-4 chunks.
        // Problem: If reranker scored wrong chunks highest (common for broad-topic
        // queries), ALL sessions reason over irrelevant content and the actual
        // answer chunk is never seen.
        //
        // New approach: Session N sees chunks [N*stride..N*stride+perSession]
        // with stride=2 for overlap. Session 1 gets [0..3], Session 2 gets [2..5],
        // Session 3 gets [4..7], etc. This covers more of the top-20 chunks
        // while maintaining partial overlap for continuity.
        // The multi-session value is BOTH depth AND breadth.
        let chunksPerSession = min(maxChunksPerSession, chunks.count)
        let stride = max(1, chunksPerSession / 2)  // 50% overlap between sessions

        // Use dynamic max for Deep Think mode (can go up to 8 sessions)
        let effectiveMaxSessions = reasoningPolicy.isDeepThinkMode ? reasoningPolicy.maxSessionsForMode : config.sessionCount

        // Build ALL session contexts upfront; each session gets a sliding window
        var sessionContexts: [String] = []
        var sessionOffset = 0
        let totalAvailableChunks = chunks.count

        // Generate enough context windows for all possible sessions
        var sessionSourceSets: [Set<String>] = []
        while sessionContexts.count < effectiveMaxSessions {
            let startIdx = min(sessionOffset, max(0, totalAvailableChunks - chunksPerSession))
            let endIdx = min(startIdx + chunksPerSession, totalAvailableChunks)

            // SENTENCE-LEVEL EXTRACTION: Instead of packing 3-4 whole chunks per session,
            // extract only query-relevant sentences from the window's chunks.
            // With 3000-3500 char budgets per session, this fits targeted data from
            // ALL chunks in the window instead of truncating at 2-3 whole chunks.
            // Universal across all document types — same extraction as Standard pipeline.
            let windowChunks = Array(chunks[startIdx..<endIdx])
            for c in windowChunks { allSources.insert(c.sourceDocument) }
            sessionSourceSets.append(Set(windowChunks.map(\.sourceDocument)))

            let extraction = await ragService.extractRelevantSentences(
                from: windowChunks,
                query: query,
                maxChars: contextBudget,
                compact: true
            )
            var ctx = extraction.context

            // FALLBACK: If keyword extraction returned nothing (common when cross-reference
            // chunks don't contain the original query's keywords), use raw chunk content.
            // These chunks were retrieved by the vector/reranker pipeline for relevance,
            // so they're worth including even if keyword matching is too strict.
            if ctx.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !windowChunks.isEmpty {
                var rawContext = ""
                for (idx, wc) in windowChunks.enumerated() {
                    let content = wc.chunk.parentContent ?? wc.chunk.content
                    let sourceLabel = "[S\(idx + 1)] (\(wc.sourceDocument))"
                    let truncated = String(content.prefix(contextBudget / max(windowChunks.count, 1)))
                    if rawContext.count + truncated.count + sourceLabel.count + 10 < contextBudget {
                        rawContext += sourceLabel + "\n" + truncated + "\n\n---\n"
                    }
                }
                ctx = rawContext
                Log.debug("[ReasoningChain] Session \(sessionContexts.count + 1): keyword extraction empty, using raw chunk content (\(ctx.count) chars)", category: .retrieval)
            } else {
                Log.debug("[ReasoningChain] Session \(sessionContexts.count + 1): \(extraction.sentencesIncluded) sentences from \(extraction.sourcesUsed) sources (\(ctx.count) chars)", category: .retrieval)
            }

            sessionContexts.append(ctx)
            sessionOffset += stride

            // If we've exhausted all chunks, wrap around to top chunks
            if sessionOffset >= totalAvailableChunks {
                sessionOffset = 0
            }
        }

        // For logging, use the first session's context
        let sharedContext = sessionContexts.first ?? ""
        Log.debug("[ReasoningChain] Built \(sessionContexts.count) rotating contexts (first: \(sharedContext.count) chars, \(chunksPerSession) chunks/session, stride \(stride))", category: .retrieval)

        if reasoningPolicy.isUnlimitedMode {
            Log.info("[ReasoningChain] UNLIMITED MODE: Will keep reasoning until \(Int(reasoningPolicy.confidenceThreshold * 100))% confident or \(config.sessionCount) sessions max", category: .llm)
        } else if reasoningPolicy.isDeepThinkMode {
            Log.info("[ReasoningChain] DEEP THINK MODE: Dynamic 4-8 sessions, targeting \(Int(reasoningPolicy.confidenceThreshold * 100))% confidence", category: .llm)
        }

        for sessionIndex in 0..<effectiveMaxSessions {
            let sessionNum = sessionIndex + 1
            actualSessionCount = sessionNum

            if reasoningPolicy.isUnlimitedMode {
                Log.debug("[ReasoningChain] Session \(sessionNum) (unlimited mode, confidence: \(Int(cumulativeConfidence * 100))%)", category: .llm)
            } else if reasoningPolicy.isDeepThinkMode {
                Log.debug("[ReasoningChain] Session \(sessionNum)/4-8 (deep think, confidence: \(Int(cumulativeConfidence * 100))%)", category: .llm)
            } else {
                Log.debug("[ReasoningChain] Session \(sessionNum)/\(config.sessionCount)", category: .llm)
            }

            if Task.isCancelled { break }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Dynamic session stopping based on confidence
            // - Maximum (unlimited): min 8 sessions, target 98%
            // - Deep Think: min 4 sessions, target 85%, max 8 sessions
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if sessionIndex >= reasoningPolicy.minSessionsBeforeEarlyStop {
                if reasoningPolicy.usesEvidenceDrivenStopping {
                    let evidenceCoverageTarget = reasoningPolicy.evidenceCoverageTarget(
                        for: evidenceTracker.subQuestions.count
                    )
                    let sourceCoverage = Float(usedWindowSources.count) / Float(max(allSources.count, 1))
                    let noveltyExhausted = reasoningPolicy.noveltyExhausted(
                        lowNoveltyStreak: lowNoveltyStreak,
                        saturationStreak: saturationStreak,
                        sourceCoverage: sourceCoverage
                    )

                    if cumulativeConfidence >= reasoningPolicy.confidenceThreshold,
                       evidenceTracker.subQuestionConfidence >= evidenceCoverageTarget,
                       noveltyExhausted {
                        let modeName = reasoningPolicy.isUnlimitedMode ? "Maximum" : "Deep Think"
                        Log.info(
                            "[ReasoningChain] \(modeName) mode: stopping at \(Int(cumulativeConfidence * 100))% confidence, coverage=\(Int(evidenceTracker.subQuestionConfidence * 100))%, sourceCoverage=\(Int(sourceCoverage * 100))%, lowNovelty=\(lowNoveltyStreak), saturation=\(saturationStreak)",
                            category: .llm
                        )
                        break
                    }
                } else if cumulativeConfidence >= reasoningPolicy.confidenceThreshold {
                    let modeName = reasoningPolicy.isUnlimitedMode ? "Maximum" : "Deep Think"
                    Log.info("[ReasoningChain] \(modeName) mode: Stopping at \(Int(cumulativeConfidence * 100))% confidence (threshold: \(Int(reasoningPolicy.confidenceThreshold * 100))%)", category: .llm)
                    break
                }
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Each session gets a ROTATED context window for chunk diversity
            // Session 1 sees chunks [0..3], Session 2 sees [2..5], etc.
            // This ensures the answer chunk gets seen even if reranker is wrong
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let contextIndex = min(sessionIndex, sessionContexts.count - 1)
            let sessionContext = sessionContexts[contextIndex]

            // SKIP sessions with empty context — calling the LLM with no documents
            // wastes tokens and produces garbage like "No new information" or refusals.
            // The sliding window can exhaust relevant chunks before all sessions run.
            if sessionContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && sessionIndex > 0 {
                Log.debug("[ReasoningChain] Session \(sessionNum) skipped — empty context window", category: .retrieval)
                continue
            }

            // DEBUG: Log what context is actually being passed
            Log.debug("[ReasoningChain] Session \(sessionNum) context (\(sessionContext.count) chars): \(sessionContext.prefix(500))...", category: .retrieval)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Build session prompt based on position in chain
            // For unlimited/deep think mode, dynamically determine if this should be the "final" session
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let effectiveSessionCount = (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) ? max(effectiveMaxSessions, sessionNum + 3) : config.sessionCount

            // For unlimited mode, use sliding window of recent insights to prevent context overflow
            // Keep only the last 3 insights (each ~500 chars) to stay well under 4096 token limit
            // ALSO apply to Deep Think mode to prevent context overflow on 4-8 sessions
            let insightsForPrompt: [String]
            if (reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode) && chainInsights.count > 3 {
                // Condense older insights into a brief summary + keep recent 2
                // FIXED: Was truncating to 100 chars each, losing most accumulated knowledge.
                // Now keep 250 chars per older insight (2.5x more) and 800 char cap on condensed.
                let oldInsightsCount = chainInsights.count - 2
                // Cut at sentence boundaries. A raw `prefix()` ends the findings block
                // mid-word, and this runs upstream of `buildChainPrompt`, so it is the
                // first place the prompt can be garbled. It also fires exactly at
                // session 5 (`chainInsights.count > 3`), which is where degraded,
                // JSON-shaped insights started in device runs.
                let condensedOld = "Prior findings (\(oldInsightsCount) sessions): " +
                    chainInsights.prefix(oldInsightsCount)
                        .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 }
                        .map { truncateAtSentenceBoundary($0, limit: 250) }
                        .joined(separator: " | ")
                insightsForPrompt = [truncateAtSentenceBoundary(condensedOld, limit: 800)]
                    + Array(chainInsights.suffix(2))
                Log.debug("[ReasoningChain] \(reasoningPolicy.isUnlimitedMode ? "Unlimited" : "Deep Think") mode: condensed \(chainInsights.count) insights to \(insightsForPrompt.count) for prompt", category: .llm)
            } else {
                insightsForPrompt = chainInsights
            }

            let sessionObjective = reasoningPolicy.usesEvidenceDrivenStopping
                ? buildSessionObjective(
                    query: query,
                    factBank: evidenceTracker,
                    sessionIndex: sessionIndex,
                    sessionCount: effectiveSessionCount
                )
                : nil

            let (prompt, systemPrompt) = buildChainPrompt(
                sessionIndex: sessionIndex,
                sessionCount: effectiveSessionCount,
                query: query,
                context: sessionContext,
                previousInsights: insightsForPrompt,
                maxInsightLength: reasoningPolicy.isUnlimitedMode ? 600 : (reasoningPolicy.isDeepThinkMode ? 800 : config.maxInsightLength),
                sessionObjective: sessionObjective
            )

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Execute session with proper consent + context overflow recovery
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            // FIXED: Reduce maxTokens to leave room for context within 4096 limit
            // Budget: system(100) + prompt+context+insights(~2500) + output(700) = ~3300 tokens
            // Increased from 500 to give sessions room for detailed prose instead of truncated bullets
            let sessionMaxTokens = reasoningPolicy.isUnlimitedMode ? 700 : (reasoningPolicy.isDeepThinkMode ? 700 : 600)

            // FIXED: Disable tools for ALL sessions — multi-query retrieval already
            // gathered all needed chunks. Session 1 tool calls waste tokens on useless
            // searches like search_exact_pattern("What's the button do?") which matches nothing.
            // Tool schema alone costs ~400 tokens we can't afford in a 4096 budget.
            let disableToolsForSession = true

            // Attempt execution with automatic context reduction on overflow
            var sessionPrompt = prompt
            let maxRetries = 2

            // CRITICAL FIX: Pass context as empty string to generateWithProperConsent.
            // buildChainPrompt() already embeds DOCUMENTS: in the prompt text.
            // Passing context AGAIN causes LLMService to wrap CONTEXT: around BOTH,
            // resulting in context appearing TWICE in the LLM input — doubling token usage.
            // This was the root cause of constant context overflow (4521+ tokens on a 4096 limit).
            var response: LLMResponse? = nil
            for retryCount in 0...maxRetries {
                // Check cancellation before each LLM call — if user sent a new query,
                // the RAGService cancels this task and we should stop immediately.
                if Task.isCancelled {
                    Log.info("[ReasoningChain] Cancelled before session \(sessionNum) LLM call", category: .llm)
                    break
                }
                do {
                    response = try await ragService.generateWithProperConsent(
                        prompt: sessionPrompt,
                        context: "",
                        systemPrompt: systemPrompt,
                        maxTokens: sessionMaxTokens,
                        disableTools: disableToolsForSession,
                        // The evidence for this session is real, but it lives inside
                        // `sessionPrompt` (see the context: "" note above), so the
                        // planner could not see it and judged every session
                        // `insufficientEvidence` → `.abstain`. All eight sessions then
                        // returned the abstention text as their "insight", which got
                        // condensed and fed to the final synthesis — telling the
                        // synthesizer there was no evidence while twenty chunks sat
                        // beside it. `sourceChunks` is planning-only and is never
                        // rendered into the prompt, so passing it here restores an
                        // honest sufficiency signal without reintroducing the context
                        // doubling that the empty `context` guards against.
                        sourceChunks: chunks,
                        forceOnDevice: true
                    )
                    break // Success - exit retry loop
                } catch {
                    let errorDesc = error.localizedDescription.lowercased()
                    let isContextOverflow = errorDesc.contains("context") || errorDesc.contains("exceeded") ||
                                           errorDesc.contains("4096") || errorDesc.contains("token")

                    if isContextOverflow && retryCount < maxRetries {
                        Log.warning("[ReasoningChain] Session \(sessionNum) context overflow, retry \(retryCount + 1)/\(maxRetries) with reduced prompt", category: .llm)

                        // Reduce prompt by truncating context and insights more aggressively
                        let reductionFactor = 1.0 - (Double(retryCount + 1) * 0.3) // 70%, then 40%
                        let reducedInsights = insightsForPrompt.map { String($0.prefix(Int(Double($0.count) * reductionFactor))) }
                        let reducedContext = String(sessionContext.prefix(Int(Double(sessionContext.count) * reductionFactor)))

                        // Rebuild prompt with reduced content
                        let (reducedPrompt, _) = buildChainPrompt(
                            sessionIndex: sessionIndex,
                            sessionCount: effectiveSessionCount,
                            query: query,
                            context: reducedContext,
                            previousInsights: reducedInsights,
                            maxInsightLength: Int(Double(config.maxInsightLength) * reductionFactor),
                            sessionObjective: sessionObjective
                        )
                        sessionPrompt = reducedPrompt
                        continue
                    }

                    // A transient decode failure from the on-device model, seen on
                    // device as `ParsingError` / "Session ended without producing a
                    // response". It is the same failure that hits MultiQuery
                    // expansion and SmartReply intermittently, and it is more likely
                    // immediately after a rate-limit backoff. Nothing about the
                    // prompt is wrong, so retry it unchanged rather than shrinking
                    // it — the overflow path above would reduce a prompt that was
                    // never too large. Matching on the SDK type as well as the text
                    // because `localizedDescription` collapses to the same generic
                    // "Failed to parse generated content" for several causes.
                    let errorDetail = String(describing: error).lowercased()
                    let isTransientGenerationFailure =
                        errorDetail.contains("parsingerror")
                        || errorDetail.contains("without producing a response")
                        || errorDesc.contains("failed to parse generated content")
                        || errorDesc.contains("rate limit")
                        || errorDesc.contains("rate-limited")

                    if isTransientGenerationFailure && retryCount < maxRetries {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) transient generation failure "
                                + "(\(type(of: error))), retry \(retryCount + 1)/\(maxRetries) with the "
                                + "same prompt after a short backoff",
                            category: .llm
                        )
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        continue
                    }

                    // Out of retries for this session. Leave `response` nil and let
                    // the guard below decide whether the chain can carry on; a dead
                    // session is not necessarily a dead query.
                    if chainInsights.isEmpty {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) failed with no insights yet: "
                                + "\(type(of: error)) — \(error.localizedDescription)",
                            category: .llm
                        )
                        break
                    }
                    Log.warning("[ReasoningChain] Session \(sessionNum) failed, terminating chain early: \(error)", category: .llm)
                    // Return result with what we've accumulated so far
                    return ReasoningChainResult(
                        finalAnswer: cleanupFinalAnswer(chainInsights.last ?? "Unable to complete analysis."),
                        chainInsights: chainInsights,
                        totalTokens: totalTokens,
                        sessionCount: sessionNum - 1,
                        confidence: cumulativeConfidence,
                        sources: Array(allSources)
                    )
                }
            }

            // If we exhausted retries without success, use what we have
            guard let successResponse = response else {
                if chainInsights.isEmpty {
                    // One dead session must not destroy the query. Each session reads
                    // a *different* rotating window of the same retrieved evidence, so
                    // a later one can succeed where this one did not.
                    //
                    // Before this, a single transient `ParsingError` on session 1 threw
                    // the whole query away and the user got "Failed to parse generated
                    // content" with no answer — observed on device, with seven untried
                    // context windows still available and retrieval having succeeded.
                    if sessionIndex < effectiveMaxSessions - 1 {
                        Log.warning(
                            "[ReasoningChain] Session \(sessionNum) produced nothing; advancing to the "
                                + "next context window (\(effectiveMaxSessions - sessionNum) remaining)",
                            category: .llm
                        )
                        continue
                    }
                    // Every session failed. `contextWindowExceeded` was misleading here
                    // — the last failure was usually a decode error, not an overflow.
                    Log.error(
                        "[ReasoningChain] All \(effectiveMaxSessions) sessions failed to produce an insight",
                        category: .llm
                    )
                    throw LLMError.generationFailed(
                        "The on-device model did not return a usable response across "
                            + "\(effectiveMaxSessions) reasoning sessions."
                    )
                }
                Log.warning("[ReasoningChain] Session \(sessionNum) exhausted retries, using accumulated insights", category: .llm)
                return ReasoningChainResult(
                    finalAnswer: cleanupFinalAnswer(chainInsights.last ?? "Unable to complete analysis."),
                    chainInsights: chainInsights,
                    totalTokens: totalTokens,
                    sessionCount: sessionNum - 1,
                    confidence: cumulativeConfidence,
                    sources: Array(allSources)
                )
            }

            totalTokens += successResponse.tokensGenerated

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Check for early completion signal
            // If the model says "ANSWER COMPLETE" or "NOT FOUND", stop early
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let responseText = successResponse.text.uppercased()
            let isAnswerComplete = responseText.contains("ANSWER COMPLETE") ||
                                   responseText.contains("NOT FOUND IN DOCUMENTS") ||
                                   responseText.contains("DOCUMENTS DO NOT CONTAIN")

            if isAnswerComplete && sessionNum >= 2 {
                Log.info("[ReasoningChain] Early termination: model signaled answer complete — breaking to synthesis", category: .llm)
                // Don't append a near-empty termination response to insights.
                // Break out of the session loop and let synthesis handle the final answer.
                // This ensures Deep Think and Maximum modes always run their synthesis pass
                // instead of returning raw concatenated insights.
                break
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // Extract insight to pass to next session
            // For FINAL session, keep FULL response (don't truncate!)
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

            let isFinalSession = sessionIndex == config.sessionCount - 1
            let insight: String

            if isFinalSession {
                // For final synthesis, extract the full answer (not truncated)
                insight = extractFinalAnswer(from: successResponse.text)
            } else {
                // For intermediate sessions, extract condensed insight.
                // Strip echoed prompt headers and invented tool-call syntax first —
                // otherwise a contaminated insight becomes the next session's PRIOR
                // FINDINGS and teaches the next model to produce the same thing.
                insight = stripPromptEchoAndToolNoise(
                    from: extractInsight(from: successResponse.text, maxLength: config.maxInsightLength)
                )
            }

            // Filter out "no new information" responses — they pollute the chain
            // and cause synthesis to include garbage like "No new information found."
            let isEmptyInsight = isUnusableInsight(insight)
            if isEmptyInsight && !isFinalSession {
                Log.debug("[ReasoningChain] Session \(sessionNum) returned empty/refusal insight — skipping", category: .llm)
                continue
            }

            var evidenceConfidence: Float? = nil
            var evidenceCoverage: Float = 0
            var evidenceNovelty: Float = 0
            var evidenceSaturation: Float = 0

            if reasoningPolicy.usesEvidenceDrivenStopping {
                if contextIndex < sessionSourceSets.count {
                    usedWindowSources.formUnion(sessionSourceSets[contextIndex])
                }

                let factUpdate = evidenceTracker.addFacts(from: insight)
                evidenceCoverage = evidenceTracker.subQuestionConfidence
                evidenceNovelty = factUpdate.noveltyScore

                if factUpdate.addedFacts == 0 || factUpdate.noveltyScore < reasoningPolicy.lowNoveltyThreshold {
                    lowNoveltyStreak += 1
                } else {
                    lowNoveltyStreak = 0
                }

                let usedSourceCoverage = Float(usedWindowSources.count) / Float(max(allSources.count, 1))
                let (calculatedConfidence, saturationScore) = AgenticPolicyService.calculateProgressConfidence(
                    allInsights: chainInsights + [insight],
                    query: query,
                    sessionNum: sessionNum,
                    subQuestionConfidence: evidenceCoverage,
                    noveltyScore: factUpdate.noveltyScore,
                    sourceCoverage: usedSourceCoverage,
                    maxConfidence: reasoningPolicy.maxConfidence,
                    sessionBudget: effectiveMaxSessions
                )
                evidenceConfidence = calculatedConfidence
                evidenceSaturation = saturationScore

                if reasoningPolicy.shouldTreatAsSaturated(
                    saturationScore: saturationScore,
                    noveltyScore: factUpdate.noveltyScore,
                    newlyAnsweredSubQuestions: factUpdate.newlyAnsweredSubQuestions
                ) {
                    saturationStreak += 1
                } else {
                    saturationStreak = 0
                }
            }

            // Parse confidence if present, or estimate based on response quality
            // Do this BEFORE appending insight so we can compare with previous insights
            if let conf = parseConfidence(from: successResponse.text) {
                if let evidenceConfidence {
                    let blendedConfidence = min((evidenceConfidence * 0.8) + (conf * 0.2), reasoningPolicy.maxConfidence)
                    cumulativeConfidence = max(cumulativeConfidence, blendedConfidence)
                } else {
                    cumulativeConfidence = (cumulativeConfidence + conf) / 2
                }
            } else if let evidenceConfidence {
                cumulativeConfidence = max(cumulativeConfidence, min(evidenceConfidence, reasoningPolicy.maxConfidence))
                Log.info(
                    "[ReasoningChain] Evidence confidence: \(Int(cumulativeConfidence * 100))% (coverage: \(Int(evidenceCoverage * 100))%, novelty: \(Int(evidenceNovelty * 100))%, saturation: \(Int(evidenceSaturation * 100))%, lowNovelty=\(lowNoveltyStreak), saturationStreak=\(saturationStreak))",
                    category: .llm
                )
            } else if reasoningPolicy.isUnlimitedMode || reasoningPolicy.isDeepThinkMode {
                // Heuristic confidence for Maximum mode:
                // Designed to require 8-15+ sessions before hitting 98%
                // Each component is conservative to ensure deep exploration

                // 1. Session contribution (up to 55%) - more sessions = more exploration
                // DEEP THINK: 8% per session (4 sessions = 32%, 6 = 48%, 7 = 55% cap)
                // MAXIMUM MODE: 3% per session for visible progress (more conservative for long runs)
                // Deep Think needs 85% reachable: 55% session + 20% length + 10% citations = 85%
                let sessionContributionRate: Float = reasoningPolicy.isDeepThinkMode ? 0.08 : 0.03
                let sessionContribution = min(sessionContributionRate * Float(sessionNum), 0.55)

                // 2. Length contribution (up to 20%) - longer insights = more substance
                // Requires 2500+ chars for full bonus
                let lengthContribution = min(Float(insight.count) / 2500.0, 0.20)

                // 3. Citation bonus (up to 10%) - grounded in sources
                let hasCitations = insight.contains("[S") || insight.contains("S1") || insight.contains("S2")
                let citationBonus: Float = hasCitations ? 0.10 : 0

                // 4. Repetition detection (up to 25%) - if repeating, we've exhausted the topic
                // Compare current insight with PREVIOUS insights (before appending)
                // MAXIMUM MODE: Much higher thresholds - designed for deep exploration with many documents
                var repetitionBonus: Float = 0

                // Require more sessions before checking repetition in Maximum mode
                let minSessionsForRepetitionCheck = reasoningPolicy.repetitionCheckStartSession

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
                        let similarityThreshold = reasoningPolicy.repetitionSimilarityThreshold
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
                    let forceTerminationThreshold = reasoningPolicy.repetitionForceTerminationThreshold
                    let forceTerminationCount = reasoningPolicy.repetitionForceTerminationCount
                    let requireConsecutive = reasoningPolicy.repetitionRequiresConsecutive

                    let shouldForceTerminate = requireConsecutive
                        ? (consecutiveSimilar >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)
                        : (similarityCount >= forceTerminationCount || maxOverlapRatio > forceTerminationThreshold)

                    if shouldForceTerminate {
                        // Repetition means we're STUCK, NOT that we found the correct answer.
                        // Don't boost confidence — the answer may be completely wrong.
                        // Just set a termination flag so the loop exits.
                        repetitionBonus = 0.0
                        Log.info("[ReasoningChain] Strong repetition detected (\(similarityCount)/4 similar, consecutive: \(consecutiveSimilar), max overlap: \(Int(maxOverlapRatio * 100))%) - stopping to avoid loops", category: .llm)

                        // FIXED: Do NOT set confidence to threshold. That caused 85% confidence
                        // on wrong answers just because the LLM repeated itself.
                        // Instead, just break out of the session loop.
                        let minSessionsBeforeForceStop = reasoningPolicy.minSessionsBeforeRepetitionStop
                        if sessionNum >= minSessionsBeforeForceStop {
                            Log.info("[ReasoningChain] Forcing early termination due to repetition loop (after \(sessionNum) sessions)", category: .llm)
                            // DON'T touch cumulativeConfidence — keep it at whatever it actually is
                            // The loop will exit because we'll set a flag below
                            chainInsights.append(insight) // Save last insight before breaking
                            break // Exit the session loop immediately
                        } else {
                            Log.info("[ReasoningChain] Repetition detected but continuing (session \(sessionNum) < \(minSessionsBeforeForceStop) minimum)", category: .llm)
                        }
                    } else if similarityCount >= 2 || maxOverlapRatio > 0.60 {
                        // Moderate repetition - slight penalty, not bonus
                        repetitionBonus = 0.0 // Don't reward repetition
                        Log.info("[ReasoningChain] Moderate repetition detected (overlap: \(Int(maxOverlapRatio * 100))%) - no confidence boost", category: .llm)
                    }
                }

                // 5. Exhaustion bonus (up to 15%) - if we're deep in sessions, boost confidence
                // Only kicks in after 10+ sessions (conservative for Maximum mode)
                let exhaustionBonus: Float = sessionNum >= 15 ? 0.15 : (sessionNum >= 12 ? 0.10 : (sessionNum >= 10 ? 0.05 : 0))

                // Only calculate confidence normally if we haven't forced termination
                let confidenceCap = reasoningPolicy.maxConfidence
                if cumulativeConfidence < confidenceCap {
                    let estimatedConfidence = sessionContribution + lengthContribution + citationBonus + repetitionBonus + exhaustionBonus
                    cumulativeConfidence = max(cumulativeConfidence, min(estimatedConfidence, confidenceCap))
                }

                Log.info("[ReasoningChain] Confidence: \(Int(cumulativeConfidence * 100))% (session: \(Int(sessionContribution * 100))%, length: \(Int(lengthContribution * 100))%, citations: \(Int(citationBonus * 100))%, repetition: \(Int(repetitionBonus * 100))%, exhaustion: \(Int(exhaustionBonus * 100))%)", category: .llm)
            }

            // Append insight AFTER confidence check (so we compare with previous insights)
            chainInsights.append(insight)

            // Emit thinking step
            // Session 0 was labelled `.searching` and therefore displayed as
            // RETRIEVAL, but retrieval completed before the chain started; session 0
            // is the initial *analysis* pass over that evidence.
            let stepType: ThinkingStep.StepType = switch sessionIndex {
            case config.sessionCount - 1: .synthesizing
            default: .analyzing
            }

            let step = ThinkingStep(
                id: UUID(),
                type: stepType,
                input: "Session \(sessionNum): \(sessionPromptDescription(sessionIndex, config.sessionCount))",
                output: isFinalSession ? "Synthesizing final answer..." : insight,
                tokensUsed: successResponse.tokensGenerated,
                duration: 0.5,
                timestamp: Date(),
                confidence: reasoningPolicy.shouldReportConfidence ? cumulativeConfidence : nil
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
        if reasoningPolicy.isUnlimitedMode, chainInsights.count >= 3 {
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
            var exhaustivePrompt = "ORIGINAL QUESTION: " + query + "\n\n"
            exhaustivePrompt += "RESEARCH FINDINGS (" + String(actualSessionCount) + " deep-dive sessions):\n"
            exhaustivePrompt += insightsSummary + "\n\n"
            exhaustivePrompt += "TASK: Synthesize an answer that DIRECTLY addresses: \"" + query + "\"\n\n"
            exhaustivePrompt += "REQUIREMENTS:\n"
            exhaustivePrompt += "- First, verify the findings actually answer the original question\n"
            exhaustivePrompt += "- Include specific values, numbers, and specifications found\n"
            exhaustivePrompt += "- Cite specific sources as [S1], [S2], etc.\n"
            exhaustivePrompt += "- Be thorough but stay focused on what was asked\n"
            exhaustivePrompt += "- Write in detailed prose with complete sentences and full paragraphs\n"
            exhaustivePrompt += "- Use ### section headers and **bold** sparingly for key terms\n"
            exhaustivePrompt += "- Use bullet points ONLY for actual lists of items or specifications\n\n"
            exhaustivePrompt += "DIRECT ANSWER:"

            var exhaustiveSystemPrompt = "You synthesize research into a direct, comprehensive answer. "
            exhaustiveSystemPrompt += "First verify the findings answer the original question. "
            exhaustiveSystemPrompt += "If findings are about something else, note that clearly. "
            exhaustiveSystemPrompt += "Include all specific values, numbers, and specifications. "
            exhaustiveSystemPrompt += "Write in detailed prose with complete sentences and natural paragraphs. "
            exhaustiveSystemPrompt += "Use ### headers and **bold** sparingly for key terms. Only use bullets for actual lists."

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
                    maxTokens: synthesisMaxTokens,
                    disableTools: true,
                    qualityMode: .maximum,
                    sourceChunks: chunks
                )
                // Clean up the synthesis output
                finalAnswer = cleanupFinalAnswer(synthesisResponse.text)
                totalTokens += synthesisResponse.tokensGenerated
                Log.info("[ReasoningChain] Exhaustive synthesis: generated \(synthesisResponse.tokensGenerated) tokens (\(finalAnswer.count) chars)", category: .llm)
            } catch {
                Log.warning("[ReasoningChain] Exhaustive synthesis failed, using last insight: \(error)", category: .llm)
                finalAnswer = cleanupFinalAnswer(chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
            }
        } else if reasoningPolicy.isDeepThinkMode, chainInsights.count >= 2 {
            // DEEP THINK MODE: Run a synthesis pass to combine all session findings.
            // Without this, the answer is just the last raw insight (which might be
            // "No new information found" if the last session had no new details).
            // Synthesis merges ALL accumulated findings into one comprehensive answer.
            Log.info("[ReasoningChain] Running Deep Think synthesis (\(chainInsights.count) insights)...", category: .llm)

            // Budget for Deep Think synthesis: keep it tight within 4096
            let maxInsightChars = 3000
            var condensedInsights: [String] = []
            var totalChars = 0

            // Include all insights, truncating individual ones if needed
            for insight in chainInsights {
                let trimmed = insight.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                // Skip empty or "no new info" insights
                if trimmed.count < 20 || trimmed.lowercased().contains("no new information") {
                    continue
                }
                if totalChars + trimmed.count <= maxInsightChars {
                    condensedInsights.append(trimmed)
                    totalChars += trimmed.count
                } else {
                    // Truncate and include
                    let remaining = maxInsightChars - totalChars
                    if remaining > 100 {
                        condensedInsights.append(String(trimmed.prefix(remaining)))
                    }
                    break
                }
            }

            if condensedInsights.isEmpty {
                // All insights were empty/trivial — fall back to last one
                finalAnswer = cleanupFinalAnswer(chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
            } else {
                let insightsSummary = condensedInsights.enumerated()
                    .map { "[\($0.offset + 1)] \($0.element)" }
                    .joined(separator: "\n")

                let synthesisPrompt = """
                QUESTION: \(query)

                ALL FINDINGS:
                \(insightsSummary)

                Write a comprehensive, detailed answer to: "\(query)"
                Combine ALL findings into flowing prose with complete sentences and full paragraphs.
                Use ### section headers to organize topics. Use **bold** sparingly for key terms only.
                Write naturally — use paragraphs for explanations, and bullets only for actual sequential steps or specification lists.
                Include every relevant detail found across all sessions. Cite as [S1], [S2].
                """

                let synthesisSystemPrompt = "Combine all research findings into one comprehensive, well-written answer. Write in detailed prose with complete sentences and natural paragraphs. Use ### headers to organize sections. Use **bold** sparingly for key terms only. Only use bullet points for actual lists of items."

                do {
                    let synthesisResponse = try await ragService.generateWithProperConsent(
                        prompt: synthesisPrompt,
                        context: "",
                        systemPrompt: synthesisSystemPrompt,
                        maxTokens: 1500,
                        disableTools: true,
                        qualityMode: .deepThink,
                        sourceChunks: chunks
                    )
                    finalAnswer = cleanupFinalAnswer(synthesisResponse.text)
                    totalTokens += synthesisResponse.tokensGenerated
                    Log.info("[ReasoningChain] Deep Think synthesis: \(synthesisResponse.tokensGenerated) tokens (\(finalAnswer.count) chars)", category: .llm)
                } catch {
                    Log.warning("[ReasoningChain] Deep Think synthesis failed, using combined insights: \(error)", category: .llm)
                    // Fallback: concatenate all non-trivial insights
                    finalAnswer = cleanupFinalAnswer(condensedInsights.joined(separator: "\n\n"))
                }
            }
        } else {
            // Standard mode: The last insight IS the final answer (session N is synthesis)
            finalAnswer = cleanupFinalAnswer(chainInsights.last ?? "Unable to synthesize answer from reasoning chain.")
        }

        if reasoningPolicy.isUnlimitedMode {
            Log.info("[ReasoningChain] UNLIMITED MODE completed: \(actualSessionCount) sessions, \(totalTokens) tokens, \(Int(cumulativeConfidence * 100))% confidence", category: .llm)
        } else {
            Log.info("[ReasoningChain] Completed \(actualSessionCount) sessions, \(totalTokens) total tokens", category: .llm)
        }

        return ReasoningChainResult(
            finalAnswer: finalAnswer,
            chainInsights: chainInsights,
            totalTokens: totalTokens,
            sessionCount: actualSessionCount,
            confidence: cumulativeConfidence,  // Don't artificially floor — report honestly
            sources: Array(allSources)
        )
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // MARK: - TRUE UNLIMITED REASONING
    // This is what a 10x expert would build: ACTUALLY runs until 98% confident
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// Result from true unlimited reasoning
    struct UnlimitedResult: Sendable {
        let finalAnswer: String
        let steps: [ThinkingStep]
        let totalTokens: Int
        let sessionsRun: Int
        let confidence: Float
        let terminationReason: TerminationReason

        enum TerminationReason: String, Sendable {
            /// Deliberately not "98% confidence achieved": the string is shown beside
            /// the live confidence value, and a device screenshot read
            /// "98% confidence achieved - Confidence: 78%" in a single row.
            case confidenceReached = "Confidence target reached"
            case contentSaturated = "No new insights (content saturated)"
            /// Sub-question coverage stopped improving: the chain kept finding new
            /// text but none of it answered more of the question, which means the
            /// remaining parts are not in this corpus.
            case answerNotInCorpus = "Remaining sub-questions not present in the documents"
            case maxSessionsReached = "Maximum sessions reached"
            case thermalLimit = "Thermal throttling detected"
            case userCancelled = "User cancelled"
            case error = "Model unavailable (inference failed)"
        }
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    // HIERARCHICAL FACT COMPRESSION
    // Solves the "alternator overflow" problem by compressing at each level
    //
    // Level 0: Raw chunks (unlimited) → Level 1: Insights (~800 chars)
    // Level 1: Insights → Level 2: Condensed facts (~200 chars each)
    // Level 2: Facts → Level 3: Core Fact Bank (fixed ~1500 chars)
    // Level 3: Fact Bank → Level 4: Final answer (unlimited via output chaining)
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// A scored fact with relevance to the original query
    struct ScoredFact {
        let content: String
        let normalizedClaim: String
        let supportTerms: [String]
        let evidenceKind: EvidenceKind
        var relevanceScore: Float  // 0-1, higher = more relevant to query
        let sessionAdded: Int      // When it was added (for recency bonus)
        /// Source markers ([S1], [S2] …) captured from the originating sentence.
        ///
        /// Held separately rather than left inline in `content`, because every
        /// extracted sentence is truncated to 150 characters (200 for conceptual
        /// queries) and a citation almost always sits at the end of its sentence —
        /// so the truncation silently ate the attribution. That is why every
        /// Maximum device run reported `citations=0/0` while Deep Think, which
        /// passes untruncated insight text straight through, verified 13–17.
        let sources: [String]

        enum EvidenceKind: String {
            case numeric
            case cited
            case procedural
            case descriptive
        }
    }

    /// Sub-question for query decomposition
    struct SubQuestion {
        let question: String
        var answered: Bool = false
        var evidence: [String] = []  // Facts that address this sub-question
    }

    /// The Fact Bank - intelligent prioritized buffer with query decomposition
    /// Evicts LOW RELEVANCE facts first, not just oldest
    /// Tracks which sub-questions have been answered for REAL confidence
    struct FactBank {
        struct Update {
            let addedFacts: Int
            let noveltyScore: Float
            let newlyAnsweredSubQuestions: Int
            let evidenceCoverage: Float
        }

        /// Core facts with relevance scores
        var scoredFacts: [ScoredFact] = []
        /// Maximum characters for the entire fact bank
        let maxChars: Int = 1500

        /// Sub-questions derived from query decomposition
        var subQuestions: [SubQuestion] = []

        /// Original query terms for relevance scoring
        var queryTerms: Set<String> = []

        /// Uses the app's existing QueryIntent for consistency across the pipeline
        var queryIntent: QueryIntent = .balanced

        /// Current session number for recency scoring
        var currentSession: Int = 0

        /// Initialize with query decomposition
        mutating func initializeWithQuery(_ query: String) {
            // Extract query terms for relevance scoring
            let words = query.lowercased().split(separator: " ").map(String.init)
            let stopWords = Set(["what", "how", "why", "does", "do", "the", "a", "an", "is", "are", "of", "in", "to", "and", "or", "for"])
            queryTerms = Set(words.filter { $0.count > 2 && !stopWords.contains($0) })

            // Decompose into sub-questions (heuristic-based)
            subQuestions = decomposeQuery(query)
        }

        /// Decompose a complex query into sub-questions
        /// Generates topic-specific sub-questions for better coverage tracking
        private func decomposeQuery(_ query: String) -> [SubQuestion] {
            var subs: [SubQuestion] = []
            let lower = query.lowercased()

            // Extract key topic words for sub-question generation
            let stopWords = Set(["what", "how", "why", "does", "do", "the", "a", "an", "is", "are", "of", "in", "to", "and", "or", "for", "on", "with", "about"])
            let topicWords = lower.split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !stopWords.contains($0) }

            // Generate topic-specific sub-questions using actual query terms
            if !topicWords.isEmpty {
                let mainTopic = topicWords.prefix(3).joined(separator: " ")

                // Core sub-questions using the actual topic
                subs.append(SubQuestion(question: "evidence \(mainTopic)"))
                subs.append(SubQuestion(question: "benefits \(mainTopic)"))
                subs.append(SubQuestion(question: "effects \(mainTopic)"))
            }

            // Add dimension-based sub-questions based on query patterns
            let dimensions: [(pattern: String, keywords: [String])] = [
                ("effect", ["effect", "impact", "influence", "change"]),
                ("affect", ["effect", "impact", "influence", "change"]),
                ("benefit", ["benefit", "advantage", "improvement", "positive"]),
                ("harm", ["harm", "risk", "negative", "damage", "concern"]),
                ("cognitive", ["cognitive", "mental", "brain", "thinking", "memory", "attention"]),
                ("how", ["mechanism", "process", "method", "how"]),
                ("why", ["reason", "cause", "because", "why"])
            ]

            for (pattern, keywords) in dimensions where lower.contains(pattern) {
                subs.append(SubQuestion(question: keywords.joined(separator: " ")))
            }

            // Document-grounded checks (not research-oriented — source docs may be manuals, not papers)
            subs.append(SubQuestion(question: "specific details values numbers"))
            subs.append(SubQuestion(question: "notes warnings exceptions"))

            // Deduplicate
            var seen = Set<String>()
            subs = subs.filter { q in
                let key = q.question.prefix(20).lowercased()
                if seen.contains(String(key)) { return false }
                seen.insert(String(key))
                return true
            }

            return subs
        }

        /// Check if a fact addresses any sub-questions and mark them
        /// Uses loose matching - any keyword overlap counts
        private mutating func updateSubQuestionCoverage(fact: String) {
            let factLower = fact.lowercased()
            let factWords = Set(factLower.split(separator: " ").map(String.init).filter { $0.count > 3 })

            for i in 0..<subQuestions.count {
                // Split sub-question into keywords
                let questionWords = Set(subQuestions[i].question.lowercased()
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count > 3 })

                // Check for ANY overlap (loose matching)
                let matchCount = questionWords.intersection(factWords).count

                if matchCount >= 1 {
                    subQuestions[i].evidence.append(String(fact.prefix(80)))
                    // Mark answered after just 1 piece of evidence (loose threshold)
                    if subQuestions[i].evidence.count >= 1 {
                        subQuestions[i].answered = true
                    }
                }
            }
        }

        /// Calculate relevance score for a fact against the query
        private func scoreRelevance(_ fact: String, session: Int) -> Float {
            var score: Float = 0.3 // Base score

            let factLower = fact.lowercased()

            // Query term overlap (0-0.4)
            let matchingTerms = queryTerms.filter { factLower.contains($0) }
            score += Float(matchingTerms.count) / Float(max(1, queryTerms.count)) * 0.4

            // Evidence markers (0-0.2)
            let evidenceMarkers = ["found", "showed", "demonstrated", "significant", "effect", "improved", "increased", "decreased"]
            if evidenceMarkers.contains(where: { factLower.contains($0) }) {
                score += 0.15
            }

            // Quantitative content (0-0.15)
            if fact.contains(where: { $0.isNumber }) || fact.contains("%") {
                score += 0.15
            }

            // Citation (0-0.1)
            if fact.contains("(") && fact.contains(")") && fact.contains(where: { $0.isNumber }) {
                score += 0.1
            }

            // Recency bonus (0-0.1) - newer facts get slight boost
            let recencyBonus = min(0.1, Float(session) / 50.0 * 0.1)
            score += recencyBonus

            return min(1.0, score)
        }

        /// Add new facts with relevance scoring
        mutating func addFacts(from insight: String) -> Update {
            currentSession += 1

            // Extract content based on query intent
            let newFacts = extractFactsFromInsight(insight)
            var existingKeys = Set(scoredFacts.map { normalizedFactKey($0.content) })
            let answeredBefore = subQuestions.filter(\ .answered).count
            var addedFacts = 0
            var noveltyScores: [Float] = []

            for (factContent, factSources) in newFacts {
                let normalizedKey = normalizedFactKey(factContent)
                guard !normalizedKey.isEmpty, !existingKeys.contains(normalizedKey) else { continue }

                existingKeys.insert(normalizedKey)
                noveltyScores.append(noveltyScore(for: factContent))
                let score = scoreRelevance(factContent, session: currentSession)
                scoredFacts.append(ScoredFact(
                    content: factContent,
                    normalizedClaim: normalizedKey,
                    supportTerms: supportTerms(for: factContent),
                    evidenceKind: evidenceKind(for: factContent),
                    relevanceScore: score,
                    sessionAdded: currentSession,
                    sources: factSources
                ))
                addedFacts += 1

                // Check if this fact addresses any sub-questions
                updateSubQuestionCoverage(fact: factContent)
            }

            // Compress using RELEVANCE-BASED eviction
            compressIntelligently()

            let answeredAfter = subQuestions.filter(\ .answered).count
            let averageNovelty = noveltyScores.isEmpty
                ? 0
                : noveltyScores.reduce(0, +) / Float(noveltyScores.count)

            return Update(
                addedFacts: addedFacts,
                noveltyScore: averageNovelty,
                newlyAnsweredSubQuestions: max(0, answeredAfter - answeredBefore),
                evidenceCoverage: subQuestionConfidence
            )
        }

        /// Compress by removing LEAST RELEVANT facts first
        private mutating func compressIntelligently() {
            var totalChars = scoredFacts.map(\.content).joined().count

            while totalChars > maxChars && scoredFacts.count > 3 {
                // Find the lowest relevance fact
                if let minIndex = scoredFacts.enumerated().min(by: { $0.element.relevanceScore < $1.element.relevanceScore })?.offset {
                    scoredFacts.remove(at: minIndex)
                    totalChars = scoredFacts.map(\.content).joined().count
                } else {
                    break
                }
            }

            // Further compress by truncating if still over
            if totalChars > maxChars {
                scoredFacts = scoredFacts.map { fact in
                    ScoredFact(
                        content: String(fact.content.prefix(100)),
                        normalizedClaim: fact.normalizedClaim,
                        supportTerms: fact.supportTerms,
                        evidenceKind: fact.evidenceKind,
                        relevanceScore: fact.relevanceScore,
                        sessionAdded: fact.sessionAdded,
                        // Attribution survives this pass deliberately: content is cut
                        // to 100 characters here, which would destroy any marker left
                        // inline, so `sources` being a separate field is what keeps
                        // the claim citable after compression.
                        sources: fact.sources
                    )
                }
            }
        }

        /// Extract content from prose insight based on query intent
        /// Pull the `[S#]` markers out of a sentence before it is truncated.
        private func sourceMarkers(in sentence: String) -> [String] {
            guard let regex = try? NSRegularExpression(pattern: "\\[S\\d+\\]") else { return [] }
            let range = NSRange(sentence.startIndex..., in: sentence)
            var found: [String] = []
            for m in regex.matches(in: sentence, range: range) {
                if let r = Range(m.range, in: sentence) {
                    let marker = String(sentence[r])
                    if !found.contains(marker) { found.append(marker) }
                }
            }
            return found
        }

        private func extractFactsFromInsight(_ insight: String) -> [(text: String, sources: [String])] {
            var extracted: [(text: String, sources: [String])] = []
            // Sessions cite once, at the top: "[S1] REVIEW ARTICLE — (Psychiatry Clin
            // Neurosci - 2019 …" followed by the reasoning. Splitting into sentences
            // therefore leaves the marker on the *first* fragment and every substantive
            // claim after it with no attribution — and those later claims are the ones
            // that reach the answer. A device run carried [S#] in 14 places and still
            // reported citations=0/0 for exactly this reason.
            //
            // An insight prefixed [S1] is derived from S1 throughout, so a sentence
            // with no marker of its own inherits the insight's.
            let insightSources = sourceMarkers(in: insight)
            let sentences = insight.components(separatedBy: CharacterSet(charactersIn: ".!?"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count > 20 }

            for sentence in sentences {
                let shouldKeep: Bool

                switch queryIntent {
                case .keyword:
                    // PRECISION: quantitative and cited content
                    let hasNumber = sentence.contains(where: { $0.isNumber })
                    let hasPercent = sentence.contains("%")
                    let hasCitation = sentence.contains("(") && sentence.contains(")")
                    let hasKeyTerms = ["found", "showed", "improved", "increased", "decreased", "significant"]
                        .contains { sentence.lowercased().contains($0) }
                    shouldKeep = hasNumber || hasPercent || hasCitation || hasKeyTerms

                case .conceptual:
                    // COMPLETENESS: explanatory and contextual content
                    let hasExplanation = ["because", "therefore", "means", "indicates", "suggests",
                                          "however", "although", "while", "this", "these"]
                        .contains { sentence.lowercased().contains($0) }
                    let hasContext = ["context", "background", "generally", "typically", "often",
                                      "can", "may", "include", "involve", "relate"]
                        .contains { sentence.lowercased().contains($0) }
                    let isSubstantive = sentence.count > 50
                    shouldKeep = hasExplanation || hasContext || isSubstantive

                case .balanced:
                    // BOTH facts AND context
                    let hasNumber = sentence.contains(where: { $0.isNumber })
                    let hasPercent = sentence.contains("%")
                    let hasCitation = sentence.contains("(") && sentence.contains(")")
                    let hasKeyTerms = ["found", "showed", "improved", "increased", "decreased", "significant",
                                       "because", "therefore", "however", "suggests", "indicates"]
                        .contains { sentence.lowercased().contains($0) }
                    let isSubstantive = sentence.count > 60
                    shouldKeep = hasNumber || hasPercent || hasCitation || hasKeyTerms || isSubstantive
                }

                if shouldKeep {
                    let maxLen = queryIntent == .conceptual ? 200 : 150
                    // Capture attribution from the *full* sentence before truncating.
                    let ownSources = sourceMarkers(in: sentence)
                    extracted.append((
                        String(sentence.prefix(maxLen)),
                        ownSources.isEmpty ? insightSources : ownSources
                    ))
                }
            }

            // Fallback if nothing extracted
            if extracted.isEmpty && !insight.isEmpty {
                let fallbackLen = queryIntent == .conceptual ? 250 : 150
                extracted.append((String(insight.prefix(fallbackLen)), insightSources))
            }

            return extracted
        }

        private func normalizedFactKey(_ fact: String) -> String {
            fact.lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
                .prefix(20)
                .joined(separator: " ")
        }

        private func noveltyScore(for fact: String) -> Float {
            let factTokens = tokenSet(for: fact)
            guard !factTokens.isEmpty else { return 0 }
            guard !scoredFacts.isEmpty else { return 1 }

            let maxOverlap = scoredFacts.reduce(Float(0)) { currentMax, existing in
                let existingTokens = tokenSet(for: existing.content)
                guard !existingTokens.isEmpty else { return currentMax }
                let overlap = Float(factTokens.intersection(existingTokens).count)
                let union = Float(factTokens.union(existingTokens).count)
                guard union > 0 else { return currentMax }
                return max(currentMax, overlap / union)
            }

            return max(0, 1 - maxOverlap)
        }

        private func supportTerms(for fact: String) -> [String] {
            var seen: Set<String> = []
            return fact.lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
                .filter { seen.insert($0).inserted }
                .prefix(5)
                .map { $0 }
        }

        private func evidenceKind(for fact: String) -> ScoredFact.EvidenceKind {
            let lower = fact.lowercased()
            if fact.contains(where: { $0.isNumber }) || fact.contains("%") {
                return .numeric
            }
            if fact.contains("[S") || (fact.contains("(") && fact.contains(")")) {
                return .cited
            }
            if lower.hasPrefix("step") || lower.hasPrefix("first") || lower.hasPrefix("then") {
                return .procedural
            }
            return .descriptive
        }

        private func tokenSet(for text: String) -> Set<String> {
            Set(
                text.lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count > 3 && !Self.factStopWords.contains($0) }
            )
        }

        private static let factStopWords: Set<String> = [
            "about", "after", "also", "among", "been", "being", "could", "from", "into", "just",
            "more", "much", "only", "over", "same", "some", "than", "that", "their", "there",
            "these", "they", "this", "very", "were", "what", "when", "where", "which", "with",
            "would"
        ]

        /// Get fact bank as context string (sorted by relevance)
        func asContext() -> String {
            if scoredFacts.isEmpty { return "" }
            let sorted = scoredFacts.sorted { $0.relevanceScore > $1.relevanceScore }
            return "CLAIM BANK:\n" + sorted.map { fact in
                let termSummary = fact.supportTerms.isEmpty ? "" : "; terms=" + fact.supportTerms.joined(separator: ",")
                // Attribution travels with the claim. Without it the final synthesis
                // has nothing to cite, which is why Self-RAG scored Maximum 0/0.
                let sourceSummary = fact.sources.isEmpty ? "" : " " + fact.sources.joined(separator: " ")
                return "• claim=\(fact.content)\(sourceSummary); kind=\(fact.evidenceKind.rawValue)\(termSummary)"
            }.joined(separator: "\n")
        }

        /// Get REAL confidence based on sub-question coverage
        var subQuestionConfidence: Float {
            guard !subQuestions.isEmpty else { return 0.5 }
            let answeredCount = subQuestions.filter(\.answered).count
            return Float(answeredCount) / Float(subQuestions.count)
        }

        /// Get unanswered sub-questions for gap-aware expansion
        var unansweredQuestions: [String] {
            subQuestions.filter { !$0.answered }.map(\.question)
        }

        /// Get count and size info
        var summary: String {
            let answered = subQuestions.filter(\.answered).count
            return "\(scoredFacts.count) claims, \(answered)/\(subQuestions.count) sub-Qs answered"
        }

        /// Legacy accessor for coreFacts (compatibility)
        var coreFacts: [String] {
            scoredFacts.map(\.content)
        }
    }

    /// TRUE UNLIMITED REASONING: Continues until 98% confident or saturated
    /// Uses hierarchical compression to NEVER hit token limits
    ///
    /// Architecture:
    /// ┌─────────────────────────────────────────────────────────────┐
    /// │ Session N: [Query + 3 chunks + Fact Bank hint] → Insight   │
    /// │     ↓                                                       │
    /// │ Extract facts → Add to Fact Bank (auto-compresses)         │
    /// │     ↓                                                       │
    /// │ Every 5 sessions: Synthesize running answer                 │
    /// │     ↓                                                       │
    /// │ Repeat until 98% confident or saturated                     │
    /// │     ↓                                                       │
    /// │ Chain multiple output passes for final answer               │
    /// └─────────────────────────────────────────────────────────────┘
    func executeTrueUnlimitedReasoning(
        query: String,
        allChunks: [RetrievedChunk],
        targetConfidence: Float = 0.98,
        maxSessions: Int = 50,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> UnlimitedResult {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // Scale the ceiling to the evidence actually retrieved rather than always
        // allowing 50. Each session reads 3 chunks and prefers unseen ones, so a pool
        // of N chunks is fully covered in about N/3 sessions; 1.5x leaves room to
        // revisit and connect. A one-document library therefore gets roughly a dozen
        // sessions and a large corpus still gets the full budget.
        //
        // This is a backstop, not the mechanism — the convergence rule below is what
        // should normally end a run. It exists so that a pathological case cannot
        // spend 26 minutes re-reading 65 chunks, which is what a device trace showed
        // when the stop condition was unreachable.
        // The ceiling is a runaway guard, not a policy lever. Convergence is what
        // ends a run, and it works: a device trace stopped at session 23 on its own.
        //
        // An earlier version of this budgeted only the top 60% of the relevance-ordered
        // pool, on the theory that late sessions read the weakest chunks. The same
        // trace refutes it — sessions 16 through 22 ran at 66–86% novelty and the chain
        // stopped on *saturation*, with `lowNoveltyStreak=0`, meaning it was still
        // finding new material when it quit. A 60% ceiling would have cut seven
        // productive sessions.
        //
        // The division of labour that is actually correct: retrieval decides what is
        // relevant, and does so with scores you can inspect; convergence decides when
        // reasoning has stopped paying; the ceiling only stops a pathological run.
        // A blunt percentage is neither a score nor an earned stop, so it belongs to
        // neither stage.
        let chunksPerSession = 3
        let coveragePasses = Int(ceil(Double(allChunks.count) / Double(chunksPerSession)))
        let evidenceScaledCeiling = max(8, Int(Double(coveragePasses) * 1.5))
        let effectiveMaxSessions = min(maxSessions, evidenceScaledCeiling)
        if effectiveMaxSessions < maxSessions {
            Log.info(
                "[Unlimited] Session ceiling scaled to evidence: \(effectiveMaxSessions) "
                    + "(pool=\(allChunks.count) chunks, requested max=\(maxSessions))",
                category: .llm
            )
        }

        let unlimitedPolicy = AgenticPolicyService.unlimitedReasoningPolicy(
            targetConfidence: targetConfidence,
            maxSessions: effectiveMaxSessions
        )

        let startTime = Date()
        var totalTokens = 0
        var allInsights: [String] = []
        var steps: [ThinkingStep] = []

        // Create detailed event forwarder for console output (Maximum mode gets full pipeline visibility)
        let detailedForwarder = makeDetailedEventForwarder(onStep: onStep)

        // Use the app's unified QueryIntent classification for consistency
        // This aligns FactBank extraction with hybrid search weight adjustments
        let queryEnhancer = QueryEnhancementService()
        let queryIntent = queryEnhancer.classifyIntent(query)

        var factBank = FactBank()
        factBank.queryIntent = queryIntent
        factBank.initializeWithQuery(query) // Decompose query into sub-questions
        Log.info("[Unlimited] FactBank: QueryIntent=\(queryIntent.rawValue), \(factBank.subQuestions.count) sub-questions", category: .llm)

        var currentAnswer = ""
        var confidence: Float = unlimitedPolicy.initialConfidence
        var terminationReason: UnlimitedResult.TerminationReason = .maxSessionsReached

        // Track content saturation via semantic similarity
        var saturationStreak = 0
        var lowNoveltyStreak = 0
        // Sub-question coverage over time. Novelty measures new *text*; this measures
        // new *answer*. A device run held coverage at 80% from session 1 through 22
        // while novelty ran 66–86% — the chain was reading fresh material that
        // answered nothing further, for twenty sessions, because nothing else it
        // needed was in the document. That is the signal for "the rest is not here",
        // and neither novelty nor saturation can express it.
        var coveragePlateauStreak = 0
        var bestCoverage: Float = -1
        var consecutiveFailures = 0 // Track empty/failed responses from model
        var expansionCount = 0
        let maxExpansions = 3 // Allow up to 3 retrieval expansions (theoretically unlimited chunks)

        // Mutable chunk pool - can EXPAND during reasoning via adaptive retrieval
        var sortedChunks = allChunks.sorted { $0.similarityScore > $1.similarityScore }
        var usedChunkIds = Set<UUID>() // Track which chunks we've already processed

        Log.info("[Unlimited] Starting TRUE unlimited reasoning: target=\(Int(targetConfidence * 100))%, max=\(effectiveMaxSessions) sessions, chunks=\(sortedChunks.count)", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // THE UNLIMITED LOOP - runs until confidence OR exhaustion
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        for sessionNum in 1...effectiveMaxSessions {
            let evidenceCoverageTarget = unlimitedPolicy.evidenceCoverageTarget(
                for: factBank.subQuestions.count
            )
            let sourceCoverage = Float(usedChunkIds.count) / Float(max(sortedChunks.count, 1))
            let noveltyExhausted = unlimitedPolicy.noveltyExhausted(
                lowNoveltyStreak: lowNoveltyStreak,
                saturationStreak: saturationStreak,
                sourceCoverage: sourceCoverage
            )

            // Two independent reasons to stop, not one conjunction of three.
            //
            // The old condition required confidence >= 0.98 AND coverage AND novelty
            // exhaustion simultaneously, and 0.98 is unreachable: `sessionProgress`
            // caps at 0.68, and the rest has to come from coverage and novelty terms
            // minus a saturation penalty that grows as the chain matures. High novelty
            // late means you have not saturated; low novelty means the penalty eats
            // the gain. Device runs peaked at 89% and therefore always ran the full
            // 50 sessions, even with novelty at 50% and saturation at 90% — the chain
            // knew it was finished and kept going.
            //
            // `noveltyExhausted` is already a correct marginal-gain stopping rule
            // (streak-based patience over low novelty, high saturation, or 85% source
            // coverage). It was simply gated behind a number it could never reach.
            //
            //   completed  — the question is answered to target confidence
            //   converged  — nothing new is being learned, and enough of the evidence
            //                has been seen that this is exhaustion rather than a
            //                cold start
            // Has answering *progressed*, as distinct from text being *new*?
            let coverageNow = factBank.subQuestionConfidence
            if coverageNow > bestCoverage + 0.001 {
                bestCoverage = coverageNow
                coveragePlateauStreak = 0
            } else {
                coveragePlateauStreak += 1
            }

            let completed = confidence >= targetConfidence
                && factBank.subQuestionConfidence >= evidenceCoverageTarget
            let converged = noveltyExhausted
                && sessionNum >= unlimitedPolicy.minimumSessionsBeforeConvergence
            // A flat coverage streak is *observed and logged, but not acted on*.
            //
            // It was briefly a stop condition and that was a mistake, measured on the
            // same corpus and question across three runs:
            //
            //   ceiling 50, no convergence   50 sessions   48 chars, 0 citations
            //   saturation convergence       23 sessions  209 chars, 1/2 verified, accept
            //   coverage plateau              8 sessions   67 chars, 0/1 verified, retry
            //
            // Coverage measures *breadth* — which sub-questions are answered — and it
            // was flat from session 1 because the last one was never in the document.
            // Novelty stayed at 61–86% because the chain was still accumulating
            // *depth*: more supporting evidence for the sub-questions already covered.
            // That depth is what let synthesis produce a citation the verifier could
            // check. Stopping on breadth alone cut it off and produced a shorter,
            // more confident, *less supported* answer — the worst direction to move.
            //
            // Saturation-based convergence is the empirically better proxy. Keep the
            // plateau visible for diagnosis; do not let it end a run.
            if coveragePlateauStreak == unlimitedPolicy.coveragePlateauStreakThreshold {
                Log.info(
                    "[Unlimited] Session \(sessionNum): sub-question coverage flat at "
                        + "\(Int(bestCoverage * 100))% for \(coveragePlateauStreak) sessions — "
                        + "remaining sub-questions look absent from this corpus. Continuing: "
                        + "later sessions still add supporting depth.",
                    category: .llm
                )
            }
            if completed || converged {
                terminationReason = .confidenceReached
                Log.info(
                    "[Unlimited] Session \(sessionNum): confidence=\(Int(confidence * 100))%, coverage=\(Int(factBank.subQuestionConfidence * 100))%, lowNoveltyStreak=\(lowNoveltyStreak) - STOPPING",
                    category: .llm
                )
                break
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // ADAPTIVE RETRIEVAL: When saturated, expand chunk pool
            // This is the "truly unlimited" part - we fetch MORE data
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            if saturationStreak >= unlimitedPolicy.saturationStreakThreshold {
                if expansionCount < maxExpansions {
                    // Generate new queries based on what FactBank has learned
                    let expansionQueries = generateExpansionQueries(
                        originalQuery: query,
                        factBank: factBank
                    )

                    await detailedForwarder?(.iterative, "Adaptive expansion", "Generating \(expansionQueries.count) new search queries")

                    var newChunks: [RetrievedChunk] = []
                    for (idx, expQuery) in expansionQueries.enumerated() {
                        await detailedForwarder?(.retrieval, "Expansion \(idx + 1)/\(expansionQueries.count)", "\"\(expQuery.prefix(40))...\"")

                        // Use full retrieval pipeline with event forwarding for Maximum mode visibility
                        if let chunks = try? await ragService.executeFullRetrievalPipeline(
                            query: expQuery,
                            topK: 20,
                            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .fallback),
                            qualityMode: qualityMode,
                            onDetailedEvent: detailedForwarder
                        ) {
                            for chunk in chunks where !usedChunkIds.contains(chunk.chunk.id) {
                                newChunks.append(chunk)
                            }
                        }
                    }

                    if !newChunks.isEmpty {
                        // Add new chunks to the pool
                        sortedChunks.append(contentsOf: newChunks)
                        sortedChunks.sort { $0.similarityScore > $1.similarityScore }
                        expansionCount += 1
                        saturationStreak = 0 // Reset saturation

                        Log.info("[Unlimited] EXPANSION \(expansionCount)/\(maxExpansions): Added \(newChunks.count) new chunks (total: \(sortedChunks.count))", category: .llm)

                        await detailedForwarder?(.iterative, "Expansion complete", "+\(newChunks.count) chunks (pool: \(sortedChunks.count))")

                        // Emit expansion step
                        let expansionStep = ThinkingStep(
                            id: UUID(),
                            type: .searching,
                            input: "Adaptive retrieval expansion",
                            output: "Found \(newChunks.count) additional sources to explore",
                            tokensUsed: 0,
                            duration: 0.2,
                            timestamp: Date(),
                            confidence: confidence
                        )
                        steps.append(expansionStep)
                        await onStep?(expansionStep)
                    } else {
                        // No new chunks found - truly saturated
                        terminationReason = .contentSaturated
                        Log.info("[Unlimited] Session \(sessionNum): No new content found after expansion - STOPPING", category: .llm)
                        break
                    }
                } else {
                    // Max expansions reached - all avenues exhausted
                    terminationReason = .contentSaturated
                    Log.info("[Unlimited] Session \(sessionNum): Max expansions (\(maxExpansions)) reached - STOPPING", category: .llm)
                    break
                }
            }

            // Select UNUSED chunks for this session - prioritize fresh content
            let unusedChunks = sortedChunks.filter { !usedChunkIds.contains($0.chunk.id) }
            let sessionChunks: [RetrievedChunk]
            if unusedChunks.count >= 3 {
                sessionChunks = Array(unusedChunks.prefix(3))
            } else if !unusedChunks.isEmpty {
                // Use remaining unused + cycle back to highest relevance
                sessionChunks = unusedChunks + Array(sortedChunks.prefix(3 - unusedChunks.count))
            } else {
                // All chunks used - cycle through top chunks
                let chunkStartIdx = ((sessionNum - 1) * 2) % max(1, sortedChunks.count)
                sessionChunks = Array(sortedChunks.dropFirst(chunkStartIdx).prefix(3))
            }

            // Mark these chunks as used
            for chunk in sessionChunks {
                usedChunkIds.insert(chunk.chunk.id)
            }

            // Build context with strict character limit
            // SENTENCE-LEVEL EXTRACTION: Instead of packing 2-3 whole chunks into
            // 2500 chars, extract query-relevant sentences from the session's chunks.
            // This fits targeted data from all available chunks instead of
            // truncating mid-sentence. Universal across all document types.
            let maxContextChars = 2500 // ~600 tokens, leaves room for prompt + response
            let extraction = await ragService.extractRelevantSentences(
                from: sessionChunks,
                query: query,
                maxChars: maxContextChars,
                compact: true
            )
            let context = extraction.context
            Log.debug("[Unlimited] Session \(sessionNum): \(extraction.sentencesIncluded) sentences from \(extraction.sourcesUsed) sources (\(context.count) chars)", category: .retrieval)

            // Build prompt based on session stage
            let (prompt, systemPrompt) = buildUnlimitedSessionPrompt(
                sessionNum: sessionNum,
                query: query,
                context: context,
                previousInsights: allInsights,
                currentAnswer: currentAnswer
            )

            // Adaptive temperature: higher early (exploration), lower late (precision)
            let adaptiveTemp: Float
            if sessionNum <= 3 {
                adaptiveTemp = 0.7 // Early: divergent, exploratory
            } else if sessionNum <= 8 {
                adaptiveTemp = 0.5 // Middle: balanced
            } else {
                adaptiveTemp = 0.3 // Late: focused, precise
            }

            // Execute LLM call - tools DISABLED to prevent context overflow
            // Chunks are already gathered and passed in the prompt
            let sessionStart = Date()
            let response: LLMResponse
            do {
                response = try await ragService.generateWithProperConsent(
                prompt: prompt,
                context: "",
                systemPrompt: systemPrompt,
                maxTokens: 1000,
                disableTools: true,
                temperature: adaptiveTemp,
                // Same defect that made Deep Think inert, in Maximum's own loop:
                // `context` is deliberately empty because the prompt already embeds
                // the evidence, so with no chunks the planner saw `chunkCount == 0`,
                // judged `insufficientEvidence`, and abstained on every session.
                // A device run retrieved 103 chunks at 84/72/67% and then reported
                // "Integrating 0 insights" before bailing in 17.8s.
                //
                // `sortedChunks` rather than `allChunks`: this loop grows its pool
                // through adaptive retrieval when it saturates, so the live pool is
                // what the planner must judge.
                sourceChunks: sortedChunks,
                forceOnDevice: true
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // This loop already survives a session that *returns* nothing, via
                // the `consecutiveFailures` three-strike counter below. A session
                // that *throws* skipped that machinery entirely and killed the whole
                // query. Observed on device: session 1 succeeded, session 2 hit
                // "[RAG] Primary LLM rate-limited", retried, failed with
                // ParsingError / "Session ended without producing a response", and
                // the run ended with no answer at all.
                //
                // The equivalent guard was added to `executeReasoningChain` in
                // fda58ed; Maximum runs this loop instead and never received it.
                // Route thrown failures into the same counter rather than inventing
                // a second recovery path.
                consecutiveFailures += 1
                Log.warning(
                    "[Unlimited] Session \(sessionNum) threw (failure \(consecutiveFailures)/3): "
                        + "\(type(of: error)) — \(error.localizedDescription)",
                    category: .llm
                )
                if consecutiveFailures >= 3 {
                    Log.error(
                        "[Unlimited] STOPPING: 3 consecutive generation failures",
                        category: .llm
                    )
                    terminationReason = .error
                    break
                }
                // Transient decode failures cluster right after a rate-limit backoff,
                // so give the model a moment before the next session.
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                continue
            }
            let sessionDuration = Date().timeIntervalSince(sessionStart)
            totalTokens += response.tokensGenerated

            let insight = cleanupFinalAnswer(response.text, isFinalAnswer: false)
            let responseTextLength = response.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            let insightLength = insight.trimmingCharacters(in: .whitespacesAndNewlines).count

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // CRITICAL: Detect model failures (0 tokens = ANE/PCC failure)
            // Don't count empty responses toward confidence or session count
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // `tokensGenerated == 0` alone was the entire test here, so a session that
            // answered "Please provide additional context" counted as a finding: it has
            // tokens. Route unusable text into the same three-strike counter as an
            // empty response — three in a row means the model is stuck, not thinking.
            let isEmpty = response.tokensGenerated == 0
                || responseTextLength == 0
                || insightLength == 0
                || isUnusableInsight(insight)

            if isEmpty {
                consecutiveFailures += 1
                Log.warning("[Unlimited] Session \(sessionNum): EMPTY RESPONSE DETECTED (failure \(consecutiveFailures)/3) - tokens=\(response.tokensGenerated), rawLen=\(responseTextLength), cleanLen=\(insightLength)", category: .llm)

                // Stop after 3 consecutive failures to avoid infinite loop
                if consecutiveFailures >= 3 {
                    Log.error("[Unlimited] STOPPING: 3 consecutive empty responses - model unavailable", category: .llm)
                    terminationReason = .error
                    break
                }

                // Don't update confidence or add to insights - just try next session
                continue
            }

            // Reset failure counter on successful response
            consecutiveFailures = 0
            allInsights.append(insight)

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // HIERARCHICAL COMPRESSION: Extract facts into Fact Bank
            // This is the "alternator" that never overflows
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let factUpdate = factBank.addFacts(from: insight)
            if factUpdate.addedFacts == 0 || factUpdate.noveltyScore < unlimitedPolicy.lowNoveltyThreshold {
                lowNoveltyStreak += 1
            } else {
                lowNoveltyStreak = 0
            }

            if sessionNum % 3 == 0 {
                Log.info(
                    "[Unlimited] Fact Bank: \(factBank.summary), +\(factUpdate.addedFacts) facts, novelty=\(Int(factUpdate.noveltyScore * 100))%, coverage=\(Int(factUpdate.evidenceCoverage * 100))%",
                    category: .llm
                )
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // REAL CONFIDENCE CALCULATION - blends session progress with sub-question coverage
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let usedSourceCoverage = Float(usedChunkIds.count) / Float(max(sortedChunks.count, 1))
            let (newConfidence, saturationScore) = calculateRealConfidence(
                allInsights: allInsights,
                query: query,
                sessionNum: sessionNum,
                subQuestionConfidence: factBank.subQuestionConfidence,
                noveltyScore: factUpdate.noveltyScore,
                sourceCoverage: usedSourceCoverage,
                maxConfidence: unlimitedPolicy.maxConfidence
            )

            // Update saturation tracking
            if unlimitedPolicy.shouldTreatAsSaturated(
                saturationScore: saturationScore,
                noveltyScore: factUpdate.noveltyScore,
                newlyAnsweredSubQuestions: factUpdate.newlyAnsweredSubQuestions
            ) {
                saturationStreak += 1
                Log.info("[Unlimited] Session \(sessionNum): High saturation (\(Int(saturationScore * 100))%), streak=\(saturationStreak)", category: .llm)
            } else {
                saturationStreak = 0 // Reset streak on valuable session
            }

            // Confidence can only go UP (ratchet)
            confidence = max(confidence, newConfidence)

            // Every 5 sessions, compress insights using the Fact Bank
            // This prevents the "alternator overflow" problem
            if sessionNum % 5 == 0 {
                currentAnswer = try await synthesizeRunningAnswer(
                    query: query,
                    factBank: factBank,
                    recentInsights: Array(allInsights.suffix(3)),
                    previousAnswer: currentAnswer,
                    sourceChunks: sortedChunks
                )
                totalTokens += 200 // Estimate for synthesis
            }

            // Every session here is a reasoning pass over evidence that was already
            // retrieved before session 1 began — the console shows "Retrieval
            // complete" above them. Labelling the first two `.searching` rendered
            // them as RETRIEVAL in the live pipeline, the same class of mislabel as
            // `.analyzing` reporting as RE-RANKING. Only a session that is actually
            // consolidating gets `.synthesizing`.
            let stepType: ThinkingStep.StepType = confidence >= 0.9 ? .synthesizing : .analyzing

            // Emit step with REAL confidence
            let step = ThinkingStep(
                id: UUID(),
                type: stepType,
                input: "Session \(sessionNum)/\(effectiveMaxSessions)",
                output: String(insight.prefix(500)) + (insight.count > 500 ? "..." : ""),
                tokensUsed: response.tokensGenerated,
                duration: sessionDuration,
                timestamp: Date(),
                confidence: confidence
            )
            steps.append(step)
            await onStep?(step)

            Log.info(
                "[Unlimited] Session \(sessionNum): confidence=\(Int(confidence * 100))%, coverage=\(Int(factBank.subQuestionConfidence * 100))%, novelty=\(Int(factUpdate.noveltyScore * 100))%, saturation=\(Int(saturationScore * 100))%, tokens=\(response.tokensGenerated)",
                category: .llm
            )
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // FINAL SYNTHESIS - produce the comprehensive answer
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let synthesisStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Final synthesis",
            output: "Integrating \(allInsights.count) insights into comprehensive answer...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: min(confidence + 0.02, unlimitedPolicy.maxConfidence)
        )
        steps.append(synthesisStep)
        await onStep?(synthesisStep)

        let finalAnswer = try await synthesizeFinalUnlimitedAnswer(
            query: query,
            factBank: factBank,
            allInsights: allInsights,
            currentAnswer: currentAnswer,
            sourceChunks: sortedChunks
        )
        totalTokens += 500 // Estimate for final synthesis

        let totalDuration = Date().timeIntervalSince(startTime)

        Log.info("[Unlimited] COMPLETE: \(allInsights.count) sessions, \(Int(confidence * 100))% confident, \(terminationReason.rawValue), \(String(format: "%.1f", totalDuration))s", category: .llm)

        // Emit completion step
        let completionStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Complete",
            output: terminationReason.rawValue,
            tokensUsed: 0,
            duration: totalDuration,
            timestamp: Date(),
            confidence: confidence
        )
        steps.append(completionStep)
        await onStep?(completionStep)

        return UnlimitedResult(
            finalAnswer: finalAnswer,
            steps: steps,
            totalTokens: totalTokens,
            sessionsRun: allInsights.count,
            confidence: confidence,
            terminationReason: terminationReason
        )
    }

    /// Calculate REAL confidence based on multiple factors
    /// Balances sub-question coverage with session progress and content quality
    private func calculateRealConfidence(
        allInsights: [String],
        query: String,
        sessionNum: Int,
        subQuestionConfidence: Float,
        noveltyScore: Float,
        sourceCoverage: Float,
        maxConfidence: Float
    ) -> (confidence: Float, saturationScore: Float) {
        AgenticPolicyService.calculateProgressConfidence(
            allInsights: allInsights,
            query: query,
            sessionNum: sessionNum,
            subQuestionConfidence: subQuestionConfidence,
            noveltyScore: noveltyScore,
            sourceCoverage: sourceCoverage,
            maxConfidence: maxConfidence
        )
    }

    /// Build prompt for unlimited session based on stage
    /// CRITICAL: Each prompt must fit in ~1500 tokens to leave room for context + response
    private func buildUnlimitedSessionPrompt(
        sessionNum: Int,
        query: String,
        context: String,
        previousInsights: [String],
        currentAnswer: String
    ) -> (prompt: String, systemPrompt: String) {
        // Keep insight summary very compact - just hints, not full content
        let insightSummary = previousInsights.isEmpty ? "" :
            "Prior findings: " + previousInsights.suffix(2).map { String($0.prefix(150)) }.joined(separator: " | ")

        // Core instruction for all sessions: document-grounded, anti-hallucination
        let coreInstruction = "Report ONLY facts found in these documents. Never invent statistics, studies, or claims not in the text."

        if sessionNum == 1 {
            // First session: Initial exploration
            return (
                """
                Q: \(query)

                DOCUMENTS FROM USER'S LIBRARY:
                \(context)

                Extract specific facts, numbers, and details from these documents.
                \(coreInstruction)
                """,
                "Document analyst. Extract ONLY facts present in the documents. Never fabricate statistics or research claims."
            )
        } else if sessionNum <= 5 {
            // Early sessions: Build breadth
            return (
                """
                Q: \(query)
                \(insightSummary)

                ADDITIONAL DOCUMENTS:
                \(context)

                What NEW facts or details do these documents add? Avoid repeating prior findings.
                \(coreInstruction)
                """,
                "Document analyst. Find new details from documents only. Never fabricate. Avoid repetition."
            )
        } else if sessionNum <= 15 {
            // Middle sessions: Build depth - use currentAnswer summary
            let answerHint = currentAnswer.isEmpty ? "" : "Current summary covers: \(String(currentAnswer.prefix(300)))..."
            return (
                """
                Q: \(query)
                \(answerHint)

                DOCUMENTS:
                \(context)

                Add nuances or deeper details not yet covered from these documents.
                \(coreInstruction)
                """,
                "Document analyst. Find nuances from documents only. Never invent facts."
            )
        } else {
            // Later sessions: Refine and verify
            return (
                """
                Q: \(query)

                DOCUMENTS:
                \(context)

                Verify findings against these documents. Add supporting details found in the text.
                \(coreInstruction)
                """,
                "Document analyst. Verify against source text. Never fabricate."
            )
        }
    }

    /// Synthesize running answer using the Fact Bank (hierarchical compression)
    /// Uses the compressed fact bank instead of raw insights to prevent overflow
    private func synthesizeRunningAnswer(
        query: String,
        factBank: FactBank,
        recentInsights: [String],
        previousAnswer: String,
        /// The live retrieved pool. Passed for post-retrieval planning only — never
        /// rendered on the on-device branch — so the planner can judge evidence
        /// sufficiency instead of seeing zero chunks and abstaining.
        sourceChunks: [RetrievedChunk]
    ) async throws -> String {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // The Fact Bank is already compressed to ~1500 chars
        let factContext = factBank.asContext()

        // Take only 2 most recent insights (freshest context), capped at 300 chars each
        let freshInsights = recentInsights.suffix(2).map { String($0.prefix(300)) }
        let freshContext = freshInsights.isEmpty ? "" : "RECENT:\n" + freshInsights.joined(separator: "\n")

        // Previous answer summary - just key structure
        let prevSummary = previousAnswer.isEmpty ? "" : "PRIOR:\n\(String(previousAnswer.prefix(400)))...\n\n"

        let prompt = """
        Q: \(query)

        \(factContext)

        \(freshContext)

        \(prevSummary)Synthesize into a coherent answer. Preserve all facts, numbers, and citations.
        If the question was vague, interpret it based on the facts gathered.
        """

        let response = try await ragService.generateWithProperConsent(
            prompt: prompt,
            context: "",
            systemPrompt: "Synthesize facts into clear answers. Preserve all data. Only include facts from the documents. Never fabricate statistics or research claims. Reply in plain prose only — never JSON, key-value pairs, or field names.",
            maxTokens: 1000,
            disableTools: true,
            sourceChunks: sourceChunks,
            // Runs inside the session loop, so it stays local for the same reason the
            // sessions do: escalating every intermediate pass would turn one query
            // into dozens of cloud round-trips. Final synthesis is where PCC belongs.
            forceOnDevice: true
        )

        return cleanupFinalAnswer(response.text, isFinalAnswer: false)
    }

    /// Final synthesis of unlimited reasoning - SINGLE PASS with optional refinement
    /// Replaces the old multi-pass concatenation approach that caused massive duplication.
    /// Uses FactBank as the single source of truth — one comprehensive synthesis, then
    /// an optional REPLACEMENT refinement pass (never concatenation).
    private func synthesizeFinalUnlimitedAnswer(
        query: String,
        factBank: FactBank,
        allInsights: [String],
        currentAnswer: String,
        /// The live retrieved pool, for post-retrieval planning. This is the final
        /// synthesis, so unlike the session loop it is deliberately *not* pinned
        /// on-device -- this is the point where escalation is warranted.
        sourceChunks: [RetrievedChunk]
    ) async throws -> String {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SINGLE-PASS SYNTHESIS — one comprehensive answer from FactBank
        // No concatenation. Optional refinement REPLACES, never appends.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let factContext = factBank.asContext() // Already compressed to ~1500 chars

        // Gather supplementary context from recent insights (non-overlapping with FactBank)
        let supplementary: String
        if allInsights.count > 3 {
            // Fit the supplementary block into whatever the window has left after the
            // fact bank, the fixed instruction text, and the reserved output.
            //
            // This block was originally suffix(3) × prefix(300), which starved the
            // synthesizer on a 50-session run. Widening it without checking the budget
            // made things worse, not better: a device trace then showed a ~3506-token
            // prompt requesting 1500 output tokens against a 4096-token on-device
            // window. 5006 into 4096 does not go — the model was left almost no room
            // and emitted five tokens, a 48-character answer after 22,292 tokens of
            // reasoning. Size the input to the window instead of assuming it fits.
            let perInsight = allInsights.count > 20 ? 220 : 320
            let maxKeep = min(8, max(3, allInsights.count / 4))
            let recent = allInsights.suffix(maxKeep).map { String($0.prefix(perInsight)) }
            let header = "\n\nSUPPLEMENTARY FINDINGS:\n"
            let joined = recent.joined(separator: "\n")

            let remaining = supplementaryCharBudget(
                factContextChars: factContext.count,
                queryChars: query.count
            )
            if remaining <= header.count + 80 {
                supplementary = ""
                Log.info(
                    "[Synthesis] Supplementary findings dropped — no context budget left "
                        + "(fact bank \(factContext.count) chars)",
                    category: .llm
                )
            } else if joined.count + header.count > remaining {
                let fitted = truncateAtSentenceBoundary(joined, limit: remaining - header.count)
                supplementary = header + fitted
                Log.info(
                    "[Synthesis] Supplementary findings trimmed to fit context: "
                        + "\(joined.count) → \(fitted.count) chars",
                    category: .llm
                )
            } else {
                supplementary = header + joined
            }
        } else {
            supplementary = ""
        }

        Log.info("[Synthesis] Single-pass synthesis with Fact Bank (\(factBank.summary)), \(allInsights.count) insights", category: .llm)

        // ── PASS 1: Comprehensive answer from ALL evidence ──
        let synthesisPrompt = """
        Q: \(query)

        DOCUMENT FINDINGS:
        \(factContext)\(supplementary)

        Write a thorough answer using ONLY the document findings above:
        - Include ALL specific values, numbers, names, and details from the findings
        - Use **bold** sparingly for key terms only — do NOT bold every noun or defined term
        - Organize by topic/theme with clear headings
        - Include practical details, caveats, or limitations ONLY if mentioned in the findings
        - Do NOT invent facts, statistics, or research claims not in the findings
        - Do NOT add "research perspective" or "future research" sections
        - Every statement must trace back to the document findings
        - Carry through the [S1], [S2] markers attached to each claim above. Cite only
          markers that appear in the findings; never invent one.
        - Preserve any uncertainty the findings express. If a finding questions a term
          or notes a possible source error, keep that qualification.
        Never repeat the same information twice.
        """

        // A throw here discards everything the run produced: up to 50 sessions and,
        // on one device trace, 26 minutes of work. `currentAnswer` is the running
        // synthesis the loop maintained along the way, so it is a real answer rather
        // than a placeholder. Degrade to it instead of failing the query outright.
        let coreResponse: LLMResponse
        do {
            coreResponse = try await ragService.generateWithProperConsent(
            prompt: synthesisPrompt,
            context: "",
            systemPrompt: "Document analyst. Answer using ONLY the provided findings. Never fabricate facts or statistics. Use **bold** sparingly for key terms only. Never repeat content. Reply in plain prose only — never JSON, key-value pairs, or field names.",
            maxTokens: 1500,
            disableTools: true,
            sourceChunks: sourceChunks
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let fallback = cleanupFinalAnswer(currentAnswer).trimmingCharacters(in: .whitespacesAndNewlines)
            Log.warning(
                "[Unlimited] Final synthesis threw (\(type(of: error))); "
                    + "returning the accumulated running answer (\(fallback.count) chars)",
                category: .llm
            )
            if !fallback.isEmpty { return fallback }
            throw error
        }
        var finalAnswer = cleanupFinalAnswer(coreResponse.text)

        // ── PASS 2: Refinement (REPLACES, never appends) — only if sufficient evidence ──
        // This pass checks for missing facts and removes duplication.
        // Only triggers when we have substantial evidence (8+ insights) AND the answer is long enough
        // that it might have missed something or contain repetition.
        if allInsights.count > 8 && finalAnswer.count > 800 {
            let refinementPrompt = """
            Q: \(query)

            FACT BANK (all known facts):
            \(factContext)

            DRAFT ANSWER:
            \(String(finalAnswer.prefix(1800)))

            Improve this draft:
            1. Add any facts from the FACT BANK that are missing from the draft
            2. Remove any duplicated or repeated content
            3. Remove any claims not supported by the FACT BANK
            4. Keep the same structure and formatting
            Return the improved complete answer.
            """

            // This pass is optional by design -- it only replaces the answer when it
            // comes back substantial. A throw should therefore cost nothing at all,
            // rather than discarding a core synthesis that already succeeded.
            let refinedResponse = try? await ragService.generateWithProperConsent(
                prompt: refinementPrompt,
                context: "",
                systemPrompt: "Editor. Only include facts from the FACT BANK. Remove repetition. Remove unsupported claims. Reply in plain prose only — never JSON, key-value pairs, or field names.",
                maxTokens: 1500,
                disableTools: true,
                sourceChunks: sourceChunks
            )
            let refined = cleanupFinalAnswer(refinedResponse?.text ?? "")

            // Only use refinement if it's substantial (not a truncated mess)
            if refined.count > finalAnswer.count / 2 {
                finalAnswer = refined  // REPLACE, never append
            }
        }

        // ── Final cross-pass deduplication ──
        finalAnswer = deduplicateSynthesizedAnswer(finalAnswer)

        Log.info("[Synthesis] Final answer: \(finalAnswer.count) chars from \(allInsights.count) insights", category: .llm)

        return finalAnswer
    }

    // MARK: - Multi-Chain Execution (kept for compatibility)

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

        // Track progressive confidence for UI - use atomic counter for thread safety
        let completedSessions = OSAllocatedUnfairLock(initialState: 0)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Cluster documents by source
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let rawDocumentClusters = clusterChunksByDocument(
            chunks: allChunks,
            maxClusters: config.maxClusters,
            minDocsPerCluster: config.minDocsPerCluster
        )

        // Clamp to a hard limit of 8 clusters
        let documentClusters = Array(rawDocumentClusters.prefix(8))

        // Clamp total sessions to 30 max, adjusting sessions per cluster if necessary
        let maxAllowedSessions = 30
        let sessionsPerCluster = max(1, min(config.sessionsPerCluster, maxAllowedSessions / max(1, documentClusters.count)))
        let totalExpectedSessions = documentClusters.count * sessionsPerCluster

        Log.info("[MultiChain] Created \(documentClusters.count) document clusters from \(allChunks.count) chunks (clamped to 8 clusters, \(sessionsPerCluster) sessions/cluster, max 30 total)", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Run parallel reasoning chains per cluster
        // Use TaskGroup for controlled parallelism
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Process clusters in batches to avoid thermal throttling
        let batchSize = config.maxParallelChains

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
                                sessionsPerCluster: sessionsPerCluster,
                                onStep: { step in
                                    // Increment session counter and recalculate confidence
                                    let currentSession = completedSessions.withLock { count -> Int in
                                        count += 1
                                        return count
                                    }

                                    // Calculate confidence based on total session progress (up to 85%)
                                    // Synthesis adds the final 15%
                                    let sessionProgress = Float(currentSession) / Float(totalExpectedSessions)
                                    let calculatedConfidence = min(0.85, 0.05 + sessionProgress * 0.80)

                                    // Create step with recalculated confidence
                                    let progressStep = ThinkingStep(
                                        id: step.id,
                                        type: step.type,
                                        input: step.input,
                                        output: step.output,
                                        tokensUsed: step.tokensUsed,
                                        duration: step.duration,
                                        timestamp: step.timestamp,
                                        confidence: calculatedConfidence
                                    )
                                    await onStep?(progressStep)
                                }
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
            // Collect successful cluster results (confidence already reported per-session)
            for (_, insight) in batchResults {
                if let insight = insight {
                    clusterInsights.append(insight)
                    totalTokens += insight.tokensUsed
                }
            }
        }

        Log.info("[MultiChain] Completed \(clusterInsights.count) cluster chains, \(totalTokens) tokens", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Final synthesis across all cluster insights
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let synthesisStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Cross-cluster synthesis",
            output: "Integrating findings from \(clusterInsights.count) research clusters...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: 0.88 // All sessions done, now synthesizing
        )
        await onStep?(synthesisStep)

        let finalAnswer = try await synthesizeClusterInsights(
            query: query,
            clusterInsights: clusterInsights,
            synthesisSessions: config.synthesisSessions,
            sourceChunks: allChunks
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

        let profiles = docToChunks.map { documentName, chunks in
            buildSemanticProfile(documentName: documentName, chunks: chunks)
        }.sorted { lhs, rhs in
            lhs.totalScore > rhs.totalScore
        }

        guard !profiles.isEmpty else { return [] }

        let numClusters = min(maxClusters, max(1, Int(ceil(Double(profiles.count) / Double(max(1, minDocsPerCluster))))))
        var clusterProfiles: [[DocumentSemanticProfile]] = Array(repeating: [], count: numClusters)
        var clusterTerms: [[String: Int]] = Array(repeating: [:], count: numClusters)

        for (index, profile) in profiles.prefix(numClusters).enumerated() {
            clusterProfiles[index].append(profile)
            clusterTerms[index] = profile.weightedTerms
        }

        for profile in profiles.dropFirst(numClusters) {
            var bestIndex = 0
            var bestScore = -Float.infinity

            for index in 0..<numClusters {
                let score = semanticClusterScore(
                    profile: profile,
                    clusterTerms: clusterTerms[index],
                    clusterSize: clusterProfiles[index].count
                )
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            clusterProfiles[bestIndex].append(profile)
            clusterTerms[bestIndex] = mergedTermWeights(clusterTerms[bestIndex], with: profile.weightedTerms)
        }

        return clusterProfiles.enumerated().compactMap { index, profilesInCluster in
            guard !profilesInCluster.isEmpty else { return nil }
            let clusterChunks = profilesInCluster
                .flatMap(\ .chunks)
                .sorted { $0.similarityScore > $1.similarityScore }

            return DocumentCluster(
                name: semanticClusterName(index: index, terms: clusterTerms[index]),
                documents: profilesInCluster.map(\ .documentName),
                chunks: clusterChunks
            )
        }
    }

    private func buildSemanticProfile(
        documentName: String,
        chunks: [RetrievedChunk]
    ) -> DocumentSemanticProfile {
        var weightedTerms: [String: Int] = [:]

        for term in semanticTerms(from: documentName, minimumLength: 3, limit: 6) {
            weightedTerms[term, default: 0] += 2
        }

        for chunk in chunks {
            for term in chunk.chunk.metadata.keywords.map({ $0.lowercased() }) where term.count > 2 {
                weightedTerms[term, default: 0] += 3
            }
            for term in chunk.chunk.metadata.entities.map({ $0.lowercased() }) where term.count > 2 {
                weightedTerms[term, default: 0] += 3
            }
            if let sectionTitle = chunk.chunk.metadata.sectionTitle {
                for term in semanticTerms(from: sectionTitle, minimumLength: 3, limit: 5) {
                    weightedTerms[term, default: 0] += 2
                }
            }
            if let sectionPath = chunk.chunk.metadata.sectionPath {
                for term in sectionPath.flatMap({ semanticTerms(from: $0, minimumLength: 3, limit: 4) }) {
                    weightedTerms[term, default: 0] += 2
                }
            }
            if let structureType = chunk.chunk.metadata.structureType?.lowercased(), structureType.count > 2 {
                weightedTerms[structureType, default: 0] += 2
            }

            let content = chunk.chunk.parentContent ?? chunk.chunk.content
            for term in semanticTerms(from: content, minimumLength: 4, limit: 18) {
                weightedTerms[term, default: 0] += 1
            }
        }

        let totalScore = chunks.reduce(0) { $0 + $1.similarityScore }

        return DocumentSemanticProfile(
            documentName: documentName,
            chunks: chunks,
            totalScore: totalScore,
            weightedTerms: weightedTerms
        )
    }

    private func semanticTerms(
        from text: String,
        minimumLength: Int,
        limit: Int
    ) -> [String] {
        Array(
            Set(
                text.lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count >= minimumLength && !Self.commonStopWords.contains($0) }
            )
            .prefix(limit)
        )
    }

    private func semanticClusterScore(
        profile: DocumentSemanticProfile,
        clusterTerms: [String: Int],
        clusterSize: Int
    ) -> Float {
        guard !clusterTerms.isEmpty else { return profile.totalScore }

        let sharedTerms = Set(profile.weightedTerms.keys).intersection(clusterTerms.keys)
        let overlapWeight = sharedTerms.reduce(0) { partial, term in
            partial + min(profile.weightedTerms[term] ?? 0, clusterTerms[term] ?? 0)
        }

        let unionTerms = Set(profile.weightedTerms.keys).union(clusterTerms.keys)
        let unionWeight = unionTerms.reduce(0) { partial, term in
            partial + max(profile.weightedTerms[term] ?? 0, clusterTerms[term] ?? 0)
        }

        let semanticSimilarity = unionWeight == 0 ? 0 : Float(overlapWeight) / Float(unionWeight)
        let relevanceBonus = min(profile.totalScore / 10.0, 0.25)
        let sizePenalty = Float(max(0, clusterSize - 1)) * 0.03
        return semanticSimilarity + relevanceBonus - sizePenalty
    }

    private func mergedTermWeights(
        _ lhs: [String: Int],
        with rhs: [String: Int]
    ) -> [String: Int] {
        rhs.reduce(into: lhs) { partial, entry in
            partial[entry.key, default: 0] += entry.value
        }
    }

    private func semanticClusterName(index: Int, terms: [String: Int]) -> String {
        let topTerms = terms
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\ .key)
            .prefix(2)

        guard !topTerms.isEmpty else {
            return "Semantic Cluster \(index + 1)"
        }

        return "Semantic Cluster \(index + 1): \(topTerms.joined(separator: " / "))"
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

        // Run the reasoning chain for this cluster - force confidence reporting for Maximum mode
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
            },
            forceConfidenceReporting: true // Multi-chain = Maximum mode, always report confidence
        )

        let docNames = Array(Set(chunks.map { $0.sourceDocument }))

        // Clean up the cluster insight before storing
        let cleanedInsight = cleanupFinalAnswer(chainResult.finalAnswer)

        return MultiChainResult.ClusterInsight(
            clusterName: clusterName,
            documents: docNames,
            insight: cleanedInsight,
            chainInsights: chainResult.chainInsights.map { cleanupFinalAnswer($0, isFinalAnswer: false) },
            tokensUsed: chainResult.totalTokens,
            sessionsRun: chainResult.sessionCount
        )
    }

    /// Synthesize insights from all clusters into final answer
    private func synthesizeClusterInsights(
        query: String,
        clusterInsights: [MultiChainResult.ClusterInsight],
        synthesisSessions: Int,
        /// The retrieved pool, for post-retrieval planning. Without it the planner
        /// judges this synthesis to have zero evidence and abstains, regardless of
        /// how much the clusters actually found.
        sourceChunks: [RetrievedChunk]
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

        // Truncate if needed to fit in context (leave room for enhanced prompt + output)
        // Enhanced system prompt is ~640 tokens, synthesis prompt header ~200 tokens
        // Output reserve: 1500 tokens, safety: 100 tokens
        // Available for content: 4096 - 640 - 200 - 1500 - 100 = 1656 tokens ≈ 2300 chars
        // But Maximum mode chains multiple sessions, so first session can be tighter
        let maxChars = 4500 // ~3200 tokens - first session uses more, refinements use less
        if synthesisInput.count > maxChars {
            synthesisInput = String(synthesisInput.prefix(maxChars)) + "\n[...truncated for synthesis]"
        }

        let synthesisPrompt = """
        \(synthesisInput)

        TASK: Synthesize ALL findings into ONE comprehensive answer.
        Integrate across clusters. Include specific values and data. Use **bold** sparingly for key terms only.
        Never repeat content. Cite [S1], [S2].

        SYNTHESIS:
        """

        let systemPrompt = """
        Synthesize document findings. Include ALL specific values, numbers, and data points.
        Cross-reference multiple sources. Never repeat content. Use **bold** sparingly for key terms only.
        Cite as [S1], [S2]. Write like a domain expert — format naturally for the content.
        """

        var totalTokens = 0
        var finalAnswer = ""

        // Run synthesis sessions - each session REFINES the previous, not concatenates
        for sessionIdx in 0 ..< synthesisSessions {
            let isLast = sessionIdx == synthesisSessions - 1
            let prompt = sessionIdx == 0 ? synthesisPrompt : """
            Your previous synthesis attempt:
            \(String(finalAnswer.prefix(3000)))

            IMPROVE THIS SYNTHESIS by:
            - Removing redundant/repeated content
            - Improving paragraph flow and transitions
            - Adding any missing details from the original findings
            - Making it more coherent and readable

            Produce a CLEAN, REFINED version (not additions - a complete rewrite):
            """

            let response = try await ragService.generateWithProperConsent(
                prompt: prompt,
                context: "",
                systemPrompt: systemPrompt,
                maxTokens: isLast ? 1500 : 1000,
                disableTools: true,
                sourceChunks: sourceChunks
            )

            // Each session REPLACES the previous answer (refinement, not concatenation)
            finalAnswer = response.text
            totalTokens += response.tokensGenerated
        }

        // Final cleanup - remove any remaining raw markers
        finalAnswer = cleanupFinalAnswer(finalAnswer)

        return (finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines), totalTokens)
    }

    /// Gather ALL relevant chunks from the library for comprehensive multi-chain analysis
    /// This retrieves more chunks than the initial search to enable thorough cluster analysis
    private func gatherAllRelevantChunks(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> [RetrievedChunk] {
        Log.info("[MultiChain] Gathering comprehensive chunks for multi-chain analysis", category: .retrieval)

        await onDetailedEvent?(.agentic, "Maximum mode", "Gathering comprehensive evidence")

        // Start with initial chunks
        var allChunks = initialChunks

        // Get broader retrieval - up to 50 chunks for comprehensive coverage
        await onDetailedEvent?(.retrieval, "Broad search", "Expanding to 50 top chunks")
        let broadChunks = try await ragService.executeFullRetrievalPipeline(
            query: query,
            topK: 50,
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .coverageExpansion),
            qualityMode: qualityMode,
            onDetailedEvent: onDetailedEvent
        )

        // Merge unique chunks
        for chunk in broadChunks {
            if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                allChunks.append(chunk)
            }
        }

        await onDetailedEvent?(.retrieval, "After broad search", "\(allChunks.count) unique chunks")

        // Also try some query variations to catch different aspects
        let queryVariations = generateQueryVariations(query: query)
        for (idx, variation) in queryVariations.prefix(3).enumerated() { // Limit to 3 variations
            await onDetailedEvent?(.retrieval, "Variation \(idx + 1)/3", "\"\(variation.prefix(30))...\"")
            let variantChunks = try await ragService.executeFullRetrievalPipeline(
                query: variation,
                topK: 20,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .queryVariation),
                qualityMode: qualityMode,
                onDetailedEvent: onDetailedEvent
            )
            for chunk in variantChunks {
                if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allChunks.append(chunk)
                }
            }
        }

        await onDetailedEvent?(.retrieval, "Gathering complete", "\(allChunks.count) chunks for analysis")

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

    /// Generate EXPANSION queries based on what FactBank has learned
    /// Uses unanswered sub-questions for GAP-AWARE retrieval
    /// This enables truly unlimited retrieval - we discover new search directions
    private func generateExpansionQueries(
        originalQuery: String,
        factBank: FactBank
    ) -> [String] {
        var queries: [String] = []

        // PRIORITY 1: Use unanswered sub-questions directly
        // These are the GAPS we haven't filled yet
        for unanswered in factBank.unansweredQuestions.prefix(3) {
            // Combine original query topic with the gap
            let queryCore = originalQuery.split(separator: " ").suffix(4).joined(separator: " ")
            queries.append("\(queryCore) \(unanswered)")
        }

        // PRIORITY 2: Extract new entities from accumulated facts
        let factText = factBank.coreFacts.joined(separator: " ")
        let words = factText.lowercased().split(separator: " ").map(String.init)
        let factWords = Set(words.filter { $0.count > 4 })

        // Find NEW terms that appeared in facts but not original query
        let originalTerms = Set(originalQuery.lowercased().split(separator: " ").map(String.init))
        let newTerms = factWords.subtracting(originalTerms)
            .filter { term in
                !["about", "which", "these", "there", "their", "would", "could", "should", "found", "showed"].contains(term)
            }

        // Build expansion queries from new terms (only if we have room)
        if queries.count < 4 {
            let topNewTerms = Array(newTerms.prefix(3))
            let originalCore = originalQuery.split(separator: " ").prefix(4).joined(separator: " ")
            for term in topNewTerms.prefix(4 - queries.count) {
                queries.append("\(originalCore) \(term)")
            }
        }

        // PRIORITY 3: Gap-filling queries for research completeness
        if queries.count < 5 {
            let gapPatterns = [
                "limitations of",
                "conflicting evidence",
                "alternative view"
            ]
            let queryCore = originalQuery.split(separator: " ").suffix(3).joined(separator: " ")
            for pattern in gapPatterns.prefix(5 - queries.count) {
                queries.append("\(pattern) \(queryCore)")
            }
        }

        Log.info("[Expansion] Generated \(queries.count) queries: \(factBank.unansweredQuestions.count) gaps + new terms", category: .llm)
        return queries
    }

    /// Build prompt for a specific position in the reasoning chain.
    /// CRITICAL: The prompt INCLUDES the context (DOCUMENTS section).
    /// Do NOT pass context separately to generateWithProperConsent — that would double it.
    ///
    /// Token budget (4096 total):
    ///   System prompt: ~80 tokens
    ///   LLMService wrapper: ~30 tokens
    ///   Output (maxTokens): 500 tokens
    ///   Available for prompt: ~3486 tokens ≈ 4880 chars
    ///   Session 1 (no insights): context ≤ 4000 chars, prompt text ~300 chars
    ///   Session 2+ (with insights): context ≤ 2000 chars + insights ≤ 1500 chars + prompt ~300 chars
    private func buildChainPrompt(
        sessionIndex: Int,
        sessionCount: Int,
        query: String,
        context: String,
        previousInsights: [String],
        maxInsightLength: Int,
        sessionObjective: String? = nil
    ) -> (prompt: String, systemPrompt: String) {
        // FIXED: Reduced insight budget from 2500 to 1200 chars.
        // With context doubling fix, real budget is:
        //   4096 tokens - 80 (system) - 30 (wrapper) - 500 (output) = 3486 tokens ≈ 4880 chars
        //   Session 1: 4000 chars context + 300 prompt = 4300 (fits)
        //   Session 2+: 2200 context + 1200 insights + 300 prompt = 3700 (fits)
        let maxInsightSummaryChars = 1200

        let insightSummary: String
        if previousInsights.isEmpty {
            insightSummary = ""
        } else {
            // For sessions with insights, provide a CONCISE summary of findings so far.
            // Don't dump the full text — just the key answer and supporting details.
            let rawSummary = "PRIOR FINDINGS:\n" + previousInsights.enumerated()
                .map { "[\($0.offset + 1)] \(truncateAtSentenceBoundary($0.element, limit: 400))" }
                .joined(separator: "\n")

            if rawSummary.count > maxInsightSummaryChars {
                insightSummary = truncateAtSentenceBoundary(rawSummary, limit: maxInsightSummaryChars)
                Log.debug("[ReasoningChain] Truncated insight summary from \(rawSummary.count) to \(maxInsightSummaryChars) chars", category: .llm)
            } else {
                insightSummary = rawSummary
            }
        }

        let objectiveBlock = sessionObjective.map { """
        SESSION OBJECTIVE:
        \($0)

        """ } ?? ""

        // Context budget: session 1 gets full context, later sessions share with insights
        let contextForPrompt = previousInsights.isEmpty
            ? String(context.prefix(4000))
            : String(context.prefix(2200))

        switch sessionIndex {
        case 0:
            // SESSION 1: Extract ALL relevant information from documents
            // CRITICAL: Don't say "find THE answer" — questions can have multiple parts.
            // "What does pressing the button do?" might have 5+ answers (record, stop, connect, reset, etc.)
            let systemPrompt = "You are a document analysis assistant. Extract all relevant information from the provided documents in clear, detailed prose. Write in complete sentences and natural paragraphs."
            let prompt = """
            QUESTION: \(query)

            \(objectiveBlock)DOCUMENTS:
            \(contextForPrompt)

            Write a detailed answer using the information found in these documents.
            Include every relevant detail, value, specification, and procedure.
            Write in complete sentences and natural paragraphs — not just bullet points.
            Use bullet points only for actual lists of items (like steps or specifications).
            Cite sources as [S1], [S2].
            """
            return (prompt, systemPrompt)

        case 1:
            // SESSION 2: Add NEW details not yet covered
            let systemPrompt = "You are a document analyst. Write ONLY new details from these documents. Never restate prior findings."
            let prompt = """
            QUESTION: \(query)

            \(insightSummary)
            \(objectiveBlock)ADDITIONAL DOCUMENTS:
            \(contextForPrompt)

            Using these additional documents, write ONLY new details about: "\(query)"
            Do NOT repeat or rephrase anything from prior findings above.
            Focus exclusively on details, values, or procedures NOT already covered.
            Write in complete sentences and full paragraphs. Cite as [S1], [S2].
            """
            return (prompt, systemPrompt)

        case sessionCount - 1:
            // FINAL SESSION: Clean synthesis of ALL accumulated findings
            let systemPrompt = "Combine all research findings into one comprehensive, well-written answer. Write in detailed prose with complete sentences and natural paragraphs. Use ### headers to organize sections. Use **bold** sparingly for key terms only."
            let prompt = """
            QUESTION: \(query)

            \(insightSummary)
            \(objectiveBlock)DOCUMENTS:
            \(contextForPrompt)

            Write a comprehensive answer to: "\(query)"
            Combine ALL findings into detailed, flowing prose.
            Use ### section headers to organize topics. Use **bold** sparingly for key terms only.
            Write in complete sentences and full paragraphs — not just bullet lists.
            Use bullet points only for actual sequential steps or specification lists.
            Include every relevant detail found. Cite as [S1], [S2].
            """
            return (prompt, systemPrompt)

        default:
            // MIDDLE SESSIONS: Enrich and expand on prior findings with new document evidence
            // CRITICAL: Frame as ENRICHMENT, not just "find new stuff".
            // Apple FM tends to give up and say "No new information" when asked only for novelty.
            // Instead, ask it to ADD DEPTH and DETAIL using the new documents as evidence.
            // But also explicitly tell it NOT to repeat prior findings verbatim to avoid dedup waste.
            // Phrasing note: an earlier version asked for "NEW details", and the
            // on-device model answered with `{ "document_analysis": { "new_details":
            // [ ... ` — inventing a schema whose key mirrored the instruction. The
            // wording below avoids naming a field, and the output format is stated
            // outright rather than implied.
            let systemPrompt = "You are a document analyst. Describe what these documents add beyond the prior findings. Do not repeat what was already found. Reply with plain prose only — never JSON, key-value pairs, or tool-call syntax."
            let prompt = """
            QUESTION: \(query)

            \(insightSummary)
            \(objectiveBlock)ADDITIONAL DOCUMENTS:
            \(contextForPrompt)

            Using these additional documents, describe what they add about: "\(query)"
            Write details, values, procedures, or context from these documents that are NOT already in prior findings.
            Do NOT repeat or rephrase information already covered above.
            If the documents contain relevant details not yet mentioned, describe them thoroughly.
            Write in complete sentences and full paragraphs, as plain prose.
            Do not reply with JSON, field names, or any structured format. Cite as [S1], [S2].
            """
            return (prompt, systemPrompt)
        }
    }

    private func buildSessionObjective(
        query: String,
        factBank: FactBank,
        sessionIndex: Int,
        sessionCount: Int
    ) -> String? {
        guard sessionIndex > 0 else { return nil }

        let unanswered = Array(factBank.unansweredQuestions.prefix(3))

        if sessionIndex == sessionCount - 1 {
            if unanswered.isEmpty {
                return "Synthesize only what is supported by the accumulated evidence. If any detail is still weakly supported, qualify it instead of guessing."
            }

            return "Before final synthesis, verify whether these remaining gaps are actually answered: \(unanswered.joined(separator: "; ")). If not, state that the documents do not fully resolve them instead of inferring beyond the evidence."
        }

        if unanswered.isEmpty {
            return "Pressure-test the current answer. Look for contradictions, missing qualifiers, numeric details, edge cases, and source-backed caveats instead of repeating the same summary."
        }

        return "Prioritize coverage for these unresolved sub-questions: \(unanswered.joined(separator: "; ")). Surface contradictions or missing evidence explicitly instead of repeating prior findings."
    }

    /// Extract insight from response - keep FULL content, just clean up formatting
    /// We want ALL the details the model found, not truncated snippets!
    private func extractInsight(from text: String, maxLength: Int) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up common LLM artifacts and markers (including truncated versions)
        let markersToRemove = [
            "REASONING:", "ONING:", "ASONING:", "SONING:", // Truncated REASONING
            "INSIGHT:", "NSIGHT:", "SIGHT:", // Truncated INSIGHT
            "ANALYSIS:", "OBSERVATION:", "CONCLUSION:",
            "Re Reasoning:", "Re REASONING:",
            "[new details found]", "[additional specifics]",
        ]

        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

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

        // Clean up again after extraction
        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // Remove empty lines and normalize whitespace
        result = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

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

    /// Deduplicate a synthesized answer by removing repeated paragraphs/sections
    /// This catches cross-pass duplication that per-LLM-call dedup can't see.
    private func deduplicateSynthesizedAnswer(_ text: String) -> String {
        // Split into paragraphs (sections separated by blank lines)
        let paragraphs = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard paragraphs.count > 1 else { return text }

        var kept: [String] = []
        var seenFingerprints: Set<String> = []

        for paragraph in paragraphs {
            // Create a fingerprint: lowercased, stripped of formatting, first 120 chars
            let stripped = paragraph
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let fingerprint = String(stripped.prefix(120))

            // Check for near-duplicate: if >70% of fingerprint matches any seen
            var isDuplicate = false
            if seenFingerprints.contains(fingerprint) {
                isDuplicate = true
            } else {
                // Check fuzzy match — paragraphs that start the same way
                for seen in seenFingerprints {
                    let shorter = min(fingerprint.count, seen.count)
                    guard shorter > 40 else { continue }
                    let prefix1 = String(fingerprint.prefix(shorter))
                    let prefix2 = String(seen.prefix(shorter))
                    if prefix1 == prefix2 {
                        isDuplicate = true
                        break
                    }
                }
            }

            if !isDuplicate {
                kept.append(paragraph)
                seenFingerprints.insert(fingerprint)
            } else {
                Log.debug("[Synthesis] Removed duplicate paragraph: \(String(paragraph.prefix(80)))...", category: .llm)
            }
        }

        // Safety: if we removed more than 60%, keep the original
        if kept.count < paragraphs.count * 2 / 5 {
            Log.info("[Synthesis] Dedup would remove \(paragraphs.count - kept.count)/\(paragraphs.count) paragraphs — aborting", category: .llm)
            return text
        }

        return kept.joined(separator: "\n\n")
    }

    /// Characters still available for the supplementary findings block.
    ///
    /// Budgeted against the **on-device** window even when synthesis may escalate to
    /// PCC. Under-using a 32K window costs nothing; over-filling a 4096 one costs the
    /// entire answer, and an On-Device selection makes the small window mandatory.
    private func supplementaryCharBudget(factContextChars: Int, queryChars: Int) -> Int {
        let window = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let outputReserveTokens = 1500          // maxTokens requested for the answer
        let serviceOverheadTokens = 200         // system prompt + LLMService wrapper
        let instructionChars = 900              // the fixed instruction text below the findings

        let inputTokens = max(0, window - outputReserveTokens - serviceOverheadTokens)
        let inputChars = Int(Double(inputTokens) * Double(FoundationModelTokenBudget.onDeviceCharsPerToken))
        return max(0, inputChars - factContextChars - queryChars - instructionChars)
    }

    /// True when a session produced text that cannot serve as a reasoning insight.
    ///
    /// Shared by both reasoning loops on purpose. This check previously existed only
    /// in `executeReasoningChain`, so Maximum's loop — which tested nothing beyond
    /// `tokensGenerated == 0` — happily stored non-answers as findings.
    ///
    /// The request-for-input cases are the ones worth naming. A device run recorded
    /// sessions 16 and 17 as *"I need additional context to determine what specific
    /// controls or mechanisms are mentioned... Please provide"* and *"Could you
    /// please"*. There is no human in this loop to answer. The model has slipped into
    /// conversational mode, and its question then enters the fact bank as a finding.
    private func isUnusableInsight(_ insight: String) -> Bool {
        let text = insight.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.count < 30 { return true }

        // Nothing learned.
        let nonAnswers = [
            "no new information", "no new details", "no additional information",
            "i can't assist", "i cannot assist", "no relevant information",
        ]
        // Addressed to a user who is not there.
        let requestsForInput = [
            "please provide", "could you please", "can you provide",
            "i need additional context", "additional context is needed",
            "please share", "please specify", "let me know if",
        ]
        if nonAnswers.contains(where: { text.contains($0) }) { return true }
        if requestsForInput.contains(where: { text.contains($0) }) { return true }
        if text.hasPrefix("i'm sorry") || text.hasPrefix("i am sorry") { return true }
        return false
    }

    /// Truncate at the last sentence boundary at or before `limit`.
    ///
    /// A raw `String.prefix(limit)` cuts mid-sentence. In the reasoning chain that
    /// is not cosmetic: `buildChainPrompt` places PRIOR FINDINGS in the middle of
    /// the prompt, so a mid-sentence cut hands the model a prompt that stops in the
    /// middle of a thought and then resumes with `SESSION OBJECTIVE:`. Sessions 6-8
    /// of a real Deep Think run responded by completing the *prompt* rather than
    /// answering it, echoing those section headers back as their insight.
    private func truncateAtSentenceBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 0 else { return text }
        let head = String(text.prefix(limit))
        // Prefer a sentence end; fall back to a line break, then a word break, so a
        // findings block never ends mid-word.
        let terminators: [Character] = [".", "!", "?"]
        if let idx = head.lastIndex(where: { terminators.contains($0) }) {
            return String(head[...idx])
        }
        if let idx = head.lastIndex(of: "\n") {
            return String(head[..<idx])
        }
        if let idx = head.lastIndex(of: " ") {
            return String(head[..<idx])
        }
        return head
    }

    /// Strip prompt scaffolding and fabricated structured output out of a session insight.
    ///
    /// Across three device runs the on-device model repeatedly wrapped otherwise good
    /// analysis in a JSON envelope it never closed:
    ///
    ///     tool_call: {tool_name: "extract_new_details", arguments: {...}}
    ///     { "tool_call_status": "completed", "new_details_found": [ ...
    ///     { "document_analysis": { "new_details": [ "The two-tier context window ...
    ///
    /// No such tool or schema exists in this codebase, and tools are explicitly
    /// disabled for chain sessions (`disableToolsForSession = true`). The invented
    /// key names track the prompt's own wording — "add NEW details" produced
    /// `new_details` — so the phrasing was priming a structured response. The prompts
    /// now ask for prose explicitly; this is the safety net for when that is ignored.
    ///
    /// The prose inside those envelopes was on-topic and correctly cited every time,
    /// so salvage it rather than throwing away the session's work. Left unsanitized
    /// it also cascades: a contaminated insight becomes the next session's PRIOR
    /// FINDINGS and teaches the next model the same shape.
    private func stripPromptEchoAndToolNoise(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var strippedEnvelope = false

        // 0. Strip model-markup wrappers before anything else. Device runs showed
        //    eight of twelve Maximum sessions producing an insight that opened with
        //    one of these, and none were caught by the JSON-envelope rules below:
        //
        //      <think> I need to determine what controls impulse responses…
        //      <tool_call name="document_analyst"> { "documents": [ "[S1] mentions…
        //      ```json { "extracted_receptors": [ …
        //
        //    `<think>` is emitted *unclosed* (zero `</think>` across every captured
        //    log), so removing the tag and keeping the prose is right — the text
        //    after it is genuine reasoning. `<tool_call …>` payloads likewise carry
        //    real cited material, so drop only the tag and let the envelope rules
        //    below salvage what follows.
        for tag in ["</think>", "<think>", "</tool_call>", "```json", "```"] {
            result = result.replacingOccurrences(of: tag, with: " ")
        }
        if let toolTag = try? NSRegularExpression(pattern: "<tool_call\\b[^>]*>", options: [.caseInsensitive]) {
            result = toolTag.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Drop a leading tool-call blob, through its closing brace.
        let toolCallPrefixes = ["tool_call:", "tool call:", "{\"tool_call", "{ \"tool_call"]
        if let marker = toolCallPrefixes.first(where: { result.lowercased().hasPrefix($0) }) {
            _ = marker
            if let close = result.lastIndex(of: "}") {
                result = String(result[result.index(after: close)...])
            } else if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            strippedEnvelope = true
        }

        // 2. Drop a leading JSON key path such as `{ "document_analysis": { "new_details": [ "`.
        //    Matches nested `"key":` pairs and their opening braces/brackets, then the
        //    opening quote of the first string value, leaving the prose intact.
        let envelopePattern = "^[\\s\\{\\[]*(?:\"[A-Za-z_][A-Za-z0-9_ ]*\"\\s*:\\s*[\\s\\{\\[]*)+\"?"
        if let regex = try? NSRegularExpression(pattern: envelopePattern),
           let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
           match.range.length > 0,
           let range = Range(match.range, in: result) {
            result = String(result[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            strippedEnvelope = true
        }

        if strippedEnvelope {
            // Trailing closers the model did emit, and the stray quotes it used to
            // separate array elements mid-prose (`... [S3]. "The document specifies`).
            while let last = result.last, "\"]}".contains(last) {
                result = String(result.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result = result.replacingOccurrences(of: "\", \"", with: " ")
            result = result.replacingOccurrences(of: ". \"", with: ". ")
        }

        // 3. Cut at any echoed prompt section header. These strings are emitted only
        //    by `buildChainPrompt`; a model reproducing one is quoting its input.
        let promptMarkers = ["SESSION OBJECTIVE:", "ADDITIONAL DOCUMENTS:", "PRIOR FINDINGS:"]
        for marker in promptMarkers {
            if let range = result.range(of: marker) {
                result = String(result[..<range.lowerBound])
            }
        }

        // 4. Drop a conversational lead-in ("Got it, here's a detailed breakdown of…:")
        //    so it does not consume budget as a PRIOR FINDINGS prefix downstream.
        let preambleStarters = ["got it", "sure,", "sure!", "certainly", "of course", "absolutely", "here's", "here is"]
        if let firstLineEnd = result.firstIndex(where: { $0 == "\n" }) {
            let firstLine = String(result[..<firstLineEnd]).trimmingCharacters(in: .whitespaces)
            let lowered = firstLine.lowercased()
            if preambleStarters.contains(where: { lowered.hasPrefix($0) }), firstLine.count < 240 {
                result = String(result[result.index(after: firstLineEnd)...])
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean up final answer by removing raw LLM markers and artifacts
    /// - Parameter isFinalAnswer: when false, skip substitutions that replace the
    ///   text with user-facing help copy. Intermediate reasoning insights must stay
    ///   as the model wrote them: a session that honestly reports "I could not find
    ///   X in these documents" is making a correct observation the chain needs, and
    ///   swapping it for "This information may be in an image, diagram, or table…"
    ///   both destroys that observation and asserts a cause nobody established. A
    ///   device run showed exactly this at session 12, after which the help text
    ///   entered the fact bank as a finding.
    private func cleanupFinalAnswer(_ text: String, isFinalAnswer: Bool = true) -> String {
        // Strip fabricated structured output before anything else looks at the text.
        // This was previously applied only to intermediate reasoning-chain insights,
        // so final answers were unprotected — and a Maximum device run returned this
        // as its entire answer after 50 sessions, 20,182 tokens, and 26 minutes:
        //
        //     { "neurotransmitters_linked_to_actions": [ "neurotransmitter": "dopamine", …
        //
        // 268 characters of unclosed JSON, and `citations=0/0` because a JSON blob
        // carries no [S#] markers for the verifier to check. `cleanupFinalAnswer` has
        // sixteen call sites and covers every path that produces a user-visible
        // answer, so this is the right place for the guard rather than each caller.
        var result = stripPromptEchoAndToolNoise(from: text)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Handle "NOT FOUND" responses gracefully
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // A model that reports it could not find something has *answered*. That answer
        // is grounded in the documents, often carries citations, and is exactly the
        // behaviour this app promises. Replacing it with boilerplate destroys all of
        // that, and a device run showed the cost precisely:
        //
        //     [Synthesis] Final answer: 385 chars from 20 insights
        //     user received: 216 chars of template
        //
        // A real synthesis built from 20 insights and 11 claims was discarded for text
        // that asserted the information "may be in an image, diagram, or table" —
        // a cause nobody established, and wrong for a text-indexed corpus — and which
        // read "about about" because `extractQueryContext` returns a phrase already
        // beginning with "about".
        //
        // So: never replace. Append a short suggestion only when the model's own
        // answer is too thin to stand on its own, and say nothing about why the
        // information is missing, because that is not known.
        let upperText = result.uppercased()
        let reportsNotFound = upperText.contains("NOT FOUND IN DOCUMENTS")
            || upperText.contains("DOCUMENTS DO NOT CONTAIN")
            || upperText.contains("COULDN'T FIND")
            || upperText.contains("COULD NOT FIND")
            || upperText.contains("NO INFORMATION FOUND")
            || upperText.contains("NOT AVAILABLE IN")
        if isFinalAnswer, reportsNotFound, result.count < 160 {
            return result + "\n\nYou could try rephrasing the question, checking the original document directly, or adding a document that covers this topic."
        }

        // Handle refusal/ethics responses that snuck through
        let refusalPatterns = [
            "I'm sorry, but I can't continue with that request",
            "I'm here to provide helpful and informative content",
            "adhering to ethical guidelines",
            "If you have any other questions or need assistance",
        ]
        for pattern in refusalPatterns {
            if text.contains(pattern) {
                // Strip the refusal, keep any actual content
                result = result.replacingOccurrences(of: pattern, with: "")
            }
        }

        // Remove all reasoning/insight markers (including truncated versions and variations)
        let markersToRemove = [
            // Full markers
            "REASONING:", "INSIGHT:", "ANALYSIS:", "OBSERVATION:", "CONCLUSION:",
            "ADDITIONAL SPECIFIC DETAILS:", "ADDITIONAL INSIGHTS:", "NEW DETAILS:",
            "SUPPORTING DOCUMENTS:", "PROCEDURE:", "SPECIAL CASES:",
            "RESPONSIBILITIES AND TASKS:", "SPECIAL NOTES:",
            "YOUR COMPREHENSIVE ANSWER:", "COMPREHENSIVE ANSWER:",
            // Truncated markers (from generation cutoffs)
            "ONING:", "ASONING:", "SONING:", "NING:",
            "NSIGHT:", "SIGHT:", "IGHT:",
            "LYSIS:", "YSIS:", "SIS:",
            "Re Reasoning:", "*ONING:",
            // Prompt structure leakage
            "CONCLUSIONS:", "REFERENCES:", "ANSWER:",
            "conclusions:", "references:", "answer:",
            // Lowercased versions
            "reasons:", "reason:", "insight:", "new details:",
            // Meta markers
            "[new details found]", "[additional specifics]",
            "*(Generation stopped", "Please try again.)*",
            "*(Generation stopped. Something went wrong. Please try again.)*",
        ]

        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // NOTE: Markdown formatting (headers, lists, code fences) is now preserved
        // MarkdownText renders full block-level markdown as of v1.2

        // Remove lines that are just leaked prompt structure markers (single words like "Reasoning:" with no content)
        let promptLeakPatterns = [
            "reasoning", "insight", "analysis", "observation", "conclusion",
            "reasons", "new details", "additional", "procedure", "special cases",
            "executive summary", "key findings", "your comprehensive answer",
        ]
        result = result.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
                // Keep empty lines (they separate blocks)
                guard !trimmed.isEmpty else { return true }
                // Filter out lines that are JUST a leaked prompt marker (no real content)
                for pattern in promptLeakPatterns {
                    if trimmed == pattern || trimmed == pattern + ":" {
                        return false
                    }
                }
                return true
            }
            .joined(separator: "\n")

        // Collapse multiple blank lines into single
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Repair malformed URLs — fix spaces, encoding issues so links actually work
        result = repairMalformedURLs(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Repair malformed URLs in LLM output so links are tappable and correct.
    /// Fixes: spaces within URLs, missing percent-encoding, whitespace before TLDs.
    /// Preserves valid markdown links and bare URLs.
    private func repairMalformedURLs(_ text: String) -> String {
        var result = text

        // 1. Fix markdown links [text](broken url) — repair the URL portion
        if let markdownLinkRegex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\((https?://[^\)]*)\)"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = markdownLinkRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let labelRange = Range(match.range(at: 1), in: result),
                      let urlRange = Range(match.range(at: 2), in: result) else { continue }
                let label = String(result[labelRange])
                let rawURL = String(result[urlRange])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(fullRange, with: "[\(label)](\(fixed))")
            }
        }

        // 2. Fix bare URLs (not inside markdown link syntax)
        if let bareURLRegex = try? NSRegularExpression(
            pattern: #"(?<!\()https?://\S+"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = bareURLRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let rawURL = String(result[range])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(range, with: fixed)
            }
        }

        return result
    }

    /// Repair a single URL string: remove internal spaces, fix encoding.
    private static func repairURL(_ url: String) -> String {
        var fixed = url
        // Remove spaces (LLM inserts spaces like "github .com" or "blob/ main")
        fixed = fixed.replacingOccurrences(of: " ", with: "")
        // Remove trailing punctuation the LLM may have appended
        while fixed.hasSuffix(".") || fixed.hasSuffix(",") || fixed.hasSuffix(";") || fixed.hasSuffix(")") {
            fixed = String(fixed.dropLast())
        }
        return fixed
    }

    /// Extract what the user was asking about from a "not found" response
    /// Used to provide helpful feedback about what couldn't be found
    private func extractQueryContext(from text: String) -> String {
        // Common patterns where the topic might be mentioned
        let patterns = [
            #"(?:about|regarding|for|on)\s+(?:the\s+)?([^.!?\n]+)"#,
            #"(?:find|locate|search for)\s+(?:the\s+)?([^.!?\n]+)"#,
            #"(?:information|data|details)\s+(?:about|on|regarding)\s+([^.!?\n]+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let topicRange = Range(match.range(at: 1), in: text) {
                let topic = String(text[topicRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if topic.count > 3 && topic.count < 100 {
                    return topic
                }
            }
        }

        return ""
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
        let orchestrator = AgenticOrchestrator(ragService: self, config: .fast, qualityMode: .standard)
        let complexity = QueryComplexityAnalyzer.shared.analyze(query).complexity
        let reasoningConfig: ReasoningChainConfig = complexity == .simple ? .light : .standard
        let totalSessions = reasoningConfig.sessionCount

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
            config: reasoningConfig,
            onStep: onStep
        )
    }

    /// Generate with a fresh session (no accumulated context)
    /// Used by AgenticOrchestrator for each thinking step
    func generateWithFreshSession(prompt: String, maxTokens: Int) async throws -> LLMResponse {
        try Task.checkCancellation()
        #if canImport(FoundationModels)
            // Create a temporary AppleFoundationLLMService for isolated generation
            let tempService = AppleFoundationLLMService()

            // Ensure cleanup on exit
            defer {
                tempService.resetSession(clearTools: true)
            }

            var config = InferenceConfig(
                maxTokens: maxTokens,
                temperature: 0.7,
                systemPrompt: "You are an expert research analyst. Be concise and precise."
            )
            // Agentic planning and evidence analysis remain local. Only the
            // final post-retrieval synthesis may be selected for PCC.
            config.executionContext = .onDeviceOnly
            config.allowPrivateCloudCompute = false

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
        maxTokens: Int,
        disableTools: Bool = false,
        temperature: Float = 0.5,
        qualityMode: RAGQualityMode = .deepThink,
        sourceChunks: [RetrievedChunk] = [],
        forceOnDevice: Bool = false
    ) async throws -> LLMResponse {
        try Task.checkCancellation()
        var config = InferenceConfig(
            maxTokens: maxTokens,
            temperature: temperature, // Adaptive: higher for exploration, lower for synthesis
            systemPrompt: systemPrompt
        )
        // Tools disabled for Maximum mode sessions to prevent context overflow
        // The chunks are pre-gathered and passed directly in the prompt
        config.disableTools = disableTools
        config.qualityMode = qualityMode

        // The user's model-picker choice, captured for this query in
        // `executeAgenticQuery`. Carry it onto the config *before* planning, so
        // the planner's `allowsPCC` reflects what was actually selected. Without
        // this the fields below keep their defaults (.automatic / .automatic /
        // true) and the picker is inert for Deep Think and Maximum.
        let userRouting = await MainActor.run { self.activeUserRoutingPreference }
        config.fmPreference = userRouting.fmPreference
        config.executionContext = userRouting.executionContext
        config.allowPrivateCloudCompute = userRouting.allowPrivateCloudCompute

        let networkAvailable = NetworkMonitor.shared.isConnected
        let pccSuppressed = await MainActor.run { self.isPCCSuppressedForDeepThink() }
        let isAppleFM = llmService is AppleFoundationLLMService
        // `forceOnDevice` is for callers whose prompts are deliberately built to
        // a local budget. The reasoning-chain sessions are the case that matters:
        // `buildChainPrompt` truncates context and insights to fit 4096 tokens and
        // disables tools to save the ~400-token schema. Once those sessions start
        // passing real chunks (below), the planner sees sufficient evidence and
        // would happily route each one to PCC — turning eight local passes into
        // eight ~8s cloud round-trips plus quota, for prompts already sized for
        // on-device. Exploration stays local; the final synthesis, which passes
        // its own chunks and is not budget-capped, is where escalation belongs.
        //
        // That pin is a heuristic about prompt budgets, so an explicit PCC
        // selection outranks it — otherwise choosing PCC would still produce
        // eight local sessions, which is what device logs showed before this.
        // `requiresOnDevice`, by contrast, is the user's instruction and is
        // absolute: On-Device means no PCC for any call in the query, synthesis
        // included. Once it is set, the planner sees `allowsPCC: false`, targets
        // `.onDevice`, and the existing `.onDevice` branch below both keeps
        // execution local and trims the context to the local budget.
        let budgetPin = forceOnDevice && !userRouting.explicitlyPrefersPCC
        if !isAppleFM || !networkAvailable || pccSuppressed
            || userRouting.requiresOnDevice || budgetPin {
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
        }

        let consentState = await MainActor.run {
            cloudConsent[.applePCC] ?? .notDetermined
        }

        // `sourceChunks` defaults to [] and 13 of this function's 14 call sites
        // rely on that default — the agentic steps pass their evidence as an
        // already-rendered `context` string rather than as chunks. The planner
        // decides sufficiency from `chunkCount > 0 && topScore >= 0.20`, so
        // every one of those calls looked like zero evidence, planned
        // `.abstain`, and (before this change) threw a bogus
        // "model isn't available" error at the user.
        //
        // That is what made Deep Think and Maximum look broken: they route
        // through this path, Standard does not. Retrieval had genuinely
        // succeeded — the reasoning chain was holding thousands of characters
        // of on-target evidence at the moment the planner declared there was
        // none.
        //
        // Sufficiency must be judged on the evidence actually being sent. When
        // a caller supplies context but no chunks, derive the signal from the
        // context itself instead of defaulting to "insufficient". Callers that
        // *do* pass chunks keep the precise scores.
        let renderedContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let planningChunks = sourceChunks
        let hasRenderedEvidence = sourceChunks.isEmpty && !renderedContext.isEmpty

        let planned = await makePostRetrievalModelPlan(
            prompt: prompt,
            context: context,
            config: config,
            chunks: planningChunks,
            consentState: consentState,
            networkAvailable: networkAvailable,
            requiresMultiDocumentSynthesis: Set(sourceChunks.map { $0.chunk.documentId }).count > 1,
            hasRenderedEvidence: hasRenderedEvidence
        )
        let plan = planned.plan
        config.modelExecutionPlan = plan
        var routedContext = context
        var routedSourceChunks = sourceChunks

        switch plan.synthesisTarget {
        case .privateCloudCompute:
            let envelope = CloudEvidenceMinimizer().makeEnvelope(
                plan: plan,
                query: prompt,
                chunks: sourceChunks,
                maximumCharacters: max(
                    800,
                    min(
                        12_000,
                        Int(Double(plan.contextBudget.remaining + plan.contextBudget.evidence) *
                            FoundationModelTokenBudget.cloudFallbackCharsPerToken)
                    )
                )
            )
            routedContext = renderCloudEvidenceEnvelope(envelope)
            let includedIDs = Set(envelope.evidence.map(\.sourceID))
            routedSourceChunks = sourceChunks.filter {
                includedIDs.contains($0.chunk.id.uuidString)
            }
            do {
                try await ensureConsentForDeepThink(
                    service: llmService,
                    prompt: prompt,
                    context: routedContext,
                    sourceChunks: routedSourceChunks.map(\.chunk),
                    allowPrivateCloudCompute: true,
                    modelExecutionPlan: plan
                )
            } catch let error as RAGServiceError {
                if plan.fallback.target == .onDevice,
                   case .cloudConsentDenied(_) = error {
                    config.allowPrivateCloudCompute = false
                    config.executionContext = .onDeviceOnly
                } else if plan.fallback.target == .onDevice,
                          case .cloudConsentUnavailable(_) = error {
                    config.allowPrivateCloudCompute = false
                    config.executionContext = .onDeviceOnly
                } else {
                    throw error
                }
            }
        case .onDevice, .deterministic:
            config.allowPrivateCloudCompute = false
            config.executionContext = .onDeviceOnly
            if !planned.localBudget.fits {
                routedContext = String(routedContext.prefix(8_500))
            }
        case .abstain:
            // The planner chose to abstain because `evidence.isSufficient` was
            // false — a designed, correct outcome, not a failure. This used to
            // `throw RAGServiceError.modelNotAvailable`, which surfaced to the
            // user as "The selected model isn't available right now. Please try
            // again." That message is wrong in every respect: the model is fine,
            // retrying will not help, and the app's actual behavior — declining
            // to answer when the evidence does not support one — is a feature
            // rather than an outage.
            //
            // It also mostly hit Deep Think and Maximum: they route through this
            // planner path, while Standard does not, which made the modes look
            // broken when they were in fact abstaining.
            //
            // Return a grounded abstention so the verification story holds and
            // the user learns something actionable about their library.
            Log.info(
                "[ModelRouter] Planner abstained "
                    + "(\(plan.stages.first(where: { $0.role == .synthesize })?.reason.rawValue ?? "unknown"), "
                    + "chunks=\(plan.evidence.chunkCount) topScore=\(plan.evidence.topScore)); "
                    + "returning grounded abstention instead of an availability error",
                category: .llm
            )
            let abstention = """
            I couldn't find enough supporting evidence in this library to answer that reliably.

            Rather than guess, I'm stopping here. You could try rephrasing the question, \
            selecting a different library, or adding a document that covers it.
            """
            return LLMResponse(
                text: abstention,
                tokensGenerated: 0,
                timeToFirstToken: 0,
                totalTime: 0,
                modelName: "Abstained (insufficient evidence)",
                toolCallsMade: 0
            )
        }

        return try await generateWithFallback(
            prompt: prompt,
            context: routedContext,
            config: config,
            sourceChunks: routedSourceChunks.map(\.chunk),
            allowStructuredRAG: false
        )
    }
}
