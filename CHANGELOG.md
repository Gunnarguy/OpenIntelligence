# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.1] - 2026-03-09 (Build 20) — Post-Release Hardening

### Pre-Launch Safety Hardening (P0–P4)

Comprehensive force-unwrap elimination and defensive coding pass across the entire codebase. 37 force-unwrap sites eliminated across 26 files — zero runtime behavior change for valid inputs, crash prevention for edge cases. 10 `fatalError()` calls replaced with graceful `URL.temporaryDirectory` fallbacks. 1,278 lines of dead code removed (3 unused files + 1 commented-out class). 3 silent Vision `catch` blocks now log via `Log.debug()`.

### Bug Fixes

- **Cross-Container Chat Bleed**: Fixed queries leaking between knowledge libraries
- **Undismissable Alerts**: `.constant()` alert bindings in `CachedDocsView` and `DocumentLibraryView` replaced with proper `@State Bool` / `Binding(get:set:)`
- **Insights Sheet**: "Show All Insights" in `AdaptiveVisualizationsView` implemented (was empty TODO)
- **StoreKit Stream Crash**: `var streamContinuation!` (IUO) replaced with `AsyncStream.makeStream()`
- **ContainerService Init**: Fixed stored-property initialization error
- **Settings Cleanup**: Removed stub System Status and Developer categories from navigation

### Onboarding Polish

- 6 haptic touch points across onboarding (light/selection/medium/success/error)
- VoiceOver labels on pipeline stage badges, processing overlay, and ingestion rows
- Analytics: `markOnboardingCompleted()` vs `skipPermanently()` with `completionMethod` tracking
- Error message: "tap to retry" → "please try again" (no tap target existed)
- `NSMicrophoneUsageDescription` added for Speech framework voice input

### Onboarding Rewrite — Pipeline Theater

Complete UI rebuild of the first-run experience. 2-page flow: welcome with use-case cards → live pipeline theater.

- **Compact capsule strip**: Extract → Chunk → Embed → Index phase indicators replace large circle badges
- **Live metrics dashboard**: Words / Chunks / Vectors / Time counters with `contentTransition(.numericText())`
- **Fixed-height log ticker**: Last 6 pipeline events with top fade gradient (replaces unbounded scroll)
- **Per-document status lines**: Inline filename + stage + metrics (replaces heavy card-style rows)
- **Retry on failure**: `processingFailed` state with visible Retry button (previously user was stuck)
- **`accessibilityReduceMotion`**: Entrance animations skip when reduce motion enabled
- **`accessibilityLabel`**: Skip button labeled for VoiceOver
- **Swift 6 migration**: `DispatchQueue.main.asyncAfter` → `Task.sleep(for:)`, `foregroundColor` → `foregroundStyle` (34 sites)
- **Dead code removal**: `entitlementStore` (unused EnvironmentObject), `pulseAnimation`, `processingProgress`, `overallProgress`, `showCards` array → `cardsRevealed` Int
- **Performance**: Static `DateFormatter` singleton, `.compositingGroup()` on SplashBackdrop, removed redundant `.animation()` modifiers

### Educational Sample Documents

3 curated onboarding documents teach users what the app does and how it works:

- **OpenIntelligence Pricing** — tiers, capabilities, AI Hub transforms, privacy architecture
- **RAG Technical Architecture** — full 6-step ingestion + 10-step query pipeline, tech specs, performance targets
- **Apple Intelligence & Private Cloud Compute** — Foundation Model specs, PCC privacy guarantees, 23 Apple frameworks

Onboarding sample imports bypass the free tier document quota (`context == .onboarding` in `addDocument()`). Prevents first-run failures when user already has documents.

### BM25Scorer Struct Refactor

`BM25Scorer` in `HybridSearchService` refactored from `class` to `struct` with an internal `Storage` reference type. All methods are `nonmutating`. Each tokenization call creates a fresh `NLTokenizer` instance (no cached state). Division-by-zero guard added: `max(storage.avgDocLength, 0.0001)`.

### Image Playground Zero-Shot Prompt

Image Playground concept extraction prompt changed from few-shot (with a hardcoded Mustang example) to zero-shot. The Mustang example was biasing all Image Playground results toward car/oil/mechanical themes regardless of document content.

### Suggested Questions Overhaul

- **Few-Shot Contamination Fix**: LLM prompt examples used hardcoded Kia Sportage questions ("What oil viscosity does the 2024 Sportage require?", "How do I reset the maintenance indicator light?"). Apple FM mimicked the car theme regardless of actual document content. Replaced with domain-neutral structural templates using placeholders. Added explicit grounding instruction preventing off-topic generation.
- **2-Question Bug Fix**: `enforceDiversity()` had a hardcoded per-document cap of 2. Since LLM questions all shared the same `relevantDocuments` (full doc list), diversity filtering killed all but 2. Fixed with dynamic per-doc cap and per-passage document attribution.
- **Stale Questions on Container Switch**: Switching libraries showed old suggested questions until async regeneration completed. Now clears `dynamicSuggestedQuestions` immediately on container switch, invalidates cache before regenerating.
- **Conversational Tone Rewrite**: Entire LLM prompt, `@Guide` description, fallback templates, and static arrays rewritten for natural, casual tone — suggestions read like questions a coworker would ask, not generic templated queries.
- **Cross-Library Race Guard**: `activeContainerId == containerId` check in ChatScreen prevents slow LLM completions from one library overwriting another library's suggested questions.
- **Improved Fallback Templates**: Content-grounded extraction patterns replace generic templates. Static fallback arrays updated to 4 items each.

### AI Hub Result Sheet Improvements

- **Markdown Rendering**: `WritingToolsResultSheet` now uses `MarkdownText` (full block-level parser) instead of plain `Text()`. Bullets, bold, headers, code fences, and block quotes from `ResponseTransformService` output now render properly.
- **Share Button**: Added `ShareLink` to result sheet alongside Copy and Insert in Chat — users can send AI Hub transform results to Messages, Notes, Mail, etc.
- **Presentation Detents**: Sheet uses `.presentationDetents([.medium, .large])` — starts at half-height for short results, draggable to full for longer output.

### Anti-Hallucination: Topical Mismatch Detection

