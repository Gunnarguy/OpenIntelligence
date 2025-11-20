import Foundation

/// Enumerates every UI surface that can trigger the subscription paywall.
enum PlanUpgradeEntryPoint: String, CaseIterable {
    case documents
    case documentLimit
    case sampleImport
    case libraryCreation
    case quotaBanner
    case settings
    case localModelGated  // Free/Starter users attempting GGUF/Core ML

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
        case .localModelGated:
            return "Unlock fully private, on-device inference"
        }
    }

    /// Supporting copy tailored to the entry point.
    var subheadline: String {
        switch self {
        case .documents:
            return "Upgrade to keep importing PDFs, research decks, and transcripts." 
        case .documentLimit:
            return "Remove a document or unlock Starter/Pro to keep growing your workspace." 
        case .sampleImport:
            return "Starter unlocks enough space for the curated onboarding corpus." 
        case .libraryCreation:
            return "Starter and Pro workspaces support multiple topic-specific libraries." 
        case .quotaBanner:
            return "Avoid interruptions by upgrading before the limit hits 100%." 
        case .settings:
            return "Review tiers, add-ons, and billing controls in one place."
        case .localModelGated:
            return "GGUF and Core ML models require Lifetime or Pro for unlimited private inference. Your data never leaves your device."
        }
    }

    /// Lowercase string for telemetry attributes.
    var analyticsValue: String { rawValue }
}
