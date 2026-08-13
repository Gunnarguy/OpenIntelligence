# Embedding & Ingestion Upgrade Assessment — August 2026

> **Purpose:** answer "is the SQLite and ingestion as good as it can be?" with evidence rather than
> opinion. Surveys the shipped stack, names what is genuinely strong, isolates the quality ceiling,
> and lists the concrete upgrades worth doing with sources.
> **Status:** research only. Nothing here is implemented. No benchmark has been run on this corpus.
> **Method:** code survey of the shipped v4.9 tree, then web research 2026-08-03.

---

## 1. What the shipped stack actually does

Established by reading the tree, not from memory.

| Layer | Implementation | Verdict |
| --- | --- | --- |
| Table extraction | `RecognizeDocumentsRequest` + `document.tables` (iOS 26+) | Current Apple API, correctly used |
| Image understanding | `ImageUnderstandingService` — classification, description, spatial caption association | Ahead of typical |
| OCR quality gating | `OCRConfiguration` — printable ratio, entropy, consonant-noise scoring, garbled detection | Genuinely good |
| Full-text | FTS5 × 3 tables (`documents`, `chunks`, `document_pages`), native `bm25()`, `fts5vocab` | Solid |
| SQLite | WAL, `busy_timeout=3000`, `columnsize=0` on chunks, integrity checks | Correct |
| Chunking | Semantic + structure-aware, token-limit enforcement, `contextualPrefix` | `contextualPrefix` is Anthropic-style contextual retrieval — already ahead |
| Retrieval | multi-query → hybrid dense+BM25 → RRF → cross-encoder rerank → MMR (λ=0.60) → parent expansion → Lost-in-the-Middle reorder | Textbook-correct ordering |
| Tokenizer | Rust-backed `swift-tokenizers`, byte-level offsets | Good |

**The parsing and retrieval layers are not the problem.** This is a more careful pipeline than most
shipped RAG apps.

### 1.1 The embedding providers, precisely

| Provider | Dim | Model | Note |
| --- | --- | --- | --- |
| `CoreMLSentenceEmbeddingProvider` | 384 | all-MiniLM-L6-v2 | The workhorse |
| `CoreAISentenceEmbeddingProvider` | 384 | **same weights** | ANE-native runtime, *not* a different model |
| `NLContextualEmbeddingProvider` | 512 | Apple contextual | Genuinely different; multilingual |
| `NLEmbeddingProvider` | — | static word vectors | Weakest |
| `AppleFMEmbeddingProvider` | — | Foundation Models | — |

**Correction worth recording:** Core AI was assumed to be a model upgrade. It is not. It loads the
same `EmbeddingModel` bundle at `dimension: Int = 384`. It buys ANE-native execution and battery,
not retrieval quality. Both primary paths share one 2021-era 6-layer model.

---

## 2. The ceiling

`all-MiniLM-L6-v2` is 23M parameters, 384 dimensions, released 2021.

Everything downstream — hybrid fusion, RRF, cross-encoder reranking, MMR, the agentic loop, the
spec sniper — inherits its first-stage recall. **Reranking cannot recover a document the first stage
never retrieved.** This is the single highest-leverage component in the system and it is the oldest.

### 2.1 Measured gap

| Model | Params | Dim | MTEB (Eng v2) | Size |
| --- | --- | --- | --- | --- |
| all-MiniLM-L6-v2 | 23M | 384 | ~56 (older MTEB) | 46 MB |
| nomic-embed-text | 137M | 768 (MRL) | 62.39 | 274 MB |
| **EmbeddingGemma-300M** | 308M | **768 → 512/256/128 (MRL)** | **69.67** | 295 MB |

EmbeddingGemma tops MTEB for models under 500M parameters, covers 100+ languages, and uses
Quantization-Aware Training to hold RAM under 200 MB.

### 2.2 Why this one is actionable rather than aspirational

