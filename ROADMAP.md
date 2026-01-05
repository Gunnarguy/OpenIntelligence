# OpenIntelligence Roadmap

**Last Updated**: December 2025
**Version**: 1.0.0
**Status**: Production (App Store Ready)

---

## 1. Completed Features (The Foundation)

### Core RAG Pipeline
- [x] **DocumentProcessor**: Multi-format parsing (PDF, TXT, MD, RTF, CSV, Office docs)
- [x] **SemanticChunker**: Paragraph-aware chunking (400w/75w overlap)
- [x] **EmbeddingService**: 512-dim vectors via NLEmbedding
- [x] **NLContextualEmbeddingProvider**: BERT-like contextual embeddings (iOS 17+) for 15-25% accuracy boost
- [x] **VectorDatabase**: Protocol with 3 implementations (InMemory, Persistent, Vectura HNSW)
- [x] **VectorStoreRouter**: Per-container database routing
- [x] **HybridSearchService**: BM25 + Vector Search fusion
- [x] **RAGEngine (Actor)**: Background MMR diversification, RRF fusion, BM25 scoring

### LLM Integrations
- [x] **AppleFoundationLLMService**: iOS 26 Foundation Models with PCC fallback
- [x] **Agentic Tool Calling**: @Generable + Tool protocol for SearchDocumentsTool, ListDocumentsTool, GetDocumentSummaryTool
- [x] **@Generable Structured Responses**: RAGAnswer, RAGSearchResults, RAGDocumentSummary types
- [x] **OnDeviceAnalysisService**: Extractive QA fallback (always available)
- [x] **OpenAIResponsesAPIService**: GPT-5 Responses API integration
- [x] **Local Model Removal**: Removed GGUF/CoreML/MLX downloadable models (Dec 2025)
  *Note*: App now uses Apple Intelligence + On-Device Analysis only. Simplifies maintenance and reduces binary size.
- [x] **Apple FM API Audit (Dec 2025)**: Full FoundationModels framework compliance
  - `prewarm(promptPrefix:)` for latency optimization
  - `SamplingMode.random(top:)` / `.random(probabilityThreshold:)` for topK/topP
  - Exhaustive `GenerationError` handling (9 cases with user-friendly messages)
  - `Transcript` access for debugging/replay
  - `LanguageModelFeedback` integration (thumbs up/down in chat UI)
  - Context window corrected to 4,096 tokens per TN3193
  - Tool `@Guide` with `.range()` constraints

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

---

## 3. Future Trajectory

### Phase 2.0 — Intelligence Layer
- [ ] **Query Planning Agent**: Multi-step reasoning over large document sets
- [ ] **Cross-Container Search**: Unified retrieval across multiple containers
- [ ] **Conversation Memory**: Persistent chat context with summarization

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

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
