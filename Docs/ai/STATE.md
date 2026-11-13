# Current State

Updated: 2026-11-13 about 07:00 PT
Branch/worktree: `main`, primary checkout
Last verified commit: 39626d71

## Objective

**Ship 5.8, the last update for a while (owner, 2026-11-12), with every change from 5.7 measured.** What remains is
his: the Xcode Cloud build and the submission, at his word, ticking "Reset rating when this version is released"
(`Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 15). Every commit since 2026-11-02 carries `[ci skip]`; nothing has been pushed
to a build.

## Status (overnight 2026-11-12 to 13, the owner's "run everything here")

| What | Result | Where |
|---|---|---|
| Answer quality, 20 cases, app model path, Simulator, one run each | 5.7 to 5.8: Standard 0.30 to 0.45, Deep Think 0.40 to 0.40, Maximum 0.25 to 0.40 (each case 0.05) | `BenchmarkRuns/2026-11-13-0014-answer-modes-5.8`, `-0142-answer-modes-v5.7.0`, `-0638-answer-modes-v5.7.0-max` |
| Seconds a question, 5.8 (two chains ran side by side, so indicative) | median Standard 20, Deep Think 72, Maximum 80 | the `.txt` files there |
| Granite against MiniLM in the app, golden retrieval | top 5 up in every mode (Standard 0.526 to 0.789, Deep Think 0.511 to 0.609, Maximum 0.500 to 0.667); first place down only on Maximum's 36 (0.472 to 0.444); no mode p<0.05 | `BenchmarkRuns/2026-11-12-full-suite/golden-score.txt` |
| Granite against MiniLM, 158 table questions, Standard | running at 07:00 (MiniLM about 07:05, Granite about 10:00) | `.../full-suite/tables-score.txt` when done |
| Table and text fidelity, 8 PDFs, 515 checks | 433 to 439; region fix (A) and layout coverage (D) kept; captioned word tables (B) and Vision-table preference (C) measured and withdrawn | `BenchmarkRuns/2026-11-12-tables`, LEDGER entry |
| Unit suite, iOS 27 Simulator, unpatched tree at cc8f4691 | 1,736 tests, 20 skipped, 1 failure: `VersionHistoryTests` (bundled history behind `Docs/USER_CHANGELOG.md` since 11-08); fixed in ca9dc31c and that class plus `PageTextRepairTests` re-run: 38 passed | `.../full-suite/unit.log` |
| Licence audit (owner's rule 1) | nothing non-commercial ships; `THIRD_PARTY_NOTICES.md` corrected (Granite embedder, uniffi MPL-2.0, Rust crates); unused unlicensed image `LogicBoard_A18Pro` removed | 259a4e38, 7c5fd50f |
| Import queue (found 2026-11-13 in the phone's trace) | the iCloud queue held 59 finished or unreachable items (oldest 10-20), so `WorkspaceSyncService` left four libraries' vector stores unsynced on every pass; 39626d71 retires them with tombstones at launch (journal `queue.retired`); not yet seen on the phone | CHANGELOG 5.8 |
| Launch freeze | 8 s on 2026-11-13 (2 s or more on 6 of 62 launches since 11-09), between the launch purchase check and the library check; cause not found; 39626d71 times `index.health` steps and `launch.workspaceRefresh` | phone journal |
| Phone | development build of cc8f4691 installed 00:12 (X-Ray outline label reads ANE, legend at its old size; table fixes); not launched (phone locked) | |
| Disk | 16 to 37 GB free (rebuildable build output, caches, one test simulator's data) | |

Still running when this was written: chain B of `BenchmarkRuns/2026-11-12-full-suite/overnight.sh` (tables Granite,
then Deep Think table slices 1/3 and 2/3, about 3 h each, until mid-afternoon). Stop it with
`pkill -f overnight.sh; pkill -f run_all.sh; pkill -f deepthink-source-passages/run.sh; pkill -x xcodebuild` if the Mac
is needed; nothing is lost but the unfinished slice.

## Active Constraints

- Commits `[ci skip]`, no attribution lines, never `git add .`, never stage `scripts/run_quality_matrix.py`.
- One cold `xcodebuild` at a time; never load the Mac while he games; benchmarks only at his word (given 2026-11-12 for
  the overnight run).
- Hard-boundary files only when he names them (the two embedding providers were named 2026-11-12).

## Working Set

- `OpenIntelligence/Services/Document/Processing/LayoutAwareExtractor.swift`: layout coverage (recovered text-layer
  blocks, three-quarters-held filter, placed after column detection).
- `OpenIntelligence/Services/Document/Processing/TextLayerTableDetector.swift`: region overlap against the region's
  rows of 3+ cells.
- `OpenIntelligence/Features/Telemetry/Dashboard/MotherboardHUDView.swift`: `socLabel`, `XRayOutlineLabel`, compact legend.
- `BenchmarkRuns/2026-11-12-full-suite/overnight.sh`, `run_all.sh`; `BenchmarkRuns/2026-11-12-tables/run_fidelity.sh`.
- `scripts/bench_answer_modes.sh` (prestaged builds, `OI_BENCH_*`). The 5.7 copy is `/private/tmp/oi-eval57-stage`
  (v5.7.0, switches patched by content, the answer test from 02044980).

## Verification

- `run_fidelity.sh tab-fin fb548e4d` -> 439/515 (after11 433), lost 4 (oncotarget p2, p10, p11), number recall up or equal on every paper.
- `xcodebuild test-without-building` (unit suite, cc8f4691) -> 1,736 executed, 1 failure (VersionHistoryTests); after ca9dc31c, `-only-testing VersionHistoryTests PageTextRepairTests` -> 38 executed, 0 failures.
- `score_golden.py` MiniLM against Granite -> see Status.
- `python3 -m unittest test_repoos_router` (in its scripts folder) -> 31 run, 1 failure (read set 51,914 bytes against 40,000).

## Blockers / Unknowns

- Router size test: the every-task read set is 51,914 bytes against a 40,000 cap; `Docs/ai/ARCHITECTURE.md` is 34,971 of
  it. Trim `ARCHITECTURE.md` (move detail to the Atlas) or raise the cap with his word.
- Open defects filed Future Backlog 2026-11-12: lines swapped in pairs on oncotarget p2/p10/p11
  (https://app.notion.com/p/41749a74d54f81cb90d7d0af22b5cb46), tables of words stored as loose lines
  (https://app.notion.com/p/41749a74d54f81fc81a5de9369017d0d), Vision's table merging columns
  (https://app.notion.com/p/41749a74d54f81c7aeb2eca4cbec2e56); import toast one short
  (https://app.notion.com/p/41749a74d54f8195b436f019ac03aede).
- 20 answer cases move by 0.05 a case: 5.7 against 5.8 is three cases on Standard and inside noise on Deep Think.
- The table-question comparison (MiniLM at 6e486015 against HEAD) also differs in tonight's table fixes, so it measures
  both together.
- The crates' copyright notices are not shown in the app (no acknowledgements screen).
- Device checks for 5.8's rows: the `device-pass` skill (at most 5 phone and 7 Mac steps).

## Exact Next Action

0. Install the 39626d71 phone build (`/private/tmp/oi-build/Build/Products/Debug-iphoneos/OpenIntelligence.app`; the install was refused while the phone was locked), have the owner open the app, pull the journal (`scripts/phone_evidence.py`) and read `queue.retired`, `index.health` (`sampleMs`, `recordsMs`, `ms`) and `launch.workspaceRefresh`; fix whichever step holds the main thread; confirm the trace no longer says "left alone this pass: an import into it has not finished".
1. When chain B's Granite table run ends (about 10:00), read `BenchmarkRuns/2026-11-12-full-suite/tables-score.txt`;
   add a LEDGER entry for `2026-11-12-full-suite` and for the three `2026-11-13-*-answer-modes*` folders, and update
   `Docs/ai/MEASUREMENTS.md` A5 with the table result (A1 and the 5.7 Maximum figure are in it).
2. Then the owner's call: the device pass (`device-pass` skill), and the Xcode Cloud build and submission of 5.8.
