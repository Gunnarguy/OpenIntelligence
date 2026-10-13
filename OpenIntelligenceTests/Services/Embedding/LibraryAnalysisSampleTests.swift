//
//  LibraryAnalysisSampleTests.swift
//  OpenIntelligenceTests
//
//  The library analysis joins and tokenises all the text it is given, and it ran over every
//  passage of a library each time the library was opened and after each import: 199 s, and
//  1,054 MB over what the process held, for 144,247 passages on a Mac. From 5.7 a library past
//  `analysisPassageLimit` is analysed from a sample, the report keeps the library's real counts,
//  a report made from a sample never asks for another embedding model, and the report is kept on
//  disk and reused while the library is unchanged. These tests hold the sample, the counts, the
//  rule about settings, and the kept files: when they come back, and when they are removed.
//

import NaturalLanguage
import XCTest

@testable import OpenIntelligenceEngine

final class LibraryAnalysisSampleTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("kept-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func record(_ document: UUID, _ index: Int) -> PassageRecord {
        PassageRecord(id: UUID(), documentId: document, chunkIndex: index, pageNumber: nil, abstractionLevel: .detail)
    }

    private func document(
        _ id: UUID = UUID(), name: String, passages: Int, addedAt: Date = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> Document {
        Document(
            id: id, filename: name, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileHash: "hash-\(name)",
            contentType: .text, addedAt: addedAt, totalChunks: passages)
    }

    private func passage(_ document: UUID, _ index: Int, _ text: String, words: Int = 0) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: text, embedding: [],
            metadata: ChunkMetadata(chunkIndex: index, keywords: ["lease", "deposit"], wordCount: words))
    }

    private func keptFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Which passages are read

    func testALibraryThatFitsIsReadWhole() {
        let document = UUID()
        let records = (0..<300).map { record(document, $0) }
        XCTAssertNil(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 100, limit: 400))
        XCTAssertNil(LibraryIntelligenceCenter.samplePositions(records: [], newCount: 0, limit: 400))
        XCTAssertNotNil(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 101, limit: 400))
    }

    func testALargeLibraryIsSampledAcrossItAndKeepsItsDocumentsFirstPassages() throws {
        let big = UUID()
        let small = UUID()
        let single = UUID()
        // The small document's first passage (number 0) is the last one stored.
        var records = (0..<9_000).map { record(big, $0) }
        records += (1..<50).map { record(small, $0) }
        records.append(record(single, 0))
        records.append(record(small, 0))

        let sample = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 0, limit: 400))
        XCTAssertTrue(sample.new.isEmpty)
        XCTAssertEqual(sample.existing, sample.existing.sorted(), "in store order")
        XCTAssertEqual(Set(sample.existing).count, sample.existing.count, "no passage twice")
        XCTAssertLessThanOrEqual(sample.existing.count, 400, "never more than the limit")
        XCTAssertGreaterThanOrEqual(sample.existing.count, 397)
        XCTAssertTrue(sample.existing.allSatisfy { $0 >= 0 && $0 < records.count })

        // Three documents' first passages, and an even sample with the rest of the limit.
        XCTAssertTrue(sample.existing.contains(0), "the big document's first passage")
        XCTAssertTrue(sample.existing.contains(records.count - 2), "the one-passage document")
        XCTAssertTrue(sample.existing.contains(records.count - 1), "the small document's first passage, stored last")
        let even = RAGService.evenSampleIndices(count: records.count, limit: 397)
        XCTAssertTrue(Set(even).isSubset(of: Set(sample.existing)))
        XCTAssertGreaterThan(sample.existing.filter { $0 > 4_500 && $0 < 9_000 }.count, 150, "the far half is there too")

        let again = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 0, limit: 400))
        XCTAssertEqual(again.existing, sample.existing, "the same library gives the same sample")
    }

    /// The limit is a limit. A library of very many small documents cannot have a first passage
    /// read for each: a quarter of the sample goes to first passages, in store order.
    func testTheSampleNeverReadsMoreThanTheLimitHoweverManyDocumentsThereAre() throws {
        var records: [PassageRecord] = []
        var documents: [UUID] = []
        for _ in 0..<20_000 {
            let id = UUID()
            documents.append(id)
            records.append(record(id, 0))
            records.append(record(id, 1))
        }
        let sample = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 0, limit: 400))
        XCTAssertLessThanOrEqual(sample.existing.count, 400)
        XCTAssertGreaterThanOrEqual(sample.existing.count, 300)
        // The first hundred documents' first passages are positions 0, 2, 4, ... 198.
        XCTAssertTrue(Set(stride(from: 0, to: 200, by: 2)).isSubset(of: Set(sample.existing)))

        let withNew = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 40_000, limit: 400))
        XCTAssertLessThanOrEqual(withNew.existing.count + withNew.new.count, 400)
        XCTAssertFalse(withNew.existing.isEmpty)
        XCTAssertFalse(withNew.new.isEmpty)
    }

    func testALibraryAndTheDocumentBeingAddedShareTheLimitByTheirSizes() throws {
        let existing = UUID()
        let records = (0..<3_000).map { record(existing, $0) }
        let sample = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: records, newCount: 9_000, limit: 400))
        XCTAssertLessThanOrEqual(sample.existing.count, 100, "a quarter of the passages, a quarter of the limit")
        XCTAssertGreaterThanOrEqual(sample.existing.count, 99)
        XCTAssertEqual(sample.new.count, 300)
        XCTAssertEqual(sample.new, RAGService.evenSampleIndices(count: 9_000, limit: 300))
        XCTAssertEqual(sample.new.first, 0, "the new document's first passage")

        // A new document against an empty library.
        let alone = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: [], newCount: 9_000, limit: 400))
        XCTAssertTrue(alone.existing.isEmpty)
        XCTAssertEqual(alone.new.count, 400)

        // A large library and a small document: the document still gets a passage.
        let many = (0..<50_000).map { record(existing, $0) }
        let lopsided = try XCTUnwrap(LibraryIntelligenceCenter.samplePositions(records: many, newCount: 3, limit: 400))
        XCTAssertEqual(lopsided.new, [0])
        XCTAssertLessThanOrEqual(lopsided.existing.count + lopsided.new.count, 400)
    }

    // MARK: - What the report says

    func testAnAnalysisOfEveryPassageIsNotAnEstimate() async {
        let id = UUID()
        let chunks = (0..<30).map { passage(id, $0, "The deposit is returned within sixty days of the lease ending.") }
        let report = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: [document(id, name: "lease.txt", passages: 30)], chunks: chunks)
        XCTAssertEqual(report.corpus.chunkCount, 30)
        XCTAssertEqual(report.corpus.analysedChunkCount, 30)
        XCTAssertFalse(report.corpus.isEstimate)
        XCTAssertTrue(report.documents.first?.descriptor.contains("30 chunks") ?? false, report.documents.first?.descriptor ?? "")
    }

    func testAnAnalysisFromASampleKeepsTheLibrarysCountsAndScalesTheWordTotals() async {
        let id = UUID()
        // Forty passages of about twenty words stand for a library of four thousand.
        let sentence = "The deposit is returned within sixty days of the lease ending, less any unpaid rent or damage beyond normal wear."
        let chunks = (0..<40).map { passage(id, $0 * 100, sentence, words: 20) }
        let center = LibraryIntelligenceCenter()
        let whole = await center.analyzeLibrary(documents: [document(id, name: "lease.txt", passages: 40)], chunks: chunks)
        let sampled = await center.analyzeLibrary(
            documents: [document(id, name: "lease.txt", passages: 4_000)],
            chunks: chunks,
            library: LibraryIntelligenceCenter.LibrarySize(passages: 4_000, passagesByDocument: [id: 4_000]))

        XCTAssertEqual(sampled.corpus.chunkCount, 4_000)
        XCTAssertEqual(sampled.corpus.analysedChunkCount, 40)
        XCTAssertTrue(sampled.corpus.isEstimate)
        // The measurements themselves are the sample's.
        XCTAssertEqual(sampled.corpus.vocabularyRichness, whole.corpus.vocabularyRichness)
        XCTAssertEqual(sampled.corpus.avgWordsPerChunk, whole.corpus.avgWordsPerChunk)
        // The document's line gives its real passage count, and its words scaled from the
        // sample's (40 passages of 20 words, standing for 4,000 passages: 80,000 words).
        let wholeLine = whole.documents.first?.descriptor ?? ""
        let sampledLine = sampled.documents.first?.descriptor ?? ""
        XCTAssertTrue(wholeLine.contains("40 chunks"), wholeLine)
        XCTAssertTrue(sampledLine.contains("4000 chunks"), sampledLine)
        XCTAssertNotEqual(
            wholeLine.replacingOccurrences(of: "40 chunks", with: ""),
            sampledLine.replacingOccurrences(of: "4000 chunks", with: ""),
            "the word count is scaled, not the sample's 800")
        // Forty passages are under a thousand words, four thousand are over fifty thousand: the
        // plan's reasons follow the library's size, not the sample's.
        XCTAssertTrue(whole.embedding.rationale.contains("Compact corpus"), whole.embedding.rationale)
        XCTAssertFalse(sampled.embedding.rationale.contains("Compact corpus"), sampled.embedding.rationale)
        XCTAssertTrue(sampled.embedding.rationale.contains("Large corpus"), sampled.embedding.rationale)
    }

    // MARK: - What a sample can change

    private func report(
        _ report: LibraryIntelligenceCenter.IntelligenceReport,
        recommending embedding: LibraryIntelligenceCenter.EmbeddingPlan
    ) -> LibraryIntelligenceCenter.IntelligenceReport {
        LibraryIntelligenceCenter.IntelligenceReport(
            corpus: report.corpus, chunking: report.chunking, embedding: embedding, retrieval: report.retrieval,
            documents: report.documents, alerts: report.alerts)
    }

    /// A library that tunes itself takes its chunking settings from the analysis, whether the
    /// analysis read every passage or a sample: they cost nothing to change and each import
    /// sets them again. Another embedding model means embedding every document again, so a
    /// sample never asks for one, unless the library has no documents yet. (Code in the
    /// passages asks for another chunking than the default, and both reports are given a
    /// confident recommendation of another model.)
    @MainActor
    func testAReportFromASampleMovesTheChunkingAndNeverTheEmbeddingModel() async {
        let id = UUID()
        let code = "func total() { let value = [1, 2, 3]; if (value.isEmpty) { return } else { print(value); } }"
        let chunks = (0..<40).map { passage(id, $0, code) }
        let center = LibraryIntelligenceCenter()
        let another = LibraryIntelligenceCenter.EmbeddingPlan(
            providerId: "nl_contextual_embedding", dimension: 768, confidence: 0.9, rationale: "for the test",
            requiresCloudConsent: false)
        let exact = report(
            await center.analyzeLibrary(documents: [document(id, name: "code.txt", passages: 40)], chunks: chunks),
            recommending: another)
        let estimate = report(
            await center.analyzeLibrary(
                documents: [document(id, name: "code.txt", passages: 9_000)], chunks: chunks,
                library: LibraryIntelligenceCenter.LibrarySize(passages: 9_000, passagesByDocument: [id: 9_000])),
            recommending: another)
        XCTAssertTrue(exact.corpus.hasCode)
        XCTAssertFalse(exact.corpus.isEstimate)
        XCTAssertTrue(estimate.corpus.isEstimate)
        XCTAssertEqual(estimate.chunking.strategy, exact.chunking.strategy, "the same passages, the same plan")

        let library = KnowledgeContainer(name: "Code")
        let fromExact = RAGService.resolveAutoAdjustments(for: library, report: exact)
        XCTAssertEqual(fromExact.0.embeddingProviderId, "nl_contextual_embedding")
        XCTAssertEqual(fromExact.0.embeddingDim, 768)
        XCTAssertNotNil(fromExact.0.chunkingDirective, "code in the passages moves the chunking off its default")
        XCTAssertEqual(fromExact.1.count, 2, "one reason for the model and one for the chunking: \(fromExact.1)")

        let fromEstimate = RAGService.resolveAutoAdjustments(for: library, report: estimate)
        XCTAssertEqual(fromEstimate.0.embeddingProviderId, library.embeddingProviderId, "a sample never changes the model")
        XCTAssertEqual(fromEstimate.0.embeddingDim, library.embeddingDim)
        XCTAssertEqual(fromEstimate.0.chunkingDirective?.strategy, fromExact.0.chunkingDirective?.strategy)
        XCTAssertEqual(
            fromEstimate.0.chunkingDirective?.targetWordWindow, fromExact.0.chunkingDirective?.targetWordWindow)
        XCTAssertEqual(fromEstimate.1.count, 1, "the chunking alone: \(fromEstimate.1)")

        let firstImport = RAGService.resolveAutoAdjustments(for: library, report: estimate, allowingEstimate: true)
        XCTAssertEqual(firstImport.0.embeddingProviderId, "nl_contextual_embedding", "a library with no documents yet")
        XCTAssertEqual(firstImport.1, fromExact.1)
    }

    /// A sample of a library with many documents does not reach every one of them. A document
    /// it missed is shown with its name and its real count, and with no preview, not as one
    /// whose passages have yet to be made.
    func testADocumentTheSampleDidNotReachHasNoPreviewAndKeepsItsCount() async {
        let reached = UUID()
        let missed = UUID()
        let chunks = (0..<10).map { passage(reached, $0, "The deposit is returned within sixty days.") }
        let report = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: [document(reached, name: "a.txt", passages: 5_000), document(missed, name: "b.txt", passages: 7)],
            chunks: chunks,
            library: LibraryIntelligenceCenter.LibrarySize(passages: 5_007, passagesByDocument: [reached: 5_000, missed: 7]))
        let missedProfile = report.documents.first { $0.id == missed }
        XCTAssertEqual(missedProfile?.preview, "")
        XCTAssertEqual(missedProfile?.keyTopics, [])
        XCTAssertTrue(missedProfile?.descriptor.contains("7 chunks") ?? false, missedProfile?.descriptor ?? "")
        XCTAssertFalse((report.documents.first { $0.id == reached }?.preview ?? "").isEmpty)

        // A document that has no passages at all still says so.
        let empty = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: [document(missed, name: "b.txt", passages: 0)], chunks: [])
        XCTAssertEqual(empty.documents.first?.preview, "Awaiting chunk extraction.")
    }

    // MARK: - The kept files

    func testASignatureFollowsTheLibrary() {
        let first = document(name: "a.txt", passages: 10)
        let second = document(name: "b.txt", passages: 20)
        let base = LibraryIntelligenceCache.signature(documents: [first, second], passages: 30)
        XCTAssertEqual(base, LibraryIntelligenceCache.signature(documents: [second, first], passages: 30), "order does not matter")
        XCTAssertNotEqual(base, LibraryIntelligenceCache.signature(documents: [first, second], passages: 31))
        XCTAssertNotEqual(base.documents, LibraryIntelligenceCache.documentsSignature([first]))
        let recut = document(second.id, name: "b.txt", passages: 21)
        XCTAssertNotEqual(base.documents, LibraryIntelligenceCache.documentsSignature([first, recut]))
        let renamed = document(second.id, name: "c.txt", passages: 20)
        XCTAssertNotEqual(base.documents, LibraryIntelligenceCache.documentsSignature([first, renamed]))
        let third = document(name: "c.txt", passages: 0)
        XCTAssertNotEqual(base.documents, LibraryIntelligenceCache.documentsSignature([first, second, third]))
        XCTAssertEqual(base.documents.count, 32)
        XCTAssertTrue(base.documents.allSatisfy { $0.isHexDigit })
    }

    func testAKeptReportComesBackWhileTheLibraryIsUnchangedAndNotAfterIt() async throws {
        let library = UUID()
        let id = UUID()
        let documents = [document(id, name: "lease.txt", passages: 4_000)]
        let chunks = (0..<40).map { passage(id, $0, "Le dépôt est rendu dans les soixante jours. The deposit is returned within sixty days.") }
        let report = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: documents, chunks: chunks,
            library: LibraryIntelligenceCenter.LibrarySize(passages: 4_000, passagesByDocument: [id: 4_000]))
        let signature = LibraryIntelligenceCache.signature(documents: documents, passages: 4_000)

        let before = await LibraryIntelligenceCache.loadReport(containerId: library, signature: signature, in: folder)
        XCTAssertNil(before, "nothing kept yet")
        await LibraryIntelligenceCache.saveReport(report, containerId: library, signature: signature, in: folder)
        let loaded = await LibraryIntelligenceCache.loadReport(containerId: library, signature: signature, in: folder)
        let kept = try XCTUnwrap(loaded)

        XCTAssertEqual(kept.corpus.chunkCount, report.corpus.chunkCount)
        XCTAssertEqual(kept.corpus.analysedChunkCount, report.corpus.analysedChunkCount)
        XCTAssertEqual(kept.corpus.isEstimate, report.corpus.isEstimate)
        XCTAssertEqual(kept.corpus.vocabularyRichness, report.corpus.vocabularyRichness)
        XCTAssertEqual(kept.corpus.technicalDensity, report.corpus.technicalDensity)
        XCTAssertEqual(kept.corpus.semanticComplexity, report.corpus.semanticComplexity)
        XCTAssertEqual(kept.corpus.hasCode, report.corpus.hasCode)
        XCTAssertEqual(kept.corpus.languageHypotheses, report.corpus.languageHypotheses)
        XCTAssertFalse(kept.corpus.languageHypotheses.isEmpty)
        XCTAssertEqual(kept.chunking.strategy, report.chunking.strategy)
        XCTAssertEqual(kept.chunking.targetWordWindow, report.chunking.targetWordWindow)
        XCTAssertEqual(kept.chunking.overlapWords, report.chunking.overlapWords)
        XCTAssertEqual(kept.embedding.providerId, report.embedding.providerId)
        XCTAssertEqual(kept.embedding.dimension, report.embedding.dimension)
        XCTAssertEqual(kept.embedding.confidence, report.embedding.confidence)
        XCTAssertEqual(kept.retrieval.fusionStyle, report.retrieval.fusionStyle)
        XCTAssertEqual(kept.retrieval.vectorWeight, report.retrieval.vectorWeight)
        XCTAssertEqual(kept.documents.map(\.id), report.documents.map(\.id))
        XCTAssertEqual(kept.documents.map(\.descriptor), report.documents.map(\.descriptor))
        XCTAssertEqual(kept.documents.map(\.preview), report.documents.map(\.preview))
        XCTAssertEqual(kept.alerts, report.alerts)

        // The library changed: one more passage in the store, or another set of documents.
        let onePassageMore = await LibraryIntelligenceCache.loadReport(
            containerId: library, signature: LibraryIntelligenceCache.signature(documents: documents, passages: 4_001),
            in: folder)
        XCTAssertNil(onePassageMore)
        let otherDocuments = await LibraryIntelligenceCache.loadReport(
            containerId: library, signature: LibraryIntelligenceCache.signature(documents: [], passages: 4_000),
            in: folder)
        XCTAssertNil(otherDocuments)
        let anotherLibrary = await LibraryIntelligenceCache.loadReport(containerId: UUID(), signature: signature, in: folder)
        XCTAssertNil(anotherLibrary, "another library")
    }

    func testAKeptVocabularyComesBackWhileTheLibraryIsUnchanged() async throws {
        let library = UUID()
        let id = UUID()
        let chunks = (0..<60).map { passage(id, $0, "The blue outlet valve feeds the sterile rinse cycle \($0).") }
        let built = CorpusVocabulary.build(from: chunks)
        XCTAssertFalse(built.keywords.isEmpty)
        let signature = LibraryIntelligenceCache.signature(documents: [document(id, name: "manual.txt", passages: 60)], passages: 60)

        let before = await LibraryIntelligenceCache.loadVocabulary(containerId: library, signature: signature, in: folder)
        XCTAssertNil(before)
        await LibraryIntelligenceCache.saveVocabulary(built, containerId: library, signature: signature, in: folder)
        let loaded = await LibraryIntelligenceCache.loadVocabulary(containerId: library, signature: signature, in: folder)
        let kept = try XCTUnwrap(loaded)
        XCTAssertEqual(kept.keywords, built.keywords)
        XCTAssertEqual(kept.coOccurrences, built.coOccurrences)
        XCTAssertEqual(kept.textSnippets, built.textSnippets)
        // The report and the vocabulary are kept apart: one being there says nothing of the other.
        let report = await LibraryIntelligenceCache.loadReport(containerId: library, signature: signature, in: folder)
        XCTAssertNil(report)
    }

    /// A vocabulary holds words and snippets of the passages it was built from, and what is
    /// kept is removed by the library's documents. So one is kept only when it was built from
    /// every passage in the store and each of them belongs to a document the library lists.
    func testAVocabularyIsKeptOnlyWhenItIsOfTheWholeLibraryAndOfListedDocuments() {
        let listed = document(name: "a.txt", passages: 10)
        let unlisted = UUID()
        XCTAssertTrue(
            RAGService.vocabularyMayBeKept(
                passageDocuments: [listed.id], passagesUsed: 10, passagesStored: 10, listedDocuments: [listed]))
        XCTAssertFalse(
            RAGService.vocabularyMayBeKept(
                passageDocuments: [listed.id, unlisted], passagesUsed: 12, passagesStored: 12, listedDocuments: [listed]),
            "passages of a document that is being imported in pieces, or was removed on another device")
        XCTAssertFalse(
            RAGService.vocabularyMayBeKept(
                passageDocuments: [listed.id], passagesUsed: 6, passagesStored: 10, listedDocuments: [listed]),
            "part of the library")
        XCTAssertFalse(
            RAGService.vocabularyMayBeKept(passageDocuments: [], passagesUsed: 0, passagesStored: 0, listedDocuments: []),
            "a library with no documents")
    }

    /// The kept files hold text from the documents (a preview of each, snippets for the
    /// vocabulary). Whatever was made from documents a library no longer has is removed, by
    /// name, without waiting for anything to replace it.
    func testWhatWasMadeFromDocumentsALibraryNoLongerHasIsRemoved() async throws {
        let lease = UUID()
        let manual = UUID()
        let gone = UUID()
        let leaseDocuments = [document(name: "lease.txt", passages: 10), document(name: "rules.txt", passages: 5)]
        let manualDocuments = [document(name: "manual.txt", passages: 60)]
        let report = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: leaseDocuments, chunks: [passage(leaseDocuments[0].id, 0, "The deposit is returned within sixty days.")])
        let vocabulary = CorpusVocabulary.build(from: [passage(manualDocuments[0].id, 0, "The blue outlet valve.")])

        func keepEverything() async {
            for (library, documents, passages) in [(lease, leaseDocuments, 15), (manual, manualDocuments, 60), (gone, manualDocuments, 60)] {
                let signature = LibraryIntelligenceCache.signature(documents: documents, passages: passages)
                await LibraryIntelligenceCache.saveReport(report, containerId: library, signature: signature, in: folder)
                await LibraryIntelligenceCache.saveVocabulary(vocabulary, containerId: library, signature: signature, in: folder)
            }
        }
        await keepEverything()
        XCTAssertEqual(keptFiles().count, 6)

        // One document deleted from the lease library: both of its files go, at once.
        let afterDelete = [leaseDocuments[0]]
        LibraryIntelligenceCache.removeStale(
            containerId: lease, documents: LibraryIntelligenceCache.documentsSignature(afterDelete), in: folder)
        XCTAssertEqual(keptFiles().count, 4)
        XCTAssertFalse(keptFiles().contains { $0.hasPrefix(lease.uuidString) })
        // The same call with the documents it still has removes nothing.
        LibraryIntelligenceCache.removeStale(
            containerId: manual, documents: LibraryIntelligenceCache.documentsSignature(manualDocuments), in: folder)
        XCTAssertEqual(keptFiles().count, 4)

        // A load of the documents: one library is gone from the list (removed on another device)
        // and one has had a document removed there. Only what still matches stays.
        await keepEverything()
        try Data("x".utf8).write(to: folder.appendingPathComponent("not-one-of-ours.json"))
        LibraryIntelligenceCache.sweep(
            keeping: [
                lease: LibraryIntelligenceCache.documentsSignature(afterDelete),
                manual: LibraryIntelligenceCache.documentsSignature(manualDocuments),
            ], in: folder)
        XCTAssertEqual(keptFiles().count, 2)
        XCTAssertTrue(keptFiles().allSatisfy { $0.hasPrefix(manual.uuidString) }, "\(keptFiles())")

        // A library whose last document is gone is not in the list at all.
        LibraryIntelligenceCache.sweep(keeping: [:], in: folder)
        XCTAssertTrue(keptFiles().isEmpty)

        // Deleting a library removes what is kept for it and leaves the others'.
        await keepEverything()
        LibraryIntelligenceCache.remove(containerId: gone, in: folder)
        XCTAssertEqual(keptFiles().count, 4)
        XCTAssertFalse(keptFiles().contains { $0.hasPrefix(gone.uuidString) })
    }

    /// One file of each kind for a library. A report saved for the library as it is now replaces
    /// the report of what it was.
    func testSavingReplacesWhatWasKeptForTheLibraryAsItWas() async throws {
        let library = UUID()
        let before = [document(name: "lease.txt", passages: 10), document(name: "rules.txt", passages: 5)]
        let after = [before[0]]
        let report = await LibraryIntelligenceCenter().analyzeLibrary(
            documents: before, chunks: [passage(before[0].id, 0, "The deposit is returned within sixty days.")])
        let old = LibraryIntelligenceCache.signature(documents: before, passages: 15)
        let new = LibraryIntelligenceCache.signature(documents: after, passages: 10)
        await LibraryIntelligenceCache.saveReport(report, containerId: library, signature: old, in: folder)
        await LibraryIntelligenceCache.saveVocabulary(.empty, containerId: library, signature: old, in: folder)
        await LibraryIntelligenceCache.saveReport(report, containerId: library, signature: new, in: folder)

        let oldReport = await LibraryIntelligenceCache.loadReport(containerId: library, signature: old, in: folder)
        XCTAssertNil(oldReport)
        let newReport = await LibraryIntelligenceCache.loadReport(containerId: library, signature: new, in: folder)
        XCTAssertNotNil(newReport)
        XCTAssertEqual(keptFiles().filter { $0.contains(".report.") }.count, 1)
        let oldVocabulary = await LibraryIntelligenceCache.loadVocabulary(containerId: library, signature: old, in: folder)
        XCTAssertNotNil(
            oldVocabulary, "saving a report does not touch the vocabulary; the sweep and the stale check do")
    }
}
