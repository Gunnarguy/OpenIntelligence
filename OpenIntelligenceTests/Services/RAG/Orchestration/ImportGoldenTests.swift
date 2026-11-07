//
//  ImportGoldenTests.swift
//  OpenIntelligenceTests
//
//  Records exactly what an import stores: each document record, every stored passage with its vector (bit for bit,
//  as a digest), the keyword index's rows and the library's vocabulary. It exists so breaking `RAGService.addDocument`
//  into steps (2026-11-06, `BenchmarkRuns/2026-11-06-decomposition/PLAN.md`) can be shown to change nothing: record
//  before, record after, compare with `scripts/golden_compare.py`.
//
//  Unlike `DeepThinkRetrievalGoldenTests`, which keeps one library across runs, every pass imports the fixtures into a
//  new library and deletes it afterwards, so the recording is of the import itself. Document overviews are switched off
//  (they come from a model call and are stored as passages), and so is Spotlight; both settings are restored.
//
//  Run only on purpose: it needs `TEST_RUNNER_OI_GOLDEN_DIR` with `import-fixtures/` (`scripts/golden_compare.py
//  prepare <dir>`), and skips without it.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ImportGoldenTests: XCTestCase {
    private let tierKey = "entitlement.activeTier"

    /// Keys that hold a clock time, a duration or a per-run path, so differ between two imports of the same file.
    private static let volatileKeys: Set<String> = []

    func testRecordImport() async throws {
        let (dir, label) = try GoldenRecording.destination()
        let fixtureDir = dir.appendingPathComponent("import-fixtures")
        let fixtures = try FileManager.default.contentsOfDirectory(at: fixtureDir, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(fixtures.isEmpty, "no fixtures in \(fixtureDir.path)")

        // The app's own engine, as `DeepThinkRetrievalGoldenTests` explains: a second engine would share its queue.
        let engine = IntentSupport.engine()
        try await Task.sleep(nanoseconds: 3_000_000_000)
        let savedTier = UserDefaults.standard.object(forKey: tierKey)
        func forcePro() {
            UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
            AppServices.shared.entitlementStore.setDebugTier(.pro)
        }
        forcePro()
        let settings = try XCTUnwrap(engine.settingsStore, "the engine has no settings store")
        let savedSummaries = settings.enableDocumentSummaries
        let savedSpotlight = settings.enableSpotlightIndexing
        settings.enableDocumentSummaries = false
        settings.enableSpotlightIndexing = false
        let libraries = engine.containerService
        let previous = libraries.activeContainerId
        // Services that call Apple's model directly take their no-model path (`DirectModelCallsForTesting`): in the
        // Simulator the model answers in different words each time, which changed the plan and the prompt between
        // two passes on 2026-11-06.
        DirectModelCallsForTesting.disabled = true
        addTeardownBlock { @MainActor in
            DirectModelCallsForTesting.disabled = false
            settings.enableDocumentSummaries = savedSummaries
            settings.enableSpotlightIndexing = savedSpotlight
            UserDefaults.standard.set(savedTier, forKey: self.tierKey)
            libraries.setActive(previous)
        }
        engine.discardPausedIngestionQueue()

        func pass(_ n: Int) async throws -> [String: Any] {
            let name = "Golden import \(n)"
            for stale in libraries.containers where stale.name == name {
                await engine.cancelAndPurgeIngestion(for: stale.id)
                for document in engine.documents where document.containerId == stale.id {
                    try? await engine.removeDocument(document)
                }
                libraries.deleteContainer(id: stale.id)
            }
            forcePro()
            let library = try libraries.createContainer(name: name)
            libraries.setActive(library.id)
            forcePro()
            let result = await engine.ingestDocuments(fixtures, containerId: library.id)
            XCTAssertEqual(result.successCount, fixtures.count, "every fixture imports")

            // Wait until nothing is queued for the library and its passage count holds for 10 s.
            let db = try await engine.dbForContainer(library.id)
            var counts: [Int] = []
            for _ in 0..<600 {
                let busy = engine.ingestionItems.contains { $0.containerId == library.id && !$0.stage.isTerminal }
                counts.append(try await db.readableChunks().count)
                if !busy, counts.count >= 5, Set(counts.suffix(5)).count == 1, counts.last! > 0 { break }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }

            let ids = GoldenRecording.Ids()
            let documents = engine.documents.filter { $0.containerId == library.id }
                .sorted { $0.filename < $1.filename }
            // Number the documents' ids first, in file-name order, so a passage's document id reads the same each run.
            for document in documents { _ = ids.token(document.id.uuidString.uppercased()) }
            let stored = try await db.readableChunks()
            let nameById = Dictionary(documents.map { ($0.id, $0.filename) }, uniquingKeysWith: { a, _ in a })
            let ordered = stored.sorted {
                let a = nameById[$0.documentId] ?? ""
                let b = nameById[$1.documentId] ?? ""
                return a != b ? a < b : $0.metadata.chunkIndex < $1.metadata.chunkIndex
            }

            var out: [String: Any] = [:]
            for document in documents {
                var keyword: [Any] = []
                for row in await SQLiteFullTextService.shared.retrieveChunks(for: document.id) {
                    keyword.append([
                        "index": row.chunkIndex, "page": row.pageNumber as Any, "section": row.sectionTitle as Any,
                        "path": row.sectionPath as Any, "type": row.structureType as Any,
                        "content": GoldenRecording.digest(row.content),
                    ])
                }
                let passages = try ordered.filter { $0.documentId == document.id }.map {
                    try GoldenRecording.normalized($0, dropping: Self.volatileKeys, ids: ids)
                }
                out[document.filename] = [
                    "record": try GoldenRecording.normalized(document, dropping: Self.volatileKeys, ids: ids),
                    "passages": passages,
                    "keywordRows": keyword,
                    "fullText": (await SQLiteFullTextService.shared.getFullContent(documentId: document.id))
                        .map(GoldenRecording.digest) as Any,
                ]
            }
            let vocabulary = await ContainerVocabularyService.shared.vocabulary(for: library.id)
            out["_vocabulary"] = try GoldenRecording.normalized(vocabulary, dropping: Self.volatileKeys, ids: ids)
            out["_passageCount"] = stored.count

            await engine.cancelAndPurgeIngestion(for: library.id)
            for document in documents { try? await engine.removeDocument(document) }
            libraries.deleteContainer(id: library.id)
            return out
        }

        // `TEST_RUNNER_OI_GOLDEN_PASSES=1` records one pass, for runs after a baseline has shown the two passes agree.
        let passes = Int(ProcessInfo.processInfo.environment["OI_GOLDEN_PASSES"] ?? "") ?? 2
        let first = try await pass(1)
        let second = passes > 1 ? try await pass(2) : first
        let unsteady = GoldenRecording.differences(first, second)
        XCTAssertTrue(unsteady.isEmpty, "two passes in one run differ: \(unsteady)")
        try GoldenRecording.write(
            ["label": label, "documents": fixtures.count, "unsteady": unsteady, "results": first],
            to: dir.appendingPathComponent("import-\(label).json"))
    }
}
