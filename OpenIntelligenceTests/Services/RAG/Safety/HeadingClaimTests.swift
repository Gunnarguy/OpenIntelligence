//
//  HeadingClaimTests.swift
//  OpenIntelligenceTests
//
//  An answer's own heading is not a claim for Fact Check (5.7, `VerificationGateService.headingLines`). The model
//  sometimes lists its title among its claims, and "Hotel Address in Lisbon" was scored Partial, so a right answer
//  read "1 of 2 Verified" (demo copy of e9de06d in the Simulator, 2026-10-15).
//

import XCTest

@testable import OpenIntelligence

final class HeadingClaimTests: XCTestCase {
    func testHeadingsAreFoundInEveryForm() {
        let answer = """
            ## Hotel Address in Lisbon
            The hotel is Casa Azulejo, Rua das Flores 41, Chiado [S3].
            **Check-out**
            Getting there:
            Take the metro to Baixa-Chiado.
            """
        let headings = VerificationGateService.headingLines(in: answer)
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Hotel Address in Lisbon")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Check-out")))
        XCTAssertTrue(headings.contains(VerificationGateService.headingKey("Getting there")))
        XCTAssertFalse(
            headings.contains(VerificationGateService.headingKey("The hotel is Casa Azulejo, Rua das Flores 41, Chiado.")))
        XCTAssertFalse(headings.contains(VerificationGateService.headingKey("Take the metro to Baixa-Chiado.")))
    }

    func testAnAnswerWithNoHeadingsHasNone() {
        XCTAssertTrue(VerificationGateService.headingLines(in: "Check-out is at 11:00 a.m. [S2].").isEmpty)
    }
}
