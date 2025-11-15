# App Readiness Memo

**Last updated:** 2025-11-14

This memo captures the core gaps observed in the OpenIntelligence repo before enabling monetization. Revisit and update this document whenever major UX, compliance, or monetization changes land.

## 1. Monetization Readiness

- **Current state:** Pricing copy lives inside `SettingsRootView` > `AboutSettingsView`. There are no StoreKit products, entitlement logic, or quota enforcement.
- **Risks:** Apple may reject if tiers are advertised without working purchases. Users have no way to upgrade even if they want to. Manual copy drift from `Docs/reference/PRICING_STRATEGY.md` is likely.
- **Actions:**
    1. Create a StoreKit configuration with `starter_monthly`, `pro_monthly`, `pro_annual`, `lifetime_cohort`, and `doc_pack_addon` SKUs. (See `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit`.)
    2. Build a `BillingService` / `EntitlementStore` that updates `SettingsStore` and ingestion quotas.
    3. Add a SwiftUI paywall modal + contextual upgrade triggers (quota banners, rerank gating).
    4. Enforce document/library limits even before StoreKit launches to keep behavior consistent.

## 2. Onboarding & Sample Content

- **Current state:** First-run experience drops the user into Chat with no documents. Sample files exist only under `TestDocuments/` for App Review.
- **Risks:** Reviewers or users cannot experience the end-to-end flow, reducing perceived value.
- **Actions:**
  1. Add a first-run checklist that imports sample docs (pricing brief, technical overview) and showcases privacy messaging.
  2. Provide empty-state illustrations and an "Import Sample Docs" button in the Documents tab.
  3. Surface document quota counters and upgrade CTAs when limits approach.

## 3. Settings & Diagnostics Polish

- **Current state:** Several sections (System Status, Developer, Retrieval tuning) contain placeholder text ("will appear here").
- **Risks:** App Review may treat placeholders as incomplete features.
- **Actions:**
  1. Populate each section with real data (e.g., retrieval parameters, ingestion telemetry, system metrics).
  2. Hide sections that are not production-ready behind reviewer mode or feature flags.

## 4. Privacy & Reviewer Tooling

- **Current state:** Documentation promises reviewer mode gating and telemetry checks, but the runtime lacks a user-accessible toggle or automated tests.
- **Risks:** Reviewers cannot validate optional providers (OpenAI, GGUF), causing delays; inconsistent privacy behavior could trigger rejection.
- **Actions:**
  1. Add a hidden reviewer toggle (debug gesture or TestFlight config) enabling OpenAI/advanced providers.
  2. Write automated tests that verify `.openAIDirect` is hidden when reviewer mode is off.
  3. Include instructions in `APP_REVIEW_NOTES_TEMPLATE.md` describing how to activate reviewer mode.

## 5. Support & Policy Surfaces

- **Current state:** About screen links to support/privacy but lacks Terms of Service, refund guidance, or in-app contact options.
- **Risks:** Monetized apps must expose full legal links and contact pathways.
- **Actions:**
  1. Add a Terms of Service viewer (Markdown or hosted link) alongside Privacy.
  2. Provide a "Contact Support" mail composer or form.
  3. Ensure refund/cancellation messaging is consistent with App Store guidelines.

## 6. Reliability & Telemetry

- **Current state:** Ingestion errors and metrics (page counts, OCR stats) are marked TODO in `RAGService`. There is limited user feedback for failures.
- **Risks:** Users and reviewers may see silent failures. Analytics promised in docs are incomplete.
- **Actions:**
  1. Complete metadata capture (pages, OCR counts) and expose them in Document detail panels.
  2. Emit user-visible toasts or status rows for ingestion errors and retries.
  3. Expand telemetry to cover quota hits, paywall views, and fallback activations.

## 7. Testing & Release Hygiene

- **Current state:** No automated UI tests, StoreKit tests, or ingestion smoke tests. Security checklist in `SECURITY.md` references TODOs (e.g., `BuildGuards.swift`).
- **Risks:** Regression risk is high, and App Review may ask for reproducible steps without evidence.
- **Actions:**
  1. Add unit tests for `RAGService`, `HybridSearchService`, and `SettingsStore` flows.
  2. Create a UI test that imports a sample doc, runs a chat query, and opens settings → about.
  3. Implement the security guardrail in `BuildGuards.swift` to block release builds with unconfigured secrets.

---

Keep this memo updated after each milestone (onboarding, paywall, reviewer tooling, etc.) so the team and App Review collateral stay aligned. When revisiting monetization, confirm every section above is checked off before resubmitting.
