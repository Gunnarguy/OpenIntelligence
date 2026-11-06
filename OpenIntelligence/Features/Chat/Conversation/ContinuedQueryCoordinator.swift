//
//  ContinuedQueryCoordinator.swift
//  OpenIntelligence
//
//  Moved unchanged from ChatScreen.swift on 2026-11-05 (5.8 split).
//

import AppIntents
import Combine
import Foundation
import StoreKit
import SwiftUI
import TipKit
import Translation

#if os(iOS)
    import PDFKit
    import VisionKit
#endif

@MainActor
final class ContinuedQueryCoordinator: ObservableObject {
    var expirationHandler: (() -> Void)?

    private var trackedSessionId: UUID?
    private var lastFinishedSessionId: UUID?
    private var lastFinishedSuccess: Bool?
    private var title: String = "Answering your question"
    private var queryPreview: String = ""
    private var firstTokenObserved = false
    private var stepsSinceGenerating = 0
    private var lastReportedFraction = 0.0
    private var lastSubtitle = "Preparing answer"
    /// Moves the bar a step every few seconds while the answer runs (5.8). A Deep Think answer reported
    /// progress only when a step ended, each model call ran 13 to 53 s with none, and the bar sat at 80%
    /// for minutes; on the owner's iPhone on 2026-11-04 iOS ended the task about 5 s after he left the app,
    /// twice, both times at 0.80. Apple: the system ends tasks that show minimal progress first.
    private var heartbeat: Task<Void, Never>?
    /// True while the answer waits for the app to come back (`RAGService.answerPausedNotification`): the beat
    /// stops, so the bar never shows progress the answer is not making.
    private var isPaused = false
    private var pauseObserver: NSObjectProtocol?
    /// Seconds between beats, and how far each moves the bar (one unit of the task's 1,000).
    private static let heartbeatInterval: Duration = .seconds(2)
    private static let heartbeatStep = 0.001
    /// The beat never passes the mark for checking the answer against its sources.
    private static let heartbeatCeiling = 0.915

    init() {
        pauseObserver = NotificationCenter.default.addObserver(
            forName: RAGService.answerPausedNotification, object: nil, queue: .main
        ) { [weak self] note in
            let paused = (note.userInfo?["paused"] as? Bool) ?? false
            MainActor.assumeIsolated { self?.isPaused = paused }
        }
        QueryRuntimeBridge.shared.configureContinuedQuery(
            run: { [weak self] in
                guard let self else { return false }
                return await self.awaitTrackedQueryCompletion()
            },
            expiration: { [weak self] in
                self?.expirationHandler?()
            }
        )
    }

    func begin(query: String, sessionId: UUID) {
        trackedSessionId = sessionId
        lastFinishedSessionId = nil
        lastFinishedSuccess = nil
        firstTokenObserved = false
        stepsSinceGenerating = 0
        lastReportedFraction = 0
        title = "Answering your question"
        queryPreview = Self.makeQueryPreview(from: query)

        QueryRuntimeBridge.shared.beginUserInitiatedQuery(
            title: title,
            subtitle: queryPreview
        )
        reportProgress(subtitle: "Preparing answer", fraction: 0.02)
        startHeartbeat()
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeatInterval)
                guard let self, !Task.isCancelled, self.trackedSessionId != nil else { return }
                guard !self.isPaused, self.lastReportedFraction < Self.heartbeatCeiling else { continue }
                self.reportProgress(
                    subtitle: self.lastSubtitle,
                    fraction: min(Self.heartbeatCeiling, self.lastReportedFraction + Self.heartbeatStep))
            }
        }
    }

    func markEmbedding() {
        reportProgress(subtitle: "Understanding your question", fraction: 0.12)
    }

    func markSearching() {
        reportProgress(subtitle: "Searching this library", fraction: 0.36)
    }

    func markGenerating() {
        reportProgress(subtitle: "Building the answer", fraction: 0.62)
    }

    func markFirstToken() {
        guard !firstTokenObserved else { return }
        firstTokenObserved = true
        reportProgress(subtitle: "Writing the answer", fraction: 0.82)
    }

    /// The pipeline reported a step before the answer started to arrive.
    ///
    /// Deep Think and Maximum reason through many steps before any text exists, and the bar sat at
    /// 62% for all of them. This moves it a sixth of the way toward 80% per reported step. It is not
    /// a share of known work, because the number of steps is not known in advance; it moves only
    /// when a step happens, never backwards, and stays below the mark for the first word.
    func markStep() {
        guard !firstTokenObserved else { return }
        stepsSinceGenerating += 1
        let fraction = 0.62 + (0.80 - 0.62) * (1 - pow(5.0 / 6.0, Double(stepsSinceGenerating)))
        reportProgress(subtitle: "Working through your documents", fraction: fraction)
    }

    /// The text is complete and the answer is being checked against its sources.
    func markChecking() {
        reportProgress(subtitle: "Checking the answer against its sources", fraction: 0.92)
    }

    func handleScenePhaseChange(_ phase: ScenePhase, isProcessing: Bool) {
        guard trackedSessionId != nil else {
            if phase == .active {
                QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
            }
            return
        }

        switch phase {
        case .inactive, .background:
            guard isProcessing else { return }
            QueryRuntimeBridge.shared.beginForegroundFallbackQueryExtensionIfNeeded(
                reason: "App moved to the background while answering a question."
            )
        case .active:
            QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
            // Back in front: an answer paused when its background time ran out goes on (5.8).
            if isPaused {
                NotificationCenter.default.post(
                    name: RAGService.answerPausedNotification, object: nil, userInfo: ["paused": false])
            }
        @unknown default:
            break
        }
    }

    func complete(sessionId: UUID, success: Bool) {
        guard trackedSessionId == sessionId else { return }

        lastFinishedSessionId = sessionId
        lastFinishedSuccess = success
        heartbeat?.cancel()
        heartbeat = nil
        QueryRuntimeBridge.shared.completeUserInitiatedQuery(success: success)
        trackedSessionId = nil
        firstTokenObserved = false
    }

    func cancelCurrentQuery() {
        guard let trackedSessionId else {
            QueryRuntimeBridge.shared.endForegroundFallbackQueryExtension()
            return
        }

        complete(sessionId: trackedSessionId, success: false)
    }

    private func reportProgress(subtitle: String, fraction: Double) {
        guard trackedSessionId != nil else { return }
        // A progress bar that moves backwards reads as lost work.
        let fraction = max(fraction, lastReportedFraction)
        lastReportedFraction = fraction
        lastSubtitle = subtitle

        QueryRuntimeBridge.shared.updateContinuedQueryProgress(
            title: title,
            subtitle: subtitle,
            fraction: fraction
        )
    }

    private func awaitTrackedQueryCompletion() async -> Bool {
        while !Task.isCancelled {
            if let trackedSessionId,
                trackedSessionId == lastFinishedSessionId,
                let lastFinishedSuccess
            {
                return lastFinishedSuccess
            }

            if trackedSessionId == nil {
                return lastFinishedSuccess ?? false
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        return false
    }

    private static func makeQueryPreview(from query: String) -> String {
        let collapsed =
            query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard collapsed.count > 72 else { return collapsed }
        return String(collapsed.prefix(69)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
