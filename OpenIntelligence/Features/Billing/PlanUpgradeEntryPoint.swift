import Foundation

/// Enumerates every UI surface that can trigger the subscription paywall.
enum PlanUpgradeEntryPoint: String, CaseIterable {
    case documents
    case documentLimit
    case sampleImport
    case libraryCreation
    case quotaBanner
    case settings
    case maximumModeLimit

    /// Human-friendly description surfaced inside the paywall hero.
    var headline: String {
        switch self {
        case .documents:
            return "Unlock more knowledge capacity"
        case .documentLimit:
            return "You've reached the current document limit"
        case .sampleImport:
            return "Need room for the curated sample workspace?"
        case .libraryCreation:
            return "Create more libraries to segment your knowledge"
        case .quotaBanner:
            return "Plan ahead before you hit the limit"
        case .settings:
            return "Manage your workspace plan"
        case .maximumModeLimit:
            return "Maximum mode is capped on Free"
        }
    }

    /// Supporting copy tailored to the entry point.
    var subheadline: String {
        switch self {
        case .documents:
            return "Upgrade to keep importing PDFs, research decks, and transcripts."
        case .documentLimit:
            return "Remove a document or unlock Pro to keep growing your workspace."
        case .sampleImport:
            return "Pro unlocks enough space for the curated onboarding corpus."
        case .libraryCreation:
            return "Pro workspaces support multiple topic-specific libraries."
        case .quotaBanner:
            return "Avoid interruptions by upgrading before the limit hits 100%."
        case .settings:
            return "Review Maximum access, workspace capacity, and billing controls in one place."
        case .maximumModeLimit:
            return "Upgrade for unlimited Maximum mode, or switch to Standard or Deep Think anytime."
        }
    }

    /// Lowercase string for telemetry attributes.
    var analyticsValue: String { rawValue }
}
