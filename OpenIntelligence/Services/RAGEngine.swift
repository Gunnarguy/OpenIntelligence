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
#if DEBUG
import os.signpost
#endif

/// Background executor for pure RAG computations (no UI/IO access)
actor RAGEngine {
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
        queryEmbedding: [Float],
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
        while selected.count < topK && !remaining.isEmpty {
            if Task.isCancelled { return selected }

            var bestScore: Float = -.infinity
            var bestIndex = 0

            for (index, candidate) in remaining.enumerated() {
                // Relevance to query (use stored similarity score)
                let relevance = candidate.similarityScore

                // Max similarity to already selected chunks (diversity penalty)
                var maxSimilarityToSelected: Float = 0
                for selectedChunk in selected {
                    let similarity = cosineSimilarity(
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

    /// Calculate cosine similarity between two embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }

        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }

        let denom = sqrt(magnitudeA) * sqrt(magnitudeB)
        return denom > 0 ? dotProduct / denom : 0
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
            builder += retrieved.chunk.content

            if index != chunks.count - 1 {
                builder += "\n\n---\n\n"
            }
        }

        return builder
    }

    // MARK: - Re-ranking and Context Utilities

    /// Re-rank results using multiple signals (semantic, keyword, proximity, position)
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

        // Build scored tuples
        var scored: [(chunk: RetrievedChunk, score: Float, keyword: Float, proximity: Float)] = []
        scored.reserveCapacity(chunks.count)

        for (i, r) in chunks.enumerated() {
            if Task.isCancelled { return Array(chunks.prefix(topK)) }
            if i % 16 == 0 { await Task.yield() }

            var score = r.similarityScore

            let keywordBoost = calculateKeywordMatch(query: query, content: r.chunk.content)
            score += keywordBoost * 0.2

            let proximityBoost = calculateTermProximity(query: query, content: r.chunk.content)
            score += proximityBoost * 0.15

            let chunkIndex = r.chunk.metadata.chunkIndex
            let positionScore = 1.0 / Float(chunkIndex + 10)
            score += positionScore * 0.05

            scored.append((r, score, keywordBoost, proximityBoost))
        }

        // Sort by rerank score desc
        scored.sort { $0.score > $1.score }

        if scored.count > 0 {
            // keep debug parity with existing logs
            let top = scored[0]
            print("   ✅ Re-ranking complete. Top score: \(String(format: "%.4f", top.score))")
            print("   📊 Score breakdown:")
            print("      - Semantic: \(String(format: "%.3f", top.chunk.similarityScore))")
            print("      - Keywords: \(String(format: "%.3f", top.keyword))")
            print("      - Proximity: \(String(format: "%.3f", top.proximity))")
        }

        return Array(scored.prefix(topK)).map { $0.chunk }
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
    func assembleContext(
        chunks: [RetrievedChunk],
        maxChars: Int
    ) async -> (context: String, used: Int) {
#if DEBUG
    let log = OSLog(subsystem: "OpenIntelligence", category: "RAGEngine")
        let spid = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: "assembleContext", signpostID: spid)
        defer { os_signpost(.end, log: log, name: "assembleContext", signpostID: spid) }
#endif
        guard !chunks.isEmpty else { return ("", 0) }

        var builder = String()
        builder.reserveCapacity(min(maxChars, 4096))
        var used = 0

        for (i, r) in chunks.enumerated() {
            if Task.isCancelled { break }
            if i % 16 == 0 { await Task.yield() }

            let header = "[Document Chunk \(i + 1), Similarity: \(String(format: "%.3f", r.similarityScore))]\n"
            let block = header + r.chunk.content + (i != chunks.count - 1 ? "\n\n---\n\n" : "")
            if builder.count + block.count <= maxChars || used == 0 {
                builder += block
                used += 1
            } else {
                break
            }
        }

        return (builder, used)
    }

    /// Compute confidence score and quality warnings (off-main)
    func assessResponseQuality(
        chunks: [RetrievedChunk],
        query: String,
        totalDocs: Int
    ) async -> (Float, [String]) {
        if Task.isCancelled { return (0.0, ["Cancelled"]) }
        await Task.yield()

        var warnings: [String] = []

        // Factor 1: Top similarity
        let topSimilarity = chunks.first?.similarityScore ?? 0
        if topSimilarity < 0.4 {
            warnings.append("Low relevance: Best match only \(String(format: "%.1f", topSimilarity * 100))% similar")
        } else if topSimilarity < 0.6 {
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
        if sourceCount == 1 && totalDocs > 1 {
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
    private func computeNorm(_ vector: [Float]) -> Float {
        var sum: Float = 0
        for v in vector { sum += v * v }
        return sqrt(sum)
    }

    private func optimizedCosineSimilarity(_ a: [Float], _ b: [Float], queryNorm: Float, chunkNorm: Float) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        for i in 0..<a.count { dot += a[i] * b[i] }
        let denom = queryNorm * chunkNorm
        return denom > 0 ? dot / denom : 0
    }

    private func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in 0..<a.count {
            let av = a[i]; let bv = b[i]
            dot += av * bv
            magA += av * av
            magB += bv * bv
        }
        let denom = sqrt(magA) * sqrt(magB)
        return denom > 0 ? dot / denom : 0
    }

    // Tokenizer used for BM25 scoring
    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text.lowercased()
        return tokenizer.tokens(for: text.startIndex..<text.endIndex).compactMap { range in
            let token = String(text[range]).trimmingCharacters(in: .punctuationCharacters)
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
            for i in 0..<(positions[0].count) {
                for j in 0..<(positions[1].count) {
                    let distance = abs(positions[0][i] - positions[1][j])
                    minDistance = min(minDistance, distance)
                }
            }
        }
        return minDistance == Int.max ? 0 : 1.0 / Float(minDistance + 1)
    }
}
