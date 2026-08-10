> **Documentation status:** Verified for OpenIntelligence v4.4 (working on v4.5) on 2026-06-30.

# RAG Technical Specifications

**Version**: 4.4 (working on v4.5)
**Updated**: June 30, 2026
**Compatibility**: iOS 26+ / Apple Intelligence

This document provides the technical formulas, algorithms, and deep dive specifications for the RAG pipeline.

> **For the High-Level Flow**: See [HOW_IT_WORKS.md](../HOW_IT_WORKS.md)

> **Full Architecture**: See [ARCHITECTURE.md](../ARCHITECTURE.md). The current repo contains 107 Swift service files under `OpenIntelligence/Services`.

> **Current State**: See [CURRENT_STATE_AND_GAPS.md](./CURRENT_STATE_AND_GAPS.md). The repo currently has 107 Swift service files under `OpenIntelligence/Services`. The 29-step pipeline below is a logical/audit view; the implementation is adaptive and does not run every step for every query.

> **Research Links**: See [Docs/Research/RAG_AND_RETRIEVAL_2024_2026.md](./Research/RAG_AND_RETRIEVAL_2024_2026.md) and [Docs/Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md](./Research/CAG_AND_CONTEXT_ENGINEERING_2024_2026.md).

---

## Pipeline Overview (29 Steps)

**How the 29 is counted** *(documented 2026-08-10; the rule was always applied, never written
down).* Ingestion contributes 6. The query loop contributes **23: Steps 1 through 9 inclusive**,
which is the query-to-response transformation proper. `Step 0` and `Step 10` are enumerated below
but are **not** counted in the 23, because neither is part of that transformation: Step 0 loads a
container vocabulary cache before any query exists, and Step 10 renders an answer that is already
final. The enumerated list therefore holds 25 entries while the figure is 23, and both are correct.

Count it yourself:

```bash
grep -cE '^  Step [0-9]' Docs/Engineering/RAG_TECHNICAL.md          # -> 25 enumerated
grep -oE '^  Step ([0-9.]+):' Docs/Engineering/RAG_TECHNICAL.md \
  | grep -vE 'Step (0|10):' | wc -l                                  # -> 23 counted
```

This is recorded because the missing rule has now caused two independent miscounts. The
`RESEARCH_PAPERS_REFERENCE_SHEET.md` F-3 finding of 2026-07-31 concluded the figure was
unenumerated, and a 2026-08-10 review concluded the correct total was 31. Both compared the raw
enumeration against the stated figure, found 25 against 23, and inferred an error in the figure.
The figure was right both times. `[evidence_level: code_verified, confidence: exact, evidence_source: the enumerated list below, git history of this file showing label 23 and enumeration 25 co-existing unchanged since 4e24bbb 2026-05-12]`

```
INGESTION (6 steps):
  1. Parse (PDFKit/Vision OCR, adaptive 5x-6x render scale/Office ZIP)
  2. SemanticChunker (≤310w, section detection)
  3. Entity Extraction (NLTagger NER + PascalCase)
  4. Token Validation (BertTokenizer ≤510)
  5. Embedding (384-dim MiniLM)
  6. Store (per-container vector store + SQLite FTS5 + metadata)

QUERY → RESPONSE (23 specified; 28 present in code, 27 active — see note below):
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
| `5.10` Extractive QA | **disabled** | Code path commented out; every query proceeds to LLM generation. Recorded reason in source: heuristic extraction produced false positives — returning `"three-quarters"` for a fuel-tank-capacity query — and bypassed the LLM entirely when it fired. Exact-value queries are now served by evidence steering at `4.8` rather than by a generation bypass. |

**What this does to the count, stated rather than quietly re-baselined.** The specification enumerates
23 (steps 1–9). The code carries **28** step labels across steps 1–9, of which **27 are active**.
`6 + 28 = 34` enumerated, `6 + 27 = 33` active. **The public "29-step" figure on FascinAIting.me and
in three documents is therefore an undercount of the shipped pipeline, not an overclaim.** Changing a
user-facing figure is an owner decision and none has been changed here; this note exists so the
decision is made with the real number in front of it.

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
  still computes `deterministicExtraction` from intent and query signals, and `ModelExecutionPlanner`
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
