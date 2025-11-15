import Foundation

/// Canonical list of StoreKit product identifiers used by the app.
/// Keeping it centralized avoids stringly-typed purchases throughout the UI.
enum BillingProduct: String, CaseIterable {
    case starterMonthly = "starter_monthly"
    case starterAnnual = "starter_annual"
    case proMonthly = "pro_monthly"
    case proAnnual = "pro_annual"
    case lifetimeCohort = "lifetime_cohort"
    case documentPackAddOn = "doc_pack_addon"

    enum Kind {
        case subscription
        case nonConsumable
        case consumable
    }

    /// Convenience metadata used by paywall copy and entitlement mapping.
    var kind: Kind {
        switch self {
        case .starterMonthly, .starterAnnual, .proMonthly, .proAnnual:
            return .subscription
        case .lifetimeCohort:
            return .nonConsumable
        case .documentPackAddOn:
            return .consumable
        }
    }

    /// Workspace tier unlocked by the purchase, if any.
    var associatedTier: WorkspaceTier? {
        switch self {
        case .starterMonthly, .starterAnnual:
            return .starter
        case .proMonthly, .proAnnual:
            return .pro
        case .lifetimeCohort:
            return .lifetime
        case .documentPackAddOn:
            return nil
        }
    }

    /// One-line marketing message for receipts / diagnostics.
    var marketingBlurb: String {
        switch self {
        case .starterMonthly:
            return "Starter plan (monthly)"
        case .starterAnnual:
            return "Starter plan (annual)"
        case .proMonthly:
            return "Pro plan (monthly)"
        case .proAnnual:
            return "Pro plan (annual)"
        case .lifetimeCohort:
            return "Lifetime cohort unlock"
        case .documentPackAddOn:
            return "Document pack add-on"
        }
    }
}
