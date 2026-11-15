//
//  FiveChecksSimulatorTests.swift
//  OpenIntelligenceTests
//
//  The hosted half of five roadmap checks run in the iOS 27 Simulator on 2026-11-14 (5.8). The screens are in
//  `OpenIntelligenceUITests/FiveChecksUITests.swift`.
//
//  - A rebuild the import queue vetoes is not a success and the library keeps its rebuild flag, the one value
//    the Documents banner reads (`DocumentLibraryView.indexRebuildBanner`), for a store with no passages and for
//    a store whose vectors are all zero. Runs with the suite, on an engine and libraries of its own.
//  - `OI_FIVE_CHECKS=seed` (as `TEST_RUNNER_OI_FIVE_CHECKS`): saves, through the chat's own save, an answer that
//    cites [S13] of 15 passages in the app's open library, for the UI test that relaunches the app and taps it.
//    `OI_FIVE_CHECKS=clean` removes what the seed added.
//  - `OI_FIVE_CHECKS=lease`: "Summarize my lease" asked of a library holding a lease and three other documents,
//    with Apple's model. Needs a copy patched by `scripts/sim_model_copy.py`.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class FiveChecksSimulatorTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?
    private static let seedPrefix = "five-checks-"

    private static var wanted: String { ProcessInfo.processInfo.environment["OI_FIVE_CHECKS"] ?? "" }

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    private func holdPro() {
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    /// A library of its own holding one short note, removed when the test ends.
    private func libraryWithOneNote(_ label: String, in engine: RAGService) async throws -> (UUID, Document) {
        holdPro()
        let library = try engine.containerService.createContainer(name: "\(label) \(UUID().uuidString.prefix(8))")
        addTeardownBlock { @MainActor in
            engine.ingestionItems.removeAll { $0.containerId == library.id }
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            engine.containerService.deleteContainer(id: library.id)
        }
        let name = "five-checks-veto-\(UUID().uuidString.prefix(8))"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
        try Data(
            "The quillberry boiler in the test flat is serviced every March by the building's own engineer. The meter in the hall cupboard is read on the first of each month."
                .utf8
        ).write(to: url)
        holdPro()
        let result = await engine.ingestDocuments([url], containerId: library.id)
        XCTAssertEqual(result.successCount, 1, "the note was imported")
        let document = try XCTUnwrap(engine.documents.first { $0.filename.hasPrefix(name) })
        return (library.id, document)
    }

    private func waitForSelfHealing(_ engine: RAGService) async throws {
        for _ in 0..<300 where engine.selfHealingRebuildTask != nil || !engine.pendingSelfHealingContainerIds.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertNil(engine.selfHealingRebuildTask, "the self-healing pass did not end in 30 s")
    }

    /// The veto itself, shared by the two stores: the health check flags the library and its repair is vetoed, the
    /// banner's Rebuild is vetoed and the flag comes back, a direct rebuild throws, and nothing was rebuilt.
    private func assertTheRebuildIsVetoed(
        _ engine: RAGService, library: UUID, document: Document, storeLabel: String
    ) async throws {
        let database = try await engine.dbForContainer(library)
        engine.ingestionItems.append(
            IngestionItem(url: document.fileURL, containerId: library, stage: .paused, detail: "Paused"))
        XCTAssertTrue(
            RAGService.blockingIngestionURLs(in: engine.ingestionItems).contains(document.fileURL),
            "the paused queue item names the document's file")
        let passagesBefore = try await database.count()

        await engine.evaluateSemanticIndexHealth(for: library)
        XCTAssertTrue(
            engine.librariesNeedingIndexRebuild.contains(library), "\(storeLabel): the health check flags the library")
        try await waitForSelfHealing(engine)
        XCTAssertTrue(
            engine.librariesNeedingIndexRebuild.contains(library),
            "\(storeLabel): after the vetoed automatic repair the library still shows its banner")

        // The banner's own button.
        engine.rebuildSemanticIndex(for: library)
        try await waitForSelfHealing(engine)
        XCTAssertTrue(
            engine.librariesNeedingIndexRebuild.contains(library),
            "\(storeLabel): after a vetoed Rebuild the banner is back")

        do {
            try await engine.reembedDocuments(in: library, reason: "Self-healing: empty vector store")
            XCTFail("\(storeLabel): a vetoed rebuild returned as if it had rebuilt")
        } catch let error as RAGServiceError {
            guard case .rebuildBlockedByQueue(let blocked) = error else {
                XCTFail("\(storeLabel): \(error)")
                return
            }
            XCTAssertEqual(blocked, 1)
            print("[FiveChecks] \(storeLabel): rebuild vetoed, error text: \(error.localizedDescription)")
        }
        let passagesAfter = try await database.count()
        XCTAssertEqual(passagesAfter, passagesBefore, "\(storeLabel): nothing was rebuilt")
        print(
            "[FiveChecks] \(storeLabel): flag kept=\(engine.librariesNeedingIndexRebuild.contains(library)) passages before=\(passagesBefore) after=\(passagesAfter)"
        )

        // The other side: with the queue item gone the same Rebuild repairs the library and the flag goes.
        engine.ingestionItems.removeAll { $0.containerId == library }
        engine.rebuildSemanticIndex(for: library)
        try await waitForSelfHealing(engine)
        for _ in 0..<300 where engine.isProcessing { try await Task.sleep(for: .milliseconds(100)) }
        let repaired = try await database.chunkCount(forDocument: document.id)
        print(
            "[FiveChecks] \(storeLabel): unblocked rebuild, flag=\(engine.librariesNeedingIndexRebuild.contains(library)) passages of the note=\(repaired)"
        )
    }

    func testAVetoedRebuildOfALibraryWithNoPassagesIsNotASuccessAndKeepsItsBanner() async throws {
        let engine = RAGService()
        let (library, document) = try await libraryWithOneNote("Five checks empty store", in: engine)
        let database = try await engine.dbForContainer(library)
        try await database.clear()
        let count = try await database.count()
        XCTAssertEqual(count, 0, "the store holds no passages")
        try await assertTheRebuildIsVetoed(engine, library: library, document: document, storeLabel: "empty store")
    }

    func testAVetoedRebuildOfALibraryWithAllZeroVectorsIsNotASuccessAndKeepsItsBanner() async throws {
        let engine = RAGService()
        let (library, document) = try await libraryWithOneNote("Five checks zero vectors", in: engine)
        let database = try await engine.dbForContainer(library)
        let stored = try await database.allChunks()
        XCTAssertFalse(stored.isEmpty)
        let width = max(stored.first?.embedding.count ?? 0, 384)
        try await database.clear()
        try await database.storeBatch(
            chunks: stored.map {
                DocumentChunk(
                    id: $0.id, documentId: $0.documentId, content: $0.content, parentContent: $0.parentContent,
                    contextualPrefix: $0.contextualPrefix, embedding: [Float](repeating: 0, count: width),
                    metadata: $0.metadata)
            })
        let count = try await database.count()
        XCTAssertEqual(count, stored.count, "the store holds the passages, with zero vectors")
        let sample = await database.getEmbeddings(forIndices: Array(0..<count))
        let nonZero = sample.filter { vector in vector.contains { $0 != 0 } }.count
        print("[FiveChecks] zero vectors: \(count) passages, \(nonZero) with a non-zero vector")
        XCTAssertEqual(nonZero, 0, "every stored vector is zero")
        try await assertTheRebuildIsVetoed(engine, library: library, document: document, storeLabel: "zero vectors")
    }

    // MARK: - Vectors another device already rebuilt (5.8)

    /// With the real embedding model: the vectors an import just wrote are recognised as the live model's, so a
    /// device that receives them need not rebuild; the same passages under other vectors are not.
    func testStoredVectorsFromTheLiveModelAreRecognised_andOtherVectorsAreNot() async throws {
        let engine = RAGService()
        let (library, _) = try await libraryWithOneNote("Five checks model check", in: engine)
        let context = await engine.resolveEmbeddingContext(preferredContainerId: library)
        let container = try XCTUnwrap(engine.containerService.containers.first { $0.id == library })
        let database = try await engine.dbForContainer(library)
        let stored = try await database.allChunks()
        let vectors = await database.getEmbeddings(forChunkIDs: stored.map(\.id))
        let usable = vectors.filter { vector in vector.contains { $0 != 0 } }.count
        print("[FiveChecks] model check: \(stored.count) passages, \(usable) with a non-zero vector, provider \(context.providerId)")
        try XCTSkipIf(usable == 0, "this Simulator's embedding model writes zero vectors, so nothing can be compared")

        let asWritten = await engine.storedVectorsAlreadyMatchLiveModel(for: container, service: context.service)
        XCTAssertTrue(asWritten, "the vectors the live model just wrote are its own")

        // The same passages under vectors from somewhere else: each one reversed, as another model's would be unrelated.
        try await database.clear()
        try await database.storeBatch(
            chunks: zip(stored, vectors).map { chunk, vector in
                DocumentChunk(
                    id: chunk.id, documentId: chunk.documentId, content: chunk.content, parentContent: chunk.parentContent,
                    contextualPrefix: chunk.contextualPrefix, embedding: Array(vector.reversed()), metadata: chunk.metadata)
            })
        let foreign = await engine.storedVectorsAlreadyMatchLiveModel(for: container, service: context.service)
        XCTAssertFalse(foreign, "vectors from another space are not the live model's")
    }

    // MARK: - A saved answer that cites [S13]

    private func passage(_ text: String, document: UUID, index: Int) -> DocumentChunk {
        DocumentChunk(
            documentId: document, content: text, embedding: [0],
            metadata: ChunkMetadata(
                chunkIndex: index, pageNumber: nil, sectionTitle: nil, keywords: [], hasNumericData: false,
                hasListStructure: false, wordCount: text.split(separator: " ").count, characterCount: text.count))
    }

    func testSeedASavedAnswerThatCitesS13() async throws {
        try XCTSkipUnless(Self.wanted == "seed", "set OI_FIVE_CHECKS=seed")
        let engine = IntentSupport.engine()
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk { try await Task.sleep(for: .milliseconds(100)) }
        let library = engine.containerService.activeContainerId

        let name = "\(Self.seedPrefix)heron-note"
        var document = engine.documents.first { $0.filename.hasPrefix(name) }
        if document == nil {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).txt")
            try Data(
                "The first paragraph is here for context.\n\nThe heron note says the boathouse key sits under the third step of the old dock.\n\nThe last paragraph comes after it."
                    .utf8
            ).write(to: url)
            let result = await engine.ingestDocuments([url], containerId: library)
            XCTAssertEqual(result.successCount, 1, "the note was imported")
            document = engine.documents.first { $0.filename.hasPrefix(name) }
        }
        let note = try XCTUnwrap(document)
        let database = try await engine.dbForContainer(library)
        let noteChunks = try await database.allChunks()
        let real = try XCTUnwrap(
            noteChunks.first { $0.documentId == note.id && !$0.metadata.abstractionLevel.isSummary })

        // Passages 1 to 12, 14 and 15 are from a file that is not in the library; passage 13 is the note's own.
        let filler = UUID()
        var passages: [RetrievedChunk] = []
        for position in 1...15 {
            if position == 13 {
                passages.append(
                    RetrievedChunk(chunk: real, similarityScore: 0.8, rank: position, sourceDocument: note.filename))
            } else {
                passages.append(
                    RetrievedChunk(
                        chunk: passage(
                            "Filler passage number \(position) says nothing about the key.", document: filler,
                            index: position),
                        similarityScore: 0.5, rank: position, sourceDocument: "\(Self.seedPrefix)filler.txt"))
            }
        }
        let answer = "The boathouse key sits under the third step of the old dock [S13]."
        let structured = try JSONDecoder().decode(
            StructuredAnswer.self,
            from: JSONSerialization.data(withJSONObject: [
                "refuse": false, "answer_type": "lookup", "answer": answer, "claims": [] as [Any],
                "evidence": [] as [Any], "missing": [] as [Any],
                "debug": ["top_score": 0.8, "loops": 1, "intent": "lookup"],
            ]))
        let messages = [
            ChatMessage(role: .user, content: "Five checks: where is the boathouse key?", containerId: library),
            ChatMessage(
                role: .assistant, content: answer, retrievedChunks: passages, structuredAnswer: structured,
                containerId: library),
        ]
        // A conversation of its own, saved the way the chat saves one.
        UserDefaults.standard.removeObject(forKey: RAGService.unsavedNewThreadKey(library))
        engine.activeThreadId = nil
        engine.persistChatHistory(messages, for: library)

        let saved = try XCTUnwrap(try engine.threadStore.listThreads(containerId: library).first)
        let kept = saved.messages.last?.retrievedChunks ?? []
        print(
            "[FiveChecks] seed: thread \(saved.title) saved with \(kept.count) of \(passages.count) passages; passage 13 from \(kept.count >= 13 ? kept[12].sourceDocument : "none"); note \(note.filename) in library \(library)"
        )
        XCTAssertEqual(kept.count, 13, "the saved answer keeps passages up to its highest label")
        XCTAssertEqual(kept.last?.chunk.id, real.id)
    }

    func testCleanTheSeed() async throws {
        try XCTSkipUnless(Self.wanted == "clean", "set OI_FIVE_CHECKS=clean")
        let engine = IntentSupport.engine()
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk { try await Task.sleep(for: .milliseconds(100)) }
        let library = engine.containerService.activeContainerId
        for document in engine.documents where document.filename.hasPrefix(Self.seedPrefix) {
            try await engine.removeDocument(document)
        }
        for thread in try engine.threadStore.listThreads(containerId: library)
        where thread.title.hasPrefix("Five checks") {
            try engine.threadStore.deleteThread(id: thread.id, containerId: library)
        }
        let left = engine.documents.filter { $0.filename.hasPrefix(Self.seedPrefix) }.count
        print("[FiveChecks] clean: \(left) seeded documents left")
        XCTAssertEqual(left, 0)
    }

    // MARK: - "Summarize my lease"

    private static let lease = """
        # Residential Lease Agreement: Juniper Flats, Unit 4B

        ## Parties and Premises

        This lease is made between Marlow Property Group (the Landlord) and Dana Whitfield (the Tenant) for the apartment at 418 Juniper Street, Unit 4B. The premises include one assigned parking space, number 27, and one storage locker in the basement.

        ## Term

        The lease runs for twelve months, from March 1, 2026 to February 28, 2027. After that it continues month to month unless either party gives 60 days' written notice.

        ## Rent and Late Charges

        Rent is $1,850 a month, due on the first day of each month. Rent received after the fifth day of the month carries a late charge of $75. A returned payment carries a charge of $35.

        ## Security Deposit and Pet Deposit

        The Tenant has paid a security deposit of $1,850, returned within 30 days of move-out less any lawful deductions. One cat or one dog under 40 pounds is allowed with a pet deposit of $300.

        ## Utilities

        The Landlord pays for water, sewer and trash collection. The Tenant pays for electricity, gas and internet service.

        ## Maintenance and Repairs

        The Tenant reports any leak or burst pipe to the Landlord's emergency line at once. The Landlord repairs heating, plumbing and appliances supplied with the unit within a reasonable time. The Tenant replaces light bulbs and smoke detector batteries.

        ## Ending the Lease Early

        The Tenant may end the lease early by giving 60 days' written notice and paying an early termination fee equal to two months' rent.
        """

    private static let flights = """
        # Spring Trip Itinerary: Lisbon

        ## Flights

        | Flight | From | To | Departs | Arrives | Seat |
        |---|---|---|---|---|---|
        | TP 204 | Newark (EWR) | Lisbon (LIS) | April 9, 18:40 | April 10, 06:25 | 23A |
        | TP 1946 | Lisbon (LIS) | Porto (OPO) | April 13, 09:15 | April 13, 10:10 | 11C |
        | TP 209 | Lisbon (LIS) | Newark (EWR) | April 17, 11:05 | April 17, 14:20 | 24F |

        ## Summary

        A nine-day trip to Portugal with three flights. The confirmation code is QX7LMP. Checked baggage allowance is one bag of 23 kilograms on each flight.

        ## Hotels

        Four nights at Casa do Bairro in Lisbon and three nights at the Ribeira Guesthouse in Porto. Breakfast is included at both.
        """

    private static let fryer = """
        # Kestrel AF-620 Air Fryer Manual

        ## Summary

        The Kestrel AF-620 is a 5.8 litre air fryer with eight presets. This manual covers first use, cooking times, cleaning and error codes.

        ## Cooking Times

        | Food | Temperature | Time |
        |---|---|---|
        | Frozen fries | 200 C | 18 minutes |
        | Chicken wings | 190 C | 24 minutes |
        | Salmon fillet | 180 C | 10 minutes |

        ## Error Codes

        E1 means the temperature sensor circuit is open. E2 means the sensor has a short circuit. Unplug the fryer and contact support for either code.

        ## Cleaning

        Wash the basket and the crisper plate in warm soapy water after each use. Wipe the heating element with a damp cloth once it has cooled.
        """

    private static let plan = """
        # Workplace Retirement Plan Summary

        ## Summary

        Employees may contribute to the 401(k) plan from their first day. The company matches 100 percent of the first 4 percent of pay contributed.

        ## Vesting

        Company contributions vest over four years: 25 percent after each full year of service.

        ## Loans

        A participant may borrow up to half of the vested balance, to a limit of $50,000, repaid through payroll over at most five years.
        """

    func testSummarizeMyLeaseCitesOnlyTheLease() async throws {
        try XCTSkipUnless(Self.wanted == "lease", "set OI_FIVE_CHECKS=lease")
        let model = AppleFoundationLLMService()
        for _ in 0..<60 where !model.isAvailable { try await Task.sleep(for: .seconds(5)) }
        XCTAssertTrue(model.isAvailable, "Apple's model is off here: run a copy patched by scripts/sim_model_copy.py")

        let plan = UserDefaults(suiteName: "FiveChecks.plan") ?? .standard
        plan.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
        let libraries = IntentSupport.libraries()
        let engine = RAGService(
            llmService: model, containerService: libraries,
            entitlementStore: EntitlementStore(billingService: StoreKitBillingService(), defaults: plan))
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk { try await Task.sleep(for: .milliseconds(100)) }
        holdPro()
        let library = try libraries.createContainer(name: "Five checks lease \(UUID().uuidString.prefix(6))")
        addTeardownBlock { @MainActor in
            for document in engine.documents where document.containerId == library.id {
                try? await engine.removeDocument(document)
            }
            libraries.deleteContainer(id: library.id)
        }

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "five-checks-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let leaseName = "Juniper Flats Lease - Unit 4B.md"
        let files = [
            (leaseName, Self.lease), ("Lisbon Trip Itinerary.md", Self.flights),
            ("Kestrel AF-620 Air Fryer Manual.md", Self.fryer), ("Retirement Plan Summary.md", Self.plan),
        ]
        var urls: [URL] = []
        for (name, text) in files {
            let url = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: url)
            urls.append(url)
        }
        // The other documents first, so the lease is not the first thing in the store.
        let result = await engine.ingestDocuments(Array(urls.dropFirst()) + [urls[0]], containerId: library.id)
        XCTAssertEqual(result.successCount, 4, "the four documents were imported")

        let inLibrary = engine.documents.filter { $0.containerId == library.id }
        let lease = try XCTUnwrap(inLibrary.first { $0.filename.hasPrefix("Juniper Flats Lease") })
        let database = try await engine.dbForContainer(library.id)
        let stored = try await database.allChunks()
        for document in inLibrary {
            let own = stored.filter { $0.documentId == document.id }
            let summaries = own.filter { $0.metadata.abstractionLevel.isSummary }.count
            let nonZero = own.filter { chunk in chunk.embedding.contains { $0 != 0 } }.count
            print(
                "[FiveChecks] lease library: \(document.filename) passages=\(own.count) summary passages=\(summaries) with a non-zero vector=\(nonZero)"
            )
        }

        let runs = Int(ProcessInfo.processInfo.environment["OI_FIVE_CHECKS_RUNS"] ?? "") ?? 3
        var problems: [String] = []
        for run in 1...runs {
            let response = try await engine.query(
                "Summarize my lease", topK: 5, containerId: library.id, qualityModeOverride: .standard)
            let context = response.retrievedChunks
            let contextLine = context.enumerated().map { index, chunk in
                "S\(index + 1)=\(chunk.sourceDocument)\(chunk.chunk.metadata.abstractionLevel.isSummary ? " (summary)" : "")"
            }.joined(separator: "; ")
            let cited = AnswerShareFormatter.sources(
                answer: response.generatedResponse, evidence: response.structuredAnswer?.evidence ?? [],
                retrievedChunks: context)
            let citedLine = cited.map { "\($0.label ?? "no label") \($0.document)" }.joined(separator: "; ")
            print(
                "[FiveChecks] lease run \(run): mode=\(response.metadata.qualityModeName ?? "?") model=\(response.metadata.modelUsed) gating=\(response.metadata.gatingDecision ?? "none")"
            )
            print("[FiveChecks] lease run \(run): context: \(contextLine)")
            print("[FiveChecks] lease run \(run): cited: \(citedLine)")
            print(
                "[FiveChecks] lease run \(run): answer: \(response.generatedResponse.replacingOccurrences(of: "\n", with: " ⏎ "))"
            )
            XCTAssertFalse(context.isEmpty, "run \(run): the answer had no passages")
            XCTAssertFalse(cited.isEmpty, "run \(run): the answer lists no source")
            let foreignCited = cited.filter { !$0.document.hasPrefix("Juniper Flats Lease") }
            if !foreignCited.isEmpty { problems.append("run \(run) cites \(foreignCited.map(\.document))") }
            let foreignContext = context.filter { $0.chunk.documentId != lease.id }
            print(
                "[FiveChecks] lease run \(run): passages from other documents in the context: \(foreignContext.count) of \(context.count); first passage from \(context.first?.sourceDocument ?? "none")"
            )
            XCTAssertEqual(
                context.first?.chunk.documentId, lease.id, "run \(run): the first passage is not the lease's")
        }
        XCTAssertTrue(problems.isEmpty, "cited passages from other documents: \(problems)")
    }
}
