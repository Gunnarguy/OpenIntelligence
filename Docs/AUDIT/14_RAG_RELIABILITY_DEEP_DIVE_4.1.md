# RAG Reliability Deep Dive - OpenIntelligence v4.1

This document provides a detailed technical analysis of the RAG safety layers, focusing on the abstention path and contradiction sweeps.

---

## Part 1: Abstention Path Deep Dive

### 1. Where is abstention represented in code?
*   **Verification Gate Level:** [VerificationGateService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L241-L260) determines `shouldAbstain` inside the `verify(...)` method.
*   **Safety Service Level:** [SourceOnlyAnswerService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift#L324-L347) evaluates outcomes, checks for critical claim failures or below-threshold fidelity, and resolves the final `shouldAbstain` flag.
*   **Orchestration Level:** [RAGService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Orchestration/RAGService.swift) intercepts the outcome and routes the session to return the refuse state if `shouldAbstain` is true.

### 2. What type or result object carries abstention state?
*   `RAGVerificationResult` (defined in `VerificationGateService.swift`):
    *   `let shouldAbstain: Bool`
    *   `let abstainReason: String?`
*   `SourceOnlyAnswerOutcome` (defined in `SourceOnlyAnswerService.swift`):
    *   `let shouldAbstain: Bool`
    *   `let abstentionReason: String?`
*   `StructuredAnswer` (passed downstream):
    *   Fidelity scores and refusal markers (e.g. `.setRefuse(shouldAbstain)`).

### 3. What gates can trigger abstention?
Abstention is triggered exclusively by failures in the **critical gates** set:
1.  **Gate A:** Retrieval Confidence (`.retrievalConfidence`)
2.  **Gate C:** Numeric Sanity (`.numericSanity`)
3.  **Gate E:** Semantic Grounding (`.semanticGrounding`)
4.  **Gate I:** Domain Isolation (`.domainIsolation`)

### 4. What counts as a critical failure?
A critical failure is defined as any of the following:
*   **Low Retrieval Score:** Gate A fails because the top retrieval similarity is below `tau` (0.40 normal, 0.55 touchy).
*   **Numeric Discrepancy:** Gate C fails because numbers/numerical tokens present in the generated response do not appear in any candidate source chunks.
*   **Semantic Drift (Ungroundedness):** Gate E fails because the cosine similarity between the response embedding and all source chunk embeddings falls below the grounding threshold (0.50 normal, 0.60 strict), or falls below the 0.85 ratio threshold compared to the query's similarity.
*   **Scientific Domain Mismatch:** Gate I fails because domain isolation blocks mixed-domain evidence.

### 5. Is abstention actually used downstream in the user-facing answer path?
Yes. If `shouldAbstain` is flagged during claim evaluation, `SourceOnlyAnswerService.verifyAndRender(...)` intercepts this and replaces the generated LLM text with a standardized refusal string using `buildAbstentionText(reason:)`.

### 6. Does the UI show abstention or warning state?
Yes. 
*   **Refusal Display:** The UI displays the standardized refusal text.
*   **Quality & Fidelity Alerts:** [AnswerIntelligenceView.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Features/Chat/Response/AnswerIntelligenceView.swift) and [SourceFidelityStatus.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Features/Chat/Response/SourceFidelityStatus.swift) parse gate results. If any non-critical gates fail, the UI shows warnings and reduced confidence scores to the user.

### 7. Are there cases where verification fails but the answer still displays?
Yes. If only non-critical gates fail (such as Gate B: Evidence Coverage, Gate D: Contradiction Sweep, Gate F: Quote Faithfulness, Gate G: Generation Quality, or Gate H: Answer Completeness), the overall verification passes `passed = false` but `shouldAbstain` remains `false`. The response is displayed alongside quality warnings.

### 8. Is abstention only internal logging, or does it affect final response behavior?
It directly governs response behavior. It overrides the model's generated text with a refusal when a critical check fails.

### 9. What exact wording is safe to use publicly?
*   **Safe:** "The app includes verification gates and abstention paths when retrieved evidence is too weak."
*   **Safe:** "The system is designed to avoid unsupported answers when critical verification gates fail."
*   **Unsafe:** "The app guarantees no hallucinations."
*   **Unsafe:** "Every answer is always fully verified."

---

### Abstention Runtime Path

| Step | File | Symbol | Evidence | Runtime Status | Notes |
|---|---|---|---|---|---|
| 1. User Query | `ChatScreen.swift` | `sendMessage` | Captures user request | Active | Triggers the RAG cycle. |
| 2. Retrieval | `IterativeRetrievalService.swift` | `retrieve` | BM25 + Vector Search | Active | Gathers candidates. |
| 3. Generation | `LLMService.swift` | `generateAnswer` | Generates candidate answer text | Active | Outputs draft text. |
| 4. Verification | `VerificationGateService.swift` | `verify` | Runs Gates A to I | Active | Calculates gate failures and `shouldAbstain`. |
| 5. Evaluation | `SourceOnlyAnswerService.swift` | `verifyAndRender` | Checks `shouldAbstain` | Active | Evaluates fidelity scores. |
| 6. Refusal / Render | `SourceOnlyAnswerService.swift` | `buildAbstentionText` | Substitutes refusal text | Active | Formats final output. |
| 7. UI Display | `AnswerIntelligenceView.swift` | `body` | Renders Refusal / Warnings | Active | Displays results to user. |

---

## Part 2: Contradiction Sweep Deep Dive

### 1. Where is contradiction checking implemented?
Contradiction checking is performed in [VerificationGateService.swift](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L472-L497) within `runGateD(response:chunks:)`, which invokes the helper [detectContradictions(in:)](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L1441-L1494).

### 2. What function performs contradiction detection?
`private func detectContradictions(in chunks: [RetrievedChunk]) -> [String]`

### 3. What signals does it use?
*   A hardcoded array of negation indicators: `["not", "never", "no longer", "unlike", "instead of", "rather than", "contrary to"]`.
*   A requirement for a high word-overlap (7 or more matching terms with length > 5) between the negated chunk and positive chunk.

### 4. Does it compare factual values, semantic claims, keywords, or heuristic contradiction indicators?
It uses a heuristic keyword-overlap approach with negation scanning. It does **not** evaluate factual values or semantic meanings. In fact, numeric comparison logic was **intentionally removed** to avoid flagging differing technical specifications as contradictions.

### 5. Does contradiction detection fail the answer, reduce confidence, create warning metadata, or force abstention?
*   It does **not** force abstention (Gate D is non-critical).
*   It **reduces confidence score** by a factor of `0.2` per contradiction (down to a floor of `0.3`).
*   It fails Gate D itself if the resulting confidence falls below `0.5` (i.e., 3 or more contradictions detected), triggering warning metadata in the UI, but the generated answer still displays.

### 6. How strong is the implementation?
It is extremely basic. It functions as a lexical pattern-matcher for immediate sentence-level negations. It lacks deep semantic comprehension or formal logical proof capabilities.

### 7. What are its known limitations?
*   Cannot detect semantic contradictions without explicit negation words (e.g. "X increases blood pressure" vs. "X lowers blood pressure" is missed).
*   Ignores numeric discrepancies because numeric analysis was deleted.
*   Prone to high false-negative rates on complex texts.

### 8. Is it user-visible?
Only indirectly, appearing as lower confidence metrics or warning annotations in the response diagnostic views.

### 9. Is "contradiction sweep" a fair phrase?
Only when qualified. It is a lexical negation scanner, not a semantic or logical reasoning engine.

---

### Verification/Contradiction Questions & Answers

| Question | Answer | Evidence | Confidence |
|---|---|---|---:|
| Where is contradiction checking? | `VerificationGateService.swift` in `runGateD` | [VerificationGateService.swift:L472-L497](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L472-L497) | 100% |
| What triggers the sweep? | Scanning retrieved chunks during the verification pipeline | [VerificationGateService.swift:L193-L196](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L193-L196) | 100% |
| Does it prevent answer display? | No, Gate D is non-critical | [VerificationGateService.swift:L241-L243](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L241-L243) | 100% |
| Does it analyze numbers? | No, numeric comparison logic was removed | [VerificationGateService.swift:L1489-L1491](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence-Public/OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift#L1489-L1491) | 100% |

---

## Owner Explanations & Communication Wording

### Safe Explanation for the Owner
The app includes a safety check that runs when generating answers. If the search results are poor, or if the generated answer contains numbers or statements that cannot be verified in your documents, the app enters an "abstention path" and refuses to answer rather than making things up. Additionally, the system scans search results for explicit contradictions (like "X is safe" vs. "X is not safe") and lowers its confidence rating if any are found, though basic contradictions won't block the answer from showing.

### Safe Public Wording
*   “The verification layer includes a contradiction sweep that flags conflicting retrieved evidence and lowers confidence when conflicts are detected.”
*   “The app includes verification gates and abstention paths when retrieved evidence is too weak.”

### Unsafe Public Wording
*   “The app guarantees no hallucinations.”
*   “The app fully resolves contradictions.”
*   “The app performs formal logical contradiction proof.”
