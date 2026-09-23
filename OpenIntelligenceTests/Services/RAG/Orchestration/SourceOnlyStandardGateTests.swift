//
//  SourceOnlyStandardGateTests.swift
//  OpenIntelligenceTests
//
//  Pins which answers skip the source-only check after generation.
//
//  Why this exists. The source-only check is two sequential structured model calls that run after
//  an answer's last word, and until 2026-09-23 Standard ran it on every extractive answer. Measured
//  that day on the macOS Debug build, four Standard lookup questions whose verification gates had
//  passed finished 19.4, 37.6, 58.3 and 163.8 seconds after their last streamed word, and the check
//  replaced none of the four answers. Standard now skips it for an answer the gates passed. The
//  skip must not reach Deep Think or Maximum, and must not reach a Standard answer the gates failed
//  or never judged, because for those the check is the only second look at the claims.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SourceOnlyStandardGateTests: XCTestCase {
    func testStandardSkipsTheCheckOnlyWhenTheGatesPassed() {
        XCTAssertTrue(RAGService.standardSkipsSourceOnlyCheck(qualityMode: .standard, gatesPassed: true))
        XCTAssertFalse(
            RAGService.standardSkipsSourceOnlyCheck(qualityMode: .standard, gatesPassed: false),
            "A Standard answer the gates flagged still gets the source-only check."
        )
        XCTAssertFalse(
            RAGService.standardSkipsSourceOnlyCheck(qualityMode: .standard, gatesPassed: nil),
            "A Standard answer the gates never judged still gets the source-only check."
        )
    }

    func testDeepThinkAndMaximumNeverSkipTheCheck() {
        for mode in [RAGQualityMode.deepThink, .maximum, .agentic] {
            for gatesPassed in [true, false, nil] as [Bool?] {
                XCTAssertFalse(
                    RAGService.standardSkipsSourceOnlyCheck(qualityMode: mode, gatesPassed: gatesPassed),
                    "\(mode) with gatesPassed \(String(describing: gatesPassed)) must keep the check."
                )
            }
        }
    }

    /// The legacy modes a stored setting can still hold resolve to Standard, so they follow it.
    func testLegacyStandardAliasesFollowStandard() {
        for mode in [RAGQualityMode.balanced, .fast, .thorough] {
            XCTAssertEqual(mode.canonical, .standard)
            XCTAssertTrue(RAGService.standardSkipsSourceOnlyCheck(qualityMode: mode, gatesPassed: true))
            XCTAssertFalse(RAGService.standardSkipsSourceOnlyCheck(qualityMode: mode, gatesPassed: false))
        }
    }
}
