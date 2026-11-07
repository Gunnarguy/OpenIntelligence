//
//  RAGService+QueryRetrieval.swift
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
    /// Step 3 (iterative): runs multi-pass iterative retrieval with self-correction.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runIterativeRetrieval(iterativeConfig: IterativeRetrievalConfig, adjustedVectorWeight: Float, adjustedKeywordWeight: Float, queryEmbeddingService: EmbeddingService, expandedQueries: [String], effectiveQuery: String, originalKeywordQuery: String?, vdb: any VectorDatabase, effectiveTopK: Int, filteredCachedChunks: [DocumentChunk]?, answerIntent: AnswerIntent, retrievedChunks: inout [RetrievedChunk], iterativeMetadata: inout (iterations: Int, confidence: Float, queries: Int)?, auditUsedIterativeRetrieval: inout Bool, auditIterativePassCount: inout Int) async throws {
        // Multi-pass iterative retrieval with self-correction
        Log.section(
            "Step 3: Iterative Retrieval (\(iterativeConfig.maxIterations) max passes)",
            level: .info,
            category: .pipeline
        )

        // Pipeline Trace: Step 3 (Iterative)
        Log.pipelineStep(
            "3", title: "Iterative Retrieval",
            details: [
                ("maxPasses", "\(iterativeConfig.maxIterations)"),
                ("targetConf", String(format: "%.0f%%", iterativeConfig.confidenceThreshold * 100)),
            ])
        emitThinkingEvent(
            .retrieval,
            title: "Multi-pass retrieval",
            detail:
                "Up to \(iterativeConfig.maxIterations) iterations for confidence ≥\(Int(iterativeConfig.confidenceThreshold * 100))%"
        )

        let iterativeService = IterativeRetrievalService(
            hybridSearchFactory: { db in
                HybridSearchService(
                    vectorDatabase: db,
                    vectorWeight: adjustedVectorWeight,
                    keywordWeight: adjustedKeywordWeight
                )
            },
            embeddingService: queryEmbeddingService
        )

        // Pass cached chunks to avoid redundant allChunks() calls in iterative retrieval
        let iterativeResult = try await iterativeService.retrieve(
            query: expandedQueries.joined(separator: " "),
            originalQuery: originalKeywordQuery ?? effectiveQuery,
            vectorDatabase: vdb,
            config: iterativeConfig,
            topK: effectiveTopK,
            cachedChunks: filteredCachedChunks,
            isOverviewQuery: answerIntent == .summarize
        )

        retrievedChunks = iterativeResult.allChunks
        iterativeMetadata = (
            iterations: iterativeResult.iterations,
            confidence: iterativeResult.confidence,
            queries: iterativeResult.queriesUsed.count
        )
        auditUsedIterativeRetrieval = true
        auditIterativePassCount = iterativeResult.iterations

        Log.info(
            "✓ Iterative retrieval complete: \(iterativeResult.iterations) passes, "
                + "\(retrievedChunks.count) chunks, confidence \(String(format: "%.0f", iterativeResult.confidence * 100))%",
            category: .retrieval
        )
        TelemetryCenter.emit(
            .retrieval,
            title: "Iterative retrieval complete",
            metadata: [
                "iterations": "\(iterativeResult.iterations)",
                "chunks": "\(retrievedChunks.count)",
                "confidence": String(format: "%.2f", iterativeResult.confidence),
                "queries": "\(iterativeResult.queriesUsed.count)",
                "hitMax": "\(iterativeResult.hitMaxIterations)",
            ],
            duration: iterativeResult.totalTime
        )
        emitThinkingEvent(
            .retrieval,
            title: "Retrieval complete",
            detail:
                "\(iterativeResult.iterations) passes → \(retrievedChunks.count) chunks (\(Int(iterativeResult.confidence * 100))% confidence)"
        )
    }

    /// Step 6 (route plan): applies the post-retrieval model plan (Private Cloud Compute envelope, consent, local fallback, abstain).
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyPostRetrievalModelPlan(uniqueSourceDocs: Int, answerIntent: AnswerIntent, qualityMode: RAGQualityMode, promptForGeneration: String, generationContext: inout String, genConfig: inout InferenceConfig, generationRetrievedChunks: inout [RetrievedChunk], cloudConsentState: CloudConsentState, networkAvailable: Bool, question: String, generationChunks: inout [DocumentChunk], engine: RAGEngine, orderedCandidates: [RetrievedChunk], useLostInMiddleMitigation: Bool) async throws {
        if ModelRoutingFeatureFlags.plannerV1Enabled,
            llmService is AppleFoundationLLMService
        {
            let requiresMultiDocumentSynthesis: Bool = {
                guard uniqueSourceDocs > 1 else { return false }
                switch answerIntent {
                case .compare, .investigate, .findings, .compute:
                    return true
                default:
                    return qualityMode.canonical != .standard
                }
            }()
            let planned = await makePostRetrievalModelPlan(
                prompt: promptForGeneration,
                context: generationContext,
                config: genConfig,
                chunks: generationRetrievedChunks,
                consentState: cloudConsentState,
                networkAvailable: networkAvailable,
                requiresMultiDocumentSynthesis: requiresMultiDocumentSynthesis
            )
            let plan = planned.plan
            genConfig.modelExecutionPlan = plan

            switch plan.synthesisTarget {
            case .privateCloudCompute:
                let maximumCloudCharacters = max(
                    800,
                    min(
                        generationContext.count,
                        Int(
                            Double(plan.contextBudget.remaining + plan.contextBudget.evidence)
                                * FoundationModelTokenBudget.cloudFallbackCharsPerToken)
                    )
                )
                let envelope = CloudEvidenceMinimizer().makeEnvelope(
                    plan: plan,
                    query: question,
                    chunks: generationRetrievedChunks,
                    maximumCharacters: maximumCloudCharacters
                )
                generationContext = renderCloudEvidenceEnvelope(envelope)
                // The envelope numbers its evidence [S1], [S2] ... in its own order, by rank, so the answer
                // keeps the passages in that order (5.7). Filtered in the local order, a label could open
                // the passage at that place in the local list (found by review, 2026-10-20).
                generationRetrievedChunks = Self.passages(generationRetrievedChunks, inTheOrderOf: envelope)
                generationChunks = generationRetrievedChunks.map(\.chunk)

                do {
                    try await ensureCloudConsentIfNeeded(
                        service: llmService,
                        prompt: promptForGeneration,
                        context: generationContext,
                        sourceChunks: generationChunks,
                        allowPrivateCloudCompute: genConfig.allowPrivateCloudCompute,
                        modelExecutionPlan: plan
                    )
                } catch let error as RAGServiceError {
                    let canFallback = plan.fallback.target == .onDevice
                    switch error {
                    case .cloudConsentDenied(_), .cloudConsentUnavailable(_):
                        guard canFallback else { throw error }
                        let nonEvidenceTokens = planned.localBudget.used - planned.localBudget.evidence
                        let localEvidenceTokens = max(
                            256,
                            planned.localBudget.contextSize - nonEvidenceTokens
                        )
                        let localMaxCharacters = min(
                            10_000,
                            max(
                                800,
                                Int(
                                    Double(localEvidenceTokens)
                                        * FoundationModelTokenBudget.onDeviceCharsPerToken)
                            )
                        )
                        let localAssembly = await engine.assembleContext(
                            chunks: orderedCandidates,
                            maxChars: localMaxCharacters,
                            compact: true,
                            useLostInMiddleMitigation: useLostInMiddleMitigation
                        )
                        generationContext = localAssembly.context
                        // Label order, not input order. See assembleContext.
                        generationRetrievedChunks = localAssembly.sources
                        generationChunks = generationRetrievedChunks.map(\.chunk)
                        genConfig.executionContext = .onDeviceOnly
                        genConfig.allowPrivateCloudCompute = false
                        Log.info(
                            "[ModelRouter] PCC consent unavailable/denied → local fallback for plan \(plan.id)",
                            category: .pipeline
                        )
                    default:
                        throw error
                    }
                }
            case .onDevice, .deterministic:
                if !planned.localBudget.fits {
                    let nonEvidenceTokens = planned.localBudget.used - planned.localBudget.evidence
                    let localEvidenceTokens = max(
                        256,
                        planned.localBudget.contextSize - nonEvidenceTokens
                    )
                    let localAssembly = await engine.assembleContext(
                        chunks: orderedCandidates,
                        maxChars: min(
                            10_000,
                            max(
                                800,
                                Int(
                                    Double(localEvidenceTokens)
                                        * FoundationModelTokenBudget.onDeviceCharsPerToken)
                            )
                        ),
                        compact: true,
                        useLostInMiddleMitigation: useLostInMiddleMitigation
                    )
                    generationContext = localAssembly.context
                    // Label order, not input order. See assembleContext.
                    generationRetrievedChunks = localAssembly.sources
                    generationChunks = generationRetrievedChunks.map(\.chunk)
                }
                genConfig.executionContext = .onDeviceOnly
            case .abstain:
                // The planner declined to route. That is not the same as
                // the model being unavailable, and reporting it that way
                // has now sent two separate debugging sessions after a
                // model that was working. Device log 2026-08-03: this
                // fired, then on-device generation completed 32 words
                // 4 seconds later.
                //
                // Log what the planner actually saw so the next
                // occurrence names its own cause instead of blaming the
                // model, and surface a truthful error.
                Log.warning(
                    """
                    [RAGService] Planner abstained with \(generationChunks.count) chunk(s) available \
                    (top score \(String(format: "%.2f", orderedCandidates.first?.similarityScore ?? 0))). \
                    This is a routing decision, not model unavailability.
                    """,
                    category: .pipeline
                )
                throw RAGServiceError.routingAbstained
            }

            TelemetryCenter.emit(
                .generation,
                title: "Post-retrieval model route selected",
                metadata: [
                    "planID": plan.id.uuidString,
                    "policy": plan.policyVersion,
                    "target": plan.synthesisTarget.rawValue,
                    "reason": plan.stages.first(where: { $0.role == .synthesize })?.reason.rawValue
                        ?? "unknown",
                    "quota": plan.pccQuotaAtPlanning.rawValue,
                    "budgetSource": plan.contextBudget.source.rawValue,
                    "evidenceChunks": "\(plan.evidence.chunkCount)",
                    "evidenceTokens": "\(plan.evidence.estimatedEvidenceTokens)",
                ]
            )
        }
    }

    /// Step 3 (single pass): runs the hybrid vector and BM25 search.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runHybridSearch(adjustedVectorWeight: Float, adjustedKeywordWeight: Float, effectiveTopK: Int, queryIntent: QueryIntent, vdb: any VectorDatabase, retrievedChunks: inout [RetrievedChunk], expandedQueries: [String], effectiveQuery: String, originalKeywordQuery: String?, queryEmbedding: [Float], filteredCachedChunks: [DocumentChunk]?, selectedId: UUID, answerIntent: AnswerIntent, trace: RetrievalTraceCollector?) async throws {
        // Single-pass hybrid search (original behavior)
        Log.section(
            "Step 3: Hybrid Search (Vector + BM25)", level: .info, category: .pipeline
        )

        // Pipeline Trace: Step 3 (Single-pass)
        Log.pipelineStep(
            "3", title: "Hybrid Search",
            details: [
                ("vector", String(format: "%.0f%%", adjustedVectorWeight * 100)),
                ("BM25", String(format: "%.0f%%", adjustedKeywordWeight * 100)),
                ("topK", "\(effectiveTopK * 3)"),
            ])

        Log.debug(
            "[RAGService] Query intent: \(queryIntent.rawValue) → weights adjusted to vector=\(String(format: "%.2f", adjustedVectorWeight)), keyword=\(String(format: "%.2f", adjustedKeywordWeight))",
            category: .retrieval
        )

        let hybridSearch = HybridSearchService(
            vectorDatabase: vdb,
            vectorWeight: adjustedVectorWeight,
            keywordWeight: adjustedKeywordWeight
        )
        // Use expanded queries for keyword search (original for vector)
        // Pass cached chunks to avoid redundant allChunks() call in lexical recall
        // For RAPTOR-lite: filteredCachedChunks may be limited to summaries for overview queries
        // Pass containerId to enable FTS5-accelerated BM25 (10-100X faster than in-memory)
        retrievedChunks = try await hybridSearch.search(
            query: expandedQueries.joined(separator: " "),
            originalQuery: originalKeywordQuery ?? effectiveQuery,
            embedding: queryEmbedding,
            topK: effectiveTopK * 3,
            cachedChunks: filteredCachedChunks,
            containerId: selectedId,
            isOverviewQuery: answerIntent == .summarize,
            trace: trace
        )
    }

    /// Step 3 (multi-vector): adds passages from vector searches on up to two appended query expansions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runSupplementaryVectorSearch(answerIntentIsExtractive: Bool, isTrivial: Bool, expandedQueries: [String], retrievedChunks: inout [RetrievedChunk], effectiveQuery: String, textToEmbed: String, selectedContainer: KnowledgeContainer?, queryEmbeddingService: EmbeddingService, vdb: any VectorDatabase, effectiveTopK: Int, auditUsedSupplementaryVectorSearch: inout Bool, answerIntent: AnswerIntent) async {
        // UNIVERSAL FIX 9: Multi-vector supplementary retrieval.
        // The primary search uses ONE embedding (HyDE or rewritten query).
        // Query expansion generates ~12 variations but only uses them for BM25 text.
        // Problem: if the primary embedding misses a needle due to vocabulary mismatch,
        // it's invisible forever. Fix: embed top-2 unique expansion variations, run
        // supplementary vector-only searches, merge any NEW chunks into results.
        // This catches needles that exist in a different embedding neighborhood.
        //
        // CRITICAL: Only use APPENDED expansions (contain original query as substring),
        // NOT replacement expansions. Synonym replacement queries like
        // "What vehicle of oil does this automobile takes" embed into a completely
        // different semantic neighborhood and pull in irrelevant chunks.
        // Appended queries like "oil type specification SAE" stay on-topic.
        let allowSupplementaryVectorSearch = !answerIntentIsExtractive && !isTrivial
        if allowSupplementaryVectorSearch && expandedQueries.count > 1 {
            let existingChunkIds = Set(retrievedChunks.map { $0.chunk.id })
            let effectiveQueryLower = effectiveQuery.lowercased()
            // Pick up to 2 expansions that:
            // 1. Differ from the primary embedding text
            // 2. Are sufficiently long
            // 3. CONTAIN the original query (appended terms, not replacements)
            //    OR are corpus phrase expansions (short focused phrases)
            let supplementaryQueries =
                expandedQueries
                .filter { expansion in
                    expansion != textToEmbed && expansion != effectiveQuery && expansion.count >= 10
                        && (expansion.lowercased().hasPrefix(effectiveQueryLower)
                            || expansion.count < effectiveQuery.count)  // Corpus phrases are shorter
                }
                .prefix(2)

            if !supplementaryQueries.isEmpty {
                Log.debug(
                    "[MultiVector] Running \(supplementaryQueries.count) supplementary vector searches",
                    category: .retrieval)
                for suppQuery in supplementaryQueries {
                    do {
                        let translatedSupplementaryQuery = await translatedQueryForEmbedding(
                            suppQuery, container: selectedContainer)
                        let suppEmbedding = try await queryEmbeddingService.generateEmbedding(
                            for: translatedSupplementaryQuery.text)
                        let suppResults = try await vdb.search(
                            embedding: suppEmbedding, topK: effectiveTopK)
                        let newChunks = suppResults.filter { !existingChunkIds.contains($0.chunk.id) }
                        if !newChunks.isEmpty {
                            auditUsedSupplementaryVectorSearch = true
                            retrievedChunks.append(contentsOf: newChunks)
                            Log.debug(
                                "[MultiVector] +\(newChunks.count) new chunks from expansion: \"\(suppQuery.prefix(50))...\"",
                                category: .retrieval)
                        }
                    } catch {
                        Log.debug(
                            "[MultiVector] Supplementary search failed: \(error.localizedDescription)",
                            category: .retrieval)
                    }
                }
            }
        } else if answerIntentIsExtractive && expandedQueries.count > 1 {
            Log.debug(
                "[MultiVector] Supplementary vector search skipped for extractive intent '\(answerIntent.rawValue)'",
                category: .retrieval)
        }
    }

    /// Step SC (write): stores a live search's passages in the semantic query cache.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func writeSemanticQueryCache(exactCacheHit: Bool, isDocumentScoped: Bool, retrievedChunks: [RetrievedChunk], cacheKey: String, selectedId: UUID, queryEmbedding: [Float], normalizedQueryText: String) async {
        // ─ Write to Semantic Cache ─────────────────────────────────────────────────────
        // Only persist when we actually ran the live search (not on cache hits)
        if !exactCacheHit && !retrievedChunks.isEmpty && !isDocumentScoped {
            await SQLiteFullTextService.shared.cacheQuery(
                normalizedQuery: cacheKey,
                containerId: selectedId,
                embedding: queryEmbedding,
                results: retrievedChunks
            )
            Log.debug(
                "[RAGService] Wrote \(retrievedChunks.count) chunks to semantic cache for query: '\(normalizedQueryText)'",
                category: .pipeline)
        }
        // ────────────────────────────────────────────────────────────────────────────
    }

    /// Step S3s: narrows the retrieved and cached pools to the documents a Shortcuts action named.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyDocumentScope(retrievedChunks: inout [RetrievedChunk], cachedAllChunks: inout [DocumentChunk]?, filteredCachedChunks: inout [DocumentChunk]?) throws {
        // Document scope (set by the Shortcuts actions that name a document). Every search
        // above went through `HybridSearchService.search`, which searches inside the named
        // documents when a scope is set. This narrows what did not: passages added by a
        // direct vector search, and the two candidate lists the later stages (parent
        // expansion, summaries, enumeration, multi-hop) draw on. A scoped question with no
        // passage is an error; the general fallback would answer it from the model alone.
        if let scope = RAGQueryScope.documentIds, !scope.isEmpty {
            let before = retrievedChunks.count
            retrievedChunks = RAGQueryScope.apply(to: retrievedChunks)
            cachedAllChunks = cachedAllChunks.map { RAGQueryScope.apply(to: $0) }
            filteredCachedChunks = filteredCachedChunks.map { RAGQueryScope.apply(to: $0) }
            Log.info(
                "[RAGService] Document scope: \(retrievedChunks.count) of \(before) retrieved passages are in the \(scope.count) named document(s)",
                category: .retrieval)
            if retrievedChunks.isEmpty {
                throw RAGQueryScopeEmptyError()
            }
        }
    }

    /// Step S3k: drops passages whose document is in no library.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func dropPassagesOfUnknownDocuments(retrievedChunks: inout [RetrievedChunk]) async {
        // Passages whose document is in no library are left out (5.7, `passagesFromKnownDocuments`).
        let liveDocumentIds = await MainActor.run { Set(self.documents.map(\.id)) }
        let fromKnownDocuments = Self.passagesFromKnownDocuments(
            retrievedChunks, knownDocumentIds: liveDocumentIds)
        if fromKnownDocuments.dropped > 0 {
            Log.warning(
                "[RAGService] Left out \(fromKnownDocuments.dropped) passage(s) whose document is in no library",
                category: .retrieval)
            retrievedChunks = fromKnownDocuments.kept
        }
    }

    /// Step S3n: attaches source names, demotes interrogative FAQ passages and emits the retrieval telemetry.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func attachSourcesAndDemoteQuestions(retrievedChunks: [RetrievedChunk], question: String, auditCandidatesCount: inout Int, recoveryRetrievedChunks: inout [RetrievedChunk], effectiveTopK: Int, selectedName: String, selectedId: UUID, retrievalTime: TimeInterval, adjustedVectorWeight: Float, adjustedKeywordWeight: Float) async -> (chunksWithSources: [RetrievedChunk], docsSnapshot: [Document]) {
        // Add source information for citations with a safe MainActor snapshot
        let docsSnapshot = await snapshotDocuments()
        var chunksWithSources: [RetrievedChunk] = retrievedChunks.map { retrieved in
            let docName =
                docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                ?? (retrieved.sourceDocument.isEmpty ? "Unknown" : retrieved.sourceDocument)
            let pageNum = retrieved.chunk.metadata.pageNumber
            return RetrievedChunk(
                chunk: retrieved.chunk,
                similarityScore: retrieved.similarityScore,
                rank: retrieved.rank,
                sourceDocument: docName,
                pageNumber: pageNum
            )
        }
        // Demote purely interrogative chunks if the query isn't asking about questions/examples
        var demotedCount = 0
        for i in 0..<chunksWithSources.count {
            if isInterrogativeChunk(chunksWithSources[i].chunk, query: question) {
                let originalScore = chunksWithSources[i].similarityScore
                chunksWithSources[i] = RetrievedChunk(
                    chunk: chunksWithSources[i].chunk,
                    similarityScore: originalScore * 0.1,  // Demote severely
                    rank: chunksWithSources[i].rank,
                    sourceDocument: chunksWithSources[i].sourceDocument,
                    pageNumber: chunksWithSources[i].pageNumber
                )
                demotedCount += 1
            }
        }
        if demotedCount > 0 {
            chunksWithSources.sort { $0.similarityScore > $1.similarityScore }
            Log.info(
                "[RAG] Demoted \(demotedCount) interrogative FAQ chunks to prevent context poisoning.",
                category: .retrieval)
        }

        auditCandidatesCount = chunksWithSources.count
        recoveryRetrievedChunks = chunksWithSources

        let chunkWordCounts = chunksWithSources.map { wordCount(of: $0.chunk.content) }
        let totalChunkWords = chunkWordCounts.reduce(0, +)
        let topContextWords = chunkWordCounts.prefix(effectiveTopK).reduce(0, +)
        let averageChunkWords =
            chunkWordCounts.isEmpty
            ? 0.0
            : Double(totalChunkWords) / Double(chunkWordCounts.count)

        TelemetryCenter.emit(
            .retrieval,
            title: "Hybrid retrieval",
            metadata: [
                "candidates": "\(chunksWithSources.count)",
                "topK": "\(effectiveTopK * 2)",
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "totalWords": "\(totalChunkWords)",
                "topWords": "\(topContextWords)",
                "avgWords": String(format: "%.1f", averageChunkWords),
            ],
            duration: retrievalTime
        )

        // Emit detailed technique events for full transparency
        emitThinkingEvent(
            .vectorSearch,
            title: "Vector search",
            detail: "Semantic similarity • \(Int(adjustedVectorWeight * 100))% weight"
        )
        emitThinkingEvent(
            .bm25,
            title: "BM25 search",
            detail: "Keyword matching • \(Int(adjustedKeywordWeight * 100))% weight"
        )
        emitThinkingEvent(
            .rrf,
            title: "RRF fusion",
            detail: "\(chunksWithSources.count) candidates merged"
        )

        Log.info(
            "✓ Retrieved \(chunksWithSources.count) chunks with hybrid fusion",
            category: .retrieval
        )

        // Universal pipeline trace: log chunks after hybrid search
        if Log.pipelineTraceEnabled {
            logChunkTrace(chunksWithSources, stage: "Post-HybridSearch", query: question)
        }
        return (chunksWithSources: chunksWithSources, docsSnapshot: docsSnapshot)
    }

    /// Step 4: re-ranks the candidates (cross-encoder or similarity order) and records the rerank trace stage.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func rerankCandidates(qualityModeUsesReRanking: Bool, chunksWithSources: [RetrievedChunk], question: String, effectiveTopK: Int, auditRerankedCount: inout Int, qualityModeDisplayName: String, trace: RetrievalTraceCollector?) async -> (engine: RAGEngine, rerankTime: TimeInterval, rerankedChunks: [RetrievedChunk]) {
        // Step 4: Re-rank results with multiple signals
        // QUALITY MODE: Check if re-ranking is enabled
        let engine = RAGEngine.shared
        let rerankStartTime = Date()
        var rerankedChunks: [RetrievedChunk]
        var rerankTime: TimeInterval = 0

        if qualityModeUsesReRanking {
            Log.section("Step 4: Multi-Signal Re-ranking", level: .info, category: .pipeline)

            // Pipeline Trace: Step 4
            Log.pipelineStep(
                "4", title: "Multi-Signal Reranking",
                details: [
                    ("candidates", "\(chunksWithSources.count)")
                ])

            rerankedChunks = await engine.rerank(
                chunks: chunksWithSources,
                query: question,
                topK: effectiveTopK * 3  // Get more candidates for MMR diversification (clamped)
            )
            auditRerankedCount = rerankedChunks.count
            rerankTime = Date().timeIntervalSince(rerankStartTime)
            Log.info(
                "✓ Re-ranked to top \(rerankedChunks.count) in \(String(format: "%.0f", rerankTime * 1000))ms",
                category: .retrieval
            )

            // Universal pipeline trace: log chunks after re-ranking
            if Log.pipelineTraceEnabled {
                logChunkTrace(rerankedChunks, stage: "Post-Rerank", query: question)
            }

            TelemetryCenter.emit(
                .retrieval,
                title: "Re-ranking complete",
                metadata: [
                    "candidates": "\(rerankedChunks.count)"
                ],
                duration: rerankTime
            )
            emitThinkingEvent(
                .rerank,
                title: "Cross-encoder rerank",
                detail: "\(rerankedChunks.count) candidates scored"
            )
        } else {
            Log.info("[RAG] Re-ranking skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
            // Use chunks as-is, sorted by existing scores
            rerankedChunks = chunksWithSources.sorted { $0.similarityScore > $1.similarityScore }
            rerankedChunks = Array(rerankedChunks.prefix(effectiveTopK * 3))
            auditRerankedCount = rerankedChunks.count
            rerankTime = Date().timeIntervalSince(rerankStartTime)
            emitThinkingEvent(
                .rerank,
                title: "Re-ranking skipped",
                detail: "Quality mode: \(qualityModeDisplayName)"
            )
        }

        // Stage capture for the retrieval benchmark. Recorded after the if/else so it
        // covers both branches: when the quality mode skips the cross-encoder,
        // `rerankedChunks` is a score-sorted passthrough and the stage still describes what
        // the pipeline handed onward. Recording only inside the reranking branch would make
        // the stage silently absent for Standard mode, which is the mode with the measured
        // baseline and therefore the one most likely to be benchmarked.
        trace?.record(.rerank, results: rerankedChunks)
        return (engine: engine, rerankTime: rerankTime, rerankedChunks: rerankedChunks)
    }

    /// Step S4c: runs the lexical-heavy cascade search and re-rank when the policy asks for it.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func runRetrievalCascade(rerankedChunks: inout [RetrievedChunk], effectiveQueryProfile: QueryProfile, qualityMode: RAGQualityMode, retrievalConfig: RetrievalConfig, effectiveTopK: Int, totalStored: Int, usedRetrievalCascade: inout Bool, expandedQueries: [String], question: String, vdb: any VectorDatabase, originalKeywordQuery: String?, queryEmbedding: [Float], docsSnapshot: [Document], engine: RAGEngine, auditCandidatesCount: inout Int, auditRerankedCount: inout Int, retrievalTime: inout TimeInterval, rerankTime: inout TimeInterval, recoveryRetrievalTime: inout TimeInterval) async throws {
        let cascadeTopSim = rerankedChunks.first?.similarityScore ?? 0
        let cascadeAvgTop5: Float = {
            let sims = rerankedChunks.prefix(5).map { $0.similarityScore }
            guard !sims.isEmpty else { return 0 }
            return sims.reduce(0, +) / Float(sims.count)
        }()
        let cascadeMetrics = RetrievalMetrics(
            topSimilarity: cascadeTopSim,
            secondSimilarity: 0,
            averageTopFive: cascadeAvgTop5,
            candidateCount: rerankedChunks.count
        )

        if let cascadeDecision = RetrievalPolicyService.cascadeDecision(
            for: effectiveQueryProfile,
            qualityMode: qualityMode,
            retrievalConfig: retrievalConfig,
            effectiveTopK: effectiveTopK,
            totalStored: totalStored,
            metrics: cascadeMetrics,
            usedRetrievalCascade: usedRetrievalCascade
        ) {
            let baseCandidateCount = rerankedChunks.count
            let cascadeStartTime = Date()
            let cascadeQuery = (expandedQueries + [question]).joined(separator: " ")
            let cascadeHybrid = HybridSearchService(
                vectorDatabase: vdb,
                vectorWeight: cascadeDecision.vectorWeight,
                keywordWeight: cascadeDecision.lexicalWeight
            )
            let cascadeRetrieved = try await cascadeHybrid.search(
                query: cascadeQuery,
                originalQuery: originalKeywordQuery ?? question,
                embedding: queryEmbedding,
                topK: cascadeDecision.topK
            )

            let cascadeTime = Date().timeIntervalSince(cascadeStartTime)
            if !cascadeRetrieved.isEmpty {
                let cascadeChunksWithSources: [RetrievedChunk] = cascadeRetrieved.map { retrieved in
                    let docName =
                        docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                        ?? "Unknown"
                    let pageNum = retrieved.chunk.metadata.pageNumber
                    return RetrievedChunk(
                        chunk: retrieved.chunk,
                        similarityScore: retrieved.similarityScore,
                        rank: retrieved.rank,
                        sourceDocument: docName,
                        pageNumber: pageNum
                    )
                }

                // Passages whose document is in no library are left out here too (5.7,
                // `passagesFromKnownDocuments`): this search runs after the first check, and on 2026-10-19 it
                // brought back the overview of a deleted note, which the answer then cited as "Unknown".
                let cascadeFromKnown = Self.passagesFromKnownDocuments(
                    cascadeChunksWithSources, knownDocumentIds: Set(docsSnapshot.map(\.id)))
                if cascadeFromKnown.dropped > 0 {
                    Log.warning(
                        "[RAGService] Left out \(cascadeFromKnown.dropped) cascade passage(s) whose document is in no library",
                        category: .retrieval)
                }
                let mergedCandidates = mergeUniqueChunks(rerankedChunks, cascadeFromKnown.kept)
                if mergedCandidates.count > rerankedChunks.count {
                    let cascadeRerankStart = Date()
                    rerankedChunks = await engine.rerank(
                        chunks: mergedCandidates,
                        query: question,
                        topK: effectiveTopK * 3
                    )
                    let cascadeRerankTime = Date().timeIntervalSince(cascadeRerankStart)
                    usedRetrievalCascade = true
                    auditCandidatesCount = mergedCandidates.count
                    auditRerankedCount = rerankedChunks.count
                    retrievalTime += cascadeTime
                    rerankTime += cascadeRerankTime
                    recoveryRetrievalTime = retrievalTime

                    let addedCount = max(0, mergedCandidates.count - baseCandidateCount)
                    Log.info(
                        "🔁 Retrieval cascade added \(addedCount) candidates (lexical \(String(format: "%.2f", cascadeDecision.lexicalWeight)))",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Retrieval cascade",
                        metadata: [
                            "candidates": "\(mergedCandidates.count)",
                            "lexicalWeight": String(format: "%.2f", cascadeDecision.lexicalWeight),
                            "vectorWeight": String(format: "%.2f", cascadeDecision.vectorWeight),
                        ],
                        duration: cascadeTime
                    )
                    emitThinkingEvent(
                        .retrieval,
                        title: "Retrieval cascade",
                        detail:
                            "\(mergedCandidates.count) candidates • lex \(String(format: "%.2f", cascadeDecision.lexicalWeight))"
                    )
                }
            }
        }
    }

    /// Step S4k: retries with a cleaned keyword query when the top similarity is below 0.45.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func retryWithCleanKeywordQuery(rerankedChunks: inout [RetrievedChunk], question: String, queryEmbeddingService: EmbeddingService, vdb: any VectorDatabase, effectiveTopK: Int, filteredCachedChunks: [DocumentChunk]?, selectedId: UUID, docsSnapshot: [Document], qualityModeUsesReRanking: Bool, engine: RAGEngine) async {
        // Keyword search fallback retry if top similarity is low (Standard Mode)
        var queryRetryDone = false
        let preRetryTopSim = rerankedChunks.first?.similarityScore ?? 0
        if preRetryTopSim < 0.45 && !queryRetryDone {
            queryRetryDone = true
            let cleanQuery = cleanQueryForKeywordSearch(question)
            if !cleanQuery.isEmpty && cleanQuery != question.lowercased() {
                Log.info(
                    "[RAG] Top similarity \(preRetryTopSim) < 0.45. Retrying search with keywords: \"\(cleanQuery)\"",
                    category: .retrieval)
                emitThinkingEvent(
                    .queryRewrite,
                    title: "Keyword search retry",
                    detail: "Retrying with: \(cleanQuery)"
                )
                do {
                    let cleanEmbedding = try await queryEmbeddingService.generateEmbedding(for: cleanQuery)
                    let retryHybrid = HybridSearchService(
                        vectorDatabase: vdb,
                        vectorWeight: 0.3,  // favor keyword matching for recovery
                        keywordWeight: 0.7
                    )
                    let retryResults = try await retryHybrid.search(
                        query: cleanQuery,
                        originalQuery: cleanQuery,
                        embedding: cleanEmbedding,
                        topK: effectiveTopK * 2,
                        cachedChunks: filteredCachedChunks,
                        containerId: selectedId
                    )

                    // Map with sources
                    let retryChunksWithSources: [RetrievedChunk] = retryResults.map { retrieved in
                        let docName =
                            docsSnapshot.first(where: { $0.id == retrieved.chunk.documentId })?.filename
                            ?? "Unknown"
                        let pageNum = retrieved.chunk.metadata.pageNumber
                        return RetrievedChunk(
                            chunk: retrieved.chunk,
                            similarityScore: retrieved.similarityScore,
                            rank: retrieved.rank,
                            sourceDocument: docName,
                            pageNumber: pageNum
                        )
                    }

                    // Demote any interrogative chunks in the retry candidates as well
                    var cleanedRetryChunks = retryChunksWithSources
                    for i in 0..<cleanedRetryChunks.count {
                        if isInterrogativeChunk(cleanedRetryChunks[i].chunk, query: question) {
                            let originalScore = cleanedRetryChunks[i].similarityScore
                            cleanedRetryChunks[i] = RetrievedChunk(
                                chunk: cleanedRetryChunks[i].chunk,
                                similarityScore: originalScore * 0.1,
                                rank: cleanedRetryChunks[i].rank,
                                sourceDocument: cleanedRetryChunks[i].sourceDocument,
                                pageNumber: cleanedRetryChunks[i].pageNumber
                            )
                        }
                    }

                    // Passages whose document is in no library are left out here too (5.7,
                    // `passagesFromKnownDocuments`), as in the retrieval cascade above.
                    cleanedRetryChunks = Self.passagesFromKnownDocuments(
                        cleanedRetryChunks, knownDocumentIds: Set(docsSnapshot.map(\.id))
                    ).kept

                    // Merge retry results with existing reranked chunks
                    let mergedChunks = mergeUniqueChunks(rerankedChunks, cleanedRetryChunks)

                    // Rerank again!
                    if qualityModeUsesReRanking && !mergedChunks.isEmpty {
                        rerankedChunks = await engine.rerank(
                            chunks: mergedChunks,
                            query: cleanQuery,
                            topK: effectiveTopK * 3
                        )
                    } else {
                        rerankedChunks = mergedChunks.sorted { $0.similarityScore > $1.similarityScore }
                        rerankedChunks = Array(rerankedChunks.prefix(effectiveTopK * 3))
                    }

                    Log.info(
                        "[RAG] Keyword retry completed, new top similarity: \(rerankedChunks.first?.similarityScore ?? 0)",
                        category: .retrieval)
                } catch {
                    Log.warning(
                        "[RAG] Keyword search retry failed: \(error.localizedDescription)", category: .retrieval
                    )
                }
            }
        }
    }

    /// Step 4.3 (filter): computes the adaptive similarity floor and filters the re-ranked passages.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func filterLowConfidenceChunks(auditLenient: inout Bool, rerankedChunks: [RetrievedChunk], auditTopSim: inout Float, auditSecondSim: inout Float, auditAvgTop5: inout Float, effectiveQueryProfile: QueryProfile, qualityMode: RAGQualityMode, retrievalConfig: RetrievalConfig, auditDynamicMin: inout Float, engine: RAGEngine, auditAcceptanceOverride: inout Bool) async -> (dynamicMin: Float, filteredChunks: [RetrievedChunk], acceptanceOverride: Bool, lenient: Bool, topSim: Float, secondSim: Float, avgTop5: Float, vocabularyMismatch: Bool) {
        // Step 4.3: Filter low-confidence chunks using container's retrieval config
        // Adaptive gating: consider "lenient" mode, quality mode, and trivial/short queries
        let lenient = await MainActor.run {
            self.settingsStore?.lenientRetrievalMode ?? false
        }
        auditLenient = lenient

        // Relative-score metrics (computed on reranked results)
        let topSim: Float = rerankedChunks.first?.similarityScore ?? 0
        let secondSim: Float = rerankedChunks.dropFirst().first?.similarityScore ?? 0
        let avgTop5: Float = {
            let sims = rerankedChunks.prefix(5).map { $0.similarityScore }
            guard !sims.isEmpty else { return 0 }
            return sims.reduce(0, +) / Float(sims.count)
        }()
        auditTopSim = topSim
        auditSecondSim = secondSim
        auditAvgTop5 = avgTop5

        let filteringMetrics = RetrievalMetrics(
            topSimilarity: topSim,
            secondSimilarity: secondSim,
            averageTopFive: avgTop5,
            candidateCount: rerankedChunks.count
        )
        let filteringDecision = RetrievalPolicyService.filteringDecision(
            for: effectiveQueryProfile,
            qualityMode: qualityMode,
            retrievalConfig: retrievalConfig,
            lenient: lenient,
            metrics: filteringMetrics
        )
        let dynamicMin = filteringDecision.dynamicMinSimilarity
        let vocabularyMismatch = filteringDecision.vocabularyMismatch

        if vocabularyMismatch {
            Log.info(
                "[RAG] Vocabulary mismatch detected (topSim=\(String(format: "%.2f", topSim)), avgTop5=\(String(format: "%.2f", avgTop5))) - using adaptive floor \(String(format: "%.2f", dynamicMin))",
                category: .retrieval
            )
        } else if effectiveQueryProfile.answerIntent == .procedure {
            Log.info(
                "[RAG] Procedural query detected - requiring higher evidence threshold \(dynamicMin)",
                category: .retrieval)
        }

        auditDynamicMin = dynamicMin
        var filteredChunks = await engine.filterBySimilarity(
            chunks: rerankedChunks,
            min: dynamicMin
        )

        // Acceptance override if relative signals are strong even with modest absolute scores
        // Also override for vocabulary mismatch scenarios where we trust relative ranking
        let acceptanceOverride = filteringDecision.acceptanceOverride
        auditAcceptanceOverride = acceptanceOverride

        TelemetryCenter.emit(
            .retrieval,
            title: "Gating metrics",
            metadata: [
                "minSimilarity": String(format: "%.2f", retrievalConfig.minSimilarity),
                "lenient": lenient ? "true" : "false",
                "topSim": String(format: "%.3f", topSim),
                "secondSim": String(format: "%.3f", secondSim),
                "avgTop5": String(format: "%.3f", avgTop5),
                "dynamicMin": String(format: "%.2f", dynamicMin),
                "override": acceptanceOverride ? "true" : "false",
            ]
        )

        emitThinkingEvent(
            .gating,
            title: "Confidence gate (\(retrievalConfig.summary))",
            detail: "min \(String(format: "%.2f", dynamicMin)) • top \(String(format: "%.2f", topSim))"
        )
        return (dynamicMin: dynamicMin, filteredChunks: filteredChunks, acceptanceOverride: acceptanceOverride, lenient: lenient, topSim: topSim, secondSim: secondSim, avgTop5: avgTop5, vocabularyMismatch: vocabularyMismatch)
    }

    /// Step 4.5: diversifies the filtered passages with MMR (or takes the top K when MMR is off).
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func diversifyWithMMR(retrievalConfig: RetrievalConfig, qualityModeUsesMMR: Bool, qualityModeDisplayName: String, effectiveTopK: Int, filteredChunks: [RetrievedChunk], auditMMRSelectedCount: inout Int, isProceduralQuery: Bool, engine: RAGEngine, queryEmbedding: [Float], selectedId: UUID) async -> (diverseChunks: [RetrievedChunk], mmrTime: TimeInterval) {
        // Step 4.5: Apply MMR for diversity using container's retrieval config
        Log.section("Step 4.5: MMR Diversification", level: .info, category: .pipeline)
        let mmrStartTime = Date()
        var mmrTime: TimeInterval = 0  // Defined at outer scope for final logging

        var diverseChunks: [RetrievedChunk] = []
        var mmrLambda: Float = retrievalConfig.mmrLambda

        // Check if MMR is enabled for this quality mode
        if !qualityModeUsesMMR {
            Log.info(
                "[RAG] MMR diversification skipped (quality mode: \(qualityModeDisplayName))",
                category: .pipeline)
            diverseChunks = Array(filteredChunks.prefix(effectiveTopK))
            auditMMRSelectedCount = diverseChunks.count
            mmrTime = Date().timeIntervalSince(mmrStartTime)
            TelemetryCenter.emit(
                .retrieval,
                title: "MMR skipped",
                metadata: ["reason": "quality_mode", "passed": "\(diverseChunks.count)"],
                duration: mmrTime
            )
        } else {
            // Pipeline Trace: Step 4.5
            Log.pipelineStep(
                "4.5", title: "MMR Diversification",
                details: [
                    ("candidates", "\(filteredChunks.count)"),
                    ("targetK", "\(effectiveTopK)"),
                ])

            // Procedural query override: favor relevance over diversity for step-by-step content
            // Consecutive chunks from same document are valuable context, not redundant
            // Note: isProceduralQuery already defined in Step 4.3.
            // Use the library's retrieval config as the base, override for procedural queries.
            mmrLambda = isProceduralQuery ? max(retrievalConfig.mmrLambda, 0.85) : retrievalConfig.mmrLambda
            if isProceduralQuery {
                Log.info(
                    "[RAG] Procedural query - boosting MMR lambda to \(mmrLambda) (favor sequential chunks)",
                    category: .retrieval)
            }

            diverseChunks = await engine.applyMMR(
                candidates: filteredChunks,
                queryEmbedding: queryEmbedding,
                topK: effectiveTopK,  // Clamped for short queries
                lambda: mmrLambda,
                vectors: await storedVectors(for: filteredChunks, in: selectedId)
            )
            auditMMRSelectedCount = diverseChunks.count
            mmrTime = Date().timeIntervalSince(mmrStartTime)
            Log.info(
                "✓ Selected \(diverseChunks.count) diverse chunks in \(String(format: "%.0f", mmrTime * 1000))ms",
                category: .retrieval
            )
            Log.debug(
                "  λ=\(String(format: "%.2f", mmrLambda)) (\(Int(mmrLambda * 100))% relevance, \(Int((1 - mmrLambda) * 100))% diversity)",
                category: .retrieval)
            let contextWordCounts = diverseChunks.map { wordCount(of: $0.chunk.content) }
            let totalContextWords = contextWordCounts.reduce(0, +)
            let maxContextWords = contextWordCounts.max() ?? 0
            let averageContextWords =
                contextWordCounts.isEmpty
                ? 0.0
                : Double(totalContextWords) / Double(contextWordCounts.count)
            TelemetryCenter.emit(
                .retrieval,
                title: "MMR diversification",
                metadata: [
                    "selected": "\(diverseChunks.count)",
                    "lambda": String(format: "%.2f", mmrLambda),
                    "totalWords": "\(totalContextWords)",
                    "avgWords": String(format: "%.1f", averageContextWords),
                    "maxWords": "\(maxContextWords)",
                ],
                duration: mmrTime
            )

            emitThinkingEvent(
                .mmr,
                title: "MMR diversity",
                detail: "λ=\(String(format: "%.1f", mmrLambda)) • \(diverseChunks.count) selected"
            )
        }
        return (diverseChunks: diverseChunks, mmrTime: mmrTime)
    }

    /// Step 4.6: expands the candidates with sibling passages from their parent sections.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func expandParentDocuments(qualityModeUsesParentDocRetrieval: Bool, adaptiveConfig: AdaptivePipelineConfig, cachedAllChunks: [DocumentChunk]?, contextCandidates: inout [RetrievedChunk], auditUsedParentDocumentRetrieval: inout Bool, effectiveQueryProfile: QueryProfile, qualityMode: RAGQualityMode, qualityModeMaxSiblingChunks: Int, useAgentic: Bool, question: String, contextStrategy: inout String) async {
        // Step 4.6: Parent Document Retrieval (optional)
        // Expand matched chunks to include sibling context from same section/page
        // Respect quality mode toggle, user settings, AND adaptive pipeline (thermal/battery aware)
        let parentDocEnabledBySettings = settingsStore?.enableParentDocumentRetrieval ?? true
        let useParentDocRetrieval =
            qualityModeUsesParentDocRetrieval && parentDocEnabledBySettings
            && adaptiveConfig.enableParentDocumentRetrieval

        if useParentDocRetrieval, contextCandidates.count > 0, let allChunks = cachedAllChunks {
            auditUsedParentDocumentRetrieval = true
            let parentConfig = RetrievalPolicyService.parentDocumentConfig(
                for: effectiveQueryProfile,
                qualityMode: qualityMode,
                maxSiblingChunks: qualityModeMaxSiblingChunks,
                useAgentic: useAgentic
            )
            if effectiveQueryProfile.answerIntent == .procedure {
                Log.info(
                    "[RAG] Procedural query - using maximum parent expansion (8 siblings)", category: .retrieval
                )
            }
            let parentService = ParentDocumentService(config: parentConfig)

            let expansionResult = await parentService.expandWithSiblings(
                retrievedChunks: contextCandidates,
                allChunks: allChunks,
                query: question
            )

            if expansionResult.addedSiblings > 0 {
                contextCandidates = expansionResult.expandedChunks
                contextStrategy = "parent_expanded"

                TelemetryCenter.emit(
                    .retrieval,
                    title: "Parent document expansion",
                    metadata: [
                        "original": "\(expansionResult.originalChunks.count)",
                        "expanded": "\(expansionResult.expandedChunks.count)",
                        "siblings": "\(expansionResult.addedSiblings)",
                        "ratio": String(format: "%.2f", expansionResult.expansionRatio),
                    ]
                )

                emitThinkingEvent(
                    .parentDoc,
                    title: "Parent context expanded",
                    detail:
                        "+\(expansionResult.addedSiblings) siblings • \(expansionResult.expandedChunks.count) total chunks"
                )

                Log.info(
                    "📚 Parent document expansion: \(expansionResult.originalChunks.count) → \(expansionResult.expandedChunks.count) chunks (+\(expansionResult.addedSiblings) siblings)",
                    category: .retrieval
                )

                if Log.pipelineTraceEnabled {
                    logChunkTrace(
                        expansionResult.expandedChunks, stage: "Post-ParentExpansion", query: question)
                }
            }
        }
    }

    /// Step 4.6 (cross references): adds the passages that extractive candidates refer to.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func addCrossReferencedPassages(answerIntentIsExtractive: Bool, contextCandidates: inout [RetrievedChunk], question: String, cachedAllChunks: [DocumentChunk]?) async {
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Step 4.6: Cross-Reference Resolution
        // Technical documents often say "see Section X on page Y". The actual
        // data (spec tables, values) lives in the referenced section but the
        // reranker scores prose cross-references higher than the actual table.
        // Scan retrieved chunks for cross-refs and fetch the referenced content.
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        if answerIntentIsExtractive {
            let crossRefChunks = await resolveCrossReferencesStandard(
                chunks: contextCandidates,
                query: question,
                allChunks: cachedAllChunks ?? []
            )
            if !crossRefChunks.isEmpty {
                // Insert cross-referenced chunks near the top so they survive context assembly
                let existingIds = Set(contextCandidates.map { $0.chunk.id })
                let newChunks = crossRefChunks.filter { !existingIds.contains($0.chunk.id) }
                contextCandidates.insert(contentsOf: newChunks, at: 0)
                Log.info(
                    "[RAG] Cross-reference resolution: +\(newChunks.count) chunks from referenced sections",
                    category: .retrieval)
                emitThinkingEvent(
                    .retrieval, title: "Cross-ref resolved",
                    detail: "+\(newChunks.count) chunks from referenced sections")
            }
        }
    }

    /// Step S3x: inserts OCR and barcode evidence as virtual passages at the front of the retrieved list.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func injectExternalEvidence(externalEvidence: [EvidenceSource]?, retrievedChunks: inout [RetrievedChunk]) {
        // Inject external evidence (like vision OCR or barcodes) as virtual retrieved chunks
        if let externalEvidence = externalEvidence {
            for evidence in externalEvidence {
                switch evidence {
                case .imageOCR(let ocrText, let metadata):
                    let virtualDocId = UUID()
                    let virtualChunk = DocumentChunk(
                        id: UUID(),
                        documentId: virtualDocId,
                        content: ocrText,
                        parentContent: nil,
                        contextualPrefix: nil,
                        embedding: [],
                        metadata: ChunkMetadata(
                            chunkIndex: 0,
                            startPosition: 0,
                            endPosition: ocrText.count,
                            pageNumber: nil,
                            sectionTitle: "Visual OCR Evidence",
                            keywords: metadata.detectedObjects,
                            semanticDensity: 1.0,
                            hasNumericData: false,
                            hasListStructure: false,
                            wordCount: metadata.ocrWordCount,
                            characterCount: ocrText.count,
                            createdAt: metadata.timestamp,
                            structureType: "paragraph",
                            siblingGroupId: nil,
                            siblingCount: nil,
                            entities: [],
                            abbreviations: [:],
                            abstractionLevel: .detail,
                            sectionPath: nil,
                            bboxArray: nil,
                            documentCategory: .general,
                            chunkType: .prose,
                            tableTitle: nil,
                            imageContentType: nil,
                            imageCaption: nil,
                            imageDescription: nil,
                            imageExtractedText: ocrText,
                            imageClassifications: metadata.detectedObjects,
                            hasCrossReferences: false,
                            resolvedReferences: []
                        )
                    )
                    let virtualRetrieved = RetrievedChunk(
                        chunk: virtualChunk,
                        similarityScore: 1.0,
                        rank: 0,
                        sourceDocument: "Camera Capture/Image OCR",
                        pageNumber: nil
                    )
                    retrievedChunks.insert(virtualRetrieved, at: 0)

                case .barcode(let payload):
                    let virtualDocId = UUID()
                    let ocrText = "Barcode scanned payload: \(payload)"
                    let virtualChunk = DocumentChunk(
                        id: UUID(),
                        documentId: virtualDocId,
                        content: ocrText,
                        parentContent: nil,
                        contextualPrefix: nil,
                        embedding: [],
                        metadata: ChunkMetadata(
                            chunkIndex: 0,
                            startPosition: 0,
                            endPosition: ocrText.count,
                            pageNumber: nil,
                            sectionTitle: "Barcode Scanner",
                            keywords: ["barcode"],
                            semanticDensity: 1.0,
                            hasNumericData: true,
                            hasListStructure: false,
                            wordCount: 3,
                            characterCount: ocrText.count,
                            createdAt: Date(),
                            structureType: "paragraph",
                            siblingGroupId: nil,
                            siblingCount: nil,
                            entities: [],
                            abbreviations: [:],
                            abstractionLevel: .detail,
                            sectionPath: nil,
                            bboxArray: nil,
                            documentCategory: .general,
                            chunkType: .prose,
                            tableTitle: nil,
                            imageContentType: nil,
                            imageCaption: nil,
                            imageDescription: nil,
                            imageExtractedText: nil,
                            imageClassifications: nil,
                            hasCrossReferences: false,
                            resolvedReferences: []
                        )
                    )
                    let virtualRetrieved = RetrievedChunk(
                        chunk: virtualChunk,
                        similarityScore: 1.0,
                        rank: 0,
                        sourceDocument: "Barcode Scanner",
                        pageNumber: nil
                    )
                    retrievedChunks.insert(virtualRetrieved, at: 0)
                default:
                    break
                }
            }
        }
    }

    /// Step 3.5: boosts passages whose section metadata matches the question and logs the top passage.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applySectionMetadataBoost(chunksWithSources: inout [RetrievedChunk], question: String, retrievalTime: TimeInterval) {
        // Step 3.5: Section Metadata Boost
        // Boost chunks whose sectionTitle/sectionPath match query keywords.
        // This is THE key signal that distinguishes "Engine Oil" chunks from "Gear Oil" chunks
        // when both contain oil specs with similar embeddings.
        // Requires Fix 1 (Title Case detection) and Fix 2 (.first→.last) to populate sectionTitle correctly.
        let sectionBoostedChunks = Self.applyMetadataBoost(
            chunks: chunksWithSources,
            query: question
        )

        if let boosted = sectionBoostedChunks {
            chunksWithSources = boosted
            Log.debug(
                "[RAGService] Applied section metadata boost to \(chunksWithSources.count) chunks",
                category: .retrieval)
        }

        Log.debug(
            "  Time: \(String(format: "%.0f", retrievalTime * 1000))ms",
            category: .performance
        )
        if let topChunk = chunksWithSources.first {
            Log.debug(
                "  Top semantic score: \(String(format: "%.4f", topChunk.similarityScore))",
                category: .retrieval
            )
            if !topChunk.sourceDocument.isEmpty {
                Log.debug(
                    "  Source: \(topChunk.sourceDocument)\(topChunk.pageNumber.map { " (p. \($0))" } ?? "")",
                    category: .retrieval
                )
            }
            // BM25 and fusion scores would be displayed here once metadata storage is enhanced
        }
    }

    /// Step S4d: applies the contextual-definition boost to the re-ranked list.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func boostContextualDefinitionMatches(contextualDefinitionLookup: Bool, rerankedChunks: inout [RetrievedChunk], question: String) {
        if contextualDefinitionLookup,
            let boostedDefinitionChunks = applyContextualDefinitionBoost(
                chunks: rerankedChunks,
                query: question
            )
        {
            rerankedChunks = boostedDefinitionChunks
            Log.info(
                "[RAG] Contextual definition ranking applied: preferring summary/prose evidence over structured comparison fragments",
                category: .retrieval
            )
        }
    }

    /// Step 4.3 (rescue): reports the dropped passages and rescues specification passages for extractive questions.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func rescueDroppedSpecChunks(filteredChunks: inout [RetrievedChunk], rerankedChunks: [RetrievedChunk], auditDroppedCount: inout Int, dynamicMin: Float, answerIntentIsExtractive: Bool, answerIntent: AnswerIntent) {
        if filteredChunks.count < rerankedChunks.count {
            let dropped = rerankedChunks.count - filteredChunks.count
            auditDroppedCount = dropped
            Log.warning(
                "   ⚠️  Filtered out \(dropped) low-confidence chunks (< \(String(format: "%.2f", dynamicMin)))",
                category: .retrieval
            )
            TelemetryCenter.emit(
                .retrieval,
                severity: .warning,
                title: "Low-confidence filtered",
                metadata: ["dropped": "\(dropped)"]
            )

            // SPEC PRESERVATION: For extractive queries, rescue chunks with actual specification values.
            // Cross-encoders often score table/spec chunks lower (sparse text, dense data)
            // but these are exactly the chunks that contain the answer.
            if answerIntentIsExtractive {
                let filteredIds = Set(filteredChunks.map { $0.chunk.id })
                let droppedChunks = rerankedChunks.filter { !filteredIds.contains($0.chunk.id) }

                // Find dropped chunks with high spec scores
                var rescuedChunks: [RetrievedChunk] = []
                let specThreshold = 5  // Minimum spec pattern score to rescue

                for chunk in droppedChunks {
                    let content = chunk.chunk.contextText
                    let specScore = countSpecPatterns(content)

                    // Also check for table structure (specs often in tables)
                    let isTableChunk =
                        chunk.chunk.metadata.structureType == "table"
                        || content.contains("|") && content.components(separatedBy: "|").count >= 4

                    // Rescue if high spec score OR table chunk with decent spec score
                    if specScore >= specThreshold || (isTableChunk && specScore >= 3) {
                        rescuedChunks.append(chunk)
                    }
                }

                if !rescuedChunks.isEmpty {
                    let maxRescue = min(5, rescuedChunks.count)
                    let topRescued = Array(rescuedChunks.prefix(maxRescue))

                    // OPTIMIZED: Boost rescued chunks to topScore - 0.02 instead of + 0.05.
                    // Previous behavior made rescued chunks rank HIGHER than the best RRF result,
                    // which could pollute results if spec detection misfires.
                    // Now: rescued chunks rank just below the top result — included in context
                    // but won't displace genuinely high-relevance content.
                    let topScore = filteredChunks.first?.similarityScore ?? 0.8
                    let rescueScore = max(topScore - 0.02, 0.5)  // Floor at 0.5 to ensure inclusion
                    let boostedRescued = topRescued.map { chunk -> RetrievedChunk in
                        RetrievedChunk(
                            chunk: chunk.chunk,
                            similarityScore: rescueScore,
                            rank: 1,
                            sourceDocument: chunk.sourceDocument,
                            pageNumber: chunk.pageNumber
                        )
                    }

                    // Insert *after* the top result, never in front of it.
                    //
                    // This was `at: 0`, which contradicted the scoring three lines above and
                    // silently outranked the cross-encoder. `rescueScore` is deliberately
                    // `topScore - 0.02` so a rescued chunk sits just below the best result —
                    // but `applyMMR` selects its first chunk by POSITION, unconditionally
                    // (`if let first = remaining.first { selected.append(...) }`), and the
                    // MMR-skipped path takes `prefix(effectiveTopK)` which is also
                    // positional. Either way the score was decorative and position decided,
                    // so every rescue displaced the reranker's top-ranked chunk.
                    //
                    // Measured over 25 cases x 2 modes on 2026-08-21
                    // (`BenchmarkRuns/overnight-25case-nodeadlock`): standard `rerank` r@1
                    // 0.667 collapsing to `final` r@1 0.417 — a quarter of all cases losing
                    // the gold document from rank 1 *after* the cross-encoder had ranked it
                    // first. Largest single quality loss measured in the pipeline.
                    //
                    // Rescued chunks still enter the candidate set and still reach MMR;
                    // they simply no longer pre-empt the top result, which is what the
                    // rescue was always documented to do.
                    let rescueInsertionIndex = filteredChunks.isEmpty ? 0 : 1
                    filteredChunks.insert(contentsOf: boostedRescued, at: rescueInsertionIndex)

                    Log.info(
                        "   🔧 Spec preservation: rescued \(topRescued.count) spec chunks (score=\(String(format: "%.2f", rescueScore)))",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Spec preservation",
                        metadata: [
                            "rescued": "\(topRescued.count)",
                            "intent": answerIntent.rawValue,
                            "boostedScore": String(format: "%.2f", rescueScore),
                        ]
                    )
                }
            }
        }
    }

    /// Step 4.4: adds passages from other documents before diversification and records the retry candidates.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func ensureMultiDocumentCoverage(rerankedChunks: [RetrievedChunk], auditUniqueDocCount: inout Int, effectiveTopK: Int, filteredChunks: inout [RetrievedChunk], retryCandidates: inout [RetrievedChunk]) -> Int {
        // Step 4.4: Ensure multiple documents are represented before diversification
        let uniqueDocCount = Set(rerankedChunks.map { $0.chunk.documentId }).count
        auditUniqueDocCount = uniqueDocCount
        if uniqueDocCount > 1 {
            let desiredDocCoverage = min(
                uniqueDocCount,
                max(2, min(effectiveTopK, 3))
            )
            let maxCandidates = max(effectiveTopK * 2, filteredChunks.count)
            let (augmented, addedDocs) = ensureDocumentCoverage(
                candidates: filteredChunks,
                fallbackPool: rerankedChunks,
                desiredDocuments: desiredDocCoverage,
                maxCandidates: maxCandidates
            )
            if filteredChunks.count != augmented.count || addedDocs > 0 {
                if addedDocs > 0 {
                    Log.info(
                        "   🔁 Expanded context to cover \(addedDocs) additional document(s)",
                        category: .retrieval
                    )
                    TelemetryCenter.emit(
                        .retrieval,
                        title: "Document coverage boost",
                        metadata: [
                            "addedDocs": "\(addedDocs)",
                            "targetDocs": "\(desiredDocCoverage)",
                            "uniqueDocs": "\(uniqueDocCount)",
                        ]
                    )
                } else {
                    Log.info(
                        "   🔁 Normalized candidate pool to \(augmented.count) chunks",
                        category: .retrieval
                    )
                }
                filteredChunks = augmented
            }
        } else if filteredChunks.isEmpty {
            filteredChunks = Array(rerankedChunks.prefix(max(effectiveTopK, 3)))
        }
        retryCandidates = filteredChunks.sorted {
            $0.similarityScore > $1.similarityScore
        }
        return uniqueDocCount
    }

}
