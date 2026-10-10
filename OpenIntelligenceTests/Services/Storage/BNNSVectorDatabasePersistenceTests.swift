//
//  BNNSVectorDatabasePersistenceTests.swift
//  OpenIntelligenceTests
//
//  What the vector store's files look like after a save that was cut off, and what the next load
//  makes of them. Through 5.6 a save wrote the metadata first and the vectors second, and a load
//  that found the two disagreeing deleted the whole store: every document's vectors in the
//  library. An import in pieces saves once a piece, forty-five times for one 88 MB file, so from
//  5.7 the vectors are written first and a load trims vectors the metadata does not list.
//  The file layout is the same as before.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class BNNSVectorDatabasePersistenceTests: XCTestCase {
    private let dimension = 4
    private var directory: URL!
    private var storageURL: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("bnns-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("vector_database_test.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var vectorsURL: URL { directory.appendingPathComponent("vector_database_test_vectors.bin") }
    private var metaURL: URL { directory.appendingPathComponent("vector_database_test_meta.json") }
    private var bytesPerVector: Int { dimension * MemoryLayout<Float>.size }

    private func embedding(_ number: Int) -> [Float] {
        // Each chunk points along its own axis, so a search for one finds that one.
        (0..<dimension).map { $0 == number % dimension ? 1 : 0.01 * Float(number + 1) }
    }

    private func chunks(_ numbers: Range<Int>, documentId: UUID) -> [DocumentChunk] {
        numbers.map {
            DocumentChunk(
                documentId: documentId, content: "chunk \($0)", embedding: embedding($0),
                metadata: ChunkMetadata(chunkIndex: $0))
        }
    }

    private func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? -1
    }

    func testTwoSavesLeaveVectorsThatMatchTheMetadata() async throws {
        let documentId = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<2, documentId: documentId))
        try await store.persist()
        try await store.storeBatch(chunks: chunks(2..<5, documentId: documentId))
        try await store.persist()
        XCTAssertEqual(fileSize(vectorsURL), 5 * bytesPerVector)

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 5)
        let fifth = await reloaded.getEmbeddings(forIndices: [4])
        XCTAssertEqual(fifth, [embedding(4)])
    }

    /// The save was cut off after the new vectors were written and before the metadata that
    /// names them: the vectors file holds two more vectors than the metadata lists.
    func testASaveCutOffAfterItsVectorsLoadsAsTheStoreWasBeforeIt() async throws {
        let documentId = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<3, documentId: documentId))
        try await store.persist()

        let extra = (embedding(7) + embedding(8)).withUnsafeBytes { Data($0) }
        let handle = try FileHandle(forWritingTo: vectorsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: extra)
        try handle.close()
        XCTAssertEqual(fileSize(vectorsURL), 5 * bytesPerVector)

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 3, "the three recorded chunks are still there")
        XCTAssertEqual(fileSize(vectorsURL), 3 * bytesPerVector, "the unlisted vectors were cut off")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))

        let found = try await reloaded.search(embedding: embedding(1), topK: 1)
        XCTAssertEqual(found.first?.chunk.content, "chunk 1")

        // And the store goes on from there.
        try await reloaded.storeBatch(chunks: chunks(3..<4, documentId: documentId))
        try await reloaded.persist()
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let countAgain = try await again.count()
        XCTAssertEqual(countAgain, 4)
    }

    /// The other way round is not repairable: with fewer vectors than the metadata lists there is
    /// no telling which chunks lost theirs. The store is cleared, as it always was, and the
    /// library's empty-index repair takes over. Deleting a document can still leave this if the
    /// app is ended in the middle of it.
    func testFewerVectorsThanTheMetadataListsStillClearsTheStore() async throws {
        let documentId = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<3, documentId: documentId))
        try await store.persist()

        let handle = try FileHandle(forWritingTo: vectorsURL)
        try handle.truncate(atOffset: UInt64(2 * bytesPerVector))
        try handle.close()

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metaURL.path))
    }

    /// A vectors file that is longer by something other than whole vectors is damage, not a
    /// cut-off save, and is not trimmed into shape.
    func testAVectorsFileLongerByPartOfAVectorIsNotRepaired() async throws {
        let documentId = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<3, documentId: documentId))
        try await store.persist()

        let handle = try FileHandle(forWritingTo: vectorsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1, 2, 3]))
        try handle.close()

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 0)
    }
}
