//
//  RAGStructuredResponse.swift
//  OpenIntelligence
//
//  @Generable structured types for guaranteed-format RAG responses.
//  Uses Apple Foundation Models' constrained decoding for type-safe LLM output.
//
//  Benefits:
//  - Guaranteed JSON structure (no parsing failures)
//  - Explicit confidence scores and citations
//  - Enables downstream processing (UI badges, analytics, source verification)
//

#if canImport(FoundationModels)
    import Foundation
    import FoundationModels

    // MARK: - Core RAG Response Types

    /// Structured RAG answer with guaranteed citations and confidence
    /// Used when requesting answers from document context
    @available(iOS 26.0, *)
    @Generable
    struct RAGAnswerClaim {
        @Guide(description: "Single grounded claim from the answer. Keep it atomic and evidence-backed.")
        var claim: String

        @Guide(description: "Source ids like [S1], [S2] that directly support this claim.")
        var citations: [String]

        @Guide(description: "True when the claim is mostly extractive rather than synthesized.")
        var isExtracted: Bool
    }

    /// Structured RAG answer with guaranteed citations and confidence
    /// Used when requesting answers from document context
    @available(iOS 26.0, *)
    @Generable
    struct RAGAnswer {
        @Guide(description: "Think through the answer from the excerpts first. Keep the reasoning grounded, concise, and focused on which source facts support the answer.")
        var reasoning: String

        @Guide(description: "The direct answer synthesized from document content. Be concise but complete.")
        var answer: String

        @Guide(description: "Confidence score 0-100 based on source quality and relevance. 90+ means direct quote, 60-89 means strong inference, below 60 means partial or uncertain.")
        var confidence: Int

        @Guide(description: "Array of source ids such as [S1], [S2], matching the excerpt identifiers in the prompt.")
        var citations: [String]

        @Guide(description: "Claim-level breakdown of the answer. Keep each claim atomic and cite only the supporting source ids.")
        var claims: [RAGAnswerClaim]

        @Guide(description: "Key terms from the query that were found in sources. Helps verify retrieval quality.")
        var matchedTerms: [String]
    }

    @available(iOS 26.0, *)
    @Generable
    struct DirectRAGAnswer {
        @Guide(description: "The direct answer synthesized from document content. Be concise but complete.")
        var answer: String

        @Guide(description: "Confidence score 0-100 based on source quality and relevance. 90+ means direct quote, 60-89 means strong inference, below 60 means partial or uncertain.")
        var confidence: Int

        @Guide(description: "Array of source ids such as [S1], [S2], matching the excerpt identifiers in the prompt.")
        var citations: [String]

        @Guide(description: "Claim-level breakdown of the answer. Keep each claim atomic and cite only the supporting source ids.")
        var claims: [RAGAnswerClaim]

        @Guide(description: "Key terms from the query that were found in sources. Helps verify retrieval quality.")
        var matchedTerms: [String]
    }

#endif
