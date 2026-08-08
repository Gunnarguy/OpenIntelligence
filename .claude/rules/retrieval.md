---
paths:
  - "OpenIntelligence/Services/RAG/Retrieval/**"
  - "OpenIntelligence/Services/RAG/Tuning/**"
  - "OpenIntelligence/Services/Query/**"
  - "OpenIntelligence/Services/Evaluation/**"
  - "OpenIntelligenceTests/Services/RAG/**"
---

# Retrieval changes

Route `retrieval_tuning_change`. Details in `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`.

**Same turn as the code change, not later:**
- `Docs/RETRIEVAL_PIPELINE.md`, including its Mermaid diagram if the flow moved.
- `CHANGELOG.md` under `[Unreleased]`, tagged `**[Retrieval]**`.
- Notion roadmap row, Component `Retrieval`, if this starts or finishes a tracked item.

**Tests:** the retrieval suites, then `bash scripts/build_simulator_smoke.sh`.

```bash
xcodebuild test -scheme OpenIntelligence -only-testing:OpenIntelligenceTests/HybridSearchServiceTests -only-testing:OpenIntelligenceTests/ContextPackingServiceTests
```

**Out of bounds here:** `SQLiteFullTextService.swift` and `BNNSVectorDatabase.swift`. Retrieval
tuning may read from them but may not change their schema or format.

## Two things this subsystem has already got wrong

**Column-aligned weight vectors.** `SQLiteFullTextService` ranks FTS5 hits with a positional weight
vector, one entry per declared column. The `chunks` table has nine columns and four call sites
passed eight weights, so every weight landed one column left of its target and `section_path` fell
out of ranking entirely. If you touch a weight vector, count the columns and pin the column list in
a comment beside it.

**Counts are not recall.** `RAGAuditSnapshot` reports how many candidates survived each stage. That
cannot answer whether the relevant chunk survived, which is the only thing recall asks. Use
`RetrievalTraceCollector` and `RetrievalStageMetrics` for that. Do not add another cardinality and
call it a quality measure.