- **Prompt Grounding Fix**: Removed `"Never say 'no information'"` instruction from the LLM system prompt — this was literally forcing the model to fabricate answers from unrelated context. Replaced with explicit instruction allowing the LLM to acknowledge when retrieved excerpts don't address the user's question.
- **Topical Mismatch Evidence-First Mode**: Added `lexicalRelevance < 0.20` as a new evidence-weakness signal. When query keywords barely appear in retrieved chunks (e.g., billing question answered with PCC encryption chunks), Evidence-First mode now activates regardless of similarity score or query intent. The cautious prompt says "Do NOT fill gaps with assumptions" and forces a confidence note at the end.
- **Decoupled Evidence-First from Procedural Intent**: Previously `useEvidenceFirstMode` required `isProceduralQuery`. Now topical mismatch alone triggers Evidence-First mode for any intent.

### Container Isolation Hardening

- **EntityIndexService Container Scoping**: Added `documentToContainer` mapping, container-scoped `chunksForEntity(_:in:)` and `chunksForEntities(_:in:)`, `removeContainer()`, and `filterByContainer()`. Updated persistence model.
- **FullTextStorageService Container Scoping**: Added `countPatternInCorpus(pattern:documentIds:)` and `searchCorpus(pattern:documentIds:maxResults:)` overloads. Legacy unscoped methods now delegate to scoped versions.
- **RAGService Legacy Fallbacks**: `countPatternInCorpus()` and `searchExactPattern()` now pass container-filtered document IDs instead of searching globally.
- **Entity Cleanup on Delete**: `removeDocument()` now calls `EntityIndexService.shared.removeDocument()`. Library deletion calls `EntityIndexService.shared.removeContainer()`.

### Deep Think / Maximum Mode Freeze Fix

- **Concurrent Query Guard**: Added `activeAgenticTask` tracking in `RAGService`. Sending a new Deep Think or Maximum query now cancels any running orchestration before starting the new one. Previously, two `AgenticOrchestrator` instances would compete for Apple FM simultaneously, queueing LLM calls and freezing the app.
- **Cancellation Propagation**: Added `try Task.checkCancellation()` at the top of both LLM gateway functions (`generateWithFreshSession`, `generateWithProperConsent`) so all 17 call sites in the orchestrator automatically abort when cancelled.
- **Reasoning Chain Abort**: Added `Task.isCancelled` check before each LLM call in the main reasoning chain retry loop for immediate exit on cancellation.

---

## [2.0] - 2026-02-28 (Build 19)

### RAG-Grounded Response Transforms

New `ResponseTransformService` provides 5 document-aware transforms that use the actual retrieved source chunks — not just the AI response text — to produce grounded, citation-backed output.

- **Key Facts**: Extracts source-backed bullet points with document attribution
- **Step-by-Step**: Converts procedures using real specs/part numbers from chunks
- **Plain English**: Simplifies complex technical content into accessible language
- **What's Missing?**: Identifies gaps between the question and the retrieved answer
- **Illustrate**: Image Playground visualization powered by LLM concept extraction
- **System Instructions**: Persistent `Instructions()` keep the LLM grounded in its document analyst role
- **Token-Aware Budgets**: Each transform type gets a tuned character budget respecting the 4096-token window
- **Timeout Protection**: 30-second `TaskGroup` timeout prevents hung generations
- **Task Cancellation**: Checks `Task.isCancelled` before expensive LLM work

### AI Hub Toolbar Redesign

Flat 5-item AI Hub menu (replaced 3-section layout):

- **Key Facts**, **Step-by-Step**, **Plain English**, **What's Missing?**, **Illustrate**
- Uses `apple.intelligence` SF Symbol, disabled when no assistant response or during processing

### Image Playground LLM Concept Extraction

Image Playground now uses the on-device LLM to translate domain-specific content into visual scene descriptions, instead of raw NLTagger noun extraction.

- **Universal approach**: LLM understands acronyms/jargon in context and converts to simple visual imagery ("SAE 0W-20" → "golden oil pouring into an engine")
- **Strict constraints**: <35 chars per concept, no technical terms, no brand names, concrete visual objects only
- **NLTagger fallback**: Falls through to NLTagger noun extraction if FoundationModels unavailable
- **Eliminates "try another description"**: Previously, raw extracted nouns like "TPB" caused Image Playground to reject the prompt

### Pipeline Quality Improvements

- **BM25 `b` Parameter Fix**: `RAGEngine.bm25Scores()` used `b=0.75` while `HybridSearchService.BM25Scorer` used `b=0.5`. Since chunks are uniform size (≤310 words), heavy length normalization was hurting recall. Aligned both to `b=0.5`
- **Accelerate Cosine Similarity**: `VerificationGateService` Gate E (Semantic Grounding) replaced manual dot-product loop with `vDSP.dot()` from Accelerate framework — same math, hardware-optimized
- **Regex Pre-Compilation**: `RAGEngine` now compiles regex patterns once as `static let` properties instead of recompiling on every query
- **NLTagger Lemmatization in BM25**: `HybridSearchService.tokenize()` now uses `NLTagger` with `.lemma` scheme for proper stemming ("running" → "run", "studies" → "study")

---

### Rich Markdown Response Rendering

LLM responses now render with full markdown formatting — headers, bullet lists, numbered lists, bold text, code blocks, and block quotes. Previously, responses displayed as a single unformatted paragraph.

#### Markdown Rendering Engine

- **Full Block-Level Parser**: `MarkdownRenderer.swift` rewritten from inline-only (`.inlineOnlyPreservingWhitespace`) to a complete block-level parser supporting headings (h1-h6), bullet lists, numbered lists, code fences, block quotes, horizontal rules, and paragraphs
- **Inline Markdown Normalization**: Apple's on-device FM concatenates markdown syntax on a single line. New `normalizeInlineMarkdown()` preprocessor splits inline markdown onto separate lines using 6 regex patterns:
  - Headers mid-line (`(?<=\S) +(#{1,6} )`)
  - Bold bullet items (`(?<=\S) +(- \*\*)`)
  - Plain bullets after punctuation (`(?<=[.!?:]) +(- [A-Z])`)
  - Numbered items after punctuation (`(?<=[.!?:]) +(\d+[.)]\s)`)
  - Bold numbered items (`(?<=\S) +(\d+[.)]\s+\*\*)`)
  - Block quotes mid-line (`(?<=\S) +(> )`)
- **SwiftUI Rendering**: `MarkdownBlockView` renders each block type with appropriate styling — `InlineMarkdownText` handles bold, italic, code, and links via `AttributedString`

#### Response Formatting Preservation

