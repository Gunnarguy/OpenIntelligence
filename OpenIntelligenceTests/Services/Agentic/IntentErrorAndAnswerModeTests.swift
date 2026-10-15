//
//  IntentErrorAndAnswerModeTests.swift
//  OpenIntelligenceTests
//
//  Two pieces of the 5.7 App Intents round. An action's failure tells the system on 27 what kind it
//  is (`OIIntentError.Kind`, `CustomAppIntentErrorConvertible`) and the person still sees the
//  message unchanged. "Set Answer Mode" (`SetAnswerModeIntent`) changes the mode the chat uses and
//  hands it back. Not covered: undo, which needs an undo manager the system gives only to an action
//  run where the app has one, and the progress the ask actions report before 27, which this iOS 27
//  Simulator cannot run.
//

import AppIntents
import XCTest

@testable import OpenIntelligence

@MainActor
final class IntentErrorAndAnswerModeTests: XCTestCase {
    func testAFailureKeepsItsMessageWhateverItsKind() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("needs iOS 27") }
        for kind in [OIIntentError.Kind.general, .itemNotFound, .partial] {
            let error = OIIntentError("That library no longer exists.", kind: kind)
            XCTAssertEqual(
                String(localized: error.appIntentError.localizedStringResource), "That library no longer exists.",
                "\(kind)")
        }
    }

    func testAGoneItemAndAPartFailureAreApplesPredefinedKinds() throws {
        guard #available(iOS 27.0, macOS 27.0, *) else { throw XCTSkip("needs iOS 27") }
        // The predefined kind is not readable back; its description names it (measured on macOS 27).
        XCTAssertTrue(OIIntentError("Gone.", kind: .itemNotFound).appIntentError.description.contains("predefined"))
        XCTAssertTrue(OIIntentError("Half.", kind: .partial).appIntentError.description.contains("predefined"))
        XCTAssertFalse(OIIntentError("Failed.").appIntentError.description.contains("predefined"))
        XCTAssertEqual(OIIntentError("Failed.").kind, .general)
    }

    func testSetAnswerModeChangesTheChatsModeAndHandsItBack() async throws {
        let before = AnswerModeSetting.current
        defer { AnswerModeSetting.set(before) }

        var intent = SetAnswerModeIntent()
        intent.value = before.canonical == .deepThink ? .standard : .deepThink
        let wanted = intent.value
        _ = try await intent.perform()

        XCTAssertEqual(AnswerModeSetting.current.canonical, wanted.qualityMode)
        if RAGService.activePresentedInstance?.registeredSettingsStore == nil {
            XCTAssertEqual(UserDefaults.standard.string(forKey: AnswerModeSetting.defaultsKey), wanted.qualityMode.rawValue)
        }
    }

    func testEachModeHasTheNameItsMenuShows() {
        XCTAssertEqual(OIAnswerMode.standard.name, "Standard")
        XCTAssertEqual(OIAnswerMode.deepThink.name, "Deep Think")
        XCTAssertEqual(OIAnswerMode.maximum.name, "Maximum")
    }
}
