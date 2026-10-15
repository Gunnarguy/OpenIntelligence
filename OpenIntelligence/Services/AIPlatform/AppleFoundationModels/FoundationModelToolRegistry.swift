//
//  FoundationModelToolRegistry.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

#if canImport(CoreSpotlight)
import CoreSpotlight
#endif

#if canImport(Vision)
import Vision
#endif

#if canImport(_Vision_FoundationModels)
import _Vision_FoundationModels
#endif

#if canImport(_CoreSpotlight_FoundationModels)
import _CoreSpotlight_FoundationModels
#endif

// MARK: - Tool Protocol Implementations for Function Calling
//
// Six tools declared here were registered nowhere (SearchDocuments, ListDocuments,
// GetDocumentSummary, GetCorpusStats, FindRelatedDocuments, CompareDocuments); a tool reaches
// a model only through `createTools`. They were removed in 5.7 (row "Six agentic tools are
// declared but registered nowhere"); the RAGService methods they called stay, for the
// diagnostics screens that use them.
// TOKEN BUDGET: Apple FM has 4096 token context limit (~10K chars).
// Each tool output should be ≤1500 chars to leave room for prompt + response.
// All tools MUST truncate results to respect this budget.

// MARK: - Exact Search Tools (Full-Text, Not Semantic)

/// Tool for counting exact pattern occurrences across ALL documents
/// Uses FullTextStorageService for precise counting (not semantic search)
@available(iOS 26.0, macOS 26.0, *)
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
@available(iOS 26.0, macOS 26.0, *)
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

// MARK: - Consolidated Engine-Native Tool Surface

/// Core retrieval tool for semantic, exact, and related-document evidence access.
@available(iOS 26.0, macOS 26.0, *)
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
@available(iOS 26.0, macOS 26.0, *)
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
@available(iOS 26.0, macOS 26.0, *)
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
@available(iOS 26.0, macOS 26.0, *)
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

// MARK: - System-Provided FoundationModels Tools (iOS 27 / macOS 27)

/// Two tools the system provides for FoundationModels sessions from iOS 27: one reads text from
/// an image, one searches a Core Spotlight index. Both are off unless their switch is set,
/// because a tool's description takes room in the model's small window on every request and
/// neither has been tried on a device with this app's questions yet.
@available(iOS 26.0, macOS 26.0, *)
nonisolated enum SystemModelTools {
    static let ocrKey = "systemTools.ocr.enabled"
    static let spotlightSearchKey = "systemTools.spotlightSearch.enabled"

    static func isOCREnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: ocrKey)
    }

    static func isSpotlightSearchEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: spotlightSearchKey)
    }

    // MARK: - System Tools Construction

    /// Returns the system tools to add for iOS 27 / macOS 27 given the configured flags.
    ///
    /// - OCRTool when `systemTools.ocr.enabled` is on.
    /// - SpotlightSearchTool configured to search ONLY the app's own Core Spotlight index
    ///   (CoreSpotlightSource, never FileSource), capped at 8 results and a 1500-character
    ///   maximum response size, when `systemTools.spotlightSearch.enabled` is on.
    static func systemTools(defaults: UserDefaults = .standard) -> [any Tool] {
        systemTools(
            ocrEnabled: isOCREnabled(defaults: defaults),
            spotlightSearchEnabled: isSpotlightSearchEnabled(defaults: defaults)
        )
    }

    /// Returns system tools given explicit flag values.
    static func systemTools(
        ocrEnabled: Bool,
        spotlightSearchEnabled: Bool
    ) -> [any Tool] {
        var tools: [any Tool] = []

        #if canImport(_Vision_FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            if ocrEnabled {
                tools.append(OCRTool())
            }
        }
        #endif

        #if canImport(_CoreSpotlight_FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            if spotlightSearchEnabled {
                // Search ONLY the app's own Core Spotlight index via CoreSpotlightSource
                // (never FileSource, which searches filesystem directories). Limit results
                // to at most 8 items and response size to 1500 UTF-8 characters to protect
                // the on-device model's ~4096 token budget.
                var source = CoreSpotlightSource()
                source.maximumResultCount = 8
                let configuration = SpotlightSearchTool.Configuration(
                    sources: [.coreSpotlight(source)],
                    maximumResponseSize: 1500
                )
                tools.append(SpotlightSearchTool(configuration: configuration))
            }
        }
        #endif

        return tools
    }

}

@available(iOS 26.0, macOS 26.0, *)
struct FoundationModelToolRegistry {
    static func createTools(toolHandler: RAGToolHandler?) -> [any Tool] {
        guard let ragService = toolHandler as? RAGService else {
            Log.debug("[Tools] No RAGService handler, so this session gets no tools", category: .pipeline)
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

        // The two exact-lexical tools. Registered 2026-08-13 because the benchmark argues for
        // them, and deliberately without the other six declared in this file, which duplicate a
        // tool already above: search_documents and find_related_documents are covered by
        // retrieve_corpus_evidence, list_documents and get_corpus_stats by get_library_overview,
        // get_document_summary by inspect_document, compare_documents by
        // compare_topic_across_documents. Handing the model six near-duplicates costs context
        // budget every turn and degrades selection; HARD_LIMITS puts the useful ceiling around
        // five. Six live tools stays near that.
        //
        // Why these two specifically. On the 2026-08-12 external benchmark the lexical arm scored
        // MRR@10 0.65 against the dense arm's 0.28, so exact matching is what this pipeline is
        // currently good at, and nothing registered exposed it to the model directly. Extractive
        // fact-lookup was the weakest category at 19/51 correct, which is exactly the "what number
        // does the paper give" question these serve. `Step 4.8 Targeted Spec Retrieval` already
        // exists in the pipeline for the same reason: the cross-encoder carries a measured prose
        // bias, roughly 0.78 for prose against 0.30 for tables.
        //
        // This is a hypothesis, not a finding. Re-run qasper_external_v1 and compare the
        // exact_value category against Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md
        // before concluding it helped.
        var countTool = CountPatternTool()
        countTool.ragService = ragService
        tools.append(countTool)

        var exactTool = SearchExactPatternTool()
        exactTool.ragService = ragService
        tools.append(exactTool)

        Log.debug("Initialized \(tools.count) engine-native tools for agentic RAG", category: .llm)

        let systemTools = SystemModelTools.systemTools()
        if !systemTools.isEmpty {
            let names = systemTools.map(\.name).joined(separator: ", ")
            Log.debug("Added system FoundationModels tools: \(names)", category: .llm)
            tools.append(contentsOf: systemTools)
        }

        return tools
    }
}

#endif
