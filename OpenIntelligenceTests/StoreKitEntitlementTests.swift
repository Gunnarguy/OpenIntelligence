@testable import OpenIntelligence
import XCTest

@MainActor
final class StoreKitEntitlementTests: XCTestCase {
    func testPreviewTicketsDecrementUntilBlocked() async {
        let defaults = UserDefaults(suiteName: "entitlement-tests-")!
        defaults.removePersistentDomain(forName: "entitlement-tests-")
        let billing = MockBillingService()
        let store = EntitlementStore(billingService: billing, defaults: defaults)

        XCTAssertEqual(store.localModelPreviewRemaining, 3)
        XCTAssertTrue(store.canUseLocalModels)

        let ticket1 = store.issueLocalModelPreviewTicket()
        let remainingAfterFirst = store.consumeLocalModelPreviewIfNeeded(ticket: ticket1, backend: .gguf)
        XCTAssertEqual(remainingAfterFirst, 2)

        _ = store.consumeLocalModelPreviewIfNeeded(ticket: store.issueLocalModelPreviewTicket(), backend: .gguf)
        let remainingFinal = store.consumeLocalModelPreviewIfNeeded(ticket: store.issueLocalModelPreviewTicket(), backend: .gguf)
        XCTAssertEqual(remainingFinal, 0)
        switch store.localModelAccessState() {
        case .blocked:
            break
        default:
            XCTFail("Expected local models to be blocked after consuming all previews")
        }
    }

    func testProTierUnlocksLocalModelsWithoutConsumption() async {
        let defaults = UserDefaults(suiteName: "entitlement-tests-pro-")!
        defaults.removePersistentDomain(forName: "entitlement-tests-pro-")
        let billing = MockBillingService()
        let store = EntitlementStore(billingService: billing, defaults: defaults)

        store.setDebugTier(.pro)
        XCTAssertEqual(store.localModelPreviewRemaining, 0)
        switch store.localModelAccessState() {
        case .unlocked:
            break
        default:
            XCTFail("Pro tier should unlock local models without preview consumption")
        }

        let ticket = store.issueLocalModelPreviewTicket()
        XCTAssertNotNil(ticket)
        let consumed = store.consumeLocalModelPreviewIfNeeded(ticket: ticket, backend: .gguf)
        XCTAssertNil(consumed)
    }

    func testDocumentLimitReflectsTier() async {
        let defaults = UserDefaults(suiteName: "entitlement-tests-tier-")!
        defaults.removePersistentDomain(forName: "entitlement-tests-tier-")
        let billing = MockBillingService()
        let store = EntitlementStore(billingService: billing, defaults: defaults)

        XCTAssertEqual(store.documentLimit, QuotaPolicy.documentLimit(for: .free))
        store.setDebugTier(.starter)
        XCTAssertEqual(store.documentLimit, QuotaPolicy.documentLimit(for: .starter))
        store.setDebugTier(.pro)
        XCTAssertEqual(store.documentLimit, QuotaPolicy.documentLimit(for: .pro))
        store.setDebugTier(.lifetime)
        XCTAssertEqual(store.documentLimit, QuotaPolicy.documentLimit(for: .lifetime))
    }
}
