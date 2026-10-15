//
//  UnfinishedImportTextTests.swift
//  OpenIntelligenceTests
//
//  The text of a document whose import never finished is removed (5.7,
//  `RAGService.removeTextOfUnfinishedImports`). An import stores a document's text before its record,
//  and an app that ended mid-import left the text behind for good. These tests store text for a
//  made-up document id in the suite's own keyword store and remove it the way the launch check
//  does. Not covered: the launch check's own conditions (no import running, a list read from disk),
//  which need a launch.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class UnfinishedImportTextTests: XCTestCase {
    func testTextWithNoDocumentIsRemovedAndListedTextIsKept() async {
        let store = SQLiteFullTextService.shared
        let leftOver = UUID()
        let listed = UUID()
        let library = UUID()
        await store.store(text: "An import that never finished.", for: leftOver, containerId: library)
        await store.store(text: "A document that is in the list.", for: listed, containerId: library)

        let removed = await RAGService.removeStoredText(of: [leftOver, listed], notIn: [listed], using: store)

        XCTAssertEqual(removed, 1)
        let leftOverStillThere = await store.exists(documentId: leftOver)
        let listedStillThere = await store.exists(documentId: listed)
        XCTAssertFalse(leftOverStillThere)
        XCTAssertTrue(listedStillThere)
        await store.delete(for: listed)
    }

    func testNothingIsRemovedWhenEveryDocumentIsListed() async {
        let ids = [UUID(), UUID()]
        let removed = await RAGService.removeStoredText(of: ids, notIn: Set(ids), using: SQLiteFullTextService.shared)
        XCTAssertEqual(removed, 0)
    }
}
