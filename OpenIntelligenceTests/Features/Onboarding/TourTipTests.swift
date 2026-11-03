//
//  TourTipTests.swift
//  OpenIntelligenceTests
//
//  The tour (5.8): each screen's tips, and the setup checklist's two steps.
//

import XCTest

@testable import OpenIntelligence

final class TourTipTests: XCTestCase {

    /// A step in no screen never shows; one in two would show on both.
    func testEveryStepIsInExactlyOneScreen() {
        let listed = Tour.screens.flatMap(\.steps)
        XCTAssertEqual(Set(listed), Set(TourStep.allCases))
        XCTAssertEqual(listed.count, TourStep.allCases.count, "a step is listed twice")
    }

    func testEveryTipHasTextAndASymbol() {
        for step in TourStep.allCases {
            XCTAssertFalse(step.title.isEmpty, step.rawValue)
            XCTAssertFalse(step.message.isEmpty, step.rawValue)
            XCTAssertFalse(step.symbol.isEmpty, step.rawValue)
            XCTAssertLessThanOrEqual(step.title.count, 40, step.rawValue)
            // 220 since 5.8: a tip says what the thing is, what it does and why, which 120 left no room for.
            XCTAssertLessThanOrEqual(step.message.count, 220, step.rawValue)
        }
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
