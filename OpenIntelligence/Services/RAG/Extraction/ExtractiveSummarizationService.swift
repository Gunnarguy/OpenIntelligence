//
//  ExtractiveSummarizationService.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Extractive summarization per AppleRAG spec §6:
//  "For .summarize intent, use sentence selection via bi-encoder similarity"
//
//  This service selects the most informative sentences from retrieved
//  chunks to create a summary without generative hallucination risk.
//
//  Algorithm:
//  1. Segment chunks into sentences
//  2. Score each sentence by relevance to query (bi-encoder similarity)
//  3. Apply MMR to diversify selection
//  4. Concatenate top sentences in document order
//

import Foundation
import NaturalLanguage

// MARK: - Extractive Summary

/// Result of extractive summarization
struct ExtractiveSummary: Sendable {
    /// Selected sentences in document order
    let sentences: [SelectedSentence]

    /// Combined summary text
    let summaryText: String

    /// Total word count
    let wordCount: Int

    /// Coverage score (fraction of query terms covered)
    let coverageScore: Float

    /// Source chunk IDs used
    let sourceChunkIds: [UUID]
}

/// A selected sentence with its metadata
struct SelectedSentence: Sendable {
    /// The sentence text
    let text: String

    /// Relevance score to query
    let score: Float

    /// Source chunk ID
    let sourceChunkId: UUID

    /// Position in original document (for ordering)
    let documentPosition: Int

    /// Page number if available
    let pageNumber: Int?
}

// MARK: - Extractive Summarization Service

