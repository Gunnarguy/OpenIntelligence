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
    case preview(remaining: Int)
    case blocked
}

struct LocalModelPreviewTicket {
    fileprivate let requiresConsumption: Bool
}

/// Tracks the currently active workspace tier and derived quotas.
@MainActor
final class EntitlementStore: ObservableObject {
    @Published private(set) var activeTier: WorkspaceTier
    @Published private(set) var documentLimit: Int
    @Published private(set) var libraryLimit: Int
    @Published private(set) var isLoading: Bool = true
    @Published var lastError: String?
    @Published private(set) var availableProducts: [BillingProduct: Product] = [:]
    @Published private(set) fileprivate var documentPacks: [DocumentPackEntry] = []
    @Published private(set) var localModelPreviewRemaining: Int
    private var previewRunsConsumed: Int
    private var previewConversionLoggedRuns: Int

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

    let billingService: BillingService
    private var eventTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private let maxAddOnPacks = 3

    private enum Keys {
        static let tier = "entitlement.activeTier"
        static let addOns = "entitlement.docAddOns"  // Legacy storage, retained for migration
        static let packs = "entitlement.docPackLedger"
        static let localPreviewRemaining = "entitlement.localPreviewRemaining"
        static let previewRunsConsumed = "entitlement.previewRunsConsumed"
        static let previewConversionRunMarker = "entitlement.previewConversionRuns"
    }

    private static let previewAllowance = 3

