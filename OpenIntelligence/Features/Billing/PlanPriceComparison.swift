//
//  PlanPriceComparison.swift
//  OpenIntelligence
//
//  The comparisons the plans screen prints under each price: what Pro Annual saves against
//  twelve months of Pro Monthly, what Annual works out to per month, and whether Lifetime costs
//  less than a year of Monthly.
//
//  Each one is a claim about money, so each follows the rules `LaunchSale` follows for the sale
//  strip:
//
//    - The caller passes StoreKit's live prices for the customer's own storefront, never the
//      paywall's hardcoded US fallbacks, so a customer in Germany is told the German saving.
//    - Percentages round down and per-month figures round up, so neither overstates the deal.
//    - A missing, zero or non-finite input yields nothing rather than something approximate.
//
//  WHERE THEY MAY APPEAR
//
//  Apple: "In the purchase flow, the amount that will be billed must be the most prominent
//  pricing element in the layout", and a per-month breakdown or a saving against another plan
//  "should be displayed in a subordinate position and size to the annual price". So the billed
//  price keeps the card's title font, and everything computed here renders below it, smaller.
//  [evidence_level: artifact_derived, confidence: exact, evidence_source:
//  https://developer.apple.com/app-store/subscriptions/ "Billing amount", fetched 2026-09-29]
//

import Foundation

enum PlanPriceComparison {
    /// Whole percent Pro Annual saves against twelve months of Pro Monthly, rounded down, or nil
    /// when there is no real saving to state.
    ///
    /// The arithmetic is `LaunchSale.percentOff`, so this badge and the sale strip round and
    /// refuse in exactly the same way. At $4.99 and $24.99 it is 58.
    static func annualSavingsPercent(monthlyPrice: Decimal, annualPrice: Decimal) -> Int? {
        guard monthlyPrice.isFinite, monthlyPrice > 0 else { return nil }
        return LaunchSale.percentOff(regular: monthlyPrice * 12, live: annualPrice)
    }

    /// Pro Annual's price spread over twelve months and formatted in the customer's currency,
    /// rounded **up** in that currency's smallest unit (cents, whole yen) so the figure is never
    /// lower than what the customer actually pays: $24.99 a year reads "$2.09", not "$2.08".
    static func perMonthText(annualPrice: Decimal, style: Decimal.FormatStyle.Currency) -> String? {
        guard annualPrice.isFinite, annualPrice > 0 else { return nil }
        return (annualPrice / 12).formatted(style.rounded(rule: .up))
    }

    /// True only when Lifetime costs less than twelve months of Pro Monthly, which is what the
    /// Lifetime card's "Less than a year of Monthly" badge claims.
    static func lifetimeCostsLessThanAYearOfMonthly(lifetimePrice: Decimal, monthlyPrice: Decimal) -> Bool {
        guard lifetimePrice.isFinite, monthlyPrice.isFinite, lifetimePrice > 0, monthlyPrice > 0 else {
            return false
        }
        return lifetimePrice < monthlyPrice * 12
    }
}
