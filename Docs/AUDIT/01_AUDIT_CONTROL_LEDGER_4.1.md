# OpenIntelligence v4.1 Audit Control Ledger

This ledger tracks the progress of the OpenIntelligence v4.1 codebase audit. Checked items indicate completed audit assessments.

## 1. Audit Rules
- [x] Existing docs are treated as claims, not facts
- [x] Code/build/target membership is treated as source of truth
- [x] Every claim must have evidence
- [x] Scaffolded code must be labeled scaffolded
- [x] Unused code must be labeled candidate until manually reviewed
- [x] No destructive reorganization during audit

## 2. Status Label Definitions
The audit uses the following precise status labels:
- `SHIPPED_USER_FACING`: Compiled, reachable, and directly interactive by a standard user.
- `SHIPPED_INTERNAL`: Compiled and active in the production targets, but running in the background without direct UI exposure.
- `DEV_ONLY` / `DEBUG_ONLY` / `TEST_ONLY`: Code, scripts, or targets only run in local development or test environments.
- `SCRIPT_ONLY`: Utility scripts not built into binary targets.
- `RESOURCE_ONLY`: Static assets, plist files, configurations, or StoreKit testing catalogs.
- `SCAFFOLDED` / `PLACEHOLDER`: Code structure or files exist in the target but do not execute functional/meaningful production behavior yet.
- `DEPRECATED`: Outdated code paths or modules retained in the workspace but bypassed at compile time or execution.
- `HISTORICAL_DOC`: Documentation files describing older iterations of the project.
- `UNUSED_CANDIDATE`: Files that appear unreferenced and compile-excluded, pending final human confirmation for deletion.
- `UNKNOWN_REQUIRES_REVIEW`: Ambiguous files needing specific review by the lead developer.

## 3. File Inventory Progress
- [x] Full file tree generated
- [x] Xcode target membership mapped
- [x] Swift source files classified
- [x] SwiftUI views classified
- [x] Services classified
- [x] Models classified
- [x] Resources classified
- [x] Scripts classified
- [x] Docs classified
- [x] Tests / debug harnesses classified
- [x] Assets classified
- [x] StoreKit files classified
- [x] Entitlements classified
- [x] AppIntent / Spotlight files classified

## 4. Component Inventory Progress
- [x] App entry points mapped
- [x] Navigation / root UI mapped
- [x] Document ingestion mapped
- [x] OCR / Vision pipeline mapped
- [x] Chunking pipeline mapped
- [x] Embedding pipeline mapped
- [x] Vector search mapped
- [x] Full-text search mapped
- [x] RAG orchestration mapped
- [x] Agentic / Deep Think / Maximum mapped
- [x] Foundation Models mapped
- [x] PCC routing mapped
- [x] Verification gates mapped
- [x] Structured answer generation mapped
- [x] Suggested questions mapped
- [x] Billing / StoreKit mapped
- [x] Entitlements / quotas mapped
- [x] Settings mapped
- [x] Diagnostics mapped
- [x] Telemetry mapped
- [x] Spotlight mapped
- [x] AppIntents mapped
- [x] Core AI scaffolding mapped
- [x] Liquid Glass / UI design system mapped
- [x] iCloud / storage / sync mapped
- [x] Scripts / CLI / evaluations mapped

## 5. Documentation Accuracy Progress
- [x] README.md audited
- [x] WHATS_NEW.md audited
- [x] CHANGELOG.md audited
- [x] Docs/ARCHITECTURE.md audited
- [x] Docs/RETRIEVAL_PIPELINE.md audited
- [x] Docs/EVALS.md audited
- [x] Docs/AI_AGENT_MAP.md audited
- [x] fastlane metadata audited
- [x] App Store metadata references audited
- [x] Inaccurate docs marked
- [x] Historical docs labeled
- [x] Public-facing claims corrected

## 6. Feature Claim Verification Progress
- [x] Private/local-first behavior verified
- [x] PCC behavior verified
- [x] Foundation Models behavior verified
- [x] Supported file types verified
- [x] OCR behavior verified
- [x] Table/list extraction verified
- [x] Metal acceleration verified
- [x] Vector database behavior verified
- [x] RAG citations verified
- [x] Verification gates verified
- [x] Billing tiers verified
- [x] Document/library limits verified
- [x] Core AI status verified
- [x] Spotlight/AppIntents status verified
- [x] Telemetry/HUD status verified
- [x] Benchmarks checked
- [x] Unsupported performance claims removed

## 7. Unused Code Review Progress
- [x] Target membership scan complete
- [x] Static reference scan complete
- [x] Dynamic entry point exceptions reviewed
- [x] Previews/debug-only files separated
- [x] Unused candidates listed
- [x] Deletion risk ranked
- [x] No files deleted during audit

## 8. Reorganization Candidate Progress
- [x] Current folder map generated
- [x] Duplicate/residual folders identified
- [x] Naming inconsistencies identified
- [x] Proposed target architecture drafted
- [x] Migration order drafted
- [x] Build-safety plan drafted
- [x] No reorganization performed without approval

## 9. Final Acceptance Criteria
- [x] Every file is inventoried
- [x] Every major component has status
- [x] Every public claim has evidence or is removed
- [x] Every future/scaffold feature is labeled
- [x] Every outdated doc has status header
- [x] README is accurate
- [x] Release notes are accurate
- [x] App Store copy mismatches are listed
- [x] Reorganization plan exists
- [x] Build/test verification completed or failure documented
