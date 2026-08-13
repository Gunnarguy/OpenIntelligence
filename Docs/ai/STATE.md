# Current State

Updated: 2026-08-13
Branch/worktree: main, primary checkout
Last verified commit: af978c5

All of this session's work is **committed and pushed**; `origin/main` and local `main` agree and the
tree is clean. Only three Swift files were touched all day: `DebugRAGValidationHarness.swift` and
`ContentView.swift`, both `#if DEBUG` and additionally gated on `--rag-validation-query` so they are
inert in a normal build, and `OnboardingChecklistView.swift` for one line of copy. Everything else
was Python, documentation, and fixture data.

## Objective

**None active. The measurement is done.** The 83-case run against `qasper_external_v1` completed on
2026-08-12 in 4.8 hours, clean tree, commit `9c634938`, and its summary is committed at
`Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md`. Findings are in `Docs/EVALS.md` under
"What has actually been measured". The v5.0 embedding arc is unblocked.

**Two results decide what happens next.**

1. **RRF fusion is measurably worse than BM25 alone.** `lexical` MRR@10 0.65 falls to `fusion` 0.51.
   Tested per-case rather than on means: over 72 paired cases lexical won 26, fusion won 6, 40 tied,
   exact two-sided sign test **p = 0.0005**. Blending a weak dense ranking into a strong lexical one
   costs rank quality, and the cross-encoder then spends its effort climbing back to 0.63. This is
   architectural, it is the cheapest thing to act on, and it was invisible before this fixture
   existed.
2. **Dense retrieval is the weakest stage.** `vector` MRR@10 0.28 against `lexical` 0.65, over 72
   cases where 8 points is resolvable. That is the measured basis for replacing MiniLM-L6-v2, which
   this project wanted to do for a year without evidence.

Accuracy was **34/77 (44%)**, scored by exact-span regex so read it as a floor. Abstention was
**2/5** on externally-authored unanswerable questions against 2/2 on the self-authored controls.
**Six cases produced no result at all** and that is unexplained; see Blockers 1.

**Nothing found on 2026-08-12 is a defect in the shipping app.** Every fix this session landed in
benchmark tooling: two Python scripts, and `DebugRAGValidationHarness.swift`, whose entire contents
sit inside `#if DEBUG`. The app was not changed. If the next session is looking for user-facing
work, this is not it; go to Blockers 5 or the Notion roadmap.

The one caveat worth carrying: `WorkspaceSyncService` resolves its root with
`OpenIntelligenceRuntimePaths.applicationSupportRoot()` rather than `baseDirectory()`, so it ignores
a configured storage override. That is invisible to a normal user, who never sets one, but
`OpenIntelligenceEngine.swift:389` does set one from `configuration.storageURL`, so an SDK consumer
with a custom storage location would find sync writing somewhere else. Tracked in Notion.

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

- **`xcodebuild test` -> 236 tests, 0 failures**, iPhone 17 Pro / iOS 27.0, run 2026-08-12 from the
  non-iCloud copy at `/private/tmp/oi-src`. The app is healthy.
- The app library was restored and verified: 4 real documents, 0 stray registrations, empty
  ingestion queue, original container `0D979768`.
- The **iCloud container was checked and is clean**: 7 files, all the owner's, no benchmark content
  from today or from the July-30-onward leakage, newest mtime May 23. Nothing this session did
  reached iCloud or the phone.

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

**1. Six of 83 cases produced no result, and nothing explains why.** Four timed out at 600s and two
returned no report: `qasper_1905.00472_04914917`, `qasper_1805.04833_f2dba5bf`,
`qasper_1805.07882_67cb001f`, `qasper_1806.04387_9f1d81b2` timed out;
`qasper_1611.06322_3319d565` and `qasper_1909.12079_3f717e6e` returned nothing. That is 7% of the
run unmeasured, and 7% is enough to move a 44% accuracy figure.

**The likely lead:** a case on 2026-08-12 took 4173s, 22x the 168s median, before returning. In the
Simulator the same shape appeared explicitly as `All 8 sessions failed to produce an insight`, which
is the agentic reasoning chain retrying. A 600s timeout may be that loop, not a slow query. Start by
reading the per-case reports under `BenchmarkRuns/qasper-overnight/reports/` for those six ids.

**Benchmark isolation is a known limitation, now mitigated rather than solved.**
`WorkspaceSyncService` writes ingested documents to the real application-support root no matter what
storage the harness was given, so runs pollute the owner's library and the accumulation slows later
cases. `--reset-shared-library` clears residue between cases and `--pool-limit N` caps documents per
case; with `--pool-limit 10` a case takes ~170s and the pack is 4.8 hours. That combination carried
83/83 to completion, so it works. `99fcdaf` should cut the run to roughly fifteen minutes by making
a reused index scorable, **still unverified**.

**Do not point `--rag-validation-storage` at the real library.** That was tried on 2026-08-12 to test
co-location and it ingested 40 papers straight into the owner's app, replaced his container in
`containers.json`, and surfaced 43 documents as pending in his UI. It was fully reverted, and the
iCloud container was verified untouched (7 files, none from any benchmark, newest mtime May 23), but
it cost a session and it is the single worst thing to repeat here.

Recovery assets: full library backup at `/private/tmp/oi-library-backup-20260812`, and
`/private/tmp/clean_benchmark_library.py`, which dry-runs by default and preserves the four real
documents. Deletions written by that script leave **no tombstones** in `deleted_documents.json`, so
they cannot propagate a delete to iCloud; that was checked rather than assumed.

Rebuild and run:

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

## Do not move the benchmark to the iOS Simulator yet. Measured 2026-08-12.

**The reasoning below was sound and the conclusion was wrong.** Keep the reasoning, because it
becomes correct the moment one thing changes, and re-deriving it wastes a session.