    init(billingService: BillingService, defaults: UserDefaults = .standard) {
        self.billingService = billingService
        self.defaults = defaults
        let storedTier = defaults.string(forKey: Keys.tier)
        let resolvedTier = WorkspaceTier(rawValue: storedTier ?? "") ?? .free
        self.activeTier = resolvedTier
        let loadedPacks = Self.loadDocumentPacks(from: defaults)
        let prunedPacks = Self.pruneExpiredPacks(loadedPacks)
        self.documentPacks = prunedPacks
        let documentCredits = Self.totalCredits(for: prunedPacks)
        self.documentLimit = QuotaPolicy.documentLimit(for: resolvedTier) + documentCredits
        self.libraryLimit = QuotaPolicy.libraryLimit(for: resolvedTier)
        let storedPreview = defaults.object(forKey: Keys.localPreviewRemaining) as? Int
        self.localModelPreviewRemaining = Self.initialPreviewAllowance(
            storedValue: storedPreview,
            tier: resolvedTier
        )
        self.previewRunsConsumed = defaults.integer(forKey: Keys.previewRunsConsumed)
        self.previewConversionLoggedRuns = defaults.integer(forKey: Keys.previewConversionRunMarker)
        eventTask = Task { await observeBillingEvents() }
        Task { await billingService.refreshProducts() }
        if prunedPacks.count != loadedPacks.count {
            persistDocumentPacks()
        }
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
        let migratedPacks = (0..<clamped).map { _ in
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

    private static func initialPreviewAllowance(storedValue: Int?, tier: WorkspaceTier) -> Int {
        if let storedValue {
            return max(0, storedValue)
        }
        return defaultPreviewAllowance(for: tier)
    }

    private static func defaultPreviewAllowance(for tier: WorkspaceTier) -> Int {
        tier == .free ? previewAllowance : 0
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

    private func persistPreviewState() {
        defaults.set(localModelPreviewRemaining, forKey: Keys.localPreviewRemaining)
        defaults.set(previewRunsConsumed, forKey: Keys.previewRunsConsumed)
        defaults.set(previewConversionLoggedRuns, forKey: Keys.previewConversionRunMarker)
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
                    "transactionId": String(transaction.id)
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
           let fallbackIndex = documentPacks.firstIndex(where: { !$0.isExpired }) {
            documentPacks.remove(at: fallbackIndex)
        }

        if documentPacks.count != originalCount {
            persistDocumentPacks()
        }
    }

    func canAddDocument(currentCount: Int) -> Bool {
        currentCount < documentLimit
    }

    func canAddLibrary(currentCount: Int) -> Bool {
        currentCount < libraryLimit
    }

    var localModelPreviewTotal: Int { Self.defaultPreviewAllowance(for: activeTier) }

    var canUseLocalModels: Bool {
        activeTier.isAtLeast(.pro) || localModelPreviewRemaining > 0
    }

    func localModelAccessState() -> LocalModelAccessState {
        if activeTier.isAtLeast(.pro) { return .unlocked }
        if localModelPreviewRemaining > 0 { return .preview(remaining: localModelPreviewRemaining) }
        return .blocked
    }

    func issueLocalModelPreviewTicket() -> LocalModelPreviewTicket? {
        if activeTier.isAtLeast(.pro) {
            return LocalModelPreviewTicket(requiresConsumption: false)
        }
        guard localModelPreviewRemaining > 0 else { return nil }
        return LocalModelPreviewTicket(requiresConsumption: true)
    }

    @discardableResult
    func consumeLocalModelPreviewIfNeeded(
        ticket: LocalModelPreviewTicket?,
        backend: ModelBackend
    ) -> Int? {
        guard let ticket, ticket.requiresConsumption else { return nil }
        guard localModelPreviewRemaining > 0 else { return nil }
        localModelPreviewRemaining -= 1
        previewRunsConsumed += 1
        persistPreviewState()
        let remaining = localModelPreviewRemaining
        TelemetryCenter.emitBillingEvent(
            "preview_model_used",
            metadata: [
                "backend": backend.rawValue,
                "remaining": String(remaining),
                "tier": activeTier.rawValue
            ]
        )
        if remaining == 0 {
            TelemetryCenter.emitBillingEvent(
                "preview_exhausted",
                metadata: [
                    "backend": backend.rawValue,
                    "tier": activeTier.rawValue
                ]
            )
        }
        return remaining
    }

    func markPreviewGateTriggered(for backend: ModelBackend) {
        TelemetryCenter.emitBillingEvent(
            "preview_gate_triggered",
            metadata: [
                "backend": backend.rawValue,
                "tier": activeTier.rawValue
            ]
        )
    }

    func product(for product: BillingProduct) -> Product? {
        availableProducts[product]
    }

    func setDebugTier(_ tier: WorkspaceTier) {
        let previousTier = activeTier
        activeTier = tier
        adjustPreviewAllowanceForTierChange(from: previousTier, to: tier)
        persistState()
        recalculateAllowances()
    }

    private func observeBillingEvents() async {
        for await event in billingService.events {
            handle(event)
        }
    }

    private func handle(_ event: BillingEvent) {
        switch event {
        case .productsLoaded(let mapping):
            availableProducts = mapping
        case .purchaseSucceeded(let product, let transaction):
            applyPurchase(for: product, transaction: transaction)
        case .transactionUpdated(let product, let transaction):
            if transaction.revocationDate != nil {
                handleRevocation(for: product, transaction: transaction)
            } else {
                applyPurchase(for: product, transaction: transaction)
            }
        case .purchaseFailed(_, let error):
            lastError = error.errorDescription
        case .userCancelled:
            lastError = nil
        case .pending:
            lastError = nil
        }
    }

    private func applyPurchase(for product: BillingProduct, transaction: Transaction) {
        if let tier = product.associatedTier {
            maybeTrackPreviewConversion(for: tier, product: product)
            upgradeTierIfNeeded(to: tier)
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
                "transactionId": String(transaction.id)
            ]
        )
    }

    private func handleRevocation(for product: BillingProduct, transaction: Transaction) {
        if product.associatedTier == activeTier {
            let previousTier = activeTier
            activeTier = .free
            adjustPreviewAllowanceForTierChange(from: previousTier, to: .free)
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
                "transactionId": String(transaction.id)
            ]
        )
    }

    private func upgradeTierIfNeeded(to tier: WorkspaceTier) {
        guard tierPriority(tier) > tierPriority(activeTier) else { return }
        let previousTier = activeTier
        activeTier = tier
        adjustPreviewAllowanceForTierChange(from: previousTier, to: tier)
    }

    private func tierPriority(_ tier: WorkspaceTier) -> Int {
        switch tier {
        case .free: return 0
        case .starter: return 1
        case .pro: return 2
        case .lifetime: return 3
        }
    }

    private func persistState() {
        defaults.set(activeTier.rawValue, forKey: Keys.tier)
        defaults.set(addOnPacks, forKey: Keys.addOns)
        persistDocumentPacks()
        persistPreviewState()
    }

    private func recalculateAllowances() {
        pruneExpiredDocumentPacksIfNeeded()
        let baseLimit = QuotaPolicy.documentLimit(for: activeTier)
        documentLimit = baseLimit + availableDocumentCredits
        libraryLimit = QuotaPolicy.libraryLimit(for: activeTier)
        if activeTier.isAtLeast(.pro) && localModelPreviewRemaining != 0 {
            localModelPreviewRemaining = 0
            persistPreviewState()
        }
    }

    private func adjustPreviewAllowanceForTierChange(
        from previousTier: WorkspaceTier,
        to newTier: WorkspaceTier
    ) {
        guard previousTier != newTier else { return }
        if newTier.isAtLeast(.pro) && localModelPreviewRemaining != 0 {
            localModelPreviewRemaining = 0
            persistPreviewState()
        }
    }

    private func maybeTrackPreviewConversion(for tier: WorkspaceTier, product: BillingProduct) {
        guard tier.isAtLeast(.pro) else { return }
        guard previewRunsConsumed > previewConversionLoggedRuns else { return }
        previewConversionLoggedRuns = previewRunsConsumed
        persistPreviewState()
        TelemetryCenter.emitBillingEvent(
            "preview_to_paid",
            metadata: [
                "product": product.rawValue,
                "tier": tier.rawValue,
                "preview_runs": String(previewRunsConsumed)
            ]
        )
    }
}
