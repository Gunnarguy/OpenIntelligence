//
//  SQLiteFullTextService+ContentReader.swift
//  OpenIntelligence
//
//  Part of SQLiteFullTextService, moved from SQLiteFullTextService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate


extension SQLiteFullTextService {
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
    func getStringValue(sql: String) -> String? {
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

}
