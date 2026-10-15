//
//  ExtractedValueRelevanceTests.swift
//  OpenIntelligenceTests
//
//  An extracted value stands in for the answer only when it is about what was asked (5.7,
//  `RAGService.extractedValueAnswersQuestion`). The cases are the ones on the roadmap row: a car
//  manual's capacities list, where the engine oil's 4.5 L locked for the fuel tank, and a lease where
//  Deep Think answered 30 days for a notice the lease sets at 60. The texts are written for the test.
//  Not covered: a run over real libraries, which is what measures how often a lock was wrong.
//

import XCTest

@testable import OpenIntelligence

final class ExtractedValueRelevanceTests: XCTestCase {
    func testAValueLabelledForSomethingElseIsNotTheAnswer() {
        XCTAssertFalse(
            RAGService.extractedValueAnswersQuestion(
                "What is the fuel tank capacity?", label: "Engine oil", context: "Engine oil 4.5 L"))
        XCTAssertTrue(
            RAGService.extractedValueAnswersQuestion(
                "What is the fuel tank capacity?", label: "Fuel tank", context: "Fuel tank 52 L"))
        XCTAssertTrue(
            RAGService.extractedValueAnswersQuestion(
                "How much fuel does the tank hold?", label: "Fuel tanks", context: ""), "a plural label still matches")
    }

    func testWithoutALabelTheTextAroundTheValueDecides() {
        XCTAssertFalse(
            RAGService.extractedValueAnswersQuestion(
                "How many days notice does the tenant have to give?", label: nil,
                context: "Rent is due within 30 days of the first of the month."))
        XCTAssertTrue(
            RAGService.extractedValueAnswersQuestion(
                "How many days notice does the tenant have to give?", label: nil,
                context: "The tenant must give 60 days written notice before moving out."))
    }

    func testAQuestionWithNoSubjectLeftIsNotChecked() {
        XCTAssertTrue(RAGService.extractedValueAnswersQuestion("How much?", label: "Engine oil", context: ""))
        XCTAssertTrue(
            RAGService.extractedValueAnswersQuestion("What does this need?", label: "Engine oil", context: ""),
            "\"does\" and \"this\" are not subject words")
    }

    func testPluralsFoldOnlyWhereTheyArePlurals() {
        XCTAssertEqual(RAGService.lookupWords(in: "tanks quarts"), ["tank", "quart"])
        XCTAssertEqual(RAGService.lookupWords(in: "does this glass status"), ["does", "this", "glass", "status"])
    }
}
