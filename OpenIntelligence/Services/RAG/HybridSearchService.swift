//
//  HybridSearchService.swift
//  OpenIntelligence
//
//  Hybrid search combining vector similarity and BM25 keyword matching.
//
//  ## Silicon-Native Vector Math
//
//  Uses Apple Accelerate framework for hardware-accelerated similarity:
//  - cblas_snrm2: L2 norm computation (AMX/Neural Engine)
//  - vDSP_dotpr: Dot product (Neural Engine optimized)
//
//  See: https://developer.apple.com/documentation/accelerate/vdsp
//       https://developer.apple.com/documentation/accelerate/blas
//

import Foundation
import NaturalLanguage
import Accelerate

/// Snapshot of BM25 corpus statistics for off-main scoring
struct BM25Snapshot: Sendable {
    let documentFrequencies: [String: Int]
    let avgDocLength: Float
    let totalDocuments: Int
}


/// BM25 (Best Matching 25) keyword scoring for hybrid search
class BM25Scorer {
    private let k1: Float = 1.5  // Term frequency saturation parameter
    private let b: Float = 0.75  // Length normalization parameter
    // OPTIMIZED: Cached tokenizer instead of allocating per tokenize() call
    private let cachedTokenizer = NLTokenizer(unit: .word)

    private var documentFrequencies: [String: Int] = [:]
    private var avgDocLength: Float = 0
    private var totalDocuments: Int = 0

    /// Index documents for BM25 scoring
    func indexDocuments(_ chunks: [DocumentChunk]) {
        totalDocuments = chunks.count
        var docLengths: [Float] = []
        var termDocCounts: [String: Set<UUID>] = [:]

        for chunk in chunks {
            let terms = tokenize(chunk.content)
            docLengths.append(Float(terms.count))

            // Count which documents contain each term
            let uniqueTerms = Set(terms)
            for term in uniqueTerms {
                termDocCounts[term, default: []].insert(chunk.id)
            }
        }

        // Calculate document frequencies and average length
        documentFrequencies = termDocCounts.mapValues { $0.count }
        avgDocLength = docLengths.reduce(0, +) / Float(max(totalDocuments, 1))
    }

    /// Calculate BM25 score for a query against a document
    func score(query: String, document: String) -> Float {
        return score(queryTerms: tokenize(query), document: document)
    }

    /// Calculate BM25 score for pre-tokenized query terms against a document.
    /// OPTIMIZED: Avoids re-tokenizing the same query for every candidate document.
    func score(queryTerms: [String], document: String) -> Float {
        let docTerms = tokenize(document)
        let docLength = Float(docTerms.count)

        // Count term frequencies in document
        var termFreqs: [String: Int] = [:]
        for term in docTerms {
            termFreqs[term, default: 0] += 1
        }

        var score: Float = 0
        for queryTerm in queryTerms {
            let tf = Float(termFreqs[queryTerm] ?? 0)
            let df = Float(documentFrequencies[queryTerm] ?? 1)

            // IDF (Inverse Document Frequency)
            let idf = log((Float(totalDocuments) - df + 0.5) / (df + 0.5) + 1)

            // BM25 formula
            let numerator = tf * (k1 + 1)
            let denominator = tf + k1 * (1 - b + b * (docLength / avgDocLength))

            score += idf * (numerator / denominator)
        }

        return score
    }

    func tokenize(_ text: String) -> [String] {
        let normalized = text.lowercased()
        cachedTokenizer.string = normalized

        return cachedTokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap {
            let token = String(normalized[$0]).trimmingCharacters(in: .punctuationCharacters)
            return token.isEmpty ? nil : token
        }
    }
}

extension BM25Scorer {
    /// Build a snapshot of current BM25 stats for use by RAGEngine
    func makeSnapshot() -> BM25Snapshot {
        return BM25Snapshot(
            documentFrequencies: documentFrequencies,
            avgDocLength: avgDocLength,
            totalDocuments: totalDocuments
        )
    }

