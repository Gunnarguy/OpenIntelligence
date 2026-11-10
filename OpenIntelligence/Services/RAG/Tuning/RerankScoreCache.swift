//
//  RerankScoreCache.swift
//  OpenIntelligence
//
//  The cross-encoder's raw score per exact input, kept on disk between benchmark runs (5.8 audit). Development builds
//  only, and only when a run names a file.
//

import CryptoKit
import Foundation

/// With `OI_RERANK_CACHE=<file>` (a test run's `TEST_RUNNER_OI_RERANK_CACHE`), `RAGEngine.rerankWithCrossEncoder`
/// reads each pair's raw logit from this file when the same token ids were scored before and writes the new ones.
/// The key is a digest of the exact token ids the model reads, so a different question, passage, prefix or truncation
/// is a different key, and a hit returns what the model returned for those ids. It exists because the Simulator runs
/// Core ML on the CPU: on 2026-11-09 one rerank of 150 pairs took about 52 s there, so a 246-question run took hours,
/// and the audit runs one per rule, every one after the reranker. A release build, or a run that names no file, reads
/// and writes nothing.
nonisolated final class RerankScoreCache: @unchecked Sendable {
    static let shared = RerankScoreCache()

    private let lock = NSLock()
    private var scores: [String: Float] = [:]
    private var unsaved = 0
    private let url: URL?
    private(set) var hits = 0
    private(set) var misses = 0

    private init() {
        #if DEBUG
            if let path = ProcessInfo.processInfo.environment["OI_RERANK_CACHE"], !path.isEmpty {
                url = URL(fileURLWithPath: path)
                if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                    let saved = try? JSONDecoder().decode([String: Float].self, from: data)
                {
                    scores = saved
                }
            } else {
                url = nil
            }
        #else
            url = nil
        #endif
    }

    var isEnabled: Bool { url != nil }

    static func key(_ ids: [Int]) -> String {
        var data = Data(capacity: ids.count * 4)
        for id in ids {
            withUnsafeBytes(of: Int32(truncatingIfNeeded: id).littleEndian) { data.append(contentsOf: $0) }
        }
        return SHA256.hash(data: data).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    func score(for key: String) -> Float? {
        guard url != nil else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if let value = scores[key] {
            hits += 1
            return value
        }
        misses += 1
        return nil
    }

    func store(_ value: Float, for key: String) {
        guard url != nil else { return }
        lock.lock()
        scores[key] = value
        unsaved += 1
        let due = unsaved >= 2_000
        lock.unlock()
        if due { save() }
    }

    func save() {
        guard let url else { return }
        lock.lock()
        let snapshot = scores
        unsaved = 0
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}
