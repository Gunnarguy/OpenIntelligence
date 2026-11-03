import Foundation

/// What the plans screen says each paid plan adds.
///
/// The rule from `Docs/BILLING_AND_LIMITS.md`: a plan bullet may name only what that plan gates, and
/// Maximum mode comes first because it is the one model feature a paid plan gates. Everything here
/// is checked against `QuotaPolicy` by `PlanBenefitsTests`, so a changed limit can't leave a stale
/// bullet behind.
enum PlanBenefits {
    struct Highlight: Identifiable {
        let icon: String
        let text: String
        var id: String { text }
    }

    static let pro = [
        "Maximum mode with no daily cap",
        "Up to \(QuotaPolicy.proDocumentLimit.formatted()) documents",
        "\(QuotaPolicy.proLibraryLimit) libraries",
        "Watched folders that import new files",
        "Cancel anytime",
    ]

    static let lifetime = [
        "Maximum mode with no daily cap",
        "Unlimited documents",
        "\(QuotaPolicy.lifetimeLibraryLimit) libraries",
        "Watched folders that import new files",
        "Never expires",
    ]

    /// The "What you get" list, shown above the plan cards.
    static let highlights = [
        Highlight(icon: "bolt.fill", text: "Maximum mode with no daily cap"),
        Highlight(icon: "doc.badge.plus", text: "More documents and more libraries"),
        Highlight(icon: "folder.badge.gearshape", text: "Watched folders that import new files"),
        Highlight(icon: "creditcard", text: "Pay once with Lifetime"),
    ]
}
