# OpenIntelligence Technical Architecture

**Version**: 2.1
**Date**: January 2026
**Status**: Production-Ready

## Executive Summary

OpenIntelligence is a native iOS 26 application implementing a complete Retrieval-Augmented Generation (RAG) pipeline. The architecture leverages Apple Intelligence (Foundation Models + Private Cloud Compute) while maintaining a protocol-based design.

**Simple Concept:** Users upload documents, ask questions, get AI-powered answers using information from their documents.

### Key Architectural Principles

1. **Privacy-First**: On-device processing by default, optional Private Cloud Compute with zero retention
2. **Protocol-Oriented**: Modular design enables swapping implementations without changing business logic
3. **Async/Await**: Modern Swift concurrency throughout
4. **Adaptive Retrieval**: Query-intent-aware weight tuning and content-type-optimized configurations
5. **Simple**: 10 core files implement complete functionality

## System Architecture

### High-Level Component Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│                        User Interface                        │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────┐   │
│  │ ChatView │    │ DocumentView │    │ ModelManager │   │
│  └────┬─────┘    └──────┬───────┘    └────────┬───────┘   │
└───────┼─────────────────┼───────────────────────┼──────────┘
        │                 │                       │
        └─────────────────┼───────────────────────┘
                          ▼
        ┌─────────────────────────────────────────────┐
        │         RAGService (Orchestrator)           │
        └─┬───────────┬────────────┬──────────────┬───┘
          │           │            │              │
    ┌─────▼──┐  ┌────▼─────┐  ┌──▼───────┐  ┌───▼────────┐
    │Document│  │Embedding │  │  Vector  │  │    LLM     │
    │Processor│ │ Service  │  │ Database │  │  Service   │
    └────────┘  └──────────┘  └──────────┘  └────────────┘
         │           │              │              │
         ▼           ▼              ▼              ▼
    ┌────────┐  ┌────────┐    ┌────────┐    ┌────────┐
    │ PDFKit │  │Natural │    │In-Mem  │    │Found.  │
    │        │  │Language│    │or Vec  │    │Models  │
    │        │  │        │    │turaKit │    │or CoreML│
    └────────┘  └────────┘    └────────┘    └────────┘
```

### Data Flow Architecture

```text
User Document Input
      │
      ▼
┌─────────────────┐
│ Parse & Extract │  ← PDFKit / Vision OCR
│   Text Content  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Chunk Documents │  ← Content-adaptive chunking
│  (150-400w)     │    ChunkingConfig.recommended()
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Generate        │  ← NLEmbedding
│ Embeddings      │  ← 512-dim vectors
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Store in Vector │  ← VectorDatabase protocol
│    Database     │  ← Cosine similarity
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Auto-Tune       │  ← RetrievalConfig.recommended()
│ Container       │    Based on document types
└─────────────────┘
         │
         ▼
    [Ready for Queries]

User Query Input
      │
      ▼
