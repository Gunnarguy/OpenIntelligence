import XCTest
@testable import OpenIntelligenceEngine

final class ContextPackingServiceTests: XCTestCase {

    var packingService: ContextPackingService!
    var graphIndexService: GraphIndexService!

    override func setUp() async throws {
        graphIndexService = GraphIndexService()
        packingService = ContextPackingService(graphIndex: graphIndexService)
    }

    override func tearDown() {
        packingService = nil
        graphIndexService = nil
    }

    private func createDummyChunk(id: UUID = UUID(), documentId: UUID = UUID(), content: String = "Test content", index: Int = 0) -> DocumentChunk {
        let metadata = ChunkMetadata(
            chunkIndex: index,
            startPosition: 0,
            endPosition: content.count,
            pageNumber: 1,
            sectionTitle: nil,
            keywords: [],
            semanticDensity: nil,
            hasNumericData: false,
            hasListStructure: false,
            wordCount: content.split(separator: " ").count,
            characterCount: content.count,
            createdAt: Date()
        )
        return DocumentChunk(
            id: id,
            documentId: documentId,
            content: content,
            parentContent: nil,
            contextualPrefix: nil,
            embedding: [],
            metadata: metadata
        )
    }

    func testBasicContextPacking() async throws {
        let chunk1 = createDummyChunk(content: "Chunk 1 content")
        let retrievedChunks = [chunk1]

        let packedContext = await packingService.pack(
            retrievedChunks: retrievedChunks,
            graphEdges: [:],
            allChunks: [chunk1.id: chunk1],
            tokenBudget: 1000
        )

        XCTAssertEqual(packedContext.chunks.count, 1)
        XCTAssertEqual(packedContext.chunks.first?.id, chunk1.id)
        XCTAssertEqual(packedContext.coreChunkCount, 1)
        XCTAssertFalse(packedContext.wasTruncated)
    }

    func testContextPackingWithTokenBudget() async throws {
        // Create chunks
        let docId = UUID()
        let chunk1 = createDummyChunk(id: UUID(), documentId: docId, content: "Chunk 1 is a relatively small chunk.", index: 0)
        let chunk2 = createDummyChunk(id: UUID(), documentId: docId, content: "Chunk 2 is another small chunk with some text.", index: 1)
        let chunk3 = createDummyChunk(id: UUID(), documentId: docId, content: "Chunk 3 is a large chunk that takes up more tokens to test if truncation logic works properly as we expect it to do.", index: 2)

        let retrievedChunks = [chunk1, chunk2, chunk3]
        let allChunks = [chunk1.id: chunk1, chunk2.id: chunk2, chunk3.id: chunk3]

        // Very tight token budget to force truncation
        // Tokens per char is ~0.71. Chunk 1 is ~36 chars (~26 tokens)
        // Chunk 2 is ~46 chars (~33 tokens). Total ~ 59 tokens.
        // Let's set budget to 50 to see if it truncates chunk 2 and 3.
        let budget = 40

        let packedContext = await packingService.pack(
            retrievedChunks: retrievedChunks,
            graphEdges: [:],
            allChunks: allChunks,
            tokenBudget: budget
        )

        XCTAssertTrue(packedContext.wasTruncated, "Should be truncated with small budget")
        XCTAssertTrue(packedContext.chunks.count < 3, "Should have fewer than 3 chunks")
        XCTAssertEqual(packedContext.trimmedChunkIds.count, 3 - packedContext.chunks.count)
    }

    func testContextPackingWithParentAndNeighbors() async throws {
        let docId = UUID()
        let parentChunk = createDummyChunk(id: UUID(), documentId: docId, content: "Parent section header", index: 0)
        let prevChunk = createDummyChunk(id: UUID(), documentId: docId, content: "Previous chunk text", index: 1)
        let mainChunk = createDummyChunk(id: UUID(), documentId: docId, content: "Main retrieved chunk", index: 2)
        let nextChunk = createDummyChunk(id: UUID(), documentId: docId, content: "Next chunk text", index: 3)
        let refChunk = createDummyChunk(id: UUID(), documentId: docId, content: "Referenced chunk text", index: 10)

        var edges = ChunkGraphEdges()
        edges.parentChunkId = parentChunk.id
        edges.prevChunkId = prevChunk.id
        edges.nextChunkId = nextChunk.id
        edges.referencedChunkIds = [refChunk.id]

        let graphEdges = [mainChunk.id: edges]
        let allChunks = [
            parentChunk.id: parentChunk,
            prevChunk.id: prevChunk,
            mainChunk.id: mainChunk,
            nextChunk.id: nextChunk,
            refChunk.id: refChunk
        ]

        let retrievedChunks = [mainChunk]

        let packedContext = await packingService.pack(
            retrievedChunks: retrievedChunks,
            graphEdges: graphEdges,
            allChunks: allChunks,
            tokenBudget: 1000,
            neighborDistance: 1,
            graphHopDistance: 1
        )

        // We expect mainChunk, parentChunk, prevChunk, nextChunk, and refChunk
        XCTAssertEqual(packedContext.coreChunkCount, 1)
        XCTAssertEqual(packedContext.contextChunkCount, 4)
        XCTAssertEqual(packedContext.chunks.count, 5)

        let ids = Set(packedContext.chunks.map { $0.id })
        XCTAssertTrue(ids.contains(mainChunk.id))
        XCTAssertTrue(ids.contains(parentChunk.id))
        XCTAssertTrue(ids.contains(prevChunk.id))
        XCTAssertTrue(ids.contains(nextChunk.id))
        XCTAssertTrue(ids.contains(refChunk.id))
    }

    func testLostInMiddleReordering() async throws {
        let docId = UUID()
        let chunks = (0..<5).map { i in
            createDummyChunk(id: UUID(), documentId: docId, content: "Chunk \(i)", index: i)
        }

        let packedContext = await packingService.pack(
            retrievedChunks: chunks,
            graphEdges: [:],
            allChunks: Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) }),
            tokenBudget: 1000
        )

        XCTAssertEqual(packedContext.chunks.count, 5)

        // applyLostInMiddleReorder turns:
        // [0, 1, 2, 3, 4] -> [0, 2, 4, 3, 1]
        XCTAssertEqual(packedContext.chunks[0].id, chunks[0].id)
        XCTAssertEqual(packedContext.chunks[1].id, chunks[2].id)
        XCTAssertEqual(packedContext.chunks[2].id, chunks[4].id)
        XCTAssertEqual(packedContext.chunks[3].id, chunks[3].id)
        XCTAssertEqual(packedContext.chunks[4].id, chunks[1].id)
    }

    func testPackForIntent() async throws {
        let docId = UUID()
        let chunk1 = createDummyChunk(id: UUID(), documentId: docId, content: "Procedure step 1", index: 1)
        let chunk2 = createDummyChunk(id: UUID(), documentId: docId, content: "Procedure step 2", index: 2)

        let retrievedChunks = [chunk1, chunk2]
        let allChunks: [UUID: DocumentChunk] = [chunk1.id: chunk1, chunk2.id: chunk2]

        let packedContext = await packingService.pack(
            for: .procedure,
            retrievedChunks: retrievedChunks,
            graphEdges: [:],
            allChunks: allChunks,
            tokenBudget: 1000
        )

        XCTAssertEqual(packedContext.coreChunkCount, 2)
        XCTAssertEqual(packedContext.chunks.count, 2)
    }
}
