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

    // MARK: - testChunkText Basic Functionality

    func testChunkText_basicSingleChunk() {
        let text = "This is a short test document. It should be parsed into a single chunk since it is small."
        let documentId = UUID()

        let chunks = chunker.chunkText(text, documentId: documentId)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].metadata.documentId, documentId)
        XCTAssertEqual(chunks[0].content, text)
        XCTAssertEqual(chunks[0].metadata.chunkIndex, 0)
        XCTAssertEqual(chunks[0].metadata.totalChunks, 1)
    }

    func testChunkText_longTextChunking() {
        // Generate a text that exceeds the target/max size of a chunk
        var longText = ""
        for i in 1...100 {
            longText += "Sentence number \(i) is here to add some length to the text. "
        }

        let documentId = UUID()
        var config = SemanticChunker.ChunkingConfig()
        config.targetSize = 100 // Set a small target to ensure multiple chunks are created
        config.minSize = 50
        config.maxSize = 150
        config.overlap = 20
        config.useTopicDetection = false // Disable topic detection to simplify chunking logic for this test

        let chunks = chunker.chunkText(longText, documentId: documentId, config: config)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertEqual(chunk.metadata.documentId, documentId)
        }
    }

    func testChunkText_WithEmptyString_ReturnsEmptyArray() {
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
        )

        let chunks = chunker.chunkText(
            text,
            documentId: documentId,
            config: config
        )

        XCTAssertTrue(chunks.isEmpty || (chunks.count == 1 && chunks.first?.content.isEmpty == true), "Chunking an empty string should return an empty array or a single empty chunk.")
    }

    func testChunkTextAsync_WithEmptyString_ReturnsEmptyArray() async {
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
        )

        let chunks = await chunker.chunkTextAsync(
            text,
            documentId: documentId,
            config: config
        )

        XCTAssertTrue(chunks.isEmpty || (chunks.count == 1 && chunks.first?.content.isEmpty == true), "Async chunking an empty string should return an empty array or a single empty chunk.")
    }

    func testChunkingConfig_presets() {
        let techConfig = SemanticChunker.ChunkingConfig.technicalReference
        XCTAssertEqual(techConfig.targetSize, 240)
        XCTAssertEqual(techConfig.maxSize, 310)

        let narrativeConfig = SemanticChunker.ChunkingConfig.narrative
        XCTAssertEqual(narrativeConfig.targetSize, 280)
        XCTAssertEqual(narrativeConfig.maxSize, 310)

        let codeConfig = SemanticChunker.ChunkingConfig.code
        XCTAssertEqual(codeConfig.targetSize, 180)
        XCTAssertEqual(codeConfig.maxSize, 280)
    }

    // MARK: - Extract Entities

    func testExtractEntitiesNamedEntities() {
        let text = "Tim Cook works at Apple in Cupertino."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Tim Cook"), "Should extract Tim Cook as a personal name")
        XCTAssertTrue(entities.contains("Apple"), "Should extract Apple as an organization name")
        XCTAssertTrue(entities.contains("Cupertino"), "Should extract Cupertino as a place name")
    }

    func testExtractEntitiesTechnicalTerms() {
        let text = "We use the SemanticChunker class with Foundation framework."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("SemanticChunker"), "Should extract SemanticChunker as a technical term (PascalCase)")
    }

    func testExtractEntitiesCapitalizedNouns() {
        let text = "The Model Architecture ensures robust performance."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Model") || entities.contains("Architecture") || entities.contains("Model Architecture"), "Should extract Model Architecture as capitalized domain term")
    }

    func testExtractEntitiesDeduplication() {
        let text = "Apple makes the iPhone. Apple is a large company."
        let entities = chunker.extractEntities(text)

        let appleCount = entities.filter { $0.lowercased() == "apple" }.count
        XCTAssertEqual(appleCount, 1, "Should deduplicate entities")
    }
}