┌─────────────────┐
│ Classify Query  │  ← QueryIntent detection
│ Intent          │    (keyword/conceptual/balanced)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Adjust Search   │  ← Dynamic vector/keyword weights
│ Weights         │    per-query ±15%
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Embed Query     │  ← Same embedding model
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ Hybrid Search               │
│ ┌─────────┐ ┌─────────────┐ │
│ │ Vector  │ │   BM25      │ │  ← Dual retrieval paths
│ │ k-NN    │ │ Keyword     │ │
│ └────┬────┘ └──────┬──────┘ │
│      └──────┬──────┘        │
│             ▼               │
│      RRF Fusion             │  ← Reciprocal Rank Fusion
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────┐
│ Cross-Encoder   │  ← ReRankerModel.mlpackage
│ Rerank          │    Neural relevance scoring
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ MMR Diversity   │  ← λ=0.6 diversity/relevance
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Lost-in-Middle  │  ← Reorder for LLM attention
│ Mitigation      │    Best chunks at start AND end
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Format Context  │  ← Build prompt with
│ for LLM         │    retrieved chunks
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ LLM Generation  │  ← Apple FM (PCC) /
│                 │    On-device fallback
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Return Response │  ← With metadata and
│ + Metrics       │    performance stats
└─────────────────┘
```

## Core Services

### DocumentProcessor

**Purpose**: Universal document parsing and semantic chunking

**Key Features**:

- Multi-format support: PDF, text, Markdown, RTF, code, CSV, Office docs
- PDFKit for native PDF parsing
- Vision framework OCR fallback for scanned pages
- **Content-adaptive chunking** via `ChunkingConfig.recommended(for:)`
- Returns `ProcessingSummary` with timing and statistics

**Chunking Presets** (Jan 2026 - Optimized):

| Preset | Target Size | Overlap | Use Case |
|--------|-------------|---------|----------|
| `technicalReference` | 280 words | 50 words (~18%) | PDFs, manuals, spec sheets |
| `narrative` | 400 words | 70 words (~17%) | Prose, articles, books |
| `code` | 250 words | 40 words (~16%) | Source code, scripts |
| Default | 350 words | 60 words (~17%) | General documents |

**File**: `OpenIntelligence/Services/DocumentProcessor.swift`


### EmbeddingService

**Purpose**: Generate semantic vector representations of text


**Key Features**:

- Uses `NLEmbedding.wordEmbedding` for 512-dimensional vectors
- Token-level embedding with averaging for chunk representations
- Cosine similarity calculation for retrieval
- Validates dimensions, NaN values, and magnitudes
- Always available on-device (no network required)


**File**: `OpenIntelligence/Services/EmbeddingService.swift`


### VectorDatabase

**Purpose**: Store and retrieve document chunks by semantic similarity

**Protocol**: Defines `store`, `search`, `clear` operations

**Implementation**: `InMemoryVectorDatabase` with linear scan

**Search**: k-NN using cosine similarity

**Key Features**:

- Thread-safe operations
- Fast in-memory search
- Protocol allows swapping implementations (e.g., VecturaKit for persistence)


**File**: `OpenIntelligence/Services/VectorDatabase.swift`


### HybridSearchService

**Purpose**: Dual-path retrieval combining semantic vectors with lexical search

**Key Features**:

- **Vector Search**: Cosine similarity on NLEmbedding vectors (semantic understanding)
- **BM25 Keyword Search**: TF-IDF variant for exact term matching
- **Reciprocal Rank Fusion (RRF)**: Combines ranked lists with `k=60` constant
- Configurable fusion weights via `RetrievalConfig`

**Default Weights** (Jan 2026):

| Weight | Value | Rationale |
|--------|-------|-----------|
| Vector | 0.4 | Semantic similarity |
| Keyword (BM25) | 0.6 | Better for specific terms, codes, model numbers |

**File**: `OpenIntelligence/Services/HybridSearchService.swift`


### QueryEnhancementService

**Purpose**: Query analysis, expansion, and intent classification

**Key Features**:

- **Query Intent Classification**: Detects `keyword`, `conceptual`, or `balanced` intent
- **Corpus Expansion**: Adds synonyms and related terms from document vocabulary
- **Garbage Term Filtering**: Rejects hyphenated fragments, stopwords, numeric-only terms
- **Per-Query Weight Adjustment**: ±15% shift based on detected intent

**Intent Classification Logic**:

```swift
enum QueryIntent {
    case keyword      // "5W-30 oil spec" → favor BM25 (+15%)
    case conceptual   // "how does the engine work" → favor vectors (+15%)
    case balanced     // Default mix
}
```

**File**: `OpenIntelligence/Services/QueryEnhancementService.swift`


### RAGEngine

**Purpose**: Background actor for compute-intensive retrieval operations

**Key Features**:

- **Singleton Pattern**: `RAGEngine.shared` prevents redundant model loading
- **Cross-Encoder Reranking**: `ReRankerModel.mlpackage` for neural relevance scoring
- **MMR Diversification**: λ=0.6 balances relevance vs. diversity
- **Lost-in-Middle Mitigation**: Reorders chunks for LLM attention patterns

**Lost-in-Middle Algorithm** (Liu et al. 2023):

LLMs attend better to the beginning and end of context. After reordering:
- Position 0: Best chunk
- Position N-1: Second-best chunk
- Middle positions: Interleaved remaining chunks

```swift
// Result: [best, 3rd, 5th, ..., 6th, 4th, 2nd-best]
func applyLostInMiddleReordering(_ chunks: [DocumentChunk]) -> [DocumentChunk]
```

**File**: `OpenIntelligence/Services/RAGEngine.swift`


### RetrievalConfig (in KnowledgeContainer)

**Purpose**: Per-container retrieval tuning parameters

**Presets** (Jan 2026):

| Preset | minSimilarity | vectorWeight | keywordWeight | Use Case |
|--------|---------------|--------------|---------------|----------|
| `default` | 0.28 | 0.4 | 0.6 | General documents |
| `balanced` | 0.35 | 0.5 | 0.5 | Mixed content |
| `technicalManual` | 0.22 | 0.3 | 0.7 | PDFs, spec sheets, manuals |
| `narrative` | 0.32 | 0.6 | 0.4 | Prose, articles |
| `code` | 0.30 | 0.35 | 0.65 | Source code |

**Auto-Tuning**: `RetrievalConfig.recommended(forDocumentTypes:)` analyzes ingested content and selects optimal preset.

**File**: `OpenIntelligence/Models/KnowledgeContainer.swift`


### LLMService

**Purpose**: Protocol abstraction for text generation

**Implementations**:

1. **AppleFoundationLLMService** (iOS 26+)
   - Uses `LanguageModelSession` from FoundationModels framework
   - Context window: **4,096 tokens per session** (per [TN3193](https://developer.apple.com/documentation/technotes/tn3193-using-the-context-window-efficiently))
   - Private Cloud Compute (PCC): Offloads compute for complex queries but **same 4,096 token API limit**
   - Streaming via `streamResponse()` with TTFT tracking
   - `prewarm(promptPrefix:)` for latency optimization
   - Full `GenerationError` handling (context overflow, guardrails, rate limits)
   - Zero data retention; encrypted PCC hops
   - **Agentic RAG Tools**: `SearchDocumentsTool`, `ListDocumentsTool`, `GetDocumentSummaryTool` (see below)

2. **OnDeviceAnalysisService**
   - Extractive QA fallback
   - Always available
   - No external dependencies
   - Quotes relevant sentences from context

3. **[REMOVED] OpenAILLMService**
   - Cloud LLM integrations removed Dec 2025
   - Dead code in `OpenAIResponsesAPIService.swift` (`#if false`)

