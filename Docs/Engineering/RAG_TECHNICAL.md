> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30; dated notes below carry their own dates. Shipped and in-development versions are not restated here: `Docs/SHIPPED_VERSION.json` is the per-platform record. Corrected 2026-09-29; from 2026-06-30 this line and the Version line below said "working on v4.5".
>
> **Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress):** section 5's per-device table, sample code and phases are wrong for the current code and carry a correction under the section. HyDE and contextual compression (sections 1 and 3) run in no user-selectable mode, section 4's grounding method has no caller, the 2026-08-10 note that the extractive override "no longer runs" is reversed, and the performance table's agentic row is set against a device measurement. Section 10's levels, battery handling and cooldown are wrong for the current code and carry a correction at the end of the section. Each change sits at the place it corrects.

# RAG Technical Specifications

**Version**: see `Docs/SHIPPED_VERSION.json` (this line read "4.4 (working on v4.5)" until 2026-09-29)
**Updated**: June 30, 2026, for the whole document; dated notes below are later
**Compatibility**: iOS 26+ / Apple Intelligence

This document provides the technical formulas, algorithms, and deep dive specifications for the RAG pipeline.

> **For the High-Level Flow**: See [HOW_IT_WORKS.md](../HOW_IT_WORKS.md)

> **Full Architecture**: See [ARCHITECTURE.md](../ai/ARCHITECTURE.md) (repointed 2026-09-29; the v4.1 architecture document this linked is archived at `Docs/Archive/ARCHITECTURE_v4.1.md`). `OpenIntelligence/Services` held 155 tracked Swift files on 2026-09-29. This line said 107 from 2026-05-12, a figure no tracked tree matches: 115 at `6dc093c` that day, 146 at the 2026-06-30 verification (`d8217c8`). `[evidence_level: grep_verified, confidence: exact, evidence_source: git ls-files 'OpenIntelligence/Services/*.swift' | wc -l and find OpenIntelligence/Services -name '*.swift' both 155; git ls-tree -r at 6dc093c and d8217c8]`

> **Current State**: See CURRENT_STATE_AND_GAPS.md *(that document no longer exists in this repository; noted 2026-08-27)*. The Swift file count under `OpenIntelligence/Services` is on the Full Architecture line above (corrected 2026-09-29; this line said 107). The 31-step pipeline below is a logical/audit view; the implementation is adaptive and does not run every step for every query.

> **Research Links**: See [Docs/Research/RAG_AND_RETRIEVAL_2024_2026.md](../Research/RAG_AND_RETRIEVAL_2024_2026.md) and [Docs/Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md](../Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md).

---

## Pipeline Overview (31 Steps)

**How the 31 is counted** *(rule documented 2026-08-10; figures corrected 2026-08-12).* Ingestion
contributes 6. The query loop contributes **25: Steps 1 through 9 inclusive**, which is the
query-to-response transformation proper. `Step 0` and `Step 10` are enumerated below but are **not**
counted, because neither is part of that transformation: Step 0 loads a container vocabulary cache
before any query exists, and Step 10 renders an answer that is already final. The enumerated list
holds 30 entries while the counted figure is 25, and both are correct.

**Corrected 2026-08-12.** This note previously read "23" counted and "25" enumerated, against a
stated total of 29. Those were right when written and the enumeration has grown since; nobody
updated the prose. Re-counted directly against the list below: **30 enumerated, 25 counted, total
31.** The counting *rule* was never wrong, only its arithmetic.

This also retracts the retraction. The note below records a 2026-08-10 review that "concluded the
correct total was 31" and dismisses it as the third instance of a recurring miscount. **That review
was reading the current list correctly**; the figure it was compared against had drifted. Left in
place rather than deleted so the record shows what was claimed and when it was withdrawn.

Count it yourself. Bound the range to the enumeration block, because a bare file-wide grep matches
prose elsewhere in this document and reports 31 rather than 30, and that false positive is how a fourth
miscount nearly happened:

```bash
START=$(grep -n '^QUERY → RESPONSE' Docs/Engineering/RAG_TECHNICAL.md | cut -d: -f1)
END=$(awk -v s="$START" 'NR>s && /^```/{print NR; exit}' Docs/Engineering/RAG_TECHNICAL.md)
sed -n "${START},${END}p" Docs/Engineering/RAG_TECHNICAL.md \
  | grep -cE '^  Step [0-9]'                                         # -> 30 enumerated
sed -n "${START},${END}p" Docs/Engineering/RAG_TECHNICAL.md \
  | grep -oE '^  Step ([0-9.]+):' | grep -vE 'Step (0|10):' | wc -l  # -> 25 counted
```

`[evidence_level: code_verified, confidence: exact, evidence_source: direct count of the enumeration block in this file, bounded to lines 53-84]`

> **Superseded 2026-08-12, kept for the record.** The paragraph below was written on 2026-08-10 and
> its final sentence is now wrong. Read it as history, not as guidance.

This is recorded because the missing rule has now caused two independent miscounts. The
`RESEARCH_PAPERS_REFERENCE_SHEET.md` F-3 finding of 2026-07-31 concluded the figure was
unenumerated, and a 2026-08-10 review concluded the correct total was 31. Both compared the raw
enumeration against the stated figure, found 25 against 23, and inferred an error in the figure.
~~The figure was right both times.~~ **The 2026-08-10 review was right: the total is 31.** The F-3
finding of 2026-07-31 was still wrong on its own terms, because the figure *was* enumerated.
`[evidence_level: code_verified, confidence: exact, evidence_source: the enumerated list below, git history of this file showing label 23 and enumeration 25 co-existing unchanged since 4e24bbb 2026-05-12]`

```
INGESTION (6 steps):
  1. Parse (PDFKit/Vision OCR, adaptive 5x-6x render scale/Office ZIP)
  2. SemanticChunker (≤310w, section detection)
  3. Entity Extraction (NLTagger NER + PascalCase)
  4. Token Validation (BertTokenizer ≤510)
  5. Embedding (384-dim MiniLM)
  6. Store (per-container vector store + SQLite FTS5 + metadata)

