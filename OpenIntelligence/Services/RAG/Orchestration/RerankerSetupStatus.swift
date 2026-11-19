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
    /// Which of the model's two forms is being prepared (1: passages up to 256 tokens, 2: up to 512), 0 before the
    /// first; and when that one began. The card names the step and counts its seconds (5.8, 2026-11-13: the bar ran
    /// to 95% on a guess and sat there, and the owner asked what it was doing).
    @Published private(set) var step = 0
    private(set) var stepStartedAt: Date?
    nonisolated static let stepCount = 2

    func setStep(_ number: Int) {
        step = number
        stepStartedAt = Date()
    }

    /// How long a load runs before the app says so. 3 s (5.8, 2026-11-10): on the owner's iPhone a load from the
    /// compiled cache took 0.46 s and 1.52 s, and a first load after an install 20.8 to 59.7 s (journal
    /// `reranker.load`, eight launches, 2026-11-09 and 10), so at 1 s a cached launch could flash the card.
    nonisolated static let showAfterSeconds: Double = 3
    /// What the card's bar estimates the first load at: the slower of the two measurements above.
    nonisolated static let expectedSeconds: Double = 50
    /// How long "Search is ready" stays.
    nonisolated static let readyShownSeconds: Double = 2.5

    /// What setup's Live Activity is told (5.8).
    enum LiveEvent { case started, finished, paused }
    /// Set at launch by the app to its setup Live Activity (`SearchSetupLiveActivity`), which lives in the app target:
    /// this type is also compiled into the engine framework, which has no Live Activities.
    var onLiveEvent: ((LiveEvent) -> Void)?

    func setPreparing(_ preparing: Bool) {
        guard isPreparing != preparing else { return }
        isPreparing = preparing
        if preparing {
            startedAt = Date().addingTimeInterval(-Self.showAfterSeconds)
            justFinished = false
            onLiveEvent?(.started)
        } else {
            onLiveEvent?(.finished)
            startedAt = nil
            step = 0
            stepStartedAt = nil
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

    /// The bar by step: each of the two forms has half the bar, filled by its own seconds against half of
    /// `expectedSeconds` and held short of its end until the step really ends. Before the first step is known, the
    /// whole-load estimate.
    nonisolated static func progress(step: Int, stepStartedAt: Date?, startedAt: Date?, now: Date) -> Double {
        guard step >= 1, let stepStartedAt else { return estimatedProgress(startedAt: startedAt, now: now) }
        let share = 1.0 / Double(stepCount)
        let within = min(0.92, max(0, now.timeIntervalSince(stepStartedAt)) / (expectedSeconds * share))
        return min(0.97, (Double(min(step, stepCount) - 1) + within) * share)
    }

    /// What the card says under its bar: the step, and how long the whole setup has run.
    nonisolated static func stepLine(step: Int, startedAt: Date?, now: Date) -> String {
        let seconds = Int(max(0, now.timeIntervalSince(startedAt ?? now)))
        let what: String
        switch step {
        case 1: what = "Step 1 of 2: compiling the model for short passages"
        case 2: what = "Step 2 of 2: compiling the model for long passages"
        default: what = "Starting"
        }
        let slow = Double(seconds) > expectedSeconds + 10 ? ", longer than usual on this device" : ""
        return "\(what) · \(seconds) s\(slow)"
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

    static func scheduleAfterLaunch() { schedule(after: delay) }

    /// On every return to the front, once per launch (5.8, 2026-11-19). A launch into the background (iOS relaunching the
    /// app after an install, a background task) skipped the warm-up, and opening the app later never started it, so the
    /// owner's first question paid the reranker's 16 to 29 s first load. Started a second after the app is in front.
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
    static func appIsInFront() -> Bool {
        #if canImport(UIKit)
            return UIApplication.shared.applicationState == .active
        #else
            return true
        #endif
    }
}

/// Whether the reranker's `.fastPrediction` form has been prepared for this build and model (5.8, 2026-11-16).
///
/// On Maximum the app loads the default form first and prepares the fast one in the background (`RAGEngine`); this
/// record lets a later launch of the same build load the fast form straight from Core ML's cache. It names the build
/// (CFBundleVersion) and the model's file name, which carries the model's fingerprint at its fixed path
/// (`RerankerModelLocation`), so an update or a new model starts from the default form again.
nonisolated enum RerankerFastForm {
    static let defaultsKey = "rerankerFastFormPrepared"

    /// The build, the installed executable's modification time and the model. The time is there because every install
    /// empties Core ML's cache while development installs share one build number (150 all through 2026-11-16), so a
    /// record keyed by build alone would load the fast form "from cache" after a reinstall and compile it in front of
    /// the person instead.
    static func stamp(for model: URL) -> String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let installed =
            Bundle.main.executableURL
            .flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .map { String(Int($0.timeIntervalSince1970)) } ?? "unknown"
        return "\(build)|\(installed)|\(model.lastPathComponent)"
    }

    static func isPrepared(for model: URL, defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: defaultsKey) == stamp(for: model)
    }

    static func markPrepared(for model: URL, defaults: UserDefaults = .standard) {
        defaults.set(stamp(for: model), forKey: defaultsKey)
    }

    static func forget(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
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
                RerankerSetupStatus.shared.onLiveEvent?(.paused)
            }
            UIApplication.shared.endBackgroundTask(identifier)
            identifier = .invalid
        }
    }
#endif
