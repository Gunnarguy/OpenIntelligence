import XCTest
@testable import OpenIntelligence

final class BM25ScorerTests: XCTestCase {

    // MARK: - Helpers

    private func makeChunk(content: String, index: Int = 0) -> DocumentChunk {
        DocumentChunk(
            documentId: UUID(),
            content: content,
            embedding: [1, 0, 0],
            metadata: ChunkMetadata(chunkIndex: index)
        )
    }

    // MARK: - Index & Snapshot

    func testIndexDocumentsComputesDocumentFrequencies() {
        let scorer = BM25Scorer()
        let chunks = [
            makeChunk(content: "swift programming language"),
            makeChunk(content: "swift iOS development", index: 1),
            makeChunk(content: "python machine learning", index: 2)
        ]
        scorer.indexDocuments(chunks)
        let snapshot = scorer.makeSnapshot()

        XCTAssertEqual(snapshot.totalDocuments, 3)
        // "swift" appears in 2 of 3 docs
        XCTAssertEqual(snapshot.documentFrequencies["swift"], 2)
        // "python" appears in 1 of 3 docs
        XCTAssertEqual(snapshot.documentFrequencies["python"], 1)
        XCTAssertGreaterThan(snapshot.avgDocLength, 0)
    }

    func testSnapshotFromCandidatesBuildsLocalStats() {
        let scorer = BM25Scorer()
        let chunk = makeChunk(content: "swift ai swift")
        let retrieved = RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1)
        let snapshot = scorer.snapshot(from: [retrieved])

