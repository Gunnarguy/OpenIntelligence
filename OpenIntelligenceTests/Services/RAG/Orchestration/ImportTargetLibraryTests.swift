//
//  ImportTargetLibraryTests.swift
//  OpenIntelligenceTests
//
//  An import goes to the library it was queued for (5.7). Through 5.6 `addDocument` used the library
//  that was active when the queue reached a file, so "Add to Library" naming another library, a file
//  added from the Opened File sheet to another library, or a file queued before the person switched
//  libraries, landed in the open one. Runs a real import of a short note on an engine of its own, in
//  the app the suite runs in, on a paid plan for the length of the test (the free plan allows one
//  library), like `DeletedLibraryTests`.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ImportTargetLibraryTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    func testAFileQueuedForAnotherLibraryIsImportedThere() async throws {
        let engine = RAGService()
        let open = engine.containerService.activeContainerId
        let other = try engine.containerService.createContainer(name: "Import target \(UUID().uuidString.prefix(8))")
        // The library's documents go first: `deleteContainer` alone leaves them in the document list, and
        // five runs of this test left five, which filled the free plan's limit on the test simulator
        // (2026-10-15). `LibraryDeletion` does the same for the app.
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == other.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: other.id)
        }
        XCTAssertNotEqual(other.id, open)

        let name = "import-target-\(UUID().uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data("The quillberry deposit for the test flat is paid before moving in.".utf8).write(to: url)

        let result = await engine.ingestDocuments([url], containerId: other.id)

        XCTAssertEqual(result.successCount, 1, "the note was imported")
        let imported = engine.documents.filter { $0.filename.hasPrefix(name) }
        XCTAssertEqual(imported.count, 1)
        XCTAssertEqual(imported.first?.containerId, other.id, "the note is in the library it was queued for")
        XCTAssertEqual(engine.containerService.activeContainerId, open, "the open library did not change")
    }

    /// "Add to Library" naming a library that is not the open one, run through the action's own `perform()`: the
    /// text is queued on the app's engine for that library, imported there, and the open library does not change.
    func testAddToLibraryNamingAnotherLibraryImportsThere() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let engine = IntentSupport.engine()
        let open = engine.containerService.activeContainerId
        let other = try engine.containerService.createContainer(name: "Add to Library target \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == other.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: other.id)
        }
        XCTAssertNotEqual(other.id, open)

        let add = AddToLibraryIntent()
        add.text = "The quillberry gate code for the second test flat is 9021, and it changes every autumn."
        add.name = "Add to Library target \(UUID().uuidString.prefix(8))"
        add.library = OILibraryEntityQuery.entity(for: other)
        _ = try await add.perform()

        var imported: Document?
        for _ in 0..<600 {
            imported = engine.documents.first { $0.containerId == other.id }
            if imported != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let document = try XCTUnwrap(imported, "the note was not imported into the library it named within a minute")
        XCTAssertGreaterThan(document.totalChunks, 0)
        XCTAssertFalse(
            engine.documents.contains { $0.filename == document.filename && $0.containerId != other.id },
            "the note went to the library it named and nowhere else")
        XCTAssertEqual(engine.containerService.activeContainerId, open, "the open library did not change")
    }
}
