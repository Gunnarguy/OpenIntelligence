//
//  AnswerModelPriority.swift
//  OpenIntelligence
//
//  The on-device model answers one request at a time, so a question waits behind every other job that
//  asks it something. On the owner's iPhone on 2026-11-04 a five-minute Deep Think answer shared the model
//  with 6 suggested-question requests and 5 document summaries, and each of its calls waited 3.7 to 13.3 s
//  before its first word (13 s of a 19.7 s call was the wait). While an answer runs, those side jobs wait
//  for it to finish (5.8). The answer itself runs the same steps with the same prompts.
//

import Foundation

enum AnswerModelPriority {
    /// True inside an answer (`RAGService.query`), and in the tasks it starts: a side job called from the
    /// answer itself runs at once, so the answer never waits on something that waits on it.
    @TaskLocal static var isAnswerPath = false

    @MainActor private static var answersRunning = 0

    @MainActor static func answerStarted() { answersRunning += 1 }
    @MainActor static func answerEnded() { answersRunning = max(0, answersRunning - 1) }
    @MainActor static var isAnswerRunning: Bool { answersRunning > 0 }

    /// Waits, before a side job's model call, until no answer is running. Returns how long it waited.
    @discardableResult
    static func waitWhileAnswering(job: String) async -> TimeInterval {
        guard !isAnswerPath else { return 0 }
        let started = Date()
        while await isAnswerRunning, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
        }
        let waited = Date().timeIntervalSince(started)
        if waited >= 0.5 {
            VerificationJournal.record("model.sideJobWaited", ["job": job, "seconds": String(format: "%.1f", waited)])
        }
        return waited
    }
}
