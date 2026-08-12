# Current State

Updated: 2026-08-12
Branch/worktree: main, primary checkout
Last verified commit: 3c09f01, which carries this session's work. **Committed, not pushed.**

## Objective

**Build the eval fixture set with external ground truth.** Notion row of the same name, v5.0, High,
now `In Progress`. The pack is built, committed and verified. **It has not been run.**

The single remaining step is one command, and it needs the owner because an agent cannot run it on
this machine. See Blockers 1.

## Status

The tree carries the fixture work described below. Everything that can be verified without
`xcodebuild` has been verified and its output read.

**`xcodebuild` deadlocks on this repository's own path, and the workaround is a copy.** Anything
that opens the project hangs forever at the "Command line invocation" header with no
`XCBBuildService` and no DerivedData, while `-version` and `-list` still work. `sample` of the hung
process shows the blocked thread in `-[DVTFilePath performCoordinatedReadRecursively:]`, parked in
`semaphore_wait_trap`: an **NSFileCoordinator** coordinated read against iCloud-synced `~/Documents`
that never returns. Plain `ls -R` on the same path is instant and no file is dataless, so this does
not look like an iCloud problem until you sample it.

Build from `rsync`'d copy at `/private/tmp/oi-src` instead. Verified by A/B on the identical
command: hangs in `~/Documents`, `exit=0` instantly from the copy. Full recipe in `RUNBOOK.md`
item 1b. **This is not a signing, sandbox, or permission-classifier problem**, and the RUNBOOK's
previous claim that an agent could not run the build has been corrected in place.

**No Swift source was touched.** The changes are Python, docs, and new fixture data only.

## Completed this session (2026-08-12)

- **`Benchmarks/ResearchFixtures/qasper_external_v1/`**, 83 cases over 40 papers from QASPER
  (Dasigi et al., NAACL 2021, CC BY 4.0), built by `scripts/build_external_fixtures.py`. Questions
  were written by readers shown only a title and abstract, and answered by separate annotators
  against full text. A case survives only where two or more annotators agreed; `annotator_agreement`
  records the count. Six abstention controls come from genuinely unanswerable questions, replacing
  two the project invented for itself. `fixtures.lock.json` pins the dataset revision, the selected
  papers and questions, and a corpus SHA-256. **Two independent rebuilds produced a byte-identical
  tree**, and `--check` verifies it offline.
- **The shared distractor pool**, which is the change that actually matters. A manifest may now
  declare a top-level `pool`, and `run_quality_matrix.py` ingests it for every case, so each
  question is asked against 39 papers that are not the answer.
- **`minimum_detectable_effect` now computes its own claim.** It previously interpolated `n` into a
  sentence whose threshold was hardcoded. See Blockers 3.
- **Non-commercial datasets can no longer be pulled into the tree by accident.**
  `prepare_rag_research_fixtures.py` refuses `financebench` and `docvqa` unless
  `--accept-non-commercial` is passed for a local-only run.
- **`build_eval_dataset.py` renders every known pack**, so `Benchmarks/rag_eval_qasper_v1.jsonl`
  reaches the in-app `RAGEvalCase` framework the same way the synthetic set does. The only change to
  the pre-existing `rag_eval_v1.jsonl` is two header comment lines; every case line is byte-identical.

Notion: the fixtures row is `In Progress` with a dated note, the harness row has a dated note, and
two new Completed rows cover the power-calculation defect and the licensing gate.

## Why the ceiling was never about sample size

This is the finding that reframed the row, and it is worth not rediscovering.

`run_quality_matrix.py` created a fresh store per (case, mode) and ingested only that case's
`input_files`. **Every case was therefore scored against an index containing nothing but its own
expected documents.** The 2026-08-11 reports show the vector stage seeing two to five candidate
chunks per case, all of them from the expected file. `R@5` asks whether the right document is in the
top five when there are at most five candidates and every one is relevant, so `MRR@10 1.000` and
`R@5 1.000` were arithmetic, not pipeline quality. Real external data at n=300 would not have moved
them. The corpus was the defect; externality and `n` were real but secondary.

`[evidence_level: run_artifact_verified, confidence: exact, evidence_source: BenchmarkRuns/20260811-150328-matrix/reports/*.txt STAGE METRICS results column; run_quality_matrix.py:391, :720]`

## Completed 2026-08-11

