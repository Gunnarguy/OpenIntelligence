//
//  EntityBindingTests.swift
//  OpenIntelligenceTests
//
//  A value counts for the subject a claim names only when the passages state it for that subject: in the same list
//  item, labelled line or section (5.8, `EntityBinding`). On the owner's iPhone on 2026-11-18 "The similarity floor in
//  Standard mode is 0.20 [S2]." was Supported at 90% by the guide's list of quality modes, whose Maximum item gives
//  0.20 and whose Standard item gives 0.28.
//

import XCTest

@testable import OpenIntelligence

final class EntityBindingTests: XCTestCase {
    /// The guide's passage as the owner's citation showed it: "### 8. Generate and verify" through the "Quality
    /// modes" list.
    @MainActor
    private func qualityModesPassage() throws -> String {
        let body = try XCTUnwrap(SampleDocumentManager.shared.sampleBodiesByName["RAG Technical Architecture"])
        let start = try XCTUnwrap(body.range(of: "### 8. Generate and verify"))
        let end = try XCTUnwrap(body.range(of: "## Seeing the work"))
        return String(body[start.lowerBound..<end.lowerBound])
    }

    private func values(_ text: String) -> [NumericValueExtractor.Mention] {
        NumericValueExtractor.mentions(inAnswer: text).filter(NumericValueExtractor.isCountedByGate)
    }

    private func misplaced(_ claim: String, _ question: String = "", in passage: String) -> [String] {
        EntityBinding.misplacedValues(claim: claim, question: question, values: values(claim), passages: [passage])
            .map(\.value)
    }

