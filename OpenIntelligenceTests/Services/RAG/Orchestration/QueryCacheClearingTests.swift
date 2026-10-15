//
//  QueryCacheClearingTests.swift
//  OpenIntelligenceTests
//
//  Every cached search's key names each library's documents with their passage counts, the embedding model
//  and the app's version (`RAGService.queryCacheKey`, 5.7), so once the documents or the version change, no
//  cached search can be found again. Through 5.6 nothing deleted a cached search: they kept the questions
//  asked and the passages found, a deleted library's text among them, until the app was removed. From 5.7
//  they are deleted when the documents or the version have changed (`RAGService.deleteUnreachableCachedSearches`,
//  after the documents are saved and at launch; `SQLiteFullTextService.deleteAllCachedQueries`).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class QueryCacheClearingTests: XCTestCase {
    private let lease = UUID()
    private let notes = UUID()

    func testTheTokenFollowsTheDocumentsAndTheVersion() {
        let token = RAGService.queryCacheDocumentsToken([(lease, 12), (notes, 3)], appVersion: "5.7 (486)")
        XCTAssertEqual(
            token, RAGService.queryCacheDocumentsToken([(notes, 3), (lease, 12)], appVersion: "5.7 (486)"),
            "the same documents in another order")
        XCTAssertNotEqual(
            token, RAGService.queryCacheDocumentsToken([(lease, 12)], appVersion: "5.7 (486)"), "a deletion")
        XCTAssertNotEqual(
            token, RAGService.queryCacheDocumentsToken([(lease, 12), (notes, 4)], appVersion: "5.7 (486)"),
            "a re-import with more passages")
        XCTAssertNotEqual(
            token, RAGService.queryCacheDocumentsToken([(lease, 12), (notes, 3)], appVersion: "5.7 (487)"),
            "an update")
    }

    func testCachedSearchesAreDeletedOnlyOnceTheDocumentsChange() async throws {
        let suite = "QueryCacheClearingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var deletions = 0
        let delete: () async -> Int = {
            deletions += 1
            return 2
        }

        let first = await RAGService.deleteUnreachableCachedSearches(
            documents: [(lease, 12)], defaults: defaults, deleteAll: delete)
        XCTAssertEqual(first, 2, "nothing recorded yet, as at the first launch after an update from 5.6")
        let second = await RAGService.deleteUnreachableCachedSearches(
            documents: [(lease, 12)], defaults: defaults, deleteAll: delete)
        XCTAssertNil(second, "the same documents: what was cached since can still be found, and stays")
        let third = await RAGService.deleteUnreachableCachedSearches(
            documents: [(lease, 12), (notes, 3)], defaults: defaults, deleteAll: delete)
        XCTAssertEqual(third, 2, "an import")
        let fourth = await RAGService.deleteUnreachableCachedSearches(
            documents: [(notes, 3)], defaults: defaults, deleteAll: delete)
        XCTAssertEqual(fourth, 2, "a deletion")
        XCTAssertEqual(deletions, 3)
    }

    func testDeletingTheCacheRemovesWhatWasCached() async {
        let library = UUID()
        let key = "how much is the deposit #libraries \(UUID().uuidString)"
        let cache = SQLiteFullTextService.shared
        await cache.cacheQuery(
            normalizedQuery: key, containerId: library, embedding: [0.1, 0.2], results: [passage(from: lease)])
        let cached = await cache.getCachedQuery(normalizedQuery: key, containerId: library)
        XCTAssertNotNil(cached, "written")
        let deleted = await cache.deleteAllCachedQueries()
        XCTAssertGreaterThanOrEqual(deleted, 1)
        let after = await cache.getCachedQuery(normalizedQuery: key, containerId: library)
        XCTAssertNil(after, "deleted")
    }

    private func passage(from document: UUID) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: document, content: "The deposit is 1,234 dollars.", embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: 0.5, rank: 1, sourceDocument: "Lease.pdf", pageNumber: nil)
    }
}
