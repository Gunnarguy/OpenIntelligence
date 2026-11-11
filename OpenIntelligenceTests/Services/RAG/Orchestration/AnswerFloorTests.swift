//
//  AnswerFloorTests.swift
//  OpenIntelligenceTests
//
//  Pins the three 5.8 fixes for the blank Standard answer of 2026-11-09 ("How much lysine is present?"): passages a
//  side search adds go behind retrieval's best passage, never in front of it; an answer with no words is caught; a
//  line that is only a number is an answer, not an orphaned list marker. And the setup card's estimated progress.
//

import XCTest

@testable import OpenIntelligence

final class AnswerFloorTests: XCTestCase {
    private func retrieved(_ text: String, score: Float) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: text, embedding: [0],
                metadata: ChunkMetadata(
                    chunkIndex: 0, pageNumber: 1, sectionTitle: nil, keywords: [], hasNumericData: false,
                    hasListStructure: false, wordCount: text.split(separator: " ").count, characterCount: text.count)),
            similarityScore: score, rank: 1)
    }

    func testSideSearchPassagesGoBehindTheTopRankedPassage() {
        let top = retrieved("Arthrospira platensis composition table: lysine 4.6 g/100 g", score: 0.9)
        let second = retrieved("prose", score: 0.5)
        var candidates = [top, second]
        let added = [
            retrieved("autism biomarkers: lysine present 12 umol/L", score: 1), retrieved("other 3", score: 1),
        ]

        RAGService.insertingBehindTopRanked(added, into: &candidates)

        XCTAssertEqual(
            candidates.map(\.chunk.id), [top.chunk.id, added[0].chunk.id, added[1].chunk.id, second.chunk.id])
    }

    func testSideSearchPassagesIntoAnEmptyListOrNothingAdded() {
        var empty: [RetrievedChunk] = []
        let added = [retrieved("only", score: 1)]
        RAGService.insertingBehindTopRanked(added, into: &empty)
        XCTAssertEqual(empty.map(\.chunk.id), added.map(\.chunk.id))

        var unchanged = [retrieved("a", score: 1)]
        let before = unchanged.map(\.chunk.id)
        RAGService.insertingBehindTopRanked([], into: &unchanged)
        XCTAssertEqual(unchanged.map(\.chunk.id), before)
    }

    func testAnswersWithNoWordsAreDegenerate() {
        for text in ["", "1", " 2. ", "-", "42", "1.\n2."] {
            XCTAssertTrue(RAGService.isDegenerateAnswer(text), "\(text.debugDescription) should be degenerate")
        }
        for text in ["60 [S1]", "Lysine is 4.6 g per 100 g [S1].", "Not found.", "六十日", "Ja"] {
            XCTAssertFalse(RAGService.isDegenerateAnswer(text), "\(text.debugDescription) is an answer")
        }
        XCTAssertFalse(RAGService.isDegenerateAnswer(RAGService.notFoundAnswer))
    }

    func testABareNumberIsNotAnOrphanListMarker() {
        for line in ["-", "*", "•", "2.", "3)", "12. "] {
            XCTAssertTrue(RAGService.isOrphanListMarker(line), line)
        }
        for line in ["1", "60", "2024", "2. Lysine", "- item"] {
            XCTAssertFalse(RAGService.isOrphanListMarker(line), line)
        }
    }

    /// The Elfar composition table as `buildStructuralTableText` writes it, rows from the paper (KBIE_13_2100863.pdf p.5).
    private let compositionTable = """
        [Part 1]
        Section Path: O. A. ELFAR ET AL
        TABLE: O. A. ELFAR ET AL
        HEADERS: Arthrospiro platensis Biochemical Composition Profile | Column 2 | Column 3
        ROW 1: Content | Amount/Value | Unit
        ROW 2: Carbohydrates | 15.0-25.0 | %
        ROW 3: Proteins | 65.0-71.0 | %
        ROW 4: Alanine | 7.7-46.6 | mg/g
        ROW 5: Arginine | 7.9-47.6 | mg/g
        ROW 6: Aspartic Acid | 12.1-72.8 | mg/g
        ROW 7: Cysteine | 0.9-5.6 | mg/g
        ROW 8: Glutamic Acid | 4.1-84.4 | mg/g
        ROW 9: Glycine | 5.3-31.9 | mg/g
        ROW 10: Histidine | 2.5-15.0 | mg/g
        ROW 11: Isoleucine | 5.4-32.6 | mg/g
        ROW 12: Leucine | 8.2-48.9 | mg/g
        ROW 13: Lysine | 4.4-26.2 | mg/g
        ROW 14: Methionine | 2.2-13.3 | mg/g
        """

    func testATableIsNotPenalisedAsATableOfContents() {
        // Before 5.8 the table took the section-number penalty for its decimals: the 0.90 -> 0.72 of 2026-11-09.
        XCTAssertGreaterThanOrEqual(RAGEngine.computeTOCPenalty(content: compositionTable, isTable: false), 0.18)
        XCTAssertEqual(RAGEngine.computeTOCPenalty(content: compositionTable, isTable: true), 0)
    }

    /// The owner's iPhone, 2026-11-10: a JAMA Psychiatry results table stored flattened as a paragraph. It was the
    /// reranker's first pick for the hazard ratio question, and the contents-page penalty took it from 0.90 to 0.60.
    func testAFlattenedResultsTableWithIntervalsIsNotAContentsPage() {
        let results = """
            Table 2. Associations of ADHD With Cognitive Impairment Model HR (95% CI) Unadjusted 3.21 (2.90-3.55) \
            Adjusted for demographics 2.98 (2.68-3.31) Somatic comorbidities 4.60 (3.99-5.29) Neuropsychiatric \
            comorbidities 3.12 (2.71-3.59) Stratified by sex 4.05 (3.29-4.99) Stratified by race and ethnicity \
            3.88 (3.10-4.86) Sensitivity analysis 2.75 (2.30-3.29)
            """
        XCTAssertGreaterThanOrEqual(RAGEngine.estimatesWithInterval(in: results), 2)
        XCTAssertEqual(RAGEngine.computeTOCPenalty(content: results, isTable: false), 0)
    }

    /// Maximum (the compute profile) turns work up, never down, and its page memory keeps an 8 GB iPhone at two pages.
    func testMaximumFidelityRaisesEveryFigureItNames() {
        typealias Max = DeviceCapabilityService.MaximumFidelity
        XCTAssertEqual(Max.renderScale, 6.0)
        XCTAssertGreaterThan(Max.rerankCeiling, 250)
        XCTAssertGreaterThan(Max.rerankFloor, 100)
        XCTAssertGreaterThan(Max.keywordLimit, 60)
        XCTAssertGreaterThan(Max.rescueRegions, 12)
        XCTAssertEqual(Int(8.0 * 1024 * 0.15 / Max.megabytesPerPage), 2)
        // A reported 7.5 GB rounds to one; the code holds two at least in Maximum.
        XCTAssertEqual(Int(7.5 * 1024 * 0.15 / Max.megabytesPerPage), 1)
    }

    /// Statistical values make a question a value question, by whole words.
    func testStatisticalValueWordsMakeAValueQuestion() {
        XCTAssertTrue(RAGService.namesAStatisticalValue("what is the hazard ratio for somatic comorbidities?"))
        XCTAssertTrue(RAGService.namesAStatisticalValue("what is the median age at diagnosis?"))
        XCTAssertTrue(RAGService.namesAStatisticalValue("what was the p-value for mental health?"))
        XCTAssertFalse(RAGService.namesAStatisticalValue("how do they generate the summaries?"))
        XCTAssertFalse(RAGService.namesAStatisticalValue("what is meant by executive function?"))
        XCTAssertFalse(RAGService.namesAStatisticalValue("what is adhd?"))
    }

    func testARealTableOfContentsIsStillPenalised() {
        let toc = """
            Table of Contents
            1. Introduction ........ 3
            2. Methods ........ 7
            2.1. Sampling ........ 8
            2.2. Analysis ........ 11
            3. Results ........ 15
            3.1. Composition ........ 16
            4. Discussion ........ 21
            5. Conclusion ........ 25
            """
        XCTAssertGreaterThan(RAGEngine.computeTOCPenalty(content: toc, isTable: false), 0.3)
        // Even if a table-of-contents page was stored as a table, its dot leaders and "Table of Contents" still count.
        XCTAssertGreaterThanOrEqual(RAGEngine.computeTOCPenalty(content: toc, isTable: true), 0.3)
    }

    func testLostInTheMiddleKeepsTheBestPassageFirst() {
        // Deep Think's own loop gave [2, 4, 1, 3, 5] through 5.7.
        XCTAssertEqual(RAGEngine.applyLostInMiddleReordering([1, 2, 3, 4, 5]), [1, 3, 5, 4, 2])
        XCTAssertEqual(RAGEngine.applyLostInMiddleReordering([1, 2, 3]), [1, 2, 3])
    }

    func testAblationNamesParse() {
        XCTAssertEqual(RetrievalAblation.parse("tocPenalty, specSniper,nonsense"), [.tocPenalty, .specSniper])
        XCTAssertEqual(RetrievalAblation.parse("all"), Set(RetrievalAblation.Rule.allCases))
        XCTAssertEqual(RetrievalAblation.parse(""), [])
    }

    func testSideSearchScoresStayUnderTheRerankersCeiling() {
        XCTAssertLessThan(RAGService.sideSearchScoreCeiling, 0.90)
    }

    func testOnlyHowManyGetsTheCountInstruction() {
        XCTAssertTrue(RAGService.getsCountInstruction("how many documents mention lysine?"))
        XCTAssertFalse(RAGService.getsCountInstruction("how much lysine is present?"))
        XCTAssertFalse(RAGService.getsCountInstruction("what is the lysine content?"))
    }

    func testSetupProgressEstimateStaysShortOfDoneAndStartsAtZero() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RerankerSetupStatus.estimatedProgress(startedAt: nil, now: start), 0)
        XCTAssertEqual(RerankerSetupStatus.estimatedProgress(startedAt: start, now: start), 0)
        XCTAssertEqual(
            RerankerSetupStatus.estimatedProgress(startedAt: start, now: start.addingTimeInterval(25)), 0.5,
            accuracy: 0.001)
        XCTAssertEqual(
            RerankerSetupStatus.estimatedProgress(startedAt: start, now: start.addingTimeInterval(500)), 0.95)
    }
}