`CoreML-LLM` (v1.2.0) ships an **EmbeddingGemma-300M Core ML conversion at 99.80% ANE utilization**,
295 MB, with Matryoshka 768/512/256/128 exposed. The conversion toolchain handles palettization,
blockwise quantization, and `.mlpackage` → `.mlmodelc` compilation.

That maps onto the existing architecture almost exactly: `CoreMLSentenceEmbeddingProvider` already
loads a compiled `.mlmodelc`, and `EmbeddingProvider` already abstracts `dimension`. Matryoshka
truncation to 256D would keep the vector store near its current footprint while still beating 384D
MiniLM on quality.

**Migration cost is the real work, not the integration.** `KnowledgeContainer.embeddingDim` is
persisted per library and `BNNSVectorDatabase` mmaps fixed-stride vectors, so changing dimension
requires a full re-embed of every library. A dimension-change path already exists conceptually
(`vectorDBKind`/`embeddingDim` mismatch triggers store invalidation in `VectorStoreRouter`), but a
user-visible "re-index required" flow would need designing.

---

## 2.3 The Apple-native constraint, resolved

The app's premise is Apple-native on-device execution, so the question is whether WWDC 2026 shipped a
first-party embedding model that removes the need for a third-party one.

**It did not.** The Foundation Models session confirms the "built-in semantic search" everyone
reported is a **Spotlight-backed Search tool**, not an embedding API:

> "we're also introducing a search tool powered by Spotlight for implementing fully local
> Retrieval-Augmented Generation. This has been one of your most requested features."

First-party text embeddings are **not** part of it. `NLContextualEmbedding` (512D) remains the only
Apple-authored text embedder available.

So the real choice is:

| Option | Apple-native? | Ceiling |
| --- | --- | --- |
| `NLContextualEmbedding` 512D | Apple-authored model | Apple's, unmeasured on this corpus |
| EmbeddingGemma via **Core AI** | Apple framework, Apple silicon, ANE, on-device | MTEB 69.67 |

**Core AI is the Apple-native answer, and it is explicitly designed for this case.** Apple's own
framing: Core AI is used "when the app needs a specialized model such as a domain classifier, **an
embedding model**, or a specialized vision model." It is the WWDC 26 successor to Core ML, targets
iOS 27, and is the same framework the app already uses.

**The purity question is already settled by the shipped app.** `all-MiniLM-L6-v2` is a
Microsoft/sentence-transformers model, not an Apple one. The app already ships third-party weights
through Apple's runtime. Swapping MiniLM for EmbeddingGemma changes the weights, not the framework,
not the privacy story, and not the on-device guarantee. Nothing leaves the device either way.

The genuinely Apple-native alternative worth benchmarking alongside it is `NLContextualEmbedding`,
which is already implemented as a provider and has never been measured against MiniLM on this corpus.

---

## 2.4 Shipping WWDC 2026 APIs this app has not adopted

Verified against the v4.9 tree. These are more clearly "not using the latest frameworks" than the
embedding model is.

| API | Status here | Evidence |
| --- | --- | --- |
| **Spotlight Search tool** (local RAG) | Not adopted | Roadmap To Do, High. `SpotlightIndexService` already indexes documents into Core Spotlight, so the index exists and only the tool binding is missing. |
| **`DynamicProfile` protocol** | Not adopted | `FoundationModelDynamicProfileRegistry.swift` exists with **zero call sites**. Apple now ships a declarative `body`-based API with per-branch `.model()` and `.reasoningLevel()`. |
| **`OCRTool`, `BarcodeReaderTool`** | Not adopted | Vision-backed system tools; the app has 8 custom tools in `FoundationModelToolRegistry` and none of these. |
| **`model.tokenCount(for:)`, `model.contextSize`** | Not adopted | The app estimates token budgets by character count (`supplementaryCharBudget`). Exact counting would have prevented the 4521-token-on-a-4096-budget overflow class directly. |
| **`response.usage`** (input/output/cached/reasoning counts) | Not adopted | Telemetry computes these by hand. |
| **`ContextOptions(reasoningLevel:)`** | Partial | `PCCReasoningLevel` is a local enum; Apple now exposes this on the session. |

