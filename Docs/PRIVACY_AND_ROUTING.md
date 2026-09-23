# Privacy and Model Routing — source-verified at v4.6, shipped tree is v5.3

> **Documentation status:** Source-verified on 2026-07-15 against v4.6. **Not re-verified since.** **iOS 5.3** and **macOS 5.3** are the shipped versions (both READY_FOR_SALE 2026-09-18, build 464, released manually after approval); `Docs/SHIPPED_VERSION.json` is the per-platform record. Corrected 2026-09-01, having said 4.9 since July; 5.1 recorded 2026-09-02, 5.2 recorded 2026-09-11, 5.3 recorded 2026-09-20. **Private Cloud Compute shipped in 5.2 on 2026-09-10 and is live on both platforms**; `Docs/SHIPPED_CAPABILITIES.json` carries it as `shipping`, so present-tense copy about it is correct. Native PCC execution is owner-confirmed on a physical device (2026-07-28). Signed physical-device installation, Archive/TestFlight entitlement propagation, quota-exhaustion, network-transition, and background/App Intent validation remain pending.
> **Note on the routing picker:** until 2026-07-30 the stored routing policy did not govern Deep Think or Maximum, and an On-Device selection could still send a minimized envelope to PCC. Consent was never bypassed. Fixed in `6f29d2d`; see `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` §8. If you are reading this document to answer a question about what a routing setting guaranteed *before* that date, the answer differs from what is described below.
> **Source of truth:** `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` and the current implementation.

OpenIntelligence is local-first. Extraction, OCR, embeddings, vector and lexical retrieval, evidence scoring, route planning, transcript handling, and response verification run on the device. No document or query content is sent to a third-party AI provider. Apple Private Cloud Compute (PCC) is the only remote model target.

## Public execution targets

- **On-device:** `SystemLanguageModel.default` on supported Apple Intelligence devices.
- **Private Cloud Compute:** `FoundationModels.PrivateCloudComputeLanguageModel` on iOS/macOS 27+ when every capability and consent gate passes.

The public SDK does not expose separately selectable 3B, 20B, Advanced, or server parameter-count identities. OpenIntelligence therefore does not claim those models. iOS/macOS 26 is genuinely local-only; local generation is never labeled or simulated as PCC. `[evidence_level: compile_verified+code_verified, confidence: exact, evidence_source: FoundationModelSessionFactory.swift, EngineSDKCompatibility.swift]`

### Reasoning level is the only tier the public SDK offers, and it is PCC-only

Apple's own system UI on iOS 27 presents a model picker naming "Cloud" and "Cloud Pro". **Neither is reachable from a third-party app.** The public SDK declares exactly one server model class, `PrivateCloudComputeLanguageModel`, and no model-choice, tier, or variant type exists in any public framework. What third parties get instead is `ContextOptions.reasoningLevel`, new in iOS/macOS 27, whose cases are `.light`, `.moderate`, `.deep` and `.custom(String)`.

Apple's capability table states it directly: reasoning is **not supported** on-device and has **multiple levels** on PCC, alongside a 4K to 32K context increase. So the app sends a reasoning level only on the PCC route and never on-device, because the on-device model has no such knob; `GenerationOptions` carries only sampling, temperature, response tokens, and tool-calling mode.

`AppleFoundationModelRoute.reasoningLevel` is the single mapping from `PCCReasoningLevel` to Apple's enum, and `contextOptions(includeSchemaInPrompt:)` builds the value each call site passes. The parameter is not cosmetic: `ContextOptions` is a defaulted argument on **every** `respond` and `streamResponse` overload, so a call site that omits it silently runs at Apple's default effort rather than failing. Until 2026-09-10 one of the app's twenty-five generation call sites passed it, which meant Deep Think and Maximum advertised highest-effort reasoning and frequently did not request any. The streaming, continuation, structured and prose-fallback paths now all pass it.

`includeSchemaInPrompt` must be threaded rather than defaulted. The guided-generation overloads default it to `true` while the plain overloads leave it `nil`, and supplying any `ContextOptions` replaces that default wholesale, so handing a structured call a bare `ContextOptions(reasoningLevel:)` would quietly stop including the schema.

Auxiliary Foundation Models calls (HyDE, cluster labels, smart replies, suggested questions, contextual compression, tagging) deliberately send no reasoning level. They are internal utility generations, not the user's answer, and spending PCC reasoning quota on a cluster label is waste.

