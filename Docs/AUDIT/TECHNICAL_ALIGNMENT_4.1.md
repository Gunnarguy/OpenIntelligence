# Technical Alignment Matrix - OpenIntelligence v4.1

---

## Executive Verdict

| Topic | Status | Confidence | Safe Public Claim | Unsafe Claim |
|---|---|---:|---|---|
| **Abstention path** | `VERIFIED_SHIPPED` | 100% | The RAG pipeline evaluates a set of critical safety gates and executes a dedicated abstention path if thresholds are not met. | The app guarantees 100% hallucination-free answers. |
| **Contradiction sweep** | `PARTIALLY_TRUE` | 100% | Flags explicit negation conflicts (e.g. "X is Y" vs. "X is not Y") in retrieved chunks and reduces confidence. | Detects and resolves all factual contradictions. |
| **Verification gates** | `VERIFIED_SHIPPED` | 100% | Employs 9 distinct verification gates (A–I) for structural safety. | All verification gates enforce strict blocking actions in all quality modes. |
| **Numeric sanity checks** | `VERIFIED_SHIPPED` | 100% | Cross-references response numbers against source documents to prevent numerical hallucinations. | Mathematically validates all arithmetic in source text. |
| **Evidence coverage** | `VERIFIED_SHIPPED` | 100% | Extracts and maps atomic response claims back to cited source chunks. | Guarantees all claims are fully covered by primary quotes. |
| **Semantic grounding** | `VERIFIED_SHIPPED` | 100% | Computes cosine similarity of response vs. chunk embeddings to verify concept alignment. | Prevents conceptual hallucinations through vector similarity. |
| **Cross-encoder reranking** | `VERIFIED_SHIPPED` | 95% | Re-ranks retrieval candidates on-device using a local TinyBERT model. | Reranker runs deep cross-encoders for all queries. |
| **On-device reranking** | `VERIFIED_SHIPPED` | 95% | Runs cross-encoder inference locally on Apple Silicon. | Runs reranking within Apple's hardware Secure Enclave. |
| **Core ML reranker** | `VERIFIED_SHIPPED` | 95% | Loads and runs `ReRankerModel` via Core ML framework. | Core ML is integrated with production Core AI libraries today. |
| **Core AI reranking** | `SCAFFOLDED` | 100% | Core AI execution pathways are stubs staged for future local model execution. | Production reranking is powered by Apple's Core AI framework today. |
| **Heuristic fallback reranking**| `VERIFIED_SHIPPED` | 100% | If Core ML fails to load, the system falls back to a multi-signal heuristic reranker. | Reranking crashes the app if the ML model is missing. |
| **Candidate-pool cutoff** | `VERIFIED_SHIPPED` | 100% | Bounds cross-encoder latency via an adaptive ceiling (100 to 250 chunks). | Reranker processes all retrieved chunks with no limit. |
| **Device-aware concurrency** | `VERIFIED_SHIPPED` | 100% | Bounds concurrent predictions (2 to 4) depending on device capability tier. | Runs unlimited concurrent prediction threads. |
| **PCC fallback** | `PARTIALLY_TRUE` | 100% | The route policy resolves PCC targets for deep reasoning queries, though the model session maps back to local execution. | Exclusively executes queries in secure remote PCC enclaves. |

---

## Technical Reality & Distinctions

1. **Abstention Mechanics:** The `shouldAbstain` flag is resolved by `VerificationGateService` based on critical failure in four gates: retrieval confidence, numeric sanity, semantic grounding, and domain isolation.
2. **Contradiction Sweep Limits:** The contradiction sweep (Gate D) is *not* a critical gate and does not force abstention. Furthermore, the detection logic is extremely conservative—only checking for explicit negation words (e.g. "not", "never") with a 7+ word overlap—meaning it cannot detect complex logical contradictions.
3. **Core ML vs. Core AI:** Reranking in the current production release uses a compiled Core ML model resource (`ReRankerModel.mlpackage`). The `CoreAI` namespace files (`CoreAIExecutionBackend.swift`, `CoreAIEmbeddingBackend.swift`) are empty stubs, and the `CoreAISentenceEmbeddingProvider.swift` is entirely disabled via `#if false`.
4. **PCC Integration:** While `FoundationModelRoutePolicy.swift` resolves routes to Private Cloud Compute (PCC), the current `EngineSDKCompatibility.swift` maps the `PrivateCloudComputeLanguageModel` initializer back to the local `SystemLanguageModel.default`. Hence, PCC routing is simulated locally in the current v4.1 build.
