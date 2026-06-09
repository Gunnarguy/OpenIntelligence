//
//  RAGEvalCase.swift
//  OpenIntelligence
//
//  Defines the data model for a single RAG evaluation test case.
//  Eval cases are stored as JSONL and loaded by RAGEvalDataset.
//

import Foundation

// MARK: - Eval Case

/// A single evaluation test case for the RAG pipeline.
///
/// Each case defines a query, the expected behavior, and the ground truth
/// used to score the pipeline's output. Cases are stored as JSONL files
/// with one `RAGEvalCase` per line.
///
/// ## JSONL Format
/// ```json
/// {"id":"exact-001","query":"What is the rated voltage?","expectedAnswer":"240V","category":"exact_value",
///  "groundTruthChunkIds":["chunk-abc"],"expectedCitations":["Manual.pdf, p.9"],"shouldAbstain":false}
/// ```
struct RAGEvalCase: Codable, Identifiable, Sendable {
    /// Unique identifier for this eval case
    let id: String

    /// The query to send to the RAG pipeline
    let query: String

    /// The expected answer text (for exact match or semantic similarity)
    let expectedAnswer: String

    /// Category of evaluation
    let category: EvalCategory

    /// Chunk IDs that should appear in retrieval results (for retrieval recall)
    let groundTruthChunkIds: [String]?

    /// Expected citation strings in the response (for citation precision)
    let expectedCitations: [String]?

    /// Whether the pipeline should abstain from answering
    let shouldAbstain: Bool

    /// Optional: the container ID to use for this eval case
    let containerId: String?

    /// Optional: the quality mode to use
    let qualityMode: String?

    /// Optional: tags for filtering eval subsets
    let tags: [String]?

    /// Optional: human notes about this case
    let notes: String?
}

// MARK: - Eval Category

/// Categories of evaluation scenarios that test different pipeline behaviors.
enum EvalCategory: String, Codable, CaseIterable, Sendable {
    /// Exact value extraction (e.g., "What is the rated voltage?" → "240V")
    case exactValue = "exact_value"

    /// Factual question requiring grounded retrieval
    case factual = "factual"

    /// Question requiring multi-document synthesis
    case multiDocument = "multi_document"

    /// Overview/summary question (tests RAPTOR-lite routing)
    case overview = "overview"

    /// Question about table/structured data
    case table = "table"

    /// Question about image/OCR content (visual evidence)
    case visualEvidence = "visual_evidence"

    /// Out-of-scope question where the pipeline should abstain
    case abstention = "abstention"

    /// Adversarial question designed to test hallucination resistance
    case adversarial = "adversarial"

    /// Conversation-aware follow-up question
    case conversational = "conversational"

    /// Specification/technical data lookup
    case specification = "specification"
}

// MARK: - Eval Result

/// The result of evaluating a single test case.
struct RAGEvalResult: Codable, Identifiable, Sendable {
    /// Matches the eval case ID
    let id: String

    /// The query that was evaluated
    let query: String

    /// The pipeline's generated response
    let generatedResponse: String

    /// Whether the expected answer was found in the response
    let answerMatch: Bool

    /// Retrieval recall: fraction of ground truth chunks retrieved
    let retrievalRecall: Double?

    /// Citation precision: fraction of cited sources that are correct
    let citationPrecision: Double?

    /// Whether the pipeline correctly abstained (or correctly didn't)
    let abstentionCorrect: Bool

    /// Response latency in seconds
    let latencySeconds: Double

    /// Tokens generated
    let tokensGenerated: Int?

    /// The quality mode used
    let qualityModeUsed: String

    /// Whether context overflow occurred
    let contextOverflow: Bool

    /// Visual evidence was used (for visual_evidence category)
    let usedVisualEvidence: Bool?

    /// Any warnings or issues detected
    let warnings: [String]

    /// Timestamp of evaluation
    let timestamp: Date
}
