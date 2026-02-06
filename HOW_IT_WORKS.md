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

### 1. Chunking

**"Break documents into pieces small enough to embed"**

We cannot feed a 50-page PDF into the model at once. We must slice it.

- **Rule:** Max 310 words per chunk.
- **Why?** The embedding model has a hard limit of 510 tokens. 310 words + overhead ensures we never crash the tokenizer.
- **Result:** A 50-page document becomes ~200 individual chunks.

### 2. The Core Concept: Embeddings

**"Convert text chunks into comparable numbers"**

This is the foundation of semantic search. The embedding model (`MiniLM-L6-v2`) takes each text chunk and converts it into a list of 384 numbers (a vector).

```
Text → [384 numbers] → Math becomes possible
```

- "How do I change my oil?" → `[0.23, -0.87, 0.45, ...]`
- "Vehicle lubricant replacement procedure" → `[0.25, -0.84, 0.43, ...]`

Even though the words are different, the _vectors_ are mathematically close in 384-dimensional space. This allows us to find answers based on _meaning_, not just keywords.

### 3. Storage (BNNS Optimized)

Once embedded, we store these vectors in a **BNNS-accelerated index** (Basic Neural Network Subroutines). This allows the Neural Engine to brute-force compare a query against thousands of chunks in milliseconds.

---

## Step 2: Retrieval (Query → Candidates)

When a user asks a question, we need to find the "needle in the haystack" (the relevant chunks).

### 1. Hybrid Search

We don't rely on just one method. We use two:

1.  **Vector Search (Semantic):** Finds concepts (e.g., matching "oil" to "lubricant").
2.  **BM25 (Keyword):** Finds exact matches (e.g., matching part number "XYZ-123").

We fuse these results using **RRF (Reciprocal Rank Fusion)** to get the top ~50 candidates.

### 2. Reranking (The Quality Filter)

The top 50 candidates are "statistically" close, but maybe not "logically" relevant.

- **Tool:** Cross-Encoder (TinyBERT).
- **Action:** Looks at the specific [Query + Chunk] pair together.
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
  1. Initial Retrieval.
  2. LLM analyzes: "What is missing?"
  3. Generate _new_ search queries.
  4. Retrieve again.
  5. Repeat 4-8 times.
  6. Synthesize final answer.
- **Speed:** 10-30 seconds.
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
