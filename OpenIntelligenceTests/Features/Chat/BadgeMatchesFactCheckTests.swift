//
//  BadgeMatchesFactCheckTests.swift
//  OpenIntelligenceTests
//
//  The response details' count and Fact Check's chip read the same claims the same way (5.8, 2026-11-18): on the
//  owner's iPhone the footer said Unverified under "5 of 6 Verified".
//

import XCTest

@testable import OpenIntelligence

final class BadgeMatchesFactCheckTests: XCTestCase {
    private func claim(_ verdict: StructuredAnswer.Claim.VerificationVerdict?) -> StructuredAnswer.Claim {
        StructuredAnswer.Claim(
            claim: "A claim.", evidenceIds: [], confidence: 0.5, isExtracted: false, verificationVerdict: verdict,
            verificationDetails: nil)
    }

    func testTheDetailsCountWhatFactCheckCounts() {
        let sets: [[StructuredAnswer.Claim]] = [
            Array(repeating: claim(.supported), count: 5) + [claim(.partial)],
            [claim(.supported), claim(.unsupported), claim(nil)],
            [claim(.supported), claim(.partial), claim(.partial), claim(.unsupported)],
        ]
        for claims in sets {
            let chip = GroundedAnswerView.factCheckSummary(for: claims)
            let details = VerificationOutcome.partialSummary(
                gatingDecision: "unverified:Gate E: Semantic Grounding", claims: claims)
            let count = chip.replacingOccurrences(of: " Verified", with: "")
            XCTAssertTrue(details.hasPrefix("\(count) claims"), "chip \(chip), details \(details)")
            XCTAssertEqual(
                VerificationOutcome.from(gatingDecision: "unverified:Gate E: Semantic Grounding", claims: claims), .partial)
        }
    }
}
