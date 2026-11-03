//
//  ObservedChangeThrottle.swift
//  OpenIntelligence
//
//  Work an iCloud change starts runs at most once every few seconds for each key, and once more after the last change
//  (5.8). Each change the iCloud watcher reported (`WorkspaceSyncService.observedWorkspaceChangeCount`) started a sync
//  pass from `ContentView` and another from the Documents tab, and a pass's own writes into iCloud were reported back
//  as a change: on the owner's Mac and iPhone on 2026-11-03 a pass ran about once a second for as long as an import
//  did. A change that arrives while one run waits joins it, since the run reads the state as it is then.
//

import Foundation

@MainActor
enum ObservedChangeThrottle {
    static let interval: TimeInterval = 5

    private static var lastRun: [String: Date] = [:]
    private static var waiting: Set<String> = []
    private static var running: Set<String> = []
    /// Keys a change reached while their work ran: each gets one more run once it ends.
    private static var changedWhileRunning: Set<String> = []

    /// Runs `work` for `key` now if it last started `interval` ago or more, otherwise once that much time has passed.
    /// A call while a run for `key` waits does nothing more, and one while it runs schedules a single run after it, so
    /// two runs of one key never overlap.
    static func run(_ key: String, interval: TimeInterval = interval, _ work: @escaping @MainActor () async -> Void) {
        if running.contains(key) {
            changedWhileRunning.insert(key)
            return
        }
        guard !waiting.contains(key) else { return }
        let wait = max(0, interval - Date().timeIntervalSince(lastRun[key] ?? .distantPast))
        waiting.insert(key)
        Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            waiting.remove(key)
            running.insert(key)
            lastRun[key] = Date()
            await work()
            running.remove(key)
            if changedWhileRunning.remove(key) != nil {
                run(key, interval: interval, work)
            }
        }
    }
}
