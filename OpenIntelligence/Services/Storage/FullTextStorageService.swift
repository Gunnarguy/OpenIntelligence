//
//  FullTextStorageService.swift
//  OpenIntelligence
//
//  Stores and retrieves COMPLETE original document text for exact queries.
//  This enables queries like "count word 'X' in all documents" that require
//  exhaustive corpus access beyond what semantic chunks provide.
//

import Foundation

/// Service for storing and retrieving complete original document text
/// This is critical for exact matching queries that need the full corpus
actor FullTextStorageService {

    // MARK: - Singleton

    static let shared = FullTextStorageService()

    // MARK: - Storage

    /// LRU-capped in-memory cache. Max 3 documents to limit memory footprint.
    /// A 1000-page PDF ≈ 5 MB text; 3 docs = 15 MB max cache.
    /// Reduced from 5 to prevent OOM on 8GB devices running heavy RAG pipelines.
    private var cache: [UUID: String] = [:]
    private var cacheOrder: [UUID] = [] // LRU order: oldest first, newest last
    private let maxCacheSize = 3
    private let fileManager = FileManager.default

    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("OpenIntelligence/FullText", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    /// Add to cache with LRU eviction
    private func cacheDocument(_ documentId: UUID, text: String) {
        // If already cached, move to end (most recent)
        if cache[documentId] != nil {
            cacheOrder.removeAll { $0 == documentId }
        } else if cache.count >= maxCacheSize {
            // Evict oldest entry
            if let oldest = cacheOrder.first {
                cache.removeValue(forKey: oldest)
                cacheOrder.removeFirst()
            }
        }
        cache[documentId] = text
        cacheOrder.append(documentId)
    }

    /// Get all document IDs that have stored full text
    private func getAllStoredDocumentIds() -> [UUID] {
        let contents = (try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)) ?? []
        return contents
            .filter { $0.pathExtension == "txt" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
    }

    // MARK: - Public API

    /// Store full text for a document
    /// - Parameters:
    ///   - text: The complete original document text (unmodified)
    ///   - documentId: Document UUID
    func store(text: String, for documentId: UUID) async {
        // Cache in memory with LRU eviction
        cacheDocument(documentId, text: text)

        // Persist to disk
        let fileURL = storageDirectory.appendingPathComponent("\(documentId.uuidString).txt")
        do {
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            Log.debug("[FullTextStorage] Stored \(text.count) chars for document \(documentId)", category: .ingestion)
        } catch {
            Log.error("[FullTextStorage] Failed to store full text: \(error)", category: .ingestion)
        }
    }

    /// Retrieve full text for a document
    /// - Parameter documentId: Document UUID
    /// - Returns: Complete original text, or nil if not stored
    func retrieve(for documentId: UUID) async -> String? {
        // Check cache first
        if let cached = cache[documentId] {
            return cached
        }

        // Load from disk
        let fileURL = storageDirectory.appendingPathComponent("\(documentId.uuidString).txt")
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            cacheDocument(documentId, text: text)  // Cache with LRU eviction
            return text
        } catch {
            Log.error("[FullTextStorage] Failed to load full text: \(error)", category: .retrieval)
            return nil
        }
    }

    /// Delete full text for a document
    func delete(for documentId: UUID) async {
        cache.removeValue(forKey: documentId)
        cacheOrder.removeAll { $0 == documentId }
        let fileURL = storageDirectory.appendingPathComponent("\(documentId.uuidString).txt")
        try? fileManager.removeItem(at: fileURL)
    }

    /// Count occurrences of a pattern in a document's full text
    /// - Parameters:
    ///   - pattern: Text pattern to search for (case-insensitive)
    ///   - documentId: Document UUID
    /// - Returns: Number of occurrences, or nil if document not found
    func countPattern(_ pattern: String, in documentId: UUID) async -> Int? {
        guard let text = await retrieve(for: documentId) else {
            return nil
        }

        let lowercasedText = text.lowercased()
        let lowercasedPattern = pattern.lowercased()

        var count = 0
        var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex

        while let range = lowercasedText.range(of: lowercasedPattern, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<lowercasedText.endIndex
        }

        return count
    }

    /// Count occurrences of a pattern across ALL documents (auto-discovers all stored documents)
    /// - Parameter pattern: Text pattern to search for (case-insensitive)
    /// - Returns: Dictionary of documentId -> count
    func countPatternInCorpus(pattern: String) async -> [UUID: Int] {
        let documentIds = getAllStoredDocumentIds()
        var results: [UUID: Int] = [:]

        for docId in documentIds {
            if let count = await countPattern(pattern, in: docId), count > 0 {
                results[docId] = count
            }
        }

        return results
    }

    /// Count occurrences of a pattern across specific documents
    /// - Parameter pattern: Text pattern to search for (case-insensitive)
    /// - Returns: Dictionary of documentId -> count, plus total
    func countPatternInCorpus(_ pattern: String, documentIds: [UUID]) async -> (perDocument: [UUID: Int], total: Int) {
        var results: [UUID: Int] = [:]
        var total = 0

        for docId in documentIds {
            if let count = await countPattern(pattern, in: docId) {
                results[docId] = count
                total += count
            }
        }

        return (perDocument: results, total: total)
    }

    /// Search for documents containing a pattern
    /// - Parameter pattern: Text pattern to search for (case-insensitive)
    /// - Returns: List of (documentId, count, firstOccurrenceContext)
    func searchCorpus(
        for pattern: String,
        in documentIds: [UUID],
        contextChars: Int = 100
    ) async -> [(documentId: UUID, count: Int, context: String)] {
        var results: [(documentId: UUID, count: Int, context: String)] = []

        for docId in documentIds {
            guard let text = await retrieve(for: docId) else { continue }

            let lowercasedText = text.lowercased()
            let lowercasedPattern = pattern.lowercased()

            // Find first occurrence for context
            guard let firstRange = lowercasedText.range(of: lowercasedPattern) else { continue }

            // Count all occurrences
            var count = 0
            var searchRange = lowercasedText.startIndex..<lowercasedText.endIndex
            while let range = lowercasedText.range(of: lowercasedPattern, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<lowercasedText.endIndex
            }

            // Extract context around first occurrence
            let contextStart = text.index(firstRange.lowerBound, offsetBy: -contextChars, limitedBy: text.startIndex) ?? text.startIndex
            let contextEnd = text.index(firstRange.upperBound, offsetBy: contextChars, limitedBy: text.endIndex) ?? text.endIndex
            let context = String(text[contextStart..<contextEnd])

            results.append((documentId: docId, count: count, context: context))
        }

        return results.sorted { $0.count > $1.count }  // Sort by count descending
    }

    /// Search match result for LLM consumption
    struct SearchMatch {
        let documentId: UUID
        let occurrences: Int
        let contextSnippet: String
    }

    /// Search for documents containing a pattern (auto-discovers all stored documents)
    /// - Parameters:
    ///   - pattern: Text pattern to search for (case-insensitive)
    ///   - maxResults: Maximum number of results to return
    /// - Returns: List of SearchMatch objects sorted by occurrence count
    func searchCorpus(pattern: String, maxResults: Int = 10) async -> [SearchMatch] {
        let documentIds = getAllStoredDocumentIds()
        let results = await searchCorpus(for: pattern, in: documentIds, contextChars: 80)

        return results.prefix(maxResults).map { result in
            SearchMatch(
                documentId: result.documentId,
                occurrences: result.count,
                contextSnippet: result.context
                    .replacingOccurrences(of: "\n", with: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    /// Get total character count for a document
    func characterCount(for documentId: UUID) async -> Int? {
        guard let text = await retrieve(for: documentId) else { return nil }
        return text.count
    }

    /// Get word count for a document (using NLTokenizer for accuracy)
    func wordCount(for documentId: UUID) async -> Int? {
        guard let text = await retrieve(for: documentId) else { return nil }

        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return count
    }

    /// Preload all documents into memory cache
    func preloadAll(documentIds: [UUID]) async {
        for docId in documentIds {
            _ = await retrieve(for: docId)
        }
        Log.info("[FullTextStorage] Preloaded \(cache.count) documents into memory", category: .retrieval)
    }

    /// Clear memory cache (keeps disk storage)
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    /// Get storage statistics
    func getStats() async -> (documentsStored: Int, totalCharacters: Int, diskSizeMB: Double) {
        var totalChars = 0
        var diskSize: UInt64 = 0

        let contents = (try? fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey])) ?? []

        for url in contents where url.pathExtension == "txt" {
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? UInt64 {
                diskSize += size
            }
        }

        for (_, text) in cache {
            totalChars += text.count
        }

        return (
            documentsStored: contents.count,
            totalCharacters: totalChars,
            diskSizeMB: Double(diskSize) / (1024 * 1024)
        )
    }
}

import NaturalLanguage
