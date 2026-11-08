//
//  RAGService+Generation.swift
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

extension RAGService {
    // MARK: - Direct Chat Fallback Helper

    /// Build a grounded-only abstain response when evidence is insufficient.
    func makeGroundedAbstainResponse(
        question _: String,
        ragQuery: RAGQuery,
        retrievedChunks: [RetrievedChunk],
        retrievalTime: TimeInterval,
        retrievalConfig: RetrievalConfig,
        embeddingProviderId: String,
        reason: String,
        gatingDecision: String
    ) async -> RAGResponse {
        Log.info("ℹ️  Grounded-only abstain: \(gatingDecision)", category: .retrieval)

        let responseText = """
            I want to stay grounded in your library, but I don't have enough evidence to answer that reliably.

            \(reason)

            Try:
            • Add or select a library with relevant documents.
            • Ask about a specific document title or section.
            • Include keywords that appear in your sources.
            """

        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: 0,
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            gatingDecision: gatingDecision,
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId
        )

        let structuredAnswer = StructuredAnswer.refusal(
            reason: responseText,
            missing: [reason],
            topScore: retrievedChunks.first?.similarityScore ?? 0,
            loops: 1,
            retrievedChunks: retrievedChunks
        )

        return RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: retrievedChunks,
            generatedResponse: responseText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: ["Grounded-only: \(reason)"],
            structuredAnswer: structuredAnswer
        )
    }

    /// Reliability-first fallback: return a best-effort answer instead of surfacing errors.
    func buildReliabilityFallbackResponse(
        question: String,
        ragQuery: RAGQuery,
        inferenceConfig: InferenceConfig,
        retrievalConfig: RetrievalConfig,
        embeddingProviderId: String,
        retrievedChunks: [RetrievedChunk],
        retrievalTime: TimeInterval,
        reason: String
    ) async -> RAGResponse {
        Log.warning("[RAG] Reliability fallback engaged: \(reason)", category: .pipeline)
        var warnings = ["Reliability fallback: \(reason)"]
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)

        if let extractiveOverride = await highPrecisionLookupOverrideAnswer(
            question: question,
            answerIntent: answerIntent,
            retrievedChunks: retrievedChunks
        ) {
            let structuredAnswer = StructuredAnswer.from(
                response: extractiveOverride,
                retrievedChunks: retrievedChunks,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1,
                allowUngroundedFallback: true
            )
            return RAGResponse(
                queryId: ragQuery.id,
                retrievedChunks: retrievedChunks,
                generatedResponse: resolvedDisplayResponse(
                    fallback: extractiveOverride,
                    structuredAnswer: structuredAnswer
                ),
                metadata: ResponseMetadata(
                    timeToFirstToken: nil,
                    totalGenerationTime: 0,
                    tokensGenerated: 0,
                    tokensPerSecond: nil,
                    modelUsed: "Direct Source Extraction",
                    retrievalTime: retrievalTime,
                    retrievalConfigSummary: retrievalConfig.summary,
                    gatingDecision: "reliability_extractive_override",
                    toolCallsMade: 0,
                    embeddingProvider: embeddingProviderId
                ),
                confidenceScore: max(retrievedChunks.first?.similarityScore ?? 0.0, 0.85),
                qualityWarnings: warnings,
                structuredAnswer: structuredAnswer
            )
        }

        let targetChunkCount = min(6, retrievedChunks.count)
        let maxContextChars = min(3600, max(1200, 700 * max(1, targetChunkCount)))
        let (fallbackContext, usedRetrieved) = await buildEvidencePackContext(
            question: question,
            candidates: retrievedChunks,
            maxContextChars: maxContextChars,
            maxChunks: targetChunkCount,
            maxCharsPerChunk: 800
        )
        Log.info(
            "[RAG] Reliability context: \(fallbackContext.count) chars, \(usedRetrieved.count) chunks",
            category: .pipeline
        )
        let sourceChunks = usedRetrieved.map { $0.chunk }

        var fallbackConfig = inferenceConfig
        fallbackConfig.executionContext = .onDeviceOnly
        fallbackConfig.allowPrivateCloudCompute = false
        fallbackConfig.maxTokens = min(fallbackConfig.maxTokens, 512)
        fallbackConfig.temperature = min(fallbackConfig.temperature, 0.4)

        let fallbackPrompt =
            question
            + "\n\nAnswer using any available excerpts. If evidence is thin, say so and summarize what is available. Cite sources like [S1]."

        do {
            let llmResponse = try await generateWithFallback(
                prompt: fallbackPrompt,
                context: fallbackContext.isEmpty ? nil : fallbackContext,
                config: fallbackConfig,
                sourceChunks: sourceChunks
            )

            let topScores = usedRetrieved.map(\.similarityScore).filter { $0 > 0 }
            let verificationResult: RAGVerificationResult?
            if !usedRetrieved.isEmpty, !topScores.isEmpty {
                let fallbackQualityMode = await MainActor.run {
                    self.settingsStore?.ragQualityMode ?? .standard
                }
                let confidencePolicy = ConfidencePolicyService.policy(
                    for: question,
                    answerIntent: answerIntent,
                    qualityMode: fallbackQualityMode
                )
                let verificationService = VerificationGateService(config: confidencePolicy.verificationConfig)

                let preferredContainerId = await MainActor.run {
                    self.currentQueryContainerId ?? self.containerService.activeContainerId
                }
                let embeddingContext = await resolveEmbeddingContext(preferredContainerId: preferredContainerId)
                let verificationContainer = await containerForId(embeddingContext.containerId)

                let responseEmbedding: [Float]?
                let queryEmbedding: [Float]?
                let responseForEmbedding = boundedVerificationResponseText(
                    llmResponse.text,
                    answerIntent: answerIntent
                )
                let translatedResponseForEmbedding = await translatedQueryForEmbedding(
                    responseForEmbedding,
                    container: verificationContainer
                )
                let translatedQuestionForEmbedding = await translatedQueryForEmbedding(
                    question,
                    container: verificationContainer
                )

                do {
                    responseEmbedding = try await embeddingContext.service.generateEmbedding(
                        for: translatedResponseForEmbedding.text)
                } catch {
                    Log.warning(
                        "[RAG] Reliability fallback could not embed response for grounding check: \(error.localizedDescription)",
                        category: .pipeline)
                    responseEmbedding = nil
                }

                do {
                    queryEmbedding = try await embeddingContext.service.generateEmbedding(
                        for: translatedQuestionForEmbedding.text)
                } catch {
                    Log.warning(
                        "[RAG] Reliability fallback could not embed query for grounding check: \(error.localizedDescription)",
                        category: .pipeline)
                    queryEmbedding = nil
                }

                let fallbackDB = await dbFor(embeddingContext.containerId)
                let chunkIDs = usedRetrieved.map { $0.chunk.id }
                let chunkEmbeddings = await fallbackDB.getEmbeddings(forChunkIDs: chunkIDs)
                let validChunkEmbeddings = chunkEmbeddings.filter { !$0.isEmpty }

                if validChunkEmbeddings.isEmpty && responseEmbedding != nil {
                    Log.warning(
                        "[RAG] Reliability fallback grounding skipped: no chunk embeddings loaded for fallback evidence",
                        category: .pipeline)
                }

                verificationResult = await verificationService.verify(
                    response: llmResponse.text,
                    query: question,
                    retrievedChunks: usedRetrieved,
                    topScores: topScores,
                    allCandidateChunks: retrievedChunks,
                    responseEmbedding: responseEmbedding,
                    queryEmbedding: queryEmbedding,
                    chunkEmbeddings: validChunkEmbeddings.isEmpty ? nil : chunkEmbeddings,
                    structuredClaims: llmResponse.structuredRAGGeneration?.claims
                )
            } else {
                verificationResult = nil
            }

            if let verificationResult, !verificationResult.passed {
                for gateResult in verificationResult.gateResults where !gateResult.passed {
                    warnings.append(
                        "Reliability fallback verification \(gateResult.gate.rawValue): \(gateResult.details)")
                }
            }

            let rejectingGates: Set<VerificationGate> = [
                .retrievalConfidence,
                .evidenceCoverage,
                .numericSanity,
                .semanticGrounding,
                .quoteFaithfulness,
            ]
            let shouldUseExtractiveFallback =
                verificationResult?.failedGates.contains {
                    rejectingGates.contains($0)
                } ?? false

            if shouldUseExtractiveFallback {
                warnings.append("Best-effort synthesis failed verification; showing excerpts instead.")
                Log.warning(
                    "[RAG] Reliability fallback answer failed verification — using extractive fallback",
                    category: .pipeline)
            } else {
                let metadata = ResponseMetadata(
                    timeToFirstToken: llmResponse.timeToFirstToken,
                    totalGenerationTime: llmResponse.totalTime,
                    tokensGenerated: llmResponse.tokensGenerated,
                    tokensPerSecond: llmResponse.tokensPerSecond,
                    modelUsed: llmResponse.modelName ?? llmService.modelName,
                    retrievalTime: retrievalTime,
                    retrievalConfigSummary: retrievalConfig.summary,
                    gatingDecision: "reliability_fallback",
                    toolCallsMade: llmResponse.toolCallsMade,
                    embeddingProvider: embeddingProviderId,
                    executionReceipt: llmResponse.executionReceipt
                )
                let structuredAnswer = StructuredAnswer.from(
                    response: llmResponse.text,
                    retrievedChunks: usedRetrieved,
                    answerIntent: answerIntent,
                    verificationResult: verificationResult,
                    structuredGeneration: llmResponse.structuredRAGGeneration,
                    loops: 1,
                    allowUngroundedFallback: true
                )
                return RAGResponse(
                    queryId: ragQuery.id,
                    retrievedChunks: usedRetrieved,
                    generatedResponse: resolvedDisplayResponse(
                        fallback: llmResponse.text,
                        structuredAnswer: structuredAnswer
                    ),
                    metadata: metadata,
                    confidenceScore: verificationResult?.overallConfidence ?? 0.0,
                    qualityWarnings: warnings,
                    structuredAnswer: structuredAnswer
                )
            }
        } catch {
            Log.error(
                "[RAG] Reliability fallback LLM also failed: \(error.localizedDescription) — falling through to extractive Path B",
                category: .pipeline)
        }

        let terms = extractQueryTerms(question)
        let snippetBullets = usedRetrieved.prefix(6).enumerated().compactMap { idx, retrieved -> String? in
            let sectionLabel = retrieved.chunk.metadata.sectionTitle.flatMap { $0.isEmpty ? nil : "**\($0)**: " } ?? ""
            let sourceName = retrieved.sourceDocument.isEmpty ? "Document" : retrieved.sourceDocument
            let snippet = Self.tidiedExcerpt(
                extractSnippet(
                    from: retrieved.chunk.content,
                    queryTerms: terms,
                    maxChars: 500
                )
            )
            guard !snippet.isEmpty else { return nil }
            return "• \(sectionLabel)\(snippet) [S\(idx + 1): \(sourceName)]"
        }
        // Both texts name the real reason when the model cannot run on this device (5.7).
        let capabilities = Self.checkDeviceCapabilities()
        let responseText: String
        if snippetBullets.isEmpty {
            responseText =
                capabilities.supportsFoundationModels
                ? "I can't reach the model right now, but your documents are still available. Please try again in a moment."
                : AppleIntelligenceCopy.chatMessage(for: capabilities.foundationModelUnavailability)
        } else {
            let closing = AppleIntelligenceCopy.excerptClosing(
                for: capabilities.foundationModelUnavailability, isAvailable: capabilities.supportsFoundationModels)
            VerificationJournal.record(
                "answer.excerpts",
                ["modelAvailable": "\(capabilities.supportsFoundationModels)",
                    "reason": capabilities.foundationModelUnavailability.map { "\($0)" } ?? "none",
                    "bullets": "\(snippetBullets.count)", "markup": "\(Self.excerptMarkupCount(snippetBullets))"])
            responseText = """
                Here are the most relevant excerpts from your documents:

                \(snippetBullets.joined(separator: "\n\n"))

                \(closing)
                """
        }

        let metadata = ResponseMetadata(
            timeToFirstToken: nil,
            totalGenerationTime: 0,
            tokensGenerated: 0,
            tokensPerSecond: nil,
            modelUsed: llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            // An answer of excerpts alone: no model wrote it and no check ran, so it reads Not
            // Checked. Through 5.6 it carried "reliability_fallback", which reads Partially Verified,
            // the label of a best-effort answer that was checked (5.7).
            gatingDecision: "excerpts_only",
            toolCallsMade: 0,
            embeddingProvider: embeddingProviderId
        )

        return RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: usedRetrieved,
            generatedResponse: responseText,
            metadata: metadata,
            confidenceScore: 0.0,
            qualityWarnings: warnings + ["Extractive fallback"],
            structuredAnswer: StructuredAnswer.from(
                response: responseText,
                retrievedChunks: usedRetrieved,
                answerIntent: answerIntent,
                verificationResult: nil,
                loops: 1
            )
        )
    }

    /// Generate a direct LLM response without document context.
    /// Used as a graceful fallback when retrieval returns no results or documents are unavailable.
    func generateDirectChatResponse(
        question: String,
        ragQuery: RAGQuery,
        inferenceConfig: InferenceConfig,
        pipelineStartTime: Date,
        retrievalTime: TimeInterval,
        fallbackNote: String? = nil
    ) async throws -> RAGResponse {
        Log.info("ℹ️  Falling back to direct LLM chat mode", category: .pipeline)
        let answerIntent = QueryEnhancementService().classifyAnswerIntent(question)
        let retrievalConfig = await MainActor.run {
            self.containerService.activeContainer?.retrievalConfig ?? .default
        }
        TelemetryCenter.emit(
            .system,
            title: "Direct chat mode",
            metadata: ["model": llmService.modelName]
        )

        Log.section("Direct LLM Generation (No RAG)", level: .info, category: .pipeline)
        let generationStartTime = Date()

        let llmResponse = try await generateWithFallback(
            prompt: question,
            context: nil,  // No document context
            config: inferenceConfig,
            sourceChunks: []
        )

        let generationTime = Date().timeIntervalSince(generationStartTime)
        TelemetryCenter.emit(
            .generation,
            title: "Response generated",
            metadata: [
                "model": llmService.modelName,
                "tokens": "\(llmResponse.tokensGenerated)",
            ],
            duration: generationTime
        )

        Log.info("✓ Response generated", category: .llm)
        Log.info("  Model: \(llmService.modelName)", category: .llm)
        Log.info(
            "  Generation time: \(String(format: "%.2f", generationTime))s", category: .performance
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
            modelUsed: llmResponse.modelName ?? llmService.modelName,
            retrievalTime: retrievalTime,
            retrievalConfigSummary: retrievalConfig.summary,
            toolCallsMade: llmResponse.toolCallsMade,
            embeddingProvider: nil,  // No embedding used in direct chat fallback
            executionReceipt: llmResponse.executionReceipt
        )

        var warnings: [String] = []
        if let note = fallbackNote { warnings.append(note) }

        let structuredAnswer = StructuredAnswer.from(
            response: llmResponse.text,
            retrievedChunks: [],
            answerIntent: answerIntent,
            verificationResult: nil,
            structuredGeneration: llmResponse.structuredRAGGeneration,
            loops: 1
        )
        let response = RAGResponse(
            queryId: ragQuery.id,
            retrievedChunks: [],
            generatedResponse: resolvedDisplayResponse(
                fallback: llmResponse.text,
                structuredAnswer: structuredAnswer
            ),
            metadata: metadata,
            confidenceScore: 1.0,
            qualityWarnings: warnings,
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
            ],
            duration: totalTime
        )

        return response
    }

    func isContextOverflowError(_ error: Error) -> Bool {
        // The type first: an error Apple throws keeps its type on the paths that do not map it.
        if ModelErrorClassifier.kind(of: error) == .contextOverflow { return true }
        let message = error.localizedDescription.lowercased()

        // Standard context overflow indicators
        if message.contains("context"), message.contains("window") { return true }
        if message.contains("context")
            && (message.contains("exceed") || message.contains("exceeded"))
        {
            return true
        }
        if message.contains("token"), message.contains("limit") { return true }
        if message.contains("4096"), message.contains("token") { return true }

        // PCC-related failures that indicate we should fall back to on-device with smaller context
        // These occur when the system expected to use PCC (65K tokens) but couldn't,
        // and the context we sent is too large for on-device (4096 tokens)
        if message.contains("private cloud compute") && message.contains("unavailable") { return true }
        if message.contains("pcc") && (message.contains("unavailable") || message.contains("required")) { return true }
        if message.contains("cloud") && message.contains("unavailable") { return true }

        return false
    }

    static let citationRegex = try? NSRegularExpression(pattern: "\\[S\\d+\\]")
    /// Matches lines that consist ONLY of a number + period (empty numbered list items).
    /// Uses multiline mode ((?m)) so ^ and $ anchor to line boundaries.
    /// Previous pattern `\b\d+\.\s*(\.)?(?=\s|$)` falsely matched decimal numbers
    /// at sentence boundaries in health/numeric data (e.g. "avg 71.6" → "71." matched),
    /// triggering unnecessary integrity repair cycles (+3-4s per query).
    private static let emptyListItemRegex = try? NSRegularExpression(pattern: #"(?m)^\s*\d+\.\s*\.?\s*$"#)
    private static let malformedInlineListRunRegex = try? NSRegularExpression(pattern: #"(?:\b\d+\.\s*\.\s*){2,}"#)
    private static let danglingMarkdownRegex = try? NSRegularExpression(pattern: #"\*\*[A-Za-z][A-Za-z\s]{0,30}$"#)

    func responseHasCitations(_ text: String) -> Bool {
        guard let regex = Self.citationRegex else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    // ═══════════════════════════════════════════════════════════════════════
    // MARK: - Context Homogeneity Detection
    // ═══════════════════════════════════════════════════════════════════════
    /// Detects whether retrieved chunks are highly repetitive/homogeneous.
    /// Uses pairwise Jaccard word similarity with O(n) sampling for large sets.
    /// Returns `true` if chunks are homogeneous (>55% avg similarity) —
    /// triggers synthesis-focused system prompt to prevent LLM enumeration loops.
    ///
    /// Theory: Inspection reports, repeated forms, and log files produce near-
    /// identical chunks (same dates, headers, boilerplate). If the LLM sees
    /// 8 chunks all saying "02/23/2024 inspection passed", it enumerates them
    /// 8 times. Detecting this BEFORE generation lets us inject a synthesis
    /// directive: "mention each fact ONCE."
    nonisolated func detectContextHomogeneity(chunks: [DocumentChunk]) -> Bool {
        guard chunks.count >= 3 else { return false }

        // Build word sets for each chunk (lowercased, alpha-only, min 3 chars)
        let wordSets: [Set<String>] = chunks.map { chunk in
            Set(
                chunk.content.lowercased()
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
                    .filter { $0.count >= 3 }
            )
        }

        // Pairwise Jaccard similarity with sampling for large chunk sets.
        // Full pairwise is O(n²) — for >10 chunks, sample up to 30 random pairs.
        var totalSimilarity: Double = 0
        var pairCount = 0
        var highPairCount = 0  // pairs with >0.60 similarity

        let n = wordSets.count
        if n <= 10 {
            // Full pairwise comparison
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let intersection = wordSets[i].intersection(wordSets[j]).count
                    let union = wordSets[i].union(wordSets[j]).count
                    guard union > 0 else { continue }
                    let jaccard = Double(intersection) / Double(union)
                    totalSimilarity += jaccard
                    pairCount += 1
                    if jaccard > 0.60 { highPairCount += 1 }
                }
            }
        } else {
            // Sampled comparison: sequential neighbors + random pairs
            // (1) Adjacent pairs (capture local repetition)
            for i in 0..<(n - 1) {
                let intersection = wordSets[i].intersection(wordSets[i + 1]).count
                let union = wordSets[i].union(wordSets[i + 1]).count
                guard union > 0 else { continue }
                let jaccard = Double(intersection) / Double(union)
                totalSimilarity += jaccard
                pairCount += 1
                if jaccard > 0.60 { highPairCount += 1 }
            }
            // (2) Strided pairs for coverage across distant chunks
            let step = max(2, n / 6)
            for i in Swift.stride(from: 0, to: n - step, by: step) {
                let j = i + step
                let intersection = wordSets[i].intersection(wordSets[j]).count
                let union = wordSets[i].union(wordSets[j]).count
                guard union > 0 else { continue }
                let jaccard = Double(intersection) / Double(union)
                totalSimilarity += jaccard
                pairCount += 1
                if jaccard > 0.60 { highPairCount += 1 }
            }
        }

        guard pairCount > 0 else { return false }

        let avgSimilarity = totalSimilarity / Double(pairCount)

        // Dual threshold: average >0.55 OR >50% of pairs are highly similar
        let isHomogeneous = avgSimilarity > 0.55 || Double(highPairCount) / Double(pairCount) > 0.50

        if isHomogeneous {
            Log.info(
                "[RAG] Context homogeneity detected: avg Jaccard=\(String(format: "%.2f", avgSimilarity)), high pairs=\(highPairCount)/\(pairCount) — injecting synthesis prompt",
                category: .retrieval)
        }

        return isHomogeneous
    }

    func responseIntegrityIssues(_ text: String) -> [String] {
        var issues: [String] = []
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        if let regex = Self.emptyListItemRegex {
            let matches = regex.matches(in: text, options: [], range: range)
            if matches.count >= 3 {
                issues.append("empty_numbered_items")
            }
        }

        if let regex = Self.malformedInlineListRunRegex,
            regex.firstMatch(in: text, options: [], range: range) != nil
        {
            issues.append("inline_placeholder_list")
        }

        if let regex = Self.danglingMarkdownRegex,
            regex.firstMatch(in: text, options: [], range: range) != nil
        {
            issues.append("dangling_markdown")
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 1: Sentence-level repetition dominance detector
        // ═══════════════════════════════════════════════════════════════
        let sentences = text.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 20 }

        if sentences.count >= 4 {
            var counts: [String: Int] = [:]
            for sentence in sentences {
                let key =
                    sentence
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                    .split(separator: " ")
                    .joined(separator: " ")
                counts[key, default: 0] += 1
            }
            if let dominant = counts.values.max(), Double(dominant) / Double(sentences.count) >= 0.45, dominant >= 3 {
                issues.append("dominant_repetition")
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 2: Intra-sentence / phrase-level repetition detector
        // ═══════════════════════════════════════════════════════════════
        // Catches "02/23/2024, 02/23/2024, 02/23/2024..." within a single bullet
        let commaSegments = text.components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { $0.count >= 4 && $0.count <= 40 }
        if commaSegments.count >= 6 {
            var segFreq: [String: Int] = [:]
            for seg in commaSegments {
                let key = seg.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                guard !key.isEmpty else { continue }
                segFreq[key, default: 0] += 1
            }
            if let topCount = segFreq.values.max(),
                topCount >= 4,
                Double(topCount) / Double(commaSegments.count) >= 0.35
            {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 3: N-gram entropy — information-theoretic quality gate
        // ═══════════════════════════════════════════════════════════════
        // Calculates Shannon entropy of word bigrams. Low entropy = degenerate
        // repetition regardless of surface pattern. This catches ALL forms of
        // repetition universally — including patterns we haven't hard-coded for.
        //
        // Theory: English prose has bigram entropy ~4-6 bits.
        // Repetitive text drops <2.0 bits. Threshold: 2.0 bits.
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if words.count >= 30 {
            var bigramCounts: [String: Int] = [:]
            var totalBigrams = 0
            for i in 0..<(words.count - 1) {
                let bigram = "\(words[i]) \(words[i + 1])"
                bigramCounts[bigram, default: 0] += 1
                totalBigrams += 1
            }

            if totalBigrams > 0 {
                var entropy: Double = 0.0
                let total = Double(totalBigrams)
                for (_, count) in bigramCounts {
                    let p = Double(count) / total
                    if p > 0 {
                        entropy -= p * log2(p)
                    }
                }

                // Very short responses naturally have lower entropy, scale threshold
                let entropyThreshold: Double = words.count < 60 ? 1.5 : 2.0

                if entropy < entropyThreshold {
                    if !issues.contains("dominant_repetition") {
                        issues.append("dominant_repetition")
                    }
                    issues.append("low_entropy")
                    Log.debug(
                        "[IntegrityCheck] Low bigram entropy: \(String(format: "%.2f", entropy)) bits (threshold: \(entropyThreshold))",
                        category: .llm)
                }
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 4: Unique word ratio — redundancy proxy
        // ═══════════════════════════════════════════════════════════════
        // High-quality prose has ~40-70% unique words. Repetitive text drops <25%.
        // This is a compression-ratio proxy: if gzip would compress 4:1, it's junk.
        if words.count >= 20 {
            let uniqueWords = Set(words)
            let uniqueRatio = Double(uniqueWords.count) / Double(words.count)
            if uniqueRatio < 0.20 {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
                issues.append("low_lexical_diversity")
                Log.debug(
                    "[IntegrityCheck] Low unique word ratio: \(String(format: "%.1f%%", uniqueRatio * 100)) (\(uniqueWords.count)/\(words.count))",
                    category: .llm)
            }
        }

        // ═══════════════════════════════════════════════════════════════
        // LAYER 5: Sliding window substring repetition
        // ═══════════════════════════════════════════════════════════════
        // Catches non-delimited repetition: "the datadata datadata" etc.
        // Uses a sliding window of 3-word sequences.
        if words.count >= 20 {
            var trigramCounts: [String: Int] = [:]
            for i in 0..<(words.count - 2) {
                let trigram = "\(words[i]) \(words[i + 1]) \(words[i + 2])"
                trigramCounts[trigram, default: 0] += 1
            }
            let totalTrigrams = words.count - 2
            if let topTrigram = trigramCounts.values.max(),
                topTrigram >= 5,
                Double(topTrigram) / Double(totalTrigrams) > 0.20
            {
                if !issues.contains("dominant_repetition") {
                    issues.append("dominant_repetition")
                }
            }
        }

        return issues
    }

    func normalizeMalformedResponseArtifacts(_ text: String) -> String {
        var output = text

        // Collapse intra-sentence phrase repetition FIRST (before sentence-level dedup)
        // This handles "02/23/2024, 02/23/2024, 02/23/2024..." within a single bullet
        output = collapseIntraLineRepetition(output)

        // Remove standalone empty numbered lines such as "2." or "2. ."
        let lines = output.components(separatedBy: .newlines)
        let filteredLines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return true }
            return trimmed.range(of: #"^\d+\.\s*(\.)?$"#, options: .regularExpression) == nil
        }
        output = filteredLines.joined(separator: "\n")

        output = output.replacingOccurrences(
            of: #"(?:\b\d+\.\s*\.\s*){2,}"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\*\*[A-Za-z][A-Za-z\s]{0,30}$"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)

        var trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed.removeFirst()
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return trimmed
    }

    func buildIntegrityRepairPrompt(
        question: String,
        issueLabels: [String],
        answerIntent: AnswerIntent,
        requiresCitations: Bool
    ) -> String {
        let formatHint: String =
            switch answerIntent {
            case .procedure:
                "Answer with direct outcome first. Use numbered steps only if complete explicit steps exist in excerpts."
            case .lookup, .tableLookup, .compute:
                "Answer with the specific value first, then 1-2 short support sentences. Keep under 120 words."
            case .compare:
                "Answer in concise compare format with only grounded differences, but keep the material distinctions and caveats from the source."
            case .summarize, .investigate, .findings:
                "Repair the answer in clear paragraphs. Preserve the important sections, supporting details, and grounded caveats. Do not collapse it into a brief summary unless the original text was mostly repetitive."
            }

        let citationHint =
            requiresCitations
            ? "Include citations like [S1], [S2] for factual claims when available in excerpts."
            : "Citations optional."

        let issueHint = issueLabels.joined(separator: ", ")

        return """
            Produce a clean, grounded final answer for the question.
            Constraints:
            - Use ONLY facts present in the provided context excerpts.
            - Fix these output issues: \(issueHint)
            - Remove repetition, placeholder numbering, and malformed fragments.
            - Do not add new facts.
            - Preserve material details and answer scope when they are already grounded; repair formatting instead of rewriting to the shortest possible summary.
            - \(formatHint)
            - \(citationHint)
            - Write in detailed prose with complete sentences. Use ### section headers and **bold** sparingly for key terms only.
            - Use bullet points only for actual sequential steps or specification values.
            - Separate paragraphs and sections with blank lines for readability.

            QUESTION:
            \(question)
            """
    }

    func compactDegenerateResponse(
        _ text: String,
        question: String,
        answerIntent: AnswerIntent
    ) -> String {
        let normalized = normalizeMalformedResponseArtifacts(text)
        let questionTerms = Set(
            question.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        )

        let sentenceRegex = try? NSRegularExpression(pattern: #"[^.!?\n]+[.!?]?"#)
        guard let sentenceRegex else { return normalized }

        let fullRange = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        let matches = sentenceRegex.matches(in: normalized, options: [], range: fullRange)
        guard !matches.isEmpty else { return normalized }

        struct Candidate {
            let text: String
            let key: String
            let score: Int
            let order: Int
        }

        var candidates: [Candidate] = []
        candidates.reserveCapacity(matches.count)

        for (idx, match) in matches.enumerated() {
            guard let range = Range(match.range, in: normalized) else { continue }
            let sentence = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard sentence.count >= 10 else { continue }

            let key =
                sentence
                .lowercased()
                .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: "", options: .regularExpression)
                .split(separator: " ")
                .joined(separator: " ")
            guard !key.isEmpty else { continue }

            let lower = sentence.lowercased()
            let overlap = questionTerms.reduce(0) { partial, term in
                partial + (lower.contains(term) ? 1 : 0)
            }
            let digitBoost = lower.rangeOfCharacter(from: .decimalDigits) != nil ? 1 : 0
            let score = overlap * 3 + digitBoost

            candidates.append(Candidate(text: sentence, key: key, score: score, order: idx))
        }

        guard !candidates.isEmpty else { return normalized }

        // Deduplicate by normalized sentence key, keeping best-scoring earliest occurrence.
        var byKey: [String: Candidate] = [:]
        for candidate in candidates {
            if let existing = byKey[candidate.key] {
                if candidate.score > existing.score
                    || (candidate.score == existing.score && candidate.order < existing.order)
                {
                    byKey[candidate.key] = candidate
                }
            } else {
                byKey[candidate.key] = candidate
            }
        }

        let ordered = byKey.values.sorted {
            if $0.score == $1.score { return $0.order < $1.order }
            return $0.score > $1.score
        }

        let maxSentences: Int
        let maxWords: Int
        switch answerIntent {
        case .lookup, .tableLookup:
            maxSentences = 5
            maxWords = 200
        case .procedure:
            maxSentences = 12
            maxWords = 600
        case .summarize, .investigate, .findings:
            maxSentences = 20
            maxWords = 1200
        default:
            maxSentences = 15
            maxWords = 800
        }

        var chosen: [String] = []
        var totalWords = 0
        for candidate in ordered.prefix(max(6, maxSentences * 2)) {
            let sentenceWords = candidate.text.split(separator: " ").count
            if totalWords + sentenceWords > maxWords, !chosen.isEmpty { continue }
            chosen.append(candidate.text)
            totalWords += sentenceWords
            if chosen.count >= maxSentences || totalWords >= maxWords { break }
        }

        guard !chosen.isEmpty else { return normalized }
        // Preserve paragraph structure: use double-newline between sentences
        // so downstream Markdown rendering can format them properly
        let compacted = chosen.joined(separator: "\n\n")
        return normalizeMalformedResponseArtifacts(compacted)
    }

    /// The verification gates for a Deep Think or Maximum answer, and the status string the badge
    /// reads (5.7): `verified:NN%` when they pass, `unverified:<gates>` when they don't, and
    /// `verification_skipped` when there is nothing to check. The same `VerificationGateService.verify`
    /// and confidence policy Standard uses, on the passages the reasoning ended with, with the
    /// answer's and the question's vectors and the passages' stored vectors for the grounding gate.
    func verifyAgenticAnswer(
        question: String,
        answer: String,
        chunks: [RetrievedChunk],
        containerId: UUID,
        answerIntent: AnswerIntent,
        qualityMode: RAGQualityMode
    ) async -> (summary: String, result: RAGVerificationResult?) {
        let trimmed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chunks.isEmpty else { return ("verification_skipped", nil) }

        let policy = ConfidencePolicyService.policy(for: question, answerIntent: answerIntent, qualityMode: qualityMode)
        let gates = VerificationGateService(config: policy.verificationConfig)
        let embeddingContext = await resolveEmbeddingContext(preferredContainerId: containerId)
        let responseEmbedding = try? await embeddingContext.service.generateEmbedding(
            for: boundedVerificationResponseText(trimmed, answerIntent: answerIntent))
        let queryEmbedding = try? await embeddingContext.service.generateEmbedding(for: question)
        let vdb = await dbFor(embeddingContext.containerId)
        let chunkEmbeddings = await vdb.getEmbeddings(forChunkIDs: chunks.map(\.chunk.id))
        let scores = chunks.map(\.similarityScore).sorted(by: >)
        let averageTopFive = scores.isEmpty ? 0 : scores.prefix(5).reduce(0, +) / Float(min(5, scores.count))
        let topScores = [scores.first ?? 0, scores.count > 1 ? scores[1] : 0, averageTopFive].filter { $0 > 0 }

        let result = await gates.verify(
            response: trimmed,
            query: question,
            retrievedChunks: chunks,
            topScores: topScores,
            allCandidateChunks: chunks,
            responseEmbedding: responseEmbedding,
            queryEmbedding: queryEmbedding,
            chunkEmbeddings: chunkEmbeddings.allSatisfy(\.isEmpty) ? nil : chunkEmbeddings,
            answerIntent: answerIntent)
        Log.info(
            "[RAGService] \(qualityMode.canonical == .maximum ? "Maximum" : "Deep Think") answer gates: "
                + (result.passed ? "passed" : "failed")
                + " (\(result.gateResults.map { "\($0.gate.rawValue):\($0.passed ? "pass" : "fail")" }.joined(separator: " ")))",
            category: .pipeline)
        return (Self.verificationSummary(for: result), result)
    }

    /// Fact Check for a Deep Think or Maximum answer (5.8, 2026-11-07): each claim its structured answer lists, checked
    /// on its own with Gate B's per-claim check (`VerificationGateService.claimVerdicts`), so the list shows a verdict
    /// for each claim instead of "Not Checked". Called after the displayed text is fixed; it makes no model call and
    /// decides no gate. The badge reads the verdicts the way Standard's does (`VerificationOutcome.from(gatingDecision:
    /// claims:)`): passing gates with no supported claim show Partial or Not supported, not Verified.
    func factCheckedAgenticAnswer(
        _ structuredAnswer: StructuredAnswer,
        answer: String,
        chunks: [RetrievedChunk],
        question: String,
        answerIntent: AnswerIntent,
        qualityMode: RAGQualityMode
    ) async -> StructuredAnswer {
        guard !structuredAnswer.claims.isEmpty, !chunks.isEmpty else { return structuredAnswer }
        let policy = ConfidencePolicyService.policy(for: question, answerIntent: answerIntent, qualityMode: qualityMode)
        let gates = VerificationGateService(config: policy.verificationConfig)
        let results = await gates.claimVerdicts(
            for: structuredAnswer.claims.map(\.claim), response: answer, chunks: chunks, query: question)
        return structuredAnswer.withClaimVerdicts(results)
    }

    /// The status string Standard writes for a verification result: `verified:NN%` or
    /// `unverified:<failed gates>`.
    nonisolated static func verificationSummary(for result: RAGVerificationResult) -> String {
        if result.passed {
            return "verified:\(String(format: "%.0f", result.overallConfidence * 100))%"
        }
        return "unverified:" + result.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }.joined(separator: "+")
    }

    func boundedVerificationResponseText(
        _ responseText: String,
        answerIntent: AnswerIntent
    ) -> String {
        let wordCap: Int =
            switch answerIntent {
            case .lookup, .tableLookup:
                140
            case .procedure:
                220
            default:
                220
            }

        let charCap = 1400
        let sentences =
            responseText
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var output: [String] = []
        var words = 0
        var chars = 0
        for sentence in sentences {
            let w = sentence.split(separator: " ").count
            let c = sentence.count
            if words + w > wordCap || chars + c > charCap, !output.isEmpty { break }
            output.append(sentence)
            words += w
            chars += c
        }

        let bounded = output.isEmpty ? String(responseText.prefix(charCap)) : output.joined(separator: ". ")
        return bounded.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isResponseIntegrityImproved(original: String, candidate: String) -> Bool {
        let originalIssues = responseIntegrityIssues(original)
        let candidateIssues = responseIntegrityIssues(candidate)
        let originalIssueSet = Set(originalIssues)
        let repetitionHeavyOriginal = !originalIssueSet.isDisjoint(with: [
            "dominant_repetition",
            "low_entropy",
            "low_lexical_diversity",
        ])

        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard candidate.count >= min(40, max(10, original.count / 6)) else { return false }

        if !repetitionHeavyOriginal,
            original.count >= 500,
            candidate.count * 100 < original.count * 45
        {
            Log.debug(
                "[IntegrityCheck] Rejecting lossy repair candidate (chars: \(candidate.count)/\(original.count))",
                category: .llm)
            return false
        }

        let originalWords = original.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        let candidateWords = candidate.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        if !repetitionHeavyOriginal,
            originalWords >= 100,
            candidateWords * 100 < originalWords * 40
        {
            Log.debug(
                "[IntegrityCheck] Rejecting lossy repair candidate (words: \(candidateWords)/\(originalWords))",
                category: .llm)
            return false
        }

        // Clear win: fewer issues
        if candidateIssues.count < originalIssues.count {
            return true
        }

        // If issue counts tie, use lexical diversity as tiebreaker.
        // Higher unique-word ratio = more informative, less repetitive.
        if candidateIssues.count == originalIssues.count {
            let origRatio = uniqueWordRatio(original)
            let candRatio = uniqueWordRatio(candidate)

            // Candidate has meaningfully better diversity (≥5% improvement)
            if candRatio > origRatio + 0.05 {
                return true
            }

            // Equal diversity: prefer shorter (more concise = synthesized better)
            let ratioDiff: Double = candRatio - origRatio
            if Swift.abs(ratioDiff) < 0.05, candidate.count <= original.count {
                return true
            }
        }

        return false
    }

    /// Fraction of unique words in text (0.0–1.0). Higher = more diverse/informative.
    private nonisolated func uniqueWordRatio(_ text: String) -> Double {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard words.count >= 5 else { return 1.0 }
        return Double(Set(words).count) / Double(words.count)
    }

    // MARK: - Post-Retrieval Model Routing

    func makePostRetrievalModelPlan(
        prompt: String,
        context: String,
        config: InferenceConfig,
        chunks: [RetrievedChunk],
        consentState: CloudConsentState,
        networkAvailable: Bool,
        requiresMultiDocumentSynthesis: Bool,
        /// True when the caller has real retrieved evidence but is passing it as
        /// an already-rendered `context` string rather than as `chunks` (the
        /// agentic reasoning steps do this). Without it the planner would read
        /// an empty `chunks` array as "no evidence" and abstain on work that had
        /// retrieved perfectly good sources.
        hasRenderedEvidence: Bool = false
    ) async -> (plan: ModelExecutionPlan, localBudget: ContextBudgetSnapshot) {
        // The strongest evidence in the set, not whatever sits in slot zero.
        //
        // By the time the planner sees these, the array has been through MMR,
        // cross-reference expansion, the spec sniper, corrective lexical/page
        // retrieval — which appends chunks carrying no vector score at all — and
        // finally Lost-in-the-Middle position reordering, which rearranges for
        // attention placement. `chunks.first` is therefore not the best chunk and
        // has no reason to be.
        //
        // Device log 2026-08-03: 21 chunks whose confidence gate reported
        // `top 1.16` were handed to the planner as `top score 0.01`.
        // `PostRetrievalEvidence.isSufficient` requires `topScore >= 0.20`, so the
        // planner abstained on excellent evidence, the reliability fallback
        // engaged, and the user got raw excerpts. This is the cause of the
        // abstentions instrumented in the previous release; the fix is to ask the
        // set for its maximum rather than its head.
        let topScore = chunks.map(\.similarityScore).max() ?? (hasRenderedEvidence ? 1.0 : 0)
        let meanScore =
            chunks.isEmpty
            ? (hasRenderedEvidence ? 1.0 : 0)
            : chunks.map(\.similarityScore).reduce(0, +) / Float(chunks.count)
        let estimatedEvidenceTokens = FoundationModelTokenBudget.estimateTokens(
            for: prompt + "\n" + context,
            isAppleFMOnDevice: true
        )
        let evidence = PostRetrievalEvidence(
            // Rendered-context callers report one logical evidence unit so the
            // planner's `chunkCount > 0` sufficiency test reflects reality.
            chunkCount: chunks.isEmpty && hasRenderedEvidence ? 1 : chunks.count,
            topScore: topScore,
            meanScore: meanScore,
            estimatedEvidenceTokens: estimatedEvidenceTokens,
            hasContradictions: false,
            requiresExactExtraction: false,
            requiresMultiDocumentSynthesis: requiresMultiDocumentSynthesis
        )

        // Foreground state, on every platform the app ships to.
        //
        // The `#else` branch hardcoded `true`, so on macOS this check did not exist. That is the
        // input `ModelExecutionPlanner` gates PCC on: it permits cloud only when
        // `isForegroundInteractive || consentGranted`. Hardcoding `true` means a Mac App Intent or
        // Shortcut running with the app backgrounded reported itself as foreground-interactive and
        // could reach Private Cloud Compute without the user present to answer the consent sheet,
        // which is the exact case the guard exists to prevent. iOS was covered; macOS was not.
        //
        // `NSApplication.isActive` is the AppKit equivalent of `UIApplication.applicationState ==
        // .active`. Both are main-actor state, hence the hop.
        #if canImport(UIKit)
            let isForegroundInteractive = await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
        #elseif canImport(AppKit)
            let isForegroundInteractive = await MainActor.run {
                NSApplication.shared.isActive
            }
        #else
            // No UI framework at all, so there is no foreground to be in. Fail closed and let
            // remembered consent be the only thing that authorises cloud, rather than assuming a user
            // is watching.
            let isForegroundInteractive = false
        #endif
        let transientConsentGranted = await MainActor.run {
            transientConsentGrants.contains(.applePCC)
        }
        // An action's question that can bring the app forward counts as one a person can be asked
        // about: the consent gate brings the app forward and shows the sheet before anything is sent
        // (`bringAppForwardForConsent`, 5.7). Without it, a question from Siri or Shortcuts with the
        // app in the background could only use Private Cloud Compute after consent remembered earlier.
        let canAskForConsent = isForegroundInteractive || bringAppForwardForConsent != nil

        let constraints = PreRetrievalConstraints(
            allowsPCC: config.allowPrivateCloudCompute && consentState != .denied,
            requiresOnDevice: config.executionContext == .onDeviceOnly,
            requiresPCC: config.executionContext == .cloudOnly,
            networkAvailable: networkAvailable,
            consentGranted: consentState == .allowed || transientConsentGranted,
            isForegroundInteractive: canAskForConsent,
            qualityMode: config.qualityMode.displayName
        )

        #if canImport(FoundationModels)
            if #available(iOS 26.0, macOS 26.0, *) {
                let capability = await LiveFoundationModelCapabilityProvider().snapshot()
                let instructions = config.systemPrompt ?? ""
                let localBudget = await FoundationModelTokenBudget.snapshot(
                    contextSize: capability.onDeviceContextSize,
                    instructions: instructions,
                    evidence: prompt + "\n" + context,
                    outputReserve: max(128, config.maxTokens),
                    schemaReserve: 200,
                    reasoningReserve: config.qualityMode.canonical == .standard ? 0 : 512
                )
                let pccBudget: ContextBudgetSnapshot?
                if let pccContextSize = capability.pccContextSize {
                    pccBudget = await FoundationModelTokenBudget.snapshot(
                        contextSize: pccContextSize,
                        instructions: instructions,
                        evidence: prompt + "\n" + context,
                        outputReserve: max(128, config.maxTokens),
                        schemaReserve: 200,
                        reasoningReserve: config.qualityMode.canonical == .standard ? 0 : 1024
                    )
                } else {
                    pccBudget = nil
                }
                let plan = ModelExecutionPlanner().makePlan(
                    constraints: constraints,
                    evidence: evidence,
                    localBudget: localBudget,
                    pccBudget: pccBudget,
                    capability: capability
                )
                return (plan, localBudget)
            }
        #endif

        let localBudget = ContextBudgetSnapshot(
            contextSize: 4096,
            instructions: FoundationModelTokenBudget.estimateTokens(
                for: config.systemPrompt ?? "",
                isAppleFMOnDevice: true
            ),
            tools: config.disableTools ? 0 : 1000,
            schema: 200,
            history: 0,
            evidence: estimatedEvidenceTokens,
            output: max(128, config.maxTokens),
            reasoning: 0,
            safety: 256,
            source: .conservativeFallback
        )
        let localCapability = FoundationModelCapabilitySnapshot(
            supportsOnDevice: true,
            onDeviceAvailable: true,
            onDeviceContextSize: localBudget.contextSize,
            supportsPCC: false,
            hasPCCEntitlement: false,
            pccAvailable: false,
            pccQuota: .unsupported,
            pccContextSize: nil,
            source: .conservativeFallback,
            unavailabilityReason: "Foundation Models PCC APIs unavailable"
        )
        return (
            ModelExecutionPlanner().makePlan(
                constraints: constraints,
                evidence: evidence,
                localBudget: localBudget,
                pccBudget: nil,
                capability: localCapability
            ),
            localBudget
        )
    }

    func renderCloudEvidenceEnvelope(_ envelope: CloudEvidenceEnvelope) -> String {
        envelope.evidence.enumerated().map { index, item in
            let page = item.pageNumber.map { " p. \($0)" } ?? ""
            return "[S\(index + 1)] \(item.documentName)\(page)\n\(item.text)"
        }.joined(separator: "\n\n---\n\n")
    }

    // MARK: - Apple Intelligence Feedback (iOS 26+)

    #if canImport(FoundationModels)
        /// Submit positive feedback for the last Apple Intelligence response
        /// This helps Apple improve model quality
        @available(iOS 26.0, *)
        func submitPositiveFeedback() {
            guard let fmService = _llmService as? AppleFoundationLLMService else {
                Log.debug("Feedback skipped: not using Apple Foundation Model", category: .llm)
                return
            }
            _ = fmService.submitPositiveFeedback()
            Log.info("✓ Positive feedback submitted to Apple Intelligence", category: .llm)
        }

        /// Submit negative feedback for the last Apple Intelligence response
        @available(iOS 26.0, *)
        func submitNegativeFeedback() {
            guard let fmService = _llmService as? AppleFoundationLLMService else {
                Log.debug("Feedback skipped: not using Apple Foundation Model", category: .llm)
                return
            }
            _ = fmService.submitNegativeFeedback()
            Log.info("✓ Negative feedback submitted to Apple Intelligence", category: .llm)
        }

        /// Check if feedback is available (using Apple Intelligence)
        var canSubmitFeedback: Bool {
            if #available(iOS 26.0, *) {
                return _llmService is AppleFoundationLLMService
            }
            return false
        }
    #endif

    // MARK: - Fallback-Aware Generation

    /// Try to generate with primary service, automatically falling back to configured fallbacks on failure
    func generateWithFallback(
        prompt: String,
        context: String?,
        config: InferenceConfig,
        sourceChunks: [DocumentChunk] = [],
        allowStructuredRAG: Bool = false,
        structuredRAGMode: StructuredRAGMode = .direct
    ) async throws -> LLMResponse {
        let upstreamHandler = LLMStreamingContext.handler

        func attempt(
            service: LLMService,
            overrideConfig: InferenceConfig? = nil,
            overrideContext: String? = nil,
            overrideSourceChunks: [DocumentChunk]? = nil
        ) async throws -> LLMResponse {
            let attemptStart = Date()
            let attemptConfig = overrideConfig ?? config
            let attemptContext = overrideContext ?? context
            let attemptSourceChunks = overrideSourceChunks ?? sourceChunks

            // ═══════════════════════════════════════════════════════════════
            // StreamCapture with LIVE repetition loop detection
            // ═══════════════════════════════════════════════════════════════
            // Monitors tokens as they arrive. If the same n-gram appears
            // >N times in a sliding window, sets a flag that the generation
            // task checks on each iteration — aborting generation mid-stream
            // instead of waiting for full output and cleaning up after.
            actor StreamCapture {
                private var captured = ""
                private var firstChunkTime: TimeInterval?

                // Repetition detection state
                private var recentTokens: [String] = []
                private var repetitionDetected = false
                private var cleanPrefixLength = 0  // chars before repetition started

                /// Sliding window size for repetition detection (in tokens/words)
                private let windowSize = 60

                func record(_ event: LLMStreamEvent, since start: Date) {
                    guard !event.text.isEmpty else { return }
                    if firstChunkTime == nil {
                        firstChunkTime = Date().timeIntervalSince(start)
                    }
                    let previousLength = captured.count
                    captured += event.text

                    // Don't keep checking after we've already flagged
                    guard !repetitionDetected else { return }

                    // Tokenize new content into words for n-gram analysis
                    let newWords = event.text.split(whereSeparator: { $0.isWhitespace || $0 == "," })
                        .map { String($0).lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
                        .filter { !$0.isEmpty }
                    recentTokens.append(contentsOf: newWords)

                    // Only check every 20 words (amortize cost)
                    guard recentTokens.count >= 40, recentTokens.count % 20 < newWords.count else { return }

                    // Keep a bounded window
                    if recentTokens.count > windowSize * 2 {
                        recentTokens = Array(recentTokens.suffix(windowSize * 2))
                    }

                    // Check for repeated n-grams (bigrams, trigrams, 4-grams)
                    for n in 2...4 {
                        guard recentTokens.count >= n * 4 else { continue }
                        let window = Array(recentTokens.suffix(windowSize))
                        guard window.count >= n * 4 else { continue }

                        var ngramCounts: [String: Int] = [:]
                        for i in 0...(window.count - n) {
                            let gram = window[i..<(i + n)].joined(separator: " ")
                            ngramCounts[gram, default: 0] += 1
                        }

                        // If any n-gram appears >30% of possible positions, it's a loop
                        let maxPositions = window.count - n + 1
                        if let (_, topCount) = ngramCounts.max(by: { $0.value < $1.value }),
                            topCount >= 6,
                            Double(topCount) / Double(maxPositions) > 0.30
                        {
                            repetitionDetected = true
                            cleanPrefixLength = previousLength
                            Log.warning(
                                "[StreamCapture] Live repetition loop detected after \(captured.count) chars (\(n)-gram repeated \(topCount)×)",
                                category: .llm)
                            return
                        }
                    }
                }

                func snapshot() -> (text: String, firstChunkTime: TimeInterval?) {
                    (captured, firstChunkTime)
                }

                func isRepetitionDetected() -> Bool {
                    repetitionDetected
                }

                /// Returns text up to where repetition started (the "clean" prefix)
                func cleanPrefix() -> String {
                    if repetitionDetected, cleanPrefixLength > 0 {
                        return String(captured.prefix(cleanPrefixLength))
                    }
                    return captured
                }
            }

            let streamCapture = StreamCapture()

            let capturingHandler: LLMStreamHandler = { [weak self] event in
                if let reasoning = event.reasoning, !reasoning.isEmpty {
                    Task { @MainActor [weak self] in
                        self?.emitThinkingEvent(.reasoning, title: "Model Reasoning", detail: reasoning)
                    }
                }
                await streamCapture.record(event, since: attemptStart)
                if let upstreamHandler {
                    await upstreamHandler(event)
                }
            }

            return try await LLMStreamingContext.$handler.withValue(capturingHandler) {
                do {
                    try await ensureCloudConsentIfNeeded(
                        service: service,
                        prompt: prompt,
                        context: attemptContext,
                        sourceChunks: attemptSourceChunks,
                        allowPrivateCloudCompute: attemptConfig.allowPrivateCloudCompute,
                        modelExecutionPlan: attemptConfig.modelExecutionPlan
                    )

                    let response: LLMResponse
                    if allowStructuredRAG,
                        #available(iOS 26.0, *),
                        let appleService = service as? AppleFoundationLLMService,
                        let attemptContext,
                        !attemptContext.isEmpty,
                        !attemptSourceChunks.isEmpty
                    {
                        let systemChars = (attemptConfig.systemPrompt ?? "").count
                        let estimatedInputTokens = FoundationModelTokenBudget.estimateTokens(
                            charsCount: attemptContext.count + prompt.count + systemChars + 180, isAppleFMOnDevice: true
                        )
                        let structuredSchemaTokens = structuredRAGMode == .reasoned ? 220 : 160
                        let structuredOutputReserve = min(max(attemptConfig.maxTokens, 180), 360)
                        let withinStructuredBudget =
                            estimatedInputTokens + structuredSchemaTokens + structuredOutputReserve <= 3600

                        if withinStructuredBudget {
                            let modeLabel = structuredRAGMode == .reasoned ? "reasoned" : "direct"
                            Log.info(
                                "[RAG] Using constrained structured answer generation (\(modeLabel))", category: .llm)
                            response = try await appleService.generateStructuredRAGAnswer(
                                prompt: prompt,
                                context: attemptContext,
                                config: attemptConfig,
                                sourceCount: attemptSourceChunks.count,
                                mode: structuredRAGMode
                            )
                        } else {
                            Log.debug(
                                "[RAG] Structured answer generation skipped due to token budget (~\(estimatedInputTokens) input tokens)",
                                category: .llm)
                            response = try await service.generate(
                                prompt: prompt,
                                context: attemptContext,
                                config: attemptConfig
                            )
                        }
                    } else {
                        response = try await service.generate(
                            prompt: prompt,
                            context: attemptContext,
                            config: attemptConfig
                        )
                    }

                    // ── Post-generation: check if StreamCapture detected a loop ──
                    if await streamCapture.isRepetitionDetected() {
                        Log.warning(
                            "[RAG] Streaming repetition detected — using clean prefix instead of full response",
                            category: .llm)
                        let cleanText = await streamCapture.cleanPrefix()
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        let (_, firstChunkTime) = await streamCapture.snapshot()

                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }

                        if cleanText.count >= 10 {
                            return LLMResponse(
                                text: cleanText,
                                tokensGenerated: cleanText.split(whereSeparator: { $0.isWhitespace }).count,
                                timeToFirstToken: response.timeToFirstToken ?? firstChunkTime,
                                totalTime: max(response.totalTime, Date().timeIntervalSince(attemptStart)),
                                modelName: response.modelName ?? service.modelName,
                                toolCallsMade: response.toolCallsMade,
                                structuredRAGGeneration: response.structuredRAGGeneration,
                                executionReceipt: response.executionReceipt
                            )
                        }
                        // If clean prefix is too short, fall through to normal response
                        // (integrity pipeline will catch it downstream)
                    }

                    let (captured, firstChunkTime) = await streamCapture.snapshot()

                    let trimmed = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let capturedTrimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty, !capturedTrimmed.isEmpty {
                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }
                        return LLMResponse(
                            text: capturedTrimmed,
                            tokensGenerated: capturedTrimmed.split(whereSeparator: { $0.isWhitespace }).count,
                            timeToFirstToken: response.timeToFirstToken ?? firstChunkTime,
                            totalTime: max(response.totalTime, Date().timeIntervalSince(attemptStart)),
                            modelName: response.modelName ?? service.modelName,
                            toolCallsMade: response.toolCallsMade,
                            structuredRAGGeneration: response.structuredRAGGeneration,
                            executionReceipt: response.executionReceipt
                        )
                    }

                    if LLMStreamingContext.handler != nil {
                        LLMStreamingContext.emit(text: "", isFinal: true)
                    }

                    return response
                } catch {
                    let (captured, firstChunkTime) = await streamCapture.snapshot()
                    let capturedTrimmed = captured.trimmingCharacters(in: .whitespacesAndNewlines)
                    if capturedTrimmed.count >= 10 {
                        // If we already streamed a meaningful partial answer, do not replace it
                        // with a fallback provider. Lowered from 24→10 to salvage more partial output.
                        Log.warning(
                            "\(service.modelName) failed after streaming partial output; returning partial response",
                            category: .llm
                        )
                        if LLMStreamingContext.handler != nil {
                            LLMStreamingContext.emit(text: "", isFinal: true)
                        }
                        let partialReceipt = attemptConfig.modelExecutionPlan.map { plan in
                            ModelExecutionReceipt(
                                planID: plan.id,
                                policyVersion: plan.policyVersion,
                                intendedTarget: plan.synthesisTarget,
                                attempts: [
                                    ModelExecutionAttempt(
                                        target: plan.synthesisTarget,
                                        startedAt: attemptStart,
                                        result: .partial,
                                        failureCode: "partial_stream"
                                    )
                                ],
                                actualTarget: plan.synthesisTarget,
                                completedTarget: plan.synthesisTarget,
                                pccQuotaAtPlanning: plan.pccQuotaAtPlanning
                            )
                        }
                        return LLMResponse(
                            text: capturedTrimmed,
                            tokensGenerated: capturedTrimmed.split(whereSeparator: { $0.isWhitespace }).count,
                            timeToFirstToken: firstChunkTime,
                            totalTime: Date().timeIntervalSince(attemptStart),
                            modelName: service.modelName,
                            toolCallsMade: 0,
                            executionReceipt: partialReceipt
                        )
                    }
                    throw error
                }
            }
        }

        let primaryAttemptStartedAt = Date()
        do {
            return try await attempt(service: _llmService)
        } catch let primaryError {
            let errorDesc = primaryError.localizedDescription

            // PCC failures fall back only when no meaningful text was streamed.
            // `attempt` returns partial output instead of throwing once streaming
            // has begun, preventing mixed PCC/local responses.
            if let plan = config.modelExecutionPlan,
                plan.synthesisTarget == .privateCloudCompute,
                plan.fallback.target == .onDevice
            {
                var localConfig = config
                localConfig.executionContext = .onDeviceOnly
                localConfig.allowPrivateCloudCompute = false
                let localContext = context.map { String($0.prefix(8_500)) }
                let localChunks = Array(sourceChunks.prefix(8))
                do {
                    // A rate-limited fallback waits as the main ladder does (5.8): in the background for the app
                    // to come back, in front 2, 5 and 12 seconds; before, one refusal threw the PCC error.
                    var localAttempt = 0
                    let localResponse: LLMResponse
                    while true {
                        do {
                            localResponse = try await attempt(
                                service: _llmService,
                                overrideConfig: localConfig,
                                overrideContext: localContext,
                                overrideSourceChunks: localChunks
                            )
                            break
                        } catch {
                            let delays = [2, 5, 12]
                            guard ModelErrorClassifier.kind(of: error) == .rateLimited, localAttempt < delays.count
                            else { throw error }
                            if await Self.waitWhileAppIsInBackground() < 1 {
                                try? await Task.sleep(for: .seconds(delays[localAttempt]))
                            }
                            if Task.isCancelled { throw CancellationError() }
                            localAttempt += 1
                        }
                    }
                    let failedCode =
                        errorDesc.lowercased().contains("quota")
                        ? "pcc_quota"
                        : "pcc_generation"
                    let localAttempts =
                        localResponse.executionReceipt?.attempts ?? [
                            ModelExecutionAttempt(
                                target: .onDevice,
                                startedAt: Date(),
                                result: .succeeded
                            )
                        ]
                    let receipt = ModelExecutionReceipt(
                        planID: plan.id,
                        policyVersion: plan.policyVersion,
                        intendedTarget: .privateCloudCompute,
                        attempts: [
                            ModelExecutionAttempt(
                                target: .privateCloudCompute,
                                startedAt: primaryAttemptStartedAt,
                                result: .failed,
                                failureCode: failedCode
                            )
                        ] + localAttempts,
                        actualTarget: .privateCloudCompute,
                        completedTarget: .onDevice,
                        fallbackReason: errorDesc.lowercased().contains("quota")
                            ? .pccQuotaReached
                            : .fallback,
                        pccQuotaAtPlanning: plan.pccQuotaAtPlanning,
                        verificationPassed: localResponse.executionReceipt?.verificationPassed
                    )
                    Log.warning(
                        "[ModelRouter] PCC failed before streaming → completed on-device fallback for plan \(plan.id)",
                        category: .llm
                    )
                    return LLMResponse(
                        text: localResponse.text,
                        tokensGenerated: localResponse.tokensGenerated,
                        timeToFirstToken: localResponse.timeToFirstToken,
                        totalTime: localResponse.totalTime,
                        modelName: localResponse.modelName,
                        toolCallsMade: localResponse.toolCallsMade,
                        structuredRAGGeneration: localResponse.structuredRAGGeneration,
                        executionReceipt: receipt
                    )
                } catch let fallbackError {
                    Log.warning(
                        "[ModelRouter] On-device fallback failed: \(fallbackError.localizedDescription)",
                        category: .llm
                    )
                    throw primaryError
                }
            }

            // Rate-limit retry: Apple FM on-device model can hit transient rate limits
            // after heavy compression. Wait briefly and retry once before falling through
            // to fallback services.
            // By the error's type (`ModelErrorClassifier`). The text test this replaces looked for
            // "rate" anywhere. Apple's "Failed to parse generated content" holds it, so an unreadable
            // response that arrived unmapped was waited out and retried here, while the same failure
            // mapped to the app's own message was not. From 5.7 both get one retry after 2 seconds,
            // a real rate limit keeps the whole ladder, and no other message enters this branch for
            // holding those four letters.
            let primaryFailureKind = ModelErrorClassifier.kind(of: primaryError)
            let isRateLimited = primaryFailureKind == .rateLimited || primaryFailureKind == .transient
            VerificationJournal.record(
                "model.failure",
                ["kind": "\(primaryFailureKind)", "mode": "standard",
                    "action": primaryFailureKind == .rateLimited
                        ? "backoffLadder" : primaryFailureKind == .transient ? "retrySamePrompt" : "fallback"])
            if isRateLimited {
                // Escalating backoff, because a flat one did not work.
                //
                // This was a single retry after 2 seconds, resending an identical prompt. A device
                // log from 2026-08-13 shows why that fails: Deep Think fired **16 generations** for
                // one question and Apple FM rate-limited four times. The last generation is the
                // answer, so the user waited through eight reasoning sessions and then lost the
                // query with all its evidence already gathered. Two seconds does not clear a
                // throttle that has not expired, and resending the same prompt at the same
                // temperature changes nothing about why it was refused.
                //
                // Do NOT stop the ladder when a retry fails with something other than a rate-limit
                // error. The observed retry failure was `ParsingError` carrying "Session ended
                // without producing a response", which is what a still-throttled on-device session
                // looks like from the outside, not a malformed prompt. Treating that as a
                // permanent failure is exactly the bug being fixed. We only reach this branch
                // because the *original* error was a rate limit, so the ladder runs to completion.
                //
                // Worst case adds 19 seconds to a query that already spent minutes in the chain.
                // An unreadable response is retried once: if it is not a throttle clearing, three
                // more generations would only delay the fallback.
                let backoffSeconds: [Int] = primaryFailureKind == .rateLimited ? [2, 5, 12] : [2]
                for (index, delay) in backoffSeconds.enumerated() {
                    Log.info(
                        "[RAG] Primary LLM \(primaryFailureKind == .rateLimited ? "rate-limited" : "returned nothing readable"): "
                            + "waiting \(delay)s before retry \(index + 1)/\(backoffSeconds.count)",
                        category: .llm
                    )
                    try? await Task.sleep(for: .seconds(delay))
                    // Explicit, because `try?` above swallows cancellation. At 2 seconds that was
                    // survivable; across a 19 second ladder a cancelled query would otherwise keep
                    // issuing generations after the user moved on.
                    if Task.isCancelled { throw CancellationError() }
                    // In the background a retry only spends the ladder: iOS rate-limits the on-device model
                    // for an app there (5.8, Apple's `GenerationError.rateLimited`). The answer waits for the
                    // app to come back and goes on from this step.
                    let waited = await Self.waitWhileAppIsInBackground()
                    if waited >= 1 {
                        Log.info(
                            "[RAG] Waited \(String(format: "%.0f", waited))s for the app to come back before retry \(index + 1)",
                            category: .llm)
                        VerificationJournal.record(
                            "model.waitedForFront", ["seconds": String(format: "%.0f", waited), "retry": "\(index + 1)"])
                    }
                    if Task.isCancelled { throw CancellationError() }
                    do {
                        let retryResponse = try await attempt(service: _llmService)
                        Log.info(
                            "[RAG] Primary LLM retry \(index + 1) succeeded after "
                                + "\(backoffSeconds.prefix(index + 1).reduce(0, +))s of backoff",
                            category: .llm
                        )
                        return retryResponse
                    } catch {
                        Log.warning(
                            "[RAG] Primary LLM retry \(index + 1)/\(backoffSeconds.count) failed: "
                                + "\(error.localizedDescription)",
                            category: .llm
                        )
                    }
                }
                Log.warning(
                    "[RAG] Primary LLM still failing after \(backoffSeconds.reduce(0, +))s of "
                        + "escalating backoff; falling through to fallback services",
                    category: .llm
                )
            }

            // Check if it's a Jinja template error (common with some GGUF models)
            let isTemplateError = errorDesc.contains("Jinja") || errorDesc.contains("template")

            if isTemplateError {
                Log.warning(
                    "⚠️  \(_llmService.modelName) has a broken chat template (Jinja error)",
                    category: .llm
                )
                Log.info(
                    "💡 Tip: Try a different GGUF model (Qwen2.5, Llama-3.2, or Phi-3)",
                    category: .llm
                )
            } else {
                Log.warning(
                    "Primary model \(_llmService.modelName) failed: \(errorDesc)",
                    category: .llm
                )
            }

            // Try fallbacks in order
            for (index, fallbackService) in _fallbackServices.enumerated() {
                Log.info(
                    "Attempting fallback #\(index + 1): \(fallbackService.modelName)",
                    category: .llm
                )
                do {
                    let response = try await attempt(service: fallbackService)
                    Log.info(
                        "✓ Fallback #\(index + 1) succeeded: \(fallbackService.modelName)",
                        category: .llm
                    )
                    return response
                } catch {
                    Log.warning(
                        "Fallback #\(index + 1) failed: \(error.localizedDescription)",
                        category: .llm
                    )
                    continue
                }
            }

            // All fallbacks exhausted - provide helpful error message
            if isTemplateError {
                throw LLMError.generationFailed(
                    """
                    Model has incompatible chat template.
                    Try: Settings → Primary Model → Select "Apple Intelligence" or "On-Device Analysis"
                    """)
            }

            // Rethrow original error
            throw primaryError
        }
    }

    // MARK: - Response Quality Assessment

    /// Calculate confidence score and identify quality warnings
    /// Critical for medical/high-stakes information retrieval
    /// - Parameters:
    ///   - chunks: Retrieved chunks for this response
    ///   - query: Original user query
    /// - Returns: Tuple of (confidence score 0-1, array of warnings)
    @MainActor
    private func assessResponseQuality(
        chunks: [RetrievedChunk],
        query: String
    ) -> (Float, [String]) {
        var warnings: [String] = []

        // Factor 1: Semantic similarity of top chunks
        let topSimilarity = chunks.first?.similarityScore ?? 0

        if topSimilarity < 0.4 {
            warnings.append(
                "Low relevance: Best match only \(String(format: "%.1f", topSimilarity * 100))% similar"
            )
        } else if topSimilarity < 0.6 {
            warnings.append("Moderate relevance: Consider rephrasing query for better results")
        }

        // Factor 2: Number of supporting chunks
        let chunkCount = chunks.count
        if chunkCount < 3 {
            warnings.append("Limited context: Only \(chunkCount) relevant chunks found")
        }

        // Factor 3: Source diversity (multiple documents = higher confidence)
        let uniqueSources = Set(chunks.map { $0.sourceDocument })
        let sourceCount = uniqueSources.count

        if sourceCount == 1, documents.count > 1 {
            warnings.append("Single source: Information from only one document")
        }

        // Factor 4: Query quality
        let queryWords = query.split(separator: " ").count
        if queryWords <= 2 {
            warnings.append("Generic query: Try more specific questions for better accuracy")
        }

        // Calculate aggregate confidence (weighted average)
        let similarityWeight: Float = 0.5
        let chunkCountWeight: Float = 0.2
        let sourceDiversityWeight: Float = 0.2
        let queryQualityWeight: Float = 0.1

        let similarityScore = min(topSimilarity / 0.8, 1.0)  // Normalize: 0.8+ = full confidence
        let chunkScore = min(Float(chunkCount) / 5.0, 1.0)  // 5+ chunks = full confidence
        let diversityScore = min(Float(sourceCount) / Float(max(documents.count, 1)), 1.0)
        let queryScore = min(Float(queryWords) / 5.0, 1.0)  // 5+ words = full confidence

        let confidence =
            (similarityScore * similarityWeight + chunkScore * chunkCountWeight + diversityScore
                * sourceDiversityWeight + queryScore * queryQualityWeight)

        return (confidence, warnings)
    }

}
