import Foundation

enum MaximumModeAccessPolicy: Equatable, Sendable {
    case unlimited
    case meteredDaily(limit: Int)

    var isUnlimited: Bool {
        if case .unlimited = self {
            return true
        }
        return false
    }

    var dailyLimit: Int? {
        if case let .meteredDaily(limit) = self {
            return limit
        }
        return nil
    }
}

enum LegacyProtectionState: String, Codable, Sendable {
    case none
    case historicalPaidPurchase
    case legacyDocumentPackOwner

    var isProtected: Bool { self != .none }

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .historicalPaidPurchase:
            return "Legacy Paid"
        case .legacyDocumentPackOwner:
            return "Legacy Pack Owner"
        }
    }
}

struct EntitlementSnapshot: Sendable {
    let activeTier: WorkspaceTier
    let documentLimit: Int
    let libraryLimit: Int
    let maximumModePolicy: MaximumModeAccessPolicy
    let legacyProtectionState: LegacyProtectionState
    let shouldOfferDocumentPack: Bool

    var isLifetime: Bool { activeTier == .lifetime }
    var isLegacyPaidProtected: Bool { legacyProtectionState.isProtected }
    var hasUnlimitedDocuments: Bool { QuotaPolicy.isUnlimitedDocumentLimit(documentLimit) }
}

enum MaximumModeExecutionDecision: Sendable {
    case allowedUnlimited
    case allowedMetered(remaining: Int, dailyLimit: Int)
    case blocked(remaining: Int, dailyLimit: Int, resetsAt: Date)
}
