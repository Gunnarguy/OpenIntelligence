> **Documentation status:** Corrected 2026-09-29. How OpenIntelligence routes to Private Cloud Compute, and every gate, consent and fallback rule on that route, is in [`Docs/PRIVACY_AND_ROUTING.md`](../PRIVACY_AND_ROUTING.md), which wins where this page disagrees. This page keeps Apple's own PCC summary and the claim boundaries. Until 2026-09-29 this block read "Verified for OpenIntelligence v4.3 on 2026-06-20" and named the codebase audit in `Docs/AUDIT/` as the source of truth; both predate PCC shipping in 5.2 on 2026-09-10. `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/SHIPPED_CAPABILITIES.json:100-108]`

# Private Cloud Compute (PCC) Security Architecture Reference

> **Primary source**: [Apple Security: Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)
> **Research source**: [Apple Security: PCC security research](https://security.apple.com/blog/pcc-security-research/)
> **Last Verified**: April 24, 2026

This document exists so OpenIntelligence does not overclaim PCC. PCC is Apple's cloud AI privacy architecture. OpenIntelligence does not own a PCC endpoint and cannot pick among Apple's server models: `PrivateCloudComputeLanguageModel` is the only server model class in the FoundationModels SDK, and since 5.2 the app requests it directly on iOS/macOS 27. Copy may say, citing Apple, that PCC has a larger context window than the device; [`HARD_LIMITS.md`](./HARD_LIMITS.md) asks it not to name a size. Corrected 2026-09-29: this paragraph said the app does not directly select Apple's server model and should not claim a larger context window through PCC at all, which 5.2 and Apple's PCC documentation have overtaken. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift:86-102; FoundationModels.swiftinterface:45,98,260,295 in the iPhoneOS SDK of Xcode 27.0 (27A266a), whose only two LanguageModel conformances are PrivateCloudComputeLanguageModel and SystemLanguageModel]`

## What PCC Is

Private Cloud Compute is Apple's cloud inference system for Apple Intelligence features that need more compute than the local device can provide. Apple designed PCC to extend device-style privacy guarantees into cloud inference through Apple Silicon servers, a hardened OS, end-to-end encryption to validated PCC nodes, target diffusion, stateless processing, and public transparency logs.

PCC matters to OpenIntelligence as its one optional remote target: on iOS/macOS 27 the final answer may be generated there, after consent. The product should still be documented as local-first and Apple-native, because ingestion, indexing, retrieval and ranking stay on device. Corrected 2026-09-29: this sentence called PCC platform context only and ended "not as an app with direct access to Apple's server model", which 5.2 overtook. `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/PRIVACY_AND_ROUTING.md:7,116; Docs/SHIPPED_CAPABILITIES.json:102]`

## Five Core Requirements

| # | Requirement | What It Means |
| --- | --- | --- |
| 1 | Stateless computation | User data is processed for the request and then deleted. |
| 2 | Enforceable guarantees | Privacy properties are technically enforced rather than just policy promises. |
| 3 | No privileged runtime access | Apple SRE staff cannot use shells or debuggers to bypass privacy guarantees. |
| 4 | Non-targetability | Requests cannot be routed to a specific node for a targeted user attack without broader system compromise. |
| 5 | Verifiable transparency | Production PCC software images and measurements are made available for independent inspection. |

## Hardware and Software Stack

- Custom Apple Silicon server hardware.
- Secure Enclave and Secure Boot lineage.
- Hardened subset of iOS/macOS foundations for inference.
- No general-purpose remote shell or debugging path.
- Code signing and trust-cache enforcement.
- Sandbox isolation for inference processes.
- Public research tooling and transparency logs for PCC software releases.

## Data Flow

```text
User device
  -> validates PCC node software/certificates
  -> encrypts request to validated node public keys
  -> sends through relay/load-balancing infrastructure

PCC node
  -> decrypts inside trusted node boundary
  -> runs inference
  -> returns response
  -> deletes user data
