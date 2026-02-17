# What's New in OpenIntelligence v1.2

**Released**: February 16, 2026 (Build 14)

---

## The One-Liner

Search got smarter, GPU actually gets used, OCR runs in parallel, tables don't get chopped in half, and responses finally show formatting instead of a wall of text.

---

## The Short Version

Three big changes:

1. **Responses look good now.** Headers, bullet lists, bold text, code blocks — instead of one giant paragraph. We rewrote the renderer from scratch and audited every function in the response pipeline that was stripping formatting.

2. **Everything runs faster on your specific chip.** GPU vector search picks the fastest Metal shader automatically. OCR runs 2-8 operations in parallel depending on your chip. Neural reranking scores multiple candidates simultaneously. Embedding generation offloads to GPU during ingestion so the Neural Engine can focus on OCR.

3. **The app doesn't hang on airplane mode anymore**, and a crash in the diversity algorithm was fixed.

---

## The Technical Version

### Rich Markdown Response Rendering

The rendering engine was rewritten from `Text(attributedString)` with `.inlineOnlyPreservingWhitespace` (which produced a single paragraph) to a full block-level parser that handles h1-h6 headings, bullet lists, numbered lists, code fences, block quotes, horizontal rules, and paragraphs as discrete SwiftUI views.

**The hidden problem**: Apple's on-device Foundation Model concatenates all markdown syntax onto a single line. `### Header - Bullet 1 - Bullet 2` instead of separate lines. A new `normalizeInlineMarkdown()` preprocessor uses 6 regex patterns to split these back into proper markdown blocks before the parser sees them.

**The bigger hidden problem**: Two response-cleaning functions were actively destroying every response's formatting:

- `RAGService.cleanupResponseText()` — stripped ALL markdown, turning formatted output back into plain text
- `AgenticOrchestrator.cleanupFinalAnswer()` — stripped headers, bullets, and numbered lists from Deep Think/Maximum mode responses

Both were rewritten. Five other cleaning functions were audited and confirmed safe. The sentence joiner in `compactDegenerateResponse()` was changed from space-joining to paragraph-break-joining.

All 6 LLM system prompts (Standard, Deep Think ×2, Maximum ×2, Integrity Repair) were updated with explicit formatting instructions: use `### headers`, `- bullets`, and `**bold**` for key terms.

### Device-Optimized Performance Engine

#### Metal GPU Vector Search — 3-Tier Shader Selection

Previously, ALL GPU cosine similarity searches used the scalar kernel — even though the SIMD4 and threadgroup kernels were compiled and sitting right there.

Now the system auto-selects:

- **Threadgroup** (≥1,000 vectors, dimension ≤384): Query vector cached in `threadgroup` shared memory, SIMD4 (`float4`) vector operations within each thread. Fastest path. MiniLM-L6-v2 at 384-dim / 4 = 96 float4s fits exactly within the `sharedQuery[96]` limit.
- **SIMD4** (100-999 vectors): `float4` hardware vector operations — 4× scalar throughput.
- **Scalar** (fallback): Arbitrary dimension support — baseline.

A new `cosineSimilarityThreadgroupPipeline` Metal compute pipeline is created at initialization alongside the existing SIMD pipeline.

#### Vision OCR — Per-Chip Concurrency + Adaptive Filtering

Concurrent OCR operations are now tuned per Apple Silicon chip:

| Chip                    | Concurrent Ops | Cooldown |
| ----------------------- | -------------- | -------- |
| A19 Pro / M4            | 8              | 1ms      |
| A18 Pro / M3            | 6              | 2ms      |
| A17 Pro / M2            | 4              | 3ms      |
| Mac (Designed for iPad) | 4              | 3ms      |
| Older                   | 2              | 6ms      |

`PageComplexityAnalyzer` pre-screens every page before Vision OCR runs. Clean digital PDFs (already have extractable text) skip OCR entirely — 50-80% skip rate on typical documents. Fewer total OCR calls means the remaining calls can run at higher concurrency.

The CIFilter preprocessing queue (`DocumentProcessor.gpuQueue`) was upgraded from a serial `DispatchQueue` to concurrent. CIContext is thread-safe per Apple documentation — the serial queue was an unnecessary bottleneck that serialized ALL GPU CIFilter renders.

#### Cross-Encoder Neural Reranking — Concurrent + Pre-Tokenized

Cross-encoder predictions now use `TaskGroup` with device-tier-aware concurrency (2-4 parallel predictions depending on chip).

Before entering the TaskGroup, ALL query-chunk pairs are tokenized upfront — tokenization overhead moved entirely out of the hot prediction loop.

`MLMultiArray` is now populated via `dataPointer` bulk memory copy instead of per-element `NSNumber` subscript — 3× faster array fills.

~90 lines of duplicated prediction code between the seed batch and feed loop were extracted into a single `@Sendable` closure.

