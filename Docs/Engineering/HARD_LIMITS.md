# OpenIntelligence Hard Limits and Claim Constraints

**Purpose**: Single source of truth for current technical constraints and the claim boundaries they create.
**Last Verified**: LLM-constraints table and its notes partially re-verified 2026-09-29 against the 5.5 tree (HEAD `8be003a`); everything else as dated below.

> **What 2026-09-29 covers.** The LLM-constraints table and the implementation notes under it were re-checked
> against source and against Apple's documentation. Three statements no longer held: the planless routing
> branch reads the SDK's on-device window instead of a literal 4096 (commit `176e32c`, 2026-08-06), PCC is an
> iOS/macOS 27 API rather than 26, and the bundled sample documents stopped asserting a 32K PCC window
> (commit `cd72250`, 2026-08-05). `32768` is still a hardcoded fallback at `FoundationModelTokenBudget.swift:39`.
> The measured-throughput section and the claim lists were not re-checked that day.
> `[evidence_level: code_verified, confidence: exact_for_the_re-checked_rows, evidence_source: FoundationModelRoutePolicy.swift:71,121-132; FoundationModelTokenBudget.swift:28-40; FoundationModelSessionFactory.swift:86-110; FoundationModels.swiftinterface:43-45 in the iPhoneOS SDK of Xcode 27.0 (27A266a)]`
>
> **What 2026-08-05 covered, kept as written.** The LLM-constraints table, the routing-literal note, the measured-throughput
> section, and the claim lists below were re-checked against source on 2026-08-05: `onDeviceLimit = 4096`
> still stands at `FoundationModelRoutePolicy.swift:60` (no longer true from 2026-08-06; see above), `32768` is still a hardcoded fallback at
> `FoundationModelTokenBudget.swift:39`, and `AppleFMEmbeddingProvider.swift` is still a scaffold.
> The embedding, chunking, context-packing, and infrastructure tables still carry their April 25, 2026
> verification and were **not** re-measured. Treat those four tables as the older figure until someone
> re-runs them. `[evidence_level: code_verified_for_the_re-checked_rows, confidence: exact_for_those_rows_stale_for_the_rest]`

## Current Status

These limits describe the current public Apple path and current repo implementation.

Use them to stop overclaiming. Do not use UI copy, debug strings, or legacy comments as evidence of larger contexts, Apple embeddings, or finished SDK maturity.

## Absolute Limits

### LLM Constraints (Public Apple Foundation Models Path)

| Constraint                     | Value                                    | Why it matters                                                                     |
| ------------------------------ | ---------------------------------------- | ---------------------------------------------------------------------------------- |
| On-Device Context window       | **SDK-reported**, 4096 fallback          | `FoundationModelTokenBudget.contextSize` returns `SystemLanguageModel.default.contextSize` on iOS/macOS 26+; 4096 is only the pre-26 fallback |
| PCC Context window             | **32,768 tokens (unverified)**           | hardcoded sync fallback in `FoundationModelTokenBudget`; the real value is async on 27 and must come from `LiveFoundationModelCapabilityProvider` |
| Model size                     | **not claimed**                          | the public SDK exposes no parameter-count or model-size selector; see the v4.7 "Public Model Truth" work |
| Public PCC/server-model access | **Native iOS/macOS 27+ API**             | app integrates directly with `PrivateCloudComputeLanguageModel`; corrected 2026-09-29 from "iOS 26+" (see the notes below) |
| Recommended tool count         | **3-5 tools**                            | tool schemas eat context budget                                                    |

Important current implementation notes:

