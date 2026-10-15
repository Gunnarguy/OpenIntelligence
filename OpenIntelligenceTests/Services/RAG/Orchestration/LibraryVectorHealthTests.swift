//
//  LibraryVectorHealthTests.swift
//  OpenIntelligenceTests
//
//  Two ways a library looked healthy and couldn't be searched by meaning, closed in 5.7.
//
//  Empty vectors: a model that returned zeros for every passage built a library that read as healthy.
//  A library made in the iOS 27 Simulator on 2026-10-08 held 127 passages, every vector zero, and
//  9 of 11 answers in it failed Gate E whatever they said. An import now stops when most of a batch
//  comes back empty (`EmbeddingVectorCheck`), and opening a library re-embeds it when a sample of its
//  vectors is empty (`RAGService.vectorsLookEmpty`).
//
//  A document with no passages: the owner's backup of 2026-09-10 held a document of 455 passages
//  with none in the store and none in the keyword index, while the health check looked only at
//  whether the whole store was empty. `RAGService.documentsMissingPassages` names such documents so
//  they're rebuilt.
//
//  Not covered: the repair itself running on a device, and a model that fails there.
//

import XCTest

@testable import OpenIntelligence

final class LibraryVectorHealthTests: XCTestCase {
    private let real: [Float] = [0.12, -0.4, 0.33, 0.05]
    private let zero: [Float] = [0, 0, 0, 0]

    func testOnlyAVectorWithLengthIsUsable() {
        XCTAssertTrue(EmbeddingVectorCheck.isUsable(real))
        XCTAssertFalse(EmbeddingVectorCheck.isUsable(zero))
        XCTAssertFalse(EmbeddingVectorCheck.isUsable([]))
        XCTAssertFalse(EmbeddingVectorCheck.isUsable([0.1, .nan, 0.2]))
        XCTAssertFalse(EmbeddingVectorCheck.isUsable([0.1, .infinity]))
    }

    func testABatchMostlyEmptyStopsTheImport() {
        XCTAssertThrowsError(
            try EmbeddingVectorCheck.requireUsable([zero, zero, real], of: "Lease.pdf")
        ) { error in
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("2 of 3 passages of Lease.pdf"), message)
        }
        XCTAssertThrowsError(try EmbeddingVectorCheck.requireUsable(Array(repeating: zero, count: 127), of: "Samples"))
    }

    func testAFewEmptyVectorsDoNotEndALongImport() {
        let batch = Array(repeating: real, count: 99) + [zero]
        XCTAssertNoThrow(try EmbeddingVectorCheck.requireUsable(batch, of: "Big.txt"))
        XCTAssertNoThrow(
            try EmbeddingVectorCheck.requireUsable([real, zero], of: "Half.txt"), "half is not more than half")
        XCTAssertEqual(EmbeddingVectorCheck.unusableCount(batch), 1)
    }

    func testTheSampleIsSpreadAcrossTheStore() {
        XCTAssertEqual(RAGService.sampleIndices(count: 0), [])
        XCTAssertEqual(RAGService.sampleIndices(count: 3), [0, 1, 2])
        let sample = RAGService.sampleIndices(count: 144_247)
        XCTAssertEqual(sample.count, 64)
        XCTAssertEqual(sample.first, 0)
        XCTAssertGreaterThan(sample.last ?? 0, 140_000, "the end of the store is sampled too")
        XCTAssertEqual(Set(sample).count, sample.count)
    }

    func testAStoreLooksEmptyOnlyWhenNearlyAllOfItsSampleIs() {
        XCTAssertTrue(RAGService.vectorsLookEmpty(Array(repeating: zero, count: 64)))
        XCTAssertTrue(RAGService.vectorsLookEmpty(Array(repeating: zero, count: 58) + Array(repeating: real, count: 6)))
        XCTAssertFalse(
            RAGService.vectorsLookEmpty(Array(repeating: zero, count: 32) + Array(repeating: real, count: 32)))
        XCTAssertFalse(RAGService.vectorsLookEmpty([]), "a store that hands back no vectors proves nothing")
        XCTAssertFalse(RAGService.vectorsLookEmpty(Array(repeating: real, count: 64)))
    }

    private func document(_ name: String, passages: Int) -> Document {
        Document(
            filename: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), contentType: .pdf, totalChunks: passages)
    }

    func testADocumentWithNoPassagesInTheStoreIsNamed() {
        let manual = document("Manual.pdf", passages: 455)
        let lease = document("Lease.pdf", passages: 12)
        let blank = document("Blank.pdf", passages: 0)

        let missing = RAGService.documentsMissingPassages(
            [manual, lease, blank], passagesByDocument: [lease.id: 13])

        XCTAssertEqual(missing.map(\.filename), ["Manual.pdf"])
    }
}
