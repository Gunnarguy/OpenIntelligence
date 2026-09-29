# OpenIntelligence RAG Quality Baseline

This document captures the RAG quality gates and evaluation framework baselines for the codebase.

## Target Quality Gates
Per `Docs/EVALS.md`, the pipeline is evaluated against these target quality thresholds:

| Metric | Target Threshold | Scope / Description |
| :--- | :--- | :--- |
| **Retrieval Recall@5** | $\ge 0.85$ | Fraction of ground-truth chunks appearing in top-5 retrieval results. |
| **Citation Precision** | $\ge 0.90$ | Fraction of cited sources in generated responses that are correct. |
| **Exact-value Accuracy** | $\ge 0.95$ | Fraction of exact-value queries answered correctly. |
| **Unsupported-claim Rate** | $\le 0.05$ | Fraction of generated responses containing unsupported claims (hallucinations). |
| **Correct Abstention Rate** | $\ge 0.85$ | Fraction of out-of-scope/adversarial queries correctly abstained. |
| **Context Overflow Rate** | $\le 0.02$ | Fraction of queries that hit context window limitations. |
| **Visual OCR Evidence Use** | $\ge 0.90$ | Fraction of visual queries utilizing OCR text. |

## Baseline Assessment
*   **IMPORTANT (label correction, 2026-07-13):** The table above contains **target thresholds copied from `Docs/EVALS.md`**, not measured results. Its correct tag is `[evidence_level: doc_claim_only, confidence: high]`. **No measured RAG baseline exists.**
*   **Evaluation Engine status:** Active. The `AppleEvaluationsBridge` and `QualityAssuranceService` actors are compiled into the `OpenIntelligenceEngine` target. `[evidence_level: code_verified, confidence: exact]`
*   **Evaluation Datasets:** Format is JSON Lines (`.jsonl`), storing query, expected answer, expected citations, and shouldAbstain conditions.
*   **Test Run Status:** No active evaluations run in this read-only phase. Pure unit tests for scoring are unavailable as the test target is deleted.
*   **Lenient Retrieval Toggle:** Settings store supports `lenientRetrievalMode` and `developerRAGTuningEnabled` to dynamically adapt thresholds. `[evidence_level: code_verified, confidence: exact]`

## Baseline Establishment — REQUIRED BEFORE ANY RAG SEMANTIC CHANGE
The measured baseline (fixed versioned corpus; repeated runs for variance bounds; noninferiority margins fixed **before** observing any post-change result) does not exist. It gates integration of #53, #56 (reopen only), #59, #62, #63, #64, #68. If the benchmark cannot be run end-to-end, the rework stays unimplemented and `OWNER_ACTION_REQUIRED` is recorded — aggregate metrics alone are insufficient; every individual changed case must be listed. `[evidence_level: code_verified (absence), confidence: exact]`
