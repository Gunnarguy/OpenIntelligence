# OpenIntelligence — Hard Limits & Architectural Constraints

> **Purpose**: Single source of truth for every hard constraint in the system. If you're about to add a feature, check this first.
> **Last Verified**: April 24, 2026
> **Rule**: If a change violates ANY constraint below, it MUST be justified with a measured workaround.

---

## The Absolute Limits

These are non-negotiable. They come from hardware, Apple's model architecture, and physics.

### LLM Constraints (Apple Foundation Models)

| Constraint                    | Value            | Source         | Why It Matters                                                        |
| ----------------------------- | ---------------- | -------------- | --------------------------------------------------------------------- |
| Context window                | **4096 tokens**  | TN3193         | EVERYTHING (instructions, prompts, tools, context, response) must fit |
| Token ≈ chars (English)       | ~3-4 chars/token | TN3193         | 4096 tokens ≈ 14,336 chars max for entire session                     |
| Token ≈ chars (CJK)           | ~1 char/token    | TN3193         | Much less room for Asian languages                                    |
| Model size                    | ~3B parameters   | Tech Report    | This is what we get. Not 7B, not 70B. 3B at 2-bit.                    |
| Quantization                  | 2-bit QAT        | Tech Report    | Quality is ~64.4 MMLU after compression (down from 67.8)              |
| Max recommended tools         | 3-5              | TN3193         | More tools = more schema tokens consumed = less room for content      |
| Adapter rank                  | 32 (fixed)       | Tech Report    | Cannot change; must retrain per model version                         |
| PCC/server model access       | No direct public app API | Framework docs / PCC docs | Do not claim app-controlled access to Apple's server model             |
| Server context (do not market) | ~65K trained context | Tech Report | Describes Apple's server model training, not a verified app context window |

### Embedding Constraints (CoreML MiniLM-L6-v2)

| Constraint                 | Value         | Why It Matters                                          |
| -------------------------- | ------------- | ------------------------------------------------------- |
| Max embedding tokens       | **510**       | 512 minus CLS/SEP tokens                                |
| Embedding dimension        | **384**       | All vectors must be 384-dim. Dimension mismatch = crash |
| Tokenizer                  | BertTokenizer | NOT NLTokenizer. Different word boundaries.             |
| Technical text token ratio | **Variable**  | `VHA21\VHAPALGarciG1` = 1 NL word but 10+ BPE tokens    |

### Chunking Constraints

| Constraint                    | Value         | Derivation                                       |
| ----------------------------- | ------------- | ------------------------------------------------ |
| Max chunk size                | **310 words** | 340 target - 30 words contextual prefix overhead |
| Max chunk limit per container | **50,000**    | Supports ~65,000 pages                           |
| Contextual prefix overhead    | ~30 words     | Section/document context prepended to each chunk |

### Context Packing Constraints

| Constraint                | Value     | Why                                                                                  |
| ------------------------- | --------- | ------------------------------------------------------------------------------------ |
| Max RAG context chars     | **5,500** | ~4,000 tokens with safety margin for instructions + response                         |
| Target RAG context tokens | ~1,500    | Leaves room for instructions (~400), prompt (~300), response (~1,500), buffer (~300) |

### Infrastructure Constraints

| Constraint           | Value                | Notes                               |
| -------------------- | -------------------- | ----------------------------------- |
| OCR render scale     | **5x-6x adaptive**   | PDF/image quality, table risk, and fidelity mode drive effective scale |
| Simulator limitation | Apple FM unavailable | Must test with fallback LLM service |
| KV cache (model)     | 8-bit quantized      | Set by Apple, not configurable      |
| Embedding table      | 4-bit quantized      | Set by Apple, not configurable      |

---

## Token Budget Breakdown

```
4096 tokens total
├── Instructions:          ~200-400 tokens
├── Tool schemas (3-5):    ~100-300 tokens
├── @Generable schema:     ~50-100 tokens
├── User prompt:           ~100-500 tokens
├── RAG context:           ~1,000-1,500 tokens (~3,500-5,250 chars)
├── Model response:        ~500-1,500 tokens
└── Safety buffer:         ~200 tokens
```

**If you add a feature that increases ANY of these categories, something else MUST shrink.**

---

## What We CAN Do vs. What We CANNOT Do

### CAN Do (On-Device ~3B Model)

| Capability               | Quality Level | Notes                                          |
| ------------------------ | ------------- | ---------------------------------------------- |
| Summarization            | Good          | Core strength per Apple                        |
| Entity extraction        | Good          | Core strength per Apple                        |
| Text classification      | Good          | Use `contentTagging` model for lighter version |
| Short Q&A with context   | Good          | If context fits in ~1500 tokens                |
| Structured output        | Excellent     | `@Generable` + constrained decoding = reliable |
| Tool calling (3-5 tools) | Good          | Guaranteed structural correctness              |
| Image understanding      | Good          | 3 resolution modes available                   |
| Multilingual (16 langs)  | Good          | RLHF-improved, native-sounding output          |

### CANNOT Do (Fundamental Limitations)

