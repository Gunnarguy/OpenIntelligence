//
//  FoundationModelToolRegistry.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Tool Protocol Implementations for Function Calling
// TOKEN BUDGET: Apple FM has 4096 token context limit (~10K chars).
// Each tool output should be ≤1500 chars to leave room for prompt + response.
// All tools MUST truncate results to respect this budget.

/// Tool for searching user's document library
@available(iOS 26.0, macOS 16.0, *)
struct SearchDocumentsTool: Tool {
    let name = "search_documents"
    let description =
        "Search the user's document library for relevant information based on a query. Returns the most relevant text chunks with citations."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description:
            "The search query to find relevant document chunks. Be specific and use keywords from the user's question."
        )
        var query: String
        @Guide(
            description:
            "Maximum number of chunks to retrieve. Use 2–4 for brief summaries, 8–12 for deep dives.",
            .range(1 ... 20)
        )
        var topK: Int?
        @Guide(
            description:
            "Minimum semantic similarity threshold. Use 0.35 by default; increase to filter noise.",
            .range(0.0 ... 1.0)
        )
        var minSimilarity: Float?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document search service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.searchDocuments(
            query: arguments.query,
            topK: arguments.topK,
            minSimilarity: arguments.minSimilarity
        )
    }
}

/// Tool for listing all available documents
@available(iOS 26.0, macOS 16.0, *)
struct ListDocumentsTool: Tool {
    let name = "list_documents"
    let description =
        "List all documents in the user's library. Returns document names, types, page counts, and dates added."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        // No arguments needed for listing
    }

    func call(arguments _: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.listDocuments()
    }
}

/// Tool for getting summary of a specific document
@available(iOS 26.0, macOS 16.0, *)
struct GetDocumentSummaryTool: Tool {
    let name = "get_document_summary"
    let description =
        "Get detailed information about a specific document including metadata, content summary, and statistics."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description:
            "The exact name of the document to get details about. Use list_documents first to see available names."
        )
        var documentName: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.getDocumentSummary(documentName: arguments.documentName)
    }
}

// MARK: - Exact Search Tools (Full-Text, Not Semantic)

/// Tool for counting exact pattern occurrences across ALL documents
/// Uses FullTextStorageService for precise counting (not semantic search)
@available(iOS 26.0, macOS 16.0, *)
struct CountPatternTool: Tool {
    let name = "count_pattern"
    let description = """
        Count EXACT occurrences of a text pattern across ALL documents in the library.
        Returns per-document counts and total. Use for questions like "how many times is X mentioned?"
        This searches the complete original text, not chunked embeddings.
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description: """
                The exact text pattern to count. Case-insensitive.
                For multi-word phrases, include the full phrase.
                Examples: "SAE 0W-20", "transmission fluid", "warning light"
                """
        )
        var pattern: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.countPatternInCorpus(pattern: arguments.pattern)
    }
}

/// Tool for searching exact text patterns with surrounding context
/// Uses FullTextStorageService for precise matching (not semantic search)
@available(iOS 26.0, macOS 16.0, *)
struct SearchExactPatternTool: Tool {
    let name = "search_exact_pattern"
    let description = """
        Search for EXACT text matches across ALL documents and return context.
        Unlike semantic search, this finds precise string matches.
        Use when you need to find specific terms, codes, model numbers, or exact phrases.
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description: """
                The exact text pattern to search for. Case-insensitive.
                Will return surrounding context for each match.
                Examples: "serial number", "model specification", "error code 404"
                """
        )
        var pattern: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.searchExactPattern(pattern: arguments.pattern)
    }
}

// MARK: - Analysis Tools

/// Tool for getting corpus-wide statistics and analysis
@available(iOS 26.0, macOS 16.0, *)
struct GetCorpusStatsTool: Tool {
    let name = "get_corpus_stats"
    let description = """
        Get statistics about the entire document library including:
        - Total documents and pages
        - Document types breakdown
        - Total word/character counts
        - Average document size
        Use for questions about the library itself.
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        // No arguments needed for corpus stats
    }

    func call(arguments _: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.getCorpusStats()
    }
}

/// Tool for finding documents related to a topic
@available(iOS 26.0, macOS 16.0, *)
struct FindRelatedDocumentsTool: Tool {
    let name = "find_related_documents"
    let description = """
        Find documents that are semantically related to a topic or query.
        Returns document names ranked by relevance, not individual chunks.
        Use when you need to identify WHICH documents cover a topic.
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description: "Topic or query to find related documents for"
        )
        var topic: String
        @Guide(
            description: "Maximum number of documents to return",
            .range(1 ... 20)
        )
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.findRelatedDocuments(
            topic: arguments.topic,
            maxResults: arguments.maxResults ?? 5
        )
    }
}