**What was measured.** One case at `--pool-limit 10` on iPhone 17 Pro / iOS 27.0 **exceeded ten
minutes and then failed**, against 170s on macOS. Ingestion and retrieval were fine. Generation was
not:

```
[ReasoningChain] All 8 sessions failed to produce an insight
[Agentic] Failed: The on-device model did not return a usable response across 8 reasoning sessions
[RAGValidation] Validation failed
```

Apple Intelligence cannot generate in the Simulator on this machine, and the agentic path retries
eight reasoning sessions before giving up. That retry loop is the ten minutes. At 83 cases that is
**14+ hours in which every case fails**, against 4 hours of real answers on macOS.

Note the trap: with a single document and a simple query it falls back to extractive quickly and
looks fine. The escalation only appears at a realistic pool size, so a one-document smoke test will
mislead you here.

**Why generation fails.** The framework loads and reports `availability: available`; generation dies
in Apple's `ModelManagerError 1026`. Verified with a bare probe with no app code involved: the same
probe on the host Mac reports available **and generates real text**, so the machine is capable and
provisioned. Ruled out: locale (`en_US` on both sides), a wedged model catalog (erasing the
simulator removed those errors entirely), and the app's own guards (failure reproduces with them
removed). Apple's forums document this exact error pair and the remedy is to toggle Apple
Intelligence off, restart the Mac, and turn it back on. **The owner has declined to do that**, which
is reasonable: this is developer convenience, not something the shipping app depends on.

`[evidence_level: measured, confidence: exact, evidence_source: bare FoundationModels probe on host vs iOS 27 simulator; one full case at --pool-limit 10 on each target]`

**The three simulator guards are therefore correct in outcome and stale in wording.**
`LLMService.AppleFoundationLLMService.isAvailable` and `RAGService.checkDeviceCapabilities` both
hardcode unavailability under `#if targetEnvironment(simulator)`, with reasons like "Foundation
Models not available in Simulator". Availability is actually reported *available*, so the reason is
wrong, but the behaviour they produce is right: without them the app attempts generation, fails,
and is slower and noisier for it. They were removed and reverted twice on 2026-08-12. **Leave them
until AFM generates in the Simulator**, then remove all three together.

This is also the whole answer to "why does the chat header say `Hybrid - Unavailable`". That pill
reads `supportsFoundationModels` from `checkDeviceCapabilities`, so on a simulator it is reporting a
compile-time constant rather than anything about the machine. On a real device it should read
available.

**Re-check trigger:** any Xcode or macOS update. Re-run the probe; if it generates, the move below
becomes correct and worth doing immediately.

## Why the Simulator is still the right destination once generation works

The owner's suggestion on 2026-08-12, and the reasoning holds.

**It ends the isolation problem outright.** A simulator has its own filesystem container, so the
app's application-support directory lives inside the simulator rather than in the owner's real
`~/Library`. `WorkspaceSyncService` can go on resolving `applicationSupportRoot()` and it no longer
matters: there is nothing of the owner's to pollute, no cleanup script, no reset between cases, and
no risk of repeating the 2026-08-12 incident. Every mitigation in `run_quality_matrix.py` exists
only to work around a problem the simulator does not have.

**It measures the platform the app is for.** This ships primarily for iPhone and iPad; benchmarking
the Mac build measures the least representative target.

**Foundation Models load in the simulator but cannot generate there.** Corrected the same day it was
written: this section first claimed they were available, on the strength of Apple's documentation
and a capable host. Measurement disagrees, and the detail is in the section above. Availability is
reported `available`; generation fails. Treat "available" from `SystemLanguageModel` as necessary
and not sufficient.

**What it needs:** `run_quality_matrix.py` drives the app by executing the macOS binary directly. A
simulator run instead needs `xcrun simctl launch --console-pty <udid> <bundle-id> --args ...` and
the same stdout parsing. That is a contained change to one function, `run_one`.

## Exact Next Action

**Act on the fusion result. It is the cheapest measured win available and it does not need another
four-hour run to justify.**

`lexical` MRR@10 0.65 falls to `fusion` 0.51, and per-case that is 26 wins to 6 with p=0.0005. RRF is
combining a strong lexical ranking with a weak dense one at equal weight. Two candidate changes,
both small, and the fixture can now tell you which works:

1. Weight the RRF arms by measured stage quality instead of equally.
2. Gate or downweight the vector arm when the lexical arm is confident.

Re-run afterwards with the same command and compare against
`Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md`. At n=77 a change smaller than ~8 points
is not resolvable, so do not claim one.

**Then the embedder.** Notion row "Benchmark three embedders and replace MiniLM-L6-v2 if warranted"
is now unblocked with evidence behind it: `vector` MRR@10 0.28. Additive-then-swap, per the owner's
standing preference.

**Do not fix these two at once.** They both move the same numbers and a combined change cannot be
attributed. Fusion first, because it is a scoring-weight change rather than a re-embed.

Rerun command, unchanged and verified end to end:

```bash
caffeinate -is env SWIFT_DETERMINISTIC_HASHING=1 python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny --pool-limit 10 --reset-shared-library --output-dir BenchmarkRuns/<name>
```

```bash
python3 scripts/save_benchmark_summary.py BenchmarkRuns/<name>
```

**Always save the summary and commit it.** `BenchmarkRuns/` is gitignored, so a run that is not
summarised did not happen as far as the next session is concerned. That was true of every run this
project made before 2026-08-12.

**Do not compare any number from this run to a `tiny_research_suite` run.** Different corpus,
different ground truth, different difficulty. A delta between the two packs measures the fixture.

The alternative that needs neither hardware nor a long run is the three high-severity findings in
`Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`.

Do not treat the device checks as session work: those need the owner's physical device.
