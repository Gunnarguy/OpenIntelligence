//
//  LibraryOrderTests.swift
//  OpenIntelligenceTests
//
//  A library chip dragged in a picker moves the library in this device's order (5.7). The stored
//  list keeps creation order, which sync restores and which names the first library.
//

import XCTest

@testable import OpenIntelligence

final class LibraryOrderTests: XCTestCase {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    func testADraggedLibraryLandsBeforeItsTarget() {
        XCTAssertEqual(ContainerService.reordered([a, b, c, d], moving: [d], before: b), [a, d, b, c])
        XCTAssertEqual(ContainerService.reordered([a, b, c, d], moving: [a], before: d), [b, c, a, d])
    }

    func testWithNoTargetItGoesToTheEnd() {
        XCTAssertEqual(ContainerService.reordered([a, b, c], moving: [a], before: nil), [b, c, a])
        XCTAssertEqual(ContainerService.reordered([a, b, c], moving: [b], before: UUID()), [a, c, b])
    }

    func testADropOnItselfOrUnknownIdsChangeNothing() {
        XCTAssertEqual(ContainerService.reordered([a, b, c], moving: [a, b], before: b), [a, b, c])
        XCTAssertEqual(ContainerService.reordered([a, b], moving: [UUID()], before: a), [a, b])
    }

    func testSeveralKeepTheirOrder() {
        XCTAssertEqual(ContainerService.reordered([a, b, c, d], moving: [d, b], before: a), [b, d, a, c])
    }

    func testTheShownOrderPutsNamedLibrariesFirstAndNewOnesAfter() {
        // The stored list is in creation order; the device's order names c, a.
        XCTAssertEqual(ContainerService.ordered([a, b, c, d], by: [c, a]), [c, a, b, d])
        // A library the order names that no longer exists is skipped.
        XCTAssertEqual(ContainerService.ordered([a, b], by: [UUID(), b]), [b, a])
        XCTAssertEqual(ContainerService.ordered([a, b], by: []), [a, b])
    }

    // The guide library leads the row wherever it sits (2026-11-18).
    func testTheGuideLibraryIsShownFirst() {
        let a = UUID(), b = UUID(), guide = UUID()
        XCTAssertEqual(ContainerService.guideFirst([a, b, guide], guide: guide), [guide, a, b])
        XCTAssertEqual(ContainerService.guideFirst([guide, a, b], guide: guide), [guide, a, b])
        XCTAssertEqual(ContainerService.guideFirst([a, b], guide: guide), [a, b], "a guide id not in the row changes nothing")
        XCTAssertEqual(ContainerService.guideFirst([a, b], guide: nil), [a, b])
    }
}
