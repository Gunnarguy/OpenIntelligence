# Current State

Updated: 2026-08-07
Branch/worktree: main, primary checkout
Last verified commit: c8f9c5a

## Objective

Wire per-stage retrieval metrics into `RAGEvalRunner` so the harness produces a real retrieval
number. Commit `cb82471` landed the instrument and stated it was not yet wired in.

## Status

Uncommitted, not built, not tested. The plumbing is roughly two thirds threaded and the stage
recording is almost entirely missing.

Why this matters: `retrievalRecallAt5` has reported exactly `0.0` on every run regardless of
retrieval quality, because every case in `Benchmarks/rag_eval_v1.jsonl` carries
`groundTruthChunkIds: null` and the runner only scored recall when those were present. The `>= 0.85`
quality gate could never pass. This repository has never measured its own retrieval.

**Correction, 2026-08-07:** an earlier version of this file claimed `searchWithFTS5` recorded
nothing and that only `.final` was captured. That was wrong, produced by grepping the literal string
`trace?.record`, which misses the `trace.record` calls inside `if let trace {` blocks. Both paths
record five of six stages. Grep for `trace\??\.record` instead. The real gap is `.rerank` plus the
`queryWithAudit` threading.

## Completed

- `RetrievalTraceCollector.swift` (new, untracked). Six canonical stages: `vector`, `lexical`,
  `fusion`, `boosted`, `rerank`, `final`. `NSLock`-guarded, one instance per query, explicitly not a
  singleton or task-local because retrieval runs concurrent child tasks.
- `HybridSearchService`: `trace:` threaded into both `search` (line 202) and `searchWithFTS5`
  (line 881), forwarded between them, and **five of the six stages recorded in each path** —
  `.vector`, `.lexical`, `.fusion`, `.boosted`, `.final`. Ten record calls total, lines 283-295 and
  1075-1079. Both paths are instrumented, not just the fallback.
- `RetrievalStageMetrics.swift`: `RetrievalStageTrace` moved out to the new file, with a comment
  explaining the target-membership reason. `RetrievalStageEvaluator.score(traces:expectedSources:)`
  scores a query's stages and rolls them up.
- `RAGEvalRunner`: recall now falls back to `expectedCitations` matched through
  `RetrievalRelevanceJudge` when `groundTruthChunkIds` is absent. Citation precision rewritten to
  score over the distinct source documents actually retrieved, instead of asking whether the
  generated prose literally contained a filename and then returning a hardcoded `1.0` in both
  remaining branches. Abstention cases are left unscored rather than awarded `1.0`.
- Separately, and unrelated to the retrieval work: the Claude context system was installed,
  audited against its specification twice by independent agents, repaired, and **committed**
  (`ce01ccd`, `d702d41`, `cd3dd73`). The first audit checked 350 requirements and found 37 real
  gaps; the second tried to prove the repairs were overstated and found 25 more, including four
  blocking ones. All are closed. The defects worth remembering, because they are the shape of
  mistake this system is supposed to prevent: a clean-tree shell bug invisible to anyone testing on
  a dirty tree; a change-detection hash blind to rewrites of untracked files, which is every file
  the system itself ships as; SessionStart erasing its own baseline when compaction re-fired it;
  and a marker regex that read this changelog's own prose describing the marker. See
  [DECISIONS.md](DECISIONS.md).
- `repoos_router.py` version derivation fixed. It read `Docs/ROADMAP.md`'s outline heading `## 0.5`
  as a release and reported `v0.5` at `confidence: exact`, so every preflight's changelog,
  release-notes and Notion targets were wrong. Now derived from `CHANGELOG.md` alone and reported as
  `version` + `state` + `last_shipped`, with a `<!-- next-version: 5.0 -->` marker naming the target.
- Supabase and Docusign MCP connectors denied for this repository in `.claude/settings.local.json`,
  which is machine-local and gitignored so the connector ids are not published.
- `notion-roadmap` skill added. Claude Code never loads `.agents/workflows/`, so the roadmap recipe
  had been unreachable from Claude Code entirely; the version in `.agents/` also described the wrong
  call shape for the connected server, which takes SQL rather than filter objects.
