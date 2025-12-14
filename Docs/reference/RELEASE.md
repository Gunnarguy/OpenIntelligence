# Release & Operations Guide

**Last Updated**: December 2025  
**Status**: Production Ready

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
- [ ] All tests pass (`⌘U` in Xcode)
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

| Operation | Target |
|-----------|--------|
| Document ingestion (sample_technical.md) | <3s |
| Query embedding | <200ms |
| Hybrid search (100 chunks) | <100ms |
| LLM TTFT (on-device) | <1s |

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

### Enable in Xcode
1. Product → Scheme → Edit Scheme
2. Run → Options → StoreKit Configuration
3. Select: `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit`

### Product Catalog

| Product ID | Type | Price | Notes |
|------------|------|-------|-------|
| `starter_monthly` | Subscription | $2.99/mo | 3-day trial |
| `starter_annual` | Subscription | $24.99/yr | 7-day trial |
| `pro_monthly` | Subscription | $8.99/mo | 7-day trial |
| `pro_annual` | Subscription | $89.99/yr | Family Sharing |
| `lifetime_cohort` | Non-consumable | $59.99 | Limited availability |
| `doc_pack_addon` | Consumable | $4.99 | +25 documents |

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

### In-App Purchases

**Subscription Group**: `OpenIntelligence Plans`

For each product:
1. App Store Connect → My Apps → OpenIntelligence → Features → In-App Purchases
2. Click "+" → Select type → Enter Product ID exactly as shown above
3. Add localization (Display Name, Description)
4. Set pricing tier
5. Enable "Cleared for Sale"

### Price Tier Mapping

| SKU | Apple Tier | Display Price |
|-----|------------|---------------|
| `starter_monthly` | S3 | $2.99 |
| `starter_annual` | S15 | $24.99 |
| `pro_monthly` | S9 | $8.99 |
| `pro_annual` | S69 | $89.99 |
| `lifetime_cohort` | Tier 60 | $59.99 |
| `doc_pack_addon` | Tier 5 | $4.99 |

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

| Metric | Target |
|--------|--------|
| Download → Trial | ≥10% |
| Trial → Paid | ≥45% |
| Monthly Churn (Starter) | ≤9% |
| Monthly Churn (Pro) | ≤6% |
| Refund Rate | <4% |

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

### GGUF Local Model Setup
1. Xcode → File → Add Packages → Add Local → `Vendor/LocalLLMClient`
2. Link to target: `LocalLLMClient`, `LocalLLMClientLlama`
3. Build for device (not Simulator)
4. Import GGUF model via Settings → Model Downloads
5. Settings → Model Selection → Set Local Primary → Pick GGUF model

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Apple Intelligence unavailable | Use "On-Device Analysis" fallback |
| Documents not importing | Check file picker permissions |
| Streaming not working | Verify LLM service selection |
| StoreKit sheet not appearing | Verify .storekit file in scheme |
| GGUF out of memory | Use smaller model (2-3B Q4_K_M) |
