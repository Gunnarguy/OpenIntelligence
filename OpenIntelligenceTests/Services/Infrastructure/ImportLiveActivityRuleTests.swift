//
//  ImportLiveActivityRuleTests.swift
//  OpenIntelligenceTests
//
//  Which import Live Activity may stay once the person is back in the app (5.8). On 2026-11-03
//  the owner found import cards on the Lock Screen and the Watch that never went away: one a
//  launch had picked back up from a process iOS ended, and one for a paused import.
//

import XCTest

@testable import OpenIntelligence

final class ImportLiveActivityRuleTests: XCTestCase {

    func testAWorkingOrQueuedImport_isMoving() {
        XCTAssertTrue(ImportLiveActivityRule.importIsMoving(stages: [.embedding], pausedByPerson: false))
        XCTAssertTrue(ImportLiveActivityRule.importIsMoving(stages: [.complete, .queued], pausedByPerson: false))
    }

    func testNothingInTheQueue_isNotMoving() {
        // A launch after iOS ended the app mid-import has an empty or restored queue, and its card was kept.
        XCTAssertFalse(ImportLiveActivityRule.importIsMoving(stages: [], pausedByPerson: false))
    }

    func testOnlyFinishedFailedOrCancelled_isNotMoving() {
        XCTAssertFalse(
            ImportLiveActivityRule.importIsMoving(stages: [.complete, .failed, .cancelled], pausedByPerson: false))
    }

    func testPausedItems_areNotMoving() {
        XCTAssertFalse(ImportLiveActivityRule.importIsMoving(stages: [.paused, .paused], pausedByPerson: false))
    }

    func testAQueuePausedByThePerson_isNotMoving_whateverItHolds() {
        XCTAssertFalse(ImportLiveActivityRule.importIsMoving(stages: [.queued, .embedding], pausedByPerson: true))
    }
}
