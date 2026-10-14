//
//  AskControlTests.swift
//  OpenIntelligenceTests
//
//  The system can stop an ask action, and on 27 the action reports progress (5.7).
//

import XCTest

@testable import OpenIntelligence

final class AskControlTests: XCTestCase {
    func testAStopRunsEveryHandlerOnceAndKeepsTheFirstReason() {
        let control = AskControl(progress: nil)
        let counter = Counter()
        control.whenCancelled { counter.add() }
        control.whenCancelled { counter.add() }
        XCTAssertNil(control.cancellationReason)

        control.cancel(because: "timeout")
        control.cancel(because: "cancelled")
        XCTAssertEqual(control.cancellationReason, "timeout")
        XCTAssertEqual(counter.value, 2)

        // A handler added after the stop runs at once.
        control.whenCancelled { counter.add() }
        XCTAssertEqual(counter.value, 3)
    }

    func testProgressKeepsMovingAndIsFullOnlyWithTheAnswer() {
        let progress = Progress()
        let control = AskControl(progress: progress)
        XCTAssertEqual(progress.totalUnitCount, 100)
        control.report("Searching your documents")
        XCTAssertEqual(progress.completedUnitCount, 5)
        XCTAssertEqual(progress.localizedDescription, "Searching your documents")
        // Ten minutes of two-second ticks: the count changes every time and the bar never fills.
        var last = progress.completedUnitCount
        for _ in 0..<300 {
            control.tick()
            XCTAssertGreaterThan(progress.completedUnitCount, last)
            last = progress.completedUnitCount
            XCTAssertLessThan(progress.fractionCompleted, 1)
        }
        control.report("   ")
        XCTAssertEqual(progress.localizedDescription, "Searching your documents", "an empty status keeps the last one")
        control.finish()
        XCTAssertEqual(progress.fractionCompleted, 1)
    }

    func testAFinishedBarStaysFull() {
        let progress = Progress()
        let control = AskControl(progress: progress)
        for _ in 0..<40 { control.tick() }
        control.finish()
        // The heartbeat's last tick and a status that arrives late used to grow the total again.
        control.tick()
        control.report("Writing the answer")
        XCTAssertEqual(progress.fractionCompleted, 1)
        XCTAssertNotEqual(progress.localizedDescription, "Writing the answer")
    }

    func testTheReasonIsSaidPlainly() {
        XCTAssertTrue(AskControl.describe("timeout").contains("too long"))
        XCTAssertEqual(AskControl.describe("cancelled"), "The question was stopped.")
    }

    func testASearchFromSiriPutsNoTextInALink() {
        XCTAssertEqual(AppLink.url(for: .searchFor("pet deposit")).absoluteString, "openintelligence://documents/search")
    }

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var value: Int { lock.withLock { count } }
        func add() { lock.withLock { count += 1 } }
    }
}
