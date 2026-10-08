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
