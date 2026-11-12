# Current State

Updated: 2026-11-12 about 02:30 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 02044980

## Objective

**Ship 5.8** (owner, 2026-11-10: "I feel like I should ship 5.8"). The board is 5.8 and Future Backlog only. What
remains: the owner's short device pass, then a Xcode Cloud build and
the App Store Connect submission at his word. Every commit carries `[ci skip]` until he asks for a build.

## Status

- **Answer benchmark, first run (2026-11-12 00:53, c1e4a160)**, `BenchmarkRuns/2026-11-12-0053-answer-modes/`,
  recorded in `BenchmarkRuns/LEDGER.md`: Standard 0.45, Deep Think 0.40 (3.8 times the time), Standard with the test's
  own model 0.50 (0.3 on 2026-10-21). 20 cases, one case is 0.05. Maximum was not measured: the free plan's 3-a-day
  limit refused 17 of 20 because the plan the gate reads had gone back to Free; the test now sets Pro and a zero count
  before every Maximum question (02044980).
- **Maximum re-run alone** (02044980, `BenchmarkRuns/2026-11-12-0223-answer-modes/`): 0.50, 20 answered, 0 refused,
  31 minutes; 8 answers open with "Needs Verification". Recorded in `LEDGER.md`.
- **Development build of 02044980 on his iPhone 16 Pro Max**, installed 02:23 PT 2026-11-12, not launched.

## Completed (2026-11-12)

- Read the phone's journal and trace from his three Standard questions (47.8, 24.5, 36.6 s): the first waited on the
  reranker's 35.8 s load; evidence in `~/Library/Developer/OpenIntelligence-evidence/2026-11-12_005528/`.
- Journal fixes, approved by the owner ("yep fix ALL of that"), 02044980: `model.usage` times (`firstTokenMs`,
  `writingMs`, `outputPerSecond`, `totalMs`, `cachedInput`, `continued`); `embedding.load` timed; `reranker.load` and
  `embedding.load` carry `newInstall` and `fastPrediction`; the stall watchdog counts only time in front (a 296,980 ms
  "stall" was a suspension). A reviewer pass found 14 points; all addressed, and the launch-time embedder load I had
  added was reverted because the Core ML embedder's on-first-use design is out of bounds without the owner's say.

## Active Constraints

- `PROCEED: IMPLEMENT` before source edits; hard-boundary files only when he names them.
- Accuracy first: anything that changes what is read, retrieved or answered is measured on every benchmark set first.
- Never load his Mac while he games. One `xcodebuild` at a time; device builds from `/private/tmp/oi-src` into
  `/private/tmp/oi-build`.

## Working Set

- `scripts/bench_answer_modes.sh`, `scripts/sim_model_copy.py`, `OpenIntelligenceTests/Services/Evaluation/AnswerQualityEvaluationTests.swift`.
- `OpenIntelligence/Services/Infrastructure/Configuration/VerificationJournal.swift` (watchdog, `firstLaunchOfThisInstall`).
- `OpenIntelligence/Services/LLM/AppleFoundationLLMService.swift` (`phaseFields`, `model.usage`).
- `OpenIntelligence/Services/RAG/Orchestration/RAGService+QueryAnswer.swift` (`retryForMissingCitations`): the open citation finding.

## Verification

- `bash scripts/bench_answer_modes.sh` (c1e4a160) -> the table above, `SUMMARY.md` in `BenchmarkRuns/2026-11-12-0053-answer-modes/`.
- `xcodebuild build-for-testing` + `test-without-building -only-testing:OpenIntelligenceTests/VerificationJournalTests
  -only-testing:OpenIntelligenceTests/ModelCallPhaseFieldsTests -only-testing:OpenIntelligenceTests/AnswerUsageTallyTests`
  on a fresh iOS 27.0 simulator -> 21 tests, 0 failures (working tree = 02044980).
- iPhone build `-configuration Debug -destination generic/platform=iOS` -> exit 0; `devicectl device info apps` -> 5.8 (150).
- Not built for macOS: the watchdog's `#else _ = started` branch is compiled only there.

## Blockers / Unknowns

- **Standard answers without inline citations:** 8 of 28 Standard answers on his iPhone since 2026-11-07 had no
  `[n]` markers ("Missing citations; preserving streamed response"), 0 of the Deep Think answers. Every Standard
  answer there skipped structured generation for its token budget (4,096 window). A fix changes answers, so it needs
  measuring; not filed in Notion yet.
- **Reranker load on the iPhone:** 20 to 130 s on most launches of 2026-11-10 and 11-11; three matched installs at
  the same minute. The new `newInstall` field settles the rest: a slow `reranker.load` with `newInstall: false` is a
  defect.
- **Loading the Core ML embedder after launch** (so a first question does not load it) is the owner's call: it reverses
  the deliberate on-first-use design in `CoreMLSentenceEmbeddingProvider` (43 MiB, August launch hangs).
- Compute profiles' retrieval side is unmeasured (QASPER 246, tables 158 per profile, the fusion ablation).
- Retrieval findings from 2026-11-10, not fixed: Standard rewrites queries though `usesQueryRewriting` is false for it;
  HyDE, contextual compression, extractive summarization and the entity index have no live call.
- Device checks not done (the `device-pass` skill). Notion rows not filed for Maximum, the hazard-ratio fix, the Deep
  Think cut-off, the 2026-11-11 fixes, or the citation finding.

## Exact Next Action

Show the owner the 2026-11-12 answer scores (Standard 0.45, Deep Think 0.40, Maximum 0.50, Standard with the test's
model 0.50, `BenchmarkRuns/LEDGER.md` last entry) and ask whether 5.8 waits on the citation finding or ships with it in
Future Backlog; then file the Notion rows listed under Blockers (`notion-roadmap` skill).
