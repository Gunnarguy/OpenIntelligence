//
//  LibraryAnalysisScaleBenchmarkTests.swift
//  OpenIntelligenceTests
//
//  Times the library analysis (`LibraryIntelligenceCenter.analyzeLibrary`) at the size of a very
//  large library, on the store files `VectorStoreScaleBenchmarkTests` leaves behind. The analysis
//  runs when the app opens a library and after every import. It is skipped unless asked for:
//
//      TEST_RUNNER_OI_ANALYSIS_BENCH=144247 TEST_RUNNER_OI_STORE_BENCH_DIR=/private/tmp/oi-store-bench \
//        xcodebuild test-without-building ... -only-testing:OpenIntelligenceTests/LibraryAnalysisScaleBenchmarkTests
//
//  Every figure is printed on a line that starts "[AnalysisBench]".
//

import XCTest

@testable import OpenIntelligenceEngine

/// The largest memory footprint seen while something runs, read every 20 ms on its own thread.
nonisolated private final class FootprintWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var peak = 0.0
    private var running = true

    static func now() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    init() {
        let thread = Thread { [self] in
            while true {
                let value = Self.now()
                lock.lock()
                let goOn = running
                if value > peak { peak = value }
                lock.unlock()
                if !goOn { break }
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
        thread.start()
    }

    func stop() -> Double {
        lock.lock()
        running = false
        let value = peak
        lock.unlock()
        return value
    }
}

@MainActor
final class LibraryAnalysisScaleBenchmarkTests: XCTestCase {
    private func report(_ name: String, _ value: String) {
        print("[AnalysisBench] \(name)=\(value)")
    }

    private func seconds(_ duration: Duration) -> String {
        String(format: "%.2f", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
    }

    func testTheLibraryAnalysisAtScale() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let total = environment["OI_ANALYSIS_BENCH"].flatMap(Int.init), total > 0 else {
            throw XCTSkip("Set TEST_RUNNER_OI_ANALYSIS_BENCH to the passage count of an existing benchmark store.")
        }
        let root = URL(fileURLWithPath: environment["OI_STORE_BENCH_DIR"] ?? NSTemporaryDirectory())
        let storageURL = root.appendingPathComponent("store-\(total)/vector_database_bench.json")
        let store = BNNSVectorDatabase(dimension: 384, storageURL: storageURL)
        let count = try await store.count()
        try XCTSkipIf(count == 0, "No benchmark store at \(storageURL.path); run VectorStoreScaleBenchmarkTests first.")
        report("passages", "\(count)")
        let clock = ContinuousClock()

        var chunks: [DocumentChunk] = []
        let read = try await clock.measure { chunks = try await store.readableChunks() }
        report("read_every_passage_s", seconds(read))
        report("characters_of_text_mb", String(format: "%.1f", Double(chunks.reduce(0) { $0 + $1.content.utf8.count }) / 1_048_576))
        report("footprint_before_mb", String(format: "%.0f", FootprintWatch.now()))

        // The first question after a launch builds a vocabulary from the library's passages
        // (it reads a sample of a large library).
        var vocabularyTerms = 0
        let vocabulary = clock.measure { vocabularyTerms = CorpusVocabulary.build(from: chunks).keywords.count }
        report("vocabulary_build_s", seconds(vocabulary))
        report("vocabulary_terms", "\(vocabularyTerms)")

        // What the app does from 5.7: a second store (so nothing is decoded yet), the sample
        // picked from its records, those passages read by id, and the analysis of them.
        let fresh = BNNSVectorDatabase(dimension: 384, storageURL: storageURL)
        var sampledReport: LibraryIntelligenceCenter.IntelligenceReport?
        let sampledWatch = FootprintWatch()
        let sampledBefore = FootprintWatch.now()
        let sampled = try await clock.measure {
            let records = try await fresh.passageRecords()
            guard
                let picked = LibraryIntelligenceCenter.samplePositions(
                    records: records, newCount: 0, limit: LibraryIntelligenceCenter.analysisPassageLimit)
            else { return }
            let read = try await fresh.chunks(withIDs: picked.existing.map { records[$0].id })
            var byDocument: [UUID: Int] = [:]
            for record in records { byDocument[record.documentId, default: 0] += 1 }
            sampledReport = await LibraryIntelligenceCenter().analyzeLibrary(
                documents: [], chunks: read,
                library: LibraryIntelligenceCenter.LibrarySize(passages: records.count, passagesByDocument: byDocument))
        }
        let sampledPeak = sampledWatch.stop()
        report("sampled_analysis_s", seconds(sampled))
        report("sampled_analysis_added_peak_mb", String(format: "%.0f", sampledPeak - sampledBefore))
        if let sampledReport {
            report("sampled_analysed_passages", "\(sampledReport.corpus.analysedChunkCount) of \(sampledReport.corpus.chunkCount)")
            report("sampled_vocabulary_richness", String(format: "%.4f", sampledReport.corpus.vocabularyRichness))
            report("sampled_technical_density", String(format: "%.4f", sampledReport.corpus.technicalDensity))
            report("sampled_semantic_complexity", String(format: "%.4f", sampledReport.corpus.semanticComplexity))
            report("sampled_avg_words_per_chunk", String(format: "%.1f", sampledReport.corpus.avgWordsPerChunk))
            report(
                "sampled_embedding_plan",
                "\(sampledReport.embedding.providerId) \(sampledReport.embedding.dimension) confidence \(String(format: "%.2f", sampledReport.embedding.confidence))")
        }

        let limit = environment["OI_ANALYSIS_BENCH_LIMIT"].flatMap(Int.init) ?? chunks.count
        let analysed = Array(chunks.prefix(limit))
        report("analysed_passages", "\(analysed.count)")
        let center = LibraryIntelligenceCenter()
        let watch = FootprintWatch()
        var signals: LibraryIntelligenceCenter.CorpusSignals?
        var plan: LibraryIntelligenceCenter.EmbeddingPlan?
        let analysis = await clock.measure {
            let made = await center.analyzeLibrary(documents: [], chunks: analysed)
            signals = made.corpus
            plan = made.embedding
        }
        let peak = watch.stop()
        report("analyze_library_s", seconds(analysis))
        report("footprint_peak_mb", String(format: "%.0f", peak))
        report("footprint_after_mb", String(format: "%.0f", FootprintWatch.now()))
        if let signals, let plan {
            report("vocabulary_richness", String(format: "%.4f", signals.vocabularyRichness))
            report("technical_density", String(format: "%.4f", signals.technicalDensity))
            report("semantic_complexity", String(format: "%.4f", signals.semanticComplexity))
            report("multilingual_score", String(format: "%.4f", signals.multilingualScore))
            report("avg_words_per_chunk", String(format: "%.1f", signals.avgWordsPerChunk))
            report("has_code", "\(signals.hasCode)")
            report("has_math", "\(signals.hasMath)")
            report("embedding_plan", "\(plan.providerId) \(plan.dimension) confidence \(String(format: "%.2f", plan.confidence))")
        }
    }
}