Newest first. The last two in this list are the previous objective; everything above them was found
while verifying it. Doc-only commits are omitted.

- `bca92c0` The owner's own one-character HUD capitalisation edit, committed on its own rather than
  folded into an unrelated change.
- `ba05818` **The two destructive library actions were indistinguishable, and one menu entry led to a
  screen that could never hold anything.** "Wipe Library" and "Delete Library" sat adjacent, both
  destructive, on `trash` and `trash.slash`. They are now "Remove All Documents from X" and "Delete
  the X Library", different icon families, divider between them. Cached Documents is gated on the
  cache holding something: `DocumentationCacheService.cache(...)` has zero call sites, but it is
  scaffolding for the open roadmap row "Web Clipper / Share Extension", not dead code.

- `5cf54b4` Three documentation-status banners asserted verification state that was wrong:
  `RELEASE_NOTES.md` claimed 202 tests against 230, and `USER_CHANGELOG.md` and `WHATS_NEW.md` both
  still said v4.9. The RUNBOOK gained the more dangerous omission, that stage figures either side of
  2026-08-11 are not comparable because the eval ground truth changed rather than the pipeline.
- `fd5af3a`, `561dcd3` Closed three gaps a final audit found: `RELEASE_NOTES.md` had no coverage of
  the correctness pass and its entry count read 74 against an actual 87, the Atlas did not record
  `LibraryDeletion`, and Notion was missing a row for it. The count had gone stale twice in one day,
  46 to 74 to 87, so the recount command is now recorded beside it instead of the number being
  retyped again.
- `b464378` **One delete-library implementation.** `DocumentLibraryView` and `ContainerSettingsSheet`
  had near-identical copies that had diverged: on an iCloud library whose shared copy fails to
  delete, the first aborted and reported, the second logged and deleted locally anyway, so the next
  sync restored the library and the user believed it was gone. Both now call
  `LibraryDeletion.delete`, which aborts. `ContainerSettingsSheet` had to stop calling `dismiss()`
  before the work started, and `resolvedLocalDeletionContainerIDs` was deleted as unreachable.
- `8d00bf5` `default.profraw` gitignored.
- `6693a39` Two CHANGELOG citations had rotted the same day they were written, because the commit
  that described a line also inserted lines above it. Fragile ones replaced with symbol names.
- `cc49ce2` **Library Settings honesty pass.** Vectors were deleted at Save, before the rebuild
  dialog, so "Later" left documents with no vectors; the delete moved into `startReembedding`.
  Sliders offered 100...600 and 0...200 against enforced clamps of 260 and 50. The "elastic"
  strategy claimed embedding similarity that never runs. "persistent JSON storage" was stale. The
  `narrative` preset declared 280/55 against those clamps.
- `4178ff0` **Library controls stopped destroying data while promising they had not.** "Remove Local
  Copies" was never local and is now "Wipe Library"; it also leaked Spotlight entries, entity-index
  rows and the imported files. Flipping a library to Local Only deletes its iCloud copy and now
  confirms. Database scope carries a `UUID` so any library can be inspected. Toolbar overflow,
  duplicate-name disambiguation, and a dead `onSetLibraryStorage` closure in Semantic Search.
- `818ea88` **Answers ending in bold or italic lost their closing markers**, because
  `hasResponseTerminalBoundary` did not accept `*`. Also the eval set credited one of the two
  documents every multi-hop question needs, which made a working reranker read as a regression.
- `0a9af59` The benchmark answered the embedder question. See Blockers 1.
- `24f305a`, `8b30ae5` The vocabulary layer: 24 terms in a plain and a technical register, attached
  in place. `Docs/ai/DECISIONS.md` holds the rationale under **2026-08-11 - Explain the vocabulary
  in two registers rather than simplifying the screens**.

Notion has five new Completed v5.0 rows for the above, plus a dated progress note on
"Retrieval benchmark harness over rag_eval_v1.jsonl" recording what that harness still cannot
measure.

## Active Constraints

- **No em-dashes anywhere.** `USER_CHANGELOG.md` renders in the app, so it is a product rule. It
  applies to Swift string literals too, which an earlier sweep missed.
- **Do not write a value into user-facing copy. Read it from the code.** This is the pattern that
  fixed five separate defects today and the one that prevents their return. A typed number drifts;
  a read one cannot.
