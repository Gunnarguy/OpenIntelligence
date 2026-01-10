# OpenIntelligence Roadmap

**Last Updated**: January 2026
**Version**: 1.1.0
**Status**: Production (App Store Ready)

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

### Phase 2: Vector Math Layer (High)
- [ ] **BNNS Vector Store**: Implement `BNNSVectorDatabase` using `Accelerate` / `vDSP`
- [ ] **Flat File Storage**: Replace `VecturaKit` abstractions with contiguous float arrays (`UnsafeBufferPointer`)
- [ ] **Optimized Dot Product**: Use `cblas_sgemm` or `vDSP_desamp` for neural engine acceleration

### Phase 3: Cross-Encoder Re-Ranking (High)
- [ ] **Re-Ranker Model**: Convert `cross-encoder/ms-marco-TinyBERT-L-2-v2` to Core ML
- [ ] **Re-Ranking Service**: Implement batch inference in `RAGEngine` (Query + Chunk pairs)
- [ ] **Heuristic Removal**: Delete `computeMetadataBoost` and rule-based scoring

### Phase 4: True Semantic Chunking (Medium)
- [ ] **Semantic Splitter**: Update `SemanticChunker` to use dot-product similarity between sentences
- [ ] **Thresholding**: Auto-detect topic boundaries based on embedding distance

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
- [ ] **Multi-Session Chaining**: Agentic RAG chains multiple 4096-token sessions for complex queries
  *Design*: Model uses tools (SearchDocumentsTool, etc.) to navigate across multiple sessions
- [ ] **Query Planning Agent**: Multi-step reasoning over large document sets
- [ ] **Cross-Container Search**: Unified retrieval across multiple containers
- [ ] **Conversation Memory**: Persistent chat context with summarization

### Phase 2.5 — God Mode RAG (Advanced)
*State-of-the-art RAG techniques from 2024-2026 research. These would push the system from 7.5/10 to 10/10.*

#### Retrieval Enhancements
- [ ] **HyDE (Hypothetical Document Embeddings)**: Generate hypothetical answer, embed that for retrieval
  *Paper*: Gao et al. 2022 - "Precise Zero-Shot Dense Retrieval without Relevance Labels"
  *Benefit*: 15-20% recall improvement for complex queries
  *Complexity*: Medium (requires LLM call before search)

- [ ] **Parent Document Retrieval**: Store full documents, retrieve child chunks but return surrounding context
  *Benefit*: Maintains coherence for multi-paragraph answers
  *Complexity*: Medium (schema change for parent-child relationships)

- [ ] **Late Chunking**: Embed entire document first, then segment embeddings post-hoc
  *Paper*: "Late Chunking" (2024) - embeddings computed before chunking preserve more context
  *Benefit*: Better embedding quality for chunk boundaries
  *Complexity*: High (architecture change to embedding pipeline)

- [ ] **Contextual Compression**: LLM-filter irrelevant sentences from retrieved chunks before generation
  *Benefit*: Maximizes signal-to-noise in context window
  *Complexity*: Medium (adds latency, but improves quality)

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

### Phase 2.1 — Model Ecosystem
- [x] **Model Marketplace**: Removed - app focuses on Apple Intelligence + PCC
- [ ] **Custom Embedding Models**: User-provided Core ML embedders
- [ ] **Fine-Tuning Pipeline**: LoRA adapters for domain-specific performance

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

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
