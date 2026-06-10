# Retrieval Pipeline

The retrieval pipeline is the core engineering idea in OpenIntelligence: answers should be grounded in user-provided material and should expose the evidence that influenced them.

## Pipeline Stages

1. **Import**: Files enter through Apple platform document workflows.
2. **Extraction**: Text, layout, metadata, and media-derived text are extracted where supported.
3. **Chunking**: Documents are split into retrievable units with metadata.
4. **Indexing**: Chunks are written into local search (SQLite FTS5) and vector retrieval (BNNSVectorDatabase) paths.
5. **Query Analysis & Planning**: Incoming questions are classified, scoped, and prepared for retrieval.
6. **Retrieval**: Candidate chunks are selected from the active library or workspace.
7. **Reranking and Packing**: Evidence is scored using local TinyBERT cross-encoders, deduplicated (MMR), expanded with parent sibling context, and compressed to fit context budgets.
8. **Dynamic Model Routing & Generation**: The answer path resolves the optimal execution route (On-Device up to 4K tokens, or secure Private Cloud Compute up to 32K tokens) and generates responses using native `LanguageModelSession` API.
9. **Fidelity Verification**: Generated responses are audited through **Verification Gates A–I** (anti-hallucination, completeness, domain isolation) to detect ungrounded claims.
10. **Presentation**: Answers are shown with liquid glass UI indicators, citations, quality gauges, and review affordances.
11. **Continuous Evaluation**: Pipeline stages are run against JSONL benchmarks and verified against quality gates (e.g. Recall@5 $\ge 0.85$, Citation Precision $\ge 0.90$) using the native Evaluations harness.

## Grounding Model

The prototype is biased toward grounded answers. If retrieved evidence is weak, contradictory, or missing, the app should show uncertainty rather than inventing a confident response.

The exact thresholds and heuristics are experimental and subject to change. The public value of the project is the architecture and behavior under iteration, not a claim that every answer is complete or correct.

## Library Isolation

Library and workspace boundaries are important because retrieval quality depends on scope. The app is designed so that a query can be answered against the user-selected document set rather than all files indiscriminately.

## Diagnostics

The repository includes diagnostic and telemetry surfaces for inspecting chunks, retrieval quality, answer details, and pipeline behavior. These are engineering tools for iteration and should not be interpreted as validation for regulated or safety-critical workflows.
