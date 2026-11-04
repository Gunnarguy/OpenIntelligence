//
//  SystemResourceAdvice.swift
//  OpenIntelligence
//

import Foundation
import os

/// Whether the system has asked apps to scale back heavy work, readable from any thread.
///
/// iOS 27 adds `UIApplication.systemPrefersReducedResourceUsage`. `SystemStateMonitor` reads it on the
/// main actor and copies it here, so an import loop or a reasoning chain can ask without hopping
/// there. Apple's guidance for the flag is to reduce or space out expensive work and to start none
/// because it changed, so nothing here starts work: the long loops read it at their own boundaries.
/// False on macOS, where the SDK has no such flag, and on iOS 26.
nonisolated enum SystemResourceAdvice {
    private static let storage = OSAllocatedUnfairLock(initialState: false)

    static var prefersReducedUsage: Bool { storage.withLock { $0 } }

    static func set(prefersReducedUsage value: Bool) {
        storage.withLock { $0 = value }
    }

    /// Waits `duration` when the system has asked apps to scale back, and returns at once otherwise.
    /// A cancelled task ends the wait early; the caller's own cancellation check follows.
    @discardableResult
    static func easeOff(for duration: Duration) async -> Bool {
        guard prefersReducedUsage else { return false }
        try? await Task.sleep(for: duration)
        recordPause(duration)
        return true
    }

    /// The last time each pause length was written to the development journal (5.8).
    private static let journalledPauses = OSAllocatedUnfairLock(initialState: [Int: Date]())

    /// Writes `system.easeOff` at most once a minute per pause length, so an import pausing every 16 passages writes
    /// one line, not hundreds. 120 ms is the embedding loop's pause, 1 s Deep Think's.
    private static func recordPause(_ duration: Duration) {
        guard VerificationJournal.isEnabled else { return }
        let ms = Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
        let now = Date()
        let due = journalledPauses.withLock { last -> Bool in
            if let previous = last[ms], now.timeIntervalSince(previous) < 60 { return false }
            last[ms] = now
            return true
        }
        guard due else { return }
        VerificationJournal.record(
            "system.easeOff", ["pauseMs": "\(ms)", "where": ms < 500 ? "embedding" : "deepThink"])
    }
}
