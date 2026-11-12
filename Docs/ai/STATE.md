# Current State

Updated: 2026-11-11 about 17:30 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 41b3b727

## Objective

**Ship 5.8** (owner, 2026-11-10: "I feel like I should ship 5.8"). The board is 5.8 and Future Backlog only. What
remains: tonight's answer benchmark (the owner starts it), the owner's short device pass, then a Xcode Cloud build
and the App Store Connect submission at his word. Every commit carries `[ci skip]` until he asks for a build.

## Tonight (2026-11-11): the answer benchmark, one command

The owner runs it when he stops gaming. It waits by itself while World of Warcraft or League of Legends is open.

```bash
bash scripts/bench_answer_modes.sh
```

It copies HEAD out of the repo, patches the copy with `scripts/sim_model_copy.py` (the app's own model service on
in the Simulator, so the engine takes the phone's path), builds once at two jobs, makes a fresh simulator
("OI answer eval", iPhone 17 Pro, iOS 27.0), and runs `AnswerQualityEvaluationTests` (20 cases, Apple's Evaluations
model judge) in Standard, Deep Think and Maximum with the app's service, then Standard with the test's own model (the
path of the 2026-10-21 runs, 0.3, for comparison). Output: `BenchmarkRuns/<date>-answer-modes/SUMMARY.md`, plus a
`.txt` per mode with each question's seconds and answer. Expect hours: the first build is a full one, a Deep Think
answer took 279 s on his phone (2026-08-18), Maximum runs up to 50 sessions.

**Morning, the next session:** read `SUMMARY.md` and the `.txt` files. A refused or empty answer is a finding; a
mode that scores below Standard is the headline (Deep Think was 2/8 and 3/8 against Standard's 4/7 and 5/8 on QASPER
in August, `BenchmarkRuns/LEDGER.md`). Record the run in `LEDGER.md`. Nothing about Maximum's answers has ever been
graded before this run.

**Not verified yet:** the patched copy and the new test settings have not been built (the owner was gaming;
nothing heavy ran on his Mac). Cloud run 499 builds the test change unpatched; if `SUMMARY.md` says the build
failed, `build.log` in the run folder names the line. The four switches `sim_model_copy.py` turns off are
`#if targetEnvironment(simulator)` blocks whose other branch is the device code.

## Done today (2026-11-11)

- **Where each test can run, settled.** Xcode Cloud simulators cannot generate (`ModelManagerError 1019`, run 496);
  the Mac's iOS 27 Simulator can. `testing-routes` skill; `scripts/xcloud.py` (start, watch `--against`, logs, list).
- **The full suite on Xcode Cloud is green for the first time**: run 498 at 7774d508, 1,683 passed on each of three
  simulators. Five defects it found are fixed (csv table citations, rows on one line, table keywords' codes,
  watched-folder note, X-Ray tip length). Baseline for later runs: 498.
- **Development build of 41b3b727 on his iPhone 16 Pro Max**, installed about 17:00 (not launched).
- **The answer test now measures the app's own path** (`OI_EVAL_MODEL=app`, `OI_EVAL_MODE`). Until today it gave
  the engine the test's own model, and 17 places in the engine branch on `llmService is AppleFoundationLLMService`.

## Active Constraints

- `PROCEED: IMPLEMENT` before source edits; hard-boundary files only when he names them.
- Accuracy first: anything that changes what is read or retrieved is measured on every benchmark set before it ships.
- Never load his Mac while he games. Long jobs go to Xcode Cloud (`scripts/xcloud.py`) or wait for his word.
- One `xcodebuild` at a time; device builds from `/private/tmp/oi-src` into `/private/tmp/oi-build`.

## Working Set

- `scripts/bench_answer_modes.sh`, `scripts/sim_model_copy.py`: tonight's run.
- `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift`: the graded test and its settings.
- `scripts/xcloud.py`, `.claude/skills/testing-routes/SKILL.md`: the cloud route and where every kind of run goes.
- `Benchmarks/rag_eval_v1.jsonl` and `Benchmarks/ResearchFixtures/tiny_research_suite/`: the 20 cases.

## Verification

- `zsh -ic 'python3 scripts/xcloud.py watch 498 --against 497'` -> run 498 SUCCEEDED, 1,683 passed per device, 6 fixed, 0 newly failing.
- `xcrun devicectl device install app --device B1483F12-4FFD-5534-BA30-29FF48070549 ...` -> "App installed" (the UDID form failed with 0xE8000112 the same minute).
- `python3 scripts/sim_model_copy.py /private/tmp/oi-eval-src` -> "patched 4"; on the repository path -> refused.
- `bash -n scripts/bench_answer_modes.sh` -> no syntax errors. Not run end to end.

## Blockers / Unknowns

- **Compute profiles' retrieval side is unmeasured**: QASPER 246 and tables 158 per profile, and the fusion fix with
  and without `OI_RETRIEVAL_ABLATE=fusionScoreOrder`. The extraction side was measured 2026-11-11: identical text across
  Balanced, Performance and Maximum (`LEDGER.md`).
- **Retrieval findings from 2026-11-10, not fixed:** Standard rewrites queries although `RAGQualityMode.usesQueryRewriting`
  is false for it (the `enableQueryRewriting` setting defaults to true and wins, `SettingsStore:561`,
  `RAGService+QueryPreparation.swift:292`); HyDE, contextual compression, extractive summarization and the entity index
  have no live call; `maxRetrievalIterations`, `iterativeRetrievalConfig`, `benefitsFromSummaries`,
  `preferSummariesForOverview`, `specificationBoostWeight`, `maxChunksPerSearchYield` have no consumer.
- `ShortcutsActionTests.testAskAboutADocumentRestsOnlyOnThatDocument` failed once (run 497, 1 of 3, no message): flaky.
- Device checks not done: Device & Performance and Intelligence Mode on the phone, Deep Think leave-and-return, X-Ray
  on the chip, setup card on a fresh install. The `device-pass` skill holds the short pass.
- Notion: rows for Maximum, the hazard-ratio fix, the Deep Think cut-off and today's five fixes are not filed.

## Exact Next Action

Read `BenchmarkRuns/<the newest date>-answer-modes/SUMMARY.md`. If it holds scores, record them in
`BenchmarkRuns/LEDGER.md` with the commit and compare each mode with Standard; if the build failed, read the end of
`build.log` in the same folder, fix the switch or test line it names, and tell the owner the run needs one more night.
