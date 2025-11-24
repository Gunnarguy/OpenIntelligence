import XCTest
@testable import OpenIntelligence

final class EmbeddingDiagnosticsTests: XCTestCase {

    func testEmbeddingServicePadsVectorsUpToTargetDimension() async throws {
        let provider = MockEmbeddingProvider(dimension: 512)
        let service = EmbeddingService(provider: provider, providerId: "mock", targetDimension: 768)

        let embedding = try await service.generateEmbedding(for: "Unit test content")

        XCTAssertEqual(embedding.count, 768, "EmbeddingService should pad vectors up to target dimension")
        XCTAssertEqual(embedding[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(embedding[511], 0.25, accuracy: 0.0001)
        XCTAssertEqual(embedding[767], 0.0, accuracy: 0.0001)
    }

    func testEmbeddingServiceTruncatesVectorsDownToTargetDimension() async throws {
        let provider = MockEmbeddingProvider(dimension: 1024)
        let service = EmbeddingService(provider: provider, providerId: "mock", targetDimension: 768)

        let embedding = try await service.generateEmbedding(for: "Another test")

        XCTAssertEqual(embedding.count, 768, "EmbeddingService should truncate down to target dimension")
    }
}

private struct MockEmbeddingProvider: EmbeddingProvider {
    let dimension: Int
    var isAvailable: Bool { true }

    func embed(text: String) async throws -> [Float] {
        Array(repeating: Float(0.25), count: dimension)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        let vector = try await embed(text: "")
        return Array(repeating: vector, count: texts.count)
    }
}
