# Current State

Updated: 2026-08-15
Branch/worktree: main, primary checkout
Last verified commit: 067de44

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

Both halves of the owner's last instruction are addressed: **make the pre-generated suggested
questions good for any uploaded document**, which is done and committed, and **run a Deep Think
benchmark**, which is running now and is resumable.

## Status

Tree clean at `067de44`. **Four commits are unpushed, deliberately.** Do not push without asking:
pushing burns Xcode Cloud minutes and the owner asked for that to stop until the device work
settles.

**A Deep Think benchmark is running right now** and will still be running for hours. Do not start a
build, a test run, or any other heavy job against it without reading the Benchmark section below
first.

## Completed

**Suggested questions were written from bibliographies, tables of contents and running headers,
because nothing judged the passage.** `buildGroundedPassages` took `chunks.prefix(limit)` with no
quality test. All five filters already in `SuggestedQuestionsService` inspect the *generated
question*, and a reference list defeats every one of them at once: it is grammatical and dense with
capitalised nouns, so "What is the role of Neurosci Yagishita Transient?" is well formed and no
question-level test can separate it from a real question. `questionSourcePenalty` now scores the
source text and **demotes rather than filters**, so a document that is entirely a reference list
still produces suggestions instead of silently producing none.

**The hand-built samples were not enough, and saying so matters more than the fix.** The first
version passed all nine synthetic cases and still hard-demoted **51 chunks of ordinary body prose**
out of a 5,425-chunk sample of the real library. Two signals were wrong: a parenthetical year marks
an author-year citation *in running text* and so fired hardest on the related-work paragraph, and
loose author-initial matching caught "Detection DET." and "Twitter PHEME,". Author detection now
requires three consecutive `Surname AB,` entries **with distinct surnames**, which is also what
makes it safe outside academia, since "Section A, Section B, Section C" is ordinary content in a
manual or a lease. Final: 99.2% of real chunks score 0, zero falsely hard-demoted.

**Every suggestion could share one sentence frame.** `enforceDiversity` spread across documents but
never across phrasing, so four of seven could open "What is the role of". Capped per two-word frame
at `max(2, count / 3)`, with a third pass that ignores the cap so the count is still met.

**The generation prompt assumed every document was a research paper.** Its worked examples were all
"methodology", "the study", "limitations", so a lease or a recipe was steered toward questions about
findings it does not have. It now names document kind as the thing to match. Two em-dashes were also
removed from prompt string literals, because the model imitates the punctuation of its instructions
and can put one inside a user-visible question.

## Active Constraints

- **Do not push.** Four commits are waiting on the owner's word. Xcode Cloud usage.
- **No em-dashes anywhere**, including Swift string literals. Comments in existing files still carry
  them; leave those, but never add one.
- **`[Unreleased]` in `CHANGELOG.md` stays empty. New entries go under `## 5.0`.** v5.0 has **not**
  shipped; the App Store is on 4.9. `Docs/SHIPPED_VERSION.json` is the authority, and the preflight
  router reports this wrong.
- **A session instruction outranks prompt text.** This regressed suggested questions on 2026-08-14.
- **Do not run a build or test suite against a benchmark without checking its timeout first.** Doing
  exactly that on 2026-08-15 starved case 2 into a 600s timeout; the same case later completed in
  294.8s untouched.
- **Commits must not carry a `Co-Authored-By: Claude` trailer.**
- The pre-commit hook blocks a `.swift` change with no doc update. It is installed and active.

## Working Set

- `OpenIntelligence/Services/Query/UX/SuggestedQuestionsService.swift`. `hasAuthorListRun`,
  `questionSourcePenalty`, `rankChunksForQuestionGeneration`, `questionTemplateKey`,
  `enforceDiversity`, and the generation prompt near line 1282.
- `BenchmarkRuns/qasper-deepthink-20260815/results.jsonl`, the live checkpoint. One JSON object per
  case; the fields that matter are nested, `run.ok`, `run.error`, `score.correct`,
  `score.gold_recall`, `score.abstained`.
