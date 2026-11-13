# Current State

Updated: 2026-11-13 about 13:30 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 75243fb7

## Objective

**Ship 5.8 with every change since 5.7 measured and described truthfully.** The owner asked on 2026-11-13 for 5.8 to be
"genuinely ready to be pushed to the App Store". Submission (Xcode Cloud build, App Store Connect, ticking "Reset
rating when this version is released", `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15) is his, at his word.
Every commit since 2026-11-02 carries `[ci skip]`; nothing is pushed.

## Release gate: what still blocks submission

1. **Three answer changes are on in the build and unmeasured** (`RetrievalAblation`: release builds turn nothing off):
   `answerFirst` (Deep Think opens with the answer, a1b67367), `maximumSourcePassages` (Maximum reads source passages,
   a8ee4986), `draftAbstainNeedsFailedClaim` (9ed8c3da). Each is kept only if its paired run shows no drop, else
   switched off before submission. Their user text is not written yet; it goes in with the decision. The CHANGELOG
   entries say "behind ... until measured".
2. **Paired reruns in progress** on 7cac2076, one Simulator at a time: `bash BenchmarkRuns/2026-11-13-answer-first/run.sh all`
   then `.../2026-11-13-maximum-passages/run.sh all` (background job started about 13:05). Before reading any score:
   `grep -c '\[QuotesOnly\]' answers.log` must be 0 (the benchmark now stops at once if Quotes only is selected).
3. **draftAbstain** has no run yet: the 20-case answer test, rule-scored (`scripts/score_answer_eval.py`), with
   `TEST_RUNNER_OI_RETRIEVAL_ABLATE=draftAbstainNeedsFailedClaim` off against on (`scripts/bench_answer_modes.sh` has
   no ablation passthrough yet).
4. **Granite against MiniLM on the 158 table questions**: MiniLM done (`BenchmarkRuns/2026-11-12-full-suite/reach-minilm.json`);
   Granite's run died at 143 of 158 in the 12:06 Simulator crash and must rerun alone (about 4 h,
   `PHASES=embedder` part of `BenchmarkRuns/2026-11-12-full-suite/run_all.sh`).
5. **5.7 against 5.8 answer quality by rule**: the LEDGER's judge-graded table is withdrawn (judge agreed with a plain
   reading on 8 of 20); both versions need a rerun with result bundles kept, then `score_answer_eval.py`.

Not a gate: the device pass (127 v5.8 rows In Progress wait on a phone or Mac check; `device-pass` skill, at most 5
phone and 7 Mac steps).

## Done 2026-11-13 (all committed)

| What | Commit |
|---|---|
| Apple's model reconnects when ready after launch | 98582397 |
| Launch-picked Quotes only lifted when the model is ready | 09e29487 |
| The launch recorded its own model selection as the person's choice (`$selectedModel` sink fired on subscription), so devices whose first launch found the model not ready stayed on Quotes only for good; fixed, plus a one-time 5.8 clear (`quotesOnlyOverrideReviewed58`) | 7cac2076 |
| TipKit tour rebuilt (52 tips) merged from `agent/tipkit-overhaul-ab8417` | fb2c8376 |
| Release text: tour wording | ddd069c2 |
| Release text checked against run records: reranker 48% (shipped 4-bit model, not PyTorch 49%), embedder test counts documents not passages, citation share, twelve chips, essential tips at launch, Standard-only blank rewrite, unmeasured speed claims reworded | 6283647e |
| Release text completeness: 12 noticeable changes added, two outdated lines and one overclaim fixed, wrong screen in What's New fixed | da8ed932 |
| App size: models are 124.6 MB against 5.7's 144.6 MB (the Core AI embedder copy is gone), not "68 MB larger" | b31eea82 |
| LEDGER corrections (judge table withdrawn, lost table run, invalid paired attempts, non-run folders) | 75243fb7 |
| Notion: 8 rows filed for today's fixes, tour row and Quotes-only row updated | (Notion) |

## Active Constraints

- Commits `[ci skip]`, no attribution lines, never `git add .`, never stage `scripts/run_quality_matrix.py`.
- **One Simulator benchmark at a time.** Three booted at once crashed simulator services on all three at 12:03 to 12:06
  and killed two benchmark runs (18 GB Mac, swap about 11 GB). One `xcodebuild` at a time.
- Hard-boundary files only when the owner names them.
- `Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` stay byte-identical (`VersionHistoryTests`).

## Working Set

- `BenchmarkRuns/2026-11-13-answer-first/run.sh`, `BenchmarkRuns/2026-11-13-maximum-passages/run.sh`: paired runs, own
  builds in `/private/tmp/oi-eval58-*` and `/private/tmp/oi-eval59-*`, Simulators "OI answer first" 9C4F1C39 and
  "OI maximum passages" FE71F476.
- `OpenIntelligence/Services/Infrastructure/Configuration/SettingsStore.swift`: override flag, `quotesOnlyOnlyBecauseModelWasNotReady`, `useAppleIntelligenceNowThatItIsReady`.
- `OpenIntelligence/Services/RAG/Orchestration/RAGService+Consent.swift`: `reconnectAppleModelIfNowAvailable`.
- `OpenIntelligence/Services/RAG/Tuning/RetrievalAblation.swift`: the three unmeasured switches.
- Release text: `Docs/USER_CHANGELOG.md`, `WHATS_NEW.md`, `OpenIntelligence/Features/Onboarding/WhatsNewStore.swift`,
  `fastlane/metadata{,-ios}/en-US/release_notes.txt`, `promotional_text.txt`, `Docs/Release/APP_STORE_METADATA_HISTORY.md`.

## Verification

- Build of 98582397 for the Simulator (`answer-first/run.sh build`) -> exit 0 (11:33); 09e29487 -> exit 0 (12:31).
- Rerun at 12:31 -> the new guard fired (`Quotes only is selected`), 212 `[QuotesOnly]` lines: invalid, which led to 7cac2076.
- `python3 scripts/secret_scan.py` -> no sensitive tokens. CloudKit APIs in `OpenIntelligence/`: 0. App Shortcuts: 10.
- `cmp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` -> identical (after b31eea82).
- Not run since the merge: the unit suite, the smoke build, `TourFlowUITests` (skipped twice under load in the TipKit session).

## Blockers / Unknowns

- Router size test (`python3 -m unittest test_repoos_router` in its scripts folder): every-task read set 51,914 bytes against 40,000; trim `Docs/ai/ARCHITECTURE.md` or the owner raises the cap. Tooling only.
- The App Store download size of 5.8 is not measured (only file sizes before compile and compression).
- Rows filed Future Backlog 2026-11-12: line pairs swapped (oncotarget), tables of words as loose lines, Vision's table merging columns, import toast one short.

## Exact Next Action

When the background paired runs finish, read `BenchmarkRuns/2026-11-13-answer-first/score.txt` and
`BenchmarkRuns/2026-11-13-maximum-passages/score.txt` after confirming `grep -c '\[QuotesOnly\]' answers.log` is 0 in
each; keep or switch off `answerFirst` and `maximumSourcePassages` by their rule (right count must not drop), replace
their `MEASUREMENT_PENDING` notes in CHANGELOG, LEDGER and `Docs/ai/MEASUREMENTS.md`, and add user text for any kept.