| Capability                    | Why Not                                                        | What We Do Instead                              |
| ----------------------------- | -------------------------------------------------------------- | ----------------------------------------------- |
| Full GraphRAG entity resolution | Requires evaluated entity extraction, relationship extraction, clustering, and community summaries | Graph-lite/context packing + deterministic entities |
| LLM-powered triple extraction | Needs larger context + higher-quality model verification       | Rule-based / deterministic entity co-occurrence where useful |
| Community summarization       | Requires processing entire graph neighborhoods                 | RAPTOR-lite document summaries and overview routing |
| Multi-hop reasoning (>2 hops) | Token budget can't fit enough context                          | Multi-session agentic reasoning (3-50 sessions) |
| General world knowledge       | Apple explicitly says it's NOT a chatbot                       | RAG-grounded responses only                     |
| Long document single-pass     | 4096 tokens ≈ 2-3 pages of text                                | Chunk + summarize + reassemble                  |
| Code generation (GPT-4 level) | 3B model, not comparable                                       | Not our use case                                |
| Real-time streaming inference | Latency varies by prompt/response length                       | Prefetch + prewarm strategies                   |

---

## Why GraphRAG Won't Work Here

The GraphRAG blog article describes a system requiring:

| GraphRAG Requirement            | What It Needs                                 | What We Have                                    |
| ------------------------------- | --------------------------------------------- | ----------------------------------------------- |
| LLM entity extraction           | Large context, high-quality LLM               | 3B model, 2-bit, 4096 tokens                    |
| LLM relationship extraction     | Multi-entity prompts, evidence tracking       | Can't fit enough context                        |
| LLM community summarization     | Process 20+ entity descriptions per community | Would consume entire token budget               |
| Three-index synchronization     | Text + vector + graph atomic updates          | Current product has text + vector + graph-lite/context packing, not full community GraphRAG |
| Entity resolution >85% accuracy | LLM-powered disambiguation with DBSCAN        | Our NLTagger gives NER tags, not disambiguation |
| Query cost: $0.008/query        | Cloud LLM API calls                           | We have $0.00/query (on-device, free)           |

**Our approach (which IS correct for our constraints):**

- Entity extraction via NLTagger (free, fast, no tokens consumed)
- Semantic similarity via embedding vectors (MiniLM, no LLM needed)
- Keyword matching via BM25/FTS5 (no LLM needed)
- Hybrid search via RRF fusion (algorithmic, no LLM)
- Context packing into 5500 chars → single LLM call for generation

**Most of our pipeline deliberately avoids the LLM to save the token budget for the one thing only the LLM can do: generate the answer.**

---

## Multi-Session Strategy (What Apple Recommends)

Apple's TN3193 explicitly recommends splitting large tasks across sessions:

```
Session 1: Summarize chunk 1 → save result
Session 2: Summarize chunk 2 → save result
Session 3: Combine summaries → final answer
```

Our agentic orchestrator does exactly this:

| Mode       | Sessions | Purpose                                                       |
| ---------- | -------- | ------------------------------------------------------------- |
| Standard   | 3        | Direct synthesis from retrieved chunks                        |
| Deep Think | 4-8      | Self-RAG 2.0: each session ADDS details from different angles |
| Maximum    | 8-50     | Multi-chain parallel reasoning + cluster synthesis            |

**This is the correct architecture. More sessions, not bigger context windows.**

---

## Current Repo-Specific Constraints

- `OpenIntelligence/Services` currently contains 107 Swift service files. The service count is real, but the most important orchestration risk is concentration in `RAGService.swift` and `DocumentProcessor.swift`.
- `AppleFMEmbeddingProvider.swift` is a placeholder/scaffold. Current embeddings come from Core ML/Natural Language paths, not a public Apple FoundationModels embedding API.
- SQLite full-text storage uses shared tables with `container_id` isolation. It is not one SQLite database per library.
- The vector store is per container, with memory-mapped `_vectors.bin`, `_norms.bin`, and `_meta.json` persistence in the BNNS/Accelerate implementation.
- CAG is only safe for tiny library summaries, session summaries, or cached routing artifacts. It is not a replacement for RAG under a 4096-token FoundationModels session budget.

---

## Checklist Before Adding Any Feature

- [ ] Does it fit in 4096 tokens? (instructions + tools + prompt + context + response)
- [ ] Does it require LLM reasoning that a 3B/2-bit model can handle?
- [ ] Does it avoid consuming tokens for work that can be done algorithmically?
- [ ] Does it work within the public FoundationModels path? (no direct PCC/server-model dependency)
- [ ] Does it handle the embedding 510-token limit?
- [ ] Does it maintain chunk size ≤ 310 words?
- [ ] Does it keep RAG context ≤ 5,500 characters?
- [ ] Does it work with 3-5 tools or fewer?
- [ ] Does it handle Apple FM unavailability on simulator?
- [ ] Is it domain-agnostic? (no hardcoded automotive/medical/legal bias)

---

## References

- [TN3193 — Context Window Management](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple FM Tech Report 2025](https://arxiv.org/abs/2507.13575) → See [APPLE_FM_TECH_REPORT_2025.md](./APPLE_FM_TECH_REPORT_2025.md)
- [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/) → See [PRIVATE_CLOUD_COMPUTE.md](./PRIVATE_CLOUD_COMPUTE.md)
- [Foundation Models Framework API](https://developer.apple.com/documentation/foundationmodels) → See [APPLE_MODELS.md](./APPLE_MODELS.md)
- [Current State and Gaps](./CURRENT_STATE_AND_GAPS.md)
