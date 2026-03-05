# What's New in OpenIntelligence v2.0.1

**Released**: March 4, 2026 (Build 19)

---

## v2.0.1 — Post-Release Hardening (since v2.0 on Feb 28)

### Safety Hardening (P0–P4)

37 force-unwrap crash sites eliminated across 26 files. 10 `fatalError()` calls replaced with graceful `URL.temporaryDirectory` fallbacks. 1,278 lines of dead code removed (3 unused files + 1 commented-out class). 3 silent Vision `catch` blocks now log via `Log.debug()`.

### Bug Fixes

- **Cross-Container Chat Bleed**: Queries no longer leak between knowledge libraries
- **Undismissable Alerts**: `.constant()` alert bindings in `CachedDocsView` and `DocumentLibraryView` replaced with proper `@State Bool` / `Binding(get:set:)`
- **Insights Sheet**: "Show All Insights" in `AdaptiveVisualizationsView` now displays content (was empty TODO)
- **StoreKit Stream Crash**: `var streamContinuation!` (IUO) replaced with `AsyncStream.makeStream()`
- **ContainerService Init**: Fixed stored-property initialization error
- **Settings Cleanup**: Removed stub System Status and Developer categories from navigation

### Onboarding Polish

- 6 haptic touch points (light/selection/medium/success/error)
- VoiceOver labels on pipeline stage badges, processing overlay, and ingestion rows
- Analytics: `markOnboardingCompleted()` vs `skipPermanently()` with `completionMethod` tracking
- Error message: "tap to retry" → "please try again" (no tap target existed)
- `NSMicrophoneUsageDescription` added for Speech framework voice input

### Onboarding Rewrite — Pipeline Theater

Complete rebuild of the first-run experience into a 2-page flow: welcome with use-case cards → live pipeline theater with compact capsule phase strip, real-time metrics dashboard (words/chunks/vectors/time), fixed-height streaming log ticker, and per-document status lines. Retry button on failure. `accessibilityReduceMotion` support. `foregroundColor` → `foregroundStyle` migration (34 sites). Dead code and performance cleanup.

### Educational Sample Documents

3 curated docs teach users the app's architecture: OpenIntelligence Pricing, RAG Technical Architecture, and Apple Intelligence & Private Cloud Compute. Sample imports bypass the free tier document quota to prevent first-run failures.

### Search & Retrieval

- `BM25Scorer` refactored from class to struct with internal `Storage` reference type (thread safety)
- Image Playground concept extraction changed from few-shot (hardcoded Mustang example) to zero-shot prompt

### Suggested Questions

- Fixed few-shot contamination: LLM prompt had Kia Sportage examples that biased all suggestions toward car topics regardless of actual documents. Replaced with domain-neutral templates.
- Fixed 2-question cap bug: diversity filter was too aggressive — now returns 4 grounded questions per library.
- Stale questions no longer flash when switching libraries — cleared immediately before regeneration.
- Stronger grounding: every suggested question must reference content from actual document passages.

### AI Hub Result Sheet

- **Markdown Rendering**: AI Hub transform results (Key Facts, Step-by-Step, etc.) now render with full markdown formatting — bullets, bold, headers, code fences — instead of showing raw `**` and `-` characters.
- **Share Button**: New Share option alongside Copy and Insert in Chat for sending results to Messages, Notes, Mail, etc.
- **Sheet Sizing**: Result sheet starts at half-height and is draggable to full-height — appropriate sizing for both short and long results.

### Anti-Hallucination: Topical Mismatch Detection

- **Prompt Grounding**: LLM system prompt no longer says "Never say no information." The model can now acknowledge when retrieved excerpts don't address the question instead of fabricating from unrelated context.
- **Evidence-First Topical Gate**: When query keywords don't appear in retrieved chunks (lexical relevance < 20%), Evidence-First mode activates regardless of similarity score. Prevents high-similarity but off-topic chunks from causing hallucination.

### Container Isolation

- EntityIndexService now tracks per-container document mapping — entity lookups are library-scoped.
- FullTextStorageService legacy methods now accept document ID filters — no more cross-library corpus searches.
- Document and library deletion properly cleans up entity index entries.

---

## v2.0 — Major Release

## The One-Liner

Search got smarter, GPU actually gets used, OCR runs in parallel, tables don't get chopped in half, and responses finally show formatting instead of a wall of text.

---

## The Short Version

Four big changes:

1. **Responses look good now.** Headers, bullet lists, bold text, code blocks — instead of one giant paragraph. We rewrote the renderer from scratch and audited every function in the response pipeline that was stripping formatting.

2. **Everything runs faster on your specific chip.** GPU vector search picks the fastest Metal shader automatically. OCR runs 2-8 operations in parallel depending on your chip. Neural reranking scores multiple candidates simultaneously. Embedding generation offloads to GPU during ingestion so the Neural Engine can focus on OCR.