`model.tokenCount` is the highest-value item on this list for correctness, because prompt-overflow
bugs in this codebase have been diagnosed from device logs more than once and the fix each time was
a hand-tuned character budget.

---

## 3. FTS5 issues, specific and cheap

```sql
CREATE VIRTUAL TABLE chunks USING fts5(
    ..., section_title, section_path, content,
    tokenize='porter unicode61', columnsize=0
)
```

**3.1 Porter stemming is English-only and lossy.** On the corpora this app targets — medical IFUs,
technical manuals, part numbers, model codes — Porter mangles exactly the identifiers the spec
sniper stage exists to catch.

**3.2 No `trigram` tokenizer.** No substring or typo tolerance. A second FTS5 table with
`tokenize='trigram'` over the same content, queried in parallel and fused through the existing RRF
stage, would cover codes and identifiers without disturbing prose retrieval.

**3.3 `bm25()` weights are uniform.** `section_title` and `section_path` are indexed alongside
`content` but weighted equally. Column weighting (`bm25(chunks, ...)` with title/path boosted) is
free recall and a one-line change.

**3.4 No `prefix=` index.** Prefix queries scan rather than seek.

---

## 4. Architectural directions worth evaluating

### 4.1 Visual document retrieval (highest ceiling, highest cost)

ColPali encodes each page as a grid of visual patch embeddings and scores with MaxSim late
interaction, **skipping OCR entirely**. It preserves tables, charts, diagrams, and layout — the
information OCR destroys. This directly addresses the hardest unsolved problem in this pipeline:
linearizing a table into text without losing its structure.

Two developments make this plausible on-device rather than theoretical:

- **ColModernVBERT** — 250M parameters, within 0.6 NDCG@5 of ColPali, 10× fewer parameters.
- **NanoVDR** — distills a 2B vision-language retriever into a **70M text-only encoder**. Critically,
  **no vision encoder is needed at query time**, which removes the latency objection for on-device
  querying. Indexing still requires the vision pass.

The multi-vector storage cost is real: ColPali produces ~1,024 patch vectors per page against one
vector per chunk today. `BNNSVectorDatabase` assumes single-vector-per-chunk and would need a
MaxSim path. Hierarchical patch compression and training-free pooling exist to reduce this.

### 4.2 Evidence-gated agentic RAG (validates current design)

**TechRAG** formalizes the pattern this app already implements: retrieve, assess whether evidence is
sufficient, reformulate and retry if not, stop when adequate or budget-exhausted. That is
`PostRetrievalEvidence.isSufficient` and the Deep Think session loop.

Its architectural recommendations, checked against the shipped tree:

| Recommendation | Status here |
| --- | --- |
| Hybrid dense + sparse | Implemented |
| Multi-stage reranking | Implemented (cross-encoder) |
| Iterative refinement on insufficient evidence | Implemented (session loop) |
| **Modality-aware indexing** — separate pipelines for text, tables, figures | **Partial.** Tables and figures are extracted but flattened into the same text index. |

4.4 is the actionable gap: tables and figures are parsed well and then indexed as if they were prose.

### 4.3 Late chunking

Embed the full document, then pool per-chunk, preserving cross-chunk context. A near-drop-in
alternative to chunk-then-embed and far cheaper to trial than 4.1. Complements `contextualPrefix`
rather than replacing it.

---

## 5. Recommended order

Reordered to put shipping Apple APIs before third-party models, per the app's Apple-native premise.

1. **`model.tokenCount(for:)` / `model.contextSize`.** Replace character-estimated budgets with exact
   counts. Directly addresses a recurring prompt-overflow bug class. Small, and it is a correctness
   fix rather than an optimization.
2. **Weight `bm25()` columns.** One line. Free recall.
3. **Add a trigram FTS5 table** for codes and identifiers, fused via existing RRF.
4. **Adopt the Spotlight Search tool.** `SpotlightIndexService` already populates the Core Spotlight
   index; this is the tool binding on top of it, and it is a first-party local-RAG path that costs
   no storage.
