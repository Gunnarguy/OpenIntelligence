//
//  ResponseMetadataGatingTests.swift
//  OpenIntelligenceTests
//
//  Pins `ResponseMetadata.appendingGatingDecision`, which `RAGService.finalizeResponse` uses to mark
//  an answer the person finished before its later stages ran (`finished_early_by_person`, 5.4).
//  The gating record is what a saved answer and an exported trace say about how the answer was
//  checked, so the marker must add to it without losing anything else the metadata carries.
//

import XCTest

@testable import OpenIntelligence

final class ResponseMetadataGatingTests: XCTestCase {
    func testAppendingAddsToAnExistingRecordAndKeepsTheRest() {
        let base = ResponseMetadata(
            totalGenerationTime: 2,
            tokensGenerated: 40,
            modelUsed: "Apple Intelligence",
            retrievalTime: 0.5,
            gatingDecision: "verified:88%",
            qualityModeName: "Deep Think"
        )

        let appended = base.appendingGatingDecision("finished_early_by_person")

        XCTAssertEqual(appended.gatingDecision, "verified:88%,finished_early_by_person")
        XCTAssertEqual(appended.tokensGenerated, 40)
        XCTAssertEqual(appended.modelUsed, "Apple Intelligence")
        XCTAssertEqual(appended.qualityModeName, "Deep Think")
    }

    func testAppendingToAnEmptyRecordStartsIt() {
        let base = ResponseMetadata(totalGenerationTime: 1, tokensGenerated: 1, modelUsed: "m", retrievalTime: 0)

        XCTAssertEqual(
            base.appendingGatingDecision("finished_early_by_person").gatingDecision, "finished_early_by_person")
    }
}
