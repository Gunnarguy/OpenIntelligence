//
//  PassagesFromKnownDocumentsTests.swift
//  OpenIntelligenceTests
//
//  A passage whose document is in no library (deleted, or an import that stopped before recording it) is left
//  out of every search, and at launch it is removed from the stores of Local Only libraries (5.7). Until then an
//  answer could cite it as "Unknown": on 2026-10-15 the owner's library BDB0BCA5 held 27 such passages and no
//  document.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class PassagesFromKnownDocumentsTests: XCTestCase {
    // A second library needs a plan that allows one (the free plan allows one library), as in
    // `ImportTargetLibraryTests`.
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    private func passage(_ document: UUID, named name: String = "") -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: document, content: "The deposit is 1,234 dollars.", embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: 0.5, rank: 1, sourceDocument: name, pageNumber: nil)
    }

    func testAPassageOfADocumentInNoLibraryIsLeftOut() {
        let lease = UUID()
        let gone = UUID()
        let result = RAGService.passagesFromKnownDocuments(
            [passage(lease), passage(gone), passage(gone, named: "Unknown")], knownDocumentIds: [lease])
        XCTAssertEqual(result.kept.map(\.chunk.documentId), [lease])
        XCTAssertEqual(result.dropped, 2)
    }

    func testAPassageThePipelineMadeItselfIsKept() {
        let capture = passage(UUID(), named: "Barcode Scanner")
        let result = RAGService.passagesFromKnownDocuments([capture], knownDocumentIds: [])
        XCTAssertEqual(result.kept.count, 1, "a capture's own document is in no library and still counts")
        XCTAssertEqual(result.dropped, 0)
    }

    func testLaunchRemovesTheStoredPassagesOfADocumentInNoLibrary() async throws {
        let libraries = ContainerService()
        let library = try libraries.createContainer(name: "Orphans \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in libraries.deleteContainer(id: library.id) }
        let store = VectorStoreRouter().db(for: library)
        let kept = UUID()
        let orphan = UUID()
        let dimension = store.dimension > 0 ? store.dimension : 384
        for document in [kept, orphan] {
            try await store.store(chunk: DocumentChunk(
                documentId: document, content: "A passage for \(document.uuidString.prefix(8)).",
                embedding: [Float](repeating: 0.01, count: dimension), metadata: ChunkMetadata(chunkIndex: 0)))
        }

        let removed = await RAGService.removePassages(notIn: [kept], from: [store])

        XCTAssertEqual(removed, 1)
        let orphanCount = try await store.chunkCount(forDocument: orphan)
        let keptCount = try await store.chunkCount(forDocument: kept)
        XCTAssertEqual(orphanCount, 0, "the passage of the document in no library is gone")
        XCTAssertEqual(keptCount, 1, "the passage of a listed document stays")
        try await store.deleteChunks(forDocument: kept)
    }
}
