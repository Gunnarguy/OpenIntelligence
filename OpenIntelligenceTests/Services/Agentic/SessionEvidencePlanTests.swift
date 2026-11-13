//
//  SessionEvidencePlanTests.swift
//  OpenIntelligenceTests
//
//  A Deep Think chain session's evidence was sized in characters and went through sentence
//  extraction. From 5.6 it is sized in tokens against the window the device reports, and read whole
//  when it fits. These pin the arithmetic, and the two promises the plan makes: the chain never
//  plans more windows than it did, and a pool that took two sessions still takes two.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class SessionEvidencePlanTests: XCTestCase {
    private func budget(_ window: Int, question: Int, first: Bool) -> Int {
        SessionEvidencePlan.evidenceTokenBudget(
            contextSize: window, outputReserve: 700,
            carriedChars: SessionEvidencePlan.carriedChars(questionLength: question, isFirstSession: first))
    }

    private func window(
        _ start: Int, _ counts: [Int], budget: Int, cap: Int, legacy: Int = 4
    )
        -> SessionEvidencePlan.Window
    {
        SessionEvidencePlan.window(start: start, tokenCounts: counts, budget: budget, cap: cap, legacyCount: legacy)
    }

    // MARK: - Budget

    func testCarriedTextCountsTheQuestionAndWhatLaterSessionsAdd() {
        XCTAssertEqual(SessionEvidencePlan.carriedChars(questionLength: 100, isFirstSession: true), 100)
        // Findings (1,200), the question twice, and the objective lines (400).
        XCTAssertEqual(SessionEvidencePlan.carriedChars(questionLength: 100, isFirstSession: false), 1800)
        XCTAssertEqual(SessionEvidencePlan.carriedChars(questionLength: -5, isFirstSession: true), 0)
    }

    func testAChainsFirstSessionOnASmallWindow() {
        // 4,096 - 700 (answer) - 40 (a 100-character question at 2.5 a token) - 400 - 256.
        XCTAssertEqual(budget(4096, question: 100, first: true), 2700)
    }

    func testLaterSessionsLeaveRoomForFindings() {
        // 1,800 carried characters at 2.5 a token is 720.
        XCTAssertEqual(budget(4096, question: 100, first: false), 2020)
    }

    func testALongQuestionTakesItsRoomFromTheEvidence() {
        XCTAssertLessThan(budget(4096, question: 600, first: false), budget(4096, question: 100, first: false))
        // 1,200 + 1,200 + 400 = 2,800 characters, 1,120 tokens.
        XCTAssertEqual(budget(4096, question: 600, first: false), 1620)
    }

    func testALargeWindowStopsAtTheReadingCeiling() {
        // 8,192 leaves 6,116, and the session still reads no more than the ceiling.
        XCTAssertEqual(budget(8192, question: 100, first: false), SessionEvidencePlan.readingCeilingTokens)
        XCTAssertEqual(SessionEvidencePlan.readingCeilingTokens, 3200)
    }

    func testAWindowTooSmallForAnythingGivesNoBudget() {
        XCTAssertEqual(budget(1000, question: 100, first: false), 0)
        XCTAssertEqual(
            SessionEvidencePlan.evidenceTokenBudget(contextSize: 0, outputReserve: 0, carriedChars: 0), 0)
    }

    // MARK: - Chunks a session

    func testASmallWindowKeepsTheCountItHad() {
        XCTAssertEqual(SessionEvidencePlan.chainChunkCap(contextSize: 4096, poolSize: 20, legacyCount: 4), 4)
        XCTAssertEqual(SessionEvidencePlan.chainChunkCap(contextSize: 0, poolSize: 20, legacyCount: 4), 4)
    }

    func testALargeWindowReadsUpToSeven() {
        XCTAssertEqual(SessionEvidencePlan.chainChunkCap(contextSize: 8192, poolSize: 20, legacyCount: 4), 7)
        XCTAssertEqual(SessionEvidencePlan.chainChunkCap(contextSize: 8192, poolSize: 9, legacyCount: 4), 5)
    }

    func testAPoolThatTookTwoSessionsStillTakesTwo() {
        // Five to eight chunks were two sessions of four. One session of seven would leave a single
        // insight, which skips the synthesis pass.
        for pool in 5...8 {
            let cap = SessionEvidencePlan.chainChunkCap(contextSize: 8192, poolSize: pool, legacyCount: 4)
            XCTAssertEqual(cap, 4, "pool \(pool)")
            let counts = [Int](repeating: 350, count: pool)
            let first = window(0, counts, budget: 3200, cap: cap)
            XCTAssertEqual(first.end, 4)
            XCTAssertEqual(window(first.end, counts, budget: 3200, cap: cap).end, pool)
        }
        // Four or fewer were one session and stay one.
        XCTAssertEqual(SessionEvidencePlan.chainChunkCap(contextSize: 8192, poolSize: 3, legacyCount: 4), 4)
    }

    // MARK: - Windows

    func testFourChunksAreReadWholeWhenTheyFit() {
        let counts = [Int](repeating: 480, count: 20)
        let join = SessionEvidencePlan.joinOverheadTokens
        XCTAssertEqual(
            window(0, counts, budget: 2020, cap: 4),
            SessionEvidencePlan.Window(end: 4, wholeChunks: true, tokens: 4 * (480 + join)))
    }

    func testChunksTooLargeToFitFourKeepTheOldWindow() {
        // Three fit and the fourth does not. Reading three whole would add a window, so this one
        // stays the old four, sized the old way.
        let counts = [Int](repeating: 540, count: 20)
        XCTAssertEqual(
            window(4, counts, budget: 2020, cap: 4),
            SessionEvidencePlan.Window(end: 8, wholeChunks: false, tokens: 0))
    }

    func testALargeWindowReadsMoreChunksPerSession() {
        // Seven small chunks fit under 3,200 (7 x 354 = 2,478), and seven is the cap.
        let small = window(0, [Int](repeating: 350, count: 20), budget: 3200, cap: 7)
        XCTAssertEqual(small, SessionEvidencePlan.Window(end: 7, wholeChunks: true, tokens: 2478))
        // Chunks with their parent passage run nearer 540 tokens: five fit (2,720), a sixth does not.
        let larger = window(0, [Int](repeating: 540, count: 20), budget: 3200, cap: 7)
        XCTAssertEqual(larger, SessionEvidencePlan.Window(end: 5, wholeChunks: true, tokens: 2720))
    }

    func testTheLastWindowTakesWhatIsLeft() {
        let last = window(16, [Int](repeating: 350, count: 18), budget: 2020, cap: 4)
        XCTAssertEqual(last.end, 18)
        XCTAssertTrue(last.wholeChunks)
    }

    func testPastTheCountedChunksThereIsNoWholeWindow() {
        // Only the first chunks of a large pool are counted. Beyond them the old window applies.
        XCTAssertEqual(
            window(5, [300, 300], budget: 2020, cap: 4),
            SessionEvidencePlan.Window(end: 5, wholeChunks: false, tokens: 0))
    }

    func testTheChainNeverPlansMoreWindowsThanItDid() {
        // The old path reads four chunks a window, so a pool of n takes ceil(n / 4) windows. Walk
        // the pool the way the chain does and count.
        for (budget, window) in [(2020, 4096), (2700, 4096), (3200, 8192)] {
            for size in [120, 350, 450, 500, 540, 600, 900, 3300] {
                for pool in [1, 3, 4, 5, 7, 8, 9, 20, 32] {
                    let cap = SessionEvidencePlan.chainChunkCap(contextSize: window, poolSize: pool, legacyCount: 4)
                    let counts = [Int](repeating: size, count: pool)
                    var offset = 0
                    var windows = 0
                    while offset < pool {
                        let next = self.window(offset, counts, budget: budget, cap: cap)
                        XCTAssertGreaterThan(next.end, offset, "a window must advance")
                        offset = next.end
                        windows += 1
                    }
                    let legacy = Int((Double(pool) / 4).rounded(.up))
                    XCTAssertLessThanOrEqual(windows, legacy, "budget \(budget), chunk size \(size), pool \(pool)")
                    if legacy >= 2 {
                        XCTAssertGreaterThanOrEqual(windows, 2, "budget \(budget), chunk size \(size), pool \(pool)")
                    }
                }
            }
        }
    }

    func testMixedSizesStopAtTheFirstChunkThatDoesNotFit() {
        // 304 + 304 + 1,404 = 2,012 fits; the next 304 does too (2,316); the fifth does not (2,620).
        let mixed = window(0, [300, 300, 1400, 300, 300], budget: 2500, cap: 7, legacy: 2)
        XCTAssertEqual(mixed, SessionEvidencePlan.Window(end: 4, wholeChunks: true, tokens: 2316))
    }

    // MARK: - Text

    func testWholeChunkContextLabelsByGlobalPositionAndKeepsTheText() {
        func chunk(_ text: String, _ document: String) -> RetrievedChunk {
            let metadata = ChunkMetadata(
                chunkIndex: 0, pageNumber: 1, sectionTitle: nil, keywords: [], hasNumericData: false,
                hasListStructure: false, wordCount: text.split(separator: " ").count, characterCount: text.count)
            return RetrievedChunk(
                chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
                similarityScore: 0.9, rank: 1, sourceDocument: document, pageNumber: 1)
        }
        let lease = "Rent is late after 11:59 p.m. on the 5th. A late charge of $75.00 applies on the 6th."
        let rules = "Quiet hours are 10:00 p.m. to 7:00 a.m. every day."
        let chunks = [chunk(lease, "Lease.pdf"), chunk(rules, "Rules.pdf")]
        XCTAssertEqual(SessionEvidencePlan.block(for: chunks[0], label: 5), "[S5] (Lease.pdf)\n\(lease)\n\n---\n")
        XCTAssertEqual(
            SessionEvidencePlan.wholeChunkContext(chunks, firstLabel: 5),
            "[S5] (Lease.pdf)\n\(lease)\n\n---\n[S6] (Rules.pdf)\n\(rules)\n\n---\n")
    }
}