- **Freeze the working tree before any build or test run**, documentation included.
  `VersionHistoryTests` compares the bundled `VersionHistory.md` against `Docs/USER_CHANGELOG.md`,
  which makes that doc a build input. Three runs were discarded on 2026-08-11 for this.
- **A new file under most `Services/` folders is also compiled into the `OpenIntelligenceEngine`
  SDK framework.** That target synchronises eighteen folders including
  `Services/Infrastructure/Integration`, but not `Presentation/` and not `Features/`. A file there
  referencing either fails **only in the test build**, with a scope error that reads exactly like
  stale DerivedData and is not. Put such files under `Features/`.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay byte
  identical.** Edit one, `cp` it over the other.
- **`[Unreleased]` in `CHANGELOG.md` stays empty.** New entries go under `## 5.0`.
- **Commits must not carry a `Co-Authored-By: Claude` trailer.** `includeCoAuthoredBy: false` is set
  in `~/.claude/settings.json`; do not add one by hand.
- **Zero call sites is not dead code.** Run `oi-claim-audit` before any removal.
- Hard-boundary files still need the owner to name them. None were touched.

## Working Set

- `Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`, **the 44 findings not
  fixed today**, with evidence and file references. This is the backlog for the library surfaces and
  the first file to open for that work.
- `OpenIntelligence/Features/Documents/Library/LibraryDeletion.swift`, the single delete
  implementation. Its header records the two lookalikes deliberately left alone and why.
- `OpenIntelligence/UI/Components/Glossary.swift`, the single source of every user-facing
  definition. Change copy here and nowhere else. `GlossaryTests` fails if a plain definition
  acquires a code identifier.
- `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift`, whose `ChunkingConfig` now
  owns the clamp constants that both `DocumentProcessor` and the Library Settings sliders read.
- `scripts/build_eval_dataset.py` and `scripts/run_quality_matrix.py`, both of which now read a
  plural `expected_sources`.
- `Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json`, the eval ground truth.

## Verification

Run on 2026-08-12 and the output read:

- `python3 scripts/build_external_fixtures.py --check` -> OK, 83 cases, 40 papers,
  `allenai/qasper @ fdc9d8214fba`.
- Two full rebuilds of the pack from separate downloads produced the **same
  `fixtures_sha256`**, `4a470066...`, which is the determinism claim actually tested rather than
  asserted.
- `python3 scripts/build_eval_dataset.py --check` -> OK, 20 cases and 83 cases.
- `python3 scripts/secret_scan.py` -> clean. `scripts/check_icloud_conflicts.sh` -> clean.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 24 tests, OK.
- `minimum_detectable_effect` re-derived numerically against the exact binomial sign test before the
  claim was changed, and the old figure checked against three readings (paired 33 pts, Wilson 21 pts,
  unpaired 47 pts) to confirm 25 matched none of them.

**Not run this session, and not runnable here:** `xcodebuild test`, the simulator smoke build, and
the retrieval benchmark. See Status for why. The last known figures are 236 / 0 and the 2026-08-11
matrix run, both against Swift that this session did not touch.

Carried forward from 2026-08-11 and still true: **nothing verifies what the UI does.** Zero test
files touch `DocumentLibraryView`, `ContainerPicker`, `DatabaseDashboardView`,
`ContainerSettingsSheet`, `LibraryDeletion` or `clearAllDocuments`. Every on-device behaviour and
every Mac path is also unverified.

## Blockers / Unknowns

**1. The benchmark is blocked by library pollution, not by the build.** The build is solved: it
succeeds from a non-iCloud copy (see Status). What stops the run is that the app's real library had
accumulated 241 benchmark documents and a stale ingestion queue, so every case stalled at
`waiting for resume decision` and blew past the 600s timeout without producing a report.

Tracked in Notion as "Benchmark runs write their fixtures into the real on-device document
library", v5.0, High. **The mechanism is not yet established**; that row records which two obvious
explanations were checked and ruled out, so start with a focused repro rather than a fix.

A backup of the library is at `/private/tmp/oi-library-backup-20260812` (144 MB, 1556 files), and a
reviewed cleanup script that keeps the four real documents is at
`<scratchpad>/clean_benchmark_library.py`. It dry-runs by default. **The owner approved running it;
it had not been run as of this handoff** because bulk deletion under `~/Library` is blocked at the
tool layer.

Once the library is clean, rebuild and run:

