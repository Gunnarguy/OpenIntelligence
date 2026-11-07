//
//  RAGService+QueryExits.swift
//  OpenIntelligence
//
//  Part of RAGService, moved from RAGService+QueryPipeline.swift on 2026-11-07 (5.8 split); only access keywords changed.
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

extension RAGService {
    /// Step 3 (empty): answers by direct chat or abstains when retrieval found no passages.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func handleNoRetrievedPassages(retrievedChunks: [RetrievedChunk], question: String, retrievalTime: TimeInterval, allowUngroundedFallback: Bool, ragQueryValue: RAGQuery, inferenceConfig: InferenceConfig, pipelineStartTime: Date, selectedId: UUID, selectedName: String, retrievalConfig: RetrievalConfig, embeddingProviderId: String) async throws -> RAGResponse? {
        // Edge case: No relevant chunks found
        if retrievedChunks.isEmpty {
            Log.warning(
                "⚠️  [RAGService] No chunks retrieved (database may be empty)",
                category: .retrieval
            )
            TelemetryCenter.emit(
                .retrieval,
                severity: .warning,
                title: "No chunks retrieved",
                metadata: [
                    "question": String(question.prefix(60))
                ],
                duration: retrievalTime
            )
            emitThinkingEvent(
                .warning,
                title: "Insufficient evidence",
                detail: "No relevant chunks found"
            )
            if allowUngroundedFallback {
                // Fallback to direct LLM chat mode
                let response = try await generateDirectChatResponse(
                    question: question,
                    ragQuery: ragQueryValue,
                    inferenceConfig: inferenceConfig,
                    pipelineStartTime: pipelineStartTime,
                    retrievalTime: retrievalTime,
                    fallbackNote:
                        "No relevant document context found; replied without RAG context."
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: [],
                retrievalTime: retrievalTime,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "I couldn't find relevant sources in your library for that question.",
                gatingDecision: "no_sources"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step 4 (empty): answers by direct chat or abstains when re-ranking left no candidates.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func handleEmptyRerank(rerankedChunks: [RetrievedChunk], allowUngroundedFallback: Bool, question: String, ragQueryValue: RAGQuery, inferenceConfig: InferenceConfig, pipelineStartTime: Date, retrievalTime: TimeInterval, selectedId: UUID, selectedName: String, retrievalConfig: RetrievalConfig, embeddingProviderId: String) async throws -> RAGResponse? {
        if rerankedChunks.isEmpty {
            Log.warning(
                "⚠️  [RAGService] Re-ranking yielded no candidates",
                category: .retrieval
            )
            emitThinkingEvent(
                .warning,
                title: "Re-ranking exhausted",
                detail: "No viable candidates"
            )
            if allowUngroundedFallback {
                let response = try await generateDirectChatResponse(
                    question: question,
                    ragQuery: ragQueryValue,
                    inferenceConfig: inferenceConfig,
                    pipelineStartTime: pipelineStartTime,
                    retrievalTime: retrievalTime,
                    fallbackNote: "No re-ranked candidates; replied without RAG context."
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: [],
                retrievalTime: retrievalTime,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "I couldn't identify reliable sources after re-ranking.",
                gatingDecision: "rerank_empty"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step 4.3 (gate): when no passage clears the similarity floor, takes the top re-ranked passages under override, lenient or fallback rules, else abstains.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func handleNoConfidentPassages(filteredChunks: inout [RetrievedChunk], acceptanceOverride: Bool, lenient: Bool, effectiveTopK: Int, rerankedChunks: [RetrievedChunk], topSim: Float, secondSim: Float, avgTop5: Float, allowUngroundedFallback: Bool, dynamicMin: Float, question: String, ragQueryValue: RAGQuery, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, embeddingProviderId: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        // Edge case: No high-confidence chunks
        if filteredChunks.isEmpty {
            if acceptanceOverride || lenient {
                // Use top reranked results directly under override/lenient conditions
                filteredChunks = Array(rerankedChunks.prefix(effectiveTopK * 2))
                Log.info(
                    "   ✅ Acceptance override applied; proceeding with top reranked results",
                    category: .retrieval
                )
                TelemetryCenter.emit(
                    .retrieval,
                    title: "Acceptance override",
                    metadata: [
                        "topSim": String(format: "%.3f", topSim),
                        "secondSim": String(format: "%.3f", secondSim),
                        "avgTop5": String(format: "%.3f", avgTop5),
                    ]
                )
            } else if allowUngroundedFallback {
                // Low-confidence retrieval: proceed with best-available reranked chunks under
                // explicit fallback allowances.
                Log.warning(
                    "   ⚠️  No chunks met the confidence threshold; proceeding with best-available context",
                    category: .retrieval
                )
                emitThinkingEvent(
                    .fallback,
                    title: "Low-confidence context",
                    detail: "Proceeding with best-available chunks"
                )
                TelemetryCenter.emit(
                    .retrieval,
                    severity: .warning,
                    title: "Low-confidence context (proceeding)",
                    metadata: [
                        "threshold": String(format: "%.2f", dynamicMin),
                        "topSim": String(format: "%.3f", topSim),
                    ]
                )

                filteredChunks = Array(rerankedChunks.prefix(max(effectiveTopK, 3)))
            } else {
                let response = await makeGroundedAbstainResponse(
                    question: question,
                    ragQuery: ragQueryValue,
                    retrievedChunks: rerankedChunks,
                    retrievalTime: retrievalTime,
                    retrievalConfig: retrievalConfig,
                    embeddingProviderId: embeddingProviderId,
                    reason: "I couldn't find high-confidence evidence in your library for this query.",
                    gatingDecision: "low_confidence"
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }
        }
        return nil
    }

    /// Step 4.5 (empty): answers by direct chat or abstains when MMR returned no passages.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func handleEmptyDiverseSet(diverseChunks: [RetrievedChunk], allowUngroundedFallback: Bool, question: String, ragQueryValue: RAGQuery, inferenceConfig: InferenceConfig, pipelineStartTime: Date, retrievalTime: TimeInterval, selectedId: UUID, selectedName: String, retrievalConfig: RetrievalConfig, embeddingProviderId: String) async throws -> RAGResponse? {
        if diverseChunks.isEmpty {
            Log.warning(
                "⚠️  [RAGService] MMR returned no candidates",
                category: .retrieval
            )
            emitThinkingEvent(
                .warning,
                title: "MMR exhausted",
                detail: "No diverse candidates"
            )
            if allowUngroundedFallback {
                let response = try await generateDirectChatResponse(
                    question: question,
                    ragQuery: ragQueryValue,
                    inferenceConfig: inferenceConfig,
                    pipelineStartTime: pipelineStartTime,
                    retrievalTime: retrievalTime,
                    fallbackNote:
                        "No diverse candidates after MMR; replied without RAG context."
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: [],
                retrievalTime: retrievalTime,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "I couldn't build a diverse evidence set to answer reliably.",
                gatingDecision: "mmr_empty"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step SH: returns the closest sources instead of an answer when fewer passages than Library Settings requires reach its minimum score.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func enforcePassagesNeeded(rerankedChunks: [RetrievedChunk], diverseChunks: [RetrievedChunk], retrievalConfig: RetrievalConfig, retrievalTime: TimeInterval, embeddingProviderId: String, ragQueryValue: RAGQuery, question: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        // The passages-needed rule of Library Settings (5.7, `RetrievalPolicyService.strongPassageShortfall`):
        // with two or more required, too few passages at the library's minimum score get the closest
        // sources instead of an answer. Each passage counts at the score the re-ranker gave it: a rescued table
        // passage is raised to just under the best score so it reaches the answer, and that is not a close
        // match (review, 2026-10-20). "high_accuracy_blocked" is the rule's older name, which
        // `VerificationOutcome` reads.
        let rerankedScores = Dictionary(
            rerankedChunks.map { ($0.chunk.id, $0.similarityScore) }, uniquingKeysWith: { first, _ in first })
        if let shortfall = RetrievalPolicyService.strongPassageShortfall(
            diverseChunks, config: retrievalConfig,
            score: { rerankedScores[$0.chunk.id] ?? $0.similarityScore })
        {
            let topSources = diverseChunks.prefix(3).enumerated().map { idx, r in
                let src = r.sourceDocument.isEmpty ? "Unknown" : r.sourceDocument
                let page = r.pageNumber.map { " (p.\($0))" } ?? ""
                let score = rerankedScores[r.chunk.id] ?? r.similarityScore
                return "- [\(idx + 1)] \(src)\(page), \(String(format: "%.0f%%", score * 100))"
            }.joined(separator: "\n")
            let cleared = shortfall.found == 0 ? "none did" : "only \(shortfall.found) did"
            let minimum = String(format: "%.0f%%", retrievalConfig.minSimilarity * 100)
            let caution =
                "This library is set to answer only when at least \(shortfall.needed) of the passages found score \(minimum) or more for your question, and \(cleared). The closest passages:\n\(topSources)\n\nTo answer from fewer, lower Passages Needed in Library Settings, under Search."

            emitThinkingEvent(
                .warning,
                title: "Too few passages at the minimum score",
                detail: "\(shortfall.found) of \(shortfall.needed) scored \(minimum) or more"
            )

            let metadata = ResponseMetadata(
                timeToFirstToken: nil,
                totalGenerationTime: 0,
                tokensGenerated: 0,
                tokensPerSecond: nil,
                modelUsed: llmService.modelName,
                retrievalTime: retrievalTime,
                retrievalConfigSummary: retrievalConfig.summary,
                gatingDecision: "high_accuracy_blocked",
                toolCallsMade: 0,
                embeddingProvider: embeddingProviderId
            )

            let response = RAGResponse(
                queryId: ragQueryValue.id,
                retrievedChunks: diverseChunks,
                generatedResponse: caution,
                metadata: metadata,
                confidenceScore: 0.0,
                qualityWarnings: ["Passages needed: \(shortfall.found) of \(shortfall.needed) scored \(minimum) or more"],
                structuredAnswer: StructuredAnswer.refusal(
                    reason: caution,
                    missing: [
                        "At least \(shortfall.needed) passages scoring \(String(format: "%.0f%%", retrievalConfig.minSimilarity * 100)) or more, which Library Settings asks for."
                    ],
                    topScore: diverseChunks.first?.similarityScore ?? 0,
                    loops: 1,
                    retrievedChunks: diverseChunks
                )
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step 5 (empty): answers by direct chat or abstains when context assembly produced no passages.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func handleEmptyAssembledContext(actualChunksUsed: Int, context: String, allowUngroundedFallback: Bool, question: String, ragQueryValue: RAGQuery, inferenceConfig: InferenceConfig, pipelineStartTime: Date, retrievalTime: TimeInterval, selectedId: UUID, selectedName: String, retrievalConfig: RetrievalConfig, embeddingProviderId: String) async throws -> RAGResponse? {
        // If context is empty, fallback to direct chat to avoid downstream failures
        if actualChunksUsed == 0 || context.isEmpty {
            Log.warning(
                "⚠️  [RAGService] Empty context after assembly",
                category: .retrieval
            )
            emitThinkingEvent(
                .warning,
                title: "Context empty",
                detail: "Insufficient evidence"
            )
            if allowUngroundedFallback {
                let response = try await generateDirectChatResponse(
                    question: question,
                    ragQuery: ragQueryValue,
                    inferenceConfig: inferenceConfig,
                    pipelineStartTime: pipelineStartTime,
                    retrievalTime: retrievalTime,
                    fallbackNote: "Empty assembled context; replied without RAG context."
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: response
                )
            }
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: [],
                retrievalTime: retrievalTime,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "I couldn't assemble enough context to answer reliably.",
                gatingDecision: "context_empty"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step SG: returns a not-found answer when the included passages are lexically and semantically irrelevant to the question.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyHardRelevanceGate(bestSimilarity: Float, lexicalRelevance: Float, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, embeddingProviderId: String, ragQueryValue: RAGQuery, question: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        if lexicalRelevance < 0.1 && bestSimilarity < 0.3 {
            Log.warning(
                "[RAG] Hard exit: Retrieved content is irrelevant (lexical=\(String(format: "%.0f%%", lexicalRelevance * 100)), similarity=\(String(format: "%.2f", bestSimilarity)))",
                category: .retrieval)

            emitThinkingEvent(
                .warning,
                title: "Content not found",
                detail: "Retrieved content doesn't match query"
            )

            let notFoundMetadata = ResponseMetadata(
                timeToFirstToken: nil,
                totalGenerationTime: 0,
                tokensGenerated: 0,
                tokensPerSecond: nil,
                modelUsed: "none",
                retrievalTime: retrievalTime,
                retrievalConfigSummary: retrievalConfig.summary,
                gatingDecision: "relevance_gate_failed",
                toolCallsMade: 0,
                embeddingProvider: embeddingProviderId
            )

            let notFoundResponse = RAGResponse(
                queryId: ragQueryValue.id,
                retrievedChunks: [],
                generatedResponse:
                    "I couldn't find relevant information about this topic in your documents. The retrieved content was about different subjects.",
                metadata: notFoundMetadata,
                confidenceScore: 0.0,
                qualityWarnings: ["Relevance gate failed: retrieved content doesn't match query"],
                structuredAnswer: StructuredAnswer.refusal(
                    reason:
                        "I couldn't find relevant information about this topic in your documents. The retrieved content was about different subjects.",
                    missing: ["No relevant information matched the query in the selected library."],
                    topScore: bestSimilarity,
                    loops: 1
                )
            )

            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: notFoundResponse
            )
        }
        return nil
    }

    /// Step 5.9: answers a summarize question from an extractive summary of the included passages, falling through to generation when it fails.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func answerWithExtractiveSummary(answerIntent: AnswerIntent, effectiveQuery: String, includedRetrievedChunks: [RetrievedChunk], retrievalTime: TimeInterval, ragQueryValue: RAGQuery, question: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Step 5.9: Extractive Summarization (AppleRAG §6)
        // For .summarize intent, use extractive selection to minimize hallucination
        // This bypasses LLM generation entirely for pure summarization queries
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if answerIntent == .summarize && answerIntent.isExtractiveFirst {
            Log.section("Step 5.9: Extractive Summarization", level: .info, category: .pipeline)
            let extractiveStart = Date()

            do {
                let summary = try await extractiveSummarizationService.summarize(
                    query: effectiveQuery,
                    chunks: includedRetrievedChunks,
                    maxWords: 300
                )

                let extractiveTime = Date().timeIntervalSince(extractiveStart)

                Log.info(
                    "[Extractive] \(summary.sentences.count) sentences, \(summary.wordCount) words, coverage: \(String(format: "%.0f", summary.coverageScore * 100))% in \(String(format: "%.0f", extractiveTime * 1000))ms",
                    category: .retrieval
                )

                emitThinkingEvent(
                    .extractive,
                    title: "Extractive summary",
                    detail: "\(summary.sentences.count) sentences • \(summary.wordCount) words"
                )

                // Build response directly from extractive summary
                let extractiveMetadata = ResponseMetadata(
                    timeToFirstToken: nil,
                    totalGenerationTime: extractiveTime,
                    tokensGenerated: summary.wordCount,
                    tokensPerSecond: nil,
                    modelUsed: "extractive",
                    retrievalTime: retrievalTime,
                    retrievalConfigSummary: "extractive_summarization",
                    gatingDecision: "extractive_intent",
                    toolCallsMade: nil
                )

                let extractiveResponse = RAGResponse(
                    queryId: ragQueryValue.id,
                    retrievedChunks: includedRetrievedChunks,
                    generatedResponse: resolvedDisplayResponse(
                        fallback: summary.summaryText,
                        structuredAnswer: StructuredAnswer.from(
                            response: summary.summaryText,
                            retrievedChunks: includedRetrievedChunks,
                            answerIntent: answerIntent,
                            verificationResult: nil,
                            loops: 1
                        )
                    ),
                    metadata: extractiveMetadata,
                    confidenceScore: summary.coverageScore,
                    qualityWarnings: [],
                    structuredAnswer: StructuredAnswer.from(
                        response: summary.summaryText,
                        retrievedChunks: includedRetrievedChunks,
                        answerIntent: answerIntent,
                        verificationResult: nil,
                        loops: 1
                    )
                )

                Log.info("✓ Extractive summary complete (\(summary.wordCount) words)", category: .pipeline)

                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: extractiveResponse
                )
            } catch {
                Log.warning(
                    "[Extractive] Summarization failed, falling back to LLM: \(error.localizedDescription)",
                    category: .retrieval)
                // Fall through to LLM generation
            }
        }
        return nil
    }

    /// Step 6d (abstain): abstains when citations are required, missing after the retry, and ungrounded fallback is off.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func abstainForMissingCitations(requiresCitations: Bool, responseText: String, allowUngroundedFallback: Bool, preserveStreamingResponse: Bool, question: String, ragQueryValue: RAGQuery, generationRetrievedChunks: [RetrievedChunk], retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, embeddingProviderId: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        if requiresCitations,
            !responseHasCitations(responseText),
            !allowUngroundedFallback,
            !preserveStreamingResponse
        {
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: generationRetrievedChunks,
                retrievalTime: retrievalTime,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "I couldn't produce a cited answer from the provided sources.",
                gatingDecision: "missing_citations"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }
        return nil
    }

    /// Step 6g (empty): answers from the recovered passages when the model returned nothing, else throws modelNotAvailable.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func fallBackFromEmptyAnswer(responseText: String, recoveryRetrievedChunks: [RetrievedChunk], question: String, effectiveTopK: Int, ragQuery: RAGQuery?, inferenceConfig: InferenceConfig, retrievalConfig: RetrievalConfig, embeddingProviderId: String, recoveryRetrievalTime: TimeInterval, selectedId: UUID, selectedName: String) async throws -> RAGResponse? {
        // Verify we got a response — if empty, route to reliability fallback
        // instead of throwing modelNotAvailable (which skips fallback entirely)
        if responseText.isEmpty {
            Log.warning(
                "⚠️  LLM returned empty response (0 tokens) — routing to reliability fallback",
                category: .llm)
            if !recoveryRetrievedChunks.isEmpty {
                let emptyFallback = await buildReliabilityFallbackResponse(
                    question: question,
                    ragQuery: ragQuery ?? RAGQuery(query: question, topK: effectiveTopK),
                    inferenceConfig: inferenceConfig,
                    retrievalConfig: retrievalConfig,
                    embeddingProviderId: embeddingProviderId,
                    retrievedChunks: recoveryRetrievedChunks,
                    retrievalTime: recoveryRetrievalTime,
                    reason: "LLM returned empty response"
                )
                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: emptyFallback
                )
            }
            throw RAGServiceError.modelNotAvailable
        }
        return nil
    }

    /// Step 7.5 (abstain): logs the verification gates and abstains when they failed in grounded-only mode or below the quality mode's threshold.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func abstainOnFailedVerification(verificationResult: RAGVerificationResult?, confidencePolicy: QueryConfidencePolicy, answerIntentIsExtractive: Bool, answerIntent: AnswerIntent, allowUngroundedFallback: Bool, qualityModeDisplayName: String, verificationService: VerificationGateService, question: String, generationRetrievedChunks: [RetrievedChunk], ragQueryValue: RAGQuery, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, embeddingProviderId: String, selectedId: UUID, selectedName: String) async -> RAGResponse? {
        if let vr = verificationResult {
            Log.pipelineStep(
                "7.5", title: "Verification Gates",
                details: [
                    ("passed", vr.passed ? "✓" : "✗"),
                    ("confidence", String(format: "%.2f", vr.overallConfidence)),
                    (
                        "gates",
                        vr.gateResults.map { "\($0.gate.rawValue):\($0.passed ? "✓" : "✗")" }.joined(
                            separator: " ")
                    ),
                ])

            // Emit verification thinking event
            // A failure names its gates (5.7): the Details panel showed every step green while
            // Gate I had failed, because nothing it reads said which.
            let failedGateNames = vr.gateResults.filter { !$0.passed }.map(\.gate.rawValue)
            emitThinkingEvent(
                .verification,
                title: vr.passed ? "Gates passed ✓" : "Gates failed ✗",
                detail: (failedGateNames.isEmpty ? "" : "Failed: \(failedGateNames.joined(separator: ", ")). ")
                    + "Confidence: \(String(format: "%.0f", vr.overallConfidence * 100))%"
            )

            if !vr.passed {
                Log.warning(
                    "⚠️ Verification gates failed - response may contain unsupported claims",
                    category: .pipeline)
                for gateResult in vr.gateResults where !gateResult.passed {
                    Log.warning(
                        "   • Gate \(gateResult.gate.rawValue): \(gateResult.details)",
                        category: .pipeline)
                }

                let effectiveThreshold = confidencePolicy.verificationPassThreshold
                if answerIntentIsExtractive {
                    Log.debug(
                        "[Verification] Extractive intent '\(answerIntent.rawValue)' - using relaxed threshold \(String(format: "%.0f", effectiveThreshold * 100))%",
                        category: .pipeline)
                }

                // Check if confidence is below quality mode threshold (Maximum mode requires 98%)
                let belowConfidenceThreshold = vr.overallConfidence < effectiveThreshold

                // If grounded-only mode and verification fails, abstain
                if !allowUngroundedFallback || belowConfidenceThreshold {
                    let thresholdDisplay =
                        answerIntentIsExtractive
                        ? "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))% (relaxed for extractive)"
                        : "\(qualityModeDisplayName) threshold \(String(format: "%.0f", effectiveThreshold * 100))%"
                    let reason =
                        belowConfidenceThreshold
                        ? "confidence \(String(format: "%.0f", vr.overallConfidence * 100))% below \(thresholdDisplay)"
                        : "grounded-only mode"
                    Log.info("🛑 Abstaining: \(reason)", category: .pipeline)
                    let abstainResponse = verificationService.generateAbstentionResponse(
                        query: question,
                        verificationResult: vr,
                        retrievedChunks: generationRetrievedChunks
                    )
                    let response = await makeGroundedAbstainResponse(
                        question: question,
                        ragQuery: ragQueryValue,
                        retrievedChunks: generationRetrievedChunks,
                        retrievalTime: retrievalTime,
                        retrievalConfig: retrievalConfig,
                        embeddingProviderId: embeddingProviderId,
                        reason: abstainResponse,
                        gatingDecision:
                            "verification_gates_failed:\(vr.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: ","))"
                    )
                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )
                }
            } else {
                Log.info(
                    "✓ All verification gates passed (confidence: \(String(format: "%.0f", vr.overallConfidence * 100))%)",
                    category: .pipeline)
            }
        }  // end if let vr
        return nil
    }

    /// Step IC: builds a recovery response from the generated text when processing the answer threw (the inner catch body).
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func recoverFromResponseProcessingError(error: any Error, llmResponse: LLMResponse, generationRetrievedChunks: [RetrievedChunk], answerIntent: AnswerIntent, reasoningTraceForMetadata: [String]?, generationTime: TimeInterval, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, embeddingProviderId: String, ragQueryValue: RAGQuery, question: String, selectedId: UUID, selectedName: String) async -> RAGResponse {
        Log.error(" Error during response processing: \(error)")
        let recoveredText = llmResponse.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let recoveredResponse = recoveredText.isEmpty ? "Error processing response" : recoveredText
        let recoveredStructuredAnswer: StructuredAnswer
        if recoveredText.isEmpty {
            recoveredStructuredAnswer = StructuredAnswer.refusal(
                reason: "Error processing response",
                missing: ["The response could not be processed safely."],
                topScore: generationRetrievedChunks.first?.similarityScore ?? 0,
                loops: 1,
                retrievedChunks: generationRetrievedChunks
            )
        } else {
            recoveredStructuredAnswer = StructuredAnswer.from(
                response: recoveredResponse,
                retrievedChunks: generationRetrievedChunks,
                answerIntent: answerIntent,
                verificationResult: nil,
                structuredGeneration: llmResponse.structuredRAGGeneration,
                loops: reasoningTraceForMetadata?.count ?? 1
            )
        }

        let recoveredDisplayText = resolvedDisplayResponse(
            fallback: recoveredResponse,
            structuredAnswer: recoveredStructuredAnswer
        )

        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: generationTime,
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: llmResponse.modelName ?? llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId,
            executionReceipt: llmResponse.executionReceipt
        )

        let response = RAGResponse(
            queryId: ragQueryValue.id,
            retrievedChunks: generationRetrievedChunks,
            generatedResponse: recoveredDisplayText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: ["Response processing recovery: \(error.localizedDescription)"],
            structuredAnswer: recoveredStructuredAnswer
        )
        return await finalizeResponse(
            query: question,
            containerId: selectedId,
            containerName: selectedName,
            response: response
        )
    }

    /// Step ND: answers a question to a library with no documents, abstaining for actions and grounded-only mode and otherwise by direct chat.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func answerWithoutDocuments(allowUngroundedFallback: Bool, asksForAnAction: Bool, question: String, ragQueryValue: RAGQuery, retrievalConfig: RetrievalConfig, embeddingProviderId: String, selectedId: UUID, selectedName: String, inferenceConfig: InferenceConfig, pipelineStartTime: Date) async throws -> RAGResponse {
        // No documents case. An action's question never gets the direct chat below (5.7): its answer goes back
        // as "Ask My Documents" or "Ask a Library", and one written by the model alone would read as if it came
        // from the library. `reliabilityModeEnabled` is on by default, so through the first 5.7 builds an
        // action asking an empty library got the model's own answer; `ShortcutsActionTests` found it on
        // 2026-10-19 ("Direct chat mode" in the trace).
        if !allowUngroundedFallback || asksForAnAction {
            let response = await makeGroundedAbstainResponse(
                question: question,
                ragQuery: ragQueryValue,
                retrievedChunks: [],
                retrievalTime: 0,
                retrievalConfig: retrievalConfig,
                embeddingProviderId: embeddingProviderId,
                reason: "This library has no documents yet.",
                gatingDecision: "no_documents"
            )
            return await finalizeResponse(
                query: question,
                containerId: selectedId,
                containerName: selectedName,
                response: response
            )
        }

        // Direct LLM chat without documents
        Log.info("ℹ️  No documents loaded - using direct LLM chat mode", category: .pipeline)
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
        TelemetryCenter.emit(
            .system,
            title: "Direct chat mode",
            metadata: [
                "model": llmService.modelName,
                "container": selectedName,
                "containerId": selectedId.uuidString,
            ]
        )

        emitThinkingEvent(
            .planning,
            title: "Direct chat",
            detail: "No documents in \(selectedName)"
        )

        Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)

        // Pipeline Trace: No documents - direct LLM
        Log.pipelineStep(
            "D", title: "Direct LLM (No Docs)",
            details: [
                ("reason", "empty library"),
                ("container", selectedName),
            ])

        let generationStartTime = Date()

        emitThinkingEvent(
            .generation,
            title: "Generating answer",
            detail: llmService.modelName
        )
        // A library with no documents gives the library's tools nothing to find, so they are not handed to
        // the model here (5.7): their descriptions took part of the window, and a call could only come back
        // empty (found by the PostDesk session's code trace, 2026-10-21).
        var noDocumentsConfig = inferenceConfig
        noDocumentsConfig.disableTools = true
        let llmResponse = try await generateWithFallback(
            prompt: question,
            context: nil,  // No document context
            config: noDocumentsConfig,
            sourceChunks: []
        )

        let generationTime = Date().timeIntervalSince(generationStartTime)
        TelemetryCenter.emit(
            .generation,
            title: "Response generated",
            metadata: [
                "model": llmService.modelName,
                "tokens": "\(llmResponse.tokensGenerated)",
                "container": selectedName,
                "containerId": selectedId.uuidString,
            ],
            duration: generationTime
        )

        emitThinkingEvent(
            .generation,
            title: "Answer composed",
            detail: "\(llmResponse.tokensGenerated) tokens in \(String(format: "%.2f", generationTime))s"
        )

        Log.info("✓ Response generated", category: .llm)
        Log.info("  Model: \(llmService.modelName)", category: .llm)
        Log.info(
            "  Generation time: \(String(format: "%.2f", generationTime))s",
            category: .performance
        )
        Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
        Log.debug(
            "  Speed: \(String(format: "%.1f", llmResponse.tokensPerSecond ?? 0)) tokens/sec",
            category: .performance
        )

        let metadata = ResponseMetadata(
            timeToFirstToken: llmResponse.timeToFirstToken,
            totalGenerationTime: llmResponse.totalTime,
            tokensGenerated: llmResponse.tokensGenerated,
            tokensPerSecond: llmResponse.tokensPerSecond,
            modelUsed: llmResponse.modelName ?? llmService.modelName,  // Use actual execution location if available
            retrievalTime: 0,  // No retrieval in direct chat mode
            retrievalConfigSummary: retrievalConfig.summary,
            toolCallsMade: llmResponse.toolCallsMade,
            embeddingProvider: embeddingProviderId,
            executionReceipt: llmResponse.executionReceipt
        )

        let structuredAnswer = StructuredAnswer.from(
            response: llmResponse.text,
            retrievedChunks: [],
            answerIntent: answerIntent,
            verificationResult: nil,
            structuredGeneration: llmResponse.structuredRAGGeneration,
            loops: 1
        )
        let response = RAGResponse(
            queryId: ragQueryValue.id,
            retrievedChunks: [],  // No chunks in direct chat mode
            generatedResponse: resolvedDisplayResponse(
                fallback: llmResponse.text,
                structuredAnswer: structuredAnswer
            ),
            metadata: metadata,
            structuredAnswer: structuredAnswer
        )

        let totalTime = Date().timeIntervalSince(pipelineStartTime)
        Log.info(
            "✅ [RAGService] Direct chat complete in \(String(format: "%.2f", totalTime))s",
            category: .pipeline
        )
        TelemetryCenter.emit(
            .system,
            title: "Query complete",
            metadata: [
                "duration": String(format: "%.2f", totalTime),
                "mode": "direct",
                "container": selectedName,
                "containerId": selectedId.uuidString,
            ],
            duration: totalTime
        )

        return await finalizeResponse(
            query: question,
            containerId: selectedId,
            containerName: selectedName,
            response: response
        )
    }

    /// Step OC: runs the reliability fallback from the recovered passages when it applies, else logs the failure and rethrows (the outer catch body).
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func recoverFromQueryFailure(error: any Error, reliabilityModeEnabled: Bool, recoveryRetrievedChunks: [RetrievedChunk], question: String, effectiveTopK: Int, ragQuery: RAGQuery?, inferenceConfig: InferenceConfig, retrievalConfig: RetrievalConfig, embeddingProviderId: String, recoveryRetrievalTime: TimeInterval, selectedId: UUID, selectedName: String) async throws -> RAGResponse {
        let isContextOverflow = isContextOverflowError(error)
        let errorMessage = error.localizedDescription

        // NEW: Catch false-positive language detection errors
        let isLanguageError =
            errorMessage.contains("Apple Intelligence couldn't process this query")
            || errorMessage.contains("Unsupported language") || errorMessage.contains("context window")  // Catch overflow here too

        // Trigger Reliability Mode if enabled OR if we hit a language/context error
        if reliabilityModeEnabled || isLanguageError {
            await MainActor.run { lastError = nil }

            let reason = isLanguageError ? "Language detection/Context limit triggered fallback" : errorMessage
            Log.warning("[RAGService] 🛡️ Reliability fallback engaged: \(reason)", category: .pipeline)

            // If we have retrieved chunks, use them to generate a safe answer
            if !recoveryRetrievedChunks.isEmpty {
                let fallbackResponse = await buildReliabilityFallbackResponse(
                    question: question,
                    ragQuery: ragQuery ?? RAGQuery(query: question, topK: effectiveTopK),
                    inferenceConfig: inferenceConfig,
                    retrievalConfig: retrievalConfig,
                    embeddingProviderId: embeddingProviderId,
                    retrievedChunks: recoveryRetrievedChunks,
                    retrievalTime: recoveryRetrievalTime,
                    reason: "AI System Limit: Switching to Safe Mode"
                )

                return await finalizeResponse(
                    query: question,
                    containerId: selectedId,
                    containerName: selectedName,
                    response: fallbackResponse
                )
            }
        }

        Log.error(" [RAGService] Query execution failed: \(error.localizedDescription)", category: .pipeline)
        TelemetryCenter.emit(
            .system,
            severity: .error,
            title: "Query failed",
            metadata: [
                "error": error.localizedDescription,
                "model": activeModelName,
            ]
        )

        // Re-throw specific errors for UI handling
        if isContextOverflow {
            throw LLMError.contextWindowExceeded
        }
        throw error
    }

}
