//
//  LibrarySwitchingTests.swift
//  OpenIntelligenceTests
//
//  The Go menu's "Next Library" and "Previous Library" (5.7) walk the library list in the order the
//  app keeps it and wrap at both ends.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class LibrarySwitchingTests: XCTestCase {
    func testNextAndPreviousWrapAroundTheList() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertEqual(LibrarySwitching.target(from: a, in: [a, b, c], step: 1), b)
        XCTAssertEqual(LibrarySwitching.target(from: c, in: [a, b, c], step: 1), a)
        XCTAssertEqual(LibrarySwitching.target(from: a, in: [a, b, c], step: -1), c)
        XCTAssertEqual(LibrarySwitching.target(from: b, in: [a, b], step: -1), a)
    }

    func testWithOneLibraryOrAnUnknownOneThereIsNowhereToGo() {
        let a = UUID()
        let b = UUID()
        XCTAssertNil(LibrarySwitching.target(from: a, in: [a], step: 1))
        XCTAssertNil(LibrarySwitching.target(from: UUID(), in: [a, b], step: 1))
        XCTAssertNil(LibrarySwitching.target(from: a, in: [], step: 1))
    }
}
