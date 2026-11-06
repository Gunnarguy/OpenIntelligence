//
//  DocumentProcessor+Checkpointing.swift
//  OpenIntelligence
//
//  Moved from DocumentProcessor.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Foundation
import os
import CryptoKit
import NaturalLanguage
import PDFKit
import UniformTypeIdentifiers
import Vision
import CoreImage
import Metal
import Tokenizers
import Compression
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - DocumentProcessor Ingestion Checkpointing & Codable Models Extension

extension DocumentProcessor {
    // MARK: - Checkpoint System Helpers

    private var checkpointsDirectoryURL: URL {
        let url = AppSupportPaths.localCacheDir().appendingPathComponent("IngestionCheckpoints", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func checkpointDirectoryURL(for fingerprint: String) -> URL {
        let url = checkpointsDirectoryURL.appendingPathComponent(fingerprint, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The key an import's checkpoints are kept under: the file's name, its size and the bytes at its start and its end
    /// (5.7). Through 5.6 it was the file's path and modification date, which change when the queued copy is staged
    /// again, so on the owner's iPhone (2026-10-21) an app update in the middle of a 913-page PDF changed the key and
    /// the 248 pages already read were read again from page 1. The bytes are read through `FileHandle`, at most 2 MB.
    /// A file that cannot be read falls back to the old key, so it still gets a directory of its own.
    func computeDocumentFingerprint(at url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int64) ?? 0
        var hasher = SHA256()
        hasher.update(data: Data("\(url.lastPathComponent)_\(size)".utf8))
        if let sample = Self.fingerprintSample(of: url, size: size) {
            hasher.update(data: sample)
        } else {
            let date = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            hasher.update(data: Data("\(url.path)_\(date)".utf8))
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }

    /// The first and last megabyte of a file (the whole file when it is under 2 MB), or nil when it cannot be read.
    nonisolated static func fingerprintSample(of url: URL, size: Int64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let window: Int64 = 1_048_576
        guard var sample = try? handle.read(upToCount: Int(min(size, window))) else { return nil }
        if size > window * 2 {
            guard (try? handle.seek(toOffset: UInt64(size - window))) != nil,
                let tail = try? handle.read(upToCount: Int(window))
            else { return nil }
            sample.append(tail)
        } else if size > window, let rest = try? handle.readToEnd() {
            sample.append(rest)
        }
        return sample
    }

    /// Clean up any checkpoint files for the given document URL
    func cleanCheckpoints(for url: URL) {
        let fingerprint = computeDocumentFingerprint(at: url)
        let checkpointDir = checkpointDirectoryURL(for: fingerprint)
        try? FileManager.default.removeItem(at: checkpointDir)
        Log.info("[Checkpoint] Cleaned up temporary page checkpoints for \(url.lastPathComponent) (fingerprint: \(fingerprint))", category: .ingestion)
    }

    // MARK: - Restored Progress Reporting

    /// What a previously interrupted streaming ingestion already committed for a document.
    ///
    /// This exists because the queue restore path resets `progress` to `nil` when it marks an item
    /// `.paused` after an app restart, so a document that had already indexed 150 of 210 pages came
    /// back displaying nothing at all. The work was never lost — `importLargePDFStreamed` skips any
    /// batch whose `endPage <= lastCompletedPage` — but the UI gave a user every reason to believe
    /// it was, and cancelling is the one action that actually does destroy it, because discarding a
    /// queue item deletes the checkpoint directory while a restart does not.
    struct RestoredIngestionProgress: Sendable, Equatable {
        /// Pages already committed. `lastCompletedPage` is a zero-based index, so this is that + 1.
        let pagesCompleted: Int
        /// `nil` when the document could not be opened to count its pages.
        let totalPages: Int?
        let chunksIndexed: Int
        /// True for a text or JSON Lines file imported in pieces: the two counts are then pieces
        /// of the file, and the total is exact.
        var countsPieces = false

        /// `nil` rather than a guess when the page total is unknown; the caller should leave the
        /// progress bar indeterminate instead of inventing a fraction.
        var fraction: Double? {
            guard let totalPages, totalPages > 0 else { return nil }
            return min(1.0, Double(pagesCompleted) / Double(totalPages))
        }

        var detail: String {
            if countsPieces, let totalPages, totalPages > 0 {
                return "Paused after app restart. \(pagesCompleted) of \(totalPages) parts are already indexed, and it resumes from there"
            }
            if let totalPages, totalPages > 0 {
                return "Paused after app restart — \(pagesCompleted) of \(totalPages) pages already indexed, resuming from there"
            }
            return "Paused after app restart — \(pagesCompleted) page\(pagesCompleted == 1 ? "" : "s") already indexed, resuming from there"
        }
    }

    /// Read-only resolution of a document's checkpoint directory.
    ///
    /// Deliberately does **not** create anything, unlike `checkpointDirectoryURL(for:)` above. This
    /// is called once per persisted item during queue restoration, and probing must not leave an
    /// empty directory behind for every document that never had a checkpoint. It shares the
    /// location with `checkpointsDirectoryURL`; the two must not drift.
    private func existingCheckpointDirectoryURL(for fingerprint: String) -> URL? {
        let dir = AppSupportPaths.localCacheDir()
            .appendingPathComponent("IngestionCheckpoints", isDirectory: true)
            .appendingPathComponent(fingerprint, isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// Returns what an interrupted ingestion already completed for this document, or `nil` when
    /// there is no checkpoint to resume from.
    ///
    /// `nil` legitimately means "no preserved progress" in three different situations, and the
    /// caller should treat all three the same: the document never had a checkpoint (it did not meet
    /// the `fileSizeMB > 10 && .pdf` gate in `importLargePDFStreamed`), the checkpoint was cleaned
    /// up on completion or discard, or the file changed on disk so its fingerprint no longer
    /// matches. A corrupt state file is the one case that is **not** silent: it warns, because a
    /// checkpoint that exists and cannot be read means a resume is about to redo work it did not
    /// have to, and that should never pass unnoticed.
    ///
    /// **This deliberately performs no document parsing.** Its caller is
    /// `RAGService.restorePersistedIngestionQueueIfNeeded()`, which is `@MainActor` and runs during
    /// launch, so opening the PDF here to count its pages would put a parse of a potentially very
    /// large file on the main actor at the worst possible moment. The page total is passed in
    /// instead: the persisted `IngestionItem` already carries `metrics.pageCount` from the run that
    /// was interrupted. When it is unknown, `totalPages` stays `nil`, `fraction` stays `nil`, and
    /// the caller shows an indeterminate bar with an honest detail line rather than a made-up
    /// percentage. The only I/O this does is one `stat` and one small JSON read.
    ///
    /// - Parameter knownPageCount: the document's page count if it is already known. Values at or
    ///   below zero are treated as unknown, since `PipelineMetrics.pageCount` defaults to `0`.
    func restoredIngestionProgress(for url: URL, knownPageCount: Int? = nil) -> RestoredIngestionProgress? {
        let fingerprint = computeDocumentFingerprint(at: url)
        guard let checkpointDir = existingCheckpointDirectoryURL(for: fingerprint) else { return nil }

        // A text or JSON Lines file imported in pieces keeps its own state file.
        let textStateURL = checkpointDir.appendingPathComponent(TextStreamingIngestionState.fileName)
        if let textData = try? Data(contentsOf: textStateURL) {
            guard let textState = try? JSONDecoder().decode(TextStreamingIngestionState.self, from: textData) else {
                Log.warning(
                    "[Checkpoint] Found an unreadable \(TextStreamingIngestionState.fileName) for \(url.lastPathComponent); the resume will restart this document",
                    category: .ingestion)
                return nil
            }
            guard textState.committed.completedPieces > 0 else { return nil }
            return RestoredIngestionProgress(
                pagesCompleted: textState.committed.completedPieces,
                totalPages: textState.totalPieces,
                chunksIndexed: textState.committed.totalChunks,
                countsPieces: true
            )
        }

        let stateURL = checkpointDir.appendingPathComponent("ingestion_state.json")
        guard let data = try? Data(contentsOf: stateURL) else { return nil }

        guard let state = try? JSONDecoder().decode(StreamingIngestionState.self, from: data) else {
            Log.warning(
                "[Checkpoint] Found an unreadable ingestion_state.json for \(url.lastPathComponent) (fingerprint: \(fingerprint)); the resume will restart this document from page 1",
                category: .ingestion
            )
            return nil
        }

        // -1 is the initial value written when a streaming session starts, meaning no batch has
        // been committed yet. There is nothing to report and nothing to skip.
        guard state.lastCompletedPage >= 0 else { return nil }

        return RestoredIngestionProgress(
            pagesCompleted: state.lastCompletedPage + 1,
            totalPages: knownPageCount.flatMap { $0 > 0 ? $0 : nil },
            chunksIndexed: state.totalChunks
        )
    }

    // MARK: - Codable Checkpoint Mappings

    struct CodableDetectedEntity: Codable, Sendable {
        let type: String
        let value: String
        let rawText: String

        init(from entity: DetectedEntity) {
            self.type = entity.type.rawValue
            self.value = entity.value
            self.rawText = entity.rawText
        }

        func toDetectedEntity() -> DetectedEntity {
            let typeEnum = DetectedEntity.EntityType(rawValue: type) ?? .unknown
            return DetectedEntity(type: typeEnum, value: value, rawText: rawText)
        }
    }

    struct CodableTableData: Codable, Sendable {
        let pageNumber: Int
        let rows: [[String]]
        let headerRow: [String]?
        let caption: String?
        let detectedEntities: [CodableDetectedEntity]
        let cellAlignments: [[String]]

        init(_ data: TableData) {
            self.pageNumber = data.pageNumber
            self.rows = data.rows
            self.headerRow = data.headerRow
            self.caption = data.caption
            self.detectedEntities = data.detectedEntities.map { CodableDetectedEntity(from: $0) }
            self.cellAlignments = data.cellAlignments.map { $0.map { $0.rawValue } }
        }

        func toTableData() -> TableData {
            let entities = self.detectedEntities.map { $0.toDetectedEntity() }
            let alignments = self.cellAlignments.map { $0.map { TableCellAlignment(rawValue: $0) ?? .left } }
            return TableData(
                pageNumber: self.pageNumber,
                rows: self.rows,
                headerRow: self.headerRow,
                caption: self.caption,
                detectedEntities: entities,
                cellAlignments: alignments
            )
        }
    }

    struct CodableTupleEntity: Codable, Sendable {
        let type: String
        let value: String
    }

    struct CodableStructuredElement: Codable, Sendable {
        let text: String
        let elementType: String
        let pageNumber: Int
        let isAtomicChunk: Bool
        let detectedEntities: [CodableTupleEntity]
        let tableData: CodableTableData?
        let listItems: [String]?
        let extractionSource: String?
        let qualityScore: Double?

        init(_ wrapper: DocumentProcessor.StructuredElementWrapper) {
            self.text = wrapper.text
            self.elementType = wrapper.elementType
            self.pageNumber = wrapper.pageNumber
            self.isAtomicChunk = wrapper.isAtomicChunk
            self.detectedEntities = wrapper.detectedEntities.map { CodableTupleEntity(type: $0.type, value: $0.value) }
            self.tableData = wrapper.tableData.map { CodableTableData($0) }
            self.listItems = wrapper.listItems
            self.extractionSource = wrapper.extractionSource
            self.qualityScore = wrapper.qualityScore
        }

        func toWrapper() -> DocumentProcessor.StructuredElementWrapper {
            let entities = self.detectedEntities.map { (type: $0.type, value: $0.value) }
            return DocumentProcessor.StructuredElementWrapper(
                text: self.text,
                elementType: self.elementType,
                pageNumber: self.pageNumber,
                isAtomicChunk: self.isAtomicChunk,
                detectedEntities: entities,
                tableData: self.tableData?.toTableData(),
                listItems: self.listItems,
                extractionSource: self.extractionSource,
                qualityScore: self.qualityScore
            )
        }
    }

    struct IngestionCheckpointPage: Codable, Sendable {
        let pageIndex: Int
        let elements: [CodableStructuredElement]
        let pageText: String
        let hasStructure: Bool
        let usedOCR: Bool
        let tablesFound: Int
        let listsFound: Int
        let headersFound: Int
    }
}
