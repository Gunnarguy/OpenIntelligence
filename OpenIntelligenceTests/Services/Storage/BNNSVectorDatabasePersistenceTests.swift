//
//  BNNSVectorDatabasePersistenceTests.swift
//  OpenIntelligenceTests
//
//  What the vector store's files look like after a save or a delete that was cut off, and what
//  the next load makes of them. Through 5.6 a save wrote the metadata first and the vectors
//  second, and a load that found the two disagreeing deleted the whole store: every document's
//  vectors in the library. An import in pieces saves once a piece, forty-five times for one
//  88 MB file, so from 5.7 the vectors are written first, and a load ignores vectors the
//  metadata does not list and never writes or removes a file itself. The file layout is the same
//  as before.
//
//  The rule the loader depends on: a cut-off save leaves MORE vectors than the metadata lists,
//  all of them after the listed ones, and a cut-off delete leaves FEWER. A delete that could
//  leave as many or more, in another order, would be loaded with every passage paired with the
//  wrong vector and no sign of it, which is why a delete writes out what is unsaved first.
//

import XCTest

@testable import OpenIntelligenceEngine

/// What a test throws to end a save part-way.
nonisolated private struct CutOff: Error {}

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

    private func listedPassages() throws -> [DocumentChunk] {
        try JSONDecoder().decode([DocumentChunk].self, from: Data(contentsOf: metaURL))
    }

    /// Every one of `expected` is in the store, with its own text and its own vector, and the
    /// store holds nothing else.
    private func assertHoldsExactly(
        _ store: BNNSVectorDatabase, _ expected: [DocumentChunk], _ message: String = "",
        file: StaticString = #filePath, line: UInt = #line
    ) async throws {
        let count = try await store.count()
        XCTAssertEqual(count, expected.count, message, file: file, line: line)
        let records = try await store.passageRecords()
        XCTAssertEqual(records.map(\.id), expected.map(\.id), message, file: file, line: line)
        let byPosition = await store.getEmbeddings(forIndices: Array(expected.indices))
        XCTAssertEqual(byPosition, expected.map(\.embedding), message, file: file, line: line)
        for chunk in expected {
            let text = try await store.chunks(withIDs: [chunk.id])
            XCTAssertEqual(text.map(\.content), [chunk.content], message, file: file, line: line)
            let vector = await store.getEmbeddings(forChunkIDs: [chunk.id])
            XCTAssertEqual(vector, [chunk.embedding], message, file: file, line: line)
        }
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

    /// A save leaves nothing beside the store's three files: its temporary files are made where
    /// the system prepares replacements, not in the library's folder.
    func testASaveLeavesOnlyTheThreeFiles() async throws {
        let documentId = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<3, documentId: documentId))
        try await store.persist()
        try await store.deleteChunks(forDocument: UUID())
        try await store.storeBatch(chunks: chunks(3..<5, documentId: UUID()))
        try await store.persist()
        try await store.deleteChunks(forDocument: documentId)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        XCTAssertEqual(
            names,
            ["vector_database_test_meta.json", "vector_database_test_norms.bin", "vector_database_test_vectors.bin"])
    }

    /// The save was cut off after the new vectors were written and before the metadata that
    /// names them: the vectors file holds two more vectors than the metadata lists.
    func testASaveCutOffAfterItsVectorsLoadsAsTheStoreWasBeforeIt() async throws {
        let documentId = UUID()
        let first = chunks(0..<3, documentId: documentId)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: first)
        try await store.persist()

        let extra = (embedding(7) + embedding(8)).withUnsafeBytes { Data($0) }
        let handle = try FileHandle(forWritingTo: vectorsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: extra)
        try handle.close()
        XCTAssertEqual(fileSize(vectorsURL), 5 * bytesPerVector)

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(reloaded, first, "the three recorded chunks, each with its own vector")
        XCTAssertEqual(
            fileSize(vectorsURL), 5 * bytesPerVector,
            "a load reads and does not write: the unlisted vectors are ignored, not cut off the file")
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path))

        let found = try await reloaded.search(embedding: embedding(1), topK: 1)
        XCTAssertEqual(found.first?.chunk.content, "chunk 1")

        // And the store goes on from there. Its next save writes the vectors file at its right
        // length, with the new chunk's vector straight after the three and not after the two
        // that were never recorded.
        let fourth = chunks(3..<4, documentId: documentId)
        try await reloaded.storeBatch(chunks: fourth)
        try await reloaded.persist()
        XCTAssertEqual(fileSize(vectorsURL), 4 * bytesPerVector)
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(again, first + fourth)
    }

    /// After such a load, a save with nothing new still puts the vectors file right.
    func testASaveWithNothingNewStillCutsOffVectorsThatWereNeverRecorded() async throws {
        let documentId = UUID()
        let first = chunks(0..<3, documentId: documentId)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: first)
        try await store.persist()
        let handle = try FileHandle(forWritingTo: vectorsURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: embedding(9).withUnsafeBytes { Data($0) })
        try handle.close()

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await reloaded.persist()
        XCTAssertEqual(fileSize(vectorsURL), 3 * bytesPerVector)
        try await assertHoldsExactly(reloaded, first)
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(again, first)
    }

    /// The other way round is not repairable: with fewer vectors than the metadata lists there is
    /// no telling which chunks lost theirs. The store loads empty, as it always did, and the
    /// library's empty-index repair takes over. The files are left as they are: the load may be
    /// a second store looking at files the first is in the middle of writing.
    func testFewerVectorsThanTheMetadataListsLoadsEmptyAndLeavesTheFiles() async throws {
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
        let found = try await reloaded.search(embedding: embedding(1), topK: 3)
        XCTAssertTrue(found.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: metaURL.path), "a load removes nothing")
        XCTAssertEqual(fileSize(vectorsURL), 2 * bytesPerVector, "a load writes nothing")
        XCTAssertEqual(try listedPassages().count, 3)

        // The store that loaded empty writes all three files the first time it saves, and what
        // was there before is gone from them.
        let fresh = chunks(10..<12, documentId: UUID())
        try await reloaded.storeBatch(chunks: fresh)
        try await reloaded.persist()
        XCTAssertEqual(fileSize(vectorsURL), 2 * bytesPerVector)
        XCTAssertEqual(try listedPassages().map(\.id), fresh.map(\.id))
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(again, fresh)
    }

    /// A vectors file that is longer by something other than whole vectors is damage, not a
    /// cut-off save, and is not read as one.
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

    #if DEBUG
    /// A save whose metadata write fails after its vectors were written. Ended there, the next
    /// launch has the store as it was before the save. Not ended, the store still holds the new
    /// passages and its next save writes them.
    func testASaveThatFailsAtItsMetadataIsFinishedByTheNextSave() async throws {
        let documentId = UUID()
        let first = chunks(0..<3, documentId: documentId)
        let second = chunks(3..<6, documentId: documentId)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: first)
        try await store.persist()

        try await store.storeBatch(chunks: second)
        await store.interruptMetadataWrites { _ in throw CutOff() }
        do {
            try await store.persist()
            XCTFail("the save finished; it was meant to fail at its metadata")
        } catch is CutOff {}
        XCTAssertEqual(fileSize(vectorsURL), 6 * bytesPerVector)
        XCTAssertEqual(try listedPassages().count, 3)

        // Ended here: the next launch.
        let afterACrash = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(afterACrash, first, "as the store was before the save")

        // Not ended: the same store, still holding all six, saves again.
        await store.interruptMetadataWrites(nil)
        try await assertHoldsExactly(store, first + second, "in memory, before the second save")
        try await store.persist()
        XCTAssertEqual(try listedPassages().map(\.id), (first + second).map(\.id))
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(reloaded, first + second)
    }

    /// A delete with passages no save has written yet, ended after it wrote the vectors that
    /// stay and before the metadata. It has to leave fewer vectors than the metadata lists, so
    /// that the next launch loads the store empty. If the delete did not write the unsaved
    /// passages out first, the files here would be five vectors and four listed passages, which
    /// a load reads as a cut-off save: four passages, each with another passage's vector.
    func testADeleteCutOffAfterItsVectorsNeverPairsAPassageWithAnotherPassagesVector() async throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks(0..<2, documentId: a) + chunks(2..<4, documentId: b))
        try await store.persist()
        try await store.storeBatch(chunks: chunks(4..<7, documentId: c))  // not saved

        // The delete writes the unsaved passages out (its first metadata write), then the
        // vectors that stay, then the metadata again.
        await store.interruptMetadataWrites { write in if write == 2 { throw CutOff() } }
        do {
            try await store.deleteChunks(forDocument: a)
            XCTFail("the delete finished; it was meant to be cut off at its second metadata write")
        } catch is CutOff {}

        XCTAssertEqual(fileSize(vectorsURL), 5 * bytesPerVector, "the vectors that stay")
        XCTAssertEqual(try listedPassages().count, 7, "every passage, the three unsaved ones included")

        let afterACrash = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await afterACrash.count()
        XCTAssertEqual(count, 0, "fewer vectors than passages: loaded empty, never mispaired")
    }

    /// The same delete when the app is not ended: its last metadata write failed. The store knows
    /// its files disagree, and the next save writes the metadata. Before 5.7's review fix nothing
    /// retried it, and the next launch found fewer vectors than passages and an empty library.
    func testADeleteThatFailsAtItsMetadataIsFinishedByTheNextSave() async throws {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let ofA = chunks(0..<2, documentId: a)
        let ofB = chunks(2..<4, documentId: b)
        let ofC = chunks(4..<7, documentId: c)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: ofA + ofB)
        try await store.persist()
        try await store.storeBatch(chunks: ofC)

        await store.interruptMetadataWrites { write in if write == 2 { throw CutOff() } }
        do {
            try await store.deleteChunks(forDocument: a)
            XCTFail("the delete finished; it was meant to fail at its second metadata write")
        } catch is CutOff {}
        await store.interruptMetadataWrites(nil)

        try await assertHoldsExactly(store, ofB + ofC, "in memory the delete is done")
        try await store.persist()
        XCTAssertEqual(try listedPassages().map(\.id), (ofB + ofC).map(\.id))
        XCTAssertEqual(fileSize(vectorsURL), 5 * bytesPerVector)
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(reloaded, ofB + ofC)
    }

    /// The first step of that delete failing: nothing has been removed yet, in memory or on disk.
    func testADeleteWhoseFirstSaveFailsRemovesNothing() async throws {
        let a = UUID()
        let b = UUID()
        let ofA = chunks(0..<2, documentId: a)
        let ofB = chunks(2..<5, documentId: b)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: ofA)
        try await store.persist()
        try await store.storeBatch(chunks: ofB)

        await store.interruptMetadataWrites { _ in throw CutOff() }
        do {
            try await store.deleteChunks(forDocument: a)
            XCTFail("the delete finished; its first save was meant to fail")
        } catch is CutOff {}
        await store.interruptMetadataWrites(nil)

        try await assertHoldsExactly(store, ofA + ofB, "nothing was removed")
        let afterACrash = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(afterACrash, ofA, "as the store was at its last whole save")

        try await store.deleteChunks(forDocument: a)
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await assertHoldsExactly(reloaded, ofB)
    }
    #endif
}
