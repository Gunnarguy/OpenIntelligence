# Docs/BILLING_AND_LIMITS.md — verified at v4.4, quota matrix re-verified at v5.3

> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30. Product identifiers and the Document Pack status re-checked against source on 2026-08-05. **The §2 quota matrix was re-read against source on 2026-09-20 and every figure matches**; the grandfathering rule in §4 changed for 5.5 on 2026-09-29 (only a Lifetime purchase, or a subscription begun before 2026-09-30, earns permanent protection), and §4 gives the lines; until 2026-09-29 this line said §4 was **not** re-verified. Shipped and in-development versions are not restated here: `Docs/SHIPPED_VERSION.json` is the per-platform record, because a version written into this header goes stale with each release. Corrected 2026-09-29; from 2026-09-22 this line said 5.3 was shipped and 5.4 open, which stopped being true when 5.4 went live on both platforms on 2026-09-24. `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.4, preparing 5.5, updated 2026-09-28; its 2026-09-24 note records both platforms READY_FOR_SALE); git blame of this line (8378a3e, 2026-09-22)]`
> **Document Pack Add-On is no longer sold (see §3).** `doc_pack_addon` is absent from `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit` and has no paywall UI. The `BillingProduct.documentPackAddOn` case, the cap logic, and the `legacyDocumentPackOwner` protection state are deliberately retained so existing owners keep their capacity. `StoreKitBillingService` still requests the id via `BillingProduct.allCases`, and StoreKit simply omits an unavailable product from the result, so nothing fails. `[evidence_level: code_verified, confidence: exact, evidence_source: StoreKitConfiguration.storekit, BillingProduct.swift, PlanUpgradeSheet.swift, StoreKitBillingService.swift:42]`
> **Source of truth:** The code. The codebase audit this line used to cite, in `Docs/AUDIT/`, is not in the repository (`Docs/AUDIT/` is gitignored).

This document describes the billing tiers, StoreKit 2 product identifiers, and resource quota boundaries as audited in the OpenIntelligence v4.4 codebase.

---

> **Correction, 2026-09-22.** The free tier's three Maximum runs a day were documented and displayed but never
> consumed: the store's `consumeIfAllowed` had no caller from 2026-05-12 until 5.4. From 5.4, `ChatScreen.sendMessage`
> spends a run before dispatch and the blocked state shows the existing dialog. Every figure in the matrix below was
> true as a limit and false as an enforcement for that period. `[evidence_level: test_verified, confidence: exact]`

## 1. Product Identifier Register

These StoreKit product IDs are defined centrally in [BillingProduct.swift](../OpenIntelligence/Services/Billing/BillingProduct.swift):

| Product Identifier | rawValue | Kind | Associated Tier | Description |
|---|---|---|---|---|
| Pro Monthly | `"pro_monthly"` | Subscription | Pro | Grants monthly access to Pro features. |
| Pro Annual | `"pro_annual"` | Subscription | Pro | Grants annual access to Pro features. |
| Lifetime (reference name Lifetime Cohort) | `"lifetime_cohort"` | Non-Consumable | Lifetime | One-time purchase for permanent Lifetime access. Customers see "Lifetime" from 5.5 (2026-09-29); the product identifier is unchanged. |
| Document Pack Add-On | `"doc_pack_addon"` | Consumable | None | **Discontinued — not sold.** Granted 10 extra document slots per pack. Enum case and entitlement logic retained for existing owners only. |

---

## 2. Resource Quotas & Limits

Enforcement logic is defined in [QuotaPolicy.swift](../OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift) and checked in [EntitlementStore.swift](../OpenIntelligence/Services/Billing/EntitlementStore.swift) at runtime before document ingestion or library creation.

### Quota Matrix by Tier

