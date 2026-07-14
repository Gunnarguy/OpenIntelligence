import XCTest
import NaturalLanguage
@testable import OpenIntelligenceEngine

final class NLEmbeddingProviderTests: XCTestCase {

    // "zxx" (no linguistic content) has no NLEmbedding word-embedding assets on any
    // platform, so the provider's embedding is nil and embed(text:) deterministically
    // takes the hash-fallback path containing the magnitude/normalization code.
    private func makeFallbackProvider() -> NLEmbeddingProvider {
        NLEmbeddingProvider(language: NLLanguage(rawValue: "zxx"))
    }

    // Independent reference implementation of the fallback embedding using a two-pass
    // magnitude (map + reduce); its left-to-right Float accumulation order matches the
    // provider's single-pass reduce, so results must agree exactly.
    private func referenceFallbackEmbedding(for text: String, dimension: Int = 512) -> [Float] {
        var vec = Array(repeating: Float(0.0), count: dimension)
        let normalized = text.lowercased()
        for (index, char) in normalized.unicodeScalars.prefix(256).enumerated() {
            if index < dimension {
                vec[index] = Float(char.value % 256) / 128.0 - 1.0
            }
        }
        if dimension > 256 {
            vec[256] = Float(min(text.count, 1000)) / 1000.0
        }
        if dimension > 261 {
            let wordCount = normalized.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            vec[261] = Float(min(wordCount, 100)) / 100.0
        }
        if dimension > 266 {
            let hasNumbers = normalized.rangeOfCharacter(from: .decimalDigits) != nil
            vec[266] = hasNumbers ? 1.0 : -1.0
        }
        let magnitude = sqrt(vec.map { $0 * $0 }.reduce(0, +))
        if magnitude > 0 {
            vec = vec.map { $0 / magnitude }
        }
        return vec
    }

    private func l2Magnitude(_ vector: [Float]) -> Float {
        sqrt(vector.reduce(0.0) { $0 + $1 * $1 })
    }

    func testFallbackEmbeddingHasUnitMagnitude() async throws {
        let provider = makeFallbackProvider()
        let embedding = try await provider.embed(text: "hello world")
        XCTAssertEqual(embedding.count, provider.dimension)
        XCTAssertEqual(l2Magnitude(embedding), 1.0, accuracy: 1e-5)
    }

    func testFallbackEmbeddingMatchesTwoPassReferenceImplementation() async throws {
        let provider = makeFallbackProvider()
        let text = "The quick brown fox jumps over 13 lazy dogs"
        let embedding = try await provider.embed(text: text)
        let expected = referenceFallbackEmbedding(for: text)
        XCTAssertEqual(embedding.count, expected.count)
        for (index, value) in embedding.enumerated() {
            XCTAssertEqual(value, expected[index], "Mismatch at dimension \(index)")
        }
    }

    func testSingleCharacterTextProducesKnownNormalizedVector() async throws {
        let provider = makeFallbackProvider()
        let embedding = try await provider.embed(text: "a")

        // Pre-normalization components for "a" (scalar 97, 1 char, 1 word, no digits):
        // vec[0] = 97/128 - 1, vec[256] = 0.001, vec[261] = 0.01, vec[266] = -1.0;
        // every other component is +0.0, which is an additive identity, so the
        // magnitude reduces to these four terms in index order.
        let v0: Float = Float(97 % 256) / 128.0 - 1.0
        let v256: Float = 0.001
        let v261: Float = 0.01
        let v266: Float = -1.0
        let magnitude = sqrt(v0 * v0 + v256 * v256 + v261 * v261 + v266 * v266)

        XCTAssertEqual(embedding[0], v0 / magnitude, accuracy: 1e-6)
        XCTAssertEqual(embedding[256], v256 / magnitude, accuracy: 1e-6)
        XCTAssertEqual(embedding[261], v261 / magnitude, accuracy: 1e-6)
        XCTAssertEqual(embedding[266], v266 / magnitude, accuracy: 1e-6)
        XCTAssertEqual(embedding[1], 0.0)
        XCTAssertEqual(l2Magnitude(embedding), 1.0, accuracy: 1e-5)
    }

    func testLongTextWithMaximalFeatureValuesIsStillNormalized() async throws {
        let provider = makeFallbackProvider()
        // Over 1000 characters saturates the length feature at 1.0 and fills all 256
        // character-frequency dimensions: the largest magnitude reachable through the
        // public API, since every fallback feature is bounded to [-1, 1].
        let text = String(repeating: "abcdefgh12345678 ", count: 80)
        let embedding = try await provider.embed(text: text)
        XCTAssertEqual(embedding.count, provider.dimension)
        XCTAssertEqual(l2Magnitude(embedding), 1.0, accuracy: 1e-4)
        for value in embedding {
            XCTAssertFalse(value.isNaN)
            XCTAssertFalse(value.isInfinite)
        }
    }

    func testFallbackEmbeddingIsDeterministicAcrossCalls() async throws {
        let provider = makeFallbackProvider()
        let first = try await provider.embed(text: "determinism check 42")
        let second = try await provider.embed(text: "determinism check 42")
        XCTAssertEqual(first, second)
    }

    func testWhitespaceOnlyInputThrowsEmptyInput() async {
        let provider = makeFallbackProvider()
        do {
            _ = try await provider.embed(text: "   \n\t ")
            XCTFail("Expected EmbeddingError.emptyInput")
        } catch let error as EmbeddingError {
            guard case .emptyInput = error else {
                XCTFail("Expected .emptyInput, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected EmbeddingError.emptyInput, got \(error)")
        }
    }
}
