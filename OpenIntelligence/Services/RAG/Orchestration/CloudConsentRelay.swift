//
//  CloudConsentRelay.swift
//  OpenIntelligence
//

import Combine
import Foundation

/// Carries a Private Cloud Compute consent request from an engine the chat does not show to the
/// app's root view, which shows the same consent sheet (5.7). The engine an action builds for its
/// question (`AskActionRunner`) is such an engine. Through the first 5.7 builds its request waited
/// on a continuation that only the chat's sheet resolved, and the chat shows only its own engine's
/// requests, so a question from Siri or Shortcuts asked while the app was in front waited for good.
///
/// One request at a time: a new one gives up the one before it. The first window to claim a request
/// shows it, so a second window on the Mac or iPad does not show it twice. A request that no window
/// has shown within `deadline` is given up: the engine's question goes on without Private Cloud
/// Compute, and nothing is remembered, unlike Don't Allow.
@MainActor
final class CloudConsentRelay: ObservableObject {
    static let shared = CloudConsentRelay()

    struct Request: Identifiable {
        let record: CloudTransmissionRecord
        fileprivate let resolve: @MainActor (CloudConsentDecision) async -> Void
        fileprivate let abandon: @MainActor () -> Void
        var id: UUID { record.id }
    }

    /// The request waiting for a window to show it, or being shown.
    @Published private(set) var request: Request?
    /// How long a request may wait for a window to show it.
    var deadline: Duration = .seconds(15)

    private var claimedBy: UUID?
    private var isShown = false
    private var watchdog: Task<Void, Never>?

    func post(
        _ record: CloudTransmissionRecord,
        resolve: @escaping @MainActor (CloudConsentDecision) async -> Void,
        abandon: @escaping @MainActor () -> Void
    ) {
        giveUp()
        request = Request(record: record, resolve: resolve, abandon: abandon)
        let id = record.id
        let deadline = deadline
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: deadline)
            guard !Task.isCancelled else { return }
            self?.expire(id)
        }
    }

    /// True for the first window that asks to show the request, false for any other.
    func claim(_ id: UUID, for window: UUID) -> Bool {
        guard request?.id == id else { return false }
        if let claimedBy { return claimedBy == window }
        claimedBy = window
        return true
    }

    /// The sheet is on screen: the request now waits for the person, however long that takes.
    func markShown(_ id: UUID) {
        guard request?.id == id else { return }
        isShown = true
        watchdog?.cancel()
        watchdog = nil
    }

    /// The person's choice, passed to the engine that asked.
    func decide(_ id: UUID, _ decision: CloudConsentDecision) async {
        guard let current = request, current.id == id else { return }
        clear()
        await current.resolve(decision)
    }

    /// The engine settled the request itself; the relay drops it without calling back.
    func withdraw(_ id: UUID) {
        guard request?.id == id else { return }
        clear()
    }

    private func expire(_ id: UUID) {
        guard request?.id == id, !isShown else { return }
        giveUp()
    }

    private func giveUp() {
        guard let current = request else { return }
        clear()
        current.abandon()
    }

    private func clear() {
        watchdog?.cancel()
        watchdog = nil
        request = nil
        claimedBy = nil
        isShown = false
    }
}
