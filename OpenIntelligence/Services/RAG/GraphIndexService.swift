//
//  GraphIndexService.swift
//  OpenIntelligence
//
//  Created Feb 2026 – AppleRAG Spec Implementation
//
//  Cross-reference and graph edge detection per AppleRAG spec §4.
//
//  Detects and indexes:
//  - "See page X" references
//  - "Refer to Table 5-2" / "Figure 3.1"
//  - "See Chapter 4" / "Section 2.3"
//  - Adjacent chunk neighbors (prev/next)
//  - Hierarchical parents (section → chapter → document)
//
//  This enables multi-hop retrieval where following references
//  often yields the answer faster than dense similarity search.
//

import Foundation
import NaturalLanguage

// MARK: - Cross-Reference Types

/// A detected cross-reference within chunk content
struct CrossReference: Sendable, Hashable {
    /// Type of reference
    let type: ReferenceType

    /// The raw text that was matched (e.g., "See page 47")
    let rawText: String

    /// Normalized target (e.g., "page:47", "table:5-2", "figure:3.1")
    let targetId: String

    /// Character range in source content
    let range: Range<Int>?

    enum ReferenceType: String, Codable, Sendable {
        case page
        case table
        case figure
        case section
        case chapter
        case appendix
        case step
        case item
        case unknown
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(targetId)
    }

    static func == (lhs: CrossReference, rhs: CrossReference) -> Bool {
        lhs.targetId == rhs.targetId
    }
}

/// Graph edges for a chunk (neighbors and cross-refs)
struct ChunkGraphEdges: Sendable {
    /// Previous chunk in document order (nil if first)
    var prevChunkId: UUID?

    /// Next chunk in document order (nil if last)
    var nextChunkId: UUID?

    /// Parent section/chapter chunk (if hierarchical)
    var parentChunkId: UUID?

    /// Child chunks under this section
    var childChunkIds: [UUID]

    /// Cross-references detected in content
    var crossReferences: [CrossReference]

    /// Chunks this one references (resolved from cross-references)
    var referencedChunkIds: [UUID]

    /// Chunks that reference this one
    var referencedByChunkIds: [UUID]

    nonisolated init() {
        self.childChunkIds = []
        self.crossReferences = []
        self.referencedChunkIds = []
        self.referencedByChunkIds = []
    }
}

// MARK: - Graph Index Service

