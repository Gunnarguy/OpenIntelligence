//
//  ObservedChangeThrottleTests.swift
//  OpenIntelligenceTests
//
//  A burst of iCloud changes starts one run now and one after the interval, not one per change (5.8,
//  `ObservedChangeThrottle`). On the owner's devices on 2026-11-03 a sync pass ran about once a second during an import.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ObservedChangeThrottleTests: XCTestCase {
    func testABurstOfChangesRunsTwiceNotOncePerChange() async throws {
        let key = "throttle-test-\(UUID().uuidString)"
        var runs = 0
        for _ in 0..<10 {
            ObservedChangeThrottle.run(key, interval: 0.3) { runs += 1 }
        }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(runs, 1, "the first change runs at once, and the rest join it while it waits")
        for _ in 0..<10 {
            ObservedChangeThrottle.run(key, interval: 0.3) { runs += 1 }
        }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(runs, 1, "a change inside the interval waits for its end")
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(runs, 2, "and then runs once for all of them")
    }

    func testKeysDoNotWaitForEachOther() async throws {
        var runs: [String] = []
        ObservedChangeThrottle.run("throttle-a-\(UUID().uuidString)", interval: 5) { runs.append("a") }
        ObservedChangeThrottle.run("throttle-b-\(UUID().uuidString)", interval: 5) { runs.append("b") }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(Set(runs), ["a", "b"])
    }

    /// A change while the work runs doesn't start a second copy alongside it; it runs once more afterwards.
    func testAChangeWhileRunningWaitsForTheRunToEnd() async throws {
        let key = "throttle-running-\(UUID().uuidString)"
        var active = 0
        var most = 0
        var runs = 0
        let work: @MainActor () async -> Void = {
            active += 1
            most = max(most, active)
            runs += 1
            try? await Task.sleep(for: .milliseconds(200))
            active -= 1
        }
        ObservedChangeThrottle.run(key, interval: 0.05, work)
        try await Task.sleep(for: .milliseconds(100))
        ObservedChangeThrottle.run(key, interval: 0.05, work)
        ObservedChangeThrottle.run(key, interval: 0.05, work)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(most, 1, "two runs of one key never overlap")
        XCTAssertEqual(runs, 2, "the changes during the first run got one run after it")
    }
}
