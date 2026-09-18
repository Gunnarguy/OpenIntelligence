//
//  LaunchSale.swift
//  OpenIntelligence
//
//  Whether a launch discount is being advertised right now, and what the price was before it.
//
//  WHY THIS FILE EXISTS
//
//  StoreKit reports only what a product costs at this moment. There is no API for a previous
//  price, and the App Store draws no strikethrough, no "was/now" and no sale badge for in-app
//  purchases. A scheduled temporary price change is therefore invisible to the customer: they
//  see a smaller number with no way to know it is a discount or that it ends. The app has to
//  say so itself, which means the app has to hold the regular price.
//
//  WHAT GUARDS THE CLAIM
//
//  A hardcoded "was" price is a factual claim about money, so two conditions must both hold:
//
//    1. `now` is inside `window`.
//    2. StoreKit's reported price is strictly below the regular price recorded here, compared
//       within the same currency.
//
//  Condition 2 does the work. If the temporary price change was never scheduled or has already
//  reverted, the price is not lower and nothing is claimed whatever the calendar says.
//
//  THE LIMIT OF THAT GUARANTEE, STATED PLAINLY
//
//  Condition 2 is not "a sale is running". It is "the price is below a constant compiled into
//  this build". Apple recalculates its generated per-territory prices when tax rates and
//  exchange rates move, so a regular price recorded today can be higher than the real one in
//  six months, and the app would then advertise a discount nobody scheduled. The table is
//  therefore dated, and `scripts/verify_sale_prices.py` re-reads it from App Store Connect and
//  reports any drift. Run it before every sale. This is a real limitation, not a theoretical one.
//
//  Two further limits worth knowing:
//    - `EntitlementStore` caches its `Product` list, so a price change cancelled mid-session is
//      not seen until the products are refreshed. `PlanUpgradeSheet` refreshes on appear.
//    - The percentage is computed per storefront from the two real numbers and rounded down,
//      because Apple rounds each territory to its own price point. A German customer may
//      genuinely see 28% where a US customer sees 33%, and each is told their own number.
//
//  WHY LIFETIME ONLY
//
//  Pro Annual is deliberately absent. Until 2026-09-18 its 7-day free trial was its one
//  introductory offer, and a customer may redeem only one per subscription group, so a discount
//  offer would have displaced the trial. The trial was withdrawn on 2026-09-18 (five starts in
//  ninety days, one paid, two stuck in billing retry); the app stopped advertising it the same day,
//  and the App Store Connect offer is removed by the owner. What still keeps Annual out of a sale is
//  the second reason: a temporary price change on a subscription is worse still, because the revert is
//  a price increase for everyone who subscribed at the sale price, which Apple surfaces through
//  consent prompts and, where consent is required and not given, ends the subscription. Lifetime
//  is a non-consumable, so it reverts with no consequence for anyone who already bought.
//  [evidence_level: code_verified, confidence: exact, evidence_source: StoreKitConfiguration.storekit
//  pro_annual introductoryOffer; https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/
//  and .../set-up-introductory-offers-for-auto-renewable-subscriptions/, fetched 2026-09-09]
//

import Foundation
import StoreKit

/// A discount the app is prepared to state, in the customer's own currency.
struct LaunchSaleOffer: Equatable {
    /// The pre-sale price, formatted in the customer's currency, e.g. "$59.99".
    let regularDisplayPrice: String
    /// Whole percent off, computed from the live and regular prices and rounded down.
    let percentOff: Int
    /// When the advertised window closes, for the deadline line.
    let endDate: Date
}

enum LaunchSale {
    // MARK: - The window

