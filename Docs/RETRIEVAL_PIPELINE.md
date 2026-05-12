# Retrieval Pipeline

The retrieval pipeline is the core engineering idea in OpenIntelligence: answers should be grounded in user-provided material and should expose the evidence that influenced them.

## Pipeline Stages

1. Import: files enter through Apple platform document workflows.
2. Extraction: text, layout, metadata, and media-derived text are extracted where supported.
3. Chunking: documents are split into retrievable units with metadata.
4. Indexing: chunks are written into local search and vector retrieval paths.
5. Query analysis: incoming questions are classified, scoped, and prepared for retrieval.
6. Retrieval: candidate chunks are selected from the active library or workspace.
7. Reranking and packing: evidence is scored, deduplicated, and packed into context.
8. Generation: the answer path uses retrieved evidence as the working context.
9. Verification: unsupported claims can be flagged, removed, or converted into an abstention.
10. Presentation: answers are shown with citations, quality indicators, and review affordances.

## Grounding Model

The prototype is biased toward grounded answers. If retrieved evidence is weak, contradictory, or missing, the app should show uncertainty rather than inventing a confident response.

The exact thresholds and heuristics are experimental and subject to change. The public value of the project is the architecture and behavior under iteration, not a claim that every answer is complete or correct.

## Library Isolation

Library and workspace boundaries are important because retrieval quality depends on scope. The app is designed so that a query can be answered against the user-selected document set rather than all files indiscriminately.

## Diagnostics

The repository includes diagnostic and telemetry surfaces for inspecting chunks, retrieval quality, answer details, and pipeline behavior. These are engineering tools for iteration and should not be interpreted as validation for regulated or safety-critical workflows.
