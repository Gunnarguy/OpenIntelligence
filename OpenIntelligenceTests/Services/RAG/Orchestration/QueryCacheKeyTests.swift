//
//  QueryCacheKeyTests.swift
//  OpenIntelligenceTests
//
//  The query cache keeps the search behind every question asked, and a question asked again uses it
//  without searching. Through 5.6 its key was the question and the library's id alone and nothing ever
//  cleared it, so a question asked again after an import or a deletion got the old passages back:
//  none from the new document, and the deleted document's text with them. Found on 2026-10-14 when
//  `ShortcutsActionTests` asked the question an earlier run had asked and got passages from notes that
//  run had deleted. From 5.7 the key carries every library's documents with their passage counts and
//  the embedding model (`RAGService.queryCacheKey`), and a cached search that names a document no
//  longer in the libraries is not used (`RAGService.cachedResultsAreCurrent`).
//

import XCTest

@testable import OpenIntelligence

final class QueryCacheKeyTests: XCTestCase {
    private let question = "how much is the deposit"
    private let lease = UUID()
    private let notes = UUID()

    private func key(
        _ documents: [(id: UUID, passages: Int)], model: String = "coreml_sentence_embedding", dimension: Int = 384
    )
        -> String
    {
        RAGService.queryCacheKey(question, documents: documents, embeddingProviderId: model, dimension: dimension)
    }

    func testTheSameLibraryGivesTheSameKeyInAnyOrder() {
        XCTAssertEqual(key([(lease, 12), (notes, 3)]), key([(notes, 3), (lease, 12)]))
        XCTAssertTrue(key([(lease, 12)]).hasPrefix(question), "the key still starts with the question")
    }

    func testAChangeToTheLibrariesOrTheModelGivesANewKey() {
        let before = key([(lease, 12)])
        XCTAssertNotEqual(before, key([(lease, 12), (notes, 3)]), "an import")
        XCTAssertNotEqual(before, key([]), "a deletion")
        XCTAssertNotEqual(before, key([(lease, 14)]), "a re-import with more passages")
        XCTAssertNotEqual(before, key([(lease, 12)], model: "coreai_sentence_embedding"), "another embedding model")
        XCTAssertNotEqual(before, key([(lease, 12)], dimension: 512), "another dimension")
        XCTAssertNotEqual(
            RAGService.queryCacheKey(
                question, documents: [(lease, 12)], embeddingProviderId: "coreml_sentence_embedding", dimension: 384,
                appVersion: "5.7 (486)"),
            RAGService.queryCacheKey(
                question, documents: [(lease, 12)], embeddingProviderId: "coreml_sentence_embedding", dimension: 384,
                appVersion: "5.7 (487)"),
            "an update")
    }

    private func passage(from document: UUID) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: document, content: "The deposit is 1,234 dollars.", embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: 0.5, rank: 1, sourceDocument: "Lease.pdf", pageNumber: nil)
    }

    func testACachedSearchIsUsedOnlyWhileEveryDocumentInItIsStillThere() {
        XCTAssertTrue(RAGService.cachedResultsAreCurrent([passage(from: lease)], documentIds: [lease, notes]))
        XCTAssertFalse(
            RAGService.cachedResultsAreCurrent([passage(from: lease), passage(from: notes)], documentIds: [lease]),
            "a passage from a deleted document would bring its text into the answer")
        XCTAssertFalse(
            RAGService.cachedResultsAreCurrent([], documentIds: [lease]), "an empty search is searched again")
    }
}
