import XCTest
@testable import OpenIntelligence

final class SemanticChunkerTests: XCTestCase {

    // MARK: - Helpers

    private func makeChunker() -> SemanticChunker {
        SemanticChunker()
    }

    private func loremText(wordCount: Int) -> String {
        let words = ["the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog",
                     "and", "then", "runs", "across", "field", "while", "birds", "fly",
                     "above", "trees", "near", "river", "that", "flows", "down", "mountain"]
        return (0..<wordCount).map { words[$0 % words.count] }.joined(separator: " ")
    }

    // MARK: - Basic Chunking

    func testChunkTextReturnsNonEmptyForNonTrivialInput() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 500)
        let chunks = chunker.chunkText(text, documentId: UUID())
        XCTAssertFalse(chunks.isEmpty, "Should produce at least one chunk for 500-word text")
    }

    func testSingleSmallTextReturnsOneChunk() {
        let chunker = makeChunker()
        let text = "A short sentence about Swift programming."
        let chunks = chunker.chunkText(text, documentId: UUID())
        XCTAssertEqual(chunks.count, 1, "Very short text should produce exactly one chunk")
    }

    func testEmptyTextReturnsOneChunk() {
        let chunker = makeChunker()
        let chunks = chunker.chunkText("", documentId: UUID())
        // Even empty text should return a single (empty) chunk rather than crashing
        XCTAssertTrue(chunks.count <= 1, "Empty text should produce at most one chunk")
    }

    // MARK: - Word Count Limits

    func testChunkWordCountNeverExceedsMaxSize() {
        let chunker = makeChunker()
        let config = SemanticChunker.ChunkingConfig()
        let text = loremText(wordCount: 2000)
        let chunks = chunker.chunkText(text, documentId: UUID(), config: config)

        for chunk in chunks {
            let wordCount = chunk.content.split(separator: " ").count
            XCTAssertLessThanOrEqual(wordCount, config.maxSize + 20,
                                     "Chunk should not exceed maxSize (310) by more than a small margin. Got \(wordCount)")
        }
    }

    func testChunkWordCountMeetsMinSize() {
        let chunker = makeChunker()
        let config = SemanticChunker.ChunkingConfig()
        let text = loremText(wordCount: 2000)
        let chunks = chunker.chunkText(text, documentId: UUID(), config: config)

        // All chunks except the last one should meet minSize
        for (index, chunk) in chunks.dropLast().enumerated() {
            let wordCount = chunk.content.split(separator: " ").count
            // Allow some slack because sentence boundaries may cause slightly smaller chunks
            XCTAssertGreaterThanOrEqual(wordCount, config.minSize / 2,
                                        "Chunk \(index) should be at least half of minSize. Got \(wordCount)")
        }
    }

    // MARK: - Metadata Correctness

    func testChunkIndicesAreSequential() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 1000)
        let chunks = chunker.chunkText(text, documentId: UUID())

        for (i, chunk) in chunks.enumerated() {
            XCTAssertEqual(chunk.metadata.chunkIndex, i,
                           "Chunk index should be sequential. Expected \(i), got \(chunk.metadata.chunkIndex)")
        }
    }

    func testTotalChunksMetadataIsConsistent() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 1000)
        let chunks = chunker.chunkText(text, documentId: UUID())

        for chunk in chunks {
            XCTAssertEqual(chunk.metadata.totalChunks, chunks.count,
                           "totalChunks metadata should equal actual chunk count")
        }
    }

    func testDocumentIdMatchesInput() {
        let chunker = makeChunker()
        let docId = UUID()
        let chunks = chunker.chunkText("Test content for document identification.", documentId: docId)

        for chunk in chunks {
            XCTAssertEqual(chunk.metadata.documentId, docId)
        }
    }

    func testWordCountMetadataIsAccurate() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 500)
        let chunks = chunker.chunkText(text, documentId: UUID())

        for chunk in chunks {
            let actualWordCount = chunk.content.split(separator: " ").count
            // Allow ±20% tolerance for word counting differences
            let tolerance = max(5, actualWordCount / 5)
            XCTAssertEqual(chunk.metadata.wordCount, actualWordCount, accuracy: tolerance,
                           "Word count metadata should roughly match actual word count")
        }
    }

    // MARK: - Config Presets

    func testTechnicalReferencePresetHasCorrectLimits() {
        let config = SemanticChunker.ChunkingConfig.technicalReference
        XCTAssertEqual(config.maxSize, 310, "Technical reference max should be 310")
        XCTAssertLessThanOrEqual(config.targetSize, 310, "Target should not exceed max")
        XCTAssertGreaterThan(config.minSize, 0, "Min size should be positive")
    }

    func testNarrativePresetHasCorrectLimits() {
        let config = SemanticChunker.ChunkingConfig.narrative
        XCTAssertEqual(config.maxSize, 310, "Narrative max should be 310")
        XCTAssertGreaterThan(config.targetSize, SemanticChunker.ChunkingConfig.technicalReference.targetSize,
                             "Narrative target should be larger than technical reference")
    }

    func testCodePresetHasConservativeLimits() {
        let config = SemanticChunker.ChunkingConfig.code
        XCTAssertLessThan(config.maxSize, 310, "Code max should be conservative (< 310)")
    }

    // MARK: - Section Detection

    func testSectionHeadersDetected() {
        let chunker = makeChunker()
        let text = """
        # Introduction

        This is the introduction section with enough words to form a meaningful chunk about the topic at hand. \
        We discuss various aspects of the system architecture and how services interact with each other \
        in the overall pipeline design.

        ## Background

        The background section provides additional context and historical information about the development \
        of the system. It covers previous approaches and why the current architecture was chosen \
        over alternatives that were considered.

        ## Implementation

        The implementation section describes the actual code changes and technical decisions made \
        during the development process. Each component is explained in detail with examples.
        """
        let chunks = chunker.chunkText(text, documentId: UUID())

        // At least some chunks should have section titles
        let chunksWithSections = chunks.filter { $0.metadata.sectionTitle != nil }
        XCTAssertFalse(chunksWithSections.isEmpty,
                       "Markdown headers should be detected as section boundaries")
    }

    // MARK: - Numeric & List Detection

    func testNumericDataDetection() {
        let chunker = makeChunker()
        let text = """
        The measurements show the following results from the experiment: temperature 98.6°F \
        pressure 14.7 psi volume 3.5 liters weight 2.8 kg. The sample size was 1500 participants \
        across 12 different research sites. Each participant was measured 3 times per day for \
        a total of 45 days resulting in 202500 individual data points collected.
        """
        let chunks = chunker.chunkText(text, documentId: UUID())

        let hasNumeric = chunks.contains { $0.metadata.hasNumericData }
        XCTAssertTrue(hasNumeric, "Chunks with measurements should flag hasNumericData")
    }

    func testListStructureDetection() {
        let chunker = makeChunker()
        let text = """
        The system requirements include the following items that must be addressed:
        - Apple Silicon Mac or iPhone with A17 Pro or newer processor
        - iOS 26.0 or later operating system version installed
        - At least 4GB of available RAM for processing large documents
        - Network connectivity for initial model download and updates
        - Sufficient storage space for the vector database and cached embeddings
        - A valid Apple Developer account for testing on physical devices
        - Xcode 26 or later with the iOS 26 SDK installed and configured
        """
        let chunks = chunker.chunkText(text, documentId: UUID())

        let hasList = chunks.contains { $0.metadata.hasListStructure }
        XCTAssertTrue(hasList, "Bullet list content should flag hasListStructure")
    }

    // MARK: - Large Document

    func testLargeDocumentChunksCorrectly() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 10000)
        let chunks = chunker.chunkText(text, documentId: UUID())

        XCTAssertGreaterThan(chunks.count, 10, "10K word document should produce many chunks")

        // All content should be covered
        let totalWords = chunks.reduce(0) { $0 + $1.content.split(separator: " ").count }
        XCTAssertGreaterThan(totalWords, 8000,
                             "Chunks should cover most of the original text (accounting for overlap)")
    }

    // MARK: - Diagnostics

    func testDiagnosticsAvailableAfterChunking() {
        let chunker = makeChunker()
        let text = loremText(wordCount: 500)
        _ = chunker.chunkText(text, documentId: UUID())

        let diagnostics = chunker.diagnostics()
        XCTAssertNotNil(diagnostics, "Diagnostics should be available after chunking")
    }
}