5. **Benchmark three embedders on `Benchmarks/rag_eval_v1.jsonl`:** MiniLM 384D (current),
   `NLContextualEmbedding` 512D (Apple-authored, already implemented, never measured), and
   EmbeddingGemma-300M @ 256D MRL via Core AI. Decide on numbers from this corpus, not MTEB.
6. **Adopt `DynamicProfile`** and retire or rewrite `FoundationModelDynamicProfileRegistry`, which
   currently has no call sites.
7. **Modality-aware indexing** — give tables and figures their own retrieval path instead of
   flattening them into prose.
8. **Evaluate late chunking.**
9. **Prototype NanoVDR or ColModernVBERT** for visual retrieval. v5.0 scope.

Items 1–4 are hours each and involve no storage migration. Item 5 is the one with a re-embed
migration attached and should be measured before committing — and note that option two is
Apple-authored and free to test, since the provider already exists.

---

## 6. Sources

- [EmbeddingGemma — Google Developers Blog](https://developers.googleblog.com/en/introducing-embeddinggemma/)
- [EmbeddingGemma 308M on-device model — MarkTechPost](https://www.marktechpost.com/2025/09/04/google-ai-releases-embeddinggemma-a-308m-parameter-on-device-embedding-model-with-state-of-the-art-mteb-results/)
- [Embedding Models 2026: Benchmark and Comparison — Ailog](https://app.ailog.fr/en/blog/news/embedding-models-2026)
- [Best Ollama Embedding Models 2026 — MorphLLM](https://www.morphllm.com/ollama-embedding-models)
- [CoreML-LLM (EmbeddingGemma-300M, 99.80% ANE)](https://github.com/john-rocky/CoreML-LLM)
- [Apple Launches Core AI — InfoQ, June 2026](https://www.infoq.com/news/2026/06/apple-core-ai-wwdc/)
- [ColPali — Hugging Face docs](https://huggingface.co/docs/transformers/en/model_doc/colpali)
- [NanoVDR: Distilling a 2B VLR into a 70M Text-Only Encoder — arXiv 2603.12824](https://arxiv.org/pdf/2603.12824)
- [TechRAG: Evidence-Gated Multimodal Agentic RAG — arXiv 2606.01613](https://arxiv.org/pdf/2606.01613)
- [Hierarchical Patch Compression for ColPali — arXiv 2506.21601](https://arxiv.org/pdf/2506.21601)
- [Visual RAG Toolkit: Training-Free Pooling and Multi-Stage Search — arXiv 2602.12510](https://arxiv.org/pdf/2602.12510)
- [Argus-Retriever — arXiv 2606.04300](https://arxiv.org/pdf/2606.04300)
- [Spatially-Grounded Document Retrieval — arXiv 2512.02660](https://arxiv.org/pdf/2512.02660)
- [Reproducibility and Insights into Visual Document Retrieval with Late Interaction — arXiv 2505.07730](https://arxiv.org/pdf/2505.07730)

`[evidence_level: code_verified for §1, web_research for §2-4, confidence: high_for_survey_unmeasured_for_recommendations, evidence_source: v4.9 tree survey + web research 2026-08-03]`

---

## Literature review, 2026-08-13

Prompted by a fair question: if the research already answers these questions, why measure anything?
The answer is that it answers some of them, and the parts it answers should be taken rather than
rediscovered. What follows is what current sources say, and specifically where it agrees or
disagrees with what this repository already does.

### 1. The fusion weighting this project just changed is what the literature recommends

The 2026-08-12 benchmark found RRF fusion scoring *worse* than the lexical arm alone
(`lexical` MRR@10 0.65 to `fusion` 0.51, 26 wins to 6 over 72 paired cases, sign test p=0.0005), and
reading `QueryProfile.adjustedHybridWeights` gave the mechanism: both arms are clamped to
`max(0.35, min(0.65, ...))`, so the dense arm is guaranteed 35% of the fusion however badly it
scores.

Current guidance says the same thing independently: **RRF benefits from per-retriever weight tuning,
with a suggested starting point of BM25 0.7 / dense 0.3 for lexical-heavy content.** That is exactly
the configuration now under test. This was arrived at from the measurement before the source was
read, which is the more reassuring order.

Also worth knowing and **not** currently implemented: **Convex Combination with α=0.5 has been
reported to outperform RRF** on some benchmarks. RRF discards score magnitude by design, using only
rank. When both retrievers are well calibrated, keeping the scores can beat throwing them away. This
is a candidate experiment after the weighting question is settled, not a replacement for it.

`[evidence_level: literature, confidence: medium, evidence_source: hybrid-search guidance surveys, 2026]`

### 2. There is now an Apache-2.0, 384-dimension embedder that is a drop-in replacement

**This removes the licensing blocker recorded in `Docs/ai/STATE.md`**, which noted that
EmbeddingGemma ships under the Gemma Terms of Use rather than Apache 2.0 and therefore could not be
adopted here.

| Model | Params | Dim | Max tokens | Licence | BEIR |
| :--- | ---: | ---: | ---: | :--- | ---: |
| `all-MiniLM-L6-v2` (shipped) | 22M | **384** | 256 | Apache 2.0 | not verified here |
| `granite-embedding-30m-english` | 30M | **384** | 512 | **Apache 2.0** | 49.1 |
| **`granite-embedding-small-english-r2`** | 47M | **384** | **8192** | **Apache 2.0** | **50.9** |

Three properties matter more than the score:

1. **384 dimensions, matching what ships.** `BNNSVectorDatabase.swift` format is a hard-boundary
   file, and a dimension change would require touching it plus a full re-index. A same-dimension
   swap avoids both.
2. **Apache 2.0**, so the concern that parked EmbeddingGemma does not apply.
3. **8192-token context against MiniLM's 256.** That is a 32x increase and it is the prerequisite
   for the "Late chunking: embed full document, pool per chunk" roadmap row, which cannot be done
   with a 256-token encoder.

**The risk is conversion, not quality.** `granite-embedding-small-english-r2` is a **ModernBERT**
architecture: alternating attention lengths, rotary position embeddings, Flash Attention 2.0. None
of that is guaranteed to convert cleanly to Core ML or to run on the ANE, and the shipped stack
depends on `CoreMLSentenceEmbeddingProvider`. The r1 `granite-embedding-30m-english` is a
conventional BERT encoder at the same 384 dimensions with a 512-token limit, so it is the safer
first attempt if r2 will not convert. **Neither has been converted or measured here.**

`[evidence_level: literature, confidence: high_for_specs_unverified_for_conversion, evidence_source: ibm-granite model cards on Hugging Face, read 2026-08-13]`

### 3. Late chunking is the right frame for the failure this benchmark actually found

The 2026-08-12 run showed the right document reaching the final ranking on **75% of missed cases**:
the correct paper arrives and the wrong passage is selected from it. That is precisely the problem
late chunking addresses, by embedding the full document first and pooling per chunk so each chunk
embedding carries document context instead of standing alone.

It requires a long-context encoder, which is the second reason the 8192-token Granite r2 matters and
the reason this cannot be attempted on MiniLM at all.

ColBERT-style late interaction scores higher again by comparing every query token against every
document token, but multiplies storage per chunk and is a poor fit for an on-device store.

`[evidence_level: literature, confidence: medium, evidence_source: late chunking and late interaction surveys, 2026; failure mode from BenchmarkRuns/qasper-overnight]`

### What to do with this

1. Finish the fusion-weight run. It is cheap, already running, and the literature agrees with the
   direction.
2. Then attempt Core ML conversion of `granite-embedding-small-english-r2`, falling back to
   `granite-embedding-30m-english` if ModernBERT will not convert. Additive-then-swap.
3. Late chunking only after a long-context encoder is actually running on device.
4. Convex Combination against RRF is a later experiment, once the arms are weighted sensibly.
