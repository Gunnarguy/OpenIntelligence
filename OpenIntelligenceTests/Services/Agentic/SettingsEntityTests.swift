//
//  SettingsEntityTests.swift
//  OpenIntelligenceTests
//
//  OpenIntelligence's settings as one item a shortcut can read (5.7, `OISettingsEntity`, "Get
//  Settings"). Runs in the app the suite runs in. Not covered: reading it from the Shortcuts app.
//

import AppIntents
import XCTest

@testable import OpenIntelligence

@MainActor
final class SettingsEntityTests: XCTestCase {
    func testTheItemSaysTheModeAndTheActiveLibrary() {
        let settings = OISettingsEntity.current()
        let libraries = IntentSupport.libraries()
        XCTAssertEqual(settings.answerMode, OIAnswerMode(AnswerModeSetting.current))
        XCTAssertEqual(settings.activeLibrary?.id, libraries.activeContainer?.id)
        XCTAssertEqual(settings.libraryCount, libraries.containers.count)
    }

    func testTheItemFollowsSetAnswerMode() async throws {
        let before = AnswerModeSetting.current
        defer { AnswerModeSetting.set(before) }
        var change = SetAnswerModeIntent()
        change.value = before.canonical == .deepThink ? .standard : .deepThink
        let wanted = change.value
        _ = try await change.perform()

        XCTAssertEqual(OISettingsEntity.current().answerMode, wanted)
        let found = try await OISettingsEntity.defaultQuery.uniqueEntity()
        XCTAssertEqual(found.answerMode, wanted)
    }
}
