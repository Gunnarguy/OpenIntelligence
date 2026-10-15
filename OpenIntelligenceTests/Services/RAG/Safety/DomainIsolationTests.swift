//
//  DomainIsolationTests.swift
//  OpenIntelligenceTests
//
//  Domain isolation keeps an answer to a lab-science question from mixing study domains, and leaves everyday
//  questions alone (5.7, `DomainIsolationService`). Through the first 5.7 builds its keywords matched inside
//  words ("um" in "number", "ip" in "trip", "cell" in "cancellation"), and in a demo library of travel and hotel
//  documents ten right answers were marked Unverified by this gate alone and one was refused (Simulator,
//  2026-10-15). The texts here use the same everyday words.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class DomainIsolationTests: XCTestCase {
    private func passage(_ text: String, score: Float = 0.8) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: score, rank: 1, sourceDocument: "Document.pdf", pageNumber: nil)
    }

    private let insurance =
        "Emergency assistance is available 24 hours a day: call the number on your policy card. Trip cancellation "
        + "covers costs you can't get back if you cancel before departure, and claims are paid at the rate in your "
        + "policy on arrival of the receipts. Participants in the group plan can ask human resources."

    func testKeywordsAreWholeWords() {
        XCTAssertEqual(DomainIsolationService.normalize("Cancel the TRIP, 10 mg/kg i.p.!"), " cancel the trip 10 mg/kg i p ")
    }

    func testEverydayWordsAreNotLabScience() {
        XCTAssertEqual(
            DomainIsolationService.classifyQuery("What's the 24-hour number for our travel insurance?").domain,
            .generalReference)
        let classification = DomainIsolationService.classifyChunk(passage(insurance))
        XCTAssertNotEqual(classification.domain.family, .inVitro, "\(classification.matchedKeywords)")
        XCTAssertNotEqual(classification.domain.family, .inVivo, "\(classification.matchedKeywords)")
    }

    func testAnEverydayQuestionIsNeverRefused() {
        let chunks = (0..<6).map { _ in passage(insurance) }
        let assessment = DomainIsolationService.assess(
            query: "What's the 24-hour number for our travel insurance?", chunks: chunks, answerIntent: nil)
        XCTAssertFalse(assessment.strictModeEnabled)
        XCTAssertFalse(assessment.shouldAbstain, assessment.reason ?? assessment.details)
    }

    func testALabQuestionStillKeepsToItsDomain() {
        let animal = passage(
            "Rats received 10 mg/kg by oral gavage, and tumor volume was measured in the xenograft group of mice.")
        let assessment = DomainIsolationService.assess(
            query: "What IC50 did the cell line reach after incubation in the MTT assay?", chunks: [animal, animal],
            answerIntent: nil)
        XCTAssertTrue(assessment.strictModeEnabled)
        XCTAssertTrue(assessment.shouldAbstain, "animal evidence for a cell culture question")
    }
}
