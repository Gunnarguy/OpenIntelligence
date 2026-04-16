import Foundation
import StoreKit

/// Abstraction over StoreKit so we can unit test entitlement flows or swap implementations later.
@MainActor
protocol BillingService: AnyObject {
    var events: AsyncStream<BillingEvent> { get }

    /// Fetches/refreshes product metadata from the App Store or local configuration file.
    func refreshProducts() async

    /// Initiates a purchase for the specified product.
    func purchase(_ product: BillingProduct) async throws -> Transaction?

    /// Restores previously purchased products (useful for Settings).
    func restorePurchases() async
}
