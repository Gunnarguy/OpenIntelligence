# Retrieval & Ingestion Upgrade Plan — August 2026

> **Scope:** iOS and macOS. Every item below is shared source with no `#if os()` branching; the four
> services involved (`SpotlightIndexService`, `CoreAISentenceEmbeddingProvider`,
> `NLContextualEmbeddingProvider`, `SQLiteFullTextService`) contain **zero** platform conditionals
> today, and both deployment targets are 26.0.
> **Research basis:** `Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md`.
> **Status, 2026-09-29.** From 2026-08-05 this line read "plan only. Nothing here is implemented", which no longer holds. The Notion roadmap (the `notion-roadmap` skill) remains the authority on what is scheduled; this block records only what the code and history show, item by item:
> - **1A, partly.** Exact counting predates this plan: `FoundationModelTokenBudget.snapshot` counts with `model.tokenCount(for:)` behind `#available(iOS 26.4, macOS 26.4, *)` (`c6052df`, 2026-07-15), and `RAGService` builds the execution plan from it. `176e32c` (2026-08-06) made the planless route check read `SystemLanguageModel.default.contextSize` in place of a fixed 4096. Open: `AgenticOrchestrator.supplementaryCharBudget` still turns the window into characters with `onDeviceCharsPerToken`, and a grep of `OpenIntelligenceTests` for `contextSize` finds no test that the packer stays under it.
> - **1B, done** in `0e647c7` (2026-08-06): one weight per `chunks` column, `bm25(chunks, 0, 0, 0, 0, 0, 10.0, 5.0, 0, 1.0)`. Before it, the 4.9 code passed weights shifted one column left, not the equal weights 1B's problem statement below describes.
> - **1C, not started.** All three FTS5 tables still declare `tokenize='porter unicode61'`.
> - **1D, not started.** No Spotlight tool is registered in `FoundationModelToolRegistry.swift` or anywhere under `Services/AIPlatform` or `Services/Agentic`.
> - **2A, done for the metrics.** `RetrievalStageMetrics` (recall@1/3/5/10, MRR, nDCG@5/10, precision@5 per stage) landed in `cb82471` (2026-08-07), was wired into the query path and `RAGEvalRunner` in `493d577`, and was corrected in `6e5937e`, which also put a STAGE METRICS block in each harness report (both 2026-08-08). The per-stage figures in `BenchmarkRuns/LEDGER.md` come from it. Open: the part-number and table-lookup cases; neither committed fixture manifest has a category for them.
> - **2B, not run.** The ledger records no comparison with `NLContextualEmbedding` or EmbeddingGemma. `coreml-provider` (2026-08-17) compared two runtimes of the same MiniLM weights, not two embedders.
> - **3A, not started.** Part of its prerequisite landed in `3b48c88` (2026-08-18): a changed embedder is detected and the library flagged for rebuild rather than mixed. The resumable, additive-then-swap re-index flow was not checked.
> - **3B, resolved without Apple's protocol.** `f26dc5b` and `0da8528` (2026-09-11) turned `FoundationModelDynamicProfileRegistry` into generation parameters per answer intent, called from `RAGService` and off unless enabled in Model Parameters. It does not adopt Apple's `DynamicProfile`.
> - **3D and 4, not started.** `0e647c7` removed a "Late Chunking" label that described a different technique; `BNNSVectorDatabase.swift` has no multi-vector or MaxSim code. **3C was not checked.**
>
> `[evidence_level: code_verified+grep_verified, confidence: high, evidence_source: git show of c6052df, 176e32c, 0e647c7, cb82471, 493d577, 6e5937e, 3b48c88, f26dc5b, 0da8528; FoundationModelTokenBudget.swift:97-123; AgenticOrchestrator.swift:8366-8375; SQLiteFullTextService.swift:195, :252, :327, :1458; grep for Spotlight and DynamicProfile; category counts in Benchmarks/ResearchFixtures/*/manifest.json; grep of BenchmarkRuns/LEDGER.md for NLContextual and Gemma; checked 2026-09-29]`

---

## 0. Honest preamble

No item below is measured on this corpus yet. The plan is ordered so that **reversible,
non-migrating changes ship first**, and the one change requiring a full re-embed is gated behind a
benchmark rather than a benchmark citation.