    /// Build a BM25 snapshot from the provided candidate chunks.
    /// This is used when we haven't pre-indexed the entire corpus.
    func snapshot(from candidates: [RetrievedChunk]) -> BM25Snapshot {
        var termDocCounts: [String: Set<UUID>] = [:]
        var totalLen: Float = 0
        var docCount = 0

        for r in candidates {
            let terms = tokenize(r.chunk.content)
            totalLen += Float(terms.count)
            docCount += 1

            let uniqueTerms = Set(terms)
            for t in uniqueTerms {
                termDocCounts[t, default: []].insert(r.chunk.id)
            }
        }

        let df = termDocCounts.mapValues { $0.count }
        let avgLen = docCount > 0 ? totalLen / Float(docCount) : 0
        return BM25Snapshot(
            documentFrequencies: df,
            avgDocLength: avgLen,
            totalDocuments: docCount
        )
    }
}

/// Hybrid search combining vector similarity and BM25 keyword matching
class HybridSearchService {
    private let vectorDatabase: VectorDatabase
    private let bm25Scorer = BM25Scorer()
    private var engine: RAGEngine { RAGEngine.shared }
    // OPTIMIZED: Cached tokenizer for keyword extraction and BM25 scoring
    private let cachedTokenizer = NLTokenizer(unit: .word)

    // Fusion weights (can be tuned)
    private let vectorWeight: Float
    private let keywordWeight: Float

    init(vectorDatabase: VectorDatabase, vectorWeight: Float = 0.7, keywordWeight: Float = 0.3) {
        self.vectorDatabase = vectorDatabase
        self.vectorWeight = vectorWeight
        self.keywordWeight = keywordWeight
    }

    /// Index documents for hybrid search
    func indexChunks(_ chunks: [DocumentChunk]) async throws {
        // Index for BM25
        bm25Scorer.indexDocuments(chunks)

        // Store in vector database
        for chunk in chunks {
            try await vectorDatabase.store(chunk: chunk)
        }

        Log.debug("Indexed \(chunks.count) chunks for hybrid retrieval", category: .pipeline)
    }

