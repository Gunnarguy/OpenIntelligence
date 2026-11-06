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

    var database: OpaquePointer?
    private var isInitialized = false
    private let fileManager = FileManager.default
    let jsonEncoder = JSONEncoder()

    nonisolated static var directDatabaseURL: URL {
        OpenIntelligenceRuntimePaths.localCacheDirectory()
            .appendingPathComponent("FTS5", isDirectory: true)
            .appendingPathComponent("fulltext.sqlite")
    }

    /// Database file location
    var databasePath: URL {
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

    func checkpoint() {
        guard let db = database else { return }
        let checkpointSQL = "PRAGMA wal_checkpoint(PASSIVE)"
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(db, checkpointSQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_step(statement)
            sqlite3_finalize(statement)
        }
    }

    func beginTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) != 0 {
            execute(sql: "BEGIN TRANSACTION")
        }
    }

    func commitTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) == 0 {
            execute(sql: "COMMIT")
        }
    }

    func rollbackTransaction() {
        guard let db = database else { return }
        if sqlite3_get_autocommit(db) == 0 {
            execute(sql: "ROLLBACK")
        }
    }

    /// Ensure database is initialized before any operation
    /// Called automatically by all public methods
    func ensureInitialized() {
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

        for migration in ColumnMigration.allCases {
            ensureColumnExists(migration)
        }

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

    // MARK: - Private Helpers

    /// Execute SQL statement without results
    @discardableResult
    func execute(sql: String) -> Bool {
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

    /// Closed catalog of additive column migrations. Every table name, column
    /// name, and column definition is a compiler-owned constant on an enum case:
    /// no call site can pass runtime strings into schema DDL, which is what made
    /// the previous `(table:column:definition:)` signature an injection surface
    /// (audited PRs #27/#55, consolidated per DEC-19). Add new columns by adding
    /// a case — never by widening this back to string parameters.
    private enum ColumnMigration: CaseIterable {
        case chunkStructuredExtractionQuality
        case chunkStructuredExtractionSource
        case chunkTableRowsRowQuality
        case chunkTableRowsIsLowQuality
        case chunkTableRowsExtractionQuality
        case chunkTableRowsExtractionSource

        var table: String {
            switch self {
            case .chunkStructuredExtractionQuality, .chunkStructuredExtractionSource:
                return "chunk_structured"
            case .chunkTableRowsRowQuality, .chunkTableRowsIsLowQuality,
                 .chunkTableRowsExtractionQuality, .chunkTableRowsExtractionSource:
                return "chunk_table_rows"
            }
        }

        var column: String {
            switch self {
            case .chunkStructuredExtractionQuality, .chunkTableRowsExtractionQuality:
                return "extraction_quality"
            case .chunkStructuredExtractionSource, .chunkTableRowsExtractionSource:
                return "extraction_source"
            case .chunkTableRowsRowQuality:
                return "row_quality"
            case .chunkTableRowsIsLowQuality:
                return "is_low_quality"
            }
        }

        var definition: String {
            switch self {
            case .chunkStructuredExtractionQuality, .chunkTableRowsRowQuality,
                 .chunkTableRowsExtractionQuality:
                return "REAL NOT NULL DEFAULT 0"
            case .chunkTableRowsIsLowQuality:
                return "INTEGER NOT NULL DEFAULT 0"
            case .chunkStructuredExtractionSource, .chunkTableRowsExtractionSource:
                return "TEXT NOT NULL DEFAULT ''"
            }
        }
    }

    private func ensureColumnExists(_ migration: ColumnMigration) {
        guard let db = database else { return }

        // Defense in depth on top of the closed enum: identifier-shape
        // validation (#27) and identifier/literal quoting (#55). The enum makes
        // these unreachable-in-practice, but they keep any future case typo
        // from producing malformed DDL.
        let identifier = "^[A-Za-z_][A-Za-z0-9_]*$"
        guard migration.table.range(of: identifier, options: .regularExpression) != nil,
              migration.column.range(of: identifier, options: .regularExpression) != nil else {
            Log.error("[SQLiteFTS5] Rejected malformed migration identifier for \(migration.table).\(migration.column)", category: .vectorDB)
            return
        }

        // PRAGMA takes a single-quoted literal; DDL identifiers are double-quoted.
        let pragmaTable = "'" + migration.table.replacingOccurrences(of: "'", with: "''") + "'"
        let pragmaSQL = "PRAGMA table_info(\(pragmaTable))"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, pragmaSQL, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            if let namePtr = sqlite3_column_text(statement, 1), String(cString: namePtr) == migration.column {
                return
            }
        }

        let quotedTable = "\"" + migration.table.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        let quotedColumn = "\"" + migration.column.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        _ = execute(sql: "ALTER TABLE \(quotedTable) ADD COLUMN \(quotedColumn) \(migration.definition)")
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

    func structuredRowQualityScore(headers: [String], row: [String]) -> Double {
        let visibleCells = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !visibleCells.isEmpty else { return 0 }

        let readability = visibleCells.map(structuredTextQualityScore).reduce(0, +) / Double(visibleCells.count)
        let fillRatio = Double(visibleCells.count) / Double(max(1, max(headers.count, row.count)))
        let informativeBonus = visibleCells.contains { $0.count >= 16 } ? 0.08 : 0

        return min(1.0, max(0.0, readability * 0.72 + fillRatio * 0.20 + informativeBonus))
    }

    func structuredSourceBonus(_ source: String) -> Double {
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
    func escapeFTS5Query(_ query: String) -> String {
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
    func escapeFTS5QueryBroad(_ query: String) -> String {
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
    func countWords(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

}

// MARK: - SQLite Transient Constant

/// SQLite constant for transient memory management
/// nonisolated(unsafe) allows access from within actors in Swift 6
nonisolated(unsafe) let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