4. **[STUB] AppleChatGPTExtensionService**
   - Stub for Writing Tools API
   - Not yet implemented

5. **CoreMLLLMService**
   - Skeleton for .mlpackage models
   - Needs tokenizer and autoregressive loop

#### Agentic RAG Strategy

Apple's 4,096-token limit per session requires intelligent multi-pass retrieval. The agentic tools enable the model to navigate large document collections within constrained context windows.

**Available Tools** (defined in `LLMService.swift`):

| Tool | Purpose | Arguments |
|------|---------|-----------|
| `SearchDocumentsTool` | Semantic search across containers | `query: String`, `limit: Int?` |
| `ListDocumentsTool` | Enumerate documents in container | `containerName: String?` |
| `GetDocumentSummaryTool` | Retrieve document metadata | `documentID: UUID` |

**Multi-Session Chaining Pattern** (per [TN3193](https://developer.apple.com/documentation/technotes/tn3193-using-the-context-window-efficiently)):

For complex queries exceeding 4K tokens:

1. **Session 1**: Model receives query + tool definitions → calls `SearchDocumentsTool`
2. **Session 2**: Relevant chunks injected → partial answer generated
3. **Session 3** (if needed): Refine with follow-up search or synthesis

```swift
// Simplified flow in AppleFoundationLLMService
let tools = [SearchDocumentsTool(), ListDocumentsTool(), GetDocumentSummaryTool()]
let session = LanguageModelSession(instructions: systemPrompt, tools: tools)

// Model autonomously decides when to call tools
for try await event in session.streamResponse(to: userQuery) {
    switch event {
    case .toolCall(let call):
        let result = await handleToolCall(call)  // RAGToolHandler
        session.respond(to: call, with: result)
    case .text(let chunk):
        yield chunk
    }
}
```

**Context Budget Strategy**:

| Component | Token Allocation |
|-----------|------------------|
| System prompt | ~200 tokens |
| Tool definitions | ~300 tokens |
| Retrieved context | ~2,500 tokens (~5,000 chars) |
| Response buffer | ~1,000 tokens |
| **Total** | **4,096 tokens** |

**Trade-offs**:
- **Pre-stuffed context**: Single pass, lower latency, but context may not be optimal
- **Pure agentic**: Model searches dynamically, multiple passes, better accuracy for complex queries

**Deep Dive**: See [`Docs/reference/AFW.md`](Docs/reference/AFW.md) for the full Apple Intelligence architecture report (on-device 3B model, PCC PT-MoE server, routing, and privacy guarantees).

**File**: `OpenIntelligence/Services/LLMService.swift` (933 lines)

### RAGService

**Purpose**: Orchestrates entire RAG pipeline (`@MainActor`)

**Key Responsibilities**:

- Document ingestion: `addDocument(_:)` → parse → chunk → embed → store
- Query execution: `query(_:topK:)` → embed → hybrid search → rerank → generate
- **Auto-tuning**: `autoTuneRetrievalConfigIfNeeded()` after document ingestion
- **Per-query weight adjustment**: Applies `QueryIntent` classification to adjust fusion weights
- State management via `@Published` properties
- Device capability detection
- Performance metrics tracking

**Query Pipeline** (Jan 2026):

```swift
// Simplified query flow
func query(_ text: String, topK: Int) async {
    // 1. Classify intent
    let intent = queryEnhancer.classifyIntent(text)
    let adjustedVectorWeight = config.vectorWeight + intent.weightAdjustment

    // 2. Hybrid search with adjusted weights
    let candidates = await hybridSearch.search(
        query: text,
        vectorWeight: adjustedVectorWeight,
        keywordWeight: 1.0 - adjustedVectorWeight
    )

    // 3. Cross-encoder rerank + MMR
    let reranked = await RAGEngine.shared.rerankWithMMR(candidates)

    // 4. Lost-in-middle reordering
    let context = await RAGEngine.shared.assembleContext(
        reranked,
        useLostInMiddleMitigation: true
    )

    // 5. LLM generation
    let response = await llmService.generate(query: text, context: context)
}
```

**Observable Properties**:

- `documents`: Array of imported documents
- `messages`: Chat conversation history
- `isProcessing`: Current operation status
- `processingStatus`: Real-time progress updates
- `lastError`: User-facing error messages
- `lastProcessingSummary`: Detailed ingestion stats

**File**: `OpenIntelligence/Services/RAGService.swift`

---

## Advanced RAG Techniques (Jan 2026)

OpenIntelligence implements state-of-the-art RAG techniques from 2024-2026 research, optimized for Apple's 4,096-token context window constraint.

### HyDE: Hypothetical Document Embeddings

**Purpose**: Bridge the vocabulary gap between questions and documents

**Problem Solved**: When users ask "What oil does my car take?", the question vocabulary doesn't match the answer ("SAE 0W-20 synthetic oil"). Embedding the question directly retrieves suboptimal chunks.

**Solution**: Generate a hypothetical answer first, then embed *that* for retrieval.

```text
User Query: "What oil does my car take?"
           ↓
HyDE Generation: "The 2024 Kia Sportage uses SAE 0W-20 synthetic oil.
                  Oil capacity is 5.3 quarts including the filter..."
           ↓
Embed hypothetical → Search → Retrieve actual matching chunks
```

**Implementation** (`HyDEService.swift`):

| Component | Details |
|-----------|---------|
| LLM Backend | Apple Foundation Models (on-device) |
| Trigger Heuristic | `shouldUseHyDE(for:)` detects factual queries |
| Latency Cost | ~200-400ms extra for generation |
| Recall Improvement | 15-25% on technical/factual queries |
| Setting | `SettingsStore.enableHyDE` (default: `true`) |

**API References**:
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- Uses Apple's on-device model for low-latency generation

**File**: `OpenIntelligence/Services/HyDEService.swift`

---

### Contextual Compression

**Purpose**: Extract only query-relevant content from retrieved chunks

**Problem Solved**: Retrieved chunks contain relevant AND irrelevant sentences. Sending all content wastes precious tokens and dilutes the LLM's attention.

**Solution**: Use LLM to filter each chunk down to only sentences that help answer the query.

```text
Retrieved Chunk (400 words):
"The Sportage features advanced safety... [irrelevant content]...
Engine oil: Use SAE 0W-20 synthetic oil. Capacity: 5.3 quarts...
[more irrelevant content about other fluids]"
           ↓
Compressed (60 words):
"Engine oil: Use SAE 0W-20 synthetic oil. Capacity: 5.3 quarts."
```

**Implementation** (`ContextualCompressionService.swift`):

| Component | Details |
|-----------|---------|
| Compression Ratio | ~40% (aggressive), ~60% (conservative) |
| Token Savings | 40-60% per chunk on average |
| Latency Cost | ~100-200ms per chunk |
| Drop Irrelevant | Chunks returning "NO_RELEVANT_CONTENT" are excluded |
| Setting | `SettingsStore.enableContextualCompression` (default: `true`) |

**Answer Grounding Verification**:

The service also provides `verifyAnswerGrounding(answer:context:query:)` to detect hallucinations:

```swift
enum GroundingStatus {
    case grounded          // Answer fully supported by context
    case partiallyGrounded // Some claims unsupported
    case ungrounded        // Significant hallucination
    case notAnswerable     // Context insufficient
}
```

**File**: `OpenIntelligence/Services/ContextualCompressionService.swift`

---

### Multi-Session Agentic Orchestration

**Purpose**: Transcend the 4,096-token limit through intelligent session chaining

**Problem Solved**: Complex queries requiring extensive reasoning can't fit in a single 4K session.

**Solution**: The `AgenticOrchestrator` manages a multi-session pipeline:

```text
┌─────────────────────────────────────────────────────────────┐
│                  AgenticOrchestrator                        │
│                                                             │
│  Session 1: PLANNING                                        │
│  "Break down query into sub-questions"                      │
│       ↓                                                     │
│  Session 2: SEARCHING (with RAG tools)                      │
│  SearchDocumentsTool → retrieve relevant chunks             │
│       ↓                                                     │
│  Session 3: ANALYZING                                       │
│  "Extract key facts from retrieved context"                 │
│       ↓                                                     │
│  Session 4: SYNTHESIZING                                    │
│  "Compose coherent answer from facts"                       │
│       ↓                                                     │
│  Session 5: REFINING                                        │
│  "Polish and verify final response"                         │
└─────────────────────────────────────────────────────────────┘
```

**Hardware-Aware Configuration** (`DeviceCapabilityService.swift`):

| Device Tier | Max Steps | Max Tokens | Use Case |
|-------------|-----------|------------|----------|
| A17 Pro (iPhone 15 Pro) | 4 | 16,000 | Basic agentic |
| A18 (iPhone 16) | 6 | 24,000 | Standard agentic |
| A19 (iPhone 17) | 8 | 32,000 | Enhanced agentic |
| M-series (iPad Pro) | 10 | 48,000 | Full power |

### SystemStateMonitor

**Purpose**: Centralized real-time device state monitoring for transparency and pipeline optimization.

**File**: `OpenIntelligence/Services/SystemStateMonitor.swift`

**Captured Metrics**:
- **Thermal State**: ProcessInfo.ThermalState (Nominal/Fair/Serious/Critical)
- **Battery**: Level (0-100%), charging state, Low Power Mode
- **Memory**: Available bytes, pressure level (Nominal/Warning/Critical)
- **CPU**: Processor count, active processor count
- **Pipeline**: Current PipelineOptimizationLevel from AdaptivePipelineOptimizer

**Architecture**:
```swift
@MainActor
final class SystemStateMonitor: ObservableObject {
    static let shared = SystemStateMonitor()
    @Published private(set) var currentState: SystemStateSnapshot

    // NotificationCenter observers for:
    // - ProcessInfo.thermalStateDidChangeNotification
    // - UIDevice.batteryLevelDidChangeNotification
    // - UIDevice.batteryStateDidChangeNotification
    // - NSProcessInfoPowerStateDidChange
    // - UIApplication.didReceiveMemoryWarningNotification
}
```

**UI Exposure**:
- **UnifiedMetricsBar**: Compact badge (thermal/battery when notable) + expanded System State card
- **SettingsView**: Live System Monitor section with 2-column grid

**Note**: iOS reports battery in ~5% increments (Apple API limitation).

**Implementation Details**:

- Each session gets fresh 4K context window
- Previous session summary injected as compressed context
- Explicit `resetSession()` prevents memory accumulation
- `Task.checkCancellation()` at each step for responsive cancellation

**File**: `OpenIntelligence/Services/AgenticOrchestrator.swift`

---

### Query Task Management

**Purpose**: Handle back-to-back queries without memory leaks or freezing

**Problem Solved**: User sends query → starts processing → sends another query → first task continues in background → memory accumulates.

**Solution**: Cancel-and-replace pattern with explicit task tracking:

```swift
@State private var currentQueryTask: Task<Void, Never>?

func sendMessage() async {
    // Cancel any in-flight query
    currentQueryTask?.cancel()

    // Start new task with explicit cleanup
    currentQueryTask = Task {
        defer { currentQueryTask = nil }

        // Pipeline stages with cancellation checks
        try Task.checkCancellation()
        await ragService.query(message)

        try Task.checkCancellation()
        // ... additional stages
    }
}
```

**Cancellation Points**:
1. After query submission
2. After embedding generation
3. After hybrid search
4. After reranking
5. After context assembly
6. During LLM streaming

**File**: `OpenIntelligence/Views/ChatV2/ChatScreen.swift`

---

### API Compatibility Matrix

All advanced features are fully compatible with Apple's FoundationModels framework:

| Feature | iOS Version | Apple API | Privacy |
|---------|-------------|-----------|---------|
| HyDE | iOS 26+ | `LanguageModelSession.respond(to:)` | On-device |
| Contextual Compression | iOS 26+ | `LanguageModelSession.respond(to:)` | On-device |
| Agentic Orchestration | iOS 26+ | `LanguageModelSession` + `Tool` protocol | On-device + PCC |
| Cross-Encoder Reranking | iOS 17+ | Core ML (`ReRankerModel.mlpackage`) | On-device |
| Lost-in-Middle | Any | Pure Swift algorithm | On-device |
| Query Intent Classification | iOS 17+ | `NLTagger` + heuristics | On-device |

**References**:
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)

---

## SwiftUI Views

### ChatView

- Message list with user/assistant roles
- Query input field
- Retrieved context viewer
- Performance metrics display (TTFT, tokens/sec)
- Configurable top-K retrieval (3, 5, 10 chunks)
- Apple Writing Tools integration for proofreading, rewriting, and summarizing user prompts (iOS 18.1+)

### DocumentLibraryView

- Document picker integration
- Processing status overlay with progress
- Document list with metadata (pages, chunks, date)
- Swipe-to-delete functionality

### SettingsView

- LLM service selection (Apple Intelligence / On-Device Analysis)
- Temperature and max tokens configuration
- Top-K retrieval depth setting
- Embedding provider selection
- Quality Mode picker (Fast/Balanced/Thorough)

### ModelManagerView

- Device capability detection
- Apple Intelligence status
- Device tier classification (low/medium/high)
- Model information display
- Custom model import instructions (placeholder)

## Dependencies

### Native iOS Frameworks

- **Foundation**: Core data structures, async runtime
- **NaturalLanguage**: `NLEmbedding` for on-device embeddings
- **PDFKit**: Native PDF parsing
- **Vision**: OCR for scanned documents
- **UniformTypeIdentifiers**: File type detection
- **WritingTools**: System proofreading/rewriting/summarization (iOS 18.1+)
- **SwiftUI**: Reactive UI framework
- **Combine**: Observable state management

### iOS 26+ (Optional)

- **FoundationModels**: Apple Intelligence LLM access
- **LanguageModelSession**: Streaming inference with PCC fallback

## Performance Targets

| Operation | Target | Current Status |
|-----------|--------|----------------|
| Document parsing | <1s/page | ✅ Achieved |
| Embedding generation | <100ms/chunk | ✅ Achieved |
| Vector search (1K chunks) | <50ms | ✅ Achieved |
| LLM generation (Apple FM) | 15-25 tok/s | ✅ Achieved |
| End-to-end query | <5s | ✅ Achieved |

## Privacy Architecture

1. **On-Device Processing**: All document parsing, embedding, and search happens locally
2. **Apple Intelligence**: Stays on-device; Private Cloud Compute only for complex queries
3. **Private Cloud Compute**: Apple Silicon servers, cryptographically enforced zero retention
4. **No Cloud APIs**: OpenAI/GPT integrations removed Dec 2025 (privacy-first design)
5. **No Telemetry**: Zero data collection or analytics

## Retrieval Quality Assessment

**Current Rating**: 7.5/10 (Jan 2026)

### What We Have (Best Practices Implemented)

| Feature | Status | Implementation |
|---------|--------|----------------|
| Hybrid Search (Vector + BM25) | ✅ | `HybridSearchService` with RRF fusion |
| Cross-Encoder Reranking | ✅ | `ReRankerModel.mlpackage` in `RAGEngine` |
| MMR Diversification | ✅ | λ=0.6 in `RAGEngine.rerankWithMMR()` |
| Query Expansion | ✅ | `QueryEnhancementService.expandQuery()` |
| Query Intent Classification | ✅ | `QueryIntent` enum with dynamic weights |
| Content-Adaptive Chunking | ✅ | `ChunkingConfig.recommended(for:)` |
| Lost-in-Middle Mitigation | ✅ | `applyLostInMiddleReordering()` |
| Auto-Tuning | ✅ | `RetrievalConfig.recommended(forDocumentTypes:)` |

### What Would Push to 10/10

| Feature | Status | Complexity |
|---------|--------|------------|
| HyDE (Hypothetical Doc Embeddings) | 🔜 Roadmap | Medium |
| RAPTOR (Hierarchical Summaries) | 🔜 Roadmap | High |
| Self-RAG | 🔜 Roadmap | High |
| Speculative RAG | 🔜 Roadmap | High |
| Parent Document Retrieval | 🔜 Roadmap | Medium |
| Learned Fusion Weights | 🔜 Roadmap | High |

See [ROADMAP.md](../../ROADMAP.md) Phase 2.5 for full "God Mode RAG" feature list.

## Advanced RAG Intelligence (v2.0)

The retrieval pipeline has been enhanced with three major intelligence upgrades:

### 1. Query Clarification (Lightweight)

**Philosophy**: Trust the embeddings. Only intervene for genuine ambiguity.

**When it activates**:
- Pronouns without referents ("What does it do?" → needs context)
- Follow-up questions ("What else?" → needs prior topic)
- Very short queries with conversation context

**When it stays out of the way**:
- Clear, specific queries → pass through unchanged
- No conversation context → no pronoun resolution needed

**File**: `Services/QueryRewriterService.swift`

**Features**:
- Ambiguity detection (pronouns, follow-ups, short queries)
- LLM-powered clarification with conversation context
- Simple fallback pronoun substitution
- Minimal intervention — doesn't over-engineer or domain-lock

### 2. Corpus-Aware Query Expansion

**Purpose**: Expand queries using the vocabulary from the user's actual documents

**Problem Solved**: Generic synonym expansion ("button" → "switch") doesn't help if the documents use specific terminology.

**Solution**: Build a vocabulary from chunk keywords and co-occurrence relationships:

```text
Query term: "button"
Corpus co-occurrences: "record", "hold", "toggle", "mode", "switch"
Expanded query: "button record hold toggle mode switch"
```

**File**: `Services/QueryEnhancementService.swift` with `CorpusVocabulary`

**Features**:
- Builds co-occurrence maps from chunk metadata keywords
- Extracts multi-word phrases (e.g., "Record Button", "Note Recording Mode")
- Preserves original query while adding domain-specific terms

### 3. Iterative Retrieval

**Purpose**: Retrieve, assess, refine, and retrieve more until confident

**Problem Solved**: Single-pass retrieval may miss relevant chunks, especially for complex queries.

**Solution**: Multi-pass retrieval loop:

```text
Iteration 1: Retrieve chunks → Assess confidence (0.4) → Need more
Iteration 2: Refine query + retrieve → Assess confidence (0.6) → Need more
Iteration 3: Refine query + retrieve → Assess confidence (0.75) → Sufficient
→ Merge all unique chunks, re-rank, return
```

**File**: `Services/IterativeRetrievalService.swift`

**Features**:
- Configurable via `RAGQualityMode` (enabled in Thorough mode)
- Confidence assessment based on: chunk count, similarity scores, source diversity
- LLM-powered query refinement between iterations
- Automatic deduplication across iterations

### Quality Mode Control

These features are controlled by the `RAGQualityMode` setting:

| Feature | Fast | Balanced | Thorough |
|---------|------|----------|----------|
| Query Rewriting | ❌ | ✅ | ✅ |
| Corpus Expansion | ✅ | ✅ | ✅ |
| Iterative Retrieval | ❌ | ❌ | ✅ |
| Max Iterations | 1 | 2 | 4 |

### Settings Integration

Users can also manually toggle features via Settings > Intelligence Layer:

- **Query Understanding** (`enableQueryRewriting`): ON by default
- **Multi-Pass Retrieval** (`enableIterativeRetrieval`): OFF by default (battery consideration)

The pipeline in `RAGService.performRAGQuery()` checks these settings:

```swift
// Step 1: Query Understanding (if enabled)
if settingsStore?.enableQueryRewriting ?? false {
    effectiveQuery = await queryRewriter.rewrite(originalQuery)
}

// Step 1.5: Corpus-Aware Expansion (always enabled)
let expandedQueries = queryEnhancer.expandQuery(effectiveQuery)

// Step 3: Retrieval (single-pass or iterative)
if settingsStore?.enableIterativeRetrieval ?? false {
    // Multi-pass with confidence assessment
    let result = try await iterativeService.retrieve(...)
} else {
    // Single-pass hybrid search
    let chunks = try await hybridSearch.search(...)
}
```

## Error Handling

- User-facing error messages in `RAGService.lastError`
- Detailed logging for debugging
- Graceful fallbacks (e.g., Apple FM → extractive QA)
- File access errors handled with `SecurityScopedResource`
- Foundation Models `GenerationError` handling (9 cases)

## Directory Structure Standards

```text
OpenIntelligence/
├── OpenIntelligenceApp.swift    # App entry point
├── ContentView.swift            # Root navigation container
├── Models/                      # Data structures (ChatMessage, DocumentChunk, etc.)
├── Services/                    # Business logic layer
│   ├── Billing/                 # StoreKit & entitlement handling
│   ├── Embeddings/              # Embedding providers (NL, CoreML)
│   └── Visualization/           # Telemetry & diagnostics services
├── Views/                       # SwiftUI presentation layer
│   ├── Billing/                 # Paywall, subscription views
│   ├── ChatV2/                  # Chat interface components
│   ├── Diagnostics/             # Debug & analysis views
│   ├── Documents/               # Document library & import
│   ├── ModelManagement/         # Model selection & download
│   ├── Onboarding/              # First-run experience
│   ├── Settings/                # User preferences
│   ├── Shared/                  # Reusable UI components
│   └── Telemetry/               # Performance visualization
├── Shared/                      # Cross-cutting utilities
├── StoreKit/                    # Product configuration
├── Utilities/                   # Extensions & helpers
└── Assets.xcassets/             # Images, colors, app icon

Docs/
├── guides/                      # How-to documentation
├── reference/                   # Architecture & API docs
└── TestDocuments/               # Sample files for testing

scripts/                         # Build & CI automation

Vendor/                          # Third-party dependencies (LocalLLMClient)
```

### Placement Rules

1. **New Models**: Place in `Models/` with `Sendable` conformance
2. **New Services**: Place in `Services/` with protocol definition
3. **New Views**: Group by feature under `Views/{FeatureName}/`
4. **Shared Components**: Reusable UI goes in `Views/Shared/`
5. **Utilities**: Extensions and helpers go in `Utilities/`
6. **Tests**: Mirror source structure under `OpenIntelligenceTests/`

---

## Appendix A: Mobile LLM Optimization

### Model Selection & Quantization

**Recommended Model Sizes**:
- iPhone 15 Pro (8GB): 2–3B parameter models
- iPhone 16 Pro Max (8GB+): 3–7B parameter models

**Quantization Strategy**:

| Quantization | Size (3B) | Quality | Speed | Recommendation |
|--------------|-----------|---------|-------|----------------|
| Q4_K_M | ~2.0 GB | Excellent | Fast | ✅ Recommended |
| Q5_K_M | ~2.4 GB | Better | Moderate | Good for Pro Max |
| Q8_0 | ~3.2 GB | Near-fp16 | Slower | Avoid on mobile |

**Starter Models**:
- Qwen2.5-3B-Instruct-Q4_K_M (1.9 GB)
- Gemma-2-2B-It-Q4_K_M (1.6 GB)
- Llama-3.2-1B-Instruct-Q4_K_M (730 MB)

### Context Window Management

| Model | Max Context | Recommended Mobile |
|-------|-------------|-------------------|
| Qwen2.5-3B | 32,768 | 8,192–16,384 |
| Gemma-2-2B | 8,192 | 4,096–8,192 |
| Llama-3.2-1B | 131,072 | 8,192 |

**RAG Context Strategy**:
- Target ~3,000 tokens (5–8 chunks @ 280-350 words)
- SemanticChunker overlap (~17% / 60 words) maintains coherence
- HybridSearchService MMR prevents redundant context

### Memory Footprint (Q4_K_M 3B)

| Component | Size |
|-----------|------|
| Model weights | ~2.0 GB |
| KV cache (8K context) | ~500 MB |
| OS + app overhead | ~1.0 GB |
| **Total** | **~3.5 GB** |

### Performance Targets

- **TTFT**: <2 seconds (3B Q4_K_M on iPhone 15 Pro)
- **TPS**: 15–25 tokens/sec
- **Battery**: ~3–5W during inference

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Slow inference (<5 TPS) | Use Q4_K_M; wait for device to cool |
| Out-of-memory crash | Use smaller model; reduce context |
| High battery drain | Add cancellation checks; limit generation length |

---

## Appendix B: Performance Optimizations

### ChatView Optimizations

**Message Pagination**:
```swift
@State private var visibleMessageCount: Int = 50
private let maxMessagesInMemory = 200
```
- Reduces SwiftUI complexity from O(n) to O(50)
- 90% faster rendering for 500+ messages

**Automatic Cleanup**:
- Keeps most recent 200 messages
- Automatic pruning after each send

**Chunked Streaming**:
- Stream in 10-char chunks (not char-by-char)
- 10x fewer UI updates during response

### Vector Database Optimizations

**Pre-computed Embedding Norms**:
- Cache norms during storage
- 50% faster vector search (no sqrt() in hot loop)

**LRU Search Cache**:
- Cache last 20 search results
- Instant returns for repeated/similar queries
- Auto-expiration after 5 minutes

### Performance Metrics

| Scenario | Before | After |
|----------|--------|-------|
| 500 messages | 30-40 FPS | 60 FPS |
| Memory (1hr) | 150-200 MB | 50-70 MB |
| Vector search (1K chunks) | 80-120ms | 40-60ms |
| Repeated query | 80-120ms | 0-5ms |

### Tunable Parameters

```swift
// ChatView.swift
private var visibleMessageCount: Int = 50  // Visible history
private let maxMessagesInMemory = 200      // Total retained

// VectorDatabase.swift
private let maxCacheSize = 20              // Query cache slots
private let cacheExpirationSeconds = 300   // Cache TTL
```
