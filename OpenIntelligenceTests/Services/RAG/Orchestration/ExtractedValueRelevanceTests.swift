//
//  ExtractedValueRelevanceTests.swift
//  OpenIntelligenceTests
//
//  An extracted value stands in for the answer only when it is about what was asked (5.7,
//  `RAGService.extractedValueAnswersQuestion`). These run the real `SpecificationExtractor` on the
//  passages of the 2026-09-26 lock probe (Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/swift/
//  LockMatrixProbe.swift), where a car manual's capacities list locked the engine oil's 4.5 L for the
//  fuel tank and its 4.8 US qt for the coolant, and judge each lock as the answer path does: by the line
//  that holds the value. The first version of the check was tested against a label this path never
//  produces, and the probe's wrong locks still passed (refuting review of d78ce2f, 2026-10-15).
//  Not covered: a run over real libraries, which is what measures how often a lock was wrong.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ExtractedValueRelevanceTests: XCTestCase {
    private func chunk(_ content: String, _ document: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            pageNumber: 1,
            sectionTitle: nil,
            keywords: [],
            hasNumericData: true,
            hasListStructure: false,
            wordCount: content.split(separator: " ").count,
            characterCount: content.count
        )
        return RetrievedChunk(
            chunk: DocumentChunk(documentId: UUID(), content: content, embedding: [0], metadata: metadata),
            similarityScore: 0.70,
            rank: 0,
            sourceDocument: document,
            pageNumber: 1
        )
    }

    private var car: RetrievedChunk {
        chunk(
            "CAPACITIES\nEngine oil with filter: 4.5 L (4.8 US qt)\nFuel tank: 14.3 US gal (54 L)\nEngine coolant: 7.2 L\nRecommended oil: SAE 0W-20",
            "Car Manual.pdf")
    }

    /// What the answer path does with a question: nil when nothing locks, else whether the lock is used.
    private func lockIsUsed(_ question: String, _ chunks: [RetrievedChunk]) async -> Bool? {
        let result = await SpecificationExtractor().extract(query: question, chunks: chunks, answerIntent: .lookup)
        guard case .success(let extraction) = result,
            extraction.confidence >= EvidenceScoringPolicyService.precisionLockThreshold(forceExtractiveAttempt: false)
        else { return nil }
        return RAGService.extractedValueAnswersQuestion(
            question, label: extraction.matchedLabel,
            context: RAGService.valueLine(extraction.answerSpan, in: extraction.sourceChunk.chunk)
                ?? extraction.surroundingContext)
    }

    func testTheProbesWrongLocksAreNotUsed() async {
        for question in ["How much fuel does the tank hold?", "What is the fuel tank capacity?", "How much coolant does it need?"] {
            let used = await lockIsUsed(question, [car])
            XCTAssertEqual(used, false, "\"\(question)\" locked the engine oil's value in the probe and must not use it")
        }
    }

    func testTheProbesRightLocksAreStillUsed() async {
        let fryer = chunk(
            "SPECIFICATIONS\nBasket capacity: 5.8 qt\nPower: 1700 W\nVoltage: 120 V\nBefore first use, remove all packaging and wash the basket.",
            "Air Fryer.pdf")
        let mower = chunk("Engine oil capacity: 4.5L. Check the level before every use.", "Mower Manual.pdf")
        let coffee = chunk(
            "Water reservoir capacity: 1.2 L. The carafe holds 12 cups. Descale every 3 months.", "Coffee Maker.pdf")
        let mixer = chunk(
            "Product weight: 11.2 lb (5.1 kg). Dimensions: 14 x 12 x 13 in. Maximum load: 30 lb.", "Stand Mixer.pdf")
        let cases: [(String, RetrievedChunk)] = [
            ("How much does the basket hold?", fryer),
            ("What is the basket capacity?", fryer),
            ("How much oil does the engine take?", car),
            ("How much oil does the engine take?", mower),
            ("How many quarts of oil does it need?", car),
            ("How much water does it hold?", coffee),
            ("What is the product weight?", mixer),
        ]
        for (question, passage) in cases {
            let used = await lockIsUsed(question, [passage])
            XCTAssertEqual(used, true, "\"\(question)\" over \(passage.sourceDocument) locked the right value in the probe")
        }
    }

    func testAValueIsJudgedByItsOwnLine() {
        XCTAssertEqual(RAGService.valueLine("4.5 L", in: car.chunk), "Engine oil with filter: 4.5 L (4.8 US qt)")
        XCTAssertEqual(RAGService.valueLine("14.3 US gal", in: car.chunk), "Fuel tank: 14.3 US gal (54 L)")
        let coffee = chunk("Water reservoir capacity: 1.2 L. The carafe holds 12 cups.", "Coffee Maker.pdf")
        XCTAssertEqual(RAGService.valueLine("1.2 L", in: coffee.chunk), "Water reservoir capacity: 1.2 L.")
        XCTAssertNil(RAGService.valueLine("9.9 L", in: car.chunk))
    }

    func testTheCheckUsesTheExtractorsSynonyms() {
        XCTAssertTrue(
            RAGService.extractedValueAnswersQuestion(
                "How much gas does it hold?", label: nil, context: "Fuel tank: 14.3 US gal (54 L)"))
    }

    func testQuestionVerbsAreNotSubjects() {
        XCTAssertFalse(
            RAGService.extractedValueAnswersQuestion(
                "How much notice do I have to give before I move out?", label: nil,
                context: "Pull the basket out and shake it halfway through."),
            "\"out\" and \"give\" say nothing about which value")
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