/// Deep Think's final step reads the passages its passes cited, not only their notes (5.8). Through 5.8's first builds
/// it read the notes alone, joined in order and cut at 3,000 characters, so the later passes were the ones lost. These
/// pin how cited passages are found and ranked, that passages are chosen by token count without one long passage
/// shutting out the rest, and that fitting the notes keeps every pass.
@MainActor
final class ChainSynthesisEvidenceTests: XCTestCase {
    func testReadsEveryLabelFormTheSessionsWrite() {
        XCTAssertEqual(ChainSynthesisEvidence.citedLabels(in: "A is 4 [S3]. B is 5 [S3, S7]. C [S2][S9]."), [3, 7, 2, 9])
        XCTAssertEqual(ChainSynthesisEvidence.citedLabels(in: "Rows [S12,S13] and [S1, 4]."), [12, 13, 1, 4])
        XCTAssertEqual(ChainSynthesisEvidence.citedLabels(in: "No labels, [1] is a note number, [S0] is not a label."), [])
    }

    func testMostCitedPassageLeadsAndOnlyReadPassagesCount() {
        let notes = ["Value 14 [S5]. Also [S2].", "Confirms 14 [S5]. Unit kg [S6].", "Wrong label [S40]."]
        // Positions are zero-based: [S5] is position 4. Read windows held positions 0...7.
        let ranked = ChainSynthesisEvidence.rankedPositions(notes: notes, readPositions: Array(0..<8))
        XCTAssertEqual(Array(ranked.prefix(3)), [4, 1, 5], "most cited first, then by first citation")
        XCTAssertEqual(ranked.count, 8, "every read passage is a candidate, the label of an unread one is not")
        XCTAssertEqual(Array(ranked.suffix(5)), [0, 2, 3, 6, 7], "uncited passages follow in retrieval order")
    }

