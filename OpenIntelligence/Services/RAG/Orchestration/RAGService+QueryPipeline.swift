//
//  RAGService+QueryPipeline.swift
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
    // MARK: - RAG Query Pipeline

    /// Re-query the last question using forced agentic (deep reasoning) mode.
    /// Called by UI when user taps "Go Deeper" after a single-pass response.
    /// - Parameter streamHandler: Optional stream handler for live token updates
    /// - Returns: The RAG response with deeper analysis, or nil if no previous query exists
    func reQueryWithAgenticMode(streamHandler: LLMStreamHandler? = nil) async throws -> RAGResponse? {
        guard let query = await MainActor.run(body: { self.lastQueryText }) else {
            Log.warning("[RAG] No previous query to re-run with agentic mode", category: .pipeline)
            return nil
        }

        // Set the force flag before querying
        await MainActor.run { self.forceAgenticOnNextQuery = true }

        Log.info("[RAG] Re-querying with forced agentic mode: \(query.prefix(50))...", category: .pipeline)
        return try await self.query(query, streamHandler: streamHandler)
    }

    /// Execute a RAG query: expand query → embed → hybrid search → re-rank → generate response
    func query(
        _ question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        qualityModeOverride: RAGQualityMode? = nil,
        externalEvidence: [EvidenceSource]? = nil,
        streamHandler: LLMStreamHandler? = nil,
        trace: RetrievalTraceCollector? = nil
    ) async throws -> RAGResponse {
        resetThinkingTimeline()
        finishAnswerNowRequested = false
        // While this answer runs, the app's side jobs leave the on-device model to it (5.8, `AnswerModelPriority`).
        AnswerModelPriority.answerStarted()
        defer { AnswerModelPriority.answerEnded() }
        // Apple's usage for every model call this answer makes is added up (`AnswerUsageTally`, 5.7) and put in
        // its metadata by `finalizeResponse`.
        return try await AnswerModelPriority.$isAnswerPath.withValue(true) {
          try await AnswerUsageTally.$current.withValue(AnswerUsageTally()) {
            try await LLMStreamingContext.$handler.withValue(streamHandler) {
                try await self.queryInternal(
                    question,
                    topK: topK,
                    config: config,
                    containerId: containerId,
                    qualityModeOverride: qualityModeOverride,
                    externalEvidence: externalEvidence,
                    trace: trace
                )
            }
          }
        }
    }

    /// - Parameter trace: optional per-query stage recorder for the retrieval benchmark. Nil
    ///   everywhere except the evaluation harness, where the only cost is a nil check per stage.
    ///   This overload owns the `.final` stage because it is the boundary at which retrieval's
    ///   output becomes the response; `HybridSearchService` records the stages up to `.candidates`
    ///   and `queryInternal` records `.rerank`.
    func queryWithAudit(
        _ question: String,
        topK: Int = 3,
        config: InferenceConfig? = nil,
        containerId: UUID? = nil,
        qualityModeOverride: RAGQualityMode? = nil,
        externalEvidence: [EvidenceSource]? = nil,
        streamHandler: LLMStreamHandler? = nil,
        trace: RetrievalTraceCollector? = nil
    ) async throws -> (response: RAGResponse, auditSnapshot: RAGAuditSnapshot?) {
        // Hold the collector for the duration of the query so the agentic path inherits it.
        //
        // `queryWithAudit` is the only place a trace enters, and in Deep Think and Maximum the work
        // happens inside `AgenticOrchestrator`, which reaches retrieval through nine separate calls
        // to `executeFullRetrievalPipeline`. Threading a parameter through all nine would be a wide
        // change to a hot path for a diagnostic that is nil in production; holding it here is one
        // line and reaches every one of them.
        //
        // Diagnostic only, and deliberately not concurrency-safe: two overlapping traced queries
        // would share a collector. The harness runs one case at a time and production passes nil,
        // so the case cannot arise today. If a second concurrent traced query is ever needed, this
        // has to become a task-local value rather than a property.
        activeRetrievalTrace = trace
        defer { activeRetrievalTrace = nil }

        let response = try await query(
            question,
            topK: topK,
            config: config,
            containerId: containerId,
            qualityModeOverride: qualityModeOverride,
            externalEvidence: externalEvidence,
            streamHandler: streamHandler,
            trace: trace
        )
        trace?.record(.final, results: response.retrievedChunks)
        return (response, lastAuditSnapshot)
    }


    func queryInternal(
        _ question: String,
        topK: Int,
        config: InferenceConfig?,
        containerId: UUID?,
        qualityModeOverride: RAGQualityMode?,
        externalEvidence: [EvidenceSource]? = nil,
        trace: RetrievalTraceCollector? = nil
    ) async throws -> RAGResponse {
        // Mark query start in trace file for pipeline debugging
        Log.traceQueryStart(question)
        let queryStartTime = CFAbsoluteTimeGetCurrent()

        // A day written beside a month as an ordinal ("September 30th") is searched as its number (`DayOrdinals`,
        // 5.7): "30th" is a word no passage dated "September 30" contains.
        let askedQuestion = question
        let question = DayOrdinals.cardinal(question)
        if question != askedQuestion {
            Log.info("[Query] Day read as a number for the search: \"\(question)\"", category: .retrieval)
        }

        // Flush trace on exit regardless of how the function returns
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - queryStartTime
            Log.traceQueryEnd(responseLength: 0, duration: duration)
            Log.flushTraceLog()
        }

        // Report CPU activity for RAG pipeline orchestration
        await MainActor.run {
            HardwareTelemetryState.shared.reportRAGPipeline(stage: "Query Processing")
        }

        // ── QueryRuntimeCoordinator: Resolve all query-scoped configuration ──────
        // Delegates mode resolution, PCC eligibility, adaptive config, query profiling,
        // and agentic routing decisions to the dedicated coordinator.
        let isAppleFMService = _llmService is AppleFoundationLLMService
        let pccSuppressed = await MainActor.run { self.isPCCSuppressed() }
        let initialCloudConsentState: CloudConsentState = await MainActor.run {
            cloudConsent[.applePCC] ?? .notDetermined
        }
        let forceAgentic = await MainActor.run {
            let forced = self.forceAgenticOnNextQuery
            self.forceAgenticOnNextQuery = false  // Reset after checking
            return forced
        }

        // Lazily create coordinator if not yet initialized (e.g., settingsStore not yet registered)
        let coordinator = await MainActor.run {
            if self.queryRuntimeCoordinator == nil {
                self.queryRuntimeCoordinator = QueryRuntimeCoordinator(settingsStore: self.settingsStore)
            }
            return self.queryRuntimeCoordinator!
        }

        let runtimeContext = await coordinator.resolveContext(
            question: question,
            qualityModeOverride: qualityModeOverride,
            isAppleFMService: isAppleFMService,
            isPCCSuppressed: pccSuppressed,
            cloudConsent: initialCloudConsentState,
            forceAgentic: forceAgentic,
            inferenceConfig: config ?? InferenceConfig()
        )

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

        // Resolve embedding context first (needed for both agentic and standard paths)
        let embeddingContext = await resolveEmbeddingContext(preferredContainerId: containerId)
        let embeddingProviderId = embeddingContext.providerId
        let queryEmbeddingService = embeddingContext.service
        let selectedId = embeddingContext.containerId
        let selectedName = embeddingContext.containerName
        let selectedDim = embeddingContext.dimension

        // AGENTIC MODE: Use multi-session orchestrator for Deep Think mode
        // Triggered by user selecting Deep Think mode, or via "Go Deeper" re-query
        if useAgentic {
            // A "Just Once" consent for Private Cloud Compute covers one question. Standard clears
            // the grant further down, where it sets the query's container. Deep Think and Maximum
            // return here, so until 5.6 the grant outlived the question it was given for, and the
            // next Deep Think or Maximum question was sent without the sheet. One question still
            // makes several model calls under one grant: this runs once, before the first of them.
            await MainActor.run {
                VerificationJournal.record(
                    "consent.grantCleared",
                    ["mode": "\(qualityMode.canonical)", "had": "\(!self.transientConsentGrants.isEmpty)"])
                self.transientConsentGrants.removeAll()
            }
            return try await executeAgenticQuery(
                question: question,
                containerId: selectedId,
                config: config,
                qualityMode: qualityMode,
                runtimeContext: runtimeContext
            )
        }

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

        // Quality mode parameters from user settings
        let qualityModeDisplayName = qualityMode.displayName
        let qualityModeInitialTopK = qualityMode.initialTopK
        let qualityModeTemperature = qualityMode.temperature
        let qualityModeUsesQueryRewriting = qualityMode.usesQueryRewriting
        let qualityModeUsesIterativeRetrieval = qualityMode.usesIterativeRetrieval
        let qualityModeRequiresCitations = qualityMode.requiresCitations

        // NEW: Comprehensive quality mode feature toggles
        let qualityModeUsesHyDE = qualityMode.usesHyDE
        let qualityModeUsesReRanking = qualityMode.usesReRanking
        let qualityModeUsesMMR = qualityMode.usesMMR
        let qualityModeUsesVerificationGates = qualityMode.usesVerificationGates
        let qualityModeUsesQueryExpansion = qualityMode.usesQueryExpansion
        let qualityModeMaxQueryExpansions = qualityMode.maxQueryExpansions
        let qualityModeUsesContainerVocabulary = qualityMode.usesContainerVocabulary
        let qualityModeUsesParentDocRetrieval = qualityMode.usesParentDocumentRetrieval
        let qualityModeMaxSiblingChunks = qualityMode.maxSiblingChunks
        let qualityModeUsesContextualCompression = qualityMode.usesContextualCompression
        let _ = qualityMode.specificationBoostWeight  // Reserved for future spec-table boosting
        let qualityModeUsesConversationMemory = qualityMode.usesConversationMemory
        let qualityModeMaxConversationTurns = qualityMode.maxConversationTurns

        // Log feature toggles for this quality mode
        Log.debug(
            "[RAGService] Quality mode '\(qualityModeDisplayName)' features: HyDE=\(qualityModeUsesHyDE), ReRank=\(qualityModeUsesReRanking), MMR=\(qualityModeUsesMMR), Verification=\(qualityModeUsesVerificationGates), QueryExpand=\(qualityModeUsesQueryExpansion), ContainerVocab=\(qualityModeUsesContainerVocabulary), ParentDoc=\(qualityModeUsesParentDocRetrieval), Compression=\(qualityModeUsesContextualCompression)",
            category: .pipeline)

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
        // Ensure cleanup even if an error is thrown later in the pipeline
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }

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

        var auditCandidatesCount = 0
        var auditRerankedCount = 0
        var auditFilteredCount = 0
        var auditDroppedCount = 0
        var auditMMRSelectedCount = 0
        var auditUniqueDocCount = 0
        var auditLenient = false
        var auditDynamicMin: Float = retrievalConfig.minSimilarity
        var auditTopSim: Float = 0
        var auditSecondSim: Float = 0
        var auditAvgTop5: Float = 0
        var auditAcceptanceOverride = false
        var usedRetrievalCascade = false
        var retryCandidates: [RetrievedChunk] = []
        var auditAnswerIntent = "unknown"
        var auditQueryWasRewritten = false
        var auditQueryExpansionCount = 0
        var auditUsedHyDE = false
        var auditUsedIterativeRetrieval = false
        var auditIterativePassCount = 0
        var auditUsedQueryRouting = false
        var auditUsedSummaryRouting = false
        var auditUsedParentDocumentRetrieval = false
        var auditUsedCorrectiveRetrieval = false
        var auditUsedContextualCompression = false
        var auditUsedGraphPacking = false
        var auditUsedSupplementaryVectorSearch = false

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

        var ragQuery: RAGQuery?
        var recoveryRetrievedChunks: [RetrievedChunk] = []
        var recoveryRetrievalTime: TimeInterval = 0
        do {
            // Clear any previous errors
            await MainActor.run {
                lastError = nil
            }

            // Edge case: Empty query
            guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Log.error("❌ [RAGService] Empty query string", category: .pipeline)
                TelemetryCenter.emit(
                    .system,
                    severity: .error,
                    title: "Query rejected",
                    metadata: ["reason": "Empty input"]
                )
                throw RAGServiceError.emptyQuery
            }

            let pipelineStartTime = Date()
            let ragQueryValue = RAGQuery(query: question, topK: effectiveTopK)
            ragQuery = ragQueryValue

            // Check if we have documents for RAG or just direct LLM chat (use live DB count)
            let hasDocuments = totalStored > 0

            if hasDocuments {
                // ENHANCED RAG pipeline with LLM query understanding + iterative retrieval

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

                if !exactCacheHit {
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

                    if useIterative {
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
                    } else {
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
                }
                // end if !exactCacheHit (Step 3)

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

                // Measure retrieval time before any MainActor work
                var retrievalTime = Date().timeIntervalSince(retrievalStartTime)
                recoveryRetrievalTime = retrievalTime

                // Log iterative metadata if applicable
                if let meta = iterativeMetadata {
                    Log.debug(
                        "[RAGService] Iterative retrieval used \(meta.iterations) iterations, \(meta.queries) query variants",
                        category: .retrieval
                    )
                }

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
                auditFilteredCount = filteredChunks.count

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

                // Context planning remains local. Consent is requested only after the
                // post-retrieval planner selects PCC and constructs the minimized payload.
                let cloudConsentState: CloudConsentState = await MainActor.run {
                    cloudConsent[.applePCC] ?? .notDetermined
                }
                if isAppleFMOnDevice,
                    cloudConsentState == .denied,
                    inferenceConfig.executionContext != .onDeviceOnly
                {
                    inferenceConfig.executionContext = .onDeviceOnly
                    inferenceConfig.allowPrivateCloudCompute = false
                    Log.info("[RAG] PCC consent denied → onDeviceOnly", category: .pipeline)
                }

                #if targetEnvironment(simulator)
                    let pccEligible = false
                #else
                    let pccEligible =
                        isAppleFMOnDevice
                        && networkAvailable
                        && inferenceConfig.allowPrivateCloudCompute
                        && inferenceConfig.executionContext != .onDeviceOnly
                        && !pccSuppressed
                #endif
                // PCC eligibility controls how much local evidence may be prepared.
                // Consent does not occur until the selected cloud envelope is final.
                let allowLargeContext = pccEligible && cloudConsentState != .denied

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

                let conservativeCharsPerToken: Double = FoundationModelTokenBudget.conservativeCharsPerToken(
                    isAppleFMOnDevice: !allowLargeContext)

                func estimateTokensConservative(chars: Int) -> Int {
                    FoundationModelTokenBudget.estimateTokens(charsCount: chars, isAppleFMOnDevice: !allowLargeContext)
                }

                // Apple FM context size is dynamic based on on-device/PCC
                let baseWindowTokens: Int = {
                    if llmService is AppleFoundationLLMService {
                        return FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: !allowLargeContext)
                    }
                    return inferenceConfig.contextLength ?? 4096
                }()

                // Only reserve tool schema tokens when tools are actually attached.
                let toolSchemaTokens: Int = {
                    if inferenceConfig.disableTools {
                        return 0  // No tools → no schema overhead
                    }
                    return isAppleFMOnDevice ? (allowLargeContext ? 800 : 1000) : 800
                }()

                let systemPromptTokens = estimateTokensConservative(chars: (inferenceConfig.systemPrompt ?? "").count)
                let promptOverheadTokens = 120 + systemPromptTokens + toolSchemaTokens
                let questionTokens = estimateTokensConservative(chars: question.count)

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

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // HARD RELEVANCE GATE: Check if retrieved content is actually relevant
                // Prevents hallucination when retrieval returns garbage
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let lexicalRelevance = checkLexicalRelevance(query: effectiveQuery, chunks: includedRetrievedChunks)
                let bestSimilarity = includedRetrievedChunks.first?.similarityScore ?? 0

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

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // Step 5.10: Extractive QA disabled — always use LLM generation.
                // Heuristic extraction produced false positives (e.g., "three-quarters"
                // for "fuel tank capacity") and skipped LLM entirely. All queries now
                // proceed to LLM generation for reliable answers.
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

                /*
                if answerIntentIsExtractive || isPrecisionValueQuery(question),
                   let extractiveOverride = await highPrecisionLookupOverrideAnswer(
                       question: question,
                       answerIntent: answerIntent,
                       retrievedChunks: precisionLookupCandidates
                   ) {
                    Log.info("[ExtractiveQA] Returning direct source extraction before LLM generation", category: .retrieval)

                    var extractiveAnswer = extractiveOverride
                    var extractiveWarnings: [String] = []
                    var extractiveConfidence = max(precisionLookupCandidates.first?.similarityScore ?? 0.0, 0.85)
                    var gatingDecision = "extractive_override_pre_generation"
                    var structuredAnswer = StructuredAnswer.from(
                        response: extractiveOverride,
                        retrievedChunks: precisionLookupCandidates,
                        answerIntent: answerIntent,
                        verificationResult: nil,
                        loops: 1
                    )

#if canImport(FoundationModels)
                    if #available(iOS 26.0, *),
                       let sourceOnlyOutcome = await sourceOnlyOutcomeIfNeeded(
                           query: question,
                           candidateAnswer: extractiveOverride,
                           retrievedChunks: precisionLookupCandidates,
                           answerIntent: answerIntent,
                           verificationResult: nil,
                           isSourceLocked: true
                       )
                    {
                        extractiveAnswer = sourceOnlyOutcome.finalAnswer
                        structuredAnswer = sourceOnlyOutcome.structuredAnswer
                        gatingDecision = appendedGatingDecision(
                            gatingDecision,
                            sourceOnlyOutcome.shouldAbstain ? "source_only_abstained" : "source_only_refined"
                        )
                        extractiveWarnings.append(contentsOf: sourceOnlyOutcome.warnings)
                        if sourceOnlyOutcome.shouldAbstain,
                           let abstentionReason = sourceOnlyOutcome.abstentionReason
                        {
                            extractiveWarnings.append(abstentionReason)
                        }
                        extractiveConfidence = sourceOnlyOutcome.shouldAbstain
                            ? min(extractiveConfidence, 0.35)
                            : min(extractiveConfidence, max(sourceOnlyOutcome.fidelityScore, 0.75))
                    }
#endif
                */

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

                // Provider-aware token budgeting (avoid hard 4K clamps for large-context providers).
                let contextTokens = estimateTokensConservative(chars: context.count)
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

                // Attempt generation with retry on context-overflow
                var llmResponse: LLMResponse
                var generationContext = context
                var generationChunks = includedChunks
                var generationRetrievedChunks = includedRetrievedChunks
                var usedOverflowRetry = false

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

                if useReasoningChain {
                    Log.info(
                        "[RAG] ✨ REASONING CHAIN ACTIVATED for Standard mode (developer override)", category: .pipeline)
                    Log.info("[RAG]   - bestRetrievalSim: \(bestRetrievalSim)", category: .pipeline)
                    Log.info("[RAG]   - contextSize: \(contextSize)", category: .pipeline)
                    Log.info("[RAG]   - chunks: \(includedRetrievedChunks.count)", category: .pipeline)
                    emitThinkingEvent(
                        .planning,
                        title: "🔗 Reasoning chain",
                        detail:
                            "\(standardComplexity.complexity == .complex ? 4 : 3) sessions × 4K = expanded Standard reasoning"
                    )

                    // Track reasoning trace for UI display
                    var chainReasoningTrace: [String]? = nil

                    // Execute reasoning chain with live thinking updates
                    do {
                        let chainResult = try await executeStandardReasoningChain(
                            query: question,
                            chunks: includedRetrievedChunks,
                            onProgress: { [weak self] title, detail in
                                // Show each reasoning phase with what it discovered
                                self?.emitThinkingEvent(
                                    .generation,
                                    title: title,
                                    detail: detail
                                )
                            }
                        )

                        // Store reasoning trace for metadata (separate from answer text)
                        // Format each insight nicely for UI display
                        if chainResult.chainInsights.count > 1 {
                            let sessionLabels = ["🔍 Analyzing Evidence", "🧠 Finding Patterns", "✨ Synthesis"]
                            chainReasoningTrace = chainResult.chainInsights.dropLast().enumerated().map {
                                idx, insight in
                                let label = idx < sessionLabels.count ? sessionLabels[idx] : "Session \(idx + 1)"
                                let cleanInsight =
                                    insight
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .replacingOccurrences(of: "INSIGHT:", with: "")
                                    .replacingOccurrences(of: "REASONING:", with: "")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                return "\(label): \(cleanInsight)"
                            }
                        }

                        // Build LLMResponse - answer only, reasoning trace stored separately
                        llmResponse = LLMResponse(
                            text: chainResult.finalAnswer,
                            tokensGenerated: chainResult.totalTokens,
                            timeToFirstToken: nil,
                            totalTime: 0,  // Not tracked per-session
                            modelName: "Apple Foundation Model (Chained)",
                            toolCallsMade: 0
                        )

                        // Store trace in a way that can be passed to metadata later
                        // We'll use a capture variable
                        reasoningTraceForMetadata = chainReasoningTrace

                        Log.info(
                            "[RAG] Reasoning chain complete: \(chainResult.sessionCount) sessions, \(chainResult.totalTokens) tokens, confidence: \(String(format: "%.0f%%", chainResult.confidence * 100))",
                            category: .pipeline)

                    } catch {
                        // Fall back to single-session generation if chain fails
                        Log.warning(
                            "[RAG] Reasoning chain failed, falling back to single session: \(error.localizedDescription)",
                            category: .pipeline)
                        emitThinkingEvent(
                            .warning,
                            title: "Chain fallback",
                            detail: "Using single session"
                        )
                        // Continue to normal generation below
                        llmResponse = try await generateWithFallback(
                            prompt: promptForGeneration,
                            context: generationContext,
                            config: genConfig,
                            sourceChunks: generationChunks,
                            allowStructuredRAG: true
                        )
                    }
                } else {
                    emitThinkingEvent(
                        .generation,
                        title: "Generating answer",
                        detail: llmService.modelName
                    )

                    do {
                        llmResponse = try await generateWithFallback(
                            prompt: promptForGeneration,
                            context: generationContext,
                            config: genConfig,
                            sourceChunks: generationChunks,
                            allowStructuredRAG: true
                        )
                    } catch {
                        // Check if this is a context overflow error
                        let isOverflowError = isContextOverflowError(error)

                        #if targetEnvironment(simulator)
                            if isOverflowError {
                                // SIMULATOR: PCC not available, must retry with smaller context
                                Log.warning("[RAG] Simulator context overflow - building evidence pack", category: .llm)
                                let reducedMax = max(256, min(genConfig.maxTokens, 384))
                                let onDeviceMaxChars = 8500  // Increased from 3500 to utilize full 4096 token window

                                let targetChunkCount = min(
                                    contextCandidates.count,
                                    isTrivial ? 6 : 9
                                )
                                let maxCharsPerChunk = max(
                                    220,
                                    min(
                                        isTrivial ? 600 : 800,
                                        onDeviceMaxChars / max(1, targetChunkCount)
                                    )
                                )
                                let (context2, usedRetryChunks) = await buildEvidencePackContext(
                                    question: question,
                                    candidates: contextCandidates,
                                    maxContextChars: onDeviceMaxChars,
                                    maxChunks: targetChunkCount,
                                    maxCharsPerChunk: maxCharsPerChunk
                                )
                                let retryRetrievedChunks = usedRetryChunks
                                let retryChunks = retryRetrievedChunks.map { $0.chunk }
                                generationContext = context2
                                generationChunks = retryChunks
                                generationRetrievedChunks = retryRetrievedChunks
                                recoveryRetrievedChunks = generationRetrievedChunks
                                usedOverflowRetry = true
                                var retryConfig = genConfig
                                retryConfig.maxTokens = reducedMax
                                retryConfig.executionContext = .onDeviceOnly
                                retryConfig.allowPrivateCloudCompute = false

                                TelemetryCenter.emit(
                                    .system,
                                    severity: .warning,
                                    title: "Simulator: evidence pack",
                                    metadata: [
                                        "contextChars": "\(context2.count)",
                                        "chunksUsed": "\(retryRetrievedChunks.count)",
                                    ]
                                )
                                llmResponse = try await generateWithFallback(
                                    prompt: promptForGeneration,
                                    context: generationContext,
                                    config: retryConfig,
                                    sourceChunks: generationChunks,
                                    allowStructuredRAG: true
                                )
                            } else {
                                // Other error - just rethrow
                                throw error
                            }
                        #else
                            if isOverflowError {
                                let reason = networkAvailable ? "PCC request overflowed" : "offline mode"
                                // FIX: Do NOT suppress PCC globally.
                                // Just because this specific request overflowed locally (e.g. system routed wrong)
                                // doesn't mean PCC is down. We will retry with smaller context, but keep PCC enabled.

                                Log.warning(
                                    "[RAG] Context overflow (\(reason)) - building evidence pack",
                                    category: .llm
                                )
                                TelemetryCenter.emit(
                                    .system,
                                    severity: .warning,
                                    title: "Context overflow - evidence pack",
                                    metadata: [
                                        "reason": reason,
                                        "chunks": "\(contextCandidates.count)",
                                    ]
                                )

                                // Apple FM has hard 4096 token limit on-device
                                // Budget: 4096 - 900 (safety) - ~700 (prompt overhead) - ~20 (question) - 768 (output) = ~1700 tokens
                                // At 2.4 chars/token, that's ~4000 chars max for context
                                let reducedMax =
                                    isTrivial
                                    ? max(256, min(genConfig.maxTokens, 384))
                                    : max(512, min(genConfig.maxTokens, 768))
                                let onDeviceBudgetTokens = max(
                                    200,
                                    4096 - 1000 - promptOverheadTokens - questionTokens - reducedMax
                                )
                                // FIXED: Reduced from 8500 to 3500 chars to actually fit in 4096 token window
                                // Apple's modelmanagerd routes to PCC when context exceeds on-device capacity
                                let onDeviceMaxChars = min(
                                    isTrivial ? 2400 : 3500,
                                    max(800, Int(Double(onDeviceBudgetTokens) * conservativeCharsPerToken))
                                )
                                let baseCandidates = retryCandidates.isEmpty ? contextCandidates : retryCandidates
                                // Use fewer, higher-quality chunks rather than many fragmented ones
                                let fallbackChunkCap =
                                    isTrivial
                                    ? min(5, baseCandidates.count)
                                    : min(6, baseCandidates.count)
                                let seedLimit =
                                    isTrivial
                                    ? min(2, baseCandidates.count)
                                    : min(3, baseCandidates.count)
                                let seedChunks = Array(baseCandidates.prefix(seedLimit))
                                let neighborPool = rerankedChunks.isEmpty ? baseCandidates : rerankedChunks
                                let fallbackChunks = buildNeighborAwareFallback(
                                    seeds: seedChunks,
                                    pool: neighborPool,
                                    maxTotal: fallbackChunkCap
                                )

                                // Use fewer chunks with more content each for better coherence
                                let targetChunkCount = min(
                                    fallbackChunks.count,
                                    isTrivial ? 4 : 5
                                )
                                // Give each chunk more room for context - better quality over quantity
                                let maxCharsPerChunk = max(
                                    350,
                                    min(
                                        isTrivial ? 650 : 750,
                                        onDeviceMaxChars / max(1, targetChunkCount)
                                    )
                                )
                                let (context2, usedRetryChunks) = await buildEvidencePackContext(
                                    question: question,
                                    candidates: fallbackChunks,
                                    maxContextChars: onDeviceMaxChars,
                                    maxChunks: targetChunkCount,
                                    maxCharsPerChunk: maxCharsPerChunk
                                )
                                let retryRetrievedChunks = usedRetryChunks
                                let retryChunks = retryRetrievedChunks.map { $0.chunk }
                                generationContext = context2
                                generationChunks = retryChunks
                                generationRetrievedChunks = retryRetrievedChunks
                                recoveryRetrievedChunks = generationRetrievedChunks
                                usedOverflowRetry = true
                                var retryConfig = genConfig
                                retryConfig.maxTokens = reducedMax
                                retryConfig.executionContext = .onDeviceOnly
                                retryConfig.allowPrivateCloudCompute = false
                                // Use minimal system prompt for on-device fallback to maximize context budget
                                retryConfig.systemPrompt =
                                    "Answer questions using ONLY the provided context. Be concise but complete. Cite sources as [S1], [S2] etc. Use **bold** sparingly for key terms. Use bullets only for actual lists."

                                TelemetryCenter.emit(
                                    .system,
                                    severity: .warning,
                                    title: "Evidence-pack retry",
                                    metadata: [
                                        "contextChars": "\(context2.count)",
                                        "chunksUsed": "\(retryRetrievedChunks.count)",
                                    ]
                                )

                                llmResponse = try await generateWithFallback(
                                    prompt: promptForGeneration,
                                    context: generationContext,
                                    config: retryConfig,
                                    sourceChunks: generationChunks,
                                    allowStructuredRAG: true
                                )
                            } else {
                                // Other error - just rethrow
                                throw error
                            }
                        #endif
                    }
                }  // End of else (non-reasoning-chain path)

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

                // Wrap all printing in error handling to prevent crashes
                do {
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

                    // Step 7.5: Verification Gates (AppleRAG Anti-Hallucination)
                    // Run Gates A-G to validate response against source evidence
                    // Respect quality mode toggle for verification
                    let runVerificationGates = qualityModeUsesVerificationGates

                    var verificationResult: RAGVerificationResult?
                    var verificationTime: TimeInterval = 0

                    if runVerificationGates {
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
                    } else {
                        Log.info(
                            "[RAG] Verification gates skipped (quality mode: \(qualityModeDisplayName))",
                            category: .pipeline)
                        emitThinkingEvent(
                            .verification,
                            title: "Verification skipped",
                            detail: "\(qualityModeDisplayName) mode"
                        )
                    }

                    // Emit telemetry for verification (only if gates were run)
                    if let vResult = verificationResult {
                        TelemetryCenter.emit(
                            .system,
                            title: "Verification complete",
                            metadata: [
                                "passed": vResult.passed ? "true" : "false",
                                "confidence": String(format: "%.2f", vResult.overallConfidence),
                                "failedGates": vResult.gateResults.filter { !$0.passed }.map { $0.gate.rawValue }
                                    .joined(separator: ","),
                            ],
                            duration: verificationTime
                        )
                    }

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

                    let response = buildStandardResponse(llmResponse: llmResponse, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, gatingSummary: gatingSummary, embeddingProviderId: embeddingProviderId, qualityMode: qualityMode, question: question, reasoningTraceForMetadata: reasoningTraceForMetadata, runtimeContext: runtimeContext, generationContext: generationContext, finalResponseText: finalResponseText, structuredAnswer: structuredAnswer, ragQueryValue: ragQueryValue, generationRetrievedChunks: generationRetrievedChunks, finalConfidenceScore: finalConfidenceScore, finalWarnings: finalWarnings, pipelineStartTime: pipelineStartTime)

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )

                } catch {
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
            } else {
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

        } catch {
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

    /// Step 9 (response): builds the response metadata and the RAGResponse and logs the total time.
    /// Moved unchanged from `queryInternal` on 2026-11-06 (`BenchmarkRuns/2026-11-06-decomposition`).
    private func buildStandardResponse(llmResponse: LLMResponse, retrievalTime: TimeInterval, retrievalConfig: RetrievalConfig, gatingSummary: String?, embeddingProviderId: String, qualityMode: RAGQualityMode, question: String, reasoningTraceForMetadata: [String]?, runtimeContext: QueryRuntimeContext, generationContext: String, finalResponseText: String, structuredAnswer: StructuredAnswer, ragQueryValue: RAGQuery, generationRetrievedChunks: [RetrievedChunk], finalConfidenceScore: Float, finalWarnings: [String], pipelineStartTime: Date) -> RAGResponse {
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