```

## What This Means for OpenIntelligence

OpenIntelligence leverages Apple's public Foundation Models framework. The app supports dynamic route selection policies, routing standard/offline queries to `SystemLanguageModel.default` and reasoning-heavy or context-overflow queries to `PrivateCloudComputeLanguageModel`.

> [!IMPORTANT]
> OpenIntelligence runs Private Cloud Compute through `FoundationModels.PrivateCloudComputeLanguageModel`, which Apple introduced in iOS/macOS 27.0, and only on 27 or later. From 5.2 on, a release guard fails any build that lacks its symbols. Retrieval and ranking always stay on device. Final answer synthesis can go there. The intermediate Deep Think and Maximum reasoning sessions stay on device unless Private Cloud Compute is chosen in the model picker, which lifts their on-device pin (`AgenticOrchestrator.swift:9000-9014`, since `6f29d2d`, 2026-07-30); every call that goes passes the same consent check (`RAGService.swift:3676-3740`). On iOS/macOS 26 nothing is simulated: the route policy and the capability snapshot both report PCC unavailable, and a PCC route that reaches the session factory throws `LLMError.modelUnavailable` rather than running a local session under the PCC label. If a planned PCC answer fails before any text has streamed, the app retries it on device, and when that succeeds the execution receipt records PCC as intended and on-device as completed. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift:86-110; FoundationModelRoutePolicy.swift:121-132; FoundationModelCapabilityProvider.swift:36-37,90-104; RAGService.swift:16693-16757]` `[evidence_level: documented, confidence: high, evidence_source: https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel (introducedAt 27.0 on every listed platform), fetched 2026-09-29]` `[evidence_level: artifact_derived, confidence: high, evidence_source: Docs/SHIPPED_CAPABILITIES.json:108 (from 5.2 the release guard fails a build with zero PrivateCloudCompute symbols)]`
>
> Corrected 2026-09-29. This block said that on iOS/macOS 26.x "PCC routes fall back cleanly to local simulation on `SystemLanguageModel.default` using a compatibility wrapper (`EngineSDKCompatibility.swift`)". That was true when it was written on 2026-06-27: the file then defined a local stand-in named `PrivateCloudComputeLanguageModel`, whose session initializers built the session on `SystemLanguageModel.default`. Commit `c6052df` removed the stand-in on 2026-07-15. The file now holds engine-SDK stubs and `EntitlementChecker`, and nothing that substitutes a model or a route. `[evidence_level: code_verified, confidence: exact, evidence_source: git show c6052df -- OpenIntelligence/Core/Support/EngineSDKCompatibility.swift; EngineSDKCompatibility.swift:1-149,156-223]`

The safe implementation assumptions are:

1. Local on-device sessions are budgeted from the window the SDK reports (`SystemLanguageModel.default.contextSize`), with 4,096 tokens as the fallback where that API is unavailable (`FoundationModelTokenBudget.swift:28-35`, corrected 2026-09-29).
2. The execution plan budgets Private Cloud Compute (PCC) sessions from the context size the SDK reports at runtime (`PrivateCloudComputeLanguageModel.contextSize`, an async property). Apple documents that window as 32K tokens, and the sample code in WWDC26 session 319 gives it as 32768. The app's own `32768` is a hardcoded synchronous fallback: the execution planner does not use it, but context assembly for a PCC-eligible question sizes the evidence it prepares from it (`RAGService.swift:12674`, `FoundationModelTokenBudget.swift:39`), and [`HARD_LIMITS.md`](./HARD_LIMITS.md) records it as not measured. On the automatic path PCC is chosen when the local budget does not fit, or when the evidence needs multi-document synthesis in Deep Think or Maximum, and only when the gates in `Docs/PRIVACY_AND_ROUTING.md` pass. Corrected 2026-09-29: this line gave "32,768 tokens" as the app's PCC budget. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelCapabilityProvider.swift:74; RAGService.swift:16288-16310; ModelExecutionPlanner.swift:77-89,132; FoundationModelTokenBudget.swift:37-39]` `[evidence_level: documented, confidence: high, evidence_source: https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute (capability table, 4K against 32K) and https://developer.apple.com/videos/play/wwdc2026/319/ (code at 5:58), both fetched 2026-09-29]`
3. The app does not own the PCC servers, but leverages Apple's OS-level PCC execution API.
4. Simulator behavior is not production behavior; Apple Intelligence availability needs physical-device validation.
5. Core privacy copy should focus on local document parsing, local indexes, and Apple-native generation where supported.

## What Not To Say

- "OpenIntelligence operates its own Private Cloud Compute servers."
- "OpenIntelligence gets a 65K local context window."
- "PCC makes the app compliant with regulated workflow requirements."
- "The app can override Apple's cloud routing safety rules."

## What To Say

- "OpenIntelligence routes the final answer between the on-device model and Apple's Private Cloud Compute, depending on the selected quality mode, the evidence and the context size; with Private Cloud Compute chosen in the model picker, Deep Think and Maximum can send their reasoning passes there too. PCC is used only on iOS and macOS 27, and only after you consent." Corrected 2026-09-29: this line gave the two windows as 4K and 32K. Those are Apple's documented figures, not ones the app measured, and `HARD_LIMITS.md` asks public copy not to name a PCC size; where a number is needed, attribute it to Apple.
- "The app keeps core document ingestion, indexing, retrieval, and storage local."
- "PCC is Apple's native privacy-safe cloud architecture, accessed via official OS APIs."

## Adapter Note

Apple documents adapter support for Foundation Models, but OpenIntelligence should only market adapters after the app has a built, signed, distributed, and evaluated adapter flow.

Potential requirements:

- Adapter entitlement and distribution path.
- Per-model-version retraining plan.
- Background Assets or equivalent delivery.
- Evaluation proving domain improvement without hurting citation faithfulness.

## References

- [Private Cloud Compute Blog Post](https://security.apple.com/blog/private-cloud-compute/)
- [Security research on Private Cloud Compute](https://security.apple.com/blog/pcc-security-research/)
- [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute) (added 2026-09-29)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple Security Bounty](https://security.apple.com/bounty/)