    private func chunk(_ text: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0, pageNumber: nil, sectionTitle: nil, keywords: [], hasNumericData: true,
            hasListStructure: true, wordCount: text.split(separator: " ").count, characterCount: text.count)
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [0], metadata: metadata),
            similarityScore: 0.9, rank: 1, sourceDocument: "RAG-Technical-Architecture.md")
    }

    // MARK: - The owner's question

    @MainActor
    func testEveryModesValueIsBoundToItsOwnListItem() throws {
        let passage = try qualityModesPassage()
        let cases: [(mode: String, floor: String, candidates: String, threshold: String)] = [
            ("Standard", "0.28", "30", "0.50"), ("Deep Think", "0.25", "35", "0.60"), ("Maximum", "0.20", "50", "0.80"),
        ]
        for own in cases {
            XCTAssertEqual(misplaced("The similarity floor in \(own.mode) mode is \(own.floor).", in: passage), [], own.mode)
            XCTAssertEqual(misplaced("\(own.mode) retrieves \(own.candidates) candidates per step.", in: passage), [])
            XCTAssertEqual(misplaced("\(own.mode)'s verification threshold is \(own.threshold).", in: passage), [])
            for other in cases where other.mode != own.mode {
                XCTAssertEqual(
                    misplaced("The similarity floor in \(own.mode) mode is \(other.floor).", in: passage), [other.floor],
                    "\(own.mode) given \(other.mode)'s floor")
                XCTAssertEqual(
                    misplaced("\(own.mode) retrieves \(other.candidates) candidates per step.", in: passage),
                    [other.candidates])
                XCTAssertEqual(
                    misplaced("The verification threshold in \(own.mode) mode is \(other.threshold).", in: passage),
                    [other.threshold])
            }
        }
        XCTAssertEqual(misplaced("Standard mode uses up to 8 query variants.", in: passage), ["8"])
        XCTAssertEqual(misplaced("Maximum uses up to 12 query variants.", in: passage), [])
    }

    /// A claim that names no subject is read against the question's.
    @MainActor
    func testAClaimNamingNoSubjectIsReadAgainstTheQuestion() throws {
        let passage = try qualityModesPassage()
        XCTAssertEqual(misplaced("It is 0.20.", "What is the similarity floor in Standard mode?", in: passage), ["0.20"])
        XCTAssertEqual(misplaced("It is 0.28.", "What is the similarity floor in Standard mode?", in: passage), [])
        XCTAssertEqual(misplaced("It is 0.20.", "", in: passage), [], "no subject anywhere: nothing to bind to")
    }

    /// Fact Check: the owner's claim is not Supported, and the right one keeps its verdict.
    @MainActor
    func testFactCheckDoesNotSupportAValueFromAnotherListItem() async throws {
        let passage = try qualityModesPassage()
        let question = "What is the similarity floor in Standard mode?"
        let wrong = "The similarity floor in Standard mode is 0.20 [S1]."
        let right = "The similarity floor in Standard mode is 0.28 [S1]."
        let gates = VerificationGateService()
        let wrongResult = await gates.claimVerdicts(for: [wrong], response: wrong, chunks: [chunk(passage)], query: question)
        let rightResult = await gates.claimVerdicts(for: [right], response: right, chunks: [chunk(passage)], query: question)
        XCTAssertEqual(wrongResult.first?.verdict, .unsupported, wrongResult.first?.details ?? "no result")
        XCTAssertTrue(wrongResult.first?.details.contains("Maximum") ?? false, wrongResult.first?.details ?? "")
        XCTAssertNotEqual(rightResult.first?.verdict, .unsupported, rightResult.first?.details ?? "no result")
    }

    /// The layer that misled the model: sentence extraction cut each list item into sentences and packed them by
    /// score, so the floors reached the model with no mode (the owner's trace, 2026-11-18 13:24: "Sentence extraction:
    /// 30 sentences from 4 sources", then "The similarity floor in Standard mode is 0.20 [S2]"). Each sentence cut from
    /// a list item now carries the item's lead.
    @MainActor
    func testSentenceExtractionKeepsEachItemsSubject() async throws {
        let passage = try qualityModesPassage()
        let result = await RAGService().extractRelevantSentences(
            from: [chunk(passage)], query: "What is the similarity floor in Standard mode?", maxChars: 3_500,
            compact: true, isExtractiveFirst: true)
        XCTAssertTrue(result.context.contains("Standard > 30 candidate passages, a similarity floor of 0.28"), result.context)
        XCTAssertTrue(
            result.context.contains("Maximum > The same loop with the widest net: 50 candidates per step, a similarity floor of 0.20"),
            result.context)
        XCTAssertTrue(result.context.contains("Deep Think > Each step retrieves 35 candidates"), result.context)
        // A table row holds its own label and is not prefixed.
        let table = await RAGService().extractRelevantSentences(
            from: [chunk("HEADERS: Nutrient | Dose\nROW 1: DHA | 1-2 g\nROW 2: Spirulina | 100-200 mg")],
            query: "How much DHA is recommended?", maxChars: 1_000, compact: true, isExtractiveFirst: true)
        XCTAssertTrue(table.context.contains("ROW 1: DHA | 1-2 g"), table.context)
        XCTAssertFalse(table.context.contains("ROW 1 > "), table.context)
    }

    // MARK: - Other shapes of the same defect

    func testASectionUnderItsHeadingIsItsSubject() {
        let passage = """
            ## Pro plan
            It costs $9.99 a month and includes unlimited Maximum answers.

            ## Free plan
            It costs nothing and includes three Maximum answers a day.
            """
        XCTAssertEqual(misplaced("The Free plan costs $9.99 a month.", in: passage), ["9.99"])
        XCTAssertEqual(misplaced("The Pro plan costs $9.99 a month.", in: passage), [])
        XCTAssertEqual(misplaced("The Free plan includes three Maximum answers a day.", in: passage), [])
    }

    func testANamedLineIsItsSubject() {
        let passage = """
            Engine oil: 4.5 L with filter
            Coolant: 6.2 L
            Fuel tank: 54 L
            """
        XCTAssertEqual(misplaced("The coolant capacity is 4.5 L.", in: passage), ["4.5"])
        XCTAssertEqual(misplaced("The coolant capacity is 6.2 L.", in: passage), [])
    }

    /// What the check leaves alone: a value with no subject to tell apart, a sentence naming both, prose without
    /// labels, and a table's rows (`valuesFromOtherRows` decides those).
    func testWhatTheCheckLeavesAlone() {
        XCTAssertEqual(misplaced("Standard's floor is 0.20.", in: "The floor is 0.20 in every mode."), [])
        XCTAssertEqual(
            misplaced(
                "Standard's floor is 0.20.",
                in: "- **Standard.** Its floor is 0.28, and Maximum's 0.20 sits below it.\n- **Maximum.** The floor is 0.20."),
            [], "the Standard item states 0.20 too")
        XCTAssertEqual(
            misplaced("Standard's floor is 0.20.", in: "Standard uses 0.28. Maximum uses 0.20 and Deep Think 0.25."),
            [], "unlabelled sentences, the claim's subject in none of them: the check only reads labels")
        XCTAssertEqual(misplaced("Only one item: 0.20.", in: "- **Maximum.** The floor is 0.20."), [], "one label only")
        XCTAssertEqual(
            misplaced(
                "The DHA dose is 1-2 g.", in: "HEADERS: Nutrient | Dose\nROW 1: DHA | 1-2 g\nROW 2: Spirulina | 100-200 mg"),
            [], "a table row's value is the row check's call")
    }

    /// A refuting review's cases (2026-11-18): true claims the first version marked Unsupported.
    func testRemarksHeadingsAndGeneralClaimsDoNotOverrule() {
        let remark = """
            - **Standard.** One pass, 30 candidates.
            - **Maximum.** 50 candidates, a floor of 0.20.
            **Note:** the default floor is 0.28 in every mode but Maximum.
            """
        XCTAssertEqual(misplaced("Standard's similarity floor is 0.28.", in: remark), [], "a remark names no subject")
        let wrapped = """
            ## Quality modes
            - **Standard.** One retrieval pass, 30 candidates and a similarity floor of
            0.28. Answers are verified at 0.50.
            - **Maximum.** 50 candidates and a similarity floor of 0.20.
            """
        XCTAssertEqual(
            misplaced("The similarity floor in Standard mode is 0.28.", in: wrapped), [],
            "a wrapped line under the list's heading is not another item")
        let general = """
            - **Standard.** One retrieval pass of 30 candidates.
            - **Reranking.** The top 10 candidates are reranked in every mode.
            """
        XCTAssertEqual(
            misplaced("Every mode then reranks the top 10.", "How many candidates does Standard retrieve?", in: general),
            [], "a claim about something else than what was asked is not read as about it")
        XCTAssertEqual(
            misplaced(
                "This threshold is part of the same loop as Deep Think and Standard, with a wider net of 50 candidates.",
                "What is the verification threshold in Maximum mode?",
                in: "- **Standard.** 30 candidates, threshold 0.50.\n- **Deep Think.** 35 candidates, threshold 0.60.\n"
                    + "- **Maximum.** 50 candidates, threshold 0.80."),
            [], "a comparison in an answer about Maximum keeps Maximum as its subject")
    }

    // MARK: - The citation page

    @MainActor
    func testTheCitationPageSaysWhoseValueItIs() throws {
        let passage = try qualityModesPassage()
        XCTAssertEqual(SourceMatch.exact.title, "Passage found word for word in this document.")
        XCTAssertEqual(
            EntityBinding.citationNote(claim: "The similarity floor in Standard mode is 0.20", passage: passage)?.text,
            "The answer's 0.20 is this passage's value for Maximum, not for what the answer says.")
        XCTAssertEqual(
            EntityBinding.citationNote(claim: "The similarity floor in Standard mode is 0.28", passage: passage)?.text,
            "The answer's 0.28 is stated here for Standard.")
        XCTAssertEqual(
            EntityBinding.citationNote(claim: "Standard mode's floor is 0.31", passage: passage)?.text,
            "The answer's 0.31 is not in this passage.")
        XCTAssertNil(EntityBinding.citationNote(claim: "Standard mode runs one pass", passage: passage))
        XCTAssertEqual(
            EntityBinding.citationNote(claim: "The similarity floor in Standard mode is 0.20", passage: passage)?.isWarning,
            true, "the page's seal gives way to the warning")
        XCTAssertEqual(
            EntityBinding.citationNote(claim: "Standard mode retrieves 30 passages", passage: "Standard\n30\nMaximum\n50")?
                .text,
            "The answer's 30 is in this passage.", "a value on a line of its own is in the passage, not missing from it")
        XCTAssertEqual(
            EntityBinding.citationNote(
                claims: ["Maximum's floor is 0.20", "The similarity floor in Standard mode is 0.20"], passage: passage)?.text,
            "The answer's 0.20 is this passage's value for Maximum, not for what the answer says.",
            "a warning first, whichever sentence it comes from")
    }

    func testTheSentencesThatCiteAPassageAreFound() throws {
        let first = chunk("- **Standard.** 30 candidate passages, a similarity floor of 0.28.")
        let second = chunk("Something else.")
        let answer = "The similarity floor in Standard mode is 0.20 [S1]. Standard retrieves 30 candidates. [S1] Other [S2]."
        let linked = CitationLinker.linkedMarkdown(answer, evidence: [], retrievedChunks: [first, second])
        let url = try XCTUnwrap(URL(string: "citation://chunk/\(first.chunk.id.uuidString)"))
        XCTAssertEqual(
            CitationLinker.sentencesCiting(url, inLinked: linked),
            ["The similarity floor in Standard mode is 0.20", "Standard retrieves 30 candidates"])
        let other = try XCTUnwrap(URL(string: "citation://chunk/\(second.chunk.id.uuidString)"))
        XCTAssertEqual(CitationLinker.sentencesCiting(other, inLinked: linked), ["Other"])
    }
}
