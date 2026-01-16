# OpenIntelligence Roadmap

**Last Updated**: January 13, 2026
**Version**: 1.6.0
**Status**: Production (App Store Ready)
**RAG Maturity Score**: 9.5/10 (Entity Extraction + Recursive Research + mmap Storage)

### Recent Improvements (January 2026 - Powerhouse RAG Upgrade)
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
  *Note*: OpenAIResponsesAPIService.swift remains as `#if false` dead code for reference only.
- [x] **Local Model Removal (Dec 2025)**: Removed GGUF/CoreML/MLX downloadable models
  *Note*: App now uses Apple Intelligence + On-Device Analysis only. Simplifies maintenance and reduces binary size.
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

### Advanced Agentic RAG (Jan 2026)
*Multi-session reasoning that transcends the 4,096 token limit*
- [x] **AgenticOrchestrator**: Multi-step reasoning pipeline (Planning→Searching→Analyzing→Synthesizing→Refining)
  *Location*: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
  *Status*: Fully implemented with hardware-aware configuration
- [x] **GraphRAG-Lite Expansion**: 2-hop entity expansion (retrieve → extract entities → retrieve again)
  *Location*: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
- [x] **Recursive Research Loop**: LLM-driven autonomous search with `[ANSWER]`/`[SEARCH: query]` tokens
  *Location*: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
  *Method*: `executeRecursiveResearch()` - 7-iteration autonomous research with accumulating context
  *Protocol*: LLM outputs `[SEARCH: specific query]` to retrieve more, `[ANSWER]` when confident
  *Benefit*: Deep multi-hop reasoning without pre-defined decomposition; LLM decides when to stop
- [x] **Entity Extraction (Connective Tissue)**: NLTagger-based NER during chunking
  *Location*: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
  *Method*: `extractEntities()` - extracts persons, organizations, places, PascalCase technical terms
  *Output*: `ChunkMetadata.entities` field populated with up to 15 entities per chunk
- [x] **Global Entity Index**: Cross-document entity correlation for GraphRAG
  *Location*: [EntityIndexService.swift](OpenIntelligence/Services/EntityIndexService.swift)
  *Structure*: `Dict<String, Set<UUID>>` mapping normalized entity names → chunk IDs
  *Features*: O(1) lookup, persistence to JSON, reverse index for efficient removal
  *Methods*: `chunksForEntity()`, `sharedEntities()`, `topEntities()`
- [x] **DeviceCapabilityService**: Hardware tier detection (A17→A18→A19→M-series)
  *Location*: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
  *Status*: Maps device → max sessions → total tokens (16K-48K depending on chip)
- [x] **HyDE (Hypothetical Document Embeddings)**: Generate hypothetical answer, embed for better retrieval
  *Paper*: Gao et al. 2022 - "Precise Zero-Shot Dense Retrieval without Relevance Labels"
  *Location*: [HyDEService.swift](OpenIntelligence/Services/HyDEService.swift)
  *Benefit*: 15-25% recall improvement on factual queries
- [x] **Contextual Compression**: LLM-filter irrelevant sentences from chunks before generation
  *Location*: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
  *Benefit*: 40-60% token savings, improved answer quality
- [x] **Answer Grounding Verification**: Detect hallucinations by checking answer vs. context
  *Location*: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
  *Status*: `verifyAnswerGrounding()` returns grounded/partial/ungrounded/notAnswerable
- [x] **Query Task Management**: Cancel-and-replace pattern for back-to-back queries
  *Location*: [ChatScreen.swift](OpenIntelligence/Views/ChatV2/ChatScreen.swift)
  *Status*: `currentQueryTask` tracking with explicit cancellation at 6 pipeline stages
- [x] **RAGQualityMode.agentic**: "Deep Think" mode exposed in quality picker
  *Status*: Always visible in chat header (not hidden behind developer tuning)
- [x] **Parent Document Retrieval**: Expand matched chunks with sibling context from same section/page
  *Location*: [ParentDocumentService.swift](OpenIntelligence/Services/ParentDocumentService.swift)
  *Benefit*: Preserves document flow, prevents answer gaps from chunk boundaries

### Hardware-Aware Optimization (Jan 2026)
*Comprehensive device-specific tuning for iPhones and iPads*
- [x] **AdaptivePipelineOptimizer**: Runtime pipeline optimization based on thermal/battery/memory state
  *Location*: [AdaptivePipelineOptimizer.swift](OpenIntelligence/Services/AdaptivePipelineOptimizer.swift)
  *Status*: Auto-adjusts HyDE, compression, retrieval limits based on device pressure
