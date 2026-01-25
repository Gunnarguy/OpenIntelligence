import Combine
import Foundation
import SwiftUI

@MainActor
final class OnboardingStateStore: ObservableObject {
    private enum Keys {
        static let hasImportedSamples = "onboarding.hasImportedSamples"
        static let hasAskedFirstQuery = "onboarding.hasAskedFirstQuery"
        static let hasAcknowledgedModel = "onboarding.hasAcknowledgedModel"
        static let hasCompleted = "onboarding.hasCompleted"
        static let hasDismissedPermanently = "onboarding.hasDismissedPermanently"
    }

    @Published private(set) var hasImportedSamples: Bool
    @Published private(set) var hasAskedFirstQuery: Bool
    @Published private(set) var hasAcknowledgedModelSelection: Bool
    @Published var isChecklistVisible: Bool
    @Published private(set) var hasDismissedPermanently: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasImportedSamples = defaults.bool(forKey: Keys.hasImportedSamples)
        self.hasAskedFirstQuery = defaults.bool(forKey: Keys.hasAskedFirstQuery)
        self.hasAcknowledgedModelSelection = defaults.bool(forKey: Keys.hasAcknowledgedModel)
        self.hasDismissedPermanently = defaults.bool(forKey: Keys.hasDismissedPermanently)
        let completed = defaults.bool(forKey: Keys.hasCompleted)
        self.isChecklistVisible = !completed && !defaults.bool(forKey: Keys.hasDismissedPermanently)
    }

    var hasCompletedOnboarding: Bool {
        hasImportedSamples && hasAskedFirstQuery && hasAcknowledgedModelSelection
    }

    /// Number of checklist steps the user already finished.
    var completedStepCount: Int {
        [hasImportedSamples, hasAcknowledgedModelSelection, hasAskedFirstQuery]
            .filter { $0 }
            .count
    }

    /// Total number of onboarding steps currently tracked.
    let totalStepCount: Int = 3

    /// Indicates whether any onboarding tasks remain unfinished and user hasn't dismissed permanently.
    var hasOutstandingSteps: Bool { !hasCompletedOnboarding && !hasDismissedPermanently }

    /// Permanently dismisses the onboarding checklist - won't show launcher anymore.
    func skipPermanently() {
        hasDismissedPermanently = true
        defaults.set(true, forKey: Keys.hasDismissedPermanently)
        isChecklistVisible = false
    }

    func markSamplesImported() {
        guard !hasImportedSamples else { return }
        hasImportedSamples = true
        defaults.set(true, forKey: Keys.hasImportedSamples)
        evaluateCompletion()
    }

    func markAskedFirstQuery() {
        guard !hasAskedFirstQuery else { return }
        hasAskedFirstQuery = true
        defaults.set(true, forKey: Keys.hasAskedFirstQuery)
        evaluateCompletion()
    }

    func markModelSelectionAcknowledged() {
        guard !hasAcknowledgedModelSelection else { return }
        hasAcknowledgedModelSelection = true
        defaults.set(true, forKey: Keys.hasAcknowledgedModel)
        evaluateCompletion()
    }

    func refreshChecklistVisibilityIfNeeded() {
        if !hasCompletedOnboarding {
            isChecklistVisible = true
        }
    }

    func dismissChecklist() {
        isChecklistVisible = false
    }

    /// Resets all onboarding state - useful for testing or re-onboarding
    func resetAllOnboarding() {
        hasImportedSamples = false
        hasAskedFirstQuery = false
        hasAcknowledgedModelSelection = false
        hasDismissedPermanently = false
        isChecklistVisible = true

        defaults.removeObject(forKey: Keys.hasImportedSamples)
        defaults.removeObject(forKey: Keys.hasAskedFirstQuery)
        defaults.removeObject(forKey: Keys.hasAcknowledgedModel)
        defaults.removeObject(forKey: Keys.hasCompleted)
        defaults.removeObject(forKey: Keys.hasDismissedPermanently)
    }

    private func evaluateCompletion() {
        if hasCompletedOnboarding {
            defaults.set(true, forKey: Keys.hasCompleted)
            isChecklistVisible = false
        }
    }
}
