# Docs/BILLING_AND_LIMITS.md — verified at v4.4, shipped tree is v4.9

> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30. Product identifiers and the Document Pack status re-checked against source on 2026-08-05; the quota and grandfathering sections were **not** re-verified.
> **Document Pack Add-On is no longer sold (see §3).** `doc_pack_addon` is absent from `OpenIntelligence/Resources/StoreKit/StoreKitConfiguration.storekit` and has no paywall UI. The `BillingProduct.documentPackAddOn` case, the cap logic, and the `legacyDocumentPackOwner` protection state are deliberately retained so existing owners keep their capacity. `StoreKitBillingService` still requests the id via `BillingProduct.allCases`, and StoreKit simply omits an unavailable product from the result, so nothing fails. `[evidence_level: code_verified, confidence: exact, evidence_source: StoreKitConfiguration.storekit, BillingProduct.swift, PlanUpgradeSheet.swift, StoreKitBillingService.swift:42]`
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.

This document describes the billing tiers, StoreKit 2 product identifiers, and resource quota boundaries as audited in the OpenIntelligence v4.4 codebase.

---

## 1. Product Identifier Register

These StoreKit product IDs are defined centrally in [BillingProduct.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Billing/BillingProduct.swift):

| Product Identifier | rawValue | Kind | Associated Tier | Description |
|---|---|---|---|---|
| Pro Monthly | `"pro_monthly"` | Subscription | Pro | Grants monthly access to Pro features. |
| Pro Annual | `"pro_annual"` | Subscription | Pro | Grants annual access to Pro features. |
| Lifetime Cohort | `"lifetime_cohort"` | Non-Consumable | Lifetime | One-time purchase for permanent Lifetime access. |
| Document Pack Add-On | `"doc_pack_addon"` | Consumable | None | **Discontinued — not sold.** Granted 10 extra document slots per pack. Enum case and entitlement logic retained for existing owners only. |

---

## 2. Resource Quotas & Limits

Enforcement logic is defined in [QuotaPolicy.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift) and checked in [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Billing/EntitlementStore.swift) at runtime before document ingestion or library creation.

### Quota Matrix by Tier

| Feature / Resource | Free Tier | Pro Tier | Lifetime Tier |
|---|---|---|---|
| **Document Limit** | 5 documents | 1,000 documents | Unlimited |
| **Library Limit** | 1 library | 10 libraries | 20 libraries |
| **Maximum Mode Runs** | 3 per day (Metered) | Unlimited | Unlimited |
| **Standard Mode Runs** | Unlimited | Unlimited | Unlimited |
| **Deep Think Runs** | Unlimited | Unlimited | Unlimited |

---

## 3. Document Pack Add-On Mechanics (discontinued product, retained for existing owners)

> The pack was withdrawn from sale in v4.4. Nothing below describes a purchase a new user can make; it describes how the app continues to honour packs bought before the withdrawal. Read every "purchase" below as "a historical purchase being re-validated."

- **Allowance:** A `"doc_pack_addon"` transaction appends a ledger entry containing 10 credits to `documentPacks`.
- **Enforcement Cap:** Users are capped at a maximum of **3 active document packs** simultaneously (yielding a maximum bonus of +30 documents). The property `hasReachedDocumentPackCap` in [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Billing/EntitlementStore.swift#L48) gates purchases if `addOnPacks >= 3`.
- **Expiration:** Consumable packs are verified against transaction expiration dates. Expired packs are pruned on app launch via `pruneExpiredDocumentPacksIfNeeded()`.

---

## 4. Entitlement Reconciliation & Legacy Protection
- **Grandfathering Protection:** A sticky paid-history protection state (`LegacyProtectionState`) is implemented. If a user has a historical paid transaction (subscription or non-consumable), [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/Billing/EntitlementStore.swift#L356) promotes their state to `.historicalPaidPurchase` or `.legacyDocumentPackOwner` on launch. This maintains their Lifetime access and protects their active document limits even if their StoreKit subscription has expired or is unrenewed.
- **Local Simulation:** In `DEBUG` simulator builds, the app supports simulated billing overrides using `simulateDebugPurchase(_:)` to bypass StoreKit connection failures.
