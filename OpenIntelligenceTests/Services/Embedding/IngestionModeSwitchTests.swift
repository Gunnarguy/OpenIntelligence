//
//  IngestionModeSwitchTests.swift
//  OpenIntelligenceTests
//
//  Ingestion mode records the compute units it wants and the model switches on the next embed (5.7). The switch
//  used to reload the 43 MiB model where it was called, on the main actor, which held the main thread for 2.36 s
//  at the start of an import on the owner's iPhone. These pin that embeddings stay the same through the switch.
//

import XCTest

@testable import OpenIntelligence

final class IngestionModeSwitchTests: XCTestCase {
    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        return dot / max((na.squareRoot() * nb.squareRoot()), .leastNonzeroMagnitude)
    }

    func testEmbeddingsAgreeBeforeDuringAndAfterIngestionMode() async throws {
        let provider = CoreMLSentenceEmbeddingProvider()
        let text = "The security deposit is two months of rent."
        let before = try await provider.embed(text: text)
        try XCTSkipIf(before.allSatisfy { $0 == 0 }, "The embedding model returned zeros here.")

        provider.enableIngestionMode()
        let during = try await provider.embed(text: text)
        provider.disableIngestionMode()
        let after = try await provider.embed(text: text)

        XCTAssertEqual(during.count, 384)
        XCTAssertGreaterThan(Self.cosine(before, during), 0.99)
        XCTAssertGreaterThan(Self.cosine(before, after), 0.99)
    }

    func testSwitchingWithNothingEmbeddedStillEmbeds() async throws {
        let provider = CoreMLSentenceEmbeddingProvider()
        provider.enableIngestionMode()
        provider.disableIngestionMode()
        let vector = try await provider.embed(text: "Quiet hours are 10 p.m. to 7 a.m.")
        XCTAssertEqual(vector.count, 384)
    }
}
