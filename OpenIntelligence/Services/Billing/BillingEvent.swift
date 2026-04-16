import Foundation
import StoreKit

/// Streamed events emitted by BillingService implementations so observers can react
/// without holding on to StoreKit transaction objects directly.
enum BillingEvent {
    case productsLoaded([BillingProduct: Product])
    case purchaseSucceeded(product: BillingProduct, transaction: Transaction)
    case purchaseFailed(product: BillingProduct, error: BillingError)
    case transactionUpdated(product: BillingProduct, transaction: Transaction)
    case userCancelled(product: BillingProduct)
    case pending(product: BillingProduct)
}
