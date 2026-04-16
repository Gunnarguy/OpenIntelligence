import Foundation

/// Shared quota policy constants for gating ingestion before StoreKit launches.
enum QuotaPolicy {
    /// Base document allowance for each tier prior to add-on credits.
    static let freeDocumentLimit: Int = 5
    static let proDocumentLimit: Int = 1_000  // Hard cap per QuotaPolicy
    static let lifetimeDocumentLimit: Int = 1_000

    /// Base workspace (container) allowance.
    static let freeLibraryLimit: Int = 1
    static let proLibraryLimit: Int = 5
    static let lifetimeLibraryLimit: Int = 10

    /// Number of extra documents granted per consumable add-on.
    static let addOnDocumentIncrement: Int = 10

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
