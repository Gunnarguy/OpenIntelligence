//
//  RerankerSetupStatus.swift
//  OpenIntelligence
//
//  Whether the reranker is still being prepared, for the model pill's "Preparing search" and a question's live steps.
//

import Combine
import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Whether the reranker (`RAGEngine`'s cross-encoder) is still being prepared on this device.
///
/// The first load after an install has Core ML compile the 22-layer Granite model for the Neural Engine: about 50 s on
/// an M3 Pro and 45.5 s on an iPhone 16 Pro Max (journal `reranker.load`, 2026-11-09), then 0.2 to 1.5 s from Core ML's
/// cache on every later launch. A question asked in that window waits for it (`RAGEngine.rerank` awaits the load
/// rather than racing it), so without a word on screen the first answer after an install would look slow for no
/// reason. `RAGEngine` sets this only once a load has run for a second, so the cached load never flashes it.
/// `RerankerSetupCard` shows it on every tab.
@MainActor
final class RerankerSetupStatus: ObservableObject {
    static let shared = RerankerSetupStatus()

    @Published private(set) var isPreparing = false
    /// True for a few seconds after a setup the person saw finishes, for the card's "Search is ready".
    @Published private(set) var justFinished = false
    /// When the load began (a second before the card showed), for the card's estimated progress.
    private(set) var startedAt: Date?

    /// How long a load runs before the app says so. 3 s (5.8, 2026-11-10): on the owner's iPhone a load from the
    /// compiled cache took 0.46 s and 1.52 s, and a first load after an install 20.8 to 59.7 s (journal
    /// `reranker.load`, eight launches, 2026-11-09 and 10), so at 1 s a cached launch could flash the card.
    nonisolated static let showAfterSeconds: Double = 3
    /// What the card's bar estimates the first load at: the slower of the two measurements above.
    nonisolated static let expectedSeconds: Double = 50
    /// How long "Search is ready" stays.
    nonisolated static let readyShownSeconds: Double = 2.5

    func setPreparing(_ preparing: Bool) {
        guard isPreparing != preparing else { return }
        isPreparing = preparing
        if preparing {
            startedAt = Date().addingTimeInterval(-Self.showAfterSeconds)
            justFinished = false
        } else {
            startedAt = nil
            justFinished = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.readyShownSeconds))
                guard let self, !self.isPreparing else { return }
                self.justFinished = false
            }
        }
    }

    /// The bar's estimate at `now`: elapsed time against `expectedSeconds`, held below 95% until the load really ends,
    /// so it never claims to be done early. A device slower than the estimate sits near the end rather than restarting.
    nonisolated static func estimatedProgress(startedAt: Date?, now: Date) -> Double {
        guard let startedAt else { return 0 }
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        return min(0.95, elapsed / expectedSeconds)
    }
}

/// Starts the reranker's load a few seconds after launch, so the first launch after an install compiles it for the
/// Neural Engine while the person looks around, not inside their first question.
///
/// `RAGEngine.shared` is created on first use, and its initializer starts the load, so until 5.8 the load began with
/// the first search. With TinyBERT that was a fraction of a second; with the Granite model the first load after an
/// install measured 28.7 and 20.7 s for its two functions on an M3 Pro (2026-11-09), and the first question would have
/// waited on it. Later launches load from Core ML's cache in about 0.2 s, so this costs nothing then. Skipped under a
/// test run, when the system asks apps to scale back, and for a launch into the background, as `EmbeddingModelWarmup`
/// is: the first search then loads it.
nonisolated enum RerankerWarmup {
    static let delay: Duration = .seconds(4)

    static func scheduleAfterLaunch() {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay)
            guard !SystemResourceAdvice.prefersReducedUsage else { return }
            guard await appIsInFront() else { return }
            #if canImport(UIKit)
                // Leaving the app during the first load would suspend it mid-compile. Ask iOS for the background time
                // it gives any app (about 30 s, not guaranteed; the Neural Engine is allowed in the background under
                // the app's continued-processing.inference entitlement). A launch is not a person's action, so a
                // continued-processing task, the kind with system progress, cannot be started for this; a question
                // asked during setup starts one, and its wait for the reranker runs inside it.
                let backgroundTime = await RerankerSetupBackgroundTime.begin()
                await RAGEngine.shared.prepareReranker()
                await backgroundTime.end(expired: false)
            #else
                await RAGEngine.shared.prepareReranker()
            #endif
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

#if canImport(UIKit)
    /// The background time held while the reranker's first load runs (5.8). If iOS takes it back first, the journal says
    /// so (`reranker.backgroundTimeExpired`) and the load goes on when the app is opened again.
    @MainActor
    final class RerankerSetupBackgroundTime {
        private var identifier: UIBackgroundTaskIdentifier = .invalid

        static func begin() -> RerankerSetupBackgroundTime {
            let time = RerankerSetupBackgroundTime()
            time.identifier = UIApplication.shared.beginBackgroundTask(withName: "RerankerSetup") { [weak time] in
                time?.end(expired: true)
            }
            return time
        }

        func end(expired: Bool) {
            guard identifier != .invalid else { return }
            if expired {
                VerificationJournal.record("reranker.backgroundTimeExpired", .failed)
            }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif
