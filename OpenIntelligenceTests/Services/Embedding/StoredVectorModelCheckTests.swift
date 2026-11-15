import XCTest

@testable import OpenIntelligence

/// A device skips the one-time rebuild of a library only when the vectors it holds are provably the live model's.
/// A wrong yes here leaves a library whose searches return noise, so every doubtful case must say no.
final class StoredVectorModelCheckTests: XCTestCase {
    private func chunk(_ document: UUID, _ index: Int, length: Int = 200) -> DocumentChunk {
        DocumentChunk(
            id: UUID(), documentId: document, content: String(repeating: "a", count: length), parentContent: nil,
            contextualPrefix: "Doc. ", embedding: [],
            metadata: ChunkMetadata(
                chunkIndex: index, startPosition: 0, endPosition: length, pageNumber: nil, sectionTitle: nil,
                keywords: [], semanticDensity: 0.5, hasNumericData: false, hasListStructure: false, wordCount: 1,
                characterCount: length, structureType: nil, sectionPath: []))
    }

    func testSamplesEveryDocument_spreadThroughIt() throws {
        let a = UUID()
        let b = UUID()
        let chunks = (0..<10).map { chunk(a, $0) } + (0..<4).map { chunk(b, $0) }
        let sample = try XCTUnwrap(StoredVectorModelCheck.sample(of: chunks, documentIds: [a, b]))
        XCTAssertEqual(sample.filter { $0.documentId == a }.map(\.metadata.chunkIndex), [0, 5])
        XCTAssertEqual(sample.filter { $0.documentId == b }.map(\.metadata.chunkIndex), [0, 2])
    }

    func testADocumentWithNoTestablePassage_meansNoSample() {
        let a = UUID()
        let b = UUID()
        // b's only passage is too short to mean anything.
        XCTAssertNil(StoredVectorModelCheck.sample(of: [chunk(a, 0), chunk(b, 0, length: 10)], documentIds: [a, b]))
        // A document the library lists and the store doesn't hold at all.
        XCTAssertNil(StoredVectorModelCheck.sample(of: [chunk(a, 0)], documentIds: [a, b]))
        XCTAssertNil(StoredVectorModelCheck.sample(of: [chunk(a, 0)], documentIds: []))
    }

    func testTheTextIsThePrefixThenTheContent() {
        XCTAssertEqual(StoredVectorModelCheck.embeddedText(of: chunk(UUID(), 0, length: 80)).prefix(6), "Doc. a")
    }

    func testTheSameModelOnAnotherChipPasses_anotherModelFails() {
        let stored: [[Float]] = [[0.6, 0.8, 0], [0, 1, 0]]
        // A few parts in a thousand apart, as two chips compute the same model.
        XCTAssertTrue(StoredVectorModelCheck.storedVectorsAreLive(stored: stored, fresh: [[0.601, 0.799, 0.002], [0.001, 1, 0]]))
        // One passage from another space fails the library, however well the other matches.
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: stored, fresh: [[0.6, 0.8, 0], [1, 0, 0]]))
    }

    func testEmptyZeroOrMismatchedVectorsNeverPass() {
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: [], fresh: []))
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: [[0, 0, 0]], fresh: [[1, 0, 0]]))
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: [[1, 0]], fresh: [[1, 0, 0]]))
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: [[1, 0, 0]], fresh: [[1, 0, 0], [0, 1, 0]]))
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreLive(stored: [[]], fresh: [[]]))
    }
}
