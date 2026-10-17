//
//  SettingsPersistenceTests.swift
//  OpenIntelligenceTests
//
//  A changed setting is saved with its new value (5.7). Through 5.6 the save ran from the
//  setting's `willSet` and wrote the value the setting had before.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SettingsPersistenceTests: XCTestCase {
    func testAChangedSettingIsSavedWithItsNewValue() async throws {
        let suite = "SettingsPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, ragService: RAGService())
        let before = store.enableSpotlightIndexing

        store.enableSpotlightIndexing = !before
        // The save runs on the main queue once the value is set; this block runs after it.
        let saved = expectation(description: "the save has run")
        DispatchQueue.main.async { saved.fulfill() }
        await fulfillment(of: [saved], timeout: 5)

        XCTAssertEqual(defaults.object(forKey: "enableSpotlightIndexing") as? Bool, !before)
    }

    /// The hardware X-Ray starts off on a new install, and a saved setting is kept (5.7).
    func testTheXRayStartsOffOnANewInstallAndASavedSettingIsKept() throws {
        let suite = "SettingsPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(SettingsStore(defaults: defaults, ragService: RAGService()).showSiliconHUD)

        defaults.set(true, forKey: "showSiliconHUD")
        XCTAssertTrue(SettingsStore(defaults: defaults, ragService: RAGService()).showSiliconHUD)
    }

    /// The chat's technical view starts off on a new install, stays on for an install that ran before (which has its
    /// model temperature saved), and a saved choice is kept (5.7). The X-Ray's setting alone, as a launch argument or the
    /// screenshot steps leave it, doesn't make an install one that ran before (review, 2026-10-17).
    func testTechnicalDetailsStartOffOnANewInstallAndStayOnForOneThatRanBefore() throws {
        let fresh = "SettingsPersistenceTests.\(UUID().uuidString)"
        let newInstall = try XCTUnwrap(UserDefaults(suiteName: fresh))
        defer { newInstall.removePersistentDomain(forName: fresh) }
        newInstall.set(false, forKey: "showSiliconHUD")
        XCTAssertFalse(SettingsStore(defaults: newInstall, ragService: RAGService()).showTechnicalDetails)

        let earlier = "SettingsPersistenceTests.\(UUID().uuidString)"
        let ranBefore = try XCTUnwrap(UserDefaults(suiteName: earlier))
        defer { ranBefore.removePersistentDomain(forName: earlier) }
        ranBefore.set(0.7, forKey: "llmTemperature")
        XCTAssertTrue(SettingsStore(defaults: ranBefore, ragService: RAGService()).showTechnicalDetails)

        ranBefore.set(false, forKey: "showTechnicalDetails")
        XCTAssertFalse(SettingsStore(defaults: ranBefore, ragService: RAGService()).showTechnicalDetails)
    }
}
