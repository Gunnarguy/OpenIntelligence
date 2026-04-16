//
//  DocumentationCacheService.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 1/25/26.
//
//  Actor-based service for caching fetched web documentation locally.
//  Enables offline access and RAG ingestion of API documentation.
//

import Foundation
import CryptoKit

/// Represents a cached documentation page
struct CachedDocument: Codable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let content: String              // Cleaned Markdown content
    let fetchDate: Date
    let contentHash: String          // SHA256 for deduplication
    let sourceType: SourceType
    let wordCount: Int

    enum SourceType: String, Codable, Sendable {
        case appleDevDocs = "apple_dev_docs"
        case github = "github"
        case stackOverflow = "stackoverflow"
        case web = "web"
    }

    var filename: String {
        makeCacheFilename(url: url, id: id)
    }

    var isExpired: Bool {
        // 30-day expiration by default
        let expirationDays: TimeInterval = 30 * 24 * 60 * 60
        return Date().timeIntervalSince(fetchDate) > expirationDays
    }
}

/// Generate a filename from URL and ID (nonisolated free function for actor safety)
nonisolated private func makeCacheFilename(url: URL, id: UUID) -> String {
    let sanitized = url.host?.replacingOccurrences(of: ".", with: "_") ?? "unknown"
    let path = url.path.replacingOccurrences(of: "/", with: "_")
    let truncatedPath = String(path.prefix(50))
    return "\(sanitized)\(truncatedPath)_\(id.uuidString.prefix(8)).md"
}

/// Metadata for a cached document (stored in index)
/// Sendable struct for use across actor boundaries
nonisolated struct CachedDocMetadata: Codable, Identifiable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let filename: String
    let fetchDate: Date
    let contentHash: String
    let wordCount: Int
    let sourceType: CachedDocument.SourceType

    var content: String { "" }  // Placeholder - full content loaded separately
}

/// Index for fast URL → CachedDocument lookup
/// Sendable struct for use across actor boundaries in Swift 6
nonisolated struct DocumentationCacheIndex: Codable, Sendable {
    var documents: [UUID: CachedDocMetadata]
    var urlToId: [String: UUID]  // URL string → document ID
    var lastUpdated: Date

    init(documents: [UUID: CachedDocMetadata] = [:], urlToId: [String: UUID] = [:], lastUpdated: Date = Date()) {
        self.documents = documents
        self.urlToId = urlToId
        self.lastUpdated = lastUpdated
    }
}

