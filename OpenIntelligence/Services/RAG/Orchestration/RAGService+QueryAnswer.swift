//
//  RAGService+QueryAnswer.swift
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
    /// Step 6 (start): logs the generation step, applies the adaptive cooldown and starts the generation clock.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func beginGenerationStep(contextWords: Int) async -> Date {
        // Step 6: Generate response using LLM with augmented context
        Log.section("Step 6: LLM Generation", level: .info, category: .pipeline)

        // Pipeline Trace: Step 6
        let llmModelName = llmService.modelName
        Log.pipelineStep(
            "6", title: "LLM Generation",
            details: [
                ("model", llmModelName),
                ("context", "\(contextWords)w"),
            ])

        // Apply thermal cooldown before heavy LLM generation if device is under pressure
        // This prevents throttling and improves generation quality on hot devices
        await AdaptivePipelineOptimizer.shared.applyCooldown()

        let generationStartTime = Date()
        return generationStartTime
    }

    /// Step 6 (citations): retries once for a cited answer when citations are required and missing.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func retryForMissingCitations(llmResponse: inout LLMResponse, requiresCitations: Bool, allowUngroundedFallback: Bool, selectedName: String, question: String, genConfig: InferenceConfig, usedOverflowRetry: Bool, generationContext: String, generationChunks: [DocumentChunk]) async -> (responseText: String, preserveStreamingResponse: Bool) {
        var responseText = llmResponse.text

        let preserveStreamingResponse = LLMStreamingContext.handler != nil
        if requiresCitations, !responseHasCitations(responseText) {
            let missingCitationDetail =
                (preserveStreamingResponse || allowUngroundedFallback)
                ? "Using best available answer"
                : "Retrying with strict citation requirement"
            emitThinkingEvent(
                .warning,
                title: "Missing citations",
                detail: missingCitationDetail
            )
            TelemetryCenter.emit(
                .generation,
                severity: .warning,
                title: "Missing citations",
                metadata: [
                    "model": llmService.modelName,
                    "container": selectedName,
                ]
            )
            if preserveStreamingResponse || allowUngroundedFallback {
                Log.warning(
                    "Missing citations; preserving streamed response",
                    category: .llm
                )
            } else {
                let retryPrompt =
                    question
                    + "\n\nYou must cite sources using bracket ids like [S1], [S2]. "
                    + "If you cannot support the answer with citations, respond exactly: "
                    + "\"Insufficient evidence in provided sources.\" "
                    + "Answer directly with no preamble."
                var retryConfig = genConfig
                retryConfig.temperature = min(retryConfig.temperature, 0.2)
                if usedOverflowRetry {
                    retryConfig.maxTokens = min(retryConfig.maxTokens, 1024)
                }
                if let retryResponse = try? await generateWithFallback(
                    prompt: retryPrompt,
                    context: generationContext,
                    config: retryConfig,
                    sourceChunks: generationChunks
                ) {
                    llmResponse = retryResponse
                    responseText = retryResponse.text
                }
            }
        }
        return (responseText: responseText, preserveStreamingResponse: preserveStreamingResponse)
    }

    /// Step 6 (integrity): normalizes malformed output and runs one grounded repair pass when needed.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func repairResponseIntegrity(responseText: inout String, question: String, answerIntent: AnswerIntent, genConfig: InferenceConfig, requiresCitations: Bool, generationContext: String, generationChunks: [DocumentChunk], llmResponse: inout LLMResponse) async {
        // Universal output integrity gate:
        // Detect malformed generation artifacts (placeholder lists, repetition loops,
        // dangling markdown) and attempt one grounded repair pass.
        var integrityIssues = responseIntegrityIssues(responseText)
        if !integrityIssues.isEmpty {
            Log.warning(
                "[RAG] Output integrity issues detected: \(integrityIssues.joined(separator: ", "))",
                category: .llm
            )
            emitThinkingEvent(
                .warning,
                title: "Output integrity repair",
                detail: "Detected malformed answer shape; repairing"
            )

            // Deterministic cleanup first (cheap, no extra model call)
            var cleanedResponse = normalizeMalformedResponseArtifacts(responseText)
            cleanedResponse = compactDegenerateResponse(
                cleanedResponse,
                question: question,
                answerIntent: answerIntent
            )
            let cleanedIssues = responseIntegrityIssues(cleanedResponse)

            // If still malformed, perform a grounded one-shot repair ONLY for non-repetition issues.
            // Repetition loops are handled better by deterministic compaction than another model pass.
            let shouldTryModelRepair =
                !cleanedIssues.isEmpty
                && cleanedIssues.contains { $0 != "dominant_repetition" }

            if shouldTryModelRepair {
                var repairConfig = genConfig
                repairConfig.temperature = min(repairConfig.temperature, 0.15)
                repairConfig.skipContinuation = true
                repairConfig.maxTokens = min(max(repairConfig.maxTokens, 192), 420)

                let repairPrompt = buildIntegrityRepairPrompt(
                    question: question,
                    issueLabels: cleanedIssues,
                    answerIntent: answerIntent,
                    requiresCitations: requiresCitations
                )

                if let repaired = try? await generateWithFallback(
                    prompt: repairPrompt,
                    context: generationContext,
                    config: repairConfig,
                    sourceChunks: generationChunks
                ) {
                    let candidate = compactDegenerateResponse(
                        normalizeMalformedResponseArtifacts(repaired.text),
                        question: question,
                        answerIntent: answerIntent
                    )
                    if isResponseIntegrityImproved(original: responseText, candidate: candidate) {
                        llmResponse = repaired
                        responseText = candidate
                        integrityIssues = responseIntegrityIssues(responseText)
                        Log.info("[RAG] Integrity repair succeeded", category: .llm)
                    } else {
                        Log.warning(
                            "[RAG] Integrity repair candidate rejected (no improvement)", category: .llm)
                        responseText = cleanedResponse
                        integrityIssues = cleanedIssues
                    }
                } else {
                    responseText = cleanedResponse
                    integrityIssues = cleanedIssues
                }
            } else {
                responseText = cleanedResponse
                integrityIssues = cleanedIssues
            }

            // Hard stop: if repetition still remains, deterministically compact once more
            // and accept that output rather than spinning another expensive model pass.
            if integrityIssues.contains("dominant_repetition") {
                let compacted = compactDegenerateResponse(
                    responseText,
                    question: question,
                    answerIntent: answerIntent
                )
                if isResponseIntegrityImproved(original: responseText, candidate: compacted) {
                    responseText = compacted
                    integrityIssues = responseIntegrityIssues(responseText)
                }
            }

            if !integrityIssues.isEmpty {
                Log.warning(
                    "[RAG] Residual integrity issues after repair: \(integrityIssues.joined(separator: ", "))",
                    category: .llm)
            }
        }
    }

    /// Step 6g (override): replaces the answer with the source-locked precision-lookup value when the model did not state it.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyPrecisionLookupOverride(answerIntentIsExtractive: Bool, question: String, answerIntent: AnswerIntent, generationRetrievedChunks: [RetrievedChunk], responseText: inout String) async -> Bool {
        var sourceLockedFinalResponse = false
        if answerIntentIsExtractive || isPrecisionValueQuery(question),
            let extractiveOverride = await highPrecisionLookupOverride(
                question: question,
                answerIntent: answerIntent,
                retrievedChunks: generationRetrievedChunks
            )
        {
            let normalizedLLM = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedOverride = extractiveOverride.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            // The model's answer stands when it already states the value the extractor found (5.7):
            // it can answer the rest of the question, and the gates check it. On 2026-10-19 "What is
            // the harbor lantern code, and where is it kept?" had its answer replaced by the
            // extractor's text, which began mid-word and left out where the code is kept.
            if Self.answerStates(value: extractiveOverride.value, in: normalizedLLM) {
                Log.info(
                    "[ExtractiveQA] Kept the model's answer: it states the extracted value \"\(extractiveOverride.value)\"",
                    category: .retrieval)
            } else {
                sourceLockedFinalResponse = true
                if normalizedLLM != normalizedOverride {
                    Log.info(
                        "[ExtractiveQA] Overriding lookup response with direct source extraction",
                        category: .retrieval)
                    responseText = normalizedOverride
                }
            }
        }
        return sourceLockedFinalResponse
    }

    /// Step 7: scores answer confidence and quality warnings.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func assessAnswerQuality(generationRetrievedChunks: [RetrievedChunk], engine: RAGEngine, question: String, auditTopSim: Float) async -> (confidenceScore: Float, qualityWarnings: [String]) {
        // Step 7: Calculate confidence score and quality warnings
        Log.section("Step 7: Quality Assessment", level: .info, category: .pipeline)
        HardwareTelemetryState.shared.reportRAGPipeline(stage: "Quality Assessment")

        // Pipeline Trace: Step 7
        Log.pipelineStep(
            "7", title: "Quality Assessment",
            details: [
                ("sources", "\(generationRetrievedChunks.count)")
            ])
        let totalDocsCount = await snapshotDocumentsCount()
        let (confidenceScore, qualityWarnings) = await engine.assessResponseQuality(
            chunks: generationRetrievedChunks,
            query: question,
            totalDocs: totalDocsCount,
            topScoreOverride: auditTopSim > 0 ? auditTopSim : nil  // Use actual reranked score
        )

        if !qualityWarnings.isEmpty {
            Log.warning("⚠️  Quality Warnings:", category: .pipeline)
            for warning in qualityWarnings {
                Log.warning("   • \(warning)", category: .pipeline)
            }
        }

        Log.info(
            "📊 Confidence Score: \(String(format: "%.1f", confidenceScore * 100))%",
            category: .pipeline
        )
        TelemetryCenter.emit(
            .system,
            title: "Response evaluated",
            metadata: [
                "confidence": String(format: "%.2f", confidenceScore)
            ]
        )
        return (confidenceScore: confidenceScore, qualityWarnings: qualityWarnings)
    }

    /// Step 7.5 (run): runs verification gates A-G against the answer and the evidence embeddings.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func verifyAnswerAgainstEvidence(question: String, answerIntent: AnswerIntent, qualityMode: RAGQualityMode, auditAvgTop5: Float, auditSecondSim: Float, auditTopSim: Float, responseText: String, queryEmbeddingService: EmbeddingService, generationRetrievedChunks: [RetrievedChunk], vdb: any VectorDatabase, verificationResult: inout RAGVerificationResult?, contextCandidates: [RetrievedChunk], queryEmbedding: [Float], llmResponse: LLMResponse, verificationTime: inout TimeInterval) async -> (confidencePolicy: QueryConfidencePolicy, verificationService: VerificationGateService) {
        Log.section("Step 7.5: Verification Gates", level: .info, category: .pipeline)

        let confidencePolicy = ConfidencePolicyService.policy(
            for: question,
            answerIntent: answerIntent,
            qualityMode: qualityMode
        )
        let verificationService = VerificationGateService(config: confidencePolicy.verificationConfig)

        let verificationStartTime = Date()
        // Use the TOP reranked scores from the pipeline (auditTopSim, auditSecondSim, etc.)
        // NOT the scores from generationRetrievedChunks which may be sibling chunks with discounted scores
        let topScores = [auditTopSim, auditSecondSim, auditAvgTop5].filter { $0 > 0 }

        // SEMANTIC GROUNDING: Embed the LLM response to check if its meaning
        // is actually grounded in source chunk embeddings. This is the primary
        // hallucination detector — catches fabricated content that string-matching
        // (number checks, keyword overlap) would miss.
        let responseEmbedding: [Float]?
        let responseForEmbedding = boundedVerificationResponseText(
            responseText,
            answerIntent: answerIntent
        )
        do {
            responseEmbedding = try await queryEmbeddingService.generateEmbedding(
                for: responseForEmbedding)
        } catch {
            Log.warning(
                "[RAG] Could not embed response for grounding check: \(error.localizedDescription)",
                category: .pipeline)
            responseEmbedding = nil
        }

        // Fetch ACTUAL chunk embeddings from the vector database mmap file.
        // BNNSVectorDatabase returns embedding: [] in search results to save memory,
        // so Gate E must load them explicitly for cosine similarity grounding checks.
        let chunkIDs = generationRetrievedChunks.map { $0.chunk.id }
        let chunkEmbeddings = await vdb.getEmbeddings(forChunkIDs: chunkIDs)
        let validChunkEmbeddings = chunkEmbeddings.filter { !$0.isEmpty }

        if validChunkEmbeddings.isEmpty && responseEmbedding != nil {
            Log.warning(
                "[RAG] Gate E: No chunk embeddings loaded — vector DB may not support getEmbeddings. Gate E will be skipped.",
                category: .pipeline)
        }

        verificationResult = await verificationService.verify(
            response: responseText,
            query: question,
            retrievedChunks: generationRetrievedChunks,
            topScores: topScores,
            allCandidateChunks: contextCandidates,
            responseEmbedding: responseEmbedding,
            queryEmbedding: queryEmbedding,
            chunkEmbeddings: validChunkEmbeddings.isEmpty ? nil : chunkEmbeddings,
            structuredClaims: llmResponse.structuredRAGGeneration?.claims
        )
        verificationTime = Date().timeIntervalSince(verificationStartTime)
        return (confidencePolicy: confidencePolicy, verificationService: verificationService)
    }

    /// Step 9 (source-only): checks an extractive answer against its sources when the Standard gates flagged it.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applySourceOnlyCheck(answerIntentIsExtractive: Bool, question: String, qualityMode: RAGQualityMode, verificationResult: RAGVerificationResult?, answerIntent: AnswerIntent, responseText: String, generationRetrievedChunks: [RetrievedChunk], sourceLockedFinalResponse: Bool, finalResponseText: inout String, structuredAnswer: inout StructuredAnswer, gatingSummary: inout String?, finalWarnings: inout [String], finalConfidenceScore: inout Float, confidenceScore: Float) async {
        #if canImport(FoundationModels)
            // Standard checks an extractive answer against its sources only when the
            // verification gates flagged it. The check is two sequential structured
            // model calls after the last word, and until 2026-09-23 it ran on every
            // extractive Standard answer; "what", "which" and "how many" questions
            // were all classified extractive that day. Measured on the macOS Debug
            // build, four such questions whose gates had passed finished 19.4, 37.6,
            // 58.3 and 163.8 seconds after their last streamed word (the 163.8 ended
            // in "exceeded the model's context size"), with a blinking cursor and a
            // locked composer throughout, and the check replaced none of the four
            // answers. A passing answer has already been through the nine verification
            // gates. Deep Think and Maximum are not skipped here; since 5.8 they, like every mode, skip
            // only where `sourceOnlyOutcomeIfNeeded` shows the check could not replace the answer.
            let sourceOnlyApplies = answerIntentIsExtractive || isPrecisionValueQuery(question)
            let standardGatesPassed = Self.standardSkipsSourceOnlyCheck(
                qualityMode: qualityMode,
                gatesPassed: verificationResult?.passed
            )
            if sourceOnlyApplies, standardGatesPassed {
                Log.info(
                    "[SourceOnly] Skipped — Standard answer passed the verification gates "
                        + "(confidence \(String(format: "%.2f", verificationResult?.overallConfidence ?? 0))). "
                        + "intent=\(answerIntent), answerChars=\(responseText.count)",
                    category: .llm
                )
            }
            if #available(iOS 26.0, *),
                sourceOnlyApplies,
                !standardGatesPassed,
                let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                    query: question,
                    candidateAnswer: responseText,
                    retrievedChunks: generationRetrievedChunks,
                    answerIntent: answerIntent,
                    verificationResult: verificationResult,
                    isSourceLocked: sourceLockedFinalResponse
                )
            {
                finalResponseText = sourceOnlyOutcome.finalAnswer
                structuredAnswer = sourceOnlyOutcome.structuredAnswer
                gatingSummary = appendedGatingDecision(
                    gatingSummary,
                    sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                )
                finalWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                if sourceOnlyOutcome.shouldAbstain,
                    let abstentionReason = sourceOnlyOutcome.abstentionReason
                {
                    finalWarnings.append(abstentionReason)
                }
                finalConfidenceScore =
                    sourceOnlyOutcome.shouldAbstain
                    ? min(confidenceScore, 0.35)
                    : min(confidenceScore, max(sourceOnlyOutcome.fidelityScore, 0.75))
            }
        #endif
    }

    /// Step 6 (prompt): writes the intent-specific system prompt and the temperature caps into the generation config.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func composeStandardGenerationConfig(inferenceConfig: InferenceConfig, includedChunks: [DocumentChunk], question: String, answerIntent: AnswerIntent, contextualDefinitionLookup: Bool, useEvidenceFirstMode: Bool, qualityModeTemperature: Float, retrievalConfig: RetrievalConfig) -> InferenceConfig {
        var genConfig = inferenceConfig

        // ═══════════════════════════════════════════════════════════════
        // Context Homogeneity Detection
        // ═══════════════════════════════════════════════════════════════
        // If retrieved chunks are >55% similar to each other (Jaccard),
        // the source content is repetitive (e.g., inspection reports with
        // repeated dates/entries). Inject synthesis-focused instructions
        // into the system prompt to prevent the LLM from enumerating
        // each chunk separately (which causes repetition loops).
        let contextIsHomogeneous = detectContextHomogeneity(chunks: includedChunks)

        // Set explicit system prompt for RAG to ensure comprehensive, ACCURATE answers
        // Keep concise to maximize context budget (every 100 chars = ~70 tokens)

        // Customize system prompt based on answer intent (AppleRAG §3)
        // BUDGET-CONSCIOUS: Every 100 chars ≈ 70 tokens. Keep prompts tight.
        let lowerQuestion = question.lowercased()
        let isBehavioralOutcomeQuery =
            lowerQuestion.contains("happens if")
            || lowerQuestion.contains("happens when")
            || lowerQuestion.contains("what does")
            || lowerQuestion.contains("what do")
            || lowerQuestion.contains("do when")

        let intentSpecificInstructions: String
        switch answerIntent {
        case .lookup, .tableLookup:
            // Detect count/enumeration queries that slipped through to lookup
            // (e.g., "how many quarts" — single-value with unit)
            let isCountQuery = lowerQuestion.contains("how many") || lowerQuestion.contains("how much")
            if isCountQuery {
                intentSpecificInstructions = """
                    State the exact count FIRST, then list only the directly relevant items by name.
                    Keep each bullet brief. Copy names, labels, and values VERBATIM from the excerpts.
                    Count carefully — only include items explicitly mentioned in the excerpts. Never duplicate items. Never invent items not in the source.
                    Use only the minimum citations needed for the count sentence or for bullets that come from different sources.
                    """
            } else if contextualDefinitionLookup {
                intentSpecificInstructions = """
                    Define the subject directly in the first sentence.
                    Then explain the most relevant grounded context or significance from the excerpts.
                    Use concise prose, but allow 2-4 sentences when the excerpts support a fuller explanation.
                    Do not collapse a research concept into a nearby product, delivery form, or adjacent therapy unless the excerpts explicitly equate them.
                    If the excerpts distinguish the subject from similar items, state that distinction clearly.
                    Use the minimum citations needed — usually one citation cluster at the end of a sentence or short paragraph.
                    """
            } else {
                intentSpecificInstructions = """
                    Answer only the exact question being asked.
                    Start with the direct answer in the first sentence.
                    If the excerpts support additional details that materially answer the question, include them instead of collapsing everything into a one-line reply.
                    Use concise prose by default, but allow 2-4 sentences when needed for a complete grounded answer.
                    Keep it to one short paragraph unless bullets materially improve clarity.
                    Copy numbers, units, and codes VERBATIM.
                    Use the minimum citations needed — usually one citation cluster at the end of the sentence or paragraph. Do not repeat citations after every clause or restated fact.
                    Many excerpts say similar things in different words — combine them into one cohesive explanation. Never repeat the same fact twice.
                    If the question assumes a mapping or condition that the excerpts contradict, correct the premise explicitly using the exact source mapping instead of accepting the user's wording.
                    """
            }
        case .procedure:
            if isBehavioralOutcomeQuery {
                intentSpecificInstructions = """
                    Answer with the direct outcome FIRST in 1-2 clear sentences. If excerpts include explicit steps, include only the relevant steps in source order.
                    Do NOT force a long numbered list when the question asks what happens.
                    """
            } else {
                intentSpecificInstructions = """
                    List relevant steps in source order. Number steps only when explicit ordered steps exist in the excerpts.
                    Include warnings and prerequisites when present in source text.
                    """
            }
        case .compare:
            intentSpecificInstructions = """
                Compare the options found. Use a structured format. Copy exact product codes and specs from excerpts.
                """
        case .summarize:
            // Detect enumeration queries routed here ("how many X are available")
            let isSummarizeEnumeration = lowerQuestion.contains("how many")
            if isSummarizeEnumeration {
                intentSpecificInstructions = """
                    The user asked for a COUNT and LIST. Follow these rules STRICTLY:
                    1. Count ONLY items explicitly named in the excerpts below.
                    2. List EVERY distinct item by name using bullets — copy names VERBATIM.
                    3. Include a brief description for each item when available.
                    4. State the count as "There are N [items]" where N is YOUR count of the bullets below it.
                    5. If the excerpts don't contain a complete list, say "The excerpts mention N of the following" — NEVER guess the total.
                    6. NEVER state a number larger than the items you actually list.
                    """
            } else {
                intentSpecificInstructions = """
                    Provide a comprehensive overview covering all major points. Organize by theme.
                    """
            }
        case .investigate, .compute:
            intentSpecificInstructions = """
                Synthesize across sources. Show reasoning and connections. Copy specific values VERBATIM.
                """
        case .findings:
            intentSpecificInstructions = """
                Summarize key findings, thesis, evidence, and methodology. Name researchers and contributions.
                """
        }

        genConfig.systemPrompt = """
            Answer using document excerpts [S1], [S2], etc.
            \(intentSpecificInstructions)
            Rules: Cite sources [S1]/[S2] using the minimum citations needed to support the answer. Copy values VERBATIM. Answer exactly what was asked; be complete for the request, not exhaustive. If the excerpts do not address the user's question, say so clearly — briefly state what the excerpts cover and that the requested topic is not in the documents. Do NOT fabricate answers from unrelated context. If the question is vague, interpret it from document topics.
            CRITICAL: NEVER invent numbers, measurements, or values. Use ONLY values that appear in the excerpts. If a specific value is not in the excerpts, state that clearly.
            ABBREVIATIONS: If an [Abbreviations] glossary appears in the context, use those EXACT definitions when expanding abbreviations. Never expand an abbreviation differently than the glossary defines it. Example: if glossary says "ED = Emotional Dysregulation", NEVER write "oppositional defiant disorder (ED)".
            Format: Write naturally and match format to the question. Use ### headers only for multi-topic answers or explicit summaries. Use **bold** sparingly for key terms only. Use bullets only for actual lists, sequential steps, or specifications the user asked to enumerate. Write prose paragraphs for direct explanations and factual lookups. Combine overlapping excerpts into unified sentences — never repeat the same fact. For direct factual questions, prefer concise prose over sections or lists, but include all materially supported details. When multiple grounded facts are needed, use 2-4 sentences rather than a one-line reply.
            \(contextIsHomogeneous ? "IMPORTANT: The source excerpts contain highly repetitive or redundant entries. SYNTHESIZE across all excerpts into a SINGLE unified answer. Do NOT list or enumerate each excerpt separately. Mention each unique fact, date, or value ONCE. Combine similar entries." : "")
            """

        // Evidence-First mode: cautious prompt for low retrieval confidence
        if useEvidenceFirstMode {
            genConfig.systemPrompt = """
                EVIDENCE-FIRST MODE (low confidence retrieval). Use ONLY excerpts [S1], [S2], etc.
                \(intentSpecificInstructions)
                Rules: Cite only the minimum supporting sources needed for each grounded point. Copy values VERBATIM. Answer exactly what was asked. Do NOT fill gaps with assumptions. NEVER invent numbers.
                ABBREVIATIONS: If an [Abbreviations] glossary appears, use those EXACT definitions. Never expand abbreviations differently.
                For procedures: preserve exact order, never omit steps, include feedback indicators.
                Format: Write naturally. Use ### headers only for multi-topic answers. Use **bold** sparingly for key terms only. Use bullets only for actual lists or sequential steps. Write prose paragraphs for explanations and direct factual answers. Merge overlapping excerpts into unified sentences. For direct factual questions, stay concise but include all materially supported details. Do not force a one-line answer when the evidence supports a fuller grounded explanation.
                \(contextIsHomogeneous ? "IMPORTANT: Excerpts contain repetitive entries. SYNTHESIZE into ONE answer. Mention each fact ONCE." : "")
                If the excerpts leave part of the question unanswered, end with one plain sentence saying what they do not cover. Do not name source ids in that sentence, and do not add a heading, a summary or a confidence note.
                """
            // Lower temperature for more conservative output
            genConfig.temperature = min(genConfig.temperature, 0.2)
            Log.info("[RAG] Using Evidence-First prompt (cautious mode)", category: .llm)
        }

        // Use adaptive mode's temperature
        genConfig.temperature = min(genConfig.temperature, qualityModeTemperature)

        // High Accuracy retrieval config overrides quality mode. By style, so the cap holds while the library
        // reads as High Precision in Library Settings (5.7).
        if retrievalConfig.style == .precise {
            genConfig.temperature = min(genConfig.temperature, 0.2)
        }
        return genConfig
    }

    /// Step 6 (output budget): caps maxTokens to the room left after the context and applies the procedural and trivial adjustments.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func capGenerationTokens(baseWindowTokens: Int, contextTokens: Int, promptOverheadTokens: Int, questionTokens: Int, globalSafetyFactor: Double, genConfig: inout InferenceConfig, isProceduralQuery: Bool, allowLargeContext: Bool, isTrivial: Bool) {
        let availableForOutput = max(
            128,
            Int(
                Double(baseWindowTokens - promptOverheadTokens - questionTokens - contextTokens)
                    * globalSafetyFactor)
        )
        if genConfig.maxTokens > availableForOutput {
            genConfig.maxTokens = availableForOutput
        }

        // For procedural queries, ensure adequate tokens to avoid continuation chains
        // Continuations increase hallucination risk as second pass "fills gaps" creatively
        if isProceduralQuery, genConfig.maxTokens < 600 {
            let boosted = min(availableForOutput, 600)
            if boosted > genConfig.maxTokens {
                Log.info(
                    "[RAG] Procedural query - boosting maxTokens \(genConfig.maxTokens) → \(boosted) to avoid continuations",
                    category: .llm)
                genConfig.maxTokens = boosted
            }
        }

        if isTrivial, !allowLargeContext {
            let capped = min(genConfig.maxTokens, 384)
            if capped != genConfig.maxTokens {
                Log.info(
                    "[RAG] Trivial query detected - limiting response to \(capped) tokens",
                    category: .llm
                )
            }
            genConfig.maxTokens = capped
        }
    }

    /// Step 6 (history): adds conversation history or memory to the prompt and decides whether citations are required.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func buildGenerationPrompt(selectedId: UUID, question: String, retrievalConfig: RetrievalConfig, qualityModeRequiresCitations: Bool) -> (promptForGeneration: String, requiresCitations: Bool) {
        // Inject conversational history to support follow-up questions
        // e.g. "What is it?" uses history to resolve "it"
        let history = chatHistory(for: selectedId)

        // Only drop the last message if it matches the current question (avoid duplicating)
        // or if we know for sure ChatScreen persisted it. Safest is to check content match.
        let lastMsg = history.last
        let dropsCurrent =
            lastMsg?.content.trimmingCharacters(in: .whitespacesAndNewlines)
            == question.trimmingCharacters(in: .whitespacesAndNewlines)

        let previousMessages =
            history
            .filter { $0.role != .system }
            .dropLast(dropsCurrent ? 1 : 0)
            .suffix(4)  // Keep last 4 turns (2 User, 2 Assistant)

        // Use ConversationMemoryService for enhanced context if enabled
        let useConversationMemory = settingsStore?.enableConversationMemory ?? true
        var historyContext = ""

        if #available(iOS 26.0, *), useConversationMemory {
            // Get intelligent memory context with summarization
            // DYNAMIC: Pass question for semantic relevance scoring and adaptive budgeting
            let memoryContext = ConversationMemoryService.shared.contextInjection(
                for: selectedId, query: question)
            if !memoryContext.isEmpty {
                historyContext = memoryContext + "\nCURRENT QUESTION: "
                Log.debug(
                    "[ConversationMemory] Injected memory context (\(memoryContext.count) chars)",
                    category: .retrieval)
            }
        }

        // Fallback to simple history if memory service didn't provide context
        if historyContext.isEmpty, !previousMessages.isEmpty {
            historyContext =
                "PREVIOUS CONVERSATION:\n"
                + previousMessages.map {
                    let role = $0.role == .user ? "User" : "Assistant"
                    // Truncate long history items to preserve token budget for RAG context
                    let content = $0.content.replacingOccurrences(of: "\n", with: " ")
                    let truncated = content.count > 300 ? String(content.prefix(300)) + "..." : content
                    return "\(role): \(truncated)"
                }.joined(separator: "\n") + "\n\nCURRENT QUESTION: "
        }

        let requiresCitations =
            retrievalConfig.requireExplicitCitations
            || qualityModeRequiresCitations
        // System prompt already contains citation and format instructions
        // Don't add conflicting instructions that cause overly brief responses
        let promptForGeneration: String = historyContext + question
        return (promptForGeneration: promptForGeneration, requiresCitations: requiresCitations)
    }

    /// Step 6 (chain gate): decides whether the developer-forced reasoning chain runs.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func decideReasoningChain(initialQueryProfile: QueryProfile, qualityMode: RAGQualityMode, useEvidenceFirstMode: Bool, isTrivial: Bool, bestRetrievalSim: Float, contextSize: Int, includedRetrievedChunks: [RetrievedChunk]) -> (useReasoningChain: Bool, standardComplexity: QueryComplexityResult, reasoningTraceForMetadata: [String]?) {
        // Track reasoning trace from chained sessions (for UI display)
        var reasoningTraceForMetadata: [String]? = nil

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // REASONING CHAIN: Developer override only in Standard pipeline.
        // Deep Think/Maximum use the agentic path (returned early at L4022).
        // This code path is only reachable when forceReasoningChain is ON,
        // which lets developers test multi-session reasoning from Standard mode.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let forceChain = settingsStore?.forceReasoningChain ?? false
        let standardComplexity = initialQueryProfile.reasoningComplexity
        let useReasoningChain: Bool = {
            // Only use for Apple Foundation Models (reasoning chain uses FM-specific features)
            guard llmService is AppleFoundationLLMService else { return false }

            // Standard stays single-pass unless a developer explicitly forces chaining.
            guard forceChain else { return false }
            guard qualityMode.canonical == .standard else { return false }

            Log.info("[RAG] Reasoning chain FORCED via settings", category: .pipeline)

            // Skip if evidence is weak (Evidence-First mode handles this)
            guard !useEvidenceFirstMode else { return false }

            // Skip trivial queries - they don't benefit from multi-session
            guard !isTrivial else { return false }

            guard standardComplexity.complexity != .simple else { return false }

            // Need some retrieval quality
            guard bestRetrievalSim >= 0.30 else { return false }

            // Need some context to benefit from chaining
            guard contextSize > 900 else { return false }

            // Need enough evidence to distribute across sessions
            guard includedRetrievedChunks.count >= 3 else { return false }

            return true
        }()
        return (useReasoningChain: useReasoningChain, standardComplexity: standardComplexity, reasoningTraceForMetadata: reasoningTraceForMetadata)
    }

    /// Step 6 (telemetry): measures the generation time and emits the 'Response generated' events.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func emitGenerationTelemetry(generationStartTime: Date, responseText: String, llmResponse: LLMResponse, selectedName: String, selectedId: UUID) -> (generationTime: TimeInterval, responseWordCount: Int) {
        let generationTime = Date().timeIntervalSince(generationStartTime)
        let responseWordCount = wordCount(of: responseText)
        TelemetryCenter.emit(
            .generation,
            title: "Response generated",
            metadata: [
                "model": llmService.modelName,
                "tokens": "\(llmResponse.tokensGenerated)",
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "words": "\(responseWordCount)",
                "characters": "\(responseText.count)",
            ],
            duration: generationTime
        )

        emitThinkingEvent(
            .generation,
            title: "Answer composed",
            detail: "\(llmResponse.tokensGenerated) tokens in \(String(format: "%.2f", generationTime))s"
        )
        return (generationTime: generationTime, responseWordCount: responseWordCount)
    }

    /// Step 6g (log): logs the model, timing, length and token rate of the generated answer.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func logGeneratedResponse(generationTime: TimeInterval, responseText: String, responseWordCount: Int, llmResponse: LLMResponse) {
        Log.info("✓ Response generated", category: .llm)
        Log.info("  Model: \(llmService.modelName)", category: .llm)
        Log.info(
            "  Generation time: \(String(format: "%.2f", generationTime))s",
            category: .performance
        )

        // Access response text safely
        Log.debug("  Response length: \(responseText.count) chars", category: .llm)
        Log.debug("  Words: \(responseWordCount)", category: .llm)

        if llmResponse.tokensGenerated > 0 {
            Log.debug("  Tokens: \(llmResponse.tokensGenerated)", category: .llm)
            if let tps = llmResponse.tokensPerSecond {
                Log.debug(
                    "  Speed: \(String(format: "%.1f", tps)) tokens/sec",
                    category: .performance
                )
            }
        }
    }

    /// Step 8: calibrates confidence and logs and emits the pipeline completion.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func calibrateConfidenceAndLogCompletion(pipelineStartTime: Date, question: String, answerIntent: AnswerIntent, qualityMode: RAGQualityMode, generationRetrievedChunks: [RetrievedChunk], verificationResult: RAGVerificationResult?, confidenceScore: Float, expansionTime: TimeInterval, embeddingTime: TimeInterval, retrievalTime: TimeInterval, rerankTime: TimeInterval, mmrTime: TimeInterval, verificationTime: TimeInterval, generationTime: TimeInterval, selectedName: String, selectedId: UUID) {
        // Step 8: Package results
        let pipelineTotalTime = Date().timeIntervalSince(pipelineStartTime)

        // Step 8.1: Calibrated Confidence (AppleRAG §7)
        // P(correct) = σ(α*s_max + β*m + γ*log(1+n_evidence) - δ)
        let confidencePolicy = ConfidencePolicyService.policy(
            for: question,
            answerIntent: answerIntent,
            qualityMode: qualityMode
        )
        let calibrationService = ConfidenceCalibrationService(
            params: confidencePolicy.calibrationParameters,
            abstentionThreshold: confidencePolicy.calibrationAbstentionThreshold,
            touchyThreshold: confidencePolicy.calibrationTouchyThreshold
        )
        let calibratedConfidence = calibrationService.calibrate(
            chunks: generationRetrievedChunks,
            verification: verificationResult,
            isTouchyQuery: confidencePolicy.isTouchyQuery
        )
        Log.info(
            "📊 Calibrated confidence: \(String(format: "%.1f", calibratedConfidence.probability * 100))% (\(calibratedConfidence.level.rawValue))",
            category: .pipeline
        )

        // Emit calibrated confidence thinking event
        emitThinkingEvent(
            .confidence,
            title: "Confidence: \(calibratedConfidence.level.rawValue)",
            detail: "\(String(format: "%.0f", calibratedConfidence.probability * 100))% P(correct)"
        )

        // Pipeline Trace: Completion summary
        Log.pipelineComplete(
            totalDuration: pipelineTotalTime,
            chunksRetrieved: generationRetrievedChunks.count,
            tokensUsed: nil,
            confidence: Double(confidenceScore)
        )

        Log.box(
            "ENHANCED PIPELINE COMPLETE ✓",
            level: .info,
            category: .pipeline,
            content: [
                "Total time: \(String(format: "%.2f", pipelineTotalTime))s",
                "  - Query Expansion: \(String(format: "%.0f", expansionTime * 1000))ms",
                "  - Embedding: \(String(format: "%.0f", embeddingTime * 1000))ms",
                "  - Hybrid Retrieval: \(String(format: "%.0f", retrievalTime * 1000))ms",
                "  - Re-ranking: \(String(format: "%.0f", rerankTime * 1000))ms",
                "  - MMR Diversification: \(String(format: "%.0f", mmrTime * 1000))ms",
                "  - Quality Assessment: <1ms",
                "  - Verification Gates: \(String(format: "%.0f", verificationTime * 1000))ms",
                "  - Generation: \(String(format: "%.2f", generationTime))s",
            ]
        )
        TelemetryCenter.emit(
            .system,
            title: "Query complete",
            metadata: [
                "duration": String(format: "%.2f", pipelineTotalTime),
                "chunks": "\(generationRetrievedChunks.count)",
                "container": selectedName,
                "containerId": selectedId.uuidString,
            ],
            duration: pipelineTotalTime
        )
    }

    /// Step 9 (gating): builds the gating summary, final warnings and the structured answer.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func summarizeGatingAndWarnings(acceptanceOverride: Bool, lenient: Bool, verificationResult: RAGVerificationResult?, qualityWarnings: [String], responseText: String, confidenceScore: Float, generationRetrievedChunks: [RetrievedChunk], answerIntent: AnswerIntent, llmResponse: LLMResponse, reasoningTraceForMetadata: [String]?, allowUngroundedFallback: Bool) -> (finalResponseText: String, structuredAnswer: StructuredAnswer, gatingSummary: String?, finalWarnings: [String], finalConfidenceScore: Float) {
        // Step 9: Create response metadata
        var gatingSummary: String? =
            acceptanceOverride
            ? "acceptance_override" : lenient ? "lenient" : nil

        // Append verification result to gating summary (only if gates were run)
        if let vResult = verificationResult {
            if vResult.passed {
                let verifySummary = "verified:\(String(format: "%.0f", vResult.overallConfidence * 100))%"
                gatingSummary = gatingSummary.map { "\($0),\(verifySummary)" } ?? verifySummary
            } else {
                let failedGates = vResult.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(
                    separator: "+")
                let verifySummary = "unverified:\(failedGates)"
                gatingSummary = gatingSummary.map { "\($0),\(verifySummary)" } ?? verifySummary
            }
        } else {
            // Verification gates were skipped
            gatingSummary = gatingSummary.map { "\($0),verification_skipped" } ?? "verification_skipped"
        }

        // Include verification warnings in quality warnings (only if gates were run)
        var finalWarnings = qualityWarnings
        if let vResult = verificationResult, !vResult.passed {
            for gateResult in vResult.gateResults where !gateResult.passed {
                finalWarnings.append("Verification \(gateResult.gate.rawValue): \(gateResult.details)")
            }
        }

        // Generate structured answer for rich UI rendering (AppleRAG §6)
        var finalResponseText = responseText
        var finalConfidenceScore = confidenceScore
        var structuredAnswer = StructuredAnswer.from(
            response: responseText,
            retrievedChunks: generationRetrievedChunks,
            answerIntent: answerIntent,
            verificationResult: verificationResult,
            structuredGeneration: llmResponse.structuredRAGGeneration,
            loops: reasoningTraceForMetadata?.count ?? 1,
            allowUngroundedFallback: allowUngroundedFallback
        )
        return (finalResponseText: finalResponseText, structuredAnswer: structuredAnswer, gatingSummary: gatingSummary, finalWarnings: finalWarnings, finalConfidenceScore: finalConfidenceScore)
    }

    /// Step 9 (response): builds the response metadata and the RAGResponse and logs the total time.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func buildStandardResponse(llmResponse: LLMResponse, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, gatingSummary: String?, embeddingProviderId: String, qualityMode: RAGQualityMode, question: String, reasoningTraceForMetadata: [String]?, runtimeContext: QueryRuntimeContext, generationContext: String, finalResponseText: String, structuredAnswer: StructuredAnswer, ragQueryValue: RAGQuery, generationRetrievedChunks: [RetrievedChunk], finalConfidenceScore: Float, finalWarnings: [String], pipelineStartTime: Date) -> RAGResponse {
        let metadata = ResponseMetadata(
            timeToFirstToken: llmResponse.timeToFirstToken,
            totalGenerationTime: llmResponse.totalTime,
            tokensGenerated: llmResponse.tokensGenerated,
            tokensPerSecond: llmResponse.tokensPerSecond,
            modelUsed: llmResponse.modelName ?? llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            gatingDecision: gatingSummary,
            toolCallsMade: llmResponse.toolCallsMade,
            embeddingProvider: embeddingProviderId,
            usedAgenticMode: false,  // Single-pass mode
            qualityModeName: qualityMode.displayName,
            originalQuery: question,  // For "Go Deeper" re-query
            reasoningTrace: reasoningTraceForMetadata,  // Chained session insights
            executionRoute: llmResponse.executionReceipt.map { receipt in
                ResponseMetadata.ExecutionRoute(
                    path: receipt.completedTarget == .privateCloudCompute
                        ? "Private Cloud Compute"
                        : "On-Device",
                    reason: receipt.summary,
                    policyApplied: receipt.policyVersion,
                    emoji: receipt.completedTarget == .privateCloudCompute ? "☁️" : "📱"
                )
            } ?? runtimeContext.executionRoute,
            tokenBudget: ResponseMetadata.TokenBudget(
                totalLimit: runtimeContext.tokenBudget.totalLimit,
                systemPrompt: runtimeContext.tokenBudget.systemPrompt,
                retrievedContext: FoundationModelTokenBudget.estimateTokens(
                    for: generationContext,
                    isAppleFMOnDevice: runtimeContext.inferenceConfig.executionContext == .onDeviceOnly),
                generation: llmResponse.tokensGenerated,
                remaining: runtimeContext.tokenBudget.totalLimit - runtimeContext.tokenBudget.systemPrompt
                    - FoundationModelTokenBudget.estimateTokens(
                        for: generationContext,
                        isAppleFMOnDevice: runtimeContext.inferenceConfig.executionContext == .onDeviceOnly)
                    - llmResponse.tokensGenerated
            ),
            executionReceipt: llmResponse.executionReceipt
        )

        let displayResponseText = resolvedDisplayResponse(
            fallback: finalResponseText,
            structuredAnswer: structuredAnswer
        )

        // Log structured answer summary
        Log.debug(
            "[StructuredAnswer] type=\(structuredAnswer.answerType.rawValue), claims=\(structuredAnswer.claims.count), evidence=\(structuredAnswer.evidence.count), gaps=\(structuredAnswer.missing.count)",
            category: .pipeline
        )

        let response = RAGResponse(
            queryId: ragQueryValue.id,
            retrievedChunks: generationRetrievedChunks,
            generatedResponse: displayResponseText,
            metadata: metadata,
            confidenceScore: finalConfidenceScore,
            qualityWarnings: finalWarnings,
            structuredAnswer: structuredAnswer
        )

        let totalTime = Date().timeIntervalSince(pipelineStartTime)
        Log.info(
            "✅ Enhanced RAG pipeline complete in \(String(format: "%.2f", totalTime))s",
            category: .pipeline
        )
        return response
    }

}