/// Service for extractive summarization using sentence selection
/// per AppleRAG spec §6.
actor ExtractiveSummarizationService {

    /// Embedding service for bi-encoder similarity
    private let embeddingService: EmbeddingService

    /// NL tokenizer for sentence segmentation
    private let sentenceTokenizer = NLTokenizer(unit: .sentence)

    /// MMR lambda (diversity vs relevance tradeoff)
    private let mmrLambda: Float = 0.7

    /// Maximum sentences to select
    private let maxSentences: Int = 8

    /// Minimum sentence length (chars) to consider
    private let minSentenceLength: Int = 20

    init(embeddingService: EmbeddingService) {
        self.embeddingService = embeddingService
    }

    // MARK: - Summarization

    /// Generate extractive summary from retrieved chunks
    ///
    /// - Parameters:
    ///   - query: User query for relevance scoring
    ///   - chunks: Retrieved chunks to summarize
    ///   - maxWords: Maximum words in summary (default 200)
    /// - Returns: Extractive summary with selected sentences
    func summarize(
        query: String,
        chunks: [RetrievedChunk],
        maxWords: Int = 200
    ) async throws -> ExtractiveSummary {
        // Step 1: Segment all chunks into sentences
        var allSentences: [(sentence: String, chunkId: UUID, position: Int, page: Int?)] = []
        var globalPosition = 0

        for chunk in chunks {
            let sentences = segmentIntoSentences(chunk.chunk.content)
            let page = chunk.chunk.metadata.pageNumber

            for sentence in sentences {
                if sentence.count >= minSentenceLength {
                    allSentences.append((
                        sentence: sentence,
                        chunkId: chunk.chunk.id,
                        position: globalPosition,
                        page: page
                    ))
                    globalPosition += 1
                }
            }
        }

        guard !allSentences.isEmpty else {
            return ExtractiveSummary(
                sentences: [],
                summaryText: "",
                wordCount: 0,
                coverageScore: 0,
                sourceChunkIds: []
            )
        }

        // Step 2: Score sentences by relevance to query
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)

        var scoredSentences: [(sentence: String, chunkId: UUID, position: Int, page: Int?, score: Float, embedding: [Float])] = []

        for item in allSentences {
            let embedding = try await embeddingService.generateEmbedding(for: item.sentence)
            let similarity = cosineSimilarity(queryEmbedding, embedding)

            scoredSentences.append((
                sentence: item.sentence,
                chunkId: item.chunkId,
                position: item.position,
                page: item.page,
                score: similarity,
                embedding: embedding
            ))
        }

        // Step 3: Apply MMR for diversity
        let selected = selectWithMMR(
            sentences: scoredSentences,
            maxSentences: maxSentences,
            maxWords: maxWords
        )

        // Step 4: Sort by document position
        let sortedSelected = selected.sorted { $0.documentPosition < $1.documentPosition }

        // Build summary text
        let summaryText = sortedSelected.map { $0.text }.joined(separator: " ")
        let wordCount = summaryText.split(separator: " ").count

        // Calculate coverage score
        let coverageScore = calculateCoverage(query: query, summary: summaryText)

        // Collect unique source chunk IDs
        let sourceChunkIds = Array(Set(sortedSelected.map { $0.sourceChunkId }))

        return ExtractiveSummary(
            sentences: sortedSelected,
            summaryText: summaryText,
            wordCount: wordCount,
            coverageScore: coverageScore,
            sourceChunkIds: sourceChunkIds
        )
    }

    // MARK: - Sentence Segmentation

    /// Segment text into sentences
    private func segmentIntoSentences(_ text: String) -> [String] {
        sentenceTokenizer.string = text

        var sentences: [String] = []
        sentenceTokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        return sentences
    }

    // MARK: - MMR Selection

    /// Select sentences using Maximal Marginal Relevance
    private func selectWithMMR(
        sentences: [(sentence: String, chunkId: UUID, position: Int, page: Int?, score: Float, embedding: [Float])],
        maxSentences: Int,
        maxWords: Int
    ) -> [SelectedSentence] {
        guard !sentences.isEmpty else { return [] }

        var selected: [SelectedSentence] = []
        var selectedEmbeddings: [[Float]] = []
        var remaining = sentences
        var totalWords = 0

        while !remaining.isEmpty && selected.count < maxSentences && totalWords < maxWords {
            // Find best candidate using MMR
            var bestIndex = -1
            var bestScore: Float = -.infinity

            for (index, candidate) in remaining.enumerated() {
                // Relevance component
                let relevance = candidate.score

                // Diversity component (max similarity to already selected)
                var maxSim: Float = 0
                for selectedEmb in selectedEmbeddings {
                    let sim = cosineSimilarity(candidate.embedding, selectedEmb)
                    maxSim = max(maxSim, sim)
                }

                // MMR score
                let mmrScore = mmrLambda * relevance - (1 - mmrLambda) * maxSim

                if mmrScore > bestScore {
                    bestScore = mmrScore
                    bestIndex = index
                }
            }

            guard bestIndex >= 0 else { break }

            let chosen = remaining[bestIndex]
            let sentenceWords = chosen.sentence.split(separator: " ").count

            // Check word limit
            if totalWords + sentenceWords > maxWords && !selected.isEmpty {
                break
            }

            selected.append(SelectedSentence(
                text: chosen.sentence,
                score: chosen.score,
                sourceChunkId: chosen.chunkId,
                documentPosition: chosen.position,
                pageNumber: chosen.page
            ))
            selectedEmbeddings.append(chosen.embedding)
            totalWords += sentenceWords

            remaining.remove(at: bestIndex)
        }

        return selected
    }

    // MARK: - Similarity & Coverage

    /// Cosine similarity between embeddings
    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dotProduct / denominator
    }

    /// Calculate term coverage score
    private func calculateCoverage(query: String, summary: String) -> Float {
        let queryTerms = Set(query.lowercased().split(separator: " ").map(String.init))
        let summaryTerms = Set(summary.lowercased().split(separator: " ").map(String.init))

        guard !queryTerms.isEmpty else { return 0 }

        let covered = queryTerms.intersection(summaryTerms)
        return Float(covered.count) / Float(queryTerms.count)
    }
}

// MARK: - Convenience Extension

extension ExtractiveSummarizationService {
    /// Create a quick summary (fewer sentences, faster)
    func quickSummary(
        query: String,
        chunks: [RetrievedChunk]
    ) async throws -> ExtractiveSummary {
        try await summarize(query: query, chunks: chunks, maxWords: 100)
    }

    /// Create a detailed summary (more sentences)
    func detailedSummary(
        query: String,
        chunks: [RetrievedChunk]
    ) async throws -> ExtractiveSummary {
        try await summarize(query: query, chunks: chunks, maxWords: 400)
    }
}
