# Cross-Encoder Reranking and Core ML Reality - OpenIntelligence v4.1

This document verifies the implementation, pipeline, thresholds, and execution configurations of the reranking systems.

---

## 1. Does the current app have a cross-encoder reranking path?

**Yes.** The app has a fully implemented cross-encoder reranking path in `RAGEngine.swift` under the `rerank(...)` actor method. 
*   **Model Loading:** If `ReRankerModel` (.mlmodelc or .mlpackage) and its vocabulary (`reranker_vocab.json`) load successfully, the pipeline routes candidate chunks through `rerankWithCrossEncoder(...)`.
*   **Fallback Path:** If the model or tokenizer fails to load, it falls back to a multi-signal heuristic reranker.
*   **Asset Presence:** Both the `ReRankerModel.mlpackage` model and the `reranker_vocab.json` file exist in the source tree under `OpenIntelligence/Resources/MLModels/` and are built into the app targets.

---

## 2. What model is expected?

The app expects a TinyBERT cross-encoder model to compute similarity scores between the query and retrieved document chunks.

| Resource | Expected Name | Exists? | Target Member? | Copied to Bundle? | Required for Cross-Encoder? | Notes |
|---|---|:---:|:---:|:---:|:---:|---|
| **Compiled Model** | `ReRankerModel.mlmodelc` | Yes | Yes | Yes | Yes | Compiled by Xcode from the source `.mlpackage`. |
| **Source Model** | `ReRankerModel.mlpackage` | Yes | Yes | Yes | No (Fallback) | Used as a source fallback if `.mlmodelc` is missing. |
| **Tokenizer Vocab** | `reranker_vocab.json` | Yes | Yes | Yes | Yes | Decoded as `[String: Int]` vocabulary map. |

---

## 3. What happens if the model or tokenizer is missing?

If either resource is missing, the system catches the failure, logs a warning, and falls back to a multi-signal **heuristic reranker**. 

The fallback reranker computes a score for each chunk using the following parameters:
*   **Semantic Score:** Base similarity score computed by the first-pass vector database search.
*   **Keyword Match:** Boosts chunks containing exact keyword matches from the query (`keywordBoost * 0.25`).
*   **Term Proximity:** Boosts chunks where query terms appear close together (`proximityBoost * 0.20`).
*   **Metadata Boost:** Boosts based on matching specific document fields (such as digits or procedural cues like "step" or "how to").
*   **Table-of-Contents Penalty:** Penalizes chunks that look like index listings or table of contents to avoid dry references.
*   **Question-Bank Penalty:** Penalizes chunks that look like repetitive question lists.
*   **topK Truncation:** Returns the top-ranked chunks truncated to the requested `topK` count.

---

## 4. Is it truly on-device?

**Yes.** It is a native **on-device Core ML reranking** path.
*   It executes locally using the `MLModel` class loading resources from the app's local resource bundle.
*   It does **not** rely on network calls or Private Cloud Compute (PCC) for inference.
*   It configures `computeUnits = .all`, which allows the operating system to schedule inference tasks dynamically across CPU, GPU, or ANE (Apple Neural Engine) depending on device capability and heat. 

---

## 5. Is it Core AI?

**No.** The active reranker is implemented in `CoreML` and utilizes compiled `.mlmodelc` format. The files under the `CoreAI` namespace are stubs and scaffolding.

| System | Current Status | Safe Claim | Unsafe Claim |
|---|---|---|---|
| **Core ML Reranker** | `VERIFIED_SHIPPED` | Uses Core ML (`ReRankerModel`) to perform on-device reranking locally. | Rerankers are powered by Apple's Core AI framework. |
| **Core AI Scaffolding** | `SCAFFOLDED` | Experimental `CoreAI` stubs are staged in the codebase for future OS-level integrations. | Production reranker runs on Apple's Core AI framework today. |

---

## 6. Candidate-pool cutoff

The candidate pool size determines how many chunks are sent to the cross-encoder for reranking.
The exact formula used in `RAGEngine.swift` is:
```swift
let adaptiveCeiling = min(chunks.count, max(100, min(250, topK * 5)))
```

Here is the evaluation of candidate pool sizes under different conditions:

