# How OpenIntelligence Actually Works

**A plain-English explanation of the gears inside the machine.**

---

## The One Gear That Turns Everything Else

**The embedding model.**

That's it. That's the core gear. Everything else exists to serve it or process its output.

```
Text → [384 numbers] → Math becomes possible
```

The embedding model (`MiniLM-L6-v2`) takes any text and converts it into 384 numbers. Those numbers represent _meaning_ in a way computers can compare.

"How do I change my oil?" → `[0.23, -0.87, 0.45, ...]`
"Vehicle lubricant replacement procedure" → `[0.25, -0.84, 0.43, ...]`

Those two vectors are _close_ in 384-dimensional space. That's the magic. That's why semantic search works.

---

## The Machine (5 Core Gears)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   GEAR 1: CHUNKER                                               │
│   "Break documents into pieces small enough to embed"           │
│                                                                 │
│   Document (50 pages) → 200 chunks (≤310 words each)            │
│   Why? Embedding model has 510 token limit.                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   GEAR 2: EMBEDDER  ← ← ← THE CORE GEAR                         │
│   "Convert text chunks into comparable numbers"                 │
│                                                                 │
│   Chunk text → [384 floats]                                     │
│   Store in HNSW index for fast nearest-neighbor lookup          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   GEAR 3: RETRIEVER                                             │
│   "Find chunks whose numbers are closest to the question"       │
│                                                                 │
│   Query → embed → cosine similarity → top 20 chunks             │
│   Also: BM25 keyword search → fuse with RRF                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   GEAR 4: RANKER                                                │
│   "Reorder chunks by actual relevance to this specific query"   │
│                                                                 │
│   Cross-encoder sees [query + chunk] together                   │
│   Catches nuance that embeddings miss                           │
│   Top 20 → reranked top 5                                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   GEAR 5: GENERATOR                                             │
│   "Write an answer using the retrieved context"                 │
│                                                                 │
│   System prompt + chunks + question → Apple FM → response       │
│   4096 token limit. That's why all the prior gears matter.      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why Each Gear Exists

| Gear          | Without It...                                           |
| ------------- | ------------------------------------------------------- |
| **Chunker**   | Can't embed — text too long for model's 510 token limit |
| **Embedder**  | Can't search — no way to compare meaning mathematically |
| **Retriever** | LLM sees nothing — just makes stuff up (hallucination)  |
| **Ranker**    | Wrong chunks get priority — garbage in, garbage out     |
| **Generator** | No human-readable answer — just a pile of chunks        |

---

## The Core Insight

**This app is a search engine that feeds an LLM.**

Everything — the 23 steps, the 51 services, the HyDE and MMR and verification gates — they're all refinements of this:

1. **Make text searchable** (chunking + embedding)
2. **Find the right pieces** (retrieval + ranking)
3. **Generate an answer from those pieces** (LLM)

The embedding model is the heart. The LLM is the mouth. Everything else is plumbing to connect them well.

---

## The Actual Constraints

The hard part isn't any single gear. It's:

1. **The 4096 token budget** — You have room for maybe 5-8 chunks. Better pick the right ones.
2. **The 510 token embedding limit** — Chunks must be small, but not so small they lose context.
3. **The "needle in haystack" problem** — 50,000 chunks, one has the answer. Find it.

All complexity exists because the constraints are brutal. If you had infinite context, you'd just dump the whole document in. You don't, so you built a machine that surgically extracts exactly what's needed.

---

# Quality Modes: How Many Times the Machine Runs

The 5 gears above are the machine. Quality modes control **how many times** you run it and **what you do between runs**.

---

## Standard Mode (1 Pass)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   STANDARD MODE: Run the machine once                           │
│                                                                 │
│   Question → [5 Gears] → Answer                                 │
│                                                                 │
│   Sessions: 1-3                                                 │
│   Token budget: ~12K                                            │
│   Time: 2-5 seconds                                             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**What happens:**

1. Run the 5 gears once
2. Get an answer
3. Done

**When to use:**

- Simple questions: "What's the oil type?"
- Facts that exist in one place
- You need speed

**The tradeoff:** If the retriever misses the right chunk, you get a wrong answer. No second chances.

---

## Deep Think Mode (4-8 Passes)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   DEEP THINK MODE: Run the machine multiple times               │
│   Each pass searches differently and ADDS to the answer         │
│                                                                 │
│   Question → [5 Gears] → Draft Answer                           │
│                    │                                            │
│                    ▼                                            │
│              ┌─────────────────────────────────────┐            │
│              │  "What details could I add?"        │            │
│              │  Generate new search queries        │            │
│              └──────────────┬──────────────────────┘            │
│                             │                                   │
│                             ▼                                   │
│              Question v2 → [5 Gears] → Enhanced Answer          │
│                             │                                   │
│                             ▼                                   │
│              Question v3 → [5 Gears] → Even More Details        │
│                             │                                   │
│                             ▼                                   │
│                      (repeat 4-8 times)                         │
│                             │                                   │
│                             ▼                                   │
│              ┌─────────────────────────────────────┐            │
│              │  SYNTHESIZER: Merge all insights    │            │
│              │  into one coherent answer           │            │
│              └─────────────────────────────────────┘            │
│                                                                 │
│   Sessions: 4-8                                                 │
│   Token budget: ~32K                                            │
│   Time: 10-30 seconds                                           │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**What happens:**