- **7 Response-Cleaning Functions Audited**: Identified and fixed markdown stripping across the entire response pipeline
- **`RAGService.cleanupResponseText()`**: Rewritten to only remove orphaned empty markers — previously stripped ALL markdown formatting from every response
- **`AgenticOrchestrator.cleanupFinalAnswer()`**: No longer strips headers (`###`), bullets (`-`), or numbered lists from Deep Think/Maximum mode responses
- **`compactDegenerateResponse()`**: Changed sentence joining from `" "` (space) to `"\n\n"` (paragraph breaks), preserving document structure

#### LLM Prompt Formatting Instructions

- **Standard Pipeline**: System prompts now instruct the LLM to use `### headers`, `- bullets`, and `**bold**` for key terms
- **Deep Think / Maximum Modes**: All 4 synthesis prompts in `AgenticOrchestrator` updated with formatting instructions
- **Integrity Repair**: `buildIntegrityRepairPrompt()` includes formatting instructions so repaired responses maintain structure

#### MMR Crash Fix

- **Array Index Out of Bounds**: Fixed crash in `RAGEngine.applyMMR()` when `mmrDiversityMatrix` returned `[[]]` instead of a proper N×N matrix
- **Root Cause**: `GPUComputeService.mmrDiversityMatrix()` returned `[[]]` for embeddings with dimension 0 — the outer array existed but contained one empty inner array
- **Fix**: Added matrix dimension validation and bounds checking in `RAGEngine.swift`; corrected edge case returns in `GPUComputeService.swift` (`guard count > 1` returns `[]` not `[[]]`, `guard dimension > 0` falls back to CPU)

---

### Device-Optimized Performance Engine

A ground-up performance overhaul that makes every pipeline stage hardware-aware. OCR, embeddings, vector search, and neural reranking now adapt to the specific Apple Silicon chip in your device — from A17 Pro through A19 Pro and M-series.

#### Metal GPU Acceleration

- **3-Tier Metal Shader Selection**: GPU vector search now uses the fastest compatible shader per query:
  - **Threadgroup** (≥1000 vectors, dimension ≤384): Query cached in shared memory + SIMD4 vector ops — fastest path
  - **SIMD4** (100-999 vectors): `float4` hardware vector operations — 4× scalar throughput
  - **Scalar** (fallback): Works with any dimension — baseline
  - Previously ALL GPU searches used the scalar kernel despite SIMD4 and threadgroup kernels being compiled
- **Threadgroup Pipeline**: New `cosineSimilarityThreadgroupPipeline` created at init alongside existing SIMD pipeline
- MiniLM-L6-v2 (384-dim / 4 = 96 float4s) fits exactly within the threadgroup shader's `sharedQuery[96]` limit

#### Vision OCR Concurrency

- **Device-Specific Concurrency**: Vision OCR operations tuned per chip:
  - A19 Pro / M4: 8 concurrent ops, 1ms cooldown
  - A18 Pro / M3: 6 concurrent ops, 2ms cooldown
  - A17 Pro / M2: 4 concurrent ops, 3ms cooldown
  - Mac (Designed for iPad): 4 concurrent ops, 3ms cooldown
  - Older devices: 2 concurrent ops, 6ms cooldown
- **Adaptive OCR Filtering**: `PageComplexityAnalyzer` pre-screens pages before Vision OCR, achieving 50-80% skip rate on clean digital PDFs — fewer total calls enables more aggressive concurrency
- **Concurrent GPU Rendering**: `DocumentProcessor.gpuQueue` upgraded from serial to concurrent — CIContext is thread-safe per Apple documentation, eliminating a bottleneck that serialized ALL CIFilter renders

#### Cross-Encoder Neural Reranking

- **Concurrent Predictions**: Cross-encoder reranking now uses `TaskGroup` with device-tier-aware concurrency (2-4 parallel predictions)
- **Pre-Tokenization**: All query-chunk pairs tokenized before entering the TaskGroup — tokenization overhead moved out of the hot loop
- **Bulk Memory Writes**: `MLMultiArray` population via `dataPointer` bulk copy instead of per-element `NSNumber` subscript — 3× faster array fills
- **Extracted `runPrediction` Closure**: Deduplicated ~90 lines of identical task body code between seed batch and feed loop into single `@Sendable` closure

#### Embedding Pipeline

- **GPU Ingestion Mode**: `CoreMLSentenceEmbeddingProvider` now switches to `.cpuAndGPU` compute units during document ingestion (via `enableIngestionMode()` / `disableIngestionMode()`), freeing the Neural Engine for concurrent Vision OCR
- **Device-Tier Compute Units**: Ingestion mode compute unit selection adapts to device capability tier

#### OCR Quality

- **5-Candidate OCR**: `StructuredDocumentParser` now evaluates `topCandidates(5)` (was 3) for richer candidate selection, improving accuracy on ambiguous text

#### Code Quality

- Updated stale "serial queue" comments across `DocumentProcessor` and `OCRConfiguration` to reflect concurrent queue reality
- Removed dead `activeTasks` counter from `RAGEngine` cross-encoder path

---

### Zero-Data-Loss Ingestion Fixes

Critical fixes that prevent silent content loss on font-encoded PDFs and correct regex patterns that were silently failing.

#### Font Substitution Cipher Detection (PHASE -1)

- **Document-Level Text Layer Validation**: New PHASE -1 runs once per document (~200-500ms) before any per-page processing. Renders one sample page via Vision OCR, compares OCR words to PDFKit words via Jaccard similarity. Threshold < 0.15 = garbled text layer detected (font substitution cipher)
- **Root Cause**: Font-encoded PDFs (Kia, Hyundai, many Asian-publisher manuals) have text layers where every character is shifted (e.g., Caesar cipher: `GPSFXPSE` = "FOREWORD"). This garbled text passes ALL per-page quality checks — 100% printable ASCII, normal word length, NLLanguageRecognizer detects "Dutch" — causing `PageComplexityAnalyzer` to skip OCR entirely. **93% of content was silently lost**
- **Fix**: When garbled flag is set: (1) all pages force image rendering regardless of complexity strategy, (2) `textQualityOK` forced false so PDFKit text is never trusted, (3) dynamic vocabulary mining skips garbled text layer. Every page routes through Vision OCR
- **Impact**: 542-page Kia Sportage manual goes from ~7% to ~100% content capture

#### Raw String Regex Fix

