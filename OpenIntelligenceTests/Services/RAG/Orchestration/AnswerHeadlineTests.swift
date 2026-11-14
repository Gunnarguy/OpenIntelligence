//
//  AnswerHeadlineTests.swift
//  OpenIntelligenceTests
//
//  The repairs of 2026-11-13, from the owner's iPhone: "3. **49**" over four studies' counts, a session badge drawn
//  over "Thinking", a dash in the live status line, "Path & Section" as an Atlas name, and a library holding every
//  document twice after a rebuild met an old copy in iCloud.
//

import XCTest

@testable import OpenIntelligence

final class AnswerHeadlineTests: XCTestCase {
    private let creatine = """
        3. **49**

        - **16 participants** (13 CPEO, 3 myopathy) received creatine monohydrate 20 g/day or placebo [S1].
        - **16 participants** with different mitochondrial disorders received combination including 3 g creatine monohydrate [S3].
        - **15 participants** with CPEO or KSS received 150 mg/kg of creatine monohydrate or placebo [S8].
        - **7 participants** (6 MELAS, 1 myopathy) received creatine monohydrate 5 g twice daily [S5].
        """
    private let sources = [
        "Sixteen participants (13 CPEO, 3 myopathy) received creatine monohydrate 20 g/day or placebo. 16 participants",
        "16 participants with different mitochondrial disorders received a combination including 3 g creatine monohydrate.",
        "15 participants with CPEO or KSS due to single deletions of mtDNA received 150 mg/kg of creatine monohydrate.",
        "7 participants (6 MELAS, 1 myopathy) received creatine monohydrate 5 g twice daily. Page 49 of the review.",
    ]

    func testAListNumberInFrontOfAnAnswerThatIsNotAListComesOff() {
        XCTAssertTrue(RAGService.strippingStrayLeadingListNumber(creatine).hasPrefix("**49**"))
        XCTAssertEqual(RAGService.strippingStrayLeadingListNumber("1. **Six**\n\n* a\n* b"), "**Six**\n\n* a\n* b")
        let list = "1. Unplug it.\n2. Wait a minute.\n3. Plug it in."
        XCTAssertEqual(RAGService.strippingStrayLeadingListNumber(list), list, "a real list keeps its numbers")
        XCTAssertEqual(RAGService.strippingStrayLeadingListNumber("3.5 mg per day [S1]."), "3.5 mg per day [S1].")
        XCTAssertEqual(RAGService.strippingStrayLeadingListNumber("60"), "60")
    }

    func testATotalNoPassageStatesComesOffAndTheCitedFiguresStay() {
        let question = "How many participants received the creatine mix?"
        let stripped = RAGService.strippingStrayLeadingListNumber(creatine)
        let result = RAGService.droppingUnsupportedHeadlineNumber(stripped, question: question, sources: sources)
        XCTAssertEqual(result.dropped, 49, "49 is on a page line, nowhere near the question's words")
        XCTAssertTrue(result.text.hasPrefix("- **16 participants**"))
        XCTAssertTrue(result.text.contains("[S5]"))
    }

    func testAHeadlineTheDocumentsStateOrThatCountsItsListStays() {
        let stated = "**16**\n\n- 13 CPEO [S1]\n- 3 myopathy [S1]"
        XCTAssertNil(
            RAGService.droppingUnsupportedHeadlineNumber(
                stated, question: "How many participants received creatine?", sources: sources
            ).dropped)
        let counted = "**Three**\n\n- PDF\n- Word\n- Excel"
        XCTAssertNil(
            RAGService.droppingUnsupportedHeadlineNumber(counted, question: "How many file formats?", sources: ["PDF, Word and Excel."]).dropped,
            "the count of the items listed under it")
        let miscounted = "**Six**\n\n* 16 participants [S1]\n* 16 participants [S2]\n* 16 participants [S5]"
        XCTAssertEqual(
            RAGService.droppingUnsupportedHeadlineNumber(
                miscounted, question: "How many participants received the creatine mix?", sources: sources
            ).dropped, 6)
        let prose = "The lease gives 60 days [S1]."
        XCTAssertNil(RAGService.droppingUnsupportedHeadlineNumber(prose, question: "How many days?", sources: []).dropped)
    }

