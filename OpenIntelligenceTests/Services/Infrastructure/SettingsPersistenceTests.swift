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
}
