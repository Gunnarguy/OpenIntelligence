//
//  SystemResourceAdviceTests.swift
//  OpenIntelligenceTests
//
//  iOS 27 tells an app when the system would prefer it to scale back heavy work. The import loop and
//  the reasoning chains read that through `SystemResourceAdvice` and wait between steps while it is
//  set. These pin the two halves: no wait when the system has not asked, a wait when it has.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class SystemResourceAdviceTests: XCTestCase {
    override func tearDown() {
        SystemResourceAdvice.set(prefersReducedUsage: false)
        super.tearDown()
    }

    func testNoWaitWhenTheSystemHasNotAsked() async {
        SystemResourceAdvice.set(prefersReducedUsage: false)
        let clock = ContinuousClock()
        let start = clock.now
        let waited = await SystemResourceAdvice.easeOff(for: .seconds(5))
        XCTAssertFalse(waited)
        XCTAssertLessThan(clock.now - start, .seconds(1))
    }

    func testWaitsWhenTheSystemHasAsked() async {
        SystemResourceAdvice.set(prefersReducedUsage: true)
        XCTAssertTrue(SystemResourceAdvice.prefersReducedUsage)
        let clock = ContinuousClock()
        let start = clock.now
        let waited = await SystemResourceAdvice.easeOff(for: .milliseconds(200))
        XCTAssertTrue(waited)
        XCTAssertGreaterThanOrEqual(clock.now - start, .milliseconds(190))
    }

    func testACancelledTaskDoesNotSitOutTheWait() async {
        SystemResourceAdvice.set(prefersReducedUsage: true)
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { await SystemResourceAdvice.easeOff(for: .seconds(30)) }
        task.cancel()
        _ = await task.value
        XCTAssertLessThan(clock.now - start, .seconds(5))
    }
}
