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
    struct RAGAnswer {
        @Guide(description: "The direct answer synthesized from document content. Be concise but complete.")
        var answer: String

        @Guide(description: "Confidence score 0-100 based on source quality and relevance. 90+ means direct quote, 60-89 means strong inference, below 60 means partial or uncertain.")
        var confidence: Int

        @Guide(description: "Array of source citations in format 'DocumentName (Page X)' or 'DocumentName' if no page number available.")
        var citations: [String]

        @Guide(description: "Key terms from the query that were found in sources. Helps verify retrieval quality.")
        var matchedTerms: [String]
    }

    /// Structured search result for document chunks
    /// Used when returning hybrid search results
    @available(iOS 26.0, *)
    @Generable
    struct RAGSearchResult {
        @Guide(description: "The source document name")
        var documentName: String

        @Guide(description: "Page number if available, otherwise 0")
        var pageNumber: Int

        @Guide(description: "The relevant text chunk content")
        var content: String

        @Guide(description: "Semantic similarity score 0.0-1.0")
        var similarity: Float

        @Guide(description: "Brief explanation of why this chunk matches the query")
        var relevanceReason: String
    }

    /// Structured collection of search results
    @available(iOS 26.0, *)
    @Generable
    struct RAGSearchResults {
        @Guide(description: "Array of relevant document chunks, ordered by relevance")
        var results: [RAGSearchResult]

        @Guide(description: "Total number of documents searched")
        var documentsSearched: Int

        @Guide(description: "The original search query")
        var query: String
    }

    // MARK: - Document Analysis Types

    /// Structured document summary
    @available(iOS 26.0, *)
    @Generable
    struct RAGDocumentSummary {
        @Guide(description: "Document file name")
        var name: String

        @Guide(description: "Document type: pdf, txt, md, etc.")
        var type: String

        @Guide(description: "Number of pages or sections")
        var pageCount: Int

        @Guide(description: "Number of text chunks indexed")
        var chunkCount: Int

        @Guide(description: "1-3 sentence summary of document content")
        var summary: String

        @Guide(description: "Key topics covered in the document")
        var topics: [String]

        @Guide(description: "Date document was added to library")
        var dateAdded: String
    }

    /// Structured document comparison
    @available(iOS 26.0, *)
    @Generable
    struct RAGDocumentComparison {
        @Guide(description: "First document being compared")
        var document1: String

        @Guide(description: "Second document being compared")
        var document2: String

        @Guide(description: "Key similarities between documents")
        var similarities: [String]

        @Guide(description: "Key differences between documents")
        var differences: [String]

        @Guide(description: "Overall comparison summary")
        var summary: String
    }

    // MARK: - Query Enhancement Types

    /// Structured query expansion for better retrieval
    @available(iOS 26.0, *)
    @Generable
    struct RAGEnhancedQuery {
        @Guide(description: "The original user query")
        var originalQuery: String

        @Guide(description: "Expanded query with synonyms and related terms")
        var expandedQuery: String

        @Guide(description: "Key entities extracted from query (names, dates, concepts)")
        var entities: [String]

        @Guide(description: "Inferred user intent: factual, comparative, exploratory, or procedural")
        var intent: String

        @Guide(description: "Suggested follow-up questions")
        var followUpQuestions: [String]
    }

    // MARK: - Diagnostic Types

    /// Structured retrieval diagnostics for debugging
    @available(iOS 26.0, *)
    @Generable
    struct RAGRetrievalDiagnostics {
        @Guide(description: "Number of chunks retrieved from vector store")
        var vectorHits: Int

        @Guide(description: "Number of chunks retrieved from BM25/keyword search")
        var bm25Hits: Int

        @Guide(description: "Number of chunks after RRF fusion")
        var fusedResults: Int

        @Guide(description: "Number of chunks after MMR diversification")
        var finalResults: Int

        @Guide(description: "Total retrieval latency in milliseconds")
        var latencyMs: Int

        @Guide(description: "Embedding provider used: nl_embedding, nl_contextual_embedding, etc.")
        var embeddingProvider: String

        @Guide(description: "Any warnings or issues detected")
        var warnings: [String]
    }

    // MARK: - Reasoning Chain Types (Apple FM Best Practice)
    // Per TN3193: Reasoning field FIRST lets the model think before answering
    // See: Docs/reference/FOUNDATION_MODELS_API.md

    /// Reasoned answer - model thinks through the problem before answering
    /// The reasoning field MUST be first so the model reasons BEFORE outputting answer
    @available(iOS 26.0, *)
    @Generable(description: "Answer with explicit reasoning steps")
    struct ReasonedAnswer {
        /// MUST BE FIRST - lets the model think step-by-step before committing to answer
        @Guide(description: "Think step-by-step: What key facts are relevant? What's the logical path to the answer?")
        var reasoning: String

        @Guide(description: "The final answer based on the reasoning above")
        var answer: String

        @Guide(description: "Confidence 0-100 in the answer")
        var confidence: Int

        @Guide(description: "Sources used: [S1], [S2], etc.")
        var sources: [String]
    }

    /// Reasoned insight - for building understanding across chained sessions
    /// Used when one session passes insight to the next
    @available(iOS 26.0, *)
    @Generable(description: "Key insight extracted from context")
    struct ReasonedInsight {
        /// MUST BE FIRST - reasoning before insight extraction
        @Guide(description: "What patterns or connections do you notice in this context?")
        var reasoning: String

        @Guide(description: "The key insight in 1-2 sentences")
        var insight: String

        @Guide(description: "Key terms/concepts discovered")
        var keyTerms: [String]

        @Guide(description: "Confidence 0-100")
        var confidence: Int
    }

    /// Reasoned synthesis - final step combining multiple insights
    @available(iOS 26.0, *)
    @Generable(description: "Final synthesis combining multiple insights")
    struct ReasonedSynthesis {
        /// MUST BE FIRST - reasoning about how insights connect
        @Guide(description: "How do these insights connect? What's the complete picture?")
        var reasoning: String

        @Guide(description: "Comprehensive answer integrating all insights")
        var synthesis: String

        @Guide(description: "Key points, numbered")
        var keyPoints: [String]

        @Guide(description: "Overall confidence 0-100")
        var confidence: Int

        @Guide(description: "All sources used")
        var sources: [String]
    }

    /// Chain link - represents one step in a reasoning chain
    /// Each link has its own 4096 token budget
    @available(iOS 26.0, *)
    @Generable(description: "One step in a reasoning chain")
    struct ChainLink {
        /// MUST BE FIRST
        @Guide(description: "What have I learned? What should I focus on next?")
        var reasoning: String

        @Guide(description: "Condensed insight to pass forward (max 2 sentences)")
        var insight: String

        @Guide(description: "Suggested focus for next step")
        var nextFocus: String

        @Guide(description: "Cumulative confidence 0-100")
        var confidence: Int
    }

#endif