QUERY → RESPONSE (25 specified; 28 present in code, 27 active — see note below):
  Step 0:   Corpus Analysis (vocabulary cache)
  Step 1:   Query Understanding (pronoun resolution, NER)
  Step 1.5: Query Expansion (corpus + container vocab)
  Step 1.5b:Per-Container Vocabulary Expansion                    [UNSPECIFIED]
  Step 1.5c:Gazetteer Domain Vocabulary Enrichment                [UNSPECIFIED]
  Step 1.6: Intent Classification (lookup/procedure/compare/summarize)
  Step 2:   Query Embedding (384-dim)
  Step 2.5: RAPTOR-lite Routing (overview → L1 summaries)
  Step 3:   Hybrid Search (Vector + BM25 + RRF) or Iterative Retrieval
  Step 3.5: Section Metadata Boost                                [UNSPECIFIED]
  Step 4:   Cross-Encoder Rerank (TinyBERT)
  Step 4.3: Low-Confidence Filtering
  Step 4.4: Multi-Document Representation (source diversity)
  Step 4.5: MMR Diversification (λ=0.6)
  Step 4.6: Parent Document Retrieval (±5 siblings)
  Step 4.6b:Cross-Reference Resolution                            [UNSPECIFIED]
  Step 4.8: Targeted Spec Retrieval ("Spec Table Sniper")         [UNSPECIFIED]
  Step 4.7: Contextual Compression (LLM filters)
  Step 4.9: Graph Context Packing (token budget)
  Step 5:   Context Assembly (Lost-in-Middle reorder)
  Step 5.9: Extractive Summarization (for summarize intent)
  Step 5.10: Extractive QA (for lookup intent)                    [DISABLED]
  Step 6:   LLM Generation (Apple FoundationModels public session budget)
  Step 6.5: Response Formatting (markdown preservation pipeline)
  Step 7:   Quality Assessment (confidence scoring)
  Step 7.5: Verification Gates A-I (anti-hallucination + completeness/domain isolation)
  Step 8:   Package Results
  Step 8.1: Calibrated Confidence (Platt scaling)
  Step 9:   Response Metadata (timing, sources, metrics)
  Step 10:  Markdown Rendering (block-level parser + inline normalization)
```

### `[UNSPECIFIED]` and `[DISABLED]` — recorded 2026-08-10

Five stages marked `[UNSPECIFIED]` above **run in the shipped app and had never appeared in any
document**. They were found by reading `// Step` markers out of `RAGService.swift` rather than by
reading a specification. One documented stage is commented out and does not run.

| Stage | Status | Detail |
|---|---|---|
| `1.5b` Per-Container Vocabulary Expansion | runs | Expands the query with terms learned from *this* library during ingestion, layered after corpus-wide expansion. |
| `1.5c` Gazetteer Domain Vocabulary Enrichment | runs | Adds prepared domain terms on top of `1.5` and `1.5b`. |
| `3.5` Section Metadata Boost | runs | Promotes chunks whose section metadata matches the query, applied to the fused set before reranking. **This is the stage `RetrievalStageEvaluator` reports as `boosted`** — the benchmark has been measuring a stage the specification did not contain. |
| `4.6b` Cross-Reference Resolution | runs | Resolves in-document references so a chunk that defers to another section pulls that section in. Shares the `4.6` number with Parent Document Retrieval in the source. |
| `4.8` Targeted Spec Retrieval ("Spec Table Sniper") | runs | Bypasses semantic similarity **and** reranker scoring entirely, searching all chunks for co-occurrence of discriminative query keywords with numeric/structured data. Exists because the cross-encoder carries a measured prose bias, ~0.78 for prose against ~0.30 for tables, which systematically demotes exactly the content that answers specification, dosage, statute-number and financial lookups. |
| `5.10` Extractive QA | **disabled** | Code path commented out; every query proceeds to LLM generation. Recorded reason in source: heuristic extraction produced false positives — returning `"three-quarters"` for a fuel-tank-capacity query — and bypassed the LLM entirely when it fired. Exact-value queries are now served by evidence steering at `4.8` rather than by a generation bypass. **Corrected 2026-09-26:** in the 5.4 source this holds for this step's own path only. The same extractor still answers through `RAGService.highPrecisionLookupOverrideAnswer`: Deep Think and Maximum return its span before the orchestrator runs, Standard swaps it in after generation, and the reliability fallback uses it. See `Docs/HOW_IT_WORKS.md` step 5.10. |

