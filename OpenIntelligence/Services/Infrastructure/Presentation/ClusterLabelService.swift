//
//  ClusterLabelService.swift
//  OpenIntelligence
//
//  Generates intelligent, context-aware labels for document clusters in the Atlas visualization.
//  Uses Apple Intelligence (FoundationModels) to analyze chunk content and produce meaningful
//  topic names like "Vehicle Settings", "Infotainment System", "Maintenance & Fluids" instead
//  of generic labels like "UI • images" or "Data • page".
//
//  Created by OpenIntelligence on 1/27/26.
//

import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Cluster Label Service

/// Service for generating intelligent, content-aware labels for document clusters
/// Uses LLM to analyze chunk content and produce meaningful topic names
actor ClusterLabelService {

    // MARK: - Singleton

    static let shared = ClusterLabelService()

    // MARK: - Cache

    /// Cache of generated labels by container ID
    /// Key: containerID, Value: [clusterKeywords hash: generated label]
    private var labelCache: [UUID: [String: String]] = [:]

    /// Cache of document-type inferences by container ID
    private var documentTypeCache: [UUID: String] = [:]

    /// Maximum cache entries per container
    private let maxCacheEntriesPerContainer = 100

    // MARK: - Types

    /// Lightweight struct for chunk data needed for labeling (avoids importing full DocumentChunk)
    struct ChunkInfo: Sendable {
        let content: String
        let keywords: [String]
        let sectionTitle: String?
    }

    // MARK: - Public API

    /// Generate a meaningful topic name from cluster keywords and sample content
    /// - Parameters:
    ///   - keywords: The top keywords found in this cluster
    ///   - sampleContent: Representative content samples from the cluster (2-3 chunks)
    ///   - documentContext: Optional document name/type for context (e.g., "2024 Kia Sportage Manual")
    ///   - containerId: Container ID for caching
    /// - Returns: A meaningful, descriptive topic name (e.g., "Infotainment Settings", "Oil Specifications")
    func generateClusterLabel(
        keywords: [String],
        sampleContent: [String],
        documentContext: String?,
        containerId: UUID
    ) async -> String {
        // Check cache first
        let cacheKey = keywords.sorted().joined(separator: "|")
        if let cached = labelCache[containerId]?[cacheKey] {
            return cached
        }

        // Try LLM-powered generation
        if let llmLabel = await generateLabelWithLLM(
            keywords: keywords,
            sampleContent: sampleContent,
            documentContext: documentContext
        ) {
            // Cache the result
            cacheLabel(llmLabel, for: cacheKey, containerId: containerId)
            return llmLabel
        }

        // Fallback to intelligent heuristic-based naming
        let fallbackLabel = generateHeuristicLabel(
            keywords: keywords,
            sampleContent: sampleContent,
            documentContext: documentContext
        )
        cacheLabel(fallbackLabel, for: cacheKey, containerId: containerId)
        return fallbackLabel
    }

    /// Batch generate labels for multiple clusters (more efficient)
    func generateClusterLabels(
        clusters: [(keywords: [String], sampleContent: [String])],
        documentContext: String?,
        containerId: UUID
    ) async -> [String] {
        var results: [String] = []
        results.reserveCapacity(clusters.count)

        // Process in parallel with controlled concurrency
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, cluster) in clusters.enumerated() {
                group.addTask {
                    let label = await self.generateClusterLabel(
                        keywords: cluster.keywords,
                        sampleContent: cluster.sampleContent,
                        documentContext: documentContext,
                        containerId: containerId
                    )
                    return (index, label)
                }
            }

            var indexed: [(Int, String)] = []
            for await result in group {
                indexed.append(result)
            }

            // Sort by original index and extract labels
            results = indexed.sorted { $0.0 < $1.0 }.map { $0.1 }
        }

        return results
    }

    /// Infer the document type/domain from content (cached per container)
    func inferDocumentType(
        from chunks: [ChunkInfo],
        documentNames: [String],
        containerId: UUID
    ) async -> String {
        // Check cache
        if let cached = documentTypeCache[containerId] {
            return cached
        }

        // Analyze document names and content to infer type
        let docType = analyzeDocumentType(chunks: chunks, documentNames: documentNames)
        documentTypeCache[containerId] = docType
        return docType
    }

    /// Clear cache for a container (call when documents change)
    func invalidateCache(for containerId: UUID) {
        labelCache.removeValue(forKey: containerId)
        documentTypeCache.removeValue(forKey: containerId)
    }

    /// Clear all caches
    func invalidateAllCaches() {
        labelCache.removeAll()
        documentTypeCache.removeAll()
    }

    // MARK: - LLM-Powered Label Generation

    @available(iOS 26.0, *)
    private func generateLabelWithLLM(
        keywords: [String],
        sampleContent: [String],
        documentContext: String?
    ) async -> String? {
        #if canImport(FoundationModels)
        do {
            // Check availability
            guard SystemLanguageModel.default.isAvailable else {
                return nil // Apple FM not available
            }

            // Build a concise prompt (stay within token limits)
            let prompt = buildLabelingPrompt(
                keywords: keywords,
                sampleContent: sampleContent,
                documentContext: documentContext
            )

            // Create a fresh session for this single-shot generation
            // Built with an explicit model and instructions, not the bare `LanguageModelSession()`.
            // Every service that used the bare initialiser failed deterministically with
            // ParsingError / "Session ended without producing a response", while every path built
            // through `FoundationModelSessionFactory` (which supplies `model:` and `instructions:`)
            // succeeded. Confirmed on an empty library with the one-word query "Test" and zero
            // retrieved chunks, which rules out content, guardrails, context size and token caps.
            // An Instruments capture of the Foundation Models template shows `assets: ""` on exactly
            // these responses, consistent with a session that never received its model assets.
            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                instructions: Instructions("You label groups of documents. Be concise.")
            )

            let response = try await session.respond(to: prompt)
            let label = cleanGeneratedLabel(response.content)

            // Validate the label is reasonable
            guard isValidLabel(label) else {
                return nil // Invalid label generated
            }

            return label

        } catch {
            return nil // LLM generation failed
        }
        #else
        return nil
        #endif
    }

    private func buildLabelingPrompt(
        keywords: [String],
        sampleContent: [String],
        documentContext: String?
    ) -> String {
        // Keep prompt VERY short to fit in Apple FM's token limit
        var prompt = "Generate a 2-4 word topic label for this document section.\n\n"

        if let context = documentContext, !context.isEmpty {
            prompt += "Document: \(context)\n"
        }

        prompt += "Keywords: \(keywords.prefix(5).joined(separator: ", "))\n"

        // Only include a brief sample (first 200 chars of first sample)
        if let firstSample = sampleContent.first {
            let truncated = String(firstSample.prefix(200))
            prompt += "Sample: \(truncated)\n"
        }

        prompt += "\nRespond with ONLY the topic label (2-4 words, no quotes or explanation)."
        prompt += "\nExamples: 'System Overview', 'Technical Specifications', 'Safety Guidelines', 'Getting Started'"

        return prompt
    }

    private func cleanGeneratedLabel(_ raw: String) -> String {
        var label = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")

        // Remove common prefixes the LLM might add
        let prefixes = ["Topic:", "Label:", "Title:", "Section:"]
        for prefix in prefixes {
            if label.lowercased().hasPrefix(prefix.lowercased()) {
                label = String(label.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }

        // Truncate if too long
        if label.count > 30 {
            let words = label.split(separator: " ").prefix(4)
            label = words.joined(separator: " ")
        }

        // Title case
        label = label.split(separator: " ")
            .map { word in
                let lower = word.lowercased()
                // Don't capitalize small words unless they're first
                if ["a", "an", "the", "and", "or", "of", "for", "in", "on", "to", "with"].contains(lower) {
                    return String(lower)
                }
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            .joined(separator: " ")

        // Capitalize first word
        if let first = label.first {
            label = first.uppercased() + label.dropFirst()
        }

        return label
    }

    private func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty else { return false }
        guard label.count >= 3 && label.count <= 40 else { return false }

        // Should have at least 1 word
        let wordCount = label.split(separator: " ").count
        guard wordCount >= 1 && wordCount <= 6 else { return false }

        // Shouldn't be just generic words
        let genericLabels = Set(["general", "content", "information", "data", "text", "document", "section", "unknown"])
        if genericLabels.contains(label.lowercased()) {
            return false
        }

        return true
    }

    // MARK: - Heuristic-Based Label Generation (Fallback)

    private func generateHeuristicLabel(
        keywords: [String],
        sampleContent: [String],
        documentContext: String?
    ) -> String {
        // Combine all text for analysis
        let allText = (sampleContent.joined(separator: " ") + " " + keywords.joined(separator: " ")).lowercased()

        // Infer document domain from context
        let domain = inferDomain(from: documentContext, content: allText)

        // Domain-specific label generation
        switch domain {
        case .technical:
            return generateTechnicalLabel(keywords: keywords, content: allText)
        case .legal:
            return generateLegalLabel(keywords: keywords, content: allText)
        case .medical:
            return generateMedicalLabel(keywords: keywords, content: allText)
        case .financial:
            return generateFinancialLabel(keywords: keywords, content: allText)
        case .academic:
            return generateAcademicLabel(keywords: keywords, content: allText)
        case .general:
            return generateGeneralLabel(keywords: keywords, content: allText)
        }
    }

    private enum DocumentDomain {
        case technical
        case legal
        case medical
        case financial
        case academic
        case general
    }

    private func inferDomain(from context: String?, content: String) -> DocumentDomain {
        let text = (context ?? "").lowercased() + " " + content.lowercased()

        // Score each domain by keyword match count (most matches wins, no priority bias)
        let domainTerms: [(DocumentDomain, [String])] = [
            (.technical, ["api", "function", "code", "software", "algorithm", "database", "server",
                         "programming", "developer", "git", "deploy", "cloud", "kubernetes"]),
            (.legal, ["agreement", "contract", "liability", "hereby", "pursuant", "jurisdiction",
                     "plaintiff", "defendant", "court", "law", "legal", "attorney"]),
            (.medical, ["study", "protocol", "cohort", "assay", "sample", "specimen",
                       "biology", "life science", "biomarker", "literature", "methods", "outcome"]),
            (.financial, ["revenue", "profit", "investment", "portfolio", "stock", "market",
                         "financial", "accounting", "budget", "expense", "asset"]),
            (.academic, ["research", "hypothesis", "methodology", "findings", "abstract",
                        "study", "thesis", "dissertation", "peer-reviewed", "journal"]),
        ]

        var bestDomain: DocumentDomain = .general
        var bestScore = 0
        for (domain, terms) in domainTerms {
            let score = terms.filter { text.contains($0) }.count
            if score > bestScore {
                bestScore = score
                bestDomain = domain
            }
        }

        // Require at least 2 matching terms to claim a domain
        return bestScore >= 2 ? bestDomain : .general
    }

    // MARK: - Domain-Specific Label Generators

    private func generateTechnicalLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["api", "endpoint", "rest", "graphql", "request", "response"], "API Reference"),
            (["authentication", "auth", "oauth", "token", "login", "jwt"], "Authentication"),
            (["database", "sql", "query", "schema", "table", "index"], "Database"),
            (["deployment", "deploy", "ci/cd", "pipeline", "docker", "kubernetes"], "Deployment"),
            (["configuration", "config", "settings", "environment", "env"], "Configuration"),
            (["testing", "test", "unit test", "integration", "spec"], "Testing"),
            (["error", "exception", "debugging", "troubleshoot", "log"], "Error Handling"),
            (["security", "encryption", "ssl", "tls", "https"], "Security"),
            (["performance", "optimization", "cache", "latency", "speed"], "Performance"),
            (["architecture", "design", "pattern", "structure", "system"], "Architecture"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: "Guide")
    }

    private func generateLegalLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["liability", "indemnify", "indemnification", "damages"], "Liability & Indemnity"),
            (["confidential", "nda", "non-disclosure", "proprietary"], "Confidentiality"),
            (["termination", "cancel", "expiration", "end"], "Termination"),
            (["payment", "fee", "compensation", "billing"], "Payment Terms"),
            (["intellectual property", "ip", "copyright", "trademark", "patent"], "Intellectual Property"),
            (["dispute", "arbitration", "mediation", "resolution"], "Dispute Resolution"),
            (["warranty", "guarantee", "representation"], "Warranties"),
            (["compliance", "regulation", "gdpr", "hipaa"], "Compliance"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: "Terms")
    }

    private func generateMedicalLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["study", "protocol", "cohort", "trial"], "Study Design"),
            (["assay", "sample", "specimen", "cell"], "Assay Notes"),
            (["protein", "gene", "genome", "biomarker"], "Biomarkers"),
            (["method", "methods", "procedure", "intervention"], "Methods"),
            (["result", "finding", "outcome", "endpoint"], "Results"),
            (["lab", "test", "measurement", "signal"], "Measurements"),
            (["analysis", "statistics", "p-value", "confidence"], "Analysis"),
            (["literature", "citation", "abstract", "paper"], "Literature"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: "Information")
    }

    private func generateFinancialLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["revenue", "income", "earnings", "proceeds"], "Revenue Analysis"),
            (["expense", "cost", "spending", "overhead"], "Expenses"),
            (["investment", "portfolio", "return", "roi"], "Investments"),
            (["budget", "forecast", "projection", "plan"], "Budget & Forecast"),
            (["tax", "taxation", "deduction", "credit"], "Tax Information"),
            (["risk", "assessment", "management", "exposure"], "Risk Management"),
            (["compliance", "audit", "regulation", "sox"], "Compliance & Audit"),
            (["cash flow", "liquidity", "working capital"], "Cash Flow"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: "Analysis")
    }

    private func generateAcademicLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["abstract", "summary", "overview"], "Abstract"),
            (["introduction", "background", "context"], "Introduction"),
            (["methodology", "method", "approach", "design"], "Methodology"),
            (["result", "finding", "data", "observation"], "Results"),
            (["discussion", "analysis", "interpretation"], "Discussion"),
            (["conclusion", "summary", "implication"], "Conclusions"),
            (["reference", "citation", "bibliography", "source"], "References"),
            (["literature", "review", "prior work", "related"], "Literature Review"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: "Section")
    }

    private func generateGeneralLabel(keywords: [String], content: String) -> String {
        let patterns: [(terms: [String], label: String)] = [
            (["introduction", "overview", "about", "getting started"], "Introduction"),
            (["faq", "question", "answer", "frequently"], "FAQ"),
            (["glossary", "term", "definition", "vocabulary"], "Glossary"),
            (["appendix", "reference", "additional", "supplementary"], "Appendix"),
        ]

        return matchPatternLabel(patterns: patterns, keywords: keywords, content: content)
            ?? generateFallbackLabel(keywords: keywords, suffix: nil)
    }

    // MARK: - Helper Methods

    private func matchPatternLabel(
        patterns: [(terms: [String], label: String)],
        keywords: [String],
        content: String
    ) -> String? {
        let allText = (keywords.joined(separator: " ") + " " + content).lowercased()

        // Score each pattern by how many terms match
        var bestMatch: (label: String, score: Int)?

        // Whole words, not substrings.
        //
        // `allText.contains(term)` scored a neuroscience paper as "API Reference"
        // because `"api"` matches inside ther**api**es and `"rest"` inside inte**rest**,
        // and as "Glossary" because `"term"` matches inside de**term**ined. Observed on
        // device 2026-08-26: a psychiatry review on dopamine and serotonin signalling
        // clustered as "API Reference" and "Glossary" in the Semantic Atlas, labels with
        // no relationship to the document.
        //
        // Fourth instance of this defect family in this release, after the
        // specification keyword lists, `extractivePriorityScore`, and the PartNumber
        // pattern. `containsTerm` is the shared matcher those fixes standardised on and
        // it handles multi-word entries like `"unit test"` as phrases.
        for pattern in patterns {
            var score = 0
            for term in pattern.terms {
                if HybridSearchService.containsTerm(allText, term) {
                    score += 1
                }
            }
            if score > 0 && (bestMatch == nil || score > bestMatch!.score) {
                bestMatch = (pattern.label, score)
            }
        }

        return bestMatch?.label
    }

    private func generateFallbackLabel(keywords: [String], suffix: String?) -> String {
        // Filter to meaningful keywords
        let meaningfulKeywords = keywords.filter { keyword in
            let word = keyword.lowercased()
            let skipWords: Set<String> = [
                // Pronouns / Articles / Conjunctions / Grammatical noise
                "the", "and", "for", "with", "this", "that", "from", "have", "are",
                "was", "were", "been", "will", "would", "could", "should", "can",
                "its", "use", "see", "set", "get", "one", "two", "also", "more",
                "general", "content", "information", "data", "text", "document",
                "our", "your", "their", "his", "her", "only", "other", "some",
                "many", "much", "most", "few", "all", "any", "both", "each", "every",
                "same", "different", "new", "old", "high", "low", "great", "small",
                "large", "good", "bad", "best", "worst", "true", "false", "yes", "no",
                "not", "non", "without", "into", "onto", "over", "under", "after",
                "before", "between", "among", "through", "during", "while", "until",
                
                // Generic structural, formatting, and layout noise
                "part", "parts", "list", "lists", "step", "steps", "page", "pages",
                "section", "sections", "chapter", "chapters", "table", "tables",
                "row", "rows", "column", "columns", "col", "cols", "line", "lines",
                "cell", "cells", "item", "items", "detail", "details", "description",
                "descriptions", "summary", "summaries", "overview", "introduction",
                "conclusion", "conclusions", "appendix", "appendices", "figure",
                "figures", "fig", "figs", "image", "images", "photo", "photos",
                "graph", "graphs", "chart", "charts", "diagram", "diagrams",
                "value", "values", "number", "numbers", "digit", "digits", "type",
                "types", "form", "forms", "group", "groups", "user", "users",
                "read", "write", "show", "find", "here", "there", "problem", "problems",
                "issue", "issues", "solution", "solutions"
            ]
            return word.count >= 3 &&
                   !skipWords.contains(word) &&
                   word.first?.isLetter == true
        }

        guard !meaningfulKeywords.isEmpty else {
            return suffix ?? "General Content"
        }

        // Title case the top keywords
        let topKeywords = meaningfulKeywords.prefix(2).map { keyword -> String in
            keyword.prefix(1).uppercased() + keyword.dropFirst().lowercased()
        }

        var label = topKeywords.joined(separator: " & ")

        if let suffix = suffix, !label.lowercased().contains(suffix.lowercased()) {
            label += " \(suffix)"
        }

        return label
    }

    private func analyzeDocumentType(chunks: [ChunkInfo], documentNames: [String]) -> String {
        // Combine document names and sample content
        let nameText = documentNames.joined(separator: " ").lowercased()
        let sampleText = chunks.prefix(10).map { $0.content }.joined(separator: " ").lowercased()

        let domain = inferDomain(from: nameText, content: sampleText)

        switch domain {
        case .technical: return "Technical Documentation"
        case .legal: return "Legal Document"
        case .medical: return "Medical Document"
        case .financial: return "Financial Document"
        case .academic: return "Academic Paper"
        case .general: return "Document"
        }
    }

    // MARK: - Cache Management

    private func cacheLabel(_ label: String, for key: String, containerId: UUID) {
        if labelCache[containerId] == nil {
            labelCache[containerId] = [:]
        }

        // Limit cache size
        if let count = labelCache[containerId]?.count, count >= maxCacheEntriesPerContainer {
            // Remove some entries to make room (simple eviction)
            if var cache = labelCache[containerId] {
                let keysToRemove = Array(cache.keys.prefix(10))
                for keyToRemove in keysToRemove {
                    cache.removeValue(forKey: keyToRemove)
                }
                labelCache[containerId] = cache
            }
        }

        labelCache[containerId]?[key] = label
    }
}