- **Silent Regex Failure**: 5 regex patterns in `OCRConfiguration.normalizeExtractedText()` used `\u{HHHH}` inside Swift raw strings (`#"..."#`). In raw strings, `\u{HHHH}` is literal text, not a Unicode escape. ICU regex requires `\x{HHHH}`. All 5 patterns silently failed — `replacingOccurrences` swallowed the error and returned text unchanged
- **Impact**: CJK bullet artifacts, en-dash/em-dash normalization, and CJK numeral-as-dash replacement were all no-ops. Fixed by changing all `\u{HHHH}` to `\x{HHHH}`

#### Garbled Text Layer Detection for Image Extraction

- **`extractImagesFromPDFPage()`** used `page.string` emptiness as a proxy for "page is visual content." Font-encoded PDFs have garbled text on every page, so the function thought every page had usable text — **skipping image extraction for all pages with diagrams and figures**
- **Fix**: Now uses `isTextQualityAcceptable(rawPageText)` quality gate. Garbled text fails → page treated as visual content → full-page image rendered and analyzed by `ImageUnderstandingService`

#### Dynamic Image Text Budget

- Changed from hardcoded `maxImageTextPerDoc = 3000` to `min(30000, max(3000, extractedImages.count * 500))` — scales with document visual complexity for large manuals

---

### Swift 6 Concurrency Compliance

11 files updated with Swift 6 strict concurrency annotations. All changes are compile-time only — zero runtime behavior change. Eliminates warnings that become hard errors in Swift 6 language mode.

- **`OCRConfiguration.swift`**: Added `nonisolated` to `universalCustomWords`, `recognitionLanguages`, and `configureRequest` to prevent `@MainActor` inference from `VNRecognizeTextRequest` parameter
- **`DocumentChunk.swift`**: Added `nonisolated` to `init` — explicitly callable from any isolation context
- **`DocumentProcessor.swift`**: Added `nonisolated` to `traceIngestionOutcome` (called from 14 `TaskGroup` closures), removed unused `bestConfidence` variable, changed `var processed` to `let`
- **`CaptureToRAGBridge.swift`**: Changed `import Vision` to `@preconcurrency import Vision` to suppress `@MainActor` inference on `VNRecognizeTextRequest`
- **`RAGEngine.swift`**: Added `await` to `DeviceCapabilityService.shared.embeddingConcurrency` access
- **`BNNSVectorDatabase.swift`**: Added `nonisolated(unsafe)` to `loadTask` (accessed in nonisolated init), discarded unused `copyBytes` result, changed `var combined` to `let`
- **`StructuredDocumentParser.swift`**, **`CoreMLRegionDetector.swift`**, **`IntelligentDocumentProcessor.swift`**: Copied mutable `var request` to `let configuredRequest` before `@Sendable` closure capture

---

### Pre-Launch Safety Hardening (P0–P3)

Comprehensive force-unwrap elimination and defensive coding pass across the entire codebase. 37 force-unwrap sites eliminated across 26 files — zero runtime behavior change for valid inputs, crash prevention for edge cases.

#### P0: Crash-Site Elimination (13 files)

- **`ContainerService`**: `loaded.first!` → `guard let` with early return
- **`ContainerVocabularyService`**: `Bundle.main.url(...)!` → `guard let` with early return
- **`IterativeRetrievalService`**: `refinementSession!` → `guard let` with throw
- **`QueryRewriterService`**: `session!` → `guard let` with fallback to original query
- **`SpatialDocumentAnalyzer`**: 4× `.min()!`/`.max()!` → `guard let` multi-binding
- **`ConversationMemoryService`**: `cleaned.first!` → `guard let` with continue
- **`LLMService`**: `trimmed.last!` → `guard let`, `suffixes.last!` → nil-coalesce
- **`LibraryVisualizationEngine`**: 4× `profile.*.first!` → `if let` bindings
- **`SettingsStore`**: `firstCandidates.first!` → `if let` fallback
- **`RAGService`**: `firstIndex(of: "|")!` → guard, `sectionBoostedChunks!` → if-let, 13× `verificationResult!` → if-let block
- **`SpecificationDetector`**: 4× `grouped[key]!` → `grouped[key, default: []]`
- **`SettingsRootView`/`AboutView`**: Hardcoded "Version 1.0.0" → dynamic `Bundle.main` version

#### P1: User-Visible Bug Fixes (5 files)

- **`CachedDocsView`**: `.constant()` alert binding → proper `@State Bool` (alert was undismissable)
- **`DocumentLibraryView`**: `.constant()` alert → `Binding(get:set:)` (alert was undismissable)
- **`AdaptiveVisualizationsView`**: Implemented "Show All Insights" sheet (was empty TODO)
- **`StoreKitBillingService`**: Replaced IUO `var streamContinuation!` with `AsyncStream.makeStream()`
- **`SettingsRootView`**: Removed stub System Status and Developer categories from navigation

#### P2: Code Quality (2 files)

- **`ContextualCompressionService`**: Triple force-unwrap `sectionTitles!` → `.flatMap` pattern
- **`AgenticOrchestrator`**: 3× `docToChunks[key]!` → `docToChunks[key, default: []]`

#### P3: Defensive FileManager & Optional Safety (16 files)

- **12× `FileManager.urls(...).first!`** across 10 storage/service files → `guard let` with descriptive `fatalError` message or safe return
- **`DocumentProcessor`**: 9× `pageText!` → nil-coalescing `(pageText ?? "")` and `.map` patterns
- **`CameraManager`**: `objectList.last!` → `if let` binding

#### P4: Crash-to-Fallback & Dead Code Removal

Eliminated all remaining crash sites and removed dead code. Zero runtime behavior change for valid inputs.

- **10× `fatalError("Application Support directory unavailable")`** across storage/service files (`ContainerVocabularyService`, `EntityIndexService`, `GazetteerService`, `FullTextStorageService`, `SQLiteFullTextService`, `DocumentationCacheService`, `AdapterManager`, `PromptEvaluationService`, `VectorDatabase`) → `?? URL.temporaryDirectory` nil-coalescing for degraded-mode operation instead of crash
- **4× `URL(string:)!`** in `LocalOpenAIServerLLMService` → `?? URL(fileURLWithPath: "/")` for static localhost URLs
- **3 dead files deleted** (−1,344 lines): `SettingsRootView.swift` (698 lines, 0 references), `DeveloperSettingsView.swift` (350 lines, 0 references), `OpenAIResponsesAPIService.swift` (178 lines, entire file was `#if false`)
- **Commented-out `VecturaVectorDatabase` class removed** from `VectorDatabase.swift` (~52 lines)
- **3 silent Vision `catch` blocks** → `Log.debug()` calls in `DocumentCaptureView`, `CameraManager`, `CaptureToRAGBridge`
- **`AssistChatIntent` stub comment** clarified (in use by `sendChatGPTRequest()`, not dead code)

