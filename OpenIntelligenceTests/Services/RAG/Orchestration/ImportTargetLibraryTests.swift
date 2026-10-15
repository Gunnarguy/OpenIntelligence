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
        addTeardownBlock { @MainActor in engine.containerService.deleteContainer(id: other.id) }
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
}
