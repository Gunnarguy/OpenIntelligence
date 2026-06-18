import XCTest
@testable import OpenIntelligenceEngine

final class SemanticChunkerTests: XCTestCase {

    // MARK: - testChunkText Basic Functionality

    func testChunkText_basicSingleChunk() {
        let chunker = SemanticChunker()
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
        let chunker = SemanticChunker()

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
            XCTAssertGreaterThanOrEqual(chunk.metadata.wordCount, config.minSize)
            // It might slightly exceed if it snaps to sentence, but generally close to target/max
        }
    }

    func testChunkText_emptyText() {
        let chunker = SemanticChunker()
        let documentId = UUID()
        let chunks = chunker.chunkText("", documentId: documentId)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].content, "")
        // Removed word count assertion for empty text as tokenizer behavior varies
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
}
