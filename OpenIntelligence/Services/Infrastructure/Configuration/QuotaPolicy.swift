import Foundation

/// Shared quota policy constants for gating ingestion before StoreKit launches.
enum QuotaPolicy {
    static let unlimitedDocumentLimit: Int = .max

    /// Base document allowance for each tier prior to add-on credits.
    static let freeDocumentLimit: Int = 5
    static let proDocumentLimit: Int = 1_000  // Hard cap per QuotaPolicy
    static let lifetimeDocumentLimit: Int = unlimitedDocumentLimit

    /// Base workspace (container) allowance.
    static let freeLibraryLimit: Int = 1
    static let proLibraryLimit: Int = 10
    static let lifetimeLibraryLimit: Int = 20

    /// Number of extra documents granted per consumable add-on.
    static let addOnDocumentIncrement: Int = 10

    /// Free-tier daily allowance for Maximum mode.
    static let freeMaximumModeDailyLimit: Int = 3

    /// Returns the allowed document count for a given workspace tier.
    static func documentLimit(for tier: WorkspaceTier = .free) -> Int {
        switch tier {
        case .free:
            return freeDocumentLimit
        case .pro:
            return proDocumentLimit
        case .lifetime:
            return lifetimeDocumentLimit
        }
    }

    static func isUnlimitedDocumentLimit(_ limit: Int) -> Bool {
        limit == unlimitedDocumentLimit
    }

    static func documentLimitDisplayText(_ limit: Int) -> String {
        isUnlimitedDocumentLimit(limit) ? "Unlimited" : "\(limit)"
    }

    /// Returns the allowed container/library count for a given workspace tier.
    static func libraryLimit(for tier: WorkspaceTier = .free) -> Int {
        switch tier {
        case .free:
            return freeLibraryLimit
        case .pro:
            return proLibraryLimit
        case .lifetime:
            return lifetimeLibraryLimit
        }
    }
}

/// User-visible error surfaced when ingestion attempts exceed the free-tier quota.
struct DocumentQuotaError: LocalizedError {
    let limit: Int

    var errorDescription: String? {
        "You've reached the current workspace limit of \(limit) documents."
    }

    var recoverySuggestion: String? {
        "Remove a document or upgrade to keep adding content."
    }
}

struct LibraryQuotaError: LocalizedError {
    let limit: Int
    let attemptedCount: Int?
    let tier: WorkspaceTier?

    var errorDescription: String? {
        if let attemptedCount, let tier {
            return "This would bring your workspace to \(attemptedCount) libraries. Your \(tier.displayName) plan supports up to \(limit) libraries."
        }

        return "You've reached the current workspace limit of \(limit) libraries."
    }

    var recoverySuggestion: String? {
        "Delete or merge a library, or upgrade to a plan with more library capacity."
    }
}