    /// Perform hybrid search with reciprocal rank fusion
    /// - Parameters:
    ///   - query: The search query string (may include expansions for BM25)
    ///   - originalQuery: The user's original query (used for keyword boost & FTS5). Falls back to `query` if nil.
    ///   - embedding: Query embedding vector
    ///   - topK: Number of top results to return
    ///   - cachedChunks: Optional pre-fetched chunks to avoid re-loading allChunks() for lexical recall
    ///   - containerId: Optional container ID to enable FTS5-accelerated BM25 scoring
    func search(query: String, originalQuery: String? = nil, embedding: [Float], topK: Int, cachedChunks: [DocumentChunk]? = nil, containerId: UUID? = nil) async throws -> [RetrievedChunk] {
        let boostQuery = originalQuery ?? query
        // Auto-select FTS5 path if containerId provided and FTS5 data available
        if let cid = containerId, await isFTS5Available(containerId: cid) {
            Log.debug("[Hybrid] Using FTS5-accelerated BM25 for container \(cid)", category: .pipeline)
            return try await searchWithFTS5(query: query, originalQuery: boostQuery, embedding: embedding, topK: topK, containerId: cid)
        }

        Log.debug("Hybrid search starting (vector: \(vectorWeight), keyword: \(keywordWeight))", category: .pipeline)

        // 1. Vector search - retrieve more candidates for better coverage
        // ENHANCEMENT: Scale vector candidates with topK for large corpus support
        let vectorCandidateMultiplier = topK > 50 ? 2 : 3  // Less aggressive multiplier for large topK
        let vectorResults = try await vectorDatabase.search(embedding: embedding, topK: topK * vectorCandidateMultiplier)

        var candidatePool = vectorResults

        if shouldRunLexicalRecall(query: query, vectorCount: vectorResults.count, topK: topK) {
            // ENHANCEMENT: Scale lexical recall with topK for large corpus support
            // For 10,000-chunk corpus with topK=100, we want lexical recall of ~300-500
            let maxRecall = min(500, max(topK * 5, 100))  // Increased from 200/40 for large corpora
            let lexicalCandidates = try await lexicalRecallCandidates(
                query: query,
                embedding: embedding,
                maxCandidates: maxRecall,
                cachedChunks: cachedChunks
            )
            if !lexicalCandidates.isEmpty {
                let existing = Set(candidatePool.map { $0.chunk.id })
                let unique = lexicalCandidates.filter { !existing.contains($0.chunk.id) }
                if !unique.isEmpty {
                    candidatePool.append(contentsOf: unique)
                    Log.debug(
                        "Lexical recall added \(unique.count) candidates (max: \(maxRecall))",
                        category: .pipeline
                    )
                }
            }
        }

        let vectorRanked = reindex(
            candidatePool.sorted { $0.similarityScore > $1.similarityScore }
        )

        // 2. BM25 keyword search (off-main via RAGEngine)
        // Build a snapshot from current candidates to ensure valid DF/length stats
        let snapshot = bm25Scorer.snapshot(from: vectorRanked)
        let keywordResults = await engine.bm25Scores(
            query: query,
            candidates: vectorRanked,
            snapshot: snapshot
        )

        // 3. Reciprocal Rank Fusion (RRF) off-main
        let fusedResults = await engine.reciprocalRankFusion(
            vectorResults: vectorRanked,
            keywordResults: keywordResults,
            k: 60,  // RRF constant (standard value)
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        // 4. Apply EXACT KEYWORD MATCH BOOST
        // OPTIMIZED: Use original query for keyword boost, not expanded query.
        // Expanded query contains corpus terms ("vehicle", "indicator") that match
        // 284/300 chunks, making the boost meaningless.
        let boostedResults = applyKeywordMatchBoost(query: boostQuery, results: fusedResults)

        // 5. Apply STRUCTURE-AWARE BOOST for spec queries (iOS 26+ structured parsing)
        let structureBoostedResults = applyStructureTypeBoost(query: boostQuery, results: boostedResults)

        // 6. Take top K from boosted results and re-rank index
        let topResults = Array(structureBoostedResults.prefix(topK))

        Log.debug(
            "Hybrid fusion: \(topResults.count) results from \(vectorResults.count) vector + \(keywordResults.count) BM25",
            category: .pipeline
        )

        return reindex(topResults)
    }

    /// Boost chunks that contain EXACT matches of important query keywords.
    /// OPTIMIZED: Uses additive score adjustment instead of full re-sort.
    /// Previous full re-sort completely overrode RRF fusion — now keyword matches
    /// add 0.05 per match (0.10 for boundary matches), capped at 0.20.
    /// Strong enough to meaningfully elevate keyword-matching chunks while preserving RRF ordering.
    ///
    /// 10x: Uses DYNAMIC hit-rate filtering instead of hardcoded stopwords.
    /// Any keyword that matches >30% of candidate chunks has zero discriminative value
    /// (it's a corpus-common word for THIS document, regardless of domain) and gets
    /// zero boost. Works for any domain, any document, forever — no hardcoded lists.
    private func applyKeywordMatchBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryKeywords = extractImportantKeywords(from: query)
        guard !queryKeywords.isEmpty, !results.isEmpty else { return results }

        // DYNAMIC HIT-RATE FILTERING: For each keyword, count how many chunks contain it.
        // If >30% of chunks match, the keyword is corpus-common and boost is meaningless.
        // This replaces all hardcoded domain stopwords with a single universal rule.
        let hitRateThreshold = 0.30
        let totalChunks = Double(results.count)
        var discriminativeKeywords: [String] = []

        for keyword in queryKeywords {
            let hitCount = results.filter { $0.chunk.content.lowercased().contains(keyword) }.count
            let hitRate = Double(hitCount) / totalChunks
            if hitRate <= hitRateThreshold {
                discriminativeKeywords.append(keyword)
            } else {
                Log.debug("[Hybrid] Keyword '\(keyword)' hit \(Int(hitRate * 100))% of chunks — filtered as non-discriminative", category: .retrieval)
            }
        }

        guard !discriminativeKeywords.isEmpty else {
            Log.debug("[Hybrid] All keywords non-discriminative (>30% hit rate), skipping boost", category: .retrieval)
            return results
        }

        var boostedResults: [RetrievedChunk] = []
        var boostedCount = 0

        for result in results {
            let contentLower = result.chunk.content.lowercased()
            var matchCount = 0

            for keyword in discriminativeKeywords {
                if contentLower.contains(keyword) {
                    matchCount += 1
                    // Extra for exact word boundary matches
                    if contentLower.contains(" \(keyword) ") ||
                       contentLower.contains(" \(keyword).") ||
                       contentLower.contains(" \(keyword),") ||
                       contentLower.hasPrefix("\(keyword) ") ||
                       contentLower.hasSuffix(" \(keyword)") {
                        matchCount += 1
                    }
                }
            }

            if matchCount > 0 {
                let boost = min(0.20, Double(matchCount) * 0.05)
                let boosted = RetrievedChunk(
                    chunk: result.chunk,
                    similarityScore: result.similarityScore + Float(boost),
                    rank: result.rank,
                    sourceDocument: result.sourceDocument,
                    pageNumber: result.pageNumber
                )
                boostedResults.append(boosted)
                boostedCount += 1
            } else {
                boostedResults.append(result)
            }
        }

        boostedResults.sort { $0.similarityScore > $1.similarityScore }

        if boostedCount > 0 {
            Log.debug("[Hybrid] Keyword boost: \(boostedCount)/\(results.count) chunks boosted for discriminative keywords \(discriminativeKeywords) (filtered \(queryKeywords.count - discriminativeKeywords.count) non-discriminative)", category: .retrieval)
        }

        return boostedResults
    }

