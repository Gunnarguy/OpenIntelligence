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
        let validKeywords = keywords.filter { !AtlasLabeling.terms(in: $0).isEmpty }
        if !validKeywords.isEmpty {
            return AtlasLabeling.formatTerms(validKeywords)
        }
        if !sampleContent.isEmpty {
            let names = AtlasLabeling.clusterNames(groups: [sampleContent])
            if let first = names.first, !first.isEmpty {
                return first
            }
        }
        return "Group 1"
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
