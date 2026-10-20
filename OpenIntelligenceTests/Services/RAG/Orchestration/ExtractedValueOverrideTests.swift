//
//  ExtractedValueOverrideTests.swift
//  OpenIntelligenceTests
//
//  When an extracted value stands in for the model's answer (5.7). On 2026-10-19, in the iOS 27.0
//  Simulator, "What is the harbor lantern code, and where is it kept?" had the model's answer replaced by
//  the extractor's window of characters: "e harbor the crew measured 3163 units and noted the weather as
//  foggy. the final instruction: the harbor lantern code is VERMILION-4417", which began mid-word and
//  left out ", kept in the blue ledger". The model's answer now stands when it already states the value,
//  and an extraction that stands in is the whole sentence holding the value.
//

import XCTest

@testable import OpenIntelligence

final class ExtractedValueOverrideTests: XCTestCase {
    func testAnAnswerThatStatesTheValueIsKept() {
        XCTAssertTrue(
            RAGService.answerStates(
                value: "VERMILION-4417", in: "The harbor lantern code is VERMILION-4417, kept in the blue ledger."))
        XCTAssertTrue(RAGService.answerStates(value: "4.5 L", in: "The engine takes 4.5L of oil."))
        XCTAssertTrue(RAGService.answerStates(value: "vermilion-4417", in: "Code: VERMILION-4417."))
    }

    func testAnAnswerWithoutTheValueIsNot() {
        XCTAssertFalse(
            RAGService.answerStates(value: "VERMILION-4417", in: "The documents do not say where the code is kept."))
        XCTAssertFalse(RAGService.answerStates(value: "4.5 L", in: "The engine takes 4.8 L of oil."))
        XCTAssertFalse(RAGService.answerStates(value: "  ", in: "Anything at all."))
    }

    func testATableRowReadsAsASentence() {
        XCTAssertEqual(
            RAGService.readableValueLine(
                "ROW 19: The final instruction | the harbor lantern code is VERMILION-4417, kept in the blue ledger."),
            "The final instruction: the harbor lantern code is VERMILION-4417, kept in the blue ledger.")
        XCTAssertEqual(
            RAGService.readableValueLine("ROW 3: E1 | Temperature sensor open circuit | Unplug and contact support."),
            "E1: Temperature sensor open circuit, Unplug and contact support.")
    }

    func testAnOrdinaryLineIsOnlyTrimmed() {
        XCTAssertEqual(
            RAGService.readableValueLine("  The final instruction: the code is VERMILION-4417. \n"),
            "The final instruction: the code is VERMILION-4417.")
    }

    /// The whole line holding the value, from the passage the 60-page PDF produced.
    func testTheValuesLineIsTheWholeSentence() {
        let content = """
            Section Path: Field log page 60 of 60: the harbor survey.
            ROW 19: The final instruction | the harbor lantern code is VERMILION-4417, kept in the blue ledger.
            Entry 1: at the harbor the crew measured 8787 units and noted the weather as wet.
            """
        let chunk = DocumentChunk(
            documentId: UUID(), content: content, parentContent: "Field log page 60 of 60: the harbor survey.",
            embedding: [0],
            metadata: ChunkMetadata(
                chunkIndex: 295, pageNumber: 60, sectionTitle: nil, keywords: [], hasNumericData: true,
                hasListStructure: false, wordCount: 40, characterCount: content.count))
        let line = RAGService.valueLine("VERMILION-4417", in: chunk)
        XCTAssertEqual(
            line.map(RAGService.readableValueLine),
            "The final instruction: the harbor lantern code is VERMILION-4417, kept in the blue ledger.")
    }
}
