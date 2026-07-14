import Foundation
import XCTest

@testable import OpenIntelligenceEngine

final class LibraryIntelligenceCenterVarianceTests: XCTestCase {
    // MARK: - Formula characterization

    // Mirrors the population-variance expression in
    // LibraryIntelligenceCenter.analyzeSemanticComplexity: a two-pass
    // mean-then-squared-deviations left fold divided by n (not n - 1).
    private func foldedVariance(_ lengths: [Int], mean: Double) -> Double {
        lengths.reduce(0.0) { $0 + pow(Double($1) - mean, 2) }
            / Double(lengths.count)
    }

    // Intermediate-array form of the same fold; must remain bit-identical
    // to foldedVariance for every input.
    private func mappedVariance(_ lengths: [Int], mean: Double) -> Double {
        lengths.map { pow(Double($0) - mean, 2) }
            .reduce(0, +) / Double(lengths.count)
    }

    private func mean(of lengths: [Int]) -> Double {
        Double(lengths.reduce(0, +)) / Double(lengths.count)
    }

    func testFoldedAndMappedFormsAreBitIdentical() {
        let cases: [[Int]] = [
            [1],
            [3, 5, 7],
            [10, 10, 10],
            [2, 4, 4, 4, 5, 5, 7, 9],
            [1_000_001, 999_999, 1_000_000, 1_000_002],
            [123_456_789, 123_456_789, 123_456_789, 123_456_789, 123_456_789],
        ]
        for lengths in cases {
            let m = mean(of: lengths)
            XCTAssertEqual(
                foldedVariance(lengths, mean: m).bitPattern,
                mappedVariance(lengths, mean: m).bitPattern,
                "Floating-point divergence for \(lengths)"
            )
        }
    }

    func testKnownPopulationVarianceValues() {
        // Deviations, squares, and sums are integer-exact in Double, so
        // these comparisons are exact.
        XCTAssertEqual(foldedVariance([2, 4, 4, 4, 5, 5, 7, 9], mean: 5.0), 4.0)
        XCTAssertEqual(foldedVariance([3, 5, 7], mean: 5.0), 8.0 / 3.0)
        // Sample variance of [3, 5, 7] would be 4.0; the divisor must stay n.
        XCTAssertNotEqual(foldedVariance([3, 5, 7], mean: 5.0), 4.0)
    }

    func testSingleElementVarianceIsZero() {
        XCTAssertEqual(foldedVariance([42], mean: 42.0), 0.0)
    }

    func testLargeMagnitudeConstantInputHasExactlyZeroVariance() {
        // The two-pass mean-then-deviations form is exact here; a one-pass
        // E[x^2] - E[x]^2 rewrite loses precision because x^2 > 2^53.
        let lengths = [Int](repeating: 123_456_789, count: 5)
        XCTAssertEqual(foldedVariance(lengths, mean: 123_456_789.0), 0.0)
    }

    // MARK: - Production path via analyzeLibrary

    private func chunk(_ content: String) -> DocumentChunk {
        DocumentChunk(
            documentId: UUID(),
            content: content,
            embedding: [],
            metadata: ChunkMetadata(chunkIndex: 0)
        )
    }

    private func semanticComplexity(ofCorpus text: String) async -> Double {
        let center = LibraryIntelligenceCenter()
        let chunks = text.isEmpty ? [] : [chunk(text)]
        let report = await center.analyzeLibrary(documents: [], chunks: chunks)
        return report.corpus.semanticComplexity
    }

    func testSemanticComplexityIsZeroForEmptyCorpus() async {
        let complexity = await semanticComplexity(ofCorpus: "")
        XCTAssertEqual(complexity, 0.0)
    }

    func testSemanticComplexityForSingleSentence() async {
        // One 4-word sentence: variance 0, one clause, lengthScore 4/30.
        let complexity = await semanticComplexity(ofCorpus: "Alpha beta gamma delta.")
        XCTAssertEqual(complexity, (4.0 / 30.0) / 3.0, accuracy: 1e-12)
    }

    func testSemanticComplexityUsesPopulationVariance() async {
        // Sentence word counts 3/5/7: mean 5, population variance 8/3.
        let text =
            "Alpha beta gamma. One two three four five. Red green blue yellow purple orange pink."
        let complexity = await semanticComplexity(ofCorpus: text)
        let expected = (5.0 / 30.0 + 0.0 + min(1.0, (8.0 / 3.0).squareRoot() / 10.0)) / 3.0
        XCTAssertEqual(complexity, expected, accuracy: 1e-12)
        // Sample variance (n - 1) would give stdDev 2.0 and a distinctly larger score.
        let sampleVarianceValue = (5.0 / 30.0 + 0.0 + 0.2) / 3.0
        XCTAssertNotEqual(complexity, sampleVarianceValue, accuracy: 1e-3)
    }

    func testSemanticComplexityZeroVarianceForEqualLengthSentences() async {
        // Two 6-word sentences with 2 and 1 clause markers: variance 0,
        // lengthScore 6/30, clauseScore (2.5 - 1) / 2.
        let text = "Alpha beta, gamma delta; epsilon zeta. One two three, four five six."
        let complexity = await semanticComplexity(ofCorpus: text)
        let expected = (6.0 / 30.0 + 0.75 + 0.0) / 3.0
        XCTAssertEqual(complexity, expected, accuracy: 1e-12)
    }
}
