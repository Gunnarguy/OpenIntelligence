//
//  RAGEngine.swift
//  OpenIntelligence
//
//  Background actor for pure, CPU-heavy RAG computations
//  - Offloads MMR selection and context assembly off the main actor
//  - Avoids touching UI or main-actor–isolated services
//

import Foundation
import os
import NaturalLanguage
import Accelerate
import CoreML
import Metal
import Tokenizers

#if DEBUG
    import os.signpost
#endif

/// Background executor for pure RAG computations (no UI/IO access)
actor RAGEngine {
    // MARK: - Shared Instance

    /// Shared singleton to avoid repeated model loading
    static let shared = RAGEngine()

    // MARK: - Pre-compiled Regex Patterns
    // Static compilation avoids try! at call sites and amortizes cost across all queries.
    // If a pattern fails to compile (should never happen), the Optional safely returns 0 matches.

    private static let sectionNumberRegex = try? Regex(#"\b\d+\.\d+\.?"#)
    private static let pageNumberRegex1 = try? Regex(#"\.{2,}\s*\d{1,3}\b"#)
    private static let pageNumberRegex2 = try? Regex(#"\.\s+\d{1,2}\b"#)
    private static let pageNumberRegex3 = try? Regex(#"\b\d{1,2}\s+\.{2,}"#)
    private static let standaloneNumberRegex = try? Regex(#"\b\d{2}\b"#)

    // MARK: - Properties

    #if canImport(CoreML)
        private var rerankerModel: MLModel?
    #endif

    private var rerankerTokenizer: Tokenizer?
    private var isSetupComplete = false

    init() {
        Task { [weak self] in
            await self?.setupReRanker()
        }
    }

    private func setupReRanker() async {
        // Only run setup once
        guard !isSetupComplete else { return }
        isSetupComplete = true

        #if canImport(CoreML)
            // Load ReRanker Model (compiled from .mlpackage to .mlmodelc by Xcode)
            let modelName = "ReRankerModel"
            if let url = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all
                    config.allowLowPrecisionAccumulationOnGPU = true
                    self.rerankerModel = try MLModel(contentsOf: url, configuration: config)
                    Log.info("[RAGEngine] Loaded ReRankerModel.mlmodelc", category: .retrieval)
                } catch {
                    Log.error("[RAGEngine] Failed to load ReRanker: \(error)", category: .retrieval)
                }
            } else if let sourceURL = OpenIntelligenceResourceBundle.url(forResource: modelName, withExtension: "mlpackage") {
                // Fallback: Check for uncompiled package
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all
                    config.allowLowPrecisionAccumulationOnGPU = true
                    self.rerankerModel = try MLModel(contentsOf: sourceURL, configuration: config)
                    Log.info("[RAGEngine] Loaded ReRankerModel.mlpackage (fallback)", category: .retrieval)
                } catch {
                    Log.error("[RAGEngine] Failed to load ReRanker from source: \(error)", category: .retrieval)
                }
            } else {
                Log.warning("[RAGEngine] ReRankerModel not found (looked for .mlmodelc and .mlpackage)", category: .retrieval)
            }
        #endif

        // Load Tokenizer
        if let url = OpenIntelligenceResourceBundle.url(forResource: "reranker_tokenizer", withExtension: "bundle") {
            do {
                self.rerankerTokenizer = try await AutoTokenizer.from(directory: url)
                Log.info("[RAGEngine] Loaded Rust-backed ReRanker Tokenizer", category: .retrieval)
            } catch {
                Log.error("[RAGEngine] Failed to load ReRanker Tokenizer: \(error)", category: .retrieval)
            }
        }
    }

    // MARK: - MMR (Maximal Marginal Relevance)

    /// Apply MMR to select diverse, non-redundant chunks
    /// Critical for comprehensive information coverage
    /// GPU-accelerated for large candidate sets (50+ vectors)
    /// - Parameters:
    ///   - candidates: Ranked candidate chunks
    ///   - queryEmbedding: Original query embedding for relevance scoring (unused here; uses stored similarityScore)
    ///   - topK: Number of diverse chunks to select
    ///   - lambda: Balance between relevance (1.0) and diversity (0.0). Default 0.7 = 70% relevance, 30% diversity
    /// - Returns: Diverse set of chunks balancing relevance and novelty
    func applyMMR(
        candidates: [RetrievedChunk],
        queryEmbedding _: [Float],
        topK: Int,
        lambda: Float = 0.7
    ) async -> [RetrievedChunk] {
        // Report CPU activity for MMR computation
        Task { @MainActor in
            HardwareTelemetryReporter.pulse(.ragOrchestration, intensity: 0.7, duration: 0.3)
            HardwareTelemetryReporter.reportCPUOperation()
        }

        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "applyMMR", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "applyMMR", signpostID: spid) }
        #endif
        guard !candidates.isEmpty else { return [] }
        guard topK > 1 else { return Array(candidates.prefix(1)) }

        // GPU ACCELERATION: Pre-compute all pairwise similarities for large candidate sets
        // This is O(n²) so GPU provides massive speedup (10-50x for 100+ candidates)
        let gpuCompute = await MainActor.run { GPUComputeService.shared }
        let metalVectorOpsEnabled = await MainActor.run {
            DeviceCapabilityService.shared.useMetalForVectorOps
        }
        let useGPU = candidates.count > 50
            && metalVectorOpsEnabled
            && gpuCompute.isGPUAvailable

        var diversityMatrix: [[Float]]? = nil
        if useGPU {
            // Report GPU activity for MMR diversity matrix computation
            Task { @MainActor in
                HardwareTelemetryReporter.pulse(.mmrComputation, intensity: 0.9, duration: 0.4)
                HardwareTelemetryReporter.reportGPUCompute()
            }

            let embeddings = candidates.map { $0.chunk.embedding }
            let matrix = gpuCompute.mmrDiversityMatrix(embeddings: embeddings)
            // Validate matrix is N×N matching candidate count — malformed matrix causes subscript crash
            if matrix.count == candidates.count, matrix.first?.count == candidates.count {
                diversityMatrix = matrix
                Log.debug("[RAGEngine] 🚀 GPU MMR diversity matrix for \(candidates.count) candidates", category: .retrieval)
            } else {
                Log.warning("[RAGEngine] ⚠️ GPU MMR matrix dimensions mismatch (got \(matrix.count)×\(matrix.first?.count ?? 0), expected \(candidates.count)×\(candidates.count)), falling back to CPU", category: .retrieval)
            }
        }

        var selected: [RetrievedChunk] = []
        var selectedIndices: [Int] = []
        var remaining = Array(candidates.enumerated())

        // Start with the most relevant chunk
        if let first = remaining.first {
            selected.append(first.element)
            selectedIndices.append(first.offset)
            remaining.removeFirst()
        }

        // Iteratively select chunks that maximize: λ * relevance - (1-λ) * max_similarity_to_selected
        while selected.count < topK, !remaining.isEmpty {
            if Task.isCancelled { return selected }

            var bestScore: Float = -.infinity
            var bestIndex = 0

            for (remainingIdx, (origIdx, candidate)) in remaining.enumerated() {
                // Relevance to query (use stored similarity score)
                let relevance = candidate.similarityScore

                // Max similarity to already selected chunks (diversity penalty)
                var maxSimilarityToSelected: Float = 0

                if let matrix = diversityMatrix {
                    // GPU PATH: Use pre-computed similarity matrix
                    for selectedIdx in selectedIndices {
                        guard origIdx < matrix.count, selectedIdx < matrix[origIdx].count else { continue }
                        let similarity = matrix[origIdx][selectedIdx]
                        maxSimilarityToSelected = max(maxSimilarityToSelected, similarity)
                    }
                } else {
                    // CPU PATH: Compute similarities on-the-fly
                    for selectedChunk in selected {
                        let similarity = cosineSimilarityAccelerated(
                            candidate.chunk.embedding,
                            selectedChunk.chunk.embedding
                        )
                        maxSimilarityToSelected = max(maxSimilarityToSelected, similarity)
                    }
                }

                // MMR score: balance relevance and diversity
                let mmrScore = lambda * relevance - (1 - lambda) * maxSimilarityToSelected

                if mmrScore > bestScore {
                    bestScore = mmrScore
                    bestIndex = remainingIdx
                }
            }

            // Add best chunk and remove from candidates
            let (origIdx, chosen) = remaining.remove(at: bestIndex)
            selected.append(chosen)
            selectedIndices.append(origIdx)
        }

        return selected
    }

    // MARK: - Silicon-Native Vector Math (Accelerate Framework)

    /// Hardware-accelerated cosine similarity using vDSP
    /// Uses vDSP_dotpr for dot product and cblas_snrm2 for L2 norm
    /// Neural Engine / AMX accelerated on Apple Silicon
    private func cosineSimilarityAccelerated(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // Modern Accelerate API: vDSP.sumOfSquares + sqrt (replaces deprecated cblas_snrm2)
        let normA = sqrt(vDSP.sumOfSquares(a))
        let normB = sqrt(vDSP.sumOfSquares(b))

        let denom = normA * normB
        return denom > 1e-9 ? dotProduct / denom : 0
    }

    /// Legacy cosine similarity (kept for compatibility, but prefer accelerated version)
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        cosineSimilarityAccelerated(a, b)
    }

    // MARK: - Context Assembly

    /// Format retrieved chunks into a context string for the LLM
    func formatContext(_ chunks: [RetrievedChunk]) async -> String {
        guard !chunks.isEmpty else { return "" }

        var builder = String()
        // Reserve some capacity to avoid many reallocations for typical sizes
        builder.reserveCapacity(4096)

        for (index, retrieved) in chunks.enumerated() {
            if Task.isCancelled { break }

            builder += "[Document Chunk \(index + 1), Similarity: \(String(format: "%.3f", retrieved.similarityScore))]\n"
            builder += retrieved.chunk.parentContent ?? retrieved.chunk.content

            if index != chunks.count - 1 {
                builder += "\n\n---\n\n"
            }
        }

        return builder
    }

    // MARK: - Re-ranking and Context Utilities

    /// Re-rank results using multiple signals (semantic, keyword, proximity, position)
    /// UPDATED: Uses Cross-Encoder model if available, otherwise falls back to heuristics
    func rerank(
        chunks: [RetrievedChunk],
        query: String,
        topK: Int
    ) async -> [RetrievedChunk] {
        // Report Neural Engine activity for reranking (cross-encoder runs on ANE)
        Task { @MainActor in
            HardwareTelemetryReporter.pulse(.reranking, intensity: 0.85, duration: 0.3)
            HardwareTelemetryState.shared.incrementANECounter()
        }

        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "rerank", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "rerank", signpostID: spid) }
        #endif
        guard !chunks.isEmpty else { return [] }

        // Cross-encoder candidate pool: ADAPTIVE ceiling for universal retrieval.
        // Fixed 100 missed needles at rank 101+ in large corpora. Now scales:
        // - Small corpus (<200 chunks): use all chunks (no artificial ceiling)
        // - Medium corpus: topK * 5 (50 candidates for topK=10)
        // - Large corpus: cap at 250 to bound latency (cross-encoder is O(n))
        // Always at least 100 to maintain existing behavior for normal queries.
        let adaptiveCeiling = min(chunks.count, max(100, min(250, topK * 5)))
        let candidateChunks = Array(chunks.prefix(adaptiveCeiling))

        #if canImport(CoreML)
            if let model = rerankerModel, let tokenizer = rerankerTokenizer {
                return await rerankWithCrossEncoder(
                    chunks: candidateChunks,
                    query: query,
                    topK: topK,
                    model: model,
                    tokenizer: tokenizer
                )
            }
        #endif

        let queryTerms = tokenize(query).filter { $0.count > 2 }
        let queryTermSet = Set(queryTerms)
        let queryLower = query.lowercased()
        let hasDigits = queryLower.rangeOfCharacter(from: .decimalDigits) != nil
        let wantsSteps = queryLower.contains("step")
            || queryLower.contains("procedure")
            || queryLower.contains("instructions")
            || queryLower.contains("checklist")
            || queryLower.contains("how to")
            || queryLower.contains("guide")

        // Build scored tuples
        var scored: [(chunk: RetrievedChunk, score: Float, keyword: Float, proximity: Float, metadata: Float)] = []
        scored.reserveCapacity(candidateChunks.count)

        for (i, r) in candidateChunks.enumerated() {
            if Task.isCancelled { return Array(candidateChunks.prefix(topK)) }
            if i % 16 == 0 { await Task.yield() }

            var score = r.similarityScore

            let keywordBoost = calculateKeywordMatch(query: query, content: r.chunk.content)
            score += keywordBoost * 0.25 // Moderate: boost keyword matches without overwhelming semantic similarity

            let proximityBoost = calculateTermProximity(query: query, content: r.chunk.content)
            score += proximityBoost * 0.20 // Moderate: favor term proximity without clobbering vector ranking

            let chunkIndex = r.chunk.metadata.chunkIndex
            let positionScore = 1.0 / Float(chunkIndex + 10)
            score += positionScore * 0.05

            let metadataBoost = computeMetadataBoost(
                chunk: r,
                queryTerms: queryTermSet,
                hasDigits: hasDigits,
                wantsSteps: wantsSteps
            )
            score += metadataBoost

            // TOC/Boilerplate Detection Penalty
            // Table-of-contents chunks have many section numbers but little actual content
                let contentForPenalty = r.chunk.parentContent ?? r.chunk.content
                let tocPenalty = computeTOCPenalty(content: contentForPenalty)
                let questionBankPenalty = computeQuestionBankPenalty(content: contentForPenalty, query: query)
                score -= tocPenalty + questionBankPenalty

            scored.append((r, score, keywordBoost, proximityBoost, metadataBoost))
        }

        // Sort by rerank score desc
        scored.sort { $0.score > $1.score }

        if scored.count > 0 {
            // keep debug parity with existing logs
            let top = scored[0]
            Log.debug("[RAGEngine] Re-ranking complete. Top score: \(String(format: "%.4f", top.score))", category: .retrieval)
            Log.debug("[RAGEngine] Score breakdown:", category: .retrieval)
            Log.debug("[RAGEngine] - Semantic: \(String(format: "%.3f", top.chunk.similarityScore))", category: .retrieval)
            Log.debug("[RAGEngine] - Keywords: \(String(format: "%.3f", top.keyword))", category: .retrieval)
            Log.debug("[RAGEngine] - Proximity: \(String(format: "%.3f", top.proximity))", category: .retrieval)
            if top.metadata > 0 {
                Log.debug("[RAGEngine] - Metadata: \(String(format: "%.3f", top.metadata))", category: .retrieval)
            }
        }

        return Array(scored.prefix(topK)).map { scoredItem in
            // Propagate the rerank score to the chunk so downstream sorting preserves re-ranking order
            RetrievedChunk(
                chunk: scoredItem.chunk.chunk,
                similarityScore: scoredItem.score,
                rank: scoredItem.chunk.rank,
                sourceDocument: scoredItem.chunk.sourceDocument,
                pageNumber: scoredItem.chunk.pageNumber
            )
        }
    }

    /// Filter chunks by minimum similarity threshold
    func filterBySimilarity(
        chunks: [RetrievedChunk],
        min: Float
    ) async -> [RetrievedChunk] {
        guard !chunks.isEmpty else { return [] }
        var out: [RetrievedChunk] = []
        out.reserveCapacity(chunks.count)

        for (i, r) in chunks.enumerated() {
            if Task.isCancelled { return out }
            if i % 32 == 0 { await Task.yield() }
            if r.similarityScore >= min {
                out.append(r)
            }
        }
        return out
    }

    /// Assemble a bounded context string and report number of chunks used
    /// - Parameters:
    ///   - chunks: Retrieved chunks sorted by relevance
    ///   - maxChars: Maximum character budget for the context
    ///   - compact: When true, uses minimal headers to maximize content density (for on-device 4K limit)
    ///   - useLostInMiddleMitigation: Reorders chunks to place best at start AND end (LLMs attend poorly to middle)
    func assembleContext(
        chunks: [RetrievedChunk],
        maxChars: Int,
        compact: Bool = false,
        useLostInMiddleMitigation: Bool = true
    ) async -> (context: String, used: Int, sources: [RetrievedChunk]) {
        let __spAssembleContext = PipelineSignposts.query.beginInterval("AssembleContext")
        defer { PipelineSignposts.query.endInterval("AssembleContext", __spAssembleContext) }
        // Report CPU activity for context assembly
        Task { @MainActor in
            HardwareTelemetryReporter.pulse(.ragOrchestration, intensity: 0.5, duration: 0.2)
            HardwareTelemetryReporter.reportCPUOperation()
        }
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "assembleContext", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "assembleContext", signpostID: spid) }
        #endif
        guard !chunks.isEmpty else { return ("", 0, []) }

        // "Lost in the Middle" mitigation (Liu et al., 2023):
        // LLMs attend strongly to the beginning and end of context, but poorly to the middle.
        // Reorder chunks so the most relevant are at positions 1, N, 2, N-1, 3, N-2, etc.
        // This ensures the best chunks are in high-attention positions.
        let orderedChunks: [RetrievedChunk]
        if useLostInMiddleMitigation, chunks.count >= 4 {
            orderedChunks = applyLostInMiddleReordering(chunks)
        } else {
            orderedChunks = chunks
        }

        var builder = String()
        builder.reserveCapacity(min(maxChars, 4096))
        var used = 0

        // The chunks that actually reached the prompt, in the order their `[Sn]` labels were
        // assigned. This must be returned rather than recomputed by the caller.
        //
        // Labels are numbered over `orderedChunks`, which is `chunks` after Lost-in-the-Middle
        // reordering. Every caller was rebuilding the citation list as `prefix(used)` of its OWN
        // pre-reordering array, so for any query with four or more chunks the two disagreed:
        // reordering emits `front + back.reversed()`, so [A,B,C,D] is shown as [A,C,D,B] and a
        // model citing [S2] meant C while the response resolved it to B. Three of four citations
        // pointed at the wrong document, silently, and nothing downstream could detect it because
        // the indices were all in range.
        var usedSources: [RetrievedChunk] = []

        // ── Abbreviation Glossary Injection ──────────────────────────────────
        // Collect all abbreviation→expansion mappings from retrieved chunks.
        // This prevents the LLM from cross-contaminating abbreviations:
        // e.g., expanding "ED" as "Oppositional Defiant Disorder" when documents
        // define it as "Emotional Dysregulation". The glossary is prepended to
        // the context string so the LLM sees the correct definitions FIRST.
        var glossary: [String: String] = [:]
        for chunk in orderedChunks {
            for (abbr, expansion) in chunk.chunk.metadata.abbreviations {
                // First definition wins (most authoritative)
                if glossary[abbr] == nil {
                    glossary[abbr] = expansion
                }
            }
        }
        if !glossary.isEmpty {
            let sortedEntries = glossary.sorted { $0.key < $1.key }
            let glossaryBlock: String
            if compact {
                // Compact: "ABBR=Expansion" format, semicolon-separated
                let entries = sortedEntries.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
                glossaryBlock = "[Glossary] \(entries)\n---\n"
            } else {
                let entries = sortedEntries.map { "  \($0.key) = \($0.value)" }.joined(separator: "\n")
                glossaryBlock = "[Abbreviations from documents — use these exact definitions]\n\(entries)\n\n---\n\n"
            }
            // Only inject if it fits within ~10% of the budget
            if glossaryBlock.count <= maxChars / 10 {
                builder += glossaryBlock
                Log.debug("[RAGEngine] Injected abbreviation glossary (\(glossary.count) entries, \(glossaryBlock.count) chars)", category: .retrieval)
            }
        }

        // Calculate target chars per chunk to fit at least 3 chunks
        // This prevents the "1 giant chunk" problem where context is too narrow
        let minChunksTarget = min(3, orderedChunks.count)
        let headerOverhead = compact ? 30 : 80  // Approximate header + separator size
        let targetCharsPerChunk = max(400, (maxChars - (minChunksTarget * headerOverhead)) / minChunksTarget)

        // ── Chunk Text Deduplication ─────────────────────────────────────
        // Skip chunks whose content is >75% word overlap (Jaccard) with an
        // already-included chunk. This prevents near-identical boilerplate
        // (e.g., repeated inspection report pages) from flooding the LLM
        // context and causing repetition loops.
        var usedWordSets: [Set<String>] = []

        for (i, r) in orderedChunks.enumerated() {

            if Task.isCancelled { break }
            if i % 16 == 0 { await Task.yield() }

            // Sanitize content to help Apple FM's language detector
            // URLs and special Unicode can confuse it into detecting wrong languages
            let rawContent = r.chunk.parentContent ?? r.chunk.content

            // Include contextual prefix (document title/author) in final context
            // This ensures author-based queries like "What did X find?" work correctly
            // The prefix was used for embedding and re-ranking, so include it for LLM too
            let content: String
            if let prefix = r.chunk.contextualPrefix, !prefix.isEmpty {
                content = prefix + rawContent
            } else {
                content = rawContent
            }
            let sanitizedContent = sanitizeForLanguageDetection(content)

            // Jaccard word-overlap deduplication
            let contentWords = Set(
                sanitizedContent.lowercased()
                    .split(separator: " ")
                    .map { $0.trimmingCharacters(in: CharacterSet.alphanumerics.inverted) }
                    .filter { $0.count >= 3 }
            )
            if contentWords.count >= 5 {
                let isDuplicate = usedWordSets.contains { existingWords in
                    let intersection = contentWords.intersection(existingWords)
                    let union = contentWords.union(existingWords)
                    guard !union.isEmpty else { return false }
                    let jaccard = Double(intersection.count) / Double(union.count)
                    return jaccard >= 0.75
                }
                if isDuplicate {
                    Log.debug("[RAGEngine] Skipping chunk \(i + 1) — >75% word overlap with existing context chunk", category: .retrieval)
                    continue
                }
            }

            // Calculate remaining budget
            let remainingBudget = maxChars - builder.count
            let chunksRemaining = orderedChunks.count - i

            // Truncate content if needed to fit more chunks
            // Priority: fit at least minChunksTarget chunks, then fill remaining space
            let truncatedContent: String
            if used < minChunksTarget - 1 && sanitizedContent.count > targetCharsPerChunk {
                // Truncate to target size to leave room for more chunks
                // Truncate at sentence boundary if possible
                truncatedContent = truncateAtSentence(sanitizedContent, maxChars: targetCharsPerChunk)
            } else if used >= minChunksTarget - 1 && chunksRemaining == 1 {
                // Last chunk: use all remaining space
                let maxForThis = remainingBudget - headerOverhead - 10
                if sanitizedContent.count > maxForThis && maxForThis > 200 {
                    truncatedContent = truncateAtSentence(sanitizedContent, maxChars: maxForThis)
                } else {
                    truncatedContent = sanitizedContent
                }
            } else {
                truncatedContent = sanitizedContent
            }

            let block: String
            if compact {
                // Compact mode: minimal headers, no similarity scores, tighter separators
                // Saves ~30-50 chars per chunk for more content in constrained budgets
                let source = r.sourceDocument.isEmpty ? "" : URL(fileURLWithPath: r.sourceDocument).lastPathComponent
                let sourceRef = source.isEmpty ? "" : "(\(source)) "
                block = "[S\(i + 1)] \(sourceRef)\(truncatedContent)" + (i != orderedChunks.count - 1 ? "\n---\n" : "")
            } else {
                // Full mode: rich metadata for better citation context
                let source = r.sourceDocument.isEmpty ? "Unknown" : r.sourceDocument
                let page = r.pageNumber.map { " p.\($0)" } ?? ""
                let header = "[S\(i + 1)] \(source)\(page) • sim \(String(format: "%.3f", r.similarityScore))\n"
                block = header + truncatedContent + (i != orderedChunks.count - 1 ? "\n\n---\n\n" : "")
            }

            if builder.count + block.count <= maxChars || used == 0 {
                builder += block
                used += 1
                usedSources.append(r)
                usedWordSets.append(contentWords)
            } else if used < minChunksTarget && remainingBudget > 300 {
                // Force-fit truncated version if we haven't hit minimum chunks yet
                let forceTruncated = truncateAtSentence(truncatedContent, maxChars: remainingBudget - headerOverhead - 20)
                if forceTruncated.count >= 150 {
                    let forceBlock: String
                    if compact {
                        let source = r.sourceDocument.isEmpty ? "" : URL(fileURLWithPath: r.sourceDocument).lastPathComponent
                        let sourceRef = source.isEmpty ? "" : "(\(source)) "
                        forceBlock = "[S\(i + 1)] \(sourceRef)\(forceTruncated)" + (i != orderedChunks.count - 1 ? "\n---\n" : "")
                    } else {
                        let source = r.sourceDocument.isEmpty ? "Unknown" : r.sourceDocument
                        let page = r.pageNumber.map { " p.\($0)" } ?? ""
                        let header = "[S\(i + 1)] \(source)\(page) • sim \(String(format: "%.3f", r.similarityScore))\n"
                        forceBlock = header + forceTruncated + (i != orderedChunks.count - 1 ? "\n\n---\n\n" : "")
                    }
                    builder += forceBlock
                    used += 1
                    usedSources.append(r)
                    usedWordSets.append(contentWords)
                } else {
                    break
                }
            } else {
                break
            }
        }

        // State the citation range the model was actually given.
        //
        // About thirty characters against a 4096 token window, and it closes the one gap that made
        // a citation like [S6] possible from a four source prompt: the model could see labels but
        // never the bound, so a source it inferred was indistinguishable to it from one it had read.
        // Semantic labels would also close it and cost roughly two hundred characters, which is 5%
        // of a Deep Think session's entire evidence budget. At this context size the cheap fix wins.
        if used == 1 {
            builder += "\n\nCite only source S1."
        } else if used > 1 {
            builder += "\n\nCite only sources S1 to S\(used)."
        }

        return (builder, used, usedSources)
    }

    /// Truncate text at a sentence boundary, preferring to keep complete sentences
    private func truncateAtSentence(_ text: String, maxChars: Int) -> String {
        guard text.count > maxChars else { return text }

        let truncated = String(text.prefix(maxChars))

        // Find last sentence-ending punctuation
        let sentenceEnders: [Character] = [".", "!", "?"]
        if let lastSentenceEnd = truncated.lastIndex(where: { sentenceEnders.contains($0) }) {
            let endIndex = truncated.index(after: lastSentenceEnd)
            let result = String(truncated[..<endIndex])
            // Only use sentence boundary if we keep at least 60% of the truncated text
            if result.count >= maxChars * 6 / 10 {
                return result
            }
        }

        // Fall back to word boundary
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }

        return truncated + "…"
    }

    /// Sanitizes content to help Apple Foundation Models' language detector.
    /// URLs, special Unicode, and non-ASCII characters can confuse it into detecting wrong languages.
    /// This preserves semantic content while removing problematic patterns.
    private func sanitizeForLanguageDetection(_ text: String) -> String {
        var result = text

        // 1. Replace URLs with placeholder (URLs often trigger wrong language detection)
        // Matches http://, https://, and www. URLs
        let urlPattern = #"https?://[^\s\]\)]+|www\.[^\s\]\)]+"#
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: .caseInsensitive) {
            result = urlRegex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[URL]"
            )
        }

        // 2. Replace non-ASCII punctuation that might confuse language detection
        // Polish-like characters: ł, ą, ę, ś, ć, ń, ź, ż, ó
        // Replace with closest ASCII equivalents
        let replacements: [(String, String)] = [
            ("ł", "l"), ("Ł", "L"),
            ("ą", "a"), ("Ą", "A"),
            ("ę", "e"), ("Ę", "E"),
            ("ś", "s"), ("Ś", "S"),
            ("ć", "c"), ("Ć", "C"),
            ("ń", "n"), ("Ń", "N"),
            ("ź", "z"), ("Ź", "Z"),
            ("ż", "z"), ("Ż", "Z"),
            ("ó", "o"), ("Ó", "O"),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }

        // 3. Remove zero-width characters that can confuse tokenizers
        result = result.replacingOccurrences(of: "\u{200B}", with: "") // zero-width space
        result = result.replacingOccurrences(of: "\u{200C}", with: "") // zero-width non-joiner
        result = result.replacingOccurrences(of: "\u{200D}", with: "") // zero-width joiner
        result = result.replacingOccurrences(of: "\u{FEFF}", with: "") // byte order mark

        return result
    }

    /// Reorders chunks to mitigate "Lost in the Middle" attention patterns (Liu et al., 2023).
    /// Places most relevant chunks at start and end of context where LLMs attend best.
    /// Pushes least-relevant chunks to the middle positions where attention is weakest.
    /// For chunks ranked [1,2,3,4,5,6], produces [1,3,5,6,4,2]:
    ///   - Start: #1 (best), #3, #5
    ///   - End: #2 (second-best), #4, #6
    ///   - Middle: worst chunks (#5, #6)
    private func applyLostInMiddleReordering(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        guard chunks.count >= 4 else { return chunks }

        // Split into odd-indexed (0, 2, 4...) and even-indexed (1, 3, 5...) positions
        // Odd-indexed go to the front (start of context — high attention)
        // Even-indexed go to the back in reverse (end of context — high attention)
        // Result: worst chunks land in the middle (low attention zone)
        var frontChunks: [RetrievedChunk] = []
        var backChunks: [RetrievedChunk] = []

        for (i, chunk) in chunks.enumerated() {
            if i % 2 == 0 {
                frontChunks.append(chunk)   // ranks 1, 3, 5, ... → front
            } else {
                backChunks.append(chunk)    // ranks 2, 4, 6, ... → back (reversed)
            }
        }

        // Front chunks in order, back chunks reversed so #2 is at the very end
        return frontChunks + backChunks.reversed()
    }

    /// Compute confidence score and quality warnings (off-main)
    func assessResponseQuality(
        chunks: [RetrievedChunk],
        query: String,
        totalDocs: Int,
        topScoreOverride: Float? = nil  // Use reranked score when available (sibling chunks have discounted scores)
    ) async -> (Float, [String]) {
        if Task.isCancelled { return (0.0, ["Cancelled"]) }
        await Task.yield()

        var warnings: [String] = []

        // Factor 1: Top similarity
        // Use override if provided (reranked score from pipeline), otherwise fall back to chunk score
        let topSimilarity = topScoreOverride ?? chunks.first?.similarityScore ?? 0

        // Adjust thresholds for reranker output (normalized 0.10-0.90)
        // A reranked score of 0.70+ is excellent, 0.50+ is good
        let lowThreshold: Float = topScoreOverride != nil ? 0.50 : 0.4
        let moderateThreshold: Float = topScoreOverride != nil ? 0.70 : 0.6

        if topSimilarity < lowThreshold {
            warnings.append("Low relevance: Best match only \(String(format: "%.1f", topSimilarity * 100))% similar")
        } else if topSimilarity < moderateThreshold {
            warnings.append("Moderate relevance: Consider rephrasing query for better results")
        }

        // Factor 2: Supporting chunk count
        let chunkCount = chunks.count
        if chunkCount < 3 {
            warnings.append("Limited context: Only \(chunkCount) relevant chunks found")
        }

        // Factor 3: Source diversity
        let uniqueSources = Set(chunks.map { $0.sourceDocument })
        let sourceCount = uniqueSources.count
        if sourceCount == 1, totalDocs > 1 {
            warnings.append("Single source: Information from only one document")
        }

        // Factor 4: Query quality
        let queryWords = query.split(separator: " ").count
        if queryWords <= 2 {
            warnings.append("Generic query: Try more specific questions for better accuracy")
        }

        // Aggregate confidence
        let similarityWeight: Float = 0.5
        let chunkCountWeight: Float = 0.2
        let sourceDiversityWeight: Float = 0.2
        let queryQualityWeight: Float = 0.1

        let similarityScore = min(topSimilarity / 0.8, 1.0)
        let chunkScore = min(Float(chunkCount) / 5.0, 1.0)
        let diversityScore = min(Float(sourceCount) / Float(max(totalDocs, 1)), 1.0)
        let queryScore = min(Float(queryWords) / 5.0, 1.0)

        let confidence = (
            similarityScore * similarityWeight +
                chunkScore * chunkCountWeight +
                    diversityScore * sourceDiversityWeight +
                    queryScore * queryQualityWeight
        )

        return (confidence, warnings)
    }

    // MARK: - Vector Search Utilities

    /// Compute vector search off-main across a snapshot of chunks
    /// - Parameters:
    ///   - embedding: Query embedding (512 dims)
    ///   - chunks: Snapshot of document chunks to search
    ///   - topK: Number of top results
    ///   - chunkNorms: Optional precomputed norms keyed by chunk id
    func computeVectorSearch(
        embedding: [Float],
        chunks: [DocumentChunk],
        topK: Int,
        chunkNorms: [UUID: Float]? = nil
    ) async -> [RetrievedChunk] {
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "computeVectorSearch", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "computeVectorSearch", signpostID: spid) }
        #endif
        guard !chunks.isEmpty, topK > 0 else { return [] }

        // Precompute query norm if using optimized path
        let queryNorm: Float? = chunkNorms == nil ? nil : computeNorm(embedding)

        var scored: [(chunk: DocumentChunk, score: Float)] = []
        scored.reserveCapacity(chunks.count)

        for (i, c) in chunks.enumerated() {
            if Task.isCancelled {
                break
            }
            if i % 64 == 0 {
                await Task.yield()
            }

            let s: Float
            if let norms = chunkNorms, let cn = norms[c.id], let qn = queryNorm {
                s = optimizedCosineSimilarity(embedding, c.embedding, queryNorm: qn, chunkNorm: cn)
            } else {
                s = cosine(embedding, c.embedding)
            }
            scored.append((c, s))
        }

        // Sort and take topK
        let top = scored.sorted { $0.score > $1.score }.prefix(min(topK, scored.count))
        return Array(top.enumerated().map { idx, pair in
            RetrievedChunk(
                chunk: pair.chunk,
                similarityScore: pair.score,
                rank: idx + 1
            )
        })
    }

    // MARK: - Hybrid Search Utilities (BM25 + RRF)

    /// Compute BM25 scores for candidates given a precomputed snapshot
    func bm25Scores(
        query: String,
        candidates: [RetrievedChunk],
        snapshot: BM25Snapshot
    ) async -> [(chunk: RetrievedChunk, score: Float)] {
        // Report CPU activity for BM25 lexical scoring
        Task { @MainActor in
            HardwareTelemetryReporter.pulse(.bm25Scoring, intensity: 0.6, duration: 0.2)
            HardwareTelemetryReporter.reportCPUOperation()
        }

        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "bm25Scores", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "bm25Scores", signpostID: spid) }
        #endif
        guard !candidates.isEmpty else { return [] }

        // Tokenize query once
        let queryTerms = tokenize(query)

        var results: [(chunk: RetrievedChunk, score: Float)] = []
        results.reserveCapacity(candidates.count)

        for (i, r) in candidates.enumerated() {
            if Task.isCancelled { return results }
            if i % 16 == 0 { await Task.yield() }

            let docTerms = tokenize(r.chunk.content)
            let docLength = Float(docTerms.count)
            if docLength == 0 {
                results.append((r, 0))
                continue
            }

            // Term frequencies in doc
            var termFreqs: [String: Int] = [:]
            for t in docTerms {
                termFreqs[t, default: 0] += 1
            }

            var score: Float = 0
            for q in queryTerms {
                let tf = Float(termFreqs[q] ?? 0)
                let df = Float(snapshot.documentFrequencies[q] ?? 1)

                // IDF
                let idf: Float = logf((Float(snapshot.totalDocuments) - df + 0.5) / (df + 0.5) + 1)

                // BM25 with k1=1.5, b=0.5 (matches BM25Scorer — lowered from 0.75 because chunks are ~260 words uniform length)
                let k1: Float = 1.5
                let b: Float = 0.5
                let numerator = tf * (k1 + 1)
                let denominator = tf + k1 * (1 - b + b * (docLength / max(snapshot.avgDocLength, 1)))
                score += idf * (denominator > 0 ? (numerator / denominator) : 0)
            }

            results.append((r, score))
        }

        return results
    }

    /// Reciprocal Rank Fusion over vector and keyword ranks
    func reciprocalRankFusion(
        vectorResults: [RetrievedChunk],
        keywordResults: [(chunk: RetrievedChunk, score: Float)],
        k: Int,
        vectorWeight: Float,
        keywordWeight: Float
    ) async -> [RetrievedChunk] {
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "reciprocalRankFusion", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "reciprocalRankFusion", signpostID: spid) }
        #endif
        guard !vectorResults.isEmpty else { return [] }

        // Scores keyed by chunk id
        var scores: [UUID: Float] = [:]
        scores.reserveCapacity(vectorResults.count)

        // Vector ranks
        for (rank, r) in vectorResults.enumerated() {
            scores[r.chunk.id, default: 0] += vectorWeight / Float(k + rank + 1)
        }

        // Keyword ranks (sort desc by BM25 score)
        let sortedKeyword = keywordResults.sorted {
            // Deterministic total order; see HybridSearchService.byScoreThenId.
            $0.score != $1.score
                ? $0.score > $1.score
                : HybridSearchService.stableTieBreakKey($0.chunk) < HybridSearchService.stableTieBreakKey($1.chunk)
        }
        for (rank, pair) in sortedKeyword.enumerated() {
            scores[pair.chunk.chunk.id, default: 0] += keywordWeight / Float(k + rank + 1)
        }

        // Sort by fused score; include ALL candidates from BOTH vector and BM25 result sets.
        // Previously this only returned vectorResults, silently dropping BM25-only candidates.
        // True RRF fuses the UNION of both sets — a document with exact keyword match but
        // low vector similarity must still be rankable.

        // Build lookup from vector results for metadata
        var vectorLookup: [UUID: RetrievedChunk] = [:]
        for r in vectorResults {
            vectorLookup[r.chunk.id] = r
        }

        // Build the full candidate set: all vector results + any BM25-only candidates
        var allCandidates: [RetrievedChunk] = vectorResults
        let existingIds = Set(vectorResults.map { $0.chunk.id })
        for pair in keywordResults {
            if !existingIds.contains(pair.chunk.chunk.id) {
                // BM25-only candidate — include with its BM25-derived similarity score
                allCandidates.append(pair.chunk)
            }
        }

        let ranked = allCandidates.sorted { (scores[$0.chunk.id] ?? 0) > (scores[$1.chunk.id] ?? 0) }
        return ranked
    }

    // MARK: - Private Helpers

    // Vector math helpers used by computeVectorSearch
    // SILICON-NATIVE: Modern vDSP API (replaces deprecated cblas_snrm2)
    private func computeNorm(_ vector: [Float]) -> Float {
        sqrt(vDSP.sumOfSquares(vector))
    }

    private func optimizedCosineSimilarity(_ a: [Float], _ b: [Float], queryNorm: Float, chunkNorm: Float) -> Float {
        guard a.count == b.count else { return 0 }
        // SILICON-NATIVE: Use vDSP_dotpr for hardware-accelerated dot product
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        let denom = queryNorm * chunkNorm
        return denom > 1e-9 ? dot / denom : 0
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        // SILICON-NATIVE: Delegate to accelerated version
        cosineSimilarityAccelerated(a, b)
    }

    // OPTIMIZED: Cached tokenizer instance to avoid allocation per tokenize() call.
    // NLTokenizer is lightweight but ~30-300 allocations per query adds up.
    private let cachedTokenizer = NLTokenizer(unit: .word)
    private let cachedLemmaTagger = NLTagger(tagSchemes: [.lemma])

    /// Tokenize text with lemmatization for BM25 scoring consistency.
    /// Matches HybridSearchService.BM25Scorer.tokenize() so inline BM25 in
    /// `bm25Scores()` produces identical term distributions.
    /// "running" → "run", "configurations" → "configuration"
    private func tokenize(_ text: String) -> [String] {
        let normalized = text.lowercased()
        cachedTokenizer.string = normalized
        cachedLemmaTagger.string = normalized
        return cachedTokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap { range in
            let token = String(normalized[range]).trimmingCharacters(in: .punctuationCharacters)
            guard !token.isEmpty else { return nil }
            // Lemmatize to match BM25Scorer: "running" → "run"
            if let lemma = cachedLemmaTagger.tag(at: range.lowerBound, unit: .word, scheme: .lemma).0?.rawValue,
               !lemma.isEmpty {
                return lemma
            }
            return token
        }
    }

    private func calculateKeywordMatch(query: String, content: String) -> Float {
        let queryTerms = Set(query.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 2 })
        let contentTerms = Set(content.lowercased().split(separator: " ").map { String($0) })
        let matches = queryTerms.intersection(contentTerms)
        return Float(matches.count) / Float(max(queryTerms.count, 1))
    }

    /// Calculate minimum span distance across ALL query terms, not just the first two.
    /// For a 5-term query, finds the smallest window containing all matched terms.
    private func calculateTermProximity(query: String, content: String) -> Float {
        let queryTerms = query.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 2 }
        let contentWords = content.lowercased().split(separator: " ").map { String($0) }
        guard queryTerms.count > 1 else { return 0 }

        var positions: [[Int]] = []
        positions.reserveCapacity(queryTerms.count)
        for term in queryTerms {
            let pos = contentWords.enumerated().compactMap { $0.element.contains(term) ? $0.offset : nil }
            positions.append(pos)
        }

        // Compute minimum span across ALL query terms (not just first two)
        // Uses a sliding window approach: for each position of term[0],
        // find the closest position of every other term and compute the span.
        let matchedPositions = positions.filter { !$0.isEmpty }
        guard matchedPositions.count >= 2 else { return 0 }

        var minSpan = Int.max
        // For each position in the first matched term's list
        for anchor in matchedPositions[0] {
            var windowMin = anchor
            var windowMax = anchor
            var allFound = true
            // Find closest position in each other term's position list
            for termIdx in 1..<matchedPositions.count {
                let termPositions = matchedPositions[termIdx]
                // Binary-search-style: find closest to anchor
                var closest = Int.max
                for pos in termPositions {
                    if abs(pos - anchor) < abs(closest - anchor) {
                        closest = pos
                    }
                }
                if closest == Int.max {
                    allFound = false
                    break
                }
                windowMin = min(windowMin, closest)
                windowMax = max(windowMax, closest)
            }
            if allFound {
                minSpan = min(minSpan, windowMax - windowMin)
            }
        }
        return minSpan == Int.max ? 0 : 1.0 / Float(minSpan + 1)
    }

    private func computeMetadataBoost(
        chunk: RetrievedChunk,
        queryTerms: Set<String>,
        hasDigits: Bool,
        wantsSteps: Bool
    ) -> Float {
        var boost: Float = 0
        let metadata = chunk.chunk.metadata

        if hasDigits, metadata.hasNumericData {
            boost += 0.04
        }

        if wantsSteps, metadata.hasListStructure {
            boost += 0.04
        }

        if let sectionTitle = metadata.sectionTitle?.lowercased() {
            if queryTerms.contains(where: { sectionTitle.contains($0) }) {
                boost += 0.04
            }
        }

        if !metadata.keywords.isEmpty, !queryTerms.isEmpty {
            let keywordSet = Set(metadata.keywords.map { $0.lowercased() })
            let overlap = keywordSet.intersection(queryTerms).count
            if overlap > 0 {
                boost += min(0.08, Float(overlap) * 0.02)
            }
        }

        return boost
    }

    /// Detect table-of-contents or index-style chunks that match keywords but lack actual content
    /// Returns a penalty score (0.0 = normal content, up to 0.5 = definitely TOC/index)
    private func computeTOCPenalty(content: String) -> Float {
        var penalty: Float = 0
        let wordCount = content.split(separator: " ").count
        guard wordCount > 10 else { return 0 }  // Too short to analyze

        // Pattern 1: Many section numbers like "1.1.", "2.3.", "3.4.5." etc.
        // TOC pages have dense section numbering
        let sectionMatches = Self.sectionNumberRegex.map { content.matches(of: $0) } ?? []
        if sectionMatches.count >= 8 {
            penalty += 0.18  // Strong indicator of TOC
        } else if sectionMatches.count >= 5 {
            penalty += 0.10
        }

        // Pattern 2: Page numbers scattered - multiple formats:
        // "...45", ".....23", ". 52", "49 ...", standalone 2-digit numbers
        let pageMatches1 = Self.pageNumberRegex1.map { content.matches(of: $0) } ?? []  // ...45, .....23
        let pageMatches2 = Self.pageNumberRegex2.map { content.matches(of: $0) } ?? []  // . 52, . 49
        let pageMatches3 = Self.pageNumberRegex3.map { content.matches(of: $0) } ?? []  // 49 ..., 50 ...
        let totalPageMatches = pageMatches1.count + pageMatches2.count + pageMatches3.count
        if totalPageMatches >= 5 {
            penalty += 0.18  // Very strong TOC indicator
        } else if totalPageMatches >= 3 {
            penalty += 0.12
        }

        // Pattern 3: High density of standalone 2-digit numbers (page references)
        // TOC has many "45", "52", "53" etc. scattered throughout
        // NOTE: Swift Regex doesn't support lookbehind, so we use word boundaries
        // and filter in code instead
        let standaloneMatches = Self.standaloneNumberRegex.map { content.matches(of: $0) } ?? []
        // Filter out numbers that are part of decimals or larger numbers
        let filteredNumberCount = standaloneMatches.filter { match in
            let matchRange = match.range
            // Check character before (if exists) isn't a dot or digit
            if matchRange.lowerBound > content.startIndex {
                let beforeIdx = content.index(before: matchRange.lowerBound)
                let beforeChar = content[beforeIdx]
                if beforeChar == "." || beforeChar.isNumber { return false }
            }
            // Check character after (if exists) isn't a dot or digit
            if matchRange.upperBound < content.endIndex {
                let afterChar = content[matchRange.upperBound]
                if afterChar == "." || afterChar.isNumber { return false }
            }
            return true
        }.count
        let numberDensity = Float(filteredNumberCount) / Float(wordCount)
        if filteredNumberCount >= 8 && numberDensity > 0.04 {
            penalty += 0.15  // High density of page-like numbers
        }

        // Pattern 4: High ratio of "?" markers (FAQ-style TOC)
        let questionCount = content.components(separatedBy: "?").count - 1
        if wordCount > 0 && Float(questionCount) / Float(wordCount) > 0.03 && questionCount >= 4 {
            penalty += 0.10
        }

        // Pattern 5: Very short average sentence length (typical of headings/TOC entries)
        let sentences = content.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if sentences.count >= 6 {
            let avgWordsPerSentence = Float(wordCount) / Float(sentences.count)
            if avgWordsPerSentence < 5 {
                penalty += 0.12  // Very short "sentences" = likely headings
            } else if avgWordsPerSentence < 7 {
                penalty += 0.06
            }
        }

        // Pattern 6: Contains explicit TOC markers
        let lowerContent = content.lowercased()
        if lowerContent.contains("table of contents")
            || (lowerContent.contains("contents") && lowerContent.contains("page"))
            || lowerContent.hasPrefix("content\n")
        {
            penalty += 0.15
        }

        // Pattern 7: High ratio of bullet points / list markers in short content
        // TOC often has • or - at start of many lines
        let bulletCount = content.components(separatedBy: "•").count - 1
            + content.components(separatedBy: "\n-").count - 1
            + content.components(separatedBy: "\n*").count - 1
        if bulletCount >= 6 && Float(bulletCount) / Float(sentences.count) > 0.4 {
            penalty += 0.08
        }

        return min(penalty, 0.50)  // Cap penalty at 0.50
    }

    /// Demote chunks that mainly list example questions rather than answering the current one.
    private func computeQuestionBankPenalty(content: String, query: String) -> Float {
        let normalizedContent = content.lowercased()
        let normalizedQuery = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalizedContent.isEmpty,
              !normalizedQuery.isEmpty,
              !querySeeksExampleQuestions(normalizedQuery)
        else {
            return 0
        }

        var penalty: Float = 0
        let markerPhrases = [
            "questions like",
            "what kinds of questions",
            "what kind of questions",
            "example questions",
            "strongest on questions",
            "strongest with questions",
            "good at answering questions"
        ]

        let markerHits = markerPhrases.reduce(into: 0) { count, phrase in
            if normalizedContent.contains(phrase) {
                count += 1
            }
        }

        if markerHits >= 2 {
            penalty += 0.18
        } else if markerHits == 1 {
            penalty += 0.10
        }

        if normalizedQuery.count >= 18, normalizedContent.contains(normalizedQuery) {
            penalty += markerHits > 0 ? 0.18 : 0.08
        }

        let exampleQuestionLineCount = countExampleQuestionLines(in: content)
        if exampleQuestionLineCount >= 3 {
            penalty += 0.14
        } else if exampleQuestionLineCount >= 2 {
            penalty += 0.08
        }

        let questionMarkCount = content.filter { $0 == "?" }.count
        if questionMarkCount >= 4 {
            penalty += 0.08
        } else if questionMarkCount >= 2, markerHits > 0 {
            penalty += 0.04
        }

        return min(penalty, 0.40)
    }

    private func querySeeksExampleQuestions(_ normalizedQuery: String) -> Bool {
        let phrases = [
            "example questions",
            "what kinds of questions",
            "what kind of questions",
            "what questions",
            "good at answering",
            "good at",
            "can i ask",
            "should i ask"
        ]

        if phrases.contains(where: { normalizedQuery.contains($0) }) {
            return normalizedQuery.contains("question") || normalizedQuery.contains("ask")
        }

        return false
    }

    private func countExampleQuestionLines(in content: String) -> Int {
        content
            .components(separatedBy: .newlines)
            .reduce(into: 0) { count, line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }

                let isBullet = trimmed.hasPrefix("-") || trimmed.hasPrefix("•") || trimmed.hasPrefix("*")
                let containsQuestion = trimmed.contains("?")
                let containsQuote = trimmed.contains("\"") || trimmed.contains("“") || trimmed.contains("”")

                if isBullet && containsQuestion && containsQuote {
                    count += 1
                }
            }
    }

    // MARK: - Core ML Cross Encoder Re-Ranking

    #if canImport(CoreML)
        private func rerankWithCrossEncoder(
            chunks: [RetrievedChunk],
            query: String,
            topK: Int,
            model: MLModel,
            tokenizer: Tokenizer
        ) async -> [RetrievedChunk] {
            let cappedTopK = min(topK, chunks.count)
            let maxLen = 512

            // Special Token IDs
            let padId = tokenizer.convertTokenToId("[PAD]") ?? 0

            // OPTIMIZATION: Pre-tokenize ALL chunks upfront (CPU-bound, fast)
            // This amortizes tokenizer overhead and enables concurrent prediction
            struct TokenizedInput: Sendable {
                let chunkIndex: Int
                let inputIds: [Int]
                let attentionMask: [Int]
                let tokenTypes: [Int]
            }

            var tokenizedInputs: [TokenizedInput] = []
            tokenizedInputs.reserveCapacity(chunks.count)

            for (idx, r) in chunks.enumerated() {
                // Include contextual prefix for cross-encoder (Anthropic's Contextual Retrieval)
                let docText = (r.chunk.contextualPrefix ?? "") + r.chunk.content
                
                var encoding: TokenizerEncoding
                do {
                    encoding = try tokenizer.encodeWithMetadata(text: query, textPair: docText, addSpecialTokens: true, offsetUnit: .utf8)
                } catch {
                    continue
                }

                var inputIds = encoding.tokenIds
                var tokenTypes = encoding.tokenTypeIds
                var attentionMask = encoding.attentionMask

                if inputIds.count > maxLen {
                    inputIds = Array(inputIds.prefix(maxLen))
                    tokenTypes = Array(tokenTypes.prefix(maxLen))
                    attentionMask = Array(attentionMask.prefix(maxLen))
                } else if inputIds.count < maxLen {
                    let padLen = maxLen - inputIds.count
                    inputIds.append(contentsOf: Array(repeating: padId, count: padLen))
                    attentionMask.append(contentsOf: Array(repeating: 0, count: padLen))
                    tokenTypes.append(contentsOf: Array(repeating: 0, count: padLen))
                }

                tokenizedInputs.append(TokenizedInput(
                    chunkIndex: idx,
                    inputIds: inputIds,
                    attentionMask: attentionMask,
                    tokenTypes: tokenTypes
                ))
            }

            // OPTIMIZATION: Concurrent predictions using TaskGroup
            // Cross-encoder MLModel.prediction is thread-safe — CoreML handles internal synchronization.
            // Device-tier-aware concurrency prevents ANE/GPU contention.
            let maxConcurrentPredictions = await min(4, max(2, DeviceCapabilityService.shared.embeddingConcurrency / 4))

            // Extracted prediction closure — shared by seed and feed paths to avoid code duplication.
            // Each invocation creates its own MLMultiArray buffers (no sharing between tasks).
            let runPrediction: @Sendable (TokenizedInput) async -> (Int, Float)? = { input in
                do {
                    let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
                    let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
                    let tokenTypeArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)

                    // Bulk copy using dataPointer for 3x faster writes vs NSNumber subscript
                    let inputPtr = inputIdsArray.dataPointer.bindMemory(to: Int32.self, capacity: maxLen)
                    let maskPtr = maskArray.dataPointer.bindMemory(to: Int32.self, capacity: maxLen)
                    let tokenPtr = tokenTypeArray.dataPointer.bindMemory(to: Int32.self, capacity: maxLen)
                    for i in 0 ..< maxLen {
                        inputPtr[i] = Int32(input.inputIds[i])
                        maskPtr[i] = Int32(input.attentionMask[i])
                        tokenPtr[i] = Int32(input.tokenTypes[i])
                    }

                    let inputs = try MLDictionaryFeatureProvider(dictionary: [
                        "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                        "attention_mask": MLFeatureValue(multiArray: maskArray),
                        "token_type_ids": MLFeatureValue(multiArray: tokenTypeArray),
                    ])

                    let output = try await model.prediction(from: inputs)

                    var score: Float = 0
                    if let logits = output.featureValue(for: "logits")?.multiArrayValue {
                        let count = logits.count
                        if count >= 1 {
                            let val0 = logits[0].floatValue
                            if count == 1 {
                                score = val0
                            } else {
                                let val1 = logits[1].floatValue
                                let e0 = exp(val0)
                                let e1 = exp(val1)
                                score = e1 / (e0 + e1)
                            }
                        }
                    }
                    return (input.chunkIndex, score)
                } catch {
                    Log.error("[RAGEngine] Re-ranking inference failed for chunk \(input.chunkIndex): \(error)", category: .retrieval)
                    return nil
                }
            }

            let scored: [(index: Int, score: Float)] = await withTaskGroup(
                of: (Int, Float)?.self,
                returning: [(Int, Float)].self
            ) { group in
                var inputIterator = tokenizedInputs.makeIterator()
                var results: [(Int, Float)] = []
                results.reserveCapacity(chunks.count)

                // Seed initial batch
                for _ in 0 ..< maxConcurrentPredictions {
                    guard let input = inputIterator.next() else { break }
                    group.addTask { [input] in await runPrediction(input) }
                }

                // Process results and feed new tasks (bounded concurrency)
                for await result in group {
                    if let r = result {
                        results.append(r)
                    }
                    // Feed next input — maintains maxConcurrentPredictions in flight
                    if let input = inputIterator.next() {
                        group.addTask { [input] in await runPrediction(input) }
                    }
                }
                return results
            }

            // Reconstruct scored chunks in score-descending order
            var scoredChunks = scored.map { (chunk: chunks[$0.index], score: $0.score) }
            scoredChunks.sort { $0.score > $1.score }

            // MS-MARCO cross-encoders output unbounded relevance scores (e.g., -10 to +10).
            // These are meant for ranking, not as probabilities.
            // We normalize to [0,1] using min-max normalization within the batch,
            // which preserves ranking order while matching downstream score thresholds.

            // Min-max normalize scores to [0,1] range
            let rawScores = scoredChunks.map { $0.score }
            let minScore = rawScores.min() ?? 0
            let maxScore = rawScores.max() ?? 1
            let scoreRange = maxScore - minScore

            // If all scores are identical, assign uniform normalized score
            let normalizedScored: [(chunk: RetrievedChunk, score: Float)]
            if scoreRange < 0.0001 {
                normalizedScored = scoredChunks.map { ($0.chunk, Float(0.5)) }
            } else {
                normalizedScored = scoredChunks.map { item in
                    // Normalize to [0.1, 0.9] to avoid extreme values
                    let normalized = 0.1 + 0.8 * (item.score - minScore) / scoreRange
                    return (item.chunk, normalized)
                }
            }

            if let top = normalizedScored.first, let bottom = normalizedScored.last {
                let rawTop = scoredChunks.first?.score ?? 0
                let rawBottom = scoredChunks.last?.score ?? 0
                Log.debug("[RAGEngine] AI Re-ranking: raw \(String(format: "%.2f", rawBottom))→\(String(format: "%.2f", rawTop)), normalized \(String(format: "%.2f", bottom.score))→\(String(format: "%.2f", top.score))", category: .retrieval)
                // Log top chunk preview for debugging retrieval quality
                let previewSource = top.chunk.chunk.parentContent ?? top.chunk.chunk.content
                let preview = String(previewSource.prefix(150)).replacingOccurrences(of: "\n", with: " ")
                Log.debug("[RAGEngine] Top chunk preview: \(preview)...", category: .retrieval)
            }

            // Apply TOC/boilerplate penalty after cross-encoder scoring
            // This demotes table-of-contents chunks that match keywords but lack actual content
            let penalizedScored = normalizedScored.map { item -> (chunk: RetrievedChunk, score: Float) in
                let contentForPenalty = item.chunk.chunk.parentContent ?? item.chunk.chunk.content
                let tocPenalty = computeTOCPenalty(content: contentForPenalty)
                let questionBankPenalty = computeQuestionBankPenalty(content: contentForPenalty, query: query)
                let adjustedScore = max(0.01, item.score - tocPenalty - questionBankPenalty)
                return (item.chunk, adjustedScore)
            }.sorted { $0.score > $1.score }

            return penalizedScored.prefix(cappedTopK).map { scoredItem in
                // Propagate cross-encoder score to the chunk so downstream sorting preserves re-ranking order
                RetrievedChunk(
                    chunk: scoredItem.chunk.chunk,
                    similarityScore: scoredItem.score,
                    rank: scoredItem.chunk.rank,
                    sourceDocument: scoredItem.chunk.sourceDocument,
                    pageNumber: scoredItem.chunk.pageNumber
                )
            }
        }
    #endif
}
