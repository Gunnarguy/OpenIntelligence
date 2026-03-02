# OpenIntelligence Roadmap

**Last Updated**: March 2, 2026
**Version**: 2.0 (Build 19)
**Status**: App Store Live
**Maturity**: Production RAG pipeline with 8 agentic tools + Motherboard HUD + Device-Optimized Performance Engine + Rich Markdown Rendering + Zero-Data-Loss Ingestion + Swift 6 Compliance + Pipeline Reliability Hardening + Memory-Safe Large PDF Ingestion
**Next Milestone**: v2.1 — Apple Intelligence Gap Closure (Guardrails, CoreSpotlight, SpeechAnalyzer, Translation, Liquid Glass, UseCase/Locale)

---

## 🎉 v1.0.0 COMPLETE - App Store Ready

**What OpenIntelligence Does:**
Import any document. Ask questions. Get cited answers. All on-device.

### RAG Pattern Coverage (16 Industry Patterns)

OpenIntelligence implements **14 of 16** recognized RAG architectural patterns:

> **Note**: 3 patterns (Federated, Streaming, ODQA) are N/A by design—not gaps but architectural decisions for privacy-first, document-scoped use case.

| #   | Pattern                      | Status | Implementation                                                                            |
| --- | ---------------------------- | ------ | ----------------------------------------------------------------------------------------- |
| 1   | **Standard RAG**             | ✅     | Foundation - 25-step pipeline                                                             |
| 2   | **Agentic RAG**              | ✅     | `AgenticOrchestrator`, 8 @Tool functions, recursive research loops                        |
| 3   | **Graph RAG**                | ✅     | `EntityIndexService` + 2-hop entity expansion (GraphRAG-Lite)                             |
| 4   | **Modular RAG**              | ✅     | Protocol-oriented design, 102 swappable services                                          |
| 5   | **Memory-Augmented RAG**     | ✅     | `ConversationMemoryService` (persistent per-container disk storage with debounced writes) |
| 6   | **Multi-Modal RAG**          | ✅     | Image classification, OCR, audio transcription, caption association                       |
| 7   | **Federated RAG**            | ⬜     | N/A - 100% on-device architecture                                                         |
| 8   | **Streaming RAG**            | ⬜     | N/A - Document-based, not real-time feeds                                                 |
| 9   | **ODQA RAG**                 | ⬜     | N/A - Scoped to user's documents, not open-domain                                         |
| 10  | **Contextual Retrieval RAG** | ✅     | Query rewriting, pronoun resolution, follow-up handling                                   |
| 11  | **Knowledge Enhanced RAG**   | ✅     | Entity extraction, EntityIndexService, structured ChunkMetadata                           |
| 12  | **Domain-Specific RAG**      | 🟡     | Content-type configs exist; domain profiles planned                                       |
| 13  | **Hybrid RAG**               | ✅     | `HybridSearchService` - BM25 + Vector + RRF fusion                                        |
| 14  | **Self-RAG**                 | ✅     | Self-RAG 2.0 with 4 Verification Gates, multi-session enrichment                          |
| 15  | **HyDE RAG**                 | ✅     | `HyDEService` - Hypothetical Document Embedding                                           |
| 16  | **Recursive/Multi-Step RAG** | ✅     | Recursive research loops, multi-chain maximum mode                                        |

**Legend**: ✅ Implemented | 🟡 Partial | ⬜ Not Applicable

**RAG Pipeline: 25 Steps End-to-End (102 Services)**

| Phase            | Steps | Details                                                                                                                                               |
| ---------------- | ----- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ingestion        | 6     | Parse → SemanticChunker → Entity Extraction → Token Validation → Embedding → Store (HNSW + FTS5 + EntityIndex)                                        |
| Query Processing | 7     | Corpus Analysis → Query Understanding → Query Expansion → Intent Classification → Query Embedding → RAPTOR-lite Routing → Hybrid Search               |
| Post-Retrieval   | 7     | Cross-Encoder Rerank → Low-Confidence Filter → Multi-Doc Representation → MMR → Parent Doc Retrieval → Contextual Compression → Graph Context Packing |
| Generation       | 3     | Context Assembly (Lost-in-Middle) → Extractive Summarization/QA → LLM Generation                                                                      |
| Post-Generation  | 4     | Quality Assessment → Verification Gates A-D → Calibrated Confidence → Response Metadata                                                               |
| Rendering        | 2     | Markdown Rendering (block-level parser + inline normalizer) → Inline Normalization (6 regex patterns)                                                 |

**102 Services across 11 categories**: See [ARCHITECTURE.md](ARCHITECTURE.md) → "Complete Service Inventory"

**Core Features Shipped:**

- ✅ Full RAG pipeline (25-step, 102 services: hybrid search, neural reranking, MMR, verification gates)
- ✅ Apple Intelligence integration (iOS 26 Foundation Models)
- ✅ Multi-format support: PDF, DOCX, XLSX, PPTX, TXT, MD, CSV, RTF, images
- ✅ 8 agentic @Tool functions for intelligent document analysis
- ✅ Self-RAG 2.0 multi-session reasoning with enrichment prompting
- ✅ Metal GPU-accelerated OCR (360 DPI, device-tier-aware concurrency)
- ✅ **Adaptive Document Intelligence Engine** (5-strategy preprocessing, multi-candidate confidence OCR, dynamic vocabulary extraction, language-agnostic quality detection)
- ✅ **Motherboard HUD** — Real-time Apple Silicon X-ray overlay with device-specific component positions, live CPU/GPU/Neural Engine telemetry
- ✅ **Universal Retrieval** — 8 research-grade fixes for near-perfect needle-in-haystack accuracy (lexical always-on, HyDE blending, corpus-learned synonyms, adaptive reranking)
- ✅ Platform-aware Vision throttling (iOS/iPadOS optimized, Mac compatible)
- ✅ TOC-aware reranking (demotes table-of-contents chunks)
- ✅ Container-based knowledge organization
- ✅ StoreKit 2 subscription billing
- ✅ Swift 6 strict concurrency compliance — 11 files updated with `nonisolated`, `@preconcurrency`, `await`, `configuredRequest` captures (compile-time only, zero runtime change)
- ✅ **Device-Optimized Performance Engine** — 3-tier Metal GPU shaders (threadgroup/SIMD4/scalar), device-specific OCR concurrency (A19: 8 ops/1ms), concurrent cross-encoder reranking (pre-tokenized TaskGroup), GPU embedding ingestion mode, concurrent CIFilter rendering
- ✅ **Rich Markdown Response Rendering** — Full block-level markdown parser (headings, bullets, numbered lists, code fences, block quotes), inline normalization preprocessor (6 regex patterns for Apple FM single-line output), formatting-aware LLM prompts, 7 response-cleaning functions audited to preserve markdown
- ✅ **MMR Crash Fix** — Fixed array index out of bounds in `RAGEngine.applyMMR()` when GPU diversity matrix returned malformed results for edge-case embeddings
- ✅ **Zero-Data-Loss Ingestion** — PHASE -1 font substitution cipher detection via Jaccard similarity (prevents 93% content loss on Kia/Hyundai manuals), raw string regex fix (5 patterns), garbled image extraction fix, dynamic image text budget scaling
- ✅ **True Parallel Hybrid Search** — Vector + FTS5 run concurrently via `async let`, native SQLite `bm25()` with weighted columns (10/5/1), FTS5-only matches surface through RRF, replaces sequential re-scoring architecture
- ✅ **Test Suite Removed** — Mock-based unit tests (200+ across 15 files) removed; Apple on-device frameworks (FoundationModels, Vision, CoreML) are untestable on simulator, BM25 tests crashed simulator process
- ✅ **Pipeline Reliability Hardening** — 11 targeted fixes across compression → generation → fallback chain: compression cap (5 chunks), fresh session per chunk, per-chunk error isolation, 12s time budget, empty→fallback routing, 1s post-compression cooldown, 2s rate-limit retry, typed `.rateLimited`/`.concurrentRequests` LLM errors, extractive Path B rewrite (6×500 chars), partial stream threshold 24→10, error logging in reliability fallback
- ✅ **Memory-Safe Large PDF Ingestion** — OOM prevention for 500+ page PDFs: `results.removeAll()` before image analysis, batch 20→5 pages, 144 DPI (2×) image understanding renders (was 360 DPI/5×), autoreleasepool for Core Graphics intermediates
- ✅ **Typed LLM Error Cases** — `.rateLimited` and `.concurrentRequests` cases in `LLMError` enum with exhaustive `switch` handling in ChatScreen, replacing fragile string matching
- ✅ **RAG-Grounded Response Transforms** — `ResponseTransformService` with 5 document-aware transforms (Key Facts, Step-by-Step, Cross-Reference, Deep Dive, Flash Cards) using retrieved source chunks. AI Hub toolbar redesign with `apple.intelligence` icon
- ✅ **Image Playground LLM Concepts** — On-device LLM translates domain jargon into visual scene descriptions for Image Playground (eliminates "try another description" errors)
- ✅ **BM25 `b` Parameter Fix** — Aligned RAGEngine `b=0.75` to `b=0.5` (matches HybridSearchService; correct for uniform chunk sizes)
- ✅ **Accelerate Gate E** — `vDSP.dot()` replaces manual cosine similarity loop in VerificationGateService
- ✅ **Regex Pre-Compilation** — RAGEngine compiles patterns once as `static let` instead of per-query

---

### � Apple Technology Integration Assessment

**Summary**: OpenIntelligence leverages **8 major Apple frameworks** extensively. We've identified **23 additional Apple Intelligence framework opportunities** across v2.1/v2.2/v3.0 milestones (see Phase 2.15 — Apple Intelligence Gap Closure).

> **Reference**: See [Docs/reference/APPLE_DOCUMENT_INTELLIGENCE.md](Docs/reference/APPLE_DOCUMENT_INTELLIGENCE.md) for comprehensive Apple framework documentation.

#### ✅ Fully Integrated Apple Frameworks (8)

| Framework            | Services Using It                                                                               | Key APIs                                                                                               |
| -------------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| **FoundationModels** | `AppleFoundationLLMService`, `HyDEService`, `ContextualCompressionService`, all @Tool functions | `LanguageModelSession`, `@Generable`, `@Guide`, `@Tool`, `prewarm()`, `LanguageModelFeedback`, TN3193  |
| **Vision**           | `OCRConfiguration`, `DocumentProcessor`, `StructuredDocumentParser`                             | `VNRecognizeTextRequest` Rev3, `RecognizeDocumentsRequest`, `topCandidates(5)`, adaptive preprocessing |
| **NaturalLanguage**  | `QueryEnhancementService`, `SemanticChunker`, `DocumentProcessor`                               | `NLTagger` (NER, POS), `NLTokenizer`, `NLLanguageRecognizer`, `NLEmbedding` (512D fallback)            |
| **CoreML**           | `CoreMLSentenceEmbeddingProvider`, `RAGEngine`, `CoreMLDocumentClassifier`                      | MiniLM-L6-v2 embeddings (384D), TinyBERT reranker, FastViT classifier (optional)                       |
| **PDFKit**           | `DocumentProcessor`                                                                             | `PDFDocument`, `PDFPage`, page-by-page text extraction                                                 |
| **Speech**           | `AudioTranscriptionService`                                                                     | `SFSpeechRecognizer`, on-device transcription for M4A/MP3/WAV/MP4                                      |
| **Metal**            | `GPUComputeService`, `VisionOCRThrottle`, `BNNSVectorDatabase`                                  | GPU-accelerated matrix operations, 3-tier shader selection, parallel OCR concurrency                   |
| **StoreKit 2**       | `StoreKitBillingService`                                                                        | `Product`, `Transaction`, `StoreKit.Transaction.updates`, subscription management                      |

#### ✅ Ready But Deferred (Code Complete, UI Disabled)

| Feature                 | Framework        | Status                                                              | Target |
| ----------------------- | ---------------- | ------------------------------------------------------------------- | ------ |
| Camera Vision Overlay   | Vision + FM      | `/Features/Camera/` complete; RecognizeDocumentsRequest implemented | v3.0   |
| Live Document Detection | VisionKit        | `DataScannerViewController` not yet wired; code ready               | v3.0   |
| Image Description       | FoundationModels | Image prompts work; awaiting Apple Intelligence image support GA    | v3.0   |

#### 🟡 Partial Integration (Opportunities Identified)

| Opportunity              | Framework             | Current State                                                                                                                                                                               | Planned Enhancement                      | Target |
| ------------------------ | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------- | ------ |
| Custom Entity Extraction | NLGazetteer           | Using NLTagger NER (persons, places, orgs)                                                                                                                                                  | Train gazetteer on product names, SKUs   | v2.2   |
| Multi-Language Docs      | Translation.framework | Language detection works; no auto-translation                                                                                                                                               | Translate foreign docs before embedding  | v2.1   |
| Domain Classifiers       | CreateMLComponents    | Static content-type configs                                                                                                                                                                 | Train classifiers on user's doc patterns | v3.0   |
| WritingTools Integration | WritingTools (iOS 26) | `WritingToolsService` with `clarifyQuery` wired to ChatScreen. `ResponseTransformService` with 5 RAG-grounded transforms (Key Facts, Step-by-Step, Cross-Reference, Deep Dive, Flash Cards) | ✅ AI Hub toolbar live (v2.0)            | ✅ Shipped |

#### ⬜ Not Yet Leveraged (Phase 2+)

