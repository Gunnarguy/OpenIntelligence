//
//  RebuildFalseAlarmTests.swift
//  OpenIntelligenceTests
//
//  On 2026-10-07 the owner imported a document, asked one question, and the Documents tab said
//  "This library needs its search index rebuilt". His phone's trace showed two causes on a healthy
//  library: the app's own tuning changed the chunk strategy and the fingerprint counted that as a
//  changed pipeline, and a stored fingerprint was gone after the library list was reloaded from disk.
//  These pin both: what the fingerprint's chunker term counts, and the device-local record that
//  keeps a fingerprint when the list loses it.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class RebuildFalseAlarmTests: XCTestCase {
    private func directive(_ source: ChunkingDirective.Source, _ strategy: String, _ window: Int) -> ChunkingDirective {
        ChunkingDirective(source: source, strategy: strategy, targetWordWindow: window, overlapWords: 40)
    }

    private func fingerprint(_ recipe: String) -> String {
        EmbeddingFingerprint.compute(
            providerId: "coreml_sentence_embedding", dimension: 384, maxSequenceLength: 512,
            poolingRecipe: "mean", modelRevision: "MiniLM-L6-v2/coreml-mlpackage", chunkerRecipe: recipe)
    }

    // MARK: - The chunker term

    func testTheAppsOwnTuningIsNotPartOfTheFingerprint() {
        XCTAssertEqual(EmbeddingFingerprint.chunkerRecipe(for: nil), "default")
        XCTAssertEqual(EmbeddingFingerprint.chunkerRecipe(for: directive(.auto, "balanced", 260)), "default")
        XCTAssertEqual(EmbeddingFingerprint.chunkerRecipe(for: directive(.auto, "densePrecision", 180)), "default")
        XCTAssertEqual(EmbeddingFingerprint.chunkerRecipe(for: directive(.baseline, "balanced", 260)), "default")
    }

    func testAChunkSizeThePersonChoseStillCounts() {
        XCTAssertEqual(
            EmbeddingFingerprint.chunkerRecipe(for: directive(.manual, "densePrecision", 180)), "densePrecision/180")
        XCTAssertNotEqual(
            fingerprint(EmbeddingFingerprint.chunkerRecipe(for: directive(.manual, "densePrecision", 180))),
            fingerprint(EmbeddingFingerprint.chunkerRecipe(for: directive(.manual, "balanced", 260))))
    }

    func testTheSelfTunerChangingStrategyLeavesTheFingerprintAlone() {
        // What the phone's log showed: recorded under one strategy, tuned to another a minute later.
        let before = fingerprint(EmbeddingFingerprint.chunkerRecipe(for: directive(.auto, "balanced", 260)))
        let after = fingerprint(EmbeddingFingerprint.chunkerRecipe(for: directive(.auto, "densePrecision", 180)))
        XCTAssertEqual(before, after)
        XCTAssertEqual(before, fingerprint(EmbeddingFingerprint.chunkerRecipe(for: nil)))
    }

    func testAFingerprintStoredThrough55IsRecognisedAsTheSamePipeline() {
        // Through 5.5 an auto directive's strategy and window were in the term. A library whose
        // directive has not changed since must match the legacy form, so it is re-recorded quietly.
        let tuned = directive(.auto, "densePrecision", 180)
        XCTAssertEqual(EmbeddingFingerprint.legacyChunkerRecipe(for: tuned), "densePrecision/180")
        XCTAssertEqual(EmbeddingFingerprint.legacyChunkerRecipe(for: nil), "default")
        let stored = fingerprint("densePrecision/180")
        XCTAssertNotEqual(stored, fingerprint(EmbeddingFingerprint.chunkerRecipe(for: tuned)))
        XCTAssertEqual(stored, fingerprint(EmbeddingFingerprint.legacyChunkerRecipe(for: tuned)))
    }

    // MARK: - Which service the fingerprint describes

    func testTheCoreMLAndCoreAIIdentitiesAreDifferentFingerprints() {
        // The real cause on the phone. A new library on Core AI was recorded from the app's default
        // service, which is Core ML, and its first question compared against the Core AI identity.
        // With the tokenizer of 2026-10-07 these two were 69f06c6c23035978 and 3236a5aa2cfabb78,
        // the "recorded" and "live" values in the owner's log. Both sides have to describe the
        // service the library embeds with, because the two identities can never be equal.
        let coreML = EmbeddingFingerprint.compute(
            providerId: "coreml_sentence_embedding", dimension: 384, maxSequenceLength: 512,
            poolingRecipe: "mean-attention-masked/l2", modelRevision: "MiniLM-L6-v2/coreml-mlpackage",
            chunkerRecipe: "default")
        let coreAI = EmbeddingFingerprint.compute(
            providerId: "coreai_sentence_embedding", dimension: 384, maxSequenceLength: 512,
            poolingRecipe: "mean-attention-masked/l2", modelRevision: "MiniLM-L6-v2/coreai-mlirb-meanpool",
            chunkerRecipe: "default")
        XCTAssertNotEqual(coreML, coreAI)
        XCTAssertEqual(coreML.count, 16)
    }

    // MARK: - The device-local record

    private func library(
        _ id: UUID = UUID(), fingerprint: String?, provider: String = "coreml_sentence_embedding", dim: Int = 384
    ) -> KnowledgeContainer {
        KnowledgeContainer(
            id: id, name: "Library", embeddingProviderId: provider, embeddingDim: dim, embeddingFingerprint: fingerprint
        )
    }

    func testAListThatLostAFingerprintGetsItBack() {
        let id = UUID()
        let record = ContainerService.updatingLocalFingerprintRecord(
            [:], with: [library(id, fingerprint: "0ca10df0aa1a2d84")])
        // The list read back from disk is an older one, written before the fingerprint was recorded.
        let reloaded = ContainerService.restoringLocalFingerprints(in: [library(id, fingerprint: nil)], record: record)
        XCTAssertEqual(reloaded.first?.embeddingFingerprint, "0ca10df0aa1a2d84")
    }

    func testSavingAStaleListDoesNotEraseTheRecord() {
        let id = UUID()
        var record = ContainerService.updatingLocalFingerprintRecord(
            [:], with: [library(id, fingerprint: "0ca10df0aa1a2d84")])
        record = ContainerService.updatingLocalFingerprintRecord(record, with: [library(id, fingerprint: nil)])
        XCTAssertEqual(record[id.uuidString], "coreml_sentence_embedding|384|0ca10df0aa1a2d84")
    }

    func testALibraryThatHasAFingerprintKeepsItsOwn() {
        let id = UUID()
        let record = [id.uuidString: "coreml_sentence_embedding|384|old"]
        let reloaded = ContainerService.restoringLocalFingerprints(
            in: [library(id, fingerprint: "new")], record: record)
        XCTAssertEqual(reloaded.first?.embeddingFingerprint, "new")
    }

    func testARecordForAnotherEmbedderIsNotRestored() {
        let id = UUID()
        let record = [id.uuidString: "coreml_sentence_embedding|384|0ca10df0aa1a2d84"]
        let otherDimension = ContainerService.restoringLocalFingerprints(
            in: [library(id, fingerprint: nil, dim: 512)], record: record)
        XCTAssertNil(otherDimension.first?.embeddingFingerprint)
        let otherProvider = ContainerService.restoringLocalFingerprints(
            in: [library(id, fingerprint: nil, provider: "coreai_sentence_embedding")], record: record)
        XCTAssertNil(otherProvider.first?.embeddingFingerprint)
    }

    func testAMalformedOrMissingEntryRestoresNothing() {
        let id = UUID()
        for record in [[id.uuidString: "garbage"], [id.uuidString: "coreml_sentence_embedding|384|"], [:]] {
            let reloaded = ContainerService.restoringLocalFingerprints(
                in: [library(id, fingerprint: nil)], record: record)
            XCTAssertNil(reloaded.first?.embeddingFingerprint)
        }
        XCTAssertNil(ContainerService.localFingerprintEntry(for: library(fingerprint: nil)))
        XCTAssertNil(ContainerService.localFingerprintEntry(for: library(fingerprint: "")))
    }
}
