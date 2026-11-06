//
//  AgenticOrchestrator.swift
//  OpenIntelligence
//
//  Retrieval-first agentic reasoning that escalates based on confidence.
//  Key insight: Don't decide complexity upfront - let retrieval results guide the pipeline.
//

import Foundation
import os
/// Retrieval-first agentic orchestrator
/// Key principle: Retrieve FIRST, then decide if escalation is needed based on results
@MainActor
final class AgenticOrchestrator: Sendable {
    weak var ragService: RAGService?
    let config: AgenticConfig
    /// Quality mode from user settings — controls retrieval parameters (topK, minSimilarity,
    /// mmrLambda, parent doc retrieval, compression, etc.) across all pipeline steps.
    /// Without this, Deep Think/Maximum use hardcoded defaults that ignore user's mode selection.
    let qualityMode: RAGQualityMode

    /// Common stop words to exclude from repetition detection
    /// These inflate overlap ratios without indicating actual semantic repetition
    static let commonStopWords: Set<String> = [
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

    /// Whether Deep Think runs its Self-RAG check after the chain (5.7). The check keyed on `config.maxSteps >= 8`, a
    /// stand-in for "this is Deep Think" that the A17 Pro's step budget of 5 never reached
    /// (`DeviceCapabilityService.optimizedAgenticConfig`), so Deep Think on an iPhone 15 Pro skipped the check every
    /// newer device runs. The step budget still picks the chain's starting length (`reasoningChainConfig`); Maximum runs
    /// its own check.
    static func runsDeepThinkSelfRAG(qualityMode: RAGQualityMode, config: AgenticConfig) -> Bool {
        qualityMode.canonical == .deepThink && !config.isUnlimited
    }

    /// Get the appropriate ReasoningChainConfig based on AgenticConfig
    /// Uses unlimited reasoning chain when AgenticConfig.isUnlimited is true
    private var reasoningChainConfig: ReasoningChainConfig {
        if config.isUnlimited {
            Log.info(
                "[Agentic] Using UNLIMITED reasoning chain (up to 50 sessions until 98% confident)", category: .llm)
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
    func makeDetailedEventForwarder(
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
                tokensUsed: 0,  // No tokens for pipeline events
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
    /// Runs a Deep Think or Maximum query, streaming only the text of its final answer.
    ///
    /// Every model call made here streams through `LLMStreamingContext.handler`, and a run makes
    /// dozens of them before the answer exists: planning, relevance checks, reasoning sessions,
    /// research decisions. So the chat's handler is parked in `finalAnswerHandler` for the whole
    /// run with `handler` cleared, and only the calls that write the final answer stream, through
    /// `LLMStreamingContext.answerHandler`. Stages that can still replace that text afterwards
    /// run through `RAGService.runFinishableStage`, so Stop or a new question keeps what streamed.
    func execute(
        query: String,
        initialContext: String = "",
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> AgenticResult {
        let chatStream = LLMStreamingContext.handler
        return try await LLMStreamingContext.$finalAnswerHandler.withValue(chatStream) {
            try await LLMStreamingContext.$handler.withValue(nil) {
                try await executeHoldingAnswerStream(query: query, initialContext: initialContext, onStep: onStep)
            }
        }
    }

    private func executeHoldingAnswerStream(
        query: String,
        initialContext: String,
        onStep: ((ThinkingStep) async -> Void)?
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
        var (multiQueryStep, initialChunks) = try await executeMultiQuerySearch(
            queries: searchQueries,
            ragService: ragService,
            onDetailedEvent: detailedForwarder
        )

        // A rewrite that finds nothing is a statement about the rewrite, not
        // about the library. Retry with what the user actually typed before any
        // downstream gate is allowed to conclude the documents don't cover it.
        //
        // Device log 2026-08-03: "Can you steam these scopes?" was rewritten to
        // "steam scopes", which fused 0 chunks, and the loop hard-exited with
        // "Retrieved content is irrelevant" after 2 of 8 sessions. A tool call in
        // the same session searched the same corpus for a related phrase and got
        // 45 chunks back — the document covers steam sterilisation in detail. The
        // planner's paraphrase lost the question, and the user was told their
        // document didn't mention it.
        if initialChunks.isEmpty, !searchQueries.contains(query) {
            Log.warning(
                "[Agentic] Query expansion \(searchQueries) returned 0 chunks. Retrying with the original query before judging relevance.",
                category: .retrieval
            )
            await detailedForwarder?(
                .retrieval, "Retrying", "Expansion found nothing — searching your original wording")

            let (retryStep, retryChunks) = try await executeMultiQuerySearch(
                queries: [query],
                ragService: ragService,
                onDetailedEvent: detailedForwarder
            )

            if !retryChunks.isEmpty {
                Log.info(
                    "[Agentic] Original query recovered \(retryChunks.count) chunk(s) the expansion missed.",
                    category: .retrieval
                )
                multiQueryStep = retryStep
                initialChunks = retryChunks
            }
        }
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

        Log.info(
            "[Agentic] Relevance check: lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), intent=\(intentValid)",
            category: .retrieval)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // HARD EXIT: If both checks fail, don't try to salvage - just say "not found"
        // This prevents the "8 sessions of philosophical rambling" problem
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if lexicalRelevance < AgenticPolicyService.hardIrrelevanceLexicalThreshold() && !intentValid {
            Log.warning(
                "[Agentic] HARD EXIT: Retrieved content is irrelevant (lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), intent=false)",
                category: .retrieval)

            let notFoundStep = ThinkingStep(
                id: UUID(),
                type: .analyzing,
                input: "Relevance check",
                output:
                    "Retrieved content doesn't match the query. The documents may not contain information about this topic.",
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
                confidence: 0.0,  // Honest: we found nothing
                sourcesUsed: 0,
                retrievedChunks: []
            )
        }

        // Downgrade quality if semantic intent doesn't match but lexical has some overlap
        if !intentValid && (retrievalQuality == .excellent || retrievalQuality == .good) {
            Log.info(
                "[Agentic] Semantic intent mismatch - downgrading from \(retrievalQuality.description) to moderate",
                category: .llm)
            retrievalQuality = AgenticPolicyService.downgradedForSemanticMismatch(retrievalQuality)
        }

        Log.info(
            "[Agentic] Retrieval quality: \(retrievalQuality.description), Intent valid: \(intentValid)", category: .llm
        )

        // Emit evaluation step so user sees the reasoning
        let evalStep = ThinkingStep(
            id: UUID(),
            type: .analyzing,
            input: "Evaluating \(initialChunks.count) results",
            output:
                "Confidence: \(retrievalQuality.description) (\(String(format: "%.0f%%", retrievalQuality.confidenceScore * 100)))\nSemantic match: \(intentValid ? "✓" : "✗") \(intentReason)",
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
                for chunk in expandedChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id })
                {
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
            Log.info(
                "[Agentic] Cross-reference resolution added \(crossRefChunks.count) chunks, quality: \(retrievalQuality.description)",
                category: .llm)
        }

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // DECISION POINT: Based on retrieval quality
        // Use REASONING CHAIN for excellent/good to multiply effective context
        // MAXIMUM MODE: gather the library's relevant passages, then the True Unlimited loop with its Fact Bank
        // (executeTrueUnlimitedReasoning). The parallel per-cluster multi-chain path it replaced was removed 2026-11-06.
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
                    targetConfidence: config.confidenceThreshold,  // 0.98 for unlimited
                    maxSessions: config.maxSteps,  // 50 for unlimited
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

                    Log.info(
                        "[Agentic] Maximum Mode: Calibrated confidence \(Int(sessionConfidence * 100))% → \(Int(finalConfidence * 100))% (addresses question: \(verification.addressesQuestion))",
                        category: .llm)

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
            // Decide from what the chain measured, not from how its answer reads.
            //
            // This was `answerIndicatesRetrievalMiss(chainResult.finalAnswer)` alone: a string
            // heuristic scanning the prose for hedging like "do not specify". It has two failure
            // modes and both were observed. A confidently wrong answer contains no hedging, so the
            // loop never ran when it was most needed. And a grounded synthesis that correctly notes
            // a gap does contain hedging, so a 91% confidence answer was discarded in favour of a
            // raw evidence dump, which is why the guard below this call exists at all.
            //
            // Meanwhile `FactBank` had already decomposed the query into sub-questions, tracked
            // which ones the evidence answered, and compared that against the coverage target the
            // chain uses for its own early-stop decision. All of it was computed and thrown away.
            // Finishing below your own coverage target is the definition of not having finished,
            // and it is a measurement rather than an inference about wording.
            //
            // The prose heuristic is kept as an additional trigger rather than replaced, because it
            // catches a real case the coverage figure cannot see: retrieval that confidently
            // returned the wrong subject entirely, where every sub-question reads as answered.
            let coverageShortfall = chainResult.evidenceCoverage < chainResult.evidenceCoverageTarget
            let hasGaps = !chainResult.unansweredQuestions.isEmpty
            let proseSuggestsMiss = answerIndicatesRetrievalMiss(chainResult.finalAnswer)

            if coverageShortfall || proseSuggestsMiss {
                Log.info(
                    "[Agentic] Researching further: coverage \(Int(chainResult.evidenceCoverage * 100))% "
                        + "against a \(Int(chainResult.evidenceCoverageTarget * 100))% target, "
                        + "\(chainResult.unansweredQuestions.count) sub-question(s) unanswered, "
                        + "prose-miss=\(proseSuggestsMiss)",
                    category: .llm
                )

                // Search the gaps, not the original question. Re-running `query` looks for what was
                // already found; the unanswered sub-questions are the only part still missing, and
                // the chain has just told us exactly what they are. Capped at three so the decision
                // prompt stays readable, and falls back to the original query when the decomposition
                // produced nothing to aim at.
                let researchQuery: String
                if hasGaps {
                    let gaps = chainResult.unansweredQuestions.prefix(3).joined(separator: "; ")
                    researchQuery = "\(query)\n\nStill unanswered: \(gaps)"
                } else {
                    researchQuery = query
                }

                // A throw here must not destroy the answer the chain already produced.
                //
                // This was `try await` with no catch, so any failure inside recursive research
                // propagated out and failed the whole query. The block below already handles
                // "research found nothing better" by falling through to the chain result; only a
                // *throw* skipped that.
                //
                // Device evidence 2026-08-14, and this is the sequence that matters: the reasoning
                // chain generated eight session insights and a final synthesis successfully, then
                // recursive research returned an empty response four times, and the user got a
                // failed query instead of the answer that existed. Recursive research is an
                // enhancement to an answer that is already in hand. It cannot be allowed to take it
                // away.
                //
                // The gate above now fires on measured coverage rather than on the prose heuristic,
                // which means this path runs far more often than it used to, so a latent failure in
                // it became a constant one.
                var recursiveResult: AgenticResult?
                do {
                    recursiveResult = try await ragService.runFinishableStage {
                        try await self.executeRecursiveResearch(
                            query: researchQuery,
                            maxIterations: 5,
                            onStep: onStep
                        )
                    }
                } catch {
                    Log.warning(
                        "[Agentic] Recursive research failed (\(type(of: error))): "
                            + "\(error.localizedDescription). Keeping the chain's answer.",
                        category: .llm
                    )
                    recursiveResult = nil
                }

                // If recursive research found a better answer, use it
                // The dump guard matters as much as the miss guard: this branch only
                // asked whether the replacement was *also* flagged as a miss, never
                // whether it was actually an answer. A raw evidence dump is flagged
                // by neither, so it won every time it appeared.
                let cleanRecursiveAnswer = (recursiveResult?.finalAnswer ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // The citation guard belongs here for the same reason as the three above it, and this
                // is the call site that actually reaches the user on a low-confidence query. It
                // returns immediately, **before** the Deep Think verification loop below, so nothing
                // downstream inspects what it hands back. A 6-case smoke at `ccc0eeb` proved that:
                // the guard added to `runVerificationLoop` did not fire here, and the case still
                // answered "No evidence of a dataset of rumors in the provided context." in 59
                // characters, from a 2000-character slice, having discarded the chain's synthesis.
                let agreesWithSynthesis = Self.researchMayReplaceSynthesis(
                    question: query, synthesis: chainResult.finalAnswer, research: cleanRecursiveAnswer)
                if recursiveResult != nil, !cleanRecursiveAnswer.isEmpty, !agreesWithSynthesis {
                    Log.warning(
                        "[Agentic] Kept the synthesis (\(chainResult.finalAnswer.count) chars): research's "
                            + "\(cleanRecursiveAnswer.count)-char answer says things the synthesis does not",
                        category: .llm)
                }
                if let recursiveResult,
                    !cleanRecursiveAnswer.isEmpty,
                    !answerIndicatesRetrievalMiss(recursiveResult.finalAnswer),
                    !looksLikeRawEvidenceDump(cleanRecursiveAnswer),
                    Self.shouldAcceptReplacement(previous: chainResult.finalAnswer, replacement: cleanRecursiveAnswer),
                    agreesWithSynthesis
                {
                    Log.info(
                        "[Agentic] Recursive research found answer after \(recursiveResult.steps.count) steps",
                        category: .llm)
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
                Log.debug(
                    "[Agentic] Recursive research also couldn't find answer - using original chain result",
                    category: .llm)
            }

            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            // SELF-RAG 2.0: Verify answer before returning (Deep Think mode only)
            // 2026 best practice: Don't just generate — verify citations and relevance
            // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
            let isDeepThinkMode = Self.runsDeepThinkSelfRAG(qualityMode: qualityMode, config: config)
            if isDeepThinkMode,
                let verified = try await ragService.runFinishableStage({
                    try await self.runVerificationLoop(
                        query: query,
                        initialAnswer: chainResult.finalAnswer,
                        initialSteps: steps,
                        initialTokens: totalTokens,
                        initialConfidence: chainResult.confidence,
                        // The array the chain actually labelled, not the pre-routing order. See
                        // `ReasoningChainResult.routedChunks`.
                        initialSources: chainResult.routedChunks,
                        ragService: ragService,
                        startTime: startTime,
                        onStep: onStep
                    )
                })
            {
                return verified
            }

            // Report the array the chain actually laboured over, not the pre-routing
            // accumulation. `initialSources:` above already does this and says why; these two
            // returns were left on `allRetrievedChunks`, so the two disagreed.
            //
            // The chain labels sources by global position in `routedChunks` (see
            // `labelOffset`), so a citation of `[S13]` is valid against that array. Handing
            // back a shorter, differently-ordered list silently turns every citation past its
            // end into a dangling reference.
            //
            // Device 2026-08-19: 20 chunks entered the pipeline, the reasoning trace cited
            // `[S13]` and `[S17]`, and 12 chunks were reported. Nothing was hallucinated —
            // the citations were right and the source list was the wrong one.
            return AgenticResult(
                finalAnswer: chainResult.finalAnswer,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: chainResult.confidence,
                sourcesUsed: chainResult.routedChunks.count,
                retrievedChunks: chainResult.routedChunks
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
                for chunk in refinedChunks where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id })
                {
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
            let isDeepThinkMode = Self.runsDeepThinkSelfRAG(qualityMode: qualityMode, config: config)
            if isDeepThinkMode,
                let verified = try await ragService.runFinishableStage({
                    try await self.runVerificationLoop(
                        query: query,
                        initialAnswer: chainResult.finalAnswer,
                        initialSteps: steps,
                        initialTokens: totalTokens,
                        initialConfidence: chainResult.confidence,
                        // The array the chain actually labelled, not the pre-routing order. See
                        // `ReasoningChainResult.routedChunks`.
                        initialSources: chainResult.routedChunks,
                        ragService: ragService,
                        startTime: startTime,
                        onStep: onStep
                    )
                })
            {
                return verified
            }

            // Report the array the chain actually laboured over, not the pre-routing
            // accumulation. `initialSources:` above already does this and says why; these two
            // returns were left on `allRetrievedChunks`, so the two disagreed.
            //
            // The chain labels sources by global position in `routedChunks` (see
            // `labelOffset`), so a citation of `[S13]` is valid against that array. Handing
            // back a shorter, differently-ordered list silently turns every citation past its
            // end into a dangling reference.
            //
            // Device 2026-08-19: 20 chunks entered the pipeline, the reasoning trace cited
            // `[S13]` and `[S17]`, and 12 chunks were reported. Nothing was hallucinated —
            // the citations were right and the source list was the wrong one.
            return AgenticResult(
                finalAnswer: chainResult.finalAnswer,
                steps: steps,
                totalTokens: totalTokens,
                totalDuration: Date().timeIntervalSince(startTime),
                confidence: chainResult.confidence,
                sourcesUsed: chainResult.routedChunks.count,
                retrievedChunks: chainResult.routedChunks
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
                        chunks: allRetrievedChunks,
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
                chunks: allRetrievedChunks,
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
                Log.info(
                    "[Agentic] Speculative RAG succeeded with \(String(format: "%.0f%%", speculativeResult.confidence * 100)) confidence (threshold: \(String(format: "%.0f%%", effectiveThreshold * 100)))",
                    category: .llm)
                return speculativeResult
            }

            // Speculative RAG didn't meet threshold - fall back to deeper retrieval
            Log.info(
                "[Agentic] Speculative RAG \(String(format: "%.0f%%", speculativeResult.confidence * 100)) < threshold \(String(format: "%.0f%%", effectiveThreshold * 100)) → escalating to deeper retrieval",
                category: .llm)

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
                Log.info(
                    "[Agentic] Single-topic, low confidence → trying alternative search strategies", category: .llm)

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
                    for chunk in broaderChunks
                    where !allRetrievedChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                        allRetrievedChunks.append(chunk)
                    }
                }

                // Format expanded results
                var expandedResults = multiQueryStep.output
                if broaderChunks.count > initialChunks.count {
                    expandedResults = "Expanded search found \(broaderChunks.count) chunks:\n\n"
                    for (index, chunk) in broaderChunks.prefix(8).enumerated() {
                        expandedResults += "[\(index + 1)] From \(chunk.sourceDocument):\n"
                        let content = chunk.chunk.contextText.prefix(500)
                        expandedResults += String(content) + "\n\n"
                    }
                }

                // Synthesize with everything we found
                let synthesisStep = try await executeDirectSynthesis(
                    query: query,
                    searchResults: expandedResults,
                    chunks: allRetrievedChunks,
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
                    confidence: 0.4,  // Low but we tried our best
                    sourcesUsed: allRetrievedChunks.count,
                    retrievedChunks: allRetrievedChunks
                )
            }
        }
    }

}