/// Actor for managing cached documentation
actor DocumentationCacheService {

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let isAutoCacheEnabled = "docCacheAutoEnabled"
        static let expirationDays = "docCacheExpirationDays"
    }

    // MARK: - Singleton

    static let shared = DocumentationCacheService()

    // MARK: - Properties

    private let cacheDirectory: URL
    private let indexURL: URL
    private var index: DocumentationCacheIndex

    /// Configuration - synced with UserDefaults for Settings exposure
    var isAutoCacheEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Keys.isAutoCacheEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isAutoCacheEnabled) }
    }
    var expirationDays: Int {
        get { UserDefaults.standard.object(forKey: Keys.expirationDays) as? Int ?? 30 }
        set { UserDefaults.standard.set(newValue, forKey: Keys.expirationDays) }
    }

    // MARK: - Initialization

    init() {
        // Use Documents/cached_docs/ for persistent storage
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        cacheDirectory = documentsDir.appendingPathComponent("cached_docs", isDirectory: true)
        indexURL = cacheDirectory.appendingPathComponent("index.json")

        // Initialize with empty index
        var loadedIndex = DocumentationCacheIndex(
            documents: [:],
            urlToId: [:],
            lastUpdated: Date()
        )

        // Create directory if needed
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Load index synchronously for actor initialization
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode(DocumentationCacheIndex.self, from: data) {
            loadedIndex = decoded
        }

        index = loadedIndex

        Log.info("[DocCache] Initialized with \(loadedIndex.documents.count) cached documents", category: .ingestion)
    }

    // MARK: - Public API

    /// Cache a document from web content
    /// - Parameters:
    ///   - url: Source URL
    ///   - title: Document title
    ///   - content: Raw content (HTML or Markdown)
    ///   - sourceType: Type of source for categorization
    /// - Returns: The cached document, or nil if duplicate
    func cache(
        url: URL,
        title: String,
        content: String,
        sourceType: CachedDocument.SourceType = .web
    ) async throws -> CachedDocument? {

        // Clean content - convert HTML to Markdown if needed
        let cleanedContent = cleanContent(content)

        // Calculate hash for deduplication
        let contentHash = sha256(cleanedContent)

        // Check for duplicate by hash
        if let existingId = findByHash(contentHash) {
            Log.debug("[DocCache] Duplicate content detected, skipping cache for \(url.absoluteString)", category: .ingestion)
            return index.documents[existingId].flatMap { metadata in
                // Return existing document
                try? loadDocument(id: existingId)
            }
        }

        // Create new cached document
        let document = CachedDocument(
            id: UUID(),
            url: url,
            title: title,
            content: cleanedContent,
            fetchDate: Date(),
            contentHash: contentHash,
            sourceType: sourceType,
            wordCount: cleanedContent.split(separator: " ").count
        )

        // Save content file - use free function to avoid actor isolation issues
        let generatedFilename = makeCacheFilename(url: url, id: document.id)
        let fileURL = cacheDirectory.appendingPathComponent(generatedFilename)
        try cleanedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Update index
        index.documents[document.id] = CachedDocMetadata(
            id: document.id,
            url: document.url,
            title: document.title,
            filename: generatedFilename,
            fetchDate: document.fetchDate,
            contentHash: document.contentHash,
            wordCount: document.wordCount,
            sourceType: document.sourceType
        )
        index.urlToId[url.absoluteString] = document.id
        index.lastUpdated = Date()

        // Persist index
        try saveIndex()

        Log.info("[DocCache] Cached document: \(title) (\(document.wordCount) words)", category: .ingestion)

        return document
    }

    /// Get a cached document by URL
    func get(url: URL) -> CachedDocument? {
        guard let id = index.urlToId[url.absoluteString] else { return nil }
        return try? loadDocument(id: id)
    }

    /// Get a cached document by ID
    func get(id: UUID) -> CachedDocument? {
        return try? loadDocument(id: id)
    }

    /// List all cached documents
    func listCached() -> [CachedDocMetadata] {
        return Array(index.documents.values).sorted { $0.fetchDate > $1.fetchDate }
    }

    /// Get statistics about the cache
    func statistics() -> (count: Int, totalWords: Int, oldestDate: Date?, newestDate: Date?) {
        let docs = Array(index.documents.values)
        let totalWords = docs.reduce(0) { $0 + $1.wordCount }
        let oldest = docs.min(by: { $0.fetchDate < $1.fetchDate })?.fetchDate
        let newest = docs.max(by: { $0.fetchDate < $1.fetchDate })?.fetchDate
        return (docs.count, totalWords, oldest, newest)
    }

    /// Delete a cached document
    func delete(id: UUID) throws {
        guard let metadata = index.documents[id] else { return }

        // Delete file
        let fileURL = cacheDirectory.appendingPathComponent(metadata.filename)
        try? FileManager.default.removeItem(at: fileURL)

        // Update index
        index.documents.removeValue(forKey: id)
        index.urlToId.removeValue(forKey: metadata.url.absoluteString)
        index.lastUpdated = Date()

        try saveIndex()

        Log.info("[DocCache] Deleted: \(metadata.title)", category: .ingestion)
    }

    /// Delete all expired documents
    func pruneExpired() throws -> Int {
        let expirationInterval: TimeInterval = TimeInterval(expirationDays * 24 * 60 * 60)
        let cutoffDate = Date().addingTimeInterval(-expirationInterval)

        var deletedCount = 0

        for (id, metadata) in index.documents {
            if metadata.fetchDate < cutoffDate {
                try? delete(id: id)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            Log.info("[DocCache] Pruned \(deletedCount) expired documents", category: .ingestion)
        }

        return deletedCount
    }

    /// Search cached documents by title or content
    func search(query: String) -> [CachedDocMetadata] {
        let lowercasedQuery = query.lowercased()

        return Array(index.documents.values).filter { metadata in
            metadata.title.lowercased().contains(lowercasedQuery) ||
            metadata.url.absoluteString.lowercased().contains(lowercasedQuery)
        }.sorted { $0.fetchDate > $1.fetchDate }
    }

    /// Check if a URL is already cached
    func isCached(url: URL) -> Bool {
        return index.urlToId[url.absoluteString] != nil
    }

    /// Clear all cached documents
    func clearAll() throws {
        // Delete all files
        for metadata in index.documents.values {
            let fileURL = cacheDirectory.appendingPathComponent(metadata.filename)
            try? FileManager.default.removeItem(at: fileURL)
        }

        // Reset index - create new index inline
        index.documents = [:]
        index.urlToId = [:]
        index.lastUpdated = Date()
        try saveIndex()

        Log.info("[DocCache] Cleared all cached documents", category: .ingestion)
    }

    // MARK: - Private Helpers

    private func loadDocument(id: UUID) throws -> CachedDocument? {
        guard let metadata = index.documents[id] else { return nil }

        let fileURL = cacheDirectory.appendingPathComponent(metadata.filename)
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        return CachedDocument(
            id: metadata.id,
            url: metadata.url,
            title: metadata.title,
            content: content,
            fetchDate: metadata.fetchDate,
            contentHash: metadata.contentHash,
            sourceType: metadata.sourceType,
            wordCount: metadata.wordCount
        )
    }

    private func findByHash(_ hash: String) -> UUID? {
        return index.documents.first { $0.value.contentHash == hash }?.key
    }

    private func saveIndex() throws {
        let data = try JSONEncoder().encode(index)
        try data.write(to: indexURL)
    }

    private func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Clean HTML content and convert to Markdown
    private func cleanContent(_ content: String) -> String {
        var cleaned = content

        // Remove script and style tags
        cleaned = cleaned.replacingOccurrences(
            of: "<script[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "<style[^>]*>[\\s\\S]*?</style>",
            with: "",
            options: .regularExpression
        )

        // Convert common HTML to Markdown
        cleaned = cleaned.replacingOccurrences(of: "<h1[^>]*>", with: "# ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</h1>", with: "\n\n")
        cleaned = cleaned.replacingOccurrences(of: "<h2[^>]*>", with: "## ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</h2>", with: "\n\n")
        cleaned = cleaned.replacingOccurrences(of: "<h3[^>]*>", with: "### ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</h3>", with: "\n\n")
        cleaned = cleaned.replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</p>", with: "\n\n")
        cleaned = cleaned.replacingOccurrences(of: "<br[^>]*>", with: "\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "<li[^>]*>", with: "- ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</li>", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "<code[^>]*>", with: "`", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</code>", with: "`")
        cleaned = cleaned.replacingOccurrences(of: "<pre[^>]*>", with: "```\n", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</pre>", with: "\n```\n")
        cleaned = cleaned.replacingOccurrences(of: "<strong[^>]*>", with: "**", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</strong>", with: "**")
        cleaned = cleaned.replacingOccurrences(of: "<em[^>]*>", with: "*", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: "</em>", with: "*")

        // Extract href from links
        let linkPattern = "<a[^>]*href=\"([^\"]*)\"[^>]*>([^<]*)</a>"
        if let regex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, range: range, withTemplate: "[$2]($1)")
        }

        // Remove remaining HTML tags
        cleaned = cleaned.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode HTML entities
        cleaned = cleaned.replacingOccurrences(of: "&nbsp;", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "&amp;", with: "&")
        cleaned = cleaned.replacingOccurrences(of: "&lt;", with: "<")
        cleaned = cleaned.replacingOccurrences(of: "&gt;", with: ">")
        cleaned = cleaned.replacingOccurrences(of: "&quot;", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        cleaned = cleaned.replacingOccurrences(of: "\r\n", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\r", with: "\n")
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        return cleaned
    }
}

// MARK: - RAG Integration Extension

extension DocumentationCacheService {

    /// Prepare a cached document for RAG ingestion
    /// Returns the content in a format suitable for DocumentProcessor
    func prepareForIngestion(id: UUID) async throws -> (title: String, content: String, metadata: [String: String])? {
        guard let document = try loadDocument(id: id) else { return nil }

        let metadata: [String: String] = [
            "source_url": document.url.absoluteString,
            "source_type": document.sourceType.rawValue,
            "cached_date": ISO8601DateFormatter().string(from: document.fetchDate),
            "word_count": String(document.wordCount)
        ]

        return (document.title, document.content, metadata)
    }

    /// Export cached document to a temporary file for ingestion
    func exportForIngestion(id: UUID) async throws -> URL? {
        guard let document = try loadDocument(id: id) else { return nil }

        let tempDir = FileManager.default.temporaryDirectory
        let filename = document.title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(100)
        let fileURL = tempDir.appendingPathComponent("\(filename).md")

        // Add metadata header
        let content = """
        ---
        title: \(document.title)
        source: \(document.url.absoluteString)
        cached: \(ISO8601DateFormatter().string(from: document.fetchDate))
        ---

        \(document.content)
        """

        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        return fileURL
    }
}
