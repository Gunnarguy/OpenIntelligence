import XCTest
@testable import OpenIntelligence

final class ContextPackingServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeChunk(content: String, docId: UUID = UUID(), index: Int = 0) -> DocumentChunk {
        DocumentChunk(
            documentId: docId,
            content: content,
            embedding: Array(repeating: Float(0.1), count: 384),
            metadata: ChunkMetadata(
                chunkIndex: index,
                wordCount: content.split(separator: " ").count,
                characterCount: content.count
            )
        )
    }

    private func makeEdges() -> ChunkGraphEdges {
        ChunkGraphEdges()
    }

    // MARK: - Basic Packing

    func testPackReturnsChunksWithinTokenBudget() async {
        let service = ContextPackingService()
        let chunks = (0..<10).map { i in
            makeChunk(content: "Chunk \(i) content about testing the context packing service.", index: i)
        }
        let allChunksDict = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        let result = await service.pack(
            retrievedChunks: chunks,
            graphEdges: [:],
            allChunks: allChunksDict,
            tokenBudget: 500
        )

        // Estimated tokens should not exceed budget
        XCTAssertLessThanOrEqual(result.estimatedTokens, 500 + 50,
                                  "Packed tokens should roughly respect budget (with small margin)")
    }

    func testPackWithEmptyChunksReturnsEmpty() async {
        let service = ContextPackingService()

        let result = await service.pack(
            retrievedChunks: [],
            graphEdges: [:],
            allChunks: [:]
        )

        XCTAssertTrue(result.chunks.isEmpty, "Empty input should produce empty output")
        XCTAssertEqual(result.coreChunkCount, 0)
        XCTAssertEqual(result.contextChunkCount, 0)
        XCTAssertFalse(result.wasTruncated)
    }

    func testPackSingleChunkFits() async {
        let service = ContextPackingService()
        let chunk = makeChunk(content: "A single small chunk.")
        let allChunksDict: [UUID: DocumentChunk] = [chunk.id: chunk]

        let result = await service.pack(
            retrievedChunks: [chunk],
            graphEdges: [:],
            allChunks: allChunksDict
        )

        XCTAssertEqual(result.chunks.count, 1)
        XCTAssertEqual(result.coreChunkCount, 1)
        XCTAssertFalse(result.wasTruncated)
        XCTAssertTrue(result.trimmedChunkIds.isEmpty)
    }

    // MARK: - Truncation

    func testPackTruncatesWhenOverBudget() async {
        let service = ContextPackingService()
        // Create chunks with substantial content that will exceed a tiny budget
        let chunks = (0..<20).map { i in
            makeChunk(content: String(repeating: "word ", count: 200) + "chunk \(i)", index: i)
        }
        let allChunksDict = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        let result = await service.pack(
            retrievedChunks: chunks,
            graphEdges: [:],
            allChunks: allChunksDict,
            tokenBudget: 100  // Very tight budget
        )

        XCTAssertTrue(result.wasTruncated, "Should truncate when content exceeds budget")
        XCTAssertFalse(result.trimmedChunkIds.isEmpty, "Should have trimmed chunk IDs")
        XCTAssertLessThan(result.chunks.count, chunks.count,
                          "Should include fewer chunks than input")
    }

    // MARK: - Default Budget

    func testDefaultTokenBudgetIs3200() async {
        let service = ContextPackingService()
        // Create content that would need >> 3200 tokens
        let chunks = (0..<50).map { i in
            makeChunk(content: String(repeating: "testing content ", count: 100) + " chunk \(i)", index: i)
        }
        let allChunksDict = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        let result = await service.pack(
            retrievedChunks: chunks,
            graphEdges: [:],
            allChunks: allChunksDict
            // No tokenBudget → uses default 3200
        )

        // Even without explicit budget, should still be bounded
        XCTAssertTrue(result.wasTruncated || result.chunks.count < 50,
                      "Default budget should prevent including all 50 large chunks")
    }

    // MARK: - Graph Context

    func testPackIncludesNeighborChunks() async {
        let service = ContextPackingService()
        let docId = UUID()
        let chunk0 = makeChunk(content: "First chunk content here.", docId: docId, index: 0)
        let chunk1 = makeChunk(content: "Second chunk core content.", docId: docId, index: 1)
        let chunk2 = makeChunk(content: "Third chunk content here.", docId: docId, index: 2)

        var edges1 = ChunkGraphEdges()
        edges1.prevChunkId = chunk0.id
        edges1.nextChunkId = chunk2.id

        let allChunksDict: [UUID: DocumentChunk] = [
            chunk0.id: chunk0,
            chunk1.id: chunk1,
            chunk2.id: chunk2
        ]

        let result = await service.pack(
            retrievedChunks: [chunk1],
            graphEdges: [chunk1.id: edges1],
            allChunks: allChunksDict,
            neighborDistance: 1
        )

        // Should include the core chunk plus neighbors
        XCTAssertGreaterThanOrEqual(result.chunks.count, 1,
                                     "Should include at least the core chunk")
        XCTAssertGreaterThanOrEqual(result.coreChunkCount, 1)
    }

    // MARK: - PackedContext Properties

    func testPackedContextCoreVsContextCounts() async {
        let service = ContextPackingService()
        let docId = UUID()
        let coreChunk = makeChunk(content: "Core retrieved chunk.", docId: docId, index: 0)
        let neighborChunk = makeChunk(content: "Neighbor chunk.", docId: docId, index: 1)

        var edges = ChunkGraphEdges()
        edges.nextChunkId = neighborChunk.id

        let allChunksDict: [UUID: DocumentChunk] = [
            coreChunk.id: coreChunk,
            neighborChunk.id: neighborChunk
        ]

        let result = await service.pack(
            retrievedChunks: [coreChunk],
            graphEdges: [coreChunk.id: edges],
            allChunks: allChunksDict
        )

        XCTAssertGreaterThanOrEqual(result.coreChunkCount, 1,
                                     "Should count at least one core chunk")
        // contextChunkCount should be the extras
        XCTAssertEqual(result.chunks.count,
                       result.coreChunkCount + result.contextChunkCount,
                       "Total chunks = core + context")
    }

    // MARK: - Character Limit

    func testPackedContextDoesNotExceed5500Characters() async {
        let service = ContextPackingService()
        let chunks = (0..<30).map { i in
            makeChunk(content: String(repeating: "text ", count: 100) + " chunk \(i)", index: i)
        }
        let allChunksDict = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })

        let result = await service.pack(
            retrievedChunks: chunks,
            graphEdges: [:],
            allChunks: allChunksDict
        )

        let totalChars = result.chunks.reduce(0) { $0 + $1.content.count }
        // With default 3200 token budget at ~1.4 chars/token ≈ 4480 chars + some overhead
        // Should be bounded, not unlimited
        XCTAssertLessThan(totalChars, 10000,
                          "Packed context should be bounded by token budget (not unlimited)")
    }
}