`[evidence_level: code_verified+build_verified, confidence: exact, evidence_source: FoundationModels.swiftinterface in the iOS 27 SDK (Xcode 27A5194q) — ContextOptions is @available(iOS 27.0, ...) with cases light/moderate/deep/custom, and is the only tier-like type across every public framework interface; https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute capability table, fetched 2026-09-10; Swift 6.4 build 2026-09-10 links ContextOptions symbols with a non-zero SystemLanguageModel control]`

## Post-retrieval decision flow

```mermaid
flowchart TD
  Q[Query] --> R[Local retrieval and evidence assembly]
  R --> P[ModelExecutionPlanner]
  C[User policy, network, foreground state] --> P
  S[Signed entitlement, availability, quota, context] --> P
  P -->|Insufficient evidence| A[Grounded abstention]
  P -->|Fits or privacy requires local| L[On-device synthesis]
  P -->|Evidence-sufficient PCC candidate| M[Minimize evidence envelope]
  M --> G{Consent valid for this payload?}
  K[Canonical remembered consent; no launch prompt] --> G
  G -->|Yes| X[Immediate quota and availability recheck]
  X --> PCC[Native PCC synthesis]
  G -->|Denied or UI unavailable| F[Declared on-device fallback]
  L --> V[Deterministic local verification]
  PCC --> V
  F --> V
  V --> T[Durable execution receipt]
```

`QueryRuntimeCoordinator` preserves the user's policy but does not predict a final route. After retrieval, `ModelExecutionPlanner` evaluates:

- evidence sufficiency, score distribution, context size, and multi-document synthesis need;
- automatic, on-device-only, prefer-cloud, or cloud-only policy;
- network and foreground/background state;
- signed PCC entitlement, live availability, live quota, and SDK-reported context size;
- whether the app is foreground-interactive, **now on macOS as well**. That input gates cloud alongside remembered consent, and until 2026-08-11 it was computed inside `#if canImport(UIKit)` with the `#else` branch hardcoding `true`. A backgrounded Shortcut on a Mac therefore reported itself foreground-interactive and could reach PCC with nobody present to answer the consent sheet, which is the case the gate exists to prevent. macOS reads `NSApplication.shared.isActive` now, and a platform with no UI framework falls closed to `false`. `[evidence_level: code_verified+build_verified, confidence: exact, evidence_source: RAGService.swift makePostRetrievalModelPlan]`;
- exact SDK token counts where available, otherwise a receipt-labeled conservative estimate.