**What this does to the count, stated rather than quietly re-baselined.** The specification enumerates
25 (steps 1-9), corrected from 23 on 2026-08-12. The code carries **28** step labels across steps 1–9, of which **27 are active**.
`6 + 28 = 34` enumerated, `6 + 27 = 33` active. **The public "29-step" figure on FascinAIting.me and
in three documents is therefore an undercount of the shipped pipeline, not an overclaim.** Changing a
user-facing figure is an owner decision and none has been changed here; this note exists so the
decision is made with the real number in front of it.

**Updated 2026-08-12.** The specification count moved from 23 to 25, so this document's own total is
now **31**, not 29. That widens rather than closes the gap the paragraph above describes: the
shipped pipeline still carries 33 active steps. **The public figure has deliberately not been
touched.** These remain the owner's to choose between, and they answer different questions:

| Figure | Total | What it counts |
| :--- | ---: | :--- |
| `29` | 6 + 23 | the specification as written before 2026-08-12. **Now stale.** |
| **`31`** | 6 + 25 | the specification as enumerated in this document today |
| `33` | 6 + 27 | step labels that actually execute in `RAGService.swift` |
| `34` | 6 + 28 | every step label present, including the one that is disabled |

`29` is the only one of these that is no longer defensible, because the list it described has
changed. Anywhere the public figure is updated, `README.md`, `Docs/AppleIntelligenceTransitionPlan.md`
and the website all carry it and must move together.

`[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift `// Step` markers across the query path; 5.10 disabled block and its recorded reason at RAGService.swift:12022-12026; 4.8 prose-bias figures at RAGService.swift:2331-2337]`

---

## Quick Reference Table

| Technique                 | File                                 | Setting                         | Default | Impact                    |
| ------------------------- | ------------------------------------ | ------------------------------- | ------- | ------------------------- |
| HyDE                      | `HyDEService.swift`                  | `enableHyDE`                    | ON      | +15-25% recall            |
| Parent Document Retrieval | `ParentDocumentService.swift`        | `enableParentDocumentRetrieval` | ON      | Multi-paragraph coherence |
| Contextual Compression    | `ContextualCompressionService.swift` | `enableContextualCompression`   | ON      | -40-60% tokens            |
| Agentic Orchestration     | `AgenticOrchestrator.swift`          | `.agentic` quality mode         | Manual  | Multi-session reasoning, not one larger context |
| Lost-in-Middle            | `RAGEngine.swift`                    | Always on                       | ON      | Better LLM attention      |
| Cross-Encoder Rerank      | `RAGEngine.swift`                    | Always on                       | ON      | Improved ranking          |
| Query Rewriting           | `QueryRewriterService.swift`         | `enableQueryRewriting`          | ON      | Clarifies ambiguity       |
| Iterative Retrieval       | `IterativeRetrievalService.swift`    | `enableIterativeRetrieval`      | OFF     | Multi-pass refinement     |
| **Adaptive Pipeline**     | `AdaptivePipelineOptimizer.swift`    | Automatic                       | ON      | Thermal/battery aware     |

## Current Implementation Notes

- The active public LLM path must fit Apple's 4096-token FoundationModels session budget. Tool schemas, retrieved context, guided output schemas, prompts, and responses all count.
- `RAGService.swift` disables tools when context has already been assembled, because tool schemas can consume roughly 1000 tokens.
- **Corrected 2026-08-10.** This entry previously read: *"Exact-value/specification queries have a
  deterministic high-precision lookup override path. It can force an extractive attempt for
  precision-value questions and requires quantitative answer signals before overriding generation."*
  **That override no longer runs.** `highPrecisionLookupOverrideAnswer` is inside the commented-out
  Step 5.10 block, so nothing forces an extractive attempt and no query bypasses generation. What
  remains is real but different in kind, and the distinction matters: `GroundedAnswerPolicy`
  still computes `deterministicExtraction` from intent and query signals (2026-10-20: nothing called it, and
  `GroundedAnswerPolicy.swift` was removed in 5.7), and `ModelExecutionPlanner`
  still routes to a `.deterministic` target when evidence `requiresExactExtraction` and carries no
  contradictions — but `.deterministic` is grouped with `.onDevice` at every execution branch, so it
  selects a **local route**, not a generation bypass. Exact-value precision is now pursued at
  retrieval time by Step 4.8 steering evidence toward specification tables, with the model still
  writing the answer, so a bad extraction becomes a bad *candidate* the verification gates can catch
  rather than an answer that skipped them. Both `exact_value` failures in the current benchmark
  (`exact_service_interval`, `exact_temperature_limit`) sit in this area.
  `[evidence_level: code_verified, confidence: exact, evidence_source: RAGService.swift:12022-12040 commented block, GroundedAnswerPolicy.swift:38-66, ModelExecutionPlanner.swift:69-72, RAGService.swift:12412 and FoundationModelRoutePolicy.swift:36 both grouping .deterministic with .onDevice]`
