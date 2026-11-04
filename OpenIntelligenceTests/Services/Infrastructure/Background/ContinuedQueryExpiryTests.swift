//
//  ContinuedQueryExpiryTests.swift
//  OpenIntelligenceTests
//
//  When the system expires an answer's continued processing task, only an app in the background
//  stops the answer (5.8). On the owner's iPhone on 2026-11-04 the task expired a second after he
//  came back to the app and a five-minute Deep Think answer was cut to "Partial answer".
//

#if os(iOS)
import XCTest

@testable import OpenIntelligence

final class ContinuedQueryExpiryTests: XCTestCase {
    func testAnAnswerInFrontKeepsRunningWhenItsTaskExpires() {
        XCTAssertTrue(BackgroundTaskService.answerKeepsRunningAfterTaskExpiry(appIsInBackground: false))
    }

    func testAnAnswerInTheBackgroundStopsWhenItsTaskExpires() {
        XCTAssertFalse(BackgroundTaskService.answerKeepsRunningAfterTaskExpiry(appIsInBackground: true))
    }
}
#endif