```bash
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/
```

```bash
cd /private/tmp/oi-src && DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme OpenIntelligence -destination "platform=macOS" -configuration Debug -derivedDataPath /private/tmp/oi-mac-nosbx -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny
```

The owner asked for the full 83-case run, standard mode only. **Expect it to be slow**: every case
ingests the whole 40-paper pool, roughly 135,000 words, because the harness cannot share one index
across cases without losing the document-name mapping and degrading citations to `[Unknown, p.1]`
(the reasoning is in `run_one`). The old 20-case run took 412 seconds against near-empty indexes, so
budget well over an hour and do not lower `--timeout`.

**What the run is for:** to see whether any stage comes off 1.000 now that retrieval has
distractors. If stages still read 1.000 against 39 distractor papers, that is a real and surprising
result about the pipeline rather than an artifact, and it should be investigated before it is
believed. If they drop, the fixture can finally show an improvement and the embedder comparison is
unblocked.

**2. Five device checks gate confidence in everything shipped 2026-08-11.** Four carried from
2026-08-10: type in Settings search; run a query with the HUD visible and watch the Neural Engine
bar; rotate with the HUD on; update from a pre-v5.0 build to see the sample refresh banner. New and
most important: **open Library Settings, change the embedding model, and press "Later"** on the
rebuild prompt. That is the data-loss path reordered in `cc49ce2`, and nothing automated covers it.
Also worth a look: wipe a library, delete one document, flip a library off iCloud, and tap a device
chip on the onboarding completion card with VoiceOver on.

**3. The harness had been overstating its own sensitivity, and the old figure is quoted widely.**
`minimum_detectable_effect(n)` interpolated the sample size into a sentence whose threshold was a
hardcoded constant, so it printed "differences below about 25 points are not resolvable" at every
`n`. Under the exact two-sided sign test it describes, `2 * 0.5**d < 0.05` first holds at d=6, and
the smallest difference that reaches it is `6/n`: **33 points at n=18, not 25**. Fixed, and run
through `oi-claim-audit` first because it is a claim correction. **Every report under
`BenchmarkRuns/` dated before 2026-08-12 carries the constant**; read those power statements as
`6/n`. At n=83 the figure is about 7 points, which clears the row's 10-point acceptance criterion.
This is the third scoring or reporting defect in this harness after the seven metric bugs of
2026-08-08 and the single-source ground-truth bug of 2026-08-11, so keep assuming more.
`[evidence_level: computed_verified, confidence: exact, evidence_source: exact binomial sign test]`

**4. The embedding arc is no longer blocked on the fixture, only on the run.** The prerequisite row
is built. Once Blockers 1 produces numbers, "Benchmark three embedders and replace MiniLM-L6-v2 if
warranted" can start against a fixture that is able to show an improvement. **Do not start the
re-embed before that run exists**; nothing is measured yet.

**5. 44 verified findings remain on the library surfaces**, in the audit file named in Working Set:
3 high, 18 medium, 13 low, 10 the verifier could not reproduce. The three high ones are worth
reading first.

**6. `OpenIntelligenceEngine.deleteLibrary` leaks everything.** It calls
`containerService.deleteContainer` alone, leaving documents, chunks, vectors and Spotlight entries
behind. It is `public` and synchronous, so routing it through `LibraryDeletion.delete` would break
the SDK signature. Deliberately untouched; decide the API question before fixing it.

**7. `README.md` claims iWork support the app does not have.** Tracked in Notion as
"iWork import is advertised but cannot read any file iWork produces" (To Do, v5.0). It is a claim
removal, so use `oi-claim-audit` first.

**8. `OnboardingChecklistView` logs "Generating BM25 dictionary + HNSW vectors".** `BNNSVectorDatabase`
is a flat store searched by batched `vDSP_mmul`, not an HNSW graph. Verify by reading that file for
any graph construction; if there is none, the log names an algorithm the app does not use.

**9. Licensing shapes the embedder decision.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0. **EmbeddingGemma is not**; it ships under the Gemma Terms
of Use, whose §3.1 requires the use restrictions to be enforceable against *your* users. Jina's v2
reranker weights are reported CC-BY-NC; verify before relying on that. Not legal advice.

**10. The What's New sheet is a changelog, not a splash.** The `"5.0"` entry has 8 items and no deep
links, and `WhatsNewView` has one button, "Done". Cutting to 3-4 and making rows navigate is the
improvement.

