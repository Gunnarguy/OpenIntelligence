> **Documentation status:** Verified for OpenIntelligence v4.4 on 2026-06-30.
> **Source of truth:** Codebase audit in `Docs/AUDIT/`.
> **Scope:** Describes shipped behavior unless explicitly labeled experimental, developer-only, or scaffolded.

# OpenIntelligence RAG Pipeline Evaluations

This document describes the formal evaluations framework implemented in OpenIntelligence. This framework is designed to validate the RAG pipeline's behavior, latency, and quality against the target quality gates defined in [WWDC26.md](file:///Users/gunnarhostetler/Documents/GitHub/OpenIntelligence/WWDC26.md).

---

## Quality Gates Target Metrics

The pipeline must satisfy the following metrics during an evaluation run:

| Metric | Target | Description |
| :--- | :--- | :--- |
| **Retrieval Recall@5** | $\ge 0.85$ | Fraction of ground-truth chunks appearing in top-5 retrieval results. |
| **Citation Precision** | $\ge 0.90$ | Fraction of cited sources in generated responses that are correct. |
| **Exact-value Accuracy** | $\ge 0.95$ | Fraction of exact-value queries answered correctly. |
| **Unsupported-claim Rate** | $\le 0.05$ | Fraction of generated responses containing unsupported claims (hallucinations). |
| **Correct Abstention Rate** | $\ge 0.85$ | Fraction of out-of-scope/adversarial queries correctly abstained. |
| **Context Overflow Rate** | $\le 0.02$ | Fraction of queries that hit context window limitations. |
| **Visual OCR Evidence Use** | $\ge 0.90$ | Fraction of visual queries utilizing OCR text. |

---

## Dataset Format (`.jsonl`)

Evaluation datasets are represented as JSON Lines files, with one JSON object per test case. Comments starting with `//` and blank lines are ignored.

### Example JSONL Case

```json
{
  "id": "exact-001",
  "query": "What is the engine oil capacity?",
  "expectedAnswer": "5.1 qt",
  "category": "exact_value",
  "groundTruthChunkIds": ["chunk-abc-123"],
  "expectedCitations": ["Manual.pdf"],
  "shouldAbstain": false
}
```

---

## Execution & Report Generation

To run evaluations programmatically:

```swift
let dataset = try RAGEvalDataset.load(from: datasetURL)
let runner = RAGEvalRunner()
let results = try await runner.run(dataset: dataset, ragService: ragService)
let metrics = RAGEvalMetrics.compute(from: results)

// Generate Markdown Report
let markdownReport = RAGEvalReportWriter.generateMarkdown(
    metrics: metrics,
    results: results,
    datasetName: dataset.name
)

// Generate JSON Report for CI/CD tracking
let jsonReport = try RAGEvalReportWriter.generateJSON(metrics: metrics, results: results)
```

---

## Apple Evaluations Framework Integration

The `AppleEvaluationsBridge` class provides compatibility with Apple's command-line tools and testing suites (`fm CLI`), allowing the evaluation runs to be analyzed natively on Apple platforms.

---

## Route Evidence Gates (Phase 9)

The metrics above score **answer** quality. `RouteEvalMetrics` scores **route honesty**: whether the `ModelExecutionReceipt` chain a run produced is internally consistent and fail-closed.

These gates exist because a route claim carries privacy consequences. A receipt that reports Private Cloud Compute for an answer that never left the device — or the reverse — is worse than no telemetry at all.

### Invariants

Every receipt is checked against six invariants. All are blocking: each one, if violated, makes route telemetry actively misleading rather than merely incomplete.

| Invariant | Guarantee |
| :--- | :--- |
| `completedTargetAttested` | A receipt may only claim a route that has a `.succeeded` attempt on that same route |
| `fallbackAttributed` | If `intendedTarget != completedTarget`, `fallbackReason` is set |
| `fallbackReasonRequiresDivergence` | If `intendedTarget == completedTarget`, `fallbackReason` is `nil` |
| `quotaFailClosed` | `.limitReached`, `.unsupported`, and `.unknown` quota states all block PCC attempts |
| `attemptChainPresent` | A non-abstaining receipt records how the answer was produced |
| `actualTargetAttempted` | The attempted route appears in the attempt chain |

`.unknown` is fail-closed deliberately: unrecognized SDK quota values map to `.unknown`, and an unrecognized state is not permission.

### Promotion Gates

| Gate | Target |
| :--- | :--- |
| Receipt integrity rate | $= 1.00$ |
| Unauthorized cloud attempts | $= 0$ |
| Unattested completions | $= 0$ |
| Unexplained fallbacks | $= 0$ |
| Receipts scored | $\ge 1$ |

An empty run **fails**. Absence of receipts is not evidence of correctness.

### Execution

```swift
let metrics = RouteEvalMetrics.compute(from: receipts)
guard metrics.meetsRouteGates else { /* inspect metrics.violations */ }
print(metrics.markdownSummary)   // paste into the evidence bundle
```

Alongside the gates, the type reports completion latency by route, PCC→on-device fallback counts, and fallback-reason distribution.

### Scope

Scoring is computable from receipts alone, so identical scoring applies to simulator, physical-device, and TestFlight runs. **This makes device evidence checkable; it does not substitute for it.** Producing receipts that represent real Private Cloud Compute execution still requires a signed device — see the `Validate:` items in the Notion engineering roadmap and `Docs/AUDIT/PCC_DYNAMIC_ROUTING_TEST_MATRIX.csv`.
