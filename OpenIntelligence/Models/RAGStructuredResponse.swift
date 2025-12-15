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

#endif
