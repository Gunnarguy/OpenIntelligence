//
//  DeferredEnrichmentTests.swift
//  OpenIntelligenceTests
//
//  An import saves its document before the model work that improves it (the overview, the tags, the
//  suggested questions), and in the background that work waits for the app to be in front (5.7). On
//  2026-10-15 iOS ended a background import 53 s in, during that work, part of which came before the save.
//  These pin the list the waiting work is kept in. Not covered: an import ended by iOS on a device,
//  which is what closes the row.
//

import XCTest

@testable import OpenIntelligence

final class DeferredEnrichmentTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "DeferredEnrichmentTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testADocumentWaitsOnceAndLeavesWhenDone() {
        let library = UUID()
        let first = UUID()
        let second = UUID()
        RAGService.deferEnrichment(of: first, in: library, defaults: defaults)
        RAGService.deferEnrichment(of: first, in: library, defaults: defaults)
        RAGService.deferEnrichment(of: second, in: library, defaults: defaults)

        let waiting = RAGService.deferredEnrichments(defaults: defaults)
        XCTAssertEqual(waiting.map { $0.document }, [first, second], "each document is listed once, in order")
        XCTAssertTrue(waiting.allSatisfy { $0.library == library })

        RAGService.finishDeferredEnrichment(of: first, defaults: defaults)
        XCTAssertEqual(RAGService.deferredEnrichments(defaults: defaults).map { $0.document }, [second])
    }

    func testAnEntryThatCannotBeReadIsSkipped() {
        defaults.set(["not two ids", "\(UUID().uuidString) \(UUID().uuidString)"], forKey: RAGService.deferredEnrichmentKey)
        XCTAssertEqual(RAGService.deferredEnrichments(defaults: defaults).count, 1)
    }
}
