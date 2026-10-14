//
//  VoiceDictationTests.swift
//  OpenIntelligenceTests
//
//  Spoken words go after what the chat field already held, one space between (5.7).
//

import XCTest

@testable import OpenIntelligence

final class VoiceDictationTests: XCTestCase {
    func testSpokenWordsFollowWhatWasTyped() {
        XCTAssertEqual(VoiceDictation.joined("What does the lease say", "about pets?"), "What does the lease say about pets?")
        XCTAssertEqual(VoiceDictation.joined("", "About pets?"), "About pets?")
        XCTAssertEqual(VoiceDictation.joined("Typed ", "  "), "Typed")
        XCTAssertEqual(VoiceDictation.joined("  ", ""), "")
    }

    @MainActor
    func testANewDictationIsIdleAndHasNoProblem() {
        let dictation = VoiceDictation()
        XCTAssertEqual(dictation.phase, .idle)
        XCTAssertNil(dictation.problem)
        XCTAssertTrue(VoiceDictation.Problem.microphoneDenied.message.contains("Microphone"))
    }

    /// Text handed to the field from outside waits there unless it was typed to be sent: the Mac's
    /// Services menu waits, its menu bar sends (5.7).
    func testTextFromOutsideWaitsInTheFieldUnlessItWasTypedToSend() {
        XCTAssertFalse(ComposerDraft(text: "Pets?").sendsAtOnce)
        XCTAssertTrue(ComposerDraft(text: "Pets?", sendsAtOnce: true).sendsAtOnce)
        XCTAssertNotEqual(ComposerDraft(text: "Pets?").id, ComposerDraft(text: "Pets?").id, "each is applied once")
    }
}