/// Tool for comparing content across multiple documents
@available(iOS 26.0, macOS 16.0, *)
struct CompareDocumentsTool: Tool {
    let name = "compare_documents"
    let description = """
        Compare how multiple documents discuss the same topic.
        Useful for finding differences, contradictions, or complementary information.
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(
            description: "Topic to compare across documents"
        )
        var topic: String
        @Guide(
            description: "Names of specific documents to compare (optional, uses all if empty)"
        )
        var documentNames: [String]?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService = ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.compareDocumentsOnTopic(
            topic: arguments.topic,
            documentNames: arguments.documentNames
        )
    }
}

// MARK: - Consolidated Engine-Native Tool Surface

/// Core retrieval tool for semantic, exact, and related-document evidence access.
@available(iOS 26.0, macOS 16.0, *)
struct RetrieveCorpusEvidenceTool: Tool {
    let name = "retrieve_corpus_evidence"
    let description = """
        Retrieve grounded evidence from the user's library.
        Modes:
        - semantic: retrieve relevant passages for a question
        - exact: find exact text matches with context
        - count_exact: count exact text occurrences across the corpus
        - related_documents: find which documents are most related to a topic
        """

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(description: "Question, topic, or literal pattern to search for")
        var query: String

        @Guide(description: "Mode: semantic, exact, count_exact, or related_documents")
        var mode: String

        @Guide(description: "Maximum number of results to return", .range(1 ... 20))
        var maxResults: Int?

        @Guide(description: "Minimum semantic similarity threshold for semantic mode", .range(0.0 ... 1.0))
        var minSimilarity: Float?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService else {
            return "Error: Retrieval service unavailable"
        }
        await ToolCallCounter.shared.increment()

        switch arguments.mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "exact":
            return try await ragService.searchExactPattern(pattern: arguments.query)
        case "count_exact":
            return try await ragService.countPatternInCorpus(pattern: arguments.query)
        case "related_documents":
            return try await ragService.findRelatedDocuments(
                topic: arguments.query,
                maxResults: arguments.maxResults ?? 5
            )
        default:
            return try await ragService.searchDocuments(
                query: arguments.query,
                topK: arguments.maxResults,
                minSimilarity: arguments.minSimilarity
            )
        }
    }
}

/// Inspect a specific document for summary and metadata.
@available(iOS 26.0, macOS 16.0, *)
struct InspectDocumentTool: Tool {
    let name = "inspect_document"
    let description = "Inspect a specific document by name and return its summary, metadata, and content overview."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(description: "Exact document name to inspect")
        var documentName: String
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService else {
            return "Error: Document service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.getDocumentSummary(documentName: arguments.documentName)
    }
}

/// Compare how documents discuss a topic.
@available(iOS 26.0, macOS 16.0, *)
struct CompareTopicAcrossDocumentsTool: Tool {
    let name = "compare_topic_across_documents"
    let description = "Compare how multiple documents discuss the same topic to find differences, overlap, and supporting evidence."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        @Guide(description: "Topic to compare across documents")
        var topic: String

        @Guide(description: "Optional specific document names to compare")
        var documentNames: [String]?
    }

    func call(arguments: Arguments) async throws -> String {
        guard let ragService else {
            return "Error: Comparison service unavailable"
        }
        await ToolCallCounter.shared.increment()
        return try await ragService.compareDocumentsOnTopic(
            topic: arguments.topic,
            documentNames: arguments.documentNames
        )
    }
}

/// High-level library overview tool for corpus-wide inspection.
@available(iOS 26.0, macOS 16.0, *)
struct GetLibraryOverviewTool: Tool {
    let name = "get_library_overview"
    let description = "Return a compact overview of the current library, including corpus stats and available documents."

    weak var ragService: RAGService?

    @Generable
    struct Arguments {
        // No arguments needed
    }

    func call(arguments _: Arguments) async throws -> String {
        guard let ragService else {
            return "Error: Library service unavailable"
        }
        await ToolCallCounter.shared.increment()

        let stats = try await ragService.getCorpusStats()
        let documents = try await ragService.listDocuments()
        return stats + "\n\nDOCUMENTS:\n" + documents
    }
}

@available(iOS 26.0, macOS 16.0, *)
struct FoundationModelToolRegistry {
    static func createTools(toolHandler: RAGToolHandler?) -> [any Tool] {
        guard let ragService = toolHandler as? RAGService else {
            return []
        }

        var tools: [any Tool] = []

        var retrieveTool = RetrieveCorpusEvidenceTool()
        retrieveTool.ragService = ragService
        tools.append(retrieveTool)

        var inspectTool = InspectDocumentTool()
        inspectTool.ragService = ragService
        tools.append(inspectTool)

        var compareTool = CompareTopicAcrossDocumentsTool()
        compareTool.ragService = ragService
        tools.append(compareTool)

        var overviewTool = GetLibraryOverviewTool()
        overviewTool.ragService = ragService
        tools.append(overviewTool)

        Log.debug("Initialized \(tools.count) engine-native tools for agentic RAG", category: .llm)
        return tools
    }
}

#endif
