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

        let __unpackRuntimeContextResult = await unpackRuntimeContext(runtimeContext: runtimeContext, question: question)
        // Quotes only answers with the documents' own words and no model (5.8). Deep Think and Maximum need a model to
        // reason, so a question asked in Quotes only runs through Standard's retrieval and stops before generation.
        let quotesOnly = await MainActor.run { self.quotesOnlySelected }
        let useAgentic = __unpackRuntimeContextResult.useAgentic && !quotesOnly
        let qualityMode = __unpackRuntimeContextResult.qualityMode
        var inferenceConfig = __unpackRuntimeContextResult.inferenceConfig
        let initialQueryProfile = __unpackRuntimeContextResult.initialQueryProfile
        // Quotes only has no model to fall back on (5.8): the exits that answer by direct chat or the reliability
        // fallback when retrieval finds nothing, or when a step fails, call Apple's model (refuting review, 2026-11-10).
        let reliabilityModeEnabled = __unpackRuntimeContextResult.reliabilityModeEnabled && !quotesOnly
        let adaptiveConfig = __unpackRuntimeContextResult.adaptiveConfig
        let initialWantsCloudContext = __unpackRuntimeContextResult.initialWantsCloudContext
        let initialQueryPlan = __unpackRuntimeContextResult.initialQueryPlan
        let networkAvailable = __unpackRuntimeContextResult.networkAvailable

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

        applyAdaptiveGenerationProfile(initialQueryProfile: initialQueryProfile, inferenceConfig: &inferenceConfig)

        // Quality mode parameters from user settings
        let qualityModeDisplayName = qualityMode.displayName
        let qualityModeInitialTopK = qualityMode.initialTopK
        let qualityModeTemperature = qualityMode.temperature
        let qualityModeUsesQueryRewriting = qualityMode.usesQueryRewriting
        let qualityModeUsesIterativeRetrieval = qualityMode.usesIterativeRetrieval
        let qualityModeRequiresCitations = qualityMode.requiresCitations

        // NEW: Comprehensive quality mode feature toggles
        let qualityModeUsesHyDE = qualityMode.usesHyDE && !quotesOnly
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

        let (vdb, retrievalConfig, selectedContainer, allowUngroundedFallbackForMode, asksForAnAction) = await resolveQueryContainer(reliabilityModeEnabled: reliabilityModeEnabled, selectedId: selectedId)
        let allowUngroundedFallback = allowUngroundedFallbackForMode && !quotesOnly
        // Ensure cleanup even if an error is thrown later in the pipeline
        defer {
            Task { await MainActor.run { self.currentQueryContainerId = nil } }
        }

        let (effectiveTopK, queryWords, totalStored, isTrivial) = await sizeStandardTopK(vdb: vdb, qualityModeInitialTopK: qualityModeInitialTopK, topK: topK, initialQueryProfile: initialQueryProfile, initialWantsCloudContext: initialWantsCloudContext, adaptiveConfig: adaptiveConfig)

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

        logStandardPipelinePlan(question: question, effectiveTopK: effectiveTopK, totalStored: totalStored, embeddingProviderId: embeddingProviderId, selectedDim: selectedDim, qualityModeDisplayName: qualityModeDisplayName, qualityModeUsesHyDE: qualityModeUsesHyDE, qualityModeUsesReRanking: qualityModeUsesReRanking, qualityModeUsesMMR: qualityModeUsesMMR, qualityModeUsesVerificationGates: qualityModeUsesVerificationGates, qualityModeUsesQueryExpansion: qualityModeUsesQueryExpansion, qualityModeUsesContainerVocabulary: qualityModeUsesContainerVocabulary, qualityModeUsesParentDocRetrieval: qualityModeUsesParentDocRetrieval, qualityModeUsesContextualCompression: qualityModeUsesContextualCompression, selectedName: selectedName, selectedId: selectedId, queryWords: queryWords, retrievalConfig: retrievalConfig)

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

                let __lookUpSemanticQueryCacheResult = await lookUpSemanticQueryCache(question: question, embeddingProviderId: embeddingProviderId, selectedDim: selectedDim, selectedId: selectedId)
                let exactCacheHit = __lookUpSemanticQueryCacheResult.exactCacheHit
                let cachedQueryEmbedding = __lookUpSemanticQueryCacheResult.cachedQueryEmbedding
                var retrievedChunks = __lookUpSemanticQueryCacheResult.retrievedChunks
                let cacheKey = __lookUpSemanticQueryCacheResult.cacheKey
                let isDocumentScoped = __lookUpSemanticQueryCacheResult.isDocumentScoped
                let normalizedQueryText = __lookUpSemanticQueryCacheResult.normalizedQueryText

                let __loadCorpusVocabularyResult = try await loadCorpusVocabulary(totalStored: totalStored, selectedName: selectedName, selectedId: selectedId, vdb: vdb, question: question, initialQueryPlan: initialQueryPlan, selectedContainer: selectedContainer, qualityModeUsesQueryRewriting: qualityModeUsesQueryRewriting)
                let finalCorpusVocabulary = __loadCorpusVocabularyResult.finalCorpusVocabulary
                let rewriteEnabledBySettings = __loadCorpusVocabularyResult.rewriteEnabledBySettings
                let simpleGroundedLookup = __loadCorpusVocabularyResult.simpleGroundedLookup
                let translatedInitialQuery = __loadCorpusVocabularyResult.translatedInitialQuery
                let useQueryRewriting = __loadCorpusVocabularyResult.useQueryRewriting && !quotesOnly
                let queryEnhancer = __loadCorpusVocabularyResult.queryEnhancer
                var cachedAllChunks = __loadCorpusVocabularyResult.cachedAllChunks
                let originalKeywordQuery = __loadCorpusVocabularyResult.originalKeywordQuery

                let effectiveQuery = await rewriteQueryWithModel(translatedInitialQuery: translatedInitialQuery, exactCacheHit: exactCacheHit, useQueryRewriting: useQueryRewriting, finalCorpusVocabulary: finalCorpusVocabulary, qualityModeUsesConversationMemory: qualityModeUsesConversationMemory, selectedId: selectedId, qualityModeMaxConversationTurns: qualityModeMaxConversationTurns, auditQueryWasRewritten: &auditQueryWasRewritten, question: question, rewriteEnabledBySettings: rewriteEnabledBySettings, simpleGroundedLookup: simpleGroundedLookup)

                let (expandedQueries, expansionTime) = await expandQueryForRetrieval(exactCacheHit: exactCacheHit, qualityModeUsesQueryExpansion: qualityModeUsesQueryExpansion, effectiveQuery: effectiveQuery, queryEnhancer: queryEnhancer, qualityMode: qualityMode, qualityModeMaxQueryExpansions: qualityModeMaxQueryExpansions, qualityModeDisplayName: qualityModeDisplayName, qualityModeUsesContainerVocabulary: qualityModeUsesContainerVocabulary, selectedId: selectedId, auditQueryExpansionCount: &auditQueryExpansionCount)

                let (answerIntent, answerIntentIsExtractive, contextualDefinitionLookup, effectiveQueryProfile, hasSummaryChunks, queryRoutingEnabled, isProceduralQuery, answerNeedsDocumentSummary) = await resolveStandardAnswerIntent(effectiveQuery: effectiveQuery, queryEnhancer: queryEnhancer, cachedAllChunks: cachedAllChunks, qualityMode: qualityMode, auditAnswerIntent: &auditAnswerIntent)

                let (embeddingStartTime, hydeEmbeddingText, hydeText) = await gateAndGenerateHyDE(qualityModeUsesHyDE: qualityModeUsesHyDE, answerIntentIsExtractive: answerIntentIsExtractive, answerIntent: answerIntent, embeddingProviderId: embeddingProviderId, selectedDim: selectedDim, effectiveQuery: effectiveQuery, selectedId: selectedId, auditUsedHyDE: &auditUsedHyDE)

                let (queryEmbedding, textToEmbed, embeddingTime) = try await embedQuery(effectiveQuery: effectiveQuery, hydeEmbeddingText: hydeEmbeddingText, cachedQueryEmbedding: cachedQueryEmbedding, exactCacheHit: exactCacheHit, queryEmbeddingService: queryEmbeddingService, embeddingStartTime: embeddingStartTime, hydeText: hydeText, embeddingProviderId: embeddingProviderId, selectedDim: selectedDim, selectedName: selectedName, selectedId: selectedId)

                let __planSearchRoutingResult = planSearchRouting(effectiveQueryProfile: effectiveQueryProfile, retrievalConfig: retrievalConfig, auditUsedQueryRouting: &auditUsedQueryRouting, queryRoutingEnabled: queryRoutingEnabled, contextualDefinitionLookup: contextualDefinitionLookup, cachedAllChunks: cachedAllChunks, hasSummaryChunks: hasSummaryChunks, auditUsedSummaryRouting: &auditUsedSummaryRouting)
                let adjustedVectorWeight = __planSearchRoutingResult.adjustedVectorWeight
                let adjustedKeywordWeight = __planSearchRoutingResult.adjustedKeywordWeight
                var filteredCachedChunks = __planSearchRoutingResult.filteredCachedChunks
                var iterativeMetadata = __planSearchRoutingResult.iterativeMetadata
                let queryIntent = __planSearchRoutingResult.queryIntent
                let retrievalStartTime = __planSearchRoutingResult.retrievalStartTime

                if !exactCacheHit {
                    let (useIterative, iterativeConfig) = decideIterativeRetrieval(answerIntentIsExtractive: answerIntentIsExtractive, answerIntent: answerIntent, qualityModeUsesIterativeRetrieval: qualityModeUsesIterativeRetrieval)

                    if useIterative {
                        try await runIterativeRetrieval(iterativeConfig: iterativeConfig, adjustedVectorWeight: adjustedVectorWeight, adjustedKeywordWeight: adjustedKeywordWeight, queryEmbeddingService: queryEmbeddingService, expandedQueries: expandedQueries, effectiveQuery: effectiveQuery, originalKeywordQuery: originalKeywordQuery, vdb: vdb, effectiveTopK: effectiveTopK, filteredCachedChunks: filteredCachedChunks, answerIntent: answerIntent, retrievedChunks: &retrievedChunks, iterativeMetadata: &iterativeMetadata, auditUsedIterativeRetrieval: &auditUsedIterativeRetrieval, auditIterativePassCount: &auditIterativePassCount)
                    } else {
                        try await runHybridSearch(adjustedVectorWeight: adjustedVectorWeight, adjustedKeywordWeight: adjustedKeywordWeight, effectiveTopK: effectiveTopK, queryIntent: queryIntent, vdb: vdb, retrievedChunks: &retrievedChunks, expandedQueries: expandedQueries, effectiveQuery: effectiveQuery, originalKeywordQuery: originalKeywordQuery, queryEmbedding: queryEmbedding, filteredCachedChunks: filteredCachedChunks, selectedId: selectedId, answerIntent: answerIntent, trace: trace)

                        await runSupplementaryVectorSearch(answerIntentIsExtractive: answerIntentIsExtractive, isTrivial: isTrivial, expandedQueries: expandedQueries, retrievedChunks: &retrievedChunks, effectiveQuery: effectiveQuery, textToEmbed: textToEmbed, selectedContainer: selectedContainer, queryEmbeddingService: queryEmbeddingService, vdb: vdb, effectiveTopK: effectiveTopK, auditUsedSupplementaryVectorSearch: &auditUsedSupplementaryVectorSearch, answerIntent: answerIntent)
                    }
                }
                // end if !exactCacheHit (Step 3)

                await writeSemanticQueryCache(exactCacheHit: exactCacheHit, isDocumentScoped: isDocumentScoped, retrievedChunks: retrievedChunks, cacheKey: cacheKey, selectedId: selectedId, queryEmbedding: queryEmbedding, normalizedQueryText: normalizedQueryText)

                try applyDocumentScope(retrievedChunks: &retrievedChunks, cachedAllChunks: &cachedAllChunks, filteredCachedChunks: &filteredCachedChunks)

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

                injectExternalEvidence(externalEvidence: externalEvidence, retrievedChunks: &retrievedChunks)

                await dropPassagesOfUnknownDocuments(retrievedChunks: &retrievedChunks)

                if let exitResponse = try await handleNoRetrievedPassages(retrievedChunks: retrievedChunks, question: question, retrievalTime: retrievalTime, allowUngroundedFallback: allowUngroundedFallback, ragQueryValue: ragQueryValue, inferenceConfig: inferenceConfig, pipelineStartTime: pipelineStartTime, selectedId: selectedId, selectedName: selectedName, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId) { return exitResponse }

                let __attachSourcesAndDemoteQuestionsResult = await attachSourcesAndDemoteQuestions(retrievedChunks: retrievedChunks, question: question, auditCandidatesCount: &auditCandidatesCount, recoveryRetrievedChunks: &recoveryRetrievedChunks, effectiveTopK: effectiveTopK, selectedName: selectedName, selectedId: selectedId, retrievalTime: retrievalTime, adjustedVectorWeight: adjustedVectorWeight, adjustedKeywordWeight: adjustedKeywordWeight)
                var chunksWithSources = __attachSourcesAndDemoteQuestionsResult.chunksWithSources
                let docsSnapshot = __attachSourcesAndDemoteQuestionsResult.docsSnapshot

                applySectionMetadataBoost(chunksWithSources: &chunksWithSources, question: question, retrievalTime: retrievalTime)

                // A follow-up is ranked by the question retrieval searched with (5.8): "how long does it last?" was found with
                // the rewritten question and then ranked and extracted with "it". The gates still read the question asked.
                let rankingQuestion = auditQueryWasRewritten ? effectiveQuery : question
                let __rerankCandidatesResult = await rerankCandidates(qualityModeUsesReRanking: qualityModeUsesReRanking, chunksWithSources: chunksWithSources, question: rankingQuestion, effectiveTopK: effectiveTopK, auditRerankedCount: &auditRerankedCount, qualityModeDisplayName: qualityModeDisplayName, trace: trace)
                let engine = __rerankCandidatesResult.engine
                var rerankTime = __rerankCandidatesResult.rerankTime
                var rerankedChunks = __rerankCandidatesResult.rerankedChunks

                try await runRetrievalCascade(rerankedChunks: &rerankedChunks, effectiveQueryProfile: effectiveQueryProfile, qualityMode: qualityMode, retrievalConfig: retrievalConfig, effectiveTopK: effectiveTopK, totalStored: totalStored, usedRetrievalCascade: &usedRetrievalCascade, expandedQueries: expandedQueries, question: question, vdb: vdb, originalKeywordQuery: originalKeywordQuery, queryEmbedding: queryEmbedding, docsSnapshot: docsSnapshot, engine: engine, auditCandidatesCount: &auditCandidatesCount, auditRerankedCount: &auditRerankedCount, retrievalTime: &retrievalTime, rerankTime: &rerankTime, recoveryRetrievalTime: &recoveryRetrievalTime)

                boostContextualDefinitionMatches(contextualDefinitionLookup: contextualDefinitionLookup, rerankedChunks: &rerankedChunks, question: question)

                await retryWithCleanKeywordQuery(rerankedChunks: &rerankedChunks, question: question, queryEmbeddingService: queryEmbeddingService, vdb: vdb, effectiveTopK: effectiveTopK, filteredCachedChunks: filteredCachedChunks, selectedId: selectedId, docsSnapshot: docsSnapshot, qualityModeUsesReRanking: qualityModeUsesReRanking, engine: engine)

                if let exitResponse = try await handleEmptyRerank(rerankedChunks: rerankedChunks, allowUngroundedFallback: allowUngroundedFallback, question: question, ragQueryValue: ragQueryValue, inferenceConfig: inferenceConfig, pipelineStartTime: pipelineStartTime, retrievalTime: retrievalTime, selectedId: selectedId, selectedName: selectedName, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId) { return exitResponse }

                let __filterLowConfidenceChunksResult = await filterLowConfidenceChunks(auditLenient: &auditLenient, rerankedChunks: rerankedChunks, auditTopSim: &auditTopSim, auditSecondSim: &auditSecondSim, auditAvgTop5: &auditAvgTop5, effectiveQueryProfile: effectiveQueryProfile, qualityMode: qualityMode, retrievalConfig: retrievalConfig, auditDynamicMin: &auditDynamicMin, engine: engine, auditAcceptanceOverride: &auditAcceptanceOverride)
                let dynamicMin = __filterLowConfidenceChunksResult.dynamicMin
                var filteredChunks = __filterLowConfidenceChunksResult.filteredChunks
                let acceptanceOverride = __filterLowConfidenceChunksResult.acceptanceOverride
                let lenient = __filterLowConfidenceChunksResult.lenient
                let topSim = __filterLowConfidenceChunksResult.topSim
                let secondSim = __filterLowConfidenceChunksResult.secondSim
                let avgTop5 = __filterLowConfidenceChunksResult.avgTop5
                let vocabularyMismatch = __filterLowConfidenceChunksResult.vocabularyMismatch

                rescueDroppedSpecChunks(filteredChunks: &filteredChunks, rerankedChunks: rerankedChunks, auditDroppedCount: &auditDroppedCount, dynamicMin: dynamicMin, answerIntentIsExtractive: answerIntentIsExtractive, answerIntent: answerIntent)

                if let exitResponse = await handleNoConfidentPassages(filteredChunks: &filteredChunks, acceptanceOverride: acceptanceOverride, lenient: lenient, effectiveTopK: effectiveTopK, rerankedChunks: rerankedChunks, topSim: topSim, secondSim: secondSim, avgTop5: avgTop5, allowUngroundedFallback: allowUngroundedFallback, dynamicMin: dynamicMin, question: question, ragQueryValue: ragQueryValue, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, selectedId: selectedId, selectedName: selectedName) { return exitResponse }
                auditFilteredCount = filteredChunks.count

                let uniqueDocCount = ensureMultiDocumentCoverage(rerankedChunks: rerankedChunks, auditUniqueDocCount: &auditUniqueDocCount, effectiveTopK: effectiveTopK, filteredChunks: &filteredChunks, retryCandidates: &retryCandidates)

                let (diverseChunks, mmrTime) = await diversifyWithMMR(retrievalConfig: retrievalConfig, qualityModeUsesMMR: qualityModeUsesMMR, qualityModeDisplayName: qualityModeDisplayName, effectiveTopK: effectiveTopK, filteredChunks: filteredChunks, auditMMRSelectedCount: &auditMMRSelectedCount, isProceduralQuery: isProceduralQuery, engine: engine, queryEmbedding: queryEmbedding, selectedId: selectedId)

                if let exitResponse = try await handleEmptyDiverseSet(diverseChunks: diverseChunks, allowUngroundedFallback: allowUngroundedFallback, question: question, ragQueryValue: ragQueryValue, inferenceConfig: inferenceConfig, pipelineStartTime: pipelineStartTime, retrievalTime: retrievalTime, selectedId: selectedId, selectedName: selectedName, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId) { return exitResponse }

                if let exitResponse = await enforcePassagesNeeded(rerankedChunks: rerankedChunks, diverseChunks: diverseChunks, retrievalConfig: retrievalConfig, retrievalTime: retrievalTime, embeddingProviderId: embeddingProviderId, ragQueryValue: ragQueryValue, question: question, selectedId: selectedId, selectedName: selectedName) { return exitResponse }

                let __prepareContextCandidatesResult = prepareContextCandidates(diverseChunks: diverseChunks, question: question)
                var contextCandidates = __prepareContextCandidatesResult.contextCandidates
                var contextStrategy = __prepareContextCandidatesResult.contextStrategy
                let isEnumerationQuery = __prepareContextCandidatesResult.isEnumerationQuery
                let isAppleFMOnDevice = __prepareContextCandidatesResult.isAppleFMOnDevice

                addSummaryDetailHybrid(answerNeedsDocumentSummary: answerNeedsDocumentSummary, cachedAllChunks: cachedAllChunks, isEnumerationQuery: isEnumerationQuery, contextCandidates: &contextCandidates, question: question, contextStrategy: &contextStrategy)

                applyFocusedNeighborWindow(diverseChunks: diverseChunks, question: question, auditAvgTop5: auditAvgTop5, auditTopSim: auditTopSim, queryWords: queryWords, rerankedChunks: rerankedChunks, uniqueDocCount: uniqueDocCount, isAppleFMOnDevice: isAppleFMOnDevice, initialWantsCloudContext: initialWantsCloudContext, effectiveTopK: effectiveTopK, contextCandidates: &contextCandidates, contextStrategy: &contextStrategy)

                addEnumerationKeywordPass(cachedAllChunks: cachedAllChunks, isEnumerationQuery: isEnumerationQuery, contextCandidates: &contextCandidates, question: question, contextStrategy: &contextStrategy)

                await expandParentDocuments(qualityModeUsesParentDocRetrieval: qualityModeUsesParentDocRetrieval, adaptiveConfig: adaptiveConfig, cachedAllChunks: cachedAllChunks, contextCandidates: &contextCandidates, auditUsedParentDocumentRetrieval: &auditUsedParentDocumentRetrieval, effectiveQueryProfile: effectiveQueryProfile, qualityMode: qualityMode, qualityModeMaxSiblingChunks: qualityModeMaxSiblingChunks, useAgentic: useAgentic, question: question, contextStrategy: &contextStrategy)

                await addCrossReferencedPassages(answerIntentIsExtractive: answerIntentIsExtractive, contextCandidates: &contextCandidates, question: question, cachedAllChunks: cachedAllChunks)

                runSpecTableSniper(answerIntentIsExtractive: answerIntentIsExtractive, cachedAllChunks: cachedAllChunks, contextCandidates: &contextCandidates, question: question)

                let __gateContextualCompressionResult = gateContextualCompression(isProceduralQuery: isProceduralQuery, vocabularyMismatch: vocabularyMismatch, contextStrategy: contextStrategy, qualityModeUsesContextualCompression: qualityModeUsesContextualCompression, adaptiveConfig: adaptiveConfig)
                let useContextualCompression = __gateContextualCompressionResult.useContextualCompression && !quotesOnly
                var compressionSavings = __gateContextualCompressionResult.compressionSavings

                await compressContextCandidates(contextCandidates: &contextCandidates, useContextualCompression: useContextualCompression, auditUsedContextualCompression: &auditUsedContextualCompression, question: question, answerIntent: answerIntent, compressionSavings: &compressionSavings)

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

                await packContextWithGraph(contextCandidates: &contextCandidates, question: question, answerIntent: answerIntent, cachedAllChunks: cachedAllChunks, allowLargeContext: allowLargeContext, isAppleFMOnDevice: isAppleFMOnDevice, auditUsedGraphPacking: &auditUsedGraphPacking)

                await runCorrectiveRetrieval(effectiveQuery: effectiveQuery, contextCandidates: &contextCandidates, answerIntentIsExtractive: answerIntentIsExtractive, effectiveTopK: effectiveTopK, selectedId: selectedId, cachedAllChunks: cachedAllChunks, answerIntent: answerIntent, qualityModeUsesReRanking: qualityModeUsesReRanking, engine: engine, question: question, rerankTime: &rerankTime, contextStrategy: &contextStrategy, auditUsedCorrectiveRetrieval: &auditUsedCorrectiveRetrieval, retrievalTime: &retrievalTime, recoveryRetrievalTime: &recoveryRetrievalTime)

                let applyTrivialCaps = disableToolsForAssembledContext(allowLargeContext: allowLargeContext, isTrivial: isTrivial, contextCandidates: contextCandidates, inferenceConfig: &inferenceConfig)

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

                let (maxContextChars, useCompactMode, reservedOutputTokens, availableForContextTokens, globalSafetyFactor) = computeContextCharBudget(inferenceConfig: inferenceConfig, baseWindowTokens: baseWindowTokens, promptOverheadTokens: promptOverheadTokens, questionTokens: questionTokens, allowLargeContext: allowLargeContext, isAppleFMOnDevice: isAppleFMOnDevice, applyTrivialCaps: applyTrivialCaps, conservativeCharsPerToken: conservativeCharsPerToken)

                // A table summary lists two rows; the table itself takes its place (5.8, `withTablesForSummaries`).
                contextCandidates = Self.withTablesForSummaries(contextCandidates, allChunks: cachedAllChunks ?? [])

                let (orderedCandidates, useLostInMiddleMitigation) = orderContextCandidates(isProceduralQuery: isProceduralQuery, contextCandidates: contextCandidates, answerIntentIsExtractive: answerIntentIsExtractive, question: question)

                let (actualChunksUsed, context, placedForAttention, promptSources, rescuedChunks) = await assembleStandardContext(answerIntentIsExtractive: answerIntentIsExtractive, isProceduralQuery: isProceduralQuery, orderedCandidates: orderedCandidates, question: rankingQuestion, maxContextChars: maxContextChars, useCompactMode: useCompactMode, engine: engine, useLostInMiddleMitigation: useLostInMiddleMitigation)

                let (contextWords, contextSize, includedRetrievedChunks, includedChunks) = finishIncludedPassages(actualChunksUsed: actualChunksUsed, context: context, question: question, placedForAttention: placedForAttention, contextCandidates: contextCandidates, contextStrategy: contextStrategy, useCompactMode: useCompactMode, promptSources: promptSources, rescuedChunks: rescuedChunks, recoveryRetrievedChunks: &recoveryRetrievedChunks)

                await recordContextAuditSnapshot(actualChunksUsed: actualChunksUsed, contextWords: contextWords, contextSize: contextSize, selectedName: selectedName, selectedId: selectedId, selectedContainer: selectedContainer, question: question, embeddingProviderId: embeddingProviderId, selectedDim: selectedDim, qualityModeDisplayName: qualityModeDisplayName, retrievalConfig: retrievalConfig, auditLenient: auditLenient, auditDynamicMin: auditDynamicMin, auditTopSim: auditTopSim, auditSecondSim: auditSecondSim, auditAvgTop5: auditAvgTop5, auditAcceptanceOverride: auditAcceptanceOverride, totalStored: totalStored, auditCandidatesCount: auditCandidatesCount, auditRerankedCount: auditRerankedCount, auditFilteredCount: auditFilteredCount, auditDroppedCount: auditDroppedCount, auditMMRSelectedCount: auditMMRSelectedCount, auditUniqueDocCount: auditUniqueDocCount, contextStrategy: contextStrategy, maxContextChars: maxContextChars, baseWindowTokens: baseWindowTokens, promptOverheadTokens: promptOverheadTokens, questionTokens: questionTokens, reservedOutputTokens: reservedOutputTokens, availableForContextTokens: availableForContextTokens, inferenceConfig: inferenceConfig, networkAvailable: networkAvailable, allowLargeContext: allowLargeContext, reliabilityModeEnabled: reliabilityModeEnabled, allowUngroundedFallback: allowUngroundedFallback, auditAnswerIntent: auditAnswerIntent, auditQueryWasRewritten: auditQueryWasRewritten, auditQueryExpansionCount: auditQueryExpansionCount, auditUsedHyDE: auditUsedHyDE, auditUsedIterativeRetrieval: auditUsedIterativeRetrieval, auditIterativePassCount: auditIterativePassCount, auditUsedQueryRouting: auditUsedQueryRouting, auditUsedSummaryRouting: auditUsedSummaryRouting, auditUsedParentDocumentRetrieval: auditUsedParentDocumentRetrieval, auditUsedCorrectiveRetrieval: auditUsedCorrectiveRetrieval, auditUsedContextualCompression: auditUsedContextualCompression, auditUsedGraphPacking: auditUsedGraphPacking, usedRetrievalCascade: usedRetrievalCascade, auditUsedSupplementaryVectorSearch: auditUsedSupplementaryVectorSearch)

                if let exitResponse = try await handleEmptyAssembledContext(actualChunksUsed: actualChunksUsed, context: context, allowUngroundedFallback: allowUngroundedFallback, question: question, ragQueryValue: ragQueryValue, inferenceConfig: inferenceConfig, pipelineStartTime: pipelineStartTime, retrievalTime: retrievalTime, selectedId: selectedId, selectedName: selectedName, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId) { return exitResponse }

                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                // HARD RELEVANCE GATE: Check if retrieved content is actually relevant
                // Prevents hallucination when retrieval returns garbage
                // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
                let lexicalRelevance = checkLexicalRelevance(query: effectiveQuery, chunks: includedRetrievedChunks)
                let bestSimilarity = includedRetrievedChunks.first?.similarityScore ?? 0

                if let exitResponse = await applyHardRelevanceGate(bestSimilarity: bestSimilarity, lexicalRelevance: lexicalRelevance, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, ragQueryValue: ragQueryValue, question: question, selectedId: selectedId, selectedName: selectedName) { return exitResponse }

                // Step QO: Quotes only answers here, from the passages assembled for the model, with no model call (5.8).
                if quotesOnly {
                    let response = quotesOnlyResponse(question: question, passages: includedRetrievedChunks, queryId: ragQueryValue.id, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId)
                    return await finalizeResponse(query: question, containerId: selectedId, containerName: selectedName, response: response)
                }

                let (useEvidenceFirstMode, uniqueSourceDocs, bestRetrievalSim) = assessEvidenceBeforeGeneration(includedRetrievedChunks: includedRetrievedChunks, actualChunksUsed: actualChunksUsed, auditAvgTop5: auditAvgTop5, auditDynamicMin: auditDynamicMin, lexicalRelevance: lexicalRelevance, isProceduralQuery: isProceduralQuery)

                if let exitResponse = await answerWithExtractiveSummary(answerIntent: answerIntent, effectiveQuery: effectiveQuery, includedRetrievedChunks: includedRetrievedChunks, retrievalTime: retrievalTime, ragQueryValue: ragQueryValue, question: question, selectedId: selectedId, selectedName: selectedName) { return exitResponse }

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

                let generationStartTime = await beginGenerationStep(contextWords: contextWords)

                var genConfig = composeStandardGenerationConfig(inferenceConfig: inferenceConfig, includedChunks: includedChunks, question: question, answerIntent: answerIntent, contextualDefinitionLookup: contextualDefinitionLookup, useEvidenceFirstMode: useEvidenceFirstMode, qualityModeTemperature: qualityModeTemperature, retrievalConfig: retrievalConfig)

                // Provider-aware token budgeting (avoid hard 4K clamps for large-context providers).
                let contextTokens = estimateTokensConservative(chars: context.count)
                capGenerationTokens(baseWindowTokens: baseWindowTokens, contextTokens: contextTokens, promptOverheadTokens: promptOverheadTokens, questionTokens: questionTokens, globalSafetyFactor: globalSafetyFactor, genConfig: &genConfig, isProceduralQuery: isProceduralQuery, allowLargeContext: allowLargeContext, isTrivial: isTrivial)

                let (promptForGeneration, requiresCitations) = buildGenerationPrompt(selectedId: selectedId, question: question, retrievalConfig: retrievalConfig, qualityModeRequiresCitations: qualityModeRequiresCitations)

                // Attempt generation with retry on context-overflow
                var llmResponse: LLMResponse
                var generationContext = context
                var generationChunks = includedChunks
                var generationRetrievedChunks = includedRetrievedChunks
                var usedOverflowRetry = false

                try await applyPostRetrievalModelPlan(uniqueSourceDocs: uniqueSourceDocs, answerIntent: answerIntent, qualityMode: qualityMode, promptForGeneration: promptForGeneration, generationContext: &generationContext, genConfig: &genConfig, generationRetrievedChunks: &generationRetrievedChunks, cloudConsentState: cloudConsentState, networkAvailable: networkAvailable, question: question, generationChunks: &generationChunks, engine: engine, orderedCandidates: orderedCandidates, useLostInMiddleMitigation: useLostInMiddleMitigation)

                let __decideReasoningChainResult = decideReasoningChain(initialQueryProfile: initialQueryProfile, qualityMode: qualityMode, useEvidenceFirstMode: useEvidenceFirstMode, isTrivial: isTrivial, bestRetrievalSim: bestRetrievalSim, contextSize: contextSize, includedRetrievedChunks: includedRetrievedChunks)
                let useReasoningChain = __decideReasoningChainResult.useReasoningChain
                let standardComplexity = __decideReasoningChainResult.standardComplexity
                var reasoningTraceForMetadata = __decideReasoningChainResult.reasoningTraceForMetadata

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

                let __retryForMissingCitationsResult = await retryForMissingCitations(llmResponse: &llmResponse, requiresCitations: requiresCitations, allowUngroundedFallback: allowUngroundedFallback, selectedName: selectedName, question: question, genConfig: genConfig, usedOverflowRetry: usedOverflowRetry, generationContext: generationContext, generationChunks: generationChunks)
                var responseText = __retryForMissingCitationsResult.responseText
                let preserveStreamingResponse = __retryForMissingCitationsResult.preserveStreamingResponse

                if let exitResponse = await abstainForMissingCitations(requiresCitations: requiresCitations, responseText: responseText, allowUngroundedFallback: allowUngroundedFallback, preserveStreamingResponse: preserveStreamingResponse, question: question, ragQueryValue: ragQueryValue, generationRetrievedChunks: generationRetrievedChunks, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, selectedId: selectedId, selectedName: selectedName) { return exitResponse }

                await repairResponseIntegrity(responseText: &responseText, question: question, answerIntent: answerIntent, genConfig: genConfig, requiresCitations: requiresCitations, generationContext: generationContext, generationChunks: generationChunks, llmResponse: &llmResponse)

                var responsiveness = await ensureAnswerResponds(responseText: &responseText, llmResponse: &llmResponse, question: promptForGeneration, genConfig: genConfig, requiresCitations: requiresCitations, generationContext: generationContext, generationChunks: generationChunks)
                let responsivenessJudgedText = responseText

                let (generationTime, responseWordCount) = emitGenerationTelemetry(generationStartTime: generationStartTime, responseText: responseText, llmResponse: llmResponse, selectedName: selectedName, selectedId: selectedId)

                // Wrap all printing in error handling to prevent crashes
                do {
                    logGeneratedResponse(generationTime: generationTime, responseText: responseText, responseWordCount: responseWordCount, llmResponse: llmResponse)

                    if let exitResponse = try await fallBackFromEmptyAnswer(responseText: responseText, recoveryRetrievedChunks: recoveryRetrievedChunks, question: question, effectiveTopK: effectiveTopK, ragQuery: ragQuery, inferenceConfig: inferenceConfig, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, recoveryRetrievalTime: recoveryRetrievalTime, selectedId: selectedId, selectedName: selectedName) { return exitResponse }

                    var sourceLockedFinalResponse = await applyPrecisionLookupOverride(answerIntentIsExtractive: answerIntentIsExtractive, question: question, answerIntent: answerIntent, generationRetrievedChunks: generationRetrievedChunks, responseText: &responseText)
                    // The extractor's value replaces an answer only when it answers too: a value lifted from a source can
                    // be a page range or a table cell that says nothing on its own.
                    if sourceLockedFinalResponse, responseText != responsivenessJudgedText,
                        let judged = responsiveness, judged.verdict != .none,
                        let lockedJudgment = await judgeResponsiveness(question: promptForGeneration, answer: responseText, stage: "extracted"),
                        lockedJudgment.verdict == .none
                    {
                        Log.info("[Responsiveness] The extracted value does not answer the question; keeping the model's answer", category: .llm)
                        responseText = responsivenessJudgedText
                        sourceLockedFinalResponse = false
                    }

                    let (confidenceScore, qualityWarnings) = await assessAnswerQuality(generationRetrievedChunks: generationRetrievedChunks, engine: engine, question: question, auditTopSim: auditTopSim)

                    // Step 7.5: Verification Gates (AppleRAG Anti-Hallucination)
                    // Run the verification gates (A to I) against the evidence
                    // Respect quality mode toggle for verification
                    let runVerificationGates = qualityModeUsesVerificationGates

                    var verificationResult: RAGVerificationResult?
                    var verificationTime: TimeInterval = 0

                    if runVerificationGates {
                        let (confidencePolicy, verificationService) = await verifyAnswerAgainstEvidence(question: question, answerIntent: answerIntent, qualityMode: qualityMode, auditAvgTop5: auditAvgTop5, auditSecondSim: auditSecondSim, auditTopSim: auditTopSim, responseText: responseText, queryEmbeddingService: queryEmbeddingService, generationRetrievedChunks: generationRetrievedChunks, vdb: vdb, verificationResult: &verificationResult, contextCandidates: contextCandidates, queryEmbedding: queryEmbedding, llmResponse: llmResponse, verificationTime: &verificationTime)

                        if let exitResponse = await abstainOnFailedVerification(verificationResult: verificationResult, confidencePolicy: confidencePolicy, answerIntentIsExtractive: answerIntentIsExtractive, answerIntent: answerIntent, allowUngroundedFallback: allowUngroundedFallback, qualityModeDisplayName: qualityModeDisplayName, verificationService: verificationService, question: question, generationRetrievedChunks: generationRetrievedChunks, ragQueryValue: ragQueryValue, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, selectedId: selectedId, selectedName: selectedName) { return exitResponse }
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

                    calibrateConfidenceAndLogCompletion(pipelineStartTime: pipelineStartTime, question: question, answerIntent: answerIntent, qualityMode: qualityMode, generationRetrievedChunks: generationRetrievedChunks, verificationResult: verificationResult, confidenceScore: confidenceScore, expansionTime: expansionTime, embeddingTime: embeddingTime, retrievalTime: retrievalTime, rerankTime: rerankTime, mmrTime: mmrTime, verificationTime: verificationTime, generationTime: generationTime, selectedName: selectedName, selectedId: selectedId)

                    var (finalResponseText, structuredAnswer, gatingSummary, finalWarnings, finalConfidenceScore) = summarizeGatingAndWarnings(acceptanceOverride: acceptanceOverride, lenient: lenient, verificationResult: verificationResult, qualityWarnings: qualityWarnings, responseText: responseText, confidenceScore: confidenceScore, generationRetrievedChunks: generationRetrievedChunks, answerIntent: answerIntent, llmResponse: llmResponse, reasoningTraceForMetadata: reasoningTraceForMetadata, allowUngroundedFallback: allowUngroundedFallback)

                    await applySourceOnlyCheck(answerIntentIsExtractive: answerIntentIsExtractive, question: question, qualityMode: qualityMode, verificationResult: verificationResult, answerIntent: answerIntent, responseText: responseText, generationRetrievedChunks: generationRetrievedChunks, sourceLockedFinalResponse: sourceLockedFinalResponse, finalResponseText: &finalResponseText, structuredAnswer: &structuredAnswer, gatingSummary: &gatingSummary, finalWarnings: &finalWarnings, finalConfidenceScore: &finalConfidenceScore, confidenceScore: confidenceScore)

                    // The shown text was replaced after the judge read it (precision override or source-only rewrite): judge
                    // the text the reader gets, so the verdict is about that answer.
                    if responsiveness != nil, finalResponseText != responsivenessJudgedText {
                        responsiveness = await judgeResponsiveness(question: promptForGeneration, answer: finalResponseText, stage: "final")
                    }
                    if let responsiveness {
                        gatingSummary = appendedGatingDecision(gatingSummary, responsiveness.gatingToken)
                        if responsiveness.verdict != .full, !responsiveness.missing.isEmpty {
                            finalWarnings.append("May not fully answer the question: \(responsiveness.missing)")
                        }
                    }

                    let response = buildStandardResponse(llmResponse: llmResponse, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, gatingSummary: gatingSummary, embeddingProviderId: embeddingProviderId, qualityMode: qualityMode, question: question, reasoningTraceForMetadata: reasoningTraceForMetadata, runtimeContext: runtimeContext, generationContext: generationContext, finalResponseText: finalResponseText, structuredAnswer: structuredAnswer, ragQueryValue: ragQueryValue, generationRetrievedChunks: generationRetrievedChunks, finalConfidenceScore: finalConfidenceScore, finalWarnings: finalWarnings, pipelineStartTime: pipelineStartTime)

                    return await finalizeResponse(
                        query: question,
                        containerId: selectedId,
                        containerName: selectedName,
                        response: response
                    )

                } catch {
                    return await recoverFromResponseProcessingError(error: error, llmResponse: llmResponse, generationRetrievedChunks: generationRetrievedChunks, answerIntent: answerIntent, reasoningTraceForMetadata: reasoningTraceForMetadata, generationTime: generationTime, retrievalTime: retrievalTime, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, ragQueryValue: ragQueryValue, question: question, selectedId: selectedId, selectedName: selectedName)
                }
            } else {
                return try await answerWithoutDocuments(allowUngroundedFallback: allowUngroundedFallback, asksForAnAction: asksForAnAction, question: question, ragQueryValue: ragQueryValue, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, selectedId: selectedId, selectedName: selectedName, inferenceConfig: inferenceConfig, pipelineStartTime: pipelineStartTime)
            }

        } catch {
            return try await recoverFromQueryFailure(error: error, reliabilityModeEnabled: reliabilityModeEnabled, recoveryRetrievedChunks: recoveryRetrievedChunks, question: question, effectiveTopK: effectiveTopK, ragQuery: ragQuery, inferenceConfig: inferenceConfig, retrievalConfig: retrievalConfig, embeddingProviderId: embeddingProviderId, recoveryRetrievalTime: recoveryRetrievalTime, selectedId: selectedId, selectedName: selectedName)
        }
    }

}
