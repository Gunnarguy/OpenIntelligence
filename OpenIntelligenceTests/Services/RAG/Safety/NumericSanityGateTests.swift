//
//  NumericSanityGateTests.swift
//  OpenIntelligenceTests
//
//  On 2026-10-08 an answer gave Apple's on-device model "2.5 billion" parameters. No passage said
//  so: the paper says about 3 billion, and "2.5" was on the page only inside the name of another
//  model, "Qwen-2.5-3B", in a benchmark table. The number check passed it and the sentence read
//  Supported. From 5.7 a number is compared as a value (`NumericValueExtractor`), and a number that
//  is part of a name is matched as the name.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class NumericSanityGateTests: XCTestCase {
    private typealias Numbers = NumericValueExtractor

    private let paper =
        "The on-device model is a compact, approximately 3-billion-parameter model optimized for Apple silicon."
    private let table = "Model | Params | Score\nQwen-2.5-3B | 71.2 | 64.0\nLlama-3.2-1B | 55.1 | 49.3"

    private func supported(_ answer: String, by passages: [String]) -> [Bool] {
        let evidence = Numbers.evidence(from: passages)
        return Numbers.mentions(inAnswer: answer).map { Numbers.isSupported($0, by: evidence) }
    }

    // MARK: - The reader

    func testANumberInsideANameIsNotAQuantity() {
        XCTAssertEqual(
            supported("There are 2.5 billion parameters in the on-device model.", by: [table, paper]), [false])
        XCTAssertEqual(supported("The score was 2.5.", by: [table, paper]), [false])
        XCTAssertEqual(supported("There were 4 models.", by: ["We compare against GPT-4 and Claude."]), [false])
        XCTAssertEqual(supported("It scored 1.5.", by: ["We tested gemini-1.5-pro."]), [false])
        XCTAssertEqual(supported("Use 30 weight oil.", by: ["Recommended oil: SAE 0W-30 or 5W-40."]), [false])
    }

    func testANameIsMatchedAsTheName() {
        XCTAssertEqual(supported("One external model is Qwen-2.5-3B.", by: [table, paper]), [true])
        XCTAssertEqual(supported("One external model is Qwen-2.5-7B.", by: [table, paper]), [false])
        XCTAssertEqual(supported("Qwen-2.5-3B's score was 64.0.", by: [table]), [true, true])
        XCTAssertEqual(supported("Use 0W-30 oil.", by: ["Recommended oil: SAE 0W-30 or 5W-40."]), [true])
        XCTAssertEqual(supported("Use 0W-20 oil.", by: ["Recommended oil: SAE 0W-30 or 5W-40."]), [false])
        // The answer writes the name with a space where the passage has none.
        XCTAssertEqual(supported("It runs on iOS 26.", by: ["Requires iOS26 or later."]), [true])
        XCTAssertEqual(supported("GPT 4 was used.", by: ["We compare against GPT-4 and Claude."]), [true])
    }

    func testAScaleWordIsPartOfTheValue() {
        XCTAssertEqual(supported("It is an approximately 3-billion-parameter model.", by: [paper]), [true])
        XCTAssertEqual(supported("It has about 3 billion parameters [S1].", by: [paper]), [true])
        XCTAssertEqual(supported("The model has 3B parameters.", by: [paper]), [true])
        XCTAssertEqual(supported("The model has 3,000,000,000 parameters.", by: [paper]), [true])
        XCTAssertEqual(supported("The model has 3 parameters.", by: [paper]), [false])
        XCTAssertEqual(supported("Revenue was $2.5M.", by: ["Revenue reached 2.5 million dollars."]), [true])
        // A table states the scale once, in its heading.
        let revenue = "Revenue (in millions)\n2024  2.5\n2025  3.1"
        XCTAssertEqual(supported("Revenue was 2.5 million.", by: [revenue]), [true])
        XCTAssertEqual(supported("Revenue was 2.5 billion.", by: [revenue]), [false])
    }

    func testDigitsInsideALargerNumberDoNotMatch() {
        XCTAssertEqual(supported("The dose is 2.5 mg.", by: ["Give 12.5 mg twice daily."]), [false])
        XCTAssertEqual(supported("The dose is 12.5 mg.", by: ["Give 12.5 mg twice daily."]), [true])
        XCTAssertEqual(supported("About 100 units shipped.", by: ["A total of 100,000 units shipped."]), [false])
    }

    func testTheSameValueWrittenAnotherWayMatches() {
        XCTAssertEqual(supported("It costs 1250 dollars.", by: ["Total due: $1,250.00"]), [true])
        XCTAssertEqual(supported("It costs $1,250.", by: ["Total due: 1250 USD"]), [true])
        XCTAssertEqual(
            supported("The late charge is $75.", by: ["A late charge of $75.00 applies on the 6th day."]), [true])
        XCTAssertEqual(supported("Notice is 60 days.", by: ["Tenant must give 60-day written notice."]), [true])
        XCTAssertEqual(supported("Notice is 30 days.", by: ["Tenant must give 60-day written notice."]), [false])
        XCTAssertEqual(supported("Tire pressure is 35 psi.", by: ["Front: 35psi, rear: 32psi"]), [true])
        XCTAssertEqual(supported("Returns 5 passages.", by: ["We keep the top-5 passages."]), [true])
        XCTAssertEqual(supported("Use version 2.1.", by: ["Requires v2.1 firmware."]), [true])
        XCTAssertEqual(supported("In 2025 it shipped.", by: ["It shipped in mid-2025."]), [true])
        XCTAssertEqual(supported("Half of it, 0.5 L.", by: ["Add .5 L of water."]), [true])
        XCTAssertEqual(supported("The score is 71.2.", by: ["Qwen-2.5-3B|71.2|64.0"]), [true])
        XCTAssertEqual(
            supported(
                "Rent is late after 11:59 p.m. on the 5th day.",
                by: ["Rent is late after 11:59 p.m. on the 5th day of the month."]),
            [true, true, true])
    }

    /// Found by a reviewing pass on 2026-10-09: each of these read as unsupported in the first draft.
    func testRangesListsAndSentenceEndsAreReadAsWritten() {
        // One scale word for both ends of a range.
        XCTAssertEqual(
            supported("It cost between 2 and 3 billion dollars.", by: ["The project cost $2 billion to $3 billion."]),
            [true, true])
        XCTAssertEqual(
            supported("It cost $2 billion to $3 billion.", by: ["It cost between 2 and 3 billion dollars."]),
            [true, true])
        XCTAssertEqual(
            supported("Between 5 and 10 million users.", by: ["5 to 10 thousand users signed up."]), [false, false])
        // A range of times, temperatures or doses is not a code.
        XCTAssertEqual(supported("The office is open 8am-5pm.", by: ["Office hours are 8 a.m. to 5 p.m."]), [true, true])
        XCTAssertEqual(supported("Bake at 350°F-400°F.", by: ["Bake between 350°F and 400°F."]), [true, true])
        XCTAssertEqual(supported("Take 5mg-10mg.", by: ["The dose is 5 mg to 10 mg."]), [true, true])
        XCTAssertEqual(supported("Issued October 5, 2024.", by: ["Issued 05-Oct-2024 by the board."]), [true, true])
        // A row of fields with no spaces.
        XCTAssertEqual(supported("The price is 500.", by: ["Widget,12,500,100"]), [true])
        XCTAssertEqual(supported("The total is 1200.", by: ["30,1200"]), [true])
        XCTAssertEqual(supported("The unit price is 500.", by: ["{\"unit_price\":500,\"max_qty\":100}"]), [true])
        // A sentence end keeps a scale word from the next sentence off the number.
        XCTAssertEqual(
            supported(
                "The policy began in 2024. Millions were affected.",
                by: ["It took effect in 2024, affecting 3 million residents."]),
            [true])
        XCTAssertEqual(supported("It cost 2.5 billion.", by: ["It cost 2.5. Billion-dollar firms noticed."]), [false])
    }

    func testANumberWithALetterAgainstItsFrontIsNotTheBareNumber() {
        XCTAssertEqual(supported("There were 3 models.", by: ["It ran on an M3 chip."]), [false])
        XCTAssertEqual(supported("It ran on the M3.", by: ["It ran on an M3 chip."]), [true])
        XCTAssertEqual(supported("In quarter 3 revenue rose.", by: ["Q3 revenue rose."]), [true])
    }

    /// 5.7 changes how a counted number is matched. It counts nothing the gate used to skip.
    func testTheGateCountsOnlyWhatItCountedBefore() {
        func counted(_ answer: String) -> [Bool] {
            Numbers.mentions(inAnswer: answer).map(Numbers.isCountedByGate)
        }
        XCTAssertEqual(counted("Revenue rose in Q3."), [false])
        XCTAssertEqual(counted("It has a 4K display, 3B parameters and an iPhone17 chip."), [false, false, false])
        XCTAssertEqual(counted("The office is open 8am-5pm on the 5th."), [false, false, false])
        XCTAssertEqual(counted("It weighs 12 kg at 35psi."), [true, true])
        XCTAssertEqual(counted("Use GPT-4 with 0W-30 and Qwen-2.5-3B."), [true, true, true])
        XCTAssertEqual(counted("About 2.5 billion, or 1,250 in 2024."), [true, true, true])
    }

    func testCitationLabelsAndListNumbersAreNotNumbersTheAnswerStates() {
        XCTAssertEqual(supported("It weighs 12 kg (see [2] and [S3, S4]).", by: ["Weight: 12 kg"]), [true])
        XCTAssertEqual(
            supported("1. Remove the basket.\n2. Wash it for 20 minutes.", by: ["Wash the basket for 20 minutes."]),
            [true])
        XCTAssertTrue(Numbers.mentions(inAnswer: "No numbers here [S1].").isEmpty)
    }

    func testAMentionReadsBackAsWritten() {
        XCTAssertEqual(
            Numbers.mentions(inAnswer: "about 2.5 billion and Qwen-2.5-3B").map(\.written),
            ["2.5 billion", "Qwen-2.5-3B"])
        XCTAssertEqual(
            Numbers.mentions(inAnswer: "on the 5th day at 10pm with 35psi").map { $0.attachedSuffix ?? "" },
            ["th", "pm", "psi"])
    }

    // MARK: - The gates

    private func chunk(_ text: String, rank: Int) -> RetrievedChunk {
        let metadata = ChunkMetadata(chunkIndex: rank - 1, pageNumber: rank, wordCount: 20, characterCount: text.count)
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: text, embedding: [], metadata: metadata),
            similarityScore: 0.9,
            rank: rank,
            sourceDocument: "Paper.pdf",
            pageNumber: rank
        )
    }

    /// One passage that states the model's size and, in the next sentence, names the other model.
    /// The words of the invented sentence are all here, and so are the digits "2.5": only reading
    /// the number as a value tells the two sentences apart.
    private let passage =
        "There are 3 billion parameters in the on-device model. One of the external models it is compared with is Qwen-2.5-3B."

    private func verify(_ sentence: String) async -> RAGVerificationResult {
        await VerificationGateService().verify(
            response: sentence,
            query: "How many parameters does the on-device model have?",
            retrievedChunks: [chunk(passage, rank: 1)],
            topScores: [0.9],
            structuredClaims: [StructuredRAGClaim(claim: sentence, citations: ["S1"], isExtracted: true)]
        )
    }

    /// The pair that isolates the number: the two sentences differ only in the figure.
    func testTheSentenceWithTheFigureFromTheNameIsNotSupported() async throws {
        let stated = await verify("There are 3 billion parameters in the on-device model.")
        let invented = await verify("There are 2.5 billion parameters in the on-device model.")

        XCTAssertEqual(stated.claimResults.map(\.verdict), [.supported], "precondition: the figure the paper states")
        let claim = try XCTUnwrap(invented.claimResults.first)
        XCTAssertNotEqual(claim.verdict, .supported, claim.details)
        XCTAssertTrue(claim.details.contains("2.5 billion"), claim.details)
    }

    func testTheNumericGateFailsOnTheFigureFromTheName() async throws {
        let stated = await verify("There are 3 billion parameters in the on-device model.")
        let invented = await verify("There are 2.5 billion parameters in the on-device model.")
        let named = await verify("One of the external models is Qwen-2.5-3B.")

        func numeric(_ result: RAGVerificationResult) throws -> RAGVerificationResult.GateResult {
            try XCTUnwrap(result.gateResults.first { $0.gate == .numericSanity })
        }
        let statedGate = try numeric(stated)
        let namedGate = try numeric(named)
        XCTAssertTrue(statedGate.passed, statedGate.details)
        XCTAssertTrue(namedGate.passed, namedGate.details)
        let failed = try numeric(invented)
        XCTAssertFalse(failed.passed, failed.details)
        XCTAssertTrue(failed.details.contains("2.5 billion"), failed.details)
        XCTAssertTrue(invented.shouldAbstain)
    }
}
