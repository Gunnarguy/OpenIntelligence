# OpenIntelligence

[![App Store](https://img.shields.io/badge/App%20Store-Download-blue.svg?logo=apple)](https://apps.apple.com/us/app/openintelligence/id6756559175)
[![Platform](https://img.shields.io/badge/platform-iOS%2026.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Services](https://img.shields.io/badge/services-102-purple.svg)](ARCHITECTURE.md)
[![How It Works](https://img.shields.io/badge/Deep%20Dive-HOW%20IT%20WORKS-orange.svg)](HOW_IT_WORKS.md)

**Ask your documents anything. Get cited answers.**

## Table of Contents

- [OpenIntelligence](#openintelligence)
  - [Table of Contents](#table-of-contents)
  - [What It Does](#what-it-does)
  - [Supported File Formats](#supported-file-formats)
  - [Core Technology](#core-technology)
    - [Embedding Pipeline](#embedding-pipeline)
    - [Search \& Retrieval](#search--retrieval)
    - [LLM Generation](#llm-generation)
  - [Apple's On-Device Language Model](#apples-on-device-language-model)
    - [Model Specifications](#model-specifications)
    - [Benchmarks vs Other Models](#benchmarks-vs-other-models)
    - [Capabilities](#capabilities)
    - [Private Cloud Compute (PCC)](#private-cloud-compute-pcc)
  - [8 Agentic @Tool Functions](#8-agentic-tool-functions)
  - [Quality Modes](#quality-modes)
  - [29-Step Pipeline](#29-step-pipeline)
  - [Verification Gates (Anti-Hallucination)](#verification-gates-anti-hallucination)
  - [Device-Optimized Performance](#device-optimized-performance)
    - [Metal GPU Vector Search — 3-Tier Shader Selection](#metal-gpu-vector-search--3-tier-shader-selection)
    - [Vision OCR — Per-Chip Concurrency](#vision-ocr--per-chip-concurrency)
    - [Cross-Encoder Reranking](#cross-encoder-reranking)
    - [Font-Encoded PDF Detection (PHASE -1)](#font-encoded-pdf-detection-phase--1)
    - [Memory-Safe Large PDF Ingestion](#memory-safe-large-pdf-ingestion)
    - [Pipeline Reliability](#pipeline-reliability)
  - [Architecture](#architecture)
    - [Apple Framework Dependencies](#apple-framework-dependencies)
    - [Data Flow](#data-flow)
  - [AI Hub — Response Transforms](#ai-hub--response-transforms)
  - [Motherboard HUD — X-Ray Your iPhone](#motherboard-hud--x-ray-your-iphone)
  - [Telemetry Badges](#telemetry-badges)
  - [Privacy](#privacy)
  - [Getting Started](#getting-started)
    - [Requirements](#requirements)
    - [Installation](#installation)
    - [Troubleshooting](#troubleshooting)
  - [Project Structure](#project-structure)
  - [Roadmap — Apple Intelligence Gap Closure](#roadmap--apple-intelligence-gap-closure)
    - [Active in v2.1 (10 frameworks)](#active-in-v21-10-frameworks)
    - [Code Complete / Not Wired (5 frameworks)](#code-complete--not-wired-5-frameworks)
    - [Remaining Gaps](#remaining-gaps)
  - [Documentation](#documentation)
  - [Contributing](#contributing)
    - [Coding Standards](#coding-standards)
  - [License](#license)

<p align="center">
  <a href="https://apps.apple.com/us/app/openintelligence/id6756559175">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
  </a>
</p>

OpenIntelligence is a document question-answering app powered entirely by Apple Intelligence. Import any document — PDFs, Office files, audio, images, code — ask questions in plain English, and get accurate answers with citations. All processing happens on your device. **102 services. 29-step pipeline. Zero data loss.**

---

## What It Does

```
┌─────────────┐      ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
│  1. ADD     │ ───▶ │  2. INDEX   │ ───▶ │   3. ASK    │ ───▶ │ 4. ANSWER   │
│  Documents  │      │ Chunk+Embed │      │ Your query  │      │ With sources│
└─────────────┘      └─────────────┘      └─────────────┘      └─────────────┘
```

1. **Add** — Tap "+" in the Documents tab, select files from the picker (PDF, Office, audio, images, code)
2. **Index** — App chunks text (≤310 words), generates 384-dim embeddings, builds vector + keyword indexes
3. **Ask** — Go to Chat tab, type a question; app retrieves relevant chunks via hybrid search
4. **Answer** — Apple Intelligence generates a response citing exact source passages

---

## Supported File Formats

| Category        | Formats                                                                                         | Notes                                                  |
| --------------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------ |
| **Documents**   | PDF                                                                                             | Native PDFKit + Vision OCR @ 360 DPI for scanned pages |
| **Office**      | DOCX, XLSX, PPTX                                                                                | Native ZIP-based XML extraction (no dependencies)      |
| **Text**        | TXT, MD, RTF                                                                                    | Direct text extraction                                 |
| **Code**        | Swift, Python, JS, TS, Java, C/C++, Go, Rust, Ruby, PHP, HTML, CSS, JSON, XML, YAML, SQL, Shell | Syntax-aware chunking                                  |
| **Data**        | CSV, JSON                                                                                       | Unlimited rows, handles special characters             |
| **Images**      | PNG, JPEG, HEIC, TIFF, GIF                                                                      | Vision OCR extracts text from images                   |
| **Audio/Video** | M4A, MP3, WAV, MP4, MOV                                                                         | Speech.framework transcription to text                 |
| **Apple**       | Pages, Numbers, Keynote                                                                         | Supported via export or direct extraction              |

---

## Core Technology

### Embedding Pipeline

| Component           | Technology          | Specification                               |
| ------------------- | ------------------- | ------------------------------------------- |
| **Embedding Model** | CoreML MiniLM-L6-v2 | 384 dimensions, bundled in app              |
| **Tokenizer**       | BertTokenizer       | 510 token max (512 - CLS/SEP)               |
| **Chunk Size**      | SemanticChunker     | ≤310 words + 30-word contextual prefix      |
| **Vector Index**    | BNNS + Metal GPU    | 3-tier shader: threadgroup / SIMD4 / scalar |
| **Keyword Index**   | SQLite FTS5         | BM25 scoring, Porter stemmer                |

### Search & Retrieval

| Component           | Technology           | Specification                                   |
| ------------------- | -------------------- | ----------------------------------------------- |
| **Hybrid Search**   | Vector + BM25        | Reciprocal Rank Fusion (k=60)                   |
| **Reranker**        | CoreML Cross-Encoder | Concurrent TaskGroup predictions, pre-tokenized |
| **Diversification** | MMR                  | λ=0.6 relevance/diversity balance               |
| **Context Window**  | Lost-in-Middle       | Best chunks at start AND end                    |

### LLM Generation

| Component         | Technology              | Specification                                   |
| ----------------- | ----------------------- | ----------------------------------------------- |
| **Primary**       | Apple Foundation Models | iOS 26 FoundationModels framework (on-device)   |
| **Fallback**      | Private Cloud Compute   | Apple-routed when context exceeds device limits |
| **Context Limit** | 4,096 tokens            | ~5,500 characters with margin                   |
| **Agentic Tools** | 8 @Tool functions       | Search, summarize, compare, analyze             |

> **Offline-First**: The app works fully offline. All parsing, embedding, search, and LLM inference run on-device. PCC only activates when online AND Apple's system decides it's needed.

---

## Apple's On-Device Language Model

The app uses Apple's ~3 billion parameter language model that runs entirely on the Neural Engine. Here's what you're actually using:

### Model Specifications

| Spec                     | Value                                               |
| ------------------------ | --------------------------------------------------- |
| **Parameters**           | ~3 billion                                          |
| **Context Window**       | 4,096 tokens (hard limit, TN3193)                   |
| **Vocabulary**           | 49,000 tokens (on-device) / 100,000 (server)        |
| **Quantization**         | 3.7 bits per weight (mixed 2-bit/4-bit)             |
| **Inference Speed**      | 0.6ms per prompt token, 30 tokens/sec               |
| **Architecture**         | Dense transformer with KV-cache sharing (5:3 split) |
| **Adapters**             | LoRA adapters (~10s of MB each) per use case        |
| **Instruction Accuracy** | 85.7% on IFEval benchmark                           |
| **Safety**               | 7.5% violation rate (lowest among comparable)       |

### Benchmarks vs Other Models

Per Apple's research, the on-device model outperforms larger open-source models in human evaluation:

| Comparison    | On-Device FM Win Rate |
| ------------- | --------------------- |
| vs Phi-3-mini | Wins                  |
| vs Mistral-7B | Wins                  |
| vs Gemma-7B   | Wins                  |
| vs Llama-3-8B | Wins                  |

Despite having only ~3B parameters (vs 7-8B), the model wins on instruction following and safety due to Apple's training approach: a 64-expert MoE teacher distilled into the dense student, with Quantization-Aware Training at 2-bit using a balanced set `{-1.5, -0.5, 0.5, 1.5}`.

### Capabilities

The model excels at these tasks (per Apple's documentation):

- **Text Generation**: Summarization, writing, rewriting, creative content
- **Entity Extraction**: Pull structured data from unstructured text
- **Text Understanding**: Comprehension, classification, analysis
- **Guided Generation**: Output Swift structs directly with `@Generable`
- **Tool Calling**: Execute Swift functions via `@Tool` protocol
- **Multi-language**: Supports 16 languages via `supportedLanguages`

### Private Cloud Compute (PCC)

When the on-device model isn't sufficient, Apple may route to PCC. Key facts:

- **Server model**: PCC runs a PT-MoE (Parallel-Track Mixture-of-Experts) variant trained on up to 65K token sequences — the Foundation Models framework exposes only the on-device ~3B model to third-party apps
- **Apple controls routing**: You can't force PCC — the system decides based on device thermals, battery, and load
- **No data retention**: Requests are processed and discarded, no training on your data
- **Verifiable privacy**: Cryptographic attestation proves what code runs on PCC servers
- **Detection**: `AppleFoundationLLMService` detects which ran by TTFT — under 1s = on-device, over 1s = PCC

**In practice**: Most queries complete on-device. PCC only activates for complex reasoning that exceeds device capabilities.

---

## 8 Agentic @Tool Functions

The LLM can call these tools autonomously during reasoning:

| Tool                       | Purpose                           | Example Use                              |
| -------------------------- | --------------------------------- | ---------------------------------------- |
| `SearchDocumentsTool`      | Semantic search across all chunks | "Find sections about safety"             |
| `ListDocumentsTool`        | List all ingested documents       | "What documents do I have?"              |
| `GetDocumentSummaryTool`   | Get/generate document summary     | "Summarize the contract"                 |
| `CountPatternTool`         | Count pattern occurrences         | "How many times is 'revenue' mentioned?" |
| `SearchExactPatternTool`   | Find exact text matches           | "Find all phone numbers"                 |
| `GetCorpusStatsTool`       | Library-wide statistics           | "How many pages total?"                  |
| `FindRelatedDocumentsTool` | Find similar documents            | "What's related to this memo?"           |
| `CompareDocumentsTool`     | Compare two documents             | "How do these contracts differ?"         |

---

## Quality Modes

| Mode           | Sessions | Use Case                                 | Response Time |
| -------------- | -------- | ---------------------------------------- | ------------- |
| **Standard**   | 1-3      | Quick factual questions                  | 2-3 seconds   |
| **Deep Think** | 4-8      | Complex analysis, multi-step reasoning   | 5-15 seconds  |
| **Maximum**    | 8-50     | Exhaustive research, document comparison | 15-60 seconds |

Deep Think and Maximum modes use **Self-RAG 2.0**: multiple reasoning sessions that enrich (not verify) answers, adding details from different evidence chains. A cancel-and-replace mechanism ensures sending a new query while one is running cleanly cancels the old task — no more freezes from competing reasoning chains.

---

## 29-Step Pipeline

OpenIntelligence processes every query through 29 distinct steps:

```
INGESTION (6 steps):
  1. Parse         → PDFKit / Vision OCR @ 360 DPI / Office ZIP extraction
                     PHASE -1: Jaccard font cipher detection (prevents 93% content loss)
                     Adaptive preprocessing (5 CIFilter strategies: minimal → maximum)
                     Multi-candidate OCR (topCandidates(5), 90% numeric threshold)
  2. Chunk         → SemanticChunker (≤310 words, section boundary detection)
                     Contextual prefix: section breadcrumbs prepended (~30 words)
                     Table-aware: atomic table block preservation
  3. Extract       → Entity extraction (NLTagger NER + PascalCase detection)
  4. Validate      → Token validation (BertTokenizer, truncate if >510)
  5. Embed         → CoreML MiniLM-L6-v2 (384-dim vectors)
                     GPU ingestion mode frees Neural Engine for concurrent OCR
  6. Store         → HNSW index + SQLite FTS5 + EntityIndex + FullTextStorage

RETRIEVAL & GENERATION (21 steps):
  Step 0    Corpus Analysis        → Build vocabulary cache per container
  Step 1    Query Understanding    → Pronoun resolution, NER extraction
  Step 1.5  Query Expansion        → Corpus-aware synonym expansion + rare term preservation
  Step 1.6  Intent Classification  → lookup / procedure / compare / summarize
  Step 2    Query Embedding        → 384-dim vector from same model
  Step 2.5  RAPTOR-lite Routing    → Overview queries → L1 summaries
  Step 3    Hybrid Search          → Vector k-NN + BM25 + true RRF fusion (parallel async let)
  Step 4    Cross-Encoder Rerank   → CoreML ReRankerModel.mlpackage (concurrent, pre-tokenized)
  Step 4.3  Low-Confidence Filter  → Drop chunks below threshold
  Step 4.4  Multi-Doc Representation → Ensure source diversity
  Step 4.5  MMR Diversification    → λ=0.6 relevance/diversity
  Step 4.6  Parent Document        → Expand ±5 sibling chunks
  Step 4.7  Contextual Compression → LLM filters irrelevant sentences (max 5 chunks, 12s budget)
  Step 4.9  Graph Context Packing  → Optimal token budget allocation
  Step 5    Context Assembly       → Lost-in-middle reordering
  Step 5.9  Extractive Summary     → For summarize intent
  Step 5.10 Extractive QA          → For lookup intent
  Step 5.11 Topical Relevance      → Lexical < 20% → Evidence-First mode
  Step 6    LLM Generation         → Apple FM / Private Cloud Compute
                                     Rate-limit retry with typed .rateLimited/.concurrentRequests
                                     Empty output → reliability fallback (Path B: 6 chunks × 500 chars)
  Step 6.5  Response Formatting    → Markdown preservation pipeline (7 cleaning functions audited)
  Step 7    Quality Assessment     → Confidence scoring
  Step 7.5  Verification Gates     → Gates A-G (see below)
  Step 8    Package Results        → Build response with sources
  Step 8.1  Calibrated Confidence  → Platt scaling (0.0-1.0)
  Step 9    Response Metadata      → Timing, token counts, source URIs

RENDERING (2 steps):
  Step 10   Markdown Rendering     → Block-level parser (h1-h6, bullets, numbered lists,
                                     code fences, block quotes, horizontal rules, paragraphs)
  Step 10.1 Inline Normalization   → 6 regex patterns split Apple FM single-line markdown
                                     into proper blocks before parsing
```

---

## Verification Gates (Anti-Hallucination)

Every response passes through 7 verification gates + a pre-generation topical check:

| Gate    | Name                 | What It Checks                                                                        | On Failure          |
| ------- | -------------------- | ------------------------------------------------------------------------------------- | ------------------- |
| **Pre** | Topical Relevance    | Query keywords must appear in chunks (lexical ≥ 20%) or Evidence-First mode activates | Evidence-First mode |
| **A**   | Retrieval Confidence | `max(score) ≥ τ` AND `margin ≥ μ` between top results                                 | **Abstain**         |
| **B**   | Evidence Coverage    | All claims must cite `evidence_ids` from retrieved chunks                             | Confidence penalty  |
| **C**   | Numeric Sanity       | Numbers in response must match source documents (year/integer exempted)               | **Abstain**         |
| **D**   | Contradiction Sweep  | Detect conflicting evidence across chunks                                             | Confidence penalty  |
| **E**   | Semantic Grounding   | Response embedding cosine similarity vs chunk embeddings (relative ≥ 0.80, vDSP.dot)  | **Abstain**         |
| **F**   | Quote Faithfulness   | Abbreviation expansions must match source definitions (Jaccard ≥ 0.50)                | Confidence penalty  |
| **G**   | Generation Quality   | Bigram entropy ≥ 2.0 bits, unique word ratio ≥ 25%, trigram dominance < 15%           | Confidence penalty  |

Critical gates (A, C, E) trigger full abstention — the app would rather say nothing than say something wrong. Advisory gates (B, D, F, G) apply confidence penalties only.

---

## Device-Optimized Performance

Every pipeline stage is hardware-aware — tuned to the specific Apple Silicon chip in your device.

### Metal GPU Vector Search — 3-Tier Shader Selection

| Shader          | Condition                | How It Works                                                                                                                                             |
| --------------- | ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Threadgroup** | ≥1,000 vectors, dim ≤384 | Query cached in `threadgroup` shared memory, SIMD4 `float4` ops. MiniLM at 384-dim / 4 = 96 float4s fits exactly within `sharedQuery[96]`. Fastest path. |
| **SIMD4**       | 100–999 vectors          | Hardware `float4` vector operations — 4× scalar throughput                                                                                               |
| **Scalar**      | Fallback                 | Arbitrary dimension support — baseline                                                                                                                   |

### Vision OCR — Per-Chip Concurrency

| Chip                    | Concurrent Ops | Cooldown | Notes              |
| ----------------------- | -------------- | -------- | ------------------ |
| A19 Pro / M4            | 8              | 1ms      | Maximum throughput |
| A18 Pro / M3            | 6              | 2ms      |                    |
| A17 Pro / M2            | 4              | 3ms      |                    |
| Mac (Designed for iPad) | 4              | 3ms      |                    |
| Older                   | 2              | 6ms      |                    |

`PageComplexityAnalyzer` pre-screens every page — clean digital PDFs skip OCR entirely (50-80% skip rate on typical documents).

### Cross-Encoder Reranking

- `TaskGroup` with device-tier-aware concurrency (2-4 parallel predictions)
- ALL query-chunk pairs tokenized upfront — tokenization overhead moved out of the hot prediction loop
- `MLMultiArray` populated via `dataPointer` bulk memory copy instead of per-element `NSNumber` subscript (3× faster array fills)

### Font-Encoded PDF Detection (PHASE -1)

Automatic Jaccard text-layer validation detects font substitution ciphers (common in Kia, Hyundai manuals) that fool every downstream quality check. Without this, 93% of content is silently lost. The system falls back to full Vision OCR when cipher encoding is detected.

### Memory-Safe Large PDF Ingestion

500+ page PDFs no longer trigger OOM watchdog kills:

- Parsed page data freed before image analysis begins (~100-200MB reclaimed)
- Image batches reduced from 20 → 5 pages (peak CIImage memory: ~50MB vs ~200MB)
- Full-page renders for Vision classification use 144 DPI (2×) instead of 360 DPI (5×)

### Pipeline Reliability

11 targeted fixes across the compression → generation → fallback chain:

- **Compression cap**: Maximum 5 chunks, fresh LLM session per chunk, per-chunk error isolation with 12s time budget
- **Generation hardening**: Empty LLM output routes to reliability fallback instead of throwing; 2s rate-limit retry with typed error cases
- **Fallback quality (Path B)**: 6 chunks × 500 chars with section titles and source names (was 3 × 240 chars, no metadata)

---

## Architecture

**102 services** organized into **11 categories**:

| Category           | Count | Key Services                                                        |
| ------------------ | ----- | ------------------------------------------------------------------- |
| **RAG Pipeline**   | 14    | RAGService, RAGEngine, VerificationGateService, AutoTuneService     |
| **Query**          | 9     | QueryEnhancementService, HyDEService, ContextualCompressionService  |
| **Document**       | 24    | IntelligentDocumentProcessor, StructuredDocumentParser, VisionOCR   |
| **Embedding**      | 7     | EmbeddingService, CoreMLSentenceEmbeddingProvider                   |
| **Storage**        | 3     | FullTextStorageService, SQLiteFullTextService                       |
| **VectorStore**    | 5     | VectorDatabase, BNNSVectorDatabase, VectorStoreRouter               |
| **LLM**            | 8     | AppleFoundationLLMService, OnDeviceAnalysisService                  |
| **Agentic**        | 7     | AgenticOrchestrator, ConversationMemoryService, WritingToolsService |
| **Infrastructure** | 22    | ContainerService, GPUComputeService, HardwareTelemetryState         |
| **Rendering**      | 1     | MarkdownRenderer (block-level parser + inline normalizer)           |
| **Billing**        | 2     | StoreKitBillingService, EntitlementStore                            |

**Full inventory**: See [ARCHITECTURE.md](ARCHITECTURE.md) → "Complete Service Inventory (102 Services)"

### Apple Framework Dependencies

OpenIntelligence is built entirely on Apple's native frameworks — **no third-party AI dependencies**:

| Framework            | Primary Use                   | Key Services                                                                         |
| -------------------- | ----------------------------- | ------------------------------------------------------------------------------------ |
| **FoundationModels** | LLM generation (iOS 26)       | `AppleFoundationLLMService`, `HyDEService`, `ContextualCompressionService`, 8 @Tools |
| **Vision**           | OCR, document detection       | `OCRConfiguration`, `DocumentProcessor`, `StructuredDocumentParser`                  |
| **NaturalLanguage**  | NER, tokenization, embeddings | `QueryEnhancementService`, `SemanticChunker`, `DocumentProcessor`                    |
| **CoreML**           | Neural embeddings, reranking  | `CoreMLSentenceEmbeddingProvider` (MiniLM-L6), `RAGEngine` (TinyBERT reranker)       |
| **PDFKit**           | PDF parsing                   | `DocumentProcessor`                                                                  |
| **Speech**           | Audio transcription           | `AudioTranscriptionService`                                                          |
| **Metal**            | GPU acceleration              | `GPUComputeService` (3-tier shaders), `VisionOCRThrottle`, `DocumentProcessor`       |
| **StoreKit 2**       | Subscription billing          | `StoreKitBillingService`                                                             |

### Data Flow

```mermaid
flowchart TD
    subgraph ING[" 📥 INGESTION "]
        A[Document<br/>PDF, DOCX, M4A, PNG] --> B[DocumentProcessor<br/>PDFKit / Vision OCR / Speech]
        B --> C[SemanticChunker<br/>≤310 words, section detect]
        C --> D[EmbeddingService<br/>384-dim, BertTokenizer ≤510]
        D --> E[(VectorDatabase<br/>HNSW + SQLite FTS5)]
    end

    subgraph RET[" 🔍 RETRIEVAL "]
        F[User Query] --> G[QueryEnhancement<br/>Intent detect, HyDE, rewrite]
        G --> H[HybridSearch<br/>Vector k-NN + BM25 + RRF k=60]
        H --> I[RAGEngine<br/>Cross-encoder rerank, MMR λ=0.6]
        I --> J[ParentDocument<br/>±5 siblings, section merge]
        J --> K[ContextPacking<br/>Graph context, token budget]
    end

    subgraph GEN[" 💬 GENERATION "]
        L[Context Assembly<br/>Lost-in-middle, 5500 char max] --> M[LLMService<br/>Apple FM, 8 @Tools]
        M --> N{Verification<br/>Gates A-G}
        N -->|Pass| O[✅ Cited Answer<br/>Sources, confidence %]
        N -->|Fail| P[🔄 Retry or Abstain]
    end

    E --> H
    K --> L
```

<details>
<summary><strong>📖 Glossary — Why Each Piece Is In OpenIntelligence</strong> (click to expand)</summary>

| Term                       | Why It's Here                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **HNSW**                   | Hierarchical Navigable Small World graph. `InMemoryVectorDatabase` builds a multi-layer graph where each chunk connects to its nearest neighbors. Searching starts at the top layer (sparse, long jumps) and descends to bottom layers (dense, precise). Result: 50,000 chunks searched in ~5ms instead of brute-force O(n) comparisons. Without this, "instant answers" would be 3-second answers.                                                                                                                                                                                                                                                                                                                                                                 |
| **SQLite FTS5**            | Full-Text Search 5 engine inside `SQLiteFullTextService`. Builds an inverted index: every word maps to which chunks contain it. Query "VIN 1HGCM82633A004352" → FTS5 instantly returns chunks containing that exact string. Vector search would fail here because embeddings capture meaning, not character sequences. FTS5 catches what vectors miss.                                                                                                                                                                                                                                                                                                                                                                                                              |
| **BM25**                   | Best Match 25 — the scoring formula inside FTS5. Factors in: (1) term frequency (mentions "oil" 8× beats 1×), (2) inverse document frequency (rare words matter more than "the"), (3) document length normalization. The chunk that's actually ABOUT oil changes scores higher than one that mentions it in passing.                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| **BertTokenizer**          | WordPiece tokenizer from the original BERT paper. Splits text into subword units: "unbelievable" → ["un", "##believ", "##able"]. Critical because MiniLM has a 512-token hard limit (510 usable after [CLS]/[SEP]). `CoreMLSentenceEmbeddingProvider.countTokens()` uses this — NOT NLTokenizer, which counts "VHA21\VHAPALGarciG1" as 1 word when it's actually 10+ tokens. Wrong count = silent truncation = lost meaning.                                                                                                                                                                                                                                                                                                                                        |
| **Contextual Prefix**      | `SemanticChunker` prepends section breadcrumbs to each chunk: "Chapter 5: Maintenance > Oil Change Procedure: [actual chunk text]". Why? A chunk saying "remove the cap and drain" means nothing without context. With the prefix, the embedding captures that this is about oil changes, not radiators. ~30 words overhead, massive relevance gain.                                                                                                                                                                                                                                                                                                                                                                                                                |
| **HyDE**                   | Hypothetical Document Embeddings via `HyDEService.swift`. Problem: user queries are short and vague ("how to fix"). Solution: generate a fake 100-word answer FIRST using Apple FM, then embed THAT and search. The hypothetical answer contains domain vocabulary the user didn't type. Deep Think mode only — adds ~500ms latency but dramatically improves recall for ambiguous queries.                                                                                                                                                                                                                                                                                                                                                                         |
| **RRF (k=60)**             | Reciprocal Rank Fusion in `HybridSearchService`. Formula: `score = Σ 1/(k + rank)` where k=60 smooths the curve. Merges two ranked lists (vector, keyword) into one. A chunk ranked #1 in keywords + #50 in vectors scores `1/61 + 1/110 = 0.0255`. A chunk ranked #5 in both scores `1/65 + 1/65 = 0.0308` — wins. Neither search dominates; both contribute fairly.                                                                                                                                                                                                                                                                                                                                                                                               |
| **MMR (λ=0.6)**            | Maximal Marginal Relevance in `RAGEngine.applyMMR()`. Iteratively selects chunks: `score = λ × relevance - (1-λ) × max_similarity_to_already_selected`. λ=0.6 means 60% relevance, 40% diversity penalty. Prevents returning 5 near-identical paragraphs from the same page. Forces coverage across different document sections. Tunable per intent — summarize queries use λ=0.5 for more diversity.                                                                                                                                                                                                                                                                                                                                                               |
| **k-NN**                   | k-Nearest Neighbors — the core retrieval primitive. `EmbeddingService` encodes query → 384-dim vector. HNSW finds the k=20 chunks with smallest cosine distance. "Car maintenance" (query) matches "vehicle servicing" (chunk) because their vectors land in similar regions of the embedding space. This is why semantic search works — meaning, not keywords.                                                                                                                                                                                                                                                                                                                                                                                                     |
| **Cross-encoder**          | `ReRankerModel.mlpackage` — a 4.5MB TinyBERT model (ms-marco-TinyBERT-L-2-v2). Unlike bi-encoders that embed query and chunk separately, cross-encoders see `[CLS] query [SEP] chunk [SEP]` together. Attention flows between them, catching subtle relevance signals. 10× slower than bi-encoder, but far more accurate. Runs on top ~20 candidates after initial retrieval to reorder by true relevance.                                                                                                                                                                                                                                                                                                                                                          |
| **Parent Document**        | `ParentDocumentService` expands context around matched chunks. If chunk #47 (0.82 relevance) matches, grab siblings #42-51 from the same document section. Why? The matching chunk might be mid-paragraph — preceding context often contains the setup, following context contains conclusions. ±5 siblings configurable. Merged chunks deduplicated before context packing.                                                                                                                                                                                                                                                                                                                                                                                        |
| **Contextual Compression** | `ContextualCompressionService` calls Apple FM with: "Given this query, extract only relevant sentences from this chunk." A 300-word chunk about oil changes might contain 200 words of background — compression strips it to the 80 words that actually answer the question. Runs BEFORE final generation. Saves 40-60% context tokens, letting more chunks fit in the 5,500-char window.                                                                                                                                                                                                                                                                                                                                                                           |
| **RAPTOR-lite**            | Recursive Abstractive Processing for Tree-Organized Retrieval — simplified. At ingestion, `RAGService` generates a ~150-word summary of each document (L1 chunk). `QueryRouterService` classifies queries: "summarize" or "what is this about" → search L1 summaries. "What's the torque spec on page 47" → search L0 detail chunks. 80% of RAPTOR's benefit (hierarchical retrieval) at 20% complexity (single summary level).                                                                                                                                                                                                                                                                                                                                     |
| **Lost-in-middle**         | Liu et al. 2023 discovered LLMs attend strongly to the start and end of context, forgetting the middle. `RAGEngine.applyLostInMiddleReordering()` fixes this: if chunks are ranked [A, B, C, D, E] by relevance, reorder to [A, C, E, D, B] — best at position 1, second-best at end, worst in middle. Apple FM now "sees" the critical evidence because it's not buried.                                                                                                                                                                                                                                                                                                                                                                                           |
| **Verification Gates**     | 7-gate anti-hallucination pipeline in `VerificationGateService`: **(A)** Retrieval confidence — top score ≥ threshold AND margin over #2 is sufficient. **(B)** Evidence coverage — every claim in the response cites a retrieved chunk. **(C)** Numeric sanity — numbers in response match source documents exactly. **(D)** Contradiction sweep — no conflicting evidence across chunks. **(E)** Semantic grounding — response embedding must be cosine-similar to source chunks. **(F)** Quote faithfulness — abbreviation expansions must match source definitions. **(G)** Generation quality — entropy and uniqueness checks catch degenerate repetition loops. Critical gates (A, C, E) fail → abstain. Advisory gates (F, G) apply confidence penalty only. |
| **Entity Index**           | `EntityIndexService` runs NLTagger NER at ingestion: extracts persons, organizations, locations, plus PascalCase technical terms. Builds a `Dict<Entity, Set<ChunkID>>` index. Query mentions "John Smith" → instant lookup returns all chunks referencing him, even if the embedding similarity is weak. Bridges the gap between keyword search (exact match) and semantic search (meaning match).                                                                                                                                                                                                                                                                                                                                                                 |
| **PCC**                    | Private Cloud Compute — Apple's confidential computing cloud. The on-device model is a ~3B dense transformer; the server model is a PT-MoE (Parallel-Track Mixture-of-Experts) trained on up to 65K token sequences. The Foundation Models framework exposes only the on-device model to third-party apps. PCC only activates when network is available, user opted in via iOS Settings, AND Apple's `modelmanagerd` decides to route there (device thermals, battery, load). `AppleFoundationLLMService` detects which ran by TTFT (<1s = on-device, >1s = PCC). Apple guarantees: end-to-end encryption, stateless computation, no data retention, cryptographic attestation, verifiable transparency.                                                            |

</details>

---

## AI Hub — Response Transforms

The AI Hub toolbar offers 5 RAG-grounded document-aware transforms powered by actual source chunks via `ResponseTransformService`:

| Transform           | What It Does                                                             |
| ------------------- | ------------------------------------------------------------------------ |
| **Key Facts**       | Extract the most important facts from the response                       |
| **Step-by-Step**    | Convert the answer into numbered procedural steps                        |
| **Plain English**   | Simplify technical language into everyday terms                          |
| **What's Missing?** | Identify gaps — what the documents don't cover about the question        |
| **Illustrate**      | Generate a visual concept via Image Playground (LLM extracts scene desc) |

Results render with full markdown formatting, include a Share button, and display in an adaptive sheet that starts at half-height.

---

## Motherboard HUD — X-Ray Your iPhone

A translucent overlay that shows where Apple Silicon components physically sit behind your screen. Real-time CPU, GPU, Neural Engine, and thermal telemetry displayed at the actual chip positions — verified from iFixit teardown images + Apple Vision AI.

- **Real-time hardware telemetry** — CPU/GPU load, memory pressure, thermal state, battery level, Neural Engine activity
- **Device-specific layouts** — Accurate component positions for iPhone 15 Pro through iPhone 17 Pro series
- **Ultra-subtle design** — Ghost outlines that pulse with activity, never distracting
- **One toggle** — Enable/disable from Settings → Telemetry

---

## Telemetry Badges

Every response shows execution metadata:

| Badge           | Meaning                                                      |
| --------------- | ------------------------------------------------------------ |
| 📱 **On-Device** | Ran on your device's Neural Engine                           |
| ☁️ **PCC**       | Ran on Apple's server silicon (same API, different hardware) |
| 🔧 **Tools: N**  | Number of @Tool functions called during reasoning            |
| ⏱️ **X.Xs**      | Total response time                                          |

---

## Privacy

- **Fully offline capable**: All parsing, embedding, search, and LLM inference run on-device with no network required
- **PCC is Apple-controlled**: If/when Apple routes to Private Cloud Compute, it uses end-to-end encryption with cryptographic attestation and zero data retention
- **No third-party APIs**: No OpenAI, no external cloud services, no API keys
- **No telemetry**: No analytics sent anywhere — ever

See [PRIVACY.md](PRIVACY.md) for full details.

---

## Getting Started

### Requirements

- **iOS 26.0+** (required for FoundationModels framework)
- **Xcode 26+** (required for Swift 6)
- **Device**: iPhone 15 Pro or newer recommended (A17+ for best performance)

### Installation

```bash
# Clone
git clone https://github.com/Gunnarguy/OpenIntelligence.git
cd OpenIntelligence

# Fetch submodules (swift-transformers)
git submodule update --init --recursive

# Open in Xcode
open OpenIntelligence.xcodeproj

# Build & Run
# Select OpenIntelligence scheme → iPhone 17 Pro → Cmd+R
```

### Troubleshooting

```bash
# Clean build if you see stale UI or build errors
./clean_and_rebuild.sh
```

---

## Project Structure

```text
OpenIntelligence/
├── App/                        # Entry point, ContentView
├── Core/
│   ├── Extensions/             # Swift extensions
│   ├── Models/                 # DocumentChunk, RAGResponse, etc.
│   └── Protocols/              # Service protocols
├── Features/
│   ├── Billing/                # StoreKit subscription UI
│   ├── Camera/                 # Vision camera overlay
│   ├── Chat/                   # Chat interface, message bubbles, AI Hub
│   ├── Database/               # Container management UI
│   ├── Diagnostics/            # Debug dashboards
│   ├── Documents/              # Document picker, ingestion UI
│   ├── Onboarding/             # Pipeline Theater first-launch experience
│   ├── Settings/               # Settings views
│   └── Telemetry/              # Motherboard HUD, execution metrics
├── Resources/
│   ├── MLModels/               # EmbeddingModel + ReRankerModel (.mlpackage)
│   └── StoreKit/               # Subscription configuration
├── Services/
│   ├── Agentic/                # AgenticOrchestrator, ConversationMemory, ResponseTransform
│   ├── Billing/                # StoreKitBillingService, EntitlementStore
│   ├── Document/               # DocumentProcessor, SemanticChunker, OCR, Transcription
│   ├── Embedding/              # EmbeddingService, CoreMLProvider, BertTokenizer
│   ├── Infrastructure/         # ContainerService, GPUCompute, Telemetry, Spotlight
│   ├── LLM/                    # AppleFoundationLLMService, 8 @Tool implementations
│   ├── Query/                  # QueryEnhancement, HyDE, Compression, Router
│   ├── RAG/                    # RAGService, RAGEngine, HybridSearch, VerificationGates
│   ├── Storage/                # FullTextStorage, SQLiteFTS5
│   └── VectorStore/            # VectorDatabase, BNNS, InMemory, Router
└── UI/                         # Shared UI components, MarkdownRenderer
```

---

## Roadmap — Apple Intelligence Gap Closure

We've audited every Apple Intelligence framework from WWDC 2024 and 2025 against the codebase. **23 framework opportunities** identified across WWDC24/25 sessions. **10 active** in production, **5 code-complete** (not yet wired to UI), **9 remaining**:

### Active in v2.1 (10 frameworks)

Guardrails API, CoreSpotlight, SpeechAnalyzer, Image Playground, NLGazetteer, BackgroundTasks, TipKit, Smart Reply, `supportsLocale()`, NSUserActivity

### Code Complete / Not Wired (5 frameworks)

Visual Intelligence (App Intents), Translation.framework, Adapter Training, Prompt Evaluation, BNNS Graph

### Remaining Gaps

| Target   | Frameworks                                                                        |
| -------- | --------------------------------------------------------------------------------- |
| **v2.1** | Liquid Glass, UseCase                                                             |
| **v2.2** | Metal 4, Lens Smudge Detection                                                    |
| **v3.0** | `@Observable` migration, WidgetKit, SwiftData, Genmoji, DataScannerViewController |

> **Full details**: See [ROADMAP.md](ROADMAP.md) → "Phase 2.15 — Apple Intelligence Gap Closure"

---

## Documentation

| Document                                            | Description                                                     |
| --------------------------------------------------- | --------------------------------------------------------------- |
| **[HOW_IT_WORKS.md](HOW_IT_WORKS.md)**              | 🔥 Plain-English deep dive: 5 gears, token budget, orchestrator |
| [ARCHITECTURE.md](ARCHITECTURE.md)                  | Complete technical architecture, 102-service inventory          |
| [RAG_TECHNICAL.md](Docs/reference/RAG_TECHNICAL.md) | Technical specs: HyDE, math, formulas, & algorithms             |
| [APPLE_MODELS.md](Docs/reference/APPLE_MODELS.md)   | Apple Intelligence specs: Context limits & token economics      |
| [ROADMAP.md](ROADMAP.md)                            | Feature roadmap and version history                             |
| [PRIVACY.md](PRIVACY.md)                            | Privacy policy and data handling                                |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Write Swift 6 compliant code with `actor` isolation for heavy tasks
4. Test on device (Simulator lacks Apple FM)
5. Submit a PR with clear description

### Coding Standards

- Use `async/await` and `actor` for concurrency (no GCD)
- Never send data to cloud without explicit consent
- Update `Docs/reference/` when changing architecture

---

## License

MIT License — see [LICENSE](LICENSE) for details.