| Framework/API                 | Use Case                                  | Priority | Notes                                        |
| ----------------------------- | ----------------------------------------- | -------- | -------------------------------------------- |
| **DataScannerViewController** | Live camera scanning UX (VisionKit)       | High     | More polished than raw AVCaptureSession      |
| **MetricKit**                 | Device performance telemetry              | Medium   | Optimize pipeline for real user hardware     |
| **OSSignposter**              | Instruments-visible profiling             | Low      | Developer debugging, not user-facing         |
| **SoundAnalysis**             | Audio content classification              | Low      | Classify speech/music/ambient in audio files |

#### iOS 26+ New APIs Status

| API                                     | Status         | Location                                                                   |
| --------------------------------------- | -------------- | -------------------------------------------------------------------------- |
| `FoundationModels.LanguageModelSession` | ✅ Production  | `AppleFoundationLLMService`, `HyDEService`, `ContextualCompressionService` |
| `@Generable`, `@Guide`, `@Tool`         | ✅ Production  | 8 agentic tools, RAGAnswer/RAGSearchResults responses                      |
| `LanguageModelFeedback`                 | ✅ Production  | Thumbs up/down feedback via `LLMService` (triggered from ChatScreen)       |
| `prewarm()`                             | ✅ Production  | Session prewarming in `LLMService` (warmUpModel + session init)            |
| `RecognizeDocumentsRequest`             | ✅ Production  | `StructuredDocumentParser`, centralized via `OCRConfiguration`             |
| `SpeechAnalyzer`                        | ✅ Production  | `SpeechAnalyzerService` called from `DocumentProcessor` (audio transcription) |
| `SystemLanguageModel.Guardrails`        | ✅ Production  | `ImagePlaygroundService` uses `.permissiveContentTransformations` guardrails   |
| `SystemLanguageModel.supportsLocale()`  | ✅ Production  | `LLMService` locale gating for language/region support checks                 |
| `SystemLanguageModel.UseCase`           | ⬜ Not Started | Planned for v2.1 — declare specific model use cases for optimized behavior    |

---

### Shipped Features (v2.0)

#### 1. Apple CoreML Vision Models Integration

_Leverage Apple's pre-trained CoreML models for enhanced document understanding_

**Status**: ✅ Infrastructure Complete (Services Ready, Models Optional)
**Target**: v2.0 (March 2026)
**Impact**: 10-20x smarter document ingestion with region detection and classification

**V1 Priority Models** (Immediate Integration):

| Model             | Size    | Use Case                                                                    | Status                            |
| ----------------- | ------- | --------------------------------------------------------------------------- | --------------------------------- |
| **FastViT T8**    | 8.2MB   | Classify document content before processing (photo, form, diagram, receipt) | ✅ Service Ready (Model Optional) |
| **DETR ResNet50** | 43-85MB | Detect tables, figures, charts, text regions in documents                   | ✅ Service Ready (Model Optional) |
| **DeepLabV3**     | 4-8MB   | Lightweight semantic segmentation for simpler documents                     | 📋 Planned                        |

**Implementation Complete**:

- ✅ `CoreMLDocumentClassifier.swift` - FastViT integration with Vision framework fallback
- ✅ `CoreMLRegionDetector.swift` - DETR integration with Vision framework fallback
- ✅ `IntelligentDocumentProcessor.swift` - Orchestrator combining classification + detection + OCR
- ✅ Graceful degradation: Works with or without bundled CoreML models
- ✅ Falls back to Vision framework APIs when models not present

**To Enable Full CoreML Models**:

1. Download from https://developer.apple.com/machine-learning/models/
2. Add `FastViTT8F16.mlmodelc` to Xcode project
3. Add `DETRResnet50SemanticSegmentationF16.mlmodelc` to Xcode project
4. Services automatically detect and use bundled models

**Enhanced Ingestion Pipeline**:

```
CURRENT:
PDF → Vision OCR → Chunker → Embeddings → LLM Query

WITH APPLE COREML MODELS:
PDF → FastViT (classify: photo? diagram? text? form?)
    ↓
    DETR (detect regions: table @ (x,y), figure @ (x,y), text block @ (x,y))
    ↓
    Vision OCR (per region, with semantic context)
    ↓
    Structure-Aware Chunker → Embeddings → HNSW
    ↓
    Query → Hybrid Search → Apple FM
```

**Architecture**:

- **CoreMLDocumentClassifier**: FastViT integration for content-type detection (actor-based)
- **CoreMLRegionDetector**: DETR integration for bounding box extraction (actor-based)
- **IntelligentDocumentProcessor**: Orchestrates classify → detect → extract pipeline
- **Semantic Zone Metadata**: ChunkMetadata includes zone type (table, figure, prose)

**V2 Model Catalog** (Future Integration):

| Model               | Size  | Use Case                                            | Target |
| ------------------- | ----- | --------------------------------------------------- | ------ |
| **BERT-SQuAD**      | 217MB | Extractive QA for simulator testing & older devices | v3.0   |
| **DepthAnythingV2** | 49MB  | 3D document scanning, AR overlay                    | v3.0   |
| **MobileNetV2**     | 12MB  | Classify images within documents                    | v3.0   |
| **YOLOv3 Tiny**     | 17MB  | Real-time camera document detection                 | v3.0   |
| **ResNet-50**       | 51MB  | High-accuracy image classification                  | v3.0   |

**Downloads**: https://developer.apple.com/machine-learning/models/

#### 2. Camera Vision Overlay with Apple Intelligence

_Live camera analysis using iOS 26 Vision framework + FoundationModels_

**Status**: ⏸️ Deferred to v3.0 (Code Complete, UI Disabled)
**Target**: v3.0 (Q2 2026)
**Impact**: Real-time document capture and analysis

> **Note**: Implementation complete but disabled for v1.0 App Store release. Code exists in `/Features/Camera/` folder. UI hooks commented out pending further testing of iOS 26 Vision APIs.

| Feature                 | Vision API                              | Status         |
| ----------------------- | --------------------------------------- | -------------- |
| Document Detection      | `DetectDocumentSegmentationRequest`     | ✅ Implemented |
| Live Text Recognition   | `RecognizeTextRequest` (continuous)     | ✅ Implemented |
| Table Structure Parsing | `RecognizeDocumentsRequest`             | ✅ Implemented |
| Barcode/QR Detection    | `DetectBarcodesRequest`                 | ✅ Implemented |
| Image Description (AI)  | `FoundationModels` image prompt         | ✅ Implemented |
| Subject Isolation       | `GenerateForegroundInstanceMaskRequest` | ✅ Implemented |
| Aesthetic Scoring       | `CalculateImageAestheticsScoresRequest` | ✅ Implemented |

**Architecture** (Ready for v2):

- **CameraVisionOverlayView**: SwiftUI view with AVCaptureSession + Vision pipeline
- **CameraManager**: AVFoundation session management with frame analysis
- **DocumentCaptureView**: Smart capture with auto document detection
- **CaptureToRAGBridge**: One-tap to extract text/tables and ingest into RAG pipeline
- **VisionOCRThrottle**: Device-tier-aware concurrency control with platform detection

**Why Deferred**:

- iOS 26 Vision framework (RecognizeDocumentsRequest) is new/experimental
- Need more real-world testing across device types
- Core RAG pipeline is production-ready; camera can wait for v2

#### 3. Documentation Cache Service

_Automatically save fetched web documentation locally for offline access_

**Status**: 📋 Planning
**Target**: v2.1 (Q2 2026)
**Impact**: No repeated web fetches; persistent knowledge base

**Architecture**:

