# OpenIntelligence AI Guide

> **Auto-injected into every Copilot session.** Read before making changes.

## 🎯 MISSION: Universal RAG Engine

Ingest ANY document, ANY size. Answer questions using Apple Intelligence. **ZERO DATA LOSS.**

### Hard Limits (MEMORIZE)

| Constraint       | Value         | Notes                                   |
| ---------------- | ------------- | --------------------------------------- |
| Embedding tokens | 510 max       | CoreML MiniLM-L6-v2 (512 - CLS/SEP)     |
| Chunk size       | 310 words max | 340 - 30 for contextual prefix overhead |
| Chunk limit      | 50000 max     | Supports ~65,000 pages per container    |
| LLM context      | 4096 tokens   | Apple FM TN3193 on-device limit         |
| Context chars    | 5500 max      | ~4000 tokens with margin                |
| Embedding dim    | 384           | MiniLM output                           |
| OCR DPI          | 360           | 5x scale factor for PDF rendering       |

**If you touch chunking/embedding/context packing → VERIFY these limits.**

---

## Directives

1. Read `HOW_IT_WORKS.md` + `ARCHITECTURE.md` first
2. NO new markdown files for plans/logs
3. Tasks tracked in `ROADMAP.md` only
4. Use iOS 26.0+ APIs (`FoundationModels`, `@Tool`, Vision structured parsing)

---

## Architecture

- **RAGService** (`@MainActor`): UI orchestrator, published state
- **RAGEngine** (`actor`): Background math (MMR, BM25, RRF)
- **Containers**: Data scoped via `VectorStoreRouter`
- **FullTextStorageService** (`actor`): Complete original document storage for exact queries
- **AgenticOrchestrator**: Multi-session reasoning with Self-RAG 2.0 enrichment prompting

### Pipeline (29 Steps End-to-End)

```
INGESTION (6 steps):
  1. Parse (PDFKit/Vision OCR 360 DPI/Office ZIP)
     - PHASE -1 Text Layer Validation (Jaccard font cipher detection)
     - Adaptive Preprocessing (5 CIFilter strategies: minimal→maximum)
     - Dynamic Vocabulary (PDFKit text mining → customWords)
     - Centralized OCR config (OCRConfiguration.configureRequest)
     - Multi-candidate confidence OCR (topCandidates(5), 90% numeric threshold)
  2. SemanticChunker (≤310w, section detection)
  3. Entity Extraction (NLTagger NER + PascalCase)
  4. Token Validation (BertTokenizer ≤510)
  5. Embedding (384-dim MiniLM)
  6. Store (HNSW index + FullTextStorage + EntityIndex)

QUERY → RESPONSE (23 steps):
  Step 0:   Corpus Analysis (vocabulary cache)
  Step 1:   Query Understanding (pronoun resolution, NER)
  Step 1.5: Query Expansion (corpus + container vocab)
  Step 1.6: Intent Classification (lookup/procedure/compare/summarize)
  Step 2:   Query Embedding (384-dim)
  Step 2.5: RAPTOR-lite Routing (overview → L1 summaries)
  Step 3:   Hybrid Search (Vector + BM25 + RRF) or Iterative Retrieval
  Step 4:   Cross-Encoder Rerank (TinyBERT)
  Step 4.3: Low-Confidence Filtering
  Step 4.4: Multi-Document Representation (source diversity)
  Step 4.5: MMR Diversification (λ=0.6)
  Step 4.6: Parent Document Retrieval (±5 siblings)
  Step 4.7: Contextual Compression (LLM filters)
  Step 4.9: Graph Context Packing (token budget)
  Step 5:   Context Assembly (Lost-in-Middle reorder)
  Step 5.9: Extractive Summarization (for summarize intent)
  Step 5.10: Extractive QA (for lookup intent)
  Step 5.11: Topical Relevance Check (lexical < 20% → Evidence-First mode)
  Step 6:   LLM Generation (Apple FM / PCC)
  Step 6.5: Response Formatting (markdown preservation pipeline)
  Step 7:   Quality Assessment (confidence scoring)
  Step 7.5: Verification Gates A-D (anti-hallucination)
  Step 8:   Package Results
  Step 8.1: Calibrated Confidence (Platt scaling)
  Step 9:   Response Metadata (timing, sources, metrics)
  Step 10:  Markdown Rendering (block-level parser + inline normalization)
```

### Multi-Session Reasoning

| Mode       | Sessions | Prompting Strategy                       |
| ---------- | -------- | ---------------------------------------- |
| Standard   | 3        | Direct synthesis                         |
| Deep Think | 4-8      | Self-RAG 2.0: ENHANCE (not verify)       |
| Maximum    | 8-50     | Multi-chain parallel + cluster synthesis |

**Self-RAG 2.0**: Sessions ADD details, don't second-guess valid answers. "SAE 0W-20" IS an oil type.

---

## Apple Framework Stack

**100% Native—No Third-Party AI**: FoundationModels, Vision, NaturalLanguage, CoreML, PDFKit, Speech, Metal, StoreKit 2

> **Full Reference**: See `Docs/reference/APPLE_DOCUMENT_INTELLIGENCE.md`

