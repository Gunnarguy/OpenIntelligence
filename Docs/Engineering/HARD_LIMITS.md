# OpenIntelligence Hard Limits and Claim Constraints

**Purpose**: Single source of truth for current technical constraints and the claim boundaries they create.
**Last Verified**: April 25, 2026

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
| Public PCC/server-model access | **Native iOS 26+ API**                   | app integrates directly with `PrivateCloudComputeLanguageModel`                    |
| Recommended tool count         | **3-5 tools**                            | tool schemas eat context budget                                                    |

Important current implementation notes:

- **The routing decision does not use the SDK value.** `FoundationModelRoutePolicy` hardcodes `let onDeviceLimit = 4096` and never consults `FoundationModelTokenBudget.contextSize` or `FoundationModelCapabilityProvider`, even though both exist and report the device's real window. Escalation therefore triggers at a literal rather than at the actual local capacity. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelRoutePolicy.swift:60]`
- **The 32,768 figure is not measured.** It is a hardcoded fallback, and the code comment on it explicitly directs routing callers to the live capability provider instead. Treat it as an upper-bound assumption, not a verified limit. It is also asserted as fact in the app's own bundled documentation, which the engine then cites back to users.
- Local-first defaults are restricted to 4,096 tokens for routing purposes. Standard queries that overflow this ceiling, or queries executed under Deep Think / Maximum, are dynamically escalated to PCC via `PrivateCloudComputeLanguageModel`.

### Measured generation throughput (physical device, 2026-07-30)

First real numbers, from an iPhone A18 Pro. These supersede the unbacked `< 0.8 s` TTFT and `≈65 tok/s` figures asserted in the Settings capability card.

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
- Dynamic secure routing to Private Cloud Compute (32K context) for reasoning-heavy queries

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
