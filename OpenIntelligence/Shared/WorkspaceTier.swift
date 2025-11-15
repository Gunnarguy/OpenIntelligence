import Foundation

/// Supported monetization tiers for the workspace.
/// Extensible so future enterprise tiers can reuse the same plumbing.
enum WorkspaceTier: String, Codable, CaseIterable {
    case free
    case starter
    case pro
    case lifetime

    /// Human-friendly label for UI surfaces.
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .starter: return "Starter"
        case .pro: return "Pro"
        case .lifetime: return "Lifetime"
        }
    }

    /// Used when comparing tiers for gating logic.
    var rank: Int {
        switch self {
        case .free: return 0
        case .starter: return 1
        case .pro: return 2
        case .lifetime: return 3
        }
    }

    /// Convenience helper for checking if the current tier already matches or exceeds another tier.
    func isAtLeast(_ tier: WorkspaceTier) -> Bool {
        rank >= tier.rank
    }
}
