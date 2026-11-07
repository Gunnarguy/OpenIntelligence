//
//  RAGService+QueryPreparation.swift
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
    /// Step P1b: unpacks the coordinator's QueryRuntimeContext into the pipeline's locals, records the query on self, logs the header and refreshes cloud consent.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func unpackRuntimeContext(runtimeContext: QueryRuntimeContext, question: String) async -> (useAgentic: Bool, qualityMode: RAGQualityMode, inferenceConfig: InferenceConfig, initialQueryProfile: QueryProfile, reliabilityModeEnabled: Bool, adaptiveConfig: AdaptivePipelineConfig, initialWantsCloudContext: Bool, initialQueryPlan: QueryExecutionPlan, networkAvailable: Bool) {
        // Unpack coordinator results into local variables for the pipeline
        // (preserves existing variable names used downstream)
        var inferenceConfig = runtimeContext.inferenceConfig
        let networkAvailable = runtimeContext.networkAvailable
        let reliabilityModeEnabled = runtimeContext.reliabilityModeEnabled
        if reliabilityModeEnabled {
            Log.info("[RAG] Reliability-first fallbacks enabled", category: .pipeline)
        }
        let initialWantsCloudContext = runtimeContext.initialWantsCloudContext
        let qualityMode = runtimeContext.qualityMode
        let initialQueryProfile = runtimeContext.queryProfile
        let initialQueryPlan = runtimeContext.queryPlan
        let useAgentic = runtimeContext.isAgentic
        let raptorSummariesEnabled = runtimeContext.raptorSummariesEnabled
        let raptorRoutingEnabled = runtimeContext.raptorRoutingEnabled
        let adaptiveConfig = runtimeContext.adaptiveConfig
        // Track query context for potential "Go Deeper" re-query
        await MainActor.run {
            self.lastQueryUsedAgentic = useAgentic
            self.lastQueryText = question
        }

        // Pipeline Trace: Emit header with mode and RAPTOR-lite status
        let modeDisplayName = runtimeContext.qualityModeDisplayName
        Log.pipelineHeader(
            mode: modeDisplayName,
            raptorSummaries: raptorSummariesEnabled,
            raptorRouting: raptorRoutingEnabled
        )

        emitThinkingEvent(
            .planning,
            title: "Execution plan: \(initialQueryPlan.executionMode.displayName)",
            detail: initialQueryPlan.reasoning
        )

        // The stored consent choices as they are now, for the plan and the gate (5.7).
        await MainActor.run { self.refreshCloudConsentFromDefaults() }
        return (useAgentic: useAgentic, qualityMode: qualityMode, inferenceConfig: inferenceConfig, initialQueryProfile: initialQueryProfile, reliabilityModeEnabled: reliabilityModeEnabled, adaptiveConfig: adaptiveConfig, initialWantsCloudContext: initialWantsCloudContext, initialQueryPlan: initialQueryPlan, networkAvailable: networkAvailable)
    }

    /// Step P4b: resolves the developer-tuning and relay flags, the selected container, its retrieval config and vector database, and records the query's container.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func resolveQueryContainer(reliabilityModeEnabled: Bool, selectedId: UUID) async -> (vdb: any VectorDatabase, retrievalConfig: RetrievalConfig, selectedContainer: KnowledgeContainer?, allowUngroundedFallback: Bool, asksForAnAction: Bool) {
        let developerTuningEnabled: Bool = await MainActor.run {
            settingsStore?.developerRAGTuningEnabled ?? false
        }

        let allowUngroundedFallback = reliabilityModeEnabled || developerTuningEnabled
        // A question an action asks (Siri, Shortcuts) of a library with no documents is answered with that, not by the
        // model alone (5.7); see the no-documents branch below.
        let asksForAnAction = await MainActor.run { asksThroughRelay }

        let selectedContainer = await MainActor.run {
            self.containerService.containers.first { $0.id == selectedId }
        }

        // OPTIMIZED: Use container's retrievalConfig if available, otherwise default.
        // Previous behavior hardcoded `.default` ignoring user-customized per-container weights.
        // Container settings UI lets users tune vector vs lexical weight — now those actually propagate.
        let retrievalConfig: RetrievalConfig = selectedContainer?.retrievalConfig ?? .default

        let vdb = await dbFor(selectedId)

        // Establish query-scoped container context for downstream tool calls and listings
        await MainActor.run {
            self.currentQueryContainerId = selectedId
            self.transientConsentGrants.removeAll()
        }
        // Optional DB warmup to ensure the vector store is loaded (prevents first-touch latency)
        let _ = try? await vdb.count()
        return (vdb: vdb, retrievalConfig: retrievalConfig, selectedContainer: selectedContainer, allowUngroundedFallback: allowUngroundedFallback, asksForAnAction: asksForAnAction)
    }

    /// Step P4c: sizes topK from the live passage count, the quality mode, the query profile and the adaptive candidate cap.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func sizeStandardTopK(vdb: any VectorDatabase, qualityModeInitialTopK: Int, topK: Int, initialQueryProfile: QueryProfile, initialWantsCloudContext: Bool, adaptiveConfig: AdaptivePipelineConfig) async -> (effectiveTopK: Int, queryWords: Int, totalStored: Int, isTrivial: Bool) {
        // Fetch current stored chunk count from vector database (fallback to cached total)
        let totalStored = (try? await vdb.count()) ?? totalChunksStored

        // CRITICAL: Dynamic topK scaling based on corpus size
        // For large documents (1000+ pages = 10,000+ chunks), fixed topK of 20 samples only 0.2%
        // This scaling ensures we sample a meaningful percentage regardless of corpus size
        //
        // Scaling strategy:
        // - Small corpus (<100 chunks): topK = 15-20 (15-20% sample)
        // - Medium corpus (100-1000): topK = 20-40 (4-20% sample)
        // - Large corpus (1000-5000): topK = 40-80 (1.5-8% sample)
        // - Huge corpus (5000-15000): topK = 80-150 (1-3% sample)
        // - Massive corpus (15000+): topK = 150-250 (1-2% sample, capped for memory)
        let corpusSizeAdjustedTopK: Int = {
            switch totalStored {
            case 0..<100:
                return max(15, min(totalStored, 20))  // Small: up to 20
            case 100..<500:
                return 25  // Medium-small
            case 500..<1000:
                return 35  // Medium
            case 1000..<2500:
                return 50  // Large
            case 2500..<5000:
                return 75  // Very large
            case 5000..<10000:
                return 100  // Huge (1000-page dense doc)
            case 10000..<20000:
                return 150  // Massive
            default:
                return 200  // Cap at 200 for memory safety
            }
        }()

        // Adjust topK based on adaptive mode parameters AND corpus size
        let requestedTopK = max(topK, qualityModeInitialTopK)
        let baseTopK = max(requestedTopK, corpusSizeAdjustedTopK)

        let queryWords = initialQueryProfile.wordCount
        let isTrivial = initialQueryProfile.isTrivial
        let applyTrivialTopKCap = isTrivial && !initialWantsCloudContext

        // Apply adaptive pipeline limit (thermal/battery/memory aware)
        // Caps retrieval when device is under pressure to prevent throttling
        let adaptiveMaxTopK = adaptiveConfig.maxRetrievalCandidates
        let uncappedEffectiveTopK =
            initialWantsCloudContext
            ? max(baseTopK, 50)  // PCC mode: even more context since we have headroom
            : max(1, applyTrivialTopKCap ? min(baseTopK, 15) : baseTopK)
        let effectiveTopK = min(uncappedEffectiveTopK, adaptiveMaxTopK)

        if corpusSizeAdjustedTopK > requestedTopK {
            Log.info(
                "[RAG] Corpus-size scaling: \(totalStored) chunks → topK boosted from \(requestedTopK) to \(corpusSizeAdjustedTopK)",
                category: .retrieval)
        }
        if effectiveTopK < uncappedEffectiveTopK {
            Log.info(
                "[Adaptive] TopK capped: \(uncappedEffectiveTopK) → \(effectiveTopK) (device pressure)",
                category: .pipeline)
        }
        if isTrivial {
            let detail =
                applyTrivialTopKCap
                ? "fast topK cap (\(effectiveTopK))"
                : "cloud context available - keeping full topK"
            Log.info("[RAG] Trivial query detected - \(detail)", category: .retrieval)
        }
        return (effectiveTopK: effectiveTopK, queryWords: queryWords, totalStored: totalStored, isTrivial: isTrivial)
    }

    /// Step SC: looks the question up in the persistent semantic query cache and takes an exact, still-current hit.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func lookUpSemanticQueryCache(question: String, embeddingProviderId: String, selectedDim: Int, selectedId: UUID) async -> (exactCacheHit: Bool, cachedQueryEmbedding: [Float]?, retrievedChunks: [RetrievedChunk], cacheKey: String, isDocumentScoped: Bool, normalizedQueryText: String) {
        // ── Semantic Query Cache ─────────────────────────────────────────────────────
        // Check the persistent SQLite semantic query cache before any LLM/embedding work.
        // Exact hit: bypass Steps 1, 1.5, 2, and 3 entirely.
        var cachedQueryEmbedding: [Float]? = nil
        var retrievedChunks: [RetrievedChunk] = []
        var exactCacheHit = false

        let normalizedQueryText = SQLiteFullTextService.normalizeQuery(question)
        // The cache's key is the question with every library's documents and the embedding
        // model (5.7), so a cached search is reused only while none of them changed. Through
        // 5.6 the key was the question alone and nothing ever cleared it: a question asked
        // again after an import or a deletion got the old passages back, none from the new
        // document and the deleted document's text with them.
        let cacheKey = await MainActor.run {
            Self.queryCacheKey(
                normalizedQueryText, documents: self.documents.map { (id: $0.id, passages: $0.totalChunks) },
                embeddingProviderId: embeddingProviderId, dimension: selectedDim)
        }
        // A question limited to named documents is searched inside them, so its result is
        // not the library's result for the same words: it skips the cache both ways.
        let isDocumentScoped = !(RAGQueryScope.documentIds ?? []).isEmpty
        if !isDocumentScoped, let cached = await SQLiteFullTextService.shared.getCachedQuery(
            normalizedQuery: cacheKey,
            containerId: selectedId
        ) {
            let knownDocuments = await MainActor.run { Set(self.documents.map(\.id)) }
            if Self.cachedResultsAreCurrent(cached.results, documentIds: knownDocuments) {
                cachedQueryEmbedding = cached.embedding
                retrievedChunks = cached.results
                exactCacheHit = true
                Log.info("[RAGService] ✅ Exact cache hit for query: '\(normalizedQueryText)'", category: .pipeline)
                emitThinkingEvent(
                    .retrieval, title: "Exact Cache Hit",
                    detail: "Bypassed rewriting, embedding, and database search")
            } else {
                Log.info(
                    "[RAGService] A cached search names a document no longer in the libraries; searching again",
                    category: .pipeline)
            }
        }
        // ────────────────────────────────────────────────────────────────────────────
        return (exactCacheHit: exactCacheHit, cachedQueryEmbedding: cachedQueryEmbedding, retrievedChunks: retrievedChunks, cacheKey: cacheKey, isDocumentScoped: isDocumentScoped, normalizedQueryText: normalizedQueryText)
    }

    /// Step 0: loads the cached or newly built corpus vocabulary and every readable passage, translates the query and decides whether to rewrite it.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func loadCorpusVocabulary(totalStored: Int, selectedName: String, selectedId: UUID, vdb: any VectorDatabase, question: String, initialQueryPlan: QueryExecutionPlan, selectedContainer: KnowledgeContainer?, qualityModeUsesQueryRewriting: Bool) async throws -> (finalCorpusVocabulary: CorpusVocabulary, rewriteEnabledBySettings: Bool, simpleGroundedLookup: Bool, translatedInitialQuery: (text: String, wasTranslated: Bool), useQueryRewriting: Bool, queryEnhancer: QueryEnhancementService, cachedAllChunks: [DocumentChunk]?, originalKeywordQuery: String?) {
        // Step 0: Build or retrieve cached Corpus Vocabulary (for context-aware understanding)
        Log.section("Step 0: Corpus Analysis", level: .info, category: .pipeline)
        HardwareTelemetryState.shared.reportRAGPipeline(stage: "Corpus Analysis")
        let corpusStartTime = Date()

        // Pipeline Trace: Step 0
        Log.pipelineStep(
            "0", title: "Corpus Analysis",
            details: [
                ("chunks", "\(totalStored)"),
                ("container", selectedName),
            ])

        // Use cached vocabulary if available to avoid expensive rebuilds
        let corpusVocabulary: CorpusVocabulary = await MainActor.run {
            if let cached = self.corpusVocabularyCache[selectedId] {
                Log.debug(
                    "[RAGService] Using cached corpus vocabulary for container \(selectedId)",
                    category: .pipeline)
                return cached
            }
            return CorpusVocabulary.empty
        }

        // Only build if not cached; also cache allChunks for lexical recall
        let finalCorpusVocabulary: CorpusVocabulary
        var cachedAllChunks: [DocumentChunk]?
        if corpusVocabulary.keywords.isEmpty {
            let allChunks = try await vdb.readableChunks()
            cachedAllChunks = await chunksOfListedDocuments(allChunks)  // Store for HybridSearchService lexical recall

            // Run viscosity scan when building vocabulary (first query)
            await runViscosityScan(allChunks, query: question)

            // Every passage of the library, whatever documents the question names. The
            // function holds the vocabulary for later questions when it is still the
            // library's.
            let built = await libraryVocabulary(for: selectedId, from: allChunks, isWholeLibrary: true)
            finalCorpusVocabulary = built
            let corpusTime = Date().timeIntervalSince(corpusStartTime)
            Log.debug(
                "Built corpus vocabulary in \(String(format: "%.0f", corpusTime * 1000))ms", category: .pipeline
            )
        } else {
            finalCorpusVocabulary = corpusVocabulary
            Log.debug("Using cached corpus vocabulary (0ms)", category: .pipeline)

            // Always load allChunks — needed for parent doc expansion, lexical recall,
            // document summary, and multi-hop even when vocabulary is cached.
            // Previously only loaded when pipelineTraceEnabled, which silently broke
            // parent doc expansion on repeat queries to the same container.
            let allChunks = try await vdb.readableChunks()
            cachedAllChunks = await chunksOfListedDocuments(allChunks)
            if Log.pipelineTraceEnabled {
                await runViscosityScan(allChunks, query: question)
            }
        }

        let queryEnhancer = QueryEnhancementService(corpusVocabulary: finalCorpusVocabulary)
        let simpleGroundedLookup = initialQueryPlan.preferLiteralQuery
        let translatedInitialQuery = await translatedQueryForEmbedding(question, container: selectedContainer)
        let originalKeywordQuery = translatedInitialQuery.wasTranslated ? question : nil

        // Check advanced RAG settings
        let rewriteEnabledBySettings = settingsStore?.enableQueryRewriting ?? qualityModeUsesQueryRewriting
        let useQueryRewriting = rewriteEnabledBySettings && !simpleGroundedLookup
        // Note: Iterative retrieval is auto-enabled for multi-hop intents (investigate/compare/findings)
        // and can be force-enabled via settings toggle. See Step 3 below.
        return (finalCorpusVocabulary: finalCorpusVocabulary, rewriteEnabledBySettings: rewriteEnabledBySettings, simpleGroundedLookup: simpleGroundedLookup, translatedInitialQuery: translatedInitialQuery, useQueryRewriting: useQueryRewriting, queryEnhancer: queryEnhancer, cachedAllChunks: cachedAllChunks, originalKeywordQuery: originalKeywordQuery)
    }

    /// Step 1: rewrites the query with the model and conversation context when enabled and not an exact cache hit.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func rewriteQueryWithModel(translatedInitialQuery: (text: String, wasTranslated: Bool), exactCacheHit: Bool, useQueryRewriting: Bool, finalCorpusVocabulary: CorpusVocabulary, qualityModeUsesConversationMemory: Bool, selectedId: UUID, qualityModeMaxConversationTurns: Int, auditQueryWasRewritten: inout Bool, question: String, rewriteEnabledBySettings: Bool, simpleGroundedLookup: Bool) async -> String {
        // Step 1: LLM-Powered Query Understanding (if enabled)
        // CACHE: Skip if exact cache hit
        var effectiveQuery = translatedInitialQuery.text
        var queryWasRewritten = false
        var rewriteTime: TimeInterval = 0

        if !exactCacheHit && useQueryRewriting {
            Log.section("Step 1: Query Understanding", level: .info, category: .pipeline)
            HardwareTelemetryState.shared.reportRAGPipeline(stage: "Query Understanding")
            let rewriteStartTime = Date()

            // Pipeline Trace: Step 1
            Log.pipelineStep(
                "1", title: "Query Understanding",
                details: [
                    ("rewriting", "enabled")
                ])
            let documentNames = await snapshotDocuments().map { $0.filename }
            let queryRewriter = QueryRewriterService(
                corpusVocabulary: finalCorpusVocabulary,
                documentSummaries: nil
            )

            // Build conversation context for pronoun resolution
            // Use ConversationMemoryService for enhanced entity-aware context if available
            // Respect both quality mode toggle and user settings
            let conversationMemoryEnabled =
                qualityModeUsesConversationMemory && (settingsStore?.enableConversationMemory ?? true)
            var recentTurns: [ConversationTurn] = []

            if #available(iOS 26.0, *), conversationMemoryEnabled {
                // Get memory-enhanced context with tracked entities
                // ONLY use actual conversation turns - NOT synthetic context from memory entities
                // Synthetic context causes false-positive rewrites (e.g., "this button" → "the button you mentioned")
                let memory = ConversationMemoryService.shared.memory(for: selectedId)
                let maxTurns = min(qualityModeMaxConversationTurns, 3)  // Use quality mode limit for rewriting
                recentTurns = memory.recentTurns.suffix(maxTurns).map { turn in
                    ConversationTurn(
                        role: "user",
                        content: turn.userQuery,
                        entities: turn.extractedFacts.prefix(3).map { String($0.prefix(50)) }
                    )
                }
                // Note: Intentionally NOT creating synthetic turns from memory.entities
                // Memory entities persist across sessions and don't provide reliable pronoun referents
                Log.debug(
                    "[ConversationMemory] Using memory for query rewriting (\(recentTurns.count) turns, \(memory.entities.count) entities)",
                    category: .retrieval)
            }

            // Fallback to raw chat history if memory didn't provide context
            if recentTurns.isEmpty {
                let conversationHistory = chatHistory(for: selectedId)
                recentTurns =
                    conversationHistory
                    .filter { $0.role != .system }
                    .suffix(4)  // Last 4 messages
                    .map { msg in
                        ConversationTurn(
                            role: msg.role == .user ? "user" : "assistant",
                            content: String(msg.content.prefix(300)),
                            entities: []  // Will be extracted by the service
                        )
                    }
            }

            do {
                let rewriteResult = try await queryRewriter.rewrite(
                    query: effectiveQuery,
                    documentNames: documentNames,
                    conversationContext: recentTurns
                )
                effectiveQuery = rewriteResult.rewritten
                queryWasRewritten = rewriteResult.wasRewritten
                auditQueryWasRewritten = rewriteResult.wasRewritten

                if rewriteResult.wasRewritten {
                    var detail = "Intent: \(rewriteResult.intent.rawValue)"
                    if !rewriteResult.resolvedEntities.isEmpty {
                        detail +=
                            " • Resolved: \(rewriteResult.resolvedEntities.prefix(2).joined(separator: ", "))"
                    } else {
                        detail += " • \(rewriteResult.entities.prefix(3).joined(separator: ", "))"
                    }
                    Log.info(
                        "✓ Query rewritten: \"\(question.prefix(40))...\" → \"\(rewriteResult.rewritten.prefix(60))...\"",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .planning,
                        title: "Query understood",
                        detail: detail
                    )
                }
            } catch {
                Log.warning(
                    "[RAGService] Query rewriting failed, using original: \(error)", category: .retrieval)
            }

            rewriteTime = Date().timeIntervalSince(rewriteStartTime)
            TelemetryCenter.emit(
                .retrieval,
                title: "Query understanding",
                metadata: [
                    "rewritten": queryWasRewritten ? "true" : "false",
                    "originalLength": "\(question.count)",
                    "rewrittenLength": "\(effectiveQuery.count)",
                ],
                duration: rewriteTime
            )
        } else {
            if rewriteEnabledBySettings && simpleGroundedLookup {
                Log.info(
                    "[RAGService] Query rewriting bypassed for simple grounded lookup", category: .retrieval)
                emitThinkingEvent(
                    .planning,
                    title: "Keeping query literal",
                    detail: "Simple grounded lookup — skipping rewrite"
                )
            } else {
                Log.debug("[RAGService] Query rewriting disabled, using original query", category: .pipeline)
            }
        }
        return effectiveQuery
    }

    /// Step 1.5: expands the query from the planner, heuristics, container vocabulary and gazetteer.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func expandQueryForRetrieval(exactCacheHit: Bool, qualityModeUsesQueryExpansion: Bool, effectiveQuery: String, queryEnhancer: QueryEnhancementService, qualityMode: RAGQualityMode, qualityModeMaxQueryExpansions: Int, qualityModeDisplayName: String, qualityModeUsesContainerVocabulary: Bool, selectedId: UUID, auditQueryExpansionCount: inout Int) async -> (expandedQueries: [String], expansionTime: TimeInterval) {
        // Step 1.5: Corpus-Aware Query Expansion
        // QUALITY MODE: Check if query expansion is enabled
        var expandedQueries: [String] = []
        var expansionTime: TimeInterval = 0

        if !exactCacheHit && qualityModeUsesQueryExpansion {
            Log.section("Step 1.5: Query Expansion", level: .info, category: .pipeline)
            let expansionStartTime = Date()

            let effectivePlanningProfile = await QueryProfileService.shared.buildProfile(
                for: effectiveQuery,
                queryEnhancer: queryEnhancer,
                routingEnabled: false
            )
            let effectiveQueryPlan = await QueryExecutionPlannerService.shared.buildPlan(
                for: effectiveQuery,
                profile: effectivePlanningProfile,
                requestedQualityMode: qualityMode,
                allowToolCalling: false
            )

            expandedQueries = effectiveQueryPlan.searchQueries.filter {
                $0.caseInsensitiveCompare(effectiveQuery) != .orderedSame
            }

            let heuristicExpansions = queryEnhancer.expandQuery(effectiveQuery)
            for candidate in heuristicExpansions {
                guard expandedQueries.count < qualityModeMaxQueryExpansions else { break }
                guard !expandedQueries.contains(where: { $0.caseInsensitiveCompare(candidate) == .orderedSame })
                else { continue }
                expandedQueries.append(candidate)
            }

            // Limit to quality mode maximum
            if expandedQueries.count > qualityModeMaxQueryExpansions {
                expandedQueries = Array(expandedQueries.prefix(qualityModeMaxQueryExpansions))
                Log.debug(
                    "[RAGService] Capped query expansions to \(qualityModeMaxQueryExpansions) (quality mode: \(qualityModeDisplayName))",
                    category: .retrieval)
            }

            // Step 1.5b: Per-Container Vocabulary Expansion (if enabled)
            if qualityModeUsesContainerVocabulary {
                let vocabExpansions = await ContainerVocabularyService.shared.expandQuery(
                    effectiveQuery,
                    containerId: selectedId
                )
                if !vocabExpansions.isEmpty {
                    let uniqueVocabTerms = vocabExpansions.filter { !expandedQueries.contains($0) }
                    // Respect max expansions limit
                    let spaceRemaining = qualityModeMaxQueryExpansions - expandedQueries.count
                    let termsToAdd = Array(uniqueVocabTerms.prefix(max(0, spaceRemaining)))
                    expandedQueries.append(contentsOf: termsToAdd)
                    Log.debug(
                        "[RAGService] Container vocabulary added \(termsToAdd.count) terms",
                        category: .retrieval
                    )
                }
            } else {
                Log.debug(
                    "[RAGService] Container vocabulary expansion skipped (quality mode: \(qualityModeDisplayName))",
                    category: .pipeline)
            }

            // Step 1.5c: Gazetteer Domain Vocabulary Enrichment
            // Adds domain-specific terms learned during ingestion (NLGazetteer)
            let gazetteerMatches = await GazetteerService.shared.matchingTerms(for: effectiveQuery)
            if !gazetteerMatches.isEmpty {
                let gazetteerTerms = gazetteerMatches.map { $0.term }
                let uniqueGazetteerTerms = gazetteerTerms.filter { term in
                    !expandedQueries.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
                }
                let gazetteerSpace = qualityModeMaxQueryExpansions - expandedQueries.count
                let gazetteerToAdd = Array(uniqueGazetteerTerms.prefix(max(0, gazetteerSpace)))
                expandedQueries.append(contentsOf: gazetteerToAdd)
                if !gazetteerToAdd.isEmpty {
                    Log.debug(
                        "[RAGService] Gazetteer added \(gazetteerToAdd.count) domain terms",
                        category: .retrieval)
                }
            }

            expansionTime = Date().timeIntervalSince(expansionStartTime)
            Log.info(
                "✓ Expanded to \(expandedQueries.count) query variations in \(String(format: "%.0f", expansionTime * 1000))ms",
                category: .pipeline
            )
            TelemetryCenter.emit(
                .retrieval,
                title: "Query expanded",
                metadata: [
                    "variants": "\(expandedQueries.count)",
                    "maxAllowed": "\(qualityModeMaxQueryExpansions)",
                ],
                duration: expansionTime
            )

            if !expandedQueries.isEmpty {
                auditQueryExpansionCount = expandedQueries.count
                emitThinkingEvent(
                    .queryRewrite,
                    title: "Query expansion",
                    detail: "\(expandedQueries.count) variants generated"
                )
            }
        } else {
            Log.info(
                "[RAG] Query expansion skipped (quality mode: \(qualityModeDisplayName))", category: .pipeline)
            emitThinkingEvent(
                .queryRewrite,
                title: "Query expansion skipped",
                detail: "Quality mode: \(qualityModeDisplayName)"
            )
        }
        return (expandedQueries: expandedQueries, expansionTime: expansionTime)
    }

    /// Step 1.6: builds the effective query profile and derives the answer intent and its flags.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func resolveStandardAnswerIntent(effectiveQuery: String, queryEnhancer: QueryEnhancementService, cachedAllChunks: [DocumentChunk]?, qualityMode: RAGQualityMode, auditAnswerIntent: inout String) async -> (answerIntent: AnswerIntent, answerIntentIsExtractive: Bool, contextualDefinitionLookup: Bool, effectiveQueryProfile: QueryProfile, hasSummaryChunks: Bool, queryRoutingEnabled: Bool, isProceduralQuery: Bool, answerNeedsDocumentSummary: Bool) {
        let queryRoutingEnabled = settingsStore?.enableQueryRouting ?? true
        let effectiveQueryProfile = await QueryProfileService.shared.buildProfile(
            for: effectiveQuery,
            queryEnhancer: queryEnhancer,
            queryRouter: queryRouter,
            routingEnabled: queryRoutingEnabled
        )

        // Step 1.6: Answer Intent Classification (AppleRAG §6)
        // Classify query intent to optimize retrieval and answering strategy
        let answerIntent = effectiveQueryProfile.answerIntent
        let isProceduralQuery = answerIntent == .procedure
        let hasSummaryChunks =
            cachedAllChunks?.contains { $0.metadata.abstractionLevel == .documentSummary } ?? false
        let contextualDefinitionLookup = shouldUseContextualDefinitionLookupMode(
            query: effectiveQuery,
            answerIntent: answerIntent,
            qualityMode: qualityMode,
            hasSummaryChunks: hasSummaryChunks
        )
        let answerIntentIsExtractive = answerIntent.isExtractiveFirst && !contextualDefinitionLookup
        let answerNeedsDocumentSummary = answerIntent.requiresDocumentSummary || contextualDefinitionLookup
        auditAnswerIntent = answerIntent.rawValue
        Log.info(
            "✓ Answer intent: \(answerIntent.rawValue) (extractive-first: \(answerIntentIsExtractive), multi-hop: \(answerIntent.benefitsFromMultiHop)\(contextualDefinitionLookup ? ", contextual-definition: true" : ""))",
            category: .pipeline
        )
        emitThinkingEvent(
            .intentRoute,
            title: "Intent: \(answerIntent.rawValue)",
            detail: contextualDefinitionLookup
                ? "Contextual definition lookup"
                : (answerIntentIsExtractive
                    ? "Extractive-first"
                    : (answerIntent.benefitsFromMultiHop ? "Multi-hop enabled" : "Standard"))
        )
        if contextualDefinitionLookup {
            Log.info(
                "[RAG] Standard contextual lookup: definition-style query will use summary + detail evidence",
                category: .pipeline
            )
            emitThinkingEvent(
                .planning,
                title: "Contextual lookup",
                detail: "Definition-style query → summary + detail grounding"
            )
        }
        return (answerIntent: answerIntent, answerIntentIsExtractive: answerIntentIsExtractive, contextualDefinitionLookup: contextualDefinitionLookup, effectiveQueryProfile: effectiveQueryProfile, hasSummaryChunks: hasSummaryChunks, queryRoutingEnabled: queryRoutingEnabled, isProceduralQuery: isProceduralQuery, answerNeedsDocumentSummary: answerNeedsDocumentSummary)
    }

    /// Step 2 (HyDE): starts the embedding clock, logs the HyDE gates and generates a hypothetical document when HyDE applies.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func gateAndGenerateHyDE(qualityModeUsesHyDE: Bool, answerIntentIsExtractive: Bool, answerIntent: AnswerIntent, embeddingProviderId: String, selectedDim: Int, effectiveQuery: String, selectedId: UUID, auditUsedHyDE: inout Bool) async -> (embeddingStartTime: Date, hydeEmbeddingText: String?, hydeText: String?) {
        // Step 2: Embed the user's query
        Log.section("Step 2: Query Embedding", level: .info, category: .pipeline)
        let embeddingStartTime = Date()

        // HyDE: Combine quality mode toggle with user settings and service availability
        let hydeEnabledBySettings = settingsStore?.enableHyDE ?? true
        let hydeIsAvailable = HyDEService.isAvailable
        let hydeEnabledForMode = qualityModeUsesHyDE && hydeEnabledBySettings && hydeIsAvailable
        // ALWAYS log HyDE gate status so we can diagnose silent failures
        Log.info(
            "[HyDE] Gates: qualityMode=\(qualityModeUsesHyDE), settings=\(hydeEnabledBySettings), available=\(hydeIsAvailable) → enabled=\(hydeEnabledForMode)",
            category: .retrieval)

        // CRITICAL: Disable HyDE for extractive/lookup queries to avoid hallucinated specifics biasing retrieval
        // HyDE can guess wrong values (e.g., "5W-40" when answer is "0W-20") and pull wrong chunks
        // Extractive-first intents (lookup, tableLookup) work better with keyword matching
        // Procedure intents need HyDE for semantic behavioral matching ("what does the button do?")
        let hydeDisabledForIntent = answerIntentIsExtractive
        if hydeDisabledForIntent && hydeEnabledForMode {
            Log.debug(
                "[HyDE] Disabled for extractive intent '\(answerIntent.rawValue)' - keyword matching preferred",
                category: .retrieval)
        }

        // Pipeline Trace: Step 2
        Log.pipelineStep(
            "2", title: "Query Embedding",
            details: [
                ("provider", embeddingProviderId),
                ("dim", "\(selectedDim)"),
                ("HyDE", (hydeEnabledForMode && !hydeDisabledForIntent) ? "enabled" : "off"),
            ])

        // HyDE (Hypothetical Document Embeddings) - Gao et al. 2022
        // Generates a hypothetical answer for better retrieval when question vocab differs from answer vocab
        // Only used for factual queries where this vocabulary gap is significant
        // DISABLED for extractive/lookup intents where specific values matter
        let useHyDE =
            hydeEnabledForMode && !hydeDisabledForIntent && HyDEService.shouldUseHyDE(for: effectiveQuery)
        var hydeText: String?
        var hydeEmbeddingText: String?

        if hydeDisabledForIntent && hydeEnabledForMode {
            // HyDE was enabled but skipped due to extractive intent
            emitThinkingEvent(
                .hyde,
                title: "HyDE skipped",
                detail: "Extractive intent '\(answerIntent.rawValue)' - using direct keyword matching"
            )
        }

        if useHyDE {
            let hydeService = HyDEService()
            do {
                let hydeResult = try await hydeService.generateHyDEQuery(
                    for: effectiveQuery,
                    containerId: selectedId
                )
                hydeText = hydeResult.hypotheticalDocument
                hydeEmbeddingText = hydeResult.combinedForEmbedding
                auditUsedHyDE = true
                Log.info(
                    "[HyDE] Generated hypothetical doc: \"\(hydeText?.prefix(80) ?? "")...\"",
                    category: .retrieval)
                emitThinkingEvent(
                    .hyde,
                    title: "HyDE generation",
                    detail: "Hypothetical doc for vocabulary bridging"
                )
            } catch {
                Log.warning(
                    "[HyDE] Failed to generate hypothetical doc: \(error.localizedDescription)",
                    category: .retrieval)
                // Fall back to regular query embedding
            }
        }
        return (embeddingStartTime: embeddingStartTime, hydeEmbeddingText: hydeEmbeddingText, hydeText: hydeText)
    }

    /// Step 2 (embedding): embeds the query, or reuses the cached vector on an exact cache hit, and checks its dimension.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func embedQuery(effectiveQuery: String, hydeEmbeddingText: String?, cachedQueryEmbedding: [Float]?, exactCacheHit: Bool, queryEmbeddingService: EmbeddingService, embeddingStartTime: Date, hydeText: String?, embeddingProviderId: String, selectedDim: Int, selectedName: String, selectedId: UUID) async throws -> (queryEmbedding: [Float], textToEmbed: String, embeddingTime: TimeInterval) {
        // Use HyDE text if available, otherwise use the rewritten query
        let textToEmbed = hydeEmbeddingText ?? effectiveQuery

        // Step 2 (embedding) is skipped on exact cache hit; we reuse the cached vector.
        let queryEmbedding: [Float]
        var embeddingTime: TimeInterval = 0
        if exactCacheHit, let cachedEmb = cachedQueryEmbedding {
            queryEmbedding = cachedEmb
            Log.info(
                "[RAGService] ✅ Reusing cached \(queryEmbedding.count)-dim embedding (exact cache hit)",
                category: .embedding)
        } else {
            // ─ Fresh embedding generation ─────────────────────────────────────────
            queryEmbedding = try await queryEmbeddingService.generateEmbedding(for: textToEmbed)
            embeddingTime = Date().timeIntervalSince(embeddingStartTime)

            let embeddingMagnitude = sqrt(queryEmbedding.map { $0 * $0 }.reduce(0, +))
            let hydeStatus = hydeText != nil ? " [HyDE]" : ""
            Log.info(
                "✓ Generated \(queryEmbedding.count)-dimensional embedding\(hydeStatus)",
                category: .embedding
            )
            Log.debug(
                "  Vector magnitude: \(String(format: "%.4f", embeddingMagnitude))",
                category: .embedding
            )
            Log.debug(
                "  Time: \(String(format: "%.0f", embeddingTime * 1000))ms",
                category: .performance
            )
            TelemetryCenter.emit(
                .embedding,
                title: "Query embedding",
                metadata: [
                    "dimensions": "\(queryEmbedding.count)",
                    "provider": embeddingProviderId,
                ],
                duration: embeddingTime
            )

            // Show provider in thinking timeline (contextual = high accuracy badge)
            let providerLabel =
                embeddingProviderId == "nl_contextual_embedding" ? "⚡ Contextual" : embeddingProviderId
            emitThinkingEvent(
                .embedding,
                title: "Embedding ready",
                detail:
                    "\(providerLabel) • \(queryEmbedding.count)D in \(String(format: "%.0f", embeddingTime * 1000)) ms"
            )

            // Warn if embedding dimension doesn't match the selected library's index dimension
            if queryEmbedding.count != selectedDim {
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Embedding dimension mismatch",
                    metadata: [
                        "expected": "\(selectedDim)",
                        "got": "\(queryEmbedding.count)",
                        "container": selectedName,
                        "containerId": selectedId.uuidString,
                    ]
                )
            }

            // No lookup by similarity (5.7). Through 5.6 a question whose embedding was within
            // 0.95 cosine of any cached one got that question's passages, from whatever the
            // library held when it was asked, and finding one decoded every cached question's
            // embedding for the library, on every question. Those rows carry no library state
            // this code can check (`SQLiteFullTextService.getCachedQueryBySimilarity`).
        }  // end of fresh-embedding else branch
        return (queryEmbedding: queryEmbedding, textToEmbed: textToEmbed, embeddingTime: embeddingTime)
    }

    /// Step P3: applies the opt-in adaptive generation profile (UserDefaults `adaptiveInferenceProfiles`) to the inference config.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func applyAdaptiveGenerationProfile(initialQueryProfile: QueryProfile, inferenceConfig: inout InferenceConfig) {
        // Adaptive generation profile, chosen from what the question is asking for rather than
        // from the quality mode alone. `RAGQualityMode` carries one temperature for every
        // question asked in that mode, so Standard answers a serial-number lookup and an
        // open-ended comparison identically; the answer intent is a better signal and is already
        // resolved by this point.
        //
        // **Off unless the owner turns it on.** `UserDefaults.bool(forKey:)` returns false for an
        // absent key, so an install that has never seen this setting behaves exactly as it did
        // before. It is opt-in because its effect on answer quality is unmeasured, and currently
        // unmeasurable in this repository: retrieval is nondeterministic, two runs of one build
        // return different evidence and different answers, and no A/B here is trustworthy yet.
        // Shipping it on by default would be changing everyone's answers on a hypothesis.
        //
        // **This sits BELOW the agentic return on purpose, and that is a limit, not a detail.**
        // Deep Think and Maximum return above via `executeAgenticQuery`, which never reads this
        // `inferenceConfig` or the `config` parameter for generation: it builds `optimizedConfig`
        // from `qualityMode.agenticConfig` and hands that to `AgenticOrchestrator`. Applying the
        // profile above the branch, which is where it was first written, mutated a local that the
        // agentic path never reads while logging `temperature 0.4 -> 0.35` as though it had taken
        // effect. A log line asserting a change that did not happen is worse than no feature, and
        // it is the exact failure this repository keeps hitting: a stage reports healthy while the
        // value it claims to have set goes nowhere. Reaching the agentic path means changing where
        // `AgenticOrchestrator` gets its generation parameters, which is tracked separately.
        #if canImport(FoundationModels)
            if UserDefaults.standard.bool(forKey: "adaptiveInferenceProfiles") {
                let intent = initialQueryProfile.answerIntent
                let previousTemperature = inferenceConfig.temperature
                let previousMaxTokens = inferenceConfig.maxTokens
                inferenceConfig = inferenceConfig.applyingAdaptiveProfile(for: intent)
                let rationale = FoundationModelDynamicProfileRegistry.profile(for: intent).generation.rationale
                Log.info(
                    "[AdaptiveProfile] intent=\(intent.rawValue) "
                        + "temperature \(previousTemperature) -> \(inferenceConfig.temperature), "
                        + "maxTokens \(previousMaxTokens) -> \(inferenceConfig.maxTokens) [\(rationale)]",
                    category: .llm
                )
            }
        #endif
    }

    /// Step P4e: logs the pipeline box and feature summary and emits the planning events and the 'Query received' telemetry.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func logStandardPipelinePlan(question: String, effectiveTopK: Int, totalStored: Int, embeddingProviderId: String, selectedDim: Int, qualityModeDisplayName: String, qualityModeUsesHyDE: Bool, qualityModeUsesReRanking: Bool, qualityModeUsesMMR: Bool, qualityModeUsesVerificationGates: Bool, qualityModeUsesQueryExpansion: Bool, qualityModeUsesContainerVocabulary: Bool, qualityModeUsesParentDocRetrieval: Bool, qualityModeUsesContextualCompression: Bool, selectedName: String, selectedId: UUID, queryWords: Int, retrievalConfig: RetrievalConfig) {
        Log.box(
            "ENHANCED RAG QUERY PIPELINE",
            level: .info,
            category: .pipeline,
            content: [
                "📝 Query: \(question)",
                "🎯 Retrieving top \(effectiveTopK) chunks from \(totalStored) total",
                "🧬 Embeddings: \(embeddingProviderId) • \(selectedDim)D",
                "⚙️ Quality Mode: \(qualityModeDisplayName)",
            ]
        )

        // Build quality mode feature summary for thinking stream
        var enabledFeatures: [String] = []
        if qualityModeUsesHyDE { enabledFeatures.append("HyDE") }
        if qualityModeUsesReRanking { enabledFeatures.append("ReRank") }
        if qualityModeUsesMMR { enabledFeatures.append("MMR") }
        if qualityModeUsesVerificationGates { enabledFeatures.append("Verify") }
        if qualityModeUsesQueryExpansion { enabledFeatures.append("Expand") }
        if qualityModeUsesContainerVocabulary { enabledFeatures.append("Vocab") }
        if qualityModeUsesParentDocRetrieval { enabledFeatures.append("Parent") }
        if qualityModeUsesContextualCompression { enabledFeatures.append("Compress") }
        let featureSummary = enabledFeatures.joined(separator: " • ")

        emitThinkingEvent(
            .planning,
            title: "\(qualityModeDisplayName) mode",
            detail: featureSummary.isEmpty ? "Minimal features" : featureSummary
        )

        emitThinkingEvent(
            .planning,
            title: "Scoping query",
            detail: "Top \(effectiveTopK) • \(selectedName)"
        )

        TelemetryCenter.emit(
            .system,
            title: "Query received",
            metadata: [
                "question": String(question.prefix(80)),
                "container": selectedName,
                "containerId": selectedId.uuidString,
                "qualityMode": qualityModeDisplayName,
                "words": "\(queryWords)",
                "characters": "\(question.count)",
                "topK": "\(effectiveTopK)",
                "minSimilarity": String(format: "%.2f", retrievalConfig.minSimilarity),
                "embeddingProvider": embeddingProviderId,
                "embeddingDim": "\(selectedDim)",
            ]
        )
    }

    /// Step 2.5: starts the retrieval clock and sets the hybrid weights, RAPTOR-lite search levels and filtered passage pool.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func planSearchRouting(effectiveQueryProfile: QueryProfile, retrievalConfig: RetrievalConfig, auditUsedQueryRouting: inout Bool, queryRoutingEnabled: Bool, contextualDefinitionLookup: Bool, cachedAllChunks: [DocumentChunk]?, hasSummaryChunks: Bool, auditUsedSummaryRouting: inout Bool) -> (adjustedVectorWeight: Float, adjustedKeywordWeight: Float, filteredCachedChunks: [DocumentChunk]?, iterativeMetadata: (iterations: Int, confidence: Float, queries: Int)?, queryIntent: QueryIntent, retrievalStartTime: Date) {
        // Step 3: Hybrid Search (vector + BM25 keyword search with RRF fusion)
        // CACHE: Entire Step 3 is bypassed on exact or similarity cache hit.
        // With optional iterative retrieval for multi-pass refinement
        let retrievalStartTime = Date()
        var iterativeMetadata: (iterations: Int, confidence: Float, queries: Int)?

        // Shared retrieval configuration is reused by both live search and recovery paths.
        let queryIntent = effectiveQueryProfile.searchIntent
        let adjustedWeights = effectiveQueryProfile.adjustedHybridWeights(from: retrievalConfig)
        let adjustedVectorWeight = adjustedWeights.vectorWeight
        let adjustedKeywordWeight = adjustedWeights.keywordWeight

        // Step 2.5: Query Classification for RAPTOR-lite (summary-first retrieval)
        // Determines whether to search document summaries (L1) or detail chunks (L0)
        // Controlled by settings.enableQueryRouting
        auditUsedQueryRouting = queryRoutingEnabled
        let queryClassification = effectiveQueryProfile.routingClassification

        // Pipeline Trace: Step 2.5 (RAPTOR-lite)
        if queryRoutingEnabled {
            Log.pipelineStep(
                "2.5", title: "RAPTOR-lite Query Routing",
                details: [
                    ("type", queryClassification.queryType.rawValue),
                    ("confidence", String(format: "%.0f%%", queryClassification.confidence * 100)),
                ])
        }
        var searchLevels = effectiveQueryProfile.abstractionLevelsToSearch
        if contextualDefinitionLookup && !searchLevels.contains(.documentSummary) {
            searchLevels.insert(.documentSummary, at: 0)
        }

        if queryRoutingEnabled {
            Log.info(
                "[RAPTOR-lite] Query type: \(queryClassification.queryType.rawValue) "
                    + "(confidence: \(String(format: "%.0f", queryClassification.confidence * 100))%) "
                    + "→ search \(searchLevels.map { $0.description }.joined(separator: ", "))",
                category: .retrieval
            )
        }

        // Filter cached chunks by abstraction level if we have summaries AND routing is enabled.
        var filteredCachedChunks: [DocumentChunk]? = cachedAllChunks
        if queryRoutingEnabled, let allChunks = cachedAllChunks {
            if hasSummaryChunks
                && (contextualDefinitionLookup
                    || (queryClassification.queryType == .overview && queryClassification.confidence >= 0.5))
            {
                filteredCachedChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                if contextualDefinitionLookup {
                    Log.info(
                        "[RAPTOR-lite] Filtered to \(filteredCachedChunks?.count ?? 0) chunks (from \(allChunks.count)) for contextual definition lookup",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .planning,
                        title: "Using summaries + details",
                        detail: "Definition query → blend document summaries with detail chunks"
                    )
                } else {
                    auditUsedSummaryRouting = true
                    Log.info(
                        "[RAPTOR-lite] Filtered to \(filteredCachedChunks?.count ?? 0) chunks (from \(allChunks.count)) for overview query",
                        category: .retrieval
                    )
                    emitThinkingEvent(
                        .planning,
                        title: "Using document summaries",
                        detail: "Overview query → searching L1 summaries first"
                    )
                }
            }
        }
        return (adjustedVectorWeight: adjustedVectorWeight, adjustedKeywordWeight: adjustedKeywordWeight, filteredCachedChunks: filteredCachedChunks, iterativeMetadata: iterativeMetadata, queryIntent: queryIntent, retrievalStartTime: retrievalStartTime)
    }

    /// Step 3 (gate): decides whether iterative retrieval runs for this intent and logs when the intent overrides the setting.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    func decideIterativeRetrieval(answerIntentIsExtractive: Bool, answerIntent: AnswerIntent, qualityModeUsesIterativeRetrieval: Bool) -> (useIterative: Bool, iterativeConfig: IterativeRetrievalConfig) {
        HardwareTelemetryState.shared.reportRAGPipeline(stage: "Hybrid Search")
        // UPGRADED: Auto-enable iterative retrieval for multi-hop intents
        // (compare, investigate, findings) even if user hasn't toggled the setting.
        // The infrastructure is fully built — this just activates it where it matters.
        let userEnabledIterative = settingsStore?.enableIterativeRetrieval ?? false
        let iterativeAllowedForIntent = !answerIntentIsExtractive
        let useIterative =
            iterativeAllowedForIntent
            && (userEnabledIterative
                || (answerIntent.benefitsFromMultiHop && qualityModeUsesIterativeRetrieval))
        let iterativeConfig = IterativeRetrievalConfig.default

        if !iterativeAllowedForIntent && userEnabledIterative {
            Log.info(
                "[RAGService] Iterative retrieval bypassed for extractive intent '\(answerIntent.rawValue)'",
                category: .retrieval)
            emitThinkingEvent(
                .iterative,
                title: "Iterative retrieval skipped",
                detail: "Extractive intent — prefer direct grounded lookup"
            )
        }
        return (useIterative: useIterative, iterativeConfig: iterativeConfig)
    }

}
