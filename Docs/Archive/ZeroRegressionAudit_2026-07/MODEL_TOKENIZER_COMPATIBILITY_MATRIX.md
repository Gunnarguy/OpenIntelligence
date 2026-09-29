# Model Tokenizer Compatibility Matrix

This matrix documents the models, tokenizers, and parameter limits configured in the application.

## Tokenizer & Embedding Specifications

| Layer | Component | Package Dependency / Source | Input Token Ceiling | Output Dimension | Notes / Behavior |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Tokenizer** | BertTokenizer | `swift-tokenizers` (DePasqualeOrg v0.7.1) | 512 tokens | N/A | Linguistic word count is not a safe proxy. `[evidence_level: code_verified, confidence: exact]` |
| **Embeddings** | CoreML Model | Local compiled asset | 510 tokens (excl. CLS/SEP) | 384 dimensions (Float) | Vectors must match exactly 384 float dimensions. `[evidence_level: code_verified, confidence: exact]` |
| **Local LLM** | Apple AFM 3 Core | `SystemLanguageModel.default` | 4,096 tokens | ~3B parameters | On-device offline inference engine. `[evidence_level: sdk_interface_verified, confidence: exact]` |
| **Remote LLM** | Private Cloud Compute | `PrivateCloudComputeLanguageModel` | 32,768 tokens | ~70B+ parameters | Enclave execution; simulated locally via compatibility wrapper. `[evidence_level: sdk_interface_verified, confidence: exact]` |

## Compatibility Safeguards
*   **Token Budget Guardrails:** Prompts are validated against the 4,096 token limit before local dispatch to prevent out-of-memory or model truncation errors. `[evidence_level: code_verified, confidence: exact]`
*   **Scaffolding:** `AppleFMEmbeddingProvider.swift` is a scaffold and is not active in production. CoreML is the active embedding source. `[evidence_level: code_verified, confidence: exact]`

## PR Impact on Model/Tokenizer Contracts (Phase A, verified 2026-07-13)
| PR | Contract | Change | Compatibility Risk | Disposition |
| :-- | :-- | :-- | :-- | :-- |
| #37 / #41 | Core ML KV-cache masks (`LanguageModelWithStatefulKVCache`) | Infer attention/causal mask scalar type from `inputDescriptionsByName[...].multiArrayConstraint.dataType` (float32 → Float, else Float16) | Only 2 of the `MLMultiArrayDataType` cases handled; no real model-descriptor fixtures; duplicate PRs (#37 additionally commits `pre_commit.sh`); upstream `swift-transformers` divergence undocumented | REWORK → consolidate, fixture-test, or upstream |
| #44 | BPE tokenizer unknown-token path | Honors `byte_fallback=false` by emitting `unknownToken` instead of hex byte-encoding | Token-ID sequences change for affected configs → byte-level **citation offsets** can shift; decode round-trips unverified | BLOCKED_PENDING_FIXTURE_TESTS |
| #56 | Embedding input shape (HyDE) | Separator `\n` → space in blended text | Every HyDE-path embedding vector changes; retrieval-rank impact unmeasured | CLOSE unless paired benchmark proves value |

## Fixture Status — NONE EXIST
Required before any tokenizer/model decision: real tokenizer fixtures (`byte_fallback` true/false/missing; unknown token present/missing; fused unknowns; ASCII/accents/emoji/combining marks/CJK/invalid sequences) with exact token IDs and decode round-trips vs upstream; Core ML model descriptors covering all scalar/mask/shape cases; generation-parity runs. Do not fake fixtures. `[evidence_level: code_verified (absence), confidence: exact]`
