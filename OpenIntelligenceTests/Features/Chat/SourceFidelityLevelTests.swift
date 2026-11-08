//
//  SourceFidelityLevelTests.swift
//  OpenIntelligenceTests
//
//  The response details card names an answer's fidelity. Through 5.7 it read the gating string on its own and called
//  every answer Source-Locked ("All claims are fully verified") unless the string held a short list of words, so an
//  answer whose gates failed (`unverified:<gates>`) and one written without passages (no string) both read verified.
//  It now reads the same outcome as the chat badge.
//

import XCTest

@testable import OpenIntelligence

final class SourceFidelityLevelTests: XCTestCase {
    private func level(_ decision: String?) -> SourceFidelityStatus.FidelityLevel {
        SourceFidelityStatus.FidelityLevel.from(VerificationOutcome.from(gatingDecision: decision))
    }

    func testOnlyAPassedCheckIsSourceLocked() {
        XCTAssertEqual(level("verified:92%"), .sourceLocked)
        XCTAssertEqual(level("verified:92%,answers:full"), .sourceLocked)
    }

    func testFailedGatesAreNotSourceLocked() {
        XCTAssertEqual(level("acceptance_override,unverified:Gate E: Semantic Grounding"), .insufficientEvidence)
        XCTAssertEqual(level("verified:92%,answers:none"), .insufficientEvidence)
    }

    func testAnAnswerWrittenWithoutPassagesIsNotSourceLocked() {
        XCTAssertEqual(level("no_documents"), .insufficientEvidence)
        XCTAssertEqual(level(nil), .notChecked)
        XCTAssertEqual(level("verification_skipped"), .notChecked)
    }

    func testWeakerOutcomesArePartial() {
        XCTAssertEqual(level("low_confidence"), .partiallySupported)
        XCTAssertEqual(level("reliability_fallback"), .partiallySupported)
    }
}
