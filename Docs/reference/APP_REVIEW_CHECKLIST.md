# App Review Submission Checklist

**Last updated:** 2025-11-12

This checklist distills the minimum actions we must complete before submitting **OpenIntelligence** to Apple’s App Review. Following these steps keeps the experience “closed loop,” eliminates unexpected cloud traffic, and ensures reviewers can sign off quickly.

---

## 1. Build Configuration

- [ ] **Reviewer mode disabled** (`SettingsStore.reviewerModeEnabled = false`). Verify in the release build that `.openAIDirect` never appears in `settings.primaryModelOptions` or UI pickers.
- [ ] **Release guard active.** Confirm a release-signed build refuses to flip `reviewerModeEnabled` (toggling resets to `false`).
- [ ] **No hidden OpenAI toggles**. Confirm `SettingsRootView` does not surface the OpenAI category when reviewer mode is off (macOS and iOS).
- [ ] **Network egress** limited to Apple domains. Capture a packet trace during ingestion + chat; ensure only Apple-hosted endpoints (PCC) appear.
- [ ] **Production provisioning**. Build the binary with App Store signing, removing any test entitlement (StoreKit external link, etc.).

## 2. Account & Demo Access

- [ ] Provide App Review with a demo account (if document import is gated). Include credentials or enable demo-mode via Review Notes.
- [ ] Pre-load the demo account with sample documents from `TestDocuments/` so the reviewer can test ingest → retrieval.
- [ ] Ensure backend services (if any) are reachable; flip any feature flags that block non-production accounts.

## 3. In-App Purchase & Pricing

- [ ] Attach the tier plan summary from `Docs/reference/PRICING_STRATEGY.md` to Review Notes, noting that all pricing is native IAP.
- [ ] Confirm StoreKit products (Free, Starter, Pro, Lifetime, Add-ons) exist and match the SKU list in code.
- [ ] Verify paywall messaging avoids non-App-Store pricing references and includes “on-device / PCC” privacy language.

## 4. Privacy & Consent

- [ ] Confirm `RAGService.cloudConsent` defaults to `notDetermined/denied` for `.openAI`.
- [ ] Run the telemetry consent flow to show reviewers the disclosure that data remains on-device/Apple PCC.
- [ ] Attach the privacy policy URL in App Store Connect; ensure it references closed-loop data handling.

## 5. Guideline References for Review Notes

Include the following summary when submitting:

```text
• All inference occurs on-device or via Apple Private Cloud Compute; no third-party APIs are contacted.
• OpenAI Direct is disabled in production builds (reviewer-only toggle removed).
• Sample documents are preloaded; no external accounts required.
• In-app purchases use StoreKit only; no external payment links.
```

## 6. Final QA Pass

- [ ] Smoke test per `smoke_test.md` (import doc, run query, switch tiers, check paywall, toggle PCC).
- [ ] Ensure app metadata (screenshots, description) matches the current feature set.
- [ ] Submit the build with the above checklist attached to Review Notes.

---

Keeping this checklist updated is part of the release process. If App Review raises new issues, capture them here so the next submission is faster.
