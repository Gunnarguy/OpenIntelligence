//
//  RedeemCodeOutcomeTests.swift
//  OpenIntelligenceTests
//
//  The plans sheet presents Apple's offer-code sheet. These pin what the app says and does with
//  what comes back: a redeemed code is said, a closed or cancelled sheet says nothing, a failure
//  gives its reason, and the entitlements are read again only after a redemption Apple handed back.
//

import StoreKit
import XCTest

@testable import OpenIntelligence

@MainActor
final class RedeemCodeOutcomeTests: XCTestCase {
    func testOnlyARedeemedCodeAndAFailureSaySomething() {
        XCTAssertEqual(RedeemCodeOutcome.redeemed.message, "Your code was redeemed.")
        XCTAssertNil(RedeemCodeOutcome.closed.message)
        XCTAssertNil(RedeemCodeOutcome.cancelled.message)
        XCTAssertEqual(
            RedeemCodeOutcome.failed("That code has expired.").message,
            "The code was not redeemed. That code has expired.")
    }

    func testEntitlementsAreReadAgainOnlyAfterARedemptionAppleHandedBack() {
        XCTAssertTrue(RedeemCodeOutcome.redeemed.readsEntitlementsAgain)
        // iOS 26: the older call does not say whether a code was redeemed, so nothing is re-read;
        // a redeemed transaction arrives through the listener purchases use.
        XCTAssertFalse(RedeemCodeOutcome.closed.readsEntitlementsAgain)
        XCTAssertFalse(RedeemCodeOutcome.cancelled.readsEntitlementsAgain)
        XCTAssertFalse(RedeemCodeOutcome.failed("x").readsEntitlementsAgain)
    }

    func testACancelledSheetIsNotAFailure() {
        XCTAssertEqual(RedeemCodeOutcome(error: StoreKitError.userCancelled), .cancelled)
        let other = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No connection."])
        XCTAssertEqual(RedeemCodeOutcome(error: other), .failed("No connection."))
    }
}
