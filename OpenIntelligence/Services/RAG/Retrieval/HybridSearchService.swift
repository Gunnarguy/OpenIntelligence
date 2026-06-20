//
//  HybridSearchService.swift
//  OpenIntelligence
//
//  True parallel hybrid search: independent vector + FTS5 searches merged via RRF.
//
//  ## Architecture
//
//  Two fully independent ranked result lists run in parallel:
//  1. Vector search (HNSW index) → ranked by cosine similarity
//  2. FTS5 search (SQLite native bm25()) → ranked at chunk granularity
//
//  Reciprocal Rank Fusion merges the UNION of both sets — a chunk found
//  only by FTS5 (keyword-only match) gets a fair RRF score from its BM25
//  rank alone, without needing a synthetic vector similarity score.
//
//  ## Silicon-Native Vector Math
//
//  Uses Apple Accelerate framework for hardware-accelerated similarity:
//  - vDSP.sumOfSquares: L2 norm computation (AMX/Neural Engine)
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
struct BM25Scorer {
    private final class Storage {
        var documentFrequencies: [String: Int] = [:]
        var avgDocLength: Float = 0
        var totalDocuments: Int = 0
    }

    private let k1: Float = 1.5  // Term frequency saturation parameter
    private let b: Float = 0.5   // Length normalization: lowered from 0.75 because all chunks are ~260 words (uniform length makes length normalization less important)
    private let storage = Storage()

    /// Index documents for BM25 scoring
    func indexDocuments(_ chunks: [DocumentChunk]) {
        storage.totalDocuments = chunks.count
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
        storage.documentFrequencies = termDocCounts.mapValues { $0.count }
        storage.avgDocLength = docLengths.reduce(0, +) / Float(max(storage.totalDocuments, 1))
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
            let df = Float(storage.documentFrequencies[queryTerm] ?? 1)

            // IDF (Inverse Document Frequency)
            let idf = log((Float(storage.totalDocuments) - df + 0.5) / (df + 0.5) + 1)

            // BM25 formula
            let numerator = tf * (k1 + 1)
            let denominator = tf + k1 * (1 - b + b * (docLength / max(storage.avgDocLength, 0.0001)))

            score += idf * (numerator / denominator)
        }

        return score
    }

    func tokenize(_ text: String) -> [String] {
        let normalized = text.lowercased()
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = normalized

        return tokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap { range in
            let token = String(normalized[range]).trimmingCharacters(in: .punctuationCharacters)
            guard !token.isEmpty else { return nil }
            return token
        }
    }
}