/// Service for extracting cross-references and building graph edges
/// per AppleRAG spec §4 (CDM enrichment with graph_edges).
actor GraphIndexService {

    // MARK: - Reference Patterns

    /// Patterns for detecting cross-references
    /// Ordered by specificity (most specific first)
    private static let referencePatterns: [(pattern: String, type: CrossReference.ReferenceType, targetGroup: Int)] = [
        // Page references
        (#"[Ss]ee\s+[Pp]age\s+(\d+)"#, .page, 1),
        (#"[Rr]efer\s+to\s+[Pp]age\s+(\d+)"#, .page, 1),
        (#"[Pp]age\s+(\d+)"#, .page, 1),
        (#"\([Pp]\.\s*(\d+)\)"#, .page, 1),

        // Table references
        (#"[Ss]ee\s+[Tt]able\s+([\d\-\.]+)"#, .table, 1),
        (#"[Rr]efer\s+to\s+[Tt]able\s+([\d\-\.]+)"#, .table, 1),
        (#"[Tt]able\s+([\d\-\.]+)"#, .table, 1),

        // Figure references
        (#"[Ss]ee\s+[Ff]igure\s+([\d\-\.]+)"#, .figure, 1),
        (#"[Rr]efer\s+to\s+[Ff]igure\s+([\d\-\.]+)"#, .figure, 1),
        (#"[Ff]igure\s+([\d\-\.]+)"#, .figure, 1),
        (#"[Ff]ig\.\s*([\d\-\.]+)"#, .figure, 1),

        // Section references
        (#"[Ss]ee\s+[Ss]ection\s+([\d\-\.]+)"#, .section, 1),
        (#"[Rr]efer\s+to\s+[Ss]ection\s+([\d\-\.]+)"#, .section, 1),
        (#"[Ss]ection\s+([\d\-\.]+)"#, .section, 1),
        (#"§\s*([\d\-\.]+)"#, .section, 1),

        // Chapter references
        (#"[Ss]ee\s+[Cc]hapter\s+(\d+)"#, .chapter, 1),
        (#"[Cc]hapter\s+(\d+)"#, .chapter, 1),

        // Appendix references
        (#"[Ss]ee\s+[Aa]ppendix\s+([A-Z\d]+)"#, .appendix, 1),
        (#"[Aa]ppendix\s+([A-Z\d]+)"#, .appendix, 1),

        // Step references (for procedures)
        (#"[Ss]ee\s+[Ss]tep\s+(\d+)"#, .step, 1),
        (#"[Ss]tep\s+(\d+)"#, .step, 1),
    ]

    // Compiled regex cache
    private var compiledPatterns: [(regex: NSRegularExpression, type: CrossReference.ReferenceType, targetGroup: Int)] = []

    init() {
        // Pre-compile patterns
        for (pattern, type, group) in Self.referencePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                compiledPatterns.append((regex, type, group))
            }
        }
    }

    // MARK: - Cross-Reference Extraction

    /// Extract all cross-references from chunk content
    func extractCrossReferences(from content: String) -> [CrossReference] {
        extractCrossReferencesSync(from: content)
    }

    /// Synchronous extraction for use within actor-isolated contexts
    private nonisolated func extractCrossReferencesSync(from content: String) -> [CrossReference] {
        var references: [CrossReference] = []
        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)

        var matchedRanges: [NSRange] = []  // Avoid duplicates

        for (pattern, type, targetGroup) in Self.referencePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let matches = regex.matches(in: content, options: [], range: fullRange)

            for match in matches {
                // Skip if this range overlaps with a previous match
                let matchRange = match.range
                if matchedRanges.contains(where: { NSIntersectionRange($0, matchRange).length > 0 }) {
                    continue
                }

                let rawText = nsContent.substring(with: matchRange)

                // Extract target identifier
                if targetGroup <= match.numberOfRanges - 1 {
                    let targetRange = match.range(at: targetGroup)
                    if targetRange.location != NSNotFound {
                        let target = nsContent.substring(with: targetRange)
                        let targetId = "\(type.rawValue):\(target)"

                        let swiftRange = Range<Int>(uncheckedBounds: (matchRange.location, matchRange.location + matchRange.length))

                        references.append(CrossReference(
                            type: type,
                            rawText: rawText,
                            targetId: targetId,
                            range: swiftRange
                        ))

                        matchedRanges.append(matchRange)
                    }
                }
            }
        }

        return references
    }

    // MARK: - Graph Edge Building

    /// Build graph edges for an ordered list of chunks from the same document
    nonisolated func buildDocumentGraph(chunks: [DocumentChunk]) -> [UUID: ChunkGraphEdges] {
        var graphEdges: [UUID: ChunkGraphEdges] = [:]

        // Initialize all chunks with empty edges
        for chunk in chunks {
            graphEdges[chunk.id] = ChunkGraphEdges()
        }

        // Build linear neighbor edges (prev/next)
        for (index, chunk) in chunks.enumerated() {
            if index > 0 {
                graphEdges[chunk.id]?.prevChunkId = chunks[index - 1].id
            }
            if index < chunks.count - 1 {
                graphEdges[chunk.id]?.nextChunkId = chunks[index + 1].id
            }
        }

        // Extract cross-references
        for chunk in chunks {
            let refs = extractCrossReferencesSync(from: chunk.content)
            graphEdges[chunk.id]?.crossReferences = refs
        }

        // Build section hierarchy (parent/child) based on sectionPath
        buildSectionHierarchy(chunks: chunks, graphEdges: &graphEdges)

        // Resolve cross-references to chunk IDs
        resolveCrossReferences(chunks: chunks, graphEdges: &graphEdges)

        return graphEdges
    }

    /// Build hierarchical parent-child edges based on section paths
    private nonisolated func buildSectionHierarchy(chunks: [DocumentChunk], graphEdges: inout [UUID: ChunkGraphEdges]) {
        // Group chunks by section path depth
        var sectionHeads: [String: UUID] = [:]  // sectionPath.joined() -> chunk ID

        for chunk in chunks {
            guard let sectionPath = chunk.metadata.sectionPath, !sectionPath.isEmpty else { continue }

            let pathKey = sectionPath.joined(separator: " > ")

            // First chunk with this section path becomes the section head
            if sectionHeads[pathKey] == nil {
                sectionHeads[pathKey] = chunk.id
            }

            // Look for parent section (one level up)
            if sectionPath.count > 1 {
                let parentPath = Array(sectionPath.dropLast())
                let parentKey = parentPath.joined(separator: " > ")

                if let parentId = sectionHeads[parentKey] {
                    graphEdges[chunk.id]?.parentChunkId = parentId
                    graphEdges[parentId]?.childChunkIds.append(chunk.id)
                }
            }
        }
    }

    /// Resolve cross-references to actual chunk IDs
    private nonisolated func resolveCrossReferences(chunks: [DocumentChunk], graphEdges: inout [UUID: ChunkGraphEdges]) {
        // Build lookup tables for quick resolution
        var pageToChunks: [Int: [UUID]] = [:]
        var tableToChunks: [String: [UUID]] = [:]
        var figureToChunks: [String: [UUID]] = [:]
        var sectionToChunks: [String: [UUID]] = [:]

        for chunk in chunks {
            // Page lookup
            if let page = chunk.metadata.pageNumber {
                pageToChunks[page, default: []].append(chunk.id)
            }

            // Structure type lookup
            if let structureType = chunk.metadata.structureType {
                if structureType.lowercased().contains("table") {
                    // Try to extract table number from section path or content
                    if let tableNum = extractTableNumber(from: chunk) {
                        tableToChunks[tableNum, default: []].append(chunk.id)
                    }
                }
                if structureType.lowercased().contains("figure") {
                    if let figNum = extractFigureNumber(from: chunk) {
                        figureToChunks[figNum, default: []].append(chunk.id)
                    }
                }
            }

            // Section path lookup
            if let sectionPath = chunk.metadata.sectionPath {
                for section in sectionPath {
                    // Extract section number if present (e.g., "2.3 Safety" -> "2.3")
                    if let match = section.firstMatch(of: /^([\d\.]+)/) {
                        sectionToChunks[String(match.1), default: []].append(chunk.id)
                    }
                }
            }
        }

        // Now resolve each chunk's cross-references
        for chunk in chunks {
            guard let refs = graphEdges[chunk.id]?.crossReferences else { continue }

            var resolvedIds: [UUID] = []

            for ref in refs {
                let target = ref.targetId.components(separatedBy: ":").dropFirst().joined()

                switch ref.type {
                case .page:
                    if let pageNum = Int(target), let chunkIds = pageToChunks[pageNum] {
                        resolvedIds.append(contentsOf: chunkIds)
                    }
                case .table:
                    if let chunkIds = tableToChunks[target] {
                        resolvedIds.append(contentsOf: chunkIds)
                    }
                case .figure:
                    if let chunkIds = figureToChunks[target] {
                        resolvedIds.append(contentsOf: chunkIds)
                    }
                case .section:
                    if let chunkIds = sectionToChunks[target] {
                        resolvedIds.append(contentsOf: chunkIds)
                    }
                default:
                    break
                }
            }

            // Remove duplicates and self-references
            let uniqueIds = Array(Set(resolvedIds)).filter { $0 != chunk.id }
            graphEdges[chunk.id]?.referencedChunkIds = uniqueIds

            // Also mark the reverse edges (referencedBy)
            for targetId in uniqueIds {
                graphEdges[targetId]?.referencedByChunkIds.append(chunk.id)
            }
        }
    }

    /// Extract table number from chunk content or metadata
    private nonisolated func extractTableNumber(from chunk: DocumentChunk) -> String? {
        // Check section path first
        if let sectionPath = chunk.metadata.sectionPath {
            for section in sectionPath {
                if let match = section.firstMatch(of: /[Tt]able\s*([\d\-\.]+)/) {
                    return String(match.1)
                }
            }
        }

        // Check content header
        let firstLine = chunk.content.prefix(100)
        if let match = firstLine.firstMatch(of: /[Tt]able\s*([\d\-\.]+)/) {
            return String(match.1)
        }

        return nil
    }

    /// Extract figure number from chunk content or metadata
    private nonisolated func extractFigureNumber(from chunk: DocumentChunk) -> String? {
        if let sectionPath = chunk.metadata.sectionPath {
            for section in sectionPath {
                if let match = section.firstMatch(of: /[Ff]igure\s*([\d\-\.]+)|[Ff]ig\.?\s*([\d\-\.]+)/) {
                    return String(match.1 ?? match.2 ?? "")
                }
            }
        }

        let firstLine = chunk.content.prefix(100)
        if let match = firstLine.firstMatch(of: /[Ff]igure\s*([\d\-\.]+)|[Ff]ig\.?\s*([\d\-\.]+)/) {
            return String(match.1 ?? match.2 ?? "")
        }

        return nil
    }

    // MARK: - Graph Traversal

    /// Get all chunks reachable within N hops from starting chunks
    func graphHops(
        from startChunkIds: [UUID],
        maxHops: Int,
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk]
    ) -> [DocumentChunk] {
        var visited: Set<UUID> = Set(startChunkIds)
        var frontier: Set<UUID> = Set(startChunkIds)
        var result: [DocumentChunk] = []

        // Add starting chunks
        for id in startChunkIds {
            if let chunk = allChunks[id] {
                result.append(chunk)
            }
        }

        // BFS traversal
        for _ in 0..<maxHops {
            var nextFrontier: Set<UUID> = []

            for id in frontier {
                guard let edges = graphEdges[id] else { continue }

                // Collect all connected chunks
                var neighbors: [UUID] = []
                if let prev = edges.prevChunkId { neighbors.append(prev) }
                if let next = edges.nextChunkId { neighbors.append(next) }
                if let parent = edges.parentChunkId { neighbors.append(parent) }
                neighbors.append(contentsOf: edges.childChunkIds)
                neighbors.append(contentsOf: edges.referencedChunkIds)
                neighbors.append(contentsOf: edges.referencedByChunkIds)

                for neighbor in neighbors {
                    if !visited.contains(neighbor) {
                        visited.insert(neighbor)
                        nextFrontier.insert(neighbor)
                        if let chunk = allChunks[neighbor] {
                            result.append(chunk)
                        }
                    }
                }
            }

            frontier = nextFrontier
            if frontier.isEmpty { break }
        }

        return result
    }

    /// Get parent chain (section → chapter → document level)
    func parentChain(
        for chunkId: UUID,
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk]
    ) -> [DocumentChunk] {
        var result: [DocumentChunk] = []
        var currentId: UUID? = chunkId

        while let id = currentId {
            if let edges = graphEdges[id], let parentId = edges.parentChunkId {
                if let parentChunk = allChunks[parentId] {
                    result.append(parentChunk)
                }
                currentId = parentId
            } else {
                break
            }
        }

        return result
    }

    /// Get immediate neighbors (prev + next chunks)
    func neighbors(
        for chunkId: UUID,
        distance: Int = 1,
        graphEdges: [UUID: ChunkGraphEdges],
        allChunks: [UUID: DocumentChunk]
    ) -> [DocumentChunk] {
        var result: [DocumentChunk] = []

        // Walk backwards
        var currentId: UUID? = chunkId
        for _ in 0..<distance {
            guard let id = currentId,
                  let edges = graphEdges[id],
                  let prevId = edges.prevChunkId,
                  let chunk = allChunks[prevId] else { break }
            result.insert(chunk, at: 0)
            currentId = prevId
        }

        // Walk forwards
        currentId = chunkId
        for _ in 0..<distance {
            guard let id = currentId,
                  let edges = graphEdges[id],
                  let nextId = edges.nextChunkId,
                  let chunk = allChunks[nextId] else { break }
            result.append(chunk)
            currentId = nextId
        }

        return result
    }
}
