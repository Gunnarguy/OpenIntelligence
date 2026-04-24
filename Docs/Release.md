# Release & Operations Guide

**Last Updated**: April 24, 2026
**Status**: Release-candidate operations guide. Verify version/build from Xcode before submission.

This is the consolidated guide for releasing OpenIntelligence to the App Store. It combines release checklists, smoke testing, StoreKit configuration, and App Store Connect setup.

Current source-of-truth docs before release:

- [Current State and Gaps](./CURRENT_STATE_AND_GAPS.md)
- [Hard Limits](./HARD_LIMITS.md)
- [Pricing and Packaging Strategy](./PRICING_STRATEGY.md)
- [Implementation Analysis](./IMPLEMENTATION_ANALYSIS_2026_04_24.md)
- [Storage and Pipeline Trace](./STORAGE_AND_PIPELINE_TRACE.md)
- [Buyer Readiness and Evaluation Plan](./BUYER_READINESS_AND_EVALUATION.md)
- [Research Index](./Research/README.md)

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

- [ ] All tests pass (`⌘U` in Xcode)
- [ ] No compiler warnings
- [ ] SwiftLint passes: `swiftlint`
- [ ] Secret scan passes: `python3 scripts/secret_scan.py`
- [ ] No `// TODO:` or `// FIXME:` in release code

### Privacy & Compliance

- [ ] `PRIVACY.md` matches app behavior
- [ ] Cloud consent flow works correctly
- [ ] Any non-Apple provider settings are hidden or explicitly consent-gated in production builds
- [ ] No user data logged in release builds
- [ ] App metadata does not claim direct PCC server-model access or 65K FoundationModels context
- [ ] Healthcare/medical-device copy avoids HIPAA, diagnostic, or clinical-decision claims unless formally verified
- [ ] Buyer-facing material uses the evaluation-pilot framing from `Docs/BUYER_READINESS_AND_EVALUATION.md`

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
**Device**: Physical Apple Intelligence-capable device for FoundationModels validation. Simulator is acceptable only for UI/storage/fallback smoke tests.

### Setup

```bash
# Reset app state
defaults delete com.openintelligence.OpenIntelligence 2>/dev/null || true

# Build and run
open OpenIntelligence.xcodeproj
```

### Test 1: Onboarding (3 min)

1. Launch app → Onboarding checklist appears
2. **Step 1**: Tap "Import Now" → Sample docs imported
3. **Step 2**: Open Settings → Confirm Apple Intelligence availability or fallback state
4. **Step 3**: Go to Chat → Ask "What documents were imported?" → Response received
5. Quit & relaunch → Onboarding does NOT reappear

### Test 2: Document Ingestion (2 min)

1. Documents tab → "+" → Select `Docs/TestDocuments/sample_technical.md`
2. Verify: Processing overlay → Progress updates → Document appears in list

### Test 3: RAG Query (2 min)

1. Chat tab → Type "What is this document about?"
2. Verify: Streaming response → Inference badge matches actual execution path

### Test 4: FoundationModels Availability (2 min)

1. On a physical device, confirm `SystemLanguageModel.default` is available or shows the correct unavailable reason
2. Ask a short cited question from an imported document
3. Verify no context-window/PCC/server-model claims appear in UI copy

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

### Required Manual Accuracy Checks

- [ ] Exact numeric/specification query returns the source value and citation
- [ ] Table/spec-sheet query returns the value from the correct row/section, not a nearby cross-reference
- [ ] Missing-evidence query abstains or states evidence gap
- [ ] Broad summary query cites multiple relevant chunks or clearly states limited evidence
- [ ] Multi-document query does not mix unrelated libraries/containers

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

| Product ID        | Type           | Price     | Notes                                  |
| ----------------- | -------------- | --------- | -------------------------------------- |
| `pro_monthly`     | Subscription   | $5.99/mo  | No trial in current fastlane setup     |
| `pro_annual`      | Subscription   | $49.99/yr | Family Sharing                         |
| `lifetime_cohort` | Non-consumable | $59.99    | Limited availability (lifetime unlock) |
| `doc_pack_addon`  | Consumable     | $2.99     | +10 documents                          |

**Release decision needed**: `doc_pack_addon` remains in `BillingProduct.swift` and `fastlane/subscriptions.json`, while current in-app Terms copy says legacy document packs are no longer sold in-app. Resolve before submission.

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
| `lifetime_cohort` | Tier 60    | $59.99        |
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

### Test Setup

```bash
# Add test target to Xcode
# File → New → Target → iOS Unit Testing Bundle → "OpenIntelligenceTests"
# Add files from OpenIntelligenceTests/ folder

# Run tests
xcodebuild test -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```

### FoundationModels Device Check

1. Build the `OpenIntelligence` scheme to a physical Apple Intelligence-capable device.
2. Confirm Apple Intelligence is enabled in Settings and the model is ready.
3. Run the onboarding/import/query smoke test with a small document.
4. Run one exact-value question and one missing-evidence question.
5. If the model is unavailable, verify the app surfaces the correct availability state instead of failing silently.

### Troubleshooting

| Issue                          | Solution                          |
| ------------------------------ | --------------------------------- |
| Apple Intelligence unavailable | Use "On-Device Analysis" fallback |
| Documents not importing        | Check file picker permissions     |
| Streaming not working          | Verify LLM service selection      |
| StoreKit sheet not appearing   | Verify .storekit file in scheme   |
| FoundationModels unavailable   | Confirm device eligibility, Apple Intelligence Settings state, model readiness, and simulator/device target |
| Context window exceeded        | Reduce retrieved chunks, disable tool schemas, shorten prompt/instructions, or split into another session |