- Notion roadmap synced. Two rows created, both Completed, `v5.0`, `General`:
  [agent directives](https://app.notion.com/p/3b549a74d54f8172a7f0c5d5b8db872b) and
  [preflight release defect](https://app.notion.com/p/3b549a74d54f815da331ecfa39ecca39). The row
  tracking this objective, *Retrieval benchmark harness over rag_eval_v1.jsonl*, is correctly
  `In Progress` for `v5.0` and was left alone.

## Active Constraints

- Placement and threading of the collector are fixed by target membership and call-site cost. Do
  not relitigate them; see [DECISIONS.md](DECISIONS.md) 2026-08-07 and
  [ARCHITECTURE.md](ARCHITECTURE.md) "Targets, and why it matters".
- Route `retrieval_tuning_change`. `Docs/RETRIEVAL_PIPELINE.md` and a `**[Retrieval]**` CHANGELOG
  entry are part of this task, not a follow-up.
- `SQLiteFullTextService.swift` and `BNNSVectorDatabase.swift` are out of bounds for this route.

## Working Set

- `OpenIntelligence/Services/RAG/Retrieval/RetrievalTraceCollector.swift`: the collector. Untracked.
- `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`: where stages must be recorded.
  `search` starts at 202, `searchWithFTS5` at 873.
- `OpenIntelligence/Services/Evaluation/RetrievalStageMetrics.swift`: the scorer.
- `OpenIntelligence/Services/Evaluation/RAGEvalRunner.swift`: the consumer, at `evaluate(case:ragService:)`.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift:8402`: `queryWithAudit`, the missing
  link. It takes no trace parameter and returns `(RAGResponse, RAGAuditSnapshot?)`.
- `Benchmarks/rag_eval_v1.jsonl`: 20 cases, all with `groundTruthChunkIds: null`, 18 with
  `expectedCitations` filenames.

## Verification

- Nothing in this changeset has been built or tested. No `xcodebuild` run, no simulator smoke run.
- `python3 scripts/secret_scan.py` -> passes, no sensitive tokens. Run 2026-08-07.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> **24 of 24
  pass**. Run 2026-08-07, after the version-derivation fix and its follow-up hardening. Was 11 of 14.
- Hook regression, 8 cases on a throwaway repo: unchanged tree, untracked file added, untracked file
  content rewritten, second call, STATE.md written, already-dirty file edited, `stop_hook_active`,
  and SessionStart re-firing on compaction without resetting the baseline. All pass.
- Preflight reports `v5.0`, state `in_development`, last shipped `v4.9`. Its unreleased-entry
  count matches `ci_post_clone.sh`'s shell count exactly; the number itself moves on every
  CHANGELOG edit, so it is deliberately not pinned here.
- Notion roadmap recipe verified by running the calls against the live database, not by reading docs.
- `.claude/hooks/session-start.sh` -> prints the brief, exits 0. Run 2026-08-07.

## Blockers / Unknowns

**Unknown: whether the Swift suite still passes.** `CHANGELOG.md` records `suite 173/173`
test-verified on 2026-08-07 across 22 test files, but that predates the uncommitted retrieval
changes in this tree and the suite has not been run since.
Verify: run the test command in [RUNBOOK.md](RUNBOOK.md).

## Exact Next Action

Record the `.rerank` stage in both search paths. It is the one canonical stage of the six that is
recorded nowhere, and it is the stage the whole exercise exists to measure: reranking cannot recover
a chunk the first stage never returned, so a per-stage report without it cannot attribute a
regression to the reranker.

In `search` the block at lines 283-286 records `.vector`, `.lexical`, `.fusion` and `.boosted`;
add `.rerank` with the cross-encoder's output. Same for `searchWithFTS5` at lines 1075-1079.

Then thread the collector through `RAGService.queryWithAudit`
(`Services/RAG/Orchestration/RAGService.swift:8402`), which currently takes no `trace` parameter and
returns `(RAGResponse, RAGAuditSnapshot?)`. That is the only remaining break in the chain:
`RAGEvalRunner` calls `queryWithAudit` and so has no way to receive a collector it constructs.

Then have `RAGEvalRunner.evaluate` build one collector per case, pass it down, and score
`collector.stages(inOrder:)` through `RetrievalStageEvaluator.score(traces:expectedSources:)`.

Then build (`bash scripts/build_simulator_smoke.sh`) and run the suite. Route
`retrieval_tuning_change` also requires `Docs/RETRIEVAL_PIPELINE.md` and a `**[Retrieval]**`
CHANGELOG entry in the same turn.
