# Docs/BILLING_AND_LIMITS.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.

This document describes the billing tiers, StoreKit 2 product identifiers, and resource quota boundaries defined and enforced in the OpenIntelligence v4.1 codebase.

---

## 1. Product Identifier Register

I define these StoreKit product IDs centrally in [BillingProduct.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Billing/BillingProduct.swift):

| Product Identifier | rawValue | Kind | Associated Tier | Description |
|---|---|---|---|---|
| Pro Monthly | `"pro_monthly"` | Subscription | Pro | Grants monthly access to Pro features. |
| Pro Annual | `"pro_annual"` | Subscription | Pro | Grants annual access to Pro features. |
| Lifetime Cohort | `"lifetime_cohort"` | Non-Consumable | Lifetime | One-time purchase for permanent Lifetime access. |
| Document Pack Add-On | `"doc_pack_addon"` | Consumable | None | Grants 10 extra document slots per pack. |

---

## 2. Resource Quotas & Limits

Enforcement logic is defined in [QuotaPolicy.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift) and checked in [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Billing/EntitlementStore.swift) at runtime before document ingestion or library creation.

### Quota Matrix by Tier

| Feature / Resource | Free Tier | Pro Tier | Lifetime Tier |
|---|---|---|---|
| **Document Limit** | 5 documents | 1,000 documents | Unlimited |
| **Library Limit** | 1 library | 10 libraries | 20 libraries |
| **Maximum Mode Runs** | 3 per day (Metered) | Unlimited | Unlimited |
| **Standard Mode Runs** | Unlimited | Unlimited | Unlimited |
| **Deep Think Runs** | Unlimited | Unlimited | Unlimited |

---

## 3. Document Pack Add-On Mechanics
- **Allowance:** Purchasing `"doc_pack_addon"` appends a ledger entry containing 10 credits to `documentPacks`.
- **Enforcement Cap:** Users are capped at a maximum of **3 active document packs** simultaneously (yielding a maximum bonus of +30 documents). The property `hasReachedDocumentPackCap` in [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Billing/EntitlementStore.swift#L48) gates purchases if `addOnPacks >= 3`.
- **Expiration:** Consumable packs are verified against transaction expiration dates. Expired packs are pruned on app launch via `pruneExpiredDocumentPacksIfNeeded()`.

---

## 4. Entitlement Reconciliation & Legacy Protection
- **Grandfathering Protection:** I implemented a sticky paid-history protection state (`LegacyProtectionState`). If a user has a historical paid transaction (subscription or non-consumable), [EntitlementStore.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/Billing/EntitlementStore.swift#L356) promotes their state to `.historicalPaidPurchase` or `.legacyDocumentPackOwner` on launch. This maintains their Lifetime access and protects their active document limits even if their StoreKit subscription has expired or is unrenewed.
- **Local Simulation:** In `DEBUG` simulator builds, the app supports simulated billing overrides using `simulateDebugPurchase(_:)` to bypass StoreKit connection failures.
