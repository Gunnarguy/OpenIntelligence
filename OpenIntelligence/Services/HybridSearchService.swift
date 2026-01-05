//
//  HybridSearchService.swift
//  OpenIntelligence
//
//  Hybrid search combining vector similarity and BM25 keyword matching
//

import Foundation
import NaturalLanguage

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
    private let engine = RAGEngine()

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
    func search(query: String, embedding: [Float], topK: Int) async throws -> [RetrievedChunk] {
        Log.debug("Hybrid search starting (vector: \(vectorWeight), keyword: \(keywordWeight))", category: .pipeline)

        // 1. Vector search - retrieve more candidates for better coverage
        let vectorResults = try await vectorDatabase.search(embedding: embedding, topK: topK * 3)

        // 2. BM25 keyword search (off-main via RAGEngine)
        // Build a snapshot from current candidates to ensure valid DF/length stats
        let snapshot = bm25Scorer.snapshot(from: vectorResults)
        let keywordResults = await engine.bm25Scores(
            query: query,
            candidates: vectorResults,
            snapshot: snapshot
        )

        // 3. Reciprocal Rank Fusion (RRF) off-main
        let fusedResults = await engine.reciprocalRankFusion(
            vectorResults: vectorResults,
            keywordResults: keywordResults,
            k: 60,  // RRF constant (standard value)
            vectorWeight: vectorWeight,
            keywordWeight: keywordWeight
        )

        // 4. Take top K from fused results
        let topResults = Array(fusedResults.prefix(topK))

        Log.debug("Hybrid fusion: \(topResults.count) results from \(vectorResults.count) vector + \(keywordResults.count) BM25", category: .pipeline)

        return topResults
    }


}
