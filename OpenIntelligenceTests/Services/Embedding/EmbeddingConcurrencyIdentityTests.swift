//
//  EmbeddingConcurrencyIdentityTests.swift
//  OpenIntelligenceTests
//
//  Since 2026-11-04 the Core ML embedder runs off the main thread (`nonisolated`, `@concurrent` embed), so a batch
//  embeds several passages at once on different threads. Before, tokenizing and pooling ran on the main actor one at
//  a time. Moving work between threads must change no number: a passage embedded inside a concurrent batch has to
//  give exactly the vector it gives alone, bit for bit. 240 of 240 matched in the Simulator on 2026-11-04
//  (BenchmarkRuns/2026-11-04-speed-research/embedding-off-main); this pins it.
//

import XCTest

@testable import OpenIntelligence

final class EmbeddingConcurrencyIdentityTests: XCTestCase {
    private static func passages() -> [String] {
        let subjects = [
            "The security deposit", "Quiet hours", "The lease", "Parking", "Rent", "The landlord",
            "A late fee", "The pet policy", "Utilities", "The move-out inspection", "Subletting", "Repairs",
        ]
        let predicates = [
            "is two months of rent.", "run from 10 p.m. to 7 a.m. on weekdays.",
            "ends on the last day of August unless renewed in writing.",
            "must be requested at least 30 days in advance.",
            "is due on the first and late after the fifth.",
        ]
        var result: [String] = []
        for round in 1...3 {
            for s in subjects {
                for p in predicates { result.append("\(s) \(p) (section \(round))") }
            }
        }
        // 180 passages: more than `DeviceCapabilityService.embeddingConcurrency` on every device, including
        // Macs where it scales with memory up to 128, so the group's refill path runs too.
        return result
    }

    func testConcurrentBatchMatchesOneAtATimeBitForBit() async throws {
        let provider = CoreMLSentenceEmbeddingProvider()
        let texts = Self.passages()

        var alone: [[Float]] = []
        for text in texts { alone.append(try await provider.embed(text: text)) }
        try XCTSkipIf(alone[0].allSatisfy { $0 == 0 }, "The embedding model returned zeros here.")

        let batched = try await provider.embedBatch(texts: texts)

        XCTAssertEqual(batched.count, texts.count)
        var maxAbsDiff: Float = 0
        for (a, b) in zip(alone, batched) {
            XCTAssertEqual(a.count, b.count)
            for (x, y) in zip(a, b) { maxAbsDiff = max(maxAbsDiff, abs(x - y)) }
        }
        XCTAssertEqual(maxAbsDiff, 0, "A passage embedded in a concurrent batch differed from the same passage alone")
    }

    func testConcurrentCallersShareOneProviderSafely() async throws {
        // The shared provider (`EmbeddingService.sharedCoreMLProvider`) is used by every search at once.
        let provider = CoreMLSentenceEmbeddingProvider()
        let text = "The pet policy allows one cat."
        let reference = try await provider.embed(text: text)
        try XCTSkipIf(reference.allSatisfy { $0 == 0 }, "The embedding model returned zeros here.")

        let results = try await withThrowingTaskGroup(of: [Float].self) { group in
            for _ in 0..<16 { group.addTask { try await provider.embed(text: text) } }
            var all: [[Float]] = []
            for try await vector in group { all.append(vector) }
            return all
        }
        XCTAssertEqual(results.count, 16)
        for vector in results { XCTAssertEqual(vector, reference) }
    }

    func testColdProviderUnderSixteenConcurrentFirstCallers() async throws {
        // No warm-up: sixteen first calls race the lazy model load that `modelLock` serializes.
        let provider = CoreMLSentenceEmbeddingProvider()
        let text = "Repairs are requested in writing."
        let results = try await withThrowingTaskGroup(of: [Float].self) { group in
            for _ in 0..<16 { group.addTask { try await provider.embed(text: text) } }
            var all: [[Float]] = []
            for try await vector in group { all.append(vector) }
            return all
        }
        try XCTSkipIf(results[0].allSatisfy { $0 == 0 }, "The embedding model returned zeros here.")
        XCTAssertEqual(results.count, 16)
        for vector in results { XCTAssertEqual(vector, results[0]) }
    }

    func testIngestionModeTogglesWhileABatchRuns() async throws {
        // How the shared provider is used: an import switches ingestion mode while a search is embedding.
        let provider = CoreMLSentenceEmbeddingProvider()
        let texts = Self.passages()
        let reference = try await provider.embedBatch(texts: texts)
        try XCTSkipIf(reference[0].allSatisfy { $0 == 0 }, "The embedding model returned zeros here.")

        async let batched = provider.embedBatch(texts: texts)
        for _ in 0..<4 {
            provider.enableIngestionMode()
            try await Task.sleep(nanoseconds: 20_000_000)
            provider.disableIngestionMode()
        }
        let result = try await batched

        XCTAssertEqual(result.count, texts.count)
        // Compute units can change mid-batch, so hold these to the cosine `IngestionModeSwitchTests` pins.
        for (a, b) in zip(reference, result) {
            var dot: Float = 0
            for (x, y) in zip(a, b) { dot += x * y }
            XCTAssertGreaterThan(dot, 0.99)
        }
    }
}