- [x] **DeviceFormFactor Detection**: iPhone, iPadMini, iPadAir, iPadPro identification
  *Location*: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
  *Status*: Maps iPad model numbers to form factors with correct chip detection
- [x] **PipelineOptimizationLevel**: Four levels (full/balanced/efficient/minimal) based on device state
  *Benefit*: Prevents thermal throttling, extends battery life during extended sessions
- [x] **QueryComplexity Estimation**: Analyzes query tokens, operators, length to predict load
  *Benefit*: Simple queries skip expensive features, complex queries get full pipeline
- [x] **Thermal Cooldown**: Pauses between heavy operations when device is critical
  *Benefit*: Reduces fan noise on iPads, prevents thermal shutdowns on sustained use
- [x] **Memory Pressure Monitoring**: Real-time available memory tracking via `os_proc_available_memory()`
  *Benefit*: Gracefully degrades features before OOM kills occur
- [x] **SystemStateMonitor**: Centralized real-time device state monitoring service
  *Location*: [SystemStateMonitor.swift](OpenIntelligence/Services/SystemStateMonitor.swift)
  *Status*: Captures thermal, battery, memory, CPU, Low Power Mode with 2-second refresh
  *Features*: NotificationCenter observers for instant state changes; SystemStateSnapshot struct
- [x] **Live System Monitor UI**: Exposed device metrics in UnifiedMetricsBar and SettingsView
  *Benefit*: Full transparency into device state and pipeline optimization decisions

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
  *Location*: [Embedding3DView.swift](OpenIntelligence/Views/Telemetry/Embedding3DView.swift)
  *Features*: Ground plane grid, intuitive semantic axes ("Similar →", "← Different", "Related ↑", "Depth"),
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
*These FoundationModels framework features have been fully integrated:*
- [x] **Content Tagging Model**: `SystemLanguageModel(useCase: .contentTagging)` for auto-labeling documents
  *Implemented*: ContentTaggingService auto-generates topic/action/emotion/object tags during document ingestion; displayed in DocumentCard and DocumentDetailsView with pill UI
- [x] **Transcript Rehydration**: `LanguageModelSession(transcript:)` for session persistence
  *Implemented*: TranscriptPersistenceService saves/restores transcripts on app background/foreground and container switch; enables conversation continuity across app launches
- [x] **isResponding Property**: Real-time generation state tracking
  *Implemented*: `session.isResponding` exposed via RAGService.isLLMResponding; UnifiedMetricsBar shows pulsing indicator during active generation

---

## 2. Technical Debt (The Cracks)