| Feature / Resource | Free Tier | Pro Tier | Lifetime Tier |
|---|---|---|---|
| **Document Limit** | 5 documents | 1,000 documents | Unlimited |
| **Library Limit** | 1 library | 10 libraries | 20 libraries |
| **Maximum Mode Runs** | 3 per day (Metered) | Unlimited | Unlimited |
| **Standard Mode Runs** | Unlimited | Unlimited | Unlimited |
| **Deep Think Runs** | Unlimited | Unlimited | Unlimited |
| **Private Cloud Compute** | Available, consent-gated, on iOS/macOS 27 | Same | Same |

Every row is read directly from `QuotaPolicy.swift`, and the Maximum-mode row from the snapshot builder in `EntitlementStore.swift`, which grants `.unlimited` to any tier other than `.free` and `.meteredDaily(QuotaPolicy.freeMaximumModeDailyLimit)` to Free. Pro is a **1,000-document, 10-library** tier, not an unlimited one; only Lifetime carries unlimited documents, and its library ceiling is 20. `[evidence_level: code_verified, confidence: exact, evidence_source: QuotaPolicy.swift freeDocumentLimit=5, proDocumentLimit=1_000, lifetimeDocumentLimit=.max, freeLibraryLimit=1, proLibraryLimit=10, lifetimeLibraryLimit=20, freeMaximumModeDailyLimit=3; EntitlementStore.buildSnapshot; read 2026-09-20]`

### What each plan advertises, and the rule behind it

Rewritten 2026-09-18, after ninety days of App Store Connect data (`~/ASC`) showed that the buyers
are people who decide within two days of download and that Lifetime carries 73% of proceeds on 29%
of purchases, while the paywall's bullets sold storage ("up to 1,000 documents", "10 libraries",
"expanded workspace limits") and said nothing about the model.

The rule: **a plan bullet may name only what that plan gates.** Deep Think and Private Cloud Compute
are free-tier features (the table above), so they may not appear as Pro benefits; they appear in
the sheet's story slides as what every plan includes. The one model feature a paid plan gates is
Maximum mode, which is `QuotaPolicy.freeMaximumModeDailyLimit` runs a day on Free and uncapped on
Pro and Lifetime, so that is the first bullet of every paid plan. Capacity follows it. Prices are
never hardcoded in a tagline, because each storefront has its own and `displayPrice` is the source.

`[evidence_level: code_verified, confidence: exact, evidence_source: PlanUpgradeSheet.swift planOptions and storySlides; QuotaPolicy.swift; EntitlementStore.swift maximumModePolicy; ~/ASC store_purchases and sub_state_analytics through 2026-09-14]`

### What each plan says against the others (5.5)

Added 2026-09-29, with the prices that take effect on 2026-09-30 and 2026-10-01. Each card compares
itself with the others in the customer's own currency, from StoreKit's live prices, and says nothing
until both products it compares have loaded in one currency; the US fallback prices never feed a
comparison.

| Card | Label beside the name | Under the price |
|---|---|---|
| Pro (Monthly) | Month to month | nothing; it is what the others are measured against |
| Pro (Annual) | none | "Save N% vs Monthly", N rounded down (58 at $4.99 and $24.99, 57 in Mexico); "$X a month, billed yearly", rounded up in the currency's smallest unit ($2.09, ¥334) |
| Lifetime | Pay once | "Less than a year of Monthly" when its price is below twelve Monthly payments; "Pays for itself against Pro Annual in N months" |

Everything computed sits below the billed price and is smaller than it. Apple: "the amount that will
be billed must be the most prominent pricing element in the layout", and a per-month breakdown or a
saving against another plan "should be displayed in a subordinate position and size to the annual
price". The arithmetic is `PlanPriceComparison`, pinned by `PlanPriceComparisonTests`.

Win-back offers are not shown on this screen. Showing and charging them there needs
`StoreKitBillingService.swift`, which this route forbids without the owner naming it, and on
2026-09-29 he chose to leave it: StoreKit shows its own win-back sheet in the iPhone and iPad app by
default when the App Store sends a win-back message (`Message` is unavailable on macOS), and the
offers can be redeemed in the App Store and in Subscription settings on every platform.
`[evidence_level: code_verified, confidence: exact, evidence_source: PlanUpgradeSheet.swift dealBadge(for:), comparisons(for:), livePrices; PlanPriceComparison.swift; https://developer.apple.com/app-store/subscriptions/ "Billing amount" and https://developer.apple.com/documentation/storekit/supporting-win-back-offers-in-your-app, both fetched 2026-09-29; StoreKit.swiftinterface in the macOS 27 SDK, Message marked unavailable on macOS]`