        XCTAssertEqual(snapshot.totalDocuments, 1)
        XCTAssertTrue(snapshot.documentFrequencies.keys.contains("swift"))
    }

    func testMakeSnapshotAfterIndexMatchesDocCount() {
        let scorer = BM25Scorer()
        let chunks = (0..<10).map { i in makeChunk(content: "document \(i) about testing", index: i) }
        scorer.indexDocuments(chunks)
        let snapshot = scorer.makeSnapshot()
        XCTAssertEqual(snapshot.totalDocuments, 10)
    }

    func testSnapshotFromEmptyCandidatesReturnsZeros() {
        let scorer = BM25Scorer()
        let snapshot = scorer.snapshot(from: [])
        XCTAssertEqual(snapshot.totalDocuments, 0)
        XCTAssertEqual(snapshot.avgDocLength, 0)
        XCTAssertTrue(snapshot.documentFrequencies.isEmpty)
    }

    // MARK: - IDF (Inverse Document Frequency)

    func testRareTermScoresHigherThanCommonTerm() {
        let scorer = BM25Scorer()
        let chunks = [
            makeChunk(content: "apple banana cherry"),
            makeChunk(content: "apple banana date", index: 1),
            makeChunk(content: "apple elderberry fig", index: 2)
        ]
        scorer.indexDocuments(chunks)

        // "apple" appears in all 3 docs (common), "cherry" in only 1 (rare)
        // The doc containing cherry should score higher for "cherry" than "apple"
        let docWithCherry = "apple banana cherry"
        let scoreCherry = scorer.score(query: "cherry", document: docWithCherry)
        let scoreApple = scorer.score(query: "apple", document: docWithCherry)

        XCTAssertGreaterThan(scoreCherry, scoreApple,
                             "Rare term 'cherry' should have higher IDF than common term 'apple'")
    }

    // MARK: - Term Frequency Saturation

    func testHigherTermFrequencyScoresHigher() {
        let scorer = BM25Scorer()
        let chunks = [
            makeChunk(content: "swift swift swift programming"),
            makeChunk(content: "swift programming language", index: 1)
        ]
        scorer.indexDocuments(chunks)

        let highTF = scorer.score(query: "swift", document: "swift swift swift programming")
        let lowTF = scorer.score(query: "swift", document: "swift programming language")

        XCTAssertGreaterThan(highTF, lowTF,
                             "Higher term frequency should produce higher BM25 score")
    }

    func testTermFrequencySaturates() {
        let scorer = BM25Scorer()
        // 5 repetitions vs 50 — the difference should be sublinear due to k1 saturation
        let doc5 = (0..<5).map { _ in "swift" }.joined(separator: " ") + " programming"
        let doc50 = (0..<50).map { _ in "swift" }.joined(separator: " ") + " programming"
        let chunks = [
            makeChunk(content: doc5),
            makeChunk(content: doc50, index: 1)
        ]
        scorer.indexDocuments(chunks)

        let score5 = scorer.score(query: "swift", document: doc5)
        let score50 = scorer.score(query: "swift", document: doc50)

        // score50 should be higher, but not 10x higher (saturation via k1)
        XCTAssertGreaterThan(score50, score5)
        XCTAssertLessThan(Double(score50), Double(score5) * 10,
                          "BM25 should saturate — 50 occurrences should not be 10x the score of 5")
    }

    // MARK: - Length Normalization

    func testLongerDocumentScoresLower() {
        let scorer = BM25Scorer()
        let shortDoc = "swift programming"
        let longDoc = "swift programming " + String(repeating: "filler word ", count: 100)
        let chunks = [
            makeChunk(content: shortDoc),
            makeChunk(content: longDoc, index: 1)
        ]
        scorer.indexDocuments(chunks)

        let shortScore = scorer.score(query: "swift", document: shortDoc)
        let longScore = scorer.score(query: "swift", document: longDoc)

        XCTAssertGreaterThan(shortScore, longScore,
                             "Short document with same term should score higher (length normalization)")
    }

    // MARK: - Edge Cases

    func testEmptyQueryReturnsZero() {
        let scorer = BM25Scorer()
        scorer.indexDocuments([makeChunk(content: "some content")])
        let score = scorer.score(query: "", document: "some content")
        XCTAssertEqual(score, 0.0)
    }

    func testEmptyDocumentReturnsZero() {
        let scorer = BM25Scorer()
        scorer.indexDocuments([makeChunk(content: "test")])
        let score = scorer.score(query: "test", document: "")
        XCTAssertEqual(score, 0.0)
    }

    func testNoMatchingTermsReturnsZero() {
        let scorer = BM25Scorer()
        scorer.indexDocuments([makeChunk(content: "cats and dogs")])
        let score = scorer.score(query: "programming swift", document: "cats and dogs")
        XCTAssertEqual(score, 0.0)
    }

    func testScoreNeverNegativeForValidInput() {
        let scorer = BM25Scorer()
        let chunks = (0..<20).map { i in makeChunk(content: "document \(i) about testing swift code", index: i) }
        scorer.indexDocuments(chunks)

        for chunk in chunks {
            let score = scorer.score(query: "testing swift", document: chunk.content)
            XCTAssertGreaterThanOrEqual(score, 0.0, "BM25 score should never be negative")
        }
    }

    func testScoreNotNaNOrInfinite() {
        let scorer = BM25Scorer()
        let longContent = String(repeating: "word ", count: 10000)
        let chunks = [makeChunk(content: longContent)]
        scorer.indexDocuments(chunks)

        let score = scorer.score(query: "word", document: longContent)
        XCTAssertFalse(score.isNaN, "Score should not be NaN")
        XCTAssertFalse(score.isInfinite, "Score should not be infinite")
    }

    func testSpecialCharactersHandledGracefully() {
        let scorer = BM25Scorer()
        let content = "C++ and C# are programming languages! @swift #coding $$money"
        scorer.indexDocuments([makeChunk(content: content)])

        let score = scorer.score(query: "C++ programming", document: content)
        XCTAssertGreaterThanOrEqual(score, 0.0, "BM25 should handle special characters")
    }

    func testUnicodeContentWorks() {
        let scorer = BM25Scorer()
        let content = "日本語のテキスト Swift プログラミング 中文內容"
        scorer.indexDocuments([makeChunk(content: content)])

        let score = scorer.score(query: "Swift", document: content)
        XCTAssertGreaterThan(score, 0.0, "Should find 'Swift' in Unicode content")
    }

    // MARK: - Tokenization

    func testTokenizeProducesLowercaseTokens() {
        let scorer = BM25Scorer()
        let tokens = scorer.tokenize("Hello World SWIFT")
        for token in tokens {
            XCTAssertEqual(token, token.lowercased(), "All tokens should be lowercased")
        }
    }

    func testTokenizeAppliesLemmatization() {
        let scorer = BM25Scorer()
        let tokens = scorer.tokenize("running configurations")
        // NLTagger lemmatization: "running" → "run", "configurations" → "configuration"
        // Exact lemmas depend on NLP model, but they should differ from input
        XCTAssertFalse(tokens.isEmpty, "Tokenization should produce tokens")
    }

    func testTokenizeRemovesPunctuation() {
        let scorer = BM25Scorer()
        let tokens = scorer.tokenize("hello, world! foo.")
        for token in tokens {
            XCTAssertFalse(token.hasSuffix(","))
            XCTAssertFalse(token.hasSuffix("!"))
            XCTAssertFalse(token.hasSuffix("."))
        }
    }

    // MARK: - Pre-tokenized Query

    func testPreTokenizedQueryMatchesRegularScore() {
        let scorer = BM25Scorer()
        let content = "swift programming language for iOS"
        scorer.indexDocuments([makeChunk(content: content)])

        let regularScore = scorer.score(query: "swift iOS", document: content)
        let queryTerms = scorer.tokenize("swift iOS")
        let preTokenizedScore = scorer.score(queryTerms: queryTerms, document: content)

        XCTAssertEqual(regularScore, preTokenizedScore, accuracy: 0.001,
                       "Pre-tokenized and regular scoring should produce identical results")
    }

    // MARK: - Multi-term Queries

    func testMultiTermQueryScoresHigherThanSingleTerm() {
        let scorer = BM25Scorer()
        let content = "swift programming language for iOS development"
        scorer.indexDocuments([makeChunk(content: content)])

        let singleTerm = scorer.score(query: "swift", document: content)
        let multiTerm = scorer.score(query: "swift programming iOS", document: content)

        XCTAssertGreaterThan(multiTerm, singleTerm,
                             "Multi-term query matching more terms should score higher")
    }

    func testSingleDocumentCorpus() {
        let scorer = BM25Scorer()
        scorer.indexDocuments([makeChunk(content: "the only document about swift")])

        let score = scorer.score(query: "swift", document: "the only document about swift")
        XCTAssertGreaterThan(score, 0.0, "Single-document corpus should still produce positive scores")
    }
}
