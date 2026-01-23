//
//  RAGEngine.swift
//  OpenIntelligence
//
//  Background actor for pure, CPU-heavy RAG computations
//  - Offloads MMR selection and context assembly off the main actor
//  - Avoids touching UI or main-actor–isolated services
//

import Foundation
import NaturalLanguage
import Accelerate
import CoreML
import Tokenizers

#if DEBUG
    import os.signpost
#endif

/// Background executor for pure RAG computations (no UI/IO access)
actor RAGEngine {
    // MARK: - Shared Instance

    /// Shared singleton to avoid repeated model loading
    static let shared = RAGEngine()

    // MARK: - Properties

    #if canImport(CoreML)
        private var rerankerModel: MLModel?
    #endif

    private var rerankerTokenizer: BertTokenizer?
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
            if let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = .all
                    config.allowLowPrecisionAccumulationOnGPU = true
                    self.rerankerModel = try MLModel(contentsOf: url, configuration: config)
                    Log.info("[RAGEngine] Loaded ReRankerModel.mlmodelc", category: .retrieval)
                } catch {
                    Log.error("[RAGEngine] Failed to load ReRanker: \(error)", category: .retrieval)
                }
            } else if let sourceURL = Bundle.main.url(forResource: modelName, withExtension: "mlpackage") {
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
        if let url = Bundle.main.url(forResource: "reranker_vocab", withExtension: "json") {
            do {
                let vocabData = try Data(contentsOf: url)
                let vocabDict = try JSONDecoder().decode([String: Int].self, from: vocabData)
                self.rerankerTokenizer = BertTokenizer(vocab: vocabDict, merges: nil, tokenizeChineseChars: true, doLowerCase: true)
                Log.info("[RAGEngine] Loaded ReRanker Tokenizer", category: .retrieval)
            } catch {
                Log.error("[RAGEngine] Failed to load ReRanker Tokenizer: \(error)", category: .retrieval)
            }
        }
    }

    // MARK: - MMR (Maximal Marginal Relevance)

    /// Apply MMR to select diverse, non-redundant chunks
    /// Critical for comprehensive information coverage
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
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "applyMMR", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "applyMMR", signpostID: spid) }
        #endif
        guard !candidates.isEmpty else { return [] }
        guard topK > 1 else { return Array(candidates.prefix(1)) }

        var selected: [RetrievedChunk] = []
        var remaining = candidates

        // Start with the most relevant chunk
        if let first = remaining.first {
            selected.append(first)
            remaining.removeFirst()
        }

        // Iteratively select chunks that maximize: λ * relevance - (1-λ) * max_similarity_to_selected
        while selected.count<topK, !remaining.isEmpty {
            if Task.isCancelled { return selected }

            var bestScore: Float = -.infinity
            var bestIndex = 0

            for (index, candidate) in remaining.enumerated() {
                // Relevance to query (use stored similarity score)
                let relevance = candidate.similarityScore

                // Max similarity to already selected chunks (diversity penalty)
                // SILICON-NATIVE: Use vDSP-accelerated cosine similarity
                var maxSimilarityToSelected: Float = 0
                for selectedChunk in selected {
                    let similarity = cosineSimilarityAccelerated(
                        candidate.chunk.embedding,
                        selectedChunk.chunk.embedding
                    )
                    maxSimilarityToSelected = max(maxSimilarityToSelected, similarity)
                }

                // MMR score: balance relevance and diversity
                let mmrScore = lambda * relevance - (1 - lambda) * maxSimilarityToSelected

                if mmrScore > bestScore {
                    bestScore = mmrScore
                    bestIndex = index
                }
            }

            // Add best chunk and remove from candidates
            let chosen = remaining.remove(at: bestIndex)
            selected.append(chosen)
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
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "rerank", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "rerank", signpostID: spid) }
        #endif
        guard !chunks.isEmpty else { return [] }

        // Limit to top 50 candidates before cross-encoder scoring (perf safeguard)
        let candidateChunks = Array(chunks.prefix(50))

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
            score += keywordBoost * 0.6 // Boosted from 0.2 to prioritize exact keyword matches

            let proximityBoost = calculateTermProximity(query: query, content: r.chunk.content)
            score += proximityBoost * 0.4 // Boosted from 0.15 to favor phrases like "press button"

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
    ) async -> (context: String, used: Int) {
        #if DEBUG
            let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
            let spid = OSSignpostID(log: log)
            os_signpost(.begin, log: log, name: "assembleContext", signpostID: spid)
            defer { os_signpost(.end, log: log, name: "assembleContext", signpostID: spid) }
        #endif
        guard !chunks.isEmpty else { return ("", 0) }

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

        // Calculate target chars per chunk to fit at least 3 chunks
        // This prevents the "1 giant chunk" problem where context is too narrow
        let minChunksTarget = min(3, orderedChunks.count)
        let headerOverhead = compact ? 30 : 80  // Approximate header + separator size
        let targetCharsPerChunk = max(400, (maxChars - (minChunksTarget * headerOverhead)) / minChunksTarget)

        for (i, r) in orderedChunks.enumerated() {

            if Task.isCancelled { break }
            if i % 16 == 0 { await Task.yield() }

            // Sanitize content to help Apple FM's language detector
            // URLs and special Unicode can confuse it into detecting wrong languages
            let content = r.chunk.parentContent ?? r.chunk.content
            let sanitizedContent = sanitizeForLanguageDetection(content)

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
                } else {
                    break
                }
            } else {
                break
            }
        }

        return (builder, used)
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

    /// Reorders chunks to mitigate "Lost in the Middle" attention patterns.
    /// Places most relevant chunks at start and end of context where LLMs attend best.
    /// Order: 1st, 3rd, 5th, ..., 6th, 4th, 2nd (interleaved from both ends)
    private func applyLostInMiddleReordering(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        guard chunks.count >= 4 else { return chunks }

        var result: [RetrievedChunk] = []
        result.reserveCapacity(chunks.count)

        // Split into two halves
        let midpoint = chunks.count / 2
        let firstHalf = Array(chunks.prefix(midpoint))
        let secondHalf = Array(chunks.suffix(from: midpoint))

        // Interleave: odd positions from first half, even positions from second half (reversed)
        var frontIdx = 0
        var backIdx = secondHalf.count - 1

        for i in 0 ..< chunks.count {
            if i % 2 == 0 {
                // Even position: take from front (highest relevance)
                if frontIdx < firstHalf.count {
                    result.append(firstHalf[frontIdx])
                    frontIdx += 1
                } else if backIdx >= 0 {
                    result.append(secondHalf[backIdx])
                    backIdx -= 1
                }
            } else {
                // Odd position: take from back (placed near end for recency attention)
                if backIdx >= 0 {
                    result.append(secondHalf[backIdx])
                    backIdx -= 1
                } else if frontIdx < firstHalf.count {
                    result.append(firstHalf[frontIdx])
                    frontIdx += 1
                }
            }
        }

        return result
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

                // BM25 with k1=1.5, b=0.75 (from scorer)
                let k1: Float = 1.5
                let b: Float = 0.75
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
        let sortedKeyword = keywordResults.sorted { $0.score > $1.score }
        for (rank, pair) in sortedKeyword.enumerated() {
            scores[pair.chunk.chunk.id, default: 0] += keywordWeight / Float(k + rank + 1)
        }

        // Sort by fused score; preserve only candidates present in vectorResults (current design)
        let ranked = vectorResults.sorted { (scores[$0.chunk.id] ?? 0) > (scores[$1.chunk.id] ?? 0) }
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

    // Tokenizer used for BM25 scoring
    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        let normalized = text.lowercased()
        tokenizer.string = normalized
        return tokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap { range in
            let token = String(normalized[range]).trimmingCharacters(in: .punctuationCharacters)
            return token.isEmpty ? nil : token
        }
    }

    private func calculateKeywordMatch(query: String, content: String) -> Float {
        let queryTerms = Set(query.lowercased().split(separator: " ").map { String($0) }.filter { $0.count > 2 })
        let contentTerms = Set(content.lowercased().split(separator: " ").map { String($0) })
        let matches = queryTerms.intersection(contentTerms)
        return Float(matches.count) / Float(max(queryTerms.count, 1))
    }

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

        var minDistance = Int.max
        if positions.allSatisfy({ !$0.isEmpty }) {
            for i in 0 ..< (positions[0].count) {
                for j in 0 ..< (positions[1].count) {

                    let distance = abs(positions[0][i] - positions[1][j])
                    minDistance = min(minDistance, distance)
                }
            }
        }
        return minDistance == Int.max ? 0 : 1.0 / Float(minDistance + 1)
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

    // MARK: - Core ML Cross Encoder Re-Ranking

    #if canImport(CoreML)
        private func rerankWithCrossEncoder(
            chunks: [RetrievedChunk],
            query: String,
            topK: Int,
            model: MLModel,
            tokenizer: BertTokenizer
        ) async -> [RetrievedChunk] {
            var scored: [(chunk: RetrievedChunk, score: Float)] = []
            let cappedTopK = min(topK, chunks.count)
            let maxLen = 512

            // Prepare query tokens once
            let queryTokens = tokenizer.tokenize(text: query)
            let queryIds = tokenizer.convertTokensToIds(queryTokens).compactMap { $0 }

            // Special Token IDs
            let clsId = tokenizer.convertTokenToId("[CLS]") ?? 101
            let sepId = tokenizer.convertTokenToId("[SEP]") ?? 102
            let padId = tokenizer.convertTokenToId("[PAD]") ?? 0

            for (idx, r) in chunks.enumerated() {
                if Task.isCancelled { break }
                if idx % 8 == 0 { await Task.yield() }

                // Include contextual prefix for cross-encoder (Anthropic's Contextual Retrieval)
                // This helps the re-ranker understand document context when scoring relevance
                let docText = (r.chunk.contextualPrefix ?? "") + r.chunk.content
                let docTokens = tokenizer.tokenize(text: docText)
                let docIds = tokenizer.convertTokensToIds(docTokens).compactMap { $0 }

                // Build sequence: [CLS] Q [SEP] D [SEP]
                // Calculate available space for D
                let fixedCount = 3 + queryIds.count // [CLS] + Q + [SEP] + [SEP]
                let availableForDoc = maxLen - fixedCount
                let truncatedDocIds = Array(docIds.prefix(max(0, availableForDoc)))

                var inputIds: [Int] = []
                inputIds.append(clsId)
                inputIds.append(contentsOf: queryIds)
                inputIds.append(sepId)
                inputIds.append(contentsOf: truncatedDocIds)
                inputIds.append(sepId)

                // Token Types: 0 for Q, 1 for D
                var tokenTypes: [Int] = []
                tokenTypes.append(contentsOf: Array(repeating: 0, count: 2 + queryIds.count)) // [CLS] Q [SEP]
                tokenTypes.append(contentsOf: Array(repeating: 1, count: 1 + truncatedDocIds.count)) // D [SEP]

                var attentionMask = Array(repeating: 1, count: inputIds.count)

                // Padding
                let padLen = maxLen - inputIds.count
                if padLen > 0 {
                    inputIds.append(contentsOf: Array(repeating: padId, count: padLen))
                    attentionMask.append(contentsOf: Array(repeating: 0, count: padLen))
                    tokenTypes.append(contentsOf: Array(repeating: 0, count: padLen))
                }

                do {
                    let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
                    let maskArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)
                    let tokenTypeArray = try MLMultiArray(shape: [1, NSNumber(value: maxLen)], dataType: .int32)

                    // Copy to MultiArray
                    for i in 0 ..< maxLen {
                        inputIdsArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: inputIds[i])
                        maskArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: attentionMask[i])
                        tokenTypeArray[[0, NSNumber(value: i)] as [NSNumber]] = NSNumber(value: tokenTypes[i])
                    }

                    let inputs = try MLDictionaryFeatureProvider(dictionary: [
                        "input_ids": MLFeatureValue(multiArray: inputIdsArray),
                        "attention_mask": MLFeatureValue(multiArray: maskArray),
                        "token_type_ids": MLFeatureValue(multiArray: tokenTypeArray),
                    ])

                    let output = try await model.prediction(from: inputs)

                    // Extract Score - handle different MLMultiArray data types
                    var score: Float = 0
                    if let logits = output.featureValue(for: "logits")?.multiArrayValue {
                        // Extract values handling different data types
                        let count = logits.count
                        if count >= 1 {
                            // Use subscript access which handles type conversion
                            let val0 = logits[0].floatValue
                            if count == 1 {
                                // MS-MARCO models output unbounded relevance scores.
                                // We'll use min-max normalization later to scale to [0,1].
                                score = val0
                            } else {
                                // Two logits (not-relevant, relevant): softmax to get P(relevant)
                                let val1 = logits[1].floatValue
                                let e0 = exp(val0)
                                let e1 = exp(val1)
                                score = e1 / (e0 + e1)
                            }
                        }
                    }

                    scored.append((r, score))

                } catch {
                    Log.error("[RAGEngine] Re-ranking inference failed: \(error)", category: .retrieval)
                }
            }

            // MS-MARCO cross-encoders output unbounded relevance scores (e.g., -10 to +10).
            // These are meant for ranking, not as probabilities.
            // We normalize to [0,1] using min-max normalization within the batch,
            // which preserves ranking order while matching downstream score thresholds.
            scored.sort { $0.score > $1.score }

            // Min-max normalize scores to [0,1] range
            let rawScores = scored.map { $0.score }
            let minScore = rawScores.min() ?? 0
            let maxScore = rawScores.max() ?? 1
            let scoreRange = maxScore - minScore

            // If all scores are identical, assign uniform normalized score
            let normalizedScored: [(chunk: RetrievedChunk, score: Float)]
            if scoreRange < 0.0001 {
                normalizedScored = scored.map { ($0.chunk, Float(0.5)) }
            } else {
                normalizedScored = scored.map { item in
                    // Normalize to [0.1, 0.9] to avoid extreme values
                    let normalized = 0.1 + 0.8 * (item.score - minScore) / scoreRange
                    return (item.chunk, normalized)
                }
            }

            if let top = normalizedScored.first, let bottom = normalizedScored.last {
                let rawTop = scored.first?.score ?? 0
                let rawBottom = scored.last?.score ?? 0
                Log.debug("[RAGEngine] AI Re-ranking: raw \(String(format: "%.2f", rawBottom))→\(String(format: "%.2f", rawTop)), normalized \(String(format: "%.2f", bottom.score))→\(String(format: "%.2f", top.score))", category: .retrieval)
                // Log top chunk preview for debugging retrieval quality
                let preview = String(top.chunk.chunk.content.prefix(150)).replacingOccurrences(of: "\n", with: " ")
                Log.debug("[RAGEngine] Top chunk preview: \(preview)...", category: .retrieval)
            }

            return normalizedScored.prefix(cappedTopK).map { scoredItem in
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
