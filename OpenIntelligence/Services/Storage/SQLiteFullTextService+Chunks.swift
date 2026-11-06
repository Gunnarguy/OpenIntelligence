//
//  SQLiteFullTextService+Chunks.swift
//  OpenIntelligence
//
//  Part of SQLiteFullTextService, moved from SQLiteFullTextService.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import NaturalLanguage
import SQLite3
import Accelerate


extension SQLiteFullTextService {
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

    func storeChunks(
        documentId: UUID,
        containerId: UUID,
        chunks: [(chunkIndex: Int, pageNumber: Int?, sectionTitle: String?,
                  sectionPath: String?, structureType: String?, chunkType: String?,
                  tableTitle: String?, content: String,
                  structuredMetadata: StructuredChunkMetadata?)],
        append: Bool = false
    ) async {
        ensureInitialized()
        guard let db = database else { return }

        if !append {
            // Delete any existing chunks for this document first
            await deleteChunks(for: documentId)
        }

        let insertSQL = """
            INSERT INTO chunks (chunk_id, document_id, container_id, chunk_index, page_number,
                               section_title, section_path, structure_type, content)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        // Wrap in transaction for speed (100x faster than individual inserts)
        beginTransaction()

        for chunk in chunks {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else { continue }

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
            sqlite3_finalize(statement)

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

        for (rowIndex, row) in structuredMetadata.rows.enumerated() {
            let rowQuality = structuredRowQualityScore(headers: structuredMetadata.headers, row: row)
            let isLowQuality = structuredMetadata.lowQualityRowIndices.contains(rowIndex) || rowQuality < 0.38

            var rowStatement: OpaquePointer?
            guard sqlite3_prepare_v2(db, insertRowSQL, -1, &rowStatement, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(rowStatement) }

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
            // This heavily boosts matches in section headings: "engine oil" matching
            // a sectionTitle="Engine Oil" gets 10x the score of matching in body text.
            //
            // The weight vector must carry exactly one entry per column of `chunks`, in
            // declaration order, or every weight silently lands on the wrong column:
            //   chunk_id, document_id, container_id, chunk_index, page_number,
            //   section_title, section_path, structure_type, content
            // That is 9 columns, so 9 weights. This previously passed 8, which shifted
            // the whole vector one slot left: section_path took the 0 meant for
            // structure_type and dropped out of ranking entirely, while section_title
            // took the 5.0 meant for section_path. Keep this list in sync with the
            // CREATE VIRTUAL TABLE above.
            let sql: String
            if containerId != nil {
                sql = """
                    SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                           section_title, section_path, content,
                           bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0) as score
                    FROM chunks
                    WHERE chunks MATCH ? AND container_id = ?
                    ORDER BY bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)
                    LIMIT ?
                """
            } else {
                sql = """
                    SELECT chunk_id, document_id, container_id, chunk_index, page_number,
                           section_title, section_path, content,
                           bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0) as score
                    FROM chunks
                    WHERE chunks MATCH ?
                    ORDER BY bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)
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

}