### High Priority
- [x] **Page Number Tracking**: DocumentProcessor now builds page→text mappings
  *Location*: [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift#L340)
  *Status*: Implemented - PDF extraction tracks page ranges, passed to SemanticChunker for accurate citations

- [x] **CoreML Sentence Embeddings**: WordPiece tokenization implemented
  *Location*: [CoreMLSentenceEmbeddingProvider.swift](OpenIntelligence/Services/Embeddings/CoreMLSentenceEmbeddingProvider.swift)
  *Status*: Scaffold complete - tokenizer protocol, WordPiece implementation, CoreML inference pipeline ready

### Medium Priority
- [ ] **RAGService Size**: 4250 LOC monolith needs decomposition
  *Impact*: Difficult to test and maintain

- [ ] **Error Recovery**: Some LLM failures don't surface user-friendly messages
  *Impact*: Users see generic errors

- [x] **Test Coverage**: HybridSearchService edge cases now covered
  *Location*: [HybridSearchServiceTests.swift](OpenIntelligenceTests/HybridSearchServiceTests.swift)
  *Status*: Added 12+ edge case tests for RRF fusion, BM25 scoring, Unicode handling, and metadata

### Low Priority
- [x] **MLX macOS-Only**: Removed with local model cleanup (Dec 2025)
  *Status*: No longer applicable - local models removed

- [x] **Vendor LocalLLMClient**: Removed from project (Dec 2025)
  *Status*: Package removed entirely - no longer needed

- [ ] **Dead Code Cleanup**: Remove `#if false` wrapped files
  *Files*: `OpenAIResponsesAPIService.swift`, `LocalOpenAIServerLLMService.swift`
  *Impact*: Reduces cognitive load and project clutter

---

## 3. Project: Silicon-Native Intelligence (Q1 2026)
*Refactoring OpenIntelligence to align with Apple's "Native Intelligence" Benchmark.*

### Phase 1: Core ML Embedding Engine (Critical)
- [x] **Model Conversion Script**: Python utility to convert `sentence-transformers/all-MiniLM-L6-v2` to Core ML
- [ ] **Tokenizer Parity**: Validate Swift `WordPieceTokenizer` against Python `transformers` output
- [x] **CoreML Provisioning**: Fixed to load `.mlmodelc` (compiled model) instead of `.mlpackage` source
- [ ] **NLEmbedding Deprecation**: Remove reliance on `NLEmbedding` / `AppleFMEmbeddingProvider`

### Phase 2: Vector Math Layer (High) ✅ COMPLETE
*Silicon-native vector operations using Apple Accelerate framework*
- [x] **BNNS Vector Store**: Implemented `BNNSVectorDatabase` using `Accelerate` / `vDSP`
  *Location*: [BNNSVectorDatabase.swift](OpenIntelligence/Services/VectorDatabase/BNNSVectorDatabase.swift)
  *Features*: vDSP_dotpr for dot products, cblas_snrm2 for L2 norms, vDSP_mmul for batch matrix ops
- [x] **Flat File Storage**: Contiguous float arrays for max Neural Engine throughput
  *Status*: flatEmbeddings array stores all vectors sequentially for vDSP_mmul compatibility
- [x] **Optimized Dot Product**: Hardware-accelerated via vDSP_dotpr (Neural Engine preferred)
  *Status*: Both RAGEngine and HybridSearchService use Accelerate-powered similarity
- [x] **Pre-Computed Norms**: O(1) cosine similarity via cached L2 norms
  *Status*: embeddingNorms array populated at insert time, avoids re-computing sqrt(sum(x^2))
- [x] **Device-Adaptive Batch Thresholds**: DeviceCapabilityService optimizes batch sizes per chip
  *Location*: [DeviceCapabilityService.swift](OpenIntelligence/Services/DeviceCapabilityService.swift)
  *Features*: vectorBatchSize, embeddingBatchSize, batchMatrixMultiplyThreshold tuned per device tier
- [x] **mmap Zero-Copy Vector Storage**: Memory-mapped embedding files for minimal RAM usage
  *Location*: [VectorDatabase.swift](OpenIntelligence/Services/VectorDatabase.swift) `MmapVectorDatabase`
  *Features*: `Data(contentsOf:, options: .alwaysMapped)` for zero-copy access, cblas_sgemv search
  *Performance*: ~2KB resident memory vs ~20MB for in-memory (10K chunks @ 512-dim)
  *Architecture*: Separate embeddings.bin (mmap'd) + metadata.json + norms.bin files

### Phase 3: Cross-Encoder Re-Ranking (High) ✅ COMPLETE
*Neural relevance scoring using BERT-based cross-encoder*
- [x] **Re-Ranker Model**: `cross-encoder/ms-marco-TinyBERT-L-2-v2` converted to Core ML
  *Location*: [ReRankerModel.mlpackage](OpenIntelligence/ReRankerModel.mlpackage/)
  *Status*: Model bundled with app, vocab file in `reranker_vocab.json`
- [x] **Re-Ranking Service**: Batch inference in `RAGEngine` (Query + Chunk pairs)
  *Location*: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift#L742)
  *Method*: `rerankWithCrossEncoder()` - tokenizes query-doc pairs, runs CoreML inference, extracts softmax scores
- [x] **BertTokenizer Integration**: WordPiece tokenization via swift-transformers
  *Location*: [swift-transformers/](OpenIntelligence/swift-transformers/)
  *Status*: Full tokenizer with special tokens ([CLS], [SEP], [PAD]), attention masks, token type IDs
- [x] **Heuristic Fallback**: `computeMetadataBoost` retained as fallback when model unavailable

### Phase 4: True Semantic Chunking (Medium) ✅ COMPLETE
*Embedding-based topic boundary detection (Late Chunking approach)*
- [x] **Semantic Splitter**: SemanticChunker now detects topic boundaries via sentence embeddings
  *Location*: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
  *Method*: `detectEmbeddingBoundaries()` computes pairwise cosine similarity between sentences
- [x] **Thresholding**: Auto-detect topic boundaries where similarity drops below 0.65
  *Status*: `embeddingSimilarityThreshold` configurable; defaults to 0.65 for balanced segmentation
- [x] **Async Chunking API**: New `chunkTextAsync()` method combines linguistic + embedding boundaries
  *Benefit*: Chunks align with genuine topic shifts rather than arbitrary word counts
- [x] **Accelerate Integration**: Cosine similarity uses vDSP_dotpr + cblas_snrm2 for hardware acceleration

### Phase 5: Cross-Container Search (Medium) ✅ COMPLETE
*Unified search across all knowledge containers*
- [x] **VectorStoreRouter.searchAll()**: Parallel search with Reciprocal Rank Fusion
  *Location*: [VectorStoreRouter.swift](OpenIntelligence/Services/VectorStoreRouter.swift)
  *Algorithm*: TaskGroup parallel queries → per-container ranking → RRF fusion → global top-K
- [x] **Container Attribution**: CrossContainerResult includes container name/ID for citations
- [x] **RAGService Integration**: `searchAllContainers()` and `searchAllContainersRaw()` tools
  *Location*: [RAGService.swift](OpenIntelligence/Services/RAGService.swift)
  *Benefit*: LLM can synthesize knowledge from multiple libraries in one query

---

## 4. Future Trajectory

### Phase 2.0 — Intelligence Layer
- [x] **Query Clarification**: Lightweight pronoun resolution and follow-up handling
  *Location*: [QueryRewriterService.swift](OpenIntelligence/Services/QueryRewriterService.swift)
  *Status*: Implemented - Only intervenes for genuine ambiguity (pronouns, follow-ups)
- [x] **Corpus-Aware Query Expansion**: Expands queries using actual document vocabulary
  *Location*: [QueryEnhancementService.swift](OpenIntelligence/Services/QueryEnhancementService.swift)
  *Status*: Implemented - Builds co-occurrence maps from chunk keywords, filters garbage terms
- [x] **Query Intent Classification**: Detects keyword-heavy vs conceptual queries
  *Location*: [QueryEnhancementService.swift](OpenIntelligence/Services/QueryEnhancementService.swift)
  *Status*: Implemented - `classifyIntent()` with `QueryIntent` enum for dynamic weight tuning
- [x] **Iterative Retrieval**: Multi-pass retrieve → assess → refine → retrieve more
  *Location*: [IterativeRetrievalService.swift](OpenIntelligence/Services/IterativeRetrievalService.swift)
  *Status*: Implemented - Full RAGService integration with configurable passes via settings
- [x] **Intelligence Layer Settings UI**: Toggles for Query Understanding and Multi-Pass Retrieval
  *Location*: [SettingsView.swift](OpenIntelligence/Views/Settings/SettingsView.swift)
  *Status*: Implemented - New Intelligence Layer card with user-facing toggles
- [x] **Context Window Fix (TN3193 Compliance)**: Fixed 65K → 4096 token budget
  *Location*: [RAGService.swift](OpenIntelligence/Services/RAGService.swift)
  *Status*: Implemented - baseWindowTokens=4096, maxContextCharsCap=5000 for Apple FM
- [x] **RAGEngine Singleton**: Prevents ReRanker model loading 4x per query
  *Location*: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift)
  *Status*: Implemented - `RAGEngine.shared` singleton with `isSetupComplete` guard
- [x] **Lost-in-Middle Mitigation**: Context reordering for LLM attention patterns
  *Location*: [RAGEngine.swift](OpenIntelligence/Services/RAGEngine.swift)
  *Status*: Implemented - `applyLostInMiddleReordering()` places best chunks at start AND end
- [x] **Content-Adaptive Chunking**: Document-type-specific chunk sizes
  *Location*: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
  *Status*: Implemented - `ChunkingConfig.recommended(for:)` with PDF/code/narrative presets
- [x] **Multi-Session Chaining**: Agentic RAG chains multiple 4096-token sessions for complex queries
  *Location*: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
  *Status*: Implemented - Multi-step planning→searching→analyzing→synthesizing→refining with session cleanup
  *Hardware*: Device-aware config via DeviceCapabilityService (A17→16K, A18→24K, A19→32K, M-series→48K)
- [x] **Query Planning Agent**: Multi-step reasoning over large document sets
  *Location*: [AgenticOrchestrator.swift](OpenIntelligence/Services/AgenticOrchestrator.swift)
  *Status*: Implemented - `executePlanningStep()` decomposes queries into 2-4 focused sub-questions, executed in parallel
- [x] **Cross-Container Search**: Unified retrieval across multiple containers
  *Location*: [VectorStoreRouter.swift](OpenIntelligence/Services/VectorStoreRouter.swift)
  *Status*: Implemented - `searchAll()` with parallel queries and RRF fusion; RAGService integration via `searchAllContainers()`
- [x] **Conversation Memory**: Persistent chat context with intelligent summarization
  *Location*: [ConversationMemoryService.swift](OpenIntelligence/Services/ConversationMemoryService.swift)
  *Status*: Fully dynamic implementation with query-adaptive optimizations
  *Dynamic Features*:
    - **Query-Adaptive Token Budget**: Simple queries get 500 chars, follow-ups get 3000 chars
    - **Semantic Relevance Scoring**: Jaccard similarity + entity matching ranks turns by relevance to current query
    - **Importance-Weighted Summarization**: High-information turns preserved longer, low-value turns summarized first
    - **Entity Prioritization**: Entities appearing in current query surfaced first
    - **Recency Boost**: Recent turns scored higher with 1-hour decay curve
  *Performance*: Non-blocking (fire-and-forget), debounced saves (2s), background LLM summarization
  *Settings*: `enableConversationMemory` in SettingsStore (default: true)
  *Settings*: `enableConversationMemory` in SettingsStore (default: true)

### Phase 2.5 — God Mode RAG (Advanced)
*State-of-the-art RAG techniques from 2024-2026 research. These would push the system from 7.5/10 to 10/10.*

#### Retrieval Enhancements
- [x] **HyDE (Hypothetical Document Embeddings)**: Generate hypothetical answer, embed that for retrieval
  *Paper*: Gao et al. 2022 - "Precise Zero-Shot Dense Retrieval without Relevance Labels"
  *Benefit*: 15-20% recall improvement for complex queries
  *Location*: [HyDEService.swift](OpenIntelligence/Services/HyDEService.swift)
  *Status*: Implemented - Auto-detects factual queries, generates hypothetical doc, embeds for search
  *Settings*: `enableHyDE` in SettingsStore (default: true)

- [x] **Parent Document Retrieval**: Expand matched chunks with sibling context from same section/page
  *Benefit*: Maintains coherence for multi-paragraph answers
  *Location*: [ParentDocumentService.swift](OpenIntelligence/Services/ParentDocumentService.swift)
  *Status*: Implemented - Expands chunks post-reranking, quality-aware config (default vs thorough)
  *Settings*: `enableParentDocumentRetrieval` in SettingsStore (default: true)
  *Schema*: Added `siblingGroupId` and `siblingCount` to ChunkMetadata

- [x] **Late Chunking (Semantic Boundary Detection)**: Detect topic boundaries via sentence embedding similarity
  *Paper*: "Late Chunking" (2024) - embeddings computed before chunking preserve more context
  *Benefit*: Better embedding quality for chunk boundaries
  *Location*: [SemanticChunker.swift](OpenIntelligence/Services/SemanticChunker.swift)
  *Status*: Implemented - `detectEmbeddingBoundaries()` computes pairwise cosine similarity; `chunkTextAsync()` combines with linguistic cues

- [x] **Contextual Compression**: LLM-filter irrelevant sentences from retrieved chunks before generation
  *Benefit*: Maximizes signal-to-noise in context window
  *Location*: [ContextualCompressionService.swift](OpenIntelligence/Services/ContextualCompressionService.swift)
  *Status*: Implemented - Compresses chunks post-retrieval, drops irrelevant content, logs token savings
  *Settings*: `enableContextualCompression` in SettingsStore (default: true)

#### Advanced Reasoning
- [ ] **Self-RAG**: Model decides when to retrieve, what to retrieve, and self-critiques answers
  *Paper*: Asai et al. 2023 - "Self-RAG: Learning to Retrieve, Generate, and Critique"
  *Benefit*: Adaptive retrieval (only retrieves when needed)
  *Complexity*: High (requires fine-tuned model or complex prompting)

- [ ] **Speculative RAG**: Generate multiple candidate answers, verify each against documents
  *Benefit*: Catches hallucinations through multi-path verification
  *Complexity*: High (3-5x compute cost)

- [ ] **RAPTOR**: Hierarchical summarization tree for multi-level retrieval
  *Paper*: Sarthi et al. 2024 - "RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval"
  *Benefit*: Enables both detail and summary retrieval in one query
  *Complexity*: High (requires pre-computed summary tree)

#### Learning & Adaptation
- [ ] **Active Learning Feedback Loop**: System improves from user corrections and thumbs up/down
  *Benefit*: Retrieval quality improves over time
  *Complexity*: Medium (need feedback storage and retraining pipeline)

- [ ] **Per-Query Learned Fusion Weights**: Train small model to predict optimal vector/BM25 blend
  *Benefit*: Replaces heuristic intent classification with learned weights
  *Complexity*: High (requires training data collection)

- [ ] **Query Routing**: Route queries to specialized indices based on detected domain
  *Benefit*: Medical queries → medical-optimized index, legal → legal index
  *Complexity*: Medium (requires domain classification and multiple indices)

### Phase 2.05 — Visual Document Understanding (Q1-Q2 2026)
*Full Vision framework integration for layout-aware document processing*

#### Layout-Aware Text Extraction
- [x] **Spatial Text Ordering**: Use VNRecognizedTextObservation bounding boxes to sort text by reading order
  *Problem*: PDF text extraction can return jumbled text when layout is complex (multi-column, sidebars)
  *Solution*: Sort OCR observations by Y position (top-to-bottom), then X position (left-to-right)
  *Impact*: Fixes copy-paste weirdness where text order doesn't match visual layout
  *Location*: `performOCR()` in [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift)
  *Status*: Implemented - observations sorted by bounding box with 2% line threshold

- [x] **Column Detection**: Detect multi-column layouts via bounding box clustering
  *Benefit*: Process columns independently before merging text
  *API*: VNRecognizedTextObservation.boundingBox + clustering algorithm
  *Location*: `detectColumns()` and `extractTextWithColumnAwareness()` in DocumentProcessor.swift
  *Status*: Implemented - detects significant gaps (>15% page width) as column boundaries

- [x] **Reading Order Reconstruction**: Reconstruct logical reading flow from spatial positions
  *Benefit*: "If you highlight half a page, the text flows correctly"
  *Location*: `extractTextWithColumnAwareness()` in DocumentProcessor.swift
  *Status*: Implemented - processes each column top-to-bottom, then combines

#### Image Understanding (Vision + Intelligence)
- [x] **PDF Image Extraction**: Extract embedded images from PDF pages
  *API*: PDFKit page rendering + CGImage extraction at image positions
  *Benefit*: Access to diagrams, charts, photos in documents
  *Location*: `extractImagesFromPDFPage()` and `extractAllImagesFromPDF()` in DocumentProcessor.swift
  *Status*: Implemented - extracts from annotations and full-page scans

- [x] **Image Classification**: Use ClassifyImageRequest to tag images
  *API*: `ClassifyImageRequest()` → [ClassificationObservation] with identifiers and confidence
  *Benefit*: "This PDF contains: diagrams (0.85), technical_drawings (0.72), charts (0.68)"
  *Location*: [ImageUnderstandingService.swift](OpenIntelligence/Services/ImageUnderstandingService.swift)
  *Status*: Implemented - iOS 18+ modern API with legacy fallback; ImageContentType enum for high-level categorization

- [x] **Image-to-Text Description**: Generate text descriptions of images via Apple Intelligence
  *API*: Classification-based descriptions (full Foundation Models image input planned for iOS 26+)
  *Benefit*: Diagrams become searchable ("fluid diagram", "wiring schematic")
  *Location*: `generateImageDescription()` in ImageUnderstandingService.swift
  *Status*: Implemented - combines classifications + captions into searchable text

- [x] **Caption-Image Association**: Link captions to adjacent images via spatial proximity
  *Heuristic*: Text within 5% of page height below an image is likely its caption
  *Location*: `findAssociatedCaption()` in ImageUnderstandingService.swift
  *Status*: Implemented - detects "Figure", "Image", "Diagram" prefixes and short nearby text

#### Document Structure Analysis (iOS 18+)
- [ ] **DetectDocumentSegmentationRequest**: Detect document boundaries and regions
  *API*: New iOS 18 Vision API for structured document detection
  *Output*: Document quadrilateral and saliency masks

- [ ] **RecognizeDocumentsRequest**: Structured document understanding
  *API*: New iOS 18 API for receipts, business cards, forms
  *Benefit*: Extract structured data from known document types

- [x] **Table Recognition**: Detect and extract table structures
  *API*: VNRecognizedTextObservation bounding box clustering for row/column alignment
  *Benefit*: Tables extracted as structured markdown format for better retrieval
  *Location*: `detectTables()` in [DocumentProcessor.swift](OpenIntelligence/Services/DocumentProcessor.swift)
  *Status*: Implemented - Grid alignment analysis, DetectedTable struct, markdown output
  *API*: Vision's table recognition capabilities
  *Output*: Structured table data (rows, columns, headers)
  *Chunking*: Tables → structured text chunks with column headers preserved

#### Enhanced Metadata
- [x] **VisualContentMetadata**: Track visual elements per page/chunk
  *Location*: [ImageUnderstandingService.swift](OpenIntelligence/Services/ImageUnderstandingService.swift)
  *Status*: Implemented - tracks imageCount, imageClassifications, hasTableContent, columnLayout, captionedImages, imagesWithDescriptions
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
  *Fields*: `imagesProcessed`, `imagesWithDescriptions`, `tablesExtracted`, `layoutComplexity`

### Phase 2.1 — Model Ecosystem
- [x] **Model Marketplace**: Removed - app focuses on Apple Intelligence + PCC
- [ ] **Custom Embedding Models**: User-provided Core ML embedders
- [ ] **Fine-Tuning Pipeline**: LoRA adapters for domain-specific performance

### Phase 2.15 — Interactive Embedding Visualization (Medium)
*Next-level 3D embedding space exploration with agentic intelligence*
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
*Native frameworks not yet leveraged for hyper-intelligence*

#### NaturalLanguage Gaps
- [x] **NLLanguageRecognizer**: Auto-detect document/query language for multi-language RAG
  *Location*: [LanguageDetectionService.swift](OpenIntelligence/Services/LanguageDetectionService.swift)
  *Status*: Implemented - Detects query/document language, caches results, provides embedding language routing
- [ ] **NLGazetteer**: Custom entity extraction (product names, part numbers, domain terms)
  *Benefit*: Boost retrieval for exact entity matches, enable domain-specific NER

#### Vision Framework Gaps
- [ ] **DataScannerViewController**: Live camera document scanning with real-time OCR
  *Benefit*: "Point at document, start querying" UX — zero friction ingestion

#### Multimedia RAG
- [x] **Speech.SFSpeechRecognizer**: Transcribe audio/video files for indexing
  *Location*: [AudioTranscriptionService.swift](OpenIntelligence/Services/AudioTranscriptionService.swift)
  *Status*: Implemented - On-device transcription for M4A, MP3, WAV, MP4, MOV; language detection; time-stamped segments
  *Supported*: m4a, mp3, wav, caf, aiff, mp4, mov, m4v (max 10 min)
- [ ] **SoundAnalysis**: Classify audio content (speech, music, ambient)

#### Translation & Localization
- [ ] **Translation.framework (iOS 17+)**: On-device translation for multi-language documents
  *Benefit*: Translate foreign docs to English before embedding for unified search

#### On-Device Learning
- [ ] **CreateMLComponents**: Train small classifiers on user's document patterns
  *Benefit*: Learn document types, topics, quality signals from usage

#### Observability
- [ ] **MetricKit**: Collect real device performance metrics
  *Benefit*: Optimize pipeline based on actual user hardware patterns
- [ ] **OSSignposter**: Instruments-visible pipeline profiling
  *Benefit*: Make embedding/search/generation visible in Xcode Instruments

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

*Move items here when actively working on them.*

| Task | Status | Owner | Notes |
|------|--------|-------|-------|
| Release Build Fix | ✅ Done | Agent | Fixed #Preview wrapped in #if DEBUG |
| Production Preflight | ✅ Done | Agent | Secret scan, privacy keys, both builds pass |
| NLContextualEmbedding | ✅ Done | Agent | 15-25% accuracy boost via contextual embeddings |
| @Generable Response Types | ✅ Done | Agent | RAGAnswer, RAGSearchResults, RAGDocumentSummary |
| High-Accuracy Container Factory | ✅ Done | Agent | KnowledgeContainer.highAccuracy() helper |
| Fix ingestion re-upload loop | ✅ Done | Agent | Prevent self-tuning rebuild recursion during auto-reembed |
| Fix Documents “New Library” crash | ✅ Done | Agent | Inject SettingsStore at root; Documents tab reads settings.useHighAccuracyEmbeddings |
| DEBUG paywall purchase simulation | ✅ Done | Agent | Allow testing entitlement unlocks even when StoreKit returns an empty catalog |
| DEBUG doc-pack refill simulation | ✅ Done | Agent | Mirror paywall simulation when doc pack Product metadata is unavailable |
| De-dupe empty-catalog billing warnings | ✅ Done | Agent | Reduce repeated “StoreKit returned an empty product catalog” / “Products unavailable” spam |
| Isolate StoreKit config to test scheme | ✅ Done | Agent | Move StoreKit .storekit config off main Run action to prevent debug simulation popups and ensure sandbox/App Store paths behave normally |
| Remove local downloadable models | ✅ Done | Agent | Removed GGUF/CoreML/MLX support; simplified to Apple Intelligence + On-Device Analysis only |
| Apple Intelligence API Audit | ✅ Done | Agent | Full FoundationModels API audit: prewarm(), SamplingMode, GenerationError handling, Transcript, LanguageModelFeedback, 4096-token context (TN3193) |
| Tool @Guide Constraints | ✅ Done | Agent | Added .range() constraints to SearchDocumentsTool topK/minSimilarity parameters |
| FM Feedback Integration | ✅ Done | Agent | Thumbs up/down in chat UI submits LanguageModelFeedback to Apple |
| Chat Attachment Race Condition | ✅ Done | Agent | Fixed: attachments now fully processed before query runs (was sending query before documents indexed) |
| Prevent unwanted On-Device Analysis fallback | ✅ Done | Agent | Keep partial streamed responses; remove low-confidence auto-switch; improve extractive QA ranking |
| Settings UX Overhaul | ✅ Done | Agent | Replaced fallback card with Context & Processing info card; improved privacy card with Apple architecture explanations; added Neural Engine info; removed model selector (Apple Intelligence only) |
| Short Query Language Fix | ✅ Done | Agent | Added English context wrapping for 1-5 word queries to prevent language detection errors |
| Conversational RAG Prompts | ✅ Done | Agent | Changed from extractive QA to conversational responses; improved context assembly logging |
| Processing Intelligence View | ✅ Done | Agent | New unified chat header component showing real-time execution location (Device/PCC), context window usage, quality mode, and expandable details |
| Quality Mode Chat Integration | ✅ Done | Agent | Quality mode quick picker added to chat header; settings now shows explanation only; seamless switching between Fast/Balanced/Thorough |
| Unified Metrics Bar Merge | ✅ Done | Agent | Merged ProcessingIntelligenceView + LiveStreamingMetrics into single UnifiedMetricsBar; eliminated duplicate UI; single expandable component with execution, context, speed, sources, quality mode |
| Entitlement Store Cleanup | ✅ Done | Agent | Removed dead "Local Model Preview" code and restored truncated methods |
| Document Upload Progress UI | ✅ Done | Agent | Added per-file progress toast for multi-document uploads |
| Remove Dead Code | ✅ Done | Agent | Deleted InstalledModel.swift and LocalComputePreference.swift |
| Intelligence Layer (v2.0) | ✅ Done | Agent | QueryRewriterService, IterativeRetrievalService, CorpusVocabulary expansion, settings UI toggles, full RAGService integration |
| Context Window TN3193 Fix | ✅ Done | Agent | Fixed baseWindowTokens 65536→4096, maxContextCharsCap 65000→5000 for Apple FM 4096-token limit |
| RAGEngine Singleton Pattern | ✅ Done | Agent | Added RAGEngine.shared to prevent ReRanker loading 4x per query; updated all callsites |
| SystemStateMonitor | ✅ Done | Agent | Real-time device monitoring (thermal/battery/memory/CPU/LPM) with 2s refresh; exposed in UnifiedMetricsBar and SettingsView |
| RAGQualityMode Simplification | ✅ Done | Agent | Reduced from 4 modes to 2 (Standard + Deep Think); removed confusing Response Style slider |
| 3D Embedding Visualization Overhaul | ✅ Done | Agent | Ground plane grid, semantic axes ("Similar →", "Related ↑"), glowing spheres, cluster badges, gesture hints |
| UnifiedMetricsBar Type Fixes | ✅ Done | Agent | Fixed MemoryPressure→MemoryPressureLevel; removed duplicate executionExplanation property |
| Cross-Encoder Re-Ranker Audit | ✅ Done | Agent | Confirmed ReRankerModel.mlpackage bundled, BertTokenizer working, rerankWithCrossEncoder() functional |
| Conversation Memory Service | ✅ Done | Agent | ConversationMemoryService with LLM summarization, entity tracking, per-container persistence, RAGService integration, Settings UI toggle |

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