Escalation never substitutes for missing evidence. Weak or irrelevant retrieval abstains or stays local according to the grounding policy. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift, FoundationModelTokenBudget.swift, RAGService.swift]`

### Correction: the policy did not reach Deep Think or Maximum before 2026-07-30

Recorded here because this document asserts the routing policy as a privacy guarantee, and for the agentic modes that assertion was not true.

`AgenticOrchestrator.generateWithProperConsent` constructed a fresh `InferenceConfig` from only `maxTokens`, `temperature`, and `systemPrompt`. `fmPreference`, `executionContext`, and `allowPrivateCloudCompute` therefore fell back to their defaults (`.automatic`, `.automatic`, `true`) even though `ChatScreen` had already assembled a config carrying the user's actual selection. The second bullet above — *"automatic, on-device-only, prefer-cloud, or cloud-only policy"* — was evaluated against a default, not against what the user chose.

Three physical-device runs, one per picker setting, were identical in routing. **With the picker on On-Device, a minimized evidence envelope of 16,642 bytes across 20 chunks was still sent to PCC, and the UI labeled it "(User Selected)".**

Scope, stated precisely:

- The consent gate was **not** bypassed. `consentState` is read independently of the picker, and `.denied` genuinely blocked PCC. The observed runs carried a remembered grant from a prior explicit allow.
- The destination was Apple PCC under the same minimization and entitlement gates described below. No third-party provider was involved, and no additional data left the device beyond the normal PCC envelope.
- What failed is narrower and still serious: **the picker and the `allowPrivateCloudCompute` setting did not restrict routing in the two modes that transmit the most.** A user who granted PCC consent once and later selected On-Device would not get on-device-only behavior.
- Standard was unaffected throughout. It consumes the `ChatScreen` config directly, derives `pccEligible` from those fields, and sizes packed context to match.

Fixed in `6f29d2d`. `RAGService` captures a `UserRoutingPreference` per query and applies it to the config before planning, so `allowsPCC` reflects the real selection. On-Device is absolute and covers final synthesis, not only the reasoning sessions. Query expansion and planning remain local under every setting by design.

`[evidence_level: device_verified_for_the_defect+build_verified+test_verified_for_the_fix, confidence: high_for_the_defect_unverified_on_device_for_the_fix, evidence_source: PCC/On-Device/Hybrid device logs 2026-07-30, ChatScreen.swift:2626, AgenticOrchestrator.swift, RAGService.swift]`

## Entitlement, OS, and quota gates

Apple approval of `com.apple.developer.private-cloud-compute` was confirmed by the user on 2026-07-15, and the source entitlement is enabled. Runtime evidence is platform-specific: native macOS uses Security.framework `SecTask`; iOS/Catalyst development and ad-hoc builds parse the embedded signed provisioning profile; App Store/TestFlight builds that omit that profile allow only the approved PCC key to continue to Apple's documented `PrivateCloudComputeLanguageModel.availability` and quota checks. The branch passes a generic arm64 iPhoneOS compile gate, while signed installation and distribution runtime validation remain pending. `[evidence_level: build_verified+sdk_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution]`

Before PCC construction, the app verifies:

1. iOS/macOS 27 availability;
2. signed entitlement presence;
3. `PrivateCloudComputeLanguageModel` availability;
4. quota is not exhausted;
5. network and policy permit PCC;
6. the planned envelope fits the live context budget.

Quota is rechecked immediately before the model is constructed. A quota failure is not retried on PCC. Unknown future SDK quota states map to `.unknown` through Swift's `@unknown default` handling and therefore do not authorize PCC.

**Corrected 2026-08-11. That last sentence was true of the mapping and false of the consequence, for as long as it has been written here.** `FoundationModelCapabilitySnapshot.canUsePCC` tested `pccQuota != .limitReached` alone, so `.unknown` authorized a cloud attempt. Three places already asserted the opposite: this paragraph, `RouteEvalMetrics.RouteInvariant.quotaFailClosed` ("`.limitReached`, `.unsupported`, and `.unknown` are all fail-closed states"), and `ModelExecutionReceipt.nonAuthorizingQuotaStates`. Only the planner disagreed, and it is the one that decides. The rule now exists once as `PCCQuotaState.authorizesCloudExecution`, exhaustive over the enum, and both the planner and the scorer derive from it. Found by reconciling the roadmap against code; no test covered this path, and `PCCQuotaAuthorizationTests` covers it now. `[evidence_level: code_verified+test_verified, confidence: exact, evidence_source: ModelExecutionPlan.swift PCCQuotaState.authorizesCloudExecution and canUsePCC, RouteEvalMetrics.swift]` Hybrid and explicit PCC policy use the declared local fallback before meaningful streaming; the receipt retains PCC as intended and on-device as completed. `[evidence_level: code_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution, evidence_source: FoundationModelCapabilityProvider.swift, FoundationModelSessionFactory.swift, ModelExecutionPlanner.swift, LLMService.swift, OpenIntelligence.entitlements]`

## Evidence minimization and consent

PCC consent happens only after the route and cloud evidence envelope are final. `CloudEvidenceMinimizer` selects a bounded set of source IDs, names, page numbers, and text. The consent sheet displays provider/model, prompt size, context size, chunk count, total estimated bytes, and the machine-readable route reason.

- **Allow once:** grants the current in-process PCC provider session.
- **Always allow:** persists provider consent; each transmission still produces a local record.
- **Deny:** blocks PCC. Hybrid and explicit PCC policy use the on-device fallback and label the answer accordingly.

Background and App Intent execution never waits for a foreground consent sheet. Remembered consent may permit PCC; otherwise Hybrid and explicit PCC policy complete through the declared on-device fallback. `[evidence_level: code_verified, confidence: high, evidence_source: RAGService.swift, CloudConsentPromptView.swift, AgenticOrchestrator.swift]`

`cloudConsent.applePCC` is the canonical remembered value. On upgrade, the legacy PCC picker is synchronized to that value; it cannot erase an explicit allow/deny decision. Selecting Ask removes the canonical decision. App launch loads consent state but does not pre-create a transmission record or present the sheet, so a prompt is tied only to a real finalized post-retrieval envelope. `[evidence_level: code_verified+test_verified, confidence: high_pending_physical_device_validation, evidence_source: SettingsStore.swift, RAGService.swift, PCCConsentPreferenceMigrationTests.swift]`

## Fallback and stream integrity

- PCC may fall back to on-device only before meaningful response text has streamed.
- Once a meaningful partial response exists, OpenIntelligence returns that single-target partial response rather than mixing cloud and local output.
- PCC is not automatically retried after quota failure.
- Intermediate Deep Think/Maximum reasoning sessions stay on-device; only final post-retrieval synthesis may be selected for PCC.
- Streaming follows the same line (5.5): in Deep Think and Maximum only the calls that write the final answer stream text to the chat; `AgenticOrchestrator.execute` holds the chat's handler back from every intermediate call. Where a final synthesis goes to PCC, the consent prompt still comes before any of its text streams. A short Standard answer on the structured path now streams its `answer` field as it is generated instead of replaying it; routing and consent for that call are unchanged.
- Retrieval evidence and citation verification remain local even when synthesis uses PCC.

`[evidence_level: code_verified, confidence: high, evidence_source: RAGService.generateWithFallback, AgenticOrchestrator.generateWithFreshSession]`

## Route telemetry

### What Apple reports, as distinct from what the app decided

`LanguageModelSession.usage` (iOS/macOS 27) is the only outcome-based evidence available about a
generation. `LanguageModelSession.Response` declares `content`, `rawContent`, `transcriptEntries`
and `usage`, and **nothing naming the backend**, so there is no way to ask Apple which model
served a request. `actualRoute` remains the app's own record of what it selected, which is a
statement of intent.

`usage.output.reasoningTokenCount` is the useful counterpart. Apple's capability table lists
reasoning as unsupported on-device and available in multiple levels on Private Cloud Compute, so a
non-zero reasoning count is positive evidence that a reasoning-capable backend did the work. Zero
reasoning tokens on a route recorded as PCC with Deep Think or Maximum selected is a contradiction
worth investigating rather than a value to display.

This is telemetry of counts and public target names, which section 8 permits. It records no query,
document, transcript or reasoning **content**, which section 8 forbids.

`[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModels.swiftinterface, Xcode 27A266a: LanguageModelSession.usage is @available(iOS 27.0, macOS 27.0, ...); Usage.Output declares totalTokenCount and reasoningTokenCount; Usage.Input declares totalTokenCount and cachedTokenCount; Response declares no backend field]`



`ModelExecutionReceipt` is the durable route truth. It records plan/policy IDs, timestamps, reason codes, intended target, attempts, actual target, fallback reason, completed target, quota category, and verification result. `ResponseMetadata.executionRoute` is a compatibility summary derived from the completed receipt.

Telemetry may include identifiers, public target names, counts, budgets, hashes, quota categories, reason codes, and verification status. It must not include raw query text, document text, transcript content, or generated reasoning. Historical responses remain readable because receipt metadata is optional. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionReceipt.swift, RAGQuery.swift, LLMService.swift]`

