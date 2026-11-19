//
//  EmbeddingModelWarmup.swift
//  OpenIntelligence
//

import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Prepares the embedding model a few seconds after launch, so the first import or question does not pay for it.
///
/// Through 5.7 this specialised the Core AI copy of MiniLM-L6-v2 (`AIModel.specialize`). That copy is retired in 5.8 (its
/// training data, MS MARCO, allows non-commercial research only), and the model is Granite small english r2 on Core ML,
/// which compiles its Neural Engine form on the first load and keeps it at one fixed path (`RerankerModelLocation`).
/// Embedding one short text here makes that first load happen while the person looks around. Skipped under a test
/// run, when the system asks apps to scale back, and for a launch into the background, as `RerankerWarmup` is.
nonisolated enum EmbeddingModelWarmup {
    static let delay: Duration = .seconds(4)

    static func scheduleAfterLaunch() { schedule(after: delay) }

    /// On every return to the front, once per launch (5.8, 2026-11-19), as `RerankerWarmup.scheduleOnForeground`: a
    /// launch into the background skipped the warm-up and the first question paid the model's 18 to 21 s first load.
    static func scheduleOnForeground() { schedule(after: .seconds(1)) }

    private static let startLock = NSLock()
    private nonisolated(unsafe) static var scheduled = false

    private static func schedule(after wait: Duration) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        let go = startLock.withLock { () -> Bool in
            if scheduled { return false }
            scheduled = true
            return true
        }
        guard go else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: wait)
            guard !SystemResourceAdvice.prefersReducedUsage, await appIsInFront() else {
                startLock.withLock { scheduled = false }
                return
            }
            let started = Date()
            do {
                _ = try await EmbeddingService.sharedCoreMLProvider.embed(text: "OpenIntelligence")
                Log.info(
                    "[EmbeddingWarmup] Prepared the embedding model in "
                        + "\(String(format: "%.2f", Date().timeIntervalSince(started)))s",
                    category: .embedding)
                VerificationJournal.record(
                    "embedding.warmup", .ok, durationMs: Date().timeIntervalSince(started) * 1000,
                    ["result": "prepared"])
            } catch {
                // The provider's own load reports its failure; the first embed tries again.
                Log.warning("[EmbeddingWarmup] Not prepared: \(error.localizedDescription)", category: .embedding)
                startLock.withLock { scheduled = false }
                VerificationJournal.record("embedding.warmup", .failed, ["error": String(describing: type(of: error))])
            }
        }
    }

    @MainActor
    private static func appIsInFront() -> Bool {
        #if canImport(UIKit)
            return UIApplication.shared.applicationState == .active
        #else
            return true
        #endif
    }
}
