import Foundation
import StoreKit

/// Production-ready BillingService that talks to StoreKit 2.
@MainActor
final class StoreKitBillingService: BillingService {
    private(set) var products: [BillingProduct: Product] = [:]
    private var purchasesInFlight = Set<BillingProduct>()
    private var updatesTask: Task<Void, Never>?

    let events: AsyncStream<BillingEvent>
    private let continuation: AsyncStream<BillingEvent>.Continuation

    init() {
        var streamContinuation: AsyncStream<BillingEvent>.Continuation!
        self.events = AsyncStream { continuation in
            streamContinuation = continuation
        }
        self.continuation = streamContinuation
        
        #if DEBUG
        // Enable StoreKit testing mode with local configuration file
        if let configURL = Bundle.main.url(forResource: "StoreKitConfiguration", withExtension: "storekit") {
            Log.info("✅ StoreKit test configuration found at: \(configURL.path)", category: .billing)
            // Note: Configuration file must also be set in scheme's StoreKit Configuration option
        } else {
            Log.warning("⚠️ StoreKit test configuration not found - products may be unavailable", category: .billing)
        }
        #endif
        
        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
        Task { await refreshProducts() }
    }

    deinit {
        updatesTask?.cancel()
        continuation.finish()
    }

    func refreshProducts() async {
        do {
            let ids = BillingProduct.allCases.map(\.rawValue)
            let storeProducts = try await Product.products(for: ids)
            var mapping: [BillingProduct: Product] = [:]
            for product in storeProducts {
                guard let billingProduct = BillingProduct(rawValue: product.id) else { continue }
                mapping[billingProduct] = product
            }
            products = mapping
            continuation.yield(.productsLoaded(mapping))
            emitBilling("Products refreshed", metadata: ["count": String(mapping.count)])
            if mapping.isEmpty {
                Log.warning("StoreKit returned an empty product catalog", category: .billing)
                emitBilling(
                    "Products unavailable",
                    severity: .warning,
                    metadata: ["requested": ids.joined(separator: ",")]
                )
            }
        } catch {
            Log.error("Failed to load StoreKit products: \(error.localizedDescription)", category: .billing)
            emitBilling(
                "Product refresh failed",
                severity: .error,
                metadata: ["reason": error.localizedDescription]
            )
        }
    }

    func purchase(_ product: BillingProduct) async throws -> Transaction? {
        guard purchasesInFlight.insert(product).inserted else {
            throw BillingError(product: product, reason: .purchaseInProgress)
        }
        defer { purchasesInFlight.remove(product) }

        guard let storeProduct = products[product] else {
            emitBilling(
                "Product unavailable",
                severity: .error,
                metadata: ["product": product.rawValue]
            )
            throw BillingError(product: product, reason: .productUnavailable)
        }

        emitBilling("Purchase initiated", metadata: ["product": product.rawValue])

        do {
            let result = try await storeProduct.purchase()
            return try handlePurchaseResult(result, for: product)
        } catch {
            let wrapped = BillingError(product: product, reason: .storeKitError(error), underlyingError: error)
            continuation.yield(.purchaseFailed(product: product, error: wrapped))
            emitBilling(
                "Purchase failed",
                severity: .error,
                metadata: [
                    "product": product.rawValue,
                    "reason": error.localizedDescription
                ]
            )
            throw wrapped
        }
    }

    func restorePurchases() async {
        emitBilling("Restore started")
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard let billingProduct = BillingProduct(rawValue: transaction.productID) else { continue }
                continuation.yield(.transactionUpdated(product: billingProduct, transaction: transaction))
                emitBilling(
                    "Restore applied",
                    metadata: [
                        "product": billingProduct.rawValue,
                        "transactionId": String(transaction.id)
                    ]
                )
            } catch {
                Log.error("Restore failed verification: \(error.localizedDescription)", category: .billing)
                let billingProduct = (error as? BillingError)?.product ?? .starterMonthly
                emitBilling(
                    "Restore verification failed",
                    severity: .error,
                    metadata: [
                        "product": billingProduct.rawValue,
                        "reason": error.localizedDescription
                    ]
                )
            }
        }
    }

    // MARK: - Helpers

    private func handlePurchaseResult(_ result: Product.PurchaseResult, for product: BillingProduct) throws -> Transaction? {
        switch result {
        case .success(let verification):
            let transaction = try checkVerified(verification, expectedProduct: product)
            continuation.yield(.purchaseSucceeded(product: product, transaction: transaction))
            emitBilling(
                "Purchase succeeded",
                metadata: [
                    "product": product.rawValue,
                    "transactionId": String(transaction.id)
                ]
            )
            Task { await transaction.finish() }
            return transaction
        case .pending:
            continuation.yield(.pending(product: product))
            emitBilling("Purchase pending", metadata: ["product": product.rawValue])
            return nil
        case .userCancelled:
            continuation.yield(.userCancelled(product: product))
            emitBilling(
                "Purchase cancelled",
                severity: .warning,
                metadata: ["product": product.rawValue]
            )
            return nil
        @unknown default:
            emitBilling(
                "Purchase failed",
                severity: .error,
                metadata: ["product": product.rawValue, "reason": "unknown state"]
            )
            throw BillingError(product: product, reason: .unknown)
        }
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            do {
                let transaction = try checkVerified(result)
                guard let billingProduct = BillingProduct(rawValue: transaction.productID) else { continue }
                continuation.yield(.transactionUpdated(product: billingProduct, transaction: transaction))
                emitBilling(
                    "Transaction updated",
                    metadata: [
                        "product": billingProduct.rawValue,
                        "transactionId": String(transaction.id)
                    ]
                )
                await transaction.finish()
            } catch {
                Log.error("Transaction update verification failed: \(error.localizedDescription)", category: .billing)
                let billingProduct = (error as? BillingError)?.product ?? .starterMonthly
                emitBilling(
                    "Transaction verification failed",
                    severity: .error,
                    metadata: [
                        "product": billingProduct.rawValue,
                        "reason": error.localizedDescription
                    ]
                )
            }
        }
    }

    private func checkVerified(
        _ result: VerificationResult<Transaction>,
        expectedProduct: BillingProduct? = nil
    ) throws -> Transaction {
        switch result {
        case .verified(let transaction):
            return transaction
        case .unverified(let unsignedTransaction, let verificationError):
            let product = expectedProduct
                ?? BillingProduct(rawValue: unsignedTransaction.productID)
                ?? .starterMonthly
            emitBilling(
                "Verification failed",
                severity: .error,
                metadata: [
                    "product": product.rawValue,
                    "reason": verificationError.localizedDescription
                ]
            )
            throw BillingError(
                product: product,
                reason: .verificationFailed,
                underlyingError: verificationError
            )
        }
    }

    private func emitBilling(
        _ title: String,
        severity: TelemetrySeverity = .info,
        metadata: [String: String] = [:]
    ) {
        TelemetryCenter.emitBillingEvent(title, severity: severity, metadata: metadata)
    }
}
