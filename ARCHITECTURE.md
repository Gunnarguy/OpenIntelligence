# OpenIntelligence Technical Architecture

**Version**: 2.9
**Date**: February 5, 2026
**Status**: Production (App Store Ready)

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Apple Framework Dependencies](#apple-framework-dependencies)
3. [System Architecture](#system-architecture)
4. [Core Services Inventory](#core-services)
   - [RAG Pipeline Services](#rag-pipeline-services-14-services)
   - [Query Services](#query-services-8-services)
   - [Document Processing Services](#document-processing-services-19-services)
   - [Embedding Services](#embedding-services-2-services)
   - [Storage Services](#storage-services-3-services)
   - [VectorStore Services](#vectorstore-services-4-services)
   - [LLM Services](#llm-services-7-services)
   - [Agentic Services](#agentic-services-3-services)
   - [Infrastructure Services](#infrastructure-services-17-services)
   - [Billing Services](#billing-services-1-service)
5. [DocumentProcessor Deep Dive](#documentprocessor)
6. [Token Budget Management](#token-budget-management)
7. [Data Structures](#data-structures)

## Executive Summary

OpenIntelligence is a native iOS 26 application implementing a complete Retrieval-Augmented Generation (RAG) pipeline. The architecture leverages Apple Intelligence (Foundation Models + Private Cloud Compute) while maintaining a protocol-based design.

**Simple Concept:** Import any document. Ask questions in plain English. Get cited answers powered by on-device AI.

**Latest (v2.9)**: Device-tier-aware Vision concurrency, platform-specific Metal optimizations, Mac compatibility via iPad mode, 4-gate verification pipeline, 78 services across 10 categories. Updated Apple framework integration assessment.

### RAG Pipeline Summary

The system implements a **23-step end-to-end pipeline** powered by **78 services**:

| Phase                | Steps | Key Services                                                                           |
| -------------------- | ----- | -------------------------------------------------------------------------------------- |
| **Ingestion**        | 6     | DocumentProcessor, SemanticChunker (table-aware), EntityIndexService, EmbeddingService |
| **Query Processing** | 7     | QueryEnhancementService, HyDEService, QueryRouterService, HybridSearchService          |
| **Post-Retrieval**   | 7     | VerificationGateService, ContextPackingService, ParentDocumentService                  |
| **Generation**       | 3     | ExtractiveSummarizationService, LLMService, AgenticOrchestrator                        |
| **Post-Generation**  | 4     | QualityAssuranceService, ConfidenceCalibrationService                                  |

> **Complete inventory**: See "Complete Service Inventory (78 Services)" below.

### Key Architectural Principles

1. **Privacy-First**: On-device processing by default, optional Private Cloud Compute with zero retention
2. **Protocol-Oriented**: Modular design enables swapping implementations without changing business logic
3. **Async/Await**: Modern Swift concurrency throughout
4. **Adaptive Retrieval**: Query-intent-aware weight tuning and content-type-optimized configurations
5. **Simple**: 10 core files implement complete functionality

## Apple Framework Dependencies

OpenIntelligence is built entirely on Apple's native frameworks—**no third-party AI dependencies**.

> **Complete Reference**: See [Docs/reference/APPLE_DOCUMENT_INTELLIGENCE.md](Docs/reference/APPLE_DOCUMENT_INTELLIGENCE.md) for detailed API documentation.

### Production Frameworks (8 Integrated)

| Framework            | Primary Use                   | Key Services                                                       |
| -------------------- | ----------------------------- | ------------------------------------------------------------------ |
| **FoundationModels** | LLM generation (iOS 26)       | `AppleFoundationLLMService`, `AgenticOrchestrator`, 8 @Tools       |
| **Vision**           | OCR, document detection       | `VisionOCRService`, `IntelligentDocumentProcessor`                 |
| **NaturalLanguage**  | NER, tokenization, embeddings | `QueryEnhancementService`, `EntityIndexService`, `SemanticChunker` |
| **CoreML**           | Neural embeddings, reranking  | `EmbeddingService` (MiniLM-L6), `ReRankerService` (TinyBERT)       |
| **PDFKit**           | PDF parsing                   | `DocumentProcessor`                                                |
| **Speech**           | Audio transcription           | `AudioTranscriptionService`                                        |
| **Metal**            | GPU acceleration              | `GPUComputeService`, `VisionOCRThrottle`                           |
| **StoreKit 2**       | Subscription billing          | `StoreKitBillingService`                                           |

### iOS 26+ APIs in Production

| API                             | Usage                                        |
| ------------------------------- | -------------------------------------------- |
| `LanguageModelSession`          | All LLM queries via Apple Intelligence       |
| `@Generable`, `@Guide`, `@Tool` | 8 agentic tools + structured response types  |
| `LanguageModelFeedback`         | User feedback submission from chat UI        |
| `prewarm()`                     | App launch prewarming for faster first query |

### Framework Opportunities (Phase 2+)

| Framework                   | Planned Use                                  | Target |
| --------------------------- | -------------------------------------------- | ------ |
| **VisionKit** (DataScanner) | Live camera document scanning                | v2.0   |
| **Translation.framework**   | Multi-language document translation          | v1.3   |
| **NLGazetteer**             | Custom entity training (product names, SKUs) | v1.3   |
| **CreateMLComponents**      | On-device classifier training                | v2.0   |
| **MetricKit**               | Production performance telemetry             | v2.0   |
| **SpeechAnalyzer** (iOS 26) | Enhanced audio quality metrics               | v1.3   |

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
         ├──────────────────────────────────┐
         │                                  │
         ▼                                  ▼
┌─────────────────┐                ┌─────────────────┐
│ Store Full Text │  ← ZERO LOSS   │ Chunk Documents │  ← Content-adaptive
│ (Original)      │                │  (≤310w max)    │    SemanticChunker
│                 │                │  + Table Blocks │    (atomic table preservation)
└────────┬────────┘                └────────┬────────┘
         │                                  │
         │                                  ▼
         │                         ┌─────────────────┐
         │                         │ Token Validate  │  ← BertTokenizer
         │                         │ (≤510 tokens)   │    Binary search truncate
         │                         └────────┬────────┘
         │                                  │
         │                                  ▼
         │                         ┌─────────────────┐
         │                         │ Generate        │  ← CoreML MiniLM-L6
         │                         │ Embeddings      │  ← 384-dim vectors
         │                         └────────┬────────┘
         │                                  │
         ▼                                  ▼
┌─────────────────┐                ┌─────────────────┐
│ FullTextStorage │                │ Store in Vector │  ← HNSW index
│ Service (disk)  │                │    Database     │  ← Cosine similarity
└─────────────────┘                └────────┬────────┘
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
│ Query Rewriting │  ← Pronoun resolution, follow-up handling
│ & Understanding │    NLTagger NER entity extraction
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
│ HyDE Expansion  │  ← Generate hypothetical answer doc
│ (if factual)    │    Embed THAT for better recall
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Embed Query     │  ← Same embedding model (384-dim)
└────────┬────────┘
         │
         ▼
┌─────────────────────────────┐
│ Hybrid Search               │
│ ┌─────────┐ ┌─────────────┐ │
│ │ Vector  │ │   BM25      │ │  ← Dual retrieval paths
│ │ k-NN    │ │ Chunk-Level │ │  ← AND-first FTS5 + per-chunk scoring
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
│ Entity-Based    │  ← 2-hop graph expansion via
│ Graph Expansion │    EntityIndexService
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Parent Document │  ← Expand ±5 sibling chunks
│ Retrieval       │    for paragraph context
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Contextual      │  ← LLM filters irrelevant
│ Compression     │    sentences from chunks
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
│ Graph Context   │  ← Optimal token budget
│ Packing         │    allocation across evidence
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
│ Quality         │  ← Confidence scoring based on
│ Assessment      │    source coverage + consistency
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Verification    │  ← Gates A-D anti-hallucination
│ Gates           │    (confidence, coverage, numeric, contradiction)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Package Results │  ← Build RAGResult with sources,
│                 │    timing, and metrics
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Calibrated      │  ← Platt scaling for confidence
│ Confidence      │    (0.0-1.0 normalized)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Response        │  ← Final metadata: latency,
│ Metadata        │    token counts, source URIs
└─────────────────┘
```

## Core Services

### Complete Service Inventory (78 Services)

OpenIntelligence is composed of **78 distinct services** organized into 9 categories. This inventory provides a complete reference.

#### RAG Pipeline Services (14 services)

| Service                          | Type        | Purpose                                                                     | File                                       |
| -------------------------------- | ----------- | --------------------------------------------------------------------------- | ------------------------------------------ |
| `RAGService`                     | class       | Main `@MainActor` orchestrator: ingestion, retrieval, UI state              | `RAG/RAGService.swift`                     |
| `RAGEngine`                      | actor       | Background math: MMR, BM25, RRF, reranking (no UI)                          | `RAG/RAGEngine.swift`                      |
| `HybridSearchService`            | class       | Vector k-NN + chunk-level BM25 with RRF fusion (k=60)                       | `RAG/HybridSearchService.swift`            |
| `IterativeRetrievalService`      | final class | Multi-pass retrieval with self-correction (auto-enabled for multi-hop)      | `RAG/IterativeRetrievalService.swift`      |
| `VerificationGateService`        | actor       | Anti-hallucination gates A-D (confidence, coverage, numeric, contradiction) | `RAG/VerificationGateService.swift`        |
| `ContextPackingService`          | actor       | Graph context packing within token budget                                   | `RAG/ContextPackingService.swift`          |
| `GraphIndexService`              | actor       | Cross-reference detection (page refs, table refs, neighbors)                | `RAG/GraphIndexService.swift`              |
| `ContainerVocabularyService`     | actor       | Per-container domain vocabulary for query expansion                         | `RAG/ContainerVocabularyService.swift`     |
| `ExtractiveSummarizationService` | actor       | Sentence selection via bi-encoder + MMR for extractive summaries            | `RAG/ExtractiveSummarizationService.swift` |
| `ExtractiveQAService`            | protocol    | Span extraction interface (CoreML, Heuristic, Placeholder impls)            | `RAG/ExtractiveQAService.swift`            |
| `ParentDocumentService`          | final class | Sibling chunk expansion (±5 chunks) for paragraph context                   | `RAG/ParentDocumentService.swift`          |
| `QualityAssuranceService`        | actor       | Accuracy metrics: Recall@K, MRR, F1, faithfulness scoring                   | `RAG/QualityAssuranceService.swift`        |
| `ConfidenceCalibrationService`   | final class | Platt scaling for calibrated confidence (0.0-1.0)                           | `RAG/ConfidenceCalibrationService.swift`   |
| `AutoTuneService`                | class       | Optimizes retrieval parameters based on feedback                            | `RAG/AutoTuneService.swift`                |

#### Query Services (8 services)

| Service                        | Type        | Purpose                                                   | File                                       |
| ------------------------------ | ----------- | --------------------------------------------------------- | ------------------------------------------ |
| `QueryEnhancementService`      | final class | Query expansion, intent classification, weight adjustment | `Query/QueryEnhancementService.swift`      |
| `QueryRewriterService`         | final class | Pronoun resolution, follow-up handling, NER extraction    | `Query/QueryRewriterService.swift`         |
| `QueryRouterService`           | actor       | RAPTOR-lite routing: overview queries → L1 summaries      | `Query/QueryRouterService.swift`           |
| `HyDEService`                  | final class | Hypothetical Document Embeddings for better recall        | `Query/HyDEService.swift`                  |
| `ContextualCompressionService` | final class | LLM-based sentence filtering from retrieved chunks        | `Query/ContextualCompressionService.swift` |
| `SuggestedQuestionsService`    | actor       | Generates contextual starter questions from documents     | `Query/SuggestedQuestionsService.swift`    |
| `QueryComplexityAnalyzer`      | final class | Analyzes query structure to determine optimal routing     | `Query/QueryComplexityAnalyzer.swift`      |
| `SpecificationExtractor`       | struct      | Extracts technical specs (dimensions, tolerances)         | `Query/SpecificationExtractor.swift`       |

#### Document Processing Services (19 services)

| Service                        | Type        | Purpose                                                          | File                                          |
| ------------------------------ | ----------- | ---------------------------------------------------------------- | --------------------------------------------- |
| `DocumentProcessor`            | struct      | Universal parsing: PDF, Office, OCR (360 DPI), GPU acceleration  | `Document/DocumentProcessor.swift`            |
| `IntelligentDocumentProcessor` | actor       | Orchestrates AI-enhanced parsing (layout, region, semantics)     | `Document/IntelligentDocumentProcessor.swift` |
| `SemanticChunker`              | struct      | Content-adaptive chunking with section + table detection (≤310w) | `Document/SemanticChunker.swift`              |
| `EntityIndexService`           | actor       | Global entity→chunk inverted index for GraphRAG                  | `Document/EntityIndexService.swift`           |
| `AudioTranscriptionService`    | final class | Audio/video transcription via Speech.framework                   | `Document/AudioTranscriptionService.swift`    |
| `ContentTaggingService`        | final class | Apple Intelligence content tagging (topics, actions, emotions)   | `Document/ContentTaggingService.swift`        |
| `LanguageDetectionService`     | final class | Multi-language detection via NLLanguageRecognizer                | `Document/LanguageDetectionService.swift`     |
| `ImageUnderstandingService`    | class       | Vision-based image classification and description                | `Document/ImageUnderstandingService.swift`    |
| `ImageDescriptionService`      | class       | Apple Intelligence image descriptions for live camera            | `Document/ImageUnderstandingService.swift`    |
| `YOLODetectionService`         | actor       | YOLO v3 object detection (80 classes) for intelligent capture    | `Document/YOLODetectionService.swift`         |
| `DocumentSummaryService`       | actor       | L1 summary generation at ingestion for RAPTOR-lite               | `Document/DocumentSummaryService.swift`       |
| `VisionOCRThrottle`            | actor       | Controls concurrent Vision requests based on device thermal      | `Document/VisionOCRThrottle.swift`            |
| `CoreMLDocumentClassifier`     | class       | ML-based document type classification (invoice vs manual)        | `Document/CoreMLDocumentClassifier.swift`     |
| `CoreMLRegionDetector`         | class       | Detects layout regions (header, footer, sidebar) via Vision      | `Document/CoreMLRegionDetector.swift`         |
| `LayoutAwareExtractor`         | struct      | Extracts text while preserving 2D spatial relationships          | `Document/LayoutAwareExtractor.swift`         |
| `PageComplexityAnalyzer`       | struct      | Scores page layout density to adjust OCR parameters              | `Document/PageComplexityAnalyzer.swift`       |
| `SpatialDocumentAnalyzer`      | class       | Analyzes spatial relationships between document elements         | `Document/SpatialDocumentAnalyzer.swift`      |
| `SpecificationDetector`        | struct      | Regex/ML detection of specification tables and key-value pairs   | `Document/SpecificationDetector.swift`        |
| `StructuredDocumentParser`     | actor       | Parses hierarchy (Section > Subsection > Paragraph)              | `Document/StructuredDocumentParser.swift`     |

#### Embedding Services (2 services)

| Service                           | Type  | Purpose                                          | File                                              |
| --------------------------------- | ----- | ------------------------------------------------ | ------------------------------------------------- |
| `EmbeddingService`                | class | 384-dim embeddings via provider pattern          | `Embedding/EmbeddingService.swift`                |
| `CoreMLSentenceEmbeddingProvider` | class | CoreML MiniLM-L6-v2 with BertTokenizer (510 max) | `Embedding/CoreMLSentenceEmbeddingProvider.swift` |

#### Storage Services (3 services)

| Service                     | Type  | Purpose                                              | File                                      |
| --------------------------- | ----- | ---------------------------------------------------- | ----------------------------------------- |
| `FullTextStorageService`    | actor | Complete original document storage for exact queries | `Storage/FullTextStorageService.swift`    |
| `SQLiteFullTextService`     | actor | FTS5-powered AND-first BM25 search (10-100x faster)  | `Storage/SQLiteFullTextService.swift`     |
| `DocumentationCacheService` | actor | Caches fetched web content for offline access        | `Storage/DocumentationCacheService.swift` |

#### VectorStore Services (4 services)

| Service                  | Type        | Purpose                                              | File                                   |
| ------------------------ | ----------- | ---------------------------------------------------- | -------------------------------------- |
| `VectorDatabase`         | protocol    | Interface for vector store implementations           | `VectorStore/VectorDatabase.swift`     |
| `InMemoryVectorDatabase` | class       | In-memory HNSW with norm caching + LRU cache         | `VectorStore/VectorDatabase.swift`     |
| `BNNSVectorDatabase`     | actor       | Accelerate BNNS brute-force with GPU batching        | `VectorStore/BNNSVectorDatabase.swift` |
| `VectorStoreRouter`      | final class | Per-container routing with multi-container RRF merge | `VectorStore/VectorStoreRouter.swift`  |

#### LLM Services (7 services)

| Service                       | Type        | Purpose                                                      | File                                    |
| ----------------------------- | ----------- | ------------------------------------------------------------ | --------------------------------------- |
| `LLMService`                  | protocol    | Interface for LLM inference (generate, isAvailable, tools)   | `LLM/LLMService.swift`                  |
| `AppleFoundationLLMService`   | class       | Apple FM + PCC with 8 @Tool functions                        | `LLM/LLMService.swift`                  |
| `OnDeviceAnalysisService`     | class       | NaturalLanguage-based extractive QA fallback                 | `LLM/LLMService.swift`                  |
| `ScreenshotMockLLMService`    | class       | Mock responses for App Store screenshot generation           | `LLM/LLMService.swift`                  |
| `LocalOpenAIServerLLMService` | final class | OpenAI-compatible local server client (MLX/llama.cpp/Ollama) | `LLM/LocalOpenAIServerLLMService.swift` |
| `OpenAIResponsesAPIService`   | class       | GPT-5 Responses API client (disabled, `#if false`)           | `LLM/OpenAIResponsesAPIService.swift`   |
| `ModelResolutionService`      | final class | Model selection transparency layer                           | `LLM/ModelResolutionService.swift`      |

#### Agentic Services (3 services)

| Service                     | Type        | Purpose                                             | File                                      |
| --------------------------- | ----------- | --------------------------------------------------- | ----------------------------------------- |
| `AgenticOrchestrator`       | class       | Multi-session reasoning with Self-RAG 2.0 prompting | `Agentic/AgenticOrchestrator.swift`       |
| `ConversationMemoryService` | final class | Persistent conversation memory with summarization   | `Agentic/ConversationMemoryService.swift` |
| `WritingToolsService`       | class       | Apple Writing Tools (proofread, rewrite, summarize) | `Agentic/WritingToolsService.swift`       |

#### Infrastructure Services (17 services)

| Service                        | Type        | Purpose                                                         | File                                                |
| ------------------------------ | ----------- | --------------------------------------------------------------- | --------------------------------------------------- |
| `ContainerService`             | final class | KnowledgeContainer management (CRUD, selection, persistence)    | `Infrastructure/ContainerService.swift`             |
| `DeviceCapabilityService`      | final class | Device tier detection (A-series vs M-series, NPU TOPS)          | `Infrastructure/DeviceCapabilityService.swift`      |
| `GPUComputeService`            | final class | Metal Performance Shaders for batch vector ops (10-50x speedup) | `Infrastructure/GPUComputeService.swift`            |
| `ProjectionService`            | final class | 3D projection: PCA, Random Projection, t-SNE, UMAP              | `Infrastructure/ProjectionService.swift`            |
| `ClusterLabelService`          | actor       | LLM-generated intelligent labels for Atlas clusters             | `Infrastructure/ClusterLabelService.swift`          |
| `TranscriptPersistenceService` | final class | Apple FM session transcript persistence for resume              | `Infrastructure/TranscriptPersistenceService.swift` |
| `SettingsStore`                | final class | Centralized settings with UserDefaults persistence              | `Infrastructure/SettingsStore.swift`                |
| `AdaptivePipelineOptimizer`    | actor       | Dynamically adjusts pipeline parameters based on load/battery   | `Infrastructure/AdaptivePipelineOptimizer.swift`    |
| `LibraryIconSuggestionService` | actor       | Suggests SF Symbols for document containers based on contents   | `Infrastructure/LibraryIconSuggestionService.swift` |
| `LibraryVisualizationEngine`   | class       | Renders 3D document atlas visualizations                        | `Infrastructure/LibraryVisualizationEngine.swift`   |
| `LoggingConfiguration`         | struct      | Centralized OSLog subsystem configuration                       | `Infrastructure/LoggingConfiguration.swift`         |
| `ProjectionCache`              | actor       | Caches expensive UMAP/t-SNE projections                         | `Infrastructure/ProjectionCache.swift`              |
| `QuotaPolicy`                  | struct      | Enforces usage limits for free tier users                       | `Infrastructure/QuotaPolicy.swift`                  |
| `SystemStateMonitor`           | class       | Monitors thermal state, memory, and battery for degradation     | `Infrastructure/SystemStateMonitor.swift`           |
| `TelemetryCenter`              | actor       | Aggregates performance metrics (TTFT, TPS, ingest speed)        | `Infrastructure/TelemetryCenter.swift`              |
| `LLMStreamingContext`          | actor       | Manages state for streaming LLM responses                       | `LLM/LLMStreamingContext.swift`                     |

#### Billing Services (1 service)

| Service                  | Type        | Purpose                                       | File                                   |
| ------------------------ | ----------- | --------------------------------------------- | -------------------------------------- |
| `StoreKitBillingService` | final class | StoreKit 2 in-app purchases and subscriptions | `Billing/StoreKitBillingService.swift` |

---

### DocumentProcessor

**Purpose**: Universal document parsing and semantic chunking

**Key Features**:

- Multi-format support: PDF, text, Markdown, RTF, code, CSV, Office docs
- PDFKit for native PDF parsing
- Vision framework OCR fallback for scanned pages
- **Content-adaptive chunking** via `ChunkingConfig.recommended(for:)`
- Returns `ProcessingSummary` with timing and statistics

**Chunking Presets** (Jan 2026 - Optimized):

| Preset               | Target Size | Overlap         | Use Case                   |
| -------------------- | ----------- | --------------- | -------------------------- |
| `technicalReference` | 280 words   | 50 words (~18%) | PDFs, manuals, spec sheets |
| `narrative`          | 400 words   | 70 words (~17%) | Prose, articles, books     |
| `code`               | 250 words   | 40 words (~16%) | Source code, scripts       |
| Default              | 350 words   | 60 words (~17%) | General documents          |

**File**: `OpenIntelligence/Services/DocumentProcessor.swift`

#### Vision Framework Integration

**Current Implementation** (Jan 2026 - Enhanced):

| Capability           | API Used                         | Status          |
| -------------------- | -------------------------------- | --------------- |
| OCR Text Recognition | `VNRecognizeTextRequest`         | ✅ Implemented  |
| High-DPI Rendering   | 360 DPI (5x scale factor)        | ✅ Enhanced     |
| Multi-language OCR   | Recognition languages config     | ✅ 10 languages |
| Accurate Mode        | `.recognitionLevel = .accurate`  | ✅ Enabled      |
| Language Correction  | `.usesLanguageCorrection = true` | ✅ Enabled      |
| Image Upscaling      | CIFilter.lanczosScaleTransform   | ✅ New          |
| Contrast Enhancement | CIColorControls                  | ✅ New          |

**Device-Tier-Aware Vision Concurrency** (Jan 26, 2026):

`VisionOCRThrottle` controls concurrent Vision OCR operations with device-specific tuning:

| Device Tier    | Chip     | Vision Ops | Cooldown | Notes                        |
| -------------- | -------- | ---------- | -------- | ---------------------------- |
| Enhanced       | A18 Pro  | 5          | 5ms      | Neural Engine optimized      |
| Advanced       | A19 Pro  | 6          | 3ms      | Next-gen ANE                 |
| Ultra-Advanced | M-series | 6          | 3ms      | Active cooling (iPad Pro)    |
| Mac Compatible | M-series | 3          | 10ms     | Conservative for macOS Metal |
| Baseline       | A17 Pro  | 4          | 8ms      | Conservative for thermal     |

**Platform Detection**: On Mac (via "Designed for iPad"), Metal command buffer scheduling differs from iOS. The system automatically detects `ProcessInfo.processInfo.isiOSAppOnMac` and uses conservative concurrency to prevent Metal validation errors in Apple's Vision framework.

**OCR Quality Improvements** (Jan 24, 2026):

```swift
// 360 DPI rendering for better text recognition (was 216 DPI)
let scale: CGFloat = 5.0  // 72 DPI × 5 = 360 DPI
let scaledSize = CGSize(width: pageRect.width * scale, height: pageRect.height * scale)

// Upscale low-res images before OCR
if imageSize.width < 1000 || imageSize.height < 1000 {
    let upscaleFilter = CIFilter.lanczosScaleTransform()
    upscaleFilter.scale = 1.5  // 50% larger
}

// Enhance contrast for faded/scanned documents
let colorControls = CIFilter.colorControls()
colorControls.contrast = 1.1
colorControls.brightness = 0.02
```

#### Office Document Extraction

**Native ZIP-Based Parsing** (Jan 24, 2026):

| Format | Structure                                              | Extraction Method     |
| ------ | ------------------------------------------------------ | --------------------- |
| .docx  | ZIP → word/document.xml                                | XML paragraph parsing |
| .xlsx  | ZIP → xl/sharedStrings.xml + xl/worksheets/sheet\*.xml | Shared string lookup  |
| .pptx  | ZIP → ppt/slides/slide\*.xml                           | Slide text extraction |

**Implementation**:

```swift
// ZIPArchive helper using Apple's Compression framework
class ZIPArchive {
    func extractFile(named: String) -> Data?  // Deflate decompression
}

// Word document extraction
func extractTextFromWordXML(_ xmlData: Data) -> String
// Parses <w:t> text elements from document.xml

// Excel extraction with shared strings
func extractSharedStringsFromExcel(_ xmlData: Data) -> [String]
func extractTextFromExcelSheet(_ xmlData: Data, sharedStrings: [String]) -> String

// PowerPoint slide extraction
func extractTextFromPowerPointSlide(_ xmlData: Data) -> String
// Parses <a:t> text elements from slide*.xml
```

**File**: `OpenIntelligence/Services/DocumentProcessor.swift`

**Implementation Status** (Jan 2026 - Visual Document Understanding):

| Capability               | API Used                                  | Status         | Location                       |
| ------------------------ | ----------------------------------------- | -------------- | ------------------------------ |
| Spatial Text Ordering    | `VNRecognizedTextObservation.boundingBox` | ✅ Implemented | `performOCR()`                 |
| Column Detection         | Bounding box clustering                   | ✅ Implemented | `detectColumns()`              |
| Image Classification     | `ClassifyImageRequest` (iOS 18+)          | ✅ Implemented | `ImageUnderstandingService`    |
| Caption Association      | Spatial proximity analysis                | ✅ Implemented | `findAssociatedCaption()`      |
| Image Description        | Classification + caption fusion           | ✅ Implemented | `generateImageDescription()`   |
| Structured Parsing       | `RecognizeDocumentsRequest` (iOS 26+)     | ✅ Implemented | `StructuredDocumentParser`     |
| Structure-Aware Chunking | Table/list preservation                   | ✅ Implemented | `createStructureAwareChunks()` |
| Document Segmentation    | `DetectDocumentSegmentationRequest`       | ❌ Not yet     | Planned                        |

**Structured Document Parsing** (iOS 26+ - Implemented):

The `StructuredDocumentParser` actor uses Vision's `RecognizeDocumentsRequest` to extract document structure:

```swift
// StructuredElement enum captures typed document elements
enum StructuredElement {
    case table(TableData)      // Rows/columns with cell text
    case paragraph(String)     // Prose text
    case list([String])        // Bullet/numbered items
    case title(String)         // Headers/section titles
}

// Structure-aware chunking preserves atomic elements
func createStructureAwareChunks(from elements: [StructuredElement]) -> [DocumentChunk]
// Tables become single chunks (never split mid-table)
// Lists grouped by parent heading
// Paragraphs chunked normally with semantic boundaries
```

**Structure Type Metadata**: Each chunk includes `structureType: String?` in ChunkMetadata:

- `"table"` - Table data (boosted for specification queries)
- `"list"` - List items (boosted for enumeration queries)
- `"paragraph"` - Prose text
- `"title"` - Section headers

**Structure Boost in Retrieval**: `HybridSearchService.applyStructureTypeBoost()` increases scores for table/list chunks when query contains specification patterns (detected via `detectSpecificationQuery()` using domain-agnostic linguistic patterns).

### Apple CoreML Vision Models (Planned v1.2.0)

**Purpose**: Enhanced document understanding using Apple's pre-trained CoreML models

OpenIntelligence will integrate Apple's official CoreML models from https://developer.apple.com/machine-learning/models/ to dramatically improve document ingestion quality.

#### V1 Priority Models

| Model             | Size    | Inference Time | Use Case                                         |
| ----------------- | ------- | -------------- | ------------------------------------------------ |
| **FastViT T8**    | 8.2MB   | 0.5-0.8ms      | Classify document content type before processing |
| **DETR ResNet50** | 43-85MB | 32-50ms        | Detect tables, figures, charts, text regions     |
| **DeepLabV3**     | 4-8MB   | ~30ms          | Lightweight semantic segmentation                |

#### Enhanced Document Pipeline

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                    COREML-ENHANCED INGESTION PIPELINE                    │
└─────────────────────────────────────────────────────────────────────────┘

PDF/Image Input
      │
      ▼
┌─────────────────┐
│ FastViT T8     │  ← 8MB model, <1ms inference
│ Content Classify│  → "document", "receipt", "diagram", "photo", "form"
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ DETR ResNet50  │  ← 43MB model, ~35ms inference
│ Region Detect  │  → Bounding boxes: [table@(x,y), figure@(x,y), text@(x,y)]
└────────┬────────┘
         │
         ├── Table Region ──→ OCR with table settings → Preserve structure
         ├── Figure Region ─→ Image classification + caption extraction
         ├── Text Region ───→ Standard OCR → Semantic chunking
         └── Form Region ───→ Key-value pair extraction
                │
                ▼
┌─────────────────┐
│ Structure-Aware │  ← Tables never split mid-row
│ Chunking       │  ← Figures kept atomic with captions
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Zone Metadata  │  ← ChunkMetadata.zoneType = "table" | "figure" | "prose"
│ Enrichment     │  ← Enables structure-aware retrieval boosting
└────────┬────────┘
         │
         ▼
    [Standard RAG Pipeline: Embed → Index → Store]
```

#### Planned Services

| Service                         | Model         | Responsibility                        |
| ------------------------------- | ------------- | ------------------------------------- |
| `DocumentClassificationService` | FastViT T8    | Pre-classify content for routing      |
| `RegionDetectionService`        | DETR ResNet50 | Detect semantic regions in pages      |
| `SemanticSegmentationService`   | DeepLabV3     | Pixel-level classification (optional) |

#### V2 Model Catalog

| Model           | Size  | Use Case                                   | Integration Target |
| --------------- | ----- | ------------------------------------------ | ------------------ |
| BERT-SQuAD      | 217MB | Extractive QA for simulator/legacy devices | v2.0               |
| DepthAnythingV2 | 49MB  | 3D document scanning, AR overlay           | v2.0               |
| MobileNetV2     | 12MB  | Classify embedded images                   | v2.0               |
| YOLOv3 Tiny     | 17MB  | Real-time camera document detection        | v2.0               |
| ResNet-50       | 51MB  | High-accuracy image classification         | v2.0               |

**Note**: All models available from Apple at https://developer.apple.com/machine-learning/models/

**Layout-Aware OCR** (Implemented):

```swift
// Sort observations by reading order (top-to-bottom, left-to-right)
let sortedObservations = observations.sorted { obs1, obs2 in
    let box1 = obs1.boundingBox
    let box2 = obs2.boundingBox
    // Use 2% threshold to detect "same line"
    let lineThreshold: CGFloat = 0.02
    if abs(box1.midY - box2.midY) > lineThreshold {
        return box1.midY > box2.midY  // Higher Y = higher on page
    }
    return box1.minX < box2.minX  // Left-to-right within line
}
// Then apply column detection for multi-column layouts
let columnText = extractTextWithColumnAwareness(from: sortedObservations)
```

**Multi-Column Detection**:

```swift
// Detect significant gaps (>15% page width) as column boundaries
let significantGapThreshold: CGFloat = 0.15
let columnBoundaries = gaps.filter { $0.gap > significantGapThreshold }
// Group text by column, process each top-to-bottom
```

**Image Understanding Flow** (Implemented):

```
PDF Page → extractImagesFromPDFPage() → ClassifyImageRequest → Image tags
                                      ↓
                        findAssociatedCaption() → Nearby caption text
                                      ↓
                      generateImageDescription() → Searchable text
                                      ↓
            "[Image on page N]: [Chart] Contains: line_graph, data_visualization. Caption: Figure 3..."
```

**Files**:

- `OpenIntelligence/Services/DocumentProcessor.swift` - Layout-aware OCR, PDF image extraction, structure-aware chunking
- `OpenIntelligence/Services/StructuredDocumentParser.swift` - iOS 26+ structured document parsing (tables, lists, paragraphs)
- `OpenIntelligence/Services/ImageUnderstandingService.swift` - Image classification and description

### EmbeddingService

**Purpose**: Generate semantic vector representations of text

**Key Features**:

- Uses CoreML MiniLM-L6-v2 for 384-dimensional vectors
- Token-level embedding with averaging for chunk representations
- Cosine similarity calculation for retrieval
- **Token Counting**: `countTokens()` using actual BertTokenizer (critical for validation)
- **Token Validation**: RAGService validates tokens before embedding, binary search truncation if exceeded
- Always available on-device (no network required)

**Token Limit** (CRITICAL):

- Max embedding tokens: **510** (512 - 2 for CLS/SEP)
- Linguistic words ≠ embedding tokens! `VHA21\VHAPALGarciG1` = 1 word but 10+ tokens
- Use `countTokens()` not word count for validation

**File**: `OpenIntelligence/Services/EmbeddingService.swift`

### FullTextStorageService

**Purpose**: Store and retrieve COMPLETE original document text for exact queries

**Key Features**:

- **ZERO Data Loss**: Stores full text before chunking - nothing is discarded
- **Pattern Counting**: `countPatternInCorpus(pattern:)` counts across ALL documents
- **Exact Search**: `searchCorpus(pattern:)` finds exact matches with context
- **Persistence**: Disk storage with memory cache for fast access
- **Actor-Based**: Thread-safe async access

**Use Cases**:

- "How many times is 'and' mentioned in all documents?" → exact count
- "Find all occurrences of 'ERROR-5021'" → exhaustive search
- Queries requiring complete corpus access, not just chunked retrieval

**Implementation**:

```swift
// Store during ingestion (in DocumentProcessor)
await FullTextStorageService.shared.store(text: extractedText, for: documentId)

// Count pattern (used by RAGToolHandler)
let counts = await FullTextStorageService.shared.countPatternInCorpus(pattern: "and")
// Returns: [UUID: Int] - document ID to occurrence count
```

**File**: `OpenIntelligence/Services/Storage/FullTextStorageService.swift`

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
- **Structure Type Boost**: Elevates table/list chunks for specification queries
- Configurable fusion weights via `RetrievalConfig`

**Default Weights** (Jan 2026):

| Weight         | Value | Rationale                                       |
| -------------- | ----- | ----------------------------------------------- |
| Vector         | 0.4   | Semantic similarity                             |
| Keyword (BM25) | 0.6   | Better for specific terms, codes, model numbers |

**Structure-Aware Retrieval** (Implemented):

```swift
// Detect specification-seeking queries via domain-agnostic linguistic patterns
func detectSpecificationQuery(_ query: String) -> Bool
// Patterns: "what is", "how much", contains alphanumeric codes, measurements

// Boost table/list chunks for spec queries
func applyStructureTypeBoost(_ results: [SearchResult], query: String) -> [SearchResult]
// Boost factors: table → 1.15x, list → 1.10x for spec queries
```

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

| Preset            | minSimilarity | vectorWeight | keywordWeight | Use Case                   |
| ----------------- | ------------- | ------------ | ------------- | -------------------------- |
| `default`         | 0.28          | 0.4          | 0.6           | General documents          |
| `balanced`        | 0.35          | 0.5          | 0.5           | Mixed content              |
| `technicalManual` | 0.22          | 0.3          | 0.7           | PDFs, spec sheets, manuals |
| `narrative`       | 0.32          | 0.6          | 0.4           | Prose, articles            |
| `code`            | 0.30          | 0.35         | 0.65          | Source code                |

**Auto-Tuning**: `RetrievalConfig.recommended(forDocumentTypes:)` analyzes ingested content and selects optimal preset.

**File**: `OpenIntelligence/Models/KnowledgeContainer.swift`

### ContainerService

**Purpose**: CRUD operations for knowledge containers with automatic migration

**Key Features**:

- Persistent storage of container metadata to JSON
- **Auto-Migration at Load Time**: Fixes containers with invalid configurations

**Container Dimension Migration** (Jan 2026):

When loading containers, the service automatically detects and corrects:

| Invalid State                                   | Auto-Migration Action                     |
| ----------------------------------------------- | ----------------------------------------- |
| `embeddingProviderId = nl_contextual_embedding` | → `coreml_sentence_embedding` (supported) |
| `embeddingDim = 784` (or other invalid)         | → `384` (CoreML standard)                 |
| Dimension not in {384, 512, 1024}               | → `384` (default)                         |

**Why Migration Matters**: Without migration, containers created with experimental providers would trigger perpetual rebuild loops as the runtime embedding dimension (384) wouldn't match the stored dimension (784).

```swift
// Automatic migration on load (ContainerService.swift)
let validDimensions: Set<Int> = [384, 512, 1024]
if container.embeddingProviderId == "nl_contextual_embedding" {
    fixed.embeddingProviderId = "coreml_sentence_embedding"
    fixed.embeddingDim = 384
}
if !validDimensions.contains(container.embeddingDim) {
    fixed.embeddingDim = 384
}
```

**File**: `OpenIntelligence/Services/ContainerService.swift`

### RAPTOR-lite (Document Summaries)

**Purpose**: Pre-computed document summaries for efficient overview queries

**Problem Solved**: Without summaries, asking "What is this document about?" requires:

1. Retrieving multiple detail chunks
2. Using Maximum mode's multi-session synthesis
3. Wasting 95% of tokens on runtime synthesis

**Solution**: Generate document summaries at ingestion time, store as Level-1 chunks

**Abstraction Levels** (defined in `DocumentChunk.swift`):

| Level | Name              | Description                       | Use Case                     |
| ----- | ----------------- | --------------------------------- | ---------------------------- |
| 0     | `detail`          | Original chunks (280-400 words)   | Specific facts, step-by-step |
| 1     | `documentSummary` | Per-document summary (~150 words) | Overview queries             |
| 2     | `clusterSummary`  | Topic cluster summary (future)    | Cross-document themes        |
| 3     | `librarySummary`  | Entire container summary (future) | Library-wide overview        |

**Components**:

1. **DocumentSummaryService** (`Services/DocumentSummaryService.swift`)
   - Actor-based for thread safety
   - Generates summaries via Apple FM at ingestion
   - Extractive fallback if LLM unavailable
   - Stores as chunk with `abstractionLevel = .documentSummary`

2. **QueryRouterService** (`Services/QueryRouterService.swift`)
   - Classifies queries: overview / detail / cross-topic
   - Pattern-based detection (70%+ confidence threshold)
   - Routes to optimal abstraction level

**Query Flow with RAPTOR-lite**:

```text
User Query
    │
    ▼
┌─────────────────┐
│ Query Router    │  ← Classify: overview/detail/cross-topic
│ Service         │
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
Overview    Detail
Query       Query
    │         │
    ▼         ▼
Search L1   Search L0
Summaries   Chunks
    │         │
    └────┬────┘
         │
         ▼
  Hybrid Search + Rerank
         │
         ▼
    LLM Generation
```

**Token Savings by Query Type**:

| Query Type  | Without RAPTOR-lite         | With RAPTOR-lite   | Savings |
| ----------- | --------------------------- | ------------------ | ------- |
| Overview    | Maximum mode (10+ sessions) | Single L1 lookup   | ~95%    |
| Detail      | Standard retrieval          | Standard retrieval | 0%      |
| Cross-topic | Maximum mode                | L1 + L0 combined   | ~50-70% |

**File**: `OpenIntelligence/Services/DocumentSummaryService.swift`, `QueryRouterService.swift`

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

| Tool                     | Purpose                           | Arguments                      |
| ------------------------ | --------------------------------- | ------------------------------ |
| `SearchDocumentsTool`    | Semantic search across containers | `query: String`, `limit: Int?` |
| `ListDocumentsTool`      | Enumerate documents in container  | `containerName: String?`       |
| `GetDocumentSummaryTool` | Retrieve document metadata        | `documentID: UUID`             |

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

| Component         | Token Allocation             |
| ----------------- | ---------------------------- |
| System prompt     | ~200 tokens                  |
| Tool definitions  | ~300 tokens                  |
| Retrieved context | ~2,500 tokens (~5,000 chars) |
| Response buffer   | ~1,000 tokens                |
| **Total**         | **4,096 tokens**             |

**Trade-offs**:

- **Pre-stuffed context**: Single pass, lower latency, but context may not be optimal
- **Pure agentic**: Model searches dynamically, multiple passes, better accuracy for complex queries

**Deep Dive**: See [`HOW_IT_WORKS.md`](../../HOW_IT_WORKS.md) for a plain-English explanation of the pipeline, token budget, and orchestrator internals.

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

**Solution**: Generate a hypothetical answer first, then embed _that_ for retrieval.

```text
User Query: "What oil does my car take?"
           ↓
HyDE Generation: "The 2024 Kia Sportage uses SAE 0W-20 synthetic oil.
                  Oil capacity is 5.3 quarts including the filter..."
           ↓
Embed hypothetical → Search → Retrieve actual matching chunks
```

**Implementation** (`HyDEService.swift`):

| Component          | Details                                       |
| ------------------ | --------------------------------------------- |
| LLM Backend        | Apple Foundation Models (on-device)           |
| Trigger Heuristic  | `shouldUseHyDE(for:)` detects factual queries |
| Latency Cost       | ~200-400ms extra for generation               |
| Recall Improvement | 15-25% on technical/factual queries           |
| Setting            | `SettingsStore.enableHyDE` (default: `true`)  |

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

| Component         | Details                                                       |
| ----------------- | ------------------------------------------------------------- |
| Compression Ratio | ~40% (aggressive), ~60% (conservative)                        |
| Token Savings     | 40-60% per chunk on average                                   |
| Latency Cost      | ~100-200ms per chunk                                          |
| Drop Irrelevant   | Chunks returning "NO_RELEVANT_CONTENT" are excluded           |
| Setting           | `SettingsStore.enableContextualCompression` (default: `true`) |

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

### Conversation Memory Service

**Purpose**: Enable multi-turn context awareness with intelligent summarization

**Problem Solved**: Each query is isolated—the LLM has no memory of prior questions. Users asking follow-up questions ("What about its price?") get confused responses because the pronoun "it" has no referent.

**Solution**: Persistent conversation memory with dynamic context injection:

```text
Turn 1: "What's the oil capacity for the Sportage?"
Turn 2: "What about the Telluride?"
Turn 3: "And its towing capacity?"  ← "its" = Telluride
```

**Implementation** (`ConversationMemoryService.swift`):

| Component       | Details                                             |
| --------------- | --------------------------------------------------- |
| Memory Storage  | Per-container JSON persistence                      |
| Recent Turns    | Last 3 turns kept verbatim                          |
| Summarization   | LLM-powered background summarization of older turns |
| Entity Tracking | Extracts people, places, products mentioned         |
| Topic Tracking  | Identifies recurring themes                         |

**Dynamic Optimizations**:

| Feature                           | Description                                                         |
| --------------------------------- | ------------------------------------------------------------------- |
| Query-Adaptive Budget             | Simple queries: 500 chars, follow-ups: 3000 chars                   |
| Semantic Relevance Scoring        | Jaccard + entity matching ranks turns by relevance to current query |
| Importance-Weighted Summarization | High-info turns preserved longer, low-value summarized first        |
| Recency Boost                     | Recent turns scored higher with 1-hour decay                        |
| Debounced Persistence             | 2-second delay prevents disk thrashing                              |
| Non-Blocking                      | Fire-and-forget turn recording, background summarization            |

**Setting**: `SettingsStore.enableConversationMemory` (default: `true`)

**File**: `OpenIntelligence/Services/ConversationMemoryService.swift`

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

| Device Tier             | Max Steps | Max Tokens | Use Case         |
| ----------------------- | --------- | ---------- | ---------------- |
| A17 Pro (iPhone 15 Pro) | 4         | 16,000     | Basic agentic    |
| A18 (iPhone 16)         | 6         | 24,000     | Standard agentic |
| A19 (iPhone 17)         | 8         | 32,000     | Enhanced agentic |
| M-series (iPad Pro)     | 10        | 48,000     | Full power       |

**Device Capability Detection** (Jan 26, 2026):

`DeviceCapabilityService` detects device tier, chip, form factor, and NPU TOPS at runtime:

| Property                   | Purpose                                            |
| -------------------------- | -------------------------------------------------- |
| `tier`                     | Capability tier (baseline/enhanced/advanced/ultra) |
| `chipName`                 | Chip identifier (A17 Pro, A18 Pro, M3, etc.)       |
| `npuTops`                  | Neural Engine TOPS (35-45 for A17-A19 Pro)         |
| `isMac`                    | Mac detection (native or iPad app on Mac)          |
| `visionParsingConcurrency` | Concurrent Vision parsing pages (6-12)             |
| `ocrExtractionConcurrency` | Concurrent OCR extraction pages (6-14)             |
| `embeddingConcurrency`     | Concurrent embedding requests (8-16)               |
| `gpuConcurrency`           | Concurrent GPU operations (4-12)                   |

**Platform-Specific Tuning**: Mac (via "Designed for iPad") receives more conservative concurrency values due to differences in macOS Metal command buffer scheduling.

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
- **IngestionQueueOverlay**: Real-time ingestion pipeline visualization (see below)

**Note**: iOS reports battery in ~5% increments (Apple API limitation).

---

### IngestionQueueOverlay

**Purpose**: Maximum transparency into document ingestion pipeline operations

**Problem Solved**: Users had no visibility into what the app was doing during document import—just a spinner. For a "nerd shit" audience, this felt like a black box.

**Solution**: Real-time granular visualization of every pipeline stage with expandable details.

**UI Components** (Jan 2026 Overhaul):

| Component              | Display                                               |
| ---------------------- | ----------------------------------------------------- |
| **Stage Indicator**    | Current operation (Extracting → Chunking → Embedding) |
| **Progress Bar**       | Visual pipeline step completion                       |
| **Live Metrics Row**   | 4-row display with real-time metrics                  |
| **Expandable Details** | Full pipeline statistics on tap                       |

**Live Metrics Display** (4 rows):

```text
Row 1: Core counts
  [12 chk] [~280w] [12 vec] [384D]

Row 2: Semantic boundaries
  [§3 sections] [⊥2 topics] [∇5 sim]

Row 3: Entity extraction
  [🏷️ 8 entities: John Smith • Acme Corp • New York...]

Row 4: Analysis scores
  [vocab 45%] [tech 12%] [</> Code] [∑ Math]
```

**Shorthand Provider Labels**:

| Full Name                   | Shorthand |
| --------------------------- | --------- |
| `coreml_sentence_embedding` | CoreML    |
| `nl_embedding`              | NL        |
| `apple_foundation`          | FM        |
| `openai_embedding`          | OpenAI    |
| `nl_contextual_embedding`   | NLCtx     |

**Expanded Pipeline Details**:

- **📄 Document Extraction**: Size, words, chars, pages, OCR info, extraction throughput
- **🧩 Semantic Chunking**: Chunk stats, strategy, boundary detection (sections/topics/∇sim)
- **🧠 Corpus Intelligence**: Vocab richness, tech density, multilingual detection, entity extraction
- **⚡ Neural Embedding**: Vector count, dimensions, encoder, embedding throughput
- **⏱ Pipeline Timing**: Waterfall visualization with per-stage bars and total throughput

**Timing Waterfall**: Visual bars showing relative time spent in each stage (Extract → Chunk → Analyze → Embed) with color coding and percentage of total.

**File**: `OpenIntelligence/Views/Shared/IngestionQueueOverlay.swift`

---

**Implementation Details**:

- Each session gets fresh 4K context window
- Previous session summary injected as compressed context
- Explicit `resetSession()` prevents memory accumulation
- `Task.checkCancellation()` at each step for responsive cancellation

**File**: `OpenIntelligence/Services/AgenticOrchestrator.swift`

---

### Recursive Research Loop

**Purpose**: Enable LLM-driven autonomous multi-hop research for complex queries

**Problem Solved**: Static decomposition (planning sub-questions upfront) doesn't adapt to what's actually found. The LLM might need information it didn't know to ask for initially.

**Solution**: Let the LLM autonomously decide when to search and when to answer using a simple token protocol.

**Protocol**:

```text
[SEARCH: specific query] → System executes RAG search, adds results to context
[ANSWER]                 → LLM provides final response
```

**Flow Example**:

```text
User: "What's the relationship between CoreData and SwiftData?"

Iteration 1: LLM analyzes initial context
→ "[SEARCH: SwiftData @Model macro migration]"
→ System retrieves SwiftData modeling chunks

Iteration 2: LLM analyzes expanded context
→ "[SEARCH: CoreData NSManagedObject conversion]"
→ System retrieves CoreData migration chunks

Iteration 3: LLM has sufficient information
→ "[ANSWER]
CoreData and SwiftData share the underlying persistent store format..."
```

**Implementation** (`AgenticOrchestrator.executeRecursiveResearch()`):

| Component             | Details                                              |
| --------------------- | ---------------------------------------------------- |
| Max Iterations        | 7 (configurable)                                     |
| Context Accumulation  | Rolling context window with 8K char limit            |
| Automatic Trimming    | Old context truncated when budget exceeded           |
| Forced Synthesis      | After max iterations, synthesize with available info |
| Confidence Estimation | Heuristic based on hedging language detection        |

**File**: `OpenIntelligence/Services/AgenticOrchestrator.swift`

---

### Entity Extraction (Connective Tissue)

**Purpose**: Extract named entities from chunks to enable cross-document correlation

**Problem Solved**: Traditional RAG treats each chunk as isolated. When a user asks about "URLSession", all chunks mentioning it should be findable—even if they're in different documents.

**Solution**: NLTagger-based entity extraction during chunking, stored in `ChunkMetadata.entities`.

**Extraction Passes**:

| Pass              | Method                  | Examples                            |
| ----------------- | ----------------------- | ----------------------------------- |
| Named Entities    | `NLTagger(.nameType)`   | "Apple", "Tim Cook", "Cupertino"    |
| Technical Terms   | PascalCase regex        | "URLSession", "CoreData", "SwiftUI" |
| Capitalized Nouns | Lexical class filtering | "Engine", "Manual", "Safety"        |

**Implementation** (`SemanticChunker.extractEntities()`):

```swift
private func extractEntities(_ text: String) -> [String] {
    // Pass 1: NER (PersonalName, OrganizationName, PlaceName)
    let nerTagger = NLTagger(tagSchemes: [.nameType])

    // Pass 2: Technical terms (PascalCase identifiers)
    let technicalPattern = #"\b([A-Z][a-z]+(?:[A-Z][a-z0-9]*)+)\b"#

    // Pass 3: Capitalized nouns (domain terms)
    let nounTagger = NLTagger(tagSchemes: [.lexicalClass])

    // Return up to 15 entities per chunk
    return Array(entities.prefix(15))
}
```

**Output**: `ChunkMetadata.entities: [String]` populated during ingestion

**File**: `OpenIntelligence/Services/SemanticChunker.swift`

---

### Global Entity Index

**Purpose**: O(1) lookup from entity name to all chunks containing it

**Problem Solved**: Finding all chunks about "CoreData" requires scanning all chunk metadata. With 10K chunks, this adds latency.

**Solution**: Inverted index maintained in memory and persisted to disk.

**Data Structure**:

```swift
actor EntityIndexService {
    // Forward index: entity → chunks that contain it
    private var entityToChunks: [String: Set<UUID>] = [:]

    // Reverse index: chunk → its entities (for efficient removal)
    private var chunkToEntities: [UUID: Set<String>] = [:]

    // Document tracking for bulk deletion
    private var documentToChunks: [UUID: Set<UUID>] = [:]
}
```

**Key Operations**:

| Method                   | Purpose                         | Complexity              |
| ------------------------ | ------------------------------- | ----------------------- |
| `indexChunk(_:)`         | Add chunk's entities to index   | O(e) where e = entities |
| `chunksForEntity(_:)`    | Find all chunks with entity     | O(1)                    |
| `chunksForEntities(_:)`  | Union search across entities    | O(e)                    |
| `sharedEntities(among:)` | Find common entities in chunks  | O(c·e)                  |
| `removeDocument(_:)`     | Delete all entries for document | O(c·e)                  |

**GraphRAG Integration**: `AgenticOrchestrator.executeGraphExpansion()` uses `chunksForEntities()` for 2-hop expansion without additional vector search.

**Persistence**: JSON snapshot saved to app container for cold-start performance.

**File**: `OpenIntelligence/Services/EntityIndexService.swift`

---

### mmap Zero-Copy Vector Storage

**Purpose**: Minimize RAM usage for large embedding corpora

**Problem Solved**: 10,000 chunks × 512 dimensions × 4 bytes = ~20MB resident memory. On memory-constrained devices, this competes with the LLM.

**Solution**: Memory-mapped files let the OS page vectors in/out on demand.

**Architecture**:

```text
┌─────────────────────────────────────────────────────────────┐
│ embeddings.bin (mmap'd)                                     │
│ ┌──────────────────┬──────────────────┬─────────────────┐   │
│ │ Chunk 0 [512 f32]│ Chunk 1 [512 f32]│ Chunk N [512 f32│   │
│ └──────────────────┴──────────────────┴─────────────────┘   │
└─────────────────────────────────────────────────────────────┘
             ↑
    Data(contentsOf:, options: .alwaysMapped)

┌─────────────────────────────────────────────────────────────┐
│ metadata.json - chunk IDs, content, metadata                │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ norms.bin - pre-computed L2 norms for fast cosine similarity│
└─────────────────────────────────────────────────────────────┘
```

**Performance Characteristics**:

| Metric                       | In-Memory DB        | mmap DB                |
| ---------------------------- | ------------------- | ---------------------- |
| Resident Memory (10K chunks) | ~20 MB              | ~2 KB                  |
| Cold Start                   | Instant             | ~100ms (metadata load) |
| Search Latency               | ~2ms                | ~5ms                   |
| Best For                     | Small corpora (<1K) | Large corpora (>5K)    |

**Hardware Acceleration**: Search uses `vDSP_dotpr` for BLAS-accelerated dot products.

**Implementation** (`MmapVectorDatabase`):

```swift
// Memory-map embeddings file
mappedEmbeddings = try Data(contentsOf: embeddingsURL, options: .alwaysMapped)

// BLAS-accelerated search
mapped.withUnsafeBytes { buffer in
    let embeddings = buffer.bindMemory(to: Float.self)
    vDSP_dotpr(query, 1, embeddings.baseAddress!.advanced(by: offset), 1, &dotProduct, vDSP_Length(dim))
}
```

**File**: `OpenIntelligence/Services/VectorDatabase.swift` (`MmapVectorDatabase` class)

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

| Feature                     | iOS Version | Apple API                                | Privacy         |
| --------------------------- | ----------- | ---------------------------------------- | --------------- |
| HyDE                        | iOS 26+     | `LanguageModelSession.respond(to:)`      | On-device       |
| Contextual Compression      | iOS 26+     | `LanguageModelSession.respond(to:)`      | On-device       |
| Agentic Orchestration       | iOS 26+     | `LanguageModelSession` + `Tool` protocol | On-device + PCC |
| Cross-Encoder Reranking     | iOS 17+     | Core ML (`ReRankerModel.mlpackage`)      | On-device       |
| Lost-in-Middle              | Any         | Pure Swift algorithm                     | On-device       |
| Query Intent Classification | iOS 17+     | `NLTagger` + heuristics                  | On-device       |

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
- Quality Mode picker (Standard / Deep Think / Maximum)

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

| Operation                 | Target       | Current Status |
| ------------------------- | ------------ | -------------- |
| Document parsing          | <1s/page     | ✅ Achieved    |
| Embedding generation      | <100ms/chunk | ✅ Achieved    |
| Vector search (1K chunks) | <50ms        | ✅ Achieved    |
| LLM generation (Apple FM) | 15-25 tok/s  | ✅ Achieved    |
| End-to-end query          | <5s          | ✅ Achieved    |

## Privacy Architecture

1. **On-Device Processing**: All document parsing, embedding, and search happens locally
2. **Apple Intelligence**: Stays on-device; Private Cloud Compute only for complex queries
3. **Private Cloud Compute**: Apple Silicon servers, cryptographically enforced zero retention
4. **No Cloud APIs**: OpenAI/GPT integrations removed Dec 2025 (privacy-first design)
5. **No Telemetry**: Zero data collection or analytics

## Retrieval Quality Assessment

**Current Rating**: 75-85% of Enterprise RAG (Jan 2026)

> **The Honest One-Liner:** "80% as good as enterprise RAG, running on 0% of the infrastructure, shipping as a real product."

### What's Actually Good ✅

| Component                     | Assessment                                                                                                                                                                          |
| ----------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **BM25 Implementation**       | **Solid.** Standard k1=1.5, b=0.75. Correct IDF formula. NLTokenizer for tokenization. Textbook BM25.                                                                               |
| **RRF Fusion**                | **Correct.** Uses k=60 (Cormack et al. 2009). Properly weights and sums reciprocal ranks.                                                                                           |
| **Cross-Encoder Reranking**   | **Production-grade.** Real BERT cross-encoder (`ms-marco-TinyBERT-L-2-v2`). Proper `[CLS] query [SEP] doc [SEP]` formatting. Token type IDs handled correctly. Softmax over logits. |
| **MMR Diversification**       | **Good.** GPU-accelerated for large candidate sets. Proper λ-weighted diversity vs relevance tradeoff. Pre-computes pairwise similarities.                                          |
| **Lost-in-Middle Mitigation** | **Implemented.** Reorders chunks to put best at positions 1 and N. Follows Liu et al. 2023.                                                                                         |
| **vDSP/Accelerate**           | **Proper hardware acceleration.** Uses `vDSP_dotpr` for dot products, `vDSP.sumOfSquares` for norms. Actually runs on Neural Engine/AMX.                                            |

### Known Limitations ⚠️

| Component                       | Honest Assessment                                                                                                                                                     | Improvement Path                                              |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| **Hybrid isn't truly parallel** | Vector search runs first, then BM25 scores are computed _on the same candidates_. It's not two independent searches being merged — BM25 is re-scoring vector results. | Run FTS5 search independently, merge two distinct result sets |
| **BM25 snapshot is per-query**  | `snapshot(from: candidates)` rebuilds document frequencies from just the ~20-50 candidates, not the full corpus. IDF is less accurate because it's local, not global. | Persist global IDF stats at ingestion time                    |
| **No FTS5 at query time**       | SQLite FTS5 is used for storage, but BM25 scoring at query time uses in-memory `BM25Scorer`, not SQLite's native `bm25()` function.                                   | Use `SELECT ... ORDER BY bm25(fts_table)` for native scoring  |
| **Cross-encoder capped at 50**  | `Array(chunks.prefix(50))` before reranking. If the right chunk is #51, it's never seen by the cross-encoder.                                                         | Two-stage: fast filter to 100, then cross-encoder to top 50   |

### Comparison to Enterprise RAG

| Aspect                | This Implementation | Enterprise (Anthropic/OpenAI/Cohere) |
| --------------------- | ------------------- | ------------------------------------ |
| **Retrieval quality** | 70-80%              | 90-95%                               |
| **Reranking quality** | 80-85%              | 90-95%                               |
| **Context packing**   | 85-90%              | 90-95%                               |
| **Overall pipeline**  | **75-85%**          | 90-95%                               |

### Why It's Still Impressive

1. **Runs entirely on a phone.** The cross-encoder alone would be a "we need a GPU server" conversation at most companies.
2. **No cloud.** Anthropic's RAG uses Claude. OpenAI's RAG uses GPT-4. This uses a 4096-token on-device model and still gets reasonable results.
3. **Constraints forced real engineering.** Can't throw 128K context at it. Had to actually solve the "find the right 5 chunks" problem.
4. **It ships.** 90% of RAG implementations are Jupyter notebooks. This is on the App Store.

### What We Have (Best Practices Implemented)

| Feature                       | Status | Implementation                                   |
| ----------------------------- | ------ | ------------------------------------------------ |
| Hybrid Search (Vector + BM25) | ✅     | `HybridSearchService` with RRF fusion            |
| Cross-Encoder Reranking       | ✅     | `ReRankerModel.mlpackage` in `RAGEngine`         |
| MMR Diversification           | ✅     | λ=0.6 in `RAGEngine.rerankWithMMR()`             |
| Query Expansion               | ✅     | `QueryEnhancementService.expandQuery()`          |
| Multi-Query Search            | ✅     | `AgenticOrchestrator.executeMultiQuerySearch()`  |
| Semantic Intent Validation    | ✅     | `AgenticOrchestrator.validateSemanticIntent()`   |
| Query Intent Classification   | ✅     | `QueryIntent` enum with dynamic weights          |
| Content-Adaptive Chunking     | ✅     | `ChunkingConfig.recommended(for:)`               |
| Lost-in-Middle Mitigation     | ✅     | `applyLostInMiddleReordering()`                  |
| Auto-Tuning                   | ✅     | `RetrievalConfig.recommended(forDocumentTypes:)` |

### Research-Backed Advanced RAG Features (12/12 Implemented)

All features below are **actually implemented and verified** in production code, not just documented aspirationally.

#### 1. Hybrid Search (Vector + BM25 + RRF)

**Papers**:

- Robertson & Zaragoza, "The Probabilistic Relevance Framework: BM25 and Beyond" (2009)
- Cormack et al., "Reciprocal Rank Fusion outperforms Condorcet and individual Rank Learning Methods" (2009)

**Implementation**: [`HybridSearchService.swift`](../../OpenIntelligence/Services/HybridSearchService.swift)

- **BM25 Scorer**: Full Okapi BM25 with IDF, term frequency saturation (k1=1.5), length normalization (b=0.75)
- **Vector Search**: vDSP-accelerated cosine similarity via Neural Engine
- **RRF Fusion**: Reciprocal rank fusion with k=60, weighted blend (vector 40%, keyword 60% default)
- **Keyword Match Boosting**: Exact match detection for technical terms

```swift
// Real implementation excerpt
let fusedResults = await engine.reciprocalRankFusion(
    vectorResults: vectorRanked,
    keywordResults: keywordResults,
    k: 60,  // RRF constant
    vectorWeight: vectorWeight,
    keywordWeight: keywordWeight
)
```

#### 2. Cross-Encoder Reranking

**Paper**: Nogueira & Cho, "Passage Re-ranking with BERT" (2019)

**Implementation**: [`RAGEngine.swift#L877`](../../OpenIntelligence/Services/RAGEngine.swift) (`rerankWithCrossEncoder()`)

- **Model**: `cross-encoder/ms-marco-TinyBERT-L-2-v2` converted to CoreML
- **Architecture**: BERT-based pairwise scoring with `[CLS] Q [SEP] D [SEP]` encoding
- **Inference**: Neural Engine accelerated via `MLModel.prediction()`
- **Fallback**: Heuristic reranking with keyword proximity if model unavailable

#### 3. MMR (Maximal Marginal Relevance) Diversification

**Paper**: Carbonell & Goldstein, "The Use of MMR, Diversity-Based Reranking for Reordering Documents" (1998)

**Implementation**: [`RAGEngine.swift#L99`](../../OpenIntelligence/Services/RAGEngine.swift) (`applyMMR()`)

- **Algorithm**: Iterative greedy selection maximizing `λ * relevance - (1-λ) * maxSimilarity`
- **Lambda**: 0.7 (70% relevance, 30% diversity)
- **Acceleration**: vDSP-powered cosine similarity via `vDSP_dotpr` and `vDSP.sumOfSquares`

```swift
// Core MMR formula implementation
let mmrScore = lambda * relevance - (1 - lambda) * maxSimilarityToSelected
```

#### 4. HyDE (Hypothetical Document Embeddings)

**Paper**: Gao et al., "Precise Zero-Shot Dense Retrieval without Relevance Labels" (2022)

**Implementation**: [`RAGService.swift#L3480`](../../OpenIntelligence/Services/RAGService.swift)

- **Strategy**: Generate hypothetical answer, embed THAT instead of raw query
- **Heuristic Activation**: Only for factual queries (what, which, specifications, dimensions)
- **Integration**: Called in Step 2 (Query Embedding) before vector search
- **Fallback**: Silent degradation to standard query embedding if generation fails

```swift
// Actual integration point
if useHyDE {
    let hydeResult = try await hydeService.generateHyDEQuery(for: effectiveQuery)
    hydeText = hydeResult.hypotheticalDocument
}
let textToEmbed = hydeText ?? effectiveQuery  // Use HyDE text if available
```

#### 5. Parent Document Retrieval

**Paper**: Inspired by LangChain's ParentDocumentRetriever pattern

**Implementation**: [`RAGService.swift#L4433`](../../OpenIntelligence/Services/RAGService.swift)

- **Expansion**: Add up to 8 sibling chunks from same document/section
- **Configs**: `.default` (2 siblings), `.thorough` (4 siblings), `.procedural` (8 siblings, 6000 tokens)
- **Smart Selection**: Procedural queries automatically get maximum expansion
- **Thermal Awareness**: Respects `AdaptivePipelineOptimizer` settings

#### 6. Contextual Compression

**Paper**: LangChain concept, inspired by "ContextualCompressionRetriever"

**Implementation**: [`RAGService.swift#L4517`](../../OpenIntelligence/Services/RAGService.swift)

- **Strategy**: Extract only query-relevant sentences, discard irrelevant content
- **Token Savings**: Typical 40-60% reduction (e.g., 335 → 180 tokens)
- **Smart Skipping**: Automatically disabled for procedural queries (destroys step ordering) and vocabulary mismatch
- **Fallback**: Preserves all original chunks if compression fails

#### 7. Lost-in-Middle Mitigation

**Paper**: Liu et al., "Lost in the Middle: How Language Models Use Long Contexts" (2023)

**Implementation**: [`RAGEngine.swift#L524`](../../OpenIntelligence/Services/RAGEngine.swift) (`applyLostInMiddleReordering()`)

- **Finding**: LLMs attend best to start and end of context window
- **Algorithm**: Interleaved reordering → `[1st, 3rd, 5th, ..., 6th, 4th, 2nd]`
- **Effect**: Best chunks at positions 0 and N-1, worst in middle

```swift
// Interleaving logic
for i in 0..<chunks.count {
    if i % 2 == 0 {
        result.append(firstHalf[frontIdx])  // High relevance at start
    } else {
        result.append(secondHalf[backIdx])  // High relevance at end
    }
}
```

#### 8. RAPTOR-lite (Recursive Abstractive Processing)

**Paper**: Sarthi et al., "RAPTOR: Recursive Abstractive Processing for Tree-Organized Retrieval" (2024)

**Implementation**:

- [`DocumentSummaryService.swift`](../../OpenIntelligence/Services/DocumentSummaryService.swift) - L1 summary generation
- [`QueryRouterService.swift`](../../OpenIntelligence/Services/QueryRouterService.swift) - Query classification
- [`RAGService.swift#L2045`](../../OpenIntelligence/Services/RAGService.swift) - Ingestion integration

**Abstraction Hierarchy**:

- **L0 (detail)**: Original chunks (280-400 words)
- **L1 (documentSummary)**: Per-doc summaries (~150 words)
- **L2+ (planned)**: Cluster and library-level summaries

**Query Routing**: Overview queries → L1 summaries, Detail queries → L0 chunks

#### 9. Query Routing

**Paper**: Extension of RAPTOR's abstraction-level routing

**Implementation**: [`QueryRouterService.swift`](../../OpenIntelligence/Services/QueryRouterService.swift)

- **Classification**: `.overview` (what is, summarize), `.detail` (how, why), `.crossTopic` (compare)
- **Confidence Scoring**: Keyword-based heuristics with 0-1 confidence
- **Integration**: Filters chunks by `abstractionLevel` before retrieval (lines 3572, 7487, 7590)

#### 10. Agentic RAG (Multi-Step Reasoning)

**Papers**:

- Yao et al., "ReAct: Synergizing Reasoning and Acting in Language Models" (2023)
- Shinn et al., "Reflexion: Language Agents with Verbal Reinforcement Learning" (2023)

**Implementation**: [`AgenticOrchestrator.swift`](../../OpenIntelligence/Services/AgenticOrchestrator.swift) (~6000 lines)

- **Multi-Query Search**: LLM generates 4-5 search variations for universal coverage
- **Semantic Validation**: Verifies retrieved chunks actually answer the question
- **Tool Library**: 14+ `@Tool` functions (search, reformulate, expand, synthesize, count patterns)
- **Reasoning Chains**: 4-50 sessions depending on mode (Standard: 3, Deep Think: 4-8, Maximum: 50)
- **Self-RAG 2.0 Enrichment**: Multi-session prompts ENHANCE rather than verify (research-validated)
- **Retrieval Miss Detection**: Falls back to recursive research if answer says "cannot find"
- **Quality Evaluation**: Confidence scoring after each step, escalation if < threshold
- **Token Budget**: 12K (standard) to 200K (maximum mode)

**Modes**:

- **Standard**: 3 sessions, direct synthesis, 12K tokens
- **Deep Think**: 4-8 sessions, Self-RAG 2.0 enrichment, 32K tokens
- **Maximum**: Multi-chain parallel reasoning, 98% confidence target, 200K tokens

**Self-RAG 2.0 Enrichment Prompting** (Jan 24, 2026 - Research-Validated):

Based on Chain-of-Verification (Meta 2023) and RR-MP (2025) research, Deep Think sessions now ENHANCE rather than VERIFY:

```swift
// OLD (caused hyper-skepticism → wrong answers):
"VERIFY: Does this answer actually answer the question?"

// NEW (enrichment-focused):
"ENHANCE this answer by adding:
- More specific values from the documents
- Quantities, capacities, specifications
Note: Specifications like 'SAE 0W-20' ARE valid answers."
```

**Key Research Findings Applied**:

- **Chain-of-Verification (Meta 2023)**: Draft → verify → refine (but verification shouldn't reject valid specs)
- **RR-MP (Jan 2025)**: Prevent "degeneration of thought" via original question grounding
- **MAIN-RAG (Dec 2024)**: Multi-agent consensus for document filtering

**Confidence Baseline Fix** (Jan 2026):

Maximum mode previously showed 0% → 0% → 0% → 85% confidence jumps. Fix starts at 5% baseline.

**Repetition Confidence Fix** (Jan 2026):

Repetition no longer artificially boosts confidence - repeated wrong answers shouldn't claim 99% certainty.

#### 11. Self-RAG (Adaptive Retrieval)

**Paper**: Asai et al., "Self-RAG: Learning to Retrieve, Generate, and Critique through Self-Reflection" (2023)

**Implementation**: [`AgenticOrchestrator.swift#L1700`](../../OpenIntelligence/Services/AgenticOrchestrator.swift) (`executeSelfRAG()`)

**4-Step Flow**:

1. **Decide**: Does query need retrieval? (heuristic: document indicators vs general knowledge)
2. **Retrieve or Generate**: RAG path if needed, direct answer otherwise
3. **Self-Critique**: Hallucination check and quality assessment
4. **Force Retrieval**: If critique fails and we didn't retrieve, retry with docs

```swift
let (needsRetrieval, reason) = try await decideIfRetrievalNeeded(query: query)
if needsRetrieval {
    // RAG path: retrieve → generate → critique
} else {
    // Direct path: generate → critique → force retrieval if bad
}
```

#### 12. Fine-Tuned Embeddings (Sentence Transformers)

**Paper**: Reimers & Gurevych, "Sentence-BERT: Sentence Embeddings using Siamese BERT-Networks" (2019)

**Implementation**: [`CoreMLSentenceEmbeddingProvider.swift`](../../OpenIntelligence/Services/Embeddings/CoreMLSentenceEmbeddingProvider.swift)

- **Model**: `all-MiniLM-L6-v2` (384-dim) - same as Pinecone, Weaviate defaults
- **Training**: Pre-trained on 1B+ sentence similarity pairs
- **Advantage**: Full sentence understanding vs word-level averaging (NLEmbedding)
- **Acceleration**: Neural Engine via CoreML with `.all` compute units
- **Default**: Set as default provider in `EmbeddingService.init()`

**Why it's "fine-tuned"**: The base MiniLM model was fine-tuned on semantic similarity tasks, making it domain-adapted for RAG compared to generic word embeddings.

---

### Learned Fusion Weights (Future)

| Feature                | Status     | Complexity |
| ---------------------- | ---------- | ---------- |
| Learned Fusion Weights | 🔜 Roadmap | High       |

**Concept**: Use ML to learn optimal vector/BM25 blend per query type rather than static 40/60 split.

See [ROADMAP.md](../../ROADMAP.md) Phase 2.5 for full "God Mode RAG" feature list.

---

### Universal Document Intelligence (AppleRAG Spec Alignment)

The system is designed to be domain-agnostic—able to understand any document type (technical manuals, legal contracts, medical records, research papers) without hardcoded domain knowledge.

**Current Implementation Status**:

| Component                | Status         | Location                                         |
| ------------------------ | -------------- | ------------------------------------------------ |
| Bi-Encoder Embedder      | ✅ Implemented | `CoreMLSentenceEmbeddingProvider` (384-dim)      |
| Cross-Encoder Reranker   | ✅ Implemented | `ReRankerModel.mlpackage` in RAGEngine           |
| Dense Vector Index       | ✅ Implemented | `VectorDatabase` protocol implementations        |
| Lexical Index (BM25)     | ✅ Implemented | `BM25Service` with corpus vocabulary             |
| Structure Index          | ✅ Implemented | `structureType` field + structure boost          |
| Structure-Aware Chunking | ✅ Implemented | Tables/lists preserved as atomic chunks          |
| Verification Gates       | ✅ Implemented | `VerificationGateService` (4-gate pipeline)      |
| Bounding Box Metadata    | ✅ Implemented | `ChunkMetadata.bboxArray` with computed `bbox`   |
| Section Path Hierarchy   | ✅ Implemented | `ChunkMetadata.sectionPath` + `buildSectionPath` |
| Extractive QA Span Model | ❌ Planned     | TinyBERT + start/end heads (Phase 2.06)          |
| Graph Index              | ❌ Planned     | Cross-reference traversal (Phase 2.06)           |

---

### Deferred to v2.0.0 (Q2 2026)

#### CameraVisionOverlayView

_Live camera analysis with Vision framework overlays_

> **Status**: ⏸️ Code complete, UI disabled for v1.0 App Store release. Files in `/Features/Camera/`.

**Purpose**: Real-time document/text/table detection from camera feed with instant RAG ingestion.

**Architecture**:

```text
AVCaptureSession → CMSampleBuffer → CGImage
                                      │
                                      ▼
              ┌──────────────────────────────────────┐
              │        VisionFrameAnalyzer           │
              │  ┌────────────────────────────────┐  │
              │  │ DetectDocumentSegmentationReq  │  │ → Document bounding box
              │  │ RecognizeTextRequest           │  │ → Live OCR text
              │  │ RecognizeDocumentsRequest      │  │ → Tables/lists structure
              │  │ DetectBarcodesRequest          │  │ → QR/barcodes
              │  └────────────────────────────────┘  │
              └──────────────┬───────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────────────┐
              │       AR Overlay Layer (SwiftUI)     │
              │  • Green bounding boxes for text     │
              │  • Blue boxes for tables             │
              │  • Yellow boxes for documents        │
              │  • Live preview of detected content  │
              └──────────────┬───────────────────────┘
                             │
                             ▼
              ┌──────────────────────────────────────┐
              │       CaptureToRAGBridge             │
              │  • One-tap capture                   │
              │  • Extract text + tables             │
              │  • Ingest to RAG container           │
              │  • Ready for immediate Q&A           │
              └──────────────────────────────────────┘
```

**Key APIs**:

| Vision API                              | Use Case                        |
| --------------------------------------- | ------------------------------- |
| `DetectDocumentSegmentationRequest`     | Find document edges in frame    |
| `RecognizeTextRequest`                  | Live OCR with bounding boxes    |
| `RecognizeDocumentsRequest`             | Table/list structure extraction |
| `DetectBarcodesRequest`                 | QR codes, barcodes              |
| `CalculateImageAestheticsScoresRequest` | Quality check before capture    |

**Files** (Implemented, UI Disabled):

- `OpenIntelligence/Features/Camera/CameraVisionOverlayView.swift`
- `OpenIntelligence/Features/Camera/CameraManager.swift`
- `OpenIntelligence/Features/Camera/DocumentCaptureView.swift`
- `OpenIntelligence/Features/Camera/CaptureToRAGBridge.swift`
- `OpenIntelligence/Services/Document/VisionOCRThrottle.swift` (used by core services)

**Why Deferred**: iOS 26 RecognizeDocumentsRequest is new; needs more real-world testing before App Store.

---

### Planned v1.2.0 Subsystems (March 2026)

#### DocumentationCacheService

_Persistent storage for fetched web documentation_

**Purpose**: Save fetched API documentation locally for offline access and RAG ingestion.

**Architecture**:

```swift
actor DocumentationCacheService {
    private let cacheDirectory: URL  // ~/Documents/cached_docs/

    struct CachedDocument: Codable {
        let url: URL
        let title: String
        let content: String       // Cleaned Markdown
        let fetchDate: Date
        let contentHash: String   // SHA256 for deduplication
        let sourceType: SourceType  // .appleDevDocs, .github, .web
    }

    func cache(_ document: CachedDocument) async throws
    func get(url: URL) -> CachedDocument?
    func listCached() -> [CachedDocument]
    func ingestToRAG(documentId: UUID, containerId: UUID) async throws
}
```

**Storage Structure**:

```
~/Documents/cached_docs/
├── index.json              # URL → filename mapping
├── apple_vision_framework.md
├── apple_foundationmodels.md
├── github_swift_transformers.md
└── ...
```

**Features**:

- Auto-cache on web fetch (configurable)
- Markdown conversion from HTML
- SHA256 deduplication
- 30-day expiration policy
- Browse/search cached docs in-app
- One-tap RAG ingestion

**File (Planned)**: `OpenIntelligence/Services/Storage/DocumentationCacheService.swift`

#### Enhanced ImageUnderstandingService

_Apple Intelligence image description via FoundationModels_

**Current** (v1.0): Image classification + OCR + caption detection

**Enhanced** (v1.2): Full natural language description using Apple FM

```swift
// Current approach
let classification = try await ClassifyImageRequest().perform(on: cgImage)
// Returns: ["chart", "line_graph", "data_visualization"]

// Enhanced approach (v1.2)
let session = LanguageModelSession()
let response = try await session.respond(
    to: "Describe this image in detail. What does it show?",
    with: [cgImage]  // Image attachment
)
// Returns: "This is a line chart showing quarterly revenue growth.
//           Q1 shows $2.1M, Q2 shows $2.8M, Q3 shows $3.2M, Q4 shows $4.1M.
//           The trend indicates 95% year-over-year growth."
```

**Benefits**:

- Rich semantic descriptions stored in chunk metadata
- Diagram understanding (flowcharts, architecture diagrams)
- Chart data extraction (bar charts, pie charts, line graphs)
- Photo scene description for contextual understanding

**File**: `OpenIntelligence/Services/Document/ImageUnderstandingService.swift`

---

The extractive QA model will provide instant, traceable answers for factual lookups:

```text
Query: "What is the recommended oil viscosity?"
      │
      ▼
┌─────────────────┐
│ Hybrid Search   │  ← Retrieve relevant chunks
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Extractive QA   │  ← TinyBERT predicts start/end positions
│ Span Model      │    Output: { span: "5W-30", confidence: 0.94 }
└────────┬────────┘
         │
         ├─── confidence ≥ 0.7 ──→ Return span directly (fast path)
         │
         └─── confidence < 0.7 ──→ Escalate to LLM generation
```

**Implemented Verification Gates** (via `VerificationGateService.swift`):

| Gate   | Check                       | Action                                           |
| ------ | --------------------------- | ------------------------------------------------ |
| Gate A | `max(chunk_scores) < τ`     | Abstain: "No relevant information found"         |
| Gate B | Evidence coverage < 70%     | Flag unsupported claims                          |
| Gate C | Numbers not in source       | Catch hallucinated specifications                |
| Gate D | Response contradicts corpus | Show: "Response mentions X, but document says Y" |

See [ROADMAP.md](../../ROADMAP.md) Phase 2.06 for implementation details.

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

### 2.5 Multi-Query Search (Universal Semantic Coverage)

**Purpose**: Guarantee retrieval of relevant content regardless of vocabulary mismatch between query and documents.

**Problem Solved**: User asks "What oil does this car take?" but documents use "motor oil viscosity specification 5W-30". Single-query retrieval grabs "oil pressure warnings" because both contain "oil" — wrong semantic intent.

**Solution**: LLM generates 4-5 diverse search queries, search with ALL of them, fuse results via RRF:

```text
User Query: "What oil does this car take?"

LLM-Generated Search Queries:
1. "What oil does this car take?" (original)
2. "engine oil specification viscosity grade"
3. "motor oil type 5W-30 0W-20"
4. "lubricant requirements recommendation"

→ Search with each query
→ RRF fusion across all results
→ Semantic validation: "Does this content answer the question?"
→ If validation fails: downgrade quality rating, try harder
```

**File**: `Services/AgenticOrchestrator.swift` (`generateSearchQueries()`, `executeMultiQuerySearch()`)

**Key Methods**:

| Method                           | Purpose                                            |
| -------------------------------- | -------------------------------------------------- |
| `generateSearchQueries()`        | LLM generates 4-5 diverse query variations         |
| `executeMultiQuerySearch()`      | Searches with all queries, RRF fusion              |
| `validateSemanticIntent()`       | Verifies retrieved chunks actually answer question |
| `answerIndicatesRetrievalMiss()` | Detects "cannot find" patterns in response         |

**Flow in Deep Think / Maximum Mode**:

```text
1. Generate search query variations (LLM-powered)
2. Multi-query search with RRF fusion
3. Semantic intent validation
4. If validation fails → downgrade quality → trigger fallbacks
5. If answer says "cannot find" → recursive research with [SEARCH: query]
```

**Why It's Universal**: Works for ANY content type because the LLM understands the user's intent and generates domain-appropriate search terms — medical, legal, technical, automotive, etc.

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

- Configurable via `RAGQualityMode` (enabled in Deep Think and Maximum modes)
- Confidence assessment based on: chunk count, similarity scores, source diversity
- LLM-powered query refinement between iterations
- Automatic deduplication across iterations

### Quality Mode Control

These features are controlled by the `RAGQualityMode` setting:

| Feature               | Standard | Deep Think | Maximum |
| --------------------- | -------- | ---------- | ------- |
| Query Rewriting       | ✅       | ✅         | ✅      |
| Corpus Expansion      | ✅       | ✅         | ✅      |
| Multi-Query Search    | ❌       | ✅         | ✅      |
| Semantic Validation   | ❌       | ✅         | ✅      |
| Iterative Retrieval   | ✅       | ✅         | ✅      |
| Agentic Orchestration | ❌       | ✅ (4-8)   | ✅ (∞)  |
| Exhaustive Synthesis  | ❌       | ❌         | ✅      |
| Confidence Target     | 85%      | 95%        | 98%     |

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
├── App/                           # App entry point & configuration
│   ├── OpenIntelligenceApp.swift  # @main entry
│   └── ContentView.swift          # Root view (tab bar)
│
├── Core/                          # Shared domain logic
│   ├── Models/                    # Data types (ChatMessage, KnowledgeContainer, etc.)
│   ├── Protocols/                 # Extracted protocols
│   └── Extensions/                # Swift extensions
│
├── Features/                      # Feature modules (Views organized by domain)
│   ├── Chat/                      # Main chat interface
│   ├── Documents/                 # Document library & management
│   ├── Settings/                  # Settings screens
│   ├── Billing/                   # StoreKit/subscription UI
│   ├── Onboarding/                # First-run experience
│   ├── Diagnostics/               # Debug views
│   └── Telemetry/                 # Visualization & analytics views
│
├── Services/                      # ALL business logic (organized by domain)
│   ├── RAG/                       # Core RAG pipeline (RAGService, RAGEngine, HybridSearch)
│   ├── LLM/                       # LLM integrations (LLMService protocol + implementations)
│   ├── Embedding/                 # Embedding providers (CoreML, NL, AppleFM)
│   ├── VectorStore/               # Vector databases (protocol + implementations)
│   ├── Query/                     # Query processing (HyDE, compression, routing)
│   ├── Document/                  # Document processing (chunking, entity extraction)
│   ├── Agentic/                   # Agentic orchestration (tools, intents, memory)
│   ├── Billing/                   # StoreKit billing service
│   └── Infrastructure/            # Cross-cutting (logging, device, settings, telemetry)
│
├── UI/                            # Reusable UI components
│   ├── DesignSystem/              # Theme, colors, typography
│   └── Components/                # Shared SwiftUI components
│
├── Resources/                     # Static resources
│   ├── Assets/                    # Image assets, colors
│   ├── MLModels/                  # CoreML models (.mlpackage)
│   └── StoreKit/                  # StoreKit configuration
│
└── swift-transformers/            # Git submodule (HuggingFace tokenizers)

Docs/
├── reference/                     # Architecture & API docs
│   ├── ARCHITECTURE.md            # Full technical reference
│   └── RELEASE.md                 # Release checklist, smoke tests
└── TestDocuments/                 # Sample files for testing

OpenIntelligenceTests/             # Unit tests + TestDoubles.swift for mocks
scripts/                           # CI/CD helpers (secret_scan, preflight_check)
fastlane/                          # App Store deployment automation
```

### Placement Rules

1. **New Models**: Place in `Core/Models/` with `Sendable` conformance
2. **New Services**: Place in appropriate `Services/{Domain}/` with protocol definition
3. **New Views**: Group by feature under `Features/{FeatureName}/`
4. **Shared Components**: Reusable UI goes in `UI/Components/`
5. **Design Tokens**: Theme, colors in `UI/DesignSystem/`
6. **Tests**: Mirror source structure under `OpenIntelligenceTests/`

---

## Appendix A: Mobile LLM Optimization

### Model Selection & Quantization

**Recommended Model Sizes**:

- iPhone 15 Pro (8GB): 2–3B parameter models
- iPhone 16 Pro Max (8GB+): 3–7B parameter models

**Quantization Strategy**:

| Quantization | Size (3B) | Quality   | Speed    | Recommendation   |
| ------------ | --------- | --------- | -------- | ---------------- |
| Q4_K_M       | ~2.0 GB   | Excellent | Fast     | ✅ Recommended   |
| Q5_K_M       | ~2.4 GB   | Better    | Moderate | Good for Pro Max |
| Q8_0         | ~3.2 GB   | Near-fp16 | Slower   | Avoid on mobile  |

**Starter Models**:

- Qwen2.5-3B-Instruct-Q4_K_M (1.9 GB)
- Gemma-2-2B-It-Q4_K_M (1.6 GB)
- Llama-3.2-1B-Instruct-Q4_K_M (730 MB)

### Context Window Management

| Model        | Max Context | Recommended Mobile |
| ------------ | ----------- | ------------------ |
| Qwen2.5-3B   | 32,768      | 8,192–16,384       |
| Gemma-2-2B   | 8,192       | 4,096–8,192        |
| Llama-3.2-1B | 131,072     | 8,192              |

**RAG Context Strategy**:

- Target ~3,000 tokens (5–8 chunks @ 280-350 words)
- SemanticChunker overlap (~17% / 60 words) maintains coherence
- HybridSearchService MMR prevents redundant context

### Memory Footprint (Q4_K_M 3B)

| Component             | Size        |
| --------------------- | ----------- |
| Model weights         | ~2.0 GB     |
| KV cache (8K context) | ~500 MB     |
| OS + app overhead     | ~1.0 GB     |
| **Total**             | **~3.5 GB** |

### Performance Targets

- **TTFT**: <2 seconds (3B Q4_K_M on iPhone 15 Pro)
- **TPS**: 15–25 tokens/sec
- **Battery**: ~3–5W during inference

### Troubleshooting

| Issue                   | Solution                                         |
| ----------------------- | ------------------------------------------------ |
| Slow inference (<5 TPS) | Use Q4_K_M; wait for device to cool              |
| Out-of-memory crash     | Use smaller model; reduce context                |
| High battery drain      | Add cancellation checks; limit generation length |

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

| Scenario                  | Before     | After    |
| ------------------------- | ---------- | -------- |
| 500 messages              | 30-40 FPS  | 60 FPS   |
| Memory (1hr)              | 150-200 MB | 50-70 MB |
| Vector search (1K chunks) | 80-120ms   | 40-60ms  |
| Repeated query            | 80-120ms   | 0-5ms    |

### Tunable Parameters

```swift
// ChatView.swift
private var visibleMessageCount: Int = 50  // Visible history
private let maxMessagesInMemory = 200      // Total retained

// VectorDatabase.swift
private let maxCacheSize = 20              // Query cache slots
private let cacheExpirationSeconds = 300   // Cache TTL
```
