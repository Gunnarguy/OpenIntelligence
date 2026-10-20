//
//  SecondEngineSaveTests.swift
//  OpenIntelligenceTests
//
//  Two engines can be alive at once on one set of libraries: the app's and one an action makes, or one per window
//  on the Mac. Through 5.6 an engine that had read the document list before a delete wrote the deleted document
//  back at its next save, as a record with no passages. Since 5.7 a save leaves out every document recorded as
//  deleted. Runs in the app the suite runs in, with documents that are only in these engines' lists.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SecondEngineSaveTests: XCTestCase {
    /// The engine applies the list it read from disk in a task of its own; this waits for a document to arrive.
    private func waitUntil(_ engine: RAGService, holds id: UUID) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !engine.documents.contains(where: { $0.id == id }), Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func tombstoned(_ id: UUID) -> Bool {
        let url = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        guard let data = try? Data(contentsOf: url), let ids = try? JSONDecoder().decode([String].self, from: data)
        else { return false }
        return ids.contains(id.uuidString)
    }

    func testADocumentDeletedInOneEngineStaysGoneWhenAnotherEngineImportsAndSaves() async throws {
        let first = RAGService()
        try await Task.sleep(for: .milliseconds(300))
        let library = try XCTUnwrap(first.containerService.activeContainerId)
        func document(_ name: String) -> Document {
            Document(
                filename: "\(name)-\(UUID().uuidString.prefix(6)).txt", fileURL: URL(fileURLWithPath: "/tmp/\(name).txt"),
                contentType: .text, totalChunks: 2, containerId: library)
        }
        let deleted = document("deleted-in-one-window")
        first.documents.append(deleted)
        await first.saveDocumentsToDisk()

        // The second engine reads the list while the document is still in it, as a second window or an
        // action's engine would.
        let second = RAGService()
        try await waitUntil(second, holds: deleted.id)
        XCTAssertTrue(second.documents.contains { $0.id == deleted.id }, "the second engine read the list with it")

        try await first.removeDocument(deleted)
        XCTAssertTrue(tombstoned(deleted.id), "recorded as deleted")
        XCTAssertTrue(second.documents.contains { $0.id == deleted.id }, "the second engine still holds it")

        // The second engine imports a file: its list gains a document and is saved whole.
        let imported = document("imported-in-the-other-window")
        second.documents.append(imported)
        await second.saveDocumentsToDisk()
        addTeardownBlock { @MainActor in try? await second.removeDocument(imported) }

        let onDisk = OIDocumentEntityQuery.loadDocumentRecords()
        XCTAssertFalse(onDisk.contains { $0.id == deleted.id }, "the deleted document is not written back")
        XCTAssertTrue(onDisk.contains { $0.id == imported.id }, "the other engine's import is saved")

        first.reloadWorkspaceData()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertFalse(first.documents.contains { $0.id == deleted.id }, "a reload does not bring it back")
    }
}
