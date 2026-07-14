# Docs/PRIVACY_AND_ROUTING.md — OpenIntelligence v4.4 (working on v4.5)

> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

This document describes the privacy guardrails, local execution boundaries, and Private Cloud Compute (PCC) routing logic in OpenIntelligence v4.4.

---

## 1. Local-First Privacy Model

OpenIntelligence was built as a local-first application. All core operations—text extraction, layout analysis, OCR, vector database queries, lexical index lookups, and response verification—run entirely on the user's device.
- **Zero Third-Party AI Sharing:** No data, documents, or user queries are sent to external APIs (e.g. OpenAI, Anthropic) or shared with third-party servers.
- **Local Databases:** Vector indices are written directly to your device's sandbox in memory-mapped BNNS vector files, and text is cached locally in SQLite.

---

## 2. On-Device vs. PCC Routing Logic

To support larger query contexts and complex queries, the app implements a dynamic routing policy defined in [FoundationModelRoutePolicy.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift):

### 1. On-Device Execution (Default)
- **Scope:** Standard query modes.
- **Constraints:** Max context window is capped at **4,096 tokens**.
- **Model Resolution:** The app always executes `SystemLanguageModel.default` for on-device queries. The installed SDK exposes no separate advanced/20B on-device model API (v4.6, compiler-probe verified); if the OS resolves different underlying weights on high-memory hardware, that happens behind `.default` and is opaque to the app. As of v4.6, route telemetry reports the executed route (`.onDevice`) truthfully regardless of the selected preference.
- **Programmatic Enforcement:** A memory verification check (`physicalMemory >= 11.5GB`) gates the manual selector and dynamic router. If physical memory is insufficient, the app hides the "Advanced" picker preference and uses the standard on-device route.

### 2. PCC Escalation
- **Entitlement gating (v4.6):** `EntitlementChecker` now **fails closed** — if entitlement presence cannot be proven from an embedded provisioning profile (including the macOS `embedded.provisionprofile` name), the PCC route throws `LLMError.modelUnavailable` and the query runs on-device. Distribution builds can no longer instantiate native PCC unentitled.
- **Scope:** Escalated queries where the context/history size exceeds 4,096 tokens, or when the user selects **Deep Think** or **Maximum** modes.
- **Target:** Apple's secure Private Cloud Compute (PCC) enclaves, running the cloud-based **AFM 3 Cloud Pro** model (70B+ parameters) with up to a **32,768-token** context window.

---

## 3. Native PCC Execution and Simulated Fallback

> [!NOTE]
> When running on iOS 27 / macOS 27+, OpenIntelligence utilizes native Apple Private Cloud Compute (PCC) execution via `FoundationModels.PrivateCloudComputeLanguageModel` for all escalated query pathways (Deep Think/Maximum modes, or contexts exceeding 4,096 tokens). This routes queries over encrypted channels to Apple's secure server enclaves.
> 
> To prevent fatal process crashes on developer builds that lack the `com.apple.developer.private-cloud-compute` developer entitlement, a runtime signature check (`EntitlementChecker`) verifies the signature. If the entitlement is missing, or if running on older OS versions (iOS/macOS 26.x), PCC routes fall back cleanly to local simulation on `SystemLanguageModel.default` using the compatibility wrapper in [EngineSDKCompatibility.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/OpenIntelligence/Core/Support/EngineSDKCompatibility.swift).

---

## 4. Consent and Controls
Local user consent dialogs (`CloudConsentPromptView.swift`) were built to manage permission. If a user denies PCC permissions, the system blocks the PCC route policy and forces standard local execution (retaining the strict 4,096 context cap and refusing to escalate).
