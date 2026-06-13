# Phase 9: Unused Code and Dead Path Analysis — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Identifies compile-excluded, preview-only, and diagnostic-only code files in the repository.

This document classifies unused code candidates and developer-only paths. To maintain safety, no files have been deleted during this audit pass.

---

## 1. Classification of Unused Code Candidates

### High-Confidence Unused
No high-confidence unused production files were found inside compile targets. All source files in `OpenIntelligence/` are membered and active in the app target, except for specific debug harnesses.

### Indirectly Used / Scaffold Keep
* **`Package.swift`**
  - **Status:** `SCAFFOLD_KEEP` / `INDIRECTLY_USED_POSSIBLE`
  - **Reason:** Bypassed by the main Xcode application build. However, it is referenced by local Swift package configurations and provides the framework boundaries for the `OpenIntelligenceEngine` package.
  - **Risk if removed:** High. Brakes package resolving for external developer tests.
  - **Recommendation:** Retain as packaging scaffolding.

---

## 2. Debug & Diagnostic Code Paths

These files are compiled into the app target but are restricted to developer diagnostic UI screens, self-tests, or local command-line execution:

| Path | Symbol | Status | Role | Deletion Risk |
|---|---|---|---|---|
| `OpenIntelligence/App/DebugRAGValidationHarness.swift` | `class DebugRAGValidationHarness` | `DEBUG_ONLY` | Initiates local evaluations on device. | Low |
| `OpenIntelligence/Features/Diagnostics/Validation/ContainerScopingSelfTestsView.swift` | `struct ContainerScopingSelfTestsView` | `TEST_ONLY` | UI self-test triggers to check isolation. | Low |
| `scripts/run_rag_benchmarks.py` | N/A | `SCRIPT_ONLY` | CLI tool to execute RAG evaluations. | Low |
| `Xrays/pipeline-xray/` (all files) | N/A | `DEV_ONLY` | HTML/JS diagnostics interface. | Low |

---

## 3. Important Exceptions & Safe Harbor Rules
During the reference scan, I verified that the following files are active despite having low static references:
- **`StoreKitTestHarness.swift`:** Referenced dynamically in debug schemes and diagnostic menus.
- **`RAGAppIntents.swift` and `VisualIntelligenceIntents.swift`:** Registered as system-discoverable app shortcuts, which are called via reflection-like hooks by iOS rather than static references.
- **Assets (`Assets.xcassets`):** Referenced via string keys in SwiftUI image builders.
