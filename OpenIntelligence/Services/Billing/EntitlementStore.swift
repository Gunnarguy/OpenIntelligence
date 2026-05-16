import Combine
import Foundation
import StoreKit

/// Ledger entry describing a document-pack consumable purchase.
private struct DocumentPackEntry: Codable, Identifiable {
    let id: UUID
    let transactionId: UInt64?
    let purchaseDate: Date
    let credits: Int
    var expirationDate: Date?

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate <= Date()
    }

    var activeCredits: Int {
        isExpired ? 0 : credits
    }
}

enum LocalModelAccessState {
    case unlocked
    case blocked
}

/// Tracks active StoreKit entitlements, legacy protection, and feature policy.
@MainActor
final class EntitlementStore: ObservableObject {
    @Published private(set) var activeTier: WorkspaceTier
    @Published private(set) var documentLimit: Int
    @Published private(set) var libraryLimit: Int
    @Published private(set) var legacyProtectionState: LegacyProtectionState
    @Published private(set) var maximumModeRemainingUses: Int
    @Published private(set) var isLoading: Bool = true
    @Published var lastError: String?
    @Published private(set) var availableProducts: [BillingProduct: Product] = [:]
    @Published fileprivate private(set) var documentPacks: [DocumentPackEntry] = []

    /// Derived count of non-expired add-on packs, retained for legacy UI bindings.
    var addOnPacks: Int { Self.activePackCount(for: documentPacks) }

    /// Total active credits granted by the ledger entries.
    var availableDocumentCredits: Int { Self.totalCredits(for: documentPacks) }

    /// Indicates whether the user has reached the maximum allowed add-on packs.
    var hasReachedDocumentPackCap: Bool { addOnPacks >= maxAddOnPacks }

    /// Maximum number of add-on packs that can be active simultaneously.
    var documentPackCap: Int { maxAddOnPacks }

    /// Remaining add-on purchases a user can make before hitting the cap.
    var remainingDocumentPackCapacity: Int { max(maxAddOnPacks - addOnPacks, 0) }

    var hasUnlimitedDocuments: Bool { entitlementSnapshot.hasUnlimitedDocuments }
    var documentLimitDisplayText: String { QuotaPolicy.documentLimitDisplayText(documentLimit) }
    var isLegacyPaidProtected: Bool { entitlementSnapshot.isLegacyPaidProtected }
    var effectiveTier: WorkspaceTier { entitlementSnapshot.activeTier }
    var hasUnlimitedMaximumMode: Bool { maximumModeAccessPolicy.isUnlimited }
    var canUseMaximumModeNow: Bool { hasUnlimitedMaximumMode || maximumModeRemainingUses > 0 }
    var shouldOfferDocumentPack: Bool { entitlementSnapshot.shouldOfferDocumentPack }

    var currentPlanDisplayName: String {
        effectiveTier.displayName
    }

    var maximumModeAccessPolicy: MaximumModeAccessPolicy {
        entitlementSnapshot.maximumModePolicy
    }

    var maximumModeSelectionSummary: String {
        switch maximumModeAccessPolicy {
        case .unlimited:
            return "Unlimited on your current plan"
        case let .meteredDaily(limit):
            return "\(maximumModeRemainingUses) of \(limit) free Maximum runs left today"
        }
    }

    var maximumModeResetDate: Date? {
        guard case .meteredDaily = maximumModeAccessPolicy else { return nil }
        return maximumModeQuotaStore.nextResetDate()
    }

    var entitlementSnapshot: EntitlementSnapshot {
        Self.buildSnapshot(
            activeTier: activeTier,
            documentCredits: availableDocumentCredits,
            legacyProtectionState: legacyProtectionState
        )
    }

    let billingService: BillingService
    private var eventTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let maxAddOnPacks = 3
    private let maximumModeQuotaStore: MaximumModeQuotaStore

    private enum Keys {
        static let tier = "entitlement.activeTier"
        static let addOns = "entitlement.docAddOns" // Legacy storage, retained for migration
        static let packs = "entitlement.docPackLedger"
        static let legacyProtection = "entitlement.legacyProtectionState"
    }