- `VerificationGateService.swift` now defines gates A-I, not only A-G.
- The vector store is not only HNSW. The current BNNS/Accelerate implementation persists memory-mapped vectors and uses Metal for larger searches when available; Vectura/HNSW is a selectable backend path.
- Full GraphRAG is not a shipped claim. The app has graph-style context packing, deterministic entities, and RAPTOR-lite summaries, but not evaluated LLM-derived entity graph/community summaries.
- **Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress):**
  - The first bullet's "4096-token FoundationModels session budget" is the fallback. The window is read from `SystemLanguageModel.default.contextSize` (4,096 on the owner's iPhone 16 Pro Max, 8,192 on his Mac), and when Hybrid can reach Private Cloud Compute, Standard sizes its first pass for 32,768 tokens.
  - The 2026-08-10 bullet above, "That override no longer runs", is wrong for the current code, as the Step 5.10 row's 2026-09-26 note already says. `highPrecisionLookupOverrideAnswer` runs outside the commented-out block: Deep Think and Maximum return a locked value before the orchestrator runs, a locked value replaces an agentic answer afterwards, and Standard swaps it in after generation (from 5.7 only when the model's answer does not already state the value).
  - "Vectura/HNSW is a selectable backend path" is not true of any build: `VecturaVectorDatabase` is behind `#if canImport(VecturaKit)`, VecturaKit is not a dependency, and a library configured for it falls back to the BNNS store.
  - The quick reference table's HyDE and contextual compression rows say ON. Their settings default to true, but neither runs in any user-selectable mode. Each needs a mode flag that is off in Standard, and Deep Think and Maximum leave for the agentic path before either step.
  - "Deterministic entities" are attached to chunks, but the entity index is never filled, so nothing expands through it.
  `[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelTokenBudget.swift:25-40, OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:14532-14543, :10561-10737, :11191-11198, :16501-16528, :12278-12325, :14320-14326 and :14406, :21863-21866, OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift:167-172, OpenIntelligence/Core/Models/RAGQualityMode.swift:189-195 and :277-284, OpenIntelligence/Services/Document/Analysis/EntityIndexService.swift:31 and :137]`

---

## 1. HyDE (Hypothetical Document Embeddings)

### What It Does

Generates a hypothetical answer to the query BEFORE embedding, then embeds that hypothetical document for retrieval instead of the raw question.

### Why It Matters

Questions and answers often don't share vocabulary:

- Query: "What oil does my car take?"
- Answer: "SAE 0W-20 synthetic oil, 5.3 quarts capacity"

By generating a hypothetical answer first, the system bridges this vocabulary gap.

### Flow

```
User Query → LLM generates hypothetical answer → Embed hypothetical → Search
```

### Code Location

```swift
// OpenIntelligence/Services/HyDEService.swift

let hydeService = HyDEService()
let result = try await hydeService.generateHyDEQuery(for: "What oil does my car take?")
// result.hypotheticalDocument = "The vehicle uses SAE 0W-20 synthetic..."
// result.combinedForEmbedding = hypothetical doc text
```

### Configuration

```swift
// SettingsStore.swift
@Published var enableHyDE: Bool  // Default: true

// HyDEService.swift - Detection heuristic
static func shouldUseHyDE(for query: String) -> Bool
// Returns true for factual queries (what, which, how much, etc.)
```

### Performance

- Latency: +200-400ms (LLM generation)
- Recall improvement: 15-25% on factual/technical queries
- Best for: Manuals, spec sheets, technical documentation

> **Corrected 2026-10-20:** in the working tree HyDE runs in no user-selectable mode. Its only
> construction is in Standard's pipeline, behind a mode flag that is false for Standard, and Deep
> Think and Maximum embed without it ("HyDE disabled in Deep Think"). The recall figure above has no
> benchmark artifact cited for this app. `[evidence_level: code_verified, confidence: exact,
> evidence_source: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:12278-12325 and
> :21863-21866, OpenIntelligence/Core/Models/RAGQualityMode.swift:189-195]`

---

## 2. Parent Document Retrieval

### What It Does

When a chunk matches a query, expands the result to include surrounding sibling chunks from the same section or page, providing coherent multi-paragraph context.

### Why It Matters

RAG typically retrieves individual chunks (200-400 words). But answers often span multiple chunks:

- The matched chunk might be mid-sentence
- Context from previous/next chunks improves coherence
- Multi-paragraph answers read more naturally

### Flow

```
Retrieved Chunks → Find siblings (same page/section) → Expand context → Compress (optional)
```

### Code Location

```swift
// OpenIntelligence/Services/ParentDocumentService.swift

let service = ParentDocumentService(config: .default)
let result = await service.expandWithSiblings(
    retrievedChunks: rerankedChunks,
    allChunks: allChunks,
    query: "What are the maintenance requirements?"
)
// result.expandedChunks includes siblings
// result.addedSiblings = count of new chunks added
```

### Configuration

```swift
// SettingsStore.swift
@Published var enableParentDocumentRetrieval: Bool  // Default: true

// ParentDocumentService.swift configs
Config.default   // 2 siblings per side, 2000 token limit
Config.thorough  // 3 siblings per side, 3000 tokens, cross-page OK
```

### Sibling Grouping

Chunks are grouped as siblings based on:

1. **Explicit `siblingGroupId`** - Set during ingestion
2. **Same page number** - PDF documents
3. **Same section title** - Markdown/structured docs
4. **Adjacent chunk indices** - Fallback for unstructured text

### Performance

- Token expansion: +20-50% (offset by contextual compression)
- Latency: <10ms (in-memory lookup)
- Best for: Multi-paragraph technical explanations

---

## 3. Contextual Compression

### What It Does

Extracts only query-relevant sentences from each retrieved chunk, discarding irrelevant content.

### Why It Matters

A 400-word chunk might only have 2 relevant sentences. Sending all 400 words:

- Wastes precious tokens (4K limit)
- Dilutes LLM attention
- May introduce confusion

### Flow