- **DocumentationCacheService**: Actor-based service for storing fetched web content
- **CachedDocument**: Struct with URL, title, content, fetchDate, hash
- **Docs/cached/** folder in workspace for persistent storage
- **Markdown conversion**: HTML → cleaned Markdown for RAG ingestion
- **De-duplication**: SHA256 hash check before storing duplicates

**Features**:

- [ ] Auto-save on every web fetch (opt-in via Settings)
- [ ] Browse cached documentation in-app
- [ ] Ingest cached docs into RAG containers
- [ ] Search across cached documentation
- [ ] Expiration/freshness policy (30-day default)

#### 3. Enhanced Image Understanding (FoundationModels + Vision)

_Use Apple Intelligence to DESCRIBE image contents, not just classify_

**Status**: 📋 Planning
**Target**: v2.1 (Q2 2026)
**Impact**: Rich semantic understanding of diagrams, charts, photos

**Current Capability** (v1.0):

- ✅ Image classification (diagram, chart, photo, logo, etc.)
- ✅ OCR from images (labels, annotations)
- ✅ Caption detection via spatial proximity
- ✅ Surrounding context extraction
- ✅ OCR retry at 360 DPI for low-quality images

**Planned Enhancements**:

- [ ] **FoundationModels Image Prompting**: Pass image to Apple FM with "Describe this image in detail"
- [ ] **Diagram Understanding**: "This flowchart shows steps: 1. Input → 2. Process → 3. Output"
- [ ] **Chart Data Extraction**: "Bar chart showing Q1=20%, Q2=35%, Q3=25%, Q4=20%"
- [ ] **Photo Scene Description**: "Meeting room with 5 people around a whiteboard"
- [ ] **Embedded Chunk Metadata**: `imageDescription` field in ChunkMetadata for search

---

### 🚀 Shipped: SQLite FTS5 Full-Text Search Engine (v1.1 → v2.0)

_Native SQLite FTS5 integration for 10-100X faster keyword search and pattern counting_

**Status**: ✅ Core Implementation Complete
**Target**: Shipped in v2.0
**Impact**: Critical performance upgrade for large document corpora

#### Architecture

- **SQLiteFullTextService**: Actor-based service replacing file-per-document storage
- **FTS5 Virtual Table**: `CREATE VIRTUAL TABLE documents USING fts5(document_id UNINDEXED, content, tokenize='porter unicode61')`
- **Built-in bm25()**: Native SQLite BM25 ranking (replaces in-memory BM25Scorer)
- **MATCH Queries**: O(log n) inverted index lookups vs O(n) linear scans
- **100% Native**: Uses iOS-bundled SQLite via `import SQLite3` - no external dependencies

#### Expected Performance Improvements

| Operation                 | Current (File-based) | With FTS5        | Improvement    |
| ------------------------- | -------------------- | ---------------- | -------------- |
| Pattern Count (1000 docs) | ~500ms               | ~5ms             | **100X**       |
| Keyword Search            | O(n) scan            | O(log n) index   | **10-100X**    |
| BM25 Scoring              | Rebuild each session | Persisted index  | **10X**        |
| Disk Storage              | ~1.5MB/1000 docs     | ~300KB/1000 docs | **5X smaller** |

#### Features

- [x] **Research & Design**: FTS5 syntax, tokenizers, bm25() function
- [x] **SQLiteFullTextService**: Core actor with FTS5 CRUD operations (1489 lines)
- [x] **Migration**: Auto-store to FTS5 during document ingestion (DocumentProcessor.swift line 257)
- [x] **HybridSearchService Update**: searchWithFTS5() uses native bm25() (line 586)
- [x] **RAGService Wiring**: All 3 hybrid search paths pass containerId for FTS5 auto-selection
- [x] **Deletion Cascade**: Document deletion removes FTS5 entries
- [ ] **Container Isolation**: Per-container FTS5 tables for data isolation
- [ ] **Benchmark Validation**: Measure 10-100X improvements on real corpora

#### Technical Details

- **Tokenizer**: `unicode61` (default, case-insensitive) + `porter` (stemming)
- **Prefix Indexes**: `prefix='2 3'` for efficient wildcard queries
- **highlight() / snippet()**: Native context extraction with match highlighting
- **NEAR Queries**: Proximity search for phrase matching
- **Contentless Option**: Store content separately, index only for max compression

---

### Critical Ingestion Pipeline Fixes (February 2026 - Zero Data Loss)

- **CRITICAL: Document-Level Text Layer Validation (PHASE -1)**
  - Root Cause: Font substitution cipher PDFs (Kia, Hyundai, many Asian-publisher manuals) have text layers where every character is shifted (e.g., Caesar +1: `GPSFXPSE` = "FOREWORD", `'03&803%` = "FOREWORD"). This garbled text passes ALL per-page quality checks: 100% printable ASCII, normal 5.5 avg word length, NLLanguageRecognizer detects "Dutch" at 56% confidence, entropy 4.29 bits/char — all within normal bounds. Result: `PageComplexityAnalyzer` classifies pages as `.trivial`/`.simple`, skips image rendering and OCR entirely. **93% of content silently lost** (only ~7% captured from pages that happened to trigger OCR for table/image reasons).
  - Detection: PHASE -1 runs ONCE per document (~200-500ms): renders 1 sample page, OCRs it with Vision, compares OCR words to PDFKit words via Jaccard similarity. Threshold < 0.15 = garbled text layer detected.
  - Fix: When garbled flag is set: (1) ALL pages force image rendering regardless of complexity strategy, (2) `textQualityOK` forced false so PDFKit text is never trusted, (3) dynamic vocabulary mining skips garbled text layer. Every page routes through Vision OCR.
  - Impact: 542-page Kia Sportage manual goes from ~7% to ~100% content capture. Applies to ANY font-encoded PDF automatically.
  - Files: `DocumentProcessor.swift` — `extractTextFromPDFWithPages()` PHASE -1 block (lines ~1114-1213), per-page loop modifications (image rendering guard, textQualityOK override, vocab skip).

- **CRITICAL: Raw String Regex Silent Failure**
  - Root Cause: In Swift raw strings (`#"..."#`), `\u{HHHH}` is **literal text**, NOT a Unicode escape. ICU regex (used by `NSRegularExpression`) requires `\x{HHHH}` with braces or `\uHHHH` without braces. All 5 affected regex patterns in `OCRConfiguration.normalizeExtractedText()` silently failed — `replacingOccurrences` swallowed the regex error and returned text **unchanged**.
  - Impact: CJK bullet artifacts (僅, 一, etc.) leaked through to chunks and FTS5 storage. En-dash/em-dash normalization between alphanumeric characters was a no-op. CJK numeral-as-dash replacement never triggered.
  - Fix: Changed all `\u{HHHH}` → `\x{HHHH}` in 5 regex patterns (OCRConfiguration.swift lines ~474-599). Added no-space CJK bullet variant handler (`僅How` → `- How`).
  - Lesson: **NEVER use `\u{HHHH}` in Swift raw strings for regex.** Use `\x{HHHH}` (ICU) or interpolate the literal character via `\u{HHHH}` outside the raw string.

- **Garbled Text Layer Detection for Image Extraction**
  - Root Cause: `extractImagesFromPDFPage()` used `page.string` emptiness as a proxy for "page is visual content." Font-encoded PDFs (Kia, Hyundai, many Asian-publisher manuals) have garbled text on EVERY page (e.g., `'03&803%` = "FOREWORD"), so the function thought every page had usable text, **skipping image extraction for ALL pages with diagrams and figures**.
  - Fix: Now uses `isTextQualityAcceptable(rawPageText)` quality gate. Garbled text layers fail the quality check → page is treated as visual content → full-page image is rendered and analyzed by `ImageUnderstandingService`.
  - Impact: Figures, diagrams, warning icons, dashboard layouts, and technical drawings in font-encoded PDFs are now captured and described.

- **Dynamic Image Text Budget**
  - Changed from hardcoded `maxImageTextPerDoc = 3000` to `min(30000, max(3000, extractedImages.count * 500))` — scales with document visual complexity for large manuals.

### Recent Improvements (January 26, 2026 - Mac Platform Stability)

- **Mac Metal Compatibility Fix**: Fixed Vision framework crash on Mac (via "Designed for iPad")
  - Root cause: Apple's Vision framework internally calls `synchronizeResource:` on shared memory buffers
  - Apple Silicon uses `MTLResourceStorageModeShared` (unified memory) - sync is invalid
  - Solution 1: Disabled GPU validation in Xcode scheme (debug-only issue)
  - Solution 2: VisionOCRThrottle detects `ProcessInfo.isiOSAppOnMac` and skips GPU sync
  - Solution 3: Conservative Mac concurrency (3 Vision ops, 10ms cooldown vs 5-6 on iOS)
- **Device-Tier-Aware Vision Concurrency**: VisionOCRThrottle now adapts to specific hardware
  - A18 Pro: 5 concurrent ops, 5ms cooldown
  - A19 Pro: 6 concurrent ops, 3ms cooldown
  - M-series (iPad Pro): 6 concurrent ops, 3ms cooldown
  - Mac Compatible: 3 concurrent ops, 10ms cooldown (conservative for macOS Metal)
- **DeviceCapabilityService Mac Detection**: `isMac` property detects both native Mac and iPad apps on Mac
  - All concurrency values now Mac-aware with conservative defaults
  - Prevents Metal command buffer scheduling issues on macOS
- **Swift 6 Warning Cleanup**: Removed unnecessary `nonisolated(unsafe)` from Sendable types
  - VisionOCRThrottle.swift, StructuredDocumentParser.swift cleaned up

### Previous Improvements (January 24, 2026 - Self-RAG 2.0 & Enhanced OCR)

- **Self-RAG 2.0 Enrichment Prompting**: Research-validated multi-session prompting (Chain-of-Verification, RR-MP 2025)
  - Changed from VERIFICATION to ENHANCEMENT across sessions
  - Session 2+ now ADDS details instead of second-guessing correct answers
  - "Technical specifications count as valid answers" - prevents hyper-skeptical rejection
  - Fixes Deep Think mode giving wrong/no answers when Standard mode works perfectly
- **Enhanced OCR Quality (360 DPI)**: 5x scale factor for PDF rendering (was 3x/216 DPI)
  - Low-res image upscaling before OCR (1.5x for images under 1000px)
  - Contrast enhancement preprocessing for better text recognition
  - Lower minimumTextHeight threshold to capture small text
- **Native Office Document Extraction**: Full support for .docx, .xlsx, .pptx without external dependencies
  - ZIP-based extraction using Apple's Compression framework (deflate decompression)
  - XML parsing for Word document.xml, Excel sharedStrings.xml + sheet.xml, PowerPoint slide\*.xml
  - Handles nested archives and multi-sheet workbooks
- **Multi-Session Prompt Grounding**: "ORIGINAL QUESTION:" prefix prevents answer drift across sessions
- **Repetition Confidence Fix**: Repetition no longer artificially boosts confidence (may indicate error, not certainty)

### Previous Improvements (January 2026 - ZERO Data Loss Architecture)

- **Full Text Storage Service**: Stores complete original document text for exact queries
  - `FullTextStorageService.swift` - Actor-based persistent storage
  - Enables "count word 'X' in all documents" queries without chunking loss
  - Pattern counting across entire corpus with `countPatternInCorpus()`
  - Disk-persisted with memory cache for fast access
  - ⚠️ **Superseded by SQLiteFullTextService in v1.1.0**
- **Token Truncation Fix**: Critical fix for 70%+ content loss during embedding
  - Root cause: NLTokenizer (linguistic words) ≠ BertTokenizer (embedding tokens)
  - Example: `VHA21\VHAPALGarciG1` = 1 NL word but 10+ BertTokenizer tokens
  - Solution: Added `countTokens()` using actual BertTokenizer in CoreMLSentenceEmbeddingProvider
  - Token validation in RAGService with binary search truncation before embedding
- **CSV Row Limit Removed**: Was 1000 rows (silent data loss), now unlimited
- **Chunk Limit Increased**: 5000 → 50000 (supports ~65,000 pages)
- **New Agentic Tools**: `countPatternInCorpus()` and `searchExactPattern()` for LLM
- **Multi-Chain Maximum Mode**: Parallel reasoning chains across document clusters - breaks the 4096 token ceiling
  - Clusters documents by topic similarity
  - Runs parallel chains per cluster (3-way parallelism)
  - Synthesizes all cluster insights into comprehensive answer
  - Full reasoning trace preserved (40+ session insights visible in UI)
  - For 17 documents: 5 clusters × 8 sessions × 4096 = 160K+ effective tokens
- **RAPTOR-lite Document Summaries**: Auto-generates ~150-word document summaries at ingestion via Apple FM, stored as L1 chunks for efficient overview queries
- **Query Router Service**: Classifies queries as overview/detail/cross-topic and routes to optimal retrieval strategy (summaries vs chunks)
- **Abstraction Levels**: ChunkMetadata now includes `abstractionLevel` field (L0=detail, L1=docSummary, L2=cluster, L3=library)
- **Entity Extraction (Connective Tissue)**: NLTagger-based extraction of named entities (persons, organizations, places) and technical terms (PascalCase identifiers) during chunking
- **Global Entity Index**: Cross-document entity correlation via `EntityIndexService` with `Dict<Entity, Set<ChunkID>>` lookup
- **Recursive Research Loop**: LLM-driven autonomous search with `[ANSWER]`/`[SEARCH: query]` token protocol for multi-hop reasoning
- **mmap Zero-Copy Vector Storage**: Memory-mapped embedding files with `cblas_sgemv` BLAS-accelerated search (~2KB resident memory vs ~20MB for in-memory)
- **Spatial Text Ordering**: OCR now sorts text by reading order using bounding boxes (top→bottom, left→right)
- **Multi-Column Detection**: Automatically detects and processes multi-column layouts correctly
- **Image Classification**: ClassifyImageRequest integration tags embedded images (iOS 18+)
- **Caption-Image Association**: Links captions to nearby images via spatial proximity analysis
- **Image Descriptions**: Generates searchable text from image classifications + captions
- **VisualContentMetadata**: New metadata struct tracks visual elements per document
- **ImageUnderstandingService**: New service for comprehensive image analysis
- **Accelerate-Powered Vector Math**: All cosine similarity computations use vDSP_dotpr and cblas_snrm2 for Neural Engine acceleration
- **Pre-Computed Embedding Norms**: O(1) normalization during search via cached L2 norms
- **Device-Adaptive Batch Sizes**: Batch thresholds tuned per device tier (A17→A18→A19→M-series)
- **Semantic Boundary Chunking**: Sentence embedding similarity detection for topic-aware chunks
- **Cross-Container Search**: Unified search across all knowledge containers with RRF fusion
- **3D Embedding Visualization Overhaul**: Intuitive spatial metaphors, ground plane grid, semantic axis labels, cluster badges, and gesture hints
- **10x RAG Pipeline Optimization (v1.0.1)**: Expert-level end-to-end audit with 20+ fixes across token budget, hybrid search, extractive QA, SpecificationDetector, verification gates, query expansion, and system prompts. Standard mode now achieves 78%+ calibrated confidence on specification lookups with 94% verification gate pass rate.
- **Research-Grade Retrieval Audit (v1.0.1)**: 10-area audit (B+/A-) with 4 critical fixes: FTS5 AND-first queries (was OR-only), chunk-level BM25 scoring in FTS5 path (was document-level), iterative retrieval auto-enable for multi-hop intents, and atomic table preservation in SemanticChunker. Deep Think/Maximum parity ensured via `originalQuery` passthrough, corpus vocabulary build/cache, and ExtractiveQA pre-check in AgenticOrchestrator.
- **Adaptive Document Intelligence Engine (v1.0.1)**: Complete overhaul of OCR ingestion pipeline for universal document handling. `OCRConfiguration` centralizes all Vision OCR configuration (eliminated 3 duplicate config blocks). `AdaptivePreprocessor` selects from 5 CIFilter strategies (minimal→maximum) based on page quality, scan type, and degradation level. `ConfidenceVerifier` uses `topCandidates(5)` with per-character confidence analysis — numeric data requires 90% confidence (vs 85% for text) to catch OCR errors in table values. Dynamic vocabulary extracted from PDFKit text layer feeds Vision `customWords`. `isTextQualityAcceptable` rewritten from English-centric (vowel ratios, common English words) to language-agnostic (Unicode categories, NLLanguageRecognizer, entropy). Per-document state properly reset between ingestions. Camera OCR pipeline upgraded to centralized config.
- **Rich Markdown Response Rendering (v1.2.0)**: Complete rewrite of `MarkdownRenderer.swift` from inline-only to full block-level parser. `normalizeInlineMarkdown()` preprocessor splits Apple FM single-line output into proper markdown blocks using 6 regex patterns (headers, bold bullets, plain bullets, numbered items, bold numbered items, block quotes). `MarkdownBlockView` renders headings (h1-h6), bullet lists, numbered lists, code fences, block quotes, horizontal rules. All 4 synthesis prompts in `AgenticOrchestrator` and standard pipeline prompts in `RAGService` updated with formatting instructions. 7 response-cleaning functions audited — `cleanupResponseText()` and `cleanupFinalAnswer()` rewritten to preserve markdown. `compactDegenerateResponse()` joining changed from space to paragraph breaks.
- **MMR Crash Fix (v1.2.0)**: Fixed `RAGEngine.applyMMR()` array index out of bounds crash. `GPUComputeService.mmrDiversityMatrix()` returned `[[]]` for dimension-0 embeddings — outer array with empty inner array. Fixed with matrix validation + bounds checks in RAGEngine, corrected edge case returns in GPUComputeService.
- **Motherboard HUD (v1.1.0)**: Real-time Apple Silicon X-ray overlay on the chat screen. `MotherboardHUDView` (622 lines) renders SoC, NAND, DRAM, modem, PMIC, WiFi/BT, and Taptic Engine at Vision AI-verified teardown positions for iPhone 15 Pro through iPhone 17 Pro series. `HardwareTelemetryState` (1,014 lines) provides live CPU/GPU/Neural Engine usage, memory pressure, thermal state, and battery telemetry. Ultra-subtle ghost outlines pulse with real activity. User toggle in Settings.
- **Universal Retrieval (v1.1.0)**: 8 research-grade fixes for near-universal needle-in-haystack accuracy: (1) BM25 lexical always-on in hybrid search, (2) proportional RRF hit-rate weighting, (3) HyDE 70/30 embedding blend, (4) year/integer exemption in Verification Gate C, (5) sentence-scored fallback in contextual compression, (6) rare corpus terms in query expansion, (7) corpus-learned dynamic synonyms from co-occurrence data, (8) adaptive cross-encoder candidate pool scaling `min(count, max(100, topK×5))`.

---

## 1. Completed Features (The Foundation)

### Core RAG Pipeline

- [x] **DocumentProcessor**: Multi-format parsing (PDF, TXT, MD, RTF, CSV, Office docs)
- [x] **SemanticChunker**: Paragraph-aware chunking with content-adaptive sizing
- [x] **Content-Adaptive Chunking**: Different chunk sizes for PDFs (150w), code (200w), narrative (350w)
- [x] **EmbeddingService**: 512-dim vectors via NLEmbedding
- [x] **NLContextualEmbeddingProvider**: BERT-like contextual embeddings (iOS 17+) for 15-25% accuracy boost
- [x] **VectorDatabase**: Protocol with 3 implementations (InMemory, Persistent, Vectura HNSW)
- [x] **VectorStoreRouter**: Per-container database routing
- [x] **HybridSearchService**: BM25 + Vector Search fusion with RRF
- [x] **RAGEngine (Actor)**: Background MMR diversification, RRF fusion, BM25 scoring, Cross-Encoder re-ranking

### Advanced Retrieval (Jan 2026)

- [x] **Query Intent Classification**: Classifies queries as keyword/conceptual/balanced
- [x] **Per-Query Weight Tuning**: Dynamic vector/keyword weights based on query intent
- [x] **Content-Type Auto-Tuning**: Auto-select RetrievalConfig based on document types
- [x] **Corpus-Aware Query Expansion**: Expands queries using actual document vocabulary with garbage filtering
- [x] **Lost-in-Middle Mitigation**: Reorders context chunks so best are at start AND end (Liu et al. 2023)
- [x] **Cross-Encoder Re-ranking**: BERT-based reranker with heuristic fallback
- [x] **Hierarchical Context Windows**: Embed precise chunks but return expanded parent context to the LLM

### LLM Integrations

- [x] **AppleFoundationLLMService**: iOS 26 Foundation Models with PCC fallback
- [x] **Agentic Tool Calling**: @Generable + Tool protocol for SearchDocumentsTool, ListDocumentsTool, GetDocumentSummaryTool
- [x] **@Generable Structured Responses**: RAGAnswer, RAGSearchResults, RAGDocumentSummary types
- [x] **OnDeviceAnalysisService**: Extractive QA fallback (always available)
- [x] **Cloud LLM Removal (Dec 2025)**: Removed OpenAI/GPT-5 direct API integration
      _Note_: OpenAIResponsesAPIService.swift remains as `#if false` dead code for reference only.
- [x] **Local Model Removal (Dec 2025)**: Removed GGUF/CoreML/MLX downloadable models
      _Note_: App now uses Apple Intelligence + On-Device Analysis only. Simplifies maintenance and reduces binary size.
- [x] **Apple FM API Audit (Dec 2025)**: Full FoundationModels framework compliance
  - `prewarm(promptPrefix:)` for latency optimization
  - `SamplingMode.random(top:)` / `.random(probabilityThreshold:)` for topK/topP
  - Exhaustive `GenerationError` handling (9 cases with user-friendly messages)
  - `Transcript` access for debugging/replay
  - `LanguageModelFeedback` integration (thumbs up/down in chat UI)
  - Context window corrected to 4,096 tokens per TN3193
  - Tool `@Guide` with `.range()` and `.maximumCount()` constraints

### Agentic Tooling

- [x] **8 @Tool Functions**: Full iOS 26 FoundationModels.Tool protocol integration
  - `SearchDocumentsTool`: Semantic search with topK/minSimilarity params
  - `ListDocumentsTool`: List all documents in library
  - `GetDocumentSummaryTool`: Document metadata and content summary
  - `CountPatternTool`: Exact pattern count across ALL documents (FTS5)
  - `SearchExactPatternTool`: Exact text search with context snippets
  - `GetCorpusStatsTool`: Library-wide statistics
  - `FindRelatedDocumentsTool`: Semantic document discovery
  - `CompareDocumentsTool`: Cross-document topic comparison
- [x] **RAGAppIntents**: Siri/Shortcuts integration
- [x] **Tool Call Counter**: Usage tracking and limits
- [x] **countPatternInCorpus Tool**: Count exact word/pattern occurrences across ALL documents
      _Location_: [RAGService.swift](OpenIntelligence/Services/RAG/RAGService.swift) extension RAGToolHandler
      _Uses_: FullTextStorageService for complete original text (not chunked)
- [x] **searchExactPattern Tool**: Find exact text patterns with context snippets
      _Benefit_: Enables "how many times is 'X' mentioned" queries with ZERO data loss

### Advanced Agentic RAG (Jan 2026)

_Multi-session reasoning that transcends the 4,096 token limit_

- [x] **AgenticOrchestrator**: Multi-step reasoning pipeline (Planning→Searching→Analyzing→Synthesizing→Refining)
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Status_: Fully implemented with hardware-aware configuration
- [x] **GraphRAG-Lite Expansion**: 2-hop entity expansion (retrieve → extract entities → retrieve again)
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
- [x] **Recursive Research Loop**: LLM-driven autonomous search with `[ANSWER]`/`[SEARCH: query]` tokens
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Method_: `executeRecursiveResearch()` - 7-iteration autonomous research with accumulating context
      _Protocol_: LLM outputs `[SEARCH: specific query]` to retrieve more, `[ANSWER]` when confident
      _Benefit_: Deep multi-hop reasoning without pre-defined decomposition; LLM decides when to stop
- [x] **Entity Extraction (Connective Tissue)**: NLTagger-based NER during chunking
      _Location_: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
      _Method_: `extractEntities()` - extracts persons, organizations, places, PascalCase technical terms
      _Output_: `ChunkMetadata.entities` field populated with up to 15 entities per chunk
- [x] **Global Entity Index**: Cross-document entity correlation for GraphRAG
      _Location_: [EntityIndexService.swift](OpenIntelligence/Services/EntityIndexService.swift)
      _Structure_: `Dict<String, Set<UUID>>` mapping normalized entity names → chunk IDs
      _Features_: O(1) lookup, persistence to JSON, reverse index for efficient removal
      _Methods_: `chunksForEntity()`, `sharedEntities()`, `topEntities()`
- [x] **DeviceCapabilityService**: Hardware tier detection (A17→A18→A19→M-series)
      _Location_: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
      _Status_: Maps device → max sessions → total tokens (16K-48K depending on chip)
- [x] **HyDE (Hypothetical Document Embeddings)**: Generate hypothetical answer, embed for better retrieval
      _Paper_: Gao et al. 2022 - "Precise Zero-Shot Dense Retrieval without Relevance Labels"
      _Location_: [HyDEService.swift](OpenIntelligence/Services/HyDEService.swift)
      _Benefit_: 15-25% recall improvement on factual queries
- [x] **Contextual Compression**: LLM-filter irrelevant sentences from chunks before generation
      _Location_: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
      _Benefit_: 40-60% token savings, improved answer quality
- [x] **Answer Grounding Verification**: Detect hallucinations by checking answer vs. context
      _Location_: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
      _Status_: `verifyAnswerGrounding()` returns grounded/partial/ungrounded/notAnswerable
- [x] **Query Task Management**: Cancel-and-replace pattern for back-to-back queries
      _Location_: [ChatScreen.swift](OpenIntelligence/Views/ChatV2/ChatScreen.swift)
      _Status_: `currentQueryTask` tracking with explicit cancellation at 6 pipeline stages
- [x] **RAGQualityMode.agentic**: "Deep Think" mode exposed in quality picker
      _Status_: Always visible in chat header (not hidden behind developer tuning)
- [x] **Parent Document Retrieval**: Expand matched chunks with sibling context from same section/page
      _Location_: [ParentDocumentService.swift](OpenIntelligence/Services/ParentDocumentService.swift)
      _Benefit_: Preserves document flow, prevents answer gaps from chunk boundaries

### Hardware-Aware Optimization (Jan 2026)

_Comprehensive device-specific tuning for iPhones and iPads_

- [x] **AdaptivePipelineOptimizer**: Runtime pipeline optimization based on thermal/battery/memory state
      _Location_: [AdaptivePipelineOptimizer.swift](OpenIntelligence/Services/AdaptivePipelineOptimizer.swift)
      _Status_: Auto-adjusts HyDE, compression, retrieval limits based on device pressure
- [x] **DeviceFormFactor Detection**: iPhone, iPadMini, iPadAir, iPadPro identification
      _Location_: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
      _Status_: Maps iPad model numbers to form factors with correct chip detection
- [x] **PipelineOptimizationLevel**: Four levels (full/balanced/efficient/minimal) based on device state
      _Benefit_: Prevents thermal throttling, extends battery life during extended sessions
- [x] **QueryComplexity Estimation**: Analyzes query tokens, operators, length to predict load
      _Benefit_: Simple queries skip expensive features, complex queries get full pipeline
- [x] **Thermal Cooldown**: Pauses between heavy operations when device is critical
      _Benefit_: Reduces fan noise on iPads, prevents thermal shutdowns on sustained use
- [x] **Memory Pressure Monitoring**: Real-time available memory tracking via `os_proc_available_memory()`
      _Benefit_: Gracefully degrades features before OOM kills occur
- [x] **SystemStateMonitor**: Centralized real-time device state monitoring service
      _Location_: [SystemStateMonitor.swift](OpenIntelligence/Services/SystemStateMonitor.swift)
      _Status_: Captures thermal, battery, memory, CPU, Low Power Mode with 2-second refresh
      _Features_: NotificationCenter observers for instant state changes; SystemStateSnapshot struct
- [x] **Live System Monitor UI**: Exposed device metrics in UnifiedMetricsBar and SettingsView
      _Benefit_: Full transparency into device state and pipeline optimization decisions

### Privacy & Security

- [x] **Cloud Consent System**: User consent before any cloud transmission
- [x] **CloudTransmission Records**: Full transparency logging
- [x] **Private Cloud Compute (PCC)**: Cryptographic zero-retention
- [x] **Execution Location Badges**: 📱 On-Device / ☁️ Cloud / 🔑 API Key
- [x] **Privacy Manifest**: `PrivacyInfo.xcprivacy` with required-reason API declarations
- [x] **User Report/Hide Controls**: In-chat Hide/Unhide + Report actions for assistant messages

### UI Components

- [x] **ChatView (V2)**: Streaming messages, context viewer, performance metrics
- [x] **DocumentLibraryView**: Import, manage, swipe-to-delete
- [x] **SettingsView**: LLM selection, API keys, retrieval config
- [x] **ModelManagerView**: Device capabilities, model status
- [x] **TelemetryView**: Real-time pipeline visualization
- [x] **DiagnosticsView**: Vector space analysis, embedding quality
- [x] **Embedding3DView Overhaul (Jan 2026)**: Complete visualization redesign
      _Location_: [Embedding3DView.swift](OpenIntelligence/Views/Telemetry/Embedding3DView.swift)
      _Features_: Ground plane grid, intuitive semantic axes ("Similar →", "← Different", "Related ↑", "Depth"),
      glowing point spheres, pill-shaped cluster badges, gesture hint overlays for both compact and fullscreen modes

### Monetization

- [x] **StoreKit 2 Integration**: Subscriptions and lifetime purchase
- [x] **EntitlementStore**: Paywall gating for premium features
- [x] **Reviewer Mode**: App Review bypass (DEBUG-only persistence)

### Infrastructure

- [x] **Logging System**: Log levels (.debug → .critical) with categories
- [x] **SettingsStore**: Centralized preferences with debouncing
- [x] **KnowledgeContainer**: Multi-container document isolation
- [x] **ContainerService**: CRUD for knowledge containers

### Apple FM APIs Now Integrated

_These FoundationModels framework features have been fully integrated:_

- [x] **Content Tagging Model**: `SystemLanguageModel(useCase: .contentTagging)` for auto-labeling documents
      _Implemented_: ContentTaggingService auto-generates topic/action/emotion/object tags during document ingestion; displayed in DocumentCard and DocumentDetailsView with pill UI
- [x] **Transcript Rehydration**: `LanguageModelSession(transcript:)` for session persistence
      _Implemented_: TranscriptPersistenceService saves/restores transcripts on app background/foreground and container switch; enables conversation continuity across app launches
- [x] **isResponding Property**: Real-time generation state tracking
      _Implemented_: `session.isResponding` exposed via RAGService.isLLMResponding; UnifiedMetricsBar shows pulsing indicator during active generation

---

## 2. Technical Debt (The Cracks)

### High Priority

- [x] **Page Number Tracking**: DocumentProcessor now builds page→text mappings
      _Location_: [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift#L340)
      _Status_: Implemented - PDF extraction tracks page ranges, passed to SemanticChunker for accurate citations

- [x] **CoreML Sentence Embeddings**: Production-ready with all-MiniLM-L6-v2
      _Location_: [CoreMLSentenceEmbeddingProvider.swift](OpenIntelligence/Services/Embeddings/CoreMLSentenceEmbeddingProvider.swift)
      _Status_: Fully integrated - 384-dim sentence embeddings via Neural Engine, outperforms legacy NLEmbedding word-level averaging

### Medium Priority

- [ ] **RAGService Size**: 4250 LOC monolith needs decomposition
      _Impact_: Difficult to test and maintain

- [ ] **Error Recovery**: Some LLM failures don't surface user-friendly messages
      _Impact_: Users see generic errors

- [x] **Test Coverage**: Previously expanded, subsequently removed — mock-based tests could not exercise real Apple framework behavior on simulator
      _Status_: Quality validated through on-device testing

### Low Priority

- [x] **MLX macOS-Only**: Removed with local model cleanup (Dec 2025)
      _Status_: No longer applicable - local models removed

- [x] **Vendor LocalLLMClient**: Removed from project (Dec 2025)
      _Status_: Package removed entirely - no longer needed

- [ ] **Dead Code Cleanup**: Remove `#if false` wrapped files
      _Files_: `LocalOpenAIServerLLMService.swift`
      _Impact_: Reduces cognitive load and project clutter

---

## 2.5. Retrieval Quality Improvements (Future)

_Known limitations in current implementation with paths to improvement._

> **Current Rating**: 75-85% of enterprise RAG quality. See [ARCHITECTURE.md → Retrieval Quality Assessment](ARCHITECTURE.md) for full analysis.

### What's Solid ✅

| Component             | Status              | Notes                                                               |
| --------------------- | ------------------- | ------------------------------------------------------------------- |
| **BM25 Scoring**      | ✅ Correct          | k1=1.5, b=0.75, proper IDF. Textbook implementation.                |
| **RRF Fusion**        | ✅ Correct          | k=60 per Cormack et al. 2009. Proper reciprocal rank summation.     |
| **Cross-Encoder**     | ✅ Production-grade | `ms-marco-TinyBERT-L-2-v2`, proper token type IDs, softmax scoring. |
| **MMR**               | ✅ Good             | GPU-accelerated pairwise similarities, λ-weighted tradeoff.         |
| **Lost-in-Middle**    | ✅ Implemented      | Liu et al. 2023 reordering in `RAGEngine`.                          |
| **vDSP Acceleration** | ✅ Hardware-native  | Neural Engine/AMX via `vDSP_dotpr`, `vDSP.sumOfSquares`.            |

### Known Limitations ⚠️

| Issue                               | Current Behavior                                              | Impact                                                             | Fix                                              |
| ----------------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------ |
| ~~**Hybrid not truly parallel**~~   | ~~Vector search runs first, BM25 re-scores same candidates~~  | ✅ **FIXED v1.2** — true parallel via `async let`                   | ✅ Implemented                                    |
| ~~**BM25 IDF is local**~~           | ~~`snapshot(from: candidates)` computes IDF from ~50 chunks~~ | ✅ **FIXED v1.2** — native SQLite `bm25()` corpus-wide              | ✅ Implemented                                    |
| ~~**FTS5 not used at query time**~~ | ~~In-memory `BM25Scorer` instead of SQLite `bm25()`~~         | ✅ **FIXED v1.2** — `searchChunks()` uses `bm25()` (10/5/1 weights) | ✅ Implemented                                    |
| **Cross-encoder cap at 50**         | `prefix(50)` before reranking                                 | Chunk #51 never seen                                               | Two-stage: fast filter → 100, cross-encoder → 50 |

### Improvement Priorities

- [x] **True Hybrid Search**: Parallel vector + FTS5 searches, merge distinct result sets ✅ _Implemented v1.2_
      _Impact_: Catches BM25-only matches currently missed
      _Location_: `HybridSearchService.searchWithFTS5()`
      _Effort_: Medium

- [x] **Global IDF Persistence**: Compute document frequencies at ingestion, persist in SQLite ✅ _Implemented v1.2 via native FTS5 bm25()_
      _Impact_: More accurate term weighting for rare/common words
      _Location_: `SQLiteFullTextService.searchChunks()`
      _Effort_: Medium

- [x] **Native FTS5 Scoring**: Use SQLite's `bm25()` function instead of in-memory scorer ✅ _Implemented v1.2_
      _Impact_: Leverages SQLite's optimized implementation
      _Location_: `HybridSearchService.searchWithFTS5()`
      _Effort_: Low

- [ ] **Expanded Rerank Pool**: Filter to 100 candidates, then cross-encoder to 50
      _Impact_: Reduces risk of missing relevant chunk just outside top 50
      _Location_: `RAGEngine.rerankCandidates()`
      _Effort_: Low

---

## 3. Project: Silicon-Native Intelligence (Q1 2026)

_Refactoring OpenIntelligence to align with Apple's "Native Intelligence" Benchmark._

### Phase 1: Core ML Embedding Engine (Critical)

- [x] **Model Conversion Script**: Python utility to convert `sentence-transformers/all-MiniLM-L6-v2` to Core ML
- [ ] **Tokenizer Parity**: Validate Swift `WordPieceTokenizer` against Python `transformers` output
- [x] **CoreML Provisioning**: Fixed to load `.mlmodelc` (compiled model) instead of `.mlpackage` source
- [ ] **NLEmbedding Deprecation**: Remove reliance on `NLEmbedding` / `AppleFMEmbeddingProvider`

### Phase 2: Vector Math Layer (High) ✅ COMPLETE

_Silicon-native vector operations using Apple Accelerate framework_

- [x] **BNNS Vector Store**: Implemented `BNNSVectorDatabase` using `Accelerate` / `vDSP`
      _Location_: [BNNSVectorDatabase.swift](OpenIntelligence/Services/VectorDatabase/BNNSVectorDatabase.swift)
      _Features_: vDSP_dotpr for dot products, cblas_snrm2 for L2 norms, vDSP_mmul for batch matrix ops
- [x] **Flat File Storage**: Contiguous float arrays for max Neural Engine throughput
      _Status_: flatEmbeddings array stores all vectors sequentially for vDSP_mmul compatibility
- [x] **Optimized Dot Product**: Hardware-accelerated via vDSP*dotpr (Neural Engine preferred)
      \_Status*: Both RAGEngine and HybridSearchService use Accelerate-powered similarity
- [x] **Pre-Computed Norms**: O(1) cosine similarity via cached L2 norms
      _Status_: embeddingNorms array populated at insert time, avoids re-computing sqrt(sum(x^2))
- [x] **Device-Adaptive Batch Thresholds**: DeviceCapabilityService optimizes batch sizes per chip
      _Location_: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
      _Features_: vectorBatchSize, embeddingBatchSize, batchMatrixMultiplyThreshold tuned per device tier
- [x] **mmap Zero-Copy Vector Storage**: Memory-mapped embedding files for minimal RAM usage
      _Location_: [VectorDatabase.swift](OpenIntelligence/Services/VectorDatabase.swift) `MmapVectorDatabase`
      _Features_: `Data(contentsOf:, options: .alwaysMapped)` for zero-copy access, cblas*sgemv search
      \_Performance*: ~2KB resident memory vs ~20MB for in-memory (10K chunks @ 512-dim)
      _Architecture_: Separate embeddings.bin (mmap'd) + metadata.json + norms.bin files

### Phase 3: Cross-Encoder Re-Ranking (High) ✅ COMPLETE

_Neural relevance scoring using BERT-based cross-encoder_

- [x] **Re-Ranker Model**: `cross-encoder/ms-marco-TinyBERT-L-2-v2` converted to Core ML
      _Location_: [ReRankerModel.mlpackage](OpenIntelligence/ReRankerModel.mlpackage/)
      _Status_: Model bundled with app, vocab file in `reranker_vocab.json`
- [x] **Re-Ranking Service**: Batch inference in `RAGEngine` (Query + Chunk pairs)
      _Location_: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift#L742)
      _Method_: `rerankWithCrossEncoder()` - tokenizes query-doc pairs, runs CoreML inference, extracts softmax scores
- [x] **BertTokenizer Integration**: WordPiece tokenization via swift-transformers
      _Location_: [swift-transformers/](OpenIntelligence/swift-transformers/)
      _Status_: Full tokenizer with special tokens ([CLS], [SEP], [PAD]), attention masks, token type IDs
- [x] **Heuristic Fallback**: `computeMetadataBoost` retained as fallback when model unavailable

### Phase 4: True Semantic Chunking (Medium) ✅ COMPLETE

_Embedding-based topic boundary detection (Late Chunking approach)_

- [x] **Semantic Splitter**: SemanticChunker now detects topic boundaries via sentence embeddings
      _Location_: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
      _Method_: `detectEmbeddingBoundaries()` computes pairwise cosine similarity between sentences
- [x] **Thresholding**: Auto-detect topic boundaries where similarity drops below 0.65
      _Status_: `embeddingSimilarityThreshold` configurable; defaults to 0.65 for balanced segmentation
- [x] **Async Chunking API**: New `chunkTextAsync()` method combines linguistic + embedding boundaries
      _Benefit_: Chunks align with genuine topic shifts rather than arbitrary word counts
- [x] **Accelerate Integration**: Cosine similarity uses vDSP_dotpr + cblas_snrm2 for hardware acceleration

### Phase 5: Cross-Container Search (Medium) ✅ COMPLETE

_Unified search across all knowledge containers_

- [x] **VectorStoreRouter.searchAll()**: Parallel search with Reciprocal Rank Fusion
      _Location_: [VectorStoreRouter.swift](OpenIntelligence/Services/VectorStoreRouter.swift)
      _Algorithm_: TaskGroup parallel queries → per-container ranking → RRF fusion → global top-K
- [x] **Container Attribution**: CrossContainerResult includes container name/ID for citations
- [x] **RAGService Integration**: `searchAllContainers()` and `searchAllContainersRaw()` tools
      _Location_: [RAGService.swift](OpenIntelligence/Services/RAGService.swift)
      _Benefit_: LLM can synthesize knowledge from multiple libraries in one query

---

## 4. Future Trajectory

### Phase 2.0 — Intelligence Layer

- [x] **Query Clarification**: Lightweight pronoun resolution and follow-up handling
      _Location_: [QueryRewriterService.swift](OpenIntelligence/Services/QueryRewriterService.swift)
      _Status_: Implemented - Only intervenes for genuine ambiguity (pronouns, follow-ups)
- [x] **Corpus-Aware Query Expansion**: Expands queries using actual document vocabulary
      _Location_: [QueryEnhancementService.swift](OpenIntelligence/Services/QueryEnhancementService.swift)
      _Status_: Implemented - Builds co-occurrence maps from chunk keywords, filters garbage terms
- [x] **Query Intent Classification**: Detects keyword-heavy vs conceptual queries
      _Location_: [QueryEnhancementService.swift](OpenIntelligence/Services/QueryEnhancementService.swift)
      _Status_: Implemented - `classifyIntent()` with `QueryIntent` enum for dynamic weight tuning
- [x] **Iterative Retrieval**: Multi-pass retrieve → assess → refine → retrieve more
      _Location_: [IterativeRetrievalService.swift](OpenIntelligence/Services/IterativeRetrievalService.swift)
      _Status_: Implemented - Full RAGService integration with configurable passes via settings
- [x] **Intelligence Layer Settings UI**: Toggles for Query Understanding and Multi-Pass Retrieval
      _Location_: [SettingsView.swift](OpenIntelligence/Views/Settings/SettingsView.swift)
      _Status_: Implemented - New Intelligence Layer card with user-facing toggles
- [x] **Context Window Fix (TN3193 Compliance)**: Fixed 65K → 4096 token budget
      _Location_: [RAGService.swift](OpenIntelligence/Services/RAGService.swift)
      _Status_: Implemented - baseWindowTokens=4096, maxContextCharsCap=5000 for Apple FM
- [x] **RAGEngine Singleton**: Prevents ReRanker model loading 4x per query
      _Location_: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift)
      _Status_: Implemented - `RAGEngine.shared` singleton with `isSetupComplete` guard
- [x] **Lost-in-Middle Mitigation**: Context reordering for LLM attention patterns
      _Location_: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift)
      _Status_: Implemented - `applyLostInMiddleReordering()` places best chunks at start AND end
- [x] **Content-Adaptive Chunking**: Document-type-specific chunk sizes
      _Location_: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
      _Status_: Implemented - `ChunkingConfig.recommended(for:)` with PDF/code/narrative presets
- [x] **Multi-Session Chaining**: Agentic RAG chains multiple 4096-token sessions for complex queries
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
- [x] **Multi-Chain Maximum Mode**: Parallel reasoning chains across document clusters
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Status_: Implemented - `executeMultiChainReasoning()` with 5 clusters × 8 sessions × 3 parallel
      _Status_: Implemented - Multi-step planning→searching→analyzing→synthesizing→refining with session cleanup
      _Hardware_: Device-aware config via DeviceCapabilityService (A17→16K, A18→24K, A19→32K, M-series→48K)
- [x] **Query Planning Agent**: Multi-step reasoning over large document sets
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Status_: Implemented - `executePlanningStep()` decomposes queries into 2-4 focused sub-questions, executed in parallel
- [x] **Cross-Container Search**: Unified retrieval across multiple containers
      _Location_: [VectorStoreRouter.swift](OpenIntelligence/Services/VectorStoreRouter.swift)
      _Status_: Implemented - `searchAll()` with parallel queries and RRF fusion; RAGService integration via `searchAllContainers()`
- [x] **Conversation Memory**: Persistent chat context with intelligent summarization
      _Location_: [ConversationMemoryService.swift](OpenIntelligence/Services/ConversationMemoryService.swift)
      _Status_: Fully dynamic implementation with query-adaptive optimizations
      _Dynamic Features_:
  - **Query-Adaptive Token Budget**: Simple queries get 500 chars, follow-ups get 3000 chars
  - **Semantic Relevance Scoring**: Jaccard similarity + entity matching ranks turns by relevance to current query
  - **Importance-Weighted Summarization**: High-information turns preserved longer, low-value turns summarized first
  - **Entity Prioritization**: Entities appearing in current query surfaced first
  - **Recency Boost**: Recent turns scored higher with 1-hour decay curve
    _Performance_: Non-blocking (fire-and-forget), debounced saves (2s), background LLM summarization
    _Settings_: `enableConversationMemory` in SettingsStore (default: true)
    _Settings_: `enableConversationMemory` in SettingsStore (default: true)

### Phase 2.5 — God Mode RAG (Advanced)

_State-of-the-art RAG techniques from 2024-2026 research. These would push the system from 7.5/10 to 10/10._

#### Retrieval Enhancements

- [x] **HyDE (Hypothetical Document Embeddings)**: Generate hypothetical answer, embed that for retrieval
      _Paper_: Gao et al. 2022 - "Precise Zero-Shot Dense Retrieval without Relevance Labels"
      _Benefit_: 15-20% recall improvement for complex queries
      _Location_: [HyDEService.swift](OpenIntelligence/Services/HyDEService.swift)
      _Status_: Implemented - Auto-detects factual queries, generates hypothetical doc, embeds for search
      _Settings_: `enableHyDE` in SettingsStore (default: true)

- [x] **Parent Document Retrieval**: Expand matched chunks with sibling context from same section/page
      _Benefit_: Maintains coherence for multi-paragraph answers
      _Location_: [ParentDocumentService.swift](OpenIntelligence/Services/ParentDocumentService.swift)
      _Status_: Implemented - Expands chunks post-reranking, quality-aware config (default vs thorough)
      _Settings_: `enableParentDocumentRetrieval` in SettingsStore (default: true)
      _Schema_: Added `siblingGroupId` and `siblingCount` to ChunkMetadata

- [x] **Late Chunking (Semantic Boundary Detection)**: Detect topic boundaries via sentence embedding similarity
      _Paper_: "Late Chunking" (2024) - embeddings computed before chunking preserve more context
      _Benefit_: Better embedding quality for chunk boundaries
      _Location_: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
      _Status_: Implemented - `detectEmbeddingBoundaries()` computes pairwise cosine similarity; `chunkTextAsync()` combines with linguistic cues

- [x] **Contextual Compression**: LLM-filter irrelevant sentences from retrieved chunks before generation
      _Benefit_: Maximizes signal-to-noise in context window
      _Location_: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
      _Status_: Implemented - Compresses chunks post-retrieval, drops irrelevant content, logs token savings
      _Settings_: `enableContextualCompression` in SettingsStore (default: true)

#### Advanced Reasoning

- [x] **Self-RAG**: Model decides when to retrieve, what to retrieve, and self-critiques answers
      _Paper_: Asai et al. 2023 - "Self-RAG: Learning to Retrieve, Generate, and Critique"
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Method_: `executeSelfRAG()` - adaptive retrieval + self-critique loop
      _Benefit_: Skips retrieval for simple queries, catches hallucinations via self-critique

- [x] **Speculative RAG**: Generate multiple candidate answers, verify each against documents
      _Location_: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
      _Method_: `executeSpeculativeRAG()` - 3 candidates with temperature variation, grounding scores
      _Benefit_: Catches hallucinations through multi-path verification

- [x] **RAPTOR-lite**: Document-level summaries at ingestion for efficient overview queries
      _Paper_: Sarthi et al. 2024 - "RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval"
      _Location_: [DocumentSummaryService.swift](OpenIntelligence/Services/DocumentSummaryService.swift)
      _Implementation_: Generates ~150-word document summaries via Apple FM at ingestion time
      _Storage_: Summaries stored as L1 chunks with `abstractionLevel = .documentSummary`
      _Benefit_: Overview queries use pre-computed summaries (95% token savings vs Maximum mode)
      _Complexity_: 80% of RAPTOR benefit at 20% complexity (1-level hierarchy only)

- [x] **Query Routing**: Classify queries to route to optimal retrieval strategy
      _Location_: [QueryRouterService.swift](OpenIntelligence/Services/QueryRouterService.swift)
      _Query Types_: Overview (→ L1 summaries), Detail (→ L0 chunks), Cross-topic (→ both levels)
      _Benefit_: Avoids wasting tokens on runtime synthesis for overview queries
      _Complexity_: Pattern-based classification with 70%+ confidence threshold

#### Learning & Adaptation

- [ ] **Active Learning Feedback Loop**: System improves from user corrections and thumbs up/down
      _Benefit_: Retrieval quality improves over time
      _Complexity_: Medium (need feedback storage and retraining pipeline)

- [ ] **Per-Query Learned Fusion Weights**: Train small model to predict optimal vector/BM25 blend
      _Benefit_: Replaces heuristic intent classification with learned weights
      _Complexity_: High (requires training data collection)

### Phase 2.05 — Visual Document Understanding (Q1-Q2 2026)

_Full Vision framework integration for layout-aware document processing_

#### Layout-Aware Text Extraction

- [x] **Spatial Text Ordering**: Use VNRecognizedTextObservation bounding boxes to sort text by reading order
      _Problem_: PDF text extraction can return jumbled text when layout is complex (multi-column, sidebars)
      _Solution_: Sort OCR observations by Y position (top-to-bottom), then X position (left-to-right)
      _Impact_: Fixes copy-paste weirdness where text order doesn't match visual layout
      _Location_: `performOCR()` in [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift)
      _Status_: Implemented - observations sorted by bounding box with 2% line threshold

- [x] **Column Detection**: Detect multi-column layouts via bounding box clustering
      _Benefit_: Process columns independently before merging text
      _API_: VNRecognizedTextObservation.boundingBox + clustering algorithm
      _Location_: `detectColumns()` and `extractTextWithColumnAwareness()` in DocumentProcessor.swift
      _Status_: Implemented - detects significant gaps (>15% page width) as column boundaries

- [x] **Reading Order Reconstruction**: Reconstruct logical reading flow from spatial positions
      _Benefit_: "If you highlight half a page, the text flows correctly"
      _Location_: `extractTextWithColumnAwareness()` in DocumentProcessor.swift
      _Status_: Implemented - processes each column top-to-bottom, then combines

#### Image Understanding (Vision + Intelligence)

- [x] **PDF Image Extraction**: Extract embedded images from PDF pages
      _API_: PDFKit page rendering + CGImage extraction at image positions
      _Benefit_: Access to diagrams, charts, photos in documents
      _Location_: `extractImagesFromPDFPage()` and `extractAllImagesFromPDF()` in DocumentProcessor.swift
      _Status_: Implemented - extracts from annotations and full-page scans

- [x] **Image Classification**: Use ClassifyImageRequest to tag images
      _API_: `ClassifyImageRequest()` → [ClassificationObservation] with identifiers and confidence
      _Benefit_: "This PDF contains: diagrams (0.85), technical*drawings (0.72), charts (0.68)"
      \_Location*: [ImageUnderstandingService.swift](OpenIntelligence/Services/ImageUnderstandingService.swift)
      _Status_: Implemented - iOS 18+ modern API with legacy fallback; ImageContentType enum for high-level categorization

- [x] **Image-to-Text Description**: Generate text descriptions of images via Apple Intelligence
      _API_: Classification-based descriptions (full Foundation Models image input planned for iOS 26+)
      _Benefit_: Diagrams become searchable ("fluid diagram", "wiring schematic")
      _Location_: `generateImageDescription()` in ImageUnderstandingService.swift
      _Status_: Implemented - combines classifications + captions into searchable text

- [x] **Caption-Image Association**: Link captions to adjacent images via spatial proximity
      _Heuristic_: Text within 5% of page height below an image is likely its caption
      _Location_: `findAssociatedCaption()` in ImageUnderstandingService.swift
      _Status_: Implemented - detects "Figure", "Image", "Diagram" prefixes and short nearby text

#### Document Structure Analysis (iOS 18+)

- [ ] **DetectDocumentSegmentationRequest**: Detect document boundaries and regions
      _API_: New iOS 18 Vision API for structured document detection
      _Output_: Document quadrilateral and saliency masks

- [x] **RecognizeDocumentsRequest**: Structured document understanding
      _API_: iOS 26+ Vision API for document element recognition
      _Location_: [StructuredDocumentParser.swift](OpenIntelligence/Services/StructuredDocumentParser.swift)
      _Status_: Implemented - Parses tables, paragraphs, lists, titles as typed elements
      _Output_: StructuredElement enum with TableData, paragraph text, list items

- [x] **Table Recognition**: Detect and extract table structures
      _API_: Vision's RecognizeDocumentsRequest table recognition capabilities
      _Location_: [StructuredDocumentParser.swift](OpenIntelligence/Services/StructuredDocumentParser.swift)
      _Status_: Implemented - Tables extracted as atomic chunks with row/column structure
      _Output_: Structured table data preserved through chunking pipeline

#### Enhanced Metadata

- [x] **VisualContentMetadata**: Track visual elements per page/chunk
      _Location_: [ImageUnderstandingService.swift](OpenIntelligence/Services/ImageUnderstandingService.swift)
      _Status_: Implemented - tracks imageCount, imageClassifications, hasTableContent, columnLayout, captionedImages, imagesWithDescriptions

  ```swift
  struct VisualContentMetadata: Codable {
      let imageCount: Int
      let imageClassifications: [String: Float]  // label → confidence
      let hasTableContent: Bool
      let columnLayout: ColumnLayout  // single, double, complex
      let captionedImages: Int
  }
  ```

- [ ] **ProcessingMetadata Extension**: Add visual processing stats
      _Fields_: `imagesProcessed`, `imagesWithDescriptions`, `tablesExtracted`, `layoutComplexity`

### Phase 2.06 — Universal Document Intelligence (AppleRAG Spec)

_Nuclear-option RAG architecture for domain-agnostic document understanding. Makes the system universally intelligent across any document type (technical manuals, legal contracts, medical records, research papers)._

#### Canonical Document Model (CDM) Enrichment

- [x] **structureType Field**: Track element type (table/paragraph/list/title) per chunk
      _Location_: `ChunkMetadata.structureType` in [DocumentChunk.swift](OpenIntelligence/Models/DocumentChunk.swift)
      _Status_: Implemented - populated by StructuredDocumentParser

- [x] **Structure-Aware Chunking**: Tables and lists preserved as atomic chunks
      _Location_: `createStructureAwareChunks()` in [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift)
      _Status_: Implemented - tables never split mid-content

- [x] **Bounding Box Preservation**: Store `bboxArray: [CGFloat]` per chunk for spatial retrieval
      _Location_: `ChunkMetadata.bboxArray` and `bbox` computed property in [DocumentChunk.swift](OpenIntelligence/Core/Models/DocumentChunk.swift)
      _Status_: Implemented - field added, ready for population during structured parsing
      _Benefit_: "Show me what's in the top-right of page 3" queries

- [x] **Section Path Hierarchy**: Store `sectionPath: [String]` (e.g., ["Chapter 5", "5.3 Fluids", "Engine Oil"])
      _Location_: `ChunkMetadata.sectionPath` in [DocumentChunk.swift](OpenIntelligence/Core/Models/DocumentChunk.swift)
      _Detection_: `detectSections()` and `buildSectionPath()` in [SemanticChunker.swift](OpenIntelligence/Services/Document/SemanticChunker.swift)
      _Status_: Implemented - hierarchical section detection with markdown headers, numbered sections, ALL CAPS
      _Benefit_: Hierarchical disambiguation ("5.3.1 Viscosity" vs "8.2.1 Viscosity" in different chapters)

- [ ] **Graph Edges**: Track cross-references ("See page 47", "Refer to Table 5-2")
      _Schema_: Add `references: [(target_id, label)]` to ChunkMetadata
      _Benefit_: Follow-the-trail retrieval for interconnected specs

#### Index Layer Expansion

- [x] **Dense Vector Index**: Semantic similarity search
      _Status_: Implemented - VectorDatabase protocol + PersistentVectorDatabase/VecturaVectorDatabase

- [x] **Lexical Index (BM25)**: Keyword/exact-match search
      _Status_: Implemented - BM25Service with corpus vocabulary

- [x] **Structure Index**: Query by element type
      _Location_: `applyStructureTypeBoost()` in [HybridSearchService.swift](OpenIntelligence/Services/HybridSearchService.swift)
      _Status_: Implemented - boosts table/list chunks for specification queries

- [ ] **Graph Index**: Cross-reference traversal
      _Implementation_: Build adjacency list from parsed references
      _Queries_: "What does Section 5 reference?" → traverse edges

#### Model Pipeline Enhancements

- [x] **Bi-Encoder Embedder**: Fast first-stage retrieval
      _Status_: Implemented - CoreMLSentenceEmbeddingProvider (384-dim)

- [x] **Cross-Encoder Reranker**: Precise relevance scoring
      _Status_: Implemented - ReRankerModel.mlpackage in RAGEngine

- [x] **Extractive QA Span Model**: Direct answer extraction without LLM generation
      _Location_: [ExtractiveQAService.swift](OpenIntelligence/Services/RAG/ExtractiveQAService.swift)
      _Protocol_: `ExtractiveQAService` with `HeuristicExtractiveQAService` (NLTagger-based) and `PlaceholderExtractiveQAService`
      _Status_: Stub + heuristic fallback implemented; CoreML model integration ready (awaiting TinyBERT conversion)
      _Architecture_: TinyBERT (6-layer) + start/end position heads (planned)
      _Output_: `ExtractionResult { answerSpan, confidence, sourcePassageIndex, spanRange }`
      _Benefit_: 10x faster for factual lookups; 100% traceable to source text
      _Fallback_: If confidence < 0.7, escalate to LLM generation

- [ ] **Multi-Hop Reasoning Model**: Chain evidence across chunks
      _Use Case_: "Compare oil specs in Chapter 5 vs recommended in Chapter 8"
      _Implementation_: Iterative retrieval with entity linking

#### Verification Gates (Anti-Hallucination)

_Implemented: VerificationGateService.swift with 4-gate verification pipeline_

- [x] **Gate A: Retrieval Confidence Threshold**
      _Location_: `runGateA()` in [VerificationGateService.swift](OpenIntelligence/Services/RAG/VerificationGateService.swift)
      _Rule_: If max(chunk*scores) < τ (0.55 normal, 0.65 touchy) OR margin < μ (0.05) → abstain
      \_Benefit*: Prevents confident-sounding hallucinations when docs don't contain answer

- [x] **Gate B: Evidence Coverage Check**
      _Location_: `runGateB()` in [VerificationGateService.swift](OpenIntelligence/Services/RAG/VerificationGateService.swift)
      _Method_: Extract claims from response, verify each has supporting evidence in corpus
      _Rule_: If coverage < 70% → flag unsupported claims
      _Benefit_: Catches answers with fabricated details not present in source

- [x] **Gate C: Numeric Sanity Check**
      _Location_: `runGateC()` in [VerificationGateService.swift](OpenIntelligence/Services/RAG/VerificationGateService.swift)
      _Method_: Extract numbers from response, verify each appears in source chunks
      _Rule_: All numbers must trace to corpus (with unit variation tolerance)
      _Benefit_: Catches hallucinated specifications, measurements, quantities

- [x] **Gate D: Contradiction Sweep**
      _Location_: `runGateD()` in [VerificationGateService.swift](OpenIntelligence/Services/RAG/VerificationGateService.swift)
      _Method_: Detect negation patterns ("not", "never", "isn't") and value conflicts between response and corpus
      _Flag_: "Response mentions X, but document says Y"
      _Benefit_: Catches hallucinated facts that contradict source

- [x] **Pipeline Integration**: Verification gates wired into RAGService
      _Location_: Step 7.5 in `queryInternal()` in [RAGService.swift](OpenIntelligence/Services/RAG/RAGService.swift)
      _Status_: All 4 gates run after LLM generation, before response packaging
      _Gating_: If grounded-only mode AND gates fail → abstain with explanation

- [ ] **Gate E: LLM Self-Consistency Check** (Future Enhancement)
      _Method_: Generate 3 responses at temperature 0.3, 0.5, 0.7
      _Rule_: If entropy(responses) > threshold → flag as "uncertain" in UI
      _Benefit_: Catches unstable generations

#### Iterative Retrieval Loop

- [x] **Basic Iterative Retrieval**: Refine search based on initial results
      _Location_: [IterativeRetrievalService.swift](OpenIntelligence/Services/IterativeRetrievalService.swift)
      _Status_: Implemented - adaptive iteration with quality thresholds

- [ ] **Formalized max_loops Parameter**: Configurable iteration limit
      _Default_: max*loops = 3
      \_Implementation*: Add to RetrievalConfig

- [ ] **Confidence Gating Per Loop**: Stop early if confidence >= 0.9
      _Benefit_: Don't waste cycles when first pass is sufficient

- [ ] **Cross-Chunk Entity Resolution**: Track entities across iterations
      _Benefit_: "5W-30" in chunk A links to "engine oil viscosity" in chunk B

### Phase 2.1 — Model Ecosystem

- [x] **Model Marketplace**: Removed - app focuses on Apple Intelligence + PCC
- [ ] **Custom Embedding Models**: User-provided Core ML embedders
- [ ] **Fine-Tuning Pipeline**: LoRA adapters for domain-specific performance

### Phase 2.15 — Interactive Embedding Visualization (Medium)

_Next-level 3D embedding space exploration with agentic intelligence_

- [ ] **Tap-to-Inspect**: Tap any point → floating card shows chunk text snippet and document name
- [ ] **Query Visualization Mode**: Animate search results in 3D space
  - Query embedding appears as pulsing star
  - Lines drawn to retrieved chunks
  - Irrelevant points fade out
- [ ] **LLM-Generated Cluster Labels**: Use Apple Intelligence to auto-name clusters
  - "Technical Specs", "Safety Warnings", "Maintenance Procedures"
- [ ] **Color Legend Sidebar**: Collapsible panel mapping documents → colors
- [ ] **Zoom-to-Cluster**: Double-tap cluster badge → camera flies in for close-up
- [ ] **Distance Ruler**: Drag between two points → shows cosine similarity score
- [ ] **Time-Series Animation**: Visualize how embeddings evolve as documents are added

### Phase 2.15 — Apple Intelligence Gap Closure (WWDC 2024 + 2025)

_Comprehensive gap analysis: every Apple Intelligence framework announced at WWDC24/25 evaluated against OpenIntelligence. 23 items identified, prioritized across v2.1/v2.2/v3.0._

---

#### v2.1 — Next Release (Critical Apple Intelligence Gaps)

##### 1. Guardrails API — `SystemLanguageModel.Guardrails` (WWDC25)

- [x] **Add Guardrails to LanguageModelSession**: Apple's built-in safety layer that flags sensitive content in both model input and output
      _API_: `LanguageModelSession(guardrails: .default)` or `.permissiveContentTransformations`
      _Why_: App already has VerificationGateService (gates A-D) for anti-hallucination. Guardrails adds Apple's own content safety layer — critical for App Store compliance and user trust.
      _Status_: ✅ Active in `ImagePlaygroundService` (`.permissiveContentTransformations`). Extend to `AppleFoundationLLMService`, `HyDEService`, `ContextualCompressionService` for full coverage.
      _Effort_: **Low** — add `guardrails: .default` to remaining `LanguageModelSession` initializations
      _Files_: `AppleFoundationLLMService.swift`, `HyDEService.swift`, `ContextualCompressionService.swift`

##### 2. CoreSpotlight Integration + Semantic Search (WWDC24/25)

- [x] **Index documents in CoreSpotlight**: Make ingested documents searchable from Spotlight, Siri, and the system semantic index
      _API_: `CSSearchableIndex`, `CSSearchableItem`, `CSUserQuery` (semantic search since iOS 18)
      _Why_: Users can't find their documents from Spotlight. A document management app without Spotlight indexing is invisible to the OS. With semantic search, users could ask Siri "What does my manual say about oil changes?" and get results from indexed containers.
      _Effort_: **Medium** — index documents in `ContainerService` on ingest, update on delete, donate `NSUserActivity` for recents
      _New Service_: `SpotlightIndexService.swift`

##### 3. SpeechAnalyzer Migration (WWDC25 — replaces SFSpeechRecognizer)

- [x] **Migrate AudioTranscriptionService to SpeechAnalyzer**: Complete rewrite of Speech framework. `SpeechAnalyzer` is an `actor` with modular analysis, `AsyncSequence` results, offline transcription, and asset management.
      _API_: `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, `.offlineTranscription` preset
      _Why_: Current `AudioTranscriptionService` uses legacy `SFSpeechRecognizer` with delegate callbacks. New API offers: offline transcription, better accuracy with downloadable models, native Swift concurrency, multiple analysis modules on same audio stream.
      _Effort_: **Medium** — rewrite `AudioTranscriptionService.swift` to use `SpeechAnalyzer` + `SpeechTranscriber`
      _Files_: `AudioTranscriptionService.swift`

##### 4. Translation Framework (iOS 17.4+)

- [x] **Multilingual RAG**: On-device translation for non-English document ingestion and cross-language queries
      _API_: `TranslationSession`, `LanguageAvailability`, SwiftUI `.translationPresentation()` modifier
      _Why_: App already has `LanguageDetectionService` via NLLanguageRecognizer but no translation. For a universal RAG engine, translation is essential for multilingual document sets and cross-language queries.
      _Effort_: **Low-Medium** — add translation option to query results, optionally translate chunks before embedding
      _New Service_: `TranslationService.swift`

##### 5. Liquid Glass UI (WWDC25 — iOS 26)

- [ ] **Adopt Liquid Glass design system**: iOS 26's glass material design for toolbars, navigation bars, tab bars, and custom views
      _API_: `.glassEffect()`, `.liquidGlass` material, `GlassEffectContainer`
      _Why_: iOS 26 introduces a completely new visual design language. Apps that don't adopt Liquid Glass will look dated immediately. Chat interface, document library, and settings all need updating.
      _Effort_: **Medium** — update `ChatScreen`, `DocumentLibraryView`, `SettingsView`, navigation bars, tab bar
      _Files_: All SwiftUI views in `/Features/` and `/UI/`

##### 6. UseCase + Locale Gating (WWDC25)

- [ ] **SystemLanguageModel.UseCase**: Declare specific model use cases for optimized behavior
      _API_: `SystemLanguageModel(useCase:)` with predefined use cases
      _Effort_: **Low** — add use case declarations to session creation
- [x] **Locale/Language gating**: Check `SystemLanguageModel.supportsLocale()` before generating
      _API_: `SystemLanguageModel.supportsLocale(_:)` — returns whether a language is supported
      _Why_: Should gate queries by supported locale rather than letting unsupported-language queries fail silently
      _Status_: ✅ Active in `LLMService` (lines 568-574)
      _Effort_: **Done**

---

#### v2.2 — Following Release (High-Impact Apple Intelligence Features)

##### 7. Visual Intelligence Framework (WWDC25)

- [x] **Visual Intelligence search integration**: Let your app appear in Visual Intelligence search results when users point their camera at objects or select content in screenshots
      _API_: `VisualIntelligence` framework, `SemanticContentDescriptor`, App Intents integration
      _Why_: Users could point their camera at a physical document and search for matching content in their OpenIntelligence knowledge base. Natural fit for a document intelligence app.
      _Effort_: **Medium** — create `VisualIntelligenceSearchIntent`, extend existing AppIntents
      _New File_: `VisualIntelligenceIntents.swift`

##### 8. Foundation Models Adapter Training (WWDC25)

- [x] **Custom LoRA adapters for domain-specific RAG**: Apple provides a Python toolkit to train custom LoRA adapters (~160MB each) that specialize the on-device LLM for domain-specific tasks
      _API_: `ModelAdapter`, `LanguageModelSession(adapter:)`, `BackgroundAssets` for adapter download
      _Why_: A trained adapter could dramatically improve answer quality for technical documents (manuals, specifications, medical records) without longer prompts. Each adapter adds domain vocabulary and response style.
      _Effort_: **High** — requires Python training pipeline, dataset curation, per-OS-version adapters, BackgroundAssets integration
      _New Files_: `AdapterManager.swift`, `scripts/train_adapter.py`, `*.fmadapter` assets

##### 9. Prompt Evaluation Framework (WWDC25)

- [x] **Systematic prompt quality testing**: Build evaluation harness for the 20+ prompts used across 9+ services
      _Methodology_: Apple's recommended approach for measuring prompt quality, regression prevention, semantic similarity scoring across test datasets
      _Why_: No automated way to verify prompt quality across model updates. When Apple FM updates silently, RAG pipeline performance could degrade without detection.
      _Effort_: **Medium** — build XCTest-based evaluation suite with gold-standard Q&A pairs per document type
      _New Files_: `PromptEvaluationTests/`, test dataset JSON files

##### 10. Metal 4 (WWDC25 — iOS 26)

- [ ] **Upgrade GPUComputeService to Metal 4**: New core API with ML inference passes, unified compute encoders, improved shader compilation, and resident resource sets
      _API_: Metal 4 `MTLCommandEncoder`, `MTLResidentSet`, ML inference integration
      _Why_: Current `GPUComputeService` uses Metal 3 API with 3-tier shader selection. Metal 4 offers native ML inference passes that could unify the vector search + reranking pipeline on GPU, plus better shader compilation for faster cold starts.
      _Effort_: **Medium** — migrate 7 Metal pipelines, evaluate ML inference passes for cross-encoder
      _Files_: `GPUComputeService.swift`, `*.metal` shader files

##### 11. BNNS Graph Updates (WWDC25)

- [x] **Enhanced neural network graph operations**: Updated BNNS Graph API for on-device inference with new operation types and optimization passes
      _API_: `BNNSGraph`, enhanced Accelerate framework neural network operations
      _Why_: Current `BNNSVectorDatabase` uses basic vDSP operations. Enhanced BNNS Graph could improve embedding search, batch operations, and potentially replace some CoreML inference paths.
      _Effort_: **Medium** — evaluate BNNS Graph for vector search and batch operations in `BNNSVectorDatabase.swift`

##### 12. Image Playground / ImageCreator (iOS 18.1+ / WWDC25)

- [x] **Programmatic on-device image generation**: Generate images from text descriptions using Apple's generative model
      _API_: `ImageCreator`, `imagePlaygroundSheet()` SwiftUI modifier
      _Why_: `DeviceCapabilityService` already checks `supportsImagePlayground` but never uses it. Could enhance document summaries with generated visual representations, or generate concept illustrations from document content.
      _Effort_: **Low** — import `ImagePlayground`, add `imagePlaygroundSheet` to chat UI, optionally use `ImageCreator` for programmatic generation

##### 13. DetectLensSmudgeRequest (WWDC25 — iOS 26)

- [ ] **Camera lens quality check before OCR**: Detect camera lens smudges/obstructions before performing OCR capture
      _API_: `DetectLensSmudgeRequest` (Vision framework)
      _Why_: Would improve camera-to-RAG quality by warning users when lens is dirty before capture
      _Effort_: **Low** — add smudge detection check to `CameraManager.swift` / `CaptureToRAGBridge.swift`

##### 14. NLGazetteer (Custom Entity Training)

- [x] **Custom entity extraction**: Train gazetteer on product names, part numbers, domain-specific terms
      _API_: `NLGazetteer` with custom vocabulary files
      _Benefit_: Boost retrieval for exact entity matches, enable domain-specific NER beyond NLTagger's built-in categories
      _Effort_: **Medium** — auto-generate gazetteer from ingested document vocabulary
      _Files_: `EntityIndexService.swift`, new `GazetteerTrainer.swift`

---

#### v3.0 — Strategic (Platform Evolution)

##### 15. @Observable Migration (iOS 17+ — Observation Framework)

- [ ] **Replace ObservableObject/Combine with @Observable**: Modern replacement for `@Published`/Combine-based state management across 40+ view models
      _API_: `@Observable` macro, automatic property tracking, fine-grained view updates
      _Why_: 90 SwiftUI files use `ObservableObject`/`@Published` (18 Combine imports). Migration reduces boilerplate, improves SwiftUI re-render performance (only views accessing changed properties update), aligns with modern Swift patterns.
      _Effort_: **High** — systemic migration across 40+ view models, can be done incrementally
      _Strategy_: Migrate leaf view models first (Settings, Diagnostics), then core flows (Chat, Documents), finally services (RAGService)

##### 16. WidgetKit — Home Screen Widgets

- [ ] **Document intelligence widgets**: Home screen widgets showing recent queries, document count per container, ingestion status, and quick query shortcuts
      _API_: `WidgetKit`, `TimelineProvider`, `IntentConfiguration`
      _Effort_: **Medium** — create widget target, share data via App Groups
      _Widget Types_:
  - **Document Count**: Number of documents and containers at a glance
  - **Recent Queries**: Last 3-5 queries with confidence scores
  - **Quick Query**: Deep-link into chat with pre-filled query
  - **Container Status**: Per-container document/chunk counts

##### 17. BackgroundTasks — Background Indexing

- [x] **BGTaskScheduler for background processing**: Background document indexing, embedding pre-computation, Spotlight index updates, conversation memory consolidation
      _API_: `BGTaskScheduler`, `BGProcessingTask`, `BGAppRefreshTask`
      _Why_: Currently no background processing. Large document ingestion blocks the UI. Background tasks could pre-compute embeddings, update Spotlight index, consolidate conversation memory, and run maintenance tasks.
      _Effort_: **Medium** — register background tasks, share data with background execution context

##### 18. SwiftData (iOS 17+)

- [ ] **Evaluate SwiftData vs raw sqlite3**: Modern persistence layer that uses SQLite underneath but with Swift-native syntax
      _Why_: Current raw `sqlite3` C API in `SQLiteFullTextService` is powerful but verbose. SwiftData could simplify CRUD for non-FTS5 data (containers, settings, conversation history) while keeping raw SQLite for FTS5 and performance-critical paths.
      _Risk_: Migration complexity, potential performance regression for FTS5-dependent paths
      _Effort_: **High** — careful evaluation needed, dual-stack migration

##### 19. TipKit — Contextual Onboarding

- [x] **Guided onboarding tips**: Contextual tips for RAG features (how to ingest, query, use containers, choose quality modes)
      _API_: `TipKit`, `Tip` protocol, `.popoverTip()`, `TipGroup`
      _Why_: App has an onboarding flow but no contextual tips during actual usage. First-time users miss features like Deep Think mode, cross-container search, quality mode selection.
      _Effort_: **Low** — define `Tip` conformances, add `.popoverTip()` modifiers to key UI elements

##### 20. Smart Reply (iOS 18.2+)

- [x] **AI-generated reply suggestions in chat**: Suggest follow-up questions based on the current query and response
      _API_: `UIMessageConversationContext` for reply suggestion context
      _Why_: After answering a query, the system could suggest related follow-up questions ("What about the maintenance schedule?", "Compare with the 2024 model")
      _Effort_: **Medium** — build suggestion engine from RAG context + entity graph

##### 21. NSUserActivity / Handoff

- [x] **Universal links and Siri activity donations**: Donate queries and document views as activities for Spotlight suggestions, Siri shortcuts, and Handoff
      _API_: `NSUserActivity`, `userActivity(_:)` SwiftUI modifier
      _Status_: ✅ Active in `DocumentLibraryView` and `ChatScreen` with `.userActivity()` modifiers
      _Effort_: **Done**

##### 22. Genmoji

- [ ] **NSAdaptiveImageGlyph handling**: Support Genmoji (custom AI-generated emoji) in chat text input and display
      _API_: `NSAdaptiveImageGlyph`, `UITextView` / attributed string support
      _Effort_: **Low** — handle `NSAdaptiveImageGlyph` in chat text rendering

##### 23. Additional Frameworks

- [ ] **DataScannerViewController**: Live camera document scanning with real-time OCR
      _API_: VisionKit `DataScannerViewController`
      _Status_: Code exists in `/Features/Camera/` but not wired to production UI
      _Effort_: **Low** — wire existing camera code to production UI

- [ ] **CreateMLComponents**: Train small on-device classifiers on user's document patterns
      _Benefit_: Learn document types, topics, quality signals from usage
      _Effort_: **Medium** — dataset collection from user feedback + classifier training

- [ ] **SoundAnalysis**: Classify audio content (speech, music, ambient) before transcription
      _Benefit_: Skip non-speech audio, improve transcription quality
      _Effort_: **Low**

- [ ] **MetricKit**: Collect real device performance metrics in production
      _Benefit_: Optimize pipeline based on actual user hardware patterns
      _Effort_: **Low**

- [ ] **OSSignposter**: Instruments-visible pipeline profiling
      _Benefit_: Make embedding/search/generation visible in Xcode Instruments
      _Effort_: **Low**

---

#### Apple Intelligence Gap Summary

| Priority      | Items  | Done | Remaining | Target | Key Capabilities                                                                                                          |
| ------------- | ------ | ---- | --------- | ------ | ------------------------------------------------------------------------------------------------------------------------- |
| **Critical**  | 6      | 4    | 2         | v2.1   | ✅ Guardrails, CoreSpotlight, SpeechAnalyzer, Translation — ⬜ Liquid Glass, UseCase (supportsLocale done)                |
| **High**      | 8      | 6    | 2         | v2.2   | ✅ Visual Intelligence, Adapter Training, Prompt Eval, BNNS Graph, Image Playground, NLGazetteer — ⬜ Metal 4, Lens Smudge |
| **Strategic** | 9      | 4    | 5         | v3.0   | ✅ BackgroundTasks, TipKit, Smart Reply, NSUserActivity — ⬜ @Observable, WidgetKit, SwiftData, Genmoji, DataScanner       |
| **Total**     | **23** | **14** | **9**   |        | **61% coverage achieved — 9 gaps remaining**                                                                              |

---

### Phase 2.2 — Platform Expansion

- [ ] **macOS Catalyst**: Native desktop experience
- [ ] **iPad Split View**: Side-by-side document + chat layout
- [ ] **WidgetKit Extensions**: Home screen widgets (document count, recent queries, quick query — see Phase 2.15 #16)
- [x] **BackgroundTasks Integration**: BGTaskScheduler for background indexing/embedding (see Phase 2.15 #17)

### Phase 2.3 — Enterprise Features

- [ ] **Team Containers**: Shared knowledge bases with access control
- [ ] **SSO Integration**: Enterprise authentication
- [ ] **Audit Logging**: Compliance-ready query history

---

## 4. Sprint Backlog (Current)

_Move items here when actively working on them._

| Task                                         | Status  | Owner | Notes                                                                                                                                                                                              |
| -------------------------------------------- | ------- | ----- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Release Build Fix                            | ✅ Done | Agent | Fixed #Preview wrapped in #if DEBUG                                                                                                                                                                |
| Production Preflight                         | ✅ Done | Agent | Secret scan, privacy keys, both builds pass                                                                                                                                                        |
| NLContextualEmbedding                        | ✅ Done | Agent | 15-25% accuracy boost via contextual embeddings                                                                                                                                                    |
| @Generable Response Types                    | ✅ Done | Agent | RAGAnswer, RAGSearchResults, RAGDocumentSummary                                                                                                                                                    |
| High-Accuracy Container Factory              | ✅ Done | Agent | KnowledgeContainer.highAccuracy() helper                                                                                                                                                           |
| Fix ingestion re-upload loop                 | ✅ Done | Agent | Prevent self-tuning rebuild recursion during auto-reembed                                                                                                                                          |
| Fix Documents “New Library” crash            | ✅ Done | Agent | Inject SettingsStore at root; Documents tab reads settings.useHighAccuracyEmbeddings                                                                                                               |
| DEBUG paywall purchase simulation            | ✅ Done | Agent | Allow testing entitlement unlocks even when StoreKit returns an empty catalog                                                                                                                      |
| DEBUG doc-pack refill simulation             | ✅ Done | Agent | Mirror paywall simulation when doc pack Product metadata is unavailable                                                                                                                            |
| De-dupe empty-catalog billing warnings       | ✅ Done | Agent | Reduce repeated “StoreKit returned an empty product catalog” / “Products unavailable” spam                                                                                                         |
| Isolate StoreKit config to test scheme       | ✅ Done | Agent | Move StoreKit .storekit config off main Run action to prevent debug simulation popups and ensure sandbox/App Store paths behave normally                                                           |
| Remove local downloadable models             | ✅ Done | Agent | Removed GGUF/CoreML/MLX support; simplified to Apple Intelligence + On-Device Analysis only                                                                                                        |
| Apple Intelligence API Audit                 | ✅ Done | Agent | Full FoundationModels API audit: prewarm(), SamplingMode, GenerationError handling, Transcript, LanguageModelFeedback, 4096-token context (TN3193)                                                 |
| Tool @Guide Constraints                      | ✅ Done | Agent | Added .range() constraints to SearchDocumentsTool topK/minSimilarity parameters                                                                                                                    |
| FM Feedback Integration                      | ✅ Done | Agent | Thumbs up/down in chat UI submits LanguageModelFeedback to Apple                                                                                                                                   |
| Chat Attachment Race Condition               | ✅ Done | Agent | Fixed: attachments now fully processed before query runs (was sending query before documents indexed)                                                                                              |
| Prevent unwanted On-Device Analysis fallback | ✅ Done | Agent | Keep partial streamed responses; remove low-confidence auto-switch; improve extractive QA ranking                                                                                                  |
| Settings UX Overhaul                         | ✅ Done | Agent | Replaced fallback card with Context & Processing info card; improved privacy card with Apple architecture explanations; added Neural Engine info; removed model selector (Apple Intelligence only) |
| Short Query Language Fix                     | ✅ Done | Agent | Added English context wrapping for 1-5 word queries to prevent language detection errors                                                                                                           |
| Conversational RAG Prompts                   | ✅ Done | Agent | Changed from extractive QA to conversational responses; improved context assembly logging                                                                                                          |
| Processing Intelligence View                 | ✅ Done | Agent | New unified chat header component showing real-time execution location (Device/PCC), context window usage, quality mode, and expandable details                                                    |
| Quality Mode Chat Integration                | ✅ Done | Agent | Quality mode quick picker added to chat header; settings now shows explanation only; seamless switching between Standard/Deep Think/Maximum                                                        |
| Unified Metrics Bar Merge                    | ✅ Done | Agent | Merged ProcessingIntelligenceView + LiveStreamingMetrics into single UnifiedMetricsBar; eliminated duplicate UI; single expandable component with execution, context, speed, sources, quality mode |
| Entitlement Store Cleanup                    | ✅ Done | Agent | Removed dead "Local Model Preview" code and restored truncated methods                                                                                                                             |
| Document Upload Progress UI                  | ✅ Done | Agent | Added per-file progress toast for multi-document uploads                                                                                                                                           |
| Remove Dead Code                             | ✅ Done | Agent | Deleted InstalledModel.swift and LocalComputePreference.swift                                                                                                                                      |
| Intelligence Layer (v2.0)                    | ✅ Done | Agent | QueryRewriterService, IterativeRetrievalService, CorpusVocabulary expansion, settings UI toggles, full RAGService integration                                                                      |
| Context Window TN3193 Fix                    | ✅ Done | Agent | Fixed baseWindowTokens 65536→4096, maxContextCharsCap 65000→5000 for Apple FM 4096-token limit                                                                                                     |
| RAGEngine Singleton Pattern                  | ✅ Done | Agent | Added RAGEngine.shared to prevent ReRanker loading 4x per query; updated all callsites                                                                                                             |
| SystemStateMonitor                           | ✅ Done | Agent | Real-time device monitoring (thermal/battery/memory/CPU/LPM) with 2s refresh; exposed in UnifiedMetricsBar and SettingsView                                                                        |
| RAGQualityMode Simplification                | ✅ Done | Agent | Reduced from 4 modes to 2 (Standard + Deep Think); removed confusing Response Style slider                                                                                                         |
| 3D Embedding Visualization Overhaul          | ✅ Done | Agent | Ground plane grid, semantic axes ("Similar →", "Related ↑"), glowing spheres, cluster badges, gesture hints                                                                                        |
| UnifiedMetricsBar Type Fixes                 | ✅ Done | Agent | Fixed MemoryPressure→MemoryPressureLevel; removed duplicate executionExplanation property                                                                                                          |
| Cross-Encoder Re-Ranker Audit                | ✅ Done | Agent | Confirmed ReRankerModel.mlpackage bundled, BertTokenizer working, rerankWithCrossEncoder() functional                                                                                              |
| Conversation Memory Service                  | ✅ Done | Agent | ConversationMemoryService with LLM summarization, entity tracking, per-container persistence, RAGService integration, Settings UI toggle                                                           |
| Container Dimension Migration                | ✅ Done | Agent | Auto-fixes containers with invalid embedding dimensions (784→384) or unsupported providers (nl_contextual→coreml) at load time                                                                     |
| Maximum Mode Confidence Fix                  | ✅ Done | Agent | Fixed 0% confidence display by starting at 5% baseline; progress now shows 5%→12%→20%→... instead of 0%→0%→85%                                                                                     |
| Ingestion Queue UI Enhancements              | ✅ Done | Agent | Shorthand provider labels (CoreML, NL, FM); 4-row granular metrics; semantic boundary display; entity extraction visualization; timing waterfall; throughput calculations                          |
| App Store Build 4                            | ✅ Done | Agent | Incremented build to 4, archived and exported IPA for Transporter upload                                                                                                                           |
| App Store Rejection Fixes (Build 9)          | ✅ Done | Agent | Fixed 3.1.2: Added Terms of Use URL to description. Fixed 5.2.5: Subtitle already compliant. 2.1: IAPs need App Store Connect screenshots                                                          |
| Deep Think Context Overflow Fix              | ✅ Done | Agent | Extended Maximum mode's sliding window insight compression to Deep Think (4-8 sessions); added context overflow retry with auto-reduction; tighter context budgets for multi-session modes         |

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