---

### Pipeline Reliability Hardening

11 targeted fixes across the compression → generation → fallback chain to eliminate 0-token LLM responses. Previously, a single rate-limited Apple FM call could cascade into a completely empty answer with no fallback.

#### Compression Hardening (ContextualCompressionService)

- **Fresh Session Per Chunk**: `resetSession()` called before each compression — prevents transcript accumulation that overflowed the 4096-token context window after 3-4 sequential compressions
- **Per-Chunk Error Isolation**: Each `compressChunk()` wrapped in `do/catch` with passthrough fallback — one failed chunk no longer aborts the entire batch
- **12-Second Time Budget**: New `totalTimeBudget` parameter (default 12s) — if compression exceeds budget, remaining chunks passthrough as originals. Prevents hung FM calls from blocking the pipeline indefinitely
- **Compression Cap**: Maximum 5 chunks sent to compression (was unlimited) — reduces sequential FM calls that exhaust rate limits before generation

#### Generation Hardening (RAGService)

- **Empty Response → Reliability Fallback**: LLM returning 0 tokens now routes to `buildReliabilityFallbackResponse()` instead of throwing `modelNotAvailable` — which previously bypassed the fallback entirely, showing users a generic error instead of extracted content
- **Post-Compression Cooldown**: 1-second `Task.sleep` after compression (when savings > 0) lets Apple FM rate limits recover before the main generation call
- **Rate-Limit Retry with Backoff**: `generateWithFallback()` detects rate-limited/concurrent errors, sleeps 2 seconds, and retries once before falling through to fallback services
- **Partial Stream Threshold**: Lowered from 24 → 10 characters — salvages more partial output from interrupted generation streams

#### Error Typing (LLMService)

- **Typed `LLMError` Cases**: Added `.rateLimited(String)` and `.concurrentRequests(String)` to the `LLMError` enum — replaces fragile string matching with direct pattern matching
- **Apple FM Error Routing**: `LanguageModelSession.GenerationError.rateLimited` and `.concurrentRequests` now throw typed errors instead of generic `.generationFailed(String)`

#### Fallback Quality (RAGService)

- **Extractive Path B Rewrite**: When all LLM attempts fail, the extractive fallback now uses 6 chunks × 500 characters (was 3 × 240) with section titles, source document names, and an explanatory header
- **Fallback Error Logging**: Reliability fallback LLM failure now logged with `do/catch` (was silent `try?`)

#### UI Error Handling (ChatScreen)

- **Exhaustive Error Switch**: `ChatScreen.friendlyErrorMessage()` handles `.rateLimited` and `.concurrentRequests` with user-friendly messages

---

### Memory-Safe Large PDF Ingestion

Prevents OOM watchdog kills during ingestion of 500+ page PDFs. A 542-page Kia Sportage manual was being killed by the debugger during the post-parsing image analysis phase.

- **Results Array Release**: `results.removeAll()` called after extracting `allElements`/`pageTexts`, freeing ~100-200MB of `PageParseResult` objects before image analysis begins
- **Image Batch Size 20 → 5**: Peak CIImage memory reduced from ~200MB to ~50MB per batch — 4 failing pages in a 5-page batch = ~16MB vs ~200MB in a 20-page batch
- **144 DPI Image Understanding**: Full-page renders for `ImageUnderstandingService` use 2× scale (144 DPI) instead of 5× (360 DPI) — each page drops from ~25MB to ~4MB. Vision classification and OCR don't need 360 DPI for image content analysis
- **autoreleasepool for Full-Page Renders**: Intermediate Core Graphics allocations from `renderPDFPageAsImage()` released immediately instead of accumulating until batch completion

---

### True Parallel Hybrid Search

Hybrid search rewritten from "FTS5 injection into vector pool" to **two fully independent searches merged via Reciprocal Rank Fusion**. Previously, FTS5 hits were injected into the vector result pool with a synthetic 0.40 similarity score, then everything was re-scored with in-memory BM25. Now:

- **Parallel execution**: Vector search and FTS5 chunk search run concurrently via `async let` (~40% faster)
- **Native SQLite `bm25()` scoring**: Uses SQLite's built-in BM25 function at chunk granularity instead of in-memory `BM25Scorer.snapshot(from:)` — eliminates local IDF bias from small candidate pools
- **FTS5-only matches no longer invisible**: Chunks found only by FTS5 (exact keyword match, no semantic similarity) get a fair RRF score from their BM25 rank alone
- **True RRF fusion**: Two independently ranked lists merged via `reciprocalRankFusion()` which handles the UNION of both sets
- **Location**: `HybridSearchService.searchWithFTS5()`

---

### Onboarding Polish

Six targeted improvements to the first-launch experience covering haptic feedback, accessibility, analytics, error messaging, and privacy permissions.

#### Haptic Feedback

- **6 Haptic Touch Points**: Added `DSHaptics` feedback across every onboarding interaction — `light` on Skip/dismiss, `selection` on Continue, `medium` on Get Started, `light` on "I'll add my own documents", `success` on import completion, `error` on import failure

#### Onboarding Analytics Separation

- **`markOnboardingCompleted()` vs `skipPermanently()`**: Previously both paths used `skipPermanently()`, making it impossible to distinguish users who completed onboarding from those who dismissed it. New `completionMethod` UserDefaults key records `"completed"` or `"skipped"`. New `wasCompletedProperly` computed property for analytics
- **`markSamplesImported()` called on completion**: The primary success path now properly calls `markSamplesImported()` through `markOnboardingCompleted()`, ensuring the checklist reflects actual sample import state

#### Accessibility

- **Pipeline Visualization Labels**: `PipelineStageBadge`, processing overlay header, and `OnboardingIngestionRow` now have `.accessibilityElement(children: .combine)` with descriptive `.accessibilityLabel` and `.accessibilityValue` — VoiceOver users can follow ingestion progress

#### Error UX

- **Import Failure Message**: Changed "Import failed — tap to retry" to "Import failed — please try again" — the previous wording implied a tap target that didn't exist

#### Privacy Permissions

- **`NSMicrophoneUsageDescription`**: Added to both Debug and Release build configurations — "Record voice queries or dictate text for hands-free document search." Required for Speech framework voice input

---

## [1.1.0] - 2026-02-13 (Build 12)

### Motherboard HUD — Real-Time Apple Silicon X-Ray Overlay

