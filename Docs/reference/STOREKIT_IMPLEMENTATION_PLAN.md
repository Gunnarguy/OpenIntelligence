# StoreKit Monetization Implementation Plan

_Last updated: 2025-11-14_

This plan consolidates the readiness memo, pricing strategy, and the November 13, 2025 App Review guideline revisions so we can wire up StoreKit without surprises. It should stay in lock-step with `APP_READINESS_MEMO.md`, `PRICING_STRATEGY.md`, and our App Store Connect configuration.

---

## 1. Inputs & Regulatory Baselines

| Source | Highlights we must honor |
| --- | --- |
| `APP_READINESS_MEMO.md` | Ship StoreKit configuration for `starter_monthly`, `pro_monthly`, `pro_annual`, `lifetime_cohort`, `doc_pack_addon`; enforce quotas before billing launches. |
| `PRICING_STRATEGY.md` | Tier constraints: Free (10 docs), Starter (40 docs, 3 containers), Pro (unlimited), Lifetime (limited launch), Add-on packs (+25 docs each). |
| [App Review Guidelines (Nov 13 2025)](https://developer.apple.com/app-store/review/guidelines/) | Section 3.1.1 (all digital unlocks via IAP), 3.1.2 (subscriptions need clear value + disclosure), 3.2.2(ix) (loan APR cap), 4.1(c) (no third-party icons), 5.1.2(i) (disclose any third-party AI data sharing). No external purchase calls except entitlements allowed in specific storefronts (not planned). |
| [Updated Guidelines News Note (Nov 13 2025)](https://developer.apple.com/news/?id=ey6d8onl) | Adds creator age gating (1.2.1(a)), reiterates privacy disclosures for AI/crypto services. Our plan keeps creator content inside the app, so age labels must remain accurate when we surface paywalls.
| [Auto-renewable subscriptions guide](https://developer.apple.com/app-store/subscriptions/) | Requires clear sign-up copy (price, duration, content), `showManageSubscriptions(in:)` entry point, restored purchases, and optional win-back + promotional offers support. Reminder: 85% proceeds after 1 year and 800 base price points (plus 100 high tiers). |

> **Consent reminder:** App Review §5.1 requires privacy policy + Terms links _inside the paywall_ once monetization lands. Copy lives in Settings today; we must add them to the modal, too.

---

## 2. SKU & Pricing Matrix

| SKU | Product Type | Apple price tier (USD) | Default allowance | Notes |
| --- | --- | --- | --- | --- |
| `starter_monthly` | Auto-renewable | Subscription Tier S3 ($2.99) | 40 docs, 3 containers, basic rerank sliders, weekly rerank refresh | Entry plan. Offer pay-as-you-go add-on for burst. |
| `pro_monthly` | Auto-renewable | Subscription Tier S9 ($8.99) | Unlimited docs/containers, advanced retrieval controls, automation hooks, high-priority ingestion | Attach telemetry for automation usage to justify value. |
| `pro_annual` | Auto-renewable | Subscription Tier S69 ($89.99) | Same as Pro monthly, marketed as "$89/yr" in copy | Annual SKU will include 7-day free trial using StoreKit introductory offer API. |
| `lifetime_cohort` | Non-consumable | Price Tier 60 ($59.99) for launch cohort | Unlimited docs (on-device inference only), Core ML cartridge access, no team sharing | Mark as limited availability; hide from paywall once capacity hits target. |
| `doc_pack_addon` | Consumable (+25 docs) | Tier 5 ($4.99) | Adds to whichever tier is active | Ensure consumable credits respect `3 ×` stack cap and sync with telemetry.

Future SKUs (not part of this sprint): `starter_annual`, enterprise seat packs.

---

## 3. Architecture Overview

```
StoreKitConfiguration.storekit (products)
          │
          ▼
 StoreKitBillingService (actor)
          │  subscribes to → Transaction.updates, Product.SubscriptionInfo
          │  publishes → BillingEvent
          ▼
   EntitlementStore (MainActor ObservableObject)
          │  exposes tier, quotas, feature flags, purchase state, grace periods
          ▼
  UI + Services
    • DocumentLibraryView → dynamic quota banners + upgrade CTA
    • RAGService.ingest → checks EntitlementStore instead of hard-coded QuotaPolicy
    • SettingsRootView/About → displays plan, Manage Subscriptions, restore
    • PaywallView → shows tiers, Terms/Privacy links, purchase buttons
```

### 3.1 BillingService responsibilities
- Load `Product` instances once per launch using StoreKit 2.
- Surface strongly typed purchase APIs (buy subscription, buy consumable, restore purchases).
- Listen to `Transaction.updates` and `Transaction.currentEntitlements` for background upgrades or revocations.
- Prevent duplicate purchases (e.g., `doc_pack_addon` limited to 3 active credits).
- Emit analytics via `TelemetryCenter` for App Store Small Business Program metrics.

### 3.2 EntitlementStore responsibilities
- Track `WorkspaceTier`, `documentLimit`, `libraryLimit`, and feature switches (advanced rerank, automation, number of fallback models, etc.).
- Persist snapshot to disk (e.g., in `UserDefaults` or lightweight file) so gating survives relaunch.
- Provide `@Published` state for SwiftUI surfaces (quota banners, paywall copy, Settings summary).
- Integrate BillingService by reacting to `BillingEvent` stream (purchase success, failure, pending, revoked, grace period, price increase pending, win-back offer available).
- Manage consumable credits ledger for `doc_pack_addon` (store purchase date, remaining credits, expiration policy).

### 3.3 UI surfaces to update
1. **DocumentLibraryView**
   - Replace `QuotaPolicy.documentLimit()` with `entitlementStore.documentLimit`.
   - Display upgrade CTAs when usage >= 80% of limit.
   - Show `doc_pack_addon` redemption banner when quota hits 100% and user is Starter.
2. **Paywall / QuotaEducationSheet**
   - Convert to full-screen cover that shows tier cards, features, price, and `buy` buttons.
   - Include Terms of Use + Privacy Policy links (App Review §3.1.2(c)).
   - Provide `Manage Subscription` and `Restore Purchases` buttons (StoreKit requirement).
3. **SettingsRootView / About**
   - Add plan summary row with renewal date (use `Product.SubscriptionInfo.Status.renewalInfo`).
   - Provide `Contact Support` & refund guidance per `APP_READINESS_MEMO` §5.
4. **RAGService / ingestion**
   - Swap direct calls to `QuotaPolicy` for `EntitlementStore.canAddDocument(count:)` to ensure gating and telemetry line up.
5. **TelemetryDashboard**
   - Log paywall views, purchase attempts, and quota hits via `TelemetryCenter.emitBillingEvent` so readiness memo §6 metrics stay in sync.

---

## 4. Implementation Phases

| Phase | Scope | Notes |
| --- | --- | --- |
| 1. Configuration groundwork | Add `StoreKitConfiguration.storekit` file with the 5 SKU definitions, update build settings to bundle it for previews/tests, and document App Store Connect parity checklist. | Satisfies readiness memo Action #1. |
| 2. Billing scaffolding | Introduce `BillingService` protocol + `StoreKitBillingService` implementation, `BillingEvent` enum, and `BillingError`. Add unit tests using `StoreKitTest` and local config file. | Keep functions concise (≤50 lines) and document tricky flows (per repo instructions). |
| 3. Entitlements + quotas | Build `EntitlementStore` and replace `QuotaPolicy` usages. Ensure `DocumentQuotaError` surfaces upgrade CTA. Include placeholder tiers for Starter/Pro until live purchases succeed. | Required so ingestion limits and paywall CTAs stay truthful pre-launch. |
| 4. UI & telemetry | Update DocumentLibraryView, SettingsRootView, paywall surfaces, and add `TelemetryCategory.billing` events (`Purchase initiated`, `Purchase succeeded`, `Purchase failed`, `Restore applied`, `Quota hit`). | Blocks release until telemetry dashboard shows subscription funnel health. |
| 5. Validation | Run `xcodebuild -scheme OpenIntelligence -destination "platform=iOS Simulator,name=iPhone 17 Pro Max" build` plus StoreKit unit tests. Update `APP_REVIEW_CHECKLIST.md` and `smoke_test.md` with monetization steps. |

---

## 5. Compliance Checklist

- **3.1.1 / 3.1.2**: All upgrades, doc packs, and lifetime unlock happen through StoreKit. Paywall copy will list duration, renewal price, benefits, and include Restore + Manage buttons.
- **Before you submit**: Document reviewer credentials (demo Apple ID) plus sample purchase steps inside `APP_REVIEW_NOTES_TEMPLATE.md`.
- **Privacy (5.1)**: Update Privacy Policy section to describe billing data handling and mention that purchase receipts stay on-device except for App Store validation. No third-party processors used.
- **Kids / age gating (1.2.1(a))**: Current metadata (productivity, 12+) remains accurate; paywall must not imply content targeting kids.
- **External purchase links**: None planned; ensures compliance with 3.1.1(a) restrictions.
- **Data disclosures (5.1.2(i))**: Mention that we do _not_ share subscription data with third-party AI; telemetry is aggregated and anonymized.
- **Family Sharing**: Decide whether to enable for Starter/Pro (default off). If enabled, add copy describing sharing per subscription guide.
- **Win-back offers**: Plan to leverage new win-back offer placement after MVP lands (phase 6). Requires App Store Connect config + copy updates.

---

## 6. Open Questions / Next Decisions

1. **Trials**: Should Starter also have a free trial, or do we reserve trials for Pro annual only? (Impacts `Product.SubscriptionOffer.Signature` support.)
2. **Lifetime SKU availability**: Do we hide the button once internal quota is met, or gate behind promo codes?
3. **Consumable UX**: Where do we surface remaining doc-pack credits (Settings? Banner? Both?).
4. **Billing grace period**: App Store Connect supports 3/16/28 day grace windows. Which aligns with our quota enforcement + compute costs?

Answer these before we ship the billing scaffolding PR to avoid rework.

---

_Keep this plan updated as implementation progresses. When a phase completes, link to the corresponding PR/commit and update the App Store submission docs._
