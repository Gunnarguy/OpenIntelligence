//
//  TourTipTests.swift
//  OpenIntelligenceTests
//
//  The tour (5.8): each screen's tips, and the setup checklist's two steps.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class TourTipTests: XCTestCase {

    /// A step in no screen never shows; one in two would show on both.
    func testEveryStepIsInExactlyOneScreen() {
        let listed = Tour.screens.flatMap(\.steps)
        XCTAssertEqual(Set(listed), Set(TourStep.allCases))
        XCTAssertEqual(listed.count, TourStep.allCases.count, "a step is listed twice")
    }

    /// Small and easy to read (the tour's rebuild, 2026-11-13): a title of at most four words and one short sentence.
    func testEveryTipIsShort() {
        for step in TourStep.allCases {
            XCTAssertFalse(step.title.isEmpty, step.rawValue)
            XCTAssertFalse(step.message.isEmpty, step.rawValue)
            XCTAssertFalse(step.symbol.isEmpty, step.rawValue)
            XCTAssertLessThanOrEqual(step.title.split(separator: " ").count, 4, step.rawValue)
            XCTAssertLessThanOrEqual(step.message.count, 130, step.rawValue)
            XCTAssertFalse(step.message.dropLast().contains(". "), "\(step.rawValue): more than one sentence")
        }
    }

    /// The pacing's exceptions stay few, and every tip gives up on its own.
    func testPacingAndLimits() {
        XCTAssertEqual(Set(TourStep.allCases.filter(\.isEssential)),
            [.composer, .notFound, .citation, .matchBanner, .modePicker, .addDocument])
        XCTAssertEqual(Tour.maxShowings, 3)
        XCTAssertEqual(Tour.maxSecondsOnScreen, 60, "TipKit's floor for MaxDisplayDuration")
        XCTAssertGreaterThanOrEqual(Tour.launchQuietSeconds, 30, "no paced tip right at launch")
        XCTAssertGreaterThanOrEqual(Tour.secondsBetweenTips, 60)
        // They show one at a time, so a screen's count is how many controls it explains, not how many at once.
        XCTAssertGreaterThanOrEqual(TourStep.allCases.count, 41, "the tour covers at least what 5.8's first tour did")
    }

    /// Smaller than the system's tip (2026-11-13): TipKit's icon is about 40 points.
    func testTipIconIsSmallerThanTipKits() {
        XCTAssertLessThan(Tour.imageSize.width, 40)
        XCTAssertEqual(Tour.imageSize.width, Tour.imageSize.height)
    }

    /// A tip with a button does the thing; its label says what.
    func testActionsAreNamed() {
        XCTAssertEqual(TourStep.composer.actionTitle, "Try a question")
        XCTAssertEqual(TourStep.notFound.actionTitle, "Go Deeper")
        for step in TourStep.allCases {
            if let title = step.actionTitle {
                XCTAssertLessThanOrEqual(title.split(separator: " ").count, 3, step.rawValue)
                XCTAssertEqual(TourTip(step).actions.count, 1, step.rawValue)
            } else {
                XCTAssertTrue(TourTip(step).actions.isEmpty, step.rawValue)
            }
        }
    }

    /// The first cited source the citation card's Show Me opens, skipping a link that resolves to nothing.
    func testFirstCitedChunkSkipsALinkToNothing() {
        let markdown = "One [[S1]](citation://chunk/\(UUID().uuidString)) two."
        XCTAssertNil(GroundedAnswerView.firstCitedChunk(in: markdown, among: []))
        XCTAssertNil(GroundedAnswerView.firstCitedChunk(in: "No sources at all.", among: []))
    }

    /// The app's copy carries no em dashes, and a tip's id is what TipKit keeps its state under.
    func testTipTextHasNoEmDashesAndIdsAreStable() {
        for step in TourStep.allCases {
            XCTAssertFalse(step.title.contains("\u{2014}") || step.message.contains("\u{2014}"), step.rawValue)
            XCTAssertEqual(step.id, "tour.\(step.rawValue)")
        }
    }

    /// Every symbol a tip names exists in SF Symbols, so no tip shows an empty square.
    func testEverySymbolExists() {
        #if canImport(UIKit)
            for step in TourStep.allCases {
                XCTAssertNotNil(UIImage(systemName: step.symbol), "\(step.rawValue): \(step.symbol)")
            }
        #endif
    }
}

@MainActor
final class OnboardingTwoStepTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "OnboardingTwoStepTests"

    override func setUp() async throws {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Through 5.7 a third step, choosing a model by hand, had no screen, so setup finished only by Start Asking or
    /// Skip (found 2026-11-03).
    func testSetupFinishesOnceDocumentsAreInAndAQuestionIsAsked() {
        let store = OnboardingStateStore(defaults: defaults)
        XCTAssertEqual(store.totalStepCount, 2)
        XCTAssertFalse(store.hasCompletedOnboarding)
        store.markSamplesImported()
        XCTAssertEqual(store.completedStepCount, 1)
        store.markAskedFirstQuery()
        XCTAssertEqual(store.completedStepCount, 2)
        XCTAssertTrue(store.hasCompletedOnboarding)
        XCTAssertFalse(store.hasOutstandingSteps)
        XCTAssertFalse(store.isChecklistVisible)
    }
}
