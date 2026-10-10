//
//  EmbeddingModelWarmup.swift
//  OpenIntelligence
//

import Foundation

#if canImport(CoreAI)
    import CoreAI
#endif
#if canImport(UIKit)
    import UIKit
#endif

/// Prepares the Core AI embedding model for this device shortly after launch, when the system's
/// cache has no entry for it.
///
/// Core AI specializes a model for the device's hardware the first time it is loaded and keeps the
/// result in `AIModelCache`. Apple's article on the cache says an entry does not survive a system
/// update. `CoreAISentenceEmbeddingProvider` loads the model when it is first created, which is when
/// something first asks for the Core AI provider: normally the first import or the first question.
/// That is where the one-off preparation was paid. Here it is paid in the background a few seconds
/// after launch instead, and only when the cache is empty for this model: once after an install
/// and once after each system update.
///
/// The provider is not touched, and nothing coordinates the two: if the provider is created during
/// those few seconds both prepare the model once. It loads through a symbolic link it makes for
/// itself; on a Mac the cache was hit through a link with a different name to the same model
/// (measured 2026-10-09, not on an iPhone), so an entry made here serves the provider's load. A
/// library kept on the Core ML provider gains nothing from it. Nothing here runs on iOS 26, in the
/// simulator (its SDK has no Core AI), under a test run, while the app is in the background, or
/// when the model is missing from the bundle.
nonisolated enum EmbeddingModelWarmup {
    /// The wait after launch before anything is read: the first screen comes first.
    static let delay: Duration = .seconds(4)

    static func scheduleAfterLaunch() {
        #if canImport(CoreAI)
            guard #available(iOS 27.0, macOS 27.0, *) else { return }
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            Task.detached(priority: .utility) {
                try? await Task.sleep(for: delay)
                // The system has asked apps to scale back: the first import pays for it instead.
                guard !SystemResourceAdvice.prefersReducedUsage else { return }
                // A launch for a background task or an action is not the moment for it either.
                guard await appIsInFront() else { return }
                await prepareIfCacheIsEmpty()
            }
        #endif
    }

    #if canImport(CoreAI)
        @MainActor
        private static func appIsInFront() -> Bool {
            #if canImport(UIKit)
                return UIApplication.shared.applicationState == .active
            #else
                return true
            #endif
        }

        @available(iOS 27.0, macOS 27.0, *)
        private static func prepareIfCacheIsEmpty() async {
            guard let source = modelDirectory() else { return }

            // Core AI takes a model folder whose name ends in ".aimodel". The bundled folder's name
            // does not, so it is reached through a link, as the provider reaches it.
            let link = FileManager.default.temporaryDirectory.appendingPathComponent("EmbeddingModelWarmup.aimodel")
            try? FileManager.default.removeItem(at: link)
            do {
                try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
                if try AIModelCache.default.model(for: link, options: .default) != nil {
                    Log.debug("[EmbeddingWarmup] The embedding model is already prepared", category: .embedding)
                    return
                }
                let started = Date()
                try await AIModel.specialize(contentsOf: link)
                Log.info(
                    "[EmbeddingWarmup] Prepared the embedding model for this device in "
                        + "\(String(format: "%.2f", Date().timeIntervalSince(started)))s",
                    category: .embedding)
            } catch {
                // The provider's own load is unaffected and reports its own failure.
                Log.warning("[EmbeddingWarmup] Not prepared: \(error.localizedDescription)", category: .embedding)
            }
        }

        /// The bundled model's folder, found the way the provider finds it.
        private static func modelDirectory() -> URL? {
            if let url = OpenIntelligenceResourceBundle.url(forResource: "EmbeddingModel", withExtension: "bundle") {
                return url
            }
            return OpenIntelligenceResourceBundle.url(forResource: "main", withExtension: "mlirb")?
                .deletingLastPathComponent()
        }
    #endif
}
