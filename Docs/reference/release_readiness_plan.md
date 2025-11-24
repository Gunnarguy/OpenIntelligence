# Release Readiness Plan

This document outlines the remaining foundational work required to make OpenIntelligence fully production-ready for App Store distribution. Each section maps to an actionable initiative with clear deliverables so we can execute incrementally without losing the end-to-end picture.

## 1. Automated Tests & Diagnostics Harness

### Goals (Tests & Diagnostics)

- Cover the critical paths: ingestion, retrieval, agentic tool calls, StoreKit entitlements, telemetries.
- Allow headless diagnostics so CI and QA can run the “Core Validation” suite without a UI.

### Deliverables (Tests & Diagnostics)

- `OpenIntelligenceTests/RAGPipelineTests.swift`: unit tests for `RAGService.query`, `HybridSearchService`, and fallback flows using mock vector DB + mock LLM service.
- `OpenIntelligenceTests/StoreKitTests.swift`: exercises `EntitlementStore` with sample products, ensuring upgrade gating logic works offline.
- `DiagnosticsCLI.swift` (in `scripts/` or a Swift Package) that invokes the existing validation tests and prints pass/fail so we can call it from CI via `swift run diagnostics-cli`.

## 2. CI/CD Pipeline

### Goals (CI/CD)

- Automatic lint + test on every PR.
- Nightly build that produces an `.ipa`, runs `preflight_check.sh`, and (optionally) uploads to TestFlight.

### Deliverables (CI/CD)

- `.github/workflows/ci.yml`: matrix build for iOS + macOS, running `xcodebuild test` and `swiftlint` (if configured).
- `.github/workflows/release.yml`: manual + nightly workflow that runs `./clean_and_rebuild.sh`, executes diagnostics CLI, then archives the app with export options from `Docs/reference/exportOptions.plist`.
- Secrets documentation in `Docs/guides/ci_setup.md` describing required GitHub Actions secrets (APPLE_API_KEY, APP_STORE_CONNECT_ISSUER, etc.).

## 3. StoreKit Catalog Enhancements

### Goals (StoreKit)

- Provide realistic placeholder products so billing/upgrade UI can be tested locally.

### Deliverables (StoreKit)

- `StoreKit/StoreKitConfiguration.storekit` update with sample tiers (`starter_monthly`, `pro_monthly`, `lifetime`), localized descriptions, intro offers, and Family Sharing flags.
- `Docs/guides/storekit_testing.md` walkthrough for enabling StoreKit Testing in Xcode, mapping product identifiers to in-app features, and simulating receipts.
- Automated sanity check (Swift or shell) that verifies `StoreKitConfiguration.storekit` contains every `QuotaPolicy` product identifier.

## 4. Release Tooling & Assets

### Goals (Release Tooling)

- Keep versioning, screenshots, and metadata consistent between repo and App Store Connect.

### Deliverables (Release Tooling)

- `scripts/bump_version.swift`: updates `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` and writes release notes stub.
- `Docs/reference/release_checklist.md`: canonical process from code freeze through App Store submission, including smoke tests.
- `Assets/Marketing/` folder with placeholder App Store screenshots (or templates) plus localized description JSON (for future Fastlane integration).

## 5. Security & Environment Checks

### Goals (Security)

- Ensure builds fail fast when secrets or env vars are missing and prevent accidental secret leakage.

### Deliverables (Security)

- `scripts/validate_env.sh`: checks for `.env` or `.envrc` placeholders, ensures required variables (OPENAI_API_KEY, NOTION_API_KEY, etc.) are set before running sensitive commands.
- Extend `secret_scan.py` with allowlist support and CI integration.
- Add a CI job (`security.yml`) that runs `bandit` (for Python scripts) and `trivy` or `gitleaks` for additional scanning.

## 6. Telemetry + Observability Enhancements

### Goals (Telemetry)

- Surface embedding/provider mismatches, StoreKit health, and cloud consent state centrally.

### Deliverables (Telemetry)

- Dashboard view aggregating TelemetryCenter events (embedding adjustments, billing failures, PCC fallbacks) with filters + export.
- JSON export (`TelemetryCenter/exportLatest()`), enabling CI artifacts for post-run inspection.
- Optional SPM module that can be imported into a macOS admin app for live monitoring during TestFlight sessions.

---

These initiatives can be tackled in parallel, but the recommended order is: (1) automated tests & diagnostics harness, (2) CI/CD pipeline, (3) StoreKit catalog, (4) release tooling/assets, (5) security checks, (6) telemetry dashboard. Each section above will get its own tracking issue/PR once we dive into implementation.