    func testNoCitationsFallsBackToRetrievalOrder() {
        XCTAssertEqual(ChainSynthesisEvidence.rankedPositions(notes: ["plain note"], readPositions: [3, 0, 1]), [0, 1, 3])
    }

    func testALongPassageDoesNotShutOutShorterOnes() {
        // Budget 1,000: 600 fits, 900 does not and is skipped, 300 still fits.
        let chosen = ChainSynthesisEvidence.choose(ranked: [4, 1, 5], counts: [600, 900, 300], budget: 1_000)
        XCTAssertEqual(chosen, [4, 5])
    }

    func testFittingKeepsEveryPassAndDropsRepeatedSentences() {
        let notes = [
            "The cohort had 412 patients. Follow-up was 24 months.",
            "The cohort had 412 patients. Mortality was 8.1 percent at one year.",
            "No new information was found in these documents.",
            "Dropout was 3 percent in the treated arm, reported in the second table.",
        ]
        let all = ChainSynthesisEvidence.fittedNotes(notes, limit: Int.max)
        XCTAssertEqual(all.count, 3, "the no-new-information note is left out, as before")
        XCTAssertFalse(all[1].contains("412"), "a sentence an earlier note holds is not repeated")
        XCTAssertTrue(all[1].contains("8.1 percent"))

        // Notes long enough to be cut: four of about 230 characters each, fitted to 600.
        let long = (1...4).map { pass in
            "Pass \(pass) read the table on page \(pass). The first value is \(pass)1.5 mg. "
                + "The second value is \(pass)2.5 mg, measured at baseline in the treated arm. "
                + "The third value is \(pass)3.5 mg, reported after twelve weeks of follow-up in the same cohort."
        }
        let tight = ChainSynthesisEvidence.fittedNotes(long, limit: 600)
        XCTAssertEqual(tight.count, 4, "a tight limit shortens every note; the last pass is not dropped")
        XCTAssertTrue(tight[3].hasPrefix("Pass 4"), "the last pass keeps its opening")
        XCTAssertLessThanOrEqual(tight.reduce(0) { $0 + $1.count }, 600)
        XCTAssertTrue(tight.allSatisfy { $0.hasSuffix(".") }, "each is cut at a sentence end")
    }

    func testBudgetIsTheWindowLessTheAnswerAndPrompt() {
        XCTAssertEqual(ChainSynthesisEvidence.evidenceTokenBudget(contextSize: 4_096), 4_096 - 1_500 - 450 - 256)
        XCTAssertEqual(
            ChainSynthesisEvidence.evidenceTokenBudget(contextSize: 8_192), SessionEvidencePlan.readingCeilingTokens,
            "the larger window stops at what a session reads until a larger final prompt is measured")
        // The notes-only path read about 700 tokens of notes on either window.
        XCTAssertGreaterThan(ChainSynthesisEvidence.evidenceTokenBudget(contextSize: 4_096), 1_800)
    }
}
