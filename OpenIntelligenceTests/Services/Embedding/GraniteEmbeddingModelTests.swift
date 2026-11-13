//
//  GraniteEmbeddingModelTests.swift
//  OpenIntelligenceTests
//
//  Pins the bundled embedder (IBM granite-embedding-small-english-r2 since 5.8) to the Hugging Face model it was built
//  from (`scripts/build_embedding_model.py`), and the per-device record that tells a model change apart (5.8).
//

import XCTest

@testable import OpenIntelligence

final class GraniteEmbeddingModelTests: XCTestCase {
    /// From the Hugging Face model in float32 at revision 2ab6fa8e (transformers 5.22.2, 2026-11-12): the question's
    /// token ids, its first four vector values, and two cosines.
    private let question = "How many days notice ends the lease?"
    private let lease =
        "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by certified mail."
    private let kitchen = "The kitchen was renovated in 2019 with quartz counters and a new range hood."
    private let questionIds = [50281, 2347, 1142, 1897, 4366, 7637, 253, 16959, 32, 50282]
    private let questionFirstFour: [Float] = [0.0069, -0.0186, -0.0101, 0.0506]

    private func provider() async throws -> CoreMLSentenceEmbeddingProvider {
        let provider = CoreMLSentenceEmbeddingProvider()
        guard provider.isAvailable else { throw XCTSkip("embedding model not bundled") }
        // The tokenizer loads asynchronously; countTokens falls back to an estimate until it has.
        for _ in 0..<100 where provider.countTokens(question) != questionIds.count {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return provider
    }

    func testTheTokenizerCountsTheModelsOwnTokens() async throws {
        let provider = try await provider()
        XCTAssertEqual(provider.countTokens(question), questionIds.count)
    }

    func testVectorsMatchTheReference() async throws {
        let provider = try await provider()
        let q = try await provider.embed(text: question)
        XCTAssertEqual(q.count, 384)
        let norm = sqrt(q.reduce(0) { $0 + $1 * $1 })
        XCTAssertEqual(norm, 1, accuracy: 1e-3)
        for (value, expected) in zip(q.prefix(4), questionFirstFour) {
            XCTAssertEqual(value, expected, accuracy: 0.003)
        }
        func cosine(_ a: [Float], _ b: [Float]) -> Float { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }
        let l = try await provider.embed(text: lease)
        let k = try await provider.embed(text: kitchen)
        XCTAssertEqual(cosine(q, l), 0.9388, accuracy: 0.01)
        XCTAssertEqual(cosine(q, k), 0.7128, accuracy: 0.01)
        XCTAssertGreaterThan(cosine(q, l), cosine(q, k))
    }

    func testTheIdentityNamesGranite() {
        let provider = CoreMLSentenceEmbeddingProvider()
        XCTAssertTrue(provider.modelRevision.hasPrefix("granite-embedding-small-english-r2@"))
        XCTAssertEqual(provider.poolingRecipe, "cls-in-graph/l2")
        XCTAssertEqual(EmbeddingProviderDefaults.preferredSentenceProviderId, EmbeddingProviderDefaults.coreML)
        if #available(iOS 27.0, macOS 27.0, *) {
            XCTAssertFalse(CoreAISentenceEmbeddingProvider.shared.isAvailable)
        }
    }

    func testALibraryWithNoRecordCountsAsAModelChange() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "emr-\(UUID().uuidString)"))
        let library = UUID()
        let live = "granite-embedding-small-english-r2@2ab6fa8e/coreml-len256-len512"
        XCTAssertTrue(EmbeddingModelRecord.modelChanged(for: library, live: live, defaults: defaults))
        EmbeddingModelRecord.recordIfAbsent(live, for: library, defaults: defaults)
        XCTAssertFalse(EmbeddingModelRecord.modelChanged(for: library, live: live, defaults: defaults))
        EmbeddingModelRecord.recordIfAbsent("another", for: library, defaults: defaults)
        XCTAssertEqual(EmbeddingModelRecord.recorded(for: library, defaults: defaults), live)
        XCTAssertTrue(EmbeddingModelRecord.modelChanged(for: library, live: "a later model", defaults: defaults))
    }

    func testTheImportCacheNamesTheModel() {
        let a = EmbeddingService.embeddingCacheName(
            for: ["x"], provider: "coreml_sentence_embedding", dimension: 384, modelRevision: "MiniLM")
        let b = EmbeddingService.embeddingCacheName(
            for: ["x"], provider: "coreml_sentence_embedding", dimension: 384, modelRevision: "Granite")
        XCTAssertNotEqual(a, b)
    }
}
