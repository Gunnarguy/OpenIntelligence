# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
