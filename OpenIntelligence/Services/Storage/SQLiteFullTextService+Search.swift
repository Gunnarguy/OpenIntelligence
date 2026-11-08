//
//  SQLiteFullTextService+Search.swift
//  OpenIntelligence
//
//  Part of SQLiteFullTextService, moved from SQLiteFullTextService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate


extension SQLiteFullTextService {
    // MARK: - FTS5 Search Operations

    /// Search documents using FTS5 MATCH with BM25 ranking
    /// - Parameters:
    ///   - query: Search query (supports FTS5 syntax: AND, OR, NOT, NEAR, phrases)
    ///   - containerId: Optional container filter
    ///   - limit: Maximum results
    /// - Returns: Ranked search results with BM25 scores
    func search(query: String, containerId: UUID? = nil, limit: Int = 20) async -> [FTS5SearchResult] {
        ensureInitialized()
        guard let db = database else { return [] }

        // Escape special FTS5 characters and prepare query
        let escapedQuery = escapeFTS5Query(query)

        // Build SQL with optional container filter
        var sql: String
        if containerId != nil {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ? AND container_id = ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] Search prepare failed: \(error)", category: .retrieval)
            return []
        }

        defer { sqlite3_finalize(statement) }

        // Bind parameters
        sqlite3_bind_text(statement, 1, escapedQuery, -1, SQLITE_TRANSIENT)
        if let cId = containerId {
            sqlite3_bind_text(statement, 2, cId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 2, Int32(limit))
        }

        var results: [FTS5SearchResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdPtr = sqlite3_column_text(statement, 0),
                  let docId = UUID(uuidString: String(cString: docIdPtr)) else {
                continue
            }

            let content = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let score = sqlite3_column_double(statement, 2)
            let snippet = sqlite3_column_text(statement, 3).map { String(cString: $0) }

            results.append(FTS5SearchResult(
                documentId: docId,
                content: content,
                bm25Score: score,
                snippet: snippet,
                highlightedContent: nil
            ))
        }

