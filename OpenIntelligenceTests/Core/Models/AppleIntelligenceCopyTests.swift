//
//  AppleIntelligenceCopyTests.swift
//  OpenIntelligenceTests
//
//  Through 5.5 chat told every device without the model "Apple Intelligence isn't available. Enable
//  it in Settings.", including hardware that can never enable it, and Settings said "Preparing AI
//  Models..." without end. These pin one wording per reason.
//

import XCTest

@testable import OpenIntelligenceEngine

final class AppleIntelligenceCopyTests: XCTestCase {
    func testAnIneligibleDeviceIsNeverToldToEnableAnything() {
        let chat = AppleIntelligenceCopy.chatMessage(for: .deviceNotEligible)
        XCTAssertTrue(chat.contains("can't run Apple Intelligence"))
        XCTAssertFalse(chat.localizedCaseInsensitiveContains("turn it on"))
        XCTAssertFalse(chat.localizedCaseInsensitiveContains("enable"))
        XCTAssertTrue(chat.contains("iPhone 15 Pro"))
        XCTAssertEqual(AppleIntelligenceCopy.status(for: .deviceNotEligible), "Not supported on this device")
    }

    func testEachReasonHasItsOwnInstruction() {
        XCTAssertTrue(AppleIntelligenceCopy.chatMessage(for: .notEnabled).contains("Settings > Apple Intelligence & Siri"))
        XCTAssertTrue(AppleIntelligenceCopy.chatMessage(for: .modelNotReady).contains("downloading"))
        XCTAssertFalse(AppleIntelligenceCopy.chatMessage(for: .modelNotReady).contains("Settings"))
        XCTAssertFalse(AppleIntelligenceCopy.status(for: .modelNotReady).contains("Preparing"))
        // No reason on record, as in the Simulator: say only what is known.
        XCTAssertEqual(AppleIntelligenceCopy.status(for: nil), AppleIntelligenceCopy.status(for: .unknown))
    }

    func testTheNoticeAppearsOnlyWhenTheModelIsUnavailableAndSaysWhatStillWorks() {
        XCTAssertNil(AppleIntelligenceCopy.notice(for: nil, isAvailable: true))
        XCTAssertNil(AppleIntelligenceCopy.notice(for: .deviceNotEligible, isAvailable: true))
        for reason in [AppleIntelligenceUnavailability.deviceNotEligible, .notEnabled, .modelNotReady, .unknown] {
            let notice = AppleIntelligenceCopy.notice(for: reason, isAvailable: false)
            XCTAssertNotNil(notice, reason.rawValue)
            XCTAssertTrue(notice?.contains("excerpts") ?? false, reason.rawValue)
        }
        XCTAssertNotNil(AppleIntelligenceCopy.notice(for: nil, isAvailable: false))
    }

    /// An answer of excerpts ends on the real reason (5.7); it said "rate-limited" for every cause.
    func testAnExcerptAnswerEndsOnTheRealReason() {
        let reasons: [AppleIntelligenceUnavailability] = [.deviceNotEligible, .notEnabled, .modelNotReady, .unknown]
        for reason in reasons {
            let closing = AppleIntelligenceCopy.excerptClosing(for: reason, isAvailable: false)
            XCTAssertTrue(closing.hasPrefix("These are excerpts"), reason.rawValue)
            XCTAssertFalse(closing.contains("rate-limited"), reason.rawValue)
        }
        XCTAssertTrue(AppleIntelligenceCopy.excerptClosing(for: .deviceNotEligible, isAvailable: false).contains("can't run"))
        XCTAssertTrue(AppleIntelligenceCopy.excerptClosing(for: .notEnabled, isAvailable: false).contains("Settings"))
        XCTAssertFalse(AppleIntelligenceCopy.excerptClosing(for: nil, isAvailable: true).contains("excerpts"))
    }
}
