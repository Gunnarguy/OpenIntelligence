//
//  VectorStoreScaleBenchmarkTests.swift
//  OpenIntelligenceTests
//
//  Times the vector store at the size of a very large library. It is skipped unless asked for,
//  because it writes several hundred megabytes and takes minutes:
//
//      TEST_RUNNER_OI_STORE_BENCH=144247 TEST_RUNNER_OI_STORE_BENCH_DIR=/private/tmp/oi-store-bench \
//        xcodebuild test-without-building ... -only-testing:OpenIntelligenceTests/VectorStoreScaleBenchmarkTests
//
//  The store's files are left in that folder, so a second run times a load of files a first run
//  (or an older build) wrote. Every figure is printed on a line that starts "[StoreBench]".
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class VectorStoreScaleBenchmarkTests: XCTestCase {
    private let dimension = 384
    private let batch = 3_000

    private static let words: [String] = [
        "pump", "valve", "torque", "sterile", "cycle", "lumen", "channel", "detergent", "rinse", "filter",
        "manual", "service", "replace", "inspect", "pressure", "temperature", "minutes", "seconds", "adapter", "seal",
        "record", "field", "value", "serial", "model", "revision", "notice", "lease", "tenant", "payment",
        "invoice", "ledger", "account", "balance", "quarter", "margin", "forecast", "sample", "cluster", "vector",
    ]

    /// A passage of about 110 words with line feeds, quotes and a non-ASCII letter in it, so its
    /// JSON has escapes, as real passages do.
    private func passage(_ number: Int, documentId: UUID) -> DocumentChunk {
        var state = UInt64(truncatingIfNeeded: number) &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        func next() -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: state >> 33)
        }
        var lines: [String] = ["Record \(number + 1) of 189579"]
        for line in 0..<11 {
            let picked = (0..<10).map { _ in Self.words[next() % Self.words.count] }
            lines.append("field_\(line): \"\(picked.joined(separator: " "))\" é \(next() % 10_000)")
        }
        let content = lines.joined(separator: "\n")
        var embedding = [Float](repeating: 0, count: dimension)
        for index in 0..<dimension { embedding[index] = Float(next() % 2_000) / 1_000 - 1 }
        return DocumentChunk(
            documentId: documentId,
            content: content,
            embedding: embedding,
            metadata: ChunkMetadata(
                chunkIndex: number,
                startPosition: number * 700,
                endPosition: number * 700 + content.count,
                sectionTitle: "Records \(number / 100 * 100 + 1) to \(number / 100 * 100 + 100)",
                keywords: (0..<8).map { _ in Self.words[next() % Self.words.count] },
                hasNumericData: true,
                wordCount: 121,
                characterCount: content.count,
                structureType: "record",
                entities: ["OpenIntelligence", "Record \(number + 1)"]
            )
        )
    }

    private func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    private func fileMB(_ url: URL) -> Double {
        Double(((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int) ?? 0) / 1_048_576
    }

    private func report(_ name: String, _ value: String) {
        print("[StoreBench] \(name)=\(value)")
    }

    func testLoadSaveAndLookupAtScale() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let total = environment["OI_STORE_BENCH"].flatMap(Int.init), total >= batch else {
            throw XCTSkip("Set TEST_RUNNER_OI_STORE_BENCH to a passage count to run the scale benchmark.")
        }
        let root = URL(fileURLWithPath: environment["OI_STORE_BENCH_DIR"] ?? NSTemporaryDirectory())
        let directory = root.appendingPathComponent("store-\(total)")
        let storageURL = directory.appendingPathComponent("vector_database_bench.json")
        let metaURL = directory.appendingPathComponent("vector_database_bench_meta.json")
        let vectorsURL = directory.appendingPathComponent("vector_database_bench_vectors.bin")
        let clock = ContinuousClock()
        let bigDocument = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let smallDocument = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        report("passages", "\(total)")

        func seconds(_ duration: Duration) -> String {
            String(format: "%.3f", Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18)
        }

        // 1. The files, written the way an import in pieces writes them: a batch, then a save.
        if !FileManager.default.fileExists(atPath: metaURL.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
            var written = 0
            var lastSave = Duration.zero
            var allSaves = Duration.zero
            while written < total {
                let upper = min(written + batch, total)
                let chunks = (written..<upper).map {
                    passage($0, documentId: $0 < total - 500 ? bigDocument : smallDocument)
                }
                try await store.storeBatch(chunks: chunks)
                lastSave = try await clock.measure { try await store.persist() }
                allSaves += lastSave
                written = upper
            }
            report("build_all_saves_s", String(format: "%.2f", Double(allSaves.components.seconds) + Double(allSaves.components.attoseconds) / 1e18))
            report("build_last_save_s", String(format: "%.3f", Double(lastSave.components.seconds) + Double(lastSave.components.attoseconds) / 1e18))
        } else {
            report("build", "reused the files already in \(directory.path)")
        }
        report("meta_mb", String(format: "%.1f", fileMB(metaURL)))
        report("vectors_mb", String(format: "%.1f", fileMB(vectorsURL)))

        // The walk over the metadata file by itself, on one thread and on all of them.
        do {
            let mapped = try Data(contentsOf: metaURL, options: .alwaysMapped)
            report("processors", "\(ProcessInfo.processInfo.activeProcessorCount)")
            var walked = 0
            let one = clock.measure { walked = PassageFileIndex.scan(mapped, threads: 1)?.count ?? -1 }
            XCTAssertEqual(walked, total)
            report("walk_one_thread_s", seconds(one))
            let several = clock.measure { walked = PassageFileIndex.scan(mapped)?.count ?? -1 }
            XCTAssertEqual(walked, total)
            report("walk_all_threads_s", seconds(several))
        }

        // 2. Open the store and ask how many passages it holds: the cost of a launch.
        let before = footprintMB()
        var store: BNNSVectorDatabase! = nil
        var count = 0
        let load = try await clock.measure {
            store = BNNSVectorDatabase(dimension: dimension, storageURL: storageURL)
            count = try await store.count()
        }
        XCTAssertEqual(count, total)
        report("load_to_count_s", seconds(load))
        report("footprint_after_load_mb", String(format: "%.0f", footprintMB() - before))

        // 3. One search, and the passages it hands back.
        let query = passage(total / 2, documentId: bigDocument).embedding
        var found: [RetrievedChunk] = []
        let search = try await clock.measure { found = try await store.search(embedding: query, topK: 60) }
        XCTAssertEqual(found.first?.chunk.metadata.chunkIndex, total / 2)
        XCTAssertEqual(found.first?.chunk.content, passage(total / 2, documentId: bigDocument).content)
        report("first_search_s", seconds(search))
        let searchAgain = try await clock.measure { _ = try await store.search(embedding: query, topK: 60) }
        report("second_search_s", seconds(searchAgain))

        // 4. Every passage at once, which is what most callers asked for through 5.6.
        var everything: [DocumentChunk] = []
        let all = try await clock.measure { everything = try await store.allChunks() }
        XCTAssertEqual(everything.count, total)
        XCTAssertEqual(everything[total - 1].content, passage(total - 1, documentId: smallDocument).content)
        report("all_chunks_s", seconds(all))
        report("footprint_after_all_chunks_mb", String(format: "%.0f", footprintMB() - before))
        everything = []
        await store.releaseDecodedPassages()
        report("footprint_after_release_mb", String(format: "%.0f", footprintMB() - before))
        let again = try await clock.measure { everything = try await store.allChunks() }
        XCTAssertEqual(everything.count, total)
        report("all_chunks_again_s", seconds(again))
        report("footprint_after_all_chunks_again_mb", String(format: "%.0f", footprintMB() - before))
        everything = []

        // 5. One more batch and a save, at full size: what each piece of an import costs.
        let extra = (total..<(total + batch)).map { passage($0, documentId: smallDocument) }
        try await store.storeBatch(chunks: extra)
        let save = try await clock.measure { try await store.persist() }
        report("save_at_full_size_s", seconds(save))
        report("footprint_after_save_mb", String(format: "%.0f", footprintMB() - before))

        // 6. Take that batch out again so the files are as they were for the next run.
        let delete = try await clock.measure { try await store.deleteChunks(forDocument: smallDocument) }
        report("delete_small_document_s", seconds(delete))
        let remaining = try await store.count()
        XCTAssertEqual(remaining, total - 500)
        let restore = (total - 500..<total).map { passage($0, documentId: smallDocument) }
        try await store.storeBatch(chunks: restore)
        try await store.persist()
        let restored = try await store.count()
        XCTAssertEqual(restored, total)

        // 7. What an older build would make of the file: it decodes the whole array.
        let beforePlain = footprintMB()
        var decoded: [DocumentChunk] = []
        let plain = try clock.measure {
            let data = try Data(contentsOf: metaURL, options: .alwaysMapped)
            decoded = try JSONDecoder().decode([DocumentChunk].self, from: data)
        }
        XCTAssertEqual(decoded.count, total)
        XCTAssertEqual(decoded[total - 1].content, passage(total - 1, documentId: smallDocument).content)
        report("plain_json_decode_s", seconds(plain))
        // What the same passages cost in memory when the whole array is decoded in one go, to
        // set beside what the store's own decode of every passage cost above.
        report("plain_json_decode_footprint_mb", String(format: "%.0f", footprintMB() - beforePlain))
        report("passage_stride_bytes", "\(MemoryLayout<DocumentChunk>.stride)")
        report("slot_stride_bytes", "\(MemoryLayout<PassageSlot>.stride)")
    }
}
