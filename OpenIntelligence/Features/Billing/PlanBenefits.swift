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
        "\(QuotaPolicy.proEvidenceThreadLimit) conversations in each library",
        "Watched folders that import new files",
        "Cancel anytime",
    ]

    static let lifetime = [
        "Maximum mode with no daily cap",
        "Unlimited documents",
        "\(QuotaPolicy.lifetimeLibraryLimit) libraries",
        "Unlimited conversations in each library",
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

    /// One line of the "Free, Pro and Lifetime" table: a thing a paid plan gates and what each plan has of it.
    struct Comparison: Identifiable {
        let icon: String
        let name: String
        let free: String
        let pro: String
        let lifetime: String
        var id: String { name }
    }

    /// Everything a plan changes, side by side, so a buyer sees what the free plan lacks without opening each
    /// card. Every figure is `QuotaPolicy`'s. iCloud Sync is paid and is left out until its two-device check
    /// passes (`testICloudSyncWaitsForTheTwoDeviceCheck`).
    static let comparison = [
        Comparison(
            icon: "bolt.fill", name: "Maximum mode",
            free: "\(QuotaPolicy.freeMaximumModeDailyLimit) a day", pro: "No cap", lifetime: "No cap"),
        Comparison(
            icon: "doc.on.doc", name: "Documents",
            free: count(QuotaPolicy.freeDocumentLimit), pro: count(QuotaPolicy.proDocumentLimit),
            lifetime: count(QuotaPolicy.lifetimeDocumentLimit)),
        Comparison(
            icon: "books.vertical", name: "Libraries",
            free: count(QuotaPolicy.freeLibraryLimit), pro: count(QuotaPolicy.proLibraryLimit),
            lifetime: count(QuotaPolicy.lifetimeLibraryLimit)),
        Comparison(
            icon: "bubble.left.and.bubble.right", name: "Conversations in each library",
            free: count(QuotaPolicy.freeEvidenceThreadLimit), pro: count(QuotaPolicy.proEvidenceThreadLimit),
            lifetime: count(QuotaPolicy.lifetimeEvidenceThreadLimit)),
        Comparison(
            icon: "folder.badge.gearshape", name: "Watched folders", free: "Not included", pro: "Included",
            lifetime: "Included"),
    ]

    private static func count(_ limit: Int) -> String {
        limit == .max ? "Unlimited" : limit.formatted()
    }
}
