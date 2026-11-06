//
//  AgenticOrchestrator+MultiChain.swift
//  OpenIntelligence
//
//  Part of AgenticOrchestrator, moved unchanged from AgenticOrchestrator.swift on 2026-11-05 (5.8 split).
//

import Foundation
import os

extension AgenticOrchestrator {
    // MARK: - Multi-Chain Execution (kept for compatibility)

    /// Execute parallel reasoning chains across document clusters
    ///
    /// ## Architecture
    /// Instead of cramming everything into one 4096-token context, we:
    /// 1. Cluster documents by topic similarity
    /// 2. Run parallel reasoning chains per cluster (each gets full 4096 tokens)
    /// 3. Synthesize all cluster insights into final answer
    ///
    /// For 17 documents: 4 clusters × 8 sessions × 4096 = 130K+ effective tokens
    /// With 3-way parallelism, completes in ~4 minutes vs 15+ for sequential
    func executeMultiChainReasoning(
        query: String,
        allChunks: [RetrievedChunk],
        config: MultiChainConfig = .maximum,
        onStep: ((ThinkingStep) async -> Void)? = nil
    ) async throws -> MultiChainResult {
        guard ragService != nil else {
            throw AgenticError.serviceUnavailable
        }

        let startTime = Date()
        var totalTokens = 0
        var clusterInsights: [MultiChainResult.ClusterInsight] = []

        // Track progressive confidence for UI - use atomic counter for thread safety
        let completedSessions = OSAllocatedUnfairLock(initialState: 0)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 1: Cluster documents by source
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        let rawDocumentClusters = clusterChunksByDocument(
            chunks: allChunks,
            maxClusters: config.maxClusters,
            minDocsPerCluster: config.minDocsPerCluster
        )

        // Clamp to a hard limit of 8 clusters
        let documentClusters = Array(rawDocumentClusters.prefix(8))

        // Clamp total sessions to 30 max, adjusting sessions per cluster if necessary
        let maxAllowedSessions = 30
        let sessionsPerCluster = max(
            1, min(config.sessionsPerCluster, maxAllowedSessions / max(1, documentClusters.count)))
        let totalExpectedSessions = documentClusters.count * sessionsPerCluster

        Log.info(
            "[MultiChain] Created \(documentClusters.count) document clusters from \(allChunks.count) chunks (clamped to 8 clusters, \(sessionsPerCluster) sessions/cluster, max 30 total)",
            category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 2: Run parallel reasoning chains per cluster
        // Use TaskGroup for controlled parallelism
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        // Process clusters in batches to avoid thermal throttling
        let batchSize = config.maxParallelChains

        for batchStart in stride(from: 0, to: documentClusters.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, documentClusters.count)
            let batch = Array(documentClusters[batchStart..<batchEnd])

            Log.info(
                "[MultiChain] Processing batch \(batchStart / batchSize + 1): clusters \(batchStart + 1)-\(batchEnd)",
                category: .llm)

            // Run this batch in parallel
            let batchResults = await withTaskGroup(of: (Int, MultiChainResult.ClusterInsight?).self) { group in
                for (localIdx, cluster) in batch.enumerated() {
                    let globalIdx = batchStart + localIdx
                    group.addTask {
                        do {
                            let insight = try await self.executeClusterChain(
                                query: query,
                                clusterName: cluster.name,
                                chunks: cluster.chunks,
                                clusterIndex: globalIdx,
                                sessionsPerCluster: sessionsPerCluster,
                                onStep: { step in
                                    // Increment session counter and recalculate confidence
                                    let currentSession = completedSessions.withLock { count -> Int in
                                        count += 1
                                        return count
                                    }

                                    // Calculate confidence based on total session progress (up to 85%)
                                    // Synthesis adds the final 15%
                                    let sessionProgress = Float(currentSession) / Float(totalExpectedSessions)
                                    let calculatedConfidence = min(0.85, 0.05 + sessionProgress * 0.80)

                                    // Create step with recalculated confidence
                                    let progressStep = ThinkingStep(
                                        id: step.id,
                                        type: step.type,
                                        input: step.input,
                                        output: step.output,
                                        tokensUsed: step.tokensUsed,
                                        duration: step.duration,
                                        timestamp: step.timestamp,
                                        confidence: calculatedConfidence
                                    )
                                    await onStep?(progressStep)
                                }
                            )
                            return (globalIdx, insight)
                        } catch {
                            Log.error("[MultiChain] Cluster \(globalIdx) failed: \(error)", category: .llm)
                            return (globalIdx, nil)
                        }
                    }
                }

                var results: [(Int, MultiChainResult.ClusterInsight?)] = []
                for await result in group {
                    results.append(result)
                }
                return results.sorted { $0.0 < $1.0 }
            }

            // Collect successful results and update progressive confidence
            // Collect successful cluster results (confidence already reported per-session)
            for (_, insight) in batchResults {
                if let insight = insight {
                    clusterInsights.append(insight)
                    totalTokens += insight.tokensUsed
                }
            }
        }

        Log.info(
            "[MultiChain] Completed \(clusterInsights.count) cluster chains, \(totalTokens) tokens", category: .llm)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // STEP 3: Final synthesis across all cluster insights
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

        let synthesisStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Cross-cluster synthesis",
            output: "Integrating findings from \(clusterInsights.count) research clusters...",
            tokensUsed: 0,
            duration: 0.1,
            timestamp: Date(),
            confidence: 0.88  // All sessions done, now synthesizing
        )
        await onStep?(synthesisStep)

        let finalAnswer = try await synthesizeClusterInsights(
            query: query,
            clusterInsights: clusterInsights,
            synthesisSessions: config.synthesisSessions,
            sourceChunks: allChunks
        )

        totalTokens += finalAnswer.tokensUsed

        let totalDuration = Date().timeIntervalSince(startTime)
        let totalSessions = clusterInsights.reduce(0) { $0 + $1.sessionsRun } + config.synthesisSessions

        // Emit final completion step with 95% confidence
        let completionStep = ThinkingStep(
            id: UUID(),
            type: .synthesizing,
            input: "Multi-chain complete",
            output: "Synthesized \(clusterInsights.count) cluster analyses into comprehensive answer",
            tokensUsed: finalAnswer.tokensUsed,
            duration: totalDuration,
            timestamp: Date(),
            confidence: 0.95
        )
        await onStep?(completionStep)

        Log.info(
            "[MultiChain] COMPLETE: \(totalSessions) sessions, \(totalTokens) tokens, \(String(format: "%.1f", totalDuration))s",
            category: .llm)

