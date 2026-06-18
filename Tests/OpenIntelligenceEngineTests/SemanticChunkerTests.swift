import XCTest
@testable import OpenIntelligenceEngine

final class SemanticChunkerTests: XCTestCase {
    var chunker: SemanticChunker!

    override func setUp() {
        super.setUp()
        chunker = SemanticChunker()
    }

    override func tearDown() {
        chunker = nil
        super.tearDown()
    }

    func testChunkText_WithEmptyString_ReturnsEmptyArray() {
        // Arrange
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
            useSemanticBoundaries: true
        )

        // Act
        let chunks = chunker.chunkText(
            text,
            documentId: documentId,
            config: config
        )

        // Assert
        XCTAssertTrue(chunks.isEmpty, "Chunking an empty string should return an empty array of chunks.")
    }

    func testChunkTextAsync_WithEmptyString_ReturnsEmptyArray() async {
        // Arrange
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
            useSemanticBoundaries: true
        )

        // Act
        let chunks = await chunker.chunkTextAsync(
            text,
            documentId: documentId,
            config: config
        )

        // Assert
        XCTAssertTrue(chunks.isEmpty, "Async chunking an empty string should return an empty array of chunks.")
    }
}
