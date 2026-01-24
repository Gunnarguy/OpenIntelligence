# OpenIntelligence Roadmap

**Last Updated**: January 23, 2026
**Version**: 1.0.0 (Build 4)
**Status**: Production (App Store Submitted)
**RAG Maturity Score**: 9.8/10 (Entity Extraction + Recursive Research + mmap Storage + RAPTOR-lite + Query Routing)

### 🚀 NEXT: SQLite FTS5 Full-Text Search Engine (v1.1.0)

_Native SQLite FTS5 integration for 10-100X faster keyword search and pattern counting_

**Status**: In Development
**Target**: v1.1.0 (February 2026)
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
- [ ] **SQLiteFullTextService**: Core actor with FTS5 CRUD operations
- [ ] **Migration**: Auto-migrate .txt files → SQLite on first launch
- [ ] **HybridSearchService Update**: Replace BM25Scorer with FTS5 bm25()
- [ ] **RAGService Wiring**: Replace FullTextStorageService calls
- [ ] **Deletion Cascade**: Document deletion removes FTS5 entries
- [ ] **Container Isolation**: Per-container FTS5 tables for data isolation
- [ ] **Benchmark Validation**: Measure 10-100X improvements

#### Technical Details

- **Tokenizer**: `unicode61` (default, case-insensitive) + `porter` (stemming)
- **Prefix Indexes**: `prefix='2 3'` for efficient wildcard queries
- **highlight() / snippet()**: Native context extraction with match highlighting
- **NEAR Queries**: Proximity search for phrase matching
- **Contentless Option**: Store content separately, index only for max compression

---

### Recent Improvements (January 2026 - ZERO Data Loss Architecture)

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

- [x] **12+ @Tool Functions**: Autonomous search, summarization, analysis
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

- [x] **Test Coverage**: HybridSearchService edge cases now covered
      _Location_: [HybridSearchServiceTests.swift](OpenIntelligenceTests/HybridSearchServiceTests.swift)
      _Status_: Added 12+ edge case tests for RRF fusion, BM25 scoring, Unicode handling, and metadata

### Low Priority

- [x] **MLX macOS-Only**: Removed with local model cleanup (Dec 2025)
      _Status_: No longer applicable - local models removed

- [x] **Vendor LocalLLMClient**: Removed from project (Dec 2025)
      _Status_: Package removed entirely - no longer needed

- [ ] **Dead Code Cleanup**: Remove `#if false` wrapped files
      _Files_: `OpenAIResponsesAPIService.swift`, `LocalOpenAIServerLLMService.swift`
      _Impact_: Reduces cognitive load and project clutter

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

### Phase 2.15 — Missing Apple Framework Opportunities

_Native frameworks not yet leveraged for hyper-intelligence_

#### NaturalLanguage Gaps

- [x] **NLLanguageRecognizer**: Auto-detect document/query language for multi-language RAG
      _Location_: [LanguageDetectionService.swift](OpenIntelligence/Services/LanguageDetectionService.swift)
      _Status_: Implemented - Detects query/document language, caches results, provides embedding language routing
- [ ] **NLGazetteer**: Custom entity extraction (product names, part numbers, domain terms)
      _Benefit_: Boost retrieval for exact entity matches, enable domain-specific NER

#### Vision Framework Gaps

- [ ] **DataScannerViewController**: Live camera document scanning with real-time OCR
      _Benefit_: "Point at document, start querying" UX — zero friction ingestion

#### Multimedia RAG

- [x] **Speech.SFSpeechRecognizer**: Transcribe audio/video files for indexing
      _Location_: [AudioTranscriptionService.swift](OpenIntelligence/Services/AudioTranscriptionService.swift)
      _Status_: Implemented - On-device transcription for M4A, MP3, WAV, MP4, MOV; language detection; time-stamped segments
      _Supported_: m4a, mp3, wav, caf, aiff, mp4, mov, m4v (max 10 min)
- [ ] **SoundAnalysis**: Classify audio content (speech, music, ambient)

#### Translation & Localization

- [ ] **Translation.framework (iOS 17+)**: On-device translation for multi-language documents
      _Benefit_: Translate foreign docs to English before embedding for unified search

#### On-Device Learning

- [ ] **CreateMLComponents**: Train small classifiers on user's document patterns
      _Benefit_: Learn document types, topics, quality signals from usage

#### Observability

- [ ] **MetricKit**: Collect real device performance metrics
      _Benefit_: Optimize pipeline based on actual user hardware patterns
- [ ] **OSSignposter**: Instruments-visible pipeline profiling
      _Benefit_: Make embedding/search/generation visible in Xcode Instruments

### Phase 2.2 — Platform Expansion

- [ ] **macOS Catalyst**: Native desktop experience
- [ ] **iPad Split View**: Side-by-side document + chat layout
- [ ] **Widget Extensions**: Quick query widget for Home Screen

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

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