    /// Boost table/list chunks when query seeks specific data (domain-agnostic).
    /// OPTIMIZED: Additive score adjustment instead of full re-sort (same fix as keyword boost).
    private func applyStructureTypeBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryLower = query.lowercased()

        let isSpecQuery = detectSpecificationQuery(queryLower)
        guard isSpecQuery else { return results }

        var boostedResults: [RetrievedChunk] = []
        var boostedCount = 0

        for result in results {
            var boostPoints = 0

            // Check if chunk has structureType metadata (from iOS 26+ structured parsing)
            if let structureType = result.chunk.metadata.structureType {
                switch structureType {
                case "table":
                    boostPoints += 5
                case "list":
                    boostPoints += 2
                default:
                    break
                }
            }

            // Also check if content looks like a table (fallback for legacy chunks)
            let content = result.chunk.content
            if content.contains("|") && content.components(separatedBy: "|").count >= 4 {
                boostPoints += 3
            }

            if result.chunk.metadata.hasNumericData {
                boostPoints += 1
            }

            // Check for specification patterns in content
            let specPatterns: [(pattern: String, weight: Int)] = [
                (#"\d+W-\d+"#, 4),
                (#"(?:API|SAE|ACEA|ILSAC)\s*[A-Z0-9-]+"#, 3),
                (#"\d+(?:\.\d+)?\s*(?:L|qt|gal|ml)"#, 2),
                (#"\d+(?:\.\d+)?\s*(?:psi|kPa|bar)"#, 2),
            ]

            for (pattern, weight) in specPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
                    boostPoints += weight
                }
            }

            if boostPoints > 0 {
                // Additive boost: 0.02 per point, capped at 0.15
                // Tables with specs get up to +0.15, enough to elevate but not override strong RRF results
                let boost = min(0.15, Double(boostPoints) * 0.02)
                let boosted = RetrievedChunk(
                    chunk: result.chunk,
                    similarityScore: result.similarityScore + Float(boost),
                    rank: result.rank,
                    sourceDocument: result.sourceDocument,
                    pageNumber: result.pageNumber
                )
                boostedResults.append(boosted)
                boostedCount += 1
            } else {
                boostedResults.append(result)
            }
        }

        boostedResults.sort { $0.similarityScore > $1.similarityScore }

        if boostedCount > 0 {
            Log.debug("[Hybrid] Structure boost: \(boostedCount) table/list chunks boosted for spec query", category: .retrieval)
        }

        return boostedResults
    }

    /// Detect if query is seeking specific data/specifications (domain-agnostic)
    /// Uses linguistic patterns that work across ANY domain
    private func detectSpecificationQuery(_ query: String) -> Bool {
        // Pattern 1: "What is the X" / "What are the X" - seeking specific values
        if query.hasPrefix("what is") || query.hasPrefix("what are") ||
           query.hasPrefix("what's") {
            return true
        }

        // Pattern 2: "How much" / "How many" - quantity queries
        if query.hasPrefix("how much") || query.hasPrefix("how many") {
            return true
        }

        // Pattern 3: Contains numbers or measurement units (seeking numeric specs)
        let hasNumbers = query.rangeOfCharacter(from: .decimalDigits) != nil
        let measurementUnits = ["mg", "kg", "ml", "liter", "gallon", "quart", "psi", "kpa",
                                "volt", "amp", "watt", "hz", "mm", "cm", "inch", "ft", "lb", "oz"]
        let hasMeasurement = measurementUnits.contains { query.contains($0) }
        if hasNumbers || hasMeasurement {
            return true
        }

        // Pattern 4: Spec-seeking keywords (domain-agnostic)
        let specPatterns = [
            "specification", "specs", "spec",
            "requirement", "requirements",
            "capacity", "rating", "rated",
            "recommended", "required",
            "maximum", "minimum", "max", "min",
            "type of", "kind of", "grade of",
            "dosage", "dose",  // Medical
            "limit", "threshold",  // Legal/technical
            "tolerance", "range"  // Engineering
        ]
        if specPatterns.contains(where: { query.contains($0) }) {
            return true
        }

        // Pattern 5: Alphanumeric codes (e.g., "ISO 9001", "API-1234")
        let alphanumericPattern = #"[A-Z]{2,}\s*[-]?\d+"#
        if let regex = try? NSRegularExpression(pattern: alphanumericPattern, options: .caseInsensitive),
           regex.firstMatch(in: query, options: [], range: NSRange(query.startIndex..., in: query)) != nil {
            return true
        }

        return false
    }

    /// Extract important keywords from query (nouns, verbs - skip stopwords).
    /// OPTIMIZED: Returns deduplicated set to prevent inflated boost scores.
    /// Previously returned duplicates from expanded queries (e.g., "oil" appearing 9x
    /// in 9 query variations), causing 282/300 chunks to be "boosted" = meaningless.
    private func extractImportantKeywords(from query: String) -> [String] {
        let stopwords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could", "should",
            "may", "might", "must", "shall", "can", "need", "dare", "ought", "used",
            "to", "of", "in", "for", "on", "with", "at", "by", "from", "as", "into",
            "through", "during", "before", "after", "above", "below", "between",
            "this", "that", "these", "those", "what", "which", "who", "whom", "whose",
            "where", "when", "why", "how", "all", "each", "every", "both", "few",
            "more", "most", "other", "some", "such", "no", "nor", "not", "only",
            "own", "same", "so", "than", "too", "very", "just", "also", "now",
            "i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your",
            "he", "him", "his", "she", "her", "it", "its", "they", "them", "their",
                // OPTIMIZED: Query-framing words that add no discriminative value.
                // "type"/"take"/"kind"/"sort" are question words, not content words.
                // Only filter true question-framing verbs and vague nouns here —
                // domain-specific filtering is handled dynamically by hit-rate analysis
                // in applyKeywordMatchBoost() (any keyword matching >30% of chunks = 0 boost).
                "type", "kind", "sort", "take", "use", "get", "find",
            "tell", "know", "look", "want", "like", "make", "put", "give", "help",
            "work", "come", "thing", "about", "much", "many", "way", "long"
        ]

        let tokens = tokenize(query)
        var seen = Set<String>()
        let important = tokens.filter { token in
            token.count >= 3 && !stopwords.contains(token) && seen.insert(token).inserted
        }

        return important
    }

