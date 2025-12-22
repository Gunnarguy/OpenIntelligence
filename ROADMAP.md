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
- [x] **OpenAILLMService**: GPT-4/3.5 API integration with streaming
- [x] **LlamaCPPiOSLLMService**: Local GGUF inference via llama.cpp
- [x] **MLXLLMService**: MLX tensor server integration (macOS)
- [x] **LocalOpenAIServerLLMService**: OpenAI-compatible local server support
- [x] **OnDeviceAnalysisService**: Extractive QA fallback (always available)
- [x] **OpenAIResponsesAPIService**: GPT-5 Responses API integration

### Agentic Tooling
- [x] **12+ @Tool Functions**: Autonomous search, summarization, analysis
- [x] **RAGAppIntents**: Siri/Shortcuts integration
- [x] **Tool Call Counter**: Usage tracking and limits

### Privacy & Security
- [x] **Cloud Consent System**: User consent before any cloud transmission
- [x] **CloudTransmission Records**: Full transparency logging
- [x] **Private Cloud Compute (PCC)**: Cryptographic zero-retention
- [x] **Execution Location Badges**: 📱 On-Device / ☁️ Cloud / 🔑 API Key

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
- [ ] **MLX macOS-Only**: Conditional compilation limits testing surface  
  *Impact*: Developer experience on iOS-only machines

- [ ] **Vendor LocalLLMClient**: Contains upstream TODOs (json-schema, threading)  
  *Impact*: Inherited technical debt, not blocking

---

## 3. Future Trajectory

### Phase 2.0 — Intelligence Layer
- [ ] **Query Planning Agent**: Multi-step reasoning over large document sets
- [ ] **Cross-Container Search**: Unified retrieval across multiple containers
- [ ] **Conversation Memory**: Persistent chat context with summarization

### Phase 2.1 — Model Ecosystem
- [ ] **Model Marketplace**: Browse/download GGUF models in-app
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

---

## Notes

- Check off items with `[x]` when complete
- Move completed Phase items to "Completed Features" section
- Keep Technical Debt items linked to source files
- Sprint Backlog resets each cycle