### The unified-log line, so a TestFlight build can be observed at all

Until 2026-09-14 a Release build wrote **nothing** about routing to the unified logging system.
Every route-naming statement went through the `Log` facade, whose only console output is a
`print()` inside `#if DEBUG`; `print` reaches stdout and never Console.app; and Release defaults the
facade to `.error` with no categories enabled. `actualRoute` therefore existed only inside the app.

`RouteLog` (`Services/Infrastructure/Configuration/RouteLog.swift`) now writes one `notice`-level
line at the start of each generation and one at its end, to subsystem
`Gunndamental.OpenIntelligence`, category `routing`, from both generation paths in `LLMService`.
The line carries exactly: the actual target and the intended target (`ModelExecutionTarget` raw
values), the fallback reason (`ModelRouteReason` raw value or `none`), the Private Cloud Compute
reasoning level (`PCCReasoningLevel` raw value, only when that route ran), the attempt count, the
first eight characters of the plan UUID, and the policy version constant. Its API accepts only
those types, so no call site can hand it a query, a passage or an answer. Every interpolation is
marked `privacy: .public` because the unified log otherwise renders dynamic strings as `<private>`,
and each of these is a public target name or a code by construction. This is the section 8
allowance for public target names, reason codes and counts, applied to the unified log.

It deliberately bypasses the `Log` facade rather than adding a unified-log sink to it: the
facade's `.llm` lines can carry prompt and response text at debug level, which section 8 forbids
from any telemetry surface.

`[evidence_level: code_verified, confidence: exact, evidence_source: RouteLog.swift; LLMService.swift RouteLog.started/completed call sites; RouteLogLineTests pins the vocabulary; SDK check 2026-09-14: Logger.notice and OSLogPrivacy in iPhoneOS27.0.sdk os.swiftinterface]`

