import XCTest

@testable import OpenIntelligence

/// Pins which purchases earn the sticky protection that resolves to Lifetime.
///
/// Through 5.4 every paid purchase earned it, a free trial included, so a month of Pro, or a trial
/// that never converted, became Lifetime for good. On 2026-09-29 the owner decided that people who
/// got it that way keep it, and that from then on only a Lifetime purchase earns it.
final class EntitlementProtectionTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    private var cutoff: Date { EntitlementStore.subscriptionProtectionCutoff }
    private var dayBeforeCutoff: Date { cutoff.addingTimeInterval(-86_400) }
    private var dayAfterCutoff: Date { cutoff.addingTimeInterval(86_400) }

    override func setUp() {
        super.setUp()
        suiteName = "EntitlementProtectionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testCutoffIsTheStartOf30September2026InUTC() {
        XCTAssertEqual(ISO8601DateFormatter().string(from: cutoff), "2026-09-30T00:00:00Z")
    }

    func testLifetimePurchaseEarnsProtectionWheneverItWasMade() {
        for date in [dayBeforeCutoff, dayAfterCutoff] {
            XCTAssertEqual(
                EntitlementStore.protectionEarned(by: .lifetimeCohort, originalPurchaseDate: date, isRevoked: false),
                .historicalPaidPurchase
            )
        }
    }

    func testSubscriptionOrTrialStartedFromTheCutoffOnEarnsNothing() {
        for product in [BillingProduct.proMonthly, .proAnnual] {
            XCTAssertNil(EntitlementStore.protectionEarned(by: product, originalPurchaseDate: cutoff, isRevoked: false))
            XCTAssertNil(
                EntitlementStore.protectionEarned(by: product, originalPurchaseDate: dayAfterCutoff, isRevoked: false)
            )
        }
    }

    func testSubscriptionOrTrialStartedBeforeTheCutoffKeepsItsProtection() {
        for product in [BillingProduct.proMonthly, .proAnnual] {
            XCTAssertEqual(
                EntitlementStore.protectionEarned(by: product, originalPurchaseDate: dayBeforeCutoff, isRevoked: false),
                .historicalPaidPurchase
            )
        }
    }

    func testRefundedTransactionEarnsNothing() {
        for product in [BillingProduct.lifetimeCohort, .proMonthly, .proAnnual] {
            XCTAssertNil(
                EntitlementStore.protectionEarned(by: product, originalPurchaseDate: dayBeforeCutoff, isRevoked: true)
            )
        }
    }

    func testDocumentPackIsNotGrandfatheredThroughThisPath() {
        XCTAssertNil(
            EntitlementStore.protectionEarned(by: .documentPackAddOn, originalPurchaseDate: dayBeforeCutoff, isRevoked: false)
        )
    }

    func testProtectionAlreadyStoredStillResolvesToLifetime() {
        defaults.set(WorkspaceTier.free.rawValue, forKey: "entitlement.activeTier")
        defaults.set(LegacyProtectionState.historicalPaidPurchase.rawValue, forKey: "entitlement.legacyProtectionState")

        XCTAssertEqual(EntitlementStore.currentEffectiveTier(defaults: defaults), .lifetime)
    }

    func testActiveProWithoutProtectionStaysPro() {
        defaults.set(WorkspaceTier.pro.rawValue, forKey: "entitlement.activeTier")
        defaults.set(LegacyProtectionState.none.rawValue, forKey: "entitlement.legacyProtectionState")

        XCTAssertEqual(EntitlementStore.currentEffectiveTier(defaults: defaults), .pro)
        XCTAssertEqual(EntitlementStore.currentLibraryLimit(defaults: defaults), 10)
    }
}
