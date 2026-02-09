# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