        return MultiChainResult(
            finalAnswer: finalAnswer.text,
            clusterInsights: clusterInsights,
            totalTokens: totalTokens,
            totalSessions: totalSessions,
            totalDuration: totalDuration,
            confidence: 0.95  // Multi-chain is inherently high confidence
        )
    }

    /// Cluster chunks by source document for parallel processing
    private func clusterChunksByDocument(
        chunks: [RetrievedChunk],
        maxClusters: Int,
        minDocsPerCluster: Int
    ) -> [DocumentCluster] {
        // Group chunks by source document
        var docToChunks: [String: [RetrievedChunk]] = [:]
        for chunk in chunks {
            let docName = chunk.sourceDocument
            docToChunks[docName, default: []].append(chunk)
        }

        let profiles = docToChunks.map { documentName, chunks in
            buildSemanticProfile(documentName: documentName, chunks: chunks)
        }.sorted { lhs, rhs in
            lhs.totalScore > rhs.totalScore
        }

        guard !profiles.isEmpty else { return [] }

        let numClusters = min(
            maxClusters, max(1, Int(ceil(Double(profiles.count) / Double(max(1, minDocsPerCluster))))))
        var clusterProfiles: [[DocumentSemanticProfile]] = Array(repeating: [], count: numClusters)
        var clusterTerms: [[String: Int]] = Array(repeating: [:], count: numClusters)

        for (index, profile) in profiles.prefix(numClusters).enumerated() {
            clusterProfiles[index].append(profile)
            clusterTerms[index] = profile.weightedTerms
        }

        for profile in profiles.dropFirst(numClusters) {
            var bestIndex = 0
            var bestScore = -Float.infinity

            for index in 0..<numClusters {
                let score = semanticClusterScore(
                    profile: profile,
                    clusterTerms: clusterTerms[index],
                    clusterSize: clusterProfiles[index].count
                )
                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            clusterProfiles[bestIndex].append(profile)
            clusterTerms[bestIndex] = mergedTermWeights(clusterTerms[bestIndex], with: profile.weightedTerms)
        }

        return clusterProfiles.enumerated().compactMap { index, profilesInCluster in
            guard !profilesInCluster.isEmpty else { return nil }
            let clusterChunks =
                profilesInCluster
                .flatMap(\.chunks)
                .sorted { $0.similarityScore > $1.similarityScore }

            return DocumentCluster(
                name: semanticClusterName(index: index, terms: clusterTerms[index]),
                documents: profilesInCluster.map(\.documentName),
                chunks: clusterChunks
            )
        }
    }

    private func buildSemanticProfile(
        documentName: String,
        chunks: [RetrievedChunk]
    ) -> DocumentSemanticProfile {
        var weightedTerms: [String: Int] = [:]

        for term in semanticTerms(from: documentName, minimumLength: 3, limit: 6) {
            weightedTerms[term, default: 0] += 2
        }

        for chunk in chunks {
            for term in chunk.chunk.metadata.keywords.map({ $0.lowercased() }) where term.count > 2 {
                weightedTerms[term, default: 0] += 3
            }
            for term in chunk.chunk.metadata.entities.map({ $0.lowercased() }) where term.count > 2 {
                weightedTerms[term, default: 0] += 3
            }
            if let sectionTitle = chunk.chunk.metadata.sectionTitle {
                for term in semanticTerms(from: sectionTitle, minimumLength: 3, limit: 5) {
                    weightedTerms[term, default: 0] += 2
                }
            }
            if let sectionPath = chunk.chunk.metadata.sectionPath {
                for term in sectionPath.flatMap({ semanticTerms(from: $0, minimumLength: 3, limit: 4) }) {
                    weightedTerms[term, default: 0] += 2
                }
            }
            if let structureType = chunk.chunk.metadata.structureType?.lowercased(), structureType.count > 2 {
                weightedTerms[structureType, default: 0] += 2
            }

            let content = chunk.chunk.contextText
            for term in semanticTerms(from: content, minimumLength: 4, limit: 18) {
                weightedTerms[term, default: 0] += 1
            }
        }

        let totalScore = chunks.reduce(0) { $0 + $1.similarityScore }

        return DocumentSemanticProfile(
            documentName: documentName,
            chunks: chunks,
            totalScore: totalScore,
            weightedTerms: weightedTerms
        )
    }

    private func semanticTerms(
        from text: String,
        minimumLength: Int,
        limit: Int
    ) -> [String] {
        Array(
            Set(
                text.lowercased()
                    .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
                    .split(separator: " ")
                    .map(String.init)
                    .filter { $0.count >= minimumLength && !Self.commonStopWords.contains($0) }
            )
            .prefix(limit)
        )
    }

    private func semanticClusterScore(
        profile: DocumentSemanticProfile,
        clusterTerms: [String: Int],
        clusterSize: Int
    ) -> Float {
        guard !clusterTerms.isEmpty else { return profile.totalScore }

        let sharedTerms = Set(profile.weightedTerms.keys).intersection(clusterTerms.keys)
        let overlapWeight = sharedTerms.reduce(0) { partial, term in
            partial + min(profile.weightedTerms[term] ?? 0, clusterTerms[term] ?? 0)
        }

        let unionTerms = Set(profile.weightedTerms.keys).union(clusterTerms.keys)
        let unionWeight = unionTerms.reduce(0) { partial, term in
            partial + max(profile.weightedTerms[term] ?? 0, clusterTerms[term] ?? 0)
        }

        let semanticSimilarity = unionWeight == 0 ? 0 : Float(overlapWeight) / Float(unionWeight)
        let relevanceBonus = min(profile.totalScore / 10.0, 0.25)
        let sizePenalty = Float(max(0, clusterSize - 1)) * 0.03
        return semanticSimilarity + relevanceBonus - sizePenalty
    }

    private func mergedTermWeights(
        _ lhs: [String: Int],
        with rhs: [String: Int]
    ) -> [String: Int] {
        rhs.reduce(into: lhs) { partial, entry in
            partial[entry.key, default: 0] += entry.value
        }
    }

    private func semanticClusterName(index: Int, terms: [String: Int]) -> String {
        let topTerms =
            terms
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    return lhs.key < rhs.key
                }
                return lhs.value > rhs.value
            }
            .map(\.key)
            .prefix(2)

        guard !topTerms.isEmpty else {
            return "Semantic Cluster \(index + 1)"
        }

        return "Semantic Cluster \(index + 1): \(topTerms.joined(separator: " / "))"
    }

    /// Execute a reasoning chain for a single document cluster
    private func executeClusterChain(
        query: String,
        clusterName: String,
        chunks: [RetrievedChunk],
        clusterIndex: Int,
        sessionsPerCluster: Int,
        onStep: ((ThinkingStep) async -> Void)?
    ) async throws -> MultiChainResult.ClusterInsight {
        guard ragService != nil else {
            throw AgenticError.serviceUnavailable
        }

        Log.info(
            "[MultiChain] Cluster \(clusterIndex + 1) (\(clusterName)): \(chunks.count) chunks, \(sessionsPerCluster) sessions",
            category: .llm)

        // Use the per-cluster chain config
        let clusterConfig = ReasoningChainConfig(
            sessionCount: sessionsPerCluster,
            maxContextPerSession: 3200,
            maxInsightLength: 2000
        )

        // Run the reasoning chain for this cluster - force confidence reporting for Maximum mode
        let chainResult = try await executeReasoningChain(
            query: query,
            chunks: chunks,
            config: clusterConfig,
            onStep: { step in
                // Tag steps with cluster info
                let taggedStep = ThinkingStep(
                    id: step.id,
                    type: step.type,
                    input: "[\(clusterName)] \(step.input)",
                    output: step.output,
                    tokensUsed: step.tokensUsed,
                    duration: step.duration,
                    timestamp: step.timestamp,
                    confidence: step.confidence
                )
                await onStep?(taggedStep)
            },
            forceConfidenceReporting: true  // Multi-chain = Maximum mode, always report confidence
        )

        let docNames = Array(Set(chunks.map { $0.sourceDocument }))

        // Clean up the cluster insight before storing
        let cleanedInsight = cleanupFinalAnswer(chainResult.finalAnswer)

        return MultiChainResult.ClusterInsight(
            clusterName: clusterName,
            documents: docNames,
            insight: cleanedInsight,
            chainInsights: chainResult.chainInsights.map { cleanupFinalAnswer($0, isFinalAnswer: false) },
            tokensUsed: chainResult.totalTokens,
            sessionsRun: chainResult.sessionCount
        )
    }

    /// Synthesize insights from all clusters into final answer
    private func synthesizeClusterInsights(
        query: String,
        clusterInsights: [MultiChainResult.ClusterInsight],
        synthesisSessions: Int,
        /// The retrieved pool, for post-retrieval planning. Without it the planner
        /// judges this synthesis to have zero evidence and abstains, regardless of
        /// how much the clusters actually found.
        sourceChunks: [RetrievedChunk]
    ) async throws -> (text: String, tokensUsed: Int) {
        guard let ragService = ragService else {
            throw AgenticError.serviceUnavailable
        }

        // Build synthesis prompt with all cluster insights
        var synthesisInput = "RESEARCH QUESTION: \(query)\n\n"
        synthesisInput += "FINDINGS FROM \(clusterInsights.count) RESEARCH CLUSTERS:\n\n"

        for (idx, cluster) in clusterInsights.enumerated() {
            synthesisInput += "━━━ CLUSTER \(idx + 1): \(cluster.clusterName) ━━━\n"
            synthesisInput += "Documents: \(cluster.documents.joined(separator: ", "))\n"
            synthesisInput += "Key Findings:\n\(cluster.insight)\n\n"
        }

        // Truncate if needed to fit in context (leave room for enhanced prompt + output)
        // Enhanced system prompt is ~640 tokens, synthesis prompt header ~200 tokens
        // Output reserve: 1500 tokens, safety: 100 tokens
        // Available for content: 4096 - 640 - 200 - 1500 - 100 = 1656 tokens ≈ 2300 chars
        // But Maximum mode chains multiple sessions, so first session can be tighter
        let maxChars = 4500  // ~3200 tokens - first session uses more, refinements use less
        if synthesisInput.count > maxChars {
            synthesisInput = String(synthesisInput.prefix(maxChars)) + "\n[...truncated for synthesis]"
        }

        let synthesisPrompt = """
            \(synthesisInput)

            TASK: Synthesize ALL findings into ONE comprehensive answer.
            Integrate across clusters. Include specific values and data. Use **bold** sparingly for key terms only.
            Never repeat content. Keep each finding's [S#] labels exactly as written; never invent or renumber one.

            SYNTHESIS:
            """

        let systemPrompt = """
            Synthesize document findings. Include ALL specific values, numbers, and data points.
            Cross-reference multiple sources. Never repeat content. Use **bold** sparingly for key terms only.
            Keep the findings' [S#] labels exactly as written. Write like a domain expert — format naturally for the content.
            """

        var totalTokens = 0
        var finalAnswer = ""

        // Run synthesis sessions - each session REFINES the previous, not concatenates
        for sessionIdx in 0..<synthesisSessions {
            let isLast = sessionIdx == synthesisSessions - 1
            let prompt =
                sessionIdx == 0
                ? synthesisPrompt
                : """
                Your previous synthesis attempt:
                \(String(finalAnswer.prefix(3000)))

                IMPROVE THIS SYNTHESIS by:
                - Removing redundant/repeated content
                - Improving paragraph flow and transitions
                - Adding any missing details from the original findings
                - Making it more coherent and readable

                Produce a CLEAN, REFINED version (not additions - a complete rewrite):
                """

            let response = try await ragService.generateWithProperConsent(
                prompt: prompt,
                context: "",
                systemPrompt: systemPrompt,
                maxTokens: isLast ? 1500 : 1000,
                disableTools: true,
                sourceChunks: sourceChunks
            )

            // Each session REPLACES the previous answer (refinement, not concatenation)
            finalAnswer = response.text
            totalTokens += response.tokensGenerated
        }

        // Final cleanup - remove any remaining raw markers
        finalAnswer = cleanupFinalAnswer(finalAnswer)

        return (finalAnswer.trimmingCharacters(in: .whitespacesAndNewlines), totalTokens)
    }

    /// Gather ALL relevant chunks from the library for comprehensive multi-chain analysis
    /// This retrieves more chunks than the initial search to enable thorough cluster analysis
    func gatherAllRelevantChunks(
        query: String,
        initialChunks: [RetrievedChunk],
        ragService: RAGService,
        onDetailedEvent: (@Sendable (ThinkingEvent.Kind, String, String) async -> Void)? = nil
    ) async throws -> [RetrievedChunk] {
        Log.info("[MultiChain] Gathering comprehensive chunks for multi-chain analysis", category: .retrieval)

        await onDetailedEvent?(.agentic, "Maximum mode", "Gathering comprehensive evidence")

        // Start with initial chunks
        var allChunks = initialChunks

        // Get broader retrieval - up to 50 chunks for comprehensive coverage
        await onDetailedEvent?(.retrieval, "Broad search", "Expanding to 50 top chunks")
        let broadChunks = try await ragService.executeFullRetrievalPipeline(
            query: query,
            topK: 50,
            minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .coverageExpansion),
            qualityMode: qualityMode,
            onDetailedEvent: onDetailedEvent
        )

        // Merge unique chunks
        for chunk in broadChunks {
            if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                allChunks.append(chunk)
            }
        }

        await onDetailedEvent?(.retrieval, "After broad search", "\(allChunks.count) unique chunks")

        // Also try some query variations to catch different aspects
        let queryVariations = generateQueryVariations(query: query)
        for (idx, variation) in queryVariations.prefix(3).enumerated() {  // Limit to 3 variations
            await onDetailedEvent?(.retrieval, "Variation \(idx + 1)/3", "\"\(variation.prefix(30))...\"")
            let variantChunks = try await ragService.executeFullRetrievalPipeline(
                query: variation,
                topK: 20,
                minSimilarity: RetrievalPolicyService.agenticMinSimilarity(for: qualityMode, stage: .queryVariation),
                qualityMode: qualityMode,
                onDetailedEvent: onDetailedEvent
            )
            for chunk in variantChunks {
                if !allChunks.contains(where: { $0.chunk.id == chunk.chunk.id }) {
                    allChunks.append(chunk)
                }
            }
        }

        await onDetailedEvent?(.retrieval, "Gathering complete", "\(allChunks.count) chunks for analysis")

        Log.info(
            "[MultiChain] Gathered \(allChunks.count) total chunks for multi-chain processing", category: .retrieval)
        return allChunks
    }

    /// Generate query variations to improve retrieval coverage
    private func generateQueryVariations(query: String) -> [String] {
        var variations: [String] = []

        // Extract key terms for variation
        let words = query.lowercased().split(separator: " ").map(String.init)
        let stopWords = Set(["what", "are", "the", "all", "of", "in", "is", "a", "an", "for", "to", "and", "or"])
        let keyTerms = words.filter { !stopWords.contains($0) && $0.count > 3 }

        // Create focused variations
        if keyTerms.count >= 2 {
            variations.append(keyTerms.prefix(3).joined(separator: " "))
            variations.append(keyTerms.suffix(3).joined(separator: " "))
        }

        // Add common research-oriented variations
        let researchPrefixes = ["findings about", "research on", "evidence for", "studies of"]
        if let mainTopic = keyTerms.first {
            for prefix in researchPrefixes.prefix(2) {
                variations.append("\(prefix) \(mainTopic)")
            }
        }

        return variations
    }

    /// Generate EXPANSION queries based on what FactBank has learned
    /// Uses unanswered sub-questions for GAP-AWARE retrieval
    /// This enables truly unlimited retrieval - we discover new search directions
    func generateExpansionQueries(
        originalQuery: String,
        factBank: FactBank
    ) -> [String] {
        var queries: [String] = []

        // PRIORITY 1: Use unanswered sub-questions directly
        // These are the GAPS we haven't filled yet
        for unanswered in factBank.unansweredQuestions.prefix(3) {
            // Combine original query topic with the gap
            let queryCore = originalQuery.split(separator: " ").suffix(4).joined(separator: " ")
            queries.append("\(queryCore) \(unanswered)")
        }

        // PRIORITY 2: Extract new entities from accumulated facts
        let factText = factBank.coreFacts.joined(separator: " ")
        let words = factText.lowercased().split(separator: " ").map(String.init)
        let factWords = Set(words.filter { $0.count > 4 })

        // Find NEW terms that appeared in facts but not original query
        let originalTerms = Set(originalQuery.lowercased().split(separator: " ").map(String.init))
        let newTerms = factWords.subtracting(originalTerms)
            .filter { term in
                !["about", "which", "these", "there", "their", "would", "could", "should", "found", "showed"].contains(
                    term)
            }

        // Build expansion queries from new terms (only if we have room)
        if queries.count < 4 {
            let topNewTerms = Array(newTerms.prefix(3))
            let originalCore = originalQuery.split(separator: " ").prefix(4).joined(separator: " ")
            for term in topNewTerms.prefix(4 - queries.count) {
                queries.append("\(originalCore) \(term)")
            }
        }

        // PRIORITY 3: Gap-filling queries for research completeness
        if queries.count < 5 {
            let gapPatterns = [
                "limitations of",
                "conflicting evidence",
                "alternative view",
            ]
            let queryCore = originalQuery.split(separator: " ").suffix(3).joined(separator: " ")
            for pattern in gapPatterns.prefix(5 - queries.count) {
                queries.append("\(pattern) \(queryCore)")
            }
        }

        Log.info(
            "[Expansion] Generated \(queries.count) queries: \(factBank.unansweredQuestions.count) gaps + new terms",
            category: .llm)
        return queries
    }

    /// Build prompt for a specific position in the reasoning chain.
    /// CRITICAL: The prompt INCLUDES the context (DOCUMENTS section).
    /// Do NOT pass context separately to generateWithProperConsent — that would double it.
    ///
    /// Token budget (4096 total):
    ///   System prompt: ~80 tokens
    ///   LLMService wrapper: ~30 tokens
    ///   Output (maxTokens): 500 tokens
    ///   Available for prompt: ~3486 tokens ≈ 4880 chars
    ///   Session 1 (no insights): context ≤ 4000 chars, prompt text ~300 chars
    ///   Session 2+ (with insights): context ≤ 2000 chars + insights ≤ 1500 chars + prompt ~300 chars

    /// One compact line naming what the chain still has not answered.
    ///
    /// Carried into each session prompt beside PRIOR FINDINGS. The prose summary says what was
    /// found and costs up to 1200 characters of a 3500 character budget; this says what is still
    /// missing and costs about eighty. It is the difference between telling a session what has been
    /// read and telling it what to go and look for.
    ///
    /// Returns nil when the decomposition produced nothing or everything is answered, so no budget
    /// is spent saying "nothing outstanding".
    func evidenceStateLine(_ factBank: FactBank) -> String? {
        let total = factBank.subQuestions.count
        guard total > 0 else { return nil }
        let open = factBank.unansweredQuestions
        guard !open.isEmpty else { return nil }
        let answered = total - open.count
        let listed = open.prefix(3).joined(separator: "; ")
        return "STILL UNANSWERED (\(answered)/\(total) covered): \(listed)"
    }

    func buildChainPrompt(
        sessionIndex: Int,
        sessionCount: Int,
        query: String,
        context: String,
        previousInsights: [String],
        maxInsightLength: Int,
        sessionObjective: String? = nil,
        evidenceState: String? = nil,
        wholeChunkContext: Bool = false
    ) -> (prompt: String, systemPrompt: String) {
        // FIXED: Reduced insight budget from 2500 to 1200 chars.
        // With context doubling fix, real budget is:
        //   4096 tokens - 80 (system) - 30 (wrapper) - 500 (output) = 3486 tokens ≈ 4880 chars
        //   Session 1: 4000 chars context + 300 prompt = 4300 (fits)
        //   Session 2+: 2200 context + 1200 insights + 300 prompt = 3700 (fits)
        let maxInsightSummaryChars = 1200

        let insightSummary: String
        if previousInsights.isEmpty {
            insightSummary = ""
        } else {
            // For sessions with insights, provide a CONCISE summary of findings so far.
            // Don't dump the full text — just the key answer and supporting details.
            let rawSummary =
                "PRIOR FINDINGS:\n"
                + previousInsights.enumerated()
                .map { "[\($0.offset + 1)] \(truncateAtSentenceBoundary($0.element, limit: 400))" }
                .joined(separator: "\n")

            if rawSummary.count > maxInsightSummaryChars {
                insightSummary = truncateAtSentenceBoundary(rawSummary, limit: maxInsightSummaryChars)
                Log.debug(
                    "[ReasoningChain] Truncated insight summary from \(rawSummary.count) to \(maxInsightSummaryChars) chars",
                    category: .llm)
            } else {
                insightSummary = rawSummary
            }
        }

        // A structured statement of what is still open, carried alongside the prose.
        //
        // PRIOR FINDINGS is free text and it degrades: device captures show it decaying into
        // "[S1] contains a section titled" and, twice, into the session's own system prompt. It
        // also costs up to 1200 of a 3500 character budget. The FactBank already knows precisely
        // which sub-questions remain unanswered, and saying so costs about eighty characters and
        // cannot rot into filler. It tells the session what to hunt rather than what was found.
        let evidenceStateBlock = evidenceState.map { "\($0)\n" } ?? ""

        let objectiveBlock =
            sessionObjective.map {
                """
                SESSION OBJECTIVE:
                \($0)

                """
            } ?? ""

        // Context budget: session 1 gets full context, later sessions share with insights.
        // A whole-chunk context was sized in tokens against the live window before it got here
        // (`SessionEvidencePlan`), so it is not cut again by characters.
        let contextForPrompt =
            wholeChunkContext
            ? context
            : (previousInsights.isEmpty ? String(context.prefix(4000)) : String(context.prefix(2200)))

        switch sessionIndex {
        case 0:
            // SESSION 1: Extract ALL relevant information from documents
            // CRITICAL: Don't say "find THE answer" — questions can have multiple parts.
            // "What does pressing the button do?" might have 5+ answers (record, stop, connect, reset, etc.)
            let systemPrompt =
                "You are a document analysis assistant. Extract all relevant information from the provided documents in clear, detailed prose. Write in complete sentences and natural paragraphs."
            let prompt = """
                QUESTION: \(query)

                \(objectiveBlock)DOCUMENTS:
                \(contextForPrompt)

                Write a detailed answer using the information found in these documents.
                Include every relevant detail, value, specification, and procedure.
                Write in complete sentences and natural paragraphs — not just bullet points.
                Use bullet points only for actual lists of items (like steps or specifications).
                Cite each fact with the [S#] label of the passage it came from, written exactly as it is labeled above.
                """
            return (prompt, systemPrompt)

        case 1:
            // SESSION 2: Add NEW details not yet covered
            let systemPrompt =
                "You are a document analyst. Write ONLY new details from these documents. Never restate prior findings."
            let prompt = """
                QUESTION: \(query)

                \(evidenceStateBlock)\(insightSummary)
                \(objectiveBlock)ADDITIONAL DOCUMENTS:
                \(contextForPrompt)

                Using these additional documents, write ONLY new details about: "\(query)"
                Do NOT repeat or rephrase anything from prior findings above.
                Focus exclusively on details, values, or procedures NOT already covered.
                Write in complete sentences and full paragraphs. Cite each fact with the [S#] label of the passage it came from, written exactly as it is labeled above.
                """
            return (prompt, systemPrompt)

        case sessionCount - 1:
            // FINAL SESSION: Clean synthesis of ALL accumulated findings
            let systemPrompt =
                "Combine all research findings into one comprehensive, well-written answer. Write in detailed prose with complete sentences and natural paragraphs. Use ### headers to organize sections. Use **bold** sparingly for key terms only."
            let prompt = """
                QUESTION: \(query)

                \(evidenceStateBlock)\(insightSummary)
                \(objectiveBlock)DOCUMENTS:
                \(contextForPrompt)

                Write a comprehensive answer to: "\(query)"
                Combine ALL findings into detailed, flowing prose.
                Use ### section headers to organize topics. Use **bold** sparingly for key terms only.
                Write in complete sentences and full paragraphs — not just bullet lists.
                Use bullet points only for actual sequential steps or specification lists.
                Include every relevant detail found. Cite each fact with the [S#] label of the passage it came from, written exactly as it is labeled above.
                """
            return (prompt, systemPrompt)

        default:
            // MIDDLE SESSIONS: Enrich and expand on prior findings with new document evidence
            // CRITICAL: Frame as ENRICHMENT, not just "find new stuff".
            // Apple FM tends to give up and say "No new information" when asked only for novelty.
            // Instead, ask it to ADD DEPTH and DETAIL using the new documents as evidence.
            // But also explicitly tell it NOT to repeat prior findings verbatim to avoid dedup waste.
            // Phrasing note: an earlier version asked for "NEW details", and the
            // on-device model answered with `{ "document_analysis": { "new_details":
            // [ ... ` — inventing a schema whose key mirrored the instruction. The
            // wording below avoids naming a field, and the output format is stated
            // outright rather than implied.
            let systemPrompt =
                "You are a document analyst. Describe what these documents add beyond the prior findings. Do not repeat what was already found. Reply with plain prose only — never JSON, key-value pairs, or tool-call syntax."
            let prompt = """
                QUESTION: \(query)

                \(evidenceStateBlock)\(insightSummary)
                \(objectiveBlock)ADDITIONAL DOCUMENTS:
                \(contextForPrompt)

                Using these additional documents, describe what they add about: "\(query)"
                Write details, values, procedures, or context from these documents that are NOT already in prior findings.
                Do NOT repeat or rephrase information already covered above.
                If the documents contain relevant details not yet mentioned, describe them thoroughly.
                Write in complete sentences and full paragraphs, as plain prose.
                Do not reply with JSON, field names, or any structured format. Cite each fact with the [S#] label of the passage it came from, written exactly as it is labeled above.
                """
            return (prompt, systemPrompt)
        }
    }

    func buildSessionObjective(
        query: String,
        factBank: FactBank,
        sessionIndex: Int,
        sessionCount: Int
    ) -> String? {
        guard sessionIndex > 0 else { return nil }

        let unanswered = Array(factBank.unansweredQuestions.prefix(3))

        if sessionIndex == sessionCount - 1 {
            if unanswered.isEmpty {
                return
                    "Synthesize only what is supported by the accumulated evidence. If any detail is still weakly supported, qualify it instead of guessing."
            }

            return
                "Before final synthesis, verify whether these remaining gaps are actually answered: \(unanswered.joined(separator: "; ")). If not, state that the documents do not fully resolve them instead of inferring beyond the evidence."
        }

        if unanswered.isEmpty {
            return
                "Pressure-test the current answer. Look for contradictions, missing qualifiers, numeric details, edge cases, and source-backed caveats instead of repeating the same summary."
        }

        return
            "Prioritize coverage for these unresolved sub-questions: \(unanswered.joined(separator: "; ")). Surface contradictions or missing evidence explicitly instead of repeating prior findings."
    }

    /// Extract insight from response - keep FULL content, just clean up formatting
    /// We want ALL the details the model found, not truncated snippets!
    func extractInsight(from text: String, maxLength: Int) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Clean up common LLM artifacts and markers (including truncated versions)
        let markersToRemove = [
            "REASONING:", "ONING:", "ASONING:", "SONING:",  // Truncated REASONING
            "INSIGHT:", "NSIGHT:", "SIGHT:",  // Truncated INSIGHT
            "ANALYSIS:", "OBSERVATION:", "CONCLUSION:",
            "Re Reasoning:", "Re REASONING:",
            "[new details found]", "[additional specifics]",
        ]

        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // If there's an INSIGHT: marker, prefer that section but keep it full
        if let insightRange = result.range(of: "INSIGHT:", options: .caseInsensitive) {
            result = String(result[insightRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // If there's REASONING: → INSIGHT:, skip the reasoning part
        else if let arrowRange = result.range(of: "→") {
            let afterArrow = String(result[arrowRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove "INSIGHT:" prefix if present
            if afterArrow.lowercased().hasPrefix("insight:") {
                result = String(afterArrow.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if afterArrow.count > 100 {
                result = afterArrow
            }
        }

        // Clean up again after extraction
        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // Remove empty lines and normalize whitespace
        result = result.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        // Only truncate if REALLY necessary (way over budget)
        // maxLength is now 1500-2500, so this is a safety valve not a bottleneck
        if result.count > maxLength {
            // Try to truncate at a sentence boundary
            let truncated = String(result.prefix(maxLength))
            if let lastPeriod = truncated.lastIndex(of: ".") {
                return String(truncated[...lastPeriod])
            }
            return truncated + "..."
        }

        return result
    }

    /// Extract full final answer from synthesis session (no truncation!)
    func extractFinalAnswer(from text: String) -> String {
        let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Look for explicit answer markers (in priority order)
        let answerMarkers = [
            "YOUR COMPREHENSIVE ANSWER:",
            "YOUR ANSWER:",
            "FINAL ANSWER:",
            "Answer:",
            "ANSWER:",
        ]

        for marker in answerMarkers {
            if let answerRange = cleanedText.range(of: marker, options: .caseInsensitive) {
                return String(cleanedText[answerRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Look for content after "→" (arrow used in our formatting)
        if let arrowRange = cleanedText.range(of: "→") {
            let afterArrow = String(cleanedText[arrowRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if afterArrow.count > 50 {  // Make sure there's substantial content
                return afterArrow
            }
        }

        // Remove any "REASONING:" prefix and return the rest
        if let reasoningRange = cleanedText.range(of: "REASONING:", options: .caseInsensitive) {
            // Check if there's content before REASONING (that's the answer)
            let beforeReasoning = String(cleanedText[..<reasoningRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeReasoning.count > 50 {
                return beforeReasoning
            }
        }

        // Just return the full text - it IS the answer
        return cleanedText
    }

    /// Deduplicate a synthesized answer by removing repeated paragraphs/sections
    /// This catches cross-pass duplication that per-LLM-call dedup can't see.
    func deduplicateSynthesizedAnswer(_ text: String) -> String {
        // Split into paragraphs (sections separated by blank lines)
        let paragraphs = text.components(separatedBy: "\n\n").filter {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }
        guard paragraphs.count > 1 else { return text }

        var kept: [String] = []
        var seenFingerprints: Set<String> = []

        for paragraph in paragraphs {
            // Create a fingerprint: lowercased, stripped of formatting, first 120 chars
            let stripped =
                paragraph
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "*", with: "")
                .lowercased()
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")

            let fingerprint = String(stripped.prefix(120))

            // Check for near-duplicate: if >70% of fingerprint matches any seen
            var isDuplicate = false
            if seenFingerprints.contains(fingerprint) {
                isDuplicate = true
            } else {
                // Check fuzzy match — paragraphs that start the same way
                for seen in seenFingerprints {
                    let shorter = min(fingerprint.count, seen.count)
                    guard shorter > 40 else { continue }
                    let prefix1 = String(fingerprint.prefix(shorter))
                    let prefix2 = String(seen.prefix(shorter))
                    if prefix1 == prefix2 {
                        isDuplicate = true
                        break
                    }
                }
            }

            if !isDuplicate {
                kept.append(paragraph)
                seenFingerprints.insert(fingerprint)
            } else {
                Log.debug("[Synthesis] Removed duplicate paragraph: \(String(paragraph.prefix(80)))...", category: .llm)
            }
        }

        // Safety: if we removed more than 60%, keep the original
        if kept.count < paragraphs.count * 2 / 5 {
            Log.info(
                "[Synthesis] Dedup would remove \(paragraphs.count - kept.count)/\(paragraphs.count) paragraphs — aborting",
                category: .llm)
            return text
        }

        return kept.joined(separator: "\n\n")
    }

    /// Characters still available for the supplementary findings block.
    ///
    /// Budgeted against the **on-device** window even when synthesis may escalate to
    /// PCC. Under-using a 32K window costs nothing; over-filling a 4096 one costs the
    /// entire answer, and an On-Device selection makes the small window mandatory.
    /// Output tokens reserved for the final synthesis, and passed as `maxTokens`.
    ///
    /// Was 1500, which starved the input it was protecting. A device run reserved
    /// 1500 and the model used ~362, while the reservation squeezed the supplementary
    /// findings from 1554 characters down to 166 — 32 sessions' worth of insight
    /// compressed into two sentences. The answer showed it: Dopamine, Glutamate and
    /// GABA were written out fully and Serotonin got "Document [S2] mentions
    /// serotonin." before stopping, because there was nothing left to write from.
    ///
    /// 1000 tokens is ~1400 characters, comfortably above every answer observed
    /// (507, 599, 793), and returns ~700 characters to the evidence.
    static let synthesisOutputTokenReserve = 1000

    func supplementaryCharBudget(factContextChars: Int, queryChars: Int) -> Int {
        let window = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let outputReserveTokens = Self.synthesisOutputTokenReserve
        let serviceOverheadTokens = 200  // system prompt + LLMService wrapper
        let instructionChars = 900  // the fixed instruction text below the findings

        let inputTokens = max(0, window - outputReserveTokens - serviceOverheadTokens)
        let inputChars = Int(Double(inputTokens) * Double(FoundationModelTokenBudget.onDeviceCharsPerToken))
        return max(0, inputChars - factContextChars - queryChars - instructionChars)
    }

    /// True when a session produced text that cannot serve as a reasoning insight.
    ///
    /// Shared by both reasoning loops on purpose. This check previously existed only
    /// in `executeReasoningChain`, so Maximum's loop — which tested nothing beyond
    /// `tokensGenerated == 0` — happily stored non-answers as findings.
    ///
    /// The request-for-input cases are the ones worth naming. A device run recorded
    /// sessions 16 and 17 as *"I need additional context to determine what specific
    /// controls or mechanisms are mentioned... Please provide"* and *"Could you
    /// please"*. There is no human in this loop to answer. The model has slipped into
    /// conversational mode, and its question then enters the fact bank as a finding.
    func isUnusableInsight(_ insight: String) -> Bool {
        let text = insight.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.count < 30 { return true }

        // Nothing learned.
        let nonAnswers = [
            "no new information", "no new details", "no additional information",
            "i can't assist", "i cannot assist", "no relevant information",
        ]
        // Addressed to a user who is not there.
        let requestsForInput = [
            "please provide", "could you please", "can you provide",
            "i need additional context", "additional context is needed",
            "please share", "please specify", "let me know if",
        ]
        if nonAnswers.contains(where: { text.contains($0) }) { return true }
        if requestsForInput.contains(where: { text.contains($0) }) { return true }
        if text.hasPrefix("i'm sorry") || text.hasPrefix("i am sorry") { return true }
        return false
    }

    /// Truncate at the last sentence boundary at or before `limit`.
    ///
    /// A raw `String.prefix(limit)` cuts mid-sentence. In the reasoning chain that
    /// is not cosmetic: `buildChainPrompt` places PRIOR FINDINGS in the middle of
    /// the prompt, so a mid-sentence cut hands the model a prompt that stops in the
    /// middle of a thought and then resumes with `SESSION OBJECTIVE:`. Sessions 6-8
    /// of a real Deep Think run responded by completing the *prompt* rather than
    /// answering it, echoing those section headers back as their insight.
    func truncateAtSentenceBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 0 else { return text }
        let head = String(text.prefix(limit))
        // Prefer a sentence end; fall back to a line break, then a word break, so a
        // findings block never ends mid-word.
        let terminators: [Character] = [".", "!", "?"]
        if let idx = head.lastIndex(where: { terminators.contains($0) }) {
            return String(head[...idx])
        }
        if let idx = head.lastIndex(of: "\n") {
            return String(head[..<idx])
        }
        if let idx = head.lastIndex(of: " ") {
            return String(head[..<idx])
        }
        return head
    }

    /// Strip prompt scaffolding and fabricated structured output out of a session insight.
    ///
    /// Across three device runs the on-device model repeatedly wrapped otherwise good
    /// analysis in a JSON envelope it never closed:
    ///
    ///     tool_call: {tool_name: "extract_new_details", arguments: {...}}
    ///     { "tool_call_status": "completed", "new_details_found": [ ...
    ///     { "document_analysis": { "new_details": [ "The two-tier context window ...
    ///
    /// No such tool or schema exists in this codebase, and tools are explicitly
    /// disabled for chain sessions (`disableToolsForSession = true`). The invented
    /// key names track the prompt's own wording — "add NEW details" produced
    /// `new_details` — so the phrasing was priming a structured response. The prompts
    /// now ask for prose explicitly; this is the safety net for when that is ignored.
    ///
    /// The prose inside those envelopes was on-topic and correctly cited every time,
    /// so salvage it rather than throwing away the session's work. Left unsanitized
    /// it also cascades: a contaminated insight becomes the next session's PRIOR
    /// FINDINGS and teaches the next model the same shape.
    func stripPromptEchoAndToolNoise(from text: String, systemPrompt: String? = nil) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var strippedEnvelope = false

        // 0a. Drop a leading echo of this session's own instructions.
        //
        // Device evidence, 2026-08-13: two Deep Think sessions recorded
        //   "You are a document analyst. Describe what these documents add about:"
        // as their insight. That is the session's own role instruction, not a finding. It
        // survived every rule below because those hunt JSON, tool calls and markup, and this
        // came back as ordinary prose. It then became the next session's PRIOR FINDINGS and was
        // condensed into the final generation prompt, which is the cascade this function exists
        // to stop.
        //
        // Matched by token overlap against the real system prompt rather than by literal prefix,
        // because what returned was a paraphrase: the prompt says "add beyond the prior findings"
        // and the echo said "add about". Bounded to two leading sentences and to short ones, so a
        // genuine finding that happens to reuse the prompt's vocabulary cannot be eaten.
        if let systemPrompt, !systemPrompt.isEmpty {
            func meaningfulWords(_ text: String) -> Set<String> {
                Set(
                    text.lowercased()
                        .split(whereSeparator: { !$0.isLetter })
                        .map(String.init)
                        .filter { $0.count > 2 }
                )
            }
            let promptWords = meaningfulWords(systemPrompt)
            var stripped = 0
            while stripped < 2,
                let sentenceEnd = result.firstIndex(where: { $0 == "." || $0 == "\n" })
            {
                let head = meaningfulWords(String(result[..<sentenceEnd]))
                guard !head.isEmpty, head.count <= 24,
                    Double(head.intersection(promptWords).count) / Double(head.count) >= 0.7
                else { break }
                result = String(result[result.index(after: sentenceEnd)...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                stripped += 1
            }
        }

        // 0. Strip model-markup wrappers before anything else. Device runs showed
        //    eight of twelve Maximum sessions producing an insight that opened with
        //    one of these, and none were caught by the JSON-envelope rules below:
        //
        //      <think> I need to determine what controls impulse responses…
        //      <tool_call name="document_analyst"> { "documents": [ "[S1] mentions…
        //      ```json { "extracted_receptors": [ …
        //
        //    `<think>` is emitted *unclosed* (zero `</think>` across every captured
        //    log), so removing the tag and keeping the prose is right — the text
        //    after it is genuine reasoning. `<tool_call …>` payloads likewise carry
        //    real cited material, so drop only the tag and let the envelope rules
        //    below salvage what follows.
        for tag in ["</think>", "<think>", "</tool_call>", "```json", "```"] {
            result = result.replacingOccurrences(of: tag, with: " ")
        }
        if let toolTag = try? NSRegularExpression(pattern: "<tool_call\\b[^>]*>", options: [.caseInsensitive]) {
            result = toolTag.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: " "
            )
        }
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Drop a leading tool-call blob, through its closing brace.
        let toolCallPrefixes = ["tool_call:", "tool call:", "{\"tool_call", "{ \"tool_call"]
        if let marker = toolCallPrefixes.first(where: { result.lowercased().hasPrefix($0) }) {
            _ = marker
            if let close = result.lastIndex(of: "}") {
                result = String(result[result.index(after: close)...])
            } else if let newline = result.firstIndex(of: "\n") {
                result = String(result[result.index(after: newline)...])
            }
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
            strippedEnvelope = true
        }

        // 2. Drop a leading JSON key path such as `{ "document_analysis": { "new_details": [ "`.
        //    Matches nested `"key":` pairs and their opening braces/brackets, then the
        //    opening quote of the first string value, leaving the prose intact.
        let envelopePattern = "^[\\s\\{\\[]*(?:\"[A-Za-z_][A-Za-z0-9_ ]*\"\\s*:\\s*[\\s\\{\\[]*)+\"?"
        if let regex = try? NSRegularExpression(pattern: envelopePattern),
            let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
            match.range.length > 0,
            let range = Range(match.range, in: result)
        {
            result = String(result[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            strippedEnvelope = true
        }

        if strippedEnvelope {
            // Trailing closers the model did emit, and the stray quotes it used to
            // separate array elements mid-prose (`... [S3]. "The document specifies`).
            while let last = result.last, "\"]}".contains(last) {
                result = String(result.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            result = result.replacingOccurrences(of: "\", \"", with: " ")
            result = result.replacingOccurrences(of: ". \"", with: ". ")
        }

        // 3. Cut at any echoed prompt section header. These strings are emitted only
        //    by `buildChainPrompt`; a model reproducing one is quoting its input.
        let promptMarkers = ["SESSION OBJECTIVE:", "ADDITIONAL DOCUMENTS:", "PRIOR FINDINGS:"]
        for marker in promptMarkers {
            if let range = result.range(of: marker) {
                result = String(result[..<range.lowerBound])
            }
        }

        // 4. Drop a conversational lead-in ("Got it, here's a detailed breakdown of…:")
        //    so it does not consume budget as a PRIOR FINDINGS prefix downstream.
        let preambleStarters = [
            "got it", "sure,", "sure!", "certainly", "of course", "absolutely", "here's", "here is",
        ]
        if let firstLineEnd = result.firstIndex(where: { $0 == "\n" }) {
            let firstLine = String(result[..<firstLineEnd]).trimmingCharacters(in: .whitespaces)
            let lowered = firstLine.lowercased()
            if preambleStarters.contains(where: { lowered.hasPrefix($0) }), firstLine.count < 240 {
                result = String(result[result.index(after: firstLineEnd)...])
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clean up final answer by removing raw LLM markers and artifacts
    /// - Parameter isFinalAnswer: when false, skip substitutions that replace the
    ///   text with user-facing help copy. Intermediate reasoning insights must stay
    ///   as the model wrote them: a session that honestly reports "I could not find
    ///   X in these documents" is making a correct observation the chain needs, and
    ///   swapping it for "This information may be in an image, diagram, or table…"
    ///   both destroys that observation and asserts a cause nobody established. A
    ///   device run showed exactly this at session 12, after which the help text
    ///   entered the fact bank as a finding.
    func cleanupFinalAnswer(_ text: String, isFinalAnswer: Bool = true) -> String {
        // Strip fabricated structured output before anything else looks at the text.
        // This was previously applied only to intermediate reasoning-chain insights,
        // so final answers were unprotected — and a Maximum device run returned this
        // as its entire answer after 50 sessions, 20,182 tokens, and 26 minutes:
        //
        //     { "neurotransmitters_linked_to_actions": [ "neurotransmitter": "dopamine", …
        //
        // 268 characters of unclosed JSON, and `citations=0/0` because a JSON blob
        // carries no [S#] markers for the verifier to check. `cleanupFinalAnswer` has
        // sixteen call sites and covers every path that produces a user-visible
        // answer, so this is the right place for the guard rather than each caller.
        var result = stripPromptEchoAndToolNoise(from: text)

        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // Handle "NOT FOUND" responses gracefully
        // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
        // A model that reports it could not find something has *answered*. That answer
        // is grounded in the documents, often carries citations, and is exactly the
        // behaviour this app promises. Replacing it with boilerplate destroys all of
        // that, and a device run showed the cost precisely:
        //
        //     [Synthesis] Final answer: 385 chars from 20 insights
        //     user received: 216 chars of template
        //
        // A real synthesis built from 20 insights and 11 claims was discarded for text
        // that asserted the information "may be in an image, diagram, or table" —
        // a cause nobody established, and wrong for a text-indexed corpus — and which
        // read "about about" because `extractQueryContext` returns a phrase already
        // beginning with "about".
        //
        // So: never replace. Append a short suggestion only when the model's own
        // answer is too thin to stand on its own, and say nothing about why the
        // information is missing, because that is not known.
        let upperText = result.uppercased()
        let reportsNotFound =
            upperText.contains("NOT FOUND IN DOCUMENTS")
            || upperText.contains("DOCUMENTS DO NOT CONTAIN")
            || upperText.contains("COULDN'T FIND")
            || upperText.contains("COULD NOT FIND")
            || upperText.contains("NO INFORMATION FOUND")
            || upperText.contains("NOT AVAILABLE IN")
        if isFinalAnswer, reportsNotFound, result.count < 160 {
            return result
                + "\n\nYou could try rephrasing the question, checking the original document directly, or adding a document that covers this topic."
        }

        // Handle refusal/ethics responses that snuck through
        let refusalPatterns = [
            "I'm sorry, but I can't continue with that request",
            "I'm here to provide helpful and informative content",
            "adhering to ethical guidelines",
            "If you have any other questions or need assistance",
        ]
        for pattern in refusalPatterns {
            if text.contains(pattern) {
                // Strip the refusal, keep any actual content
                result = result.replacingOccurrences(of: pattern, with: "")
            }
        }

        // Remove all reasoning/insight markers (including truncated versions and variations)
        let markersToRemove = [
            // Full markers
            "REASONING:", "INSIGHT:", "ANALYSIS:", "OBSERVATION:", "CONCLUSION:",
            "ADDITIONAL SPECIFIC DETAILS:", "ADDITIONAL INSIGHTS:", "NEW DETAILS:",
            "SUPPORTING DOCUMENTS:", "PROCEDURE:", "SPECIAL CASES:",
            "RESPONSIBILITIES AND TASKS:", "SPECIAL NOTES:",
            "YOUR COMPREHENSIVE ANSWER:", "COMPREHENSIVE ANSWER:",
            // Truncated markers (from generation cutoffs)
            "ONING:", "ASONING:", "SONING:", "NING:",
            "NSIGHT:", "SIGHT:", "IGHT:",
            "LYSIS:", "YSIS:", "SIS:",
            "Re Reasoning:", "*ONING:",
            // Prompt structure leakage
            "CONCLUSIONS:", "REFERENCES:", "ANSWER:",
            "conclusions:", "references:", "answer:",
            // Lowercased versions
            "reasons:", "reason:", "insight:", "new details:",
            // Meta markers
            "[new details found]", "[additional specifics]",
            "*(Generation stopped", "Please try again.)*",
            "*(Generation stopped. Something went wrong. Please try again.)*",
        ]

        for marker in markersToRemove {
            result = result.replacingOccurrences(of: marker, with: "", options: .caseInsensitive)
        }

        // NOTE: Markdown formatting (headers, lists, code fences) is now preserved
        // MarkdownText renders full block-level markdown as of v1.2

        // Remove lines that are just leaked prompt structure markers (single words like "Reasoning:" with no content)
        let promptLeakPatterns = [
            "reasoning", "insight", "analysis", "observation", "conclusion",
            "reasons", "new details", "additional", "procedure", "special cases",
            "executive summary", "key findings", "your comprehensive answer",
        ]
        result = result.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces).lowercased()
                // Keep empty lines (they separate blocks)
                guard !trimmed.isEmpty else { return true }
                // Filter out lines that are JUST a leaked prompt marker (no real content)
                for pattern in promptLeakPatterns {
                    if trimmed == pattern || trimmed == pattern + ":" {
                        return false
                    }
                }
                return true
            }
            .joined(separator: "\n")

        // Collapse multiple blank lines into single
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }

        // Repair malformed URLs — fix spaces, encoding issues so links actually work
        result = repairMalformedURLs(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Repair malformed URLs in LLM output so links are tappable and correct.
    /// Fixes: spaces within URLs, missing percent-encoding, whitespace before TLDs.
    /// Preserves valid markdown links and bare URLs.
    private func repairMalformedURLs(_ text: String) -> String {
        var result = text

        // 1. Fix markdown links [text](broken url) — repair the URL portion
        if let markdownLinkRegex = try? NSRegularExpression(
            pattern: #"\[([^\]]+)\]\((https?://[^\)]*)\)"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = markdownLinkRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                    let labelRange = Range(match.range(at: 1), in: result),
                    let urlRange = Range(match.range(at: 2), in: result)
                else { continue }
                let label = String(result[labelRange])
                let rawURL = String(result[urlRange])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(fullRange, with: "[\(label)](\(fixed))")
            }
        }

        // 2. Fix bare URLs (not inside markdown link syntax)
        if let bareURLRegex = try? NSRegularExpression(
            pattern: #"(?<!\()https?://\S+"#,
            options: []
        ) {
            let nsRange = NSRange(result.startIndex..., in: result)
            let matches = bareURLRegex.matches(in: result, options: [], range: nsRange)
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result) else { continue }
                let rawURL = String(result[range])
                let fixed = Self.repairURL(rawURL)
                result.replaceSubrange(range, with: fixed)
            }
        }

        return result
    }

    /// Repair a single URL string: remove internal spaces, fix encoding.
    private static func repairURL(_ url: String) -> String {
        var fixed = url
        // Remove spaces (LLM inserts spaces like "github .com" or "blob/ main")
        fixed = fixed.replacingOccurrences(of: " ", with: "")
        // Remove trailing punctuation the LLM may have appended
        while fixed.hasSuffix(".") || fixed.hasSuffix(",") || fixed.hasSuffix(";") || fixed.hasSuffix(")") {
            fixed = String(fixed.dropLast())
        }
        return fixed
    }

    /// Extract what the user was asking about from a "not found" response
    /// Used to provide helpful feedback about what couldn't be found
    private func extractQueryContext(from text: String) -> String {
        // Common patterns where the topic might be mentioned
        let patterns = [
            #"(?:about|regarding|for|on)\s+(?:the\s+)?([^.!?\n]+)"#,
            #"(?:find|locate|search for)\s+(?:the\s+)?([^.!?\n]+)"#,
            #"(?:information|data|details)\s+(?:about|on|regarding)\s+([^.!?\n]+)"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let topicRange = Range(match.range(at: 1), in: text)
            {
                let topic = String(text[topicRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if topic.count > 3 && topic.count < 100 {
                    return topic
                }
            }
        }

        return ""
    }

    /// Parse confidence score from text
    func parseConfidence(from text: String) -> Float? {
        // Look for patterns like "confidence: 85" or "85%"
        let patterns = [
            #"confidence[:\s]+(\d+)"#,
            #"(\d+)%\s*confidence"#,
            #"(\d+)/100"#,
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let numRange = Range(match.range(at: 1), in: text),
                let value = Float(text[numRange])
            {
                return value > 1 ? value / 100 : value
            }
        }

        return nil
    }

    /// Description of what each session focuses on
    func sessionPromptDescription(_ index: Int, _ total: Int) -> String {
        switch index {
        case 0: return "Initial Analysis"
        case total - 1: return "Final Synthesis"
        case 1: return "Pattern Recognition"
        default: return "Deepening Understanding"
        }
    }
}
