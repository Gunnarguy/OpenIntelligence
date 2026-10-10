//
//  CompletionNotificationPolicyTests.swift
//  OpenIntelligenceTests
//
//  From 5.7 the app can post a notification when an import or a long answer finishes. These pin when
//  it does: only with the Settings switch on, only while the app is not in front, and for an answer
//  only when it took long enough to be worth leaving the app for.
//

import UserNotifications
import XCTest

@testable import OpenIntelligence

@MainActor
final class CompletionNotificationPolicyTests: XCTestCase {
    private typealias Policy = CompletionNotificationPolicy

    func testNothingIsShownWithTheSwitchOffOrTheAppInFront() {
        let events: [Policy.Event] = [
            .importFinished(success: true), .importFinished(success: false),
            .answerFinished(success: true, duration: 300),
        ]
        for event in events {
            XCTAssertNil(Policy.content(for: event, isEnabled: false, appIsActive: false))
            XCTAssertNil(Policy.content(for: event, isEnabled: true, appIsActive: true))
            XCTAssertNotNil(Policy.content(for: event, isEnabled: true, appIsActive: false))
        }
    }

    func testAQuickAnswerIsNotAnnounced() {
        let limit = Policy.minimumAnswerDuration
        XCTAssertNil(Policy.content(for: .answerFinished(success: true, duration: limit - 1), isEnabled: true, appIsActive: false))
        XCTAssertNotNil(Policy.content(for: .answerFinished(success: true, duration: limit), isEnabled: true, appIsActive: false))
    }

    func testATapGoesToWhereTheResultIs() {
        func destination(_ event: Policy.Event) -> AppDestination? {
            Policy.content(for: event, isEnabled: true, appIsActive: false)?.destination
        }
        XCTAssertEqual(destination(.importFinished(success: true)), .documents)
        XCTAssertEqual(destination(.importFinished(success: false)), .importQueue)
        XCTAssertEqual(destination(.answerFinished(success: true, duration: 60)), .chat)
        XCTAssertEqual(destination(.answerFinished(success: false, duration: 60)), .chat)
    }

    func testAFailureIsNotWordedAsASuccess() throws {
        let stopped = try XCTUnwrap(Policy.content(for: .importFinished(success: false), isEnabled: true, appIsActive: false))
        XCTAssertEqual(stopped.title, "Import stopped")
        let unfinished = try XCTUnwrap(
            Policy.content(for: .answerFinished(success: false, duration: 60), isEnabled: true, appIsActive: false))
        XCTAssertEqual(unfinished.title, "Your question did not finish")
    }

    /// The rule is handed whether something finished and how long it took, never the question or a
    /// file name, so the text can only be one of these four. It can be read on a locked screen.
    func testTheTextIsOneOfFourFixedSentences() {
        let events: [CompletionNotificationPolicy.Event] = [
            .importFinished(success: true), .importFinished(success: false),
            .answerFinished(success: true, duration: 90), .answerFinished(success: false, duration: 90),
        ]
        let shown = events.compactMap { Policy.content(for: $0, isEnabled: true, appIsActive: false) }
        XCTAssertEqual(
            shown.map(\.title),
            ["Import finished", "Import stopped", "Your answer is ready", "Your question did not finish"])
        XCTAssertEqual(
            shown.map(\.body),
            [
                "Your documents are ready to ask about.",
                "Some documents were not imported. Open OpenIntelligence to see which.",
                "OpenIntelligence finished the question you asked.",
                "Open OpenIntelligence to ask it again.",
            ])
    }

    /// The system calls the tap handler by its Objective-C selector. A Swift method that only
    /// nearly matches the protocol's requirement compiles and is never called, which is what two
    /// earlier forms of the foreground method did.
    func testTheTapHandlerIsTheOneTheSystemCalls() {
        let tapped = #selector(
            UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))
        XCTAssertTrue(CompletionNotificationService.shared.responds(to: tapped))
    }

    /// The link a notification carries has to be one the router reads back.
    func testEveryDestinationSurvivesTheLinkRoundTrip() {
        for destination in [AppDestination.documents, .importQueue, .chat] {
            XCTAssertEqual(AppLink.destination(for: AppLink.url(for: destination)), destination)
        }
    }
}
