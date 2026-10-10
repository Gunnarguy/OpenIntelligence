//
//  TextPieceImportTests.swift
//  OpenIntelligenceTests
//
//  On 2026-10-09 an 88 MB JSON Lines file (189,579 records) could not be imported on an iPhone:
//  read whole it held 2.8 GB, and the app was ended for memory before a fifth of it was chunked.
//  From 5.7 such a file is imported a piece at a time. These pin the parts of that which can be
//  checked without a device: how the file is cut, how records keep their numbers and share
//  passages, what the processor does with one piece, and how a restart decides where it stands.
//  The import loop itself (`RAGService.importLargeTextStreamed`) has no test here.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class TextPieceImportTests: XCTestCase {

    // MARK: - Cutting the file

    private func lines(_ count: Int, width: Int = 40) -> String {
        (1...count).map { "{\"n\": \($0), \"text\": \"\(String(repeating: "x", count: width))\"}" }
            .joined(separator: "\n") + "\n"
    }

    func testPiecesEndAtLineFeedsAndCoverTheFile() {
        let text = lines(500)
        let reader = TextPieceReader(data: Data(text.utf8))
        let ranges = reader.pieceRanges(targetBytes: 1_000)

        XCTAssertGreaterThan(ranges.count, 10)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, reader.count)
        for (previous, next) in zip(ranges, ranges.dropFirst()) {
            XCTAssertEqual(previous.upperBound, next.lowerBound, "pieces touch")
        }
        var rejoined = Data()
        for range in ranges {
            let piece = reader.bytes(in: range)
            XCTAssertEqual(piece.last, 0x0A, "a piece ends just after a line feed")
            XCTAssertLessThanOrEqual(piece.count, 1_000)
            rejoined.append(piece)
        }
        XCTAssertEqual(rejoined, Data(text.utf8))
    }

    func testALineLongerThanAPieceIsKeptWhole() {
        let long = String(repeating: "y", count: 5_000)
        let text = "short one\n" + long + "\nshort two\n"
        let reader = TextPieceReader(data: Data(text.utf8))
        let pieces = reader.pieceRanges(targetBytes: 100).map { String(decoding: reader.bytes(in: $0), as: UTF8.self) }
        XCTAssertEqual(pieces, ["short one\n", long + "\n", "short two\n"])
    }

    func testALineOverTheCeilingIsCutBetweenCharacters() {
        // "é" is two bytes, so an odd byte limit falls inside a character.
        let text = String(repeating: "é", count: 400)
        let reader = TextPieceReader(data: Data(text.utf8))
        let ranges = reader.pieceRanges(targetBytes: 101, longestLine: 101)
        XCTAssertGreaterThan(ranges.count, 1)
        var rejoined = ""
        for range in ranges {
            let piece = String(data: reader.bytes(in: range), encoding: .utf8)
            XCTAssertNotNil(piece, "every piece is valid UTF-8 by itself")
            rejoined += piece ?? ""
        }
        XCTAssertEqual(rejoined, text)
    }

    func testAFileWithNoLineFeedAtTheEndAndAnEmptyFile() {
        let reader = TextPieceReader(data: Data("one\ntwo".utf8))
        XCTAssertEqual(reader.pieceRanges(targetBytes: 4), [0..<4, 4..<7])
        XCTAssertEqual(TextPieceReader(data: Data()).pieceRanges(), [])
        XCTAssertFalse(TextPieceReader(data: Data()).canBeCutAtLineFeeds)
    }

    func testOnlyAFileWhoseLineFeedsAreSingleBytesIsCut() {
        XCTAssertTrue(TextPieceReader(data: Data("plain\ntext\n".utf8)).canBeCutAtLineFeeds)
        XCTAssertTrue(TextPieceReader(data: Data("\u{FEFF}with a UTF-8 mark\n".utf8)).canBeCutAtLineFeeds)
        XCTAssertFalse(
            TextPieceReader(data: "sixteen\nbits\n".data(using: .utf16)!).canBeCutAtLineFeeds,
            "UTF-16 with its byte-order mark")
        XCTAssertFalse(
            TextPieceReader(data: "sixteen\nbits\n".data(using: .utf16LittleEndian)!).canBeCutAtLineFeeds,
            "UTF-16 with no mark, by its zero bytes")
    }

    /// The reader's count gives each piece's first record number, so it has to be the number of
    /// records the record reader finds in the same bytes.
    func testTheLineCountIsTheRecordReadersCount() throws {
        let text = "{\"a\": 1}\n\n   \n{\"a\": 2}\r\n\t\r\n{\"a\": 3}\nnot json\n{\"a\": 4}"
        let reader = TextPieceReader(data: Data(text.utf8))
        let extraction = try XCTUnwrap(JSONRecordExtractor.extract(from: text, fileExtension: "jsonl"))
        XCTAssertEqual(reader.nonBlankLineCount(in: 0..<reader.count), extraction.records.count)
        XCTAssertEqual(reader.nonBlankLineCount(in: 0..<reader.count), 5)

        // Counted piece by piece it is the same total.
        let byPiece = reader.pieceRanges(targetBytes: 12).reduce(0) { $0 + reader.nonBlankLineCount(in: $1) }
        XCTAssertEqual(byPiece, 5)
    }

    // MARK: - Record numbers across pieces

    func testAPiecesRecordsCarryTheirNumbersInTheWholeFile() throws {
        let numbering = JSONRecordExtractor.Numbering(first: 4, total: 9)
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(
                from: "{\"a\": 1}\nplain words\n{\"a\": 3}\n", fileExtension: "jsonl", numbering: numbering))
        XCTAssertEqual(
            extraction.records, ["Record 4 of 9\na: 1", "Record 5 of 9\nplain words", "Record 6 of 9\na: 3"])

        let passages = try XCTUnwrap(
            JSONRecordExtractor.passages(in: extraction.text, expectedCount: 3, numbering: numbering))
        XCTAssertEqual(passages.map(\.text), extraction.records)

        // Asked for with the numbers of a whole file, the same text holds no such headers.
        XCTAssertNil(JSONRecordExtractor.passages(in: extraction.text, expectedCount: 3))
    }

    func testAWholeFileIsNumberedAsBefore() throws {
        let extraction = try XCTUnwrap(
            JSONRecordExtractor.extract(from: "{\"a\": 1}\n{\"a\": 2}\n", fileExtension: "jsonl"))
        XCTAssertEqual(extraction.records, ["Record 1 of 2\na: 1", "Record 2 of 2\na: 2"])
        XCTAssertEqual(JSONRecordExtractor.passages(in: extraction.text, expectedCount: 2)?.count, 2)
    }

    // MARK: - Packing short records

    func testShortRecordsShareAPassageAndALongOneIsAlone() {
        // Joining costs 2. 10 + 2 + 10 + 2 + 10 = 34 fits 40; a fourth 10 would make 46.
        XCTAssertEqual(
            JSONRecordExtractor.packedRanges(tokenCounts: [10, 10, 10, 10, 10], maxTokens: 40),
            [0..<3, 3..<5])
        // A record over the limit by itself closes the passage before it and takes none after it.
        XCTAssertEqual(
            JSONRecordExtractor.packedRanges(tokenCounts: [10, 90, 10, 10], maxTokens: 40),
            [0..<1, 1..<2, 2..<4])
        XCTAssertEqual(JSONRecordExtractor.packedRanges(tokenCounts: [90], maxTokens: 40), [0..<1])
        XCTAssertEqual(JSONRecordExtractor.packedRanges(tokenCounts: [], maxTokens: 40), [])
    }

    func testEveryRecordIsInExactlyOnePassageInOrder() {
        let counts = (0..<500).map { ($0 * 37) % 120 + 1 }
        let ranges = JSONRecordExtractor.packedRanges(tokenCounts: counts, maxTokens: 100)
        XCTAssertEqual(ranges.flatMap { Array($0) }, Array(0..<500))
        for range in ranges where range.count > 1 {
            let used = counts[range].reduce(0, +) + 2 * (range.count - 1)
            XCTAssertLessThanOrEqual(used, 100)
        }
    }

    // MARK: - Which files are imported in pieces

    func testOnlyLargeLineBasedTextIsImportedInPieces() {
        let limit = DocumentProcessor.piecewiseTextBytes
        func pieces(_ ext: String, _ type: DocumentType, _ bytes: Int) -> Bool {
            DocumentProcessor.importsInPieces(fileExtension: ext, documentType: type, fileBytes: bytes)
        }
        XCTAssertFalse(pieces("jsonl", .json, limit))
        XCTAssertTrue(pieces("jsonl", .json, limit + 1))
        XCTAssertTrue(pieces("NDJSON", .json, limit + 1))
        XCTAssertTrue(pieces("txt", .text, limit + 1))
        XCTAssertTrue(pieces("md", .markdown, limit + 1))
        // A .json file is one parsed value up to the size at which it is read as text.
        XCTAssertFalse(pieces("json", .json, limit + 1))
        XCTAssertTrue(pieces("json", .json, JSONRecordExtractor.maxFileBytes + 1))
        XCTAssertFalse(pieces("pdf", .pdf, limit * 10))
        XCTAssertFalse(pieces("xml", .xml, limit * 10))
    }

    // MARK: - One piece through the processor

    func testAPieceKeepsItsNumbersPacksItsRecordsAndHandsBackItsText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.jsonl")
        let source = (1...40).map { "{\"id\": \"n\($0)\", \"text\": \"The pump was checked on shift \($0).\"}" }
            .joined(separator: "\n")
        try Data(source.utf8).write(to: url)

        var kept = ""
        let piece = DocumentProcessor.TextPiece(
            numbering: .init(first: 101, total: 500), keepText: { kept = $0 })
        let (_, chunks) = try await DocumentProcessor().processDocument(at: url, textPiece: piece)

        XCTAssertTrue(kept.hasPrefix("Record 101 of 500\n"), "the piece's text came back: \(kept.prefix(60))")
        XCTAssertTrue(kept.contains("Record 140 of 500\n"))

        XCTAssertFalse(chunks.isEmpty)
        XCTAssertLessThan(chunks.count, 40, "short records share passages")
        let joined = chunks.map { $0.text }.joined(separator: "\n\n")
        var searchFrom = joined.startIndex
        for number in 101...140 {
            let header = "Record \(number) of 500\n"
            let found = joined.range(of: header, range: searchFrom..<joined.endIndex)
            XCTAssertNotNil(found, "record \(number) is in a passage, after the one before it")
            if let found { searchFrom = found.upperBound }
        }
        let firstTitle = chunks.first?.metadata.sectionTitle ?? ""
        XCTAssertTrue(firstTitle.hasPrefix("Records 101 to "), firstTitle)
        let indexes = chunks.map { $0.metadata.chunkIndex }
        XCTAssertEqual(indexes, Array(chunks.indices))
    }

    func testAWholeFileStillGivesEachRecordItsOwnPassage() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.jsonl")
        let source = (1...12).map { "{\"id\": \"n\($0)\", \"text\": \"The pump was checked on shift \($0).\"}" }
            .joined(separator: "\n")
        try Data(source.utf8).write(to: url)

        let (document, chunks) = try await DocumentProcessor().processDocument(at: url)
        XCTAssertEqual(chunks.count, 12)
        let firstTitle = chunks.first?.metadata.sectionTitle
        XCTAssertEqual(firstTitle, "Record 1")
        await FullTextStorageService.shared.delete(for: document.id)
    }

    // MARK: - Chunk numbers of the whole document

    func testMovedMetadataShiftsItsNumbersAndKeepsEverythingElse() throws {
        // Every field is set to something other than its default, so one that `moved` drops shows.
        let original = ChunkMetadata(
            chunkIndex: 3, startPosition: 10, endPosition: 50, pageNumber: 2, sectionTitle: "Records 4 to 9",
            keywords: ["pump"], semanticDensity: 0.4, hasNumericData: true, hasListStructure: true, wordCount: 7,
            characterCount: 40, createdAt: Date(timeIntervalSince1970: 1_700_000_000), structureType: "table",
            siblingGroupId: "g", siblingCount: 2, entities: ["Pump A"],
            abbreviations: ["IFU": "Instructions For Use"], abstractionLevel: .documentSummary,
            sectionPath: ["Records 4 to 9"], bboxArray: [1, 2, 3, 4], documentCategory: .technicalManual,
            chunkType: .tableSemantic, tableTitle: "T", imageContentType: "diagram", mediaReferenceId: "m1",
            imageCaption: "a caption", imageDescription: "a description", imageExtractedText: "text in it",
            imageClassifications: ["chart"], hasCrossReferences: true, resolvedReferences: ["Section 2"])
        let moved = original.moved(chunkIndexBy: 100, positionBy: 1_000)

        XCTAssertEqual(moved.chunkIndex, 103)
        XCTAssertEqual(moved.startPosition, 1_010)
        XCTAssertEqual(moved.endPosition, 1_050)

        // Everything else is the same. Compared as encoded, so a field added to the type and
        // forgotten in `moved` shows up here.
        let fields: (ChunkMetadata) throws -> [String: String] = { metadata in
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(metadata)) as? [String: Any] ?? [:]
            return object.filter { !["chunkIndex", "startPosition", "endPosition"].contains($0.key) }
                .mapValues { "\($0)" }
        }
        let movedFields = try fields(moved)
        let originalFields = try fields(original)
        XCTAssertEqual(movedFields, originalFields)
    }

    // MARK: - A piece's vectors, kept as they are made

    func testAStoppedPieceReadsBackWhatItHadEmbeddedAndGoesOn() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(TextPieceVectors.fileName)

        let texts = ["one", "two", "three", "four", "five"]
        let key = TextPieceVectors.key(pieceNumber: 3, texts: texts, dimension: 4, providerId: "p")
        let vectors: [[Float]] = (0..<5).map { row in (0..<4).map { Float(row * 10 + $0) } }

        let nothingYet = await TextPieceVectors.read(at: url, key: key, dimension: 4, limit: 5)
        XCTAssertEqual(nothingYet, [])

        try await TextPieceVectors.append(Array(vectors[0..<2]), to: url, key: key, startsFile: true)
        try await TextPieceVectors.append(Array(vectors[2..<3]), to: url, key: key, startsFile: false)
        let kept = await TextPieceVectors.read(at: url, key: key, dimension: 4, limit: 5)
        XCTAssertEqual(kept, Array(vectors[0..<3]))

        // The app was stopped part-way through writing a vector: the whole ones still count, and
        // what is written next lands after them.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([1, 2, 3, 4, 5]))
        try handle.close()
        let afterAStop = await TextPieceVectors.read(at: url, key: key, dimension: 4, limit: 5)
        XCTAssertEqual(afterAStop, Array(vectors[0..<3]))
        try await TextPieceVectors.append(Array(vectors[3..<5]), to: url, key: key, startsFile: false)
        let all = await TextPieceVectors.read(at: url, key: key, dimension: 4, limit: 5)
        XCTAssertEqual(all, vectors)

        // Another piece, other passages, another vector size or another embedder: not read.
        for other in [
            TextPieceVectors.key(pieceNumber: 4, texts: texts, dimension: 4, providerId: "p"),
            TextPieceVectors.key(pieceNumber: 3, texts: texts.reversed(), dimension: 4, providerId: "p"),
            TextPieceVectors.key(pieceNumber: 3, texts: texts, dimension: 8, providerId: "p"),
            TextPieceVectors.key(pieceNumber: 3, texts: texts, dimension: 4, providerId: "q"),
        ] {
            XCTAssertNotEqual(other, key)
            let read = await TextPieceVectors.read(at: url, key: other, dimension: 4, limit: 5)
            XCTAssertEqual(read, [])
        }

        // The first slice of the next piece starts the file over.
        let nextKey = TextPieceVectors.key(pieceNumber: 4, texts: ["six"], dimension: 4, providerId: "p")
        try await TextPieceVectors.append([vectors[4]], to: url, key: nextKey, startsFile: true)
        let next = await TextPieceVectors.read(at: url, key: nextKey, dimension: 4, limit: 1)
        XCTAssertEqual(next, [vectors[4]])
    }

    // MARK: - Where a restart stands

    func testAPieceThatWasBeingStoredIsRedoneCountedFinishedOrStartedOver() {
        typealias State = TextStreamingIngestionState
        func recovery(pending: Int?, vector: Int, index: Int) -> State.Recovery {
            State.recovery(committedChunks: 100, pendingChunks: pending, vectorChunks: vector, indexChunks: index)
        }
        XCTAssertEqual(recovery(pending: nil, vector: 100, index: 100), .nothingPending)
        XCTAssertEqual(recovery(pending: 130, vector: 100, index: 100), .redoPiece, "neither store has it")
        XCTAssertEqual(recovery(pending: 130, vector: 130, index: 130), .pieceWentIn, "both stores have it")
        // What the owner's phone held on 2026-10-10 at 01:03 PT (59,292 and 55,592 of 55,592
        // committed), which started a 17-part import over.
        XCTAssertEqual(
            recovery(pending: 130, vector: 130, index: 100), .finishIndex,
            "the vector store has it and the search index does not")
        XCTAssertEqual(recovery(pending: 130, vector: 115, index: 130), .startOver)
        XCTAssertEqual(recovery(pending: 130, vector: 115, index: 100), .startOver)
        XCTAssertEqual(recovery(pending: 130, vector: 100, index: 130), .startOver)
    }

    func testAPiecesPassagesAreNumberedByPlaceEvenWhenASplitRepeatedANumber() {
        // What the processor hands back when its second passage was split in two: the parts take
        // 1 and 2, and the passage after them is 2 as well.
        let fromTheProcessor = [0, 1, 2, 2, 3].map {
            ChunkMetadata(chunkIndex: $0, startPosition: 10 * $0, endPosition: 10 * $0 + 9)
        }
        let numbered = RAGService.documentNumbered(fromTheProcessor, chunkBase: 100, positionBase: 1_000)
        XCTAssertEqual(numbered.map(\.chunkIndex), [100, 101, 102, 103, 104])
        XCTAssertEqual(numbered.map(\.startPosition), [1_000, 1_010, 1_020, 1_020, 1_030])
        XCTAssertEqual(numbered.map(\.endPosition), [1_009, 1_019, 1_029, 1_029, 1_039])
    }

    private func storedChunk(_ number: Int, documentId: UUID, tableTitle: String? = nil) -> DocumentChunk {
        DocumentChunk(
            documentId: documentId, content: "record \(number)", embedding: [],
            metadata: ChunkMetadata(chunkIndex: number, sectionTitle: "Record \(number)", tableTitle: tableTitle))
    }

    func testTheIndexRowsOfAStoredPieceAreRebuiltFromItsChunks() {
        let documentId = UUID()
        let stored = (0..<130).map { storedChunk($0, documentId: documentId) }
        let rows = RAGService.searchIndexRows(forStored: stored, first: 100, count: 30)
        XCTAssertEqual(rows?.count, 30)
        XCTAssertEqual(rows?.map(\.chunkIndex), Array(100..<130))
        XCTAssertEqual(rows?.first?.content, "record 100")
        XCTAssertEqual(rows?.last?.sectionTitle, "Record 129")
        XCTAssertNil(rows?.first?.structuredMetadata)
    }

    func testAStoredPieceThatIsNotExactlyThePieceIsNotIndexed() {
        let documentId = UUID()
        let stored = (0..<130).map { storedChunk($0, documentId: documentId) }
        XCTAssertNil(RAGService.searchIndexRows(forStored: stored, first: 100, count: 31), "one chunk short")
        XCTAssertNil(RAGService.searchIndexRows(forStored: stored, first: 100, count: 0))

        XCTAssertNil(RAGService.searchIndexRows(forStored: stored, first: 101, count: 30), "one chunk too many")

        // A piece stored by a build that numbered split passages like the passages after them
        // (through the 2026-10-10 01:30 build) still has its rows rebuilt: the piece is found by
        // where it sits in the store, not by its numbers.
        var repeated = stored
        repeated[111] = storedChunk(110, documentId: documentId)
        let rows = RAGService.searchIndexRows(forStored: repeated, first: 100, count: 30)
        XCTAssertEqual(rows?.count, 30)
        XCTAssertEqual(rows?[11].content, "record 110")

        var withTable = stored
        withTable[120] = storedChunk(120, documentId: documentId, tableTitle: "Rent by year")
        XCTAssertNil(
            RAGService.searchIndexRows(forStored: withTable, first: 100, count: 30),
            "a table's row needs a payload the vector store does not keep")
    }

    func testTheStateSurvivesBeingSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(TextStreamingIngestionState.fileName)

        var state = TextStreamingIngestionState(
            documentId: UUID(), containerId: UUID(), fileBytes: 9_000_000, pieceBytes: TextPieceReader.pieceBytes,
            longestLineBytes: 1_000, totalPieces: 5, totalRecords: 1_234)
        state.committed.completedBytes = 4_000_000
        state.committed.completedPieces = 2
        state.committed.totalChunks = 900
        state.pending = state.committed
        state.pending?.completedPieces = 3
        try state.write(to: url)

        XCTAssertEqual(TextStreamingIngestionState.read(at: url), state)
        XCTAssertNil(TextStreamingIngestionState.read(at: directory.appendingPathComponent("missing.json")))
    }

    func testAPausedImportInPiecesSaysHowManyPartsAreIn() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("big.jsonl")
        try Data("{\"a\": 1}\n".utf8).write(to: url)

        let processor = DocumentProcessor()
        defer {
            processor.cleanCheckpoints(for: url)
            try? FileManager.default.removeItem(at: directory)
        }
        XCTAssertNil(processor.restoredIngestionProgress(for: url), "no checkpoint yet")

        let checkpoint = processor.checkpointDirectoryURL(for: processor.computeDocumentFingerprint(at: url))
        var state = TextStreamingIngestionState(
            documentId: UUID(), fileBytes: 9, pieceBytes: TextPieceReader.pieceBytes, totalPieces: 44,
            totalRecords: 1)
        try state.write(to: checkpoint.appendingPathComponent(TextStreamingIngestionState.fileName))
        XCTAssertNil(processor.restoredIngestionProgress(for: url), "nothing committed yet")

        state.committed.completedPieces = 11
        state.committed.totalChunks = 17_000
        try state.write(to: checkpoint.appendingPathComponent(TextStreamingIngestionState.fileName))
        let restored = try XCTUnwrap(processor.restoredIngestionProgress(for: url))
        XCTAssertEqual(restored.fraction, 0.25)
        XCTAssertEqual(restored.chunksIndexed, 17_000)
        XCTAssertTrue(restored.detail.contains("11 of 44 parts"), restored.detail)
    }
}
