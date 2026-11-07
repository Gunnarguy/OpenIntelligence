//
//  RAGService+QueryContext.swift
//  OpenIntelligence
//
//  Part of RAGService, moved from RAGService+QueryPipeline.swift on 2026-11-05 (5.8 split); only access keywords changed.
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
    /// Step 4.7: compresses the leading candidates with the contextual compression model.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func compressContextCandidates(contextCandidates: inout [RetrievedChunk], useContextualCompression: Bool, auditUsedContextualCompression: inout Bool, question: String, answerIntent: AnswerIntent, compressionSavings: inout Int) async {
        if useContextualCompression, HyDEService.isAvailable, contextCandidates.count > 0 {
            auditUsedContextualCompression = true
            // SMART COMPRESSION BUDGET: Estimate how many chunks will fit in context
            // before wasting time compressing all candidates. Context budget typically
            // fits 3-5 chunks, so compressing 18 at ~3s each = 54s wasted.
            // Only compress top-N where N = estimated fit + small buffer.
            // Use conservative inline estimates (exact budget is computed later):
            //   4096 window - ~1500 overhead/prompt - ~50 question - 300 output = ~2246 tokens
            let estQuestionTokens = max(20, question.count / 4)
            let estimatedAvailableTokens = 4096 - 1500 - estQuestionTokens - 300
            let estimatedCharsAvailable = Int(
                Double(estimatedAvailableTokens) * FoundationModelTokenBudget.onDeviceCharsPerToken * 0.88)
            var totalChars = 0
            var estimatedFit = 0
            for candidate in contextCandidates {
                totalChars += candidate.chunk.text.count
                if totalChars <= max(estimatedCharsAvailable, 3500) {
                    estimatedFit += 1
                }
            }
            // Add buffer of 2 so compression can potentially include slightly more
            let compressionLimit = min(contextCandidates.count, max(estimatedFit + 2, 5))

            // Cap compression to max 5 chunks (~15s) to preserve LLM rate-limit
            // budget for the actual generation step. Without this cap, 10+ chunks
            // at ~3s each = 30s+ of sequential LLM calls that exhaust Apple FM
            // rate limits before the main generation even starts.
            let maxCompressionChunks = 5
            let cappedCompressionLimit = min(compressionLimit, maxCompressionChunks)

            // Skip compression entirely if only 3 or fewer chunks fit — ROI is negative
            // (3 chunks × 3s = 9s for negligible token savings)
            if cappedCompressionLimit <= 3 {
                Log.info(
                    "[RAG] Skipping compression - only \(estimatedFit) chunks fit in context budget (ROI negative)",
                    category: .retrieval)
                emitThinkingEvent(
                    .compression, title: "Compression skipped",
                    detail: "Only \(estimatedFit) chunks fit — ROI negative")
            } else if compressionLimit > maxCompressionChunks {
                Log.info(
                    "[RAG] Capping compression from \(compressionLimit) to \(maxCompressionChunks) chunks to preserve LLM rate budget for generation",
                    category: .retrieval)
                emitThinkingEvent(
                    .compression, title: "Compression capped",
                    detail: "\(compressionLimit)→\(maxCompressionChunks) chunks — protecting generation budget")
            }

            let chunksToCompress =
                cappedCompressionLimit <= 3 ? [] : Array(contextCandidates.prefix(cappedCompressionLimit))
            let compressionService = ContextualCompressionService()
            let chunkTexts = chunksToCompress.map { $0.chunk.text }
            // Pass section titles so compression LLM understands chunk topics.
            // Without this, abbreviation queries like "HRV" get 319→2 token compression
            // because the chunk body has only raw stats without the full metric name.
            let sectionTitles = chunksToCompress.map { $0.chunk.metadata.sectionTitle }

            // Select compression config based on query type
            // "exactly", "detail", "comprehensive", "all about" → verbose (minimal compression)
            // Simple factual lookups → default (moderate compression)
            let queryLower = question.lowercased()
            let wantsComprehensiveAnswer =
                queryLower.contains("exactly") || queryLower.contains("detail")
                || queryLower.contains("comprehensive") || queryLower.contains("everything about")
                || queryLower.contains("all about") || queryLower.contains("explain")
                || queryLower.contains("tell me about") || answerIntent == .investigate
                || answerIntent == .compare

            let compressionConfig: ContextualCompressionService.Config =
                wantsComprehensiveAnswer ? .verbose : .default

            if wantsComprehensiveAnswer {
                Log.info("[RAG] Using verbose compression for comprehensive query", category: .retrieval)
            }

            do {
                let compressionStartTime = Date()
                let compressionResults = try await compressionService.compressChunks(
                    chunkTexts,
                    forQuery: question,
                    sectionTitles: sectionTitles,
                    config: compressionConfig
                )
                let compressionTime = Date().timeIntervalSince(compressionStartTime)

                // Update only the compressed chunks; leave remaining candidates untouched
                var updatedCandidates: [RetrievedChunk] = []
                var droppedIrrelevantCount = 0
                for (index, result) in compressionResults.enumerated() where index < chunksToCompress.count {
                    let original = chunksToCompress[index]

                    // CRITICAL: If compression LLM says NO_RELEVANT_CONTENT, REMOVE the chunk entirely.
                    // Keeping 400-char stubs wastes precious context budget (only 3 chunks fit!)
                    // and those stubs compete with actually relevant chunks in spec sort.
                    // The compression LLM already proved it can distinguish topics accurately.
                    if result.wasMarkedIrrelevant {
                        droppedIrrelevantCount += 1
                        Log.debug(
                            "[Compression] Dropping irrelevant chunk: \(original.chunk.text.prefix(50))...",
                            category: .retrieval)
                        continue  // Skip — don't add to candidates
                    }

                    let effectiveText = result.effectiveContent

                    // Create updated chunk with compressed text
                    var compressedChunk = original.chunk
                    compressedChunk.text = effectiveText
                    updatedCandidates.append(
                        RetrievedChunk(
                            chunk: compressedChunk,
                            similarityScore: original.similarityScore,
                            rank: original.rank,
                            sourceDocument: original.sourceDocument,
                            pageNumber: original.pageNumber
                        ))
                }
                if droppedIrrelevantCount > 0 {
                    Log.info(
                        "[Compression] Removed \(droppedIrrelevantCount) irrelevant chunks — freeing context space",
                        category: .retrieval)
                }

                let originalTokens = compressionResults.reduce(0) { $0 + $1.originalTokens }
                let compressedTokens = compressionResults.reduce(0) { $0 + $1.compressedTokens }
                let lowRelevanceCount = compressionResults.filter { $0.wasMarkedIrrelevant }.count
                compressionSavings = originalTokens - compressedTokens

                if updatedCandidates.count > 0 {
                    // Merge: compressed chunks replace front, uncompressed remain at tail
                    let remaining = Array(contextCandidates.dropFirst(updatedCandidates.count))
                    contextCandidates = updatedCandidates + remaining
                    let lowRelNote = lowRelevanceCount > 0 ? " (\(lowRelevanceCount) fallback)" : ""
                    Log.info(
                        "[Compression] \(originalTokens)→\(compressedTokens) tokens saved \(compressionSavings) in \(String(format: "%.0f", compressionTime * 1000))ms\(lowRelNote)",
                        category: .retrieval)
                    emitThinkingEvent(
                        .compression,
                        title: "Context compressed",
                        detail: "Saved \(compressionSavings) tokens • \(contextCandidates.count) chunks"
                    )
                }
            } catch {
                // Safety filter or other compression failures - keep ALL original chunks intact
                // This is critical for procedural content that may trigger false positives
                Log.warning(
                    "[Compression] Failed, using original chunks: \(error.localizedDescription)",
                    category: .retrieval)
                Log.info(
                    "[Compression] Preserving all \(contextCandidates.count) original chunks for procedural safety",
                    category: .retrieval)
            }

            // Cooldown: let Apple FM rate limits recover after sequential compression
            // calls before the main generation step. Without this pause, generation
            // frequently hits .rateLimited immediately after 5 compression calls.
            if compressionSavings > 0 {
                Log.debug(
                    "[RAG] Post-compression cooldown (1s) to recover FM rate budget", category: .retrieval)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Step 4.9: packs graph neighbors and references around the candidates for multi-hop intents.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func packContextWithGraph(contextCandidates: inout [RetrievedChunk], question: String, answerIntent: AnswerIntent, cachedAllChunks: [DocumentChunk]?, allowLargeContext: Bool, isAppleFMOnDevice: Bool, auditUsedGraphPacking: inout Bool) async {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Step 4.9: Graph-Based Context Packing (AppleRAG §5)
        // pack(R + parents(R) + neighbors(R,±1) + graphHops(R,1))
        // Expands retrieved chunks with graph context for richer LLM input
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Universal pipeline trace: log chunk content before graph packing
        if Log.pipelineTraceEnabled {
            logChunkTrace(contextCandidates, stage: "Pre-GraphPack", query: question)
        }

        if answerIntent.benefitsFromMultiHop, let allChunks = cachedAllChunks {
            let graphPackingStart = Date()

            // Build graph edges for document traversal
            let graphEdges = graphIndexService.buildDocumentGraph(chunks: allChunks)

            // Build lookup table
            var chunkLookup: [UUID: DocumentChunk] = [:]
            for chunk in allChunks {
                chunkLookup[chunk.id] = chunk
            }

            // Extract core chunks from candidates
            let coreChunks = contextCandidates.map { $0.chunk }

            // Sized to the window the device reports (5.7): see `graphPackingTokenBudget(windowTokens:)`.
            let graphTokenBudget = allowLargeContext
                ? 24000
                : Self.graphPackingTokenBudget(
                    windowTokens: FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: isAppleFMOnDevice))

            // Pack with graph context
            let packedContext = await contextPackingService.pack(
                retrievedChunks: coreChunks,
                graphEdges: graphEdges,
                allChunks: chunkLookup,
                tokenBudget: graphTokenBudget,
                neighborDistance: answerIntent.benefitsFromMultiHop ? 1 : 0,
                graphHopDistance: answerIntent.benefitsFromMultiHop ? 1 : 0,
                query: question
            )

            let graphPackingTime = Date().timeIntervalSince(graphPackingStart)

            // Update candidates with packed chunks (convert back to RetrievedChunk)
            if packedContext.contextChunkCount > 0 {
                auditUsedGraphPacking = true
                var packedCandidates: [RetrievedChunk] = []
                for (index, chunk) in packedContext.chunks.enumerated() {
                    // Find original score if this was a core chunk, else assign lower score
                    let originalScore =
                        contextCandidates.first { $0.chunk.id == chunk.id }?.similarityScore ?? 0.3
                    let resolvedSourceDocument = contextCandidates.first { $0.chunk.id == chunk.id }?
                        .sourceDocument
                    let sourceDocument = {
                        let existing =
                            resolvedSourceDocument?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        return existing.isEmpty ? getDocumentName(for: chunk.documentId) : existing
                    }()
                    packedCandidates.append(
                        RetrievedChunk(
                            chunk: chunk,
                            similarityScore: originalScore,
                            rank: index,
                            sourceDocument: sourceDocument,
                            pageNumber: chunk.metadata.pageNumber
                        ))
                }
                contextCandidates = packedCandidates

                VerificationJournal.record(
                    "retrieval.graphPack",
                    ["tokens": "\(packedContext.estimatedTokens)", "budget": "\(graphTokenBudget)",
                        "window": "\(FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: isAppleFMOnDevice))",
                        "withinBudget": "\(packedContext.estimatedTokens <= graphTokenBudget)",
                        "truncated": "\(packedContext.wasTruncated)", "core": "\(packedContext.coreChunkCount)",
                        "context": "\(packedContext.contextChunkCount)"])
                Log.info(
                    "[GraphPack] \(packedContext.coreChunkCount) core + \(packedContext.contextChunkCount) context chunks (\(packedContext.estimatedTokens) tokens) in \(String(format: "%.0f", graphPackingTime * 1000))ms\(packedContext.wasTruncated ? " [truncated]" : "")",
                    category: .retrieval
                )

                // Universal pipeline trace: log chunks after graph packing
                if Log.pipelineTraceEnabled {
                    logChunkTrace(packedCandidates, stage: "Post-GraphPack", query: question)
                }

                emitThinkingEvent(
                    .graphPack,
                    title: "Graph context packed",
                    detail: "+\(packedContext.contextChunkCount) neighbors/refs"
                )
            }
        }
    }

    /// Step SR: runs corrective lexical retrieval and adopts or rejects its candidates.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runCorrectiveRetrieval(effectiveQuery: String, contextCandidates: inout [RetrievedChunk], answerIntentIsExtractive: Bool, effectiveTopK: Int, selectedId: UUID, cachedAllChunks: [DocumentChunk]?, answerIntent: AnswerIntent, qualityModeUsesReRanking: Bool, engine: RAGEngine, question: String, rerankTime: inout TimeInterval, contextStrategy: inout String, auditUsedCorrectiveRetrieval: inout Bool, retrievalTime: inout TimeInterval, recoveryRetrievalTime: inout TimeInterval) async {
        let shouldAttemptCorrective = shouldAttemptCorrectiveRetrieval(
            query: effectiveQuery,
            candidates: contextCandidates,
            answerIntentIsExtractive: answerIntentIsExtractive,
            targetCount: effectiveTopK
        )

        if shouldAttemptCorrective {
            let correctiveStartTime = Date()
            let preCorrectiveLexical = checkLexicalRelevance(
                query: effectiveQuery,
                chunks: Array(contextCandidates.prefix(5))
            )
            let preCorrectiveTopSim = contextCandidates.first?.similarityScore ?? 0
            let hadStructuredEvidence = contextCandidates.prefix(5).contains { candidate in
                looksTableLike(
                    text: candidate.chunk.contextText,
                    structureType: candidate.chunk.metadata.structureType
                )
            }

            let correctiveCandidates = await performCorrectiveRetrieval(
                query: effectiveQuery,
                containerId: selectedId,
                allChunks: cachedAllChunks,
                existingCandidates: contextCandidates,
                answerIntent: answerIntent,
                targetCount: max(effectiveTopK, 4)
            )

            if !correctiveCandidates.isEmpty {
                let mergedCandidates = mergeUniqueChunks(contextCandidates, correctiveCandidates)
                if mergedCandidates.count > contextCandidates.count {
                    let rerankLimit = min(max(effectiveTopK * 3, 10), mergedCandidates.count)
                    let correctiveRerankStart = Date()
                    let correctedCandidates: [RetrievedChunk]

                    if qualityModeUsesReRanking {
                        correctedCandidates = await engine.rerank(
                            chunks: mergedCandidates,
                            query: question,
                            topK: rerankLimit
                        )
                        rerankTime += Date().timeIntervalSince(correctiveRerankStart)
                    } else {
                        correctedCandidates = Array(
                            mergedCandidates
                                .sorted { $0.similarityScore > $1.similarityScore }
                                .prefix(rerankLimit)
                        )
                    }

                    let postCorrectiveLexical = checkLexicalRelevance(
                        query: effectiveQuery,
                        chunks: Array(correctedCandidates.prefix(5))
                    )
                    let postCorrectiveTopSim = correctedCandidates.first?.similarityScore ?? 0
                    let hasStructuredEvidence = correctedCandidates.prefix(5).contains { candidate in
                        looksTableLike(
                            text: candidate.chunk.contextText,
                            structureType: candidate.chunk.metadata.structureType
                        )
                    }

                    let shouldAdoptCorrective =
                        postCorrectiveLexical > preCorrectiveLexical + 0.08
                        || postCorrectiveTopSim > preCorrectiveTopSim + 0.04
                        || (answerIntentIsExtractive
                            && postCorrectiveLexical >= preCorrectiveLexical
                            && hasStructuredEvidence
                            && !hadStructuredEvidence)
                        || (answerIntentIsExtractive
                            && preCorrectiveLexical < 0.55
                            && postCorrectiveLexical >= preCorrectiveLexical)

                    if shouldAdoptCorrective {
                        contextCandidates = correctedCandidates
                        contextStrategy = "corrective_fts"
                        auditUsedCorrectiveRetrieval = true

                        let correctiveTime = Date().timeIntervalSince(correctiveStartTime)
                        retrievalTime += correctiveTime
                        recoveryRetrievalTime = retrievalTime
                        let preLexicalPercent = String(format: "%.0f%%", preCorrectiveLexical * 100)
                        let postLexicalPercent = String(format: "%.0f%%", postCorrectiveLexical * 100)

                        Log.info(
                            "[Corrective] Adopted lexical corrective retrieval: +\(correctiveCandidates.count) hits, lexical \(preLexicalPercent)->\(postLexicalPercent)",
                            category: .retrieval
                        )
                        TelemetryCenter.emit(
                            .retrieval,
                            title: "Corrective retrieval",
                            metadata: [
                                "added": "\(correctiveCandidates.count)",
                                "preLexical": String(format: "%.2f", preCorrectiveLexical),
                                "postLexical": String(format: "%.2f", postCorrectiveLexical),
                                "preTop": String(format: "%.2f", preCorrectiveTopSim),
                                "postTop": String(format: "%.2f", postCorrectiveTopSim),
                            ],
                            duration: correctiveTime
                        )
                        emitThinkingEvent(
                            .retrieval,
                            title: "Corrective retrieval",
                            detail: "+\(correctiveCandidates.count) lexical/page hits"
                        )

                        if Log.pipelineTraceEnabled {
                            logChunkTrace(contextCandidates, stage: "Post-CorrectiveRetrieval", query: question)
                        }
                    } else {
                        let preLexicalPercent = String(format: "%.0f%%", preCorrectiveLexical * 100)
                        let postLexicalPercent = String(format: "%.0f%%", postCorrectiveLexical * 100)
                        Log.info(
                            "[Corrective] Rejected corrective retrieval: lexical \(preLexicalPercent)->\(postLexicalPercent)",
                            category: .retrieval
                        )
                    }
                }
            }
        }
    }

    /// Step 5 (assembly): builds the context by sentence extraction or whole-passage packing with needle rescue.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func assembleStandardContext(answerIntentIsExtractive: Bool, isProceduralQuery: Bool, orderedCandidates: [RetrievedChunk], question: String, maxContextChars: Int, useCompactMode: Bool, engine: RAGEngine, useLostInMiddleMitigation: Bool) async -> (actualChunksUsed: Int, context: String, placedForAttention: Bool, promptSources: [RetrievedChunk], rescuedChunks: [RetrievedChunk]) {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // SENTENCE-LEVEL EXTRACTION (lookup intent only)
        // Instead of packing 3 whole chunks into 4475 chars, extract
        // only query-relevant sentences from ALL candidates.
        // This fits targeted data from 10-15+ chunks vs 3 whole ones —
        // the difference between finding "Engine oil: 5.1 qt" and missing it.
        // Universal across all domains: medical, legal, automotive, etc.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let context: String
        let actualChunksUsed: Int
        // Chunks whose sentences reached the prompt via needle rescue but which are not in
        // the packed prefix. They must be attached to the response, because the prompt
        // gives them citation labels and a label the response cannot resolve is a dead
        // reference in front of the user.
        var rescuedChunks: [RetrievedChunk] = []
        // The chunks the prompt actually labelled, in label order. Every branch below sets
        // this rather than letting the caller recompute `prefix(actualChunksUsed)`, which
        // is what silently mismatched labels against sources.
        var promptSources: [RetrievedChunk] = []
        // Whether the whole-chunk assembler placed the passages for attention, which it does only when it
        // packs four or more; the "Position reorder" event reports that and nothing else.
        var placedForAttention = false

        if answerIntentIsExtractive && !isProceduralQuery {
            let extractionResult = await extractRelevantSentences(
                from: orderedCandidates,
                query: question,
                maxChars: maxContextChars,
                compact: useCompactMode,
                isExtractiveFirst: answerIntentIsExtractive,
                leadingCandidateWhole: true,
                // The answer keeps only the sources used (`promptSources` below), so the labels number those.
                numberByUse: true
            )

            // Sentence extraction is a narrowing filter, and a filter that matches nothing
            // must not be allowed to discard the evidence retrieval just found.
            //
            // Measured on 2026-08-08, case `exact_capex` ("What was the FY2018 capital
            // expenditure amount?"): retrieval was the strongest in the whole run —
            // topSim 1.317, the correct document at rank 1 in all five slots, MMR selecting
            // 5 of 5 with nothing dropped. Extraction then matched zero sentences, returned
            // 0 chars from 4 chunks, and the pipeline logged "Empty context after assembly"
            // and fell back to *direct LLM chat with no RAG at all*. The model, correctly,
            // said the information was not in the provided context, because by then there
            // was no context.
            //
            // That fallback is also the more dangerous failure than the wrong answer it
            // produced here: answering from model priors while the user believes the app is
            // reading their documents is exactly the ungrounded behaviour the verification
            // gates exist to prevent. Whole-chunk assembly is always available and always
            // better than nothing, so use it.
            if extractionResult.context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                !orderedCandidates.isEmpty
            {
                let assembled = await engine.assembleContext(
                    chunks: orderedCandidates,
                    maxChars: maxContextChars,
                    compact: useCompactMode,
                    useLostInMiddleMitigation: useLostInMiddleMitigation
                )
                context = assembled.context
                actualChunksUsed = assembled.used
                promptSources = assembled.sources
                placedForAttention = useLostInMiddleMitigation && assembled.used >= 4
                Log.info(
                    "[RAG] Whole-passage context keeps candidates \(Self.candidatePlaces(of: assembled.sources, in: orderedCandidates)) "
                        + "of \(orderedCandidates.count), in label order",
                    category: .retrieval)
                Log.warning(
                    "[RAG] Sentence extraction matched nothing across \(orderedCandidates.count) candidate(s); "
                        + "falling back to whole-chunk assembly (\(assembled.used) chunks, \(assembled.context.count) chars) "
                        + "rather than returning an empty context",
                    category: .retrieval
                )
            } else {
                context = extractionResult.context
                actualChunksUsed = extractionResult.sourcesUsed
                promptSources = extractionResult.usedSourceIndices.compactMap {
                    orderedCandidates.indices.contains($0) ? orderedCandidates[$0] : nil
                }
                Log.info(
                    "[RAG] Sentence extraction: \(extractionResult.sentencesIncluded) sentences from \(extractionResult.sourcesUsed) sources (\(context.count) chars)",
                    category: .retrieval)
            }
        } else {
            let assembled = await engine.assembleContext(
                chunks: orderedCandidates,
                maxChars: maxContextChars,
                compact: useCompactMode,
                useLostInMiddleMitigation: useLostInMiddleMitigation
            )
            var assembledContext = assembled.context
            actualChunksUsed = assembled.used
            promptSources = assembled.sources
            placedForAttention = useLostInMiddleMitigation && assembled.used >= 4
            Log.info(
                "[RAG] Whole-passage context keeps candidates \(Self.candidatePlaces(of: assembled.sources, in: orderedCandidates)) "
                    + "of \(orderedCandidates.count), in label order",
                category: .retrieval)

            // UNIVERSAL FIX 10: Needle rescue from dropped chunks.
            // When assembleContext runs out of budget, chunks at positions 4+ are dropped
            // entirely. But a keyword-matching needle sentence in chunk #7 is now invisible
            // to the LLM. Fix: run sentence extraction on the DROPPED chunks only,
            // appending high-value sentences into any remaining budget.
            // This catches needles across ALL intents (summarize, procedure, compare, etc.)
            // without replacing whole-chunk packing for the primary chunks.
            let droppedChunks = Self.candidatesPastThePacked(orderedCandidates, packed: assembled.sources)
            let remainingBudget = maxContextChars - assembledContext.count
            let rescueBudgetFloor = (answerIntentIsExtractive || isPrecisionValueQuery(question)) ? 80 : 160

            if !droppedChunks.isEmpty && remainingBudget > rescueBudgetFloor {
                let rescueResult = await extractRelevantSentences(
                    from: droppedChunks,
                    query: question,
                    maxChars: remainingBudget,
                    compact: true,  // Always compact for rescue sentences to maximize density
                    isExtractiveFirst: answerIntentIsExtractive,
                    // Continue the packed block's numbering instead of restarting at [S1].
                    // Both blocks land in one prompt, so restarting produced two different
                    // chunks both labelled [S1]. A device trace on 2026-08-14 shows the
                    // consequence: four packed sources followed by rescue sources numbered
                    // from one again, and an answer citing [S5] and [S6], which are the
                    // fifth and sixth sources the model was shown and which resolved to
                    // nothing downstream.
                    labelOffset: assembled.used,
                    // Only the rescued sources join the answer (`rescuedChunks`), so the labels number those.
                    numberByUse: true
                )
                if rescueResult.sentencesIncluded > 0 {
                    rescuedChunks = rescueResult.usedSourceIndices.compactMap {
                        droppedChunks.indices.contains($0) ? droppedChunks[$0] : nil
                    }
                    assembledContext += "\n---\n" + rescueResult.context
                    Log.info(
                        "[RAG] Needle rescue: +\(rescueResult.sentencesIncluded) sentences from \(rescueResult.sourcesUsed) dropped chunks (\(rescueResult.context.count) chars)",
                        category: .retrieval)
                }
            }

            context = assembledContext
        }
        return (actualChunksUsed: actualChunksUsed, context: context, placedForAttention: placedForAttention, promptSources: promptSources, rescuedChunks: rescuedChunks)
    }

    /// Step 5 (audit): emits the context telemetry and stores the RAGAuditSnapshot.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func recordContextAuditSnapshot(actualChunksUsed: Int, contextWords: Int, contextSize: Int, selectedName: String, selectedId: UUID, selectedContainer: KnowledgeContainer?, question: String, embeddingProviderId: String, selectedDim: Int, qualityModeDisplayName: String, retrievalConfig: RetrievalConfig, auditLenient: Bool, auditDynamicMin: Float, auditTopSim: Float, auditSecondSim: Float, auditAvgTop5: Float, auditAcceptanceOverride: Bool, totalStored: Int, auditCandidatesCount: Int, auditRerankedCount: Int, auditFilteredCount: Int, auditDroppedCount: Int, auditMMRSelectedCount: Int, auditUniqueDocCount: Int, contextStrategy: String, maxContextChars: Int, baseWindowTokens: Int, promptOverheadTokens: Int, questionTokens: Int, reservedOutputTokens: Int, availableForContextTokens: Int, inferenceConfig: InferenceConfig, networkAvailable: Bool, allowLargeContext: Bool, reliabilityModeEnabled: Bool, allowUngroundedFallback: Bool, auditAnswerIntent: String, auditQueryWasRewritten: Bool, auditQueryExpansionCount: Int, auditUsedHyDE: Bool, auditUsedIterativeRetrieval: Bool, auditIterativePassCount: Int, auditUsedQueryRouting: Bool, auditUsedSummaryRouting: Bool, auditUsedParentDocumentRetrieval: Bool, auditUsedCorrectiveRetrieval: Bool, auditUsedContextualCompression: Bool, auditUsedGraphPacking: Bool, usedRetrievalCascade: Bool, auditUsedSupplementaryVectorSearch: Bool) async {
        Log.section("Step 5: Context Assembly Complete", level: .info, category: .pipeline)

        // Pipeline Trace: Step 5
        Log.pipelineStep(
            "5", title: "Context Assembly",
            details: [
                ("chunks", "\(actualChunksUsed)"),
                ("words", "\(contextWords)"),
                ("chars", "\(contextSize)"),
            ])

        Log.info(
            "✓ Final context: \(contextSize) chars, \(contextWords) words from \(actualChunksUsed) chunks",
            category: .pipeline
        )
        TelemetryCenter.emit(
            .retrieval,
            title: "Context assembled",
            metadata: [
                "chunks": "\(actualChunksUsed)",
                "chars": "\(contextSize)",
                "container": selectedName,
                "containerId": selectedId.uuidString,
            ]
        )

        emitThinkingEvent(
            .context,
            title: "Context ready",
            detail: "\(actualChunksUsed) chunks • \(contextWords) words"
        )

        let chunkingTarget =
            selectedContainer?.chunkingDirective?.targetWordWindow
            ?? documentProcessor.targetChunkSize
        let chunkingOverlap =
            selectedContainer?.chunkingDirective?.overlapWords
            ?? documentProcessor.chunkOverlap
        let chunkingSource =
            selectedContainer?.chunkingDirective?.source.rawValue
            ?? "baseline"
        let vectorDBKind = selectedContainer?.vectorDBKind ?? .persistentJSON

        let auditSnapshot = RAGAuditSnapshot(
            timestamp: Date(),
            query: question,
            containerId: selectedId,
            containerName: selectedName,
            embeddingProviderId: embeddingProviderId,
            embeddingDim: selectedDim,
            vectorDBKind: vectorDBKind,
            chunkingTargetWords: chunkingTarget,
            chunkingOverlapWords: chunkingOverlap,
            chunkingSource: chunkingSource,
            qualityModeName: qualityModeDisplayName,
            retrievalConfig: retrievalConfig,
            lenientRetrieval: auditLenient,
            dynamicMin: auditDynamicMin,
            topSim: auditTopSim,
            secondSim: auditSecondSim,
            avgTop5: auditAvgTop5,
            acceptanceOverride: auditAcceptanceOverride,
            totalStoredChunks: totalStored,
            candidatesCount: auditCandidatesCount,
            rerankedCount: auditRerankedCount,
            filteredCount: auditFilteredCount,
            droppedCount: auditDroppedCount,
            mmrSelectedCount: auditMMRSelectedCount,
            uniqueDocCount: auditUniqueDocCount,
            contextStrategy: contextStrategy,
            contextChars: contextSize,
            contextWords: contextWords,
            contextChunksUsed: actualChunksUsed,
            maxContextChars: maxContextChars,
            baseWindowTokens: baseWindowTokens,
            safetyTokens: 0,  // Unified into globalSafetyFactor (no separate flat buffer)
            promptOverheadTokens: promptOverheadTokens,
            questionTokens: questionTokens,
            reservedOutputTokens: reservedOutputTokens,
            availableContextTokens: availableForContextTokens,
            executionContext: inferenceConfig.executionContext,
            allowPrivateCloudCompute: inferenceConfig.allowPrivateCloudCompute,
            networkConnected: networkAvailable,
            wantsCloudContext: allowLargeContext,
            reliabilityModeEnabled: reliabilityModeEnabled,
            allowUngroundedFallback: allowUngroundedFallback,
            modelName: llmService.modelName,
            featureFlags: RAGAuditFeatureFlags(
                answerIntent: auditAnswerIntent,
                queryWasRewritten: auditQueryWasRewritten,
                queryExpansionCount: auditQueryExpansionCount,
                usedHyDE: auditUsedHyDE,
                usedIterativeRetrieval: auditUsedIterativeRetrieval,
                iterativePassCount: auditIterativePassCount,
                usedQueryRouting: auditUsedQueryRouting,
                usedSummaryRouting: auditUsedSummaryRouting,
                usedParentDocumentRetrieval: auditUsedParentDocumentRetrieval,
                usedCorrectiveRetrieval: auditUsedCorrectiveRetrieval,
                usedContextualCompression: auditUsedContextualCompression,
                usedGraphPacking: auditUsedGraphPacking,
                usedRetrievalCascade: usedRetrievalCascade,
                usedSupplementaryVectorSearch: auditUsedSupplementaryVectorSearch,
                usedFullUnlimitedReasoning: false
            )
        )

        await MainActor.run {
            self.lastAuditSnapshot = auditSnapshot
        }
    }

    /// Step SX (setup): starts the context candidates from the MMR list and detects enumeration questions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func prepareContextCandidates(diverseChunks: [RetrievedChunk], question: String) -> (contextCandidates: [RetrievedChunk], contextStrategy: String, isEnumerationQuery: Bool, isAppleFMOnDevice: Bool) {
        let isAppleFMOnDevice = llmService is AppleFoundationLLMService
        var contextCandidates = diverseChunks
        var contextStrategy = "mmr"

        // Enumeration queries need ALL chunk slots for detail —
        // RAPTOR summaries waste 25% of context on generic overviews.
        // Covers: "how many X", "list all X", "what are all the X", "show every X", etc.
        let isEnumerationQuery: Bool = {
            let lq = question.lowercased()
            let quickTriggers = [
                "how many", "list all", "list every", "list the", "list each",
                "name all", "name every", "show all", "show every",
                "what are all", "give me all", "give me every", "enumerate",
                "how many kinds", "how many categories",
                "count the", "count all", "total number of",
            ]
            return quickTriggers.contains { lq.contains($0) }
        }()
        return (contextCandidates: contextCandidates, contextStrategy: contextStrategy, isEnumerationQuery: isEnumerationQuery, isAppleFMOnDevice: isAppleFMOnDevice)
    }

    /// Step SX: blends document summaries with detail passages for questions that need a document summary.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func addSummaryDetailHybrid(answerNeedsDocumentSummary: Bool, cachedAllChunks: [DocumentChunk]?, isEnumerationQuery: Bool, contextCandidates: inout [RetrievedChunk], question: String, contextStrategy: inout String) {
        // ═══════════════════════════════════════════════════════════════════════════════
        // Summary-detail hybrid context for research/findings queries
        // ═══════════════════════════════════════════════════════════════════════════════
        // When user asks "What did X find?", we need BOTH:
        // 1. Document summary (L1) for high-level context
        // 2. Most relevant detail chunks (L0) for specific findings
        //
        // Strategy:
        // - Reserve ~25% of token budget for summary (provides roadmap)
        // - Use remaining 75% for highest-relevance detail chunks
        // - Smart deduplication to avoid redundant content
        // - Dynamic chunk count based on available tokens
        // ═══════════════════════════════════════════════════════════════════════════════
        if answerNeedsDocumentSummary && !isEnumerationQuery, let allChunks = cachedAllChunks {
            let summaryChunks = allChunks.filter { $0.metadata.abstractionLevel == .documentSummary }
            let existingIds = Set(contextCandidates.map { $0.chunk.id })

            // Get relevant document IDs from top candidates
            let relevantDocIds = Set(contextCandidates.prefix(5).map { $0.chunk.documentId })

            // Prioritize summaries from documents that appear in top results
            let prioritizedSummaries =
                summaryChunks
                .filter { !existingIds.contains($0.id) }
                .sorted { chunk1, chunk2 in
                    let score1 = relevantDocIds.contains(chunk1.documentId) ? 1 : 0
                    let score2 = relevantDocIds.contains(chunk2.documentId) ? 1 : 0
                    return score1 > score2
                }

            if !prioritizedSummaries.isEmpty {
                // Calculate token budget for summaries (~25% of total context)
                // Average summary is ~150 words ≈ 200 tokens ≈ 600 chars
                let estimatedContextBudget = 4000  // Conservative estimate for on-device
                let summaryBudgetChars = estimatedContextBudget / 4  // 25% for summaries

                // Select summaries that fit in budget, prioritizing relevant docs
                var selectedSummaries: [RetrievedChunk] = []
                var summaryCharsUsed = 0

                for (index, chunk) in prioritizedSummaries.enumerated() {
                    let chunkChars = chunk.content.count
                    if summaryCharsUsed + chunkChars <= summaryBudgetChars || selectedSummaries.isEmpty {
                        // Assign high scores with decay for ordering
                        let score = Float(0.98 - (Double(index) * 0.02))  // 0.98, 0.96, 0.94...
                        // Look up document name from documents array
                        let docName = getDocumentName(for: chunk.documentId)
                        selectedSummaries.append(
                            RetrievedChunk(
                                chunk: chunk,
                                similarityScore: score,
                                rank: index,
                                sourceDocument: docName,
                                pageNumber: nil
                            ))
                        summaryCharsUsed += chunkChars
                    }
                    // Limit to max 3 summaries to leave room for detail chunks
                    if selectedSummaries.count >= 3 { break }
                }

                // Calculate how many detail chunks we can keep
                let remainingBudgetChars = estimatedContextBudget - summaryCharsUsed
                let avgDetailChunkChars =
                    contextCandidates.isEmpty
                    ? 400
                    : contextCandidates.prefix(10).reduce(0) { $0 + $1.chunk.content.count }
                        / min(10, contextCandidates.count)
                let maxDetailChunks = max(3, remainingBudgetChars / max(avgDetailChunkChars, 200))

                // Filter detail chunks to remove any that are substantially covered by summaries
                // (Avoid redundant content - summaries already capture key points)
                var detailCandidates = contextCandidates.filter { retrieved in
                    // Keep chunk if it's NOT a summary (L0 detail chunks)
                    retrieved.chunk.metadata.abstractionLevel != .documentSummary
                }

                // ═══════════════════════════════════════════════════════════════════
                // Author-name cross-reference boost
                // If query contains a name, boost chunks from matching document
                // ═══════════════════════════════════════════════════════════════════
                let queryWords = question.split(separator: " ").map { String($0).lowercased() }
                let potentialAuthorNames = queryWords.filter { word in
                    // Capitalized in original query, >2 chars, not common words
                    let originalWord = question.split(separator: " ").first { String($0).lowercased() == word }
                    let commonWords = Set([
                        "what", "did", "does", "find", "show", "the", "and", "for", "how", "why",
                    ])
                    return originalWord?.first?.isUppercase == true && word.count > 2
                        && !commonWords.contains(word)
                }

                if !potentialAuthorNames.isEmpty {
                    // Boost chunks from documents that match author name in filename
                    detailCandidates = detailCandidates.sorted { a, b in
                        let aFile = a.sourceDocument.lowercased()
                        let bFile = b.sourceDocument.lowercased()
                        let aMatchCount = potentialAuthorNames.filter { aFile.contains($0) }.count
                        let bMatchCount = potentialAuthorNames.filter { bFile.contains($0) }.count

                        if aMatchCount != bMatchCount {
                            return aMatchCount > bMatchCount  // More matches = higher priority
                        }
                        return a.similarityScore > b.similarityScore  // Fall back to similarity
                    }

                    let boostedCount = detailCandidates.prefix(maxDetailChunks).filter { chunk in
                        potentialAuthorNames.contains { chunk.sourceDocument.lowercased().contains($0) }
                    }.count

                    if boostedCount > 0 {
                        Log.debug(
                            "[Findings Context] Author boost: \(boostedCount) chunks from '\(potentialAuthorNames.joined(separator: ", "))' documents",
                            category: .retrieval)
                    }
                }

                // Take top N detail chunks by relevance score (now potentially author-boosted)
                let topDetailChunks = Array(detailCandidates.prefix(maxDetailChunks))

                // Merge: Summaries FIRST (high-level roadmap), then detail chunks
                contextCandidates = selectedSummaries + topDetailChunks
                contextStrategy = "summary_detail_hybrid"

                let totalChars = summaryCharsUsed + topDetailChunks.reduce(0) { $0 + $1.chunk.content.count }
                Log.info(
                    "[Hybrid Context] \(selectedSummaries.count) summaries (\(summaryCharsUsed) chars) + "
                        + "\(topDetailChunks.count) detail chunks → \(totalChars) total chars",
                    category: .retrieval
                )
                emitThinkingEvent(
                    .context,
                    title: "Hybrid Context",
                    detail:
                        "\(selectedSummaries.count) summaries + \(topDetailChunks.count) details = comprehensive coverage"
                )

                if Log.pipelineTraceEnabled {
                    Log.debug(
                        "[Hybrid Context] Summary budget: \(summaryBudgetChars) chars, used: \(summaryCharsUsed)",
                        category: .retrieval)
                    Log.debug(
                        "[Hybrid Context] Detail budget: \(remainingBudgetChars) chars, chunks: \(topDetailChunks.count)",
                        category: .retrieval)
                    Log.debug(
                        "[Hybrid Context] Avg detail chunk: \(avgDetailChunkChars) chars", category: .retrieval)
                }
            } else if !summaryChunks.isEmpty {
                Log.debug(
                    "[Hybrid Context] Summary chunks already in candidates - no injection needed",
                    category: .retrieval)
            } else {
                Log.info(
                    "[Hybrid Context] No summary chunks available - using detail-only retrieval",
                    category: .retrieval)
                emitThinkingEvent(
                    .context,
                    title: "Detail-Only Context",
                    detail: "Re-ingest documents to enable summary-enhanced retrieval"
                )
            }
        }
    }

    /// Step SF: narrows strong short single-document questions to a neighbor window around the top passage (on-device Apple model only).
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyFocusedNeighborWindow(diverseChunks: [RetrievedChunk], question: String, auditAvgTop5: Float, auditTopSim: Float, queryWords: Int, rerankedChunks: [RetrievedChunk], uniqueDocCount: Int, isAppleFMOnDevice: Bool, initialWantsCloudContext: Bool, effectiveTopK: Int, contextCandidates: inout [RetrievedChunk], contextStrategy: inout String) {
        // Universal pipeline trace: log chunk content previews at each stage
        if Log.pipelineTraceEnabled {
            logChunkTrace(diverseChunks, stage: "Post-MMR", query: question)
        }

        let strongTopSim =
            auditTopSim >= 0.72 || (auditTopSim >= 0.68 && (auditTopSim - auditAvgTop5) >= 0.03)
        let shortQuery = queryWords <= 12
        let topDocId = rerankedChunks.first?.chunk.documentId
        let topDocSample = min(10, rerankedChunks.count)
        let topDocHits = rerankedChunks.prefix(topDocSample).filter { $0.chunk.documentId == topDocId }.count
        let topDocShare = topDocSample > 0 ? Double(topDocHits) / Double(topDocSample) : 0
        let focusedDocScope = uniqueDocCount <= 2 || topDocShare >= 0.6

        if isAppleFMOnDevice,
            !initialWantsCloudContext,
            strongTopSim,
            shortQuery,
            focusedDocScope,
            let focusSeed = rerankedChunks.first
        {
            let maxFocusedTotal = min(max(5, min(10, effectiveTopK)), rerankedChunks.count)
            let neighborsPerSeed = min(4, max(1, (maxFocusedTotal - 1) / 2))
            var focused = buildNeighborAwareFallback(
                seeds: [focusSeed],
                pool: rerankedChunks,
                maxTotal: maxFocusedTotal,
                neighborsPerSeed: neighborsPerSeed
            )
            if focused.count > 1 {
                focused.sort {
                    if $0.chunk.documentId == $1.chunk.documentId {
                        return $0.chunk.metadata.chunkIndex < $1.chunk.metadata.chunkIndex
                    }
                    return $0.similarityScore > $1.similarityScore
                }
                contextCandidates = focused
                contextStrategy = "focused_window"
                let sourceName = focusSeed.sourceDocument.isEmpty ? "unknown" : focusSeed.sourceDocument
                Log.info(
                    "🔎 Focused context window (\(focused.count) chunks) • topSim \(String(format: "%.3f", auditTopSim)) • source \(sourceName)",
                    category: .retrieval
                )

                if Log.pipelineTraceEnabled {
                    logChunkTrace(focused, stage: "Post-FocusedWindow", query: question)
                }
            }
        }
    }

    /// Step SE: adds a BM25 second pass over every passage for enumeration questions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func addEnumerationKeywordPass(cachedAllChunks: [DocumentChunk]?, isEnumerationQuery: Bool, contextCandidates: inout [RetrievedChunk], question: String, contextStrategy: inout String) {
        // ═══════════════════════════════════════════════════════════════════
        // ITERATIVE RETRIEVAL: BM25 second-pass for enumeration queries
        // ═══════════════════════════════════════════════════════════════════
        // When asking "how many X are available", vector search retrieves
        // chunks ABOUT the topic but misses the actual enumerated list page
        // (sparse, low semantic density). A targeted BM25 keyword scan over
        // ALL chunks in the container finds it.
        // ═══════════════════════════════════════════════════════════════════
        if isEnumerationQuery, let allChunks = cachedAllChunks, !allChunks.isEmpty {
            let existingIds = Set(contextCandidates.map { $0.chunk.id })

            // Extract subject noun from enumeration query patterns:
            // "how many [NOUN] are available" → NOUN
            // "list all [NOUN]"               → NOUN
            // "what are all the [NOUN]"       → NOUN
            // "show every [NOUN]"             → NOUN
            // "total number of [NOUN]"        → NOUN
            let lq = question.lowercased()
            let stopWords: Set<String> = [
                "are", "is", "does", "do", "can", "will", "were", "was",
                "have", "has", "for", "the", "in", "on", "at", "to", "of",
                "available", "there", "exist", "supported", "included",
                "a", "an", "this", "that", "it", "its", "my", "your",
            ]
            let subjectNoun: String = {
                // Try each trigger phrase, extract noun after it
                let triggers = [
                    "how many ", "list all ", "list every ", "list the ", "list each ",
                    "name all ", "name every ", "show all ", "show every ",
                    "what are all the ", "what are all ", "what are the ",
                    "give me all ", "give me every ",
                    "total number of ", "count the ", "count all ",
                    "enumerate ",
                ]
                for trigger in triggers {
                    if let range = lq.range(of: trigger) {
                        let afterTrigger = String(lq[range.upperBound...])
                        let words = afterTrigger.split(separator: " ")
                        let nouns = words.prefix(4).filter { !stopWords.contains(String($0)) }
                        if !nouns.isEmpty {
                            return nouns.map(String.init).joined(separator: " ")
                        }
                    }
                }
                return ""
            }()

            if !subjectNoun.isEmpty {
                let bm25 = BM25Scorer()
                bm25.indexDocuments(allChunks)
                let queryTerms = bm25.tokenize(subjectNoun)

                // Score ALL chunks by BM25 keyword match
                var scored: [(chunk: DocumentChunk, score: Float)] = []
                for chunk in allChunks {
                    let s = bm25.score(queryTerms: queryTerms, document: chunk.content)
                    if s > 0 { scored.append((chunk, s)) }
                }
                scored.sort { $0.score > $1.score }

                // Inject top BM25 results not already in candidates
                var added = 0
                for (chunk, bm25Score) in scored.prefix(15) {
                    guard !existingIds.contains(chunk.id), added < 5 else { continue }
                    let docName = getDocumentName(for: chunk.documentId)
                    contextCandidates.append(
                        RetrievedChunk(
                            chunk: chunk,
                            similarityScore: min(bm25Score / 10.0, 0.85),
                            rank: contextCandidates.count,
                            sourceDocument: docName,
                            pageNumber: chunk.metadata.pageNumber
                        ))
                    added += 1
                }

                if added > 0 {
                    contextStrategy = "enumeration_iterative"
                    Log.info(
                        "[Iterative Retrieval] Enumeration 2nd pass: +\(added) BM25 chunks for '\(subjectNoun)'",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .retrieval,
                        title: "Iterative Retrieval",
                        detail: "BM25 2nd pass: +\(added) chunks targeting '\(subjectNoun)' list"
                    )

                    if Log.pipelineTraceEnabled {
                        logChunkTrace(contextCandidates, stage: "Post-EnumerationIterative", query: question)
                    }
                }
            }
        }
    }

    /// Step 4.8: adds specification-table passages found by keyword and number co-occurrence for extractive questions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runSpecTableSniper(answerIntentIsExtractive: Bool, cachedAllChunks: [DocumentChunk]?, contextCandidates: inout [RetrievedChunk], question: String) {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Step 4.8: Targeted Spec Retrieval ("Spec Table Sniper")
        // The reranker has an inherent prose bias: prose scores ~0.78 while
        // tables/specs score ~0.30. For lookup/extractive queries, bypass
        // semantic scoring entirely and search ALL chunks for co-occurrence
        // of query keywords + numeric data.
        //
        // This is the "needle in a haystack" sniper — universal across domains:
        // medical dosages, legal statute numbers, technical specs, financial data.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if answerIntentIsExtractive, let allChunks = cachedAllChunks {
            let existingIds = Set(contextCandidates.map { $0.chunk.id })
            let sniperResults = specTableSniper(
                query: question,
                allChunks: allChunks,
                excludeIds: existingIds
            )
            if !sniperResults.isEmpty {
                // Insert at position 0 — these targeted results should survive
                // context assembly budget cuts ahead of prose chunks
                contextCandidates.insert(contentsOf: sniperResults, at: 0)

                // Demote chunks that merely CITE other sections ("given in X on page Y")
                // now that we have the actual data they were pointing to
                demoteCrossReferenceChunks(&contextCandidates)

                Log.info(
                    "[RAG] Spec sniper: +\(sniperResults.count) targeted chunks from \(allChunks.count) total (keyword+number co-occurrence)",
                    category: .retrieval)
                emitThinkingEvent(
                    .retrieval, title: "Spec sniper",
                    detail: "+\(sniperResults.count) targeted chunks via keyword+number co-occurrence")
            }
        }
    }

    /// Step 4.7 (gates): decides whether contextual compression runs and logs each reason it is skipped.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func gateContextualCompression(isProceduralQuery: Bool, vocabularyMismatch: Bool, contextStrategy: String, qualityModeUsesContextualCompression: Bool, adaptiveConfig: AdaptivePipelineConfig) -> (useContextualCompression: Bool, compressionSavings: Int) {
        // Step 4.7: Contextual Compression (optional)
        // Extract only query-relevant sentences from chunks to maximize signal and save tokens
        // Respect quality mode toggle, user settings, AND adaptive pipeline (thermal/battery aware)
        // CRITICAL: Skip compression for procedural queries - compression destroys step ordering
        // (e.g., 335→27 tokens = 8% retention loses critical procedural constraints)
        // CRITICAL: Skip compression for vocabulary mismatch - compressor can't judge relevance
        // when query terms don't match document vocabulary (conversational vs technical)
        // CRITICAL: Skip compression for parent-expanded content - parent chunks are too large
        // for compression model (exceed context window) AND compression defeats hierarchical purpose
        let compressionEnabledBySettings = settingsStore?.enableContextualCompression ?? true
        let skipCompressionForProcedural = isProceduralQuery  // Preserve contiguous spans
        let skipCompressionForVocabMismatch = vocabularyMismatch  // Compressor will destroy content
        let skipCompressionForParentExpansion = contextStrategy == "parent_expanded"  // Chunks too large + defeats purpose
        let useContextualCompression =
            qualityModeUsesContextualCompression && compressionEnabledBySettings
            && adaptiveConfig.enableContextualCompression && !skipCompressionForProcedural
            && !skipCompressionForVocabMismatch && !skipCompressionForParentExpansion
        var compressionSavings = 0

        if skipCompressionForProcedural {
            Log.info(
                "[RAG] Skipping compression for procedural query - preserving contiguous spans",
                category: .retrieval)
            emitThinkingEvent(
                .compression, title: "Compression skipped",
                detail: "Procedural query — preserving step ordering")
        }

        if skipCompressionForVocabMismatch {
            Log.info(
                "[RAG] Skipping compression for vocabulary mismatch - compressor can't judge relevance",
                category: .retrieval)
            emitThinkingEvent(
                .compression, title: "Compression skipped",
                detail: "Vocabulary mismatch — compressor can't judge relevance")
        }

        if skipCompressionForParentExpansion {
            Log.info(
                "[RAG] Skipping compression for parent-expanded content - chunks exceed compression model capacity",
                category: .retrieval)
            emitThinkingEvent(
                .compression, title: "Compression skipped",
                detail: "Parent-expanded chunks exceed model capacity")
        }
        return (useContextualCompression: useContextualCompression, compressionSavings: compressionSavings)
    }

    /// Step 5 (tools): starts context assembly and turns tools off when the context is already assembled.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func disableToolsForAssembledContext(allowLargeContext: Bool, isTrivial: Bool, contextCandidates: [RetrievedChunk], inferenceConfig: inout InferenceConfig) -> Bool {
        // Step 5: Construct context from retrieved chunks (off-main)
        // Note: rawContext assembly is handled via engine.assembleContext with size limits
        HardwareTelemetryState.shared.reportRAGPipeline(stage: "Context Assembly")

        let applyTrivialCaps = isTrivial && !allowLargeContext

        // CRITICAL OPTIMIZATION: Disable tools when the RAG pipeline has already
        // retrieved and assembled context. Tool schemas eat ~1000 tokens (24% of
        // the window). When context is pre-assembled, the LLM prompt already
        // says "don't use tools" — so we're burning tokens on dead weight.
        if !inferenceConfig.disableTools && contextCandidates.count > 0 {
            inferenceConfig.disableTools = true
            Log.info(
                "[RAG] Auto-disabled tools: context pre-assembled (\(contextCandidates.count) chunks). Reclaimed ~1000 tokens for context.",
                category: .pipeline)
        }
        return applyTrivialCaps
    }

    /// Step 5 (budget): computes the token and character budget for the context.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func computeContextCharBudget(inferenceConfig: InferenceConfig, baseWindowTokens: Int, promptOverheadTokens: Int, questionTokens: Int, allowLargeContext: Bool, isAppleFMOnDevice: Bool, applyTrivialCaps: Bool, conservativeCharsPerToken: Double) -> (maxContextChars: Int, useCompactMode: Bool, reservedOutputTokens: Int, availableForContextTokens: Int, globalSafetyFactor: Double) {
        // Transcript tokens NO LONGER deducted from context budget.
        // This eliminates the failure mode where transcript > window → 0 context.
        let rawTranscriptTokens: Int
        if let appleFMService = llmService as? AppleFoundationLLMService {
            rawTranscriptTokens = appleFMService.estimatedTranscriptTokens
        } else {
            rawTranscriptTokens = 0
        }
        if rawTranscriptTokens > 0 {
            Log.debug(
                "[RAG] Transcript history: ~\(rawTranscriptTokens) tokens (auto-trimmed by LLM service, not deducted from context)",
                category: .pipeline)
        }

        // Reserve room for output
        let reservedOutputTokens = max(150, min(inferenceConfig.maxTokens, 300))

        // OPTIMIZED: Single safety margin based on execution location.
        let rawAvailableTokens = baseWindowTokens - promptOverheadTokens - questionTokens - reservedOutputTokens
        let globalSafetyFactor: Double = allowLargeContext ? 0.92 : (isAppleFMOnDevice ? 0.88 : 0.90)
        let availableForContextTokens = max(
            0,
            Int(Double(rawAvailableTokens) * globalSafetyFactor)
        )
        let cappedContextTokens =
            applyTrivialCaps
            ? min(availableForContextTokens, allowLargeContext ? 20000 : 2600)
            : availableForContextTokens

        let maxContextCharsCap: Int = {
            if llmService is AppleFoundationLLMService {
                if allowLargeContext {
                    return applyTrivialCaps ? 6000 : 45000
                } else {
                    return applyTrivialCaps ? 2500 : 10000
                }
            } else {
                return applyTrivialCaps ? 6000 : 10000
            }
        }()

        let maxContextChars = min(
            max(800, Int(Double(cappedContextTokens) * conservativeCharsPerToken)),
            maxContextCharsCap
        )

        // Use compact mode for Apple FM to maximize content in limited space, unless we have PCC's large context window.
        let useCompactMode = isAppleFMOnDevice && !allowLargeContext

        #if targetEnvironment(simulator)
            Log.info(
                "[RAG] Simulator mode: using on-device context budget (4096 tokens, \(maxContextChars) chars)",
                category: .pipeline)
        #endif

        Log.debug(
            "Context budget: base=\(baseWindowTokens), question=\(questionTokens), transcript=\(rawTranscriptTokens)(not deducted), available=\(availableForContextTokens) tokens → \(maxContextChars) chars, compact=\(useCompactMode)",
            category: .pipeline)
        return (maxContextChars: maxContextChars, useCompactMode: useCompactMode, reservedOutputTokens: reservedOutputTokens, availableForContextTokens: availableForContextTokens, globalSafetyFactor: globalSafetyFactor)
    }

    /// Step 5 (ordering): orders the candidates for procedural, extractive or default questions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func orderContextCandidates(isProceduralQuery: Bool, contextCandidates: [RetrievedChunk], answerIntentIsExtractive: Bool, question: String) -> (orderedCandidates: [RetrievedChunk], useLostInMiddleMitigation: Bool) {
        // For procedural queries, preserve document order instead of relevance order
        // This prevents sequence inversions (e.g., "dry before disinfect" errors)
        let orderedCandidates: [RetrievedChunk]
        if isProceduralQuery {
            // Sort by document ID then chunk index to preserve original document sequence
            orderedCandidates = contextCandidates.sorted(by: { (a: RetrievedChunk, b: RetrievedChunk) -> Bool in
                if a.chunk.documentId == b.chunk.documentId {
                    return a.chunk.metadata.chunkIndex < b.chunk.metadata.chunkIndex
                }
                // Group by document, then by first appearance order
                return a.rank < b.rank
            })
            Log.info(
                "[RAG] Procedural query - preserving document order for sequence fidelity", category: .retrieval
            )
        } else if answerIntentIsExtractive {
            // For lookup/table queries, prioritize chunks containing specifications
            // that MATCH the query topic — not just any specs
            let queryKeywords = extractQueryTerms(question)

            // CORPUS-AWARE KEYWORD DISCOUNTING:
            // Keywords that appear in >40% of candidates are corpus-generic and should
            // NOT get bonus weight.  e.g. "car" in a car manual matches everything,
            // diluting the signal from discriminative keywords like "oil".
            // This is the same principle as IDF in BM25 — universal, domain-agnostic.
            let candidateCount = max(1, contextCandidates.count)
            let keywordDocFreq: [String: Int] = {
                var freq: [String: Int] = [:]
                for kw in queryKeywords {
                    var count = 0
                    for c in contextCandidates {
                        let text = c.chunk.contextText.lowercased()
                        if text.contains(kw) { count += 1 }
                    }
                    freq[kw] = count
                }
                return freq
            }()
            let discriminativeKeywords = queryKeywords.filter { kw in
                let df = keywordDocFreq[kw] ?? 0
                return Double(df) / Double(candidateCount) <= 0.40
            }
            let discardedKeywords = queryKeywords.filter { !discriminativeKeywords.contains($0) }
            if !discardedKeywords.isEmpty {
                Log.info(
                    "[RAG] Corpus-aware: discounted generic keywords \(discardedKeywords) (>40% of chunks)",
                    category: .retrieval)
            }

            let byPriority = contextCandidates.sorted(by: { (a: RetrievedChunk, b: RetrievedChunk) -> Bool in
                let aContent = a.chunk.contextText
                let bContent = b.chunk.contextText
                let aPriority = EvidenceScoringPolicyService.extractivePriorityScore(
                    content: aContent,
                    queryKeywords: discriminativeKeywords,
                    structureType: a.chunk.metadata.structureType
                )
                let bPriority = EvidenceScoringPolicyService.extractivePriorityScore(
                    content: bContent,
                    queryKeywords: discriminativeKeywords,
                    structureType: b.chunk.metadata.structureType
                )

                // Clear advantage outranks relevance; a difference of 1 does not.
                // Expressed as bands rather than an epsilon, because the epsilon
                // form was not a strict weak ordering and left this sort's output
                // undefined. See `extractiveEvidencePrecedes` for the full note and
                // for why the LEDGER's 27.0%/15.2% rank-1 figure needs re-taking.
                return EvidenceScoringPolicyService.extractiveEvidencePrecedes(
                    lhsPriority: aPriority, lhsRelevance: a.similarityScore,
                    rhsPriority: bPriority, rhsRelevance: b.similarityScore
                )
            })
            // Retrieval's best passage stays first, whatever the question's words say (5.7):
            // the keyword priority orders the rest. Sentence extraction below puts it in whole.
            orderedCandidates = Self.leadingWithTopRanked(contextCandidates.first, then: byPriority)
            Log.info(
                "[RAG] Extractive query - prioritizing specs (discriminative: [\(discriminativeKeywords.joined(separator: ", "))])",
                category: .retrieval)
        } else {
            orderedCandidates = contextCandidates
        }

        // For procedural queries, disable "Lost in Middle" reordering to preserve sequence
        let useLostInMiddleMitigation = !isProceduralQuery
        return (orderedCandidates: orderedCandidates, useLostInMiddleMitigation: useLostInMiddleMitigation)
    }

    /// Step 5 (citations): logs the assembled context, lists the passages the prompt labelled and records them for recovery.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func finishIncludedPassages(actualChunksUsed: Int, context: String, question: String, placedForAttention: Bool, contextCandidates: [RetrievedChunk], contextStrategy: String, useCompactMode: Bool, promptSources: [RetrievedChunk], rescuedChunks: [RetrievedChunk], recoveryRetrievedChunks: inout [RetrievedChunk]) -> (contextWords: Int, contextSize: Int, includedRetrievedChunks: [RetrievedChunk], includedChunks: [DocumentChunk]) {
        // Universal pipeline trace: log final assembled context
        if Log.pipelineTraceEnabled {
            logFinalContext(context, actualChunksUsed: actualChunksUsed, query: question)
        }

        // Emit lost-in-middle event if it was applied
        if placedForAttention {
            emitThinkingEvent(
                .lostInMiddle,
                title: "Position reorder",
                detail: "Attention-optimal placement"
            )
        }

        Log.info(
            "   ✓ Using \(actualChunksUsed)/\(contextCandidates.count) chunks (\(context.count) chars)\(useCompactMode ? " [compact]" : "") • \(contextStrategy)",
            category: .pipeline
        )

        let contextSize = context.count
        let contextWords = context.split(separator: " ").count
        // BUGFIX: Use orderedCandidates (post-sort) not contextCandidates (pre-sort).
        // Previously, spec prioritization sorted candidates but the slicing used the
        // original unsorted array, so fuse-box tables could be selected over oil specs.
        // The packed prefix plus anything needle rescue contributed. Appending in this
        // order is what makes the labels correct: rescue labels start at `assembled.used`,
        // which is exactly where the prefix ends.
        let includedRetrievedChunks = promptSources + rescuedChunks

        // The citation map: which document each [Sn] the model was shown actually resolves
        // to. Nothing printed this, which is why labels could point at the wrong document
        // for an unknown length of time while every guard passed: the indices were in
        // range, the chunks were real, and only the mapping was wrong. With this line a
        // cited answer can be checked against its sources by reading one log entry.
        logCitationMap(includedRetrievedChunks, rescued: rescuedChunks.count, route: "standard")
        // let precisionLookupCandidates = buildPrecisionLookupCandidates(
        //     included: includedRetrievedChunks,
        //     ordered: orderedCandidates,
        //     desiredCount: max(actualChunksUsed + 6, 16)
        // )
        let includedChunks = includedRetrievedChunks.map { $0.chunk }
        recoveryRetrievedChunks = includedRetrievedChunks
        return (contextWords: contextWords, contextSize: contextSize, includedRetrievedChunks: includedRetrievedChunks, includedChunks: includedChunks)
    }

    /// Step SV: computes the pre-generation confidence and decides whether the Evidence-First prompt is used.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func assessEvidenceBeforeGeneration(includedRetrievedChunks: [RetrievedChunk], actualChunksUsed: Int, auditAvgTop5: Float, auditDynamicMin: Float, lexicalRelevance: Float, isProceduralQuery: Bool) -> (useEvidenceFirstMode: Bool, uniqueSourceDocs: Int, bestRetrievalSim: Float) {
        // EVIDENCE-FIRST GATE: Check retrieval quality BEFORE generation
        // If evidence is weak, switch to Evidence-First mode instead of generating verbosely
        // Key insight: P(all claims correct) = p^N where N = number of claims
        // With weak evidence (p=0.92) and N=50 claims: 0.92^50 ≈ 1.5% chance of being fully correct
        let bestRetrievalSim = includedRetrievedChunks.first?.similarityScore ?? 0
        let avgRetrievalSim =
            includedRetrievedChunks.isEmpty
            ? 0
            : includedRetrievedChunks.map { $0.similarityScore }.reduce(0, +)
                / Float(includedRetrievedChunks.count)
        let uniqueSourceDocs = Set(includedRetrievedChunks.map { $0.chunk.documentId }).count

        // Pre-generation confidence estimate
        let preGenConfidence: Float = {
            var score: Float = 0.5
            if bestRetrievalSim >= 0.35 { score += 0.15 }
            if avgRetrievalSim >= 0.28 { score += 0.10 }
            if uniqueSourceDocs >= 2 { score += 0.10 }
            if actualChunksUsed >= 5 { score += 0.10 }
            return min(1.0, score)
        }()

        // Evidence-First mode triggers:
        // 1. Best similarity below threshold
        // 2. Low pre-generation confidence
        // 3. Average top-5 similarity below the dynamic minimum (key insight: if avgTop5 < dynamicMin, evidence is weak)
        let avgTop5BelowThreshold = auditAvgTop5 < auditDynamicMin
        let topicalMismatch = lexicalRelevance < 0.20
        let evidenceIsWeak =
            bestRetrievalSim < 0.25 || preGenConfidence < 0.70 || avgTop5BelowThreshold || topicalMismatch
        let useEvidenceFirstMode = evidenceIsWeak && (isProceduralQuery || topicalMismatch)

        if useEvidenceFirstMode {
            let triggerReason: String
            if topicalMismatch {
                triggerReason =
                    "topical mismatch (lexical relevance \(String(format: "%.0f%%", lexicalRelevance * 100)) < 20%)"
            } else if avgTop5BelowThreshold {
                triggerReason =
                    "avgTop5 (\(String(format: "%.2f", auditAvgTop5))) < dynamicMin (\(String(format: "%.2f", auditDynamicMin)))"
            } else if bestRetrievalSim < 0.25 {
                triggerReason = "bestSim (\(String(format: "%.2f", bestRetrievalSim))) < 0.25"
            } else {
                triggerReason = "preGenConf (\(String(format: "%.2f", preGenConfidence))) < 0.70"
            }
            Log.warning("[RAG] Evidence-First mode triggered: \(triggerReason)", category: .retrieval)
            emitThinkingEvent(
                .warning,
                title: "Evidence-First mode",
                detail: "Low confidence (\(String(format: "%.0f", preGenConfidence * 100))%) - \(triggerReason)"
            )
        }
        return (useEvidenceFirstMode: useEvidenceFirstMode, uniqueSourceDocs: uniqueSourceDocs, bestRetrievalSim: bestRetrievalSim)
    }

}
