# v5.0 Embedding Arc — Working Ledger

> **Purpose:** durable state for the embedding, reranking, and measurement arc. A fresh session
> should be able to read this file and resume without re-deriving anything.
> **Status:** audit complete, implementation not started. Nothing below is implemented.
> **Research basis:** `Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md`,
> `Docs/Engineering/RETRIEVAL_UPGRADE_PLAN_2026-08.md`.
> **Live task list:** harness task IDs 1-11 (see summary table below).
> **Last audit:** 2026-08-07, against `84bcf15`.

---

## 0. Honest preamble

**No retrieval claim in this arc is measured on this corpus.** That is the entire reason the
harness comes first. Published leaderboard figures (MTEB, MS MARCO) are general-corpus numbers;
this corpus is manuals, policies, and spec sheets. They do not decide anything here.

Where a statement below is directional rather than measured, it says so.

---

## 1. What is actually running

| Component | Reality | Evidence |
| --- | --- | --- |
| Reranker | `cross-encoder/ms-marco-TinyBERT-L2-v2`, **2 layers**, 8.4 MB, loaded via Core ML `MLModel` | `THIRD_PARTY_NOTICES.md:10-15`, `RAGEngine.swift:61-84` `[evidence_level: code_verified, confidence: exact]` |
| Reranker asset age | Unchanged since `170121f` (v2.1.1) | `git log -- ReRankerModel.mlpackage` `[evidence_level: code_verified, confidence: exact]` |
| Default embedder | `coreml_sentence_embedding` = all-MiniLM-L6-v2, 23M params, 384d, 2021 | `KnowledgeContainer.swift:153` `[evidence_level: code_verified, confidence: exact]` |
| Core AI embedder | **Same MiniLM weights**, same 384d. ANE-native runtime, not a better model. Opt-in per container, not default. | `CoreAISentenceEmbeddingProvider.swift:21`, `EmbeddingService.swift:78-79`, research doc §1.1 `[evidence_level: code_verified, confidence: exact]` |
| Core AI asset | `EmbeddingModel.bundle`, 86 MB, `main.mlirb`, producer `coreai-core 1.0.0b2` | `metadata.json` `[evidence_level: code_verified, confidence: exact]` |

**The headline: 2021 weights through a 2027 runtime, and the 2027 runtime is off by default.**

### 1.1 The CoreAI name collision

Two unrelated things share the name. This has already caused confusion about whether Core AI was
integrated at all.

- **Real and working:** `Services/Embedding/Providers/CoreAISentenceEmbeddingProvider.swift`
  does `import CoreAI` and uses `AIModel` / `InferenceFunction`.
- **Dead:** `Services/AIPlatform/CoreAI/` holds three scaffolded-never-finished files with
  **zero callers repo-wide**. `CoreAIEmbeddingBackend.generateEmbedding` returns `[]`.
  `CoreAIExecutionBackend.execute` returns `[:]`. `CoreAIModelRegistry` is a dictionary whose
  `registerModel` is never called, containing a `case reranker` nothing implements. None of the
  three import Apple's framework. `[evidence_level: code_verified, confidence: exact]`

---

## 2. WWDC 2026 adoption, verified 2026-08-07

Verified twice: against the tree by grep, and against Apple's published documentation. The table
in `Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md` §2.4 is **stale** on two rows and
should be read through this one.

| API | Status | Evidence |
| --- | --- | --- |
| `model.tokenCount(for:)` | **Adopted** (research doc says otherwise and is wrong) | `FoundationModelTokenBudget.swift:99-104` |
| `ContextOptions(reasoningLevel:)` | **Adopted** | `LLMService.swift:701-708` |
| `response.usage` | Not adopted, zero hits | `input.totalTokenCount`, `input.cachedTokenCount`, `output.totalTokenCount`, `output.reasoningTokenCount` |
| `DynamicProfile` | Not adopted | `FoundationModelDynamicProfileRegistry.swift` exists, zero call sites |
| Spotlight search tool | Not adopted | `SpotlightIndexService` already indexes; only the tool binding is missing |
| `OCRTool`, `BarcodeReaderTool` | Not adopted | Vision-backed system tools |
| Agentic tools | 8 declared, **4 registered** | `FoundationModelToolRegistry.swift:421-446` |

**There is no first-party text embedding API and no reranking API.** Confirmed against Apple's
own session content, not inferred. The Spotlight tool is a search tool. This settles the
"Apple-native" question: third-party weights through Apple's runtime is the only path, and it is
already what ships. `[evidence_level: doc_verified, confidence: exact, evidence_source: https://developer.apple.com/videos/play/wwdc2026/241/]`

**Evaluations framework** (new in Xcode 27): `ModelJudgeEvaluator` for LLM-as-judge, `Evaluator`
closures for rule-based metrics, `Metric`, `ScoreDimension`, Swift Testing integration via the
`.evaluates` trait. `[evidence_level: doc_verified, confidence: exact, evidence_source: https://developer.apple.com/videos/play/wwdc2026/298/]`

**`apple/coreai-models`** — catalog enumerated 2026-08-07. **No pre-converted embedding model, no
cross-encoder, no reranker, no EmbeddingGemma.** It ships export *recipes*, not shipped models.
Registry presets are Qwen3, `gemma-3-*-it` (instruct LLMs, not EmbeddingGemma), T5, Mistral,
Mixtral, gpt-oss, CLIP, CLAP, Whisper, wav2vec2, SAM3, YOLOS, Depth Anything, Stable Diffusion,
FLUX.2, PVT, EDSR, EfficientSAM, RoBERTa.

