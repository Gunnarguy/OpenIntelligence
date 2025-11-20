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
   - Uses `LanguageModelSession` for on-device inference
   - Automatic Private Cloud Compute fallback
   - Streaming response support
   - Zero data retention

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
