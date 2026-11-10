//
//  DeepThinkRetrievalGoldenTests.swift
//  OpenIntelligenceTests
//
//  Records exactly what Deep Think's and Maximum's retrieval returns for a fixed library and a fixed set of
//  questions: every passage, in order, with its score's bit pattern, rank and page. It exists so a speed change to
//  that retrieval (`RAGService.executeFullRetrievalPipeline`, `AgenticOrchestrator.executeMultiQuerySearch`) can be
//  shown to change nothing: record on the code before the change, record on the code after, compare the two files.
//
//  Run only on purpose. It needs `TEST_RUNNER_OI_GOLDEN_DIR` (a folder holding `fixtures/` and `queries.json`,
//  prepared by `scripts/golden_retrieval.py prepare`) and writes `results-<TEST_RUNNER_OI_GOLDEN_LABEL>.json` there;
//  without the variable it skips. It imports the fixtures once into its own library, "Golden retrieval", in the test
//  simulator, and reuses that library on later runs so every run searches the same stored passages. Each run searches
//  everything twice and fails if the two passes differ, which is what makes a difference between two runs mean the
//  code changed rather than the search being unsteady.
//

import CryptoKit
import XCTest

@testable import OpenIntelligence

@MainActor
final class DeepThinkRetrievalGoldenTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"
    private var savedTier: Any?
    private static let libraryName = "Golden retrieval"

    override func setUp() async throws {
        savedTier = UserDefaults.standard.object(forKey: tierKey)
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.set(savedTier, forKey: tierKey)
    }

    private struct Queries: Decodable {
        struct Single: Decodable {
            let query: String
            let scope: String?
        }
        let single: [Single]
        let groups: [[String]]
    }

    /// One passage as retrieval returned it. The id is left out on purpose: a re-import gives new ids, and the
    /// document name, passage index and a hash of the text name the same passage across imports.
    private struct Hit: Codable, Equatable {
        let file: String
        let index: Int
        let text: String
        let score: UInt32
        let rank: Int
        let page: Int?
    }

    private func hits(_ chunks: [RetrievedChunk]) -> [Hit] {
        chunks.map { retrieved in
            let digest = SHA256.hash(data: Data(retrieved.chunk.content.utf8))
            return Hit(
                file: retrieved.sourceDocument,
                index: retrieved.chunk.metadata.chunkIndex,
                text: digest.prefix(6).map { String(format: "%02x", $0) }.joined(),
                score: retrieved.similarityScore.bitPattern,
                rank: retrieved.rank,
                page: retrieved.pageNumber)
        }
    }

    func testRecordDeepThinkRetrieval() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let folder = environment["OI_GOLDEN_DIR"] else {
            throw XCTSkip("Set TEST_RUNNER_OI_GOLDEN_DIR to record the golden retrieval run")
        }
        let label = environment["OI_GOLDEN_LABEL"] ?? "run"
        let dir = URL(fileURLWithPath: folder)
        let queries = try JSONDecoder().decode(
            Queries.self, from: Data(contentsOf: dir.appendingPathComponent("queries.json")))
        let fixtureDir = dir.appendingPathComponent("fixtures")
        let fixtures = try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(fixtureDir.path)")

        // The app's own engine, not a second one: the two would share the import queue, and on 2026-11-05 the app's
        // engine restored this test's 72 queued files as paused while the test's engine had imported 5, so the rest
        // arrived during the searches and the two passes disagreed.
        let engine = IntentSupport.engine()
        // The plan: the app reconciles StoreKit at launch and writes the free plan back (1 library, few documents),
        // and imports check the app's own store, so wait out the launch check and set Pro on that store, again before
        // each step that counts against a limit.
        try await Task.sleep(nanoseconds: 3_000_000_000)
        func forcePro() {
            UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
            AppServices.shared.entitlementStore.setDebugTier(.pro)
        }
        forcePro()
        let libraries = engine.containerService
        let previous = libraries.activeContainerId
        addTeardownBlock { @MainActor in libraries.setActive(previous) }
        let fixtureNames = Set(fixtures.map(\.lastPathComponent))

        func documents(in id: UUID) -> [Document] { engine.documents.filter { $0.containerId == id } }

        var library =
            try libraries.containers.first { $0.name == Self.libraryName }
            ?? libraries.createContainer(name: Self.libraryName)
        engine.discardPausedIngestionQueue()
        let queuedHere = engine.ingestionItems.contains { $0.containerId == library.id }
        if queuedHere || Set(documents(in: library.id).map(\.filename)) != fixtureNames {
            // Anything but exactly the fixtures, fully imported, is rebuilt from nothing.
            await engine.cancelAndPurgeIngestion(for: library.id)
            for document in documents(in: library.id) { try? await engine.removeDocument(document) }
            libraries.deleteContainer(id: library.id)
            forcePro()
            library = try libraries.createContainer(name: Self.libraryName)
            libraries.setActive(library.id)
            forcePro()
            let result = await engine.ingestDocuments(fixtures, containerId: library.id)
            XCTAssertEqual(result.successCount, fixtures.count, "every fixture imports")
        }
        libraries.setActive(library.id)

        // Search only a settled library: nothing queued for it and the same passage count five times running (10 s).
        // An import leaves each document's overview for later (`deferredEnrichments`), and those overviews are stored as
        // passages. On 2026-11-05 69 of them were written during the searches (40 in the first pass, 29 in the second),
        // after the passage count had looked settled, and 367 of 760 searches differed between the passes. Run that work
        // now and wait for it to finish before anything is searched.
        for _ in 0..<1800 {
            let waiting = RAGService.deferredEnrichments().contains { $0.library == library.id }
            if !waiting { break }
            engine.runDeferredEnrichmentsIfNeeded()
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        XCTAssertFalse(
            RAGService.deferredEnrichments().contains { $0.library == library.id },
            "the golden library's overviews never finished")

        let db = try await engine.dbForContainer(library.id)
        var counts: [Int] = []
        for _ in 0..<600 {
            let busy = engine.ingestionItems.contains { $0.containerId == library.id && !$0.stage.isTerminal }
            counts.append(try await db.readableChunks().count)
            if !busy, counts.count >= 5, Set(counts.suffix(5)).count == 1, counts.last! > 0 { break }
            try await Task.sleep(nanoseconds: 2_000_000_000)
        }
        let stored = try await db.readableChunks()
        XCTAssertFalse(stored.isEmpty, "the golden library holds no passages")
        let documentsByName = Dictionary(
            documents(in: library.id).map { ($0.filename, $0.id) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(Set(documentsByName.keys), fixtureNames, "the golden library holds exactly the fixtures")

        let orchestrator = AgenticOrchestrator(ragService: engine, qualityMode: .deepThink)

        func search(
            _ query: String, mode: RAGQualityMode?, topK: Int, minSimilarity: Float?, scope: Set<UUID>?
        ) async throws -> [Hit] {
            let chunks = try await RAGQueryScope.$documentIds.withValue(scope) {
                try await engine.executeFullRetrievalPipeline(
                    query: query, topK: topK, minSimilarity: minSimilarity, qualityMode: mode)
            }
            return hits(chunks)
        }

        // The on-device window sets parent expansion's budget, so everything runs under the window this simulator
        // reports and again under 4,096 (Apple's documented window) and 8,192 (a Mac on macOS 27).
        // TEST_RUNNER_OI_GOLDEN_WINDOWS=device searches under the simulator's window only, for runs that score a
        // ranking change rather than prove nothing changed (2026-11-09, the reranker swap).
        let windows: [Int?] = environment["OI_GOLDEN_WINDOWS"] == "device" ? [nil] : [nil, 4096, 8192]
        addTeardownBlock { FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = nil }

        func pass() async throws -> [String: [Hit]] {
            var out: [String: [Hit]] = [:]
            for window in windows {
                FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = window
                let w = window.map(String.init) ?? "device"
                let full = window == nil
                for (i, item) in queries.single.enumerated() {
                    if full || i < 40 {
                        out["\(w)|deepThink|15|0.05|\(i)"] = try await search(
                            item.query, mode: .deepThink, topK: 15, minSimilarity: 0.05, scope: nil)
                    }
                    if i < 40 {
                        out["\(w)|maximum|15|0.05|\(i)"] = try await search(
                            item.query, mode: .maximum, topK: 15, minSimilarity: 0.05, scope: nil)
                    }
                    if i < 20 {
                        // The precision lookup Deep Think and Maximum run first (`executeAgenticPrecisionLookupIfAvailable`).
                        out["\(w)|deepThink|24|0.03|\(i)"] = try await search(
                            item.query, mode: .deepThink, topK: 24, minSimilarity: 0.03, scope: nil)
                        out["\(w)|maximum|24|0.03|\(i)"] = try await search(
                            item.query, mode: .maximum, topK: 24, minSimilarity: 0.03, scope: nil)
                        out["\(w)|standard|20|nil|\(i)"] = try await search(
                            item.query, mode: .standard, topK: 20, minSimilarity: nil, scope: nil)
                        out["\(w)|settings|20|nil|\(i)"] = try await search(
                            item.query, mode: nil, topK: 20, minSimilarity: nil, scope: nil)
                    }
                    if full || i < 40, let name = item.scope, let id = documentsByName[name] {
                        out["\(w)|scoped|15|0.05|\(i)"] = try await search(
                            item.query, mode: .deepThink, topK: 15, minSimilarity: 0.05, scope: [id])
                    }
                }
                for (i, group) in queries.groups.enumerated() {
                    let (_, chunks) = try await orchestrator.executeMultiQuerySearch(queries: group, ragService: engine)
                    out["\(w)|multi|\(i)"] = hits(chunks)
                }
            }
            FoundationModelTokenBudget.onDeviceContextSizeOverrideForTesting = nil
            return out
        }

        let started = Date()
        let first = try await pass()
        let firstSeconds = Date().timeIntervalSince(started)
        // TEST_RUNNER_OI_GOLDEN_PASSES=1 records one pass, for runs after a baseline has shown the passes agree.
        let second = environment["OI_GOLDEN_PASSES"] == "1" ? first : try await pass()
        let secondSeconds = Date().timeIntervalSince(started) - firstSeconds

        let passagesAfter = try await db.readableChunks().count
        XCTAssertEqual(
            passagesAfter, stored.count, "the library changed during the run, so the passes are not comparable")
        let unsteady = first.keys.filter { first[$0] != second[$0] }.sorted()
        XCTAssertTrue(
            unsteady.isEmpty, "two passes in one run differ for \(unsteady.count) searches: \(unsteady.prefix(10))")

        struct Record: Encodable {
            let label: String
            let passages: Int
            let passagesAfter: Int
            let documents: Int
            let deviceWindow: Int
            let retrievalConfig: String
            let searches: Int
            let firstPassSeconds: Double
            let secondPassSeconds: Double
            let unsteady: [String]
            let results: [String: [Hit]]
        }
        let record = Record(
            label: label, passages: stored.count, passagesAfter: passagesAfter, documents: documentsByName.count,
            deviceWindow: FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true),
            retrievalConfig: String(describing: libraries.containers.first { $0.id == library.id }?.retrievalConfig),
            searches: first.count,
            firstPassSeconds: firstSeconds, secondPassSeconds: secondSeconds, unsteady: unsteady, results: first)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        try encoder.encode(record).write(to: dir.appendingPathComponent("results-\(label).json"))
    }
}
