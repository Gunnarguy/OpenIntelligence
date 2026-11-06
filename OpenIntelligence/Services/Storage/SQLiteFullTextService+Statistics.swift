//
//  SQLiteFullTextService+Statistics.swift
//  OpenIntelligence
//
//  Part of SQLiteFullTextService, moved from SQLiteFullTextService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate


extension SQLiteFullTextService {
    // MARK: - Statistics

    /// Get storage statistics
    func getStats() async -> (documentsStored: Int, totalCharacters: Int, totalWords: Int) {
        ensureInitialized()
        guard let db = database else { return (0, 0, 0) }

        var docCount = 0
        var charCount = 0
        var wordCount = 0

        let sql = "SELECT COUNT(*), COALESCE(SUM(character_count), 0), COALESCE(SUM(word_count), 0) FROM document_meta"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                docCount = Int(sqlite3_column_int64(statement, 0))
                charCount = Int(sqlite3_column_int64(statement, 1))
                wordCount = Int(sqlite3_column_int64(statement, 2))
            }
            sqlite3_finalize(statement)
        }

        return (docCount, charCount, wordCount)
    }

    /// Get all stored document IDs
    func getAllDocumentIds() async -> [UUID] {
        ensureInitialized()
        guard let db = database else { return [] }

        let sql = "SELECT DISTINCT document_id FROM documents"
        var statement: OpaquePointer?
        var ids: [UUID] = []

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                if let idPtr = sqlite3_column_text(statement, 0),
                   let uuid = UUID(uuidString: String(cString: idPtr)) {
                    ids.append(uuid)
                }
            }
            sqlite3_finalize(statement)
        }

        return ids
    }

    /// Check if document exists
    func exists(documentId: UUID) async -> Bool {
        ensureInitialized()
        guard let db = database else { return false }

        let sql = "SELECT 1 FROM documents WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    /// Get document count for a container (0 if no FTS5 data exists)
    func documentCount(for containerId: UUID) async -> Int {
        ensureInitialized()
        guard let db = database else { return 0 }

        let sql = "SELECT COUNT(*) FROM document_meta WHERE container_id = ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }

    /// Get total character count for a container
    func totalCharacterCount(for containerId: UUID) async -> Int {
        ensureInitialized()
        guard let db = database else { return 0 }

        let sql = "SELECT COALESCE(SUM(LENGTH(content)), 0) FROM fts_content WHERE document_id IN (SELECT document_id FROM document_meta WHERE container_id = ?)"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }
        return 0
    }

    // MARK: - Statistics & Diagnostics

    /// Comprehensive FTS5 database statistics for visualization
    struct FTS5Statistics: Sendable {
        let totalDocuments: Int
        let totalCharacters: Int
        let totalWords: Int
        let databaseSizeBytes: Int64
        let documentsPerContainer: [UUID: Int]
        let averageDocumentSize: Int
        let largestDocument: (documentId: UUID?, characters: Int)
        let smallestDocument: (documentId: UUID?, characters: Int)
        let indexStatus: String
        let lastModified: Date?
        let containerStats: [ContainerStat]

        struct ContainerStat: Identifiable, Sendable {
            let id: UUID
            let containerId: UUID
            let documentCount: Int
            let totalCharacters: Int
            let totalWords: Int
        }
    }

    /// Get comprehensive statistics about the FTS5 database
    func getStatistics() async -> FTS5Statistics {
        Log.info("[SQLiteFTS5] getStatistics() entered", category: .vectorDB)
        ensureInitialized()
        guard let db = database else {
            Log.warning("[SQLiteFTS5] getStatistics() — database is nil!", category: .vectorDB)
            return FTS5Statistics(
                totalDocuments: 0,
                totalCharacters: 0,
                totalWords: 0,
                databaseSizeBytes: 0,
                documentsPerContainer: [:],
                averageDocumentSize: 0,
                largestDocument: (nil, 0),
                smallestDocument: (nil, 0),
                indexStatus: "Not initialized",
                lastModified: nil,
                containerStats: []
            )
        }

        // Get total document count
        let totalDocs = getIntValue(sql: "SELECT COUNT(*) FROM document_meta")

        // Get total characters and words
        let totalChars = getIntValue(sql: "SELECT COALESCE(SUM(character_count), 0) FROM document_meta")
        let totalWords = getIntValue(sql: "SELECT COALESCE(SUM(word_count), 0) FROM document_meta")

        // Get database file size
        let dbSize = (try? FileManager.default.attributesOfItem(atPath: databasePath.path)[.size] as? Int64) ?? 0

        // Get documents per container
        var containerCounts: [UUID: Int] = [:]
        var containerStats: [FTS5Statistics.ContainerStat] = []

        let containerSQL = """
            SELECT container_id, COUNT(*), COALESCE(SUM(character_count), 0), COALESCE(SUM(word_count), 0)
            FROM document_meta
            GROUP BY container_id
        """
        var containerStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, containerSQL, -1, &containerStmt, nil) == SQLITE_OK {
            while sqlite3_step(containerStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(containerStmt, 0),
                   let containerId = UUID(uuidString: String(cString: cStr)) {
                    let count = Int(sqlite3_column_int(containerStmt, 1))
                    let chars = Int(sqlite3_column_int(containerStmt, 2))
                    let words = Int(sqlite3_column_int(containerStmt, 3))
                    containerCounts[containerId] = count
                    containerStats.append(FTS5Statistics.ContainerStat(
                        id: containerId,
                        containerId: containerId,
                        documentCount: count,
                        totalCharacters: chars,
                        totalWords: words
                    ))
                }
            }
            sqlite3_finalize(containerStmt)
        }

        // Get largest document
        var largestDoc: (UUID?, Int) = (nil, 0)
        let largestSQL = "SELECT document_id, character_count FROM document_meta ORDER BY character_count DESC LIMIT 1"
        var largestStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, largestSQL, -1, &largestStmt, nil) == SQLITE_OK {
            if sqlite3_step(largestStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(largestStmt, 0) {
                    largestDoc = (UUID(uuidString: String(cString: cStr)), Int(sqlite3_column_int(largestStmt, 1)))
                }
            }
            sqlite3_finalize(largestStmt)
        }

        // Get smallest document
        var smallestDoc: (UUID?, Int) = (nil, 0)
        let smallestSQL = "SELECT document_id, character_count FROM document_meta ORDER BY character_count ASC LIMIT 1"
        var smallestStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, smallestSQL, -1, &smallestStmt, nil) == SQLITE_OK {
            if sqlite3_step(smallestStmt) == SQLITE_ROW {
                if let cStr = sqlite3_column_text(smallestStmt, 0) {
                    smallestDoc = (UUID(uuidString: String(cString: cStr)), Int(sqlite3_column_int(smallestStmt, 1)))
                }
            }
            sqlite3_finalize(smallestStmt)
        }

        // Get last modified time
        let lastMod = (try? FileManager.default.attributesOfItem(atPath: databasePath.path)[.modificationDate] as? Date)

        // Calculate average
        let avgSize = totalDocs > 0 ? totalChars / totalDocs : 0

        Log.info("[SQLiteFTS5] getStatistics() complete — \(totalDocs) docs", category: .vectorDB)
        return FTS5Statistics(
            totalDocuments: totalDocs,
            totalCharacters: totalChars,
            totalWords: totalWords,
            databaseSizeBytes: dbSize,
            documentsPerContainer: containerCounts,
            averageDocumentSize: avgSize,
            largestDocument: largestDoc,
            smallestDocument: smallestDoc,
            indexStatus: totalDocs > 0 ? "Active" : "Empty",
            lastModified: lastMod,
            containerStats: containerStats
        )
    }

    /// Get individual document statistics
    struct DocumentStat: Identifiable, Sendable {
        let id: UUID
        let documentId: UUID
        let containerId: UUID
        let characterCount: Int
        let wordCount: Int
        let createdAt: Date
    }

    /// Get stats for all documents in a container
    func getDocumentStats(containerId: UUID) async -> [DocumentStat] {
        Log.info("[SQLiteFTS5] getDocumentStats() entered", category: .vectorDB)
        ensureInitialized()
        guard let db = database else {
            Log.warning("[SQLiteFTS5] getDocumentStats() — database is nil!", category: .vectorDB)
            return []
        }

        var results: [DocumentStat] = []
        let sql = """
            SELECT document_id, container_id, character_count, word_count, created_at
            FROM document_meta
            WHERE container_id = ?
            ORDER BY character_count DESC
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        let containerIdStr = containerId.uuidString
        sqlite3_bind_text(statement, 1, containerIdStr, -1, SQLITE_TRANSIENT)

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdStr = sqlite3_column_text(statement, 0),
                  let contIdStr = sqlite3_column_text(statement, 1),
                  let docId = UUID(uuidString: String(cString: docIdStr)),
                  let contId = UUID(uuidString: String(cString: contIdStr)) else {
                continue
            }

            let chars = Int(sqlite3_column_int(statement, 2))
            let words = Int(sqlite3_column_int(statement, 3))
            let timestamp = sqlite3_column_double(statement, 4)
            let createdAt = Date(timeIntervalSince1970: timestamp)

            results.append(DocumentStat(
                id: docId,
                documentId: docId,
                containerId: contId,
                characterCount: chars,
                wordCount: words,
                createdAt: createdAt
            ))
        }

        Log.info("[SQLiteFTS5] getDocumentStats() complete — \(results.count) docs", category: .vectorDB)
        return results
    }

    /// Get FTS5-specific index statistics
    struct FTS5IndexInfo: Sendable {
        let totalTerms: Int
        let uniqueTerms: Int
        let averageTermFrequency: Double
        let compressionRatio: Double
    }

    /// Get FTS5 index information (uses built-in fts5vocab for term analysis)
    func getIndexInfo() async -> FTS5IndexInfo {
        ensureInitialized()
        guard database != nil else {
            return FTS5IndexInfo(totalTerms: 0, uniqueTerms: 0, averageTermFrequency: 0, compressionRatio: 1.0)
        }

        // Create vocabulary table for analysis (if not exists)
        execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS documents_vocab USING fts5vocab(documents, 'row')")

        // Count unique terms
        let uniqueTerms = getIntValue(sql: "SELECT COUNT(DISTINCT term) FROM documents_vocab")

        // Count total term occurrences
        let totalOccurrences = getIntValue(sql: "SELECT COALESCE(SUM(cnt), 0) FROM documents_vocab")

        // Get total characters from metadata
        let totalChars = getIntValue(sql: "SELECT COALESCE(SUM(character_count), 0) FROM document_meta")

        // Get database size
        let dbSize = (try? FileManager.default.attributesOfItem(atPath: databasePath.path)[.size] as? Int64) ?? 0

        // Estimate compression ratio (original text size vs db size)
        let compressionRatio = totalChars > 0 ? Double(dbSize) / Double(totalChars) : 1.0

        // Average term frequency
        let avgFreq = uniqueTerms > 0 ? Double(totalOccurrences) / Double(uniqueTerms) : 0

        return FTS5IndexInfo(
            totalTerms: totalOccurrences,
            uniqueTerms: uniqueTerms,
            averageTermFrequency: avgFreq,
            compressionRatio: compressionRatio
        )
    }

    /// Helper to get single integer value from SQL
    private func getIntValue(sql: String) -> Int {
        guard let db = database else { return 0 }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        return sqlite3_step(statement) == SQLITE_ROW ? Int(sqlite3_column_int(statement, 0)) : 0
    }

    // MARK: - Advanced Diagnostics (Power User Features)

    /// Deep diagnostic report for power users
    struct DeepDiagnostics: Sendable {
        let databasePath: String
        let databaseSizeBytes: Int64
        let walSizeBytes: Int64
        let shmSizeBytes: Int64
        let pageSize: Int
        let pageCount: Int
        let freePageCount: Int
        let schemaVersion: Int
        let userVersion: Int
        let journalMode: String
        let autoVacuum: String
        let cacheSize: Int
        let mMapSize: Int64
        let integrityCheckResult: String
        let lastOptimizeTime: Date?
        let tableStats: [TableStat]
        let pragmaSettings: [String: String]

        struct TableStat: Identifiable, Sendable {
            let id: String
            let name: String
            let rowCount: Int
            let estimatedSize: Int64
        }
    }

    /// Get deep database diagnostics
    func getDeepDiagnostics() async -> DeepDiagnostics {
        ensureInitialized()

        let path = databasePath.path
        let dbSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0
        let walPath = path + "-wal"
        let shmPath = path + "-shm"
        let walSize = (try? FileManager.default.attributesOfItem(atPath: walPath)[.size] as? Int64) ?? 0
        let shmSize = (try? FileManager.default.attributesOfItem(atPath: shmPath)[.size] as? Int64) ?? 0

        let pageSize = getIntValue(sql: "PRAGMA page_size")
        let pageCount = getIntValue(sql: "PRAGMA page_count")
        let freePageCount = getIntValue(sql: "PRAGMA freelist_count")
        let schemaVersion = getIntValue(sql: "PRAGMA schema_version")
        let userVersion = getIntValue(sql: "PRAGMA user_version")
        let cacheSize = getIntValue(sql: "PRAGMA cache_size")
        let journalMode = getStringValue(sql: "PRAGMA journal_mode") ?? "unknown"
        let autoVacuum = getStringValue(sql: "PRAGMA auto_vacuum") ?? "unknown"
        let mMapSize = Int64(getIntValue(sql: "PRAGMA mmap_size"))

        // Lightweight integrity check — PRAGMA quick_check scans ALL FTS5 shadow
        // tables and can take 30+ seconds on large databases, blocking the actor
        // and causing the Database tab to load indefinitely. Use a fast heuristic instead.
        let integrityResult: String = {
            let docCount = getIntValue(sql: "SELECT COUNT(*) FROM documents")
            let metaCount = getIntValue(sql: "SELECT COUNT(*) FROM document_meta")
            if docCount >= 0 && metaCount >= 0 {
                return docCount == metaCount ? "ok" : "mismatch (docs: \(docCount), meta: \(metaCount))"
            }
            return "unknown"
        }()

        // Gather table statistics
        var tableStats: [DeepDiagnostics.TableStat] = []

        // FTS5 documents table
        let docCount = getIntValue(sql: "SELECT COUNT(*) FROM documents")
        tableStats.append(DeepDiagnostics.TableStat(
            id: "documents",
            name: "documents (FTS5)",
            rowCount: docCount,
            estimatedSize: dbSize / 2 // Rough estimate
        ))

        // Metadata table
        let metaCount = getIntValue(sql: "SELECT COUNT(*) FROM document_meta")
        tableStats.append(DeepDiagnostics.TableStat(
            id: "document_meta",
            name: "document_meta",
            rowCount: metaCount,
            estimatedSize: Int64(metaCount * 200) // ~200 bytes per row estimate
        ))

        // Pragma settings
        let pragmas: [String: String] = [
            "journal_mode": journalMode,
            "auto_vacuum": autoVacuum,
            "synchronous": getStringValue(sql: "PRAGMA synchronous") ?? "unknown",
            "temp_store": getStringValue(sql: "PRAGMA temp_store") ?? "unknown",
            "locking_mode": getStringValue(sql: "PRAGMA locking_mode") ?? "unknown",
            "encoding": getStringValue(sql: "PRAGMA encoding") ?? "unknown"
        ]

        return DeepDiagnostics(
            databasePath: path,
            databaseSizeBytes: dbSize,
            walSizeBytes: walSize,
            shmSizeBytes: shmSize,
            pageSize: pageSize,
            pageCount: pageCount,
            freePageCount: freePageCount,
            schemaVersion: schemaVersion,
            userVersion: userVersion,
            journalMode: journalMode,
            autoVacuum: autoVacuum,
            cacheSize: cacheSize,
            mMapSize: mMapSize,
            integrityCheckResult: integrityResult,
            lastOptimizeTime: nil, // Would need to track this separately
            tableStats: tableStats,
            pragmaSettings: pragmas
        )
    }

    /// Top terms by frequency in the index
    struct TermFrequency: Identifiable, Sendable {
        let id: String
        let term: String
        let documentFrequency: Int // Number of docs containing term
        let totalOccurrences: Int  // Total occurrences across all docs
    }

    /// Get top N most frequent terms in the index (global)
    func getTopTerms(limit: Int = 50) async -> [TermFrequency] {
        ensureInitialized()
        guard let db = database else { return [] }

        // Ensure vocab table exists
        execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS documents_vocab USING fts5vocab(documents, 'row')")

        let sql = """
            SELECT term, doc as doc_freq, cnt as total_count
            FROM documents_vocab
            ORDER BY cnt DESC
            LIMIT ?
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int(statement, 1, Int32(limit))

        var results: [TermFrequency] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let termPtr = sqlite3_column_text(statement, 0) else { continue }
            let term = String(cString: termPtr)
            let docFreq = Int(sqlite3_column_int(statement, 1))
            let totalCount = Int(sqlite3_column_int(statement, 2))

            results.append(TermFrequency(
                id: term,
                term: term,
                documentFrequency: docFreq,
                totalOccurrences: totalCount
            ))
        }

        return results
    }

    /// Get top N most frequent terms for a specific container
    /// Analyzes term frequency from documents in this container only
    /// The most characters of a library the two statistics below read.
    nonisolated static let statisticsCharacterBudget = 2_000_000
    /// The least a document contributes when a library has many documents.
    nonisolated static let statisticsFloorPerDocument = 20_000

    /// Where to read a long text: `count` equal slices, the first at the start and the last at
    /// the end, `share` characters in all. Starts are 1-based, as SQLite's `substr` counts.
    nonisolated static func evenSlices(length: Int, share: Int, count: Int = 8) -> [(start: Int, length: Int)] {
        guard length > 0, share > 0 else { return [] }
        guard length > share, count > 1 else { return [(1, min(length, share))] }
        let slice = max(1, share / count)
        return (0..<count).map { index in
            (1 + index * (length - slice) / (count - 1), slice)
        }
    }

    /// Text for the term and phrase statistics: a short document whole, evenly spaced slices of
    /// a long one, about `statisticsCharacterBudget` characters for the library.
    ///
    /// Both statistics used to read every character of every document. For a library holding
    /// one 88-million-character document that was 14 million words counted, then a string built
    /// for every pair and every triple of them, inside this actor: the Atlas map that waits for
    /// them never finished, and every keyword search queued behind it. The top terms and the
    /// frequent phrases of a library are statistics, and a spread sample gives them.
    private func statisticsText(containerId: UUID, db: OpaquePointer) -> [(document: Int, text: String)] {
        var rows: [(rowid: Int64, length: Int)] = []
        var lengths: OpaquePointer?
        guard
            sqlite3_prepare_v2(
                db, "SELECT rowid, length(content) FROM documents WHERE container_id = ?", -1, &lengths, nil)
                == SQLITE_OK
        else { return [] }
        sqlite3_bind_text(lengths, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
        while sqlite3_step(lengths) == SQLITE_ROW {
            rows.append((sqlite3_column_int64(lengths, 0), Int(sqlite3_column_int64(lengths, 1))))
        }
        sqlite3_finalize(lengths)
        guard !rows.isEmpty else { return [] }

        let share = max(Self.statisticsFloorPerDocument, Self.statisticsCharacterBudget / rows.count)
        var texts: [(document: Int, text: String)] = []
        var read = 0
        for (document, row) in rows.enumerated() {
            guard read < Self.statisticsCharacterBudget * 2 else { break }
            let slices = Self.evenSlices(length: row.length, share: share)
            guard !slices.isEmpty else { continue }
            let columns = slices.map { _ in "substr(content, ?, ?)" }.joined(separator: ", ")
            var statement: OpaquePointer?
            guard
                sqlite3_prepare_v2(db, "SELECT \(columns) FROM documents WHERE rowid = ?", -1, &statement, nil)
                    == SQLITE_OK
            else { continue }
            for (index, slice) in slices.enumerated() {
                sqlite3_bind_int64(statement, Int32(index * 2 + 1), Int64(slice.start))
                sqlite3_bind_int64(statement, Int32(index * 2 + 2), Int64(slice.length))
            }
            sqlite3_bind_int64(statement, Int32(slices.count * 2 + 1), row.rowid)
            if sqlite3_step(statement) == SQLITE_ROW {
                for index in 0..<slices.count {
                    guard let pointer = sqlite3_column_text(statement, Int32(index)) else { continue }
                    let text = String(cString: pointer)
                    read += text.count
                    texts.append((document, text))
                }
            }
            sqlite3_finalize(statement)
        }
        return texts
    }

    func getTopTermsForContainer(containerId: UUID, limit: Int = 50) async -> [TermFrequency] {
        ensureInitialized()
        guard let db = database else { return [] }

        // A sample of the library's text, not all of it: see `statisticsText`.
        let texts = statisticsText(containerId: containerId, db: db)

        // Term analysis
        var termCounts: [String: Int] = [:]
        var termDocCounts: [String: Set<Int>] = [:] // Track which docs contain each term
        var docIndex = 0

        // Stopwords to filter out
        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
            "by", "from", "as", "is", "was", "are", "were", "been", "be", "have", "has", "had",
            "do", "does", "did", "will", "would", "could", "should", "may", "might", "must",
            "that", "this", "these", "those", "it", "its", "their", "they", "them", "there",
            "what", "which", "who", "whom", "when", "where", "why", "how", "all", "each",
            "every", "both", "few", "more", "most", "other", "some", "such", "no", "nor",
            "not", "only", "own", "same", "so", "than", "too", "very", "just", "can"
        ]

        for (document, text) in texts {
            docIndex = document
            let content = text.lowercased()

            // Tokenize - split on non-alphanumerics
            let words = content.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopwords.contains($0) }

            for word in words {
                termCounts[word, default: 0] += 1
                termDocCounts[word, default: Set()].insert(docIndex)
            }
            docIndex += 1
        }

        // Convert to TermFrequency array, sorted by count
        var results = termCounts.map { term, count in
            TermFrequency(
                id: term,
                term: term,
                documentFrequency: termDocCounts[term]?.count ?? 1,
                totalOccurrences: count
            )
        }

        results.sort { $0.totalOccurrences > $1.totalOccurrences }
        return Array(results.prefix(limit))
    }

    /// Get key phrases and concepts for a container (more meaningful than single words)
    /// Returns multi-word phrases that appear frequently
    func getKeyPhrasesForContainer(containerId: UUID, limit: Int = 20) async -> [(phrase: String, count: Int)] {
        ensureInitialized()
        guard let db = database else { return [] }

        // A sample of the library's text, not all of it: see `statisticsText`.
        let texts = statisticsText(containerId: containerId, db: db)

        var bigramCounts: [String: Int] = [:]
        var trigramCounts: [String: Int] = [:]

        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
            "by", "from", "as", "is", "was", "are", "were", "been", "be", "have", "has", "had",
            "that", "this", "it", "its", "they", "them", "there", "can", "will", "would"
        ]

        for (_, text) in texts {
            let content = text.lowercased()

            // Split into words
            let words = content.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }
            guard words.count > 2 else { continue }

            // Extract bigrams (2-word phrases)
            for i in 0..<(words.count - 1) {
                let w1 = words[i], w2 = words[i + 1]
                // At least one non-stopword
                if !stopwords.contains(w1) || !stopwords.contains(w2) {
                    let bigram = "\(w1) \(w2)"
                    bigramCounts[bigram, default: 0] += 1
                }
            }

            // Extract trigrams (3-word phrases) for even more context
            for i in 0..<(words.count - 2) {
                let w1 = words[i], w2 = words[i + 1], w3 = words[i + 2]
                // At least one non-stopword
                if !stopwords.contains(w1) || !stopwords.contains(w2) || !stopwords.contains(w3) {
                    let trigram = "\(w1) \(w2) \(w3)"
                    trigramCounts[trigram, default: 0] += 1
                }
            }
        }

        // Combine and sort - prefer trigrams for meaning, but include strong bigrams
        var phrases: [(String, Int)] = []

        // Add trigrams with count >= 3. Only the strongest can reach the result, and the check
        // below compares every kept bigram with every kept trigram, so both lists are cut first.
        let keep = max(limit, 1) * 5
        for (phrase, count) in trigramCounts.filter({ $0.value >= 3 }).sorted(by: { $0.value > $1.value }).prefix(keep) {
            phrases.append((phrase, count))
        }

        // Add bigrams with count >= 5 (higher threshold since less specific)
        for (phrase, count) in bigramCounts.filter({ $0.value >= 5 }).sorted(by: { $0.value > $1.value }).prefix(keep) {
            // Skip if this bigram is part of a trigram we already have
            let isSubphrase = phrases.contains { $0.0.contains(phrase) }
            if !isSubphrase {
                phrases.append((phrase, count))
            }
        }

        phrases.sort { $0.1 > $1.1 }
        return Array(phrases.prefix(limit))
    }

    /// Term distribution buckets for histogram
    struct TermDistribution: Sendable {
        let bucket: String // e.g., "1-10", "11-50", etc.
        let termCount: Int
    }

    /// Get term frequency distribution for histogram
    func getTermDistribution() async -> [TermDistribution] {
        ensureInitialized()
        guard let db = database else { return [] }

        // Ensure vocab table exists
        execute(sql: "CREATE VIRTUAL TABLE IF NOT EXISTS documents_vocab USING fts5vocab(documents, 'row')")

        // Get all term counts
        let sql = "SELECT cnt FROM documents_vocab"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var counts: [Int] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            counts.append(Int(sqlite3_column_int(statement, 0)))
        }

        // Bucket the counts
        var buckets: [String: Int] = [
            "1": 0,
            "2-5": 0,
            "6-10": 0,
            "11-25": 0,
            "26-50": 0,
            "51-100": 0,
            "101-500": 0,
            "500+": 0
        ]

        for count in counts {
            switch count {
            case 1: buckets["1"]! += 1
            case 2...5: buckets["2-5"]! += 1
            case 6...10: buckets["6-10"]! += 1
            case 11...25: buckets["11-25"]! += 1
            case 26...50: buckets["26-50"]! += 1
            case 51...100: buckets["51-100"]! += 1
            case 101...500: buckets["101-500"]! += 1
            default: buckets["500+"]! += 1
            }
        }

        let orderedKeys = ["1", "2-5", "6-10", "11-25", "26-50", "51-100", "101-500", "500+"]
        return orderedKeys.map { TermDistribution(bucket: $0, termCount: buckets[$0] ?? 0) }
    }

    /// Document length distribution
    struct DocumentLengthStat: Identifiable, Sendable {
        let id: UUID
        let documentId: UUID
        let characterCount: Int
        let wordCount: Int
        let avgWordLength: Double
        let uniqueWordEstimate: Int
    }

    /// Get detailed document length statistics
    func getDocumentLengthStats(containerId: UUID? = nil) async -> [DocumentLengthStat] {
        ensureInitialized()
        guard let db = database else { return [] }

        var sql: String
        if containerId != nil {
            sql = """
                SELECT dm.document_id, dm.character_count, dm.word_count, d.content
                FROM document_meta dm
                JOIN documents d ON dm.document_id = d.document_id
                WHERE dm.container_id = ?
            """
        } else {
            sql = """
                SELECT dm.document_id, dm.character_count, dm.word_count, d.content
                FROM document_meta dm
                JOIN documents d ON dm.document_id = d.document_id
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        if let cId = containerId {
            sqlite3_bind_text(statement, 1, cId.uuidString, -1, SQLITE_TRANSIENT)
        }

        var results: [DocumentLengthStat] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdPtr = sqlite3_column_text(statement, 0),
                  let docId = UUID(uuidString: String(cString: docIdPtr)) else { continue }

            let chars = Int(sqlite3_column_int(statement, 1))
            let words = Int(sqlite3_column_int(statement, 2))

            // Calculate additional stats from content
            var avgWordLen = 0.0
            var uniqueWords = 0

            if let contentPtr = sqlite3_column_text(statement, 3) {
                let content = String(cString: contentPtr)
                let wordArray = content.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
                if !wordArray.isEmpty {
                    let totalCharsInWords = wordArray.reduce(0) { $0 + $1.count }
                    avgWordLen = Double(totalCharsInWords) / Double(wordArray.count)
                    uniqueWords = Set(wordArray.map { $0.lowercased() }).count
                }
            }

            results.append(DocumentLengthStat(
                id: docId,
                documentId: docId,
                characterCount: chars,
                wordCount: words,
                avgWordLength: avgWordLen,
                uniqueWordEstimate: uniqueWords
            ))
        }

        return results
    }

    /// Search performance metrics
    struct SearchPerformanceMetrics: Sendable {
        let queryLatencyMs: Double
        let documentsScanned: Int
        let termsMatched: Int
        let resultsReturned: Int
        let indexHits: Int
    }

    /// Perform a timed search with performance metrics
    func timedSearch(query: String, containerId: UUID? = nil, limit: Int = 20) async -> (results: [FTS5SearchResult], metrics: SearchPerformanceMetrics) {
        ensureInitialized()

        let startTime = CFAbsoluteTimeGetCurrent()

        let results = await search(query: query, containerId: containerId, limit: limit)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000 // ms

        // Count documents in scope
        let docCount: Int
        if let cId = containerId {
            docCount = await documentCount(for: cId)
        } else {
            let stats = await getStats()
            docCount = stats.documentsStored
        }

        // Count matched terms (simplified)
        let queryTerms = query.split(whereSeparator: { $0.isWhitespace }).count

        let metrics = SearchPerformanceMetrics(
            queryLatencyMs: elapsed,
            documentsScanned: docCount,
            termsMatched: queryTerms,
            resultsReturned: results.count,
            indexHits: results.count // Simplified
        )

        return (results, metrics)
    }

    /// Optimize the database (VACUUM and rebuild)
    func optimize() async -> (success: Bool, freedBytes: Int64, elapsedMs: Double) {
        ensureInitialized()

        let startTime = CFAbsoluteTimeGetCurrent()
        let sizeBefore = (try? FileManager.default.attributesOfItem(atPath: databasePath.path)[.size] as? Int64) ?? 0

        // Run FTS5 optimize
        execute(sql: "INSERT INTO documents(documents) VALUES('optimize')")

        // Run VACUUM
        execute(sql: "VACUUM")

        let sizeAfter = (try? FileManager.default.attributesOfItem(atPath: databasePath.path)[.size] as? Int64) ?? 0
        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let freedBytes = sizeBefore - sizeAfter

        Log.info("[SQLiteFTS5] Optimized: freed \(freedBytes) bytes in \(String(format: "%.1f", elapsed))ms", category: .vectorDB)

        return (true, freedBytes, elapsed)
    }

    /// Rebuild the FTS5 index from scratch
    func rebuildIndex() async -> (success: Bool, elapsedMs: Double) {
        ensureInitialized()

        let startTime = CFAbsoluteTimeGetCurrent()

        // FTS5 rebuild command
        let success = execute(sql: "INSERT INTO documents(documents) VALUES('rebuild')")

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        Log.info("[SQLiteFTS5] Index rebuilt in \(String(format: "%.1f", elapsed))ms", category: .vectorDB)

        return (success, elapsed)
    }

    /// Get integrity check results
    func runIntegrityCheck() async -> [String] {
        ensureInitialized()
        guard let db = database else { return ["Database not initialized"] }

        // Run FTS5 integrity check
        let fts5Check = execute(sql: "INSERT INTO documents(documents) VALUES('integrity-check')")

        // Run SQLite integrity check
        let sql = "PRAGMA integrity_check"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return ["Failed to prepare integrity check"]
        }
        defer { sqlite3_finalize(statement) }

        var results: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let msgPtr = sqlite3_column_text(statement, 0) {
                results.append(String(cString: msgPtr))
            }
        }

        if fts5Check {
            results.insert("FTS5 index: OK", at: 0)
        } else {
            results.insert("FTS5 index: CHECK FAILED", at: 0)
        }

        return results
    }

    /// Get full content for a document (no truncation)
    func getFullContent(documentId: UUID) async -> String? {
        ensureInitialized()
        guard let db = database else { return nil }

        // Try fast B-tree indexed table first
        let fastSQL = "SELECT content FROM document_content WHERE document_id = ? LIMIT 1"
        var fastStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, fastSQL, -1, &fastStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(fastStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(fastStmt) == SQLITE_ROW,
               let contentPtr = sqlite3_column_text(fastStmt, 0) {
                let result = String(cString: contentPtr)
                sqlite3_finalize(fastStmt)
                return result
            }
            sqlite3_finalize(fastStmt)
        }

        // Fallback to FTS5 table (pre-migration documents)
        let sql = "SELECT content FROM documents WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            if let contentPtr = sqlite3_column_text(statement, 0) {
                return String(cString: contentPtr)
            }
        }

        return nil
    }

    /// Get stored content length in characters (efficient — no full content load)
    func getContentLength(documentId: UUID) async -> Int? {
        ensureInitialized()
        guard let db = database else { return nil }

        let sql = "SELECT character_count FROM document_meta WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            return Int(sqlite3_column_int64(statement, 0))
        }

        return nil
    }

    /// Get a content preview for a document
    func getContentPreview(documentId: UUID, maxLength: Int = 500) async -> String? {
        ensureInitialized()
        guard let db = database else { return nil }

        // Try fast B-tree indexed table first
        let fastSQL = "SELECT content FROM document_content WHERE document_id = ? LIMIT 1"
        var fastStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, fastSQL, -1, &fastStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(fastStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            if sqlite3_step(fastStmt) == SQLITE_ROW,
               let contentPtr = sqlite3_column_text(fastStmt, 0) {
                let content = String(cString: contentPtr)
                sqlite3_finalize(fastStmt)
                if content.count <= maxLength {
                    return content
                }
                return String(content.prefix(maxLength)) + "\n\n--- Preview truncated (\(content.count.formatted()) characters stored) ---"
            }
            sqlite3_finalize(fastStmt)
        }

        // Fallback to FTS5 table
        let sql = "SELECT content FROM documents WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            if let contentPtr = sqlite3_column_text(statement, 0) {
                let content = String(cString: contentPtr)
                if content.count <= maxLength {
                    return content
                }
                return String(content.prefix(maxLength)) + "\n\n--- Preview truncated (\(content.count.formatted()) of \(content.count.formatted()) characters stored) ---"
            }
        }

        return nil
    }

}
