//
//  DocumentDeletionTests.swift
//  OpenIntelligenceTests
//
//  "Delete Documents" asks first and deletes nothing it cannot find (5.7).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class DocumentDeletionTests: XCTestCase {
    func testTheQuestionNamesWhatGoes() {
        XCTAssertEqual(
            DocumentDeletion.question(for: ["Lease.pdf"]),
            "Delete “Lease.pdf”? Its passages and its Spotlight entries go with it.")
        XCTAssertEqual(
            DocumentDeletion.question(for: ["A.pdf", "B.txt"]),
            "Delete 2 documents, “A.pdf” and “B.txt”? Their passages and Spotlight entries go with them.")
        XCTAssertEqual(
            DocumentDeletion.question(for: ["A", "B", "C", "D", "E"]),
            "Delete 5 documents, “A”, “B”, “C” and 2 more? Their passages and Spotlight entries go with them.")
        XCTAssertEqual(DocumentDeletion.done(count: 1), "Deleted the document.")
        XCTAssertEqual(DocumentDeletion.done(count: 3), "Deleted 3 documents.")
        XCTAssertEqual(
            DocumentDeletion.done(count: 1, undoable: true), "Deleted the document. You can undo it for a few seconds.")
    }

    /// The safety the action rests on: a document the engine's list does not hold is never handed
    /// to `removeDocument`, whose save would otherwise write that list as it is.
    func testADocumentNotInTheLibrariesIsRefusedAndNothingIsDeleted() async throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let engine = RAGService()
        do {
            _ = try await DocumentDeletion.documents([UUID()], in: engine, attempts: 2)
            XCTFail("an unknown document was accepted")
        } catch let error as OIIntentError {
            XCTAssertEqual(error.message, "That document is no longer in your libraries.")
        }
    }
}