- `/private/tmp/qasper-deepthink2.log`, the running harness output.
- `/private/tmp/oi-library-backup-20260815-0109`, a 423MB copy of the owner's real library taken
  before the run. Delete it once the run is finished and the library is confirmed intact.
- `Docs/EVALS.md`, the single entry point for measurement. Read it before quoting any number.

## Verification

- `xcodebuild test` -> **236 tests, 0 failures, `** TEST SUCCEEDED **`**, run three times, once per
  commit, from `/private/tmp/oi-test-src`. `xcodebuild` deadlocks on this repository's own path; see
  `RUNBOOK.md` item 1b.
- `questionSourcePenalty` extracted verbatim from the committed source and run over a stratified
  5,425-chunk sample of `LocalCache/FTS5/fulltext.sqlite` -> 99.2% score 0, **zero** false hard
  demotions, while bibliography, numbered references, table of contents, running header and numeric
  table all still demote hard. Twelve hand-built samples hold their verdicts, including three
  label-list cases ("Section A, Section B, Section C") that the first version got wrong.
- The prompt change is **not device-verified**. No document-type spread has been run through it.

## Blockers / Unknowns

1. **The suggested-question prompt change has never run on device.** Compile-verified and
   suite-verified only. **Verification path:** upload a non-academic document, a manual or a lease
   or a recipe, and read the chips. That is the only thing that shows whether removing the
   paper-shaped exemplars helped or drifted.
2. **Deep Think scored `miss` on the first four benchmark cases.** Case 1 abstained with
   `gold_recall 0.5`; case 3 answered with `gold_recall 0.0`. Four cases is not a result, and the
   scorer's `patterns_hit` definition has not been audited against what Deep Think actually emits.
   Do not report a Deep Think quality number off this until the run is larger and that definition is
   checked.
3. **`getResearchDecision` and the title-routing turn still return empty responses, cause unknown.**
   Unchanged from the previous session. Contained, not fixed: both log a warning and keep the
   existing answer. Apple reports no error, `generatedTokenCount` 21 to 49, `deltasCount: 2`.
   **Verification path:** commit `2016394` logs the partial streamed text, so run one Deep Think
   query and read `grep -A7 "Non-GenerationError escaped" <device-log>`.
4. **`doc_pack_addon` does not load from StoreKit.** Revenue affecting, untouched.
5. **The fusion weight must not be set to one global value.** See `Docs/RETRIEVAL_PIPELINE.md` 16.

## Benchmark in flight

83 QASPER cases, Deep Think only, `--pcc deny --pool-limit 10 --timeout 1500`, against the macOS
Debug build at `/private/tmp/oi-mac-nosbx`. Cases run 250 to 400 seconds each, so the full set needs
roughly 8 hours from 01:23. It writes `results.jsonl` incrementally and **is resumable**:

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes deep-think --pcc deny --pool-limit 10 --reset-shared-library --timeout 1500 --resume BenchmarkRuns/qasper-deepthink-20260815
```

`--resume` skips any `(case_id, mode)` already in `results.jsonl`, **including rows that failed**, so
delete a row where `run.ok` is false before resuming or that case is never retried. `--timeout` is
not recorded in `run_config.json` and so may be changed on resume; every other parameter must match
or the harness refuses to merge two configurations into one file.

## Exact Next Action

**Read the benchmark checkpoint and decide whether the run is worth continuing**, before anything
else, because it is holding the machine:

```bash
python3 -c "import json;rs=[json.loads(l) for l in open('BenchmarkRuns/qasper-deepthink-20260815/results.jsonl')];print(len(rs),'cases;',sum(1 for r in rs if r['score'].get('correct')),'correct;',sum(1 for r in rs if r['score'].get('abstained')),'abstained')"
```

If Deep Think is still near zero correct after 20 or more cases, stop the run and audit the scorer
against one full answer before spending the rest of the night on it. `score.gold_recall` above zero
with `correct` false means retrieval found the evidence and the scorer or the answer is at fault,
which is a different bug from retrieval missing.

Then, when the owner is available, take Blocker 1: put a manual or a lease through the app and look
at the suggested questions. That is the only part of tonight's work that no test covers.
