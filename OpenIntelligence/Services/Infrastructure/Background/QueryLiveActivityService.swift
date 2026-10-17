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
            let running = activity?.id
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

        func update(title: String, subtitle: String, fraction: Double) {
            guard isRunning else { return }
            latest = Self.state(title: title, subtitle: subtitle, fraction: fraction)
            guard let activity, Date().timeIntervalSince(lastUpdateAt) >= Self.minimumUpdateInterval else { return }
            lastUpdateAt = Date()
            let content = ActivityContent(state: latest, staleDate: Date().addingTimeInterval(120))
            Task { await activity.update(content) }
        }

        func complete(success: Bool) {
            isRunning = false
            pendingStart?.cancel()
            pendingStart = nil
            guard let activity else { return }
            self.activity = nil
            let final = QueryLiveActivityAttributes.ContentState(
                progress: success ? 1 : latest.progress,
                title: success ? "Answer ready" : "Stopped",
                subtitle: success ? "Open OpenIntelligence to read it." : "The answer did not finish.",
                finished: true)
            Task {
                await activity.end(
                    ActivityContent(state: final, staleDate: nil), dismissalPolicy: .after(.now + 300))
            }
        }

        /// Whether `sessionID` names the Live Activity of the answer still running. The Stop button
        /// (`StopLongAnswerIntent`) stops the chat only then, so a Stop tapped on an ended answer's
        /// Live Activity, which stays up a few minutes, cannot stop a newer answer.
        func isRunningActivity(sessionID: String) -> Bool {
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
                Log.info(
                    "[QueryLiveActivity] Started for an answer still running \(leaving ? "as the app left the front" : "after 10 s")",
                    category: .ui)
            } catch {
                Log.warning("[QueryLiveActivity] Could not start: \(error.localizedDescription)", category: .ui)
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
                subtitle: cut(subtitle, 120))
        }
    }
#endif