1. Run the 5 gears → get draft answer
2. Ask: "What could I add to make this more complete?"
3. Generate new search queries based on what's missing
4. Run the 5 gears again with new queries
5. ENRICH the answer (don't second-guess it)
6. Repeat 4-8 times
7. Synthesize everything into one final answer

**The key insight: ENHANCE, don't VERIFY**

Early versions made a mistake: each session would "verify" the previous answer. This caused hyper-skepticism — the LLM would reject correct answers like "SAE 0W-20" because it thought they were "too specific to be real."

Now each session ADDS details. "SAE 0W-20" stays in the answer; session 2 might add "with 6.0 quart capacity."

**When to use:**

- Complex questions spanning multiple document sections
- "Compare X and Y across these documents"
- Research-style questions where you want thoroughness
- You can wait 15-30 seconds for a better answer

**The tradeoff:** Slower, but catches things the first pass missed.

---

## Maximum Mode (8-50 Passes)

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   MAXIMUM MODE: Keep running until 98% confident                │
│   Multiple PARALLEL chains that merge at the end                │
│                                                                 │
│                        Question                                 │
│                            │                                    │
│              ┌─────────────┼─────────────┐                      │
│              │             │             │                      │
│              ▼             ▼             ▼                      │
│         ┌────────┐    ┌────────┐    ┌────────┐                  │
│         │Chain 1 │    │Chain 2 │    │Chain 3 │                  │
│         │8 passes│    │8 passes│    │8 passes│                  │
│         │Cluster │    │Cluster │    │Cluster │                  │
│         │   A    │    │   B    │    │   C    │                  │
│         └───┬────┘    └───┬────┘    └───┬────┘                  │
│             │             │             │                       │
│             └─────────────┼─────────────┘                       │
│                           │                                     │
│                           ▼                                     │
│              ┌─────────────────────────────────┐                │
│              │  CLUSTER SYNTHESIZER            │                │
│              │  "Merge findings from all       │                │
│              │   document clusters"            │                │
│              └──────────────┬──────────────────┘                │
│                             │                                   │
│                             ▼                                   │
│              ┌─────────────────────────────────┐                │
│              │  CONFIDENCE CHECK               │                │
│              │  Are we at 98%? No → keep going │                │
│              └─────────────────────────────────┘                │
│                                                                 │
│   Sessions: 8-50                                                │
│   Token budget: ~200K                                           │
│   Time: 30 seconds - 2 minutes                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**What happens:**

1. Cluster documents into groups (e.g., "maintenance docs", "specs docs", "safety docs")
2. Spawn PARALLEL reasoning chains — one per cluster
3. Each chain runs 8+ Deep Think passes on its cluster
4. Chains run simultaneously (not sequential)
5. Merge all chain outputs in a synthesis step
6. Check confidence: Are we at 98%?
7. If not, spawn more chains or dig deeper
8. Keep going until confident or hit 50 sessions

**Why clusters?**

The 4096 token limit means you can only see ~5 chunks at a time. With Maximum mode, you escape this by having different chains look at different parts of your documents. Chain 1 might find the oil spec. Chain 2 might find the capacity. Chain 3 might find the drain plug torque. The synthesizer combines them all.

**When to use:**

- "Summarize everything in these 500 pages"
- Cross-document comparisons
- You need the most complete possible answer
- You're willing to wait for quality

**The tradeoff:** Slow (30s-2min), but essentially searches your entire document corpus from multiple angles.

---

## Comparison

| Mode           | Sessions | Token Budget | Time     | Use Case                        |
| -------------- | -------- | ------------ | -------- | ------------------------------- |
| **Standard**   | 1-3      | ~12K         | 2-5s     | Quick lookups, simple facts     |
| **Deep Think** | 4-8      | ~32K         | 10-30s   | Research, multi-section answers |
| **Maximum**    | 8-50     | ~200K        | 30s-2min | Exhaustive search, summaries    |

---

## The Mental Model

```
Standard:     "Search once, answer once"
Deep Think:   "Search, answer, search better, enrich, repeat"
Maximum:      "Search everything from every angle, merge it all"
```

Standard is a rifle shot.
Deep Think is a careful exploration.
Maximum is carpet bombing.

---

## Why This Matters

The 4096 token limit is **brutal**. OpenAI gives you 128K. Apple gives you 4K — that's 32× smaller.

Every mode exists to work around this constraint:

- **Standard** accepts the limit and makes one good attempt
- **Deep Think** sidesteps it by running multiple small sessions that build on each other
- **Maximum** breaks through it by running parallel chains that each see different document clusters, then merges everything

You're not making the window bigger. You're taking more windows.

---

# How It All Stitches Together: The Token Budget

This is where brains melt. Let me explain how 51 services coordinate to fit everything into 4096 tokens.

---

## The Problem: Everything Has to Fit in One Box

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   THE 4096 TOKEN BOX (Apple FM's context window)                │
│                                                                 │
│   ┌─────────────────┐  ┌─────────────────┐  ┌──────────────┐   │
│   │  Instructions   │  │   Retrieved     │  │   Question   │   │
│   │   ~200-400      │  │    Chunks       │  │   ~50-200    │   │
│   │    tokens       │  │  ~1500-2500     │  │    tokens    │   │
│   └─────────────────┘  └─────────────────┘  └──────────────┘   │
│                                                                 │
│   ┌─────────────────────────────────────────────────────────┐   │
│   │                     RESPONSE                             │   │
│   │                   ~500-1500 tokens                       │   │
│   │             (model has to leave room for this)           │   │
│   └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│   Total: Instructions + Chunks + Question + Response ≤ 4096     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Everything competes for the same 4096 tokens:**

- System instructions (telling the LLM how to behave)
- Your retrieved chunks (the evidence)
- Your question
- The model's response

If you shove too much context in, the model has no room to answer. If you put too little, it doesn't have enough evidence.

---

## The Token Budget Breakdown (From Actual Code)

The code in `AgenticOrchestrator.swift` shows the REAL budget allocation:

```
┌────────────────────────────────────────────────────────────────┐
│  ACTUAL BUDGET (from executeComprehensiveSynthesis)            │
├────────────────────────────────────────────────────────────────┤
│  System prompt:         ~370-610 tokens    (mode-dependent)    │
│  User query:            ~50 tokens                             │
│  Context (chunks):      ~2200 tokens max   ≈ 2800 chars        │
│  Response generation:   ~800 tokens                            │
│  Safety margin:         ~100 tokens                            │
├────────────────────────────────────────────────────────────────┤
│  TOTAL:                    4096 tokens                         │
└────────────────────────────────────────────────────────────────┘
```

**The actual numbers from the code:**

- Standard mode system prompt: ~370 tokens
- Deep Think system prompt: ~610 tokens (enhanced for detail extraction)
- Max context characters: **2800** (reduced when using enhanced prompts)
- Max response tokens: **800** (conservative to stay within 4096)
- Conversion ratio: **1.4 chars/token** (Apple FM)

**Translation:** You get roughly **2800 characters of document context**. At ~300 chars per chunk, that's about **5-8 chunks**. The enhanced Deep Think prompt eats into this budget.

---

## When Does the LLM Actually Run?

**This is the key insight:** The LLM does NOT initiate the process. The LLM sits at the END, waiting.

```
USER ASKS QUESTION
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│   ENTIRE PIPELINE RUNS FIRST (no LLM involvement)             │
│                                                               │
│   1. Query Enhancement (NLTagger, regex - no LLM)             │
│   2. Query Embedding (MiniLM CoreML - no LLM)                 │
│   3. Hybrid Search (HNSW + BM25 - no LLM)                     │
│   4. Cross-Encoder Rerank (TinyBERT CoreML - no LLM)          │
│   5. MMR Diversification (math - no LLM)                      │
│   6. Context Packing (string operations - no LLM)             │
│                                                               │
│   All of this happens BEFORE the LLM is called.               │
│   The LLM has no idea a query is happening.                   │
│                                                               │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│                                                               │
│   NOW THE LLM IS CALLED                                       │
│                                                               │
│   The LLM receives a SINGLE request with:                     │
│     - System prompt (instructions)                            │
│     - Packed context (pre-selected chunks)                    │
│     - User question                                           │
│                                                               │
│   The LLM generates ONE response and is done.                 │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

**Standard Mode = 1 LLM call.** Everything else is pre-processing.

---

## How the Services Stitch Together

```
USER ASKS QUESTION
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 1: QUERY ENHANCEMENT                                    │
│                                                               │
│  QueryEnhancementService:                                     │
│    "What oil does my car need?"                               │
│    → Expands to: ["oil type", "lubricant specification",      │
│                   "engine oil requirement"]                   │
│                                                               │
│  NO LLM - uses NLTagger NER + regex patterns                  │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 2: RETRIEVAL (Vector + BM25)                            │
│                                                               │
│  HybridSearchService:                                         │
│    Vector search → top 50 by embedding similarity             │
│    BM25 search → top 50 by keyword match                      │
│    RRF fusion → merged ranked list                            │
│                                                               │
│  Returns: 50 candidate chunks                                 │
│  (Way too many to fit in context)                             │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 3: RERANKING (Brutal Filtering)                         │
│                                                               │
│  RAGEngine.rerankWithCrossEncoder():                          │
│    50 chunks → cross-encoder scores each                      │
│    Sort by relevance to THIS specific query                   │
│    → Top 10 candidates                                        │
│                                                               │
│  MMR Diversification:                                         │
│    Remove near-duplicates (don't waste tokens on repetition)  │
│    → Final 5-8 diverse, relevant chunks                       │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 4: CONTEXT PACKING (Token Tetris)                       │
│                                                               │
│  ContextPackingService:                                       │
│    Budget: 5500 characters (~1800 tokens for chunks)          │
│                                                               │
│    For each chunk:                                            │
│      - If full chunk fits → add it                            │
│      - If chunk too big → truncate at sentence boundary       │
│      - Track remaining budget                                 │
│      - Stop when budget exhausted                             │
│                                                               │
│  Lost-in-Middle Reordering:                                   │
│    Chunks [A, B, C, D, E] ranked by relevance                 │
│    Reorder to [A, C, E, D, B]                                 │
│    Best chunks at START and END (where LLM pays attention)    │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 5: LLM GENERATION (STANDARD MODE = 1 CALL)              │
│                                                               │
│  AppleFoundationLLMService:                                   │
│    Assemble final prompt:                                     │
│      [Instructions] + [Packed Chunks] + [Question]            │
│                                                               │
│    Check: Total tokens < 4096? ✓                              │
│    If too big: Emergency truncation (drop lowest chunk)       │
│                                                               │
│    Send to Apple FM → Get response                            │
│                                                               │
│    THIS IS THE ONLY LLM CALL IN STANDARD MODE.                │
│    The LLM is NOT involved in retrieval or ranking.           │
└───────────────────────────────────────────────────────────────┘
        │
        ▼
┌───────────────────────────────────────────────────────────────┐
│  STEP 6: VERIFICATION (Did We Hallucinate?)                   │
│                                                               │
│  VerificationGateService:                                     │
│    Gate A: Did retrieval confidence exceed threshold?         │
│    Gate B: Are response claims backed by chunks?              │
│    Gate C: Do numbers match source documents?                 │
│    Gate D: Any contradictions between chunks?                 │
│                                                               │
│    If gates fail: "I don't have enough information"           │
│    (Better to abstain than hallucinate)                       │
└───────────────────────────────────────────────────────────────┘
```

---

## Deep Think / Maximum: MULTIPLE LLM Calls

**Standard Mode:** 1 LLM call at the end. Fast. Simple.

**Deep Think / Maximum:** Multiple SEPARATE LLM calls, each with its own 4096-token budget.

**Key insight:** The LLM does NOT "check in" or "nudge" during retrieval. Each LLM call is independent. The orchestrator (not the LLM) decides when to call the LLM again.

```
DEEP THINK (3-8 SEPARATE LLM calls)

                    ┌─────────────────────────────────────────┐
                    │  AgenticOrchestrator (the conductor)    │
                    │  Controls the loop. Decides next step.  │
                    └─────────────────────────────────────────┘
                                      │
         ┌────────────────────────────┼────────────────────────────┐
         │                            │                            │
         ▼                            ▼                            ▼
    ┌─────────┐                  ┌─────────┐                  ┌─────────┐
    │ LLM     │                  │ LLM     │                  │ LLM     │
    │ Call 1  │                  │ Call 2  │                  │ Call 3  │
    │         │                  │         │                  │         │
    │ "Here's │                  │ "Adding │                  │ "Final  │
    │ what I  │                  │ these   │                  │ synthe- │
    │ found"  │                  │ details"│                  │ sis"    │
    └─────────┘                  └─────────┘                  └─────────┘
         │                            │                            │
         └────────────────────────────┴────────────────────────────┘
                                      │
                                      ▼
                            [Combined Answer]
```

**Each LLM call is STATELESS.** The LLM from Call 1 has no memory of what it said. The orchestrator passes insights from prior calls as context to the next call.

---

## How Multi-Session Actually Works (from the code)

From `AgenticOrchestrator.swift`, here's what really happens:

```
DEEP THINK MODE (executeReasoningChain):

Call 1 (Fact Finding):
  Input:  [System Prompt ~370 tokens] + [Chunks A,B,C ~2800 chars] + [Query ~50 tokens]
  Output: "Key facts: The manual specifies SAE 0W-20 oil..."

  → Orchestrator extracts this insight, stores it

Call 2 (Analysis):
  Input:  [System Prompt] + [NEW Chunks D,E ~2000 chars] + [Prior insight ~300 chars] + [Query]
  Output: "Pattern detected: All torque specs are in ft-lbs..."

  → Orchestrator adds this insight to the chain

Call 3 (Synthesis):
  Input:  [System Prompt] + [All prior insights ~600 chars] + [Top chunks ~1500 chars] + [Query]
  Output: "Based on the evidence: Use SAE 0W-20, 6 quarts, torque to 25 ft-lbs [S1][S2]"

TOTAL: 3 separate LanguageModelSession.respond() calls
```

**The trick:** Each call sees different chunks + accumulated insights. Effective context across 3 calls = way more than 4096 tokens, but each call respects the limit.

---

## Maximum Mode: Parallel Chains

Maximum mode (8-50 sessions) does something crazier:

```
MAXIMUM MODE (executeTrueUnlimitedReasoning):

                    Cluster documents by topic
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
    ┌─────────┐       ┌─────────┐       ┌─────────┐
    │ Chain 1 │       │ Chain 2 │       │ Chain 3 │
    │         │       │         │       │         │
    │ Engine  │       │ Chassis │       │ Electric│
    │ docs    │       │ docs    │       │ docs    │
    │         │       │         │       │         │
    │ 3 LLM   │       │ 3 LLM   │       │ 3 LLM   │
    │ calls   │       │ calls   │       │ calls   │
    └─────────┘       └─────────┘       └─────────┘
         │                 │                 │
         └─────────────────┼─────────────────┘
                           │
                           ▼
                    ┌─────────────┐
                    │ Synthesizer │
                    │             │
                    │ Final LLM   │
                    │ call merges │
                    │ all chains  │
                    └─────────────┘
                           │
                           ▼
                    [Comprehensive Answer]
```

**Total LLM calls:** 3 chains × 3 sessions + 1 synthesizer = **10 LLM calls minimum**

Each chain explores a different part of your document corpus. The synthesizer combines findings. That's how you escape the 4096 limit — by running many independent sessions.

---

## The Stitching: What Coordinates All This?

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   RAGService (The Orchestrator)                                 │
│   @MainActor, ~10,000 lines                                     │
│                                                                 │
│   "I'm the conductor. I call each service in sequence,          │
│    track token budgets, handle errors, and update the UI."      │
│                                                                 │
│   For Standard mode: I do retrieval → rerank → 1 LLM call       │
│   For Deep Think: I hand off to AgenticOrchestrator             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
        │
        │ calls
        ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   AgenticOrchestrator (The Deep Thinker)                        │
│   @MainActor, ~6000 lines                                       │
│                                                                 │
│   "For Deep Think and Maximum modes, I manage the multi-        │
│    session reasoning loop. I track confidence, decide when      │
│    to search again, and synthesize final answers."              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
        │
        │ coordinates
        ▼
┌───────────────────────────────────────────────────────────────────────────────┐
│                                                                               │
│  51 Services (Specialized Workers)                                            │
│                                                                               │
│  DocumentProcessor → SemanticChunker → EmbeddingService → VectorDatabase     │
│                                                                               │
│  QueryEnhancementService → HybridSearchService → RAGEngine → LLMService       │
│                                                                               │
│  VerificationGateService → ContextPackingService → ParentDocumentService      │
│                                                                               │
│  Each service does ONE thing well. Orchestrators sequence them.               │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
```

---

# How the AgenticOrchestrator Actually Works (The Black Box Opened)

This is the brain. The decision-maker. Let's crack it open.

---

## The Core Loop: Retrieval-First, Then Decide

The orchestrator doesn't guess how hard a question is upfront. It **retrieves first**, then looks at the results and decides what to do.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│  QUERY ARRIVES                                                  │
│                                                                 │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  STEP 0: Self-RAG Check                                 │    │
│  │  "Does this query even NEED retrieval?"                 │    │
│  │                                                         │    │
│  │  If query is "What's 2+2?" → Skip retrieval entirely    │    │
│  │  If query is "What oil does my car need?" → Need docs   │    │
│  └─────────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  STEP 1: Multi-Query Retrieval                          │    │
│  │  Generate 3-5 search variations of original query       │    │
│  │  Run ALL of them through vector + BM25                  │    │
│  │  Fuse results with RRF                                  │    │
│  └─────────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  STEP 2: EVALUATE RESULTS (The Decision Point)          │    │
│  │                                                         │    │
│  │  Check 1: Lexical relevance                             │    │
│  │    "Do query keywords appear in retrieved chunks?"      │    │
│  │    → Returns 0.0 to 1.0                                 │    │
│  │                                                         │    │
│  │  Check 2: Semantic intent validation                    │    │
│  │    "Does retrieved content ADDRESS the question?"       │    │
│  │    → Returns true/false                                 │    │
│  │                                                         │    │
│  │  Check 3: Similarity score thresholds                   │    │
│  │    excellent: top score > 0.45, top-3 avg > 0.35        │    │
│  │    good:      top score > 0.30, top-3 avg > 0.22        │    │
│  │    moderate:  top score > 0.15, top-3 avg > 0.12        │    │
│  │    low:       anything worse                            │    │
│  └─────────────────────────────────────────────────────────┘    │
│       │                                                         │
│       ▼                                                         │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  DECISION BRANCH (switch statement in the actual code)  │    │
│  │                                                         │    │
│  │  if lexical < 0.1 AND intent = false:                   │    │
│  │      → HARD EXIT: Return "not found" (don't hallucinate)│    │
│  │                                                         │    │
│  │  else if quality = excellent:                           │    │
│  │      → Run reasoning chain (3+ LLM calls)               │    │
│  │                                                         │    │
│  │  else if quality = good:                                │    │
│  │      → Run reasoning chain (3+ LLM calls)               │    │
│  │                                                         │    │
│  │  else if quality = moderate or low:                     │    │
│  │      → Run graph expansion first                        │    │
│  │      → Then re-evaluate                                 │    │
│  │      → Then run reasoning chain                         │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## The Actual Code Flow (Simplified from 6000 lines)

```swift
// AgenticOrchestrator.execute() - the main entry point

func execute(query: String, onStep: ((ThinkingStep) -> Void)?) async throws -> AgenticResult {

    // ━━━ STEP 0: Do we even need retrieval? ━━━
    let (needsRetrieval, _) = try await decideIfRetrievalNeeded(query: query)
    if !needsRetrieval {
        return try await executeSelfRAG(query: query)  // Skip docs, just answer
    }

    // ━━━ STEP 1: Multi-query retrieval ━━━
    let searchQueries = try await generateSearchQueries(originalQuery: query)
    // Returns: ["oil type specification", "engine lubricant", "motor oil grade", ...]

    let (_, initialChunks) = try await executeMultiQuerySearch(queries: searchQueries)
    // Returns: Top chunks from ALL query variations, fused with RRF

    // ━━━ STEP 2: Evaluate what we got ━━━
    var retrievalQuality = evaluateRetrievalQuality(chunks: initialChunks, query: query)
    let lexicalRelevance = checkLexicalRelevance(query: query, chunks: initialChunks)
    let (intentValid, _) = try await validateSemanticIntent(query: query, chunks: initialChunks)

    // ━━━ HARD EXIT: If retrieval is garbage, don't waste LLM calls ━━━
    if lexicalRelevance < 0.1 && !intentValid {
        return AgenticResult(
            finalAnswer: "I couldn't find information about this in your documents.",
            confidence: 0.0
        )
    }

    // ━━━ DECISION BRANCH: What do we do with these results? ━━━
    switch retrievalQuality {

    case .excellent, .good:
        // Good results → run reasoning chain immediately
        if config.isUnlimited {
            // Maximum mode: 8-50 parallel chains
            return try await executeTrueUnlimitedReasoning(query: query, chunks: initialChunks)
        } else {
            // Deep Think: 3-8 session chain
            return try await executeReasoningChain(query: query, chunks: initialChunks)
        }

    case .moderate, .low:
        // Weak results → try to improve before reasoning
        let (_, expandedChunks) = try await executeGraphExpansion(query: query, chunks: initialChunks)

        // Re-evaluate after expansion
        retrievalQuality = evaluateRetrievalQuality(chunks: expandedChunks, query: query)

        // NOW run reasoning chain with (hopefully) better chunks
        return try await executeReasoningChain(query: query, chunks: expandedChunks)
    }
}
```

---

## The Quality Thresholds (from actual code)

```swift
private enum RetrievalQuality {
    case excellent  // Top score > 0.45, top-3 avg > 0.35
    case good       // Top score > 0.30, top-3 avg > 0.22
    case moderate   // Top score > 0.15, top-3 avg > 0.12
    case low        // Anything worse
}
```

**These numbers are SEMANTIC similarity scores**, not percentages. A 0.35 similarity doesn't mean "35% match" — it means the embedding vectors have a cosine similarity of 0.35, which is actually pretty good for semantic search.

---

## What Happens in Each Reasoning Chain Session

```
SESSION 1: "FACT FINDING"
┌─────────────────────────────────────────────────────────────────┐
│  Input:                                                         │
│    - System prompt: "Extract key facts from these excerpts"     │
│    - Chunks A, B, C (top 3 by relevance)                        │
│    - Original query                                             │
│                                                                 │
│  LLM Output:                                                    │
│    "Key facts found:                                            │
│     - The manual specifies SAE 0W-20 oil [S1]                   │
│     - Capacity is 6 quarts with filter [S2]                     │
│     - Drain plug torque is 25 ft-lbs [S3]"                      │
│                                                                 │
│  Orchestrator extracts this insight → stores in memory          │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
SESSION 2: "ANALYSIS"
┌─────────────────────────────────────────────────────────────────┐
│  Input:                                                         │
│    - System prompt: "Analyze patterns, find additional details" │
│    - NEW chunks D, E (different from session 1!)                │
│    - Prior insight from session 1                               │
│    - Original query                                             │
│                                                                 │
│  LLM Output:                                                    │
│    "Additional findings:                                        │
│     - Synthetic blend is recommended for cold climates [S4]     │
│     - Oil filter part number is XYZ-123 [S5]"                   │
│                                                                 │
│  Orchestrator adds this insight to the chain                    │
└─────────────────────────────────────────────────────────────────┘
        │
        ▼
SESSION 3: "SYNTHESIS"
┌─────────────────────────────────────────────────────────────────┐
│  Input:                                                         │
│    - System prompt: "Synthesize all findings into final answer" │
│    - ALL prior insights (from sessions 1 + 2)                   │
│    - Top chunks (best evidence)                                 │
│    - Original query                                             │
│                                                                 │
│  LLM Output:                                                    │
│    "Your car needs SAE 0W-20 synthetic blend oil, 6 quarts      │
│     with filter change. Torque drain plug to 25 ft-lbs.         │
│     Filter part number: XYZ-123.                                │
│     [S1][S2][S3][S4][S5]"                                       │
│                                                                 │
│  This becomes the FINAL ANSWER                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## The Insight Accumulation Pattern

This is the key trick. Each LLM call is stateless, but the ORCHESTRATOR maintains state:

```swift
// Inside executeReasoningChain()

var accumulatedInsights: [String] = []

for sessionIndex in 0..<sessionCount {

    // Pick DIFFERENT chunks for each session (sliding window)
    let sessionChunks = selectChunksForSession(
        allChunks: chunks,
        sessionIndex: sessionIndex,
        totalSessions: sessionCount
    )

    // Build context including PRIOR insights
    let context = buildSessionContext(
        chunks: sessionChunks,
        priorInsights: accumulatedInsights,  // ← This is the memory
        sessionType: sessionTypes[sessionIndex]
    )

    // Call LLM (this is the actual LanguageModelSession.respond())
    let response = try await llmService.generate(
        systemPrompt: sessionPrompts[sessionIndex],
        context: context,
        query: query,
        maxTokens: 800
    )

    // Extract and store the insight for next session
    let insight = extractInsight(from: response.text)
    accumulatedInsights.append(insight)
}

return accumulatedInsights.last!  // Final synthesis is the answer
```

---

## Maximum Mode: Parallel Chains

Maximum mode is the same pattern, but running MULTIPLE chains in parallel across document clusters:

```swift
// Inside executeTrueUnlimitedReasoning()

// 1. Cluster documents by topic
let clusters = clusterDocumentsByTopic(allChunks)
// Returns: [EngineCluster, ChassisCluster, ElectricalCluster, ...]

// 2. Run a reasoning chain on EACH cluster (in parallel)
let chainResults = try await withThrowingTaskGroup(of: ChainResult.self) { group in
    for cluster in clusters {
        group.addTask {
            return try await self.executeReasoningChain(
                query: query,
                chunks: cluster.chunks,
                config: .light  // Shorter chains per cluster
            )
        }
    }

    var results: [ChainResult] = []
    for try await result in group {
        results.append(result)
    }
    return results
}

// 3. Final synthesis: merge all chain insights
let finalAnswer = try await synthesizeChainResults(
    query: query,
    chainResults: chainResults
)
```

---

## Summary: The Orchestrator's Job

1. **Retrieve first** — don't guess complexity upfront
2. **Evaluate quality** — lexical overlap, semantic intent, similarity scores
3. **Hard exit if garbage** — don't waste LLM calls on irrelevant content
4. **Branch based on quality** — excellent/good → proceed, moderate/low → expand first
5. **Run reasoning chain** — multiple LLM calls with different chunks + accumulated insights
6. **Accumulate insights** — orchestrator maintains state between stateless LLM calls
7. **Maximum mode** — same pattern, but parallel chains across document clusters

**The orchestrator is not a black box.** It's a state machine with clear decision points based on retrieval quality metrics.

---

## The Real Magic: Async/Await Chains

Every service is `async`. They chain together with `await`:

```swift
// Pseudocode of what RAGService actually does (STANDARD MODE)
// This is 1 LLM call. Deep Think/Maximum call this pattern MULTIPLE times.

func answerQuestion(query: String) async throws -> String {

    // 1. Enhance the query (NO LLM - uses NLTagger)
    let expandedQueries = await queryEnhancer.expand(query)

    // 2. Parallel retrieval (NO LLM - CoreML models only)
    async let vectorResults = vectorStore.search(query)
    async let bm25Results = bm25Index.search(query)

    // 3. Wait for both, fuse (NO LLM - math)
    let fused = await rrfFuse(vectorResults, bm25Results)

    // 4. Rerank (NO LLM - TinyBERT cross-encoder, not Apple FM)
    let reranked = await ragEngine.rerank(fused, query: query)

    // 5. Pack into token budget (NO LLM - string ops)
    let context = await contextPacker.pack(reranked, maxChars: 2800)

    // 6. Generate (THE ONLY LLM CALL)
    let response = await llmService.generate(
        instructions: systemPrompt,  // ~370-610 tokens
        context: context,            // ~2000 tokens
        question: query,             // ~50 tokens
        maxTokens: 800               // response budget
    )

    // 7. Verify (NO LLM - pattern matching)
    let verified = await verificationGates.check(response, sources: reranked)

    return verified.answer
}
```

**Standard Mode = 1 LLM call.** Everything before step 6 is pre-processing with CoreML models (MiniLM, TinyBERT) and math. The LLM only shows up at the end.

---

## LLM Call Count by Mode

| Mode           | LLM Calls | What Happens                                 |
| -------------- | --------- | -------------------------------------------- |
| **Standard**   | 1         | Retrieval → Pack → Generate → Done           |
| **Deep Think** | 3-8       | Reasoning chain: Fact → Analysis → Synthesis |
| **Maximum**    | 10-50+    | Parallel chains + synthesizer + verification |

Each LLM call is a fresh `LanguageModelSession.respond()`. No persistent context between calls — the orchestrator passes insights manually.

---

# The Apple Foundation Model: What You're Actually Using

The "Generator" gear at the end is Apple's on-device ~3 billion parameter language model. Here's what it actually is:

---

## The Model

| Spec                | Value                                               |
| ------------------- | --------------------------------------------------- |
| **Parameters**      | ~3 billion                                          |
| **Context Window**  | 4,096 tokens (TN3193)                               |
| **Vocabulary**      | 49,000 tokens                                       |
| **Quantization**    | 3.7 bits per weight (mixed 2-bit/4-bit)             |
| **Inference Speed** | 0.6ms per prompt token, 30 tokens/second generation |
| **Architecture**    | Transformer with grouped-query-attention            |

## What It Can Do

Per Apple's documentation, the on-device model excels at:

| Capability                | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| **Text Generation**       | Summarization, writing, rewriting, creative content  |
| **Entity Extraction**     | Pull structured data from unstructured text          |
| **Text Understanding**    | Comprehension, classification, analysis              |
| **Guided Generation**     | Generate Swift structs directly with `@Generable`    |
| **Tool Calling**          | Call Swift functions via `@Tool` to take actions     |
| **Instruction Following** | 85.7% accuracy on IFEval (beats Llama-3-8B)          |
| **Safety**                | 7.5% violation rate (lowest among comparable models) |

## How This App Uses It

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   OpenIntelligence uses Apple FM via:                           │
│                                                                 │
│   1. LanguageModelSession — streaming text generation           │
│                                                                 │
│   2. @Tool functions — 8 agentic tools:                         │
│      • searchDocuments() — RAG retrieval                        │
│      • reformulateQuery() — query rewriting                     │
│      • expandSearch() — broaden search terms                    │
│      • synthesizeAnswer() — combine evidence                    │
│      • countPatterns() — find recurring themes                  │
│      • extractEntities() — pull names/dates/values              │
│      • compareDocuments() — cross-document analysis             │
│      • summarizeSection() — condense long passages              │
│                                                                 │
│   3. @Generable structs — structured JSON output                │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Why This Model + RAG Is Powerful

**Without RAG:** The 3B model can only answer from what it learned during training. Ask about your documents? It has no idea — it'll make stuff up.

**With RAG:** The model receives your actual document chunks as context. Now it's answering based on YOUR data, with citations, and we verify it didn't hallucinate.

```
Naked Model:        "What oil does my car need?" → Makes up an answer
Model + RAG:        "What oil does my car need?" → "SAE 0W-20 [Source: Owner's Manual, p.47]"
```

The model is the same. The difference is what you feed it.

---

## Summary

**The machine:** 5 gears (chunk → embed → retrieve → rank → generate)

**The modes:**

- Standard = run once
- Deep Think = run 4-8×, enrich each time
- Maximum = run 8-50× in parallel clusters, merge everything

**The constraint:** 4096 tokens. Everything exists because of this limit.

**The stitching:** RAGService and AgenticOrchestrator call 51 specialized services via async/await chains, each service doing one job, token budgets tracked at every step.

**The LLM:** Apple's ~3B on-device model with tool calling, guided generation, 30 tokens/sec, runs entirely on Neural Engine.

**The result:** A surgical extraction machine that finds the exact pieces needed to answer correctly, even with a tiny context window, using a compact but capable on-device model.
