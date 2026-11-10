//
//  QueryLiveActivityService.swift
//  OpenIntelligence
//

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
    @preconcurrency import ActivityKit
    import Foundation
    import UIKit

    /// A Live Activity for an answer that takes a while: Deep Think and Maximum, or a long Standard
    /// answer (5.7). `QueryLiveActivityAttributes` was declared before 5.7 and never started.
    ///
    /// It starts when a question is still running `startDelay` after it began, so a quick answer
    /// never puts anything on the Lock Screen; that is how it is limited to long answers without
    /// the question's mode, which the begin call does not carry. ActivityKit starts a Live
    /// Activity only for an app in front (`ActivityAuthorizationError.visibility`), so it also
    /// starts the moment the app is about to leave the front with a question running: the phone
    /// locked, or another app opened, before the 10 seconds were up. It follows the same title,
    /// step and fraction the background task reports, and it ends when the answer does, showing
    /// "Answer ready" or "Stopped" for a few minutes.
    ///
    /// It never shows the question: a Live Activity can be read on a locked screen, and the begin
    /// call's subtitle is the question's first words, so it is dropped here. What it shows is the
    /// title and the step names ("Searching this library"), which name nothing of the person's.
    @available(iOS 17.0, *)
    @MainActor
    final class QueryLiveActivityService {
        static let shared = QueryLiveActivityService()

        static let startDelay: Duration = .seconds(10)
        private static let minimumUpdateInterval: TimeInterval = 1.5

        private var activity: Activity<QueryLiveActivityAttributes>?
        private var pendingStart: Task<Void, Never>?
        private var latest = QueryLiveActivityAttributes.ContentState(progress: 0, title: "", subtitle: "")
        private var lastUpdateAt: Date = .distantPast
        private var isRunning = false

        private var leavingObserver: NSObjectProtocol?

        private init() {
            // Posted on the main thread while the app is still in front, which is the last moment
            // a Live Activity can be started from it.
            leavingObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification, object: nil, queue: nil
            ) { _ in
                MainActor.assumeIsolated { QueryLiveActivityService.shared.startIfStillRunning(leaving: true) }
            }
        }

        /// Ends any answer's Live Activity still up at launch, where nothing is answering yet: one a
        /// launch left when it ended without closing it.
        /// Ends every answer's Live Activity but the one running: at launch, and from 5.7 also when the app comes back
        /// to the front, where an "Answer ready" stayed on the Lock Screen for its five minutes after the person had
        /// opened the app to read it (the owner, 2026-10-17).
        func endLeftovers() {
            // One held without an answer running is a leftover too (5.8).
            if !isRunning { activity = nil }
            let running = activity?.id
            VerificationJournal.record(
                "liveactivity.answer.endLeftovers",
                ["ended": "\(Activity<QueryLiveActivityAttributes>.activities.filter { $0.id != running }.count)",
                    "running": isRunning ? "1" : "0"])
            for leftover in Activity<QueryLiveActivityAttributes>.activities where leftover.id != running {
                Task { await leftover.end(nil, dismissalPolicy: .immediate) }
            }
        }

        func begin(title: String, subtitle _: String) {
            isRunning = true
            latest = Self.state(title: title, subtitle: "", fraction: 0)
            pendingStart?.cancel()
            pendingStart = Task { [weak self] in
                try? await Task.sleep(for: Self.startDelay)
                guard !Task.isCancelled else { return }
                self?.startIfStillRunning(leaving: false)
            }
        }

        /// While the answer waits for the app to come back (5.8): the Live Activity reads "Paused" and
        /// "Tap to resume." instead of the step, and tapping it opens the app, where the answer goes on.
        private var isPaused = false

        func setPaused(_ paused: Bool) {
            guard isRunning, paused != isPaused else { return }
            isPaused = paused
            guard let activity else { return }
            let state =
                paused
                ? QueryLiveActivityAttributes.ContentState(
                    progress: latest.progress, title: "Paused", subtitle: "Tap to resume.",
                    tintHex: LiveActivityTint.currentHex())
                : latest
            lastUpdateAt = Date()
            VerificationJournal.record("liveactivity.answer.paused", ["paused": "\(paused)"])
            // A stale date, so a paused card left by an app iOS has since closed reads as out of date.
            Task { await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(15 * 60))) }
        }

        func update(title: String, subtitle: String, fraction: Double) {
            guard isRunning else { return }
            latest = Self.state(title: title, subtitle: subtitle, fraction: fraction)
            guard !isPaused else { return }
            guard let activity, Date().timeIntervalSince(lastUpdateAt) >= Self.minimumUpdateInterval else { return }
            lastUpdateAt = Date()
            let content = ActivityContent(state: latest, staleDate: Date().addingTimeInterval(120))
            Task { await activity.update(content) }
        }

        func complete(success: Bool) {
            isRunning = false
            isPaused = false
            pendingStart?.cancel()
            pendingStart = nil
            guard let activity else {
                VerificationJournal.record("liveactivity.answer.end", ["shown": "0", "success": "\(success)"])
                return
            }
            self.activity = nil
            VerificationJournal.record(
                "liveactivity.answer.end",
                ["shown": "1", "success": "\(success)", "session": VerificationJournal.anon(activity.attributes.sessionID)])
            let final = QueryLiveActivityAttributes.ContentState(
                progress: success ? 1 : latest.progress,
                title: success ? "Answer ready" : "Stopped",
                subtitle: success ? "Open OpenIntelligence to read it." : "The answer did not finish.",
                finished: true, tintHex: LiveActivityTint.currentHex())
            Task {
                await activity.end(
                    ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(.now + 300))
            }
        }

        /// Whether an answer is running, so search setup's Live Activity stands aside for it (5.8).
        var isAnswerRunning: Bool { isRunning }

        /// Whether `sessionID` names the Live Activity of the answer still running. The Stop button
        /// (`StopLongAnswerIntent`) stops the chat only then, so a Stop tapped on an ended answer's
        /// Live Activity, which stays up a few minutes, cannot stop a newer answer.
        func isRunningActivity(sessionID: String) -> Bool {
            VerificationJournal.record(
                "liveactivity.answer.stopTapped",
                ["matchesRunning": "\(isRunning && activity?.attributes.sessionID.uuidString == sessionID)"])
            guard isRunning, let activity else { return false }
            return activity.attributes.sessionID.uuidString == sessionID
        }

        /// `leaving`: called as the app leaves the front, when the request has to be made now. At
        /// the 10 seconds it is made only while the app is in front, where it can succeed.
        private func startIfStillRunning(leaving: Bool) {
            guard isRunning, activity == nil else { return }
            guard leaving || UIApplication.shared.applicationState == .active else { return }
            guard ActivityAuthorizationInfo().areActivitiesEnabled,
                !ProcessInfo.processInfo.isiOSAppOnMac
            else { return }
            pendingStart?.cancel()
            pendingStart = nil
            // One at a time: an answer left from a session the app did not end closes first.
            for leftover in Activity<QueryLiveActivityAttributes>.activities {
                Task { await leftover.end(nil, dismissalPolicy: .immediate) }
            }
            do {
                activity = try Activity.request(
                    attributes: QueryLiveActivityAttributes(sessionID: UUID()),
                    content: ActivityContent(state: latest, staleDate: Date().addingTimeInterval(120)),
                    pushType: nil)
                lastUpdateAt = Date()
                VerificationJournal.record(
                    "liveactivity.answer.start", .ok,
                    ["trigger": leaving ? "leavingFront" : "after10s",
                        "session": VerificationJournal.anon(activity?.attributes.sessionID)])
                Log.info(
                    "[QueryLiveActivity] Started for an answer still running \(leaving ? "as the app left the front" : "after 10 s")",
                    category: .ui)
            } catch {
                Log.warning("[QueryLiveActivity] Could not start: \(error.localizedDescription)", category: .ui)
                VerificationJournal.record(
                    "liveactivity.answer.start", .failed, ["error": String(describing: type(of: error))])
            }
        }

        /// The state the Live Activity shows: the title and step cut to fit, the fraction kept
        /// between 0 and 1. A Live Activity's data is limited to 4 KB.
        static func state(
            title: String, subtitle: String, fraction: Double
        ) -> QueryLiveActivityAttributes.ContentState {
            func cut(_ text: String, _ limit: Int) -> String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.count > limit ? String(trimmed.prefix(limit - 1)) + "…" : trimmed
            }
            let shownTitle = cut(title, 60)
            return QueryLiveActivityAttributes.ContentState(
                progress: fraction.isFinite ? min(max(fraction, 0), 1) : 0,
                title: shownTitle.isEmpty ? "Answering your question" : shownTitle,
                subtitle: cut(subtitle, 120), tintHex: LiveActivityTint.currentHex())
        }
    }

    /// The reranker's first setup after an update, in the Dynamic Island and on the Lock Screen (5.8), on the answer's
    /// Live Activity with `isSetup`. Asked for by the owner on 2026-11-10 after leaving the app during setup showed
    /// nothing.
    ///
    /// ActivityKit starts one only for an app in front, so it starts as the app is about to leave the front while setup
    /// runs; in the app the "Setting up search" card says the same, so it ends when the app comes back. The bar is the
    /// card's estimate (`RerankerSetupStatus.estimatedProgress`), updated every 3 s while the app has background time.
    /// When iOS takes that time back it reads "Paused", "Open OpenIntelligence to finish." (the app is suspended and
    /// setup goes on when it is opened); when setup ends it reads "Search is ready" for a minute. An answer's Live
    /// Activity takes precedence: a question asked during setup waits for it inside its own.
    @available(iOS 17.0, *)
    @MainActor
    final class SearchSetupLiveActivity {
        static let shared = SearchSetupLiveActivity()

        private static let title = "Setting up search"
        private static let subtitle = "Once after an update, about a minute."
        private static let updateInterval: Duration = .seconds(3)

        private var activity: Activity<QueryLiveActivityAttributes>?
        private var ticker: Task<Void, Never>?
        private var isPaused = false
        private var observers: [NSObjectProtocol] = []

        private init() {
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { _ in
                    MainActor.assumeIsolated { SearchSetupLiveActivity.shared.startIfPreparing() }
                })
            observers.append(
                center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
                    MainActor.assumeIsolated { SearchSetupLiveActivity.shared.endNow() }
                })
        }

        /// Called when setup starts showing, so the observers above are in place before the app can leave the front.
        func watch() {}

        private func state(progress: Double? = nil, title: String = SearchSetupLiveActivity.title,
            subtitle: String = SearchSetupLiveActivity.subtitle, finished: Bool? = nil
        ) -> QueryLiveActivityAttributes.ContentState {
            let estimate = RerankerSetupStatus.estimatedProgress(
                startedAt: RerankerSetupStatus.shared.startedAt, now: Date())
            return QueryLiveActivityAttributes.ContentState(
                progress: progress ?? estimate, title: title, subtitle: subtitle, finished: finished, isSetup: true,
                tintHex: LiveActivityTint.currentHex())
        }

        private func startIfPreparing() {
            guard RerankerSetupStatus.shared.isPreparing, activity == nil,
                !QueryLiveActivityService.shared.isAnswerRunning,
                ActivityAuthorizationInfo().areActivitiesEnabled,
                !ProcessInfo.processInfo.isiOSAppOnMac
            else { return }
            isPaused = false
            do {
                activity = try Activity.request(
                    attributes: QueryLiveActivityAttributes(sessionID: UUID()),
                    content: ActivityContent(state: state(), staleDate: Date().addingTimeInterval(120)),
                    pushType: nil)
                VerificationJournal.record("liveactivity.setup.start", .ok)
                ticker?.cancel()
                ticker = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: Self.updateInterval)
                        guard let self, let activity = self.activity, !self.isPaused else { return }
                        await activity.update(
                            ActivityContent(state: self.state(), staleDate: Date().addingTimeInterval(120)))
                    }
                }
            } catch {
                VerificationJournal.record(
                    "liveactivity.setup.start", .failed, ["error": String(describing: type(of: error))])
            }
        }

        /// iOS took the background time back: setup is suspended with the app until it is opened.
        func paused() {
            guard let activity, !isPaused else { return }
            isPaused = true
            ticker?.cancel()
            let content = ActivityContent(
                state: state(title: "Paused", subtitle: "Open OpenIntelligence to finish."),
                staleDate: Date().addingTimeInterval(15 * 60))
            VerificationJournal.record("liveactivity.setup.paused")
            Task { await activity.update(content) }
        }

        /// Setup ended. In the background the Live Activity reads "Search is ready" for a minute; in front it is
        /// already gone.
        func finished() {
            ticker?.cancel()
            guard let activity else { return }
            self.activity = nil
            let content = ActivityContent(
                state: state(progress: 1, title: "Search is ready", subtitle: "Questions are answered at full speed.",
                    finished: true),
                staleDate: nil)
            VerificationJournal.record("liveactivity.setup.end", .ok)
            Task { await activity.end(content, dismissalPolicy: .after(.now + 60)) }
        }

        /// The app is in front again, where the card shows setup: end every setup Live Activity at once.
        private func endNow() {
            ticker?.cancel()
            activity = nil
            isPaused = false
            for leftover in Activity<QueryLiveActivityAttributes>.activities where leftover.content.state.isSetup == true {
                Task { await leftover.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }
#endif
