//
//  VectorStorePassageIndexTests.swift
//  OpenIntelligenceTests
//
//  From 5.7 the vector store no longer decodes its metadata file to open a library. It walks the
//  file once for each passage's place and a few of its values, and decodes a passage when it is
//  asked for. The file is the file it was: one JSON array of passages. These tests hold the two
//  halves of that to each other. Whatever the walk reads, the decoder reads the same. Whatever
//  the store writes, a plain decode of the whole array reads back, which is all an older build
//  does. And the vectors stay lined up with the passages through saves, deletes and reloads.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class VectorStorePassageIndexTests: XCTestCase {
    private let dimension = 4
    private var directory: URL!
    private var storageURL: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("passages-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appendingPathComponent("vector_database_test.json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var metaURL: URL { directory.appendingPathComponent("vector_database_test_meta.json") }
    private var vectorsURL: URL { directory.appendingPathComponent("vector_database_test_vectors.bin") }
    private var normsURL: URL { directory.appendingPathComponent("vector_database_test_norms.bin") }

    /// A vector no other number shares, so a search for it has one right answer.
    private func embedding(_ number: Int) -> [Float] {
        let angle = Float(number) * 0.37
        return [cos(angle), sin(angle), cos(angle * 1.7 + 0.3), Float(number % 97) / 97]
    }

    /// Text that is hard on anything that reads JSON by hand: quotes, backslashes, brackets and
    /// braces, the bytes that end one passage and start the next, a line that looks like one of
    /// the keys the walk reads, text outside ASCII, and a control character.
    private func awkwardText(_ number: Int) -> String {
        switch number % 8 {
        case 0: return "plain passage \(number)"
        case 1: return "she said \"stop\" and then \\\"again\\\" in passage \(number)"
        case 2: return "ends with a backslash \(number) \\"
        case 3: return "braces { [ ] } and },{\" in the middle of passage \(number)"
        case 4: return "looks like a key: \"chunkIndex\":999,\"id\":\"nope\",\"metadata\":{\"pageNumber\":7} \(number)"
        case 5: return "Ελληνικά 中文 العربية 🧪 passage \(number)"
        case 6: return "line one\nline two\ttabbed\u{0001} passage \(number)"
        default: return String(repeating: "\\", count: number % 5 + 1) + "\" passage \(number)"
        }
    }

    private func chunk(
        _ number: Int, documentId: UUID, text: String? = nil, page: Int? = nil,
        level: ChunkAbstractionLevel = .detail
    ) -> DocumentChunk {
        DocumentChunk(
            documentId: documentId,
            content: text ?? awkwardText(number),
            parentContent: number % 3 == 0 ? "parent of \(number) with a \"quote\"" : nil,
            contextualPrefix: number % 4 == 0 ? "[From file \(number).txt] " : nil,
            embedding: embedding(number),
            metadata: ChunkMetadata(
                chunkIndex: number,
                pageNumber: page,
                sectionTitle: number % 2 == 0 ? "Section {\(number)}" : nil,
                keywords: ["alpha", "be\"ta", "gam\\ma"],
                structureType: "paragraph",
                entities: ["Entity \(number)"],
                abbreviations: ["chunkIndex": "a value under a key the walk also looks for", "id": "another"],
                abstractionLevel: level,
                sectionPath: ["Top", "Sub [\(number)]"]
            )
        )
    }

    private func stripped(_ chunk: DocumentChunk) -> DocumentChunk {
        DocumentChunk(
            id: chunk.id, documentId: chunk.documentId, content: chunk.content,
            parentContent: chunk.parentContent, contextualPrefix: chunk.contextualPrefix, embedding: [],
            metadata: chunk.metadata)
    }

    private func assertSamePassage(
        _ found: DocumentChunk?, _ expected: DocumentChunk, _ message: String = "", file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let found else {
            XCTFail("no passage. \(message)", file: file, line: line)
            return
        }
        XCTAssertEqual(found.id, expected.id, message, file: file, line: line)
        XCTAssertEqual(found.documentId, expected.documentId, message, file: file, line: line)
        XCTAssertEqual(found.content, expected.content, message, file: file, line: line)
        XCTAssertEqual(found.parentContent, expected.parentContent, message, file: file, line: line)
        XCTAssertEqual(found.contextualPrefix, expected.contextualPrefix, message, file: file, line: line)
        XCTAssertEqual(found.metadata.chunkIndex, expected.metadata.chunkIndex, message, file: file, line: line)
        XCTAssertEqual(found.metadata.pageNumber, expected.metadata.pageNumber, message, file: file, line: line)
        XCTAssertEqual(found.metadata.keywords, expected.metadata.keywords, message, file: file, line: line)
        XCTAssertEqual(found.metadata.abbreviations, expected.metadata.abbreviations, message, file: file, line: line)
        XCTAssertEqual(found.metadata.sectionPath, expected.metadata.sectionPath, message, file: file, line: line)
        XCTAssertEqual(
            found.metadata.abstractionLevel, expected.metadata.abstractionLevel, message, file: file, line: line)
    }

    /// The three files the way a 5.6 build wrote them: the whole array through `JSONEncoder`.
    /// With `metadata`, those bytes are the metadata file instead.
    private func writeStoreAsFivePointSixDid(_ chunks: [DocumentChunk], metadata: Data? = nil) throws {
        try (metadata ?? JSONEncoder().encode(chunks.map(stripped))).write(to: metaURL)
        var vectors = Data()
        var norms: [Float] = []
        for chunk in chunks {
            chunk.embedding.withUnsafeBytes { vectors.append(contentsOf: $0) }
            norms.append(sqrt(chunk.embedding.reduce(0) { $0 + $1 * $1 }))
        }
        try vectors.write(to: vectorsURL)
        try norms.withUnsafeBytes { Data($0) }.write(to: normsURL)
    }

    // MARK: - The walk against the decoder

    func testTheWalkReadsWhatTheDecoderReads() throws {
        let documents = [UUID(), UUID(), UUID()]
        let chunks = (0..<400).map {
            chunk(
                $0, documentId: documents[$0 % 3], page: $0 % 5 == 0 ? nil : $0 % 40,
                level: $0 % 50 == 0 ? .documentSummary : .detail)
        }
        let data = try JSONEncoder().encode(chunks.map(stripped))
        let slots = try XCTUnwrap(PassageFileIndex.scan(data))
        XCTAssertEqual(slots.count, chunks.count)
        let decoder = JSONDecoder()
        for (index, slot) in slots.enumerated() {
            let expected = chunks[index]
            XCTAssertEqual(slot.record.id, expected.id)
            XCTAssertEqual(slot.record.documentId, expected.documentId)
            XCTAssertEqual(slot.record.chunkIndex, expected.metadata.chunkIndex)
            XCTAssertEqual(slot.record.pageNumber, expected.metadata.pageNumber)
            XCTAssertEqual(slot.record.abstractionLevel, expected.metadata.abstractionLevel)
            // The bytes the slot points at are that passage and nothing else.
            let bytes = data[(data.startIndex + slot.offset)..<(data.startIndex + slot.offset + slot.length)]
            assertSamePassage(try decoder.decode(DocumentChunk.self, from: bytes), expected, "passage \(index)")
        }
    }

    func testAFileWithSpaceAndNewLinesBetweenEverythingIsWalkedTheSame() throws {
        let document = UUID()
        let chunks = (0..<60).map { chunk($0, documentId: document, page: $0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(chunks.map(stripped))
        let slots = try XCTUnwrap(PassageFileIndex.scan(data))
        XCTAssertEqual(slots.map(\.record.id), chunks.map(\.id))
        XCTAssertEqual(slots.map(\.record.chunkIndex), Array(0..<60))
        XCTAssertEqual(slots.map(\.record.pageNumber), (0..<60).map { Optional($0) })
    }

    func testSeveralStretchesFindWhatOneWalkFinds() throws {
        let document = UUID()
        // Past the size at which the walk splits up, with the text that most looks like a
        // boundary in every eighth passage.
        let filler = String(repeating: "lorem ipsum dolor sit amet ", count: 40)
        let chunks = (0..<9_000).map { chunk($0, documentId: document, text: awkwardText($0) + " " + filler) }
        let data = try JSONEncoder().encode(chunks.map(stripped))
        XCTAssertGreaterThan(data.count, PassageFileIndex.parallelThresholdBytes)
        let one = try XCTUnwrap(PassageFileIndex.scan(data, threads: 1))
        for threads in [2, 3, 8, 16] {
            let several = try XCTUnwrap(PassageFileIndex.scan(data, threads: threads))
            XCTAssertEqual(several.count, one.count, "\(threads) threads")
            XCTAssertEqual(several.map(\.offset), one.map(\.offset), "\(threads) threads")
            XCTAssertEqual(several.map(\.length), one.map(\.length), "\(threads) threads")
            XCTAssertEqual(several.map(\.id), one.map(\.id), "\(threads) threads")
        }
        XCTAssertEqual(one.map(\.id), chunks.map(\.id))
    }

    func testNumbersWrittenAnotherWayAreReadByTheDecoder() throws {
        let id = UUID()
        let document = UUID()
        let json = """
            [{"documentId":"\(document.uuidString.lowercased())","metadata":{"chunkIndex":3.0,"pageNumber":1e1,"keywords":[]},"embedding":[],"content":"x","id":"\(id.uuidString)"}]
            """
        let data = Data(json.utf8)
        let slots = try XCTUnwrap(PassageFileIndex.scan(data))
        let decoded = try JSONDecoder().decode([DocumentChunk].self, from: data)
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots[0].record.id, decoded[0].id)
        XCTAssertEqual(slots[0].record.documentId, decoded[0].documentId)
        XCTAssertEqual(slots[0].record.chunkIndex, decoded[0].metadata.chunkIndex)
        XCTAssertEqual(slots[0].record.pageNumber, decoded[0].metadata.pageNumber)
        XCTAssertEqual(slots[0].record.abstractionLevel, .detail)
    }

    func testBytesThatAreNotAPassageArrayAreRefused() throws {
        let document = UUID()
        let good = try JSONEncoder().encode([stripped(chunk(1, documentId: document))])
        XCTAssertNotNil(PassageFileIndex.scan(good))
        XCTAssertEqual(PassageFileIndex.scan(Data("[]".utf8))?.count, 0)
        XCTAssertEqual(PassageFileIndex.scan(Data(" [ ] \n".utf8))?.count, 0)
        for bad in ["", "{}", "[1,2]", "[{}]", "[{\"id\":\"not a uuid\"}]", "null", "[{\"id\":"] {
            XCTAssertNil(PassageFileIndex.scan(Data(bad.utf8)), bad)
        }
        // Cut off anywhere, the file is refused, never read short.
        for cut in [1, good.count / 3, good.count / 2, good.count - 2, good.count - 1] {
            XCTAssertNil(PassageFileIndex.scan(good.prefix(cut)), "cut at \(cut) of \(good.count)")
        }
        // Something after the array is not ignored.
        XCTAssertNil(PassageFileIndex.scan(good + Data("x".utf8)))
    }

    /// One passage as JSON text, with whatever a test wants spliced into it.
    private func passageJSON(
        id: UUID, document: UUID, idKey: String = "\"id\"", top: String = "", metadata: String = ""
    ) -> String {
        "{\(idKey):\"\(id.uuidString)\",\"documentId\":\"\(document.uuidString)\",\"content\":\"x\",\"embedding\":[],"
            + "\"metadata\":{\"chunkIndex\":3,\"keywords\":[]\(metadata)}\(top)}"
    }

    /// Where the walk and the decoder both read the bytes, they read the same passages. Returns
    /// what each made of them.
    @discardableResult
    private func assertTheWalkNeverDisagrees(
        _ json: String, file: StaticString = #filePath, line: UInt = #line
    ) -> (slots: [PassageSlot]?, decoded: [DocumentChunk]?) {
        let data = Data(json.utf8)
        let slots = PassageFileIndex.scan(data)
        let decoded = try? JSONDecoder().decode([DocumentChunk].self, from: data)
        if let slots, let decoded {
            XCTAssertEqual(slots.map(\.record.id), decoded.map(\.id), json, file: file, line: line)
            XCTAssertEqual(slots.map(\.record.documentId), decoded.map(\.documentId), json, file: file, line: line)
            XCTAssertEqual(
                slots.map(\.record.chunkIndex), decoded.map(\.metadata.chunkIndex), json, file: file, line: line)
            XCTAssertEqual(
                slots.map(\.record.pageNumber), decoded.map(\.metadata.pageNumber), json, file: file, line: line)
            XCTAssertEqual(
                slots.map(\.record.abstractionLevel), decoded.map(\.metadata.abstractionLevel), json, file: file,
                line: line)
        }
        return (slots, decoded)
    }

    /// A key the walk reads, written twice or written with an escape, is the decoder's to read:
    /// which of two values counts, and what an escaped key spells, are its rules.
    func testRepeatedAndEscapedKeysAreReadTheWayTheDecoderReadsThem() throws {
        let first = UUID()
        let second = UUID()
        let document = UUID()
        let other = UUID()
        let cases = [
            // "id" twice, at the start and at the end.
            "[" + passageJSON(id: first, document: document, top: ",\"id\":\"\(second.uuidString)\"") + "]",
            // "documentId" twice.
            "[" + passageJSON(id: first, document: document, top: ",\"documentId\":\"\(other.uuidString)\"") + "]",
            // "metadata" twice, with another number in the second.
            "[" + passageJSON(id: first, document: document, top: ",\"metadata\":{\"chunkIndex\":9,\"keywords\":[]}") + "]",
            // The numbers inside the metadata twice.
            "[" + passageJSON(id: first, document: document, metadata: ",\"chunkIndex\":8") + "]",
            "[" + passageJSON(id: first, document: document, metadata: ",\"pageNumber\":4,\"pageNumber\":6") + "]",
            "[" + passageJSON(id: first, document: document, metadata: ",\"abstractionLevel\":0,\"abstractionLevel\":2") + "]",
            // The same keys spelled with an escape, alone and beside the plain spelling.
            "[" + passageJSON(id: first, document: document, idKey: "\"\\u0069d\"") + "]",
            "[" + passageJSON(id: first, document: document, top: ",\"\\u0069d\":\"\(second.uuidString)\"") + "]",
            "[" + passageJSON(id: first, document: document, top: ",\"document\\u0049d\":\"\(other.uuidString)\"") + "]",
            "[" + passageJSON(id: first, document: document, metadata: ",\"page\\u004eumber\":11") + "]",
            "[" + passageJSON(id: first, document: document, metadata: ",\"abstraction\\u004cevel\":2") + "]",
            "[" + passageJSON(id: first, document: document, metadata: ",\"chunk\\u0049ndex\":12") + "]",
            // An escaped key the walk does not read changes nothing.
            "[" + passageJSON(id: first, document: document, top: ",\"not\\u0065d\":1") + "]",
        ]
        var bothRead = 0
        for json in cases {
            let made = assertTheWalkNeverDisagrees(json)
            if made.slots != nil, made.decoded != nil { bothRead += 1 }
            // What the decoder reads, the walk does not refuse.
            if made.decoded != nil { XCTAssertNotNil(made.slots, json) }
        }
        XCTAssertGreaterThan(bothRead, 0, "none of the cases was read by both, so nothing was compared")
    }

    /// The walk skips the values it does not read. It still refuses a file whose skipped values
    /// are not JSON as far as it looks: a bare word that is not a number, true, false or null,
    /// and a bracket closed by the other kind.
    func testValuesThatAreNotJSONAreRefusedAndTheOnesThatAreAreSkipped() throws {
        let id = UUID()
        let document = UUID()
        let good = [
            "0", "-0", "10", "-12.5e-3", "1E+5", "0.5", "true", "false", "null", "[]", "{}", "\"]}\"",
            "[[],{},[{\"a\":[null,true,false,\"]}\",-1.5]}]]", "{\"a\":{\"b\":[1,{\"c\":\"}\"}]}}",
        ]
        for value in good {
            for json in [
                "[" + passageJSON(id: id, document: document, top: ",\"extra\":\(value)") + "]",
                "[" + passageJSON(id: id, document: document, metadata: ",\"extra\":\(value)") + "]",
            ] {
                let made = assertTheWalkNeverDisagrees(json)
                XCTAssertEqual(made.slots?.count, 1, json)
                XCTAssertEqual(made.decoded?.count, 1, json)
            }
        }
        let bad = [
            "", "tru", "nul", "True", "+1", ".5", "0x10", "NaN", "Infinity", "1 2",
            "[1,2}", "{\"a\":[1}]", "{\"a\":1]", "[[1]", "[1]]",
        ]
        for value in bad {
            for json in [
                "[" + passageJSON(id: id, document: document, top: ",\"extra\":\(value)") + "]",
                "[" + passageJSON(id: id, document: document, metadata: ",\"extra\":\(value)") + "]",
            ] {
                XCTAssertNil(PassageFileIndex.scan(Data(json.utf8)), json)
                XCTAssertNil(try? JSONDecoder().decode([DocumentChunk].self, from: Data(json.utf8)), json)
            }
        }
        // Four that are not JSON numbers and that `JSONDecoder` takes all the same under a key
        // nothing decodes: it checks a number's digits when the number is read, and nothing
        // reads these (measured on macOS 27.0 and in the iOS 27.0 Simulator, 2026-10-12;
        // `JSONSerialization` refuses all four). The walk refuses them, which costs nothing: a
        // file the walk refuses is decoded whole
        // (`testAFileTheWalkCannotFollowIsOpenedByDecodingItWhole`).
        for value in ["01", "1.", "1e", "-"] {
            for json in [
                "[" + passageJSON(id: id, document: document, top: ",\"extra\":\(value)") + "]",
                "[" + passageJSON(id: id, document: document, metadata: ",\"extra\":\(value)") + "]",
            ] {
                XCTAssertNil(PassageFileIndex.scan(Data(json.utf8)), json)
            }
        }
    }

    // MARK: - The store on files a 5.6 build wrote

    func testAStoreWrittenByFivePointSixOpensSearchesAndReadsByDocument() async throws {
        let first = UUID()
        let second = UUID()
        let chunks = (0..<300).map { chunk($0, documentId: $0 % 3 == 0 ? second : first, page: $0 % 10) }
        try writeStoreAsFivePointSixDid(chunks)

        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await store.count()
        XCTAssertEqual(count, 300)

        for number in [0, 1, 7, 133, 299] {
            let found = try await store.search(embedding: embedding(number), topK: 1)
            assertSamePassage(found.first?.chunk, chunks[number], "search for passage \(number)")
            XCTAssertEqual(found.first?.chunk.embedding, [], "the store hands passages back without their vectors")
        }

        let records = try await store.passageRecords()
        XCTAssertEqual(records.map(\.id), chunks.map(\.id))
        XCTAssertEqual(records.map(\.documentId), chunks.map(\.documentId))
        XCTAssertEqual(records.map(\.pageNumber), chunks.map(\.metadata.pageNumber))

        let ofSecond = try await store.chunks(forDocument: second)
        XCTAssertEqual(ofSecond.map(\.id), chunks.filter { $0.documentId == second }.map(\.id))
        let firstFive = try await store.chunks(forDocument: second, limit: 5)
        XCTAssertEqual(firstFive.map(\.id), Array(chunks.filter { $0.documentId == second }.prefix(5)).map(\.id))
        let noneAsked = try await store.chunks(forDocument: second, limit: 0)
        XCTAssertTrue(noneAsked.isEmpty)
        let howMany = try await store.chunkCount(forDocument: second)
        XCTAssertEqual(howMany, 100)
        let none = try await store.chunkCount(forDocument: UUID())
        XCTAssertEqual(none, 0)

        // By id: in the order asked, an id the store does not hold left out, an id asked for
        // twice handed back twice.
        let picked = try await store.chunks(withIDs: [chunks[299].id, chunks[0].id, chunks[150].id])
        XCTAssertEqual(picked.map(\.id), [chunks[299].id, chunks[0].id, chunks[150].id])
        for (found, number) in zip(picked, [299, 0, 150]) { assertSamePassage(found, chunks[number], "by id") }
        let byId = try await store.chunks(withIDs: [chunks[42].id, UUID(), chunks[7].id, chunks[42].id])
        XCTAssertEqual(byId.map(\.id), [chunks[42].id, chunks[7].id, chunks[42].id])

        let everything = try await store.allChunks()
        XCTAssertEqual(everything.count, 300)
        for index in [0, 1, 2, 3, 4, 5, 6, 7, 150, 299] {
            assertSamePassage(everything[index], chunks[index], "allChunks at \(index)")
        }
        let readable = try await store.readableChunks()
        XCTAssertEqual(readable.map(\.id), everything.map(\.id), "with nothing unreadable the two are the same")

        // Vectors by id: a few (each looked up) and many (found in one pass over the records).
        let embeddings = await store.getEmbeddings(forChunkIDs: [chunks[9].id, UUID()])
        XCTAssertEqual(embeddings, [embedding(9), []])
        var asked: [(id: UUID, vector: [Float])] = (0..<300).filter { $0 % 7 == 3 }.reversed().map {
            (chunks[$0].id, embedding($0))
        }
        asked.insert((UUID(), []), at: 5)
        asked.append((chunks[3].id, embedding(3)))
        asked.append((chunks[3].id, embedding(3)))
        XCTAssertGreaterThan(asked.count, 16)
        let many = await store.getEmbeddings(forChunkIDs: asked.map(\.id))
        XCTAssertEqual(many, asked.map(\.vector))
    }

    /// A metadata file the walk refuses and the decoder reads (here, a value nested deeper than
    /// the walk follows) is opened by decoding it whole, as every file was through 5.6. The
    /// store's next save writes it in the form the walk follows.
    func testAFileTheWalkCannotFollowIsOpenedByDecodingItWhole() async throws {
        let document = UUID()
        let chunks = (0..<12).map { chunk($0, documentId: document, page: $0) }
        var parts = try chunks.map { try String(decoding: JSONEncoder().encode(stripped($0)), as: UTF8.self) }
        let deep = String(repeating: "[", count: 70) + "1" + String(repeating: "]", count: 70)
        parts[4] = String(parts[4].dropLast()) + ",\"extra\":\(deep)}"
        let metadata = Data(("[" + parts.joined(separator: ",") + "]").utf8)
        XCTAssertNil(PassageFileIndex.scan(metadata), "the walk does not follow a value 70 deep")
        XCTAssertEqual(try JSONDecoder().decode([DocumentChunk].self, from: metadata).count, 12)
        try writeStoreAsFivePointSixDid(chunks, metadata: metadata)

        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await store.count()
        XCTAssertEqual(count, 12)
        for number in [0, 4, 11] {
            let found = try await store.search(embedding: embedding(number), topK: 1)
            assertSamePassage(found.first?.chunk, chunks[number], "search for passage \(number)")
        }
        let everything = try await store.allChunks()
        XCTAssertEqual(everything.map(\.id), chunks.map(\.id))
        let ofDocument = try await store.chunks(forDocument: document)
        XCTAssertEqual(ofDocument.map(\.id), chunks.map(\.id))

        let added = chunk(12, documentId: document, page: 12)
        try await store.storeBatch(chunks: [added])
        try await store.persist()
        let written = try Data(contentsOf: metaURL)
        XCTAssertEqual(PassageFileIndex.scan(written)?.count, 13, "the file the store wrote is one the walk follows")
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let records = try await reloaded.passageRecords()
        XCTAssertEqual(records.map(\.id), (chunks + [added]).map(\.id))
        for number in [0, 4, 11, 12] {
            let found = try await reloaded.search(embedding: embedding(number), topK: 1)
            assertSamePassage(found.first?.chunk, (chunks + [added])[number], "after the save, passage \(number)")
        }
    }

    // MARK: - The audit's figures

    /// The search-index rebuild will not wipe the keyword index of a store nothing can be read
    /// from. It finds out by reading a batch of passages at a time until one comes back, so a
    /// store whose first passages cannot be read and whose later ones can is not taken for one
    /// that holds nothing.
    func testAStoreHoldsAReadablePassageWhenAnyOneIsNotOnlyItsFirst() async throws {
        let document = UUID()
        let chunks = (0..<10).map { chunk($0, documentId: document) }
        try writeStoreAsFivePointSixDid(chunks, metadata: try metadataJSON(chunks, damagingAll: Set(0..<8)))
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let records = try await store.passageRecords()
        XCTAssertEqual(records.count, 10, "every passage has a record, readable or not")
        let firstBatch = try await store.chunks(withIDs: records.prefix(4).map(\.id))
        XCTAssertTrue(firstBatch.isEmpty, "the first batch hands nothing back")
        let readable = try await RAGService.holdsAReadablePassage(store, records: records, batch: 4)
        XCTAssertTrue(readable)

        try? FileManager.default.removeItem(at: metaURL)
        try writeStoreAsFivePointSixDid(chunks, metadata: try metadataJSON(chunks, damagingAll: Set(0..<10)))
        let nothingReadable = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let itsRecords = try await nothingReadable.passageRecords()
        XCTAssertEqual(itsRecords.count, 10)
        let none = try await RAGService.holdsAReadablePassage(nothingReadable, records: itsRecords, batch: 4)
        XCTAssertFalse(none)
        let noRecords = try await RAGService.holdsAReadablePassage(nothingReadable, records: [])
        XCTAssertFalse(noRecords)
    }

    /// The store keeps vectors of one length and hands passages back without them. The audit
    /// counted every passage of every library as a dimension mismatch, because it measured the
    /// empty vector on the passage. It counts none when the store's length is the library's, and
    /// all of them when it is not, and its word figures are those of every passage.
    func testTheAuditCountsNoMismatchWhenTheStoreMatchesTheLibrary() async throws {
        let document = UUID()
        let total = 5_000
        let chunks = (0..<total).map { number in
            chunk(number, documentId: document, text: Array(repeating: "word", count: number % 7 + 1).joined(separator: " "))
        }
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: chunks)
        try await store.persist()
        let records = try await store.passageRecords()

        let matching = await RAGService.vectorAuditFigures(
            of: store, records: records, storeDimension: dimension, expectedDimension: dimension)
        XCTAssertEqual(matching.mismatched, 0)
        XCTAssertEqual(matching.minimumWords, 1)
        XCTAssertEqual(matching.maximumWords, 7)
        let expectedAverage = Double((0..<total).reduce(0) { $0 + $1 % 7 + 1 }) / Double(total)
        XCTAssertEqual(matching.averageWords, expectedAverage, accuracy: 0.000001)

        let other = await RAGService.vectorAuditFigures(
            of: store, records: records, storeDimension: dimension, expectedDimension: dimension * 2)
        XCTAssertEqual(other.mismatched, total, "a library set to another length than its store holds")

        // A store that hands passages back with their vectors is measured from those.
        let inMemory = InMemoryVectorDatabase(dimension: dimension)
        try await inMemory.storeBatch(chunks: Array(chunks.prefix(40)))
        let inMemoryRecords = try await inMemory.passageRecords()
        let kept = await RAGService.vectorAuditFigures(
            of: inMemory, records: inMemoryRecords, storeDimension: dimension, expectedDimension: dimension)
        XCTAssertEqual(kept.mismatched, 0)
        let emptyStore = await RAGService.vectorAuditFigures(
            of: inMemory, records: [], storeDimension: dimension, expectedDimension: dimension)
        XCTAssertEqual(emptyStore.mismatched, 0)
        XCTAssertEqual(emptyStore.minimumWords, 0)
        XCTAssertEqual(emptyStore.averageWords, 0)
    }

    // MARK: - A passage that cannot be read

    /// The metadata file with one passage's text replaced by a number. It is still JSON, so the
    /// walk gives the passage a place, and it is not a passage `DocumentChunk` decodes.
    private func metadataJSON(_ chunks: [DocumentChunk], damaging damaged: Int) throws -> Data {
        try metadataJSON(chunks, damagingAll: [damaged])
    }

    private func metadataJSON(_ chunks: [DocumentChunk], damagingAll damaged: Set<Int>) throws -> Data {
        var data = Data("[".utf8)
        for (index, chunk) in chunks.enumerated() {
            var encoded = try JSONEncoder().encode(stripped(chunk))
            if damaged.contains(index) {
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                object["content"] = 7
                encoded = try JSONSerialization.data(withJSONObject: object)
            }
            if index > 0 { data.append(UInt8(ascii: ",")) }
            data.append(encoded)
        }
        data.append(UInt8(ascii: "]"))
        return data
    }

    /// Through 5.6 one passage that did not decode failed the decode of the whole file, and the
    /// library opened empty. Now the passage has a place and no text. It is counted, it is left
    /// out of searches, of reads of its document, of reads by id and of `readableChunks()`, and
    /// `allChunks()` refuses, because its callers may pair that array with the vectors by
    /// position. Every other passage keeps its own vector. Small enough to be read on the
    /// store's own thread, and large enough to be read on several.
    func testAPassageThatCannotBeReadIsLeftOutAndNeverShiftsTheOthers() async throws {
        for total in [12, 2_600] {
            try? FileManager.default.removeItem(at: metaURL)
            let first = UUID()
            let second = UUID()
            let chunks = (0..<total).map { chunk($0, documentId: $0 % 2 == 0 ? first : second, page: $0 % 9) }
            let damaged = total / 2 + 1  // one of `second`'s
            let metadata = try metadataJSON(chunks, damaging: damaged)
            XCTAssertNil(
                try? JSONDecoder().decode([DocumentChunk].self, from: metadata),
                "a 5.6 build could not open this file at all")
            try writeStoreAsFivePointSixDid(chunks, metadata: metadata)
            let readableIds = chunks.indices.filter { $0 != damaged }.map { chunks[$0].id }

            let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
            let count = try await store.count()
            XCTAssertEqual(count, total, "\(total): the passage is counted")
            let records = try await store.passageRecords()
            XCTAssertEqual(records.map(\.id), chunks.map(\.id))
            let ofSecond = try await store.chunkCount(forDocument: second)
            XCTAssertEqual(ofSecond, total / 2)

            // Searches: its neighbours are found by their own vectors, and it is not handed back.
            for number in [damaged - 1, damaged + 1, 0, total - 1] {
                let found = try await store.search(embedding: embedding(number), topK: 1)
                assertSamePassage(found.first?.chunk, chunks[number], "\(total): search for passage \(number)")
            }
            let nearIt = try await store.search(embedding: embedding(damaged), topK: 3)
            XCTAssertFalse(nearIt.contains { $0.chunk.id == chunks[damaged].id })

            // Reads of a set of passages leave it out.
            let itsDocument = try await store.chunks(forDocument: second)
            XCTAssertEqual(itsDocument.map(\.id), chunks.filter { $0.documentId == second }.map(\.id).filter { $0 != chunks[damaged].id })
            let byId = try await store.chunks(withIDs: [chunks[damaged - 1].id, chunks[damaged].id, chunks[damaged + 1].id])
            XCTAssertEqual(byId.map(\.id), [chunks[damaged - 1].id, chunks[damaged + 1].id])
            let readable = try await store.readableChunks()
            XCTAssertEqual(readable.map(\.id), readableIds, "\(total): every other passage, in order")
            assertSamePassage(readable[damaged], chunks[damaged + 1], "\(total): the passage after the gap")
            let readableAgain = try await store.readableChunks()
            XCTAssertEqual(readableAgain.map(\.id), readableIds)

            // The read that is paired with the vectors by position refuses, every time.
            for attempt in 1...2 {
                do {
                    _ = try await store.allChunks()
                    XCTFail("\(total): allChunks() handed back passages on attempt \(attempt)")
                } catch {}
            }

            // Its vector is still its own, and so is everyone else's.
            let vectors = await store.getEmbeddings(forIndices: [damaged - 1, damaged, damaged + 1])
            XCTAssertEqual(vectors, [embedding(damaged - 1), embedding(damaged), embedding(damaged + 1)])

            // A save keeps the file as it is (the bytes are copied), and what is added is read.
            let added = chunk(total, documentId: first)
            try await store.storeBatch(chunks: [added])
            try await store.persist()
            let afterSave = try await store.readableChunks()
            XCTAssertEqual(afterSave.map(\.id), readableIds + [added.id])
            let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
            let reloadedCount = try await reloaded.count()
            XCTAssertEqual(reloadedCount, total + 1)
            let reloadedReadable = try await reloaded.readableChunks()
            XCTAssertEqual(reloadedReadable.map(\.id), readableIds + [added.id])
            let foundAdded = try await reloaded.search(embedding: embedding(total), topK: 1)
            assertSamePassage(foundAdded.first?.chunk, added, "\(total): the passage added after the damage")

            // Removing the document it belongs to removes it, and the store is whole again.
            try await reloaded.deleteChunks(forDocument: second)
            let whole = try await reloaded.allChunks()
            XCTAssertEqual(whole.map(\.id), chunks.filter { $0.documentId == first }.map(\.id) + [added.id])
            let wholeVectors = await reloaded.getEmbeddings(forIndices: Array(whole.indices))
            XCTAssertEqual(
                wholeVectors, (chunks.indices.filter { $0 % 2 == 0 } + [total]).map { embedding($0) },
                "\(total): each passage that stayed has its own vector")
        }
    }

    /// The stores that keep every passage in memory answer the same questions from `allChunks()`.
    /// They have to give the answers the indexed store gives.
    func testAStoreInMemoryAnswersTheSameQuestions() async throws {
        let first = UUID()
        let second = UUID()
        let chunks = (0..<60).map { chunk($0, documentId: $0 % 3 == 0 ? second : first, page: $0 % 7) }
        let store = InMemoryVectorDatabase(dimension: dimension)
        try await store.storeBatch(chunks: chunks)
        let everything = try await store.allChunks()
        XCTAssertEqual(everything.count, 60)
        let records = try await store.passageRecords()
        XCTAssertEqual(records.map(\.id), everything.map(\.id))
        XCTAssertEqual(records.map(\.pageNumber), everything.map(\.metadata.pageNumber))
        let ofSecond = try await store.chunks(forDocument: second)
        XCTAssertEqual(ofSecond.map(\.id), everything.filter { $0.documentId == second }.map(\.id))
        let firstThree = try await store.chunks(forDocument: second, limit: 3)
        XCTAssertEqual(firstThree.map(\.id), Array(ofSecond.prefix(3)).map(\.id))
        let howMany = try await store.chunkCount(forDocument: second)
        XCTAssertEqual(howMany, 20)
        let byId = try await store.chunks(withIDs: [everything[9].id, UUID(), everything[5].id, everything[0].id])
        XCTAssertEqual(byId.map(\.id), [everything[9].id, everything[5].id, everything[0].id])
        let readable = try await store.readableChunks()
        XCTAssertEqual(readable.map(\.id), everything.map(\.id))
    }

    // MARK: - What a save writes

    /// A 5.6 build opens a library by decoding the whole metadata file as one array. That has to
    /// go on working on a file written by 5.7, after appends and after a delete.
    func testAFileThisStoreWritesDecodesWholeTheWayAnOlderBuildReadsIt() async throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let all =
            (0..<40).map { chunk($0, documentId: first) } + (40..<70).map { chunk($0, documentId: second) }
            + (70..<120).map { chunk($0, documentId: third) }
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: Array(all[0..<40]))
        try await store.persist()
        try await store.storeBatch(chunks: Array(all[40..<70]))
        try await store.persist()
        try await store.storeBatch(chunks: Array(all[70..<120]))
        try await store.persist()

        var decoded = try JSONDecoder().decode([DocumentChunk].self, from: Data(contentsOf: metaURL))
        XCTAssertEqual(decoded.map(\.id), all.map(\.id))
        for index in decoded.indices { assertSamePassage(decoded[index], all[index], "after three saves, \(index)") }
        XCTAssertTrue(decoded.allSatisfy { $0.embedding.isEmpty })

        try await store.deleteChunks(forDocument: second)
        let kept = Array(all[0..<40]) + Array(all[70..<120])
        decoded = try JSONDecoder().decode([DocumentChunk].self, from: Data(contentsOf: metaURL))
        XCTAssertEqual(decoded.map(\.id), kept.map(\.id))
        for index in decoded.indices { assertSamePassage(decoded[index], kept[index], "after the delete, \(index)") }

        let vectorBytes = (try FileManager.default.attributesOfItem(atPath: vectorsURL.path))[.size] as? Int
        XCTAssertEqual(vectorBytes, kept.count * dimension * MemoryLayout<Float>.size)
    }

    /// A passage that is already in the file is copied, not encoded again: after a second save
    /// the file begins with every byte the first save wrote, up to its closing bracket.
    func testASaveCopiesThePassagesAlreadyInTheFileByteForByte() async throws {
        let document = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: (0..<50).map { chunk($0, documentId: document) })
        try await store.persist()
        let before = try Data(contentsOf: metaURL)
        XCTAssertEqual(before.last, UInt8(ascii: "]"))

        try await store.storeBatch(chunks: (50..<80).map { chunk($0, documentId: document) })
        try await store.persist()
        let after = try Data(contentsOf: metaURL)
        XCTAssertGreaterThan(after.count, before.count)
        XCTAssertEqual(after.prefix(before.count - 1), before.dropLast())
        XCTAssertEqual(after[after.startIndex + before.count - 1], UInt8(ascii: ","))
    }

    func testVectorsStayWithTheirPassagesThroughSavesADeleteAndAReload() async throws {
        let documents = [UUID(), UUID(), UUID()]
        // The three documents' passages are interleaved, so deleting one takes passages out of
        // the middle of both files everywhere.
        let all = (0..<240).map { chunk($0, documentId: documents[$0 % 3], page: $0) }
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: Array(all[0..<100]))
        try await store.persist()
        try await store.storeBatch(chunks: Array(all[100..<240]))
        // Not saved yet: the delete has to cope with passages in the file and passages in memory.
        try await store.deleteChunks(forDocument: documents[1])
        let kept = all.filter { $0.documentId != documents[1] }

        func check(_ store: BNNSVectorDatabase, _ label: String) async throws {
            let count = try await store.count()
            XCTAssertEqual(count, kept.count, label)
            let records = try await store.passageRecords()
            XCTAssertEqual(records.map(\.id), kept.map(\.id), label)
            for number in [0, 2, 3, 99, 101, 102, 236, 239] where number % 3 != 1 {
                let found = try await store.search(embedding: embedding(number), topK: 1)
                assertSamePassage(found.first?.chunk, all[number], "\(label): search for \(number)")
            }
            let gone = try await store.chunkCount(forDocument: documents[1])
            XCTAssertEqual(gone, 0, label)
            let vectors = await store.getEmbeddings(forIndices: Array(kept.indices))
            XCTAssertEqual(vectors, kept.map(\.embedding), label)
        }
        try await check(store, "the store that deleted")
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await check(reloaded, "a store opened on its files")

        // And it goes on from there.
        let more = (240..<260).map { chunk($0, documentId: documents[0]) }
        try await reloaded.storeBatch(chunks: more)
        try await reloaded.persist()
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let found = try await again.search(embedding: embedding(250), topK: 1)
        assertSamePassage(found.first?.chunk, more[10], "a passage added after the reload")
        let countAgain = try await again.count()
        XCTAssertEqual(countAgain, kept.count + 20)
    }

    func testEveryPassageAtOnceStaysRightAsTheStoreChanges() async throws {
        let first = UUID()
        let second = UUID()
        var expected = (0..<2_600).map { chunk($0, documentId: $0 < 2_500 ? first : second) }
        try writeStoreAsFivePointSixDid(expected)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)

        // Enough passages that they are decoded on several threads, and two callers at once.
        async let one = store.allChunks()
        async let two = store.allChunks()
        let (a, b) = try await (one, two)
        XCTAssertEqual(a.map(\.id), expected.map(\.id))
        XCTAssertEqual(b.map(\.id), expected.map(\.id))

        let added = (2_600..<2_640).map { chunk($0, documentId: second) }
        try await store.storeBatch(chunks: added)
        expected += added
        var now = try await store.allChunks()
        XCTAssertEqual(now.map(\.id), expected.map(\.id), "after a batch that is not saved yet")
        try await store.persist()
        now = try await store.allChunks()
        XCTAssertEqual(now.map(\.id), expected.map(\.id), "after the save")

        try await store.deleteChunks(forDocument: second)
        expected.removeAll { $0.documentId == second }
        now = try await store.allChunks()
        XCTAssertEqual(now.map(\.id), expected.map(\.id), "after a delete")
        let ofFirst = try await store.chunks(forDocument: first)
        XCTAssertEqual(ofFirst.count, 2_500)
        assertSamePassage(ofFirst[2_499], expected[2_499])
    }

    /// Under memory pressure the store lets go of the passages it has decoded. They come back
    /// from the file the next time they are asked for.
    func testDecodedPassagesComeBackAfterTheyAreReleased() async throws {
        let document = UUID()
        let chunks = (0..<2_400).map { chunk($0, documentId: document) }
        try writeStoreAsFivePointSixDid(chunks)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let before = try await store.allChunks()
        XCTAssertEqual(before.map(\.id), chunks.map(\.id))
        await store.releaseDecodedPassages()
        let found = try await store.search(embedding: embedding(1_200), topK: 1)
        assertSamePassage(found.first?.chunk, chunks[1_200])
        let after = try await store.allChunks()
        XCTAssertEqual(after.map(\.id), chunks.map(\.id))
        assertSamePassage(after[2_399], chunks[2_399])
    }

    func testOneDocumentOfALargeStoreIsReadWithoutTheOthers() async throws {
        let big = UUID()
        let small = UUID()
        let chunks = (0..<3_200).map { chunk($0, documentId: $0 % 16 == 0 ? small : big) }
        try writeStoreAsFivePointSixDid(chunks)
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        // More than the store decodes on one thread, so this is the path with several.
        let ofBig = try await store.chunks(forDocument: big)
        let expected = chunks.filter { $0.documentId == big }
        XCTAssertEqual(ofBig.map(\.id), expected.map(\.id))
        assertSamePassage(ofBig.last, expected[expected.count - 1])
        let ofSmall = try await store.chunks(forDocument: small)
        XCTAssertEqual(ofSmall.count, 200)
    }

    func testChangingOnePassageKeepsTheOthers() async throws {
        let document = UUID()
        let original = (0..<30).map { chunk($0, documentId: document) }
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: original)
        try await store.persist()

        let replacement = DocumentChunk(
            id: original[12].id, documentId: document, content: "rewritten \"passage\"", embedding: embedding(900),
            metadata: ChunkMetadata(chunkIndex: 12, pageNumber: 4))
        try await store.updateChunk(replacement)

        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 30)
        let found = try await reloaded.search(embedding: embedding(900), topK: 1)
        XCTAssertEqual(found.first?.chunk.content, "rewritten \"passage\"")
        XCTAssertEqual(found.first?.chunk.metadata.pageNumber, 4)
        let neighbour = try await reloaded.search(embedding: embedding(13), topK: 1)
        assertSamePassage(neighbour.first?.chunk, original[13])
        let decoded = try JSONDecoder().decode([DocumentChunk].self, from: Data(contentsOf: metaURL))
        XCTAssertEqual(decoded.map(\.id), original.map(\.id))
    }

    func testAStoreWithNoFilesKeepsItsVectorsAfterADelete() async throws {
        let first = UUID()
        let second = UUID()
        let store = BNNSVectorDatabase(dimension: dimension)
        let chunks = (0..<20).map { chunk($0, documentId: $0 % 2 == 0 ? first : second) }
        try await store.storeBatch(chunks: chunks)
        try await store.deleteChunks(forDocument: first)
        let count = try await store.count()
        XCTAssertEqual(count, 10)
        let found = try await store.search(embedding: embedding(7), topK: 1)
        assertSamePassage(found.first?.chunk, chunks[7])
        let everything = try await store.allChunks()
        XCTAssertEqual(everything.map(\.id), chunks.filter { $0.documentId == second }.map(\.id))
    }

    /// Chat's suggested questions are drawn from a pool of passages. From 5.7 the pool is chosen
    /// from the store's records and only those passages are read. It has to be the pool the
    /// older rule chose from every passage.
    func testThePoolChosenFromRecordsIsThePoolChosenFromPassages() {
        let document = UUID()
        let limit = RAGService.suggestedQuestionPoolLimit
        for count in [0, 10, limit, limit + 1, limit * 2 + 37] {
            let chunks = (0..<count).map {
                chunk($0, documentId: document, text: "p\($0)", level: $0 % 701 == 3 ? .documentSummary : .detail)
            }
            let fromPassages = RAGService.suggestedQuestionPool(from: chunks).map(\.id)
            let positions = RAGService.suggestedQuestionPoolPositions(levels: chunks.map(\.metadata.abstractionLevel))
            XCTAssertEqual(positions.map { chunks[$0].id }, fromPassages, "\(count) passages")
        }
    }

    /// Hybrid search turns keyword hits into passages. It used to look for them in every
    /// passage of the library. From 5.7 it finds their positions in the records and reads only
    /// those, and it has to end up with the same passages, duplicates and all.
    func testKeywordHitsAreFoundThroughRecordsAsTheyWereThroughEveryPassage() {
        let documents = [UUID(), UUID()]
        var chunks: [DocumentChunk] = []
        for number in 0..<300 {
            chunks.append(
                chunk(
                    number % 120, documentId: documents[number % 2], text: "t\(number)",
                    level: number % 9 == 0 ? .documentSummary : .detail))
        }
        let records = chunks.map {
            PassageRecord(
                id: $0.id, documentId: $0.documentId, chunkIndex: $0.metadata.chunkIndex,
                pageNumber: $0.metadata.pageNumber, abstractionLevel: $0.metadata.abstractionLevel)
        }
        func key(_ document: UUID, _ index: Int) -> String { "\(document.uuidString)_\(index)" }
        let needs: [Set<String>] = [
            [],
            [key(documents[0], 0)],
            [key(documents[0], 4), key(documents[1], 5), key(documents[1], 119)],
            [key(documents[0], 2), key(UUID(), 2), "not a key"],
            Set((0..<120).map { key(documents[$0 % 2], $0) }),
        ]
        for needed in needs {
            for summariesOnly in [false, true] {
                let every = summariesOnly ? RAPTORSummaryRouter.filterSummaryChunks(chunks) : chunks
                let expected = HybridSearchService.buildNeededChunkLookup(from: every, neededChunkIds: needed)
                let positions = HybridSearchService.neededChunkPositions(
                    records: records, neededChunkIds: needed, summariesOnly: summariesOnly)
                let read = positions.map { chunks[$0] }
                let found = HybridSearchService.buildNeededChunkLookup(from: read, neededChunkIds: needed)
                XCTAssertEqual(found.mapValues(\.id), expected.mapValues(\.id), "\(needed.count) needed, summaries only \(summariesOnly)")
                XCTAssertEqual(positions.count, expected.count)
            }
        }
    }

    func testAnEmptyStoreSavesAndOpens() async throws {
        let document = UUID()
        let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        try await store.storeBatch(chunks: [chunk(0, documentId: document)])
        try await store.persist()
        try await store.deleteChunks(forDocument: document)
        XCTAssertEqual(try String(contentsOf: metaURL, encoding: .utf8), "[]")
        let reloaded = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let count = try await reloaded.count()
        XCTAssertEqual(count, 0)
        let everything = try await reloaded.allChunks()
        XCTAssertTrue(everything.isEmpty)
        try await reloaded.storeBatch(chunks: [chunk(1, documentId: document)])
        try await reloaded.persist()
        let again = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
        let found = try await again.search(embedding: embedding(1), topK: 1)
        XCTAssertEqual(found.first?.chunk.metadata.chunkIndex, 1)
    }
}
