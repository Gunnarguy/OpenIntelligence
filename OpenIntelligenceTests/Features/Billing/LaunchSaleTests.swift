//
//  LaunchSaleTests.swift
//  OpenIntelligenceTests
//
//  `LaunchSale.percentOff` is the only arithmetic in this app that turns into a public claim
//  about money, so it is pinned here rather than trusted.
//
//  The `Product`-taking entry point cannot be reached from a unit test, because StoreKit
//  products cannot be constructed outside a StoreKitTest session. The percentage maths and the
//  refusals are split out precisely so they can be tested without one.
//

import XCTest

@testable import OpenIntelligence

final class LaunchSaleTests: XCTestCase {
    // MARK: - The saving is never overstated

    func testRoundsTheSavingDownRatherThanToNearest() {
        // 100 -> 67.40 is 32.6% off. Advertising 33% would overstate it.
        XCTAssertEqual(LaunchSale.percentOff(regular: 100, live: 67.40), 32)
        // 100 -> 67.99 is 32.01% off.
        XCTAssertEqual(LaunchSale.percentOff(regular: 100, live: 67.99), 32)
    }

    func testTheShippingPriceReportsThirtyThreePercent() {
        // The pair this release actually plans to run.
        XCTAssertEqual(LaunchSale.percentOff(regular: 59.99, live: 39.99), 33)
    }

    func testEveryRecordedCurrencyProducesAPlausiblePercentageAtAThirdOff() {
        // A third off each recorded regular price should land in the high twenties or low
        // thirties in every currency. Anything outside that means a table entry is wrong by
        // an order of magnitude, which is the failure mode that would fabricate a discount.
        for (currency, regular) in LaunchSale.regularLifetimePrices {
            let approximateSalePrice = regular * 0.67
            let percent = LaunchSale.percentOff(regular: regular, live: approximateSalePrice)
            XCTAssertNotNil(percent, "\(currency) produced no percentage at a third off")
            if let percent {
                XCTAssertTrue(
                    (30...36).contains(percent),
                    "\(currency): a third off computed as \(percent)%, which is not a third"
                )
            }
        }
    }

    // MARK: - Refusals

    func testSaysNothingWhenThePriceHasNotActuallyDropped() {
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: 59.99), "equal prices are not a discount")
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: 69.99), "a higher price is not a discount")
    }

    func testSaysNothingForASavingBelowOnePercent() {
        // 59.99 -> 59.95 is 0.07% off. Rounding down gives 0, which is not worth a claim.
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: 59.95))
    }

    func testSaysNothingForNonsenseInput() {
        XCTAssertNil(LaunchSale.percentOff(regular: 0, live: 0), "a zero regular price cannot be discounted")
        XCTAssertNil(LaunchSale.percentOff(regular: -10, live: -20), "negative regular price")
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: -1), "negative live price")
        XCTAssertNil(LaunchSale.percentOff(regular: .nan, live: 39.99), "NaN must not trap")
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: .nan), "NaN must not trap")
    }

    func testSaysNothingForAFreeProduct() {
        // 100% off a paid product means something has gone wrong upstream rather than that a
        // sale is running, so the app stays quiet rather than advertising a free purchase.
        XCTAssertNil(LaunchSale.percentOff(regular: 59.99, live: 0))
    }

    // MARK: - The recorded price table

    func testEveryRecordedCurrencyIsAPlausibleAmount() {
        XCTAssertFalse(LaunchSale.regularLifetimePrices.isEmpty)
        for (currency, price) in LaunchSale.regularLifetimePrices {
            XCTAssertEqual(currency.count, 3, "\(currency) is not an ISO 4217 code")
            XCTAssertEqual(currency, currency.uppercased(), "\(currency) should be uppercase")
            XCTAssertTrue(price > 0, "\(currency) has a non-positive regular price")
        }
    }

    func testUSDRegularPriceMatchesTheListedPrice() {
        // If this ever fails, either the App Store price changed permanently or the table is
        // stale. Both mean the banner is about to misstate a saving. Re-run
        // scripts/verify_sale_prices.py before changing this number.
        XCTAssertEqual(LaunchSale.regularLifetimePrices["USD"], 59.99)
    }

    // MARK: - The window

    func testWindowIsOrderedAndNotOpenForever() {
        guard let window = LaunchSale.window else { return }
        XCTAssertLessThan(window.start, window.end)
        XCTAssertLessThan(
            window.duration, 60 * 60 * 24 * 90,
            "a launch sale open for more than 90 days is not a launch sale"
        )
    }

    func testDeadlineTextNamesTheLastFullDayRatherThanTheDayItExpires() {
        // The window ends at midnight on the 30th, so the last day a customer can buy is the
        // 29th. Naming the 30th would promise a day that does not exist.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        guard let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30)) else {
            return XCTFail("could not build the test date")
        }
        XCTAssertEqual(LaunchSale.deadlineText(for: end), "September 29")
    }

    // MARK: - Lifetime in months of Pro Annual

    func testMonthsOfAnnual_atTheSalePrice_isSixteen() {
        XCTAssertEqual(LaunchSale.monthsOfAnnual(lifetimePrice: 39.99, annualPricePerYear: 29.99), 16)
    }

    func testMonthsOfAnnual_atTheRegularPrice_isTwentyFour() {
        XCTAssertEqual(LaunchSale.monthsOfAnnual(lifetimePrice: 59.99, annualPricePerYear: 29.99), 24)
    }

    func testMonthsOfAnnual_roundsDown_andRefusesNonsense() {
        XCTAssertEqual(LaunchSale.monthsOfAnnual(lifetimePrice: 35, annualPricePerYear: 30), 14)
        XCTAssertNil(LaunchSale.monthsOfAnnual(lifetimePrice: 0, annualPricePerYear: 29.99))
        XCTAssertNil(LaunchSale.monthsOfAnnual(lifetimePrice: 39.99, annualPricePerYear: 0))
        XCTAssertNil(LaunchSale.monthsOfAnnual(lifetimePrice: 1, annualPricePerYear: 100))
    }
}