Where a claim is directional rather than measured, it says so.

### Version gating, not platform gating

The real constraint is OS version, identical on both platforms:

| Dependency | Floor | Deployment target |
| --- | --- | --- |
| `model.tokenCount(for:)`, `contextSize` | 26.4 | 26.0 → needs `@available` |
| Core AI | 27.0 | 26.0 → needs `@available` |
| `DynamicProfile`, system tools | 27.0 | 26.0 → needs `@available` |
| FTS5 trigram, `bm25()` weights | none | ships everywhere |

Foundation Models items are additionally Apple-silicon-gated on Mac. That is already true of
everything the app does. **Phases 1B and 1C improve retrieval on every Mac regardless of chip or OS
version**, which is why they come first.

---

## Phase 1 — No migration, no storage change

Shippable in 4.9 or 4.10. Each item is independently revertable.

### 1A. Exact token counting

**Problem.** Prompt budgets are estimated from character counts (`supplementaryCharBudget`,
`synthesisOutputTokenReserve`). Device logs have shown 4521 tokens submitted against a 4096 window;
each fix so far has been a hand-tuned character constant. This is a correctness defect, not tuning.

**Change.** Behind `@available(iOS 26.4, macOS 26.4, *)`, replace estimation with
`model.tokenCount(for:)` and read the real window from `model.contextSize` instead of the hardcoded
4096 fallback. Keep the character estimate as the pre-26.4 path.

**Files.** `AgenticOrchestrator.swift` (budget computation), `RAGService.swift` (context packing),
wherever `4096` is currently literal.

**Verification.** A prompt that previously overflowed must now be trimmed to fit. Add a unit test
asserting the packer never returns a prompt exceeding `contextSize`.

**Risk.** Low. Falls back cleanly. **Confidence: very high** — this removes a class of bug rather
than tuning around it.

### 1B. Weight the BM25 columns

**Problem.** `chunks` indexes `section_title`, `section_path`, and `content`, and `bm25()` weights
all three equally. A query term matching a section heading is worth no more than one appearing in
body prose.

**Change.** Pass explicit column weights to `bm25()`. Heading and path columns weighted above body.

**Files.** `SQLiteFullTextService.swift` only.

**Verification.** Requires 2A to quantify. Directionally safe; ordering changes, recall set does not
shrink.

**Risk.** Very low, no schema change. **Confidence: high on direction, unmeasured on magnitude.**

### 1C. Trigram index for identifiers

**Problem.** `tokenize='porter unicode61'` is English-only and stems aggressively. On IFUs, part
numbers, model codes, and abbreviations — exactly what the spec-sniper stage hunts — Porter
destroys the token.

**Change.** Add a second FTS5 table over the same chunk content with `tokenize='trigram'`. Query it
in parallel and fuse through the **existing** RRF stage, so no new ranking logic. Prose retrieval is
untouched.

**Cost.** Roughly one extra index's worth of disk. Must be added to the same rebuild/migration path
as the existing tables, and to `deleted_documents` cleanup.

**Files.** `SQLiteFullTextService.swift`, plus the RRF fusion site in `RAGEngine.swift`.

**Verification.** 2A, with a query set containing part numbers.

**Risk.** Low-medium — new table needs migration and cleanup wiring. **Confidence: medium-high.**

### 1D. Spotlight search tool

**Problem.** WWDC 26 shipped a Spotlight-backed Search tool for fully local RAG. `SpotlightIndexService`
**already populates** the Core Spotlight index on both platforms; only the tool binding is missing.
Tracked as a High-priority roadmap To Do since 2026-06-15.

**Change.** Register the system Search tool in `FoundationModelToolRegistry` behind
`@available(iOS 27, macOS 27, *)`.

**Open question worth answering before shipping.** Whether it beats the app's own hybrid
dense+BM25+rerank path, or is better used as a *fallback* when in-library retrieval is insufficient.
It should not silently displace the measured pipeline.

**Risk.** Low, additive. **Confidence: medium** — clearly free, unclear if better.

---

## Phase 2 — Measurement (gates Phase 3)

### 2A. Retrieval benchmark harness

