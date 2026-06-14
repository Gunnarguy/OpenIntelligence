# Docs/PRIVACY_AND_ROUTING.md — OpenIntelligence v4.1

> **Documentation status:** Verified for OpenIntelligence v4.1 on 2026-06-13.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

This document describes the privacy guardrails, local execution boundaries, and simulated Private Cloud Compute (PCC) routing logic in OpenIntelligence v4.1.

---

## 1. Local-First Privacy Model

I built OpenIntelligence as a local-first application. All core operations—text extraction, layout analysis, OCR, vector database queries, lexical index lookups, and response verification—run entirely on the user's device.
- **Zero Third-Party AI Sharing:** No data, documents, or user queries are sent to external APIs (e.g. OpenAI, Anthropic) or shared with third-party servers.
- **Local Databases:** Vector indices are written directly to your device's sandbox in memory-mapped BNNS vector files, and text is cached locally in SQLite.

---

## 2. On-Device vs. PCC Routing Logic

To support larger query contexts and complex queries, the app implements a dynamic routing policy defined in [FoundationModelRoutePolicy.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift):

### 1. On-Device Execution (Default)
- **Scope:** Standard query modes.
- **Constraints:** Max context window is capped at **4,096 tokens**.
- **Model:** Executes locally using `SystemLanguageModel.default`.

### 2. PCC Escalation
- **Scope:** Escalated queries where the context/history size exceeds 4,096 tokens, or when the user selects **Deep Think** or **Maximum** modes.
- **Target:** Apple's secure Private Cloud Compute (PCC) enclaves, supporting up to a **32,768-token** context window.

---

## 3. Current Code Reality: PCC Simulation

> [!WARNING]
> While the model routing policy maps routes to remote Private Cloud Compute, remote enclave execution is not compiled in or active in the current codebase.
>
> All elevated PCC routes are resolved locally on `SystemLanguageModel.default` using a compatibility wrapper in [EngineSDKCompatibility.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Core/Support/EngineSDKCompatibility.swift). The app compiles and runs entirely on-device, and no remote attestation or network-enclave execution is active.

---

## 4. Consent and Controls
I built local user consent dialogs (`CloudConsentPromptView.swift`) to manage permission. If a user denies PCC permissions, the system blocks the PCC route policy and forces standard local execution (retaining the strict 4,096 context cap and refusing to escalate).
