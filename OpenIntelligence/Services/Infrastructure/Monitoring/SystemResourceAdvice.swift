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
        return true
    }
}
