# Current State

Updated: 2026-08-09
Branch/worktree: main, primary checkout
Last verified commit: ec32a5b

## Objective

None active. The previous objective closed tonight and everything is committed and pushed; the tree
is clean. The user has said the next arc is **v5.0 planning**, and expects to start a fresh session
for it. Do not invent a task from the leftovers below; ask, or take a row from Notion.

## Status

Two commits landed on `main` tonight and were pushed:

- `3028d0c` — ingestion format coverage (21 tests, 4 files) plus the two defects it found.
- `ec32a5b` — the benchmark grader fix, and the first `Retrieval benchmark` section the RUNBOOK has
  ever had.

**Nothing has shipped to users.** The App Store is on **v4.9**. `v5.0` is `in_development` with 36
unreleased CHANGELOG entries and **no `v5.0` section in `Docs/RELEASE_NOTES.md` yet** — that section
and a release cut are the gap between the work being done and users having it.

Since v4.9 the app itself has 18 commits over 31 files, +1797/-197. Worth knowing before planning:
roughly 670 of those inserted lines are the retrieval eval instrument
(`RetrievalStageMetrics.swift`, `RetrievalTraceCollector.swift`, `RAGEvalRunner` wiring), which
changes nothing a user experiences. The user-facing share is concentrated in ingestion, retrieval
fallbacks, index-recovery UI, and sync races.

## Completed

**Ingestion format coverage.** The automated corpus was 25 markdown files against 20 advertised
formats. Now 21 tests across 8 formats, asserted on **extraction** rather than on answers, because an
answer score structurally cannot see the failure that motivated them: on 2026-08-08 a table-chunking
change destroyed 70% of retrieved table text while the answer benchmark reported an unchanged 16/20.
Two defects fixed: every `.docx` table was extracted then discarded
(`DocumentProcessor.swift:8645`), and a fully scanned PDF reported zero OCR pages (`:4636`).
`extractTextFromIWorkDocument` (`:8474`) cannot read any document current iWork produces; it fails
loudly and two tests pin both shapes.

**The retrieval rerun, and the grader defect it exposed.** The rerun was blocked for two sessions
because the benchmark app is sandboxed unless built with code signing disabled; that is now solved
and written down in `Docs/ai/RUNBOOK.md` under **Retrieval benchmark**. The run itself is
`BenchmarkRuns/20260809-191737-matrix`: **no regression from the ingestion work**, retrieval at
ceiling (R@5 = 1.00 at every stage but `lexical` 0.94), 0 hallucinated, abstention correctness 100%.

**Corrected scores: 18/20 today against 17/20 for the 08-08 baseline.** The run artifacts record
17/20 and 14/20 respectively and were deliberately **not** rewritten, because they are provenance.
The grader was counting the verification gate's own explanation as an abstention. The one genuine
gain is `exact_capex`; everything else that appeared to move was grading or environment. The only
two real content failures are `exact_service_interval` and `exact_temperature_limit`, both 0/1
patterns in every run including the baseline, and both unrelated to the ingestion work.

## Active Constraints

- **Always pass `SWIFT_DETERMINISTIC_HASHING=1` to the benchmark.** Omitting it moved the score a
  point on its own. The harness states at `run_quality_matrix.py:599` that runs are comparable only
  if provenance matches, and it records this key.
- **Do not change chunk shape without running the ingestion fixtures.** This is what they are for.
- `BenchmarkRuns/` is gitignored in full, so no run named here survives a fresh clone.
- Running the instrumented macOS binary from the repository root drops a `default.profraw`. Delete
  it; it is untracked and not ignored.
- Hard-boundary files still require the user to name them in an approval. `WorkspaceSyncService.swift`
  and `SQLiteFullTextService.swift` both changed since v4.9 under prior approvals; that does not
  carry forward.

## Working Set

Nothing is in flight. These are the files the next task will most likely open:

- `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift:349` — builds the
  `[Needs Verification]` banner and its `*(Reason: …)*` suffix. Start of Blocker 1.
- `OpenIntelligence/App/DebugRAGValidationHarness.swift:320` — prints `response.generatedResponse`
  verbatim, which is what rules the harness out as the truncation source.
- `scripts/run_quality_matrix.py` — `VERIFICATION_BANNER` and `strip_verification_banner` near
  `:290`; the docstring records both forms of the grading bug and why the closing `)*` is optional.
- `Docs/ai/RUNBOOK.md` — **Retrieval benchmark** section. Read before running any benchmark.
- For the v5.0 arc: `Docs/Engineering/V5_EMBEDDING_ARC_LEDGER.md` is the durable ledger and should be
  read first. `Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md` and
  `Docs/Engineering/RETRIEVAL_UPGRADE_PLAN_2026-08.md` are the source docs. All three exist and were
  last touched 2026-08-05/07, so **verify their claims against current code before acting** — they
  predate everything committed since.

