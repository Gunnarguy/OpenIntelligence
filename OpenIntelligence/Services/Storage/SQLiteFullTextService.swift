//
//  SQLiteFullTextService.swift
//  OpenIntelligence
//
//  SQLite FTS5-powered full-text search service for 10-100X faster
//  keyword search and pattern counting compared to file-based storage.
//
//  Uses iOS-bundled SQLite via `import SQLite3` - 100% native, zero dependencies.
//
//  Features:
//  - FTS5 virtual table with inverted index (O(log n) lookups)
//  - Built-in bm25() ranking function
//  - Porter stemmer + unicode61 tokenizer
//  - highlight() and snippet() for context extraction
//  - Container isolation via separate tables per container
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate

// MARK: - FTS5 Search Result

/// Result from FTS5 search with BM25 ranking
public struct FTS5SearchResult: Sendable {
    public let documentId: UUID
    public let content: String
    public let bm25Score: Double
    public let snippet: String?
    public let highlightedContent: String?
}

/// Result from pattern counting
public struct FTS5PatternCount: Sendable {
    public let documentId: UUID
    public let count: Int
    public let matchPositions: [Range<String.Index>]?
}

// MARK: - SQLite Full Text Service

/// Actor-based SQLite FTS5 service for high-performance full-text search
/// Replaces file-per-document FullTextStorageService with SQLite inverted index
actor SQLiteFullTextService {

    struct StructuredChunkMetadata: Sendable {
        let chunkType: String?
        let tableTitle: String?
        let headers: [String]
        let rows: [[String]]
        let searchText: String
        let extractionQuality: Double
        let extractionSource: String
        let lowQualityRowIndices: [Int]

        var rowCount: Int { rows.count }

        var columnCount: Int {
            max(headers.count, rows.map(\ .count).max() ?? 0)
        }
    }

    struct SQLiteChunk: Sendable {
        let chunkIndex: Int
        let pageNumber: Int?
        let sectionTitle: String?
        let sectionPath: String?
        let structureType: String?
        let content: String
    }

    // MARK: - Singleton

    static let shared = SQLiteFullTextService()

    // MARK: - Properties

    private var database: OpaquePointer?
    private var isInitialized = false
    private let fileManager = FileManager.default
    private let jsonEncoder = JSONEncoder()

    nonisolated private static var directDatabaseURL: URL {
        OpenIntelligenceRuntimePaths.localCacheDirectory()
            .appendingPathComponent("FTS5", isDirectory: true)
            .appendingPathComponent("fulltext.sqlite")
    }

    /// Database file location
    private var databasePath: URL {
        let dir = AppSupportPaths.localCacheDir().appendingPathComponent("FTS5", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fulltext.sqlite")
    }

    // MARK: - Initialization

    private init() {
        // Don't initialize in background - use ensureInitialized() for lazy init
    }

    deinit {
        if let db = database {
            sqlite3_close(db)
        }
    }

    /// Shutdown and close the SQLite database cleanly, executing a WAL checkpoint first.
    func shutdown() {
        guard isInitialized, let db = database else { return }
        
        Log.info("[SQLiteFTS5] Shutting down FTS5 database connection...", category: .vectorDB)
        
        // Execute a WAL checkpoint
        let checkpointSQL = "PRAGMA wal_checkpoint(TRUNCATE)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, checkpointSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
        
        sqlite3_close(db)
        database = nil
        isInitialized = false
        Log.info("[SQLiteFTS5] FTS5 database shutdown completed cleanly.", category: .vectorDB)
    }

    private func checkpoint() {
        guard let db = database else { return }
        let checkpointSQL = "PRAGMA wal_checkpoint(PASSIVE)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, checkpointSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    private func beginTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) != 0 {
            execute(sql: "BEGIN TRANSACTION")
        }
    }

    private func commitTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) == 0 {
            execute(sql: "COMMIT")
        }
    }

    private func rollbackTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) == 0 {
            execute(sql: "ROLLBACK")
        }
    }

    /// Ensure database is initialized before any operation
    /// Called automatically by all public methods
    private func ensureInitialized() {
        guard !isInitialized else { return }
        isInitialized = initializeDatabase()
    }

    /// Initialize SQLite database with FTS5 table
    @discardableResult
    private func initializeDatabase() -> Bool {
        let path = databasePath.path

        guard sqlite3_open(path, &database) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(database))
            Log.error("[SQLiteFTS5] Failed to open database: \(errorMessage)", category: .vectorDB)
            if let db = database {
                sqlite3_close(db)
                database = nil
            }
            return false
        }

        // Enable WAL mode for better concurrency
        execute(sql: "PRAGMA journal_mode=WAL")
        execute(sql: "PRAGMA busy_timeout=3000")

        // Create FTS5 virtual table with porter stemmer for English and unicode61 for case-insensitivity
        // document_id is UNINDEXED (not searchable) - used only for lookups
        // content is the searchable text
        // container_id allows per-container isolation
        let createTableSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS documents USING fts5(
                document_id UNINDEXED,
                container_id UNINDEXED,
                content,
                tokenize='porter unicode61'
            )
        """

        if execute(sql: createTableSQL) {
            Log.info("[SQLiteFTS5] Database initialized at \(path)", category: .vectorDB)
        } else {
            Log.error("[SQLiteFTS5] Failed to create FTS5 table", category: .vectorDB)
            if let db = database {
                sqlite3_close(db)
                database = nil
            }
            return false
        }

        // Create metadata table for tracking document info
        let createMetaSQL = """
            CREATE TABLE IF NOT EXISTS document_meta (
                document_id TEXT PRIMARY KEY,
                container_id TEXT NOT NULL,
                character_count INTEGER NOT NULL,
                word_count INTEGER NOT NULL,
                created_at REAL NOT NULL
            )
        """
        _ = execute(sql: createMetaSQL)

        // MARK: Document Content Lookup Table
        // Regular table (NOT FTS5) for fast document_id-based content retrieval.
        // FTS5 UNINDEXED columns require full table scans for WHERE clauses,
        // which causes 30+ second hangs when viewing document content.
        // This table has a proper B-tree index on document_id for O(log n) lookup.
        let createContentSQL = """
            CREATE TABLE IF NOT EXISTS document_content (
                document_id TEXT PRIMARY KEY,
                container_id TEXT NOT NULL,
                content TEXT NOT NULL
            )
        """
        _ = execute(sql: createContentSQL)

        // MARK: Chunk-Level FTS5 Table
        // Indexes individual chunks (not whole documents) for chunk-level BM25 scoring.
        // section_title and section_path are SEARCHABLE — enabling queries like:
        //   "oil" filtered to chunks whose section contains "engine"
        // This is the key to distinguishing "engine oil" chunks from "gear oil" chunks.
        let createChunkTableSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
                chunk_id UNINDEXED,
                document_id UNINDEXED,
                container_id UNINDEXED,
                chunk_index UNINDEXED,
                page_number UNINDEXED,
                section_title,
                section_path,
                structure_type UNINDEXED,
                content,
                tokenize='porter unicode61',
                columnsize=0
            )
        """

        if execute(sql: createChunkTableSQL) {
            Log.info("[SQLiteFTS5] Chunk-level FTS5 table initialized", category: .vectorDB)
        }

        let createChunkStructuredSQL = """
            CREATE TABLE IF NOT EXISTS chunk_structured (
                chunk_id TEXT PRIMARY KEY,
                document_id TEXT NOT NULL,
                container_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                page_number INTEGER,
                section_title TEXT,
                section_path TEXT,
                structure_type TEXT,
                chunk_type TEXT,
                table_title TEXT,
                table_headers_json TEXT,
                table_rows_json TEXT,
                table_row_count INTEGER NOT NULL DEFAULT 0,
                table_column_count INTEGER NOT NULL DEFAULT 0,
                extraction_quality REAL NOT NULL DEFAULT 0,
                extraction_source TEXT NOT NULL DEFAULT '',
                search_text TEXT NOT NULL
            )
        """
        _ = execute(sql: createChunkStructuredSQL)
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_structured_container ON chunk_structured(container_id)")
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_structured_document ON chunk_structured(document_id)")
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_structured_type ON chunk_structured(structure_type)")
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_structured_title ON chunk_structured(table_title)")

        let createChunkTableRowsSQL = """
            CREATE TABLE IF NOT EXISTS chunk_table_rows (
                row_id TEXT PRIMARY KEY,
                chunk_id TEXT NOT NULL,
                document_id TEXT NOT NULL,
                container_id TEXT NOT NULL,
                chunk_index INTEGER NOT NULL,
                page_number INTEGER,
                table_title TEXT,
                row_index INTEGER NOT NULL,
                headers_json TEXT,
                row_json TEXT NOT NULL,
                row_text TEXT NOT NULL,
                row_quality REAL NOT NULL DEFAULT 0,
                is_low_quality INTEGER NOT NULL DEFAULT 0,
                extraction_quality REAL NOT NULL DEFAULT 0,
                extraction_source TEXT NOT NULL DEFAULT ''
            )
        """
        _ = execute(sql: createChunkTableRowsSQL)
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_table_rows_container ON chunk_table_rows(container_id)")
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_table_rows_document ON chunk_table_rows(document_id)")
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_chunk_table_rows_chunk ON chunk_table_rows(chunk_id)")

        ensureColumnExists(table: "chunk_structured", column: "extraction_quality", definition: "REAL NOT NULL DEFAULT 0")
        ensureColumnExists(table: "chunk_structured", column: "extraction_source", definition: "TEXT NOT NULL DEFAULT ''")
        ensureColumnExists(table: "chunk_table_rows", column: "row_quality", definition: "REAL NOT NULL DEFAULT 0")
        ensureColumnExists(table: "chunk_table_rows", column: "is_low_quality", definition: "INTEGER NOT NULL DEFAULT 0")
        ensureColumnExists(table: "chunk_table_rows", column: "extraction_quality", definition: "REAL NOT NULL DEFAULT 0")
        ensureColumnExists(table: "chunk_table_rows", column: "extraction_source", definition: "TEXT NOT NULL DEFAULT ''")

        // MARK: Page-Level FTS5 Table
        // Stores each PDF page as a separate row for page-level search and context isolation.
        // This enables: (1) page-scoped BM25 search, (2) page-level context retrieval,
        // (3) proper page boundary preservation in exports and queries.
        let createPageTableSQL = """
            CREATE VIRTUAL TABLE IF NOT EXISTS document_pages USING fts5(
                page_id UNINDEXED,
                document_id UNINDEXED,
                container_id UNINDEXED,
                page_number UNINDEXED,
                content,
                tokenize='porter unicode61'
            )
        """

        if execute(sql: createPageTableSQL) {
            Log.info("[SQLiteFTS5] Page-level FTS5 table initialized", category: .vectorDB)
        }

        // MARK: Semantic Query Cache Table
        let createSemanticQueryCacheSQL = """
            CREATE TABLE IF NOT EXISTS semantic_query_cache (
                normalized_query TEXT NOT NULL,
                container_id TEXT NOT NULL,
                embedding_json TEXT NOT NULL,
                results_json TEXT NOT NULL,
                created_at REAL NOT NULL,
                PRIMARY KEY (normalized_query, container_id)
            )
        """
        _ = execute(sql: createSemanticQueryCacheSQL)
        _ = execute(sql: "CREATE INDEX IF NOT EXISTS idx_semantic_query_cache_container ON semantic_query_cache(container_id)")

        return true
    }

    // NOTE: Bulk backfill removed — caused actor thread blocking.
    // Individual documents are migrated on-demand in readFromFTS5Fallback().

    // MARK: - Core CRUD Operations

    /// Store document text in FTS5 index
    /// - Parameters:
    ///   - text: Complete document text
    ///   - documentId: Document UUID
    ///   - containerId: Container UUID for isolation
    func store(text: String, for documentId: UUID, containerId: UUID) async {
        ensureInitialized()
        guard let db = database else {
            Log.error("[SQLiteFTS5] Database not initialized", category: .vectorDB)
            return
        }

        // Delete existing entry if present (upsert behavior)
        await delete(for: documentId)

        // Insert into FTS5 table
        let insertSQL = "INSERT INTO documents (document_id, container_id, content) VALUES (?, ?, ?)"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            Log.error("[SQLiteFTS5] Failed to prepare insert statement", category: .vectorDB)
            return
        }

        defer { sqlite3_finalize(statement) }

        let docIdStr = documentId.uuidString
        let containerIdStr = containerId.uuidString

        sqlite3_bind_text(statement, 1, docIdStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, containerIdStr, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, text, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] Insert failed: \(error)", category: .vectorDB)
            return
        }

        // Store in fast-lookup content table (regular B-tree indexed table)
        let contentSQL = "INSERT OR REPLACE INTO document_content (document_id, container_id, content) VALUES (?, ?, ?)"
        var contentStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, contentSQL, -1, &contentStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(contentStmt, 1, docIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(contentStmt, 2, containerIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(contentStmt, 3, text, -1, SQLITE_TRANSIENT)
            sqlite3_step(contentStmt)
            sqlite3_finalize(contentStmt)
        }

        // Store metadata
        let wordCount = countWords(in: text)
        let metaSQL = "INSERT OR REPLACE INTO document_meta (document_id, container_id, character_count, word_count, created_at) VALUES (?, ?, ?, ?, ?)"
        var metaStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, docIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(metaStmt, 2, containerIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(metaStmt, 3, Int64(text.count))
            sqlite3_bind_int64(metaStmt, 4, Int64(wordCount))
            sqlite3_bind_double(metaStmt, 5, Date().timeIntervalSince1970)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        checkpoint()
        Log.debug("[SQLiteFTS5] Stored document \(documentId) (\(text.count) chars, \(wordCount) words)", category: .vectorDB)
    }

    /// Store per-page text in FTS5 index for page-level search and context isolation
    /// - Parameters:
    ///   - pages: Array of (pageNumber, content) tuples — one per PDF page
    ///   - documentId: Document UUID
    ///   - containerId: Container UUID for isolation
    func storePages(pages: [(pageNumber: Int, content: String)], for documentId: UUID, containerId: UUID) async {
        ensureInitialized()
        guard let db = database else {
            Log.error("[SQLiteFTS5] Database not initialized for page storage", category: .vectorDB)
            return
        }

        guard !pages.isEmpty else { return }

        // Delete existing pages for this document
        let deleteSQL = "DELETE FROM document_pages WHERE document_id = ?"
        var delStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(delStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(delStmt)
            sqlite3_finalize(delStmt)
        }

        // Insert each page as a separate row in a transaction
        beginTransaction()

        let insertSQL = "INSERT INTO document_pages (page_id, document_id, container_id, page_number, content) VALUES (?, ?, ?, ?, ?)"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            Log.error("[SQLiteFTS5] Failed to prepare page insert statement", category: .vectorDB)
            rollbackTransaction()
            return
        }

        let docIdStr = documentId.uuidString
        let containerIdStr = containerId.uuidString
        var storedCount = 0

        for (pageNumber, content) in pages {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            let pageId = "\(docIdStr)_p\(pageNumber)"
            sqlite3_bind_text(statement, 1, pageId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, docIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, containerIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 4, Int64(pageNumber))
            sqlite3_bind_text(statement, 5, trimmed, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                Log.warning("[SQLiteFTS5] Failed to insert page \(pageNumber): \(error)", category: .vectorDB)
            } else {
                storedCount += 1
            }
        }

        sqlite3_finalize(statement)
        commitTransaction()
        checkpoint()

        Log.info("[SQLiteFTS5] Stored \(storedCount) pages for document \(documentId)", category: .vectorDB)
    }

    /// Search pages within a container, returning page-level results with page numbers
    struct PageSearchResult: Sendable {
        let documentId: UUID
        let pageNumber: Int
        let content: String
        let bm25Score: Double
        let snippet: String
    }

    func searchPages(query: String, containerId: UUID, limit: Int = 10) async -> [PageSearchResult] {
        ensureInitialized()
        guard let db = database else { return [] }

        let searchSQL = """
            SELECT page_id, document_id, page_number, content,
                   bm25(document_pages) as score,
                   snippet(document_pages, 4, '<b>', '</b>', '...', 32) as snip
            FROM document_pages
            WHERE document_pages MATCH ? AND container_id = ?
            ORDER BY bm25(document_pages)
            LIMIT ?
        """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK else {
            Log.error("[SQLiteFTS5] Failed to prepare page search", category: .vectorDB)
            return []
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, query, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, containerId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 3, Int64(limit))

        var results: [PageSearchResult] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let docIdStr = sqlite3_column_text(statement, 1),
                  let documentId = UUID(uuidString: String(cString: docIdStr)) else { continue }
            let pageNumber = Int(sqlite3_column_int64(statement, 2))
            let content = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let score = sqlite3_column_double(statement, 4)
            let snippet = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""

            results.append(PageSearchResult(
                documentId: documentId,
                pageNumber: pageNumber,
                content: content,
                bm25Score: score,
                snippet: snippet
            ))
        }

        return results
    }

    /// Retrieve text for a specific page
    func retrievePage(documentId: UUID, pageNumber: Int) async -> String? {
        ensureInitialized()
        guard let db = database else { return nil }

        let sql = "SELECT content FROM document_pages WHERE document_id = ? AND page_number = ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, Int64(pageNumber))

        if sqlite3_step(statement) == SQLITE_ROW,
           let text = sqlite3_column_text(statement, 0) {
            return String(cString: text)
        }
        return nil
    }

    /// Retrieve all pages for a document, ordered by page number
    func retrieveAllPages(for documentId: UUID) async -> [(pageNumber: Int, content: String)] {
        ensureInitialized()
        guard let db = database else { return [] }

        let sql = "SELECT page_number, content FROM document_pages WHERE document_id = ? ORDER BY CAST(page_number AS INTEGER)"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        var pages: [(pageNumber: Int, content: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let pageNumber = Int(sqlite3_column_int64(statement, 0))
            if let text = sqlite3_column_text(statement, 1) {
                pages.append((pageNumber: pageNumber, content: String(cString: text)))
            }
        }
        return pages
    }

    /// Retrieve full document text
    func retrieve(for documentId: UUID) async -> String? {
        ensureInitialized()
        guard let db = database else { return nil }

        let selectSQL = "SELECT content FROM documents WHERE document_id = ?"
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, selectSQL, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW {
            if let contentPtr = sqlite3_column_text(statement, 0) {
                return String(cString: contentPtr)
            }
        }

        return nil
    }

    /// Delete document from FTS5 index
    func delete(for documentId: UUID) async {
        ensureInitialized()
        guard let db = database else { return }

        // Delete from FTS5
        let deleteSQL = "DELETE FROM documents WHERE document_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        // Delete from metadata
        let deleteMetaSQL = "DELETE FROM document_meta WHERE document_id = ?"
        var metaStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteMetaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        // Delete from page-level table
        let deletePageSQL = "DELETE FROM document_pages WHERE document_id = ?"
        var pageStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deletePageSQL, -1, &pageStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(pageStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(pageStmt)
            sqlite3_finalize(pageStmt)
        }

        // Delete from content lookup table
        let deleteContentSQL = "DELETE FROM document_content WHERE document_id = ?"
        var contentStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteContentSQL, -1, &contentStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(contentStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(contentStmt)
            sqlite3_finalize(contentStmt)
        }

        checkpoint()
        Log.debug("[SQLiteFTS5] Deleted document \(documentId)", category: .vectorDB)
    }

    /// Delete all documents for a container
    func deleteContainer(containerId: UUID) async {
        ensureInitialized()
        guard let db = database else { return }

        // Get all document IDs for this container first
        let selectSQL = "SELECT document_id FROM documents WHERE container_id = ?"
        var selectStmt: OpaquePointer?
        var documentIds: [String] = []

        if sqlite3_prepare_v2(db, selectSQL, -1, &selectStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(selectStmt, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            while sqlite3_step(selectStmt) == SQLITE_ROW {
                if let idPtr = sqlite3_column_text(selectStmt, 0) {
                    documentIds.append(String(cString: idPtr))
                }
            }
            sqlite3_finalize(selectStmt)
        }

        // Delete from FTS5
        let deleteSQL = "DELETE FROM documents WHERE container_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        // Delete from metadata
        let deleteMetaSQL = "DELETE FROM document_meta WHERE container_id = ?"
        var metaStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteMetaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        // Delete from page-level table
        let deletePageSQL = "DELETE FROM document_pages WHERE container_id = ?"
        var pageDelStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deletePageSQL, -1, &pageDelStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(pageDelStmt, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(pageDelStmt)
            sqlite3_finalize(pageDelStmt)
        }

        // Delete from content lookup table
        let deleteContentSQL = "DELETE FROM document_content WHERE container_id = ?"
        var contentDelStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteContentSQL, -1, &contentDelStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(contentDelStmt, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(contentDelStmt)
            sqlite3_finalize(contentDelStmt)
        }

        checkpoint()
        Log.info("[SQLiteFTS5] Deleted \(documentIds.count) documents for container \(containerId)", category: .vectorDB)
    }

    // MARK: - Chunk-Level CRUD Operations

    /// Result from chunk-level FTS5 search with section context
    struct ChunkSearchResult: Sendable {
        let chunkId: String
        let documentId: UUID
        let containerId: UUID
        let chunkIndex: Int
        let pageNumber: Int?
        let sectionTitle: String?
        let sectionPath: String?
        let content: String
        let bm25Score: Double
    }

    /// Store a single chunk in the chunk-level FTS5 index.
    /// Called during ingestion after chunking and metadata extraction.
    /// - Parameters:
    ///   - chunkId: Unique chunk identifier (documentId_chunkIndex)
    ///   - documentId: Parent document UUID
    ///   - containerId: Container UUID
    ///   - chunkIndex: Position in document (0-based)
    ///   - pageNumber: Page number (nil if unknown)
    ///   - sectionTitle: Nearest parent section heading (nil if not detected)
    ///   - sectionPath: Full hierarchical path e.g. "SPECIFICATIONS > Engine Oil"
    ///   - structureType: table/paragraph/list/title (nil if undetected)
    ///   - content: The chunk text
    func storeChunk(
        chunkId: String,
        documentId: UUID,
        containerId: UUID,
        chunkIndex: Int,
        pageNumber: Int?,
        sectionTitle: String?,
        sectionPath: String?,
        structureType: String?,
        content: String,
        structuredMetadata: StructuredChunkMetadata? = nil
    ) async {
        ensureInitialized()
        guard let db = database else { return }

        let insertSQL = """
            INSERT INTO chunks (chunk_id, document_id, container_id, chunk_index, page_number,
                               section_title, section_path, structure_type, content)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            Log.error("[SQLiteFTS5] Failed to prepare chunk insert", category: .vectorDB)
            return
        }

        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, chunkId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, documentId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, containerId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 4, Int32(chunkIndex))
        if let pn = pageNumber {
            sqlite3_bind_int(statement, 5, Int32(pn))
        } else {
            sqlite3_bind_null(statement, 5)
        }
        sqlite3_bind_text(statement, 6, sectionTitle ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, sectionPath ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 8, structureType ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 9, content, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) != SQLITE_DONE {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] Chunk insert failed: \(error)", category: .vectorDB)
            return
        }

        if let structuredMetadata {
            persistStructuredChunkMetadata(
                chunkId: chunkId,
                documentId: documentId,
                containerId: containerId,
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                sectionTitle: sectionTitle,
                sectionPath: sectionPath,
                structureType: structureType,
                structuredMetadata: structuredMetadata,
                using: db
            )
        }
        checkpoint()
    }

    /// Store all chunks for a document in a single transaction (fast batch insert)
    func storeChunks(
        documentId: UUID,
        containerId: UUID,
        chunks: [(chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                  sectionPath: String?, structureType: String?, chunkType: String?,
                  tableTitle: String?, content: String,
                  structuredMetadata: StructuredChunkMetadata?)]
    ) async {
        ensureInitialized()
        guard let db = database else { return }

        // Delete any existing chunks for this document first
        await deleteChunks(for: documentId)

        let insertSQL = """
            INSERT INTO chunks (chunk_id, document_id, container_id, chunk_index, page_number,
                               section_title, section_path, structure_type, content)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        // Wrap in transaction for speed (100x faster than individual inserts)
        beginTransaction()

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            rollbackTransaction()
            return
        }
        defer { sqlite3_finalize(statement) }

        for chunk in chunks {
            let chunkId = "\(documentId.uuidString)_\(chunk.chunkIndex)"
            sqlite3_bind_text(statement, 1, chunkId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 3, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(statement, 4, Int32(chunk.chunkIndex))
            if let pn = chunk.pageNumber {
                sqlite3_bind_int(statement, 5, Int32(pn))
            } else {
                sqlite3_bind_null(statement, 5)
            }
            sqlite3_bind_text(statement, 6, chunk.sectionTitle ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 7, chunk.sectionPath ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 8, chunk.structureType ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 9, chunk.content, -1, SQLITE_TRANSIENT)

            sqlite3_step(statement)
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            if let structuredMetadata = chunk.structuredMetadata {
                persistStructuredChunkMetadata(
                    chunkId: chunkId,
                    documentId: documentId,
                    containerId: containerId,
                    chunkIndex: chunk.chunkIndex,
                    pageNumber: chunk.pageNumber,
                    sectionTitle: chunk.sectionTitle,
                    sectionPath: chunk.sectionPath,
                    structureType: chunk.structureType,
                    structuredMetadata: StructuredChunkMetadata(
                        chunkType: chunk.chunkType ?? structuredMetadata.chunkType,
                        tableTitle: chunk.tableTitle ?? structuredMetadata.tableTitle,
                        headers: structuredMetadata.headers,
                        rows: structuredMetadata.rows,
                        searchText: structuredMetadata.searchText,
                        extractionQuality: structuredMetadata.extractionQuality,
                        extractionSource: structuredMetadata.extractionSource,
                        lowQualityRowIndices: structuredMetadata.lowQualityRowIndices
                    ),
                    using: db
                )
            }
        }

        commitTransaction()
        checkpoint()
        Log.info("[SQLiteFTS5] Stored \(chunks.count) chunks for document \(documentId)", category: .vectorDB)
    }

    /// Retrieve all chunks for a specific document
    func retrieveChunks(for documentId: UUID) async -> [SQLiteChunk] {
        ensureInitialized()
        guard let db = database else { return [] }

        let sql = """
            SELECT chunk_index, page_number, section_title, section_path, structure_type, content 
            FROM chunks 
            WHERE document_id = ? 
            ORDER BY chunk_index
        """
        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] retrieveChunks prepare failed: \(error)", category: .vectorDB)
            return []
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        var chunks: [SQLiteChunk] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let chunkIndex = Int(sqlite3_column_int(statement, 0))
            let pageNumber: Int? = sqlite3_column_type(statement, 1) != SQLITE_NULL
                ? Int(sqlite3_column_int(statement, 1)) : nil
            
            let sectionTitle: String? = {
                guard let ptr = sqlite3_column_text(statement, 2) else { return nil }
                let str = String(cString: ptr)
                return str.isEmpty ? nil : str
            }()
            
            let sectionPath: String? = {
                guard let ptr = sqlite3_column_text(statement, 3) else { return nil }
                let str = String(cString: ptr)
                return str.isEmpty ? nil : str
            }()
            
            let structureType: String? = {
                guard let ptr = sqlite3_column_text(statement, 4) else { return nil }
                let str = String(cString: ptr)
                return str.isEmpty ? nil : str
            }()
            
            guard let contentPtr = sqlite3_column_text(statement, 5) else { continue }
            let content = String(cString: contentPtr)
            
            chunks.append(SQLiteChunk(
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                sectionTitle: sectionTitle,
                sectionPath: sectionPath,
                structureType: structureType,
                content: content
            ))
        }
        return chunks
    }

    /// Delete all chunks for a document
    func deleteChunks(for documentId: UUID) async {
        ensureInitialized()
        guard let db = database else { return }

        let deleteSQL = "DELETE FROM chunks WHERE document_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        deleteStructuredMetadata(documentId: documentId, using: db)
        checkpoint()
    }

    /// Delete all chunks for a container
    func deleteChunksForContainer(containerId: UUID) async {
        ensureInitialized()
        guard let db = database else { return }

        let deleteSQL = "DELETE FROM chunks WHERE container_id = ?"
        var statement: OpaquePointer?

        if sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }

        deleteStructuredMetadata(containerId: containerId, using: db)
        checkpoint()
    }

    private func persistStructuredChunkMetadata(
        chunkId: String,
        documentId: UUID,
        containerId: UUID,
        chunkIndex: Int,
        pageNumber: Int?,
        sectionTitle: String?,
        sectionPath: String?,
        structureType: String?,
        structuredMetadata: StructuredChunkMetadata,
        using db: OpaquePointer?
    ) {
        guard let db else { return }

        let headersJSON = jsonString(for: structuredMetadata.headers)
        let rowsJSON = jsonString(for: structuredMetadata.rows)
        let insertStructuredSQL = """
            INSERT OR REPLACE INTO chunk_structured (
                chunk_id, document_id, container_id, chunk_index, page_number,
                section_title, section_path, structure_type, chunk_type, table_title,
                table_headers_json, table_rows_json, table_row_count, table_column_count,
                extraction_quality, extraction_source, search_text
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var structuredStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, insertStructuredSQL, -1, &structuredStatement, nil) == SQLITE_OK {
            defer { sqlite3_finalize(structuredStatement) }
            sqlite3_bind_text(structuredStatement, 1, chunkId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 2, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 3, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(structuredStatement, 4, Int32(chunkIndex))
            if let pageNumber {
                sqlite3_bind_int(structuredStatement, 5, Int32(pageNumber))
            } else {
                sqlite3_bind_null(structuredStatement, 5)
            }
            sqlite3_bind_text(structuredStatement, 6, sectionTitle ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 7, sectionPath ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 8, structureType ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 9, structuredMetadata.chunkType ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 10, structuredMetadata.tableTitle ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 11, headersJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 12, rowsJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(structuredStatement, 13, Int32(structuredMetadata.rowCount))
            sqlite3_bind_int(structuredStatement, 14, Int32(structuredMetadata.columnCount))
            sqlite3_bind_double(structuredStatement, 15, structuredMetadata.extractionQuality)
            sqlite3_bind_text(structuredStatement, 16, structuredMetadata.extractionSource, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(structuredStatement, 17, structuredMetadata.searchText, -1, SQLITE_TRANSIENT)

            if sqlite3_step(structuredStatement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                Log.error("[SQLiteFTS5] Structured chunk metadata insert failed: \(error)", category: .vectorDB)
            }
        }

        let insertRowSQL = """
            INSERT OR REPLACE INTO chunk_table_rows (
                row_id, chunk_id, document_id, container_id, chunk_index, page_number,
                table_title, row_index, headers_json, row_json, row_text,
                row_quality, is_low_quality, extraction_quality, extraction_source
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        var rowStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertRowSQL, -1, &rowStatement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(rowStatement) }

        for (rowIndex, row) in structuredMetadata.rows.enumerated() {
            let rowQuality = structuredRowQualityScore(headers: structuredMetadata.headers, row: row)
            let isLowQuality = structuredMetadata.lowQualityRowIndices.contains(rowIndex) || rowQuality < 0.38

            let rowId = "\(chunkId)_row_\(rowIndex)"
            let rowJSON = jsonString(for: row)
            let rowText = rowText(headers: structuredMetadata.headers, row: row)
            guard !rowText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if isLowQuality && rowQuality < 0.28 {
                continue
            }

            sqlite3_bind_text(rowStatement, 1, rowId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(rowStatement, 2, chunkId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(rowStatement, 3, documentId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(rowStatement, 4, containerId.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(rowStatement, 5, Int32(chunkIndex))
            if let pageNumber {
                sqlite3_bind_int(rowStatement, 6, Int32(pageNumber))
            } else {
                sqlite3_bind_null(rowStatement, 6)
            }
            sqlite3_bind_text(rowStatement, 7, structuredMetadata.tableTitle ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(rowStatement, 8, Int32(rowIndex))
            sqlite3_bind_text(rowStatement, 9, headersJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(rowStatement, 10, rowJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(rowStatement, 11, rowText, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(rowStatement, 12, rowQuality)
            sqlite3_bind_int(rowStatement, 13, isLowQuality ? 1 : 0)
            sqlite3_bind_double(rowStatement, 14, structuredMetadata.extractionQuality)
            sqlite3_bind_text(rowStatement, 15, structuredMetadata.extractionSource, -1, SQLITE_TRANSIENT)

            if sqlite3_step(rowStatement) != SQLITE_DONE {
                let error = String(cString: sqlite3_errmsg(db))
                Log.error("[SQLiteFTS5] Structured table row insert failed: \(error)", category: .vectorDB)
            }

            sqlite3_reset(rowStatement)
            sqlite3_clear_bindings(rowStatement)
        }
    }

    private func deleteStructuredMetadata(documentId: UUID, using db: OpaquePointer?) {
        guard let db else { return }
        let deletes = [
            "DELETE FROM chunk_structured WHERE document_id = ?",
            "DELETE FROM chunk_table_rows WHERE document_id = ?"
        ]

        for sql in deletes {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    private func deleteStructuredMetadata(containerId: UUID, using db: OpaquePointer?) {
        guard let db else { return }
        let deletes = [
            "DELETE FROM chunk_structured WHERE container_id = ?",
            "DELETE FROM chunk_table_rows WHERE container_id = ?"
        ]

        for sql in deletes {
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
                sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(statement)
                sqlite3_finalize(statement)
            }
        }
    }

    private func jsonString<T: Encodable>(for value: T) -> String {
        guard let data = try? jsonEncoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private func rowText(headers: [String], row: [String]) -> String {
        guard !row.isEmpty else { return "" }

        let pairs = row.enumerated().compactMap { index, value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let header = index < headers.count ? headers[index].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            if header.isEmpty {
                return trimmed
            }
            return "\(header): \(trimmed)"
        }

        return pairs.joined(separator: " | ")
    }

    private func meaningfulStructuredSearchTerms(from query: String) -> [String] {
        let stopWords: Set<String> = [
            "a", "an", "the", "and", "or", "but", "if", "then", "else", "is", "are", "was", "were",
            "do", "does", "did", "what", "which", "who", "when", "where", "why", "how", "can", "could",
            "should", "would", "please", "show", "tell", "mean", "means", "meaning", "indicate", "indicates",
            "signal", "signals", "about", "from", "with", "for", "into", "onto", "your", "their", "there",
            "much", "many", "kind", "type", "listed", "light", "lights", "indicator", "indicators", "led"
        ]

        return query.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 && !stopWords.contains($0) }
    }

    private func searchStructuredChunks(
        query: String,
        containerId: UUID?,
        limit: Int
    ) -> [ChunkSearchResult] {
        guard let db = database else { return [] }

        let terms = meaningfulStructuredSearchTerms(from: query)
        guard !terms.isEmpty else { return [] }

        let sql: String
        if containerId != nil {
            sql = """
                SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                       section_title, section_path, table_title, search_text, table_row_count,
                       extraction_quality, extraction_source
                FROM chunk_structured
                WHERE structure_type = 'table' AND container_id = ?
            """
        } else {
            sql = """
                SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                       section_title, section_path, table_title, search_text, table_row_count,
                       extraction_quality, extraction_source
                FROM chunk_structured
                WHERE structure_type = 'table'
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] Structured chunk search prepare failed: \(error)", category: .retrieval)
            return []
        }

        defer { sqlite3_finalize(statement) }

        if let containerId {
            sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
        }

        var scoredResults: [(result: ChunkSearchResult, score: Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let chunkIdPtr = sqlite3_column_text(statement, 0),
                  let documentIdPtr = sqlite3_column_text(statement, 1),
                  let containerIdPtr = sqlite3_column_text(statement, 2),
                  let documentId = UUID(uuidString: String(cString: documentIdPtr)),
                  let rowContainerId = UUID(uuidString: String(cString: containerIdPtr)) else {
                continue
            }

            let chunkId = String(cString: chunkIdPtr)
            let chunkIndex = Int(sqlite3_column_int(statement, 3))
            let pageNumber: Int? = sqlite3_column_type(statement, 4) != SQLITE_NULL
                ? Int(sqlite3_column_int(statement, 4)) : nil
            let sectionTitle = sqlite3_column_text(statement, 5).map { String(cString: $0) }
            let sectionPath = sqlite3_column_text(statement, 6).map { String(cString: $0) }
            let tableTitle = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            let searchText = sqlite3_column_text(statement, 8).map { String(cString: $0) } ?? ""
            let rowCount = Int(sqlite3_column_int(statement, 9))
            let extractionQuality = sqlite3_column_double(statement, 10)
            let extractionSource = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? ""

            guard extractionQuality >= 0.26 else { continue }

            let titleLower = tableTitle.lowercased()
            let searchLower = searchText.lowercased()
            let titleHits = terms.filter { titleLower.contains($0) }.count
            let searchHits = terms.filter { searchLower.contains($0) }.count
            let minRequired = min(2, terms.count)
            guard searchHits >= minRequired || titleHits > 0 else { continue }

            let coverage = Double(searchHits + titleHits) / Double(max(1, terms.count))
            let qualityFactor = 0.55 + min(1.0, max(0.0, extractionQuality)) * 0.45
            let score = (Double(titleHits) * 2.5 + Double(searchHits) * 1.2 + coverage * 2.0 + min(Double(rowCount), 12.0) * 0.03) * qualityFactor + structuredSourceBonus(extractionSource)

            let result = ChunkSearchResult(
                chunkId: chunkId,
                documentId: documentId,
                containerId: rowContainerId,
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                sectionTitle: sectionTitle?.isEmpty == true ? nil : sectionTitle,
                sectionPath: sectionPath?.isEmpty == true ? nil : sectionPath,
                content: searchText,
                bm25Score: score
            )
            scoredResults.append((result, score))
        }

        let results = scoredResults
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .prefix(limit)
            .map(\ .result)

        if !results.isEmpty {
            Log.debug("[SQLiteFTS5] Structured chunk search '\(query)' returned \(results.count) results", category: .retrieval)
        }

        return results
    }

    private func searchStructuredTableRowsInternal(
        query: String,
        containerId: UUID?,
        limit: Int
    ) -> [ChunkSearchResult] {
        guard let db = database else { return [] }

        let terms = meaningfulStructuredSearchTerms(from: query)
        guard !terms.isEmpty else { return [] }

        let sql: String
        if containerId != nil {
            sql = """
                SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                       table_title, headers_json, row_text, row_quality, is_low_quality,
                       extraction_quality, extraction_source
                FROM chunk_table_rows
                WHERE container_id = ?
            """
        } else {
            sql = """
                SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                       table_title, headers_json, row_text, row_quality, is_low_quality,
                       extraction_quality, extraction_source
                FROM chunk_table_rows
            """
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            Log.error("[SQLiteFTS5] Structured row search prepare failed: \(error)", category: .retrieval)
            return []
        }

        defer { sqlite3_finalize(statement) }

        if let containerId {
            sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)
        }

        var scoredResults: [(result: ChunkSearchResult, score: Double)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let chunkIdPtr = sqlite3_column_text(statement, 0),
                  let documentIdPtr = sqlite3_column_text(statement, 1),
                  let containerIdPtr = sqlite3_column_text(statement, 2),
                  let documentId = UUID(uuidString: String(cString: documentIdPtr)),
                  let rowContainerId = UUID(uuidString: String(cString: containerIdPtr)) else {
                continue
            }

            let chunkId = String(cString: chunkIdPtr)
            let chunkIndex = Int(sqlite3_column_int(statement, 3))
            let pageNumber: Int? = sqlite3_column_type(statement, 4) != SQLITE_NULL
                ? Int(sqlite3_column_int(statement, 4)) : nil
            let tableTitle = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            let headersJSON = sqlite3_column_text(statement, 6).map { String(cString: $0) } ?? ""
            let rowText = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
            let rowQuality = sqlite3_column_double(statement, 8)
            let isLowQuality = sqlite3_column_int(statement, 9) != 0
            let extractionQuality = sqlite3_column_double(statement, 10)
            let extractionSource = sqlite3_column_text(statement, 11).map { String(cString: $0) } ?? ""

            guard !isLowQuality else { continue }
            guard rowQuality >= 0.38 else { continue }

            let titleLower = tableTitle.lowercased()
            let headerLower = headersJSON.lowercased()
            let rowLower = rowText.lowercased()

            var uniqueHits = Set<String>()
            let titleHits = terms.filter { term in
                let matched = titleLower.contains(term)
                if matched { uniqueHits.insert(term) }
                return matched
            }.count
            let headerHits = terms.filter { term in
                let matched = headerLower.contains(term)
                if matched { uniqueHits.insert(term) }
                return matched
            }.count
            let rowHits = terms.filter { term in
                let matched = rowLower.contains(term)
                if matched { uniqueHits.insert(term) }
                return matched
            }.count

            let minRequired = min(2, terms.count)
            guard uniqueHits.count >= minRequired else { continue }

            let coverage = Double(uniqueHits.count) / Double(max(1, terms.count))
            let qualityFactor = (0.60 + min(1.0, max(0.0, rowQuality)) * 0.30) * (0.80 + min(1.0, max(0.0, extractionQuality)) * 0.20)
            let score = (Double(rowHits) * 1.8 + Double(headerHits) * 1.5 + Double(titleHits) * 1.1 + coverage * 2.2) * qualityFactor + structuredSourceBonus(extractionSource)

            let result = ChunkSearchResult(
                chunkId: chunkId,
                documentId: documentId,
                containerId: rowContainerId,
                chunkIndex: chunkIndex,
                pageNumber: pageNumber,
                sectionTitle: tableTitle.isEmpty ? nil : tableTitle,
                sectionPath: nil,
                content: rowText,
                bm25Score: score
            )
            scoredResults.append((result, score))
        }

        let results = scoredResults
            .sorted { lhs, rhs in lhs.score > rhs.score }
            .prefix(limit)
            .map(\.result)

        if !results.isEmpty {
            Log.debug("[SQLiteFTS5] Structured row search '\(query)' returned \(results.count) results", category: .retrieval)
        }

        return results
    }

    func searchStructuredRows(
        query: String,
        containerId: UUID? = nil,
        limit: Int = 20
    ) async -> [ChunkSearchResult] {
        ensureInitialized()
        return searchStructuredTableRowsInternal(query: query, containerId: containerId, limit: limit)
    }

    /// Search chunks with BM25 ranking.
    /// The key advantage: FTS5 BM25 is computed PER-CHUNK, not per-document.
    /// section_title and section_path are searchable — when query mentions "engine oil",
    /// chunks whose section contains "engine" get a higher BM25 score automatically.
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - containerId: Container filter
    ///   - limit: Max results
    /// - Returns: Chunk-level BM25 results with section context
    func searchChunks(
        query: String,
        containerId: UUID? = nil,
        limit: Int = 50
    ) async -> [ChunkSearchResult] {
        ensureInitialized()
        guard let db = database else { return [] }

        func executeChunkSearch(escapedQuery: String) -> [ChunkSearchResult] {
            // BM25 weights: section_title(10.0), section_path(5.0), content(1.0)
            // This heavily boosts matches in section headings — "engine oil" matching
            // a sectionTitle="Engine Oil" gets 10x the score of matching in body text.
            let sql: String
            if containerId != nil {
                sql = """
                    SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                           section_title, section_path, content,
                           bm25(chunks, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0) as score
                    FROM chunks
                    WHERE chunks MATCH ? AND container_id = ?
                    ORDER BY bm25(chunks, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)
                    LIMIT ?
                """
            } else {
                sql = """
                    SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                           section_title, section_path, content,
                           bm25(chunks, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0) as score
                    FROM chunks
                    WHERE chunks MATCH ?
                    ORDER BY bm25(chunks, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)
                    LIMIT ?
                """
            }

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                let error = String(cString: sqlite3_errmsg(db))
                Log.error("[SQLiteFTS5] Chunk search prepare failed: \(error)", category: .retrieval)
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

            var results: [ChunkSearchResult] = []

            while sqlite3_step(statement) == SQLITE_ROW {
                guard let chunkIdPtr = sqlite3_column_text(statement, 0),
                      let docIdPtr = sqlite3_column_text(statement, 1),
                      let containerIdPtr = sqlite3_column_text(statement, 2),
                      let docId = UUID(uuidString: String(cString: docIdPtr)),
                      let cId = UUID(uuidString: String(cString: containerIdPtr)) else {
                    continue
                }

                let chunkId = String(cString: chunkIdPtr)
                let chunkIndex = Int(sqlite3_column_int(statement, 3))
                let pageNumber: Int? = sqlite3_column_type(statement, 4) != SQLITE_NULL
                    ? Int(sqlite3_column_int(statement, 4)) : nil
                let sectionTitle = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let sectionPath = sqlite3_column_text(statement, 6).map { String(cString: $0) }
                let content = sqlite3_column_text(statement, 7).map { String(cString: $0) } ?? ""
                let score = sqlite3_column_double(statement, 8)

                results.append(ChunkSearchResult(
                    chunkId: chunkId,
                    documentId: docId,
                    containerId: cId,
                    chunkIndex: chunkIndex,
                    pageNumber: pageNumber,
                    sectionTitle: sectionTitle?.isEmpty == true ? nil : sectionTitle,
                    sectionPath: sectionPath?.isEmpty == true ? nil : sectionPath,
                    content: content,
                    bm25Score: score
                ))
            }

            return results
        }

        let preciseQuery = escapeFTS5Query(query)
        var results = executeChunkSearch(escapedQuery: preciseQuery)
        if !results.isEmpty {
            Log.debug("[SQLiteFTS5] Chunk search '\(query)' returned \(results.count) results", category: .retrieval)
            return results
        }

        let broadQuery = escapeFTS5QueryBroad(query)
        results = executeChunkSearch(escapedQuery: broadQuery)
        if !results.isEmpty {
            Log.debug("[SQLiteFTS5] Chunk search '\(query)' needed OR fallback → \(results.count) results", category: .retrieval)
        } else {
            results = searchStructuredChunks(query: query, containerId: containerId, limit: limit)
            if results.isEmpty {
                Log.debug("[SQLiteFTS5] Chunk search '\(query)' returned 0 results", category: .retrieval)
            }
        }
        return results
    }

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
                ORDER BY bm25(documents)
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents)
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
                ORDER BY bm25(documents)
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content, bm25(documents) as score,
                       snippet(documents, 2, '<b>', '</b>', '...', 32) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents)
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
                ORDER BY bm25(documents)
                LIMIT ?
            """
        } else {
            sql = """
                SELECT document_id, content,
                       snippet(documents, 2, '>>>>', '<<<<', '...', \(contextChars / 6)) as snip
                FROM documents
                WHERE documents MATCH ?
                ORDER BY bm25(documents)
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

    // MARK: - Migration Support

    /// Migrate from FullTextStorageService (file-based) to SQLite FTS5
    /// Call this once on app launch to migrate existing data
    func migrateFromFileStorage(containerId: UUID) async -> Int {
        ensureInitialized()
        let fileService = FullTextStorageService.shared
        let fileManager = FileManager.default

        // Get the file-based storage directory
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else { return 0 }
        let oldDir = appSupport.appendingPathComponent("OpenIntelligence/FullText", isDirectory: true)

        guard fileManager.fileExists(atPath: oldDir.path) else {
            Log.info("[SQLiteFTS5] No file-based storage to migrate", category: .vectorDB)
            return 0
        }

        let contents = (try? fileManager.contentsOfDirectory(at: oldDir, includingPropertiesForKeys: nil)) ?? []
        let txtFiles = contents.filter { $0.pathExtension == "txt" }

        var migrated = 0
        for file in txtFiles {
            guard let docId = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else {
                continue
            }

            // Check if already migrated
            if await exists(documentId: docId) {
                continue
            }

            // Read from file service
            if let text = await fileService.retrieve(for: docId) {
                await store(text: text, for: docId, containerId: containerId)
                migrated += 1
            }
        }

        Log.info("[SQLiteFTS5] Migrated \(migrated) documents from file-based storage", category: .vectorDB)
        return migrated
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
    func getTopTermsForContainer(containerId: UUID, limit: Int = 50) async -> [TermFrequency] {
        ensureInitialized()
        guard let db = database else { return [] }

        // Get all content for this container and analyze term frequencies
        let sql = "SELECT content FROM documents WHERE container_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)

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

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let contentPtr = sqlite3_column_text(statement, 0) else { continue }
            let content = String(cString: contentPtr).lowercased()

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

        let sql = "SELECT content FROM documents WHERE container_id = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, containerId.uuidString, -1, SQLITE_TRANSIENT)

        var bigramCounts: [String: Int] = [:]
        var trigramCounts: [String: Int] = [:]

        let stopwords: Set<String> = [
            "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with",
            "by", "from", "as", "is", "was", "are", "were", "been", "be", "have", "has", "had",
            "that", "this", "it", "its", "they", "them", "there", "can", "will", "would"
        ]

        while sqlite3_step(statement) == SQLITE_ROW {
            guard let contentPtr = sqlite3_column_text(statement, 0) else { continue }
            let content = String(cString: contentPtr).lowercased()

            // Split into words
            let words = content.components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 2 }

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

        // Add trigrams with count >= 3
        for (phrase, count) in trigramCounts where count >= 3 {
            phrases.append((phrase, count))
        }

        // Add bigrams with count >= 5 (higher threshold since less specific)
        for (phrase, count) in bigramCounts where count >= 5 {
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

    // MARK: - Non-Isolated Content Reader

    /// Populate document_content table from FTS5 in the background.
    /// Opens its own connection — does NOT touch the actor. Called once
    /// after the Database tab loads so subsequent document taps are instant.
    nonisolated static func backgroundPopulateContentTable() {
        let dbPath = directDatabaseURL.path

        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return
        }
        defer { sqlite3_close(db) }

        sqlite3_busy_timeout(db, 5000)

        // Quick check: if document_content already has at least as many rows as documents, skip.
        let contentCount = { () -> Int in
            let sql = "SELECT COUNT(*) FROM document_content"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : -1
        }()

        let docCount = { () -> Int in
            let sql = "SELECT COUNT(*) FROM documents"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return -1 }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : -1
        }()

        guard contentCount >= 0 && contentCount < docCount else { return }

        // Backfill any missing rows
        let backfillSQL = """
            INSERT OR IGNORE INTO document_content (document_id, container_id, content)
            SELECT document_id, container_id, content FROM documents
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, backfillSQL, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    /// Read document content WITHOUT going through the actor queue.
    /// Opens a separate read-only SQLite connection, bypassing actor contention.
    ///
    /// When the Database Dashboard opens, `loadAllData()` fires 6 expensive
    /// async let calls to this actor. All execute serially. If the user taps
    /// a document before they finish, `getFullContent()` queues behind ALL of
    /// them, causing the preview sheet to spin indefinitely.
    ///
    /// This static method sidesteps the issue entirely by opening its own
    /// read-only connection. Safe because SQLite WAL mode supports concurrent readers.
    nonisolated static func readContentDirectly(documentId: UUID) -> String? {
        let dbPath = directDatabaseURL.path

        // Open separate read-only connection — does NOT touch the actor's connection
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            if let db = db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        // Query the B-tree indexed document_content table (O(log n) lookup).
        // The FTS5 'documents' table has document_id UNINDEXED, which means
        // WHERE document_id = ? requires a full table scan — 30+ seconds for
        // large document sets. document_content has a PRIMARY KEY index.
        let sql = "SELECT content FROM document_content WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            // Fallback: table may not exist yet (pre-migration). Try FTS5 table.
            return readFromFTS5Fallback(db: db!, documentId: documentId)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW,
           let contentPtr = sqlite3_column_text(statement, 0) {
            return String(cString: contentPtr)
        }

        // Fallback to FTS5 if document_content doesn't have the row yet
        // (documents ingested before this migration)
        return readFromFTS5Fallback(db: db!, documentId: documentId)
    }

    /// Fallback reader for documents ingested before the document_content table existed.
    /// Scans the FTS5 table (slow for large datasets, but works).
    /// When it finds data, also inserts into document_content so subsequent reads are O(log n).
    private nonisolated static func readFromFTS5Fallback(db: OpaquePointer, documentId: UUID) -> String? {
        let sql = "SELECT content, container_id FROM documents WHERE document_id = ? LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)

        if sqlite3_step(statement) == SQLITE_ROW,
           let contentPtr = sqlite3_column_text(statement, 0) {
            let content = String(cString: contentPtr)
            let containerId = sqlite3_column_text(statement, 1).map { String(cString: $0) }

            // Migrate this single row to document_content for fast future reads.
            // Uses a READWRITE connection briefly — safe under WAL mode.
            migrateRowToContentTable(dbPath: db, documentId: documentId, containerId: containerId, content: content)

            return content
        }

        return nil
    }

    /// Migrate a single row from FTS5 → document_content on demand.
    /// Opens a brief read-write connection to INSERT the row so subsequent
    /// reads hit the B-tree indexed table instead of scanning FTS5.
    private nonisolated static func migrateRowToContentTable(dbPath: OpaquePointer, documentId: UUID, containerId: String?, content: String) {
        // We need a writable connection — the passed db is read-only.
        // Get the path from the read-only handle.
        guard let pathPtr = sqlite3_db_filename(dbPath, "main") else { return }
        let path = String(cString: pathPtr)

        var rwDb: OpaquePointer?
        guard sqlite3_open_v2(path, &rwDb, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            if let rwDb = rwDb { sqlite3_close(rwDb) }
            return
        }
        defer { sqlite3_close(rwDb) }

        // Set busy timeout so we don't fail immediately if the actor holds a write lock
        sqlite3_busy_timeout(rwDb, 3000)

        let insertSQL = "INSERT OR IGNORE INTO document_content (document_id, container_id, content) VALUES (?, ?, ?)"
        var insertStmt: OpaquePointer?
        guard sqlite3_prepare_v2(rwDb, insertSQL, -1, &insertStmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(insertStmt) }

        sqlite3_bind_text(insertStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
        if let containerId = containerId {
            sqlite3_bind_text(insertStmt, 2, containerId, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(insertStmt, 2)
        }
        sqlite3_bind_text(insertStmt, 3, content, -1, SQLITE_TRANSIENT)

        sqlite3_step(insertStmt)
    }

    /// Get string value from PRAGMA
    private func getStringValue(sql: String) -> String? {
        guard let db = database else { return nil }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }

        if sqlite3_step(statement) == SQLITE_ROW {
            if let ptr = sqlite3_column_text(statement, 0) {
                return String(cString: ptr)
            }
        }
        return nil
    }

    // MARK: - Private Helpers

    /// Execute SQL statement without results
    @discardableResult
    private func execute(sql: String) -> Bool {
        guard let db = database else { return false }

        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            if let error = errorMessage {
                Log.error("[SQLiteFTS5] SQL error: \(String(cString: error))", category: .vectorDB)
                sqlite3_free(error)
            }
            return false
        }

        return true
    }

    private func ensureColumnExists(table: String, column: String, definition: String) {
        guard let db = database else { return }

        let pragmaSQL = "PRAGMA table_info(\(table))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1), String(cString: namePtr) == column {
                return
            }
        }

        _ = execute(sql: "ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func structuredTextQualityScore(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let scalarCount = trimmed.unicodeScalars.count
        guard scalarCount > 0 else { return 0 }

        let printableCount = trimmed.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
            || CharacterSet.whitespacesAndNewlines.contains($0)
            || CharacterSet.punctuationCharacters.contains($0)
            || CharacterSet.symbols.contains($0)
        }.count
        let printableRatio = Double(printableCount) / Double(scalarCount)

        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        let digits = trimmed.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
        let alphaNumericRatio = Double(letters + digits) / Double(scalarCount)

        var score = printableRatio * 0.48 + alphaNumericRatio * 0.26

        if letters >= 8 {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(trimmed)
            let confidence = recognizer.languageHypotheses(withMaximum: 1).values.max() ?? 0
            score += min(0.18, confidence * 0.18)
            if confidence < 0.15 {
                score -= 0.20
            }
        } else if digits > 0 {
            score += 0.08
        }

        return min(1.0, max(0.0, score))
    }

    private func structuredRowQualityScore(headers: [String], row: [String]) -> Double {
        let visibleCells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !visibleCells.isEmpty else { return 0 }

        let readability = visibleCells.map(structuredTextQualityScore).reduce(0, +) / Double(visibleCells.count)
        let fillRatio = Double(visibleCells.count) / Double(max(1, max(headers.count, row.count)))
        let informativeBonus = visibleCells.contains { $0.count >= 16 } ? 0.08 : 0

        return min(1.0, max(0.0, readability * 0.72 + fillRatio * 0.20 + informativeBonus))
    }

    private func structuredSourceBonus(_ source: String) -> Double {
        switch source {
        case "crop_rescue":
            return 0.16
        case "state_list_recovery":
            return 0.14
        case "vision_document":
            return 0.10
        case "layout_table":
            return 0.06
        case "text_inferred":
            return -0.08
        default:
            return 0
        }
    }

    /// Escape and construct FTS5 query from natural language input.
    /// OPTIMIZED: Uses AND-first (implicit) for precision, OR fallback for recall.
    /// Previous OR-only behavior matched ANY term, so "system error capacity" hit
    /// every chunk containing "system" OR "error" OR "capacity" — ~90% of a large doc.
    /// AND-first ensures all content terms must co-occur, dramatically improving
    /// needle-in-haystack precision for BM25 scoring.
    private func escapeFTS5Query(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // FTS5 stopwords to skip (common words that add noise)
        let ftsStop: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "do", "does", "did", "will", "would", "could", "should", "can",
            "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "this", "that", "what", "which", "who", "how", "it", "its",
            "i", "me", "my", "we", "you", "your", "he", "she", "they",
            // Generic query-framing words (not domain-specific content words)
            "kind", "type", "take", "use", "need", "much",
            "mean", "means", "meaning", "indicate", "indicates", "signal", "signals",
            "show", "shows", "tell", "tells"
        ]

        // Split into content words, escape each
        let words = trimmed.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters).replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { $0.count >= 2 && !ftsStop.contains($0) }

        guard !words.isEmpty else {
            // Fallback: return original as quoted phrase
            return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        // AND-first strategy: FTS5 implicit AND (space-separated) requires ALL terms
        // to appear in the document. This is far more precise for needle-in-haystack.
        // For single-term queries, AND and OR are equivalent.
        // For multi-term queries, AND dramatically reduces false positives.
        //
        // Note: FTS5 porter stemmer handles morphological variants automatically
        // ("running" → "run", "oils" → "oil"), so AND won't miss inflected forms.
        return words.map { "\"\($0)\"" }.joined(separator: " ")
    }

    /// Build an OR-based FTS5 query for broad recall (fallback when AND returns nothing)
    private func escapeFTS5QueryBroad(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let ftsStop: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been",
            "do", "does", "did", "will", "would", "could", "should", "can",
            "to", "of", "in", "for", "on", "with", "at", "by", "from",
            "this", "that", "what", "which", "who", "how", "it", "its",
            "i", "me", "my", "we", "you", "your", "he", "she", "they",
            "kind", "type", "take", "use", "need", "much",
            "mean", "means", "meaning", "indicate", "indicates", "signal", "signals",
            "show", "shows", "tell", "tells"
        ]

        let words = trimmed.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .punctuationCharacters).replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { $0.count >= 2 && !ftsStop.contains($0) }

        guard !words.isEmpty else {
            return "\"\(trimmed.replacingOccurrences(of: "\"", with: "\"\""))\""
        }

        // OR-based: any term matches (broad recall fallback)
        return words.map { "\"\($0)\"" }.joined(separator: " OR ")
    }

    /// Count words using simple whitespace split (for metadata)
    private func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
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

// MARK: - SQLite Transient Constant

/// SQLite constant for transient memory management
/// nonisolated(unsafe) allows access from within actors in Swift 6
nonisolated(unsafe) private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