## Validation boundary

Private Cloud Compute shipped in 5.2 on 2026-09-10 and is live on both platforms, so the open question is no longer whether it reaches users but which of its paths have been exercised on a signed iOS 27 device and distribution artifact. These are still unconfirmed and are tracked as open items rather than assumed: entitlement inspection on a distribution artifact, intended-versus-actual receipt confirmation, consent allow/deny/revoke, App Intent and background behavior, quota approach and exhaustion, offline and mid-request network changes, and physical-device thermal and battery checks. Native PCC execution itself is owner-confirmed on a physical device (2026-07-28). `[evidence_level: code_verified, confidence: exact_for_unverified_status, evidence_source: PCC dynamic routing test matrix; Docs/SHIPPED_CAPABILITIES.json private_cloud_compute status `shipping` since 2026-09-10; Docs/SHIPPED_VERSION.json]`


## Adaptive profiles do not change routing (added 2026-09-11)

`FoundationModelDynamicProfileRegistry` chooses `temperature` and `maxTokens` from the answer
intent. It has no effect on **where** a request runs.

Routing stays entirely in `FoundationModelRoutePolicy`, which reads the explicit model preference
first, then the execution plan, then the context estimate against the on-device window. The
registry is not consulted there and cannot escalate a request to Private Cloud Compute, cannot
suppress one, and cannot alter the consent prompt. A profile changes how the chosen model samples,
not which model is chosen or what leaves the device.

This is worth stating because the registry's previous shape could have affected routing
indirectly: it produced a full replacement `systemPrompt`, and prompt length feeds the token
estimate that the planless routing branch compares against the on-device context window. Producing
generation parameters only removes that coupling.

`[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelDynamicProfileRegistry.swift returns FoundationModelGenerationProfile only; FoundationModelRoutePolicy.determineRoute has no reference to it]`


## A reasoning profile you write yourself (added 2026-09-11)

`ContextOptions.ReasoningLevel` has a fourth case besides `light`, `moderate` and `deep`:
`custom(String)`. It carries free text describing how the model should approach the problem. The
named levels are a dial; this is a sentence. `AppleFoundationModelRoute.reasoningLevel` reads
`UserDefaults` key `customReasoningProfile` and substitutes `.custom(...)` when it is non-empty.

**What this does and does not touch, since it is text the owner wrote reaching Apple's servers:**

- **It is not the app's reasoning, and the distinction matters.** Deep Think and Maximum run their
  own multi-session reasoning through `executeReasoningChain`, `executeTrueUnlimitedReasoning`,
  `executeMultiChainReasoning` and `executeRecursiveResearch`, and four of those call sites pass
  `forceOnDevice: true`. That reasoning happens on the device and a written profile does not touch
  it. What this field controls is Apple's **model-internal** reasoning setting, the effort spent
  inside one generation.
- It therefore applies **only on the Private Cloud Compute route.** Apple's capability table lists
  that setting as unsupported on-device and `GenerationOptions` carries no equivalent, so an
  on-device generation has no reasoning level to replace. Pinned by
  `testAProfileDoesNotLeakOntoTheOnDeviceRoute`. **Read carefully:** this says Apple's model does
  not expose a reasoning dial on device. It does not say this app does not reason on device, which
  is the opposite of true and is exactly the conflation the first draft of the settings copy
  shipped.
- It **cannot start reasoning that was not already going to happen.** `.none` means the query type
  does not warrant the spend, and the substitution is skipped for it. Without that guard a profile
  reading "think very hard about everything" would convert every cheap lookup into a billed PCC
  reasoning request. Pinned by `testAProfileDoesNotStartReasoningWhereThereWasNone`.
- It changes **nothing about routing**: not whether a request goes to PCC, not the consent prompt,
  not what evidence is attached. It describes how the model should think once a request has already
  been approved and sent.
- The text is **sent to Apple as part of the request** on a PCC route, under the same end-to-end
  encrypted, non-retained terms as the rest of that request. Anyone writing a profile should
  understand it leaves the device exactly as the question and the approved passages do. The
  Model Parameters footer says where it applies; this is the privacy statement behind it.

`[evidence_level: test_verified, confidence: high, evidence_source: FoundationModelRoute.swift reasoningLevel; CustomReasoningProfileTests, 6 cases; ReasoningLevel.custom read from iPhoneOS27.0.sdk FoundationModels.swiftinterface]`
