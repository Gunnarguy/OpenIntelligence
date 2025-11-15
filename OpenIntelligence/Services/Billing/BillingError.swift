import Foundation

/// Billing-specific error wrapper so UI can surface friendly messages.
struct BillingError: LocalizedError {
    enum Reason {
        case productUnavailable
        case purchaseInProgress
        case verificationFailed
        case storeKitError(Error)
        case unknown
    }

    let product: BillingProduct
    let reason: Reason
    let underlyingError: Error?

    init(product: BillingProduct, reason: Reason, underlyingError: Error? = nil) {
        self.product = product
        self.reason = reason
        self.underlyingError = underlyingError
    }

    var errorDescription: String? {
        switch reason {
        case .productUnavailable:
            return "That product isn't available right now."
        case .purchaseInProgress:
            return "A purchase is already in progress for this product."
        case .verificationFailed:
            return "We couldn't verify the App Store receipt."
        case .storeKitError(let error):
            return error.localizedDescription
        case .unknown:
            return "Something went wrong during the purchase."
        }
    }
}