The useful find is **`models/roberta/export.py`**: a working Apple-authored transformer-**encoder**
to `.aimodel` recipe using `coreai_torch.TorchConverter` with `transformers.AutoTokenizer`,
supporting `--dtype float16/bfloat16/float32` and `--dynamic` (batch 1-64, sequence to 512). That
is the conversion template for **both** a cross-encoder reranker and a replacement embedder, since
both are encoders. Pinned deps: `coreai-core==1.0.0b2`, `coreai-torch==0.4.1`,
`transformers==4.57.3`. Note that `coreai-core==1.0.0b2` exactly matches the producer string in
this app's existing `EmbeddingModel.bundle/metadata.json`, so the shipped Core AI asset came from
this same toolchain version. Prerequisite: `uv` is not installed on this machine.
`[evidence_level: code_verified, confidence: exact, evidence_source: shallow clone of apple/coreai-models, models/README.md, python/src/coreai_models/model_registry.py]`

---

## 3. Corrections to prior sessions

**`84bcf15` did not swap any model.** It touched five files: `CHANGELOG.md`,
`Docs/RELEASE_NOTES.md`, `Docs/USER_CHANGELOG.md`, `WHATS_NEW.md`, `SettingsView.swift`. It
restored the word "TinyBERT" to a Settings label. No model asset, no reranker code, no pipeline
code. TinyBERT was already what shipped and always had been. The label was accurate; the model is
dated. Two different problems, and only the first was addressed.

**The Notion Evaluations row was correctly corrected. An earlier draft of this ledger said
otherwise and was wrong.** Recorded because the wrong version was acted on.

The row is [RAG evaluation suite (XCTest, deterministic scoring)](https://app.notion.com/38049a74d54f81429589e271d7bf613d).
It is a **Completed v4.1** row (Added 2026-06-15, Completed 2026-06-29) describing the eval suite
that shipped, not a To Do migration row. Its old body claimed Swift Testing and a Model-as-Judge
pattern as *shipped capabilities*, and both were false about this repo. The 2026-08-06 correction
was legitimate, and it correctly traced the "Model Judges" Settings copy back to this row as its
origin.

The claim that it was wrongly corrected came from reading the previous handoff's summary of the
row rather than the row itself. That is precisely the failure
`.claude/skills/oi-claim-audit/SKILL.md` exists to prevent, committed three turns after the skill
was written. **Read the artifact, not the summary of the artifact.**

What was genuinely wrong is narrower: the corrected body says "there is no Apple 'Evaluations
framework' import either", which reads as though none exists to import. One does, new in Xcode 27,
postdating that row. Fixed 2026-08-07 with a dated addendum bounding that sentence; the row keeps
Completed and no property changed. The adoption work had no tracking at all, so it now has its own
row: [Adopt Apple's Evaluations framework for answer-quality grading](https://app.notion.com/p/3b549a74d54f814cbb06fa629417b657)
(To Do / Orchestration / High / v5.0).

---

## 4. Tracks and gates

| # | Work | Gate |
| --- | --- | --- |
| 2 | Per-stage retrieval metrics: recall@k, MRR, nDCG | none, start here |
| 3 | Apple Evaluations for answer quality | none, parallel with 2 |
| 4 | Enumerate `apple/coreai-models` | none, pure research |
| 5 | Reranker bake-off | **blocked by 2** |
| 6 | Three-way embedder bake-off | **blocked by 2** |
| 7 | Embedding migration | **blocked by 6** |
| 1, 8, 9, 11 | Notion restore, stub deletion, unadopted APIs, router version drift | none |
| 10 | Routing instrumentation + device check | **blocked on user authorization** |

### Why the harness is first

Reranking cannot recover a chunk the first stage never returned. First-stage recall is the ceiling
on every downstream feature. Without measurement, every model decision is a guess, and the last
cycle withdrew five multipliers for exactly that reason.

### Why the reranker is cheap and the embedder is not

Reranking scores (query, document) pairs at query time. **Nothing is persisted.** No
`embeddingDim`, no `BNNSVectorDatabase` stride, no re-embed. A reranker swap is a model asset plus
tokenizer behind an unchanged interface, and it is revertable.

The embedder is the opposite. `KnowledgeContainer.embeddingDim` is persisted per library and
`BNNSVectorDatabase` mmaps fixed-stride vectors. **Additive-then-swap, never
destructive-then-rebuild.** Most of the 4.9 cycle went to documents disappearing; this would
reintroduce that class of failure with a whole library as blast radius.

---

## 5. Governance notes for this arc

- `FoundationModelRoutePolicy.swift` is a **hard-boundary file**
  (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md:19`). It requires Gunnar naming the file in his
  approval. An unauthorized edit was made and reverted on 2026-08-07.
- `Services/AIPlatform/**` is approval-gated, which covers the CoreAI stub deletion (task #8).
- The RepoOS preflight reports `Active release: v0.5` while `CHANGELOG.md`'s first numbered
  heading is `4.9`. Anything writing release docs off the preflight would target a nonexistent
  version. Task #11.
- `.agents/rules/00-repoos-routing.md` requires an implementation plan and an explicit
  `PROCEED: IMPLEMENT` before the first source edit.
