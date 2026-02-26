# How OpenIntelligence Actually Works

**A chronological walkthrough of the pipeline: Ingestion → Retrieval → Reasoning → Output.**

> **Built on Apple's AI Stack**: 100% native—FoundationModels (iOS 26), Vision OCR, NaturalLanguage NER, CoreML embeddings. No third-party AI dependencies. See [ARCHITECTURE.md](ARCHITECTURE.md#apple-framework-dependencies) for complete framework inventory.

## Table of Contents

- [How OpenIntelligence Actually Works](#how-openintelligence-actually-works)
  - [Table of Contents](#table-of-contents)
  - [Pipeline Overview](#pipeline-overview)
  - [Step 1: Ingestion (Data → Numbers)](#step-1-ingestion-data--numbers)
    - [1. Chunking](#1-chunking)
    - [2. The Core Concept: Embeddings](#2-the-core-concept-embeddings)
    - [3. Storage (BNNS Optimized)](#3-storage-bnns-optimized)
  - [Step 2: Retrieval (Query → Candidates)](#step-2-retrieval-query--candidates)
    - [1. Hybrid Search](#1-hybrid-search)
    - [2. Reranking (The Quality Filter)](#2-reranking-the-quality-filter)
  - [Step 3: The Bottleneck (Token Budget)](#step-3-the-bottleneck-token-budget)
    - [The Problem](#the-problem)
    - [The Solution: Context Packing](#the-solution-context-packing)
  - [Step 4: Orchestration (The Modes)](#step-4-orchestration-the-modes)
    - [Standard Mode (1 Pass)](#standard-mode-1-pass)
    - [Deep Think Mode (4-8 Passes)](#deep-think-mode-4-8-passes)
    - [Maximum Mode (8-50 Passes)](#maximum-mode-8-50-passes)
  - [Step 5: The Agentic Brain (Deep Reasoning)](#step-5-the-agentic-brain-deep-reasoning)
    - [The Decision Loop](#the-decision-loop)
    - [The Accumulation Pattern](#the-accumulation-pattern)
  - [Step 6: Generation (The Output)](#step-6-generation-the-output)
    - [The Model: Apple Foundation Model](#the-model-apple-foundation-model)
    - [Summary](#summary)

---

## Pipeline Overview

Before diving into the steps, here is the high-level map of the machine.

```
┌─────────────────────────────────────────────────────────────────┐
│   INPUT: RAW DOCUMENT                                           │
│   "PDFs, Text, Images"                                          │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│   STEP 1: INGESTION & INDEXING                                  │
│   Parse → Chunk (≤310 words) → Embed (384-dim) → Store (BNNS)   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│   STEP 2: RETRIEVAL                                             │
│   Query → Hybrid Search (Vector + BM25) → Cross-Encoder Rank    │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│   STEP 3: CONTEXT PACKING                                       │
│   Fit best chunks into 4096 token limit (Lost-in-Middle sort)   │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│   STEP 4: ORCHESTRATION & GENERATION                            │
│   Mode Selection (Standard/Deep) → Apple FM → Final Answer      │
└─────────────────────────────────────────────────────────────────┘
```

---

## Step 1: Ingestion (Data → Numbers)

The process begins with converting human-readable documents into machine-understandable math.

### 0. Adaptive Document Intelligence

**"Understand the document BEFORE reading it"**

Before OCR even runs, the engine analyzes each page:

1. **Text Layer Validation (PHASE -1)**: Before any per-page processing, the engine validates the entire document's text layer against Vision OCR output. Font-encoded PDFs (Kia, Hyundai, many Asian-publisher manuals) use font substitution ciphers — every glyph maps to the wrong character, so "FOREWORD" reads as "GPSFXPSE". This garbled text passes ALL quality checks (100% printable ASCII, normal word lengths, NLLanguageRecognizer detects "Dutch"). PHASE -1 renders one sample page via Vision OCR, compares OCR words to PDFKit words via Jaccard similarity. Threshold < 0.15 = garbled. When detected, every page is forced through full OCR — prevents **93% content loss** on affected documents.
2. **Page Complexity Analysis**: `PageComplexityAnalyzer` scores every page for text quality, table presence, numeric density, and visual complexity. Pages with tables/numbers are FORCED through Vision OCR even if PDFKit text looks acceptable (because PDFKit scrambles table cell values).
3. **Dynamic Vocabulary Extraction**: PDFKit's rough text layer is mined for acronyms, alphanumeric codes (e.g., "0W-20", "R-134a"), CamelCase terms, and compound units. These become Vision's `customWords` so it doesn't autocorrect legitimate technical terms.
4. **Adaptive Preprocessing**: Based on page quality, one of 5 GPU-accelerated CIFilter strategies is selected — from "minimal" (clean digital PDFs) to "maximum" (faded microfiche/bad phone photos) — applying appropriate sharpening, contrast, denoising, and exposure correction. CIFilter rendering runs on a **concurrent** `DispatchQueue` — CIContext is thread-safe, so multiple pages preprocess in parallel.
5. **Multi-Candidate Confidence OCR**: Vision returns up to **5** alternative transcriptions per text line. Numeric data requires 90% confidence (vs 85% for text). When a table cell reads "15.5" at 82% confidence but "14.3" at 78%, both alternatives are flagged for verification rather than blindly trusting the first guess.

**Memory-Safe Image Analysis (v1.2):** After OCR parsing completes, the engine analyzes pages for images/diagrams. For 500+ page PDFs, this would previously OOM-kill the app. Now: parsed results are freed before image analysis begins (~100-200MB reclaimed), pages are processed in **5-page batches** (was 20), and image understanding renders use **144 DPI** (2× scale) instead of the 360 DPI used for OCR — each page image is ~4MB instead of ~25MB. All renders wrapped in `autoreleasepool` for immediate Core Graphics cleanup.

### 1. Chunking

**"Break documents into pieces small enough to embed"**

We cannot feed a 50-page PDF into the model at once. We must slice it.

- **Rule:** Max 310 words per chunk.
- **Why?** The embedding model has a hard limit of 510 tokens. 310 words + overhead ensures we never crash the tokenizer.
- **Table Preservation:** Tables (markdown `|` tables, tab-separated data) are detected as a pre-pass and treated as atomic units. The chunker never splits through a table — it snaps boundaries to table edges or includes a table as one oversized chunk rather than destroying its row structure.
- **Result:** A 50-page document becomes ~200 individual chunks, with spec tables kept intact.

### 2. The Core Concept: Embeddings

**"Convert text chunks into comparable numbers"**

This is the foundation of semantic search. The embedding model (`MiniLM-L6-v2`) takes each text chunk and converts it into a list of 384 numbers (a vector).

```
Text → [384 numbers] → Math becomes possible
```

- "How do I change my oil?" → `[0.23, -0.87, 0.45, ...]`
- "Vehicle lubricant replacement procedure" → `[0.25, -0.84, 0.43, ...]`

Even though the words are different, the _vectors_ are mathematically close in 384-dimensional space. This allows us to find answers based on _meaning_, not just keywords.

### 3. Storage (BNNS + Metal GPU Optimized)

Once embedded, we store these vectors in a **BNNS-accelerated index** backed by **Metal GPU compute**. The GPU search path uses a 3-tier shader selection:

1. **Threadgroup** (≥1000 vectors): Caches the query in fast shared memory + SIMD4 vector ops — the fastest path. MiniLM's 384 dimensions fit exactly (384/4 = 96 float4s).
2. **SIMD4** (100-999 vectors): Processes 4 floats per hardware cycle — 4× scalar throughput.
3. **Scalar** (fallback): Works with any dimension.

For mmap'd vector databases, `makeBuffer(bytesNoCopy:)` lets the GPU read directly from memory-mapped pages on Apple Silicon unified memory — no heap copy for the document vectors.

---

## Step 2: Retrieval (Query → Candidates)

When a user asks a question, we need to find the "needle in the haystack" (the relevant chunks).

### 1. Hybrid Search

We don't rely on just one method. We use two **independent, parallel** searches:

1.  **Vector Search (Semantic):** Finds concepts (e.g., matching "oil" to "lubricant"). Runs via vDSP-accelerated cosine similarity.
2.  **FTS5 BM25 (Keyword):** Finds exact matches (e.g., matching part number "XYZ-123"). Uses AND-first FTS5 queries (all terms must co-occur) with automatic OR fallback. Scoring uses SQLite's native `bm25()` function with weighted columns (section_title: 10×, section_path: 5×, content: 1×).

Both searches run **concurrently** via `async let` — producing two independent ranked lists. We fuse these results using **RRF (Reciprocal Rank Fusion)** to get the top ~50 candidates. FTS5-only matches (chunks that wouldn't appear in vector results) now surface through RRF with fair ranking.

### 2. Reranking (The Quality Filter)

The top 50 candidates are "statistically" close, but maybe not "logically" relevant.

- **Tool:** Cross-Encoder (TinyBERT) with **concurrent predictions**.
- **Action:** All query-chunk pairs are pre-tokenized, then scored in parallel using a `TaskGroup` (2-4 concurrent predictions based on device tier). `MLMultiArray` buffers are filled via bulk `dataPointer` writes — 3× faster than per-element subscripts.
- **Result:** Reorders the top 50 by actual relevance, discarding the noise. We keep only the top 5-10.

---

## Step 3: The Bottleneck (Token Budget)

Before we can generate an answer, we hit the hard constraint: **The 4096 Token Window.**

### The Problem

Everything competes for the same space:

1.  **System Instructions:** ~400 tokens
2.  **User Question:** ~100 tokens
3.  **The Answer (Reservation):** ~800 tokens
4.  **Available for Context:** ~2500-3000 tokens (~10 chunks)

### The Solution: Context Packing

The `ContextPackingService` treats this like a game of Tetris:

1.  Takes the top reranked chunks.
2.  Fits them into the remaining budget (approx. 2500-5500 characters).
3.  **Lost-in-Middle Reordering:** It places the _most_ important chunks at the beginning and end of the context window, because LLMs pay less attention to the middle.

---

## Step 4: Orchestration (The Modes)

Now that we have the context, **RAGService** decides how to run the generation. This is where "Quality Modes" come in.

### Standard Mode (1 Pass)

**"Search once, answer once"**

- **Process:** Retrieval → Packing → 1 LLM Call.
- **Speed:** 2-5 seconds.
- **Use Case:** Simple lookups, facts.
- **Mechanism:** The LLM is called _once_ at the very end. It just summarizes the chunks we found.

### Deep Think Mode (4-8 Passes)

**"Search, answer, search better, enrich, repeat"**

- **Process:**
  1. Initial Retrieval (same hybrid search as Standard).
  2. **ExtractiveQA Pre-Check:** For simple lookups, try to extract the answer directly before entering multi-session reasoning. Saves 4-8 LLM sessions when a spec is directly extractable.
  3. LLM analyzes: "What is missing?"
  4. Generate _new_ search queries.
  5. Retrieve again (auto-enables **iterative retrieval** for multi-hop intents like compare/investigate).
  6. Repeat 4-8 times.
  7. Synthesize final answer.
- **Speed:** 10-30 seconds (or 2-5s if ExtractiveQA short-circuits).
- **Use Case:** Complex research, multi-part questions.

### Maximum Mode (8-50 Passes)

**"Search everything from every angle"**

- **Process:** Spawns multiple _parallel_ Deep Think chains on different clusters of documents (e.g., one chain reads "Safety Docs", another reads "Engine Specs").
- **Speed:** 30s - 2 minutes.
- **Use Case:** "Summarize this entire project."

---

## Step 5: The Agentic Brain (Deep Reasoning)

For **Deep Think** and **Maximum** modes, the `AgenticOrchestrator` takes over. It doesn't just "guess"; it evaluates.

### The Decision Loop

1.  **Self-RAG Check:** "Does this question even need documents?" (If user asks "2+2", skip retrieval).
2.  **Evaluate Retrieval Quality:**
    - It checks **Lexical Relevance** (do words match?).
    - It checks **Semantic Intent** (does the chunk answer the specific question?).
3.  **Branching Logic:**
    - **Excellent Results:** Go straight to reasoning.
    - **Poor Results:** Trigger **Graph Expansion** (look for related documents) before giving up or answering.

### The Accumulation Pattern

In multi-step reasoning, the specific LLM calls are **stateless** (they don't remember the past).

- The Orchestrator maintains a "memory" of insights.
- **Session 1 Output:** "Found oil type." -> Saved to memory.
- **Session 2 Input:** "Here is the memory: 'Found oil type'. Now find capacity."
- This allows us to build answers larger than any single context window could hold.

---

## Step 6: Generation (The Output)

Finally, we generate the human-readable response. This is the only part the user sees.

### The Model: Apple Foundation Model

We use the on-device ~3 billion parameter model (Quantized to 3.7 bits).

- **Role:** It acts as the "Mouth." It takes the "Brain's" findings (the context) and formulates a coherent sentence.
- **Capability:** 30 tokens/sec generation.
- **Verification:**
  - **VerificationGateService** runs after generation.
  - It checks: "Did the model hallucinate?"
  - If the model claims a number that isn't in the source chunks, the answer is flagged or discarded.

### Summary

The system is `Search Engine` + `Logic Controller` + `Writer`.

1.  **Search Engine:** Finds the raw data (Ingestion/Retrieval).
2.  **Logic Controller:** Fits data into constraints and iterates (Orchestration).
3.  **Writer:** Formats the final text (Generation).

### Failure Recovery: Pipeline Reliability Hardening (v1.2)

Apple's on-device FM has rate limits and a 4096-token context window. If compression consumes too many FM calls, the generation call can fail silently — returning 0 tokens. The pipeline now has 11 hardening fixes to prevent this:

**Compression Hardening:**

- Maximum **5 chunks** sent to compression (was unlimited)
- **Fresh session** (`resetSession()`) before each chunk prevents transcript overflow after 3-4 compressions
- **Per-chunk error isolation** — one compression failure no longer aborts the batch
- **12-second time budget** — compression bails early if time runs out, passing remaining chunks through as originals
- **1-second cooldown** after compression lets FM rate limits recover before generation

**Generation Hardening:**

- **Empty response → fallback** — 0-token LLM output routes to `buildReliabilityFallbackResponse()` instead of throwing
- **Rate-limit retry** — detects rate-limited errors, sleeps 2s, retries once
- **Typed LLM errors** — `.rateLimited` and `.concurrentRequests` cases replace fragile string matching

**Fallback Quality:**

- **Extractive Path B rewrite** — 6 chunks × 500 chars with section titles and source names (was 3 × 240 chars, no metadata)
- **Partial stream threshold** lowered from 24 → 10 chars to salvage more partial output
- **Error logging** in reliability fallback (was silent `try?`)

---

## Bonus: Device-Optimized Performance (v1.2)

Every pipeline stage adapts to the specific Apple Silicon in your device. The system detects your chip at launch and configures concurrency, compute units, and shader selection accordingly.

### Hardware-Aware Pipeline

| Stage             | What Adapts                      | How                                                                                           |
| ----------------- | -------------------------------- | --------------------------------------------------------------------------------------------- |
| **OCR**           | Concurrent Vision ops + cooldown | A19: 8 ops / 1ms. A18: 6 / 2ms. A17: 4 / 3ms. Adaptive filtering skips 50-80% of clean pages. |
| **Preprocessing** | CIFilter rendering queue         | Concurrent (was serial) — CIContext is thread-safe per Apple docs                             |
| **Embedding**     | CoreML compute units             | GPU (`.cpuAndGPU`) during ingestion, freeing ANE for Vision OCR                               |
| **Vector Search** | Metal shader tier                | Threadgroup (≥1000 docs) → SIMD4 (100+) → scalar fallback                                     |
| **Reranking**     | TaskGroup concurrency            | 2-4 parallel cross-encoder predictions based on device tier                                   |

### Metal Shader Selection

The GPU vector search automatically picks the fastest compatible kernel:

```
Query arrives → check dimension alignment → check corpus size
  │
  ├── dimension % 4 == 0 AND dimension/4 ≤ 96 AND docs ≥ 1000
  │   └── THREADGROUP: Query cached in shared memory + SIMD4 (fastest)
  │
  ├── dimension % 4 == 0 AND docs ≥ 100
  │   └── SIMD4: float4 vector ops (4× scalar)
  │
  └── else
      └── SCALAR: Per-element float ops (always works)
```

MiniLM-L6-v2 (384 dimensions) → 384/4 = 96 float4s → fits exactly in `sharedQuery[96]`, so all searches ≥1000 vectors take the threadgroup fast path.

---

## Bonus: Motherboard HUD (v1.1)

While the RAG pipeline handles the intelligence, the **Motherboard HUD** shows you what's happening inside the device in real-time.

### What It Shows

A translucent X-ray overlay on the chat screen renders the physical positions of Apple Silicon components — exactly where they sit behind the glass. Each component pulses with live telemetry:

| Component   | Telemetry                        | Visual                              |
| ----------- | -------------------------------- | ----------------------------------- |
| **SoC**     | CPU + GPU + Neural Engine load   | Pulsing glow at the A-series chip   |
| **NAND**    | Storage activity                 | Activity indicator at flash storage |
| **DRAM**    | Memory pressure (normal/warning) | Color-coded at the RAM position     |
| **Modem**   | Network state                    | Signal indicator at Qualcomm modem  |
| **PMIC**    | Battery + thermal state          | Power management chip activity      |
| **WiFi/BT** | Wireless activity                | Radio module indicator              |
| **Taptic**  | Haptic feedback                  | Animated pulse at Taptic Engine     |

### How Positions Are Determined

Component positions come from iFixit teardown photographs analyzed with Apple Vision AI. Each device model has its own layout map — an iPhone 15 Pro has components in different positions than an iPhone 17 Pro. The HUD normalizes these positions to screen coordinates.

### Design Philosophy

**Ultra-subtle**: Components render as barely-visible ghost outlines. You can read chat messages through them. They only become noticeable when activity spikes — exactly when you'd want to see them.

---

## Bonus: Universal Retrieval (v1.1)

Eight targeted fixes to the retrieval pipeline that collectively ensure near-perfect needle-in-haystack accuracy across any document type:

1. **Lexical Always-On** — BM25 keyword search always contributes to hybrid results, even when vector search dominates. Previously, high vector scores could suppress lexical matches entirely.
2. **Proportional Hit-Rate** — RRF fusion weights scale with each method's hit count. If BM25 finds 50 matches and vector finds 10, BM25 gets proportionally more influence.
3. **HyDE Blending** — The hypothetical document embedding is blended 70/30 with the original query embedding instead of replacing it. This preserves the user's exact terminology.
4. **Year/Integer Exemption** — Verification Gate C no longer flags years (1900-2100) or small integers (1-10) as potential hallucinations. "Chapter 3" and "2024" aren't fabricated numbers.
5. **Sentence-Scored Fallback** — When LLM-based contextual compression fails, individual sentences are scored by query-term overlap and information density. This preserves critical data.
6. **Rare Term Preservation** — Query expansion includes rare corpus terms that exactly match query words, even if they don't appear in the synonym dictionary.
7. **Corpus-Learned Synonyms** — Dynamic synonym generation from document word co-occurrence data. If "viscosity" always appears near "SAE" in your documents, they become synonyms.
8. **Adaptive Reranking** — Cross-encoder candidate pool scales with corpus size: `min(count, max(100, topK×5))`. Large corpora get more candidates evaluated.

---

## Bonus: Rich Markdown Rendering (v1.2)

Responses now display with proper formatting — headers, bullet lists, numbered lists, bold text, code blocks — instead of a wall of unformatted text.

### The Problem

Apple's on-device Foundation Model outputs markdown syntax (`### headers`, `- bullets`, `**bold**`) but concatenates everything on a single line. The previous renderer treated all text as inline content, so `### Header - **Item**: description` displayed as plain text with literal `###` symbols visible.

### The Fix (Three Layers)

1. **Block-Level Parser**: `MarkdownRenderer.swift` was rewritten from `.inlineOnlyPreservingWhitespace` to a full parser that recognizes headings, bullets, numbered lists, code fences, block quotes, and horizontal rules. Each block renders as its own SwiftUI view with appropriate styling.

2. **Inline Normalizer**: A preprocessing step (`normalizeInlineMarkdown()`) uses 6 regex patterns to detect markdown syntax embedded mid-line and split it onto separate lines before the parser runs. For example, `Sport mode - **Throttle**: aggressive` becomes two lines — the text before, and `- **Throttle**: aggressive` as a proper bullet.

3. **Pipeline Preservation**: Seven response-cleaning functions across 4 files were audited. Two were actively stripping ALL markdown from responses — `cleanupResponseText()` in RAGService and `cleanupFinalAnswer()` in AgenticOrchestrator. Both were rewritten to preserve formatting while still removing orphaned markers and degenerate artifacts.

### Why It Matters

The LLM produces good structure — headers for sections, bullets for lists, bold for key terms. Without proper rendering, users see raw syntax mixed into a single paragraph. With it, responses look like well-formatted documents with clear visual hierarchy.
