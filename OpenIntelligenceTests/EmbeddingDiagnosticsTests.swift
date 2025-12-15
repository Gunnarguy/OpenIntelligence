@testable import OpenIntelligence
import XCTest

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

    // MARK: - Provider Factory Tests

    func testEmbeddingServiceForProviderReturnsCorrectProviderId() {
        let nlService = EmbeddingService.forProvider(id: "nl_embedding", targetDimension: 512)
        XCTAssertEqual(nlService.providerId, "nl_embedding")

        // On iOS 17+, should get contextual; otherwise falls back
        let contextualService = EmbeddingService.forProvider(id: "nl_contextual_embedding", targetDimension: 512)
        XCTAssertTrue(
            contextualService.providerId == "nl_contextual_embedding" || contextualService.providerId == "nl_embedding",
            "Should return contextual on iOS 17+ or fallback to nl_embedding"
        )
    }

    func testEmbeddingServiceForProviderWithFallback() {
        // Request an unknown provider with fallback enabled
        let service = EmbeddingService.forProvider(id: "nonexistent_provider", targetDimension: 512, allowFallback: true)

        // Should fall back to nl_embedding
        XCTAssertEqual(service.providerId, "nl_embedding", "Unknown provider should fall back to nl_embedding")
    }

    func testEmbeddingServiceForProviderWithoutFallback() {
        // Request nl_embedding specifically - should always work
        let service = EmbeddingService.forProvider(id: "nl_embedding", targetDimension: 512, allowFallback: false)
        XCTAssertEqual(service.providerId, "nl_embedding")
    }

    func testEmbeddingServiceIsAvailable() {
        let service = EmbeddingService.forProvider(id: "nl_embedding", targetDimension: 512)
        XCTAssertTrue(service.isAvailable, "NLEmbedding should always be available")
    }

    // MARK: - Batch Embedding Tests

    func testEmbeddingServiceBatchEmbedding() async throws {
        let provider = MockEmbeddingProvider(dimension: 512)
        let service = EmbeddingService(provider: provider, providerId: "mock", targetDimension: 512)

        let texts = ["First text", "Second text", "Third text"]
        let embeddings = try await service.generateEmbeddings(for: texts)

        XCTAssertEqual(embeddings.count, 3, "Should return one embedding per text")
        for embedding in embeddings {
            XCTAssertEqual(embedding.count, 512, "Each embedding should have correct dimension")
        }
    }

    // MARK: - NLContextualEmbedding Specific Tests (iOS 17+)

    @available(iOS 17.0, *)
    func testNLContextualEmbeddingProviderPoolingStrategies() async throws {
        // Test that different pooling strategies produce valid embeddings
        let meanProvider = NLContextualEmbeddingProvider(language: .english, pooling: .mean)
        let clsProvider = NLContextualEmbeddingProvider(language: .english, pooling: .cls)

        // Skip if assets not available (CI environment)
        guard meanProvider.isAvailable else {
            throw XCTSkip("NLContextualEmbedding assets not available")
        }

        let text = "The quick brown fox jumps over the lazy dog."

        let meanEmbedding = try await meanProvider.embed(text: text)
        let clsEmbedding = try await clsProvider.embed(text: text)

        XCTAssertGreaterThan(meanEmbedding.count, 0, "Mean pooling should produce non-empty embedding")
        XCTAssertGreaterThan(clsEmbedding.count, 0, "CLS pooling should produce non-empty embedding")

        // Different pooling strategies should produce different results
        XCTAssertNotEqual(meanEmbedding, clsEmbedding, "Different pooling should produce different embeddings")
    }

    @available(iOS 17.0, *)
    func testNLContextualEmbeddingProviderDimension() async throws {
        let provider = NLContextualEmbeddingProvider(language: .english, pooling: .mean)

        guard provider.isAvailable else {
            throw XCTSkip("NLContextualEmbedding assets not available")
        }

        // Dimension should be reasonable (typically 512 or 768)
        XCTAssertGreaterThanOrEqual(provider.dimension, 384)
        XCTAssertLessThanOrEqual(provider.dimension, 1024)
    }

    @available(iOS 17.0, *)
    func testNLContextualEmbeddingProviderEmptyTextHandling() async throws {
        let provider = NLContextualEmbeddingProvider(language: .english, pooling: .mean)

        guard provider.isAvailable else {
            throw XCTSkip("NLContextualEmbedding assets not available")
        }

        // Empty text should be handled gracefully (returns zeros or throws)
        let embedding = try await provider.embed(text: "   ")
        XCTAssertEqual(embedding.count, provider.dimension, "Should return zero vector for whitespace")
    }

    @available(iOS 17.0, *)
    func testNLContextualEmbeddingProviderBatchConsistency() async throws {
        let provider = NLContextualEmbeddingProvider(language: .english, pooling: .mean)

        guard provider.isAvailable else {
            throw XCTSkip("NLContextualEmbedding assets not available")
        }

        let text = "Consistency test sentence."

        // Same text should produce same embedding
        let embedding1 = try await provider.embed(text: text)
        let embedding2 = try await provider.embed(text: text)

        XCTAssertEqual(embedding1, embedding2, "Same text should produce identical embeddings")
    }
}

private struct MockEmbeddingProvider: EmbeddingProvider {
    let dimension: Int
    var isAvailable: Bool { true }

    func embed(text _: String) async throws -> [Float] {
        Array(repeating: Float(0.25), count: dimension)
    }

    func embedBatch(texts: [String]) async throws -> [[Float]] {
        let vector = try await embed(text: "")
        return Array(repeating: vector, count: texts.count)
    }
}
