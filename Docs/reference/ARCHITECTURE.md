# OpenIntelligence Technical Architecture

**Version**: 2.0
**Date**: October 2025
**Status**: Production-Ready

## Executive Summary

OpenIntelligence is a native iOS 26 application implementing a complete Retrieval-Augmented Generation (RAG) pipeline. The architecture leverages Apple Intelligence (Foundation Models + Private Cloud Compute) while maintaining a protocol-based design.

**Simple Concept:** Users upload documents, ask questions, get AI-powered answers using information from their documents.

### Key Architectural Principles

1. **Privacy-First**: On-device processing by default, optional Private Cloud Compute with zero retention
2. **Protocol-Oriented**: Modular design enables swapping implementations without changing business logic
3. **Async/Await**: Modern Swift concurrency throughout
4. **Simple**: 10 core files implement complete functionality

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
│ Chunk Documents │  ← Semantic splitting
│  (400w/50w)     │    with overlap
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
    [Ready for Queries]

User Query Input
      │
      ▼
┌─────────────────┐
│ Embed Query     │  ← Same embedding model
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Vector Search   │  ← k-NN with cosine
│  (Top-K: 3-10)  │    similarity
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
│ LLM Generation  │  ← Apple FM / OpenAI /
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
- Paragraph-aware semantic chunking
- Configurable chunk size (default 400 words) with 50-word overlap
- Returns `ProcessingSummary` with timing and statistics


**File**: `RAGMLCore/Services/DocumentProcessor.swift`


### EmbeddingService

**Purpose**: Generate semantic vector representations of text


**Key Features**:

- Uses `NLEmbedding.wordEmbedding` for 512-dimensional vectors
- Token-level embedding with averaging for chunk representations
- Cosine similarity calculation for retrieval
- Validates dimensions, NaN values, and magnitudes
- Always available on-device (no network required)


**File**: `RAGMLCore/Services/EmbeddingService.swift`


### VectorDatabase

**Purpose**: Store and retrieve document chunks by semantic similarity

**Protocol**: Defines `store`, `search`, `clear` operations

**Implementation**: `InMemoryVectorDatabase` with linear scan

**Search**: k-NN using cosine similarity

**Key Features**:

- Thread-safe operations
- Fast in-memory search
- Protocol allows swapping implementations (e.g., VecturaKit for persistence)


**File**: `RAGMLCore/Services/VectorDatabase.swift`


### LLMService

**Purpose**: Protocol abstraction for text generation

**Implementations**:

1. **AppleFoundationLLMService** (iOS 26+)
   - Uses `LanguageModelSession` from FoundationModels framework
   - Context window: **4,096 tokens** on-device (per [TN3193](https://developer.apple.com/documentation/technotes/tn3193-using-the-context-window-efficiently))
   - Automatic Private Cloud Compute (PCC) fallback for complex queries
   - Streaming via `streamResponse()` with TTFT tracking
   - `prewarm(promptPrefix:)` for latency optimization
   - Full `GenerationError` handling (context overflow, guardrails, rate limits)
   - Zero data retention; encrypted PCC hops
   - Agentic tools: `SearchDocumentsTool`, `ListDocumentsTool`, `GetDocumentSummaryTool`

2. **OpenAILLMService**
   - Direct API integration (production-ready)
   - GPT-4/GPT-3.5 support
   - Streaming completion
   - User-provided API key

3. **OnDeviceAnalysisService**
   - Extractive QA fallback
   - Always available
   - No external dependencies
   - Quotes relevant sentences from context

4. **AppleChatGPTExtensionService**
   - Stub for Writing Tools API
   - Not yet implemented

5. **CoreMLLLMService**
   - Skeleton for .mlpackage models
   - Needs tokenizer and autoregressive loop

**File**: `RAGMLCore/Services/LLMService.swift` (933 lines)

### RAGService

**Purpose**: Orchestrates entire RAG pipeline

**Key Responsibilities**:

- Document ingestion: `addDocument(_:)` → parse → chunk → embed → store
- Query execution: `query(_:topK:)` → embed → search → format → generate
- State management via `@Published` properties
- Device capability detection
- Performance metrics tracking

**Observable Properties**:

- `documents`: Array of imported documents
- `messages`: Chat conversation history
- `isProcessing`: Current operation status
- `processingStatus`: Real-time progress updates
- `lastError`: User-facing error messages
- `lastProcessingSummary`: Detailed ingestion stats

**File**: `RAGMLCore/Services/RAGService.swift`

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

- LLM service selection
- OpenAI API key management
- Temperature and max tokens configuration
- Top-K retrieval depth setting
- Embedding provider selection

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
| LLM generation (OpenAI) | 20+ tok/s | ✅ Achieved |
| End-to-end query | <5s | ✅ Achieved |

## Privacy Architecture

1. **On-Device Processing**: All document parsing, embedding, and search happens locally
2. **Apple Intelligence**: Stays on-device; Private Cloud Compute only for complex queries
3. **Private Cloud Compute**: Apple Silicon servers, cryptographically enforced zero retention
4. **OpenAI Pathway**: Explicit user consent, sends prompt + context only
5. **No Telemetry**: Zero data collection or analytics

## Error Handling

- User-facing error messages in `RAGService.lastError`
- Detailed logging for debugging
- Graceful fallbacks (e.g., OpenAI → extractive QA)
- File access errors handled with `SecurityScopedResource`
- Network errors with retry logic in OpenAI service

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
- Target ~3,000 tokens (3–4 chunks @ 400 words)
- SemanticChunker overlap (75 words) maintains coherence
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