A full-screen X-ray overlay that shows where Apple Silicon components physically sit behind the iPhone screen. The HUD renders real-time hardware telemetry at the actual chip positions verified from iFixit teardown images + Apple Vision AI.

#### New Features

- **MotherboardHUDView** (622 lines): Full-screen transparent overlay showing SoC, NAND, DRAM, modem, PMIC, WiFi/BT, and Taptic Engine positions with live CPU/GPU/Neural Engine activity indicators
- **HardwareTelemetryState** (1,014 lines): Centralized hardware telemetry service tracking CPU usage, GPU load, memory pressure, thermal state, battery level, and Neural Engine activity in real-time
- **Device-Specific Component Positioning**: Vision AI-verified teardown positions for every Apple Intelligence-capable iPhone:
  - iPhone 15 Pro/Max (A17 Pro)
  - iPhone 16/Plus (A18)
  - iPhone 16 Pro/Max (A18 Pro)
  - iPhone 17 Pro/Max (A19 Pro)
- **Taptic Engine Visualization**: Animated haptic feedback indicator at the actual Taptic Engine position
- **Ultra-Subtle Design**: Components render as barely-visible ghost outlines that pulse with activity — visible enough to be informative without distracting from chat
- **User Toggle**: Enable/disable the HUD from Settings → Telemetry section
- **ChatScreen Integration**: HUD overlays the chat interface as a ZStack layer, updating in real-time during queries

#### Universal Retrieval Improvements (Fixes 1-8)

Eight research-grade fixes to achieve near-universal needle-in-haystack retrieval accuracy:

- **Fix 1 — Lexical Always-On**: BM25 keyword search now always contributes to hybrid search results, even when vector search dominates
- **Fix 2 — Proportional Hit-Rate**: RRF fusion weights adjusted proportionally based on each search method's hit count
- **Fix 3 — HyDE Blended Embedding**: HyDE hypothetical document embedding blended 70/30 with original query embedding instead of replacing it
- **Fix 4 — Year Range Exemption**: Verification Gate C now exempts years 1900-2100 and small integers 1-10 from numeric hallucination checks
- **Fix 5 — Sentence-Scored Fallback**: Contextual Compression falls back to sentence-level scoring when LLM compression fails, preserving information
- **Fix 6 — Rare Terms in Vocabulary**: Query expansion now includes rare corpus terms that exactly match query words
- **Fix 7 — Corpus-Learned Synonyms**: Dynamic synonym generation from document co-occurrence data, supplementing the hardcoded synonym dictionary
- **Fix 8 — Adaptive Reranking Ceiling**: Cross-encoder candidate pool scales adaptively: `min(count, max(100, topK×5))` instead of fixed 100 cap

#### Repository & Infrastructure

- **Sensitive File Cleanup**: Added sensitive files to .gitignore, cleaned repository history
- **Google Ads Campaign Materials**: Added complete marketing asset package (headlines, descriptions, keywords, audiences, campaign setup guides, image/video specs)
- **Apple Document Intelligence Reference**: Added comprehensive 1,700-line Apple framework reference document

### Changed

- **Service Count**: 80 services across 10 categories (added HardwareTelemetryState)
- **Theme System**: Extended UI theme with HUD-specific colors and opacity levels
- **Settings View**: Added Motherboard HUD toggle with device-specific chip name display

---

## [1.0.1] - 2026-02-07 (Build 11)

### RAG Pipeline Optimization (10x Expert Pass)

Comprehensive end-to-end pipeline audit and optimization. Standard mode now performs at near-perfect retrieval accuracy for specification queries against large documents (1400+ chunks).

#### Token Budget & Context

- **Conditional tool schema tokens**: Tool schema overhead (1000 tokens) only reserved when tools are enabled. Reclaims ~24% of the 4096-token budget for non-agentic queries.
- **Unified safety margin**: Replaced compound safety (15% × factor + 400 flat) with single 12% haircut. Net gain: ~300 chars more context per query.

#### Hybrid Search & Retrieval

- **FTS5 phrase-match bug**: `escapeFTS5Query()` was wrapping multi-word queries as `"exact phrase"` (0 results). Rewritten to OR-joined terms: `"oil" OR "car" OR "take"`.
- **Keyword boost stopwords**: Added domain-aware stopwords (`"type"`, `"car"`, `"take"`, `"kind"`, `"vehicle"`, etc.) to `extractImportantKeywords`. Previously 160/300 chunks were boosted; now only truly relevant keywords boost (~55 chunks for "oil").
- **Keyword deduplication**: `extractImportantKeywords` now uses `Set` to prevent duplicate tokens from expanded queries inflating boost counts.
- **Post-RRF boost rewrite**: Keyword and structure boosts changed from full re-sort to additive score adjustments (keyword: +0.03/match capped at 0.12, structure: +0.02/point capped at 0.15). Preserves RRF fusion ordering.
- **BM25 tokenizer caching**: Cached `NLTokenizer` instances in `RAGEngine`, `BM25Scorer`, and `HybridSearchService` to avoid repeated allocation.
- **`originalQuery` parameter**: `HybridSearchService.search()` now accepts `originalQuery` so FTS5 and keyword boost use the clean user query, not the expanded version.

#### Query Expansion

- **Expansion bloat reduction**: Removed bare "overview"/"summary" expansions; max reduced from 8 to 6 variations.
- **Corpus expansion noise filter**: Added non-Latin script rejection (OCR artifacts like "僅"), short alphanumeric noise rejection ("SENSOR4", "10A").
- **Corpus key term filtering**: Key terms like "type", "does", "car" filtered through `corpusStopwords` before co-occurrence lookup to prevent irrelevant expansions ("indicator lights", "lamp", "turn signal lever").
- **Phrase expansion leak**: `findCorpusPhrases` now uses substantive terms only, not raw key terms.

#### Extractive QA

- **ExtractiveQA chunk scope**: Now receives top 8 spec-prioritized chunks (`orderedCandidates.prefix(8)`) instead of only the 3 budget-truncated context chunks. Ensures oil spec chunks are scanned even when fuse-box tables filled the context budget.
- **Chunk slicing bug**: `includedRetrievedChunks` now sliced from `orderedCandidates` (post-sort) instead of `contextCandidates` (pre-sort). Previously spec prioritization sorted correctly but the slicing ignored it.
- **Category-aware Code filter**: Even without Grade candidates, Code candidates (fuse box entries) now require ≥1 matched keyword within proximity. Eliminates 31+ fuse-code false positives like "HEATER3", "PUMP 20A".
- **Distance vs Grade scoring**: Distance measurements (km, miles, m) score 0.01 vs Grade's 0.12 (was 0.08 vs 0.10). Prevents "13,000 km" from competing with "0W-20".

