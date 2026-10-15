//
//  SavedEntitlementSnapshotTests.swift
//  OpenIntelligenceTests
//
//  An engine with no entitlement store, which is what a Shortcuts or Siri action builds while the app is closed,
//  reads the document limit from what the app's store last saved (`EntitlementStore.savedEntitlementSnapshot`,
//  5.7). Until 5.7 it used the free plan's limit, so Add to Library refused a Pro or Lifetime library of five
//  documents or more.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class SavedEntitlementSnapshotTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suite = "SavedEntitlementSnapshotTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNothingSavedIsTheFreePlan() {
        let saved = EntitlementStore.savedEntitlementSnapshot(defaults: defaults)
        XCTAssertEqual(saved.activeTier, .free)
        XCTAssertEqual(saved.documentLimit, QuotaPolicy.documentLimit(for: .free))
    }

    func testTheSavedPlanSetsTheLimit() {
        defaults.set(WorkspaceTier.pro.rawValue, forKey: "entitlement.activeTier")
        XCTAssertEqual(EntitlementStore.savedEntitlementSnapshot(defaults: defaults).documentLimit,
                       QuotaPolicy.documentLimit(for: .pro))
        defaults.set(WorkspaceTier.lifetime.rawValue, forKey: "entitlement.activeTier")
        XCTAssertTrue(EntitlementStore.savedEntitlementSnapshot(defaults: defaults).hasUnlimitedDocuments)
    }

    func testADocumentPackCountsUntilItExpires() throws {
        let live = #"[{"id":"\#(UUID().uuidString)","purchaseDate":0,"credits":25}]"#
        defaults.set(Data(live.utf8), forKey: "entitlement.docPackLedger")
        XCTAssertEqual(EntitlementStore.savedEntitlementSnapshot(defaults: defaults).documentLimit,
                       QuotaPolicy.documentLimit(for: .free) + 25, "a pack adds its credits")

        let expired = #"[{"id":"\#(UUID().uuidString)","purchaseDate":0,"credits":25,"expirationDate":0}]"#
        defaults.set(Data(expired.utf8), forKey: "entitlement.docPackLedger")
        XCTAssertEqual(EntitlementStore.savedEntitlementSnapshot(defaults: defaults).documentLimit,
                       QuotaPolicy.documentLimit(for: .free), "an expired pack adds nothing")
    }
}
