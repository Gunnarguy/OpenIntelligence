# OpenIntelligence Performance Baseline

This document lists the frozen performance limits and baseline architectural bounds of the application.

## Core Architectural Limits
Per `Docs/Engineering/HARD_LIMITS.md`:

*   **Context Window (On-Device):** 4,096 tokens (managed via `SystemLanguageModel.default`). `[evidence_level: code_verified, confidence: exact]`
*   **Context Window (PCC Remote):** 32,768 tokens (managed via `PrivateCloudComputeLanguageModel` for reasoning-heavy queries). `[evidence_level: code_verified, confidence: exact]`
*   **CoreML Embedding Size:** 510 tokens maximum (512 tokens minus special tokens CLS/SEP). `[evidence_level: code_verified, confidence: exact]`
*   **Vector Embedding Dimension:** 384 float dimensions (enforced across the main path). `[evidence_level: code_verified, confidence: exact]`
*   **Max RAG Context Characters:** ~5,500 characters. `[evidence_level: code_verified, confidence: exact]`
*   **OCR Render Scale:** 5x to 6x adaptive scaling. `[evidence_level: code_verified, confidence: exact]`

## Baseline Measurements — LABEL CORRECTION (2026-07-13)
No instrumented performance measurement has been executed in Phase A. The items below are architecture descriptions or unmeasured impressions, retagged accordingly (the Independent Verification Report flagged the launch-time line as overstated):
*   **App Launch Time:** ~500ms claim — `[evidence_level: doc_claim_only, confidence: low]`. NOT MEASURED.
*   **Ingestion Pipeline:** Uses thread-safe background operations — `[evidence_level: code_verified, confidence: high]` (architecture only, no throughput numbers).
*   **Memory Footprint:** 12GB RAM gate exists in code for local-model resolution — `[evidence_level: code_verified, confidence: exact]` (gate presence, not measured footprint).
*   **Execution Warnings:** 0 compile warnings in TE-01/TE-03/TE-04 builds — `[evidence_level: compile_verified, confidence: exact]` (first-party code; SwiftPM deps compiled with `-suppress-warnings`).

## Required Measured Baseline (Phase B / owner)
Release-build physical-device measurements (median/p90/p95, peak RSS, allocations, CPU/GPU time, energy, thermal, cold+warm) for: ingestion throughput, vector search, hybrid retrieval, context assembly, generation, prewarming. These gate every performance-motivated PR (#28, #31, #33, #35, #39, #45, #47, #49, #57, #61, #63). A claimed optimization without native measurement remains unproven. `OWNER_ACTION_REQUIRED` for device runs. `[evidence_level: code_verified (absence), confidence: exact]`
