//
//  SystemToolsAndScanTests.swift
//  OpenIntelligenceTests
//
//  The switches for the two system model tools, the passages one extractive scan looks at, and
//  the keyword join that used to build a string for every passage of the library.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SystemToolsAndScanTests: XCTestCase {
    private func passages(_ count: Int, document: UUID = UUID()) -> [DocumentChunk] {
        (0..<count).map {
            DocumentChunk(
                documentId: document, content: "passage \($0)", embedding: [], metadata: ChunkMetadata(chunkIndex: $0))
        }
    }

    func testBothSystemToolsAreOffUntilSwitchedOn() throws {
        guard #available(iOS 26.0, macOS 26.0, *) else { throw XCTSkip("needs FoundationModels") }
        let suite = "system-tools-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(SystemModelTools.isOCREnabled(defaults: defaults))
        XCTAssertFalse(SystemModelTools.isSpotlightSearchEnabled(defaults: defaults))
        XCTAssertTrue(SystemModelTools.systemTools(defaults: defaults).isEmpty)
        defaults.set(true, forKey: SystemModelTools.ocrKey)
        XCTAssertTrue(SystemModelTools.isOCREnabled(defaults: defaults))
        XCTAssertFalse(SystemModelTools.isSpotlightSearchEnabled(defaults: defaults))
    }

    func testTheSpecScanKeepsItsRuleForASmallLibraryAndIsBoundedForALargeOne() {
        let small = passages(300)
        let retrieved: Set<UUID> = [small[3].id, small[200].id]
        let scanned = RAGService.passagesToScanForSpecSniper(allChunks: small, excludeIds: retrieved)
        XCTAssertEqual(scanned.count, 298)
        XCTAssertFalse(scanned.contains { retrieved.contains($0.id) })

        let large = passages(144_247)
        let already: Set<UUID> = [large[0].id]
        let bounded = RAGService.passagesToScanForSpecSniper(allChunks: large, excludeIds: already)
        XCTAssertLessThanOrEqual(bounded.count, RAGService.specScanLimit)
        XCTAssertGreaterThan(bounded.count, RAGService.specScanLimit - 2)
        XCTAssertFalse(bounded.contains { already.contains($0.id) }, "a passage already retrieved is never scanned")
    }

    func testTheKeywordJoinFindsOnlyThePassagesItWasAskedFor() {
        let document = UUID()
        let library = passages(5_000, document: document)
        let wanted: Set<String> = ["\(document.uuidString)_17", "\(document.uuidString)_4999", "\(UUID().uuidString)_3"]
        let found = HybridSearchService.buildNeededChunkLookup(from: library, neededChunkIds: wanted)
        XCTAssertEqual(Set(found.keys), ["\(document.uuidString)_17", "\(document.uuidString)_4999"])
        XCTAssertEqual(found["\(document.uuidString)_17"]?.metadata.chunkIndex, 17)
        XCTAssertTrue(HybridSearchService.buildNeededChunkLookup(from: library, neededChunkIds: []).isEmpty)
    }
}