```
Retrieved Chunks → LLM filters each → Keep only relevant sentences → Assemble context
```

### Code Location

```swift
// OpenIntelligence/Services/ContextualCompressionService.swift

let service = ContextualCompressionService()
let results = try await service.compressChunks(chunks, forQuery: query)
// Each result contains: originalTokens, compressedTokens, compressionRatio
```

### Configuration

```swift
// SettingsStore.swift
@Published var enableContextualCompression: Bool  // Default: true

// Compression configs
Config.default      // 40% retention (aggressive)
Config.conservative // 60% retention (safer)
```

### Performance

- Token savings: 40-60% average
- Latency: +100-200ms per chunk
- Drops entirely irrelevant chunks automatically

> **Corrected 2026-10-20:** in the working tree contextual compression runs in no user-selectable
> mode. Its only call is in Standard's pipeline, behind a mode flag that is off for Standard and
> Maximum and on only for Deep Think, which never reaches that step. `[evidence_level: code_verified,
> confidence: exact, evidence_source: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:14320-14326
> and :14406, OpenIntelligence/Core/Models/RAGQualityMode.swift:277-284]`

---

## 4. Answer Grounding Verification

### What It Does

After generating an answer, verifies that claims are supported by retrieved context. Detects hallucinations.

### Status Levels

```swift
enum GroundingStatus {
    case grounded          // ✅ Answer fully supported
    case partiallyGrounded // ⚠️ Some claims unsupported
    case ungrounded        // ❌ Significant hallucination
    case notAnswerable     // 📭 Context insufficient
    case unverified        // 🔄 Couldn't verify
}
```

### Code Location

```swift
// OpenIntelligence/Services/ContextualCompressionService.swift

let verification = try await service.verifyAnswerGrounding(
    answer: generatedAnswer,
    context: retrievedChunks,
    query: userQuery
)
// verification.status, verification.confidence, verification.explanation
```

### Use Cases

- Display confidence indicators in UI
- Trigger re-retrieval on low confidence
- Flag potentially hallucinated responses

> **Corrected 2026-10-20:** `verifyAnswerGrounding` is defined and nothing calls it, so these uses do
> not happen through it. The checks that run are the nine gates of `VerificationGateService`, once,
> after generation. They label the answer, and Standard abstains only when reliability mode is off or
> their overall confidence is under the bar. No gate triggers re-retrieval. `[evidence_level:
> code_verified, confidence: exact, evidence_source:
> OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift:452 (no caller),
> OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:16623-16709]`

---

## 5. Multi-Session Agentic Orchestration

### What It Does

Chains multiple 4K-token sessions together to handle complex queries requiring extensive reasoning.

### Pipeline Steps

```
1. PLANNING    → Break query into sub-questions
2. SEARCHING   → Use RAG tools to retrieve relevant chunks
3. ANALYZING   → Extract key facts from context
4. SYNTHESIZING → Compose coherent answer
5. REFINING    → Polish and verify response
```

### Hardware-Aware Configuration

| Device            | Chip    | Max Steps | Max Tokens |
| ----------------- | ------- | --------- | ---------- |
| iPhone 15 Pro     | A17 Pro | 4         | 16,000     |
| iPhone 16         | A18     | 6         | 24,000     |
| iPhone 17         | A19     | 8         | 32,000     |
| iPad Pro M-series | M1-M4   | 10        | 48,000     |

### Code Location

```swift
// OpenIntelligence/Services/AgenticOrchestrator.swift

let config = AgenticConfig(
    maxSteps: 6,
    maxTotalTokens: 24000,
    tokensPerSession: 4000
)
let orchestrator = AgenticOrchestrator(config: config)
let response = try await orchestrator.process(query: userQuery, ragService: ragService)
```

### Device Detection

```swift
// OpenIntelligence/Services/DeviceCapabilityService.swift

let tier = DeviceCapabilityService.currentTier
let config = DeviceCapabilityService.optimizedAgenticConfig()
```

### Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress)

This section described the v4.4 loop, and four things in it are wrong for the current code. The
table, the sample and the phases above are kept as they were written.

- **The per-device table.** `DeviceCapabilityService.optimizedAgenticConfig()` gives the A17 Pro 5
  steps and 20,000 tokens (confidence 0.85, escalation 0.35), the A18 and A18 Pro 8 steps and 32,000
  tokens (0.90, 0.40), the A19 10 and 40,000 (0.92, 0.45), and the ultra tier 12 steps and 56,000
  tokens for each 16 GB of memory, never fewer than 12 and 56,000 and at most 32 and 128,000 (0.95,
  0.50). The ultra tier is a Mac with an M1 Ultra or an M2 or later, an iPad Pro with an M2 or later
  and an iPhone with an A20 or later, by model identifier. M1, M1 Pro and M1 Max Macs, the M1 iPads
  and the M2 iPad Air get the A18's numbers, and the M3 iPad Air the A19's. The table's "A18 6
  and 24,000" matches nothing that drives the loop. A second table on the same service,
  `maxConcurrentAgenticSteps` and `maxAgenticTokenBudget`, gives the A18 5 steps and 24,000 tokens,
  and it is only printed in a diagnostic summary.
