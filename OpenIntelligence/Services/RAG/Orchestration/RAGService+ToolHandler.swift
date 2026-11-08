//
//  RAGService+ToolHandler.swift
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
// MARK: - RAGService Tool Handler Implementation

// This enables agentic RAG where the LLM can decide when to search documents

extension RAGService: RAGToolHandler {
    /// Search documents for relevant information
    /// Called by the LLM when it needs information from the document library
    func searchDocuments(query: String) async throws -> String {
        Log.debug(" [Tool Call] search_documents(query: \"\(query)\")")

        // Use the existing RAG pipeline to search
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuery.text)

        let db = await dbFor(embeddingContext.containerId)

        let retrievedChunks = try await db.search(
            embedding: queryEmbedding,
            topK: 3  // Return top 3 chunks for tool call
        )

        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Format retrieved chunks for LLM consumption
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"

        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview  // Truncated preview to control token usage
            result += "\n\n"
        }

        Log.info(" [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// Callback type for emitting detailed thinking events during retrieval
    /// Used by AgenticOrchestrator to stream verbose pipeline events to ThinkingView
    typealias DetailedThinkingCallback = @Sendable (ThinkingEvent.Kind, String, String) async -> Void

    /// Execute the FULL retrieval pipeline (HyDE, hybrid search, AI re-ranking, MMR)
    /// This gives Deep Think mode the same quality retrieval as Standard mode
    /// Used by AgenticOrchestrator for high-quality chunk retrieval with reasoning on top
    /// - Parameter qualityMode: Controls retrieval parameters (mmrLambda, parent doc, etc.)
    /// - Parameter onDetailedEvent: Optional callback for verbose thinking events (for Deep Think/Maximum)
    /// - Parameter trace: Optional per-stage recorder. Nil in production; the benchmark passes one.
    ///
    ///   This parameter did not exist until 2026-08-19, and its absence is why the agentic path was
    ///   unmeasurable. A paired benchmark recorded standard mode across seven stages — vector,
    ///   lexical, fusion, boosted, candidates, rerank, final — and deep-think across exactly one,
    ///   `final`, because `queryWithAudit` records that stage from the response and nothing inside
    ///   this function recorded anything. The numbers showed deep-think retrieval at r@10 **0.625**
    ///   against standard's **1.000** on the same eight cases, and no way to say which stage lost
    ///   the document. Two hypotheses were formed and refuted by reading source in the same hour.
    ///   Instrumenting is the fix that makes the next attempt an attribution rather than a guess.
    func executeFullRetrievalPipeline(
        query: String,
        topK: Int = 20,
        minSimilarity: Float? = nil,
        qualityMode: RAGQualityMode? = nil,
        onDetailedEvent: DetailedThinkingCallback? = nil,
        trace: RetrievalTraceCollector? = nil
    ) async throws -> [RetrievedChunk] {
        // Callers in `AgenticOrchestrator` pass nothing, so fall back to whatever `queryWithAudit`
        // is holding. That is what makes Deep Think measurable without touching nine call sites.
        let effectiveTrace = trace ?? activeRetrievalTrace
        let chunks = try await performFullRetrievalPipeline(
            // Deep Think's and Maximum's own searches read a day the same way as the question (`DayOrdinals`).
            query: DayOrdinals.cardinal(query),
            topK: topK,
            minSimilarity: minSimilarity,
            qualityMode: qualityMode,
            onDetailedEvent: onDetailedEvent,
            trace: effectiveTrace
        )

        // The stage `queryWithAudit` records for the standard path, recorded here too so the two
        // modes are comparable end to end rather than only where they happen to overlap.
        effectiveTrace?.record(.final, results: chunks)

        // An empty retrieval is the moment to check whether this library can answer at all,
        // because it is the moment the user finds out it cannot.
        //
        // `evaluateSemanticIndexHealth` had exactly one caller, gated on the active container
        // actually *changing*, so a library that lost its vector store while the user was already
        // in it was never checked. A device capture on 2026-08-18 shows the consequence: FTS5 held
        // the document, the Database tab listed it, Atlas showed nothing, the query fused "0
        // results into 0 unique chunks" and hard-exited, and no rebuild banner ever appeared
        // because nothing evaluated health. Deleting and re-creating the library was the only way
        // out, and that is what the owner had to do.
        //
        // Detached so it cannot slow the query it is reacting to, and gated on an empty result so
        // it costs a vector-store count only in the case that has already failed.
        // `evaluateSemanticIndexHealth` treats a read failure as "not proven missing" and flags
        // only when documents exist and the store genuinely reads zero, so this cannot raise a
        // banner on a library that is merely slow.
        if chunks.isEmpty {
            let containerId = await MainActor.run { self.containerService.activeContainerId }
            Task { @MainActor [weak self] in
                await self?.evaluateSemanticIndexHealth(for: containerId)
            }
        }

        return chunks
    }

    private func performFullRetrievalPipeline(
        query: String,
        topK: Int,
        minSimilarity: Float?,
        qualityMode: RAGQualityMode?,
        onDetailedEvent: DetailedThinkingCallback?,
        trace: RetrievalTraceCollector? = nil
    ) async throws -> [RetrievedChunk] {
        // Resolve quality mode from parameter or settings
        let mode: RAGQualityMode
        if let explicit = qualityMode {
            mode = explicit
        } else {
            mode = await MainActor.run { self.settingsStore?.ragQualityMode ?? .standard }
        }
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let resolvedRetrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig
                ?? .default
        }
        let effectiveMinSimilarity = minSimilarity ?? resolvedRetrievalConfig.minSimilarity
        let db = await dbFor(embeddingContext.containerId)
        // Narrowed when the question names documents, and without passages of no document (5.7,
        // `chunksOfListedDocuments`): this list feeds the overview routing, lexical recall, the spec sniper and
        // sibling expansion below, the way `cachedAllChunks` does for Standard (review, 2026-10-19).
        let allChunks = RAGQueryScope.apply(to: await chunksOfListedDocuments(try await db.readableChunks()))

        // Skip if no chunks
        guard !allChunks.isEmpty else { return [] }

        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let semanticQuery = translatedQuery.text
        let originalKeywordQuery = translatedQuery.wasTranslated ? query : semanticQuery

        // Emit: Starting retrieval pipeline
        await onDetailedEvent?(.planning, "Query analysis", "Analyzing: \"\(query.prefix(50))...\"")

        // RAPTOR-lite: Query routing for summary-first retrieval
        // Only filter chunks if query routing is enabled AND we have summaries
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: semanticQuery,
            queryRouter: queryRouter,
            routingEnabled: queryRoutingEnabled
        )
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = queryProfile.routingClassification
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                // For overview queries in agentic mode, use summaries first
                let searchLevels = queryProfile.abstractionLevelsToSearch
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info(
                    "[RAPTOR-lite] Agentic retrieval using \(effectiveChunks.count) summary chunks for overview query",
                    category: .retrieval)
                await onDetailedEvent?(
                    .retrieval, "RAPTOR-lite routing", "Using \(effectiveChunks.count) summary chunks")
            }
        }

        // Step 1: Use the semantic retrieval query for embedding
        // NOTE: HyDE disabled in Deep Think - it hallucinates without document context
        // and poisons retrieval with irrelevant content (e.g., "serial numbers" for "button" queries)
        let textToEmbed = semanticQuery

        // Step 2: Generate query embedding
        await onDetailedEvent?(.embedding, "Encoding query", "384-dim neural embedding")
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: textToEmbed)
        await onDetailedEvent?(.vectorSearch, "Vector ready", "Query encoded for semantic search")

        // Step 3: Classify query intent for adaptive weights AND expand query
        // Fetch corpus vocabulary from cache (built during Standard mode or prior queries)
        let cachedVocab: CorpusVocabulary? = await MainActor.run {
            self.corpusVocabularyCache[embeddingContext.containerId]
        }
        // If not cached yet, build it now from available chunks (ensures DT/Max gets corpus-aware expansion)
        let agenticVocab: CorpusVocabulary?
        if let cached = cachedVocab {
            agenticVocab = cached
        } else if !allChunks.isEmpty {
            // `allChunks` is only the named documents' passages when the question is limited to
            // documents. A vocabulary of those serves this question and is not held as the
            // library's. (From 2026-10-09 until this was written it was, so the first such
            // question after a launch left every later one expanding from one document's words.)
            let built = await libraryVocabulary(
                for: embeddingContext.containerId, from: allChunks,
                isWholeLibrary: (RAGQueryScope.documentIds ?? []).isEmpty)
            agenticVocab = built
        } else {
            agenticVocab = nil
        }

        let queryEnhancer = QueryEnhancementService(corpusVocabulary: agenticVocab)
        let queryIntent = queryProfile.searchIntent
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: resolvedRetrievalConfig)
        let vectorWeight = adjustedWeights.vectorWeight
        let keywordWeight = adjustedWeights.keywordWeight

        // Emit: Query expansion
        await onDetailedEvent?(
            .queryRewrite, "Query expansion",
            "Intent: \(queryIntent.rawValue) → Vector \(Int(vectorWeight * 100))% / Keyword \(Int(keywordWeight * 100))%"
        )

        // EXPAND query with synonyms for better keyword matching
        // e.g., "button" → "button switch toggle control key trigger"
        var expandedQueries = queryEnhancer.expandQuery(semanticQuery)

        // Gazetteer domain vocabulary enrichment
        let gazetteerMatchesFR = await GazetteerService.shared.matchingTerms(for: semanticQuery)
        if !gazetteerMatchesFR.isEmpty {
            // A matched term is in the question already; appended again it only repeats words (5.7).
            let uniqueGazetteer = gazetteerMatchesFR.map { $0.term }.filter { term in
                !semanticQuery.localizedCaseInsensitiveContains(term)
                    && !expandedQueries.contains { $0.caseInsensitiveCompare(term) == .orderedSame }
            }
            expandedQueries.append(contentsOf: uniqueGazetteer.prefix(5))
            if !uniqueGazetteer.isEmpty {
                Log.debug(
                    "[FullRetrieval] Gazetteer added \(min(uniqueGazetteer.count, 5)) domain terms",
                    category: .retrieval)
            }
        }

        let expandedQueryString = expandedQueries.joined(separator: " ")
        Log.debug("[FullRetrieval] Expanded query: \(expandedQueryString.prefix(100))...", category: .retrieval)

        if expandedQueries.count > 1 {
            await onDetailedEvent?(.queryRewrite, "Synonym expansion", "+\(expandedQueries.count - 1) terms added")
        }

        // Step 4: Hybrid search (vector + BM25) with EXPANDED query for keywords
        await onDetailedEvent?(.retrieval, "Hybrid search", "Vector + BM25 on \(effectiveChunks.count) chunks")

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        var retrievedChunks = try await hybridSearch.search(
            query: expandedQueryString,  // Use expanded query for better keyword matching
            originalQuery: originalKeywordQuery,
            embedding: queryEmbedding,
            topK: topK * 2,  // Get extra for re-ranking
            cachedChunks: effectiveChunks,  // Use RAPTOR-lite filtered chunks
            containerId: embeddingContext.containerId,  // Enable SQLite FTS5 acceleration
            trace: trace  // Records vector, lexical, fusion, boosted and candidates
        )

        // Demote purely interrogative chunks to prevent retrieval poisoning
        var demotedCount = 0
        for i in 0..<retrievedChunks.count {
            if isInterrogativeChunk(retrievedChunks[i].chunk, query: query) {
                let originalScore = retrievedChunks[i].similarityScore
                retrievedChunks[i] = RetrievedChunk(
                    chunk: retrievedChunks[i].chunk,
                    similarityScore: originalScore * 0.1,  // Demote severely
                    rank: retrievedChunks[i].rank,
                    sourceDocument: retrievedChunks[i].sourceDocument,
                    pageNumber: retrievedChunks[i].pageNumber
                )
                demotedCount += 1
            }
        }
        if demotedCount > 0 {
            retrievedChunks.sort { $0.similarityScore > $1.similarityScore }
            Log.info("[FullRetrieval] Demoted \(demotedCount) purely interrogative/FAQ chunks.", category: .retrieval)
        }

        await onDetailedEvent?(.rrf, "RRF fusion", "\(retrievedChunks.count) candidates from hybrid search")

        // Step 5: AI Re-ranking with ReRanker model
        await onDetailedEvent?(.rerank, "AI re-ranking", "Scoring \(retrievedChunks.count) chunks with neural model")

        let engine = RAGEngine.shared
        retrievedChunks = await engine.rerank(chunks: retrievedChunks, query: semanticQuery, topK: topK * 2)
        // Record the stage that just ran. This line missing is why every deep-think benchmark trace
        // showed six stages and no `.rerank`, which was then read as "Deep Think has no reranker"
        // and hardened into ledger entries, STATE, a roadmap row and a commit message on 2026-08-20
        // before this function was actually read. The reranker has been on this path all along —
        // unconditional between the hybrid search above and here. An unrecorded stage is not an
        // absent stage; this is the same lesson as the fusion order/score split, one layer up.
        trace?.record(.rerank, results: retrievedChunks)

        await onDetailedEvent?(
            .rerank, "Re-ranking complete",
            "Top scores: \(retrievedChunks.prefix(3).map { String(format: "%.0f%%", $0.similarityScore * 100) }.joined(separator: ", "))"
        )

        // Step 6: MMR Diversification (uses quality mode lambda)
        let mmrLambda: Float = resolvedRetrievalConfig.mmrLambda
        await onDetailedEvent?(
            .mmr, "MMR diversification", "Optimizing for coverage (λ=\(String(format: "%.2f", mmrLambda)))")
        retrievedChunks = await engine.applyMMR(
            candidates: retrievedChunks,
            queryEmbedding: queryEmbedding,
            topK: topK,
            lambda: mmrLambda,
            vectors: await storedVectors(for: retrievedChunks, in: embeddingContext.containerId)
        )

        await onDetailedEvent?(.mmr, "Diversity optimized", "\(retrievedChunks.count) chunks after MMR")

        // Step 7: Filter by similarity
        let preFilterCount = retrievedChunks.count
        retrievedChunks = await engine.filterBySimilarity(chunks: retrievedChunks, min: effectiveMinSimilarity)

        if preFilterCount > retrievedChunks.count {
            await onDetailedEvent?(
                .context, "Quality filter",
                "Kept \(retrievedChunks.count)/\(preFilterCount) (≥\(Int(effectiveMinSimilarity * 100))% threshold)")
        }

        // Precision/spec lookups need the same rescue path in Deep Think that
        // Standard mode uses. Rerankers often prefer prose around a spec table
        // over the actual row containing the value.
        let fullPipelineAnswerIntent = queryProfile.answerIntent
        if fullPipelineAnswerIntent.isExtractiveFirst || isPrecisionValueQuery(query) {
            let existingIds = Set(retrievedChunks.map { $0.chunk.id })
            let sniperResults = specTableSniper(
                query: query,
                allChunks: allChunks,
                excludeIds: existingIds
            )
            if !sniperResults.isEmpty {
                retrievedChunks.insert(contentsOf: sniperResults, at: 0)
                demoteCrossReferenceChunks(&retrievedChunks)
                await onDetailedEvent?(
                    .retrieval, "Spec sniper",
                    "+\(sniperResults.count) targeted chunks via keyword+number co-occurrence")
                Log.info(
                    "[FullRetrieval] Spec sniper added \(sniperResults.count) targeted chunks", category: .retrieval)
            }
        }

        // Step 7.5: Parent Document Retrieval (expand with sibling chunks for context)
        if mode.usesParentDocumentRetrieval && !retrievedChunks.isEmpty {
            let maxSiblings = mode.maxSiblingChunks
            await onDetailedEvent?(.parentDoc, "Parent doc retrieval", "Expanding with ±\(maxSiblings) sibling chunks")

            var expandedChunks: [RetrievedChunk] = []
            var seenChunkIds = Set<UUID>()

            // Expansion is only worth what survives into the prompt. Ungated, this stage grew an
            // 18-chunk result to 85 immediately before synthesis applied a fixed-size cut, so it
            // actively harmed the answer: none of the added context fit, and the inflated array
            // displaced the ranked set that did. Siblings are now admitted in parent-rank order
            // and only while the projected evidence still fits the on-device window.
            //
            // The on-device ratio is used regardless of where the query is ultimately allowed to
            // run. Sizing this against a cloud window would expand most aggressively in exactly
            // the case the device cannot hold.
            let expansionTokenBudget = FoundationModelTokenBudget.tokenBudget(isAppleFMOnDevice: true)
            var projectedTokens = 0
            var siblingsSkippedForBudget = 0

            func projectedTokenCost(_ chunk: DocumentChunk) -> Int {
                FoundationModelTokenBudget.estimateTokens(
                    charsCount: chunk.contextText.count,
                    isAppleFMOnDevice: true
                )
            }

            // Each document's passages once, in the order `allChunks` holds them (5.8). The sibling search below
            // filtered every passage in the library for every result: 8,202 passages for each of about 30 results,
            // in each of Deep Think's five searches, on his iPhone on 2026-11-04. `Dictionary(grouping:by:)` keeps
            // each group in sequence order, so filtering a document's group gives the same passages in the same order
            // as filtering the library, and the sort after it gives the same result
            // (`DeepThinkRetrievalGoldenTests` compares the two).
            let passagesByDocument = Dictionary(grouping: allChunks, by: \.documentId)

            for chunk in retrievedChunks {
                // Add the original chunk. Primary matches are never gated — the budget governs how
                // much *extra* context expansion may buy, not whether retrieval's own results survive.
                if seenChunkIds.insert(chunk.chunk.id).inserted {
                    expandedChunks.append(chunk)
                    projectedTokens += projectedTokenCost(chunk.chunk)
                }

                // Find sibling chunks from the same document
                let siblings = (passagesByDocument[chunk.chunk.documentId] ?? []).filter { candidate in
                    candidate.documentId == chunk.chunk.documentId && candidate.id != chunk.chunk.id
                        && abs(candidate.metadata.chunkIndex - chunk.chunk.metadata.chunkIndex) <= maxSiblings
                }.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }

                for sibling in siblings {
                    guard !seenChunkIds.contains(sibling.id) else { continue }

                    let cost = projectedTokenCost(sibling)
                    guard projectedTokens + cost <= expansionTokenBudget else {
                        siblingsSkippedForBudget += 1
                        continue
                    }

                    seenChunkIds.insert(sibling.id)
                    projectedTokens += cost
                    // Siblings get a discounted score
                    expandedChunks.append(
                        RetrievedChunk(
                            chunk: sibling,
                            similarityScore: chunk.similarityScore * 0.85,
                            rank: expandedChunks.count + 1,
                            sourceDocument: chunk.sourceDocument,
                            pageNumber: sibling.metadata.pageNumber
                        ))
                }
            }

            if expandedChunks.count > retrievedChunks.count {
                await onDetailedEvent?(
                    .parentDoc, "Context expanded",
                    "\(retrievedChunks.count) → \(expandedChunks.count) chunks with siblings")
                retrievedChunks = expandedChunks
            }

            if siblingsSkippedForBudget > 0 {
                await onDetailedEvent?(
                    .parentDoc,
                    "Expansion capped",
                    "Skipped \(siblingsSkippedForBudget) siblings at ~\(projectedTokens)/\(expansionTokenBudget) tokens"
                )
                Log.info(
                    "[FullRetrieval] Parent expansion capped by budget: skipped \(siblingsSkippedForBudget) siblings, "
                        + "projected ~\(projectedTokens)/\(expansionTokenBudget) tokens",
                    category: .retrieval
                )
            }
        }

        // Step 8: Lost-in-Middle reorder (place best chunks at start and end)
        if retrievedChunks.count >= 4 {
            var reordered: [RetrievedChunk] = []
            let sorted = retrievedChunks.sorted { $0.similarityScore > $1.similarityScore }
            for (index, chunk) in sorted.enumerated() {
                if index % 2 == 0 {
                    reordered.append(chunk)  // Even indices go to front
                } else {
                    reordered.insert(chunk, at: reordered.count / 2)  // Odd go to middle
                }
            }
            retrievedChunks = reordered
            await onDetailedEvent?(.lostInMiddle, "Lost-in-Middle reorder", "Best evidence at start/end of context")
        }

        // Passages whose document is in no library are left out (5.7, `passagesFromKnownDocuments`): the vector
        // search above reads the whole store. Deep Think and Maximum search through here, not through
        // `searchDocumentsRaw` (review, 2026-10-19).
        let listedDocumentIds = await MainActor.run { Set(self.documents.map(\.id)) }
        let fromListedDocuments = Self.passagesFromKnownDocuments(retrievedChunks, knownDocumentIds: listedDocumentIds)
        if fromListedDocuments.dropped > 0 {
            Log.warning(
                "[FullRetrieval] Left out \(fromListedDocuments.dropped) passage(s) whose document is in no library",
                category: .retrieval)
            retrievedChunks = fromListedDocuments.kept
        }

        // Enrich with document names
        var enrichedChunks: [RetrievedChunk] = []
        for (rank, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            enrichedChunks.append(
                RetrievedChunk(
                    chunk: retrieved.chunk,
                    similarityScore: retrieved.similarityScore,
                    rank: rank + 1,
                    sourceDocument: docName,
                    pageNumber: retrieved.chunk.metadata.pageNumber
                ))
        }

        // Final retrieval summary
        await onDetailedEvent?(.retrieval, "Retrieval complete", "\(enrichedChunks.count) chunks ready for synthesis")

        // A table summary lists two rows; the table itself takes its place (5.8, `withTablesForSummaries`).
        return Self.withTablesForSummaries(enrichedChunks, allChunks: allChunks)
    }

    /// Search and return raw chunks for agentic orchestrator (not just formatted string)
    /// Uses hybrid search (vector + BM25) for better retrieval quality on technical documents.
    /// Used internally by AgenticOrchestrator to collect chunks for UnifiedMetricsBar
    func searchDocumentsRaw(query: String, topK: Int = 10, minSimilarity: Float? = nil) async throws -> [RetrievedChunk]
    {
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedQuery = await translatedQueryForEmbedding(query, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedQuery.text)

        let db = await dbFor(embeddingContext.containerId)
        let queryRoutingEnabled = await MainActor.run { self.settingsStore?.enableQueryRouting ?? true }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: translatedQuery.text,
            queryRouter: queryRouter,
            routingEnabled: queryRoutingEnabled
        )
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig
                ?? .default
        }
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        // Use hybrid search (vector + BM25) for better keyword matching on technical terms
        // Critical for technical docs where exact terms like codes and specs matter
        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let allChunks = RAGQueryScope.apply(to: try await db.readableChunks())  // narrowed when the question names documents

        // RAPTOR-lite: Query routing for summary-first retrieval
        var effectiveChunks = allChunks

        if queryRoutingEnabled {
            let queryClassification = queryProfile.routingClassification
            let hasSummaries = allChunks.contains { $0.metadata.abstractionLevel == .documentSummary }

            if hasSummaries && queryClassification.queryType == .overview && queryClassification.confidence >= 0.5 {
                let searchLevels = queryProfile.abstractionLevelsToSearch
                effectiveChunks = allChunks.filter { searchLevels.contains($0.metadata.abstractionLevel) }
                Log.info("[RAPTOR-lite] Raw search using \(effectiveChunks.count) summary chunks", category: .retrieval)
            }
        }

        // A document scope narrows the candidates before the search and the result after it.
        effectiveChunks = RAGQueryScope.apply(to: effectiveChunks)

        // Request more candidates for better coverage
        let effectiveTopK = max(topK, 15)
        var retrievedChunks = try await hybridSearch.search(
            query: translatedQuery.text,
            originalQuery: translatedQuery.wasTranslated ? query : translatedQuery.text,
            embedding: queryEmbedding,
            topK: effectiveTopK,
            cachedChunks: effectiveChunks,
            containerId: embeddingContext.containerId  // Enable SQLite FTS5 acceleration
        )
        retrievedChunks = RAGQueryScope.apply(to: retrievedChunks)

        let engine = RAGEngine.shared
        retrievedChunks = await engine.filterBySimilarity(
            chunks: retrievedChunks,
            min: minSimilarity ?? retrievalConfig.minSimilarity
        )

        // Passages whose document is in no library are left out (5.7, `passagesFromKnownDocuments`).
        let liveDocumentIds = await MainActor.run { Set(self.documents.map(\.id)) }
        retrievedChunks = Self.passagesFromKnownDocuments(retrievedChunks, knownDocumentIds: liveDocumentIds).kept

        // Enrich with source document names
        var enrichedChunks: [RetrievedChunk] = []
        for (rank, retrieved) in retrievedChunks.enumerated() {
            let docName = await documentName(for: retrieved.chunk.documentId)
            enrichedChunks.append(
                RetrievedChunk(
                    chunk: retrieved.chunk,
                    similarityScore: retrieved.similarityScore,
                    rank: rank + 1,
                    sourceDocument: docName,
                    pageNumber: retrieved.chunk.metadata.pageNumber
                ))
        }

        // A table summary lists two rows; the table itself takes its place (5.8, `withTablesForSummaries`).
        return Self.withTablesForSummaries(enrichedChunks, allChunks: allChunks)
    }

    /// Agentic search with optional topK and minSimilarity (called by Function Calling)
    func searchDocuments(query: String, topK: Int?, minSimilarity: Float?) async throws -> String {
        Log.debug(
            "[Tool Call] search_documents(query: \"\(query)\", topK: \(topK?.description ?? "nil"), minSimilarity: \(minSimilarity?.description ?? "nil"))"
        )

        let k = max(1, topK ?? 3)
        let retrievedChunks = try await searchDocumentsRaw(
            query: query,
            topK: k,
            minSimilarity: minSimilarity
        )

        // Edge case: No results
        if retrievedChunks.isEmpty {
            return "No relevant information found for: \(query)"
        }

        // Step 4: Format retrieved chunks for LLM consumption (citations + preview)
        var result = "Found \(retrievedChunks.count) relevant chunks:\n\n"
        for (index, retrieved) in retrievedChunks.enumerated() {
            let docName = retrieved.sourceDocument
            result += "[\(index + 1)] From \(docName)"
            if let page = retrieved.chunk.metadata.pageNumber {
                result += " (Page \(page))"
            }
            result +=
                " (Relevance: \(String(format: "%.1f%%", retrieved.similarityScore * 100))):\n"
            let fullText = retrieved.chunk.content.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fullText.count > 600 ? String(fullText.prefix(600)) + " [...]" : fullText
            result += preview
            result += "\n\n"
        }

        Log.info(" [Tool Call] Returned \(retrievedChunks.count) chunks")
        return result
    }

    /// List all available documents
    /// Called by the LLM when user asks what documents are available
    func listDocuments() async throws -> String {
        Log.debug(" [Tool Call] list_documents()")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { doc in
            if let cid = doc.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        if scopedDocs.isEmpty {
            return "No documents available in the selected library."
        }

        var result = "Available documents (\(scopedDocs.count)):\n\n"

        for (index, doc) in scopedDocs.enumerated() {
            result += "\(index + 1). \(doc.filename)\n"
            if let pages = doc.processingMetadata?.pagesProcessed {
                result += "   - Pages: \(pages)\n"
            }
            result += "   - Chunks: \(doc.totalChunks)\n"
            result += "   - Added: \(formatDate(doc.addedAt))\n"
            result += "\n"
        }

        Log.info(" [Tool Call] Listed \(scopedDocs.count) documents (scoped)")
        return result
    }

    /// Get summary of a specific document
    /// Called by the LLM when user asks about a specific document
    func getDocumentSummary(documentName: String) async throws -> String {
        Log.debug(" [Tool Call] get_document_summary(documentName: \"\(documentName)\")")

        // Scope to the query's container (or active if no query in flight)
        let (activeId, defaultId, docsSnapshot) = await MainActor.run {
            (
                self.currentQueryContainerId ?? self.containerService.activeContainerId,
                self.containerService.containers.first?.id,
                self.documents
            )
        }
        let scopedDocs = docsSnapshot.filter { d in
            if let cid = d.containerId {
                return cid == activeId
            } else {
                return activeId == defaultId
            }
        }
        guard
            let doc = scopedDocs.first(where: {
                $0.filename.lowercased().contains(documentName.lowercased())
            })
        else {
            return "Document not found in selected library: \(documentName)"
        }

        var result = "Document: \(doc.filename)\n"
        if let pages = doc.processingMetadata?.pagesProcessed {
            result += "- Pages: \(pages)\n"
        }
        result += "- Chunks: \(doc.totalChunks)\n"
        result += "- Added: \(formatDate(doc.addedAt))\n"
        result += "- File Type: \(doc.contentType.rawValue)"

        Log.info(" [Tool Call] Returned summary for \(doc.filename) (scoped)")
        return result
    }

    /// Count occurrences of a pattern across ALL documents (exact matching)
    /// This uses full-text storage, not semantic search - ZERO data loss counting
    /// FTS5 path is 10-100X faster than legacy file-based storage
    /// Token-budget aware: max ~600 chars output (15 docs × ~40 chars each)
    func countPatternInCorpus(pattern: String) async throws -> String {
        Log.debug("🔧 [Tool Call] count_pattern_in_corpus(pattern: \"\(pattern)\")")

        let activeId = await MainActor.run { self.containerService.activeContainerId }

        // Try FTS5 first (10-100X faster), fall back to legacy file storage
        let fts5Available = await SQLiteFullTextService.shared.documentCount(for: activeId) > 0

        let counts: [UUID: Int]
        if fts5Available {
            // FTS5 path: Use container-scoped search with native bm25()
            counts = await SQLiteFullTextService.shared.countPatternInCorpus(
                pattern: pattern,
                containerId: activeId
            )
            Log.debug("[RAGService] Using FTS5 for pattern count (container: \(activeId))", category: .retrieval)
        } else {
            // Legacy path: File-based storage — scope to active container's documents
            let containerDocs = await MainActor.run {
                documents.filter { doc in
                    if let cid = doc.containerId { return cid == activeId }
                    return activeId == containerService.containers.first?.id
                }
            }
            let docIds = containerDocs.map { $0.id }
            counts = await FullTextStorageService.shared.countPatternInCorpus(pattern: pattern, documentIds: docIds)
            Log.debug(
                "[RAGService] Using legacy file storage for pattern count (scoped to \(docIds.count) docs)",
                category: .retrieval)
        }

        if counts.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        let totalOccurrences = counts.values.reduce(0, +)

        // Compact format for token budget
        var result = "**'\(pattern)':** \(totalOccurrences) total in \(counts.count) docs\n"

        // Sort by count descending, limit to 15 for token budget (~600 chars max)
        let sortedCounts = counts.sorted { $0.value > $1.value }
        let maxDocs = 15

        for (docId, count) in sortedCounts.prefix(maxDocs) {
            let docName = await documentName(for: docId)
            // Truncate long names
            let truncName = docName.count > 35 ? String(docName.prefix(32)) + "..." : docName
            result += "- \(truncName): \(count)\n"
        }

        if sortedCounts.count > maxDocs {
            result += "... +\(sortedCounts.count - maxDocs) more\n"
        }

        Log.info("🔧 [Tool Call] Pattern '\(pattern)' found \(totalOccurrences) times in \(counts.count) docs")
        return result
    }

    /// Search for exact text pattern across ALL documents
    /// Returns documents containing the pattern with context
    /// FTS5 path is 10-100X faster with native snippet() support
    /// Token-budget aware: max ~800 chars (8 matches × ~100 chars each)
    func searchExactPattern(pattern: String) async throws -> String {
        Log.debug("🔧 [Tool Call] search_exact_pattern(pattern: \"\(pattern)\")")

        let activeId = await MainActor.run { self.containerService.activeContainerId }

        // Try FTS5 first (10-100X faster with native snippets), fall back to legacy
        let fts5Available = await SQLiteFullTextService.shared.documentCount(for: activeId) > 0

        let matches: [FullTextStorageService.SearchMatch]
        if fts5Available {
            // FTS5 path: Use container-scoped search with native snippet()
            let fts5Matches = await SQLiteFullTextService.shared.searchCorpus(
                pattern: pattern,
                containerId: activeId,
                maxResults: 10,
                contextChars: 300
            )
            // Convert to legacy SearchMatch format for compatibility
            matches = fts5Matches.map { m in
                FullTextStorageService.SearchMatch(
                    documentId: m.documentId,
                    occurrences: m.count,
                    contextSnippet: m.context
                )
            }
            Log.debug("[RAGService] Using FTS5 for exact search (container: \(activeId))", category: .retrieval)
        } else {
            // Legacy path: File-based storage — scope to active container's documents
            let containerDocs = await MainActor.run {
                documents.filter { doc in
                    if let cid = doc.containerId { return cid == activeId }
                    return activeId == containerService.containers.first?.id
                }
            }
            let docIds = containerDocs.map { $0.id }
            matches = await FullTextStorageService.shared.searchCorpus(
                pattern: pattern, documentIds: docIds, maxResults: 10)
            Log.debug(
                "[RAGService] Using legacy file storage for exact search (scoped to \(docIds.count) docs)",
                category: .retrieval)
        }

        if matches.isEmpty {
            return "Pattern '\(pattern)' not found in any documents."
        }

        // Context budget: enough to show actual values, not just cross-references
        // 200 chars per snippet ensures spec table values are visible
        let maxMatches = 8
        let maxSnippetChars = 200

        var result = "**'\(pattern)'** in \(matches.count) docs:\n"

        for match in matches.prefix(maxMatches) {
            let docName = await documentName(for: match.documentId)
            let truncName = docName.count > 30 ? String(docName.prefix(27)) + "..." : docName
            let truncSnippet =
                match.contextSnippet.count > maxSnippetChars
                ? String(match.contextSnippet.prefix(maxSnippetChars)) + "..."
                : match.contextSnippet
            result += "**\(truncName)** (\(match.occurrences)x): \"\(truncSnippet)\"\n"
        }

        if matches.count > maxMatches {
            result += "... +\(matches.count - maxMatches) more\n"
        }

        Log.info("🔧 [Tool Call] Pattern '\(pattern)' found in \(matches.count) docs with context")
        return result
    }

    /// Get corpus-wide statistics
    /// Token-budget aware: returns compact stats (~200-400 chars)
    func getCorpusStats() async throws -> String {
        Log.debug("🔧 [Tool Call] get_corpus_stats()")

        let activeId = await MainActor.run { self.containerService.activeContainerId }
        let docs = await MainActor.run { self.documents }

        guard !docs.isEmpty else {
            return "No documents in the current container."
        }

        // Calculate statistics
        let totalDocs = docs.count
        let totalPages = docs.reduce(0) { $0 + ($1.processingMetadata?.pagesProcessed ?? 1) }
        let totalChunks = docs.reduce(0) { $0 + $1.totalChunks }

        // Document type breakdown (top 5 only to save tokens)
        var typeBreakdown: [String: Int] = [:]
        for doc in docs {
            let ext = doc.contentType.rawValue.uppercased()
            typeBreakdown[ext, default: 0] += 1
        }

        // FTS5 stats
        let fts5DocCount = await SQLiteFullTextService.shared.documentCount(for: activeId)
        let fts5TotalChars = await SQLiteFullTextService.shared.totalCharacterCount(for: activeId)

        // Compact format to respect 4096 token budget
        var result = "📊 **Corpus:** \(totalDocs) docs, \(totalPages) pages, \(totalChunks) chunks\n"
        result += "**FTS5:** \(fts5DocCount) indexed (\(formatByteCount(fts5TotalChars)))\n"
        result += "**Types:** "
        result += typeBreakdown.sorted(by: { $0.value > $1.value })
            .prefix(5)
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ", ")

        Log.info("🔧 [Tool Call] Corpus stats: \(totalDocs) docs, \(totalPages) pages")
        return result
    }

    /// Find documents semantically related to a topic
    /// Token-budget aware: returns compact list (~50 chars per doc, max 10 docs = ~500 chars)
    func findRelatedDocuments(topic: String, maxResults: Int) async throws -> String {
        Log.debug("🔧 [Tool Call] find_related_documents(topic: \"\(topic)\", max: \(maxResults))")

        // Clamp maxResults to avoid token overflow (10 docs × ~50 chars = ~500 chars)
        let safeMaxResults = min(maxResults, 10)

        // Get semantic search results using HybridSearchService
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedTopic = await translatedQueryForEmbedding(topic, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedTopic.text)
        let db = await dbFor(embeddingContext.containerId)
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig
                ?? .default
        }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: translatedTopic.text, routingEnabled: false)
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let results = try await hybridSearch.search(
            query: translatedTopic.text,
            originalQuery: translatedTopic.wasTranslated ? topic : translatedTopic.text,
            embedding: queryEmbedding,
            topK: safeMaxResults * 3,
            cachedChunks: nil as [DocumentChunk]?,
            containerId: embeddingContext.containerId
        )

        if results.isEmpty {
            return "No documents found related to '\(topic)'."
        }

        // Group by document and score by average relevance
        var docScores: [UUID: (name: String, avgScore: Float, chunkCount: Int)] = [:]

        for result in results {
            let docId = result.chunk.documentId
            let docName = await documentName(for: docId)

            if var existing = docScores[docId] {
                existing.avgScore =
                    (existing.avgScore * Float(existing.chunkCount) + result.similarityScore)
                    / Float(existing.chunkCount + 1)
                existing.chunkCount += 1
                docScores[docId] = existing
            } else {
                docScores[docId] = (name: docName, avgScore: result.similarityScore, chunkCount: 1)
            }
        }

        // Sort by score, limit to safe max
        let sortedDocs = docScores.sorted { $0.value.avgScore > $1.value.avgScore }
            .prefix(safeMaxResults)

        // Compact format
        var result = "**Related to '\(topic)':** \(sortedDocs.count) docs\n"

        for (index, (_, info)) in sortedDocs.enumerated() {
            let relevance = String(format: "%.0f%%", info.avgScore * 100)
            // Truncate long names to 40 chars
            let truncatedName = info.name.count > 40 ? String(info.name.prefix(37)) + "..." : info.name
            result += "\(index + 1). \(truncatedName) (\(relevance))\n"
        }

        Log.info("🔧 [Tool Call] Found \(sortedDocs.count) documents related to '\(topic)'")
        return result
    }

    /// Compare how multiple documents discuss a topic
    /// Token-budget aware: max 1500 chars total (~600 tokens) to leave room for synthesis
    func compareDocumentsOnTopic(topic: String, documentNames: [String]?) async throws -> String {
        Log.debug("🔧 [Tool Call] compare_documents(topic: \"\(topic)\")")

        // Token budget: ~1500 chars max for comparison output
        let maxTotalChars = 1500
        let maxSnippetChars = 200  // Per snippet
        let maxDocsToCompare = 5  // Max documents
        let maxSnippetsPerDoc = 2  // Max snippets per doc

        // Search for the topic using HybridSearchService
        let embeddingContext = await resolveEmbeddingContext()
        let container = await containerForId(embeddingContext.containerId)
        let translatedTopic = await translatedQueryForEmbedding(topic, container: container)
        let queryEmbedding = try await embeddingContext.service.generateEmbedding(for: translatedTopic.text)
        let db = await dbFor(embeddingContext.containerId)
        let retrievalConfig = await MainActor.run {
            self.containerService.containers.first { $0.id == embeddingContext.containerId }?.retrievalConfig
                ?? .default
        }
        let queryProfile = await QueryProfileService.shared.buildProfile(
            for: translatedTopic.text, routingEnabled: false)
        let adjustedWeights = queryProfile.adjustedHybridWeights(from: retrievalConfig)

        let hybridSearch = HybridSearchService(
            vectorDatabase: db,
            vectorWeight: adjustedWeights.vectorWeight,
            keywordWeight: adjustedWeights.keywordWeight
        )

        let results = try await hybridSearch.search(
            query: translatedTopic.text,
            originalQuery: translatedTopic.wasTranslated ? topic : translatedTopic.text,
            embedding: queryEmbedding,
            topK: 20,
            cachedChunks: nil as [DocumentChunk]?,
            containerId: embeddingContext.containerId
        )

        if results.isEmpty {
            return "No content found about '\(topic)' in the document library."
        }

        // Filter by specific documents if provided
        let filteredResults: [RetrievedChunk]
        if let names = documentNames, !names.isEmpty {
            let lowercaseNames = Set(names.map { $0.lowercased() })
            filteredResults = await results.asyncFilter { result in
                let docName = await self.documentName(for: result.chunk.documentId)
                return lowercaseNames.contains(docName.lowercased())
            }
        } else {
            filteredResults = results
        }

        if filteredResults.isEmpty {
            return "Specified documents don't contain content about '\(topic)'."
        }

        // Group by document
        var docContent: [String: [String]] = [:]

        for result in filteredResults.prefix(15) {
            let docName = await documentName(for: result.chunk.documentId)
            let content = result.chunk.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            // Strict snippet limit
            let snippet = content.count > maxSnippetChars ? String(content.prefix(maxSnippetChars)) + "..." : content

            if (docContent[docName]?.count ?? 0) < maxSnippetsPerDoc {
                docContent[docName, default: []].append(snippet)
            }
        }

        // Build result with char budget tracking
        var result = "**Compare '\(topic)':**\n"
        var currentChars = result.count

        for (docName, snippets) in docContent.sorted(by: { $0.key < $1.key }).prefix(maxDocsToCompare) {
            let truncatedName = docName.count > 30 ? String(docName.prefix(27)) + "..." : docName
            let header = "**\(truncatedName):** "

            if currentChars + header.count > maxTotalChars { break }
            result += header
            currentChars += header.count

            for snippet in snippets.prefix(maxSnippetsPerDoc) {
                let quotedSnippet = "\"\(snippet)\" "
                if currentChars + quotedSnippet.count > maxTotalChars { break }
                result += quotedSnippet
                currentChars += quotedSnippet.count
            }
            result += "\n"
        }

        Log.info("🔧 [Tool Call] Compared '\(topic)' across \(docContent.count) documents (\(result.count) chars)")
        return result
    }

    private func formatByteCount(_ chars: Int) -> String {
        if chars < 1000 {
            return "\(chars) chars"
        } else if chars < 1_000_000 {
            return String(format: "%.1fK chars", Float(chars) / 1000)
        } else {
            return String(format: "%.1fM chars", Float(chars) / 1_000_000)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
