//
//  IntelligenceModeCardTests.swift
//  OpenIntelligenceTests
//
//  The Intelligence Mode card's steps (5.8): each traced to its call site on 2026-11-10. The list it replaced named
//  four steps that run in no mode and put Standard-only steps under Deep Think and Maximum.
//

import SwiftUI
import XCTest

@testable import OpenIntelligence

@MainActor
final class IntelligenceModeCardTests: XCTestCase {
    private func card(_ mode: RAGQualityMode = .standard) -> IntelligenceModeCard {
        IntelligenceModeCard(
            mode: mode, windowTokens: 8_192, windowDescription: "8,192 tokens", deepThinkTarget: 90, maximumLimit: nil,
            privateCloudComputeCompiledIn: true, callout: { _ in "" }, onSelect: { _ in })
    }

    func testStepsThatRunInNoModeStayOff() {
        let names = card().steps.map { $0.name.lowercased() + " " + $0.engine.lowercased() }.joined(separator: " ")
        for withdrawn in ["hyde", "compression", "extractive", "entity link"] {
            XCTAssertFalse(names.contains(withdrawn), "\(withdrawn) runs in no mode (traced 2026-11-10)")
        }
    }

    func testEachStepNamesTheModesThatRunIt() {
        let steps = Dictionary(uniqueKeysWithValues: card().steps.map { ($0.id, $0.modes) })
        XCTAssertEqual(steps["again"], [.standard])
        XCTAssertEqual(steps["phrasings"], [.deepThink, .maximum])
        XCTAssertEqual(steps["turns"], [.standard], "Only Standard reads earlier turns")
        XCTAssertEqual(steps["arrange"], [.standard], "Graph context packing and the passage order are Standard's")
        XCTAssertEqual(steps["chain"], [.deepThink, .maximum], "Maximum takes the chain after a good search")
        XCTAssertEqual(steps["research"], [.deepThink])
        XCTAssertEqual(steps["fifty"], [.maximum])
        XCTAssertEqual(steps["withhold"], [.standard], "Only Standard's gates can withhold; the source-only check is shared")
    }

    func testChainPassagesFollowTheWindow() {
        let large = card(.deepThink).steps.first { $0.id == "chain" }?.detail ?? ""
        XCTAssertTrue(large.contains("up to 7 passages"))
        let small = IntelligenceModeCard(
            mode: .deepThink, windowTokens: 4_096, windowDescription: "4,096 tokens", deepThinkTarget: 85, maximumLimit: nil,
            privateCloudComputeCompiledIn: false, callout: { _ in "" }, onSelect: { _ in }
        ).steps.first { $0.id == "chain" }?.detail ?? ""
        XCTAssertTrue(small.contains("read up to 4 passages"))
        XCTAssertTrue(small.contains("85% sure"))
    }
}
