# StoreKit Testing Guide

This guide walks through configuring StoreKit Testing so you can validate paywalls, entitlements, and upgrade flows entirely on-device—no App Store Connect login required.

## 1. Prerequisites

- Xcode 16 or newer with the iOS 18+ simulator images installed.
- An Apple ID signed into Xcode (Window ▸ Accounts) for managing test devices.
- The repository cloned locally with the `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit` file available.
- Optional: a clean simulator so previous sandbox accounts do not retain stale receipts.

## 2. Enable StoreKit Testing in Xcode

1. Open `OpenIntelligence.xcodeproj` in Xcode.
2. Select **Product ▸ Scheme ▸ Edit Scheme…**.
3. Under **Run ▸ Options**, enable **StoreKit Configuration** and point it to `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit`.
4. Build & run (⌘R). The simulator will now load the test catalog automatically.

> Tip: If the selector is greyed out, close the scheme sheet, wait for Xcode indexing to finish, and try again.

## 3. Understand the Catalog

| Product ID | Kind | Notes |
| --- | --- | --- |
| `starter_monthly` | Auto-renewable | Localized copies for en_US, en_GB, de_DE, ja_JP plus a 3-day free trial. |
| `starter_annual` | Auto-renewable | Annual billing with Family Sharing enabled and a 7-day free trial. |
| `pro_monthly` | Auto-renewable | Unlimited tier with a week-long free trial for debugging upgrade flows. |
| `pro_annual` | Auto-renewable | Family Sharing enabled for whole-household testing. |
| `lifetime_cohort` | Non-consumable | Grants the lifetime tier—good for validating entitlement persistence across reinstalls. |
| `doc_pack_addon` | Consumable | Adds 25 documents per purchase for testing quota boosts. |

The full JSON catalog lives at `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit`. Update it anytime you need to tweak prices, tiers, or localization copy.

## 4. Map Products to Features

`BillingProduct` (in `OpenIntelligence/Services/Billing/BillingProduct.swift`) associates each product identifier with:

- Purchase kind (subscription vs non-consumable vs consumable).
- The `WorkspaceTier` it unlocks.
- The marketing blurb shown on receipts and telemetry.

Whenever you add a new StoreKit product, add a case to `BillingProduct` so the entitlement pipeline can recognize it.

## 5. Run Local Purchase Tests

1. Launch the app on a simulator.
2. Navigate to the Upgrade/Plan screen.
3. Choose a product and complete the StoreKit sheet. Xcode prompts you to create a sandbox tester on first use.
4. Observe logs in Xcode—`BillingProduct` identifiers are printed via `Log.info` when receipts validate.
5. Open Diagnostics ▸ Billing to confirm entitlements match expectations.

To reset purchases during testing, use **Debug ▸ StoreKit ▸ Clear Transactions** in Xcode or wipe the simulator.

## 6. Validate the Catalog Automatically

A Swift helper script ensures the StoreKit configuration contains every product enumerated in `BillingProduct`:

```sh
swift scripts/verify_storekit_products.swift
```

The script scans both files and fails if products are missing or extra. Add it to CI once workflows are in place.

## 7. Troubleshooting

| Symptom | Fix |
| --- | --- |
| StoreKit sheet never appears | Ensure the scheme is referencing the `.storekit` file and the simulator has network connectivity. |
| Purchases succeed but entitlements do not change | Verify the product ID exists in `BillingProduct` and that `RAGService` receives the updated `WorkspaceTier`. |
| Sandbox account locked | In the simulator, open **Settings ▸ App Store**, sign out of any sandbox user, then retry. |
| Free trial not offered | Delete the test user (Debug ▸ StoreKit ▸ App Store ▸ Manage Test Accounts) so the next purchase starts fresh. |

---
Need another locale or billing scenario covered? Duplicate an existing entry in the StoreKit config, update the locale metadata, and re-run the verification script to keep everything in sync.