3. **You can transform any AI response 5 ways** — extract key facts, step-by-step instructions, plain English simplification, gap analysis (what's missing?), or illustrated visualizations. All grounded in your actual source documents, not hallucinated.

4. **The app doesn't hang on airplane mode anymore**, and a crash in the diversity algorithm was fixed.

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

### RAG-Grounded Response Transforms

A new AI Hub toolbar (top-right, `apple.intelligence` icon) provides 5 document-aware transforms on any AI response:

| Transform           | What It Does                                                   |
| ------------------- | -------------------------------------------------------------- |
| **Key Facts**       | Source-backed bullet points with document/page attribution     |
| **Step-by-Step**    | Procedures using real specs and part numbers from chunks       |
| **Plain English**   | Simplifies complex technical content into accessible language  |
| **What's Missing?** | Identifies gaps between your question and the retrieved answer |
| **Illustrate**      | Image Playground visualization via LLM concept extraction      |

Each transform receives the retrieved chunks (not just the response text), so output is grounded in the user's actual documents. Uses `Instructions()` for persistent system context, token-aware budgets per transform type, 30-second timeout, and task cancellation support.

### Image Playground — LLM Concept Extraction

Image Playground previously used NLTagger to extract raw nouns/entities from RAG responses. Domain-specific terms ("TPB", "SAE 0W-20") caused "try another description" errors.

Now uses the on-device LLM to translate response content into 3-5 short, concrete visual scene descriptions (<35 chars each). The LLM understands technical jargon in context and converts it to simple visual imagery. Falls back to NLTagger if FoundationModels is unavailable.

### Pipeline Quality Fixes

| Fix                       | Details                                                                                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BM25 `b` alignment**    | RAGEngine used `b=0.75`, HybridSearchService used `b=0.5`. Uniform chunk size means length normalization should be minimal. Aligned both to `b=0.5` — better recall |
| **Accelerate Gate E**     | VerificationGateService cosine similarity replaced with `vDSP.dot()` — hardware-optimized                                                                           |
| **Regex pre-compilation** | RAGEngine regex patterns compiled once as `static let` instead of per-query                                                                                         |
| **BM25 lemmatization**    | `tokenize()` uses NLTagger `.lemma` scheme: "studies" → "study", "running" → "run"                                                                                  |

### Stability & Hardening

| Fix                       | Details                                                                                                                                                                                                                                                                                                                                                |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **MMR Crash**             | `RAGEngine.applyMMR()` crashed on array index out of bounds when `GPUComputeService.mmrDiversityMatrix()` returned `[[]]` (one empty inner array) instead of a proper N×N matrix. Added matrix dimension validation and bounds checking. Fixed GPU edge cases: `guard count > 1` now returns `[]` not `[[]]`, `guard dimension > 0` falls back to CPU. |
| **Airplane Mode Hang**    | `StoreKit.Product.products(for:)` blocks 30-60 seconds when offline. Wrapped in `withThrowingTaskGroup` with a 5-second timeout race. Environment logging moved to non-blocking Task.                                                                                                                                                                  |
| **Production Crash Risk** | `fatalError()` for a threading violation in LLMService replaced with `assertionFailure` + safe fallback. DEBUG builds still assert; Release builds attempt access gracefully.                                                                                                                                                                          |
| **Pipeline Trace Leak**   | 3 diagnostic functions with ~30 `print()` calls were reachable in Release builds via a user-accessible settings toggle. Wrapped in `#if DEBUG` — compiled out of Release entirely.                                                                                                                                                                     |
| **Privacy Manifest**      | Added `NSPrivacyAccessedAPICategorySystemBootTime` (reason `35F9.1`), `NSPrivacyTracking = false`, empty `NSPrivacyCollectedDataTypes`.                                                                                                                                                                                                                |
| **Dead Code**             | Removed unused `activeTasks` counter from cross-encoder path. Updated stale "serial queue" comments to reflect concurrent reality.                                                                                                                                                                                                                     |

### Zero-Data-Loss Ingestion Fixes

Critical fixes preventing silent content loss on font-encoded PDFs:

| Fix                                               | Details                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Font Substitution Cipher Detection (PHASE -1)** | New document-level validation renders one sample page via Vision OCR and compares to PDFKit text via Jaccard similarity. Threshold < 0.15 = garbled text layer (font substitution cipher). When detected, all pages forced through full OCR. Prevents **93% content loss** on PDFs from Kia, Hyundai, and Asian-publisher manuals where `FOREWORD` reads as `GPSFXPSE`. |
| **Raw String Regex Fix**                          | 5 regex patterns in `OCRConfiguration.normalizeExtractedText()` used `\u{HHHH}` inside Swift raw strings — silently invalid. ICU regex requires `\x{HHHH}`. All 5 patterns (CJK bullets, en-dash, em-dash, CJK numerals) were no-ops. Fixed.                                                                                                                            |
| **Garbled Image Extraction**                      | `extractImagesFromPDFPage()` used `page.string` emptiness as proxy for "page is visual." Font-encoded PDFs have garbled text on every page, so image extraction was skipped entirely. Now uses `isTextQualityAcceptable()` as quality gate.                                                                                                                             |
| **Dynamic Image Text Budget**                     | Changed from hardcoded `maxImageTextPerDoc = 3000` to `min(30000, max(3000, extractedImages.count * 500))` — scales with document visual complexity.                                                                                                                                                                                                                    |

### Swift 6 Concurrency Compliance

11 files updated with strict concurrency annotations — **zero runtime behavior change**. All changes are compile-time only, eliminating warnings that become hard errors in Swift 6 language mode:

- `nonisolated` on `OCRConfiguration` statics, `DocumentChunk.init`, `DocumentProcessor.traceIngestionOutcome`
- `@preconcurrency import Vision` in `CaptureToRAGBridge`
- `await` on `DeviceCapabilityService` access in `RAGEngine`
- `let configuredRequest = request` before `@Sendable` closures in 3 files
- `nonisolated(unsafe)` on `BNNSVectorDatabase.loadTask` for nonisolated init access
- Dead code removal (`var bestConfidence`), `var` → `let` fixes

### Pipeline Reliability Hardening

11 targeted fixes across the compression → generation → fallback chain. Previously, a rate-limited Apple FM call during compression could cascade into a 0-token response with no fallback — the user saw a generic error instead of document content.

| Fix                           | Details                                                                                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| **Compression Cap**           | Maximum 5 chunks sent to compression (was unlimited) — reduces sequential FM calls that exhaust rate limits                                    |
| **Fresh Session Per Chunk**   | `resetSession()` before each compression prevents transcript accumulation that overflowed the 4096-token context window after 3-4 compressions |
| **Per-Chunk Error Isolation** | Each `compressChunk()` wrapped in `do/catch` with passthrough fallback — one failure no longer aborts the batch                                |
| **12-Second Time Budget**     | Compression batch bails out after 12s, passing remaining chunks through as originals                                                           |
| **Empty Response → Fallback** | LLM returning 0 tokens now routes to `buildReliabilityFallbackResponse()` instead of throwing an error that bypassed fallback entirely         |
| **Post-Compression Cooldown** | 1s sleep after compression lets Apple FM rate limits recover before generation                                                                 |
| **Rate-Limit Retry**          | `generateWithFallback()` detects rate-limited errors, sleeps 2s, retries once                                                                  |
| **Typed LLM Errors**          | New `.rateLimited` and `.concurrentRequests` cases in `LLMError` — replaces fragile string matching                                            |
| **Extractive Path B Rewrite** | Fallback now uses 6 chunks × 500 chars with section titles and source names (was 3 × 240 chars)                                                |
| **Partial Stream Threshold**  | Lowered from 24 → 10 characters to salvage more partial output                                                                                 |
| **Error Logging**             | Reliability fallback LLM failure now logged via `do/catch` (was silent `try?`)                                                                 |

### Memory-Safe Large PDF Ingestion

Prevents OOM watchdog kills during ingestion of 500+ page PDFs. A 542-page owner's manual was killed during post-parsing image analysis.

| Fix                             | Details                                                                                                     |
| ------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| **Results Array Release**       | `results.removeAll()` frees ~100-200MB of parsed page data before image analysis begins                     |
| **Image Batch 20 → 5**          | Peak CIImage memory per batch drops from ~200MB to ~50MB                                                    |
| **144 DPI Image Understanding** | Full-page renders for Vision classification use 2× scale (was 5×/360 DPI) — each page ~4MB instead of ~25MB |
| **autoreleasepool**             | Core Graphics intermediates released immediately instead of accumulating                                    |

### True Parallel Hybrid Search

Replaced the sequential "vector-first, then BM25 re-score" pipeline with true parallel hybrid retrieval:

| Before (v1.1)                                   | After (v1.2)                                                   |
| ----------------------------------------------- | -------------------------------------------------------------- |
| Vector search runs first                        | Vector + FTS5 run concurrently via `async let`                 |
| BM25 re-scores the same vector candidates       | Two independent ranked lists merged via RRF                    |
| In-memory `BM25Scorer` with per-query snapshots | Native SQLite `bm25()` with corpus-wide IDF                    |
| FTS5-only matches invisible                     | FTS5-only hits surface through RRF with fair ranking           |
| BM25 column weights: uniform                    | Weighted: section_title (10×), section_path (5×), content (1×) |

### Onboarding Polish

Six first-launch experience improvements:

- **Haptic Feedback**: 6 touch points across onboarding — `light` on skip/dismiss, `selection` on continue, `medium` on get started, `success`/`error` on import result
- **Analytics Separation**: New `markOnboardingCompleted()` path distinct from `skipPermanently()` — `completionMethod` UserDefaults key tracks `"completed"` vs `"skipped"` for conversion analytics
- **Sample Import on Completion**: `markSamplesImported()` now called through the primary success path via `markOnboardingCompleted()`
- **Pipeline Accessibility**: `PipelineStageBadge`, processing header, and `OnboardingIngestionRow` have VoiceOver labels and values — screen reader users can follow ingestion progress
- **Error Message Fix**: "Import failed — tap to retry" → "Import failed — please try again" (previous wording implied a non-existent tap target)
- **Microphone Permission**: `NSMicrophoneUsageDescription` added to both build configs for Speech framework voice input

---

## Cumulative Changes Since App Store Launch (v1.0.0 → v2.0)

For the complete build-by-build changelog, see [CHANGELOG.md](CHANGELOG.md).

### What changed at a glance

| Area                       | v1.0.0 (Launch)                         | v2.0 (Current)                                                                                  |
| -------------------------- | --------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Pipeline steps             | 23                                      | 25                                                                                              |
| Services                   | 79                                      | 102                                                                                             |
| Categories                 | 10                                      | 11                                                                                              |
| GPU vector search          | Scalar kernel only                      | 3-tier auto-selection (threadgroup/SIMD4/scalar)                                                |
| OCR concurrency            | Fixed for all devices                   | Per-chip (2-8 concurrent ops)                                                                   |
| OCR page filtering         | Process every page                      | 50-80% skip rate via PageComplexityAnalyzer                                                     |
| CIFilter rendering         | Serial queue                            | Concurrent queue                                                                                |
| Cross-encoder reranking    | Sequential, tokenized in-loop           | Concurrent TaskGroup, pre-tokenized, bulk memory writes                                         |
| Embedding during ingestion | Neural Engine                           | GPU (frees Neural Engine for OCR)                                                               |
| FTS5 queries               | OR-joined (matched everything)          | AND-first with automatic OR fallback                                                            |
| BM25 scoring               | Document-level (all chunks same score)  | Native SQLite `bm25()` with weighted columns (10/5/1)                                           |
| HyDE embedding             | 100% hypothetical                       | 70/30 blend with original query                                                                 |
| Iterative retrieval        | Implemented but hardcoded off           | Auto-enabled for multi-hop intents                                                              |
| Table handling in chunker  | Could split tables mid-row              | Table-block detection, atomic preservation                                                      |
| OCR candidates             | topCandidates(3)                        | topCandidates(5)                                                                                |
| Response rendering         | Single unformatted paragraph            | Full block-level markdown parser                                                                |
| Response transforms        | —                                       | 5 RAG-grounded transforms (Key Facts, Step-by-Step, Plain English, What's Missing?, Illustrate) |
| Image Playground concepts  | —                                       | LLM-powered visual scene extraction (domain jargon → concrete imagery)                          |
| BM25 `b` parameter         | Inconsistent (0.75 vs 0.5)              | Aligned to 0.5 (correct for uniform chunk size)                                                 |
| Response cleaning          | Stripped all markdown                   | Preserves all formatting                                                                        |
| LLM prompts                | No formatting instructions              | Headers, bullets, bold instructions in all 6 prompts                                            |
| Cross-encoder pool cap     | Fixed 100                               | Adaptive: min(count, max(100, topK×5))                                                          |
| Token budget               | Tool schema always reserved             | Conditional — reclaims ~24% when tools unused                                                   |
| Verification Gate C        | Years/integers penalized, 80% threshold | Years/integers exempt, 70% threshold                                                            |
| Spec detection             | Matched any letter+digit combo          | Matches only actual patterns (e.g., oil viscosity)                                              |
| StoreKit offline           | Hangs 30-60 seconds                     | 5-second timeout                                                                                |
| Motherboard HUD            | —                                       | Real-time Apple Silicon X-ray overlay                                                           |
| Font-encoded PDFs          | Silently lost 93% of content            | PHASE -1 Jaccard detection, full OCR forced                                                     |
| Swift 6 concurrency        | Warnings in 11 files                    | All annotations complete, zero warnings                                                         |
| Hybrid search architecture | Sequential vector → BM25 re-score       | True parallel vector + FTS5, merged via RRF                                                     |
| LLM reliability            | 0-token responses on rate limit         | 11-fix hardening: compression cap, retry, typed errors                                          |
| Large PDF memory           | OOM kill on 500+ pages                  | Batch 5-page, 144 DPI image, results release                                                    |
