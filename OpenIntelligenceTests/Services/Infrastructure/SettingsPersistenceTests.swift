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

    /// Each of the settings that were missing from the save list is saved when it alone changes (5.7): before, a
    /// relaunch brought back the old value of Pipeline Trace, Force Reasoning Chain, the sampling strategy and the rest.
    func testEverySettingThatPersistAllWritesIsSavedWhenItAloneChanges() async throws {
        let suite = "SettingsPersistenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults, ragService: RAGService())

        func saved() async {
            let done = expectation(description: "the save has run")
            DispatchQueue.main.async { done.fulfill() }
            await fulfillment(of: [done], timeout: 5)
        }
        // The store saves every setting once as it starts, from saves queued on the main queue; those run first, or the
        // first change below would be saved by them whether or not it is on the list (review, 2026-10-18).
        await saved()

        let trace = store.enablePipelineTrace
        // Its `didSet` sets the process-wide trace flag, which later tests in the run would inherit.
        defer { store.enablePipelineTrace = trace }
        store.enablePipelineTrace = !trace
        await saved()
        XCTAssertEqual(defaults.object(forKey: "enablePipelineTrace") as? Bool, !trace)

        let chain = store.forceReasoningChain
        store.forceReasoningChain = !chain
        await saved()
        XCTAssertEqual(defaults.object(forKey: "forceReasoningChain") as? Bool, !chain)

        let summaries = store.enableDocumentSummaries
        store.enableDocumentSummaries = !summaries
        await saved()
        XCTAssertEqual(defaults.object(forKey: "enableDocumentSummaries") as? Bool, !summaries)

        let routing = store.enableQueryRouting
        store.enableQueryRouting = !routing
        await saved()
        XCTAssertEqual(defaults.object(forKey: "enableQueryRouting") as? Bool, !routing)

        store.topK = store.topK + 7
        await saved()
        XCTAssertEqual(defaults.object(forKey: "llmTopK") as? Int, store.topK)

        store.samplingStrategy = store.samplingStrategy == .greedy ? .topP : .greedy
        await saved()
        XCTAssertEqual(defaults.string(forKey: "llmSamplingStrategy"), store.samplingStrategy.rawValue)

        store.seed = 42
        await saved()
        XCTAssertEqual(defaults.object(forKey: "llmSamplingSeed") as? Int, 42)
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
