import XCTest

@testable import OpenIntelligenceEngine

/// Pins the intent classifier's treatment of short queries.
///
/// `isExtractiveFirst` is the single gate on both the ExtractiveQA path and the source-only
/// verifier, and `.lookup` is the intent that opens it. A query landing on `.lookup` by accident is
/// therefore not a cosmetic misclassification — it routes a question into machinery built for
/// extracting spec values, and on device 2026-08-19 that reduced 2,305 words of evidence to an
/// eight-word answer after 145 seconds.
final class AnswerIntentClassificationTests: XCTestCase {

    private let service = QueryEnhancementService()

    // MARK: - The regression this file exists for

    /// The exact query from the 2026-08-19 device capture. Four words, matches no lookup pattern,
    /// and was classified `.lookup` purely because `words.count <= 5`.
    func testShortConceptualQuestionIsNotTreatedAsAnExtractiveLookup() {
        let intent = service.classifyAnswerIntent("What regulates anxiety-like actions?")
        XCTAssertFalse(
            intent.isExtractiveFirst,
            "A four-word mechanism question must not open the extractive gate; it was classified \(intent)."
        )
    }

    /// Length alone must not imply extractive intent for any of these.
    func testShortMechanismQuestionsAreNotExtractive() {
        let queries = [
            "What regulates anxiety-like actions?",
            "What causes depression?",
            "Why does serotonin matter?",
            "What influences dopamine release?",
        ]
        for query in queries {
            XCTAssertFalse(
                service.classifyAnswerIntent(query).isExtractiveFirst,
                "\"\(query)\" should not be extractive-first."
            )
        }
    }

    // MARK: - What must keep working

    /// Genuine spec lookups are caught by pattern, not by word count, so they are unaffected.
    func testSpecLookupPatternsStillClassifyAsLookup() {
        XCTAssertEqual(service.classifyAnswerIntent("What type of oil should I use?"), .lookup)
        XCTAssertEqual(service.classifyAnswerIntent("engine oil capacity"), .lookup)
        XCTAssertEqual(service.classifyAnswerIntent("recommended tire pressure"), .lookup)
    }

    /// The other intent branches are untouched by this change.
    func testOtherIntentsAreUnaffected() {
        XCTAssertEqual(service.classifyAnswerIntent("How do I replace the filter?"), .procedure)
        // Deliberately "overview" and not "summary": `computePatterns` contains "sum" and runs at
        // priority 2, so "summary" and "summarize" substring-match as arithmetic aggregation and
        // never reach the summarize branch at priority 5. That is a separate, pre-existing defect,
        // pinned by `testSummaryWordsAreShadowedByTheComputeBranch_knownDefect` below.
        XCTAssertEqual(service.classifyAnswerIntent("Give me an overview of the document"), .summarize)
        XCTAssertEqual(service.classifyAnswerIntent("Compare dopamine versus serotonin"), .compare)
    }

    /// A separate pre-existing defect, found while writing these tests and pinned rather than
    /// fixed, because it was outside the three changes that were asked for.
    ///
    /// `computePatterns` (priority 2) contains the bare substring "sum", so every query containing
    /// "summary", "summarize", "consume", "presumably" or "assume" is classified as arithmetic
    /// aggregation before the summarize branch at priority 5 is ever reached. The strings
    /// "summarize" and "summary" in `summarizePatterns` are consequently unreachable.
    func testSummaryWordsAreShadowedByTheComputeBranch_knownDefect() {
        XCTAssertEqual(service.classifyAnswerIntent("Give me a summary of the document"), .compute)
        XCTAssertEqual(service.classifyAnswerIntent("Summarize the paper for me"), .compute)
    }

    /// The known remaining hole, pinned deliberately rather than left implicit.
    ///
    /// `lookupStarters` classifies *any* query beginning with "what" as `.lookup`, so a mechanism
    /// question phrased outside the verb list above still opens the extractive gate. Narrowing that
    /// rule reroutes a large amount of traffic and is a separate decision; this asserts the current
    /// behaviour so that changing it is a deliberate act with a failing test attached.
    func testBareWhatPrefixStillClassifiesAsLookup_knownLimitation() {
        XCTAssertEqual(service.classifyAnswerIntent("What underlies anxiety-like actions?"), .lookup)
    }

    /// Unclassified queries default to `.investigate` whatever their length, which is the whole
    /// point: the classifier should decline to guess rather than guess extractive.
    func testUnclassifiedQueriesDefaultToInvestigateRegardlessOfLength() {
        XCTAssertEqual(service.classifyAnswerIntent("anxiety-like actions"), .investigate)
        XCTAssertEqual(service.classifyAnswerIntent("dopamine and serotonin timescales"), .investigate)
    }
}