- **What the numbers do.** The step count only picks the chain's starting length (8 or more steps
  `.deep`, 5 or more `.standard`, else `.light`) and caps the decomposed pipeline at the steps less
  2. Deep Think's chain stops at 8 sessions on every device, and earlier when the pool runs out of
  distinct windows. The token figure is checked only by the decomposed pipeline and the research
  rounds, never inside the chain or Maximum's own loop. Maximum ignores this table and uses
  `AgenticConfig.unlimited` (50 steps, 200,000 tokens, 0.98).
- **The sample code.** `AgenticConfig` has no `tokensPerSession`. Its fields are `maxSteps`,
  `maxTotalTokens`, `streamIntermediateResults`, `confidenceThreshold` and `escalationThreshold`. The
  orchestrator is `Services/Agentic/AgenticOrchestrator.swift`, and its entry point is
  `execute(query:initialContext:onStep:)`, not `process(query:ragService:)`.
- **The phases and the sessions.** No Deep Think or Maximum step uses a tool: every session and
  synthesis passes `disableTools: true`. Retrieval runs before the sessions, as up to 5 search
  phrasings each sent through the full pipeline and fused into 20 passages, and each session reads
  the next window cut from that pool, so "SEARCHING" happens once, before the sessions, and again
  only in the research rounds after Deep Think's chain. Where the OS can count tokens, Deep Think's
  chain sizes its windows from the window the device reports (4,096 on the owner's iPhone, 8,192 on his
  Mac), not a fixed 4K, and it falls back to sentences extracted to 3,500 characters (3,000 when
  Maximum runs the chain). Maximum's own loop reads a fixed 2,500 characters a session. A precision
  lookup can return an extracted value before any of this runs.

`Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`, section 19, has the loop with its file and line
citations. `[evidence_level: code_verified, confidence: exact, evidence_source:
OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift:1044-1091, :1096-1488
(the tier tables), :605-628 and :1714-1715, OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift:95-150,
:212-226, :272, :1749-1751, :2942, :4931-4936, :5003-5126, :5313, :6833,
OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift:304,
OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:10561-10737 and :10863-10871]`

---

## 6. Query Task Management

### What It Does

Handles back-to-back queries without memory leaks or freezing using cancel-and-replace pattern.

### Problem Solved

```
User sends Query A → Processing starts
User sends Query B → Query A continues in background → Memory accumulates
```

### Solution

```swift
// OpenIntelligence/Views/ChatV2/ChatScreen.swift

@State private var currentQueryTask: Task<Void, Never>?

func sendMessage() async {
    // Cancel any in-flight query
    currentQueryTask?.cancel()

    currentQueryTask = Task {
        defer { currentQueryTask = nil }

        // Cancellation checkpoints throughout pipeline
        try Task.checkCancellation()  // After embedding
        try Task.checkCancellation()  // After search
        try Task.checkCancellation()  // After rerank
        try Task.checkCancellation()  // After context assembly
        try Task.checkCancellation()  // During streaming
    }
}
```

### Cancellation Points (6 total)

1. After query submission
2. After embedding generation
3. After hybrid search
4. After reranking
5. After context assembly
6. During LLM streaming

---

## 7. Lost-in-Middle Mitigation

### What It Does

Reorders context chunks so the most relevant are at the START and END of the context window.

### Why It Matters

LLMs have attention patterns that favor the beginning and end of context (Liu et al. 2023). Middle content gets less attention.

### Algorithm

```
Input:  [1st, 2nd, 3rd, 4th, 5th, 6th]  (by relevance)
Output: [1st, 3rd, 5th, 6th, 4th, 2nd]  (interleaved)
```

### Code Location

```swift
// OpenIntelligence/Services/RAGEngine.swift

func applyLostInMiddleReordering(_ chunks: [DocumentChunk]) -> [DocumentChunk]
```

### Always Enabled

This optimization has no downside and is always applied.

---

## 8. Cross-Encoder Reranking

### What It Does

Uses a neural model to score query-chunk relevance pairs, improving on initial vector similarity scores.

### Flow

```
Hybrid Search (Vector + BM25) → RRF Fusion → Cross-Encoder Rerank → Final ranking
```

### Model

- `ReRankerModel.mlpackage` (bundled Core ML model)
- Based on TinyBERT/ms-marco architecture
- Falls back to heuristic scoring if model unavailable

### Code Location

```swift
// OpenIntelligence/Services/RAGEngine.swift

let reranked = await engine.rerankWithCrossEncoder(
    query: query,
    chunks: candidates,
    topK: 10
)
```

---

## Apple API References

| API                      | Framework        | iOS Version | Purpose               |
| ------------------------ | ---------------- | ----------- | --------------------- |
| `LanguageModelSession`   | FoundationModels | 26+         | LLM generation        |
| `Tool` protocol          | FoundationModels | 26+         | Agentic tool calling  |
| `@Generable` macro       | FoundationModels | 26+         | Structured output     |
| `Transcript`             | FoundationModels | 26+         | Session persistence   |
| `prewarm(promptPrefix:)` | FoundationModels | 26+         | Latency optimization  |
| `NLEmbedding`            | NaturalLanguage  | 13+         | Word/sentence vectors |
| `NLContextualEmbedding`  | NaturalLanguage  | 17+         | BERT-like embeddings  |

### Key Documentation Links

