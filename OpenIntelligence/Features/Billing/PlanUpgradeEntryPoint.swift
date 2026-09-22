import Foundation

/// Enumerates every UI surface that can trigger the subscription paywall.
enum PlanUpgradeEntryPoint: String, CaseIterable {
    case documents
    case documentLimit
    case sampleImport
    case libraryCreation
    case iCloudSync
    case quotaBanner
    case settings
    case localModelGated // Free users attempting GGUF/Core ML
    case maximumModeLimit
    case launchSale // the in-app sale banner, shown only while LaunchSale has a real offer
    case momentOfValue // once, after the review prompt, on a verified answer
    case onboarding // once, when the setup checklist is finished; dismissible, never repeated

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
        case .iCloudSync:
            return "Unlock iCloud library sync"
        case .quotaBanner:
            return "Plan ahead before you hit the limit"
        case .settings:
            return "Manage your workspace plan"
        case .localModelGated:
            return "Unlock fully private, on-device inference"
        case .maximumModeLimit:
            return "Maximum mode is capped on Free"
        case .launchSale:
            return "Lifetime is on sale"
        case .momentOfValue:
            return "That answer came from your files"
        case .onboarding:
            return "Start free. Upgrade when your library outgrows it."
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
        case .iCloudSync:
            return "iCloud library sync is available on Pro and Lifetime so full-fidelity multi-device libraries stay on paid workspaces."
        case .quotaBanner:
            return "Avoid interruptions by upgrading before the limit hits 100%."
        case .settings:
            return "Review tiers, add-ons, and billing controls in one place."
        case .localModelGated:
            return "GGUF and Core ML models require Lifetime or Pro for unlimited private inference. Your data never leaves your device."
        case .maximumModeLimit:
            return "Upgrade for unlimited Maximum mode, or switch to Standard or Deep Think anytime."
        case .launchSale:
            return "One payment, no renewal, no daily cap on Maximum mode, unlimited documents. The discount is real and it ends on the date shown."
        case .momentOfValue:
            return "Every plan runs the same model. Pro and Lifetime lift the daily cap on Maximum mode and raise the document and library limits. You will not be asked again."
        case .onboarding:
            return "Free is 5 documents, one library and three Maximum runs a day, on the same model as every paid plan. This screen shows once; the Plan & Usage row in Settings has it whenever you want it."
        }
    }

    /// Lowercase string for telemetry attributes.
    var analyticsValue: String { rawValue }
}
