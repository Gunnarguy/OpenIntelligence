//
//  StoredVectorRepairTests.swift
//  OpenIntelligenceTests
//
//  The health check's model check (5.8, 2026-11-18): one passage of each document embedded again and compared with its
//  stored vector; the documents another model wrote are re-embedded in place once per model revision, and a library
//  whose vectors still don't match afterwards, or whose repairs the person stopped, shows its rebuild banner instead.
//  Through f5759e4d sync had written the old model's vectors back over every in-place rebuild, so the libraries that
//  record said were Granite's still held MiniLM's (`VectorMergeKeepsReembeddedVectorsTests`).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class StoredVectorRepairTests: XCTestCase {
    private let live: [Float] = [0.6, 0.8, 0, 0]
    private let another: [Float] = [0, 0, 0.8, 0.6]

    private func chunk(_ document: UUID, _ index: Int, length: Int = 200) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: String(repeating: "a", count: length), embedding: [],
            metadata: ChunkMetadata(chunkIndex: index, characterCount: length))
    }

    private func defaults() throws -> UserDefaults {
        let name = "svr-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return defaults
    }

    func testOnePassageOfEachDocument_skippingDocumentsWithNoTestablePassage() throws {
        let a = UUID(), b = UUID(), c = UUID()
        let chunks = (0..<10).map { chunk(a, $0) } + (0..<4).map { chunk(b, $0) } + [chunk(c, 0, length: 10)]
        let sample = try XCTUnwrap(
            StoredVectorModelCheck.sample(of: chunks, documentIds: [a, b, c], perDocument: 1, skippingUntestable: true))
        XCTAssertEqual(sample.count, 2)
        XCTAssertEqual(Set(sample.map(\.documentId)), [a, b])
        // The default still refuses a library with an untestable document (the 2026-11-14 skip-the-rebuild check).
        XCTAssertNil(StoredVectorModelCheck.sample(of: chunks, documentIds: [a, b, c]))
    }

    /// Review row 4: a library where one document was rebuilt and another was not repairs only the second.
    func testAMixedLibraryNamesOnlyTheDocumentsAnotherModelWrote() throws {
        let rebuilt = UUID(), stale = UUID()
        let sample = [chunk(rebuilt, 0), chunk(stale, 0)]
        let verdict = try XCTUnwrap(
            StoredVectorModelCheck.documentsWithAnotherModelsVectors(
                sample: sample, stored: [live, another], fresh: [live, live]))
        XCTAssertEqual(verdict.failing, [stale])
        XCTAssertEqual(verdict.compared, 2)
    }

    /// Review row 3: an embedder that fails and returns zeros, or a stored vector of zeros, is no evidence of another
    /// model, so it never queues a rebuild.
    func testZeroVectorsOnEitherSideSayNothing() {
        let zero: [Float] = [0, 0, 0, 0]
        XCTAssertNil(StoredVectorModelCheck.isAnotherModels(stored: live, fresh: zero))
        XCTAssertNil(StoredVectorModelCheck.isAnotherModels(stored: zero, fresh: live))
        XCTAssertNil(StoredVectorModelCheck.isAnotherModels(stored: live, fresh: [1, 0]))
        XCTAssertFalse(StoredVectorModelCheck.storedVectorsAreAnotherModels(stored: [another], fresh: [zero]))
        XCTAssertNil(
            StoredVectorModelCheck.documentsWithAnotherModelsVectors(
                sample: [chunk(UUID(), 0)], stored: [another], fresh: [zero]))
        XCTAssertEqual(StoredVectorModelCheck.isAnotherModels(stored: another, fresh: live), true)
        XCTAssertEqual(StoredVectorModelCheck.isAnotherModels(stored: live, fresh: live), false)
    }

    /// Review row 2: the check run twice with the stored vectors unchanged queues one repair, then shows the banner.
    func testARepairThatDidNotTakeShowsTheBannerInsteadOfQueueingAgain() throws {
        let defaults = try defaults()
        let library = UUID(), stale = UUID()
        let revision = "granite-embedding-small-english-r2@test"
        XCTAssertTrue(StoredVectorModelCheck.checkIsDue(library: library, revision: revision, defaults: defaults))
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: [stale], library: library, revision: revision, repairsSuppressed: false, defaults: defaults),
            .rebuild([stale]))
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: [stale], library: library, revision: revision, repairsSuppressed: false, defaults: defaults),
            .showBanner)
        // A later model revision gets its own repair.
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: [stale], library: library, revision: revision + "-next", repairsSuppressed: false,
                defaults: defaults),
            .rebuild([stale]))
    }

    func testStoppedRepairsShowTheBanner_andALiveLibraryIsNotCheckedAgain() throws {
        let defaults = try defaults()
        let library = UUID()
        let revision = "granite@test"
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: [UUID()], library: library, revision: revision, repairsSuppressed: true, defaults: defaults),
            .showBanner)
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: nil, library: library, revision: revision, repairsSuppressed: false, defaults: defaults),
            .none, "nothing compared records nothing")
        XCTAssertTrue(StoredVectorModelCheck.checkIsDue(library: library, revision: revision, defaults: defaults))
        XCTAssertEqual(
            StoredVectorModelCheck.repairAction(
                failing: [], library: library, revision: revision, repairsSuppressed: false, defaults: defaults),
            .none)
        XCTAssertFalse(StoredVectorModelCheck.checkIsDue(library: library, revision: revision, defaults: defaults))
    }

    func testCandidatesSpreadThroughEachDocument() {
        let a = UUID(), b = UUID()
        let records = (0..<9).map { PassageRecord(id: UUID(), documentId: a, chunkIndex: $0, pageNumber: nil, abstractionLevel: .detail) }
            + [PassageRecord(id: UUID(), documentId: b, chunkIndex: 0, pageNumber: nil, abstractionLevel: .detail)]
        let ids = RAGService.modelCheckCandidateIds(from: records)
        let picked = records.filter { ids.contains($0.id) }
        XCTAssertEqual(picked.filter { $0.documentId == a }.map(\.chunkIndex), [0, 3, 6])
        XCTAssertEqual(picked.filter { $0.documentId == b }.count, 1)
    }

    /// Gate E may decline to judge only in a Granite library the check flagged (review row 5).
    func testOnlyAFlaggedGraniteLibraryLetsGateEDecline() {
        let engine = RAGService()
        let library = UUID()
        XCTAssertFalse(engine.passageVectorsMayBeAnotherModels(in: library, providerId: EmbeddingProviderDefaults.coreML))
        engine.librariesWithAnotherModelsVectors.insert(library)
        defer { engine.librariesWithAnotherModelsVectors.remove(library) }
        XCTAssertTrue(engine.passageVectorsMayBeAnotherModels(in: library, providerId: EmbeddingProviderDefaults.coreML))
        for other in ["nl_embedding", "apple_fm_embed", EmbeddingProviderDefaults.coreAI] {
            XCTAssertFalse(engine.passageVectorsMayBeAnotherModels(in: library, providerId: other), other)
        }
    }

    // MARK: - Wiring, with the real model (review row 11)

    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    private func holdPro() {
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    /// The health check (`evaluateSemanticIndexHealth`) finds a library whose stored vectors another model wrote,
    /// re-embeds it in place through the self-healing queue, flags it for Gate E meanwhile, and the next check finds the
    /// live model's vectors, records that and lifts the flag.
    func testTheHealthCheckRepairsALibraryHoldingAnotherModelsVectors() async throws {
        let engine = RAGService()
        holdPro()
        let library = try engine.containerService.createContainer(name: "Model check wiring \(UUID().uuidString.prefix(8))")
        let recordKey = "storedVectorModelCheck.\(library.id.uuidString)"
        addTeardownBlock { @MainActor in
            UserDefaults.standard.removeObject(forKey: recordKey)
            engine.ingestionItems.removeAll { $0.containerId == library.id }
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: library.id)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("model-check-\(UUID().uuidString.prefix(8)).txt")
        try Data(
            "The quillberry boiler in the test flat is serviced every March by the building's own engineer. The meter in the hall cupboard is read on the first of each month."
                .utf8
        ).write(to: url)
        let result = await engine.ingestDocuments([url], containerId: library.id)
        XCTAssertEqual(result.successCount, 1)
        for _ in 0..<300 where engine.isProcessing { try await Task.sleep(for: .milliseconds(100)) }

        let database = try await engine.dbForContainer(library.id)
        let stored = try await database.allChunks()
        let vectors = await database.getEmbeddings(forChunkIDs: stored.map(\.id))
        try XCTSkipIf(!vectors.contains(where: EmbeddingVectorCheck.isUsable), "this Simulator's model writes zero vectors")
        // Another model's vectors: each one reversed, unrelated to the live model's for the same text.
        try await database.clear()
        try await database.storeBatch(
            chunks: zip(stored, vectors).map { chunk, vector in
                DocumentChunk(
                    id: chunk.id, documentId: chunk.documentId, content: chunk.content, parentContent: chunk.parentContent,
                    contextualPrefix: chunk.contextualPrefix, embedding: Array(vector.reversed()), metadata: chunk.metadata)
            })
        try await database.persist()

        await engine.evaluateSemanticIndexHealth(for: library.id)
        XCTAssertTrue(engine.librariesWithAnotherModelsVectors.contains(library.id), "the check flagged the library")
        XCTAssertTrue(
            engine.pendingSelfHealingContainerIds.contains(library.id) || engine.selfHealingRebuildTask != nil,
            "the check queued the in-place repair")
        for _ in 0..<300 where engine.selfHealingRebuildTask != nil || !engine.pendingSelfHealingContainerIds.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        for _ in 0..<300 where engine.isProcessing { try await Task.sleep(for: .milliseconds(100)) }

        // The import's document summary can land after the snapshot above, so the repaired store holds at least the
        // passages it had.
        let repaired = try await database.allChunks()
        let repairedById = Dictionary(repaired.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        XCTAssertTrue(Set(stored.map(\.id)).isSubset(of: Set(repairedById.keys)), "the passages were kept")
        for passage in stored {
            XCTAssertEqual(
                repairedById[passage.id]?.metadata.createdAt, passage.metadata.createdAt.addingTimeInterval(0.001),
                "each passage is dated one millisecond after its own time")
        }
        let container = try XCTUnwrap(engine.containerService.containers.first { $0.id == library.id })
        let context = await engine.resolveEmbeddingContext(preferredContainerId: library.id)
        let matches = await engine.storedVectorsAlreadyMatchLiveModel(for: container, service: context.service)
        XCTAssertTrue(matches, "the repair wrote the live model's vectors")

        // The next launch's check finds the live model's vectors, records that and lifts the flag.
        engine.indexRepairsTriedThisLaunch.remove("model:\(library.id.uuidString)")
        let records = try await database.passageRecords()
        let actedAgain = await engine.storedVectorsAreAnotherModels(in: container, db: database, records: records)
        XCTAssertFalse(actedAgain)
        XCTAssertFalse(engine.librariesWithAnotherModelsVectors.contains(library.id))
        XCTAssertFalse(
            StoredVectorModelCheck.checkIsDue(
                library: library.id, revision: EmbeddingService.sharedCoreMLProvider.modelRevision))
    }
}