    init(billingService: BillingService, defaults: UserDefaults = .standard) {
        self.billingService = billingService
        self.defaults = defaults
        self.maximumModeQuotaStore = MaximumModeQuotaStore(defaults: defaults)

        let storedTier = defaults.string(forKey: Keys.tier)
        let resolvedTier = WorkspaceTier(rawValue: storedTier ?? "") ?? .free
        activeTier = resolvedTier

        let loadedPacks = Self.loadDocumentPacks(from: defaults)
        let prunedPacks = Self.pruneExpiredPacks(loadedPacks)
        documentPacks = prunedPacks

        let storedLegacy = defaults.string(forKey: Keys.legacyProtection)
        let resolvedLegacy = LegacyProtectionState(rawValue: storedLegacy ?? "") ?? .none
        legacyProtectionState = resolvedLegacy

        let initialSnapshot = Self.buildSnapshot(
            activeTier: resolvedTier,
            documentCredits: Self.totalCredits(for: prunedPacks),
            legacyProtectionState: resolvedLegacy
        )
        documentLimit = initialSnapshot.documentLimit
        libraryLimit = initialSnapshot.libraryLimit
        maximumModeRemainingUses = 0

        eventTask = Task { await observeBillingEvents() }
        Task { await billingService.refreshProducts() }
        if prunedPacks.count != loadedPacks.count {
            persistDocumentPacks()
        }
        recalculateAllowances()
        isLoading = false
    }

    deinit {
        eventTask?.cancel()
    }

