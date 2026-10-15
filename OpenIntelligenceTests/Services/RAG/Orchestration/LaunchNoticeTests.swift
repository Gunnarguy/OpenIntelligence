//
//  LaunchNoticeTests.swift
//  OpenIntelligenceTests
//
//  An engine started without Apple's model says nothing through `lastError` (5.7). The Documents screen
//  shows `lastError` as "Error Processing Document", and through 5.6 an engine started where Apple
//  Intelligence could not run put "Apple Intelligence is required but unavailable. Enable it in Settings"
//  there, on devices that can never enable it too. The empty chat's notice says it by reason instead
//  (`AppleIntelligenceCopy`). The iOS Simulator has no model, so this runs the no-model path.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class LaunchNoticeTests: XCTestCase {
    func testAnEngineStartedWithoutTheModelLeavesTheDocumentErrorEmpty() {
        let engine = RAGService()
        XCTAssertNil(engine.lastError, "launch put this in the document error: \(engine.lastError ?? "")")
    }
}