    func testTheJudgeIsGivenTheQuestionAskedNotTheConversationBeforeIt() {
        let question = "What regulates mitochondrial quality?"
        let prompt = "PREVIOUS CONVERSATION:\nUser: How many participants received the creatine mix?\nAssistant: 16 [S3]\n\nCURRENT QUESTION: " + question
        let judged = RAGService.judgedQuestion(prompt: prompt, question: question)
        XCTAssertTrue(judged.hasPrefix(question), "the question comes first, alone")
        XCTAssertTrue(judged.contains("for reference only"))
        XCTAssertTrue(judged.contains("creatine mix"), "a follow-up can still be read against the turns before it")
        XCTAssertFalse(judged.contains("CURRENT QUESTION"))
        XCTAssertEqual(RAGService.judgedQuestion(prompt: question, question: question), question)
    }

    func testAPapersOwnReferenceNumbersComeOutOfAnAnswer() {
        let passages = ["MERCS regulate mitophagy [124]. MFN2 disruption uncouples them [222].", "DRP1 drives fission [205, 206].", "Fusion [3]."]
        let answer = "The ER contact site [124] uncouples through MFN2 [222]. DRP1 [205, 206] and fusion [3] matter [S2]."
        let result = RAGService.removingCopiedReferenceNumbers(answer, sources: passages)
        XCTAssertEqual(result.removed, 4)
        XCTAssertEqual(result.text, "The ER contact site uncouples through MFN2. DRP1 and fusion matter [S2].")
        let own = RAGService.removingCopiedReferenceNumbers("It is 60 days [2].", sources: ["Sixty days.", "60 days.", "x"])
        XCTAssertEqual(own.removed, 0, "a bracket no passage holds, within the sources, is left")
    }

    func testTheLiveStatusLineIsPlainWords() {
        XCTAssertEqual(
            RAGService.plainStatusText("- The document mentions \"fusion\".\n- **Depolarizing** mitochondria leads to"),
            "The document mentions \"fusion\". Depolarizing mitochondria leads to")
        XCTAssertEqual(RAGService.plainStatusText("### Findings\n1. First"), "Findings First")
    }

    func testImportLabelsAreNotWhatAClusterIsAbout() {
        let passage = "[Part 1]\nSection Path: X. Li et al.\nTABLE: Outcomes\nHEADERS: Column 1 | IVF | IVM\nROW 2: oocytes | 12 | 9"
        let terms = AtlasLabeling.terms(in: passage)
        for label in ["path", "section", "table", "headers", "row", "column", "part"] {
            XCTAssertFalse(terms.contains(label), "\(label) is the app's own label")
        }
        XCTAssertTrue(terms.contains("oocytes"))
        XCTAssertTrue(AtlasLabeling.terms(in: "The table of contents lists each section.").contains("section"), "a document's own word stays")
    }

    func testADocumentKeepsOnlyItsNewestSetOfPassages() {
        let document = UUID()
        let other = UUID()
        let rebuilt = Date(timeIntervalSince1970: 1_800_000_000)
        func passage(_ index: Int, _ document: UUID, _ made: Date) -> DocumentChunk {
            DocumentChunk(
                documentId: document, content: "p\(index)", embedding: [0],
                metadata: ChunkMetadata(chunkIndex: index, createdAt: made))
        }
        let old = (0..<5).map { passage($0, document, rebuilt.addingTimeInterval(-9 * 86_400 + Double($0))) }
        let new = (0..<4).map { passage($0, document, rebuilt.addingTimeInterval(Double($0) * 60)) }
        let untouched = (0..<3).map { passage($0, other, rebuilt.addingTimeInterval(-30 * 86_400 + Double($0))) }
        let result = PassageGenerations.newest(of: old + untouched + new)
        XCTAssertEqual(result.removed, 5)
        XCTAssertEqual(result.kept.filter { $0.documentId == document }.count, 4)
        XCTAssertEqual(result.kept.filter { $0.documentId == other }.count, 3, "a document imported once is whole")
        XCTAssertEqual(PassageGenerations.newest(of: new + untouched).removed, 0)
        let paused = (0..<3).map { passage($0, other, rebuilt) } + (3..<6).map { passage($0, other, rebuilt.addingTimeInterval(5 * 3600)) }
        XCTAssertEqual(PassageGenerations.newest(of: paused).removed, 0, "an import paused for hours holds each place once")
    }
}