    /// The advertised sale period, or `nil` when no sale is planned.
    ///
    /// These dates must match the temporary price change in App Store Connect. They are UTC
    /// instants; App Store Connect schedules in Pacific time, so leave slack rather than
    /// matching to the minute.
    ///
    /// The two ends are not symmetric, because this value is compiled in and the price change is
    /// not. The window is fixed when the binary is built; the price change can be rescheduled
    /// afterwards. So:
    ///
    ///   - `end` must equal the price change's end date in App Store Connect. It is not itself
    ///     shown: `deadlineText` names the day before, because the window closes at midnight at
    ///     the start of `end`. That is exact rather than approximate. App Store Connect's
    ///     intervals are half-open, `[start, end)`, so the end date is the day the price
    ///     **reverts** and the last day at the sale price is the day before it. A later `end`
    ///     would promise days that are charged at full price.
    ///     [evidence_level: measured, confidence: high, evidence_source: POST
    ///     /v1/inAppPurchasePriceSchedules rejects overlapping intervals and requires the
    ///     timeline be covered, which only holds for adjacent intervals sharing a boundary date
    ///     if the boundary belongs to the later one, 2026-09-09]
    ///   - `start` may sit **earlier** than the price change with no harm. Condition 2 keeps the
    ///     banner silent until the price actually drops, so an early start simply absorbs a
    ///     review that takes longer than expected.
    ///
    /// `scripts/schedule_sale.py --write-window` writes both from the same pair of dates.
    ///
    /// Set for the iOS and macOS 27 launch alongside 5.2. Change both dates when the real
    /// dates are known. See `Docs/Release/5.2/launch-sale.md`.
    static let window: DateInterval? = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        guard
            let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)),
            let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30))
        else { return nil }
        return DateInterval(start: start, end: end)
    }()

    // MARK: - Regular prices, per currency

    /// Pre-sale customer prices for Lifetime Cohort, keyed by ISO currency code.
    ///
    /// Read from App Store Connect on **2026-09-09**, not converted. Only the USA price is set
    /// by hand; Apple generates the other 174 storefronts, and those generated figures are what
    /// customers actually pay.
    ///
    /// Keying by currency rather than territory is safe **because it was checked**: across all
    /// 177 generated territory prices, every currency resolves to exactly one amount. That is a
    /// property of this price schedule, not a guarantee from Apple, and
    /// `scripts/verify_sale_prices.py` re-checks it.
    ///
    /// A currency absent from this table yields no offer and no banner, which is the correct
    /// failure: silence rather than a figure converted at a rate Apple did not use.
    ///
    /// [evidence_level: measured, confidence: exact, evidence_source:
    /// /v1/inAppPurchasePriceSchedules/6756638872/automaticPrices, 177 territory rows grouped by
    /// currency, 2026-09-09; USA base price from the same schedule's manualPrices]
    static let regularLifetimePrices: [String: Decimal] = [
        "USD": 59.99, "GBP": 59.99, "EUR": 69.99, "CAD": 79.99, "AUD": 99.99,
        "INR": 5900, "JPY": 10000, "BRL": 399.90, "MXN": 1299,
    ]

    /// The date the price table above was read from App Store Connect, for the drift check.
    static let pricesVerifiedOn = "2026-09-09"

    // MARK: - The money math, isolated so it can be tested

    /// Whole percent off, rounded **down** so the app never overstates a saving.
    ///
    /// Returns `nil` unless there is a real, representable discount of at least one percent.
    /// Rejects non-finite input rather than trapping in the `Int` conversion.
    static func percentOff(regular: Decimal, live: Decimal) -> Int? {
        guard regular.isFinite, live.isFinite else { return nil }
        guard regular > 0, live >= 0, live < regular else { return nil }

        let fraction = (regular - live) / regular * 100
        guard fraction.isFinite else { return nil }

        let percent = Int((fraction as NSDecimalNumber).doubleValue.rounded(.down))
        guard percent >= 1, percent <= 99 else { return nil }
        return percent
    }

    // MARK: - The one question this type answers

    /// The discount to advertise for `product`, or `nil` to say nothing at all.
    ///
    /// `storeProduct` must be the StoreKit product for `product`; the identifiers are checked
    /// rather than trusted, so a mismatched pair yields `nil` instead of comparing one
    /// product's price against another's regular price.
    static func offer(
        for product: BillingProduct,
        storeProduct: Product,
        now: Date = Date()
    ) -> LaunchSaleOffer? {
        guard product == .lifetimeCohort else { return nil }
        guard storeProduct.id == product.rawValue else { return nil }
        guard let window, window.contains(now) else { return nil }

        let currency = storeProduct.priceFormatStyle.currencyCode
        guard let regular = regularLifetimePrices[currency] else { return nil }
        guard let percent = percentOff(regular: regular, live: storeProduct.price) else { return nil }

        return LaunchSaleOffer(
            regularDisplayPrice: regular.formatted(storeProduct.priceFormatStyle),
            percentOff: percent,
            endDate: window.end
        )
    }

    /// The deadline for the banner, e.g. "September 30".
    ///
    /// Rendered in the window's own timezone rather than the device's, so a customer in Hawaii
    /// is not told the sale ends a day earlier than everyone else is told.
    /// How many months of Pro Annual the Lifetime price buys, rounded down, or nil when the
    /// arithmetic has nothing to stand on. True at the sale price and at the regular one; the
    /// paywall shows it under the Lifetime card so the comparison a buyer is already making in
    /// their head is done for them with the store's own numbers.
    static func monthsOfAnnual(lifetimePrice: Decimal, annualPricePerYear: Decimal) -> Int? {
        guard lifetimePrice > 0, annualPricePerYear > 0 else { return nil }
        let months = (lifetimePrice / annualPricePerYear * 12) as NSDecimalNumber
        let n = Int(months.doubleValue.rounded(.down))
        return n >= 1 ? n : nil
    }

    static func deadlineText(for endDate: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? .gmt
        // The window ends at midnight on the end date, so the last full day is the day before.
        let lastDay = calendar.date(byAdding: .day, value: -1, to: endDate) ?? endDate
        var style = Date.FormatStyle.dateTime.month(.wide).day()
        style.timeZone = calendar.timeZone
        return lastDay.formatted(style)
    }
}
