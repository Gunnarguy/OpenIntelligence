//
//  LargeLibraryCostTests.swift
//  OpenIntelligenceTests
//
//  Work that used to grow with the number of passages in a library and now does not. Found on
//  2026-10-10 with a library of 144,247 passages on the owner's iPhone: a part-of-speech tagger
//  run over every passage for the first question after each launch, every passage scored to pick
//  a few dozen suggested-question samples each time Chat opened, a regular expression compiled
//  for every pattern for every passage, and both copies of every synced library decoded and
//  compared on every launch.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class LargeLibraryCostTests: XCTestCase {
    private func passages(_ count: Int, summaries: Set<Int> = []) -> [DocumentChunk] {
        let document = UUID()
        return (0..<count).map { index in
            let metadata = ChunkMetadata(
                chunkIndex: index, abstractionLevel: summaries.contains(index) ? .documentSummary : .detail)
            return DocumentChunk(
                documentId: document, content: "passage \(index)", embedding: [], metadata: metadata)
        }
    }

    func testAVocabularyIsBuiltFromEveryPassageOfASmallLibrary() {
        let small = passages(300)
        XCTAssertEqual(CorpusVocabulary.sampledForVocabulary(small).map(\.metadata.chunkIndex), Array(0..<300))
    }

    func testAVocabularyIsBuiltFromAnEvenSampleOfALargeLibrary() {
        let sample = CorpusVocabulary.sampledForVocabulary(passages(144_247))
        XCTAssertEqual(sample.count, CorpusVocabulary.vocabularySampleLimit)
        let numbers = sample.map(\.metadata.chunkIndex)
        XCTAssertEqual(numbers, numbers.sorted(), "in the library's order")
        XCTAssertEqual(numbers.first, 0)
        XCTAssertGreaterThan(numbers.last ?? 0, 144_000, "reaches the end of the library")
    }

    func testTheQuestionSamplerSeesABoundedPoolThatKeepsEverySummary() {
        let summaries: Set<Int> = [7, 50_001, 144_246]
        let pool = RAGService.suggestedQuestionPool(from: passages(144_247, summaries: summaries))
        XCTAssertLessThanOrEqual(pool.count, RAGService.suggestedQuestionPoolLimit + summaries.count)
        XCTAssertEqual(
            Set(pool.filter { $0.metadata.abstractionLevel == .documentSummary }.map(\.metadata.chunkIndex)),
            summaries)
        XCTAssertEqual(RAGService.suggestedQuestionPool(from: passages(900)).count, 900)
    }

    func testCrossReferencesAreStillFoundWithPatternsCompiledOnce() {
        let text = "See page 12 for the schedule. Refer to page 40 for the limits."
        for _ in 0..<3 {
            XCTAssertEqual(Set(GraphIndexService.extractReferenceTargets(from: text)), ["page:12", "page:40"])
        }
    }

    func testALongTextIsReadInEvenSlicesThatStayInsideIt() {
        let slices = SQLiteFullTextService.evenSlices(length: 88_000_000, share: 2_000_000)
        XCTAssertEqual(slices.count, 8)
        XCTAssertEqual(slices.reduce(0) { $0 + $1.length }, 2_000_000)
        XCTAssertEqual(slices.first?.start, 1, "SQLite counts characters from 1")
        XCTAssertEqual(slices.last.map { $0.start + $0.length - 1 }, 88_000_000, "the last slice ends at the end")
        XCTAssertEqual(slices.map(\.start), slices.map(\.start).sorted())

        let short = SQLiteFullTextService.evenSlices(length: 900, share: 2_000_000)
        XCTAssertEqual(short.count, 1)
        XCTAssertEqual(short.first?.start, 1)
        XCTAssertEqual(short.first?.length, 900)
        XCTAssertTrue(SQLiteFullTextService.evenSlices(length: 0, share: 2_000_000).isEmpty)
    }

    func testTheAtlasStatisticsFinishOnAVeryLongDocument() async {
        // Six million characters in one document. Reading all of it took the phrase statistic
        // long enough on a phone that the Atlas map never finished.
        let library = UUID()
        let document = UUID()
        let sentence = "the hydraulic pump schedule lists each filter change for the service bay. "
        let text = String(repeating: sentence, count: 6_000_000 / sentence.count)
        await SQLiteFullTextService.shared.store(text: text, for: document, containerId: library)
        let started = Date()
        let terms = await SQLiteFullTextService.shared.getTopTermsForContainer(containerId: library, limit: 10)
        let phrases = await SQLiteFullTextService.shared.getKeyPhrasesForContainer(containerId: library, limit: 5)
        let seconds = Date().timeIntervalSince(started)
        await SQLiteFullTextService.shared.delete(for: document)

        XCTAssertTrue(terms.map(\.term).contains("hydraulic"))
        XCTAssertFalse(phrases.isEmpty)
        XCTAssertLessThan(seconds, 30)
    }

    func testANewLibraryOnIPhoneUsesTheCoreMLCopyAndNoLibraryIsMovedBetweenCopies() {
        #if os(iOS)
            XCTAssertEqual(EmbeddingProviderDefaults.preferredSentenceProviderId, "coreml_sentence_embedding")
        #endif
        XCTAssertTrue(
            EmbeddingProviderDefaults.areCopiesOfOneModel("coreai_sentence_embedding", "coreml_sentence_embedding"))
        XCTAssertFalse(
            EmbeddingProviderDefaults.areCopiesOfOneModel("coreai_sentence_embedding", "nl_contextual_embedding"))
    }

    func testTheSyncRecordSurvivesARestartAndChangesWithItsInputs() throws {
        let suite = "large-library-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = UUID()
        let signature = "vector_database_\(library)_meta.json:159339521:1791620402.0|docs:\(UUID())"
        let digest = WorkspaceSyncService.vectorStoreSignatureDigest(signature)

        XCTAssertEqual(WorkspaceSyncService.savedVectorStoreSignatureDigests(defaults: defaults), [:])
        WorkspaceSyncService.saveVectorStoreSignatureDigests([library: digest], defaults: defaults)
        XCTAssertEqual(WorkspaceSyncService.savedVectorStoreSignatureDigests(defaults: defaults), [library: digest])

        // One byte more in a file, or a second later, is a different record.
        XCTAssertNotEqual(digest, WorkspaceSyncService.vectorStoreSignatureDigest(signature + "1"))
        XCTAssertEqual(digest, WorkspaceSyncService.vectorStoreSignatureDigest(signature))
    }
}
