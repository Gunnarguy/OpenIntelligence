# OpenIntelligence Roadmap

**Last Updated**: November 2025  
**Platform Strategy**: iOS-first, macOS planned for later

---

## ✅ Completed (Nov 2025)

### Core RAG Infrastructure
- ✅ Per-container vector databases with persistent JSON storage
- ✅ Hybrid search (cosine similarity + BM25 + reciprocal rank fusion)
- ✅ MMR diversification for result variety
- ✅ Semantic chunking with diagnostics (target 400 words, 75 overlap)
- ✅ Query enhancement service with expansion variants
- ✅ Cached norms for fast cosine similarity computation

### LLM Backends (6 Total)
- ✅ Apple Intelligence (Foundation Models) - streaming, tool calling, PCC
- ✅ ChatGPT Extension integration (iOS 18.1+)
- ✅ GGUF local via llama.cpp (iOS cartridge system)
- ✅ Core ML .mlpackage support (scaffold complete, tokenizer TODO)
- ✅ On-Device Analysis (extractive QA fallback)
- ✅ OpenAI Direct (macOS only, user API key)

### Embedding Providers (3 Total)
- ✅ NLEmbedding (512-dim, default)
- ✅ Core ML Sentence Transformers
- ✅ Apple FM embeddings (protocol ready, implementation future)
- ✅ Per-container embedding provider selection
- ✅ Factory pattern: `EmbeddingService.forProvider(id:)`

### Agentic Capabilities
- ✅ Apple Intelligence tool calling with 12 @Tool functions
- ✅ RAGToolHandler with container-scoped execution
- ✅ Tools: search, list documents, summarize, analytics, container management
- ✅ Weak reference pattern to avoid retain cycles

### UI & Telemetry
- ✅ ChatV2 modern architecture with streaming
- ✅ **InferenceLocationBadge** - shows execution (📱 on-device / ☁️ PCC / 🔑 cloud)
- ✅ **ToolCallBadge** - displays function call count
- ✅ MessageMetaView integration with inline badges
- ✅ ResponseDetailsView with full metrics
- ✅ TelemetryCenter instrumentation across pipeline
- ✅ Vector space 2D visualization (UMAP projection)

### Model Management
- ✅ ModelRegistry cartridge system
- ✅ ModelDownloadService for GGUF/Core ML installation
- ✅ Installation progress tracking
- ✅ Model activation/selection UI

### Additional Features
- ✅ Writing Tools API integration
- ✅ Siri App Intents (beta)
- ✅ Strict mode per container (high-confidence gating)
- ✅ Documents overlay with import/management
- ✅ Settings persistence via SettingsStore

---

## 🎯 Next Priorities (Q1 2026)

### 1. Core ML Tokenizer Implementation (HIGH) - 8-12h
- Implement proper BPE or SentencePiece tokenizer
- Complete `CoreMLLLMService` generation loop
- Test with popular models (Phi-3, Mistral 7B)
- **Blocker**: Currently placeholder implementation

### 2. End-to-End Testing Suite (HIGH) - 6-8h
- Document ingestion flow tests
- Query pipeline with tool execution
- Container isolation validation
- Embedding provider switching scenarios
- Performance regression suite

### 3. Embedding Provider Switcher UI (MEDIUM) - 4-6h
- Add provider selector in container settings
- Show active provider in Documents overlay
- Warn about dimension mismatches
- Re-embedding workflow guidance

### 4. Performance Optimization (MEDIUM) - 8-10h
- Benchmark Core ML vs GGUF inference
- Profile hybrid search at 10K+ chunks
- Optimize MMR computation for large result sets
- Add execution badges to streaming responses (real-time)

### 5. Model Cartridge Polish (MEDIUM) - 6-8h
- Download progress improvements
- Error recovery for failed downloads
- Model validation before activation
- Better metadata display (quant type, size, etc.)

### 6. Documentation Updates (LOW) - 2-3h
- Update README with current feature set
- Add embedding provider guide
- Core ML model setup instructions
- Tool function documentation

---

## 🔮 Future (Q2-Q3 2026)

### macOS Support
- MLX Local implementation (deferred from iOS-first)
- Ollama integration
- Desktop-specific UI optimizations
- Cross-platform container sync

### Advanced Vector Features
- VecturaKit HNSW integration for scale
- Incremental vector updates (no full re-embedding)
- Vector compression techniques
- Cross-container semantic search

### Agentic Enhancements
- Web search tool integration
- Multi-step reasoning workflows
- Tool chaining and composition
- Custom tool registration API

### Enterprise Features
- Multi-user container sharing
- Access control lists (ACLs)
- Audit logging
- Data residency controls

### Embeddings
- Multi-language embedding support
- Fine-tuned domain-specific embeddings
- Hybrid embedding strategies (semantic + keyword)
- Embedding model updates without re-ingestion

### Evaluation & Monitoring
- Golden Q&A test sets
- Automatic quality regression detection
- A/B testing framework for retrieval strategies
- Performance alerting (latency/accuracy budgets)

---

## 🚫 Not Planned (Explicitly Deferred)

- Android/cross-platform mobile
- Cloud-hosted backend (privacy-first = local-first)
- Proprietary closed-source models beyond Apple/OpenAI
- Real-time collaborative editing
- Blockchain/Web3 integrations

---

## 📊 Progress Metrics

| Category | Complete | In Progress | Planned |
|----------|----------|-------------|---------|
| LLM Backends | 5/6 (83%) | Core ML tokenizer | macOS MLX |
| Embedding Providers | 3/3 (100%) | - | Multi-language |
| UI Components | 15/16 (94%) | Embedding selector | - |
| Agentic Tools | 12/12 (100%) | - | Web search |
| Testing | 40% | Test suite | Regression |
| Documentation | 60% | Updates needed | API docs |

---

**Overall Status**: 🟢 **iOS Production-Ready**  
**Next Milestone**: Core ML tokenizer completion + testing suite  
**Platform Focus**: iOS 26.0+ (macOS deferred to Q2 2026)