#### Embedding Pipeline — GPU Ingestion Mode

During document ingestion, `CoreMLSentenceEmbeddingProvider` switches compute units from the default (Neural Engine) to `.cpuAndGPU` via `enableIngestionMode()` / `disableIngestionMode()`. This frees the Neural Engine to handle Vision OCR concurrently. Compute unit selection also adapts to device capability tier.

#### OCR Quality

`StructuredDocumentParser` now evaluates `topCandidates(5)` (was 3) for richer candidate selection, improving accuracy on ambiguous text.

### Stability & Hardening

| Fix                       | Details                                                                                                                                                                                                                                                                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **MMR Crash**             | `RAGEngine.applyMMR()` crashed on array index out of bounds when `GPUComputeService.mmrDiversityMatrix()` returned `[[]]` (one empty inner array) instead of a proper N×N matrix. Added matrix dimension validation and bounds checking. Fixed GPU edge cases: `guard count > 1` now returns `[]` not `[[]]`, `guard dimension > 0` falls back to CPU. |
| **Airplane Mode Hang**    | `StoreKit.Product.products(for:)` blocks 30-60 seconds when offline. Wrapped in `withThrowingTaskGroup` with a 5-second timeout race. Environment logging moved to non-blocking Task.                                                                                                                                                                  |
| **Production Crash Risk** | `fatalError()` for a threading violation in LLMService replaced with `assertionFailure` + safe fallback. DEBUG builds still assert; Release builds attempt access gracefully.                                                                                                                                                                          |
| **Pipeline Trace Leak**   | 3 diagnostic functions with ~30 `print()` calls were reachable in Release builds via a user-accessible settings toggle. Wrapped in `#if DEBUG` — compiled out of Release entirely.                                                                                                                                                                     |
| **Privacy Manifest**      | Added `NSPrivacyAccessedAPICategorySystemBootTime` (reason `35F9.1`), `NSPrivacyTracking = false`, empty `NSPrivacyCollectedDataTypes`.                                                                                                                                                                                                                |
| **Dead Code**             | Removed unused `activeTasks` counter from cross-encoder path. Updated stale "serial queue" comments to reflect concurrent reality.                                                                                                                                                                                                                     |

---

## Cumulative Changes Since App Store Launch (v1.0.0 → v1.2.0)

For the complete build-by-build changelog, see [CHANGELOG.md](CHANGELOG.md).

### What changed at a glance

| Area                       | v1.0.0 (Launch)                         | v1.2.0 (Current)                                        |
| -------------------------- | --------------------------------------- | ------------------------------------------------------- |
| Pipeline steps             | 23                                      | 25                                                      |
| Services                   | 79                                      | 81                                                      |
| Categories                 | 10                                      | 11                                                      |
| GPU vector search          | Scalar kernel only                      | 3-tier auto-selection (threadgroup/SIMD4/scalar)        |
| OCR concurrency            | Fixed for all devices                   | Per-chip (2-8 concurrent ops)                           |
| OCR page filtering         | Process every page                      | 50-80% skip rate via PageComplexityAnalyzer             |
| CIFilter rendering         | Serial queue                            | Concurrent queue                                        |
| Cross-encoder reranking    | Sequential, tokenized in-loop           | Concurrent TaskGroup, pre-tokenized, bulk memory writes |
| Embedding during ingestion | Neural Engine                           | GPU (frees Neural Engine for OCR)                       |
| FTS5 queries               | OR-joined (matched everything)          | AND-first with automatic OR fallback                    |
| BM25 scoring               | Document-level (all chunks same score)  | Per-chunk via in-memory scorer                          |
| HyDE embedding             | 100% hypothetical                       | 70/30 blend with original query                         |
| Iterative retrieval        | Implemented but hardcoded off           | Auto-enabled for multi-hop intents                      |
| Table handling in chunker  | Could split tables mid-row              | Table-block detection, atomic preservation              |
| OCR candidates             | topCandidates(3)                        | topCandidates(5)                                        |
| Response rendering         | Single unformatted paragraph            | Full block-level markdown parser                        |
| Response cleaning          | Stripped all markdown                   | Preserves all formatting                                |
| LLM prompts                | No formatting instructions              | Headers, bullets, bold instructions in all 6 prompts    |
| Cross-encoder pool cap     | Fixed 100                               | Adaptive: min(count, max(100, topK×5))                  |
| Token budget               | Tool schema always reserved             | Conditional — reclaims ~24% when tools unused           |
| Verification Gate C        | Years/integers penalized, 80% threshold | Years/integers exempt, 70% threshold                    |
| Spec detection             | Matched any letter+digit combo          | Matches only actual patterns (e.g., oil viscosity)      |
| StoreKit offline           | Hangs 30-60 seconds                     | 5-second timeout                                        |
| Motherboard HUD            | —                                       | Real-time Apple Silicon X-ray overlay                   |