#### SpecificationDetector

- **Grade pattern overhaul**: `\d+[A-Z]-\d+|\b[A-Z]\d+` → `\d+W-\d+`. Old pattern matched any letter+digit (G2, E85, C3, A3). New pattern matches only oil viscosity grades (0W-20, 5W-30, 10W-40).
- **PartNumber pattern fix**: Old pattern `[A-Z0-9]{2,}[-.]?[A-Z0-9]{2,}[-.]?[A-Z0-9]{2,}` with `.caseInsensitive` matched every 6+ letter English word ("engine", "change", "service", "normal", "maintenance"). Now requires a dash/dot delimiter.

#### Verification Gates

- **Gate C wider chunk scope**: Numeric verification now receives all `contextCandidates` (post-MMR), not just the 3 budget-truncated chunks. Prevents false "unverified" flags for numbers from spec-rescued chunks.
- **Gate C year/metadata exemption**: Years (2020-2030) and small integers (1-10) auto-verified as metadata. "2024" model year no longer penalizes confidence.
- **Gate C threshold**: Relaxed from 80% → 70%. Still catches egregious hallucination while not punishing correct responses with incidental metadata numbers.

#### Spec Preservation

- **Rescue score fix**: Changed from `topScore + 0.05` (ranked #1) to `topScore - 0.02` (floor 0.5). Rescued spec chunks now rank just below organic top results.
- **Removed domain viscosity regex**: The spec rescue system no longer uses a domain-specific viscosity pattern. SpecificationDetector's universal patterns handle detection.

#### System Prompts

- **6 prompts rewritten**: All system prompts (Standard, Deep Think, Maximum × with/without tools) rewritten from procedural/robotic to natural, conversational tone. Removed rigid word minimums; added "talk to friends" style instructions.

#### Anti-Hallucination

- **Rule 6 softened**: "NEVER say I don't have information" → "Prefer providing relevant information". Prevents over-eager abstention on valid queries.

### Research-Grade Retrieval Audit

10-area audit (Chunking, BM25/FTS5, Re-ranking, Context Assembly, Parent Doc, Verification, Query Enhancement, HyDE, Iterative Retrieval, Contextual Compression) graded B+/A-. Four critical gaps fixed to reach research-grade needle-in-haystack retrieval.

#### FTS5 Query Construction

- **AND-first queries**: `escapeFTS5Query()` rewritten from OR-joined (`"oil" OR "capacity"`) to AND-first (implicit conjunction: `oil capacity`). OR matched every page mentioning any single term; AND requires all terms to co-occur. Automatic OR fallback via `escapeFTS5QueryBroad()` + `searchBroad()` if AND returns 0 results.
- **Domain-aware FTS5 stopwords**: Added `"kind"`, `"type"`, `"car"`, `"take"`, `"use"`, `"need"`, `"vehicle"`, `"much"` to FTS5 stopword list. These common query words diluted AND precision.

#### Chunk-Level BM25 Scoring

- **FTS5 path chunk granularity**: The FTS5-accelerated search path was scoring BM25 at the **document level** — `SQLiteFullTextService` stores entire documents, so all chunks from the same document received identical BM25 scores. Replaced with in-memory `BM25Scorer.snapshot()` on vector candidates for per-chunk scoring. The non-FTS5 path already had this; now both paths match.

#### Iterative Retrieval

- **Auto-enable for multi-hop intents**: `IterativeRetrievalService` was fully implemented but hardcoded to `false` (`settingsStore?.enableIterativeRetrieval ?? false`). Now auto-enables for multi-hop query intents (`investigate`, `compare`, `findings`) in Deep Think and Maximum modes via `answerIntent.benefitsFromMultiHop`.

#### Table Preservation (SemanticChunker)

- **Atomic table detection**: New pre-pass `detectTableBlocks()` scans for contiguous markdown tables (2+ `|` per line) and tab-separated data (2+ tabs with content). Requires ≥2 consecutive matching lines.
- **Chunk boundary protection**: `findOptimalChunkRange()` now receives `tableBlocks` parameter. Section and topic boundaries inside table blocks are skipped. Table ends are preferred as natural break points. If the fallback word-count boundary lands inside a table, the chunker either extends to include the full table (if within `maxSize`), snaps back to before the table, or includes it as an oversized atomic unit.
- **Both chunking paths covered**: Sync (`chunkText`) and async (`chunkTextWithBoundaries`) paths both detect and respect table blocks.

#### Deep Think / Maximum Mode Parity

- **`originalQuery` in `executeFullRetrievalPipeline`**: All 7 AgenticOrchestrator call sites now receive FTS5 + keyword boost from the clean user query, not the expanded version.
- **Corpus vocabulary in agentic path**: `executeFullRetrievalPipeline()` now builds/caches `CorpusVocabulary` if not already cached, ensuring Deep Think and Maximum get corpus-aware query expansion.
- **ExtractiveQA pre-check**: AgenticOrchestrator Step 2.1 attempts direct specification extraction for `lookup`/`tableLookup` intents before entering multi-session reasoning. Saves 4-8 LLM sessions when the answer is directly extractable.

## [1.0.0] - 2026-01-26 (Build 10)

### Added

- **Standalone Image Visual Understanding**: Imported images (JPEG, PNG, HEIC) now get full visual analysis:
  - Vision classification (photo, diagram, chart, screenshot, logo, etc.)
  - OCR text extraction (labels, product names, annotations)
  - AI description generation (iOS 26+ Apple Intelligence)
  - Structured output for RAG: `[Image: Type]\nContent: labels\nText: "OCR"\nDescription: AI`
  - Previously: standalone images only got raw OCR text
- **Device-Tier-Aware Vision Concurrency**: VisionOCRThrottle now adapts to specific hardware:
  - A18 Pro: 5 concurrent ops, 5ms cooldown
  - A19 Pro: 6 concurrent ops, 4ms cooldown
  - M-series iPad Pro: 6 concurrent ops, 5ms cooldown
  - Mac (iPad compatible): 3 concurrent ops, 8ms cooldown
- **Mac Platform Detection**: DeviceCapabilityService `isMac` property detects both native Mac and iPad apps on Mac.
- **Parallel Image Analysis**: ImageUnderstandingService.analyzeDocumentImages now uses TaskGroup for ~5x speedup.
  - Previously sequential: each image processed one-by-one
  - Now parallel: up to 5-6 concurrent image analyses (gated by VisionOCRThrottle)
- **Actor-Based Vision Throttling**: VisionOCRThrottle now uses Swift Concurrency's AsyncSemaphore pattern.
  - Eliminates priority inversion warnings ("Hang Risk") for async methods
  - Uses `CheckedContinuation` for cooperative thread suspension
  - Swift runtime handles priority propagation automatically

### Fixed

- **Mac Metal Compatibility**: Fixed Vision framework crash on Mac ("Designed for iPad" mode).
  - Apple's Vision framework internally calls `synchronizeResource:` on shared memory buffers
  - Apple Silicon uses `MTLResourceStorageModeShared` - synchronization is invalid
  - GPU validation disabled in Xcode scheme (debug-only issue)
  - VisionOCRThrottle detects `ProcessInfo.isiOSAppOnMac` and skips GPU sync
  - Conservative Mac concurrency prevents Metal command buffer scheduling issues
- **Self-Tuning Auto-Rebuild Bug**: Fixed immediate re-embedding of ALL documents after adding one file.
  - Added 30-second cooldown after ingestion before allowing self-tuning rebuilds
  - Visible logging for self-tuning decisions (`Log.warning` with details)
- **Swift 6 Warnings**: Removed unnecessary `nonisolated(unsafe)` from Sendable types in VisionOCRThrottle.swift and StructuredDocumentParser.swift.
- **iPhone Memory Exhaustion (OOM)**: Fixed 2.7GB memory spike on large PDFs with many images.
  - `analyzeEmbeddedImages` was loading ALL images into memory before analysis
  - Now processes in 20-page batches, releasing CIImages after each batch
  - Peak memory reduced from 5+ GB to ~960MB for image analysis phase

### Performance

- **iOS 26 Vision Optimizations**: Leveraging WWDC 2025 Vision framework improvements:
  - RecognizeDocumentsRequest batch scheduling improvements
  - Device-tier-aware cooldown times (4-8ms depending on chip)
  - Balanced concurrent Vision operations (5-6 on A18/A19 Pro)

## [1.0.0] - 2026-01-20 (Build 4)

### Added

- **Container Dimension Migration**: Auto-fixes containers with invalid embedding dimensions (784→384) or unsupported providers (nl_contextual→coreml) at load time.
- **Ingestion Queue Granular UI**: Maximum transparency ingestion overlay with 4-row metrics display:
  - Real-time semantic boundary detection (sections, topic boundaries, embedding gradients)
  - Entity extraction visualization with top entities preview
  - Throughput calculations (words/sec, chunks/sec, vectors/sec)
  - Timing waterfall with per-stage progress bars
- **Shorthand Provider Labels**: Compact provider names for UI pills (CoreML, NL, FM, OpenAI, NLCtx).
- **Shorthand Chunking Strategy Labels**: Abbreviated strategy names (Semantic, Sent, Para, etc.).

### Fixed

- **Maximum Mode 0% Confidence**: Confidence now starts at 5% baseline, showing meaningful progress (5%→12%→20%→...) instead of (0%→0%→0%→85%).
- **Export Options Plist**: Fixed App Store submission with correct export options.

## [1.0.0] - 2026-01-09 (Build 3)

### Added

- **Query Intent Classification**: Classifies queries as keyword/conceptual/balanced for optimal retrieval strategy.
- **Per-Query Weight Tuning**: Dynamic vector/keyword weights based on query intent (keyword→more BM25, conceptual→more vector).
- **Content-Type Auto-Tuning**: Auto-select RetrievalConfig based on document types in container.
- **Corpus-Aware Query Expansion**: Expands queries using actual document vocabulary with garbage filtering.
- **Lost-in-Middle Mitigation**: Reorders context chunks so best matches appear at start AND end (Liu et al. 2023).
- **Cross-Encoder Re-ranking**: BERT-based CoreML reranker with heuristic fallback.
- **Memory Caching**: Per-container vocabulary cache prevents repeated `allChunks()` calls.
- **Content-Adaptive Chunking**: Different presets for code (250w/40w), technical (280w/50w), narrative (400w/70w).

### Changed

- **Context Budget**: Increased from 5000 to 7500 chars; safety margin reduced 900→500 tokens.
- **Chunking Strategy**: Optimized to 280-400 words with ~17% overlap (was 220w at 50% overlap).
- **System Prompts**: Enhanced for comprehensive, detailed responses (150-300 word minimum guidance).
- **Default Chunk Size**: 350 words target (was 400), 60 word overlap (was 75).

### Fixed

- **Memory Leak**: Fixed vocabulary reload on every query via `corpusVocabularyCache`.
- **PCC Token Limit**: Corrected to 4096 tokens (was incorrectly documented as 65K in UI).
- **Offline Capability**: Fixed inaccurate descriptions about always-available offline mode.
- **UI Defaults**: All settings screens now show correct optimized chunking values.

## [0.9.0] - 2025-11-19 (Internal Beta)

### Added

- **Hybrid Search Engine**: Full implementation of BM25 + Vector Search + RRF Fusion.
- **Agentic Tooling**: 8 `@Tool` functions for Apple Intelligence integration (iOS 26 FoundationModels.Tool protocol).
- **Telemetry Dashboard**: Real-time visualization of RAG pipeline performance (TTFT, Tokens/sec).
- **Apple Foundation Models**: iOS 26 Foundation Models with PCC fallback.
- **OnDeviceAnalysisService**: Extractive QA fallback (always available offline).
- **Privacy Controls**: Private Cloud Compute (PCC) toggles and execution location badges.
- **NLContextualEmbedding Provider**: BERT-like contextual embeddings for 15-25% accuracy boost.
- **AdaptiveEmbeddingOptimizer**: Auto-recommends optimal embedding based on corpus complexity.
- **SemanticChunker**: Paragraph-aware chunking with topic boundary detection.
- **VectorStoreRouter**: Per-container database routing with LRU cache.

### Changed

- **Architecture**: Refactored to a Protocol-First design with `RAGService` orchestration.
- **Concurrency**: Moved heavy compute to `RAGEngine` actor for UI responsiveness.
- **Documentation**: Complete rewrite of `README.md` and architecture docs.
- **Cloud LLM Removal**: Removed OpenAI/GPT direct API integration (Apple-only now).
- **Local Model Removal**: Removed GGUF/CoreML/MLX downloadable models for simpler maintenance.
