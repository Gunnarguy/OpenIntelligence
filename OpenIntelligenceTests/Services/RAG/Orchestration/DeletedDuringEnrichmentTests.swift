//
//  DeletedDuringEnrichmentTests.swift
//  OpenIntelligenceTests
//
//  An import saves its document and then writes its overview, tags and suggested questions, which takes seconds.
//  Since that work moved after the save (2026-10-15, during 5.7; no release had it), a document deleted in those
//  seconds kept its overview as a passage of no document, and a later answer cited it as "Unknown Document Summary":
//  seen in the iOS 27 Simulator on 2026-10-19, when an action's engine loaded the library and answered from the
//  overview of a note a test had deleted right after importing it. Runs a real import on the app's engine, in the
//  app the suite runs in, and acts while the import reports writing the overview.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class DeletedDuringEnrichmentTests: XCTestCase {
    /// Starts an import of a short note and returns once its document is saved and the import reports writing its
    /// overview, with the task the import runs in.
    private func importUntilTheOverviewIsWritten(
        _ engine: RAGService, library: UUID, name: String
    ) async throws -> (document: Document, importing: Task<IngestionBatchResult, Never>, file: URL) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data(
            ("The quillberry boiler in the test flat is serviced every October by the building's own engineer, "
                + "and the service record is kept in the drawer under the kitchen sink.").utf8
        ).write(to: url)
        let importing = Task { @MainActor in await engine.ingestDocuments([url], containerId: library) }
        for _ in 0..<1200 {
            let writingOverview = engine.ingestionItems.contains {
                $0.filename.hasPrefix(name) && $0.detail == "Optimizing overview..."
            }
            if writingOverview, let document = engine.documents.first(where: { $0.filename.hasPrefix(name) }) {
                return (document, importing, url)
            }
            try await Task.sleep(for: .milliseconds(25))
        }
        _ = await importing.value
        throw XCTSkip("the import never reported writing an overview (summaries off, or no model), so there is no race")
    }

    func testADocumentDeletedWhileItsOverviewIsWrittenLeavesNoPassage() async throws {
        let engine = IntentSupport.engine()
        let library = try XCTUnwrap(engine.containerService.activeContainerId)
        let (document, importing, url) = try await importUntilTheOverviewIsWritten(
            engine, library: library, name: "enrichment-race-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: url) }

        try await engine.removeDocument(document)
        _ = await importing.value

        let db = try await engine.dbForContainer(library)
        let left = try await db.chunks(forDocument: document.id)
        XCTAssertTrue(left.isEmpty, "passages of the deleted note are still stored: \(left.map(\.content))")
        XCTAssertFalse(engine.documents.contains { $0.id == document.id })
    }

    /// Deleted and undone in the same seconds: the note comes back with its overview, which was stored while the
    /// deletion waited (review, 2026-10-19: the first version of the guard left it without one for good).
    func testADocumentDeletedAndUndoneWhileItsOverviewIsWrittenKeepsItsOverview() async throws {
        let engine = IntentSupport.engine()
        let library = try XCTUnwrap(engine.containerService.activeContainerId)
        let (document, importing, url) = try await importUntilTheOverviewIsWritten(
            engine, library: library, name: "enrichment-undo-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: url) }
        addTeardownBlock { @MainActor in try? await engine.removeDocument(document) }

        let removal = try XCTUnwrap(engine.scheduleRemoval(of: [document], window: .seconds(60)))
        XCTAssertTrue(engine.undoRemoval(removal))
        _ = await importing.value

        let db = try await engine.dbForContainer(library)
        let stored = try await db.chunks(forDocument: document.id)
        XCTAssertTrue(engine.documents.contains { $0.id == document.id }, "the note is back")
        XCTAssertTrue(
            stored.contains { $0.metadata.abstractionLevel == .documentSummary },
            "the note came back without its overview: \(stored.map(\.metadata.abstractionLevel))")
    }
}