---

## 3. Document Pack Add-On Mechanics (discontinued product, retained for existing owners)

> The pack was withdrawn from sale in v4.4. Nothing below describes a purchase a new user can make; it describes how the app continues to honour packs bought before the withdrawal. Read every "purchase" below as "a historical purchase being re-validated."

- **Allowance:** A `"doc_pack_addon"` transaction appends a ledger entry containing 10 credits to `documentPacks`.
- **Enforcement Cap:** Users are capped at a maximum of **3 active document packs** simultaneously (yielding a maximum bonus of +30 documents). The property `hasReachedDocumentPackCap` in [EntitlementStore.swift](../OpenIntelligence/Services/Billing/EntitlementStore.swift#L48) gates purchases if `addOnPacks >= 3`.
- **Expiration:** Consumable packs are verified against transaction expiration dates. Expired packs are pruned on app launch via `pruneExpiredDocumentPacksIfNeeded()`.

---

## 4. Entitlement Reconciliation & Legacy Protection
- **Grandfathering Protection:** A sticky paid-history protection state (`LegacyProtectionState`) resolves the effective tier to Lifetime whatever the current StoreKit tier (`EntitlementStore.swift:205`, `:267`). **Changed for 5.5 on 2026-09-29.** Only two things earn `.historicalPaidPurchase` now, through `EntitlementStore.protectionEarned(by:originalPurchaseDate:isRevoked:)` (`:242`): a Lifetime purchase (`lifetime_cohort`), and a Pro subscription whose original purchase date is before 2026-09-30 00:00 UTC (`subscriptionProtectionCutoff`, `:235`). A subscription that begins later gives Pro while it is active and nothing permanent, and a refunded transaction earns nothing. The launch reconcile ([EntitlementStore.swift](../OpenIntelligence/Services/Billing/EntitlementStore.swift#L384)), the StoreKit history scan for a new device or reinstall (`:441`) and each purchase or restore (`:575`) all apply that one rule. Protection already stored on a device is never lowered.
  - **Why the cutoff:** through 5.4 every paid purchase earned the protection, a free trial included, so a month of Pro, or a trial that never converted, became Lifetime for good. The owner decided on 2026-09-29 that people who got it that way keep it; see `Docs/ai/DECISIONS.md`, 2026-09-29. Whether a subscription that lapses and is bought again keeps its first original purchase date is not verified; Apple documents that `originalID` stays the same across renewals and restores.
  - **Still true:** `.legacyDocumentPackOwner`, for owners of the discontinued Document Pack (§3), also resolves to Lifetime; a refund does not clear protection that was already stored (`handleRevocation`, `:600`).
  `[evidence_level: code_verified, confidence: exact, evidence_source: EntitlementStore.swift:205, 235, 242-258, 267, 384-425, 441-464, 575-590, 600; MonetizationPolicy.swift:22-27; EntitlementProtectionTests (8 tests); Transaction.originalPurchaseDate in the Xcode 27 iOS StoreKit swiftinterface; developer.apple.com/documentation/storekit/transaction/originalid, read 2026-09-29]`
- **Local Simulation:** In `DEBUG` builds, on a device as well as in the simulator, the app supports simulated billing overrides using `simulateDebugPurchase(_:)` to bypass StoreKit connection failures (corrected 2026-09-29: this said simulator builds; the gate is `#if DEBUG` alone, `EntitlementStore.swift:430-491`).

---

## 5. Promotional pricing and the launch sale

*Added 2026-09-09.*

### Where a sale is announced, and where it is not

Three places, all reading the same `LaunchSale.offer`, which returns nothing unless StoreKit's live
price is genuinely below the recorded regular price in the customer's currency and the date is
inside the window: the plans sheet (since 5.2), the `LaunchSaleBanner` at the top of the Chat and
Documents tabs for the free tier (5.3), and the App Store promotional text, which is set by API on
the live version and is the only one of the three that a human has to take down when the sale
ends; the metadata history carries the text to restore. No countdown, no "only N left", no
pre-selected plan: the discount is real and the copy says the real number and the real last day.

The Lifetime card also states its price in months of Pro Annual (`LaunchSale.monthsOfAnnual`,
2026-09-18): StoreKit's live prices for the customer's storefront, never the hardcoded US
fallbacks, rounded down, nil until both products have loaded. At the sale price ($39.99 against
$29.99) that reads 16 months; on 2026-09-30 ($49.99 against $29.99), 20; from 2026-10-01 ($49.99
against $24.99), 24. It is the comparison a buyer is already making, done with the
store's own numbers.

### Regular prices, as App Store Connect holds them

Only the USA price is set by hand. Apple generates the other 174 storefronts from it, and those
generated figures are what customers actually pay, so they are read from the API rather than
converted.

**Changed 2026-09-30.** The owner set the standing Lifetime price to $49.99 on 2026-09-29, effective the day the
launch sale ended, so the price went from the $39.99 sale straight to $49.99. It was $59.99 before the sale (59.99 GBP,
69.99 EUR, 79.99 CAD, 99.99 AUD, 5900 INR, 10000 JPY, 399.90 BRL, 1299 MXN). The Lifetime column below is Apple's
equalization of the $49.99 price point, read before the write; Pro Annual is unchanged. The schedule written was
`[null to 2026-09-30] 39.99` and `[2026-09-30 to null] 49.99`, read back identical, and the schedule it replaced is
`.sale-snapshots/20260929T192514Z-pre-lifetime-4999.json` (`scripts/schedule_sale.py --restore <that file> --confirm`
undoes it). Before the next sale, set `REGULAR_PRICE` in `scripts/schedule_sale.py` and
`LaunchSale.regularLifetimePrices` to these prices; the script refuses to write while its constant says 59.99, and the
single-amount-per-currency property below has not been re-checked for the new price point. **Done 2026-09-29 for
5.5:** both now hold these prices (`REGULAR_PRICE = 49.99`), and `scripts/verify_sale_prices.py` reported every
recorded currency matching the schedule's open-ended $49.99 interval, with no currency carrying two prices across the
28 territories it checks. **That was not enough.** Read across all 175 territories the same day, the
$49.99 point does not resolve to one price per currency: USD is 49.99 in 87 territories and 59.99 in 22 (ALB ARM AZE BEN BLR BRB CIV CMR COG GEO GHA ISL KEN MAR MDA MUS NPL SEN UGA UKR ZMB ZWE),
and EUR is 59.99 in 24 and 49.99 in one (MNE). `LaunchSale` keys by currency, so in a future sale window Montenegro
would be told its regular EUR 49.99 was reduced from EUR 59.99. No build is exposed, because the only window closed on
2026-09-30 and a new sale needs a new build. Before the next sale, key the table by territory or leave USD and EUR out,
and make `scripts/verify_sale_prices.py` read every territory rather than its 28.
`[evidence_level: measured, confidence: exact, evidence_source: open-ended rows of /v1/inAppPurchasePriceSchedules/6756638872/automaticPrices and manualPrices, 175 territories, grouped by /v1/territories currency, 2026-09-29]`
`[evidence_level: measured, confidence: exact, evidence_source: POST /v1/inAppPurchasePriceSchedules and GET .../manualPrices, 2026-09-29 12:25 PT; /v1/inAppPurchasePricePoints/<49.99 USA>/equalizations]`

**Changed 2026-10-01, subscriptions.** On 2026-09-29 the owner scheduled Pro Annual at $24.99 (was $29.99) and Pro
Monthly at $4.99 (was $5.99) from 2026-10-01, in App Store Connect's price editor, which recalculated every storefront
from the US price: Annual goes down in 161 storefronts and Monthly in 166, none goes up, and the rest keep their current
price. Existing subscribers renew at the lower price; Apple offers no way to preserve a higher one. The columns below
are the scheduled 2026-10-01 prices read back from the API. At these prices Annual is 5.0 times Monthly, as before, so
the saving stays 58% where both prices moved together. Through 5.4 the paywall hardcoded that figure as a bullet; from
5.5 it is computed per storefront (§2, "What each plan says against the others"). The local
`StoreKitConfiguration.storekit`, which only Xcode and the simulator read, carries the same US prices from 2026-09-29
at the owner's word: $4.99, $24.99 and $49.99, Lifetime named "Lifetime", the product descriptions App Store Connect
has in review, and no introductory offer (App Store Connect lists none on either subscription, read the same day).
Loaded in a StoreKit test session on the iOS 27 simulator, it returned exactly those three prices. The annual win-back offer is now $14.99 for the first year
(`winback_annual_2026_1499`, 2026-10-01 to 2027-10-01, every storefront). The $19.99 offer it replaces cannot be ended
through the API while live (HTTP 409) and stays until 2027-09-24; App Store Connect states that where offers overlap
"the best offer will be shown". The monthly win-back ($2.99 a month for three months) is unchanged.
`[evidence_level: measured, confidence: exact, evidence_source: GET /v1/subscriptions/{id}/prices per territory and /v1/subscriptions/6756638919/winBackOffers, read 2026-09-29 after the changes; App Store Connect price-change confirmation screens]`

| Currency | Lifetime | Pro Annual | Pro Monthly |
|---|---|---|---|
| USD | 49.99 | 24.99 | 4.99 |
| GBP | 49.99 | 24.99 | 4.99 |
| EUR (Germany) | 59.99 | 29.99 | 5.99 |
| CAD | 69.99 | 34.99 | 6.99 |
| AUD | 79.99 | 39.99 | 7.99 |
| INR | 4999 | 2499 | 499 |
| JPY | 8000 | 4000 | 800 |
| BRL | 299.90 | 149.90 | 29.90 |
| MXN | 999 | 499 | 99 |

For the $59.99 schedule (corrected 2026-09-29: not for the $49.99 one, see above): across all 177 generated Lifetime
territory prices, every currency resolves to exactly one
amount, which is what makes `LaunchSale` safe to key by currency rather than territory. That is
a property of this price schedule and not a guarantee from Apple, so
`scripts/verify_sale_prices.py` re-checks it and reports drift.
`[evidence_level: measured, confidence: exact, evidence_source: /v1/inAppPurchasePriceSchedules/6756638872/automaticPrices (177 rows) and /v1/subscriptions/6756638919/prices (175 rows), grouped by currency, read 2026-09-09]`

US proceeds are a flat 85% of list under the Small Business Program, which the price point
records show directly. The **blended** net across all territories is lower, 66.4%, because
several storefronts quote VAT-inclusive prices that Apple remits. Use 66.4% for revenue
forecasts and 85% only for US-only questions.
`[evidence_level: measured, confidence: exact, evidence_source: proceeds field on USA price points (85%); SUM(proceeds_usd)/SUM(sales_usd) over the ten Lifetime rows in store_purchases, ~/ASC/data/asc.sqlite3, 2026-09-09. That archive is not version-controlled, so the figure is reproducible only while it exists.]`

### How a discount is delivered, and why the app has to announce it

A non-consumable cannot have a "sale" in the App Store sense. The only mechanism is a
**temporary price change**, which App Store Connect accepts with a start and an end date and
reverts on its own; the maximum length is one year.
`[evidence_level: documented, confidence: exact, evidence_source: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/schedule-price-changes-for-in-app-purchases, fetched 2026-09-09]`

**The App Store shows no strikethrough, no "was/now" and no sale badge for in-app purchases.** A
customer during a price change simply sees a smaller number. The discount therefore does not
exist as a discount unless the app says so, which is what `LaunchSale` and the paywall banner
are for.

### What `LaunchSale` guarantees, and what it does not

`OpenIntelligence/Features/Billing/LaunchSale.swift` advertises nothing unless both hold:

1. `now` is inside `LaunchSale.window`.
2. StoreKit's reported price is strictly below the regular price recorded for Lifetime **in
   that customer's currency**.

Condition 2 means a price change that was never scheduled, never reached a storefront, or has
already reverted produces silence whatever the date says. The percentage comes from the two real
numbers, rounded **down**, so the saving is never overstated, and it is computed per storefront
because Apple rounds each territory to its own price point.

**The limit, stated plainly.** Condition 2 is not "a sale is running", it is "the price is below
a constant compiled into this build". Apple recalculates generated prices when tax and exchange
rates move, so a table recorded today can be wrong in six months and the app would then
advertise a discount nobody scheduled. Run `scripts/verify_sale_prices.py` before every sale.
Separately, `EntitlementStore` caches its products, so `PlanUpgradeSheet` refreshes them on
appear to keep the banner and the checkout price the same number.
`[evidence_level: code_verified, confidence: high, evidence_source: LaunchSale.swift offer(for:storeProduct:now:), PlanUpgradeSheet.swift .task, OpenIntelligenceTests/Features/Billing/LaunchSaleTests.swift]`

### Why only Lifetime is ever discounted

Pro Annual and Pro Monthly are deliberately excluded, for two independent reasons.

- **Pro Annual's 7-day free trial was withdrawn on 2026-09-18.** Ninety days of data: five trial
  starts, one converted to full price, two stuck in billing retry, one churned from the trial;
  Annual's proceeds for the period were $25 against Lifetime's $140. The app stopped advertising
  the trial that day (`PlanUpgradeSheet`), and the introductory offer, one per territory in App
  Store Connect, 175 in all, is removed by the owner (an agent's deletion was blocked by the
  harness). Until it is removed, the store's own purchase sheet still shows the trial; the app
  under-claims rather than over-claims in the meantime. Existing trialists are unaffected by the
  removal. **Done 2026-09-18:** all 175 per-territory offers were deleted through
  `DELETE /v1/subscriptionIntroductoryOffers/{id}`, verified by re-listing the subscription's
  `introductoryOffers` and getting zero. Pro Annual now has no introductory offer of any kind, so
  it could take one again in future; the reason below is why it still takes no sale.
- **A temporary price change on a subscription creates a price increase later.** When the price
  reverts, everyone who subscribed at the sale price faces an increase at renewal. Apple
  requires consent where a region demands it, where the increase exceeds 50% and about US$50 a
  year, or where the subscriber saw an increase in the last 12 months, and a subscriber who does
  not consent has the subscription expire at the end of the current cycle.

Lifetime is a non-consumable, so it reverts with no consequence for anyone who already bought.
It is also 83% of revenue, so restricting the sale to it costs almost nothing.
`[evidence_level: documented+measured, confidence: exact, evidence_source: GET /v1/subscriptions/{id}/introductoryOffers, 0 rows for pro_annual and pro_monthly, 2026-09-29 (the trial was withdrawn 2026-09-18; the local StoreKitConfiguration.storekit carried it until 2026-09-29); https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-pricing-for-auto-renewable-subscriptions/ and .../set-up-introductory-offers-for-auto-renewable-subscriptions/, fetched 2026-09-09; store_purchases revenue share]`

### One US price change is a different discount in every storefront

Apple rounds each territory to its own price ladder, so a single USA change from $59.99 to $39.99
does not land at 33% anywhere but the USA and the UK. Read from Apple's equalizations for the
$39.99 USA price point rather than converted:

| Territory | Regular | Sale | Off |
|---|---|---|---|
| Mexico | MX$1299 | MX$899 | 30% |
| India | ₹5900 | ₹3999 | 32% |
| USA, United Kingdom | 59.99 | 39.99 | 33% |
| Germany | €69.99 | €44.99 | 35% |
| Canada | CA$79.99 | CA$49.99 | 37% |
| Brazil | R$399.90 | R$249.90 | 37% |
| Australia, Japan | A$99.99, ¥10000 | A$59.99, ¥6000 | 40% |

This is why `LaunchSale.percentOff` computes per storefront from the customer's own two prices
instead of showing a single advertised figure, and why marketing copy that has to be true
everywhere says "a third off" rather than a percentage. 30% is the floor across these nine.
`[evidence_level: measured, confidence: exact, evidence_source: /v1/inAppPurchasePricePoints/<USA 39.99>/equalizations, 174 rows, read 2026-09-09]`

### Writing the price change: the schedule is replaced, not amended

There is no "add a price change" call. `POST /v1/inAppPurchasePriceSchedules` submits the
**entire** schedule, and the schedule is not a list of prices, it is a **partition of the
timeline**. Apple enforces that intervals do not intersect, that the timeline is covered with no
gaps, and that the rightmost interval has no end date.

A temporary sale is therefore **three** intervals, because the regular price has to hold both
the time before the sale and the time after it:

| Interval | Price | Role |
|---|---|---|
| `null` to start | 59.99 | open at the start of time |
| start to end | 39.99 | the sale |
| end to `null` | 59.99 | what it reverts to, open forever |

`[evidence_level: measured, confidence: exact, evidence_source: two HTTP 409 responses from POST /v1/inAppPurchasePriceSchedules, 2026-09-09. ENTITY_ERROR.INVALID_INTERVAL: "Adjacent intervals must not intersect for USA: [null - null] and [2026-09-15T00:00 - 2026-09-30T00:00]". ENTITY_ERROR.INVALID_END_DATE: "Entire timeline must be covered for USA. Rightmost interval must not have an end date". Apple's reference documents the field names but none of this.]`

The consequence for the guard in `schedule_sale.py`: the price that answers "what is the regular
price" is the **open-ended** interval, not the one with a null start. A sale is already
scheduled means the null-start interval is still the regular price but so is the tail, and it is
the tail that customers pay once the sale expires.

Two further things the error messages settle, which Apple's help pages do not. Inline entity ids
must be written `${local-id}` with literal braces, not as bare strings. And the intervals are
half-open: `[start, end)`, since adjacent intervals share a boundary date without intersecting.
So the end date is the day the price **reverts**, and the last day at the sale price is the day
before. `LaunchSale.deadlineText` names that day, which makes the advertised deadline exact
rather than approximate.
`[evidence_level: measured, confidence: high, evidence_source: same two 409 responses; the half-open reading is what makes "must not intersect" and "must be covered" simultaneously satisfiable for adjacent intervals sharing a date, and is confirmed by Apple accepting that shape]`

### Running a sale

1. `zsh -ic 'python3 scripts/verify_sale_prices.py'` and fix any drift it reports.
2. Set `LaunchSale.window` **before the build**, since it compiles into the binary:
   `scripts/schedule_sale.py --start ... --end ... --write-window`.
3. On release day, the same script with `--confirm` writes the temporary price change.

Step 1 is not optional; it is what keeps the struck-through price honest. `schedule_sale.py`
reads the live schedule first and refuses to write if the standing price is not what this repo
expects, or if a hand-set price exists outside the USA, because either would mean the submission
silently changes or deletes a real price. The full procedure with exact figures is
`Docs/Release/5.2/launch-sale.md`.

### Offer codes, for targeted discounts that leave the list price alone

Offer codes now cover consumables, non-consumables and non-renewing subscriptions, not just
auto-renewable ones, and promo codes for in-app purchases were retired on 2026-03-26. Limits: 10
active offers per app, up to 1,000,000 codes per app per quarter, one-time-use batches of 500 to
25,000, custom-code batches up to 25,000 redemptions, a maximum 6-month expiry, and one
redemption per customer per offer. An offer can be a discounted price rather than free.
`[evidence_level: documented, confidence: exact, evidence_source: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases/, fetched 2026-09-09]`

Prefer offer codes over a price change for win-back and targeted outreach: they never touch the
public price and each redemption is attributable.