    private static func loadDocumentPacks(from defaults: UserDefaults) -> [DocumentPackEntry] {
        if let data = defaults.data(forKey: Keys.packs) {
            do {
                let decoder = JSONDecoder()
                return try decoder.decode([DocumentPackEntry].self, from: data)
            } catch {
                Log.error("Failed to decode document pack ledger: \(error.localizedDescription)", category: .billing)
                defaults.removeObject(forKey: Keys.packs)
            }
        }

        // Legacy migration path: convert stored pack count into individual entries.
        let legacyCount = defaults.integer(forKey: Keys.addOns)
        guard legacyCount > 0 else { return [] }
        let clamped = min(legacyCount, 3)
        defaults.removeObject(forKey: Keys.addOns)
        let now = Date()
        let migratedPacks = (0 ..< clamped).map { _ in
            DocumentPackEntry(
                id: UUID(),
                transactionId: nil,
                purchaseDate: now,
                credits: QuotaPolicy.addOnDocumentIncrement,
                expirationDate: nil
            )
        }
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(migratedPacks)
            defaults.set(data, forKey: Keys.packs)
        } catch {
            Log.error("Failed to persist migrated document pack ledger: \(error.localizedDescription)", category: .billing)
        }
        return migratedPacks
    }

    private static func totalCredits(for packs: [DocumentPackEntry]) -> Int {
        packs.reduce(into: 0) { partialResult, entry in
            partialResult += entry.activeCredits
        }
    }

    private static func activePackCount(for packs: [DocumentPackEntry]) -> Int {
        packs.reduce(into: 0) { count, entry in
            if !entry.isExpired {
                count += 1
            }
        }
    }

    private static func pruneExpiredPacks(_ packs: [DocumentPackEntry]) -> [DocumentPackEntry] {
        packs.filter { !$0.isExpired }
    }

    private static func buildSnapshot(
        activeTier: WorkspaceTier,
        documentCredits: Int,
        legacyProtectionState: LegacyProtectionState
    ) -> EntitlementSnapshot {
        let resolvedTier: WorkspaceTier = legacyProtectionState.isProtected ? .lifetime : activeTier
        let baseDocumentLimit = QuotaPolicy.documentLimit(for: resolvedTier)
        let resolvedDocumentLimit: Int
        if QuotaPolicy.isUnlimitedDocumentLimit(baseDocumentLimit) {
            resolvedDocumentLimit = baseDocumentLimit
        } else {
            resolvedDocumentLimit = baseDocumentLimit + documentCredits
        }

        let maximumModePolicy: MaximumModeAccessPolicy
        if resolvedTier != .free {
            maximumModePolicy = .unlimited
        } else {
            maximumModePolicy = .meteredDaily(limit: QuotaPolicy.freeMaximumModeDailyLimit)
        }

        return EntitlementSnapshot(
            activeTier: resolvedTier,
            documentLimit: resolvedDocumentLimit,
            libraryLimit: QuotaPolicy.libraryLimit(for: resolvedTier),
            maximumModePolicy: maximumModePolicy,
            legacyProtectionState: legacyProtectionState,
            shouldOfferDocumentPack: false
        )
    }

    nonisolated static func currentEffectiveTier(defaults: UserDefaults = .standard) -> WorkspaceTier {
        let storedTier = defaults.string(forKey: Keys.tier)
        let activeTier = WorkspaceTier(rawValue: storedTier ?? "") ?? .free
        let storedLegacy = defaults.string(forKey: Keys.legacyProtection)
        let legacyProtectionState = LegacyProtectionState(rawValue: storedLegacy ?? "") ?? .none

        return legacyProtectionState.isProtected ? .lifetime : activeTier
    }

    nonisolated static func currentLibraryLimit(defaults: UserDefaults = .standard) -> Int {
        QuotaPolicy.libraryLimit(for: currentEffectiveTier(defaults: defaults))
    }

    private func persistDocumentPacks() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(documentPacks)
            defaults.set(data, forKey: Keys.packs)
        } catch {
            Log.error("Failed to persist document pack ledger: \(error.localizedDescription)", category: .billing)
        }
    }

    private func persistState() {
        defaults.set(activeTier.rawValue, forKey: Keys.tier)
        defaults.set(addOnPacks, forKey: Keys.addOns)
        defaults.set(legacyProtectionState.rawValue, forKey: Keys.legacyProtection)
        persistDocumentPacks()
    }

    /// Drops expired ledger entries and persists when mutations occur.
    private func pruneExpiredDocumentPacksIfNeeded() {
        let originalCount = documentPacks.count
        documentPacks.removeAll { $0.isExpired }
        if documentPacks.count != originalCount {
            persistDocumentPacks()
        }
    }

    /// Appends a new ledger entry for a consumable purchase while enforcing the pack cap.
    private func appendDocumentPack(for transaction: Transaction) {
        let identifier = transaction.id
        guard !documentPacks.contains(where: { $0.transactionId == identifier }) else { return }
        guard !hasReachedDocumentPackCap else {
            TelemetryCenter.emitBillingEvent(
                "Document pack ignored – cap reached",
                severity: .warning,
                metadata: [
                    "transactionId": String(transaction.id),
                ]
            )
            return
        }

        let entry = DocumentPackEntry(
            id: UUID(),
            transactionId: identifier,
            purchaseDate: transaction.purchaseDate,
            credits: QuotaPolicy.addOnDocumentIncrement,
            expirationDate: transaction.expirationDate
        )
        documentPacks.append(entry)
        promoteLegacyProtection(to: .legacyDocumentPackOwner)
        persistDocumentPacks()
    }

    /// Removes the ledger entry associated with a revoked consumable transaction.
    private func removeDocumentPack(for transaction: Transaction) {
        let identifier = transaction.id
        let originalCount = documentPacks.count

        documentPacks.removeAll { entry in
            guard let storedId = entry.transactionId else { return false }
            return storedId == identifier
        }

        if documentPacks.count == originalCount,
           let fallbackIndex = documentPacks.firstIndex(where: { !$0.isExpired })
        {
            documentPacks.remove(at: fallbackIndex)
        }

        if documentPacks.count != originalCount {
            persistDocumentPacks()
        }
    }

    func canAddDocument(currentCount: Int) -> Bool {
        hasUnlimitedDocuments || currentCount < documentLimit
    }

    func canAddLibrary(currentCount: Int) -> Bool {
        currentCount < libraryLimit
    }

    func refreshTransientState() {
        recalculateAllowances()
    }

    func consumeMaximumModeUseIfNeeded() -> MaximumModeExecutionDecision {
        switch maximumModeAccessPolicy {
        case .unlimited:
            recalculateAllowances()
            return .allowedUnlimited
        case let .meteredDaily(limit):
            let decision = maximumModeQuotaStore.consumeIfAllowed(limit: limit)
            recalculateAllowances()
            return decision
        }
    }

    /// Reconciles entitlements from StoreKit on launch.
    /// This rebuilds the active StoreKit tier, then layers in sticky paid-history
    /// protection. Any verified past paid purchase is treated as effective
    /// Lifetime access for app gating, even if the active StoreKit tier is free.
    func reconcileEntitlementsOnLaunch() async {
        isLoading = true
        defer { isLoading = false }

        pruneExpiredDocumentPacksIfNeeded()

        var resolvedTier: WorkspaceTier = .free
        var reconciledCount = 0

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                guard let billingProduct = BillingProduct(rawValue: transaction.productID) else { continue }
                guard transaction.revocationDate == nil else { continue }
                if let tier = billingProduct.associatedTier {
                    resolvedTier = maxTier(resolvedTier, tier)
                    reconciledCount += 1
                    Log.info("✅ Reconciled entitlement: \(billingProduct.rawValue)", category: .billing)
                }
            case .unverified(_, let error):
                Log.warning("Entitlement reconciliation skipped unverified transaction: \(error.localizedDescription)", category: .billing)
            }
        }

        activeTier = resolvedTier

        if resolvedTier != .free {
            promoteLegacyProtection(to: .historicalPaidPurchase)
        } else if legacyProtectionState == .none,
                  let historicalProtection = await detectHistoricalProtectionFromStoreKit()
        {
            promoteLegacyProtection(to: historicalProtection)
        }

        if !documentPacks.isEmpty {
            promoteLegacyProtection(to: .legacyDocumentPackOwner)
        }

        persistState()
        recalculateAllowances()

        if reconciledCount > 0 || isLegacyPaidProtected {
            Log.info(
                "Entitlement reconciliation complete — activeTier: \(activeTier.rawValue), effectiveTier: \(effectiveTier.rawValue), legacy: \(legacyProtectionState.rawValue), docs: \(documentLimit), libs: \(libraryLimit)",
                category: .billing
            )
        }
    }

    private func detectHistoricalProtectionFromStoreKit() async -> LegacyProtectionState? {
        // AppTransaction is useful when migrating a paid app to freemium, but it doesn't
        // identify past IAP purchases. Here we intentionally inspect restorable paid SKUs
        // and grandfather them into effective Lifetime access.
        for product in [BillingProduct.proMonthly, .proAnnual, .lifetimeCohort] {
            guard let result = await Transaction.latest(for: product.rawValue) else { continue }
            switch result {
            case .verified(let transaction):
                guard transaction.revocationDate == nil else { continue }
                return .historicalPaidPurchase
            case .unverified:
                continue
            }
        }

        // We intentionally do not enable SKIncludeConsumableInAppPurchaseHistory because
        // Apple recommends server-side reconciliation before relying on finished consumable
        // history across reinstalls. Local document-pack ownership remains sticky instead.
        return nil
    }

    func product(for product: BillingProduct) -> Product? {
        availableProducts[product]
    }

    #if DEBUG
        private enum DebugKeys {
            /// When enabled, the UI may simulate purchases if StoreKit metadata fails to load.
            /// Default is `false` so Debug builds exercise the same StoreKit path as Release.
            static let enableBillingSimulation = "billing.debugSimulationEnabled"
        }

        /// Opt-in flag controlling whether the app should simulate purchases when StoreKit
        /// returns an empty/partial product catalog in DEBUG builds.
        var isDebugBillingSimulationEnabled: Bool {
            defaults.bool(forKey: DebugKeys.enableBillingSimulation)
        }

        /// DEBUG-only helper to simulate a consumable purchase when StoreKit is unavailable.
        /// This keeps UI development unblocked when `Product.products(for:)` returns an empty catalog.
        func addDebugDocumentPack() {
            guard !hasReachedDocumentPackCap else {
                lastError = "Document pack cap reached (DEBUG simulation)"
                return
            }
            let entry = DocumentPackEntry(
                id: UUID(),
                transactionId: nil,
                purchaseDate: Date(),
                credits: QuotaPolicy.addOnDocumentIncrement,
                expirationDate: nil
            )
            documentPacks.append(entry)
            promoteLegacyProtection(to: .legacyDocumentPackOwner)
            persistState()
            recalculateAllowances()
            lastError = nil
            TelemetryCenter.emitBillingEvent(
                "debug_purchase_simulated",
                metadata: [
                    "product": BillingProduct.documentPackAddOn.rawValue,
                    "credits": String(QuotaPolicy.addOnDocumentIncrement),
                ]
            )
        }

        /// DEBUG-only helper to simulate a tier unlock when StoreKit is unavailable.
        func simulateDebugPurchase(_ product: BillingProduct) {
            if let tier = product.associatedTier {
                setDebugTier(tier)
                lastError = nil
                TelemetryCenter.emitBillingEvent(
                    "debug_purchase_simulated",
                    metadata: [
                        "product": product.rawValue,
                        "tier": tier.rawValue,
                    ]
                )
                return
            }

            if product == .documentPackAddOn {
                addDebugDocumentPack()
                return
            }
        }
    #endif

    #if DEBUG
        /// DEBUG-only helper to force the active tier without a StoreKit transaction.
        /// Used by local purchase simulation and developer tooling.
        func setDebugTier(_ tier: WorkspaceTier) {
            activeTier = tier
            if tier != .free {
                promoteLegacyProtection(to: .historicalPaidPurchase)
            }
            persistState()
            recalculateAllowances()
        }
    #endif

    private func observeBillingEvents() async {
        for await event in billingService.events {
            handle(event)
        }
    }

    private func handle(_ event: BillingEvent) {
        switch event {
        case let .productsLoaded(mapping):
            availableProducts = mapping
        case let .purchaseSucceeded(product, transaction):
            applyPurchase(for: product, transaction: transaction)
        case let .transactionUpdated(product, transaction):
            if transaction.revocationDate != nil {
                handleRevocation(for: product, transaction: transaction)
            } else {
                applyPurchase(for: product, transaction: transaction)
            }
        case let .purchaseFailed(_, error):
            lastError = error.errorDescription
        case .userCancelled(_):
            lastError = nil
        case .pending(_):
            lastError = nil
        }
    }

    private func applyPurchase(for product: BillingProduct, transaction: Transaction) {
        if let tier = product.associatedTier {
            upgradeTierIfNeeded(to: tier)
            promoteLegacyProtection(to: .historicalPaidPurchase)
        }
        if product == .documentPackAddOn {
            appendDocumentPack(for: transaction)
        }
        persistState()
        recalculateAllowances()
        TelemetryCenter.emitBillingEvent(
            "Purchase processed",
            metadata: [
                "product": product.rawValue,
                "transactionId": String(transaction.id),
            ]
        )
    }

    private func handleRevocation(for product: BillingProduct, transaction: Transaction) {
        if product.associatedTier == activeTier {
            activeTier = .free
        }
        if product == .documentPackAddOn {
            removeDocumentPack(for: transaction)
        }
        persistState()
        recalculateAllowances()
        TelemetryCenter.emitBillingEvent(
            "Purchase revoked",
            severity: .warning,
            metadata: [
                "product": product.rawValue,
                "transactionId": String(transaction.id),
            ]
        )
    }

    private func upgradeTierIfNeeded(to tier: WorkspaceTier) {
        guard tierPriority(tier) > tierPriority(activeTier) else { return }
        activeTier = tier
    }

    private func promoteLegacyProtection(to state: LegacyProtectionState) {
        guard legacyProtectionPriority(state) > legacyProtectionPriority(legacyProtectionState) else { return }
        legacyProtectionState = state
    }

    private func legacyProtectionPriority(_ state: LegacyProtectionState) -> Int {
        switch state {
        case .none: return 0
        case .legacyDocumentPackOwner: return 1
        case .historicalPaidPurchase: return 2
        }
    }

    private func maxTier(_ lhs: WorkspaceTier, _ rhs: WorkspaceTier) -> WorkspaceTier {
        tierPriority(lhs) >= tierPriority(rhs) ? lhs : rhs
    }

    private func tierPriority(_ tier: WorkspaceTier) -> Int {
        switch tier {
        case .free: return 0
        case .pro: return 1
        case .lifetime: return 2
        }
    }

    private func recalculateAllowances() {
        pruneExpiredDocumentPacksIfNeeded()
        let snapshot = entitlementSnapshot
        documentLimit = snapshot.documentLimit
        libraryLimit = snapshot.libraryLimit

        switch snapshot.maximumModePolicy {
        case .unlimited:
            maximumModeRemainingUses = 0
        case let .meteredDaily(limit):
            maximumModeRemainingUses = maximumModeQuotaStore.currentState(limit: limit).remainingUses
        }
    }
}
