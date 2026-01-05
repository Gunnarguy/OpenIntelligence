import Foundation
import StoreKit

/// Production-ready BillingService that talks to StoreKit 2.
@MainActor
final class StoreKitBillingService: BillingService {
    private(set) var products: [BillingProduct: Product] = [:]
    private var purchasesInFlight = Set<BillingProduct>()
    private var updatesTask: Task<Void, Never>?

    private var refreshInFlight = false
    private var hasEmittedEmptyCatalogWarning = false

    /// Cached diagnostics for this process (receipt existence can change, but this provides
    /// high-signal context when debugging “empty product catalog” on-device).
    private lazy var cachedStoreKitDiagnostics: [String: String] = Self.makeStoreKitDiagnostics()

    let events: AsyncStream<BillingEvent>
    private let continuation: AsyncStream<BillingEvent>.Continuation

    init() {
        var streamContinuation: AsyncStream<BillingEvent>.Continuation!
        events = AsyncStream { continuation in
            streamContinuation = continuation
        }
        continuation = streamContinuation

        updatesTask = Task { [weak self] in await self?.listenForTransactions() }
    }

    deinit {
        updatesTask?.cancel()
        continuation.finish()
    }

    func refreshProducts() async {
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }
        do {
            let ids = BillingProduct.allCases.map(\.rawValue)
            let diagnostics = cachedStoreKitDiagnostics
            Log.info("🔍 Requesting \(ids.count) products from StoreKit: \(ids.joined(separator: ", "))", category: .billing)
            Log.info(
                "🧾 StoreKit diagnostics: \(Self.formatDiagnostics(diagnostics))",
                category: .billing
            )

            let storeProducts = try await Product.products(for: ids)
            Log.info("📦 StoreKit returned \(storeProducts.count) products", category: .billing)

            var mapping: [BillingProduct: Product] = [:]
            for product in storeProducts {
                Log.info("  ✅ Loaded: \(product.id) - \(product.displayName) (\(product.displayPrice))", category: .billing)
                guard let billingProduct = BillingProduct(rawValue: product.id) else {
                    Log.warning("  ⚠️ Unknown product ID: \(product.id)", category: .billing)
                    continue
                }
                mapping[billingProduct] = product
            }

            products = mapping
            continuation.yield(.productsLoaded(mapping))

            let loadedIDs = mapping.keys.map(\.rawValue).sorted()
            let missingIDs = ids.filter { id in !loadedIDs.contains(id) }

            if !missingIDs.isEmpty {
                Log.warning("❌ Missing products: \(missingIDs.joined(separator: ", "))", category: .billing)
            }

            emitBilling(
                "Products refreshed",
                metadata: [
                    "environment": diagnostics["environment"] ?? "unknown",
                    "bundleId": diagnostics["bundleId"] ?? "unknown",
                    "receiptPresent": diagnostics["receiptPresent"] ?? "unknown",
                    "receiptSandboxHint": diagnostics["receiptSandboxHint"] ?? "unknown",
                    "loaded": String(mapping.count),
                    "expected": String(ids.count),
                    "loadedIDs": loadedIDs.joined(separator: ","),
                    "missingIDs": missingIDs.joined(separator: ","),
                ]
            )

            if mapping.isEmpty {
                // This can legitimately happen in Simulator/DEBUG when StoreKit testing isn't configured,
                // or when ASC agreements / sandbox accounts are not fully set up.
                // Only emit once per session to reduce noisy duplicate warnings.
                if !hasEmittedEmptyCatalogWarning {
                    hasEmittedEmptyCatalogWarning = true
                    #if DEBUG
                        #if targetEnvironment(simulator)
                            Log.warning(
                                "StoreKit returned an empty product catalog. If you’re on Simulator, enable a StoreKit Configuration (.storekit) in the scheme (Run → Options → StoreKit Configuration).",
                                category: .billing
                            )
                        #else
                            Log.warning(
                                "StoreKit returned an empty product catalog. If you’re on a device, verify Sandbox sign-in and App Store Connect IAP availability.",
                                category: .billing
                            )
                        #endif
                    #else
                        Log.warning("StoreKit returned an empty product catalog", category: .billing)
                    #endif
                    emitBilling(
                        "Products unavailable",
                        severity: .warning,
                        metadata: [
                            "requested": ids.joined(separator: ","),
                            "environment": diagnostics["environment"] ?? "unknown",
                            "bundleId": diagnostics["bundleId"] ?? "unknown",
                            "receiptPresent": diagnostics["receiptPresent"] ?? "unknown",
                            "receiptSandboxHint": diagnostics["receiptSandboxHint"] ?? "unknown",
                        ]
                    )
                }
            }
        } catch {
            Log.error("Failed to load StoreKit products: \(error.localizedDescription)", category: .billing)
            emitBilling(
                "Product refresh failed",
                severity: .error,
                metadata: [
                    "reason": error.localizedDescription,
                    "environment": cachedStoreKitDiagnostics["environment"] ?? "unknown",
                    "bundleId": cachedStoreKitDiagnostics["bundleId"] ?? "unknown",
                    "receiptPresent": cachedStoreKitDiagnostics["receiptPresent"] ?? "unknown",
                    "receiptSandboxHint": cachedStoreKitDiagnostics["receiptSandboxHint"] ?? "unknown",
                ]
            )
        }
    }

    func purchase(_ product: BillingProduct) async throws -> Transaction? {
        guard purchasesInFlight.insert(product).inserted else {
            throw BillingError(product: product, reason: .purchaseInProgress)
        }
        defer { purchasesInFlight.remove(product) }

        // Product metadata can be missing on cold start (or when StoreKit returns a partial catalog).
        // Refresh once to maximize the chance we reach `storeProduct.purchase()` (which triggers
        // the native App Store confirmation sheet for subscriptions, non-consumables, and consumables).
        if products[product] == nil {
            await refreshProducts()
        }

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
            let message = wrapped.errorDescription ?? error.localizedDescription
            emitBilling(
                "Purchase failed",
                severity: .error,
                metadata: [
                    "product": product.rawValue,
                    "reason": message,
                ]
            )
            throw wrapped
        }
    }

    func restorePurchases() async {
        emitBilling("Restore started")

        // On-device sandbox debugging quality-of-life:
        // `AppStore.sync()` can prompt the user to sign in (including Sandbox) and refresh receipts.
        // This often resolves the “nothing restores / products unavailable” state after account changes.
        do {
            try await AppStore.sync()
            emitBilling(
                "App Store sync succeeded",
                metadata: [
                    "environment": cachedStoreKitDiagnostics["environment"] ?? "unknown",
                    "receiptPresent": cachedStoreKitDiagnostics["receiptPresent"] ?? "unknown",
                    "receiptSandboxHint": cachedStoreKitDiagnostics["receiptSandboxHint"] ?? "unknown",
                ]
            )
        } catch {
            Log.warning("AppStore.sync() failed: \(error.localizedDescription)", category: .billing)
            emitBilling(
                "App Store sync failed",
                severity: .warning,
                metadata: [
                    "reason": error.localizedDescription,
                    "environment": cachedStoreKitDiagnostics["environment"] ?? "unknown",
                ]
            )
        }

        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                guard let billingProduct = BillingProduct(rawValue: transaction.productID) else { continue }
                continuation.yield(.transactionUpdated(product: billingProduct, transaction: transaction))
                emitBilling(
                    "Restore applied",
                    metadata: [
                        "product": billingProduct.rawValue,
                        "transactionId": String(transaction.id),
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
                        "reason": error.localizedDescription,
                    ]
                )
            }
        }
    }

    // MARK: - Helpers

    private func handlePurchaseResult(_ result: Product.PurchaseResult, for product: BillingProduct) throws -> Transaction? {
        switch result {
        case let .success(verification):
            let transaction = try checkVerified(verification, expectedProduct: product)
            continuation.yield(.purchaseSucceeded(product: product, transaction: transaction))
            emitBilling(
                "Purchase succeeded",
                metadata: [
                    "product": product.rawValue,
                    "transactionId": String(transaction.id),
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
                        "transactionId": String(transaction.id),
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
                        "reason": error.localizedDescription,
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
        case let .verified(transaction):
            return transaction
        case let .unverified(unsignedTransaction, verificationError):
            let product = expectedProduct
                ?? BillingProduct(rawValue: unsignedTransaction.productID)
                ?? .starterMonthly
            emitBilling(
                "Verification failed",
                severity: .error,
                metadata: [
                    "product": product.rawValue,
                    "reason": verificationError.localizedDescription,
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

    // MARK: - StoreKit diagnostics

    private static func makeStoreKitDiagnostics() -> [String: String] {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
        let buildNumber = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"

        // Non-async heuristics (no deprecated APIs): we cannot synchronously query StoreKit transactions.
        // Fall back to conservative defaults; detailed receipt info will be captured in event streams elsewhere.
        let receiptPresent = "unknown"
        let receiptSandboxHint = "unknown"

        #if targetEnvironment(simulator)
            let environment = "simulator"
        #else
            let environment = "device"
        #endif

        return [
            "environment": environment,
            "bundleId": bundleId,
            "appVersion": appVersion,
            "buildNumber": buildNumber,
            "receiptPresent": receiptPresent,
            "receiptSandboxHint": receiptSandboxHint,
        ]
    }

    private static func formatDiagnostics(_ diagnostics: [String: String]) -> String {
        // Stable ordering keeps logs diffable.
        let keys = [
            "environment",
            "bundleId",
            "appVersion",
            "buildNumber",
            "receiptPresent",
            "receiptSandboxHint",
        ]

        return keys
            .compactMap { key in
                guard let value = diagnostics[key] else { return nil }
                return "\(key)=\(value)"
            }
            .joined(separator: ", ")
    }
}
