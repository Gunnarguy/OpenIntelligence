//
//  IngestionLiveActivityStageTextTests.swift
//  OpenIntelligenceTests
//
//  The status line of an import's Live Activity. On 2026-10-09 an import in pieces that the
//  system had stopped in the background read "Queued" in the Dynamic Island, and then "Failed"
//  for an import that had only been paused. The second was a cancellation recorded as an error;
//  this pins the first: what the line says for a piece, and for an import waiting for the app.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class IngestionLiveActivityStageTextTests: XCTestCase {
    private typealias Line = IngestionLiveActivityStageText

    func testAPieceIsNamed() {
        XCTAssertEqual(
            Line.text(stage: .embedding, detail: "Part 12 of 45: embedding 960 of 3,850 passages"), "Part 12 of 45")
        XCTAssertEqual(Line.text(stage: .embedding, detail: "Part 12 of 45: reading"), "Part 12 of 45")
    }

    func testAnImportTheSystemStoppedSaysItIsWaitingForTheApp() {
        XCTAssertEqual(
            Line.text(stage: .queued, detail: OpenIntelligence.IngestionItem.queuedForResumeDetail),
            Line.pausedInBackground)
    }

    func testAnythingElseIsTheStagesOwnName() {
        XCTAssertEqual(Line.text(stage: .queued, detail: "Queued"), "Queued")
        XCTAssertEqual(Line.text(stage: .embedding, detail: "Vectorizing batch 3 (40 chunks)"), "Embedding")
        XCTAssertEqual(Line.text(stage: .complete, detail: "Imported in 45 parts"), "Complete")
        XCTAssertEqual(Line.text(stage: .failed, detail: "Part 3 of 45: reading"), "Failed")
    }
}
