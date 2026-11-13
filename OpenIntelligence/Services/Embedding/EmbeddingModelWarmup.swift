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

    static func scheduleAfterLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !SystemResourceAdvice.prefersReducedUsage else { return }
            guard await appIsInFront() else { return }
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