- [TN3193: Context Window Management](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- [Tool Protocol](https://developer.apple.com/documentation/foundationmodels/tool)
- [Expanding Generation with Tool Calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling)

---

## Settings Quick Reference

All advanced RAG settings in `SettingsStore.swift`:

```swift
// Query Understanding
@Published var enableQueryRewriting: Bool        // Default: true
@Published var enableIterativeRetrieval: Bool    // Default: false

// Advanced Retrieval (Jan 2026)
@Published var enableHyDE: Bool                  // Default: true
@Published var enableContextualCompression: Bool // Default: true

// Quality Mode
@Published var ragQualityMode: RAGQualityMode    // .standard, .deepThink, .maximum
```

---

## Performance Impact Summary

| Technique              | Latency Cost     | Token Impact   | Quality Impact    |
| ---------------------- | ---------------- | -------------- | ----------------- |
| HyDE                   | +200-400ms       | Neutral        | +15-25% recall    |
| Contextual Compression | +100-200ms/chunk | -40-60%        | Improved focus    |
| Agentic Orchestration  | +2-10s           | +12K-44K total | Complex reasoning |
| Lost-in-Middle         | ~0ms             | Neutral        | Better attention  |
| Cross-Encoder Rerank   | +50-100ms        | Neutral        | Better ranking    |
| Query Rewriting        | +100-200ms       | Neutral        | Clearer intent    |

> **Corrected 2026-10-20:** two rows here describe nothing that runs, and one row is far from what was
> measured. HyDE and contextual compression run in no user-selectable mode in the working tree (see
> sections 1 and 3). The agentic row's "+2-10s" has no measurement behind it, and the one device A/B in
> `Docs/AUDIT/QUALITY_MODE_VERIFICATION_2026-07-30.md` took 99.4 seconds and 3,342 tokens for one Deep
> Think question on an iPhone (A18 Pro), eight sessions, on 2026-07-30. In the troubleshooting table
> below, "Enable grounding verification" names a method nothing calls (section 4), and Query
> Rewriting costs a model call only for a question the ambiguity check flags. `[evidence_level:
> code_verified for the modes and the method, device_verified for the 99.4 s (that document's own tag),
> confidence: high, evidence_source: OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:12278-12325,
> :14320-14326, :11982-11983, OpenIntelligence/Services/Query/Rewriting/QueryRewriterService.swift:83-100,
> OpenIntelligence/Services/Query/Enhancement/ContextualCompressionService.swift:452, Docs/AUDIT/QUALITY_MODE_VERIFICATION_2026-07-30.md lines 25-33]`

---

## Troubleshooting

| Issue               | Cause                         | Solution                           |
| ------------------- | ----------------------------- | ---------------------------------- |
| HyDE not triggering | Query not detected as factual | Check `shouldUseHyDE()` heuristics |
| High latency        | All features enabled          | Disable compression for speed      |
| Memory growth       | Query tasks not cancelled     | Check `currentQueryTask` pattern   |
| Poor retrieval      | Wrong quality mode            | Try `.deepThink` or `.maximum`     |
| Hallucinations      | Ungrounded responses          | Enable grounding verification      |

---

## File Map

```
OpenIntelligence/Services/
├── Query/
│   ├── Rewriting/
│   │   ├── HyDEService.swift              # Hypothetical Document Embeddings
│   │   └── QueryRewriterService.swift     # Query clarification / rewriting
│   └── Intent/
│       └── QueryEnhancementService.swift  # Semantic classification & intent analysis
├── RAG/
│   ├── Orchestration/
│   │   ├── RAGEngine.swift                # Reranking, MMR, and positional salience (Lost-in-Middle) packing
│   │   └── RAGService.swift               # Main RAG execution orchestrator
│   ├── Retrieval/
│   │   ├── ParentDocumentService.swift    # Parent/sibling context expansion
│   │   └── IterativeRetrievalService.swift # Multi-pass retrieval loops
│   ├── Compression/
│   │   └── ContextualCompressionService.swift # Chunk-level prompt token compression
│   └── Safety/
│       └── VerificationGateService.swift  # Anti-hallucination verification checks (Gates A-I)
├── Agentic/
│   └── AgenticOrchestrator.swift          # Closed-loop agentic multi-session reasoning
├── Storage/
│   ├── SQLiteFullTextService.swift        # Relational metadata + FTS5 search index
│   └── SettingsStore.swift                # Persistence of user options & feature gates
└── Infrastructure/
    ├── Configuration/
    │   └── DeviceCapabilityService.swift  # Apple Silicon hardware tier / form factor detection
    └── Optimization/
        └── AdaptivePipelineOptimizer.swift # Real-time thermal and battery throttling mitigation

OpenIntelligence/Features/ChatV2/
└── ChatScreen.swift                       # Query task management & UI entry point
```

---

## 10. Adaptive Pipeline Optimization

### What It Does

Monitors device state (thermal, battery, memory) in real-time and dynamically adjusts which RAG features are enabled for each query. Prevents thermal throttling on sustained use and extends battery life.

### Why It Matters

Full RAG pipeline (HyDE + Compression + Parent Doc + 25 chunks) is computationally expensive:

- Can cause thermal throttling on iPhone after 5-10 queries
- Drains battery rapidly during research sessions
- May trigger memory warnings on older devices

The adaptive optimizer provides automatic graceful degradation.

### Optimization Levels

| Level        | Thermal State | Features Disabled | TopK Cap |
| ------------ | ------------- | ----------------- | -------- |
| `.full`      | Nominal       | None              | 50       |
| `.balanced`  | Fair          | Parent Doc        | 30       |
| `.efficient` | Serious       | HyDE, Compression | 20       |
| `.minimal`   | Critical      | All advanced      | 10       |

### Device State Monitoring

```swift
// OpenIntelligence/Services/AdaptivePipelineOptimizer.swift

struct DeviceRuntimeState {
    let thermalState: ProcessInfo.ThermalState
    let batteryLevel: Float        // 0.0-1.0
    let batteryState: UIDevice.BatteryState
    let availableMemoryGB: Double  // via os_proc_available_memory()
    let memoryPressure: MemoryPressure
}
```

### Integration Points

The optimizer is automatically consulted at query start:

```swift
// In RAGService.queryInternal()

let queryComplexity = QueryComplexity.estimate(from: question)
let adaptiveConfig = AdaptivePipelineOptimizer.shared.configForQuery(complexity: queryComplexity)

// Features respect both user settings AND adaptive config
let useHyDE = useHyDESetting && adaptiveConfig.enableHyDE
let useContextualCompression = useCompressionSetting && adaptiveConfig.enableContextualCompression
let useParentDocRetrieval = useParentDocSetting && adaptiveConfig.enableParentDocRetrieval
```

### Query Complexity Estimation

Simple queries skip expensive features even when device is cool:

```swift
enum QueryComplexity: Int {
    case simple = 0     // "What is X?" - skip HyDE
    case standard = 1   // Normal questions
    case complex = 2    // Multi-part, OR operators
    case research = 3   // Long queries needing full pipeline
}
```

### Thermal Cooldown

Before heavy LLM generation, a cooldown may be applied:

```swift
await AdaptivePipelineOptimizer.shared.applyCooldown()
// Returns immediately if thermal is .nominal
// Waits 0.1-2.0s based on thermal severity
```

### Form Factor Detection

iPad models receive special treatment:

| Form Factor | Thermal Headroom | Default Level   |
| ----------- | ---------------- | --------------- |
| iPhone      | Standard         | Based on state  |
| iPad mini   | Limited          | Balanced        |
| iPad Air    | Good             | Full            |
| iPad Pro    | Excellent        | Full (extended) |

### Configuration

```swift
// Check current optimization level
let level = AdaptivePipelineOptimizer.shared.currentOptimizationLevel

// Override for testing (persists until cleared)
AdaptivePipelineOptimizer.shared.setUserOverride(.full)
AdaptivePipelineOptimizer.shared.clearUserOverride()
```

### Best Practices

1. **Don't disable manually** - Let the optimizer handle it automatically
2. **Check telemetry** - `[Adaptive] Pipeline adjusted to efficient mode` in logs
3. **iPad Pro users** - Get the full experience with minimal throttling
4. **Older iPhones** - Will automatically scale back on sustained use

### Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress)

This section describes an earlier optimizer, and five things in it are wrong for the current code. The
text above is kept as it was written.

- **What lowers the level.** Only two states do. A critical thermal state selects minimal (shown as
  Emergency), and critical memory pressure selects efficient (shown as Power Saver). Serious thermal no
  longer throttles, the battery level no longer degrades anything (the code says "Battery level no
  longer triggers degradation"), and nothing but a manual override selects balanced. Low Power Mode is
  read only to keep background work off the GPU and for display.
- **What each level changes.** The candidate cap starts from the device tier, 75 on an A17 Pro, 100 on
  an A18, 150 on an A19 and 250 on the ultra tier. It is halved at efficient and is 10 at minimal, and a
  trivial question is held to 10 and a complex one to 50. `RAGService` reads the adaptive configuration
  in four places, all on Standard's path: the configuration recorded for the query, the candidate cap,
  the parent-document switch and the compression switch. The HyDE, rewriting and iterative-retrieval
  switches, the step limit (`maxAgenticSteps`, 0 at minimal), the query timeout and the level recorded
  for the query have no reader. The integration code above, with `adaptiveConfig.enableHyDE`, is not
  in the source.
- **Deep Think and Maximum.** Neither loop reads the level, the adaptive configuration, the thermal
  state, the memory pressure, the battery or Low Power Mode, so a hot phone, low memory, a low battery
  or Low Power Mode do not make them do less. What the device changes for them is section 5's chip
  configuration. From 5.7 both loops wait 1 second before each session from the second while iOS 27
  asks apps to use less, and the session count is not cut.
- **The cooldown.** `applyCooldown` does not return at once on a cool phone. Before each Standard
  generation it waits the tier's `stepCooldownMs`, 200 ms on an A17 Pro, 100 on an A18, 50 on an A19
  and 0 on the ultra tier, 150 ms more at efficient and 300 ms at minimal. Deep Think and Maximum do
  not call it.
- **Complexity.** The cases are trivial, standard, complex and agentic, taken from the query's profile.

`[evidence_level: code_verified, confidence: exact, evidence_source:
OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift:56-71
(recommendedOptimizationLevel), :115-261 (the tiers and levels), :324-400 (configForQuery), :408-413
(applyCooldown), :599-603 (QueryComplexity), OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:11545,
:11740, :14191, :14325 and :15541, OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift:66
and :233-234, OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift:5174 and :6643 (the pauses),
OpenIntelligence/Services/Infrastructure/Background/BackgroundTaskService.swift:1084-1087, the v5.6.0 tag
(no pause), a search of every Swift file under OpenIntelligence/ for each field and for the thermal,
battery and Low Power readers]`
