# Release & Operations Guide

> Archived reference snapshot. For current repo-grounded guidance, use [../Release.md](../Release.md).
> Billing and pricing details in this archived file may no longer match the current repo policy exactly; verify against code and [../PRICING_STRATEGY.md](../PRICING_STRATEGY.md) before using them.

**Last Updated**: March 2026
**Status**: Production (v2.0 — Build 19)

This is the consolidated guide for releasing OpenIntelligence to the App Store. It combines release checklists, smoke testing, StoreKit configuration, and App Store Connect setup.

---

## Table of Contents

1. [Pre-Release Checklist](#1-pre-release-checklist)
2. [Smoke Test Protocol](#2-smoke-test-protocol)
3. [Version Bump](#3-version-bump)
4. [StoreKit Testing](#4-storekit-testing)
5. [Archive & Submission](#5-archive--submission)
6. [App Store Connect Setup](#6-app-store-connect-setup)
7. [Post-Release Monitoring](#7-post-release-monitoring)

---

## 1. Pre-Release Checklist

### Code Quality

- [ ] Clean build (`⌘B` in Xcode) — no test target (removed, see Quick Reference below)
- [ ] No compiler warnings
- [ ] SwiftLint passes: `swiftlint`
- [ ] Secret scan passes: `python3 scripts/secret_scan.py`
- [ ] No `// TODO:` or `// FIXME:` in release code

### Privacy & Compliance

- [ ] `PRIVACY.md` matches app behavior
- [ ] Cloud consent flow works correctly
- [ ] OpenAI settings hidden in production builds
- [ ] No user data logged in release builds

### StoreKit

- [ ] Products load correctly
- [ ] Purchase flows complete
- [ ] Restore purchases works
- [ ] Quota enforcement blocks at limits

### Performance

- [ ] 10-page PDF ingestion < 30 seconds
- [ ] Query response < 5 seconds
- [ ] Memory usage < 500MB during normal operation

---

## 2. Smoke Test Protocol

**Time**: ~10 minutes
**Device**: iPhone 17 Pro Max Simulator (iOS 26.0+)

### Setup

```bash
# Reset app state
defaults delete com.openintelligence.OpenIntelligence 2>/dev/null || true

# Build & Run
open OpenIntelligence.xcodeproj  # ⌘R
```

### Test 1: Onboarding (3 min)

1. Launch app → Onboarding checklist appears
2. **Step 1**: Tap "Import Now" → Sample docs imported
3. **Step 2**: Open Settings → Select model → Step complete
4. **Step 3**: Go to Chat → Ask "What documents were imported?" → Response received
5. Quit & relaunch → Onboarding does NOT reappear

### Test 2: Document Ingestion (2 min)

1. Documents tab → "+" → Select `Docs/TestDocuments/sample_technical.md`
2. Verify: Processing overlay → Progress updates → Document appears in list

### Test 3: RAG Query (2 min)

1. Chat tab → Type "What is this document about?"
2. Verify: Streaming response → Inference badge shows (📱/☁️/🔑)

### Test 4: Model Switching (2 min)

1. Settings → Change Primary Model
2. Return to Chat → Ask question
3. Verify: Response uses new model

### Test 5: Container Isolation (1 min)

1. Documents → Create "Test Container 2"
2. Verify: New container is empty
3. Import doc → Query only finds new container's content

### Performance Benchmarks

| Operation                                | Target |
| ---------------------------------------- | ------ |
| Document ingestion (sample_technical.md) | <3s    |
| Query embedding                          | <200ms |
| Hybrid search (100 chunks)               | <100ms |
| LLM TTFT (on-device)                     | <1s    |

---

## 3. Version Bump

### Semantic Versioning

- **MAJOR**: Breaking changes
- **MINOR**: New features (backwards compatible)
- **PATCH**: Bug fixes

### Update Locations

1. **Xcode** → Project → Target → General:
   - `CFBundleShortVersionString`: `X.Y.Z`
   - `CFBundleVersion`: Increment each submission

2. **CHANGELOG.md**:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added

- Feature description

### Fixed

- Bug fix description
```

---

## 4. StoreKit Testing

### Two Modes (Best Practice)

**🔧 Development (Local StoreKit)** — Use 99% of the time

- **What it is**: The `.storekit` file simulates purchases locally
- **Pros**: Instant, no network, no sandbox accounts needed
- **Your Apple ID appears but NO CHARGES EVER HAPPEN**
- **Setup**: Run the `OpenIntelligence-StoreKitTesting` scheme (it has `StoreKitConfiguration.storekit` attached)
- **Reset purchases**: Debug menu (in-app) → StoreKit → Clear Transactions

**☁️ Pre-Submission Sandbox** — Use once before App Store upload

- **What it is**: Tests real StoreKit servers with fake accounts
- **When**: Final smoke test before submission only
- **Setup**: See "Switch to Sandbox" below

### Current Setup (Scheme Isolation)

This repo uses **two schemes** so local StoreKit testing never leaks into “real StoreKit” runs:

- **`OpenIntelligence`** (default) → **StoreKit Configuration: None**
  - Use this when testing on a **physical device** with **real StoreKit servers** (Sandbox purchases).
- **`OpenIntelligence-StoreKitTesting`** → **StoreKitConfiguration.storekit**
  - Use this for **local simulation** (especially on Simulator) with instant purchases.

**When you tap Purchase in `OpenIntelligence-StoreKitTesting`:**

- ✅ Shows your real Apple ID (`gunnarguy@me.com`)
- ✅ This is NORMAL and SAFE — you will NOT be charged
- ✅ Simulates purchases instantly without network calls

**When you tap Purchase in `OpenIntelligence` on a device:**

- ✅ Talks to Apple’s StoreKit servers
- ✅ Purchases complete using a Sandbox tester (no charges)
- ⚠️ Requires correct App Store Connect setup + Sandbox sign-in

### Switch to Sandbox (Only Before App Store Upload)

1. In Xcode, select the **`OpenIntelligence`** scheme and a **physical device** destination.
2. Confirm **Run → Options → StoreKit Configuration = None**.
3. [App Store Connect](https://appstoreconnect.apple.com) → Users and Access → Sandbox → Add Tester
   - Email: `test+oi1@yourdomain.com` (can be fake, Apple sends confirmation)
   - Password: Set something memorable
4. **Device**: Settings → App Store → Sandbox Account → Sign in with sandbox tester
5. Run app → Test one purchase → Verify it completes
6. After validation, you can switch back to the `OpenIntelligence-StoreKitTesting` scheme for day-to-day local UI work.

### Product Catalog

| Product ID        | Type           | Price     | Notes                                                                                                                                          |
| ----------------- | -------------- | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `pro_monthly`     | Subscription   | $5.99/mo  | Unlimited Maximum, 1,000 docs, 5 libs                                                                                                          |
| `pro_annual`      | Subscription   | $49.99/yr | Same unlocks as monthly                                                                                                                        |
| `lifetime_cohort` | Non-consumable | $59.99    | Unlimited Maximum, unlimited docs                                                                                                              |
| `doc_pack_addon`  | Consumable     | $2.99     | Active purchase UI, entitlement plumbing, quota math, and App Store metadata still exist; some in-app copy still says packs are no longer sold |

### Validate Catalog

```bash
swift scripts/verify_storekit_products.swift
```

### Reset Purchases

Debug → StoreKit → Clear Transactions

---

## 5. Archive & Submission

### Create Archive

```bash
xcodebuild archive \
  -scheme OpenIntelligence \
  -archivePath ./build/OpenIntelligence.xcarchive \
  -destination 'generic/platform=iOS'

xcodebuild -exportArchive \
  -archivePath ./build/OpenIntelligence.xcarchive \
  -exportPath ./build/Export \
  -exportOptionsPlist Docs/reference/exportOptions.plist
```

### Pre-Submission Checks

- [ ] Archive builds without errors
- [ ] App thinning report shows acceptable sizes
- [ ] No missing entitlements warnings

### Automation

```bash
./scripts/preflight_check.sh    # Validates build
./scripts/package_submission.sh # Creates .ipa + symbols
```

---

## 6. App Store Connect Setup

### In-App Purchases & Subscriptions

> **Note (App Store Connect UI)**: If the “Create” dialog only shows **Consumable** and **Non-Consumable**, you’re currently on the **In-App Purchases** page.
> Auto-renewable subscriptions are created from the **Subscriptions** page (and require a **Subscription Group**).

#### Quick prerequisites (if options are missing)

- Ensure the **Paid Applications / Agreements, Tax, and Banking** setup is completed for the account.
- Ensure you’re inside the correct app: **My Apps → OpenIntelligence**.
- Use **Monetization → In-App Purchases and Subscriptions** and then select the correct sub-section:
  - **Subscriptions** (for Pro plans)
  - **In-App Purchases** (for lifetime + consumables)

#### Subscriptions (Auto-Renewable)

**Subscription Group**: `OpenIntelligence Plans`

For each product:

1. App Store Connect → My Apps → OpenIntelligence → **Monetization** → **Subscriptions**
2. Create the subscription group (once): `OpenIntelligence Plans`
3. Inside the group, click "+" to add each subscription
4. Select duration (monthly/annual), then enter Product ID exactly as shown above
5. Add localization (Display Name, Description)
6. Set pricing tier
7. Enable "Cleared for Sale"

#### In-App Purchases (Consumable / Non-Consumable)

1. App Store Connect → My Apps → OpenIntelligence → **Monetization** → **In-App Purchases**
2. Click "+" → Select type (Consumable / Non-Consumable)
3. Enter Product ID exactly as shown above
4. Add localization (Display Name, Description)
5. Set pricing tier
6. Enable "Cleared for Sale"

### Price Tier Mapping

| SKU               | Apple Tier | Display Price |
| ----------------- | ---------- | ------------- |
| `pro_monthly`     | S6         | $5.99         |
| `pro_annual`      | S39        | $49.99        |
| `lifetime_cohort` | Tier TBD   | $59.99        |
| `doc_pack_addon`  | Tier 3     | $2.99         |

### App Store Metadata

- [ ] Screenshots (all device sizes)
- [ ] App description and keywords
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] What's New text

---

## 7. Post-Release Monitoring

### Monitor

- [ ] App Store Connect rejection feedback
- [ ] Crash reports (Xcode Organizer)
- [ ] User reviews
- [ ] Memory/CPU analytics

### Rollback Plan

1. Expedited review request for hotfix
2. Or: Remove current version from sale
3. Document in `CHANGELOG.md`

### Success Metrics

| Metric              | Target |
| ------------------- | ------ |
| Download → Trial    | ≥10%   |
| Trial → Paid        | ≥45%   |
| Monthly Churn (Pro) | ≤6%    |
| Refund Rate         | <4%    |

---

## Quick Reference

### Testing

The unit test suite was removed — all tests relied on mock objects and could not exercise real Apple framework behavior on the iOS Simulator (FoundationModels, Vision OCR, CoreML Neural Engine are unavailable). BM25 tests crashed the simulator process due to an Apple NaturalLanguage framework bug. Quality is validated through on-device testing.

### GGUF Local Model Setup

1. Xcode → File → Add Packages → Add Local → `Vendor/LocalLLMClient`
2. Link to target: `LocalLLMClient`, `LocalLLMClientLlama`
3. Build for device (not Simulator)
4. Import GGUF model via Settings → Model Downloads
5. Settings → Model Selection → Set Local Primary → Pick GGUF model

### Troubleshooting

| Issue                          | Solution                          |
| ------------------------------ | --------------------------------- |
| Apple Intelligence unavailable | Use "On-Device Analysis" fallback |
| Documents not importing        | Check file picker permissions     |
| Streaming not working          | Verify LLM service selection      |
| StoreKit sheet not appearing   | Verify .storekit file in scheme   |
| GGUF out of memory             | Use smaller model (2-3B Q4_K_M)   |