        Log.debug("[SQLiteFTS5] Search '\(query)' returned \(results.count) results", category: .retrieval)
        return results
    }

    /// Search using OR-based broad query (fallback when AND-first returns nothing)
    func searchBroad(query: String, containerId: UUID? = nil, limit: Int = 20) async -> [FTS5SearchResult] {
        ensureInitialized()
        guard let db = database else { return [] }

        let escapedQuery = escapeFTS5QueryBroad(query)

        var sql: String
        if containerId != nil {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ? AND container_id = ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, escapedQuery, -1, SQLITE_TRANSIENT)
        if let cId = containerId {
            sqlite3_bind_text(statement, 2, cId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(limit))
        } else {
            sqlite3_bind_int(statement, 2, Int32(limit))
        }

        var results: [FTS5SearchResult] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdPtr = sqlite3_column_text(statement, 0),
                  let docId = UUID(uuidString: String(cString: docIdPtr)) else {
                continue
            }

            let content = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
            let score = sqlite3_column_double(statement, 2)
            let snippet = sqlite3_column_text(statement, 3).map { String(cString: $0) }

            results.append(FTS5SearchResult(
                documentId: docId,
                content: content,
                bm25Score: score,
                snippet: snippet,
                highlightedContent: nil
            ))
        }

        return results
    }

    /// Count exact pattern occurrences across all documents (or in specific container)
    /// Uses FTS5 MATCH for fast filtering, then exact count for precision
    func countPatternInCorpus(pattern: String, containerId: UUID? = nil) async -> [UUID: Int] {
        ensureInitialized()
        guard let db = database else { return [:] }

        let startTime = CFAbsoluteTimeGetCurrent()

        // First, use FTS5 to quickly find documents that might contain the pattern
        let escapedPattern = escapeFTS5Query(pattern)

        var sql: String
        if containerId != nil {
            sql = "SELECT document_id, content FROM documents WHERE documents MATCH ? AND container_id = ?"
        } else {
            sql = "SELECT document_id, content FROM documents WHERE documents MATCH ?"
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            Log.error("[SQLiteFTS5] countPatternInCorpus prepare failed", category: .retrieval)
            return [:]
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, escapedPattern, -1, SQLITE_TRANSIENT)
        if let containerId = containerId {
            sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)
        }

        var results: [UUID: Int] = [:]
        let lowercasedPattern = pattern.lowercased()

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdPtr = sqlite3_column_text(statement, 0),
                  let docId = UUID(uuidString: String(cString: docIdPtr)),
                  let contentPtr = sqlite3_column_text(statement, 1) else {
                continue
            }

            let content = String(cString: contentPtr).lowercased()

            // Count exact occurrences (FTS5 MATCH may use stemming)
            var count = 0
            var searchRange = content.startIndex..<content.endIndex
            while let range = content.range(of: lowercasedPattern, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<content.endIndex
            }

            if count > 0 {
                results[docId] = count
            }
        }

        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        Log.debug("[SQLiteFTS5] countPatternInCorpus('\(pattern)'): \(results.count) docs with matches in \(String(format: "%.1f", elapsed * 1000))ms", category: .retrieval)

        return results
    }

    /// Get BM25 scores for documents matching a query
    /// This replaces the in-memory BM25Scorer with FTS5's native implementation
    func bm25Scores(query: String, containerId: UUID? = nil) async -> [UUID: Double] {
        // Try AND-first (precise) query
        let results = await search(query: query, containerId: containerId, limit: 1000)

        if !results.isEmpty {
            return Dictionary(uniqueKeysWithValues: results.map { ($0.documentId, -$0.bm25Score) })
        }

        // AND returned nothing — fall back to OR for broader recall
        // This handles cases where no single document contains ALL query terms
        let broadResults = await searchBroad(query: query, containerId: containerId, limit: 1000)
        if !broadResults.isEmpty {
            Log.debug("[SQLiteFTS5] AND query returned 0 results, OR fallback found \(broadResults.count)", category: .retrieval)
        }
        return Dictionary(uniqueKeysWithValues: broadResults.map { ($0.documentId, -$0.bm25Score) })
    }

    /// Search corpus and return matches with context snippets
    func searchCorpus(pattern: String, containerId: UUID? = nil, maxResults: Int = 10, contextChars: Int = 80) async -> [(documentId: UUID, count: Int, context: String)] {
        ensureInitialized()
        guard let db = database else { return [] }

        let escapedPattern = escapeFTS5Query(pattern)

        var sql: String
        if containerId != nil {
            sql = """
                SELECT document_id, content,
                       snippet(documents, 2, '>>>>', '<<<<', '...', \(contextChars / 6)) as snip
                FROM documents
                WHERE documents MATCH ? AND container_id = ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content,
                       snippet(documents, 2, '>>>>', '<<<<', '...', \(contextChars / 6)) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents), document_id
                LIMIT ?
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, escapedPattern, -1, SQLITE_TRANSIENT)
        if let containerId = containerId {
            sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 3, Int32(maxResults))
        } else {
            sqlite3_bind_int(statement, 2, Int32(maxResults))
        }

        var results: [(documentId: UUID, count: Int, context: String)] = []
        let lowercasedPattern = pattern.lowercased()

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdPtr = sqlite3_column_text(statement, 0),
                  let docId = UUID(uuidString: String(cString: docIdPtr)),
                  let contentPtr = sqlite3_column_text(statement, 1) else {
                continue
            }

            let content = String(cString: contentPtr).lowercased()
            let snippet = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""

            // Count occurrences
            var count = 0
            var searchRange = content.startIndex..<content.endIndex
            while let range = content.range(of: lowercasedPattern, range: searchRange) {
                count += 1
                searchRange = range.upperBound..<content.endIndex
            }

            if count > 0 {
                results.append((documentId: docId, count: count, context: snippet))
            }
        }

        return results.sorted { $0.count > $1.count }
    }

    // MARK: - Semantic Cache & Vocab Check

    /// Normalize a query for exact text matching
    static func normalizeQuery(_ query: String) -> String {
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Retrieve a cached query by exact text match
    func getCachedQuery(normalizedQuery: String, containerId: UUID) async -> (embedding: [Float], results: [RetrievedChunk])? {
        ensureInitialized()
        guard let db = database else { return nil }

        let sql = "SELECT embedding_json, results_json FROM semantic_query_cache WHERE normalized_query = ? AND container_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, normalizedQuery, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            guard let embPtr = sqlite3_column_text(statement, 0),
                  let resPtr = sqlite3_column_text(statement, 1) else {
                return nil
            }

            let embStr = String(cString: embPtr)
            let resStr = String(cString: resPtr)

            guard let embData = embStr.data(using: .utf8),
                  let resData = resStr.data(using: .utf8) else {
                return nil
            }

            let decoder = JSONDecoder()
            do {
                let embedding = try decoder.decode([Float].self, from: embData)
                let results = try decoder.decode([RetrievedChunk].self, from: resData)
                return (embedding, results)
            } catch {
                Log.error("[SQLiteFTS5] Failed to decode cached query: \(error)", category: .vectorDB)
                return nil
            }
        }
        return nil
    }

    /// Cache a query, its embedding, and the retrieved chunks
    func cacheQuery(normalizedQuery: String, containerId: UUID, embedding: [Float], results: [RetrievedChunk]) async {
        ensureInitialized()
        guard let db = database else { return }

        let encoder = JSONEncoder()
        do {
            let embData = try encoder.encode(embedding)
            let resData = try encoder.encode(results)

            let embStr = String(data: embData, encoding: .utf8) ?? "[]"
            let resStr = String(data: resData, encoding: .utf8) ?? "[]"

            let sql = "INSERT OR REPLACE INTO semantic_query_cache (normalized_query, container_id, embedding_json, results_json, created_at) VALUES (?, ?, ?, ?, ?)"
            var statement: OpaquePointer?

            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                Log.error("[SQLiteFTS5] Failed to prepare cacheQuery statement", category: .vectorDB)
                return
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, normalizedQuery, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, embStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 4, resStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)

            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                Log.error("[SQLiteFTS5] Failed to insert query cache: \(error)", category: .vectorDB)
            } else {
                checkpoint()
                Log.debug("[SQLiteFTS5] Cached query successfully: '\(normalizedQuery)'", category: .vectorDB)
            }
        } catch {
            Log.error("[SQLiteFTS5] Failed to serialize query for caching: \(error)", category: .vectorDB)
        }
    }

    /// Deletes every cached search and returns how many there were (5.7). `RAGService` calls it once the
    /// documents or the app's version have changed: every cached search's key names both, so from then on
    /// none of them can be found again. Through 5.6 nothing deleted them, and they hold the questions asked
    /// and the passages found, a deleted library's text among them.
    @discardableResult
    func deleteAllCachedQueries() -> Int {
        ensureInitialized()
        guard let db = database, execute(sql: "DELETE FROM semantic_query_cache") else { return 0 }
        let deleted = Int(sqlite3_changes(db))
        checkpoint()
        return deleted
    }

    /// Retrieve a cached query using cosine similarity (>0.95 threshold) on query embedding
    func getCachedQueryBySimilarity(embedding: [Float], containerId: UUID, threshold: Float = 0.95) async -> [RetrievedChunk]? {
        ensureInitialized()
        guard let db = database, !embedding.isEmpty else { return nil }

        let sql = "SELECT embedding_json, results_json, normalized_query FROM semantic_query_cache WHERE container_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)

        let decoder = JSONDecoder()

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let embPtr = sqlite3_column_text(statement, 0),
                  let resPtr = sqlite3_column_text(statement, 1),
                  let queryPtr = sqlite3_column_text(statement, 2) else {
                continue
            }

            let embStr = String(cString: embPtr)
            let resStr = String(cString: resPtr)
            let queryStr = String(cString: queryPtr)

            guard let embData = embStr.data(using: .utf8) else { continue }

            do {
                let cachedEmbedding = try decoder.decode([Float].self, from: embData)
                let similarity = cosineSimilarity(embedding, cachedEmbedding)
                if similarity >= threshold {
                    Log.debug("[SQLiteFTS5] Semantic cache hit by embedding similarity (\(String(format: "%.3f", similarity)) >= \(threshold)) with cached query: '\(queryStr)'", category: .vectorDB)
                    if let resData = resStr.data(using: .utf8) {
                        return try decoder.decode([RetrievedChunk].self, from: resData)
                    }
                }
            } catch {
                continue
            }
        }

        return nil
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        var dotProduct: Float = 0.0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        var sumSqA: Float = 0.0
        vDSP_svesq(a, 1, &sumSqA, vDSP_Length(a.count))
        let normA = sqrt(sumSqA)

        var sumSqB: Float = 0.0
        vDSP_svesq(b, 1, &sumSqB, vDSP_Length(b.count))
        let normB = sqrt(sumSqB)

        let magnitude = normA * normB
        guard magnitude > 0 else { return 0.0 }
        return dotProduct / magnitude
    }

    /// Check which of the input words exist in the document vocabulary index.
    /// When a container is supplied, restrict the vocabulary test to that library's documents.
    func checkVocabularyPresence(words: [String], containerId: UUID? = nil) async -> [String: Bool] {
        ensureInitialized()
        guard let db = database, !words.isEmpty else { return [:] }

        var results: [String: Bool] = [:]

        let stopWords: Set<String> = [
            "i", "me", "my", "myself", "we", "our", "ours", "ourselves", "you", "your", "yours",
            "him", "his", "himself", "she", "her", "hers", "herself", "it", "its", "itself",
            "they", "them", "their", "theirs", "themselves", "what", "which", "who", "whom",
            "this", "that", "these", "those", "am", "is", "are", "was", "were", "be", "been",
            "being", "have", "has", "had", "having", "do", "does", "did", "doing", "a", "an",
            "the", "and", "but", "if", "or", "because", "as", "until", "while", "of", "at",
            "by", "for", "with", "about", "against", "between", "into", "through", "during",
            "before", "after", "above", "below", "to", "from", "up", "down", "in", "out",
            "on", "off", "over", "under", "again", "further", "then", "once", "here", "there",
            "when", "where", "why", "how", "all", "any", "both", "each", "few", "more", "most",
            "other", "some", "such", "no", "nor", "not", "only", "own", "same", "so", "than",
            "too", "very", "can", "will", "just", "should", "now"
        ]

        // Prepare list of terms to query: original and stemmed
        var termsToQuery = Set<String>()
        var wordToTerms: [String: [String]] = [:]

        for word in words {
            let normalized = word.lowercased().trimmingCharacters(in: .alphanumerics.inverted)
            guard !normalized.isEmpty else {
                results[word] = true // Keep empty or non-alphanumeric words (punctuation)
                continue
            }

            // Keep stop words
            if stopWords.contains(normalized) {
                results[word] = true
                continue
            }

            // Keep numbers
            if Double(normalized) != nil {
                results[word] = true
                continue
            }

            let stemmed = stem(normalized)
            wordToTerms[word] = [normalized, stemmed]
            termsToQuery.insert(normalized)
            termsToQuery.insert(stemmed)
        }

        let termsArray = Array(termsToQuery)
        var existingTerms = Set<String>()

        if let containerId {
            for term in termsArray where termExistsInContainer(term, containerId: containerId, db: db) {
                existingTerms.insert(term)
            }
        } else {
            execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS documents_vocab USING fts5vocab(documents, 'row')")

            let chunkSize = 100
            for i in stride(from: 0, to: termsArray.count, by: chunkSize) {
                let chunk = Array(termsArray[i..<min(i + chunkSize, termsArray.count)])
                let placeholders = String(repeating: "?,", count: chunk.count).dropLast()
                let sql = "SELECT DISTINCT term FROM documents_vocab WHERE term IN (\(placeholders))"

                var statement: OpaquePointer?
                if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                    for (idx, term) in chunk.enumerated() {
                        sqlite3_bind_text(statement, Int32(idx + 1), term, -1, SQLITE_TRANSIENT)
                    }
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let termPtr = sqlite3_column_text(statement, 0) {
                            existingTerms.insert(String(cString: termPtr))
                        }
                    }
                    sqlite3_finalize(statement)
                }
            }
        }

        // Map back to check if either original or stemmed term exists
        for word in words {
            if results[word] != nil { continue }
            if let terms = wordToTerms[word] {
                let exists = terms.contains { existingTerms.contains($0) }
                results[word] = exists
            } else {
                results[word] = false
            }
        }

        return results
    }

    private func termExistsInContainer(_ term: String, containerId: UUID, db: OpaquePointer) -> Bool {
        let sql = "SELECT 1 FROM documents WHERE documents MATCH ? AND container_id = ? LIMIT 1"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, term, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)

        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func stem(_ word: String) -> String {
        var w = word.lowercased()
        if w.hasSuffix("sses") {
            w = String(w.dropLast(2))
        } else if w.hasSuffix("ies") {
            w = String(w.dropLast(3)) + "i"
        } else if w.hasSuffix("ss") {
            // do nothing
        } else if w.hasSuffix("s") && !w.hasSuffix("us") && !w.hasSuffix("is") && !w.hasSuffix("as") {
            w = String(w.dropLast())
        }

        if w.hasSuffix("eed") {
            w = String(w.dropLast(1))
        } else if w.hasSuffix("ing") {
            w = String(w.dropLast(3))
            if w.hasSuffix("at") || w.hasSuffix("bl") || w.hasSuffix("iz") {
                w += "e"
            }
        } else if w.hasSuffix("ed") {
            w = String(w.dropLast(2))
            if w.hasSuffix("at") || w.hasSuffix("bl") || w.hasSuffix("iz") {
                w += "e"
            }
        }

        if w.hasSuffix("y") && w.count > 2 {
            let vowels = CharacterSet(charactersIn: "aeiou")
            let prefix = String(w.dropLast())
            if prefix.rangeOfCharacter(from: vowels) != nil {
                w = prefix + "i"
            }
        }
        return w
    }
}