## v5.0 roadmap, reconciled against code 2026-08-11

All 27 open v5.0 rows were checked against the code, each verdict challenged by a second pass told to
refute it. **19 open, 7 partial, 1 needs hardware. Nothing was found already shipped and unmarked**,
so the roadmap was not stale in the direction of overstating what is left; it was stale in
understating what has landed inside seven rows. Every partial now carries a dated note in Notion
saying which half is real, so tomorrow does not rebuild it.

**Three rows were retitled** because all three began "Validate: PCC" and read as *PCC does not work*.
It does: the entitlement is `true` in `OpenIntelligence.entitlements` (read via plistlib) and
`PrivateCloudComputeLanguageModel` is wired at `FoundationModelCapabilityProvider.swift:54`,
`FoundationModelSessionFactory.swift:92` and `FoundationModelRoutePolicy.swift:127`. Row titles
publish to the public roadmap page, so the old wording told every reader the same wrong thing.

**PCC cannot be exercised from an agent shell.** Tested directly: `fm available` prints `System model
available` on stdout and `Private Cloud Compute is not available in this context. Please use the
Terminal app.` on stderr. Local builds carry no entitlements at all because the smoke and benchmark
builds pass `CODE_SIGNING_ALLOWED=NO`. No run in `BenchmarkRuns/` records a PCC route. Those rows need
the owner's device, and that is a hard limit rather than an unattempted check.

**Two defects surfaced that were not on the roadmap. Both are now fixed in `0e7458a`.**

1. **The planner attempted PCC on a quota state its own route gate scores as unauthorized.** Three
   places already asserted fail-closed on `.unknown`: `RouteEvalMetrics.RouteInvariant.quotaFailClosed`,
   `Docs/PRIVACY_AND_ROUTING.md` in prose, and `ModelExecutionReceipt.nonAuthorizingQuotaStates`. Only
   `canUsePCC` disagreed, testing `!= .limitReached` alone, and it is the one that decides. The rule
   now lives once as `PCCQuotaState.authorizesCloudExecution`, exhaustive over the enum, and both
   sides derive from it. That doc sentence had been false for as long as it was written and is now
   annotated as corrected. `PCCQuotaAuthorizationTests`, 6 cases.
2. **macOS had no foreground check at all**, so a backgrounded Shortcut reported itself
   foreground-interactive and could reach PCC unattended. It reads `NSApplication.shared.isActive`
   now, and a platform with neither UIKit nor AppKit falls closed. **The Notion row stays open**: it
   also asks for the backgrounded Shortcuts path to be exercised, which needs the owner's device.

**Also found:** `RAGEvalRunner` has zero call sites repo-wide, so the in-app half of evaluation cannot
be invoked at all; every measurement goes through `scripts/run_quality_matrix.py` plus
`DebugRAGValidationHarness`. And `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 7 and risks
R06/R07 cite the wrong files for the consent guard.

## Exact Next Action

**Clean the app library, then run the benchmark against `qasper_external_v1`.** Order matters: the
run cannot complete until the stale ingestion queue is gone. Commands and the cleanup script are in
Blockers 1. The owner has already chosen the scope: all 83 cases, `--modes standard --pcc deny`.

The fixture work itself is done, so this is no longer a building task. It is a measuring task, and
until the measurement exists the row stays `In Progress` and the embedder comparison stays parked.

**Record the result honestly, whichever way it goes.** The interesting outcome is not "the numbers
improved". It is whether retrieval can now fail at all. If stages still read 1.000 against 39
distractor papers, do not celebrate it and do not assume the pool is working: check
`pool_documents` and `fixture_corpus_sha256` in the run's provenance, and check the `results` column
in a per-case `STAGE METRICS` block, which should now be in the hundreds rather than 2 to 5.

**Do not compare any number from this run to a `tiny_research_suite` run.** Different corpus,
different ground truth, different difficulty. A delta between the two packs measures the fixture.

If an agent picks this up and `xcodebuild` hangs at the invocation header with no DerivedData, that
is the environment failure in Status, not a code problem. Hand the build to the owner rather than
spending the session on it; that cost most of an hour on 2026-08-12.

The alternative that needs neither hardware nor a build is the three high-severity findings in
`Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`.

Do not treat Blockers 2 as session work: those five checks need the owner's physical device.
