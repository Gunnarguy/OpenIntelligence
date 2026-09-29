//
//  PlanPriceComparisonTests.swift
//  OpenIntelligenceTests
//
//  Every comparison the plans screen prints is a claim about money, so each is pinned here at
//  the prices App Store Connect holds from 2026-10-01 (Docs/BILLING_AND_LIMITS.md §5), including
//  the storefronts where rounding makes the answer differ from the US one.
//

import XCTest

@testable import OpenIntelligence

final class PlanPriceComparisonTests: XCTestCase {
    // MARK: - Annual against twelve months of Monthly

    func testAnnualSavesFiftyEightPercentAtTheUSPrices() {
        // $24.99 against 12 x $4.99 = $59.88 is 58.27% off.
        XCTAssertEqual(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 4.99, annualPrice: 24.99), 58)
        // The prices before 2026-10-01 give the same figure: $29.99 against $71.88.
        XCTAssertEqual(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 5.99, annualPrice: 29.99), 58)
    }

    func testEachStorefrontIsToldItsOwnSavingRoundedDown() {
        // Mexico: 499 against 12 x 99 = 1188 is 57.99% off, which must read 57, not 58.
        XCTAssertEqual(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 99, annualPrice: 499), 57)
        // Japan: 4000 against 9600 is 58.33% off.
        XCTAssertEqual(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 800, annualPrice: 4000), 58)
    }

    func testNoSavingIsClaimedWhenAnnualIsNotCheaper() {
        XCTAssertNil(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 2, annualPrice: 24))
        XCTAssertNil(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 2, annualPrice: 30))
        XCTAssertNil(PlanPriceComparison.annualSavingsPercent(monthlyPrice: 0, annualPrice: 24.99))
        XCTAssertNil(PlanPriceComparison.annualSavingsPercent(monthlyPrice: -4.99, annualPrice: 24.99))
    }

    // MARK: - Annual per month

    private func currency(_ code: String, _ locale: String) -> Decimal.FormatStyle.Currency {
        Decimal.FormatStyle.Currency(code: code, locale: Locale(identifier: locale))
    }

    func testPerMonthRoundsUpSoItIsNeverCheaperThanTheRealPrice() {
        // $24.99 / 12 = $2.0825. Rounding to nearest would say $2.08, which understates it.
        XCTAssertEqual(PlanPriceComparison.perMonthText(annualPrice: 24.99, style: currency("USD", "en_US")), "$2.09")
        XCTAssertEqual(PlanPriceComparison.perMonthText(annualPrice: 29.99, style: currency("USD", "en_US")), "$2.50")
    }

    func testPerMonthRoundsInTheCurrencysOwnSmallestUnit() {
        // Yen have no minor unit: 4000 / 12 = 333.33 must read 334, not 333.
        XCTAssertEqual(PlanPriceComparison.perMonthText(annualPrice: 4000, style: currency("JPY", "en_US")), "¥334")
        // An exact division is not pushed up a cent.
        XCTAssertEqual(PlanPriceComparison.perMonthText(annualPrice: 12, style: currency("USD", "en_US")), "$1.00")
    }

    func testPerMonthSaysNothingForNonsense() {
        XCTAssertNil(PlanPriceComparison.perMonthText(annualPrice: 0, style: currency("USD", "en_US")))
        XCTAssertNil(PlanPriceComparison.perMonthText(annualPrice: -24.99, style: currency("USD", "en_US")))
    }

    // MARK: - Lifetime against a year of Monthly

    func testLifetimeCostsLessThanAYearOfMonthlyAtEveryRecordedPrice() {
        // Lifetime and Pro Monthly from 2026-10-01, per Docs/BILLING_AND_LIMITS.md §5.
        let prices: [(String, Decimal, Decimal)] = [
            ("USD", 49.99, 4.99), ("GBP", 49.99, 4.99), ("EUR", 59.99, 5.99), ("CAD", 69.99, 6.99),
            ("AUD", 79.99, 7.99), ("INR", 4999, 499), ("JPY", 8000, 800), ("BRL", 299.90, 29.90),
            ("MXN", 999, 99),
        ]
        for (code, lifetime, monthly) in prices {
            XCTAssertTrue(
                PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: lifetime, monthlyPrice: monthly),
                "\(code): \(lifetime) should be less than 12 x \(monthly)"
            )
        }
    }

    func testLifetimeClaimIsWithheldWhenItIsNotTrue() {
        // Exactly twelve months is not "less than a year". Built from strings: a float literal
        // reaches Decimal through Double, so `59.88` is 59.8799... and `4.99 * 12` is 59.8800...,
        // which made this very assertion fail on its first run. StoreKit's prices are exact
        // Decimals, so the app compares exactly; only literals in a test can drift.
        XCTAssertFalse(
            PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(
                lifetimePrice: Decimal(string: "59.88")!, monthlyPrice: Decimal(string: "4.99")!))
        // The price before the launch sale against the old Monthly: 59.99 < 71.88 was true.
        XCTAssertTrue(PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: 59.99, monthlyPrice: 5.99))
        // A Lifetime price above a year of Monthly says nothing.
        XCTAssertFalse(
            PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: 99.99, monthlyPrice: 4.99))
        XCTAssertFalse(PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: 49.99, monthlyPrice: 0))
        XCTAssertFalse(PlanPriceComparison.lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: 0, monthlyPrice: 4.99))
    }
}
