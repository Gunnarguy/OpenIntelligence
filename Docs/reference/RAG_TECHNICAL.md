# RAG Technical Specifications

**Version**: 1.4
**Updated**: February 23, 2026
**Compatibility**: iOS 26+ / Apple Intelligence

This document provides the technical formulas, algorithms, and deep dive specifications for the RAG pipeline.

> **For the High-Level Flow**: See [HOW_IT_WORKS.md](../../HOW_IT_WORKS.md)

> **Full Architecture**: See [ARCHITECTURE.md](../../ARCHITECTURE.md) → "Complete Service Inventory (102 Services)"

---

## Pipeline Overview (29 Steps)

```
INGESTION (6 steps):
  1. Parse (PDFKit/Vision OCR 360 DPI/Office ZIP)
  2. SemanticChunker (≤310w, section detection)
  3. Entity Extraction (NLTagger NER + PascalCase)
  4. Token Validation (BertTokenizer ≤510)
  5. Embedding (384-dim MiniLM)
  6. Store (HNSW index + FTS5 + EntityIndex)

QUERY → RESPONSE (23 steps):
  Step 0:   Corpus Analysis (vocabulary cache)
  Step 1:   Query Understanding (pronoun resolution, NER)
  Step 1.5: Query Expansion (corpus + container vocab)
  Step 1.6: Intent Classification (lookup/procedure/compare/summarize)
  Step 2:   Query Embedding (384-dim)
  Step 2.5: RAPTOR-lite Routing (overview → L1 summaries)
  Step 3:   Hybrid Search (Vector + BM25 + RRF) or Iterative Retrieval
  Step 4:   Cross-Encoder Rerank (TinyBERT)
  Step 4.3: Low-Confidence Filtering
  Step 4.4: Multi-Document Representation (source diversity)
  Step 4.5: MMR Diversification (λ=0.6)
  Step 4.6: Parent Document Retrieval (±5 siblings)
  Step 4.7: Contextual Compression (LLM filters)
  Step 4.9: Graph Context Packing (token budget)
  Step 5:   Context Assembly (Lost-in-Middle reorder)
  Step 5.9: Extractive Summarization (for summarize intent)
  Step 5.10: Extractive QA (for lookup intent)
  Step 6:   LLM Generation (Apple FM / PCC)
  Step 6.5: Response Formatting (markdown preservation pipeline)
  Step 7:   Quality Assessment (confidence scoring)
  Step 7.5: Verification Gates A-G (anti-hallucination)
  Step 8:   Package Results
  Step 8.1: Calibrated Confidence (Platt scaling)
  Step 9:   Response Metadata (timing, sources, metrics)
  Step 10:  Markdown Rendering (block-level parser + inline normalization)
```

---

## Quick Reference Table

| Technique                 | File                                 | Setting                         | Default | Impact                    |
| ------------------------- | ------------------------------------ | ------------------------------- | ------- | ------------------------- |
| HyDE                      | `HyDEService.swift`                  | `enableHyDE`                    | ON      | +15-25% recall            |
| Parent Document Retrieval | `ParentDocumentService.swift`        | `enableParentDocumentRetrieval` | ON      | Multi-paragraph coherence |
| Contextual Compression    | `ContextualCompressionService.swift` | `enableContextualCompression`   | ON      | -40-60% tokens            |
| Agentic Orchestration     | `AgenticOrchestrator.swift`          | `.agentic` quality mode         | Manual  | 16K-48K context           |
| Lost-in-Middle            | `RAGEngine.swift`                    | Always on                       | ON      | Better LLM attention      |
| Cross-Encoder Rerank      | `RAGEngine.swift`                    | Always on                       | ON      | Improved ranking          |
| Query Rewriting           | `QueryRewriterService.swift`         | `enableQueryRewriting`          | ON      | Clarifies ambiguity       |
| Iterative Retrieval       | `IterativeRetrievalService.swift`    | `enableIterativeRetrieval`      | OFF     | Multi-pass refinement     |
| **Adaptive Pipeline**     | `AdaptivePipelineOptimizer.swift`    | Automatic                       | ON      | Thermal/battery aware     |

---

## 1. HyDE (Hypothetical Document Embeddings)

### What It Does

Generates a hypothetical answer to the query BEFORE embedding, then embeds that hypothetical document for retrieval instead of the raw question.

### Why It Matters

Questions and answers often don't share vocabulary:

- Query: "What oil does my car take?"
- Answer: "SAE 0W-20 synthetic oil, 5.3 quarts capacity"

By generating a hypothetical answer first, we bridge this vocabulary gap.

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
Services/
├── HyDEService.swift                    # Hypothetical Document Embeddings
├── ParentDocumentService.swift          # Parent/sibling context expansion
├── ContextualCompressionService.swift   # Chunk compression + grounding
├── AgenticOrchestrator.swift            # Multi-session reasoning
├── DeviceCapabilityService.swift        # Hardware tier detection + form factors
├── AdaptivePipelineOptimizer.swift      # Runtime thermal/battery optimization
├── RAGEngine.swift                      # Reranking, MMR, lost-in-middle
├── RAGService.swift                     # Main orchestrator
├── QueryRewriterService.swift           # Query clarification
├── QueryEnhancementService.swift        # Intent classification
├── IterativeRetrievalService.swift      # Multi-pass retrieval
└── SettingsStore.swift                  # All settings

Views/ChatV2/
└── ChatScreen.swift                     # Query task management
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