| Chunk Count | topK | Candidate Pool | Comment Matches Code? | Notes |
|---:|---:|---:|---:|---|
| 25 | 5 | 25 | Yes | All chunks used (25 < 100). |
| 50 | 10 | 50 | Yes | All chunks used (50 < 100). |
| 150 | 10 | 100 | **No** | Comment says "Small corpus (<200 chunks): use all chunks (no artificial ceiling)", but the formula cuts it off at 100, discarding 50 chunks. |
| 199 | 10 | 100 | **No** | Comment says "no artificial ceiling" for <200, but a ceiling of 100 is applied, discarding 99 chunks. |
| 200 | 10 | 100 | Yes | Outside "small corpus" definition; matches expected floor. |
| 500 | 10 | 100 | Yes | Cap at floor (100). |
| 500 | 20 | 100 | Yes | Cap at floor (100). |
| 5,000 | 10 | 100 | Yes | Cap at floor (100). |
| 5,000 | 50 | 250 | Yes | Cap at maximum ceiling (250). |

*Discrepancy:* There is a clear mismatch between the inline comments claiming that any corpus under 200 chunks skips the artificial ceiling and the actual mathematical formula. Under the current formula, if `chunks.count` is between 100 and 199 and `topK * 5` is less than `chunks.count`, the ceiling defaults to 100, which trims valid candidate chunks before they reach the cross-encoder.

---

## 7. Device-aware concurrency

*   **Calculation:** Concurrency is calculated in `RAGEngine.swift` at setup time:
    `let maxConcurrentPredictions = await min(4, max(2, DeviceCapabilityService.shared.embeddingConcurrency / 4))`
*   **Bounds:** Max concurrent predictions is capped at **4** and min is floored at **2**.
*   **Dependency:** It is directly proportional to `embeddingConcurrency` divided by 4.
*   **Tradeoff Managed:** Bounding concurrency prevents thread thrashing, thermal throttling, and memory overhead when allocating multiple high-dimensional `MLMultiArray` buffers concurrently.
*   **Benchmark Evidence:** Telemetry counters and log marks indicate that task groups process predictions concurrently in batches of 2 to 4.

---

## 8. What is the actual reranking pipeline?

The app's reranking pipeline runs as follows:
1.  **First-pass retrieval:** The system performs a hybrid search combining BM25 keyword matching and dense vector search, returning a raw list of candidate chunks.
2.  **Candidate pool selection:** It applies the adaptive ceiling formula to truncate the candidate list to a manageable pool (between 100 and 250 chunks).
3.  **Cross-encoder scoring:** If the Core ML model is loaded, it pairs the user query with each candidate chunk, tokenizes them, pads them to a sequence length of 512, and runs local inference to get a combined relevance score.
4.  **Heuristic scoring (Fallback):** If Core ML is missing, it calculates a heuristic score by combining semantic scores, term proximity boosts, metadata boosts, and table-of-contents or question-bank penalties.
5.  **Output truncation:** Chunks are sorted by their new reranked scores, and the top-ranked chunks are truncated to the requested `topK` count and sent downstream.

---

## 9. Safe wording for Vik / public conversation

### Concise LinkedIn Reply
> “I've implemented a Core ML cross-encoder reranking path locally in my Swift RAG engine. Keeping the candidate-pool ceiling adaptive is crucial to bound latency on older iOS devices. I use a multi-signal heuristic fallback when ML resources are missing.”

### Technical LinkedIn Reply
> “Running cross-encoders on-device presents a neat scheduling problem. In OpenIntelligence v4.1, I load a TinyBERT model through Core ML and throttle concurrency dynamically (between 2 and 4 concurrent predictions) based on hardware capability tiers to prevent GPU/Neural Engine thermal spikes. I'm especially interested in how people size the candidate pool before reranking.”

### DM Reply
> “Hey Vik! Thanks for the comment. On-device cross-encoders are definitely a constraint. In the v4.1 build, I compile the model directly into Xcode targets using `.mlpackage`. It runs entirely locally via Core ML. I also staged some Core AI scaffolding for future framework updates, though that's compiled out for now. Let me know if you want to chat more about the latency tradeoffs!”
