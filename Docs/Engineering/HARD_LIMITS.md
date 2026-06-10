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
| On-Device Context window       | **4096 tokens**                          | default local path using `SystemLanguageModel.default`                             |
| PCC Context window             | **32,768 tokens**                        | dynamic path using `PrivateCloudComputeLanguageModel` for reasoning-heavy queries  |
| Model size                     | about **3B parameters** (local)          | useful, but not a large-server-model class system                                  |
| Public PCC/server-model access | **Native iOS 26+ API**                   | app integrates directly with `PrivateCloudComputeLanguageModel`                    |
| Recommended tool count         | **3-5 tools**                            | tool schemas eat context budget                                                    |

Important current implementation note:

- Local-first defaults are restricted to 4,096 tokens. Standard queries that overflow this ceiling, or queries executed under Deep Think / Maximum modes, are dynamically escalated to Private Cloud Compute (PCC) via `PrivateCloudComputeLanguageModel` with up to 32K tokens support.

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
