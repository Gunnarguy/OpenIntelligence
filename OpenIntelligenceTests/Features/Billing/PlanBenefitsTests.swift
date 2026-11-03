//
//  PlanBenefitsTests.swift
//  OpenIntelligenceTests
//
//  What the plans screen says each plan adds. The rule in `Docs/BILLING_AND_LIMITS.md`: a plan bullet may
//  name only what that plan gates, and Maximum mode comes first.
//

import XCTest

@testable import OpenIntelligence

final class PlanBenefitsTests: XCTestCase {
    func testEveryPaidPlanLeadsWithMaximumMode() {
        XCTAssertEqual(PlanBenefits.pro.first, "Maximum mode with no daily cap")
        XCTAssertEqual(PlanBenefits.lifetime.first, "Maximum mode with no daily cap")
        XCTAssertEqual(PlanBenefits.highlights.first?.text, "Maximum mode with no daily cap")
    }

    /// The figures are read from `QuotaPolicy`, so a changed limit changes this test's result and the plan
    /// bullet with it, rather than leaving the screen stale.
    func testTheLimitsStatedAreThePolicy() {
        XCTAssertTrue(PlanBenefits.pro.contains("Up to 1,000 documents"))
        XCTAssertTrue(PlanBenefits.pro.contains("10 libraries"))
        XCTAssertTrue(PlanBenefits.lifetime.contains("20 libraries"))
        XCTAssertTrue(PlanBenefits.lifetime.contains("Unlimited documents"))
        XCTAssertEqual(QuotaPolicy.proDocumentLimit, 1_000)
        XCTAssertEqual(QuotaPolicy.proLibraryLimit, 10)
        XCTAssertEqual(QuotaPolicy.lifetimeLibraryLimit, 20)
    }

    /// Deep Think and Private Cloud Compute are in every plan, so they may not read as a paid benefit.
    func testNoBulletSellsWhatEveryPlanHas() {
        let bullets = PlanBenefits.pro + PlanBenefits.lifetime + PlanBenefits.highlights.map(\.text)
        for free in ["Deep Think", "Private Cloud Compute", "Apple Intelligence"] {
            XCTAssertFalse(bullets.contains { $0.contains(free) }, free)
        }
    }

    /// iCloud Sync is paid, and goes on the cards when the two-device check on its roadmap row passes.
    /// This fails on the day it is added, as a reminder to confirm that check closed.
    func testICloudSyncWaitsForTheTwoDeviceCheck() {
        let bullets = PlanBenefits.pro + PlanBenefits.lifetime + PlanBenefits.highlights.map(\.text)
        XCTAssertFalse(bullets.contains { $0.contains("iCloud") })
    }
}