### Apple Framework Integration (23 WWDC24/25 Items)

**✅ Active in v2.0 (10):** Guardrails API, CoreSpotlight, SpeechAnalyzer, Image Playground, NLGazetteer, BackgroundTasks, TipKit, Smart Reply, supportsLocale(), NSUserActivity

**📦 Code Complete / Not Wired (5):** Visual Intelligence (App Intents), Translation.framework, Adapter Training, Prompt Evaluation, BNNS Graph

**Remaining Gaps (9):**

| Target   | Frameworks                                                          |
| -------- | ------------------------------------------------------------------- |
| **v2.1** | Liquid Glass, UseCase                                               |
| **v2.2** | Metal 4, Lens Smudge Detection                                      |
| **v3.0** | @Observable, WidgetKit, SwiftData, Genmoji, DataScanner (VisionKit) |

> **Full Gap Analysis**: See `ROADMAP.md` → "Phase 2.15 — Apple Intelligence Gap Closure"

## Service Inventory (102 Services)

| Category           | Count | Key Services                                                                                                            |
| ------------------ | ----- | ----------------------------------------------------------------------------------------------------------------------- |
| **RAG Pipeline**   | 14    | RAGService, RAGEngine, HybridSearchService, VerificationGateService, ContextPackingService                              |
| **Query**          | 9     | QueryEnhancementService, HyDEService, ContextualCompressionService, QueryRouterService                                  |
| **Document**       | 24    | DocumentProcessor, SemanticChunker, EntityIndexService, AudioTranscriptionService, OCRConfiguration, TranslationService |
| **Embedding**      | 7     | EmbeddingService, CoreMLSentenceEmbeddingProvider                                                                       |
| **Storage**        | 3     | FullTextStorageService, SQLiteFullTextService, DocumentationCacheService                                                |
| **VectorStore**    | 5     | VectorDatabase (protocol), InMemoryVectorDatabase, BNNSVectorDatabase, VectorStoreRouter                                |
| **LLM**            | 8     | AppleFoundationLLMService, OnDeviceAnalysisService, LocalOpenAIServerLLMService                                         |
| **Agentic**        | 7     | AgenticOrchestrator, ConversationMemoryService, ResponseTransformService, WritingToolsService                           |
| **Rendering**      | 1     | MarkdownRenderer (block-level parser, inline normalizer, 6 regex patterns for Apple FM output)                          |
| **Infrastructure** | 22    | ContainerService, GPUComputeService (3-tier Metal shaders), HardwareTelemetryState, DeviceCapabilityService, AppTips    |

| **Billing** | 2 | StoreKitBillingService, EntitlementStore |

**Latest additions (v2.0.1, Mar 4)**: Pre-launch safety hardening (37 force-unwraps, 10 fatalError→fallback, 1,278 lines dead code removed). Bug fixes (cross-container chat bleed, undismissable alerts, insights sheet, StoreKit IUO, ContainerService init). Onboarding polish (haptics, VoiceOver, analytics). `ResponseTransformService` (5 RAG-grounded transforms using source chunks), AI Hub toolbar, Image Playground LLM concept extraction, BM25 struct refactor, Image Playground zero-shot prompt. Onboarding Rewrite — Pipeline Theater (2-page flow, capsule phase strip, live metrics dashboard, streaming log ticker, retry on failure, `accessibilityReduceMotion`, `foregroundStyle` migration 34 sites). Educational Sample Documents (3 curated docs with onboarding quota bypass). Suggested Questions Overhaul (few-shot contamination fix, 2-question diversity bug, stale questions on container switch, conversational tone rewrite). Container Isolation Hardening (EntityIndexService per-container scoping, FullTextStorageService scoped search, entity cleanup on delete). AI Hub Result Sheet (MarkdownText rendering, ShareLink, presentation detents). Anti-hallucination topical mismatch (prompt grounding fix, Evidence-First mode on lexical relevance < 20%).

**Full inventory**: See `ARCHITECTURE.md` → "Complete Service Inventory"

---

---

## Commands

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
./clean_and_rebuild.sh  # Fixes stale UI
```

---

## Pitfalls

1. **Token truncation** → Use `countTokens()`, not word count! Technical text ≠ 1.5 tokens/word
2. **NLTokenizer ≠ BertTokenizer** → `VHA21\VHAPALGarciG1` = 1 NL word but 10+ embedding tokens
3. **Context overflow** → >5500 chars = LLM error
4. **Dimension mismatch** → Must be 384-dim
5. **Simulator** → Apple FM unavailable; test fallbacks
6. **CSV data** → No row limits; tabs/special chars handled
7. **Markdown rendering** → Apple FM concatenates markdown on one line; `normalizeInlineMarkdown()` preprocessor handles this
8. **Response cleaning** → 7 functions in pipeline; do NOT strip markdown from `cleanupResponseText()` or `cleanupFinalAnswer()`
9. **Large PDF OOM** → 500+ page PDFs must use 5-page image batches with 144 DPI (2×) renders and autoreleasepool; results.removeAll() before image analysis
10. **Rate-limit cascade** → Apple FM rate limits during compression can cascade to 0-token generation; compression capped at 5 chunks with fresh session per chunk
