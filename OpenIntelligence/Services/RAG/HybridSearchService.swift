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
        let queryTerms = tokenize(query)
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

    private func tokenize(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        let normalized = text.lowercased()
        tokenizer.string = normalized

        return tokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap {
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
    ///   - query: The search query string
    ///   - embedding: Query embedding vector
    ///   - topK: Number of top results to return
    ///   - cachedChunks: Optional pre-fetched chunks to avoid re-loading allChunks() for lexical recall
    func search(query: String, embedding: [Float], topK: Int, cachedChunks: [DocumentChunk]? = nil) async throws -> [RetrievedChunk] {
        Log.debug("Hybrid search starting (vector: \(vectorWeight), keyword: \(keywordWeight))", category: .pipeline)

        // 1. Vector search - retrieve more candidates for better coverage
        let vectorResults = try await vectorDatabase.search(embedding: embedding, topK: topK * 3)

        var candidatePool = vectorResults

        if shouldRunLexicalRecall(query: query, vectorCount: vectorResults.count, topK: topK) {
            let maxRecall = min(200, max(topK * 10, 40))
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
                        "Lexical recall added \(unique.count) candidates",
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
        // If query keywords appear verbatim in chunk, boost its ranking significantly
        let boostedResults = applyKeywordMatchBoost(query: query, results: fusedResults)

        // 5. Apply STRUCTURE-AWARE BOOST for spec queries (iOS 26+ structured parsing)
        // Tables chunks are boosted when query is about specifications (oil, fuel, capacity, etc.)
        let structureBoostedResults = applyStructureTypeBoost(query: query, results: boostedResults)

        // 6. Take top K from boosted results and re-rank index
        let topResults = Array(structureBoostedResults.prefix(topK))

        Log.debug(
            "Hybrid fusion: \(topResults.count) results from \(vectorResults.count) vector + \(keywordResults.count) BM25",
            category: .pipeline
        )

        return reindex(topResults)
    }

    /// Boost chunks that contain EXACT matches of important query keywords
    /// This fixes cases where "button" in query should strongly prefer chunks with "button"
    private func applyKeywordMatchBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryKeywords = extractImportantKeywords(from: query)
        guard !queryKeywords.isEmpty else { return results }

        // Score each result by keyword match count
        var scoredResults: [(chunk: RetrievedChunk, boost: Int, originalRank: Int)] = []

        for (idx, result) in results.enumerated() {
            let contentLower = result.chunk.content.lowercased()
            var matchCount = 0

            for keyword in queryKeywords {
                if contentLower.contains(keyword) {
                    matchCount += 1
                    // Extra boost for exact word boundary matches
                    if contentLower.contains(" \(keyword) ") ||
                       contentLower.contains(" \(keyword).") ||
                       contentLower.contains(" \(keyword),") ||
                       contentLower.hasPrefix("\(keyword) ") ||
                       contentLower.hasSuffix(" \(keyword)") {
                        matchCount += 1
                    }
                }
            }

            scoredResults.append((result, matchCount, idx))
        }

        // Sort by: keyword match count (desc), then original rank (asc)
        scoredResults.sort {
            if $0.boost != $1.boost {
                return $0.boost > $1.boost  // More keyword matches = better
            }
            return $0.originalRank < $1.originalRank  // Preserve original order for ties
        }

        let boostedCount = scoredResults.prefix(10).filter { $0.boost > 0 }.count
        if boostedCount > 0 {
            Log.debug("[Hybrid] Keyword boost: \(boostedCount) chunks boosted for keywords \(queryKeywords)", category: .retrieval)
        }

        return scoredResults.map { $0.chunk }
    }

    /// Boost table/list chunks when query seeks specific data (domain-agnostic)
    /// Detects spec-seeking queries via linguistic patterns, not hardcoded keywords
    private func applyStructureTypeBoost(query: String, results: [RetrievedChunk]) -> [RetrievedChunk] {
        let queryLower = query.lowercased()

        // Domain-agnostic detection of "specification-seeking" queries
        // These patterns work for ANY domain: medical, legal, technical, automotive, etc.
        let isSpecQuery = detectSpecificationQuery(queryLower)
        guard isSpecQuery else { return results }

        // Score each result by structure type
        var scoredResults: [(chunk: RetrievedChunk, boost: Int, originalRank: Int)] = []

        for (idx, result) in results.enumerated() {
            var boost = 0

            // Check if chunk has structureType metadata (from iOS 26+ structured parsing)
            if let structureType = result.chunk.metadata.structureType {
                switch structureType {
                case "table":
                    boost += 3  // Strong boost for tables on spec queries
                case "list":
                    boost += 1  // Mild boost for lists
                default:
                    break
                }
            }

            // Also check if content looks like a table (fallback for legacy chunks)
            let content = result.chunk.content
            if content.contains("|") && content.components(separatedBy: "|").count >= 4 {
                // Contains table-like markdown formatting
                boost += 2
            }

            // Boost if chunk contains numbers/measurements (specs often have numeric data)
            if result.chunk.metadata.hasNumericData {
                boost += 1
            }

            scoredResults.append((result, boost, idx))
        }

        // Sort by: boost (desc), then original rank (asc)
        scoredResults.sort {
            if $0.boost != $1.boost {
                return $0.boost > $1.boost
            }
            return $0.originalRank < $1.originalRank
        }

        let boostedCount = scoredResults.prefix(10).filter { $0.boost > 0 }.count
        if boostedCount > 0 {
            Log.debug("[Hybrid] Structure boost: \(boostedCount) table/list chunks boosted for spec query", category: .retrieval)
        }

        return scoredResults.map { $0.chunk }
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

    /// Extract important keywords from query (nouns, verbs - skip stopwords)
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
            "he", "him", "his", "she", "her", "it", "its", "they", "them", "their"
        ]

        let tokens = tokenize(query)
        let important = tokens.filter { token in
            token.count >= 3 && !stopwords.contains(token)
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
        let tokenizer = NLTokenizer(unit: .word)
        let normalized = text.lowercased()
        tokenizer.string = normalized

        return tokenizer.tokens(for: normalized.startIndex ..< normalized.endIndex).compactMap {
            let token = String(normalized[$0]).trimmingCharacters(in: .punctuationCharacters)
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

}
