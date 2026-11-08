//
//  SQLiteFullTextService+Documents.swift
//  OpenIntelligence
//
//  Part of SQLiteFullTextService, moved from SQLiteFullTextService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate


extension SQLiteFullTextService {
    // MARK: - Core CRUD Operations

    /// Store document text in FTS5 index
    /// - Parameters:
    ///   - text: Complete document text
    ///   - documentId: Document UUID
    ///   - containerId: Container UUID for isolation
    func store(text: String, for documentId: UUID, containerId: UUID, append: Bool = false) async {
        ensureInitialized()
        guard let db = database else {
            Log.error("[SQLiteFTS5] Database not initialized", category: .vectorDB)
            return
        }

        var finalC = text
        if append {
            if let existingText = await retrieve(for: documentId) {
                if !existingText.isEmpty {
                    finalC = existingText + "\n\n" + text
                }
            }
        }
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
        sqlite3_bind_text(statement, 3, finalC, -1, SQLITE_TRANSIENT)

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
            sqlite3_bind_text(contentStmt, 3, finalC, -1, SQLITE_TRANSIENT)
            sqlite3_step(contentStmt)
            sqlite3_finalize(contentStmt)
        }

        // Store metadata
        let wordCount = countWords(in: finalC)
        let metaSQL = "INSERT OR REPLACE INTO document_meta (document_id, container_id, character_count, word_count, created_at) VALUES (?, ?, ?, ?, ?)"
        var metaStmt: OpaquePointer?

        if sqlite3_prepare_v2(db, metaSQL, -1, &metaStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(metaStmt, 1, docIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(metaStmt, 2, containerIdStr, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(metaStmt, 3, Int64(finalC.count))
            sqlite3_bind_int64(metaStmt, 4, Int64(wordCount))
            sqlite3_bind_double(metaStmt, 5, Date().timeIntervalSince1970)
            sqlite3_step(metaStmt)
            sqlite3_finalize(metaStmt)
        }

        checkpoint()
        Log.debug("[SQLiteFTS5] Stored document \(documentId) (\(finalC.count) chars, \(wordCount) words)", category: .vectorDB)
    }

    /// Store per-page text in FTS5 index for page-level search and context isolation
    /// - Parameters:
    ///   - pages: Array of (pageNumber, content) tuples — one per PDF page
    ///   - documentId: Document UUID
    ///   - containerId: Container UUID for isolation
    func storePages(pages: [(pageNumber: Int, content: String)], for documentId: UUID, containerId: UUID, append: Bool = false) async {
        ensureInitialized()
        guard let db = database else {
            Log.error("[SQLiteFTS5] Database not initialized for page storage", category: .vectorDB)
            return
        }

        guard !pages.isEmpty else { return }

        if !append {
            // Delete existing pages for this document
            let deleteSQL = "DELETE FROM document_pages WHERE document_id = ?"
            var delStmt: OpaquePointer?
            if sqlite3_prepare_v2(db, deleteSQL, -1, &delStmt, nil) == SQLITE_OK {
                sqlite3_bind_text(delStmt, 1, documentId.uuidString, -1, SQLITE_TRANSIENT)
                sqlite3_step(delStmt)
                sqlite3_finalize(delStmt)
            }
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
            ORDER BY bm25(document_pages), page_id
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

}
