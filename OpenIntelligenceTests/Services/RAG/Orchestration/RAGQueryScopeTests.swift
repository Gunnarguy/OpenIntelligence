//
//  RAGQueryScopeTests.swift
//  OpenIntelligenceTests
//
//  "Ask About a Document" wrote the file name into the question and searched the whole library.
//  The scope that replaces it is a task-local set of document ids. These pin what it keeps, and
//  that it does not leak into a question asked outside it.
//

import XCTest

@testable import OpenIntelligenceEngine

final class RAGQueryScopeTests: XCTestCase {
    private func chunk(in document: UUID, _ text: String) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: text, embedding: [0],
            metadata: ChunkMetadata(chunkIndex: 0, wordCount: 2, characterCount: text.count))
    }

    private func retrieved(_ chunk: DocumentChunk) -> RetrievedChunk {
        RetrievedChunk(chunk: chunk, similarityScore: 0.5, rank: 1, sourceDocument: "x")
    }

    func testWithoutAScopeEverythingIsKept() {
        let chunks = [chunk(in: UUID(), "one"), chunk(in: UUID(), "two")]
        XCTAssertNil(RAGQueryScope.documentIds)
        XCTAssertEqual(RAGQueryScope.apply(to: chunks).map(\.content), ["one", "two"])
        XCTAssertEqual(RAGQueryScope.apply(to: chunks.map(retrieved)).count, 2)
    }

    func testAScopeKeepsOnlyTheNamedDocumentsPassages() {
        let lease = UUID()
        let rules = UUID()
        let chunks = [chunk(in: lease, "rent"), chunk(in: rules, "quiet hours"), chunk(in: lease, "late charge")]
        RAGQueryScope.$documentIds.withValue([lease]) {
            XCTAssertEqual(RAGQueryScope.apply(to: chunks).map(\.content), ["rent", "late charge"])
            XCTAssertEqual(RAGQueryScope.apply(to: chunks.map(retrieved)).map(\.chunk.content), ["rent", "late charge"])
        }
        XCTAssertEqual(RAGQueryScope.apply(to: chunks).count, 3, "the scope ends with the call that set it")
    }

    func testAScopeReachesWorkStartedInsideItAndNotBesideIt() async {
        let lease = UUID()
        let chunks = [chunk(in: lease, "rent"), chunk(in: UUID(), "quiet hours")]
        await RAGQueryScope.$documentIds.withValue([lease]) {
            async let inside = Task { RAGQueryScope.apply(to: chunks).count }.value
            let count = await inside
            XCTAssertEqual(count, 1, "a task started inside the scope inherits it")
        }
        let outside = await Task { RAGQueryScope.apply(to: chunks).count }.value
        XCTAssertEqual(outside, 2)
    }
}