## Verification

Every line below was run in this session and its output read.

- `SWIFT_DETERMINISTIC_HASHING=1 python3 scripts/run_quality_matrix.py --app … --modes standard
  --pcc deny` -> **17/20 recorded, 20/20 measured, 0 hallucinated**, 9.7 min. Run by the user.
- Re-scoring all three saved runs with the fixed grader -> baseline `14 -> 17`, today-no-env
  `16 -> 17`, today-env `17 -> 18`. The baseline figure reproduces the regrade independently recorded
  in the `strip_verification_banner` docstring, which is what shows the fix corrects rather than
  inflates.
- 9 edge cases against `strip_verification_banner` -> all pass, including that **a genuine abstention
  inside a banner is still detected**, so a correct refusal on a negative control cannot become a
  false hallucination.
- `python3 -m py_compile scripts/run_quality_matrix.py` -> OK.
- `python3 scripts/secret_scan.py` -> `no sensitive tokens discovered`.
- `scripts/check_icloud_conflicts.sh` -> `OK: no iCloud damage found`.
- `codesign -d --entitlements -` on the benchmark app -> prints no entitlements.

Carried from the previous session, **not re-run today** — app source is byte-identical to when these
ran: `xcodebuild test` -> 202 tests / 0 failures; `build_simulator_smoke.sh` -> succeeded; macOS
Debug build -> succeeded.

## Blockers / Unknowns

**1. The app emits a malformed `[Needs Verification]` block, and users see it.** The closing `)*` is a
literal at `SourceOnlyAnswerService.swift:349` and is absent from the delivered answer. The grader now
tolerates it, so the benchmark is unaffected, but the app still ships the broken markdown. The
app-side cause is unidentified. Both affected answers ended at a sentence-final period, which
suggests sentence-boundary truncation, but `truncateAtSentence` (`RAGEngine.swift:610`) is applied to
chunk content rather than to the answer, so that is a lead and not a finding.
`[evidence_level: inferred, confidence: low]`

**2. The verification gate refuses to certify answers the corpus fully supports.**
`multi_hop_project_m1` returned at confidence 0.35 against 0.96 at the baseline for materially the
same correct content, faulting it for not giving a date behind "Q1 review gate" or a name behind
"Owner-1A" — specificity the corpus does not contain and the question did not ask for. A correct,
fully grounded answer is being hedged to the user.

**3. Whether transcription of real speech works at all is still untested.** No test exercises `.mp3`,
`.wav`, `.mp4`, `.mov` or `.m4a` with actual speech. `say` fails from an agent shell (`-241`), so
this needs a committed sample or a human with an audio session. Notion row exists.

**4. No end-to-end tests exist.** The unit suite covers none of routing, gates, sync, or retrieval as
a whole. Blockers 1 and 2 both live in exactly that seam and neither would have been caught by the
suite.

**`xcodebuild` hang triage** (unchanged, all three still valid). A bare `xcodebuild -list` is the
discriminator. `-list` also hangs -> an open Xcode.app holds SwiftPM locks; quit it, ask first.
`-list` fine but every build hangs -> `rm -rf /var/folders/*/*/C/com.apple.DeveloperTools`. Only one
invocation hangs -> that invocation's own DerivedData is wedged. Run `pgrep -f xcodebuild` before
concluding the toolchain is broken; an idle session can leave one running.

## Exact Next Action

**Ask the user what they want to open on for v5.0, then read
`Docs/Engineering/V5_EMBEDDING_ARC_LEDGER.md` and the Notion roadmap via the `notion-roadmap` skill
before proposing anything.** The user ended 2026-08-09 saying they are planning considerably more for
v5.0 and would continue in a fresh session. Do not answer a roadmap question from these docs alone —
Notion is the source of truth and the ledger predates every commit since 2026-08-07.

Two things are ready to hand if they are wanted instead:

- **Blocker 1**, which is the only item here that reaches users. Confirm whether the string is already
  malformed when it leaves the engine: add a temporary length-and-tail log immediately after the
  ternary at `SourceOnlyAnswerService.swift:349`, run the benchmark case `multi_hop_project_m1`, which
  reproduces it, and compare that tail against what `DebugRAGValidationHarness.swift:320` prints. If
  intact at `:349` and truncated at `:320`, walk the `RAGResponse` construction path; if already
  truncated at `:349`, then `abstentionReason` arrives malformed and the cause is upstream. Needs
  `PROCEED: IMPLEMENT`, and the temporary log must come back out.
- **Cutting v5.0**, which needs a `v5.0` section in `Docs/RELEASE_NOTES.md` covering 36 unreleased
  entries. Nothing since v4.9 is in users' hands until that happens.
