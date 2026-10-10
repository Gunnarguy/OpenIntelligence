//
//  LibraryMapSampleTests.swift
//  OpenIntelligenceTests
//
//  How many passages the Atlas and the other library maps read. Through 5.6 they read every one,
//  with every embedding, and analysed them on the main thread. On 2026-10-10 a library that an
//  import had taken to 63,000 passages held the main thread for more than ten seconds when the
//  Atlas opened, and iOS ended the app (watchdog 0x8BADF00D) with the import running. From 5.7
//  a map reads at most `RAGService.visualizationPassageLimit` passages, spread evenly across the
//  library, and the profile carries the library's own count beside the count it was built from.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class LibraryMapSampleTests: XCTestCase {
    private typealias Service = OpenIntelligence.RAGService

    func testALibraryThatFitsIsReadWhole() {
        XCTAssertEqual(Service.evenSampleIndices(count: 0, limit: 6_000), [])
        XCTAssertEqual(Service.evenSampleIndices(count: 5, limit: 6_000), [0, 1, 2, 3, 4])
        XCTAssertEqual(Service.evenSampleIndices(count: 6_000, limit: 6_000).count, 6_000)
        XCTAssertEqual(Service.evenSampleIndices(count: 5, limit: 0), [])
    }

    func testALargerLibraryIsReadEvenlyAndInOrder() {
        XCTAssertEqual(Service.evenSampleIndices(count: 10, limit: 4), [0, 2, 5, 7])

        // The size the import in pieces was heading for when the app was ended.
        let count = 163_000
        let limit = Service.visualizationPassageLimit
        let kept = Service.evenSampleIndices(count: count, limit: limit)
        XCTAssertEqual(kept.count, limit)
        XCTAssertEqual(kept.first, 0)
        XCTAssertLessThan(kept.last ?? count, count)
        let gaps = zip(kept, kept.dropFirst()).map { $1 - $0 }
        XCTAssertEqual(Set(gaps), [27, 28], "every step is the same size to within one passage")
        XCTAssertGreaterThan(kept.last ?? 0, count - 29, "the sample reaches the end of the library")
        XCTAssertEqual(kept, Service.evenSampleIndices(count: count, limit: limit), "the same passages every time")
    }

    private func chunks(_ count: Int, documentId: UUID, words: Int) -> [OpenIntelligence.DocumentChunk] {
        (0..<count).map {
            OpenIntelligence.DocumentChunk(
                documentId: documentId, content: "passage \($0) about the lease and the rent", embedding: [],
                metadata: OpenIntelligence.ChunkMetadata(chunkIndex: $0, wordCount: words))
        }
    }

    private func profile(
        of chunks: [OpenIntelligence.DocumentChunk], libraryPassageCount: Int?
    ) async throws -> LibraryProfile {
        let engine = LibraryVisualizationEngine.shared
        let containerId = UUID()
        await engine.analyze(
            containerId: containerId, documents: [], chunks: chunks, retrievalHistory: [],
            libraryPassageCount: libraryPassageCount)
        for _ in 0..<400 {
            if let profile = engine.currentProfile, profile.containerId == containerId { return profile }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("the profile was not built")
        throw CancellationError()
    }

    func testAProfileBuiltFromEveryPassageSaysSo() async throws {
        let built = try await profile(of: chunks(40, documentId: UUID(), words: 25), libraryPassageCount: 40)
        XCTAssertEqual(built.chunkCount, 40)
        XCTAssertEqual(built.libraryPassageCount, 40)
        XCTAssertEqual(built.totalWords, 1_000)
        XCTAssertFalse(built.isSampled)

        // A caller that passes no count gets what it always got.
        let asBefore = try await profile(of: chunks(40, documentId: UUID(), words: 25), libraryPassageCount: nil)
        XCTAssertEqual(asBefore.libraryPassageCount, 40)
        XCTAssertFalse(asBefore.isSampled)
    }

    func testAProfileBuiltFromASampleCarriesTheLibrarysOwnCount() async throws {
        let built = try await profile(of: chunks(40, documentId: UUID(), words: 25), libraryPassageCount: 1_000)
        XCTAssertEqual(built.chunkCount, 40, "what the map was drawn from")
        XCTAssertEqual(built.libraryPassageCount, 1_000, "what the library holds")
        XCTAssertEqual(built.avgChunkSize, 25)
        XCTAssertEqual(built.totalWords, 25_000, "scaled from the sample to the library")
        XCTAssertTrue(built.isSampled)
    }
}
