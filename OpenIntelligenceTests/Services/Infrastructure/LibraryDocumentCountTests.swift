//
//  LibraryDocumentCountTests.swift
//  OpenIntelligenceTests
//
//  A library's count is counted from its documents (5.8). On the owner's iPhone on 2026-11-03 General's pill read 4
//  while it held 3: iCloud's merge keeps the larger of each device's saved total.
//

import XCTest

@testable import OpenIntelligence

final class LibraryDocumentCountTests: XCTestCase {

    func testDocumentsAreCountedByTheirLibrary() {
        let general = UUID()
        let other = UUID()
        let counts = ContainerService.documentCounts(of: [general, general, general, other], defaultLibrary: general)
        XCTAssertEqual(counts[general], 3)
        XCTAssertEqual(counts[other], 1)
    }

    /// The Documents screen lists a document with no library under the first one, so the count does too.
    func testADocumentWithNoLibraryCountsTowardTheFirst() {
        let general = UUID()
        let counts = ContainerService.documentCounts(of: [nil, general], defaultLibrary: general)
        XCTAssertEqual(counts[general], 2)
    }

    func testWithNoLibrariesNothingIsCounted() {
        XCTAssertTrue(ContainerService.documentCounts(of: [nil, nil], defaultLibrary: nil).isEmpty)
    }
}