- **The routing decision uses the SDK value.** Corrected 2026-09-29: this bullet said `FoundationModelRoutePolicy` hardcodes `let onDeviceLimit = 4096` and never consults `FoundationModelTokenBudget.contextSize` or `FoundationModelCapabilityProvider`. That was true when it was written; commit `176e32c` changed it on 2026-08-06. The planless branch now sets `let onDeviceLimit = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)`, which returns `SystemLanguageModel.default.contextSize` on iOS/macOS 26 and later and 4096 only as the fallback. When a `ModelExecutionPlan` is attached the route comes from the plan, which `RAGService` sizes from the on-device and PCC context sizes in `LiveFoundationModelCapabilityProvider`'s snapshot. The route policy itself still never calls the capability provider. The difference matters on iOS 27, where the sample code in Apple's WWDC26 session 319 gives `SystemLanguageModel().contextSize` as 8192 on newer devices. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelRoutePolicy.swift:28-47,71; FoundationModelTokenBudget.swift:28-36; RAGService.swift:16288-16310]` `[evidence_level: documented, confidence: high, evidence_source: https://developer.apple.com/videos/play/wwdc2026/319/ (code at 5:58), fetched 2026-09-29]`
- **PCC is an iOS/macOS 27 API, not 26.** Corrected 2026-09-29: the table said "Native iOS 26+ API". The SDK declares `PrivateCloudComputeLanguageModel` `@available(iOS 27.0, macOS 27.0, visionOS 27.0, watchOS 27.0, *)`, and all three places the app constructs it sit behind `if #available(iOS 27.0, macOS 27.0, *)` inside `#if compiler(>=6.4)`. On 26 the session factory throws `LLMError.modelUnavailable` instead. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModels.swiftinterface:43-45 in the iPhoneOS SDK of Xcode 27.0 (27A266a); FoundationModelSessionFactory.swift:87-110; FoundationModelRoutePolicy.swift:122-129; FoundationModelCapabilityProvider.swift:36-54]` `[evidence_level: documented, confidence: high, evidence_source: https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel (introducedAt 27.0), fetched 2026-09-29]`
- **The 32,768 figure is not measured.** It is a hardcoded fallback, and the code comment on it explicitly directs routing callers to the live capability provider instead. Treat it as an upper-bound assumption, not a verified limit. ~~It is also asserted as fact in the app's own bundled documentation, which the engine then cites back to users.~~ Corrected 2026-09-29, two points. Apple does document the figure: its PCC article gives a 32K-token context, and the sample code in WWDC26 session 319 gives `PrivateCloudComputeLanguageModel().contextSize` as 32768; what stays unmeasured is the value the app receives, which it reads at runtime. And the bundled documentation no longer asserts it: commit `cd72250` removed the figure from the sample documents on 2026-08-05 and deleted the QA case that graded it, and `SampleDocumentManager.swift` contains no 32K, 32,768 or 32768 today. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelTokenBudget.swift:37-39; FoundationModelCapabilityProvider.swift:74; QualityAssuranceService.swift:290; git show cd72250]` `[evidence_level: grep_verified, confidence: high, evidence_source: grep of SampleDocumentManager.swift for 32K, 32,768 and 32768, 2026-09-29]` `[evidence_level: documented, confidence: high, evidence_source: https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute and https://developer.apple.com/videos/play/wwdc2026/319/, both fetched 2026-09-29]`
- ~~Local-first defaults are restricted to 4,096 tokens for routing purposes. Standard queries that overflow this ceiling, or queries executed under Deep Think / Maximum, are dynamically escalated to PCC via `PrivateCloudComputeLanguageModel`.~~ Corrected 2026-09-29: the local ceiling is the SDK-reported window (first bullet), and Deep Think or Maximum alone does not escalate. With no plan and the model preference on Automatic, a Standard, Deep Think or Maximum query goes to PCC only when its on-device estimate exceeds that window and PCC is allowed and available; exact lookups never do, and an explicit PCC preference skips the size check. With a plan, the automatic path escalates when the local budget does not fit, or when the evidence needs multi-document synthesis in Deep Think or Maximum, and only when the PCC budget fits and the network, consent and capability gates pass. Either way the target is `PrivateCloudComputeLanguageModel`, on iOS/macOS 27 only. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelRoutePolicy.swift:49-118; ModelExecutionPlanner.swift:77-89]`

### Measured generation throughput (physical device, 2026-07-30)

First real numbers, from an iPhone A18 Pro. These superseded the unbacked `< 0.8 s` TTFT and `≈65 tok/s` figures that the Settings capability card asserted until 2026-08-05. The card now reads `2-3 s` and `27-86 tok/s`, both labelled `A18 Pro`, so the shipped copy and this table no longer disagree.

| Path | Throughput | TTFT | Sample |
| :--- | ---: | ---: | :--- |
| On-device (`SystemLanguageModel.default`) | **27 tok/s** | 2.2–3.2 s | 340 tokens in 15.44 s |
| Private Cloud Compute | **86 tok/s** | 2.2–2.5 s | 453 tokens in 7.45 s |

**PCC is roughly 3.2× faster per token than on-device.** The claimed `≈65 tok/s` is about 2.4× optimistic for the local path and is only exceeded by PCC. No observed TTFT was under 2 seconds, so `< 0.8 s` is not supported on this hardware.

`[evidence_level: measured, confidence: high_for_this_device_unverified_across_hardware, evidence_source: four iPhone A18 Pro Deep Think runs 2026-07-30]`

### Embedding Constraints

| Constraint                   | Value                   | Why it matters                                      |
| ---------------------------- | ----------------------- | --------------------------------------------------- |
| Max Core ML embedding tokens | **510**                 | 512 minus CLS and SEP                               |
| Core embedding dimension     | **384**                 | all vectors in the main path must match             |
| Tokenizer                    | Bert tokenizer          | linguistic word count is not a safe proxy           |
| Apple FM embeddings          | **not available today** | `AppleFMEmbeddingProvider.swift` is a scaffold only |

### Chunking Constraints

| Constraint                 | Value               | Why it matters                                     |
| -------------------------- | ------------------- | -------------------------------------------------- |
| Target chunk size          | about **260** words | practical balance for retrieval                    |
| Hard chunk ceiling         | **310** words       | leaves room for contextual prefix before embedding |
| Contextual prefix overhead | about **30** words  | must be reserved in chunk sizing                   |

### Context Packing Constraints

| Constraint             | Value                           | Why it matters                                |
| ---------------------- | ------------------------------- | --------------------------------------------- |
| Max RAG context chars  | about **5500**                  | practical ceiling for current prompt assembly |
| Default packing budget | about **3200** estimated tokens | tuned for the public Apple path               |

### Infrastructure Constraints

| Constraint           | Value                                    | Why it matters                                      |
| -------------------- | ---------------------------------------- | --------------------------------------------------- |
| OCR render scale     | **5x to 6x adaptive**                    | internal page-by-page quality and memory tradeoff   |
| Simulator limitation | Apple FM unavailable                     | simulator is not enough for full runtime validation |
| Vector persistence   | memory-mapped binary files plus metadata | real engine asset, but app-path oriented today      |

Important current implementation note:

- the app does not expose or control Apple's internal vision-model tiers directly
- the app does use its own adaptive OCR and visual-recovery heuristics to decide when pages need heavier processing

## What These Limits Mean For Claims

### Safe current claims

- local-first indexing and retrieval on Apple devices
- full-text plus vector retrieval
- source review and verification-oriented answer flow
- Apple-native generation path (On-Device and PCC) where available
- Dynamic secure routing to Private Cloud Compute for reasoning-heavy queries — **without naming a context size**, because the 32,768 figure above is an unverified hardcoded fallback and this list previously contradicted its own table by citing it

### Claim only with caveats

- offline behavior: core local indexing and some answer paths can work locally, but execution mode and Apple-managed routing matter
- Private Cloud Compute: Apple-controlled routing context, not an app-owned backend
- evaluation SDK or XCFramework: true as a staged evaluation artifact, not as a finished productized SDK
- benchmark results: useful for internal regression and pilot evaluation, not audited proof of production accuracy

### Do not claim from current repo state

- Apple Foundation Models embeddings
- full GraphRAG
- guaranteed correctness
- medical, legal, safety, or IFU reliability

## Why Full GraphRAG Is Not A Current Claim

The repo does contain graph-style retrieval support:

- cross-reference extraction
- parent and neighbor expansion
- RAPTOR-lite summaries
- entity indexing

It does not contain the full evaluated GraphRAG stack of:

- entity resolution
- graph community detection
- community summaries
- graph-centric retrieval evaluation

Use "graph-style context packing" or "GraphRAG-lite" only if you immediately explain the limits.

## Repo-Specific Constraints That Matter In Public Claims

- `AppleFMEmbeddingProvider.swift` is unavailable and should not be marketed as current capability.
- `OIEngine` exists, but it still routes through app-owned services and runtime paths.
- SQLite isolation is implemented with shared tables plus `container_id`, not a completely separate per-library database system.
- Vector stores are persisted per container, but through app support paths and app lifecycle assumptions.
- The benchmark harness is debug-driven and early.
- StoreKit and app pricing surfaces are real app code, not engine maturity proof.

## Practical Checklist Before Making A Public Claim

- Does the claim survive a 4096-token public Foundation Models budget?
- Does it avoid implying direct PCC control or a larger public context window?
- Does it avoid implying Apple embeddings when the provider is still a scaffold?
- Does it avoid calling GraphRAG features "full GraphRAG"?
- Does it avoid turning citations or verification into accuracy guarantees?
- Does it avoid regulated-use language unless separate validation exists?