**Change.** Extend `Benchmarks/rag_eval_v1.jsonl` runs to report retrieval-stage metrics —
recall@k, MRR, nDCG — not just end-answer quality, so a retrieval change can be attributed. Add
query cases covering part numbers and table lookups, which the current set underrepresents.

**Why first.** Every Phase 1 item and all of Phase 3 is unfalsifiable without it. This is the
highest-value item in the document.

### 2B. Three-way embedder comparison

Run on this corpus, on device, not from MTEB:

| Candidate | Dim | Note |
| --- | --- | --- |
| all-MiniLM-L6-v2 | 384 | current baseline |
| `NLContextualEmbedding` | 512 | **Apple-authored, provider already exists, never measured** |
| EmbeddingGemma-300M via Core AI | 768→256 MRL | Core ML conversion exists at 99.8% ANE |

Report recall@k, index size, embed throughput, and memory.

**The Apple-native question is already settled either way:** the shipped app runs
`all-MiniLM-L6-v2`, a Microsoft/sentence-transformers model, through Apple's runtime. Core AI is
Apple's WWDC 26 framework and is explicitly intended for embedding models. No option here weakens
the on-device or privacy guarantee.

**If `NLContextualEmbedding` wins or ties, take it** — it is Apple-authored, already implemented,
and needs no new asset.

---

## Phase 3 — Conditional on Phase 2

### 3A. Embedding migration *(only if 2B shows a real win)*

`KnowledgeContainer.embeddingDim` is persisted per library and `BNNSVectorDatabase` mmaps
fixed-stride vectors, so a dimension change is a **full re-embed of every library**.

Required before shipping: a user-visible "re-index required" flow, resumable, that does not delete
the existing index until the new one is complete. Given this session's history of documents
disappearing, the migration must be additive-then-swap, never destructive-then-rebuild.

### 3B. `DynamicProfile` adoption

`FoundationModelDynamicProfileRegistry.swift` exists with **zero call sites**. Apple now ships a
declarative `body`-based protocol with per-branch `.model()` and `.reasoningLevel()`. Either adopt
it or delete the dead file; leaving an unused registry that looks implemented is worse than neither.

### 3C. Modality-aware indexing

Tables are extracted via `RecognizeDocumentsRequest` and figures via `ImageUnderstandingService` —
both well — and then **flattened into the same prose text index**. TechRAG names separate
text/table/figure retrieval paths as a core requirement; it is the one recommendation of theirs the
app does not already satisfy.

### 3D. Late chunking

Embed the full document, pool per-chunk. Complements `contextualPrefix`. Cheap to trial once 2A
exists.

---

## Phase 4 — v5.0

Visual document retrieval via NanoVDR (70M text-only encoder at query time) or ColModernVBERT
(250M, within 0.6 nDCG@5 of ColPali). This is the only approach that solves table indexing by not
linearizing tables at all. Requires multi-vector MaxSim support in `BNNSVectorDatabase`.

**Not tracked in Notion.** An earlier draft of this document claimed it was tracked alongside the
CKSyncEngine migration; a 2026-08-05 query of the roadmap database found the CKSyncEngine row
(`Move workspace metadata to CKSyncEngine or SwiftData + CloudKit`, v5.0) but no row for visual
retrieval. Neither is 3D (late chunking) tracked. Create both rows before treating either as planned
work. `[evidence_level: notion_verified, confidence: exact]`

---

## Sequencing summary

```
2A  benchmark harness        ← do this first, everything else is unfalsifiable without it
1A  exact token counting     ← correctness fix, independent
1B  bm25 weights             ← one line
1C  trigram index            ← needs migration wiring
1D  spotlight tool           ← additive, evaluate as fallback
2B  embedder comparison      ← gates 3A
3B  DynamicProfile           ← adopt or delete
3C  modality-aware indexing
3A  embedding migration      ← only with 2B evidence, additive-then-swap
3D  late chunking
4   visual retrieval         ← v5.0
```

`[evidence_level: code_verified for the survey, web_research for the API claims, unmeasured for every
performance claim, confidence: high_for_1A_directional_for_1B_1C_unmeasured_for_2B_3A,
evidence_source: v4.9 tree, WWDC26 sessions 241/324/326, research doc 2026-08-03]`