    private func shouldRunLexicalRecall(query: String, vectorCount: Int, topK: Int) -> Bool {
        let normalized = query.lowercased()
        let hasDigits = normalized.rangeOfCharacter(from: .decimalDigits) != nil
        let hasExactCue =
            normalized.contains("section")
            || normalized.contains("article")
            || normalized.contains("clause")
            || normalized.contains("exhibit")
            || normalized.contains("statute")
        return vectorCount < topK || hasDigits || hasExactCue
    }

    private func lexicalRecallCandidates(
        query: String,
        embedding: [Float],
        maxCandidates: Int,
        cachedChunks: [DocumentChunk]? = nil
    ) async throws -> [RetrievedChunk] {
        let queryTerms = tokenize(query).filter { $0.count > 2 }
        guard !queryTerms.isEmpty, maxCandidates > 0 else { return [] }

        let queryLower = query.lowercased()
        let digitTerms = queryLower.split(whereSeparator: { !$0.isNumber }).map(String.init)
        let requiresDigits = !digitTerms.isEmpty
        let queryNorm = computeNorm(embedding)

        // Use cached chunks if provided, otherwise fetch (avoids repeated allChunks calls)
        let allChunks: [DocumentChunk]
        if let cached = cachedChunks {
            allChunks = cached
            Log.debug("Lexical recall using cached chunks (\(cached.count))", category: .pipeline)
        } else {
            allChunks = try await vectorDatabase.allChunks()
        }
        guard !allChunks.isEmpty else { return [] }

        var results: [RetrievedChunk] = []
        results.reserveCapacity(min(maxCandidates, allChunks.count))

        for chunk in allChunks {
            if results.count >= maxCandidates { break }
            guard chunk.embedding.count == embedding.count else { continue }

            let contentLower = chunk.content.lowercased()
            if requiresDigits {
                let hasDigitMatch = digitTerms.contains(where: { contentLower.contains($0) })
                if !hasDigitMatch { continue }
            }

            var matched = false
            for term in queryTerms {
                if contentLower.contains(term) {
                    matched = true
                    break
                }
            }
            guard matched else { continue }

            let similarity = cosineSimilarity(embedding, chunk.embedding, queryNorm: queryNorm)
            results.append(
                RetrievedChunk(
                    chunk: chunk,
                    similarityScore: similarity,
                    rank: 0
                )
            )
        }

        let ranked = results.sorted { $0.similarityScore > $1.similarityScore }
        return reindex(ranked)
    }