extension BM25Scorer {
    /// Build a snapshot of current BM25 stats for use by RAGEngine
    func makeSnapshot() -> BM25Snapshot {
        return BM25Snapshot(
            documentFrequencies: storage.documentFrequencies,
            avgDocLength: storage.avgDocLength,
            totalDocuments: storage.totalDocuments
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
    private var bm25Scorer = BM25Scorer()
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
    func search(query: String, originalQuery: String? = nil, embedding: [Float], topK: Int, cachedChunks: [DocumentChunk]? = nil, containerId: UUID? = nil, isOverviewQuery: Bool = false) async throws -> [RetrievedChunk] {
        let boostQuery = originalQuery ?? query
        // Auto-select FTS5 path if containerId provided and FTS5 data available
        if let cid = containerId, await isFTS5Available(containerId: cid) {
            Log.debug("[Hybrid] Using FTS5-accelerated BM25 for container \(cid)", category: .pipeline)
            return try await searchWithFTS5(query: query, originalQuery: boostQuery, embedding: embedding, topK: topK, containerId: cid, cachedChunks: cachedChunks, isOverviewQuery: isOverviewQuery)
        }

        Log.debug("Hybrid search starting (vector: \(vectorWeight), keyword: \(keywordWeight))", category: .pipeline)

        // 1. Vector search - retrieve more candidates for better coverage
        // ENHANCEMENT: Scale vector candidates with topK for large corpus support
        let vectorCandidateMultiplier = topK > 50 ? 2 : 3  // Less aggressive multiplier for large topK
        let vectorResults = try await vectorDatabase.search(embedding: embedding, topK: topK * vectorCandidateMultiplier)

        let vectorResultsFiltered = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryRetrievedChunks(vectorResults) : vectorResults
        var candidatePool = vectorResultsFiltered

        if shouldRunLexicalRecall(query: query, vectorCount: vectorResultsFiltered.count, topK: topK) {
            // UNIVERSAL: Always runs, but candidate pool scales with vector confidence.
            // Healthy vector = smaller pool (fast). Weak vector = full pool (thorough).
            let maxRecall = lexicalRecallLimit(query: query, vectorCount: vectorResultsFiltered.count, topK: topK)
            let lexicalCandidates = try await lexicalRecallCandidates(
                query: query,
                embedding: embedding,
                maxCandidates: maxRecall,
                cachedChunks: cachedChunks,
                isOverviewQuery: isOverviewQuery
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

        return sanitizeRetrievedChunks(reindex(topResults))
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
    func applyKeywordMatchBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryKeywords = extractImportantKeywords(from: query)
        guard !queryKeywords.isEmpty, !results.isEmpty else { return results }

        // PROPORTIONAL HIT-RATE SCALING: For each keyword, measure how many chunks contain it.
        // Instead of binary disable at 30%, scale the boost proportionally:
        // 0% hit rate → full boost, 50%+ → zero boost (linear decay).
        // This preserves SOME boost for domain-critical terms like "insulin" in a diabetes
        // manual (might hit 40% of chunks but still deserves partial boost) while eliminating
        // boost for truly universal terms (60%+ hit rate = corpus noise).
        let decayCeiling = 0.50  // hit rate at which boost reaches zero
        let totalChunks = Double(results.count)
        var discriminativeKeywords: [(keyword: String, scaleFactor: Double)] = []

        for keyword in queryKeywords {
            let hitCount = results.filter { $0.chunk.content.lowercased().contains(keyword) }.count
            let hitRate = Double(hitCount) / totalChunks
            let scaleFactor = max(0.0, 1.0 - (hitRate / decayCeiling))
            if scaleFactor > 0.0 {
                discriminativeKeywords.append((keyword: keyword, scaleFactor: scaleFactor))
            } else {
                Log.debug("[Hybrid] Keyword '\(keyword)' hit \(Int(hitRate * 100))% of chunks — zero boost (≥\(Int(decayCeiling * 100))%)", category: .retrieval)
            }
        }

        guard !discriminativeKeywords.isEmpty else {
            Log.debug("[Hybrid] All keywords above \(Int(decayCeiling * 100))% hit rate, skipping boost", category: .retrieval)
            return results
        }

        var boostedResults: [RetrievedChunk] = []
        var boostedCount = 0

        for result in results {
            let contentLower = result.chunk.content.lowercased()
            var weightedMatchScore = 0.0

            for (keyword, scaleFactor) in discriminativeKeywords {
                if contentLower.contains(keyword) {
                    weightedMatchScore += 1.0 * scaleFactor
                    // Extra for exact word boundary matches
                    if contentLower.contains(" \(keyword) ") ||
                       contentLower.contains(" \(keyword).") ||
                       contentLower.contains(" \(keyword),") ||
                       contentLower.hasPrefix("\(keyword) ") ||
                       contentLower.hasSuffix(" \(keyword)") {
                        weightedMatchScore += 1.0 * scaleFactor
                    }
                }
            }

            if weightedMatchScore > 0 {
                let boost = min(0.20, weightedMatchScore * 0.05)
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
            let keywordNames = discriminativeKeywords.map { "\($0.keyword)(\(Int($0.scaleFactor * 100))%)" }
            Log.debug("[Hybrid] Keyword boost: \(boostedCount)/\(results.count) chunks boosted for \(keywordNames) (filtered \(queryKeywords.count - discriminativeKeywords.count) at ≥\(Int(decayCeiling * 100))% hit rate)", category: .retrieval)
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

            // Check for specification patterns in content (universal, not domain-specific)
            // CRITICAL: Patterns must use \b word boundaries to prevent false matches.
            // Previously `\d+\s*m` matched "7 m" in "page 7-7 mentions" → 300/300 chunks boosted = useless.
            let specPatterns: [(pattern: String, weight: Int)] = [
                (#"\d+(?:\.\d+)?\s*(?:L|qt|gal|ml|mL|mg|g|kg|lb|oz)\b"#, 2),
                (#"\d+(?:\.\d+)?\s*(?:psi|kPa|bar|Pa|atm|mmHg)\b"#, 2),
                (#"\d+(?:\.\d+)?\s*(?:mm|cm|km|in|ft|yd)\b"#, 2),  // No bare 'm' — matches everything
                (#"\d+(?:\.\d+)?\s*(?:V|A|W|kW|mA|Ah|kWh|Hz|MHz|GHz)\b"#, 2),
                (#"(?:ISO|IEEE|ANSI|ASTM|IEC|DIN|EN|UL|NFPA)[-\s]?[A-Z0-9-]+"#, 3),
            ]

            for (pattern, weight) in specPatterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   regex.firstMatch(in: content, options: [], range: NSRange(content.startIndex..., in: content)) != nil {
                    boostPoints += weight
                }
            }

            if boostPoints >= 5 {
                // Additive boost: 0.04 per point, capped at 0.30
                // CRITICAL: Require minimum 5 boost points before applying any boost.
                // ≥3 was still too permissive: hasNumericData(1) + any measurement like
                // "12V" or "25 mm"(2) = 3 → 295/300 chunks boosted = near-universal = useless.
                // ≥5 requires: structureType=table(5), or list(2)+specPattern(2)+numeric(1),
                // or pipe-table(3)+specPattern(2). Much more selective.
                // Cap of 0.30 helps bridge the reranker's prose bias (~0.78 prose vs ~0.30 table).
                let boost = min(0.30, Double(boostPoints) * 0.04)
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

    /// Determines whether lexical recall should run and how many candidates to fetch.
    /// UNIVERSAL FIX: Always runs lexical recall — keyword-only needles must never be invisible.
    /// When vector search is healthy, uses a smaller candidate pool (topK*2) to keep latency low.
    /// When vector search is weak (< topK results) or query has exact-match cues, uses the full pool.
    private func shouldRunLexicalRecall(query: String, vectorCount: Int, topK: Int) -> Bool {
        // Always run — the only question is how many candidates (handled by caller's maxRecall)
        return true
    }

    /// Returns the lexical recall candidate limit, scaled by retrieval confidence.
    /// Healthy vector search → smaller pool (fast). Weak vector → full pool (thorough).
    private func lexicalRecallLimit(query: String, vectorCount: Int, topK: Int) -> Int {
        let normalized = query.lowercased()
        let hasDigits = normalized.rangeOfCharacter(from: .decimalDigits) != nil
        let hasExactCue =
            normalized.contains("section")
            || normalized.contains("article")
            || normalized.contains("clause")
            || normalized.contains("exhibit")
            || normalized.contains("statute")

        if vectorCount < topK || hasDigits || hasExactCue {
            // Weak vector or exact-match query: full lexical recall
            return min(500, max(topK * 5, 100))
        } else {
            // Healthy vector: smaller lexical recall to catch keyword-only needles without latency hit
            return min(200, max(topK * 2, 50))
        }
    }

    private func lexicalRecallCandidates(
        query: String,
        embedding: [Float],
        maxCandidates: Int,
        cachedChunks: [DocumentChunk]? = nil,
        isOverviewQuery: Bool = false
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
            allChunks = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryChunks(cached) : cached
            Log.debug("Lexical recall using cached chunks (\(cached.count))", category: .pipeline)
        } else {
            let fetched = try await vectorDatabase.allChunks()
            allChunks = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryChunks(fetched) : fetched
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

    private func sanitizeRetrievedChunks(_ chunks: [RetrievedChunk]) -> [RetrievedChunk] {
        chunks.map(sanitizeRetrievedChunk)
    }

    private func sanitizeRetrievedChunk(_ retrieved: RetrievedChunk) -> RetrievedChunk {
        let cleanedSectionTitle = trustedLegacySectionLabel(retrieved.chunk.metadata.sectionTitle)
        let cleanedSectionPath = trustedLegacySectionPath(retrieved.chunk.metadata.sectionPath)
        let cleanedContent = stripLegacySectionPathPrefix(
            from: retrieved.chunk.content,
            cleanedSectionPath: cleanedSectionPath
        )
        let cleanedParentContent = retrieved.chunk.parentContent.map {
            stripLegacySectionPathPrefix(from: $0, cleanedSectionPath: cleanedSectionPath)
        }

        guard cleanedSectionTitle != retrieved.chunk.metadata.sectionTitle
            || cleanedSectionPath != retrieved.chunk.metadata.sectionPath
            || cleanedContent != retrieved.chunk.content
            || cleanedParentContent != retrieved.chunk.parentContent
        else {
            return retrieved
        }

        let base = retrieved.chunk.metadata
        let cleanedMetadata = ChunkMetadata(
            chunkIndex: base.chunkIndex,
            startPosition: base.startPosition,
            endPosition: base.endPosition,
            pageNumber: base.pageNumber,
            sectionTitle: cleanedSectionTitle,
            keywords: base.keywords,
            semanticDensity: base.semanticDensity,
            hasNumericData: base.hasNumericData,
            hasListStructure: base.hasListStructure,
            wordCount: base.wordCount,
            characterCount: base.characterCount,
            createdAt: base.createdAt,
            structureType: base.structureType,
            siblingGroupId: base.siblingGroupId,
            siblingCount: base.siblingCount,
            entities: base.entities,
            abbreviations: base.abbreviations,
            abstractionLevel: base.abstractionLevel,
            sectionPath: cleanedSectionPath,
            bboxArray: base.bboxArray,
            documentCategory: base.documentCategory,
            chunkType: base.chunkType,
            tableTitle: base.tableTitle,
            imageContentType: base.imageContentType,
            imageCaption: base.imageCaption,
            imageDescription: base.imageDescription,
            imageExtractedText: base.imageExtractedText,
            imageClassifications: base.imageClassifications,
            hasCrossReferences: base.hasCrossReferences,
            resolvedReferences: base.resolvedReferences
        )

        let cleanedChunk = DocumentChunk(
            id: retrieved.chunk.id,
            documentId: retrieved.chunk.documentId,
            content: cleanedContent,
            parentContent: cleanedParentContent,
            contextualPrefix: retrieved.chunk.contextualPrefix,
            embedding: retrieved.chunk.embedding,
            metadata: cleanedMetadata
        )

        return RetrievedChunk(
            chunk: cleanedChunk,
            similarityScore: retrieved.similarityScore,
            rank: retrieved.rank,
            sourceDocument: retrieved.sourceDocument,
            pageNumber: retrieved.pageNumber ?? cleanedMetadata.pageNumber
        )
    }

    private func trustedLegacySectionPath(_ rawPath: [String]?) -> [String]? {
        let cleaned = (rawPath ?? []).compactMap(trustedLegacySectionLabel)
        guard !cleaned.isEmpty else { return nil }

        return cleaned.reduce(into: [String]()) { result, component in
            if result.last?.caseInsensitiveCompare(component) != .orderedSame {
                result.append(component)
            }
        }
    }

    private func trustedLegacySectionLabel(_ raw: String?) -> String? {
        guard let raw else { return nil }

        let normalized = OCRConfiguration.normalizeExtractedText(raw)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        guard !normalized.contains("_"), !normalized.contains("|") else { return nil }

        let scalars = normalized.unicodeScalars
        let letterCount = scalars.filter { CharacterSet.letters.contains($0) }.count
        let alnumCount = scalars.filter { CharacterSet.alphanumerics.contains($0) }.count
        let latinCount = scalars.filter { scalar in
            (0x0041...0x005A).contains(scalar.value) || (0x0061...0x007A).contains(scalar.value)
        }.count
        let cyrillicCount = scalars.filter { scalar in
            (0x0400...0x04FF).contains(scalar.value) || (0x0500...0x052F).contains(scalar.value)
        }.count

        guard letterCount >= 2 else { return nil }
        if scalars.count >= 8, Double(alnumCount) / Double(max(1, scalars.count)) < 0.55 {
            return nil
        }
        if latinCount > 0, cyrillicCount > 0 {
            return nil
        }

        return normalized
    }

    private func stripLegacySectionPathPrefix(from text: String, cleanedSectionPath: [String]?) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard let firstLine = lines.first else { return text }
        guard firstLine.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Section Path:") else { return text }

        var updatedLines = lines
        if let cleanedSectionPath, !cleanedSectionPath.isEmpty {
            updatedLines[0] = "Section Path: \(cleanedSectionPath.joined(separator: " > "))"
        } else {
            updatedLines.removeFirst()
            while updatedLines.first?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                updatedLines.removeFirst()
            }
        }

        return updatedLines.joined(separator: "\n")
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

    /// True parallel hybrid search: vector + FTS5 as independent ranked lists merged via RRF.
    ///
    /// ## Architecture (v2 — True Hybrid)
    /// Previous approach injected FTS5 hits into the vector pool with a synthetic 0.40 similarity
    /// score, then re-scored everything with in-memory BM25. This meant BM25-only matches that
    /// vector search missed entirely were invisible unless they happened to land in FTS5 results.
    ///
    /// New approach runs two fully independent searches in parallel:
    /// 1. **Vector search** — semantic similarity via HNSW index
    /// 2. **FTS5 search** — native SQLite `bm25()` at chunk granularity
    ///
    /// Both produce independently ranked result lists. `reciprocalRankFusion()` merges the
    /// UNION of both sets — a chunk found only by FTS5 (keyword-only match) gets a fair
    /// RRF score from its BM25 rank alone, without needing a synthetic vector score.
    ///
    /// Benefits:
    /// - BM25-only matches are no longer invisible (catches vocabulary mismatch gaps)
    /// - Native SQLite `bm25()` replaces in-memory `BM25Scorer.snapshot(from:)` — no local IDF bias
    /// - `async let` parallelism: vector and FTS5 run concurrently, ~40% faster than sequential
    func searchWithFTS5(
        query: String,
        originalQuery: String,
        embedding: [Float],
        topK: Int,
        containerId: UUID,
        cachedChunks: [DocumentChunk]? = nil,
        isOverviewQuery: Bool = false
    ) async throws -> [RetrievedChunk] {
        Log.debug("[Hybrid] True parallel hybrid search starting (vector + FTS5)", category: .pipeline)

        let startTime = CFAbsoluteTimeGetCurrent()
        let queryLower = originalQuery.lowercased()
        let useStructuredRowSearch = EvidenceScoringPolicyService.isStateLookupQuery(queryLower)
            || detectSpecificationQuery(queryLower)

        // ── PARALLEL SEARCH ──────────────────────────────────────────────
        // Run vector search and FTS5 search concurrently as two independent ranked lists.
        // Neither result set influences the other — they're merged purely via RRF.
        let vectorCandidateMultiplier = topK > 50 ? 2 : 3
        let fts5Limit = min(topK * 3, 60)  // FTS5 is fast; retrieve a generous pool

        async let vectorTask = vectorDatabase.search(embedding: embedding, topK: topK * vectorCandidateMultiplier)
        async let fts5Task = SQLiteFullTextService.shared.searchChunks(
            query: originalQuery,
            containerId: containerId,
            limit: fts5Limit
        )
        async let structuredRowTask: [SQLiteFullTextService.ChunkSearchResult] = useStructuredRowSearch
            ? SQLiteFullTextService.shared.searchStructuredRows(
                query: originalQuery,
                containerId: containerId,
                limit: min(topK * 3, 36)
            )
            : []

        let vectorResults = try await vectorTask
        let vectorResultsFiltered = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryRetrievedChunks(vectorResults) : vectorResults
        var fts5ChunkResults = await fts5Task
        let structuredRowResults = await structuredRowTask

        if fts5ChunkResults.isEmpty,
           query.caseInsensitiveCompare(originalQuery) != .orderedSame
        {
            let expandedFTSResults = await SQLiteFullTextService.shared.searchChunks(
                query: query,
                containerId: containerId,
                limit: fts5Limit
            )
            if !expandedFTSResults.isEmpty {
                Log.debug("[Hybrid] FTS5 fallback used expanded query terms after original query miss", category: .pipeline)
                fts5ChunkResults = expandedFTSResults
            }
        }

        // ── CONVERT FTS5 RESULTS TO RANKED LIST ─────────────────────────
        // FTS5 returns ChunkSearchResult with native bm25Score. We need to convert
        // these to (chunk: RetrievedChunk, score: Float) tuples for RRF fusion.
        // For FTS5-only hits (not in vector results), we need the full DocumentChunk
        // to construct RetrievedChunk. Look up from cached chunks or vector DB.
        var fts5KeywordResults: [(chunk: RetrievedChunk, score: Float)] = []

        if !fts5ChunkResults.isEmpty || !structuredRowResults.isEmpty {
            // Build lookup for chunks already found by vector search
            let vectorChunkLookup: [String: RetrievedChunk] = {
                var dict = [String: RetrievedChunk]()
                dict.reserveCapacity(vectorResultsFiltered.count)
                for r in vectorResultsFiltered {
                    let key = "\(r.chunk.documentId.uuidString)_\(r.chunk.metadata.chunkIndex)"
                    dict[key] = r
                }
                return dict
            }()

            // Build lookup for all chunks (needed for FTS5-only hits)
            let allChunkLookup: [String: DocumentChunk]
            if !fts5ChunkResults.allSatisfy({ vectorChunkLookup[$0.chunkId] != nil }) {
                // Some FTS5 results aren't in vector results — need the full chunk data
                let allChunks: [DocumentChunk]
                if let cachedChunks {
                    allChunks = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryChunks(cachedChunks) : cachedChunks
                } else {
                    let fetched = try await vectorDatabase.allChunks()
                    allChunks = isOverviewQuery ? RAPTORSummaryRouter.filterSummaryChunks(fetched) : fetched
                }
                var dict = [String: DocumentChunk]()
                dict.reserveCapacity(allChunks.count)
                for chunk in allChunks {
                    let key = "\(chunk.documentId.uuidString)_\(chunk.metadata.chunkIndex)"
                    dict[key] = chunk
                }
                allChunkLookup = dict
            } else {
                allChunkLookup = [:]
            }

            var lexicalHitsByChunkId: [String: (chunk: RetrievedChunk, score: Float)] = [:]
            var fts5OnlyCount = 0
            var structuredRowOnlyCount = 0
            for fts5Hit in fts5ChunkResults {
                // FTS5 bm25() returns negative scores (lower = better match in SQLite).
                // Negate to get positive scores for RRF ranking.
                let bm25Score: Float = fts5Hit.bm25Score < 0 ? Float(-fts5Hit.bm25Score) : Float(fts5Hit.bm25Score)

                if let existingChunk = vectorChunkLookup[fts5Hit.chunkId] {
                    // Chunk found by both vector and FTS5 — use the full RetrievedChunk
                    lexicalHitsByChunkId[fts5Hit.chunkId] = (chunk: existingChunk, score: bm25Score)
                } else if let docChunk = allChunkLookup[fts5Hit.chunkId] {
                    // FTS5-only hit: construct RetrievedChunk from DocumentChunk.
                    // We don't have a reliable filename at this layer, so avoid using section metadata as provenance.
                    let retrieved = RetrievedChunk(
                        chunk: docChunk,
                        similarityScore: 0,  // No vector similarity — RRF uses rank, not score
                        rank: 0,
                        sourceDocument: "Unknown",
                        pageNumber: fts5Hit.pageNumber
                    )
                    lexicalHitsByChunkId[fts5Hit.chunkId] = (chunk: retrieved, score: bm25Score)
                    fts5OnlyCount += 1
                }
                // else: FTS5 hit doesn't match any known chunk — skip (stale index)
            }

            for rowHit in structuredRowResults {
                if EvidenceScoringPolicyService.isStateLookupQuery(queryLower),
                   !EvidenceScoringPolicyService.satisfiesStateLookupAnchors(query: queryLower, content: rowHit.content)
                {
                    continue
                }

                let rowScore = rowHit.bm25Score < 0 ? Float(-rowHit.bm25Score) : Float(rowHit.bm25Score)
                let mergedScore = rowScore + 0.10

                if let existingChunk = vectorChunkLookup[rowHit.chunkId] {
                    let existing = lexicalHitsByChunkId[rowHit.chunkId]
                    if existing == nil || existing!.score < mergedScore {
                        lexicalHitsByChunkId[rowHit.chunkId] = (chunk: existingChunk, score: mergedScore)
                    }
                } else if let docChunk = allChunkLookup[rowHit.chunkId] {
                    let retrieved = RetrievedChunk(
                        chunk: docChunk,
                        similarityScore: 0,
                        rank: 0,
                        sourceDocument: "Unknown",
                        pageNumber: rowHit.pageNumber
                    )
                    let existing = lexicalHitsByChunkId[rowHit.chunkId]
                    if existing == nil || existing!.score < mergedScore {
                        lexicalHitsByChunkId[rowHit.chunkId] = (chunk: retrieved, score: mergedScore)
                    }
                    structuredRowOnlyCount += 1
                }
            }

            fts5KeywordResults = lexicalHitsByChunkId.values
                .sorted { $0.score > $1.score }
                .map { ($0.chunk, $0.score) }

            if fts5OnlyCount > 0 {
                Log.info("[Hybrid] FTS5 found \(fts5OnlyCount) chunks missed by vector search (true hybrid gain)", category: .pipeline)
            }
            if structuredRowOnlyCount > 0 {
                Log.info("[Hybrid] Structured row search found \(structuredRowOnlyCount) row-backed chunks", category: .pipeline)
            }
        }

        // ── RRF FUSION ──────────────────────────────────────────────────
        // Two independent ranked lists → fused via Reciprocal Rank Fusion.
        // vectorResults sorted by similarity score, fts5KeywordResults sorted by BM25 score.
        // RRF handles the UNION — chunks found by only one method still get ranked.
        let vectorRanked = reindex(vectorResults.sorted { $0.similarityScore > $1.similarityScore })

        let fusedResults = await engine.reciprocalRankFusion(
            vectorResults: vectorRanked,
            keywordResults: fts5KeywordResults,
            k: 60,
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        // ── BOOSTS ──────────────────────────────────────────────────────
        let boostedResults = applyKeywordMatchBoost(query: originalQuery, results: fusedResults)
        let structureBoostedResults = applyStructureTypeBoost(query: originalQuery, results: boostedResults)
        let anchorAdjustedResults = applyStateLookupAnchorBoost(query: originalQuery, results: structureBoostedResults)

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let fts5OnlyHits = fts5KeywordResults.filter { r in !vectorResults.contains(where: { $0.chunk.id == r.chunk.chunk.id }) }.count
        Log.debug(
            "[Hybrid] True parallel search completed in \(String(format: "%.1f", elapsed * 1000))ms — " +
            "\(vectorResults.count) vector + \(fts5ChunkResults.count) FTS5 + \(structuredRowResults.count) row hits (\(fts5OnlyHits) lexical-only)",
            category: .pipeline
        )

        return sanitizeRetrievedChunks(reindex(Array(anchorAdjustedResults.prefix(topK))))
    }

    private func applyStateLookupAnchorBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        guard EvidenceScoringPolicyService.isStateLookupQuery(query), !results.isEmpty else { return results }

        let adjusted = results.map { result -> RetrievedChunk in
            let content = result.chunk.parentContent ?? result.chunk.content
            let adjustment = EvidenceScoringPolicyService.stateLookupAnchorAdjustment(
                query: query,
                content: content,
                structureType: result.chunk.metadata.structureType
            )
            return RetrievedChunk(
                chunk: result.chunk,
                similarityScore: max(0.01, result.similarityScore + adjustment),
                rank: result.rank,
                sourceDocument: result.sourceDocument,
                pageNumber: result.pageNumber
            )
        }

        return adjusted.sorted { $0.similarityScore > $1.similarityScore }
    }

}
