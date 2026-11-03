//
//  RebuildKeepsDocumentIdTests.swift
//  OpenIntelligenceTests
//
//  A rebuild re-imports each document under its own id and records no deletion (5.8). Through 5.7 it removed the
//  document, which wrote its id to `deleted_documents.json`, and imported it again under a new id. iCloud carried the
//  deletions to the other device, which wiped the passages, found the library empty, rebuilt it the same way and sent
//  the deletions back: on the owner's iPhone and Mac on 2026-11-03 one pass took 5,165, 1,888 and 403 passages. Runs a
//  real import and rebuild of a short note on an engine of its own, on a paid plan for the length of the test, like
//  `ImportTargetLibraryTests`.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class RebuildKeepsDocumentIdTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    private func recordedDeletions() -> Set<String> {
        let url = AppSupportPaths.baseDir().appendingPathComponent("deleted_documents.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    /// A new chunk size for the library, so the rebuild takes the full path that re-imports each document; with the
    /// chunking unchanged it re-embeds the stored passages and never removes or re-adds anything.
    private func changeChunking(of libraryId: UUID, in engine: RAGService) throws {
        var library = try XCTUnwrap(engine.containerService.containers.first { $0.id == libraryId })
        library.chunkingDirective = ChunkingDirective(
            source: .manual, strategy: "balanced", targetWordWindow: 180, overlapWords: 30)
        engine.containerService.updateContainer(library)
    }

    func testARebuildKeepsTheDocumentsIdLibraryAndPassagesAndRecordsNoDeletion() async throws {
        let engine = RAGService()
        let library = try engine.containerService.createContainer(
            name: "Rebuild keeps id \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: library.id)
        }

        let name = "rebuild-keeps-id-\(UUID().uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data("The quillberry boiler in the test flat is serviced every March by the building's own engineer.".utf8)
            .write(to: url)
        let result = await engine.ingestDocuments([url], containerId: library.id)
        XCTAssertEqual(result.successCount, 1, "the note was imported")
        let before = try XCTUnwrap(engine.documents.first { $0.filename.hasPrefix(name) })

        try changeChunking(of: library.id, in: engine)
        try await engine.reembedDocuments(in: library.id, reason: "test")

        let after = engine.documents.filter { $0.filename.hasPrefix(name) }
        XCTAssertEqual(after.count, 1, "one record, not a second copy")
        XCTAssertEqual(after.first?.id, before.id, "the rebuilt document keeps its id")
        XCTAssertEqual(after.first?.containerId, library.id, "and its library")
        XCTAssertFalse(recordedDeletions().contains(before.id.uuidString), "a rebuild records no deletion")
        let db = try await engine.dbForContainer(library.id)
        let passages = try await db.chunkCount(forDocument: before.id)
        XCTAssertGreaterThan(passages, 0, "its passages are back under the same id")
    }

    /// At the plan's document limit a rebuild still re-imports (review, 2026-11-03): the kept record counts toward the
    /// limit, and the check refused the re-add, leaving the document listed with no passages.
    func testARebuildAtTheFreePlansLimitStillRestoresEveryDocument() async throws {
        let engine = RAGService()
        // Set again here: the app the suite runs in checks purchases at launch and can write the free plan back after
        // `setUp` (a second run failed at this line on 2026-11-03 with the free plan's one-library limit).
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let library = try engine.containerService.createContainer(name: "Rebuild at limit \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: library.id)
        }
        let name = "rebuild-at-limit-\(UUID().uuidString.prefix(8))"
        var urls: [URL] = []
        for n in 0..<5 {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(n).txt")
            try Data("Quillberry note \(n): the test flat's meter number \(4100 + n) is read on the first of each month.".utf8)
                .write(to: url)
            urls.append(url)
        }
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let result = await engine.ingestDocuments(urls, containerId: library.id)
        XCTAssertEqual(result.successCount, 5)

        UserDefaults.standard.set(WorkspaceTier.free.rawValue, forKey: tierKey)
        try changeChunking(of: library.id, in: engine)
        try await engine.reembedDocuments(in: library.id, reason: "test")

        let db = try await engine.dbForContainer(library.id)
        for document in engine.documents where document.filename.hasPrefix(name) {
            let passages = try await db.chunkCount(forDocument: document.id)
            XCTAssertGreaterThan(passages, 0, "\(document.filename) has its passages back")
        }
        XCTAssertEqual(engine.documents.filter { $0.filename.hasPrefix(name) }.count, 5)
    }
}