    private func tokenize(_ text: String) -> [String] {
        let normalized = text.lowercased()
        cachedTokenizer.string = normalized

        return cachedTokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap {
            var token = String(normalized[$0]).trimmingCharacters(in: .punctuationCharacters)
            if token.isEmpty { return nil }
            // Handle contractions: "what's" → "what", "don't" → "don", "it's" → "it"
            // Both straight (') and curly (\u{2019}) apostrophes.
            // Without this, "what's" bypasses the "what" stopword and gets used as a keyword.
            for apostrophe in ["'", "\u{2019}"] {
                if let range = token.range(of: apostrophe) {
                    token = String(token[token.startIndex..<range.lowerBound])
                    break
                }
            }
            return token.isEmpty ? nil : token
        }
    }

    private func computeNorm(_ vector: [Float]) -> Float {
        // Modern Accelerate API: vDSP.sumOfSquares + sqrt (replaces deprecated cblas_snrm2)
        sqrt(vDSP.sumOfSquares(vector))
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float], queryNorm: Float) -> Float {
        guard a.count == b.count, queryNorm > 0 else { return 0 }

        // Accelerate-powered dot product using vDSP (Neural Engine optimized)
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        // Modern Accelerate API for L2 norm (replaces deprecated cblas_snrm2)
        let magB = sqrt(vDSP.sumOfSquares(b))
        let denom = queryNorm * magB

        return denom > 0 ? dot / denom : 0
    }

    private func reindex(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        chunks.enumerated().map { idx, r in
            RetrievedChunk(
                chunk: r.chunk,
                similarityScore: r.similarityScore,
                rank: idx + 1,
                sourceDocument: r.sourceDocument,
                pageNumber: r.pageNumber
            )
        }
    }

    // MARK: - FTS5 Integration (10-100X faster BM25)

    /// Check if FTS5 acceleration is available for a container
    /// Call this to determine if FTS5 can be used for BM25 scoring
    func isFTS5Available(containerId: UUID) async -> Bool {
        let fts5Service = SQLiteFullTextService.shared
        let docIds = await fts5Service.getAllDocumentIds()
        return !docIds.isEmpty
    }

    /// Get BM25 scores using FTS5's native implementation (10-100X faster)
    /// - Parameters:
    ///   - query: Search query
    ///   - containerId: Container to search within
    /// - Returns: Map of document UUIDs to BM25 scores
    func fts5BM25Scores(query: String, containerId: UUID) async -> [UUID: Double] {
        let fts5Service = SQLiteFullTextService.shared
        return await fts5Service.bm25Scores(query: query, containerId: containerId)
    }

    /// Perform hybrid search using FTS5 for BM25 scoring
    /// FTS5-accelerated hybrid search path.
    /// This is the optimized path when FTS5 data is available
    func searchWithFTS5(
        query: String,
        originalQuery: String,
        embedding: [Float],
        topK: Int,
        containerId: UUID
    ) async throws -> [RetrievedChunk] {
        Log.debug("[Hybrid] FTS5-accelerated search starting", category: .pipeline)

        let startTime = CFAbsoluteTimeGetCurrent()

        // 1. Vector search (same as before)
        let vectorCandidateMultiplier = topK > 50 ? 2 : 3
        let vectorResults = try await vectorDatabase.search(embedding: embedding, topK: topK * vectorCandidateMultiplier)

        // 2. CHUNK-LEVEL BM25 scoring (not document-level)
        // CRITICAL FIX: Previously used FTS5 document-level BM25 which gave ALL chunks from
        // the same document the SAME score. A 200-page manual has "oil" on page 5 and
        // "transmission" on page 180 — but every chunk got identical BM25 score.
        // Now: compute BM25 at chunk granularity using in-memory scorer for precise differentiation.
        let snapshot = bm25Scorer.snapshot(from: vectorResults)
        let keywordResults = await engine.bm25Scores(
            query: originalQuery,
            candidates: vectorResults,
            snapshot: snapshot
        )

        // 3. Reciprocal Rank Fusion
        let vectorRanked = reindex(vectorResults.sorted { $0.similarityScore > $1.similarityScore })
        let fusedResults = await engine.reciprocalRankFusion(
            vectorResults: vectorRanked,
            keywordResults: keywordResults,
            k: 60,
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        // 4. Apply boosts — use ORIGINAL query for targeted matching
        let boostedResults = applyKeywordMatchBoost(query: originalQuery, results: fusedResults)
        let structureBoostedResults = applyStructureTypeBoost(query: originalQuery, results: boostedResults)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.debug("[Hybrid] FTS5-accelerated search completed in \(String(format: "%.1f", elapsed * 1000))ms", category: .pipeline)

        return reindex(Array(structureBoostedResults.prefix(topK)))
    }

}
